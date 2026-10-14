;;; ============================================================
;;; objetos_padrao.lsp - CONSULTAS PADRAO DOS OBJETOS HIDRAULICOS (OPD:)
;;;
;;; Parte de SISTEMA (sem interacao). Serve a interface padrao de comandos
;;; que todo objeto hidraulico tem (docs/arquitetura.md secao 18b):
;;;     <TIPO>CAD   cadastrar / editar        <TIPO>S     listar os cadastrados
;;;     <TIPO>INFO  ver informacoes           <TIPO>ZOOM  encontrar e dar zoom
;;; e a OBJETOVINCULOS (realce dos vinculos de PARAMS). Os fluxos com perguntas
;;; ficam em views/objetos_padrao_view.lsp.
;;;
;;; O QUE ESTE ARQUIVO OFERECE
;;;   OPD:Objetos tipo         enames dos objetos de um tipo (nil = todos)
;;;   OPD:Procurar tipo texto  objetos cujo nome contem o texto ou cujo handle e igual
;;;   OPD:Casa texto nome h    teste puro usado por OPD:Procurar
;;;   OPD:Linha en             "nome  [Tipo]  handle"
;;;   OPD:Referencias en       vinculos de PARAMS: lista de (chave . handle); os
;;;                            o handle de JUSANTE vem como ("JUSANTE" . handle)
;;;   OPD:Alvo handle          ename do alvo de um vinculo, ou nil se nao existe
;;;   OPD:Vinculos filtro      todos os vinculos: (origem chave handle alvo-ou-nil)
;;;   OPD:Referenciando en     objetos que apontam para `en` em algum PARAMS
;;;
;;; AUDITORIA (catalogo "auditoria"; ver plugins/auditoria.lsp). Cadastra aqui:
;;;   "indice"        handles de HYDRO.OBJETOS que nao existem mais e objetos do
;;;                   desenho fora do indice (corrige: OBJ:Reindexar)
;;;   "params"        vinculos de PARAMS (exceto JUSANTE, que e da verificacao
;;;                   "ligacoes") que apontam para entidade apagada ou inexistente (corrige: escolher outra entidade ou remover o vinculo)
;;;   "tipo-ausente"  cadastro de um tipo que nao esta carregado (so informa; nao
;;;                   apaga nada, pois os dados voltam a valer ao carregar o tipo)
;;;
;;; Sem variaveis globais.
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; BUSCA (puro)
;;; ------------------------------------------------------------
;; Objetos de um tipo (tipo = id) ou de todos os tipos (tipo = nil)
(defun OPD:Objetos (tipo)
  (if tipo (OBJ:ListaTipo tipo) (OBJ:Listar))
)

;; Teste puro: o texto vazio casa com tudo; senao casa o handle igual ou o nome
;; que CONTEM o texto (sem diferenciar maiusculas).
(defun OPD:Casa (texto nome handle / t1)
  (setq t1 (strcase texto))
  (cond
    ((equal t1 "") T)
    ((equal t1 (strcase handle)) T)
    ((vl-string-search t1 (strcase nome)) T)
    (T nil)
  )
)

(defun OPD:Procurar (tipo texto / out en)
  (foreach en (OPD:Objetos tipo)
    (if (OPD:Casa texto (OBJ:Nome en) (HYDRO:Handle en))
      (setq out (append out (list en)))
    )
  )
  out
)

(defun OPD:Linha (en)
  (strcat (OBJ:Nome en) "  [" (OBJ:_NomeTipo (OBJ:TipoDe en)) "]  " (HYDRO:Handle en))
)

