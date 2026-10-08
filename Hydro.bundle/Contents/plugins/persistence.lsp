;;; ============================================================
;;; persistence.lsp - PERSISTENCIA DE DADOS NO DESENHO (DB:)
;;;
;;; Guarda uma arvore de chaves no Named Object Dictionary do DWG.
;;;
;;;   (DB:Set "PROJECT.CITY" "Fortaleza")
;;;   (DB:Get "PROJECT.CITY")
;;;   (DB:GetOrDefault "ROADWAY.SPEED" 60.0)
;;;   (DB:Exists "PROJECT.CITY")
;;;   (DB:Delete "PROJECT.STATE")      ; tambem remove ramos inteiros
;;;   (DB:GetTree) (DB:SetTree tree) (DB:Clear)
;;;
;;; A arvore e uma alist:
;;;   (("PROJECT" ("CITY" . "Fortaleza") ("STATE" . "CE"))
;;;    ("HYDRO"   ("TR" . 5.0)))
;;;
;;; ATENCAO: um valor que seja LISTA e gravado como folha, mas nao
;;; deve ser usado como caminho intermediario (ex.: gravar uma lista em
;;; "A.B" e depois tentar "A.B.C").
;;;
;;; Mudancas desta versao:
;;;   - arvore gravada em blocos de 1000 caracteres (sem estourar o limite
;;;     de um unico grupo 1 do XRECORD)
;;;   - dictremove no lugar de entdel
;;;   - variaveis locais declaradas; typos corrigidos
;;;   - protecao quando um caminho passa por uma folha (nao-lista)
;;; ============================================================
(vl-load-com)

;; Chave raiz no dicionario (funcao, nao variavel global).
;; Mantida igual a versao anterior para ler desenhos ja gravados.
(defun DB:_RootKey () "MYAPP_DATA")

;;; ------------------------------------------------------------
;;; BAIXO NIVEL
;;; ------------------------------------------------------------
(defun DB:_Chunk (str tam / lst)
  (while (> (strlen str) tam)
    (setq lst (cons (substr str 1 tam) lst))
    (setq str (substr str (1+ tam)))
  )
  (reverse (cons str lst))
)

(defun DB:_Save (tree / dict chunks)
  (setq dict (namedobjdict))
  (if (dictsearch dict (DB:_RootKey))
    (dictremove dict (DB:_RootKey))
  )
  (setq chunks
    (mapcar
      (function (lambda (s) (cons 1 s)))
      (DB:_Chunk (vl-prin1-to-string tree) 1000)
    )
  )
  (dictadd
    dict
    (DB:_RootKey)
    (entmakex
      (append
        (list '(0 . "XRECORD") '(100 . "AcDbXrecord"))
        chunks
      )
    )
  )
  tree
)

(defun DB:_Load (/ rec txt g r)
  (if (setq rec (dictsearch (namedobjdict) (DB:_RootKey)))
    (progn
      (setq txt "")
      (foreach g rec
        (if (= (car g) 1)
          (setq txt (strcat txt (cdr g)))
        )
      )
      (if (/= txt "")
        (progn
          (setq r (vl-catch-all-apply 'read (list txt)))
          (if (vl-catch-all-error-p r)
            (progn
              (princ "\n[DB] Dados corrompidos; retornando arvore vazia.")
              nil
            )
            r
          )
        )
        nil
      )
    )
    nil
  )
)

;;; ------------------------------------------------------------
;;; CAMINHOS
;;; ------------------------------------------------------------
(defun DB:_Split (str sep / pos lst)
  (setq lst nil)
  (while (setq pos (vl-string-search sep str))
    (setq lst (append lst (list (substr str 1 pos))))
    (setq str (substr str (+ pos 1 (strlen sep))))
  )
  (append lst (list str))
)

;; (DB:_PathToList "PROJECT.CITY") -> ("PROJECT" "CITY")
(defun DB:_PathToList (path)
  (DB:_Split path ".")
)

;;; ------------------------------------------------------------
;;; OPERACOES NA ARVORE
;;; ------------------------------------------------------------
(defun DB:_GetNode (tree path / par)
  (cond
    ((null path) tree)
    ((not (listp tree)) nil)
    ((setq par (assoc (car path) tree))
      (DB:_GetNode (cdr par) (cdr path))
    )
    (T nil)
  )
)

(defun DB:_SetNode (tree path value / key node)
  (if (not (listp tree)) (setq tree nil))
  (setq key (car path))
  (if (= (length path) 1)
    (if (assoc key tree)
      (subst (cons key value) (assoc key tree) tree)
      (append tree (list (cons key value)))
    )
    (progn
      (setq node (assoc key tree))
      (if node
        (subst
          (cons key (DB:_SetNode (cdr node) (cdr path) value))
          node
          tree
        )
        (append
          tree
          (list (cons key (DB:_SetNode nil (cdr path) value)))
        )
      )
    )
  )
)

(defun DB:_DeleteNode (tree path / key node)
  (if (not (listp tree))
    tree
    (progn
      (setq key (car path))
      (if (= (length path) 1)
        (vl-remove (assoc key tree) tree)
        (progn
          (setq node (assoc key tree))
          (if node
            (subst
              (cons key (DB:_DeleteNode (cdr node) (cdr path)))
              node
              tree
            )
            tree
          )
        )
      )
    )
  )
)

;;; ============================================================
;;; API PUBLICA
;;; ============================================================
(defun DB:GetTree ()
  (DB:_Load)
)

(defun DB:SetTree (tree)
  (DB:_Save tree)
)

(defun DB:Get (path)
  (DB:_GetNode (DB:GetTree) (DB:_PathToList path))
)

(defun DB:GetOrDefault (path default / value)
  (setq value (DB:Get path))
  (if value value default)
)

(defun DB:Set (path value / tree)
  (setq tree (DB:_SetNode (DB:GetTree) (DB:_PathToList path) value))
  (DB:_Save tree)
  value
)

(defun DB:Exists (path)
  (not (null (DB:Get path)))
)

(defun DB:Delete (path / tree)
  (setq tree (DB:_DeleteNode (DB:GetTree) (DB:_PathToList path)))
  (DB:_Save tree)
  T
)

(defun DB:Clear ()
  (DB:_Save nil)
)

;;; ------------------------------------------------------------
;;; COMANDOS DE DEPURACAO
;;; ------------------------------------------------------------
(defun c:SETUSERVALUE (/ path value)
  (setq path (getstring "\nInforme o path (ex.: PROJECT.CITY): "))
  (setq value (getstring T "\nInforme o valor: "))
  (DB:Set path value)
  (princ (strcat "\nValor gravado: " value))
  (princ)
)

(defun c:GETUSERVALUE (/ path)
  (setq path (getstring "\nInforme o path: "))
  (princ (strcat "\nValor: " (vl-prin1-to-string (DB:Get path))))
  (princ)
)

(HYDRO:Provide "persistencia" "2.0")
(princ)
