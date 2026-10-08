;;; ============================================================
;;; viewer.lsp - VISUALIZADOR DE DADOS PERSISTIDOS (VIEW:)
;;;
;;; Comandos:
;;;   HYDRODADOS  abre o dialogo (viewer.dcl) com duas visoes:
;;;                 - Configuracoes: tudo o que esta gravado no DB do desenho
;;;                 - Entidades com dados: entidades com XData "DREN-*"
;;;               Filtro por texto, detalhes, "Ir para" (zoom + selecao)
;;;               e exportacao CSV (separador ";" e decimal ",").
;;;   HYDRODUMP   mesma informacao em texto, na linha de comando.
;;;
;;; INDEPENDENCIA
;;;   - Nao chama nenhum outro plugin. Le o DB via HYDRO:ListAll (core) e
;;;     le o XData direto das entidades.
;;;   - Descobre as aplicacoes de XData por CONVENCAO: nome comeca com "DREN-".
;;;     Plugin novo que usar "DREN-ALGO" aparece aqui sem alterar este arquivo.
;;;   - Rotulos e unidades vem de HYDRO:GetLabel (cada plugin registra os seus).
;;;     Sem rotulo, mostra o dado cru (path / codigo XData).
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; UTILITARIOS
;;; ------------------------------------------------------------
(defun VIEW:_Try (fn / r)
  (setq r (vl-catch-all-apply fn nil))
  (if (vl-catch-all-error-p r) nil r)
)

(defun VIEW:_Replace (s de para / pos out)
  (setq out "")
  (while (setq pos (vl-string-search de s))
    (setq out (strcat out (substr s 1 pos) para))
    (setq s (substr s (+ pos 1 (strlen de))))
  )
  (strcat out s)
)

(defun VIEW:_Trunc (s n)
  (if (> (strlen s) n)
    (strcat (substr s 1 (- n 2)) "..")
    s
  )
)