;;; ------------------------------------------------------------
;;; VINCULOS (PARAMS)
;;; ------------------------------------------------------------
;; PARAMS guarda ligacoes com OUTROS objetos/entidades: (chave . handle). Todo
;; valor string de PARAMS e tratado como handle.
(defun OPD:Referencias (en / out p)
  (foreach p (OBJ:ParamsDe en)
    (cond
      ((= (type (cdr p)) 'STR)
        (setq out (append out (list p))))
      ;; JUSANTE e um par (handle . flag): o handle e um vinculo
      ((and (equal (car p) "JUSANTE") (listp (cdr p)))
        (setq out (append out (list (cons "JUSANTE" (car (cdr p)))))))
    )
  )
  out
)

;; ename do alvo, ou nil se o handle nao existe mais (ou a entidade foi apagada)
(defun OPD:Alvo (h / e)
  (setq e (vl-catch-all-apply 'handent (list h)))
  (if (and e (not (vl-catch-all-error-p e)) (HYDRO:EntValida e)) e nil)
)

;; filtro = ename de um objeto (so os vinculos dele) ou nil (todos os objetos)
;; Retorna lista de (origem chave handle alvo); alvo = nil quando o vinculo esta quebrado
(defun OPD:Vinculos (filtro / out o p)
  (foreach o (if filtro (list filtro) (OBJ:Listar))
    (foreach p (OPD:Referencias o)
      (setq out
        (append out (list (list o (car p) (cdr p) (OPD:Alvo (cdr p))))))
    )
  )
  out
)

;; objetos que apontam para `en` em algum PARAMS
(defun OPD:Referenciando (en / out v)
  (foreach v (OPD:Vinculos nil)
    (if (and (nth 3 v) (equal (nth 3 v) en) (not (member (car v) out)))
      (setq out (append out (list (car v))))
    )
  )
  out
)

;;; ------------------------------------------------------------
;;; AUDITORIA: INDICE
;;; ------------------------------------------------------------
;; entidades do desenho (dos tipos DXF conhecidos) que tem registro HYDRO-OBJ
(defun OPD:_ComRegistro (/ dxfs ss i en out)
  (setq dxfs (OBJ:DxfUniao))
  (if dxfs
    (setq ss (ssget "_X" (list (cons 0 (HYDRO:Join dxfs ",")))))
  )
  (if ss
    (progn
      (setq i (sslength ss))
      (while (> i 0)
        (setq i (1- i))
        (setq en (ssname ss i))
        (if (OBJ:Ler en)
          (setq out (cons en out))
        )
      )
    )
  )
  out
)

;; problemas: ("FANTASMA" handle) | ("FORA" ename)
(defun OPD:_AudIndice (/ out h en listados)
  (foreach h (HYDRO:Get "HYDRO.OBJETOS" nil)
    (setq en (handent h))
    (if (not (and en (HYDRO:EntValida en) (OBJ:Ler en)))
      (setq out (append out (list (list "FANTASMA" h))))
    )
  )
  (setq listados (OBJ:Listar))
  (foreach en (OPD:_ComRegistro)
    (if (and (OBJ:TipoDe en) (not (member en listados)))
      (setq out (append out (list (list "FORA" en))))
    )
  )
  out
)

(defun OPD:_TxtIndice (p)
  (if (equal (car p) "FANTASMA")
    (strcat "Indice de objetos cita o handle " (cadr p)
            ", que nao existe mais ou nao tem cadastro")
    (strcat "Objeto fora do indice: " (OBJ:Nome (cadr p)) " (" (HYDRO:Handle (cadr p)) ")")
  )
)

(defun OPD:_ReparaIndice (problemas)
  (OBJ:Reindexar)
  (length problemas)
)

;;; ------------------------------------------------------------
;;; AUDITORIA: VINCULOS DE PARAMS
;;; ------------------------------------------------------------
;; problemas: ("PARAMS-QUEBRADO" origem chave handle)
(defun OPD:_AudParams (/ out v)
  (foreach v (OPD:Vinculos nil)
    ;; JUSANTE e auditado pela verificacao "ligacoes" (plugin ligacao)
    (if (and (not (nth 3 v)) (not (equal (nth 1 v) "JUSANTE")))
      (setq out
        (append out
          (list (list "PARAMS-QUEBRADO" (nth 0 v) (nth 1 v) (nth 2 v)))))
    )
  )
  out
)

(defun OPD:_TxtParams (p)
  (strcat "Vinculo quebrado: " (OBJ:Nome (nth 1 p)) " -> " (nth 2 p)
          " (handle " (nth 3 p) " nao existe)")
)

;; Para cada vinculo pergunta: outra entidade, [Remover] o vinculo, ou Enter
;; (deixa como esta). Esc interrompe sem alterar o que falta. Retorna quantos corrigiu.
(defun OPD:_ReparaParams (problemas / n p en chave h sel reg params)
  (setq n 0)
  (foreach p problemas
    (setq en (nth 1 p) chave (nth 2 p) h (nth 3 p))
    (if (HYDRO:EntValida en)
      (progn
        (princ
          (strcat "\n" (OBJ:Nome en) ": o vinculo " chave " aponta para " h
                  ", que nao existe mais."))
        (initget "Remover")
        (setq sel
          (vl-catch-all-apply 'entsel
            (list (strcat "\nSelecione a nova entidade de " chave
                          " ou [Remover vinculo] (Enter = deixar como esta): "))))
        (if (vl-catch-all-error-p sel) (setq sel nil))
        (if sel
          (progn
            (setq reg (OBJ:Registro en))
            (setq params (HYDRO:Val "PARAMS" reg))
            (setq params
              (if (equal sel "Remover")
                (vl-remove (assoc chave params) params)
                (subst (cons chave (HYDRO:Handle (car sel))) (assoc chave params) params)))
            (if (OBJ:GravaRegistro (OBJ:TipoDe en) en (OBJ:_SetChave reg "PARAMS" params))
              (setq n (1+ n))
            )
          )
        )
      )
    )
  )
  n
)

;;; ------------------------------------------------------------
;;; AUDITORIA: TIPO AUSENTE (so informa)
;;; ------------------------------------------------------------
(defun OPD:_AudTipo (/ out en)
  (foreach en (OPD:_ComRegistro)
    (if (not (OBJ:TipoDe en))
      (setq out
        (append out
          (list (list "TIPO-AUSENTE" en (HYDRO:Val "TIPO" (OBJ:Ler en))))))
    )
  )
  out
)

(defun OPD:_TxtTipo (p)
  (strcat "Entidade " (HYDRO:Handle (nth 1 p)) " tem cadastro do tipo '"
          (if (nth 2 p) (nth 2 p) "?")
          "' que nao esta carregado (os dados foram preservados)")
)

(HYDRO:RegAdd "auditoria" "indice"
  (list (cons "NOME" "Indice de objetos")
        (cons "VERIFICA" 'OPD:_AudIndice)
        (cons "TEXTO" 'OPD:_TxtIndice)
        (cons "REPARA" 'OPD:_ReparaIndice)))

(HYDRO:RegAdd "auditoria" "params"
  (list (cons "NOME" "Vinculos (PARAMS)")
        (cons "VERIFICA" 'OPD:_AudParams)
        (cons "TEXTO" 'OPD:_TxtParams)
        (cons "REPARA" 'OPD:_ReparaParams)))

(HYDRO:RegAdd "auditoria" "tipo-ausente"
  (list (cons "NOME" "Tipos de objeto ausentes")
        (cons "VERIFICA" 'OPD:_AudTipo)
        (cons "TEXTO" 'OPD:_TxtTipo)))

(HYDRO:Provide "objetos-padrao" "1.0")
(princ)
