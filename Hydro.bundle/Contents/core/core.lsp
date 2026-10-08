;;; ============================================================
;;; core.lsp - NUCLEO DO CONJUNTO HYDRO
;;;
;;; Responsabilidades:
;;;   1. Registro de funcionalidades  (Provide / Has / Require)
;;;   2. Eventos entre plugins        (On / Emit)
;;;   3. Configuracao compartilhada   (Get / Set / Del)
;;;   4. Utilitarios comuns           (AskReal, AskInt, FmtNum, ...)
;;;   5. Localizacao de arquivos      (FindFile / FindModule)
;;;   6. Carregador de modulos        (LoadModule / LoadAll)
;;;
;;; ESTRUTURA DE PASTAS (a raiz e a pasta Contents do bundle)
;;;   <raiz>/hydro.lsp          ponto de entrada (define HYDRO:*dir* e chama o core)
;;;   <raiz>/core/core.lsp      este arquivo
;;;   <raiz>/plugins/*.lsp      plugins do sistema (listados em HYDRO:Manifest, sem extensao)
;;;   <raiz>/plugins/models/    objetos do sistema (bacia, sarjeta...)
;;;   <raiz>/plugins/registry/  catalogos de metodos e tipos (so cadastros)
;;;   <raiz>/views/*.lsp        views: dialogos, comandos e desenho (idem)
;;;   <raiz>/resources/dcl      dialogos (.dcl)
;;;   <raiz>/resources/slides   imagens (.sld)
;;;   <raiz>/resources/icons    icones das barras de ferramentas (.bmp/.png)
;;; Este arquivo NAO carrega os plugins sozinho: quem chama HYDRO:LoadAll e o
;;; hydro.lsp (ou, no modo VLX, o proprio VLX ja traz tudo embutido).
;;;
;;; Variaveis globais do conjunto inteiro (as UNICAS):
;;;   HYDRO:*features*  alist  ("nome" . "versao")
;;;   HYDRO:*hooks*     lista  (evento id funcao)
;;;   HYDRO:*session*   alist  usada so quando NAO ha plugin de persistencia
;;;   HYDRO:*labels*    alist  rotulos legiveis dos dados (usado pelo visualizador)
;;;   HYDRO:*registry*  alist  catalogos de extensoes (metodos, tipos de hidrograma...)
;;;   HYDRO:*dir*       raiz do conjunto (pasta Contents), sem barra no final
;;;   HYDRO:*embedded*  T apenas quando tudo foi compilado em UM unico VLX
;;;
;;; CATALOGO DE EVENTOS (contrato entre plugins)
;;;   "sarjeta.calculada"  dados = alist com:
;;;       "BACIA" "TALVEGUE" (enames)   "AREA" "COMPRIMENTO" "DECLIVIDADE" "TC"
;;;       "CASOS" (lista de (rotulo tr intensidade vazao))
;;;       "Q" (vazao do primeiro caso)  "LAMINA" "LARGURA" "VELOCIDADE"
;;       "SECAO" (alist da secao)  "SECAO-ID"
;;; ============================================================
(vl-load-com)

(if (not (boundp 'HYDRO:*session*)) (setq HYDRO:*session* nil))
(setq HYDRO:*features* nil)
(setq HYDRO:*hooks* nil)
(setq HYDRO:*labels* nil)
(setq HYDRO:*registry* nil)

;; A raiz (HYDRO:*dir*) e definida pelo hydro.lsp ANTES de carregar o core.
(if (not (boundp 'HYDRO:*dir*)) (setq HYDRO:*dir* nil))
(if (not (boundp 'HYDRO:*embedded*)) (setq HYDRO:*embedded* nil))

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

;; Lista TODA a configuracao como alist plana (("HYDRO.IDF.K" . 781.0) ...),
;; seja qual for o backend (DB no desenho ou memoria da sessao).
;; Um no e "ramo" se seu valor e uma lista de nos (pares com chave string).
(defun HYDRO:_IsBranch (v)
  (and v
       (listp v)
       (vl-every
         (function (lambda (x) (and (listp x) x (= (type (car x)) 'STR))))
         v
       )
  )
)

(defun HYDRO:_Flatten (tree prefix / out n key v)
  (foreach n tree
    (if (and (listp n) n (= (type (car n)) 'STR))
      (progn
        (setq key (if (= prefix "") (car n) (strcat prefix "." (car n))))
        (setq v (cdr n))
        (if (HYDRO:_IsBranch v)
          (setq out (append out (HYDRO:_Flatten v key)))
          (setq out (append out (list (cons key v))))
        )
      )
    )
  )
  out
)

(defun HYDRO:ListAll ()
  (if (HYDRO:Has "persistencia")
    (HYDRO:_Flatten (DB:GetTree) "")
    HYDRO:*session*
  )
)

;;; ------------------------------------------------------------
;;; ROTULOS (descrevem os dados para quem for exibi-los)
;;; ------------------------------------------------------------
;; Cada plugin descreve os seus dados, sem saber quem vai usar:
;;   (HYDRO:SetLabel "HYDRO.RUNOFF" "Coeficiente de runoff (C)" "")
;;   (HYDRO:SetLabel "xdata:DREN-SARJETA:1040" "Vazao Q" "m3/s")
;; Chaves de XData: "xdata:<APP>:<codigo>".  Chaves de DB: o proprio path.
(defun HYDRO:SetLabel (chave rotulo unidade)
  (setq HYDRO:*labels*
    (cons (cons chave (cons rotulo unidade))
          (vl-remove (assoc chave HYDRO:*labels*) HYDRO:*labels*)
    )
  )
  chave
)

;; Retorna (rotulo . unidade) ou nil
(defun HYDRO:GetLabel (chave)
  (cdr (assoc chave HYDRO:*labels*))
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

;; Junta uma lista de strings com um separador
(defun HYDRO:Join (linhas sep / out l)
  (setq out (car linhas))
  (foreach l (cdr linhas)
    (setq out (strcat out sep l))
  )
  (if out out "")
)

(defun HYDRO:_Pad2 (n)
  (if (< n 10) (strcat "0" (itoa n)) (itoa n))
)

;; Data e hora atuais: "2026-10-02 15:30"
(defun HYDRO:Now (/ c d f)
  (setq c (getvar "CDATE"))
  (setq d (fix c))
  (setq f (fix (+ 0.5 (* 1000000.0 (- c d)))))
  (strcat
    (itoa (/ d 10000)) "-"
    (HYDRO:_Pad2 (rem (/ d 100) 100)) "-"
    (HYDRO:_Pad2 (rem d 100)) " "
    (HYDRO:_Pad2 (/ f 10000)) ":"
    (HYDRO:_Pad2 (rem (/ f 100) 100))
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

;;; ------------------------------------------------------------
;;; REGISTRO DE EXTENSOES (catalogos de metodos, tipos, ...)
;;; ------------------------------------------------------------
;; Qualquer plugin pode cadastrar itens em um catalogo e qualquer outro pode
;; listar/usar, sem se conhecerem:
;;   (HYDRO:RegAdd "metodo-chuva-vazao" "racional" dados)   ; dados = alist
;;   (HYDRO:RegList "metodo-chuva-vazao")   -> (("racional" . dados) ...)
;;   (HYDRO:RegGet  "metodo-chuva-vazao" "racional")        -> dados
;; Catalogos em uso: "metodo-chuva-vazao" (metodos.lsp) e
;; "hidrograma-tipo" (hidrograma.lsp). Veja docs/arquitetura.md.
(defun HYDRO:RegAdd (cat id dados / lista)
  (setq lista (cdr (assoc cat HYDRO:*registry*)))
  (setq lista
    (append (vl-remove (assoc id lista) lista) (list (cons id dados)))
  )
  (setq HYDRO:*registry*
    (cons (cons cat lista)
          (vl-remove (assoc cat HYDRO:*registry*) HYDRO:*registry*)
    )
  )
  id
)

(defun HYDRO:RegList (cat)
  (cdr (assoc cat HYDRO:*registry*))
)

(defun HYDRO:RegGet (cat id)
  (cdr (assoc id (HYDRO:RegList cat)))
)

;; Remove um item do catalogo (util em testes ou para desativar um item)
(defun HYDRO:RegDel (cat id / lista)
  (setq lista (vl-remove (assoc id (HYDRO:RegList cat)) (HYDRO:RegList cat)))
  (setq HYDRO:*registry*
    (cons (cons cat lista)
          (vl-remove (assoc cat HYDRO:*registry*) HYDRO:*registry*)))
  T
)

;;; ------------------------------------------------------------
;;; UTILITARIOS DE ENTRADA/SAIDA
;;; ------------------------------------------------------------
;; "0,045" ou "0.045" -> 0.045 ; vazio/invalido -> nil
(defun HYDRO:ParseReal (s)
  (if (and s (/= (vl-string-trim " " s) ""))
    (distof (vl-string-subst "." "," s) 2)
    nil
  )
)

;; real sem zeros a direita: 781.000000 -> 781 ; nil -> ""
(defun HYDRO:FmtReal (x / s)
  (if x
    (progn
      (setq s (rtos x 2 6))
      (if (vl-string-search "." s)
        (progn
          (while (= (substr s (strlen s)) "0")
            (setq s (substr s 1 (1- (strlen s))))
          )
          (if (= (substr s (strlen s)) ".")
            (setq s (substr s 1 (1- (strlen s))))
          )
        )
      )
      s
    )
    ""
  )
)

;; numero para CSV do Excel pt-BR (virgula decimal)
(defun HYDRO:CsvNum (x)
  (vl-string-subst "," "." (HYDRO:FmtReal x))
)

;; Menu numerado na linha de comando. Retorna o indice (0-based).
(defun HYDRO:Escolher (titulo itens padrao / i r txt)
  (princ (strcat "\n" titulo))
  (setq i 0)
  (foreach txt itens
    (setq i (1+ i))
    (princ (strcat "\n  " (itoa i) " - " txt))
  )
  (setq r
    (getint
      (strcat "\nEscolha [1-" (itoa (length itens)) "] <" (itoa (1+ padrao)) ">: ")
    )
  )
  (cond
    ((not r) padrao)
    ((and (>= r 1) (<= r (length itens))) (1- r))
    (T padrao)
  )
)

;; Pergunta UM parametro conforme o tipo: "real" (padrao), "int",
;; "arquivo" (getfiled) ou "opcoes" (menu numerado sobre a lista ops)
(defun HYDRO:_AskUm (rot uni tipo ops atual / r i txt)
  (setq txt (strcat rot (if (and uni (/= uni "")) (strcat " (" uni ")") "")))
  (cond
    ((= tipo "arquivo")
      (setq r (getfiled txt (if atual atual "") "csv;txt" 0))
      (if r r atual)
    )
    ((= tipo "opcoes")
      ;; ops = lista de strings, ou SIMBOLO de uma funcao (sem argumentos)
      ;; que devolve a lista no momento da pergunta (opcoes dinamicas)
      (if (and ops (not (listp ops)))
        (setq ops (apply ops nil))
      )
      (if ops
        (progn
          (setq i (vl-position atual ops))
          (nth (HYDRO:Escolher txt ops (if i i 0)) ops)
        )
        atual
      )
    )
    ((= tipo "int") (HYDRO:AskInt txt atual))
    (T (HYDRO:AskReal txt atual))
  )
)

;; Pergunta uma LISTA de parametros descritos em defs:
;;   defs = lista de (chave rotulo padrao unidade [tipo [opcoes]])
;;   prefixo = onde lembrar o ultimo valor usado (ex.: "HYDRO.MET.scs-cn.")
;;   sobrescritas = alist (chave . valor) que vale como padrao desta vez
;;                  (nao e memorizado)
;; Retorna alist (chave . valor).
(defun HYDRO:AskParams (defs prefixo sobrescritas / out d chave atual v)
  (foreach d defs
    (setq chave (nth 0 d))
    (setq atual (HYDRO:Get (strcat prefixo chave) nil))
    (if (assoc chave sobrescritas)
      (setq atual (cdr (assoc chave sobrescritas)))
    )
    (if (not atual) (setq atual (nth 2 d)))
    (setq v
      (HYDRO:_AskUm
        (nth 1 d) (nth 3 d) (if (nth 4 d) (nth 4 d) "real") (nth 5 d) atual
      )
    )
    (if (not (assoc chave sobrescritas))
      (HYDRO:Set (strcat prefixo chave) v)
    )
    (setq out (append out (list (cons chave v))))
  )
  out
)

;; Cria um MTEXT diretamente no banco de dados (sem COMMAND).
;;   pt = ponto no UCS ; str = texto (use "\\P" para quebra de linha)
;;   altura em unidades do desenho ; rot em graus
(defun HYDRO:Mtext (pt str altura rot)
  (entmakex
    (list
      '(0 . "MTEXT")
      '(100 . "AcDbEntity")
      '(100 . "AcDbMText")
      (cons 7 (getvar "TEXTSTYLE"))
      (cons 10 (trans pt 1 0))
      (cons 40 altura)
      (cons 41 0.0)
      (cons 71 1)
      (cons 50 (* rot (/ pi 180.0)))
      (cons 1 str)
    )
  )
)

;; Zoom em uma entidade (janela com 15% de margem). Retorna T ou nil.
(defun HYDRO:ZoomEnt (en / obj mn mx dx dy m r)
  (setq obj (vlax-ename->vla-object en))
  (setq r
    (vl-catch-all-apply
      (function
        (lambda ()
          (vla-getboundingbox obj 'mn 'mx)
          (setq mn (vlax-safearray->list mn))
          (setq mx (vlax-safearray->list mx))
          (setq dx (- (car mx) (car mn)))
          (setq dy (- (cadr mx) (cadr mn)))
          (setq m (max (* 0.15 (max dx dy)) 1.0))
          (vla-zoomwindow
            (vlax-get-acad-object)
            (vlax-3d-point (list (- (car mn) m) (- (cadr mn) m) 0.0))
            (vlax-3d-point (list (+ (car mx) m) (+ (cadr mx) m) 0.0))
          )
          T
        )
      )
      nil
    )
  )
  (if (vl-catch-all-error-p r) nil r)
)

;;; ------------------------------------------------------------
;;; DADOS GRAVADOS EM ENTIDADES (qualquer objeto, inclusive do Civil 3D)
;;; ------------------------------------------------------------
;; Os dados ficam no dicionario de extensao da propria entidade (vlax-ldata),
;; de modo que acompanham a entidade ao copiar, colar e salvar. Se a entidade
;; nao aceitar dados (objeto bloqueado ou de um tipo que nao permite
;; dicionario de extensao), grava na RESERVA CENTRAL: dicionario
;; "HYDRO-CENTRAL" do desenho, com chave "<chave>:<handle>". A leitura procura
;; primeiro na entidade e depois na reserva; quem chama nao precisa saber onde.
;;   (HYDRO:DadoGravar en "HYDRO-OBJ" alist)  -> T ou nil
;;   (HYDRO:DadoLer    en "HYDRO-OBJ")        -> alist ou nil
;;   (HYDRO:DadoApagar en "HYDRO-OBJ")
;; Nao grave pares com valor nil (use T ou omita o par).
(defun HYDRO:_CentralKey (chave en)
  (strcat chave ":" (HYDRO:Handle en))
)

(defun HYDRO:DadoLer (en chave / r)
  (setq r (vl-catch-all-apply 'vlax-ldata-get (list en chave nil)))
  (if (or (vl-catch-all-error-p r) (null r))
    (progn
      (setq r
        (vl-catch-all-apply
          'vlax-ldata-get
          (list "HYDRO-CENTRAL" (HYDRO:_CentralKey chave en) nil)))
      (if (vl-catch-all-error-p r) nil r)
    )
    r
  )
)

(defun HYDRO:DadoGravar (en chave dados / r)
  (setq r (vl-catch-all-apply 'vlax-ldata-put (list en chave dados)))
  (if (vl-catch-all-error-p r)
    (progn
      (setq r
        (vl-catch-all-apply
          'vlax-ldata-put
          (list "HYDRO-CENTRAL" (HYDRO:_CentralKey chave en) dados)))
      (if (vl-catch-all-error-p r) nil T)
    )
    (progn
      ;; gravou na entidade: remove copia antiga da reserva (evita divergencia)
      (vl-catch-all-apply
        'vlax-ldata-delete
        (list "HYDRO-CENTRAL" (HYDRO:_CentralKey chave en)))
      T
    )
  )
)

(defun HYDRO:DadoApagar (en chave)
  (vl-catch-all-apply 'vlax-ldata-delete (list en chave))
  (vl-catch-all-apply
    'vlax-ldata-delete
    (list "HYDRO-CENTRAL" (HYDRO:_CentralKey chave en)))
  T
)

;; A entidade existe e nao foi apagada?
(defun HYDRO:EntValida (en / r)
  (if (and en (= (type en) 'ENAME))
    (progn
      (setq r
        (vl-catch-all-apply
          (function
            (lambda ()
              (not (vlax-erased-p (vlax-ename->vla-object en)))
            )
          )
          nil
        )
      )
      (if (or (vl-catch-all-error-p r) (not r)) nil T)
    )
    nil
  )
)

;; Nome DXF da entidade (grupo 0): "LWPOLYLINE", "AECC_PIPE"...
(defun HYDRO:DxfDe (en / d)
  (setq d (vl-catch-all-apply 'entget (list en)))
  (if (or (vl-catch-all-error-p d) (null d))
    nil
    (cdr (assoc 0 d))
  )
)

;;; ------------------------------------------------------------
;;; FONTE DE TRACOS PARA IMAGENS DE DCL
;;; (DCL nao desenha texto dentro de imagem; as letras sao tracos)
;;; Entrada: (caractere largura (x1 y1 x2 y2) ...), y cresce para baixo.
;;; ------------------------------------------------------------
(defun HYDRO:_Glifos ()
  '(("0" 6 (0 0 6 0) (6 0 6 10) (6 10 0 10) (0 10 0 0))
    ("1" 6 (3 0 3 10) (1 2 3 0) (1 10 5 10))
    ("2" 6 (0 0 6 0) (6 0 6 5) (6 5 0 5) (0 5 0 10) (0 10 6 10))
    ("3" 6 (0 0 6 0) (6 0 6 10) (0 5 6 5) (0 10 6 10))
    ("4" 6 (0 0 0 5) (0 5 6 5) (6 0 6 10))
    ("5" 6 (6 0 0 0) (0 0 0 5) (0 5 6 5) (6 5 6 10) (6 10 0 10))
    ("6" 6 (6 0 0 0) (0 0 0 10) (0 10 6 10) (6 10 6 5) (6 5 0 5))
    ("7" 6 (0 0 6 0) (6 0 6 10))
    ("8" 6 (0 0 6 0) (6 0 6 10) (6 10 0 10) (0 10 0 0) (0 5 6 5))
    ("9" 6 (0 0 6 0) (0 0 0 5) (0 5 6 5) (6 0 6 10) (0 10 6 10))
    ("." 2 (0 9 1 9) (0 10 1 10))
    (":" 2 (0 3 1 3) (0 4 1 4) (0 8 1 8) (0 9 1 9))
    ("%" 6 (0 10 6 0) (0 0 2 0) (2 0 2 2) (2 2 0 2) (0 2 0 0)
           (4 8 6 8) (6 8 6 10) (6 10 4 10) (4 10 4 8))
    ("=" 6 (0 3 6 3) (0 7 6 7))
    (" " 4)
    ("V" 6 (0 0 3 10) (3 10 6 0))
    ("H" 6 (0 0 0 10) (6 0 6 10) (0 5 6 5))
    ("h" 6 (0 0 0 10) (0 6 3 4) (3 4 6 6) (6 6 6 10))
    ("w" 8 (0 4 2 10) (2 10 4 5) (4 5 6 10) (6 10 8 4))
    ("s" 5 (5 4 1 4) (1 4 1 7) (1 7 5 7) (5 7 5 10) (5 10 1 10))
    ("y" 6 (0 3 3 10) (6 3 2 13))
   )
)

;; Desenha o texto em (x,y) (canto superior esquerdo). Retorna o x final.
(defun HYDRO:ImgTexto (str x y cor / i g seg)
  (setq i 1)
  (while (<= i (strlen str))
    (setq g (assoc (substr str i 1) (HYDRO:_Glifos)))
    (if g
      (progn
        (foreach seg (cddr g)
          (vector_image
            (+ x (nth 0 seg)) (+ y (nth 1 seg))
            (+ x (nth 2 seg)) (+ y (nth 3 seg))
            cor
          )
        )
        (setq x (+ x (cadr g) 3))
      )
      (setq x (+ x 6))
    )
    (setq i (1+ i))
  )
  x
)

;; Largura em pixels do texto (sem o espacamento depois do ultimo caractere)
(defun HYDRO:ImgTextoLargura (str / i g w)
  (setq i 1 w 0)
  (while (<= i (strlen str))
    (setq g (assoc (substr str i 1) (HYDRO:_Glifos)))
    (setq w (+ w (if g (cadr g) 6) 3))
    (setq i (1+ i))
  )
  (if (> w 0) (- w 3) 0)
)


;; Subpastas da raiz onde recursos e codigo podem estar.
;; "Sarjetas/" e mantida por compatibilidade com a estrutura antiga.
(defun HYDRO:_SubDirs ()
  '("" "core/" "plugins/" "plugins/models/" "plugins/registry/" "views/" "resources/dcl/" "resources/slides/" "resources/icons/")
)

;; Localiza um arquivo de recurso (DCL, SLD, ...) pelo NOME, sem precisar saber
;; em que subpasta esta:  (HYDRO:FindFile "idf.dcl")
;; Ordem: raiz do HYDRO e subpastas conhecidas; depois o caminho de suporte
;; do AutoCAD (o PackageContents.xml pode acrescentar pastas a ele).
(defun HYDRO:FindFile (arquivo / subs achou)
  (setq subs (if HYDRO:*dir* (HYDRO:_SubDirs) nil))
  (while (and subs (not achou))
    (setq achou (findfile (strcat HYDRO:*dir* "/" (car subs) arquivo)))
    (setq subs (cdr subs))
  )
  (if achou achou (findfile arquivo))
)

;; Devolve o caminho do PRIMEIRO arquivo existente da lista (ou nil).
;; ATENCAO: em AutoLISP, (or ...) e (and ...) devolvem T ou nil, NAO o valor
;; da expressao. Por isso nao se usa (or (findfile a) (findfile b)) para
;; obter um caminho; use esta funcao.
(defun HYDRO:FirstFile (caminhos / achou)
  (while (and caminhos (not achou))
    (setq achou (findfile (car caminhos)))
    (setq caminhos (cdr caminhos))
  )
  achou
)

;; Localiza um MODULO de codigo pelo caminho relativo a raiz, SEM extensao:
;;   (HYDRO:FindModule "plugins/idf")
;; Prefere .fas (compilado) e cai para .lsp (fonte).
(defun HYDRO:FindModule (rel / exts cands achou)
  (setq exts '(".fas" ".lsp"))
  (while (and exts (not achou))
    (setq cands (list (strcat rel (car exts))))
    (if HYDRO:*dir*
      (setq cands (cons (strcat HYDRO:*dir* "/" rel (car exts)) cands))
    )
    (setq achou (HYDRO:FirstFile cands))
    (setq exts (cdr exts))
  )
  achou
)

;;; ------------------------------------------------------------
;;; 6. CARREGADOR
;;; ------------------------------------------------------------
(defun HYDRO:LoadModule (rel / path r)
  (setq path (HYDRO:FindModule rel))
  (cond
    ((not path)
      (HYDRO:Log (strcat "Modulo nao encontrado: " rel))
      nil
    )
    (T
      (setq r (vl-catch-all-apply 'load (list path)))
      (if (vl-catch-all-error-p r)
        (progn
          (HYDRO:Log (strcat "Erro ao carregar " rel ": "
                             (vl-catch-all-error-message r)))
          nil
        )
        (progn
          (HYDRO:Log (strcat "Modulo carregado: " rel))
          T
        )
      )
    )
  )
)

;; Lista de modulos (caminho relativo a raiz, SEM extensao).
;; Para adicionar um plugin novo, inclua-o aqui.
;; A ordem importa pouco: nenhum modulo executa codigo dependente de outro
;; no momento do load (tudo e resolvido quando o comando roda).

;; plugins/          = sistema (dados, calculo, eventos); carrega primeiro.
;; plugins/models/   = objetos do sistema (bacia, sarjeta...): so a funcionalidade do objeto.
;; plugins/registry/ = catalogos de metodos e tipos (so cadastros); depois do sistema.
;; views/   = interface (dialogos, comandos, desenho); depende dos plugins.
(defun HYDRO:Manifest ()
  '("plugins/persistence"
    "plugins/relacao"
    "plugins/idf"
    "plugins/precipitacao"
    "plugins/secao"
    "plugins/sarjetas"
    "plugins/hidrograma"
    "plugins/objetos"
    "plugins/ligacao"
    "plugins/objetos_padrao"
    "plugins/auditoria"
    "plugins/models/bacia"
    "plugins/models/sarjeta"
    "plugins/models/objetos_tipos"
    "plugins/registry/metodos"
    "plugins/registry/tempo_conc"
    "plugins/registry/hidrograma_tipos"
    "plugins/registry/hietograma_tipos"
    "views/idf_view"
    "views/secao_view"
    "views/bacia_view"
    "views/bacia_tabela"
    "views/hidrograma_view"
    "views/objetos_tabela"
    "views/objetos_padrao_view"
    "views/auditoria_view"
    "views/viewer"
    "views/painel"
    "views/painel_acoes"
    "views/menu"
    "views/toolbar"
   )
)

(defun HYDRO:LoadAll (/ m)
  (foreach m (HYDRO:Manifest)
    (HYDRO:LoadModule m)
  )
  (HYDRO:Log (strcat "Plugins ativos: " (HYDRO:ListaFeatures)))
  ;; todos os plugins ja cadastraram o que tinham a cadastrar (catalogos,
  ;; acoes, rotulos): quem precisa do conjunto completo age agora
  (HYDRO:Emit "hydro.carregado" nil)
  (princ)
)

(defun c:HYDROPLUGINS ()
  (HYDRO:Log (strcat "Raiz: " (if HYDRO:*dir* HYDRO:*dir* "(nao definida)")))
  (HYDRO:Log (strcat "Plugins ativos: " (HYDRO:ListaFeatures)))
  (princ)
)

(HYDRO:Provide "core" "1.0")
(princ)