;; real sem zeros a direita: 781.000000 -> 781
(defun VIEW:_Real (x / s)
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

(defun VIEW:_FmtVal (v)
  (cond
    ((null v) "(vazio)")
    ((= (type v) 'REAL) (VIEW:_Real v))
    ((= (type v) 'INT) (itoa v))
    ((= (type v) 'STR) v)
    (T (vl-prin1-to-string v))
  )
)

(defun VIEW:_HandleLt (h1 h2)
  (if (= (strlen h1) (strlen h2))
    (< h1 h2)
    (< (strlen h1) (strlen h2))
  )
)

;;; ------------------------------------------------------------
;;; GEOMETRIA (tudo protegido: entidade pode nao ser curva)
;;; ------------------------------------------------------------
(defun VIEW:_Tipo (en / d)
  (setq d (vl-catch-all-apply 'entget (list en)))
  (if (or (vl-catch-all-error-p d) (null d))
    nil
    (cdr (assoc 0 d))
  )
)

(defun VIEW:_Comprimento (en)
  (VIEW:_Try
    (function
      (lambda ()
        (vlax-curve-getDistAtParam en (vlax-curve-getEndParam en))
      )
    )
  )
)

;; area so para curvas fechadas
(defun VIEW:_Area (en)
  (VIEW:_Try
    (function
      (lambda ()
        (if (vlax-curve-isClosed en)
          (vla-get-area (vlax-ename->vla-object en))
          nil
        )
      )
    )
  )
)

(defun VIEW:_ResumoGeom (en / c a)
  (setq c (VIEW:_Comprimento en))
  (setq a (VIEW:_Area en))
  (strcat
    (if c (strcat ", L=" (rtos c 2 2) " m") "")
    (if a (strcat ", A=" (rtos a 2 0) " m2") "")
  )
)

(defun VIEW:_Zoom (en / obj mn mx dx dy m)
  (setq obj (vlax-ename->vla-object en))
  (VIEW:_Try
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
  )
)

;;; ------------------------------------------------------------
;;; REGISTROS DE CONFIGURACAO (DB)
;;; ------------------------------------------------------------
(defun VIEW:_RegConfig (chave rot uni v / txt det)
  (setq txt (VIEW:_FmtVal v))
  (setq det
    (append
      (list (strcat "Chave: " chave))
      (if (/= rot "") (list (strcat "Descricao: " rot)))
      (if (/= uni "") (list (strcat "Unidade: " uni)))
      (if (and v (listp v))
        (cons
          "Valor (lista):"
          (mapcar
            (function (lambda (x) (strcat "  " (vl-prin1-to-string x))))
            v
          )
        )
        (list (strcat "Valor: " txt))
      )
    )
  )
  (list
    (cons "LINHA"
      (strcat
        (VIEW:_Trunc chave 29) "\t"
        (VIEW:_Trunc rot 31) "\t"
        (VIEW:_Trunc (strcat txt (if (/= uni "") (strcat " " uni) "")) 40)
      )
    )
    (cons "DETALHE" det)
    (cons "EN" nil)
    (cons "CSV"
      (list
        (cons "Chave" chave)
        (cons "Descricao" rot)
        (cons "Valor" txt)
        (cons "Unidade" uni)
      )
    )
  )
)

(defun VIEW:Configs (/ par lab out)
  (foreach par (HYDRO:ListAll)
    (setq lab (HYDRO:GetLabel (car par)))
    (setq out
      (cons
        (VIEW:_RegConfig
          (car par)
          (if lab (car lab) "")
          (if lab (cdr lab) "")
          (cdr par)
        )
        out
      )
    )
  )
  (reverse out)
)

;;; ------------------------------------------------------------
;;; REGISTROS DE ENTIDADES (XData)
;;; ------------------------------------------------------------
(defun VIEW:_RotuloPadrao (code)
  (cond
    ((= code 1000) "Texto")
    ((= code 1005) "Handle relacionado")
    ((= code 1040) "Valor real")
    ((= code 1070) "Inteiro")
    ((= code 1071) "Inteiro longo")
    (T (strcat "Codigo " (itoa code)))
  )
)

(defun VIEW:_DescreveHandle (h / en tipo)
  (setq en (handent h))
  (setq tipo (if en (VIEW:_Tipo en) nil))
  (if tipo
    (strcat h " (" tipo (VIEW:_ResumoGeom en) ")")
    (strcat h " (nao encontrada)")
  )
)

;; retorna (rotulo unidade texto)
(defun VIEW:_DescreverPar (app par / code val lab)
  (setq code (car par))
  (setq val (cdr par))
  (setq lab (HYDRO:GetLabel (strcat "xdata:" app ":" (itoa code))))
  (list
    (if lab (car lab) (VIEW:_RotuloPadrao code))
    (if (and lab (cdr lab)) (cdr lab) "")
    (if (and (= code 1005) (= (type val) 'STR))
      (VIEW:_DescreveHandle val)
      (VIEW:_FmtVal val)
    )
  )
)

(defun VIEW:_DadoTxt (d)
  (strcat (car d) ": " (caddr d) (if (/= (cadr d) "") (strcat " " (cadr d)) ""))
)

(defun VIEW:_RegEntidade (en app / ent h tipo camada pares dados comp area resumo)
  (setq ent (entget en (list app)))
  (setq h (cdr (assoc 5 ent)))
  (setq tipo (cdr (assoc 0 ent)))
  (setq camada (cdr (assoc 8 ent)))
  (setq pares (cdr (assoc app (cdr (assoc -3 ent)))))
  (setq dados
    (mapcar (function (lambda (p) (VIEW:_DescreverPar app p))) pares)
  )
  (setq comp (VIEW:_Comprimento en))
  (setq area (VIEW:_Area en))
  (setq resumo (HYDRO:Join (mapcar 'VIEW:_DadoTxt dados) " | "))
  (list
    (cons "HANDLE" h)
    (cons "EN" en)
    (cons "LINHA"
      (strcat
        (VIEW:_Trunc (strcat h " " tipo) 29) "\t"
        (VIEW:_Trunc camada 31) "\t"
        (VIEW:_Trunc resumo 60)
      )
    )
    (cons "DETALHE"
      (append
        (list
          (strcat "Handle: " h)
          (strcat "Tipo: " tipo)
          (strcat "Camada: " camada)
          (strcat "Aplicacao: " app)
        )
        (if comp (list (strcat "Comprimento: " (rtos comp 2 2) " m")))
        (if area (list (strcat "Area: " (rtos area 2 2) " m2")))
        (list "--- Dados ---")
        (mapcar
          (function (lambda (d) (strcat "  " (VIEW:_DadoTxt d))))
          dados
        )
      )
    )
    (cons "CSV"
      (append
        (list
          (cons "Handle" h)
          (cons "Tipo" tipo)
          (cons "Camada" camada)
          (cons "Aplicacao" app)
        )
        (if comp (list (cons "Comprimento (m)" (rtos comp 2 3))))
        (if area (list (cons "Area (m2)" (rtos area 2 2))))
        (mapcar
          (function
            (lambda (d)
              (cons
                (if (/= (cadr d) "") (strcat (car d) " (" (cadr d) ")") (car d))
                (caddr d)
              )
            )
          )
          dados
        )
      )
    )
  )
)

;; Aplicacoes de XData por convencao: nome comeca com "DREN-"
(defun VIEW:_Apps (/ a out)
  (setq a (tblnext "APPID" T))
  (while a
    (if (wcmatch (strcase (cdr (assoc 2 a))) "DREN-*")
      (setq out (cons (cdr (assoc 2 a)) out))
    )
    (setq a (tblnext "APPID"))
  )
  (reverse out)
)

(defun VIEW:Entidades (/ regs app ss i en)
  (foreach app (VIEW:_Apps)
    (if (setq ss (ssget "_X" (list (list -3 (list app)))))
      (progn
        (setq i (sslength ss))
        (while (> i 0)
          (setq i (1- i))
          (setq en (ssname ss i))
          (setq regs (cons (VIEW:_RegEntidade en app) regs))
        )
      )
    )
  )
  (vl-sort
    regs
    (function
      (lambda (a b)
        (VIEW:_HandleLt (cdr (assoc "HANDLE" a)) (cdr (assoc "HANDLE" b)))
      )
    )
  )
)

;;; ------------------------------------------------------------
;;; FILTRO E CSV
;;; ------------------------------------------------------------
(defun VIEW:_Filtra (regs filtro / out r)
  (if (= filtro "")
    regs
    (progn
      (foreach r regs
        (if (vl-string-search (strcase filtro) (strcase (cdr (assoc "LINHA" r))))
          (setq out (cons r out))
        )
      )
      (reverse out)
    )
  )
)

;; numero -> virgula decimal (Excel pt-BR); texto com ; ou " -> entre aspas
(defun VIEW:_CsvCelula (s)
  (cond
    ((null s) "")
    ((and (distof s 2) (vl-string-search "." s))
      (VIEW:_Replace s "." ",")
    )
    ((or (vl-string-search ";" s) (vl-string-search "\"" s))
      (strcat "\"" (VIEW:_Replace s "\"" "\"\"") "\"")
    )
    (T s)
  )
)

(defun VIEW:_CsvLinha (celulas)
  (HYDRO:Join (mapcar 'VIEW:_CsvCelula celulas) ";")
)

(defun VIEW:_ExportaCsv (regs modo / arq f cols r c)
  (setq arq
    (getfiled
      "Salvar CSV"
      (strcat (getvar "DWGPREFIX") "hydro_" (if (= modo "cfg") "config" "entidades") ".csv")
      "csv"
      1
    )
  )
  (if (and arq regs)
    (progn
      ;; colunas = uniao das colunas dos registros, na ordem em que aparecem
      (foreach r regs
        (foreach c (cdr (assoc "CSV" r))
          (if (not (member (car c) cols))
            (setq cols (append cols (list (car c))))
          )
        )
      )
      (setq f (open arq "w"))
      (if f
        (progn
          (write-line (VIEW:_CsvLinha cols) f)
          (foreach r regs
            (write-line
              (VIEW:_CsvLinha
                (mapcar
                  (function
                    (lambda (col) (cdr (assoc col (cdr (assoc "CSV" r)))))
                  )
                  cols
                )
              )
              f
            )
          )
          (close f)
          (alert (strcat "Arquivo salvo:\n" arq))
        )
        (alert "Nao foi possivel gravar o arquivo.")
      )
    )
  )
)

;;; ------------------------------------------------------------
;;; DIALOGO
;;; ------------------------------------------------------------
(defun VIEW:_Detalhe (regs sel / r)
  (setq r (if regs (nth sel regs)))
  (start_list "detalhe")
  (mapcar
    'add_list
    (if r (cdr (assoc "DETALHE" r)) (list "(nada selecionado)"))
  )
  (end_list)
)

(defun VIEW:_Preenche (modo filtro regs)
  (set_tile "modo_cfg" (if (= modo "cfg") "1" "0"))
  (set_tile "modo_ent" (if (= modo "ent") "1" "0"))
  (set_tile "filtro" filtro)
  (set_tile "titulo" (strcat (itoa (length regs)) " registro(s)"))
  (start_list "lista")
  (mapcar
    'add_list
    (mapcar (function (lambda (r) (cdr (assoc "LINHA" r)))) regs)
  )
  (end_list)
  (if regs
    (progn (set_tile "lista" "0") (VIEW:_Detalhe regs 0))
    (VIEW:_Detalhe nil 0)
  )
  (mode_tile "ir" (if (and (= modo "ent") regs) 0 1))
  (mode_tile "csv" (if regs 0 1))
)

(defun VIEW:_Ir (r / en)
  (if (and r (setq en (cdr (assoc "EN" r))))
    (progn
      (VIEW:_Zoom en)
      (sssetfirst nil (ssadd en (ssadd)))
    )
  )
)

(defun VIEW:Abrir (/ dcl dcl_id modo filtro regs sel cod continua)
  (setq dcl (HYDRO:FindFile "viewer.dcl"))
  (cond
    ((not dcl)
      (alert "Arquivo viewer.dcl nao encontrado. Use HYDRODUMP para ver em texto.")
      nil
    )
    ((< (setq dcl_id (load_dialog dcl)) 0)
      (alert "Nao foi possivel carregar viewer.dcl.")
      nil
    )
    (T
      (setq modo "cfg")
      (setq filtro "")
      (setq continua T)
      (while continua
        (setq regs
          (VIEW:_Filtra
            (if (= modo "cfg") (VIEW:Configs) (VIEW:Entidades))
            filtro
          )
        )
        (setq sel 0)
        (if (not (new_dialog "view_dialog" dcl_id))
          (setq continua nil)
          (progn
            (VIEW:_Preenche modo filtro regs)
            (action_tile "modo_cfg" "(done_dialog 10)")
            (action_tile "modo_ent" "(done_dialog 11)")
            (action_tile "filtrar"
              "(setq filtro (get_tile \"filtro\")) (done_dialog 12)")
            (action_tile "lista"
              "(setq sel (atoi $value)) (VIEW:_Detalhe regs sel)")
            (action_tile "ir"
              "(setq sel (atoi (get_tile \"lista\"))) (done_dialog 3)")
            (action_tile "csv" "(done_dialog 4)")
            (action_tile "fechar" "(done_dialog 1)")
            (setq cod (start_dialog))
            (cond
              ((= cod 10) (setq modo "cfg"))
              ((= cod 11) (setq modo "ent"))
              ((= cod 12) nil)
              ((= cod 3)
                (VIEW:_Ir (nth sel regs))
                (setq continua nil)
              )
              ((= cod 4) (VIEW:_ExportaCsv regs modo))
              (T (setq continua nil))
            )
          )
        )
      )
      (unload_dialog dcl_id)
      T
    )
  )
)

;;; ------------------------------------------------------------
;;; COMANDOS
;;; ------------------------------------------------------------
(defun c:HYDRODADOS ()
  (VIEW:Abrir)
  (princ)
)

(defun c:HYDRODUMP (/ r)
  (princ "\n=== CONFIGURACOES ===")
  (foreach r (VIEW:Configs)
    (princ (strcat "\n" (VIEW:_Replace (cdr (assoc "LINHA" r)) "\t" "  |  ")))
  )
  (princ "\n\n=== ENTIDADES COM DADOS ===")
  (foreach r (VIEW:Entidades)
    (princ (strcat "\n" (VIEW:_Replace (cdr (assoc "LINHA" r)) "\t" "  |  ")))
  )
  (princ)
)

(HYDRO:Provide "visualizador" "1.0")
(princ)
