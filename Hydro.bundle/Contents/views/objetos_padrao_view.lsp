;;; ============================================================
;;; views/objetos_padrao_view.lsp - FLUXOS PADRAO DOS COMANDOS DE OBJETO (OPV:)
;;;
;;; Os fluxos que os modelos usam nos comandos padrao, cada um recebendo o id do
;;; tipo (docs/arquitetura.md secao 18b):
;;;   (OPV:Cadastrar tipo)   <TIPO>CAD   escolhe a entidade e cadastra / edita
;;;   (OPV:EditaCampo tipo)  <TIPO>EDITA escolhe o objeto e UM campo a alterar
;;;   (OPV:Listar tipo)      <TIPO>S     lista os cadastrados (tipo nil = todos)
;;;   (OPV:Info tipo)        <TIPO>INFO  mostra as informacoes de um objeto
;;;   (OPV:Zoom tipo)        <TIPO>ZOOM  procura por nome/handle, da zoom e seleciona
;;; Comandos gerais (valem para qualquer tipo)
;;;   OBJETOS          lista os objetos de um tipo (ou todos)
;;;   OBJETOZOOM       localiza qualquer objeto
;;;   OBJETOVINCULOS   realca as entidades vinculadas em PARAMS (ex.: talvegue)
;;; Depende de "objetos-padrao".
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; REALCE E SELECAO
;;; ------------------------------------------------------------
;; Seleciona as entidades (ficam com grips ate Esc) e as realca com REDRAW
(defun OPV:Selecionar (lista / ss en)
  (setq ss (ssadd))
  (foreach en lista
    (ssadd en ss)
    (vl-catch-all-apply 'redraw (list en 3))
  )
  (vl-catch-all-apply 'sssetfirst (list nil ss))
  ss
)

;; Zoom no objeto, seleciona e mostra a linha dele
(defun OPV:Ir (en)
  (if (not (HYDRO:ZoomEnt en))
    (princ "\nNao foi possivel dar zoom nesta entidade.")
  )
  (OPV:Selecionar (list en))
  (princ (strcat "\n" (OPD:Linha en)))
)

;;; ------------------------------------------------------------
;;; FLUXOS POR TIPO
;;; ------------------------------------------------------------
(defun OPV:Cadastrar (tipo / sel en)
  (setq sel
    (entsel
      (strcat "\nSelecione a entidade para cadastrar/editar como "
              (OBJ:_NomeTipo tipo) ": ")))
  (if sel
    (progn
      (setq en (car sel))
      (if (if (and (equal (OBJ:TipoDe en) tipo) (OBJ:Cap tipo "EDITAR"))
            (OBJ:Editar en)
            (OBJ:CadastroInterativoTipo en tipo))
        (alert (OBJ:ToString en))
      )
    )
  )
  (princ)
)

;; <TIPO>EDITA: escolhe o objeto, depois o CAMPO a alterar; pergunta so ele
(defun OPV:EditaCampo (tipo / sel en)
  (setq sel (entsel (strcat "\nSelecione o objeto (" (OBJ:_NomeTipo tipo) ") a editar: ")))
  (if sel
    (progn
      (setq en (car sel))
      (cond
        ((not (equal (OBJ:TipoDe en) tipo))
          (alert (strcat "Esta entidade nao e do tipo " (OBJ:_NomeTipo tipo) ".")))
        ((OBJ:EditaCampoInterativo en)
          (princ "\nCampo alterado.")
          (if (OBJ:Obsoleto en nil)
            (princ "\nResultado desatualizado: recalcule com CALCULAOBJETO."))
        )
      )
    )
  )
  (princ)
)

(defun OPV:Listar (tipo / lista en dest)
  (setq lista (OPD:Objetos tipo))
  (if lista
    (progn
      (princ
        (strcat "\n=== " (if tipo (OBJ:_NomeTipo tipo) "OBJETOS HIDRAULICOS")
                " no desenho: " (itoa (length lista)) " ==="))
      (princ "\nnome   [tipo]   handle   afluentes   destino")
      (foreach en lista
        (princ (strcat "\n" (OPD:Linha en)))
        (if (HYDRO:Has "ligacao")
          (progn
            (setq dest (LIG:Destino en))
            (princ
              (strcat "   " (itoa (length (LIG:Afluentes en))) " afluente(s)   "
                      (if dest (strcat "-> " (OBJ:Nome dest)) "sem destino")))
          )
        )
      )
    )
    (princ
      (strcat "\nNenhum objeto "
              (if tipo (strcat "do tipo " (OBJ:_NomeTipo tipo) " ") "")
              "cadastrado neste desenho."))
  )
  (princ)
)

(defun OPV:Info (tipo / sel en)
  (setq sel (entsel "\nSelecione o objeto: "))
  (if sel
    (progn
      (setq en (car sel))
      (cond
        ((not (OBJ:TipoDe en))
          (alert "Esta entidade nao e um objeto hidraulico."))
        ((and tipo (not (equal (OBJ:TipoDe en) tipo)))
          (alert
            (strcat "Esta entidade e do tipo " (OBJ:_NomeTipo (OBJ:TipoDe en))
                    ", nao " (OBJ:_NomeTipo tipo) ".")))
        (T (alert (OBJ:ToString en)))
      )
    )
  )
  (princ)
)

(defun OPV:Zoom (tipo / txt achados en idx)
  (cond
    ((null (OPD:Objetos tipo))
      (princ "\nNenhum objeto cadastrado.")
    )
    (T
      (setq txt (getstring T "\nNome (ou parte) ou handle (Enter = escolher da lista): "))
      (setq achados (OPD:Procurar tipo txt))
      (cond
        ((null achados) (princ "\nNenhum objeto encontrado."))
        ((= (length achados) 1) (setq en (car achados)))
        (T
          (setq idx
            (HYDRO:Escolher "Objetos encontrados:" (mapcar 'OPD:Linha achados) 0))
          (setq en (nth idx achados))
        )
      )
      (if en (OPV:Ir en))
    )
  )
  (princ)
)

;;; ------------------------------------------------------------
;;; COMANDOS GERAIS
;;; ------------------------------------------------------------
(defun c:OBJETOS (/ tipos itens idx)
  (setq tipos (OBJ:Tipos))
  (setq itens
    (cons "Todos os tipos"
      (mapcar
        (function
          (lambda (x)
            (strcat (cdr (assoc "NOME" (cdr x))) " ("
                    (itoa (length (OBJ:ListaTipo (car x)))) ")")))
        tipos)))
  (setq idx (HYDRO:Escolher "Listar objetos de:" itens 0))
  (OPV:Listar (if (= idx 0) nil (car (nth (1- idx) tipos))))
  (princ)
)

(defun c:OBJETOZOOM ()
  (OPV:Zoom nil)
)

;; Realce dos vinculos de PARAMS. Sem selecao: todas as entidades que algum objeto
;; cita em PARAMS (ex.: o talvegue de cada bacia). Com um objeto: ele, o que ele cita
;; e quem cita ele.
(defun c:OBJETOVINCULOS (/ sel en vs v alvos quebrados nome)
  (setq sel (entsel "\nSelecione um objeto (Enter = vinculos de todos): "))
  (setq en (if sel (car sel) nil))
  (cond
    ((and en (not (OBJ:TipoDe en)))
      (princ "\nEsta entidade nao e um objeto hidraulico.")
    )
    (T
      (setq vs (OPD:Vinculos en))
      (if en
        (progn
          (setq alvos (list en))
          (foreach v (OPD:Referenciando en)
            (princ (strcat "\n  " (OBJ:Nome v) " -> aponta para " (OBJ:Nome en)))
            (if (not (member v alvos)) (setq alvos (append alvos (list v))))
          )
        )
      )
      (foreach v (vl-remove-if-not (function (lambda (x) (nth 3 x))) vs)
        (setq nome
          (if (OBJ:TipoDe (nth 3 v))
            (OBJ:Nome (nth 3 v))
            (strcat (HYDRO:DxfDe (nth 3 v)) " " (nth 2 v))))
        (princ (strcat "\n  " (OBJ:Nome (nth 0 v)) " -> " (nth 1 v) ": " nome))
        (if (not (member (nth 3 v) alvos))
          (setq alvos (append alvos (list (nth 3 v))))
        )
      )
      (foreach v (vl-remove-if (function (lambda (x) (nth 3 x))) vs)
        (setq quebrados (1+ (if quebrados quebrados 0)))
        (princ
          (strcat "\n  QUEBRADO: " (OBJ:Nome (nth 0 v)) " -> " (nth 1 v) ": "
                  (nth 2 v) " (nao existe)"))
      )
      (cond
        (alvos
          (OPV:Selecionar alvos)
          (princ (strcat "\n" (itoa (length alvos)) " entidade(s) realcada(s)/selecionada(s)."))
        )
        (T (princ "\nNenhum vinculo encontrado."))
      )
      (if quebrados
        (princ
          (strcat "\n" (itoa quebrados)
                  " vinculo(s) quebrado(s): rode HYDROAUDIT para corrigir."))
      )
    )
  )
  (princ)
)

(HYDRO:Provide "objetos-padrao-view" "1.0")
(princ)
