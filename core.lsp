;;; ============================================================
;;; core.lsp - NUCLEO DO CONJUNTO HYDRO
;;;
;;; Responsabilidades:
;;;   1. Registro de funcionalidades  (Provide / Has / Require)
;;;   2. Eventos entre plugins        (On / Emit)
;;;   3. Configuracao compartilhada   (Get / Set / Del)
;;;   4. Utilitarios comuns           (AskReal, AskInt, FmtNum, ...)
;;;   5. Carregador de modulos        (LoadModule / LoadAll)
;;;
;;; Variaveis globais do conjunto inteiro (as UNICAS):
;;;   HYDRO:*features*  alist  ("nome" . "versao")
;;;   HYDRO:*hooks*     lista  (evento id funcao)
;;;   HYDRO:*session*   alist  usada so quando NAO ha plugin de persistencia
;;;   HYDRO:*dir*       pasta onde estao os .lsp
;;;
;;; CATALOGO DE EVENTOS (contrato entre plugins)
;;;   "sarjeta.calculada"  dados = alist com:
;;;       "BACIA" "TALVEGUE" (enames)   "AREA" "COMPRIMENTO" "DECLIVIDADE" "TC"
;;;       "CASOS" (lista de (rotulo tr intensidade vazao))
;;;       "Q" (vazao do primeiro caso)  "LAMINA" "LARGURA" "VELOCIDADE" "SECAO"
;;; ============================================================
(vl-load-com)

(if (not (boundp 'HYDRO:*session*)) (setq HYDRO:*session* nil))
(setq HYDRO:*features* nil)
(setq HYDRO:*hooks* nil)

;; Pasta dos arquivos. Se voce definir HYDRO:*dir* ANTES de carregar o core,
;; o valor e respeitado. Senao tenta descobrir pelo caminho de suporte do AutoCAD.
(if (not (boundp 'HYDRO:*dir*)) (setq HYDRO:*dir* nil))
(if (and (not HYDRO:*dir*) (findfile "core.lsp"))
  (setq HYDRO:*dir* (vl-filename-directory (findfile "core.lsp")))
)

;;; ------------------------------------------------------------
;;; LOG
;;; ------------------------------------------------------------
(defun HYDRO:Log (msg)
  (princ (strcat "\n[HYDRO] " msg))
  (princ)
)

;;; ------------------------------------------------------------
;;; 1. REGISTRO DE FUNCIONALIDADES
;;; ------------------------------------------------------------
;; Cada plugin anuncia o que oferece, no final do seu arquivo:
;;   (HYDRO:Provide "persistencia" "2.0")
(defun HYDRO:Provide (nome versao)
  (setq HYDRO:*features*
    (cons (cons nome versao)
          (vl-remove (assoc nome HYDRO:*features*) HYDRO:*features*)
    )
  )
  nome
)

;; Pergunta se uma funcionalidade esta carregada: (if (HYDRO:Has "xdata") ...)
(defun HYDRO:Has (nome)
  (if (assoc nome HYDRO:*features*) T nil)
)

(defun HYDRO:Version (nome)
  (cdr (assoc nome HYDRO:*features*))
)

;; Dependencia OBRIGATORIA: avisa o usuario e retorna nil se faltar.
(defun HYDRO:Require (nome / ok)
  (setq ok (HYDRO:Has nome))
  (if (not ok)
    (HYDRO:Log (strcat "Plugin requerido nao carregado: " nome))
  )
  ok
)

(defun HYDRO:ListaFeatures (/ f out)
  (setq out "")
  (foreach f (reverse HYDRO:*features*)
    (setq out (strcat out (if (= out "") "" ", ") (car f) " " (cdr f)))
  )
  out
)

;;; ------------------------------------------------------------
;;; 2. EVENTOS
;;; ------------------------------------------------------------
;; Assinar:   (HYDRO:On "sarjeta.calculada" "xdata" 'XD:_OnSarjetaCalculada)
;; id evita assinatura duplicada quando o arquivo e recarregado.
(defun HYDRO:On (evento id fn)
  (setq HYDRO:*hooks*
    (append
      (vl-remove-if
        (function (lambda (h) (and (= (car h) evento) (= (cadr h) id))))
        HYDRO:*hooks*
      )
      (list (list evento id fn))
    )
  )
  id
)

(defun HYDRO:Off (evento id)
  (setq HYDRO:*hooks*
    (vl-remove-if
      (function (lambda (h) (and (= (car h) evento) (= (cadr h) id))))
      HYDRO:*hooks*
    )
  )
  T
)

;; Publicar: (HYDRO:Emit "sarjeta.calculada" resultado)
;; Um assinante com erro NAO derruba o emissor nem os outros assinantes.
;; Retorna quantos assinantes rodaram sem erro.
(defun HYDRO:Emit (evento dados / h r n)
  (setq n 0)
  (foreach h HYDRO:*hooks*
    (if (= (car h) evento)
      (progn
        (setq r (vl-catch-all-apply (caddr h) (list dados)))
        (if (vl-catch-all-error-p r)
          (HYDRO:Log
            (strcat "Erro no assinante '" (cadr h) "' do evento '" evento
                    "': " (vl-catch-all-error-message r))
          )
          (setq n (1+ n))
        )
      )
    )
  )
  n
)

;;; ------------------------------------------------------------
;;; 3. CONFIGURACAO COMPARTILHADA
;;; ------------------------------------------------------------
;; Se o plugin "persistencia" estiver carregado, grava no desenho (DB:).
;; Caso contrario, guarda so em memoria durante a sessao.
;; Quem usa HYDRO:Get / HYDRO:Set nao precisa saber qual dos dois esta ativo.
(defun HYDRO:Get (path padrao / v)
  (setq v
    (if (HYDRO:Has "persistencia")
      (DB:Get path)
      (cdr (assoc path HYDRO:*session*))
    )
  )
  (if v v padrao)
)

(defun HYDRO:Set (path valor)
  (if (HYDRO:Has "persistencia")
    (DB:Set path valor)
    (setq HYDRO:*session*
      (cons (cons path valor)
            (vl-remove (assoc path HYDRO:*session*) HYDRO:*session*)
      )
    )
  )
  valor
)

(defun HYDRO:Del (path)
  (if (HYDRO:Has "persistencia")
    (DB:Delete path)
    (setq HYDRO:*session* (vl-remove (assoc path HYDRO:*session*) HYDRO:*session*))
  )
  T
)

;;; ------------------------------------------------------------
;;; 4. UTILITARIOS COMUNS
;;; ------------------------------------------------------------
(defun HYDRO:Val (chave alist)
  (cdr (assoc chave alist))
)

;; Handle (string) de uma entidade ENAME ou VLA-OBJECT
(defun HYDRO:Handle (obj)
  (cond
    ((= (type obj) 'ENAME) (cdr (assoc 5 (entget obj))))
    ((= (type obj) 'VLA-OBJECT) (vla-get-handle obj))
    (T nil)
  )
)

;; 5 -> "5"   2.5 -> "2.50"
(defun HYDRO:FmtNum (x)
  (if (equal x (fix x) 1e-9)
    (itoa (fix x))
    (rtos x 2 2)
  )
)

;; Pergunta um real mostrando o valor atual; Enter mantem o atual.
(defun HYDRO:AskReal (msg atual / r)
  (setq r
    (getreal
      (strcat "\n" msg (if atual (strcat " <" (rtos atual 2 3) ">") "") ": ")
    )
  )
  (if r r atual)
)

(defun HYDRO:AskInt (msg atual / r)
  (setq r
    (getint
      (strcat "\n" msg (if atual (strcat " <" (itoa atual) ">") "") ": ")
    )
  )
  (if r r atual)
)

;; Localiza arquivo (DCL, SLD...) na pasta do HYDRO, na subpasta Sarjetas
;; ou no caminho de suporte do AutoCAD.
(defun HYDRO:FindFile (arquivo / cands achou)
  (setq cands (list arquivo))
  (if HYDRO:*dir*
    (setq cands
      (append
        (list (strcat HYDRO:*dir* "/" arquivo)
              (strcat HYDRO:*dir* "/Sarjetas/" arquivo))
        cands
      )
    )
  )
  (while (and cands (not achou))
    (setq achou (findfile (car cands)))
    (setq cands (cdr cands))
  )
  achou
)

;;; ------------------------------------------------------------
;;; 5. CARREGADOR
;;; ------------------------------------------------------------
(defun HYDRO:LoadModule (arquivo / path r)
  (setq path (HYDRO:FindFile arquivo))
  (cond
    ((not path)
      (HYDRO:Log (strcat "Modulo nao encontrado: " arquivo))
      nil
    )
    (T
      (setq r (vl-catch-all-apply 'load (list path)))
      (if (vl-catch-all-error-p r)
        (progn
          (HYDRO:Log (strcat "Erro ao carregar " arquivo ": "
                             (vl-catch-all-error-message r)))
          nil
        )
        (progn
          (HYDRO:Log (strcat "Modulo carregado: " arquivo))
          T
        )
      )
    )
  )
)

;; Lista de modulos. Para adicionar um plugin novo, inclua o nome aqui.
;; A ordem importa pouco: nenhum modulo executa codigo dependente de outro
;; no momento do load (tudo e resolvido quando o comando roda).
(defun HYDRO:Manifest ()
  '("persistence.lsp"
    "relacao.lsp"
    "idf.lsp"
    "sarjetas.lsp"
   )
)

(defun HYDRO:LoadAll (/ m)
  (foreach m (HYDRO:Manifest)
    (HYDRO:LoadModule m)
  )
  (HYDRO:Log (strcat "Plugins ativos: " (HYDRO:ListaFeatures)))
  (princ)
)

(HYDRO:Provide "core" "1.0")
(HYDRO:LoadAll)
(princ)
