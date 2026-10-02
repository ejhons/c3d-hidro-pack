;;; ============================================================
;;; idf.lsp - PLUGIN DE PRECIPITACAO (PREC:)
;;;
;;; Equacao IDF:   i = K * (TR + s)^a / (tc + b)^c + p      [mm/h]
;;;
;;; API:
;;;   (PREC:Params)               -> alist (("K" . x) ("A" . x) ...) ou nil se incompleto
;;;   (PREC:Intensidade tc tr)    -> mm/h ou nil
;;;   (PREC:AskParams)            pergunta e grava K a b c s p
;;;   (PREC:Tr) / (PREC:AskTr)    tempo de retorno atual
;;;   (PREC:Dialog par tc tr)     abre o dialogo DCL
;;;
;;; Comandos: IDF, ATUALIZAIDF, ATUALIZATR
;;;
;;; Chaves usadas em HYDRO:Get/Set (mesmas de antes, desenhos antigos
;;; continuam funcionando):
;;;   HYDRO.IDF.K  .A  .B  .C  .S  .P   e   HYDRO.TR   HYDRO.TC.MINIMO
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; PARAMETROS
;;; ------------------------------------------------------------
(defun PREC:Params (/ par)
  (setq par
    (list
      (cons "K" (HYDRO:Get "HYDRO.IDF.K" nil))
      (cons "A" (HYDRO:Get "HYDRO.IDF.A" nil))
      (cons "B" (HYDRO:Get "HYDRO.IDF.B" nil))
      (cons "C" (HYDRO:Get "HYDRO.IDF.C" nil))
      (cons "S" (HYDRO:Get "HYDRO.IDF.S" nil))
      (cons "P" (HYDRO:Get "HYDRO.IDF.P" nil))
    )
  )
  (if (member nil (mapcar 'cdr par)) nil par)
)

(defun PREC:AskParams (/ n)
  (foreach n '("K" "A" "B" "C" "S" "P")
    (HYDRO:Set
      (strcat "HYDRO.IDF." n)
      (HYDRO:AskReal
        (strcat "IDF - Digite o valor de " (strcase n T))
        (HYDRO:Get (strcat "HYDRO.IDF." n) nil)
      )
    )
  )
  (princ)
)

(defun PREC:Tr ()
  (HYDRO:Get "HYDRO.TR" nil)
)

(defun PREC:AskTr (/ tr)
  (setq tr (HYDRO:AskReal "Digite o tempo de retorno (anos)" (PREC:Tr)))
  (if tr (HYDRO:Set "HYDRO.TR" tr))
  tr
)

;;; ------------------------------------------------------------
;;; CALCULO
;;; ------------------------------------------------------------
(defun PREC:Intensidade (tc tr / par k a b c s p)
  (setq par (PREC:Params))
  (if (and par tc tr)
    (progn
      (setq k (cdr (assoc "K" par)))
      (setq a (cdr (assoc "A" par)))
      (setq b (cdr (assoc "B" par)))
      (setq c (cdr (assoc "C" par)))
      (setq s (cdr (assoc "S" par)))
      (setq p (cdr (assoc "P" par)))
      (+ (/ (* k (expt (abs (+ tr s)) a))
            (expt (abs (+ tc b)) c))
         p)
    )
    nil
  )
)

;;; ------------------------------------------------------------
;;; DIALOGO
;;; ------------------------------------------------------------
(defun PREC:_DesenhaFormula (/ slide_file)
  (setq slide_file (HYDRO:FindFile "idf_formula.sld"))
  (start_image "formula")
  (if slide_file
    (slide_image 0 0 (dimx_tile "formula") (dimy_tile "formula") slide_file)
    (fill_image 0 0 (dimx_tile "formula") (dimy_tile "formula") -2)
  )
  (end_image)
)

(defun PREC:Dialog (par tc tr / dcl_file dcl_id result intensidade k a b c s p)
  (setq k (cdr (assoc "K" par)))
  (setq a (cdr (assoc "A" par)))
  (setq b (cdr (assoc "B" par)))
  (setq c (cdr (assoc "C" par)))
  (setq s (cdr (assoc "S" par)))
  (setq p (cdr (assoc "P" par)))

  (setq intensidade (PREC:Intensidade tc tr))
  (setq dcl_file (HYDRO:FindFile "idf.dcl"))

  (cond
    ((not dcl_file)
      (alert "Arquivo idf.dcl nao encontrado.")
      nil
    )
    ((< (setq dcl_id (load_dialog dcl_file)) 0)
      (alert "Nao foi possivel carregar o arquivo DCL.")
      nil
    )
    ((not (new_dialog "idf_dialog" dcl_id))
      (alert "Nao foi possivel abrir o dialogo.")
      (unload_dialog dcl_id)
      nil
    )
    (T
      (PREC:_DesenhaFormula)

      (set_tile "k_val" (rtos k 2 3))
      (set_tile "a_val" (rtos a 2 3))
      (set_tile "b_val" (rtos b 2 3))
      (set_tile "c_val" (rtos c 2 3))
      (set_tile "s_val" (rtos s 2 3))
      (set_tile "p_val" (rtos p 2 3))
      (set_tile "tc_val" (rtos tc 2 3))
      (set_tile "tr_val" (HYDRO:FmtNum tr))

      (set_tile "substituicao_1"
        (strcat "i = " (rtos k 2 3)
                " * (" (HYDRO:FmtNum tr)
                (if (< s 0.0) " - " " + ") (rtos (abs s) 2 3)
                ")^" (rtos a 2 3)))
      (set_tile "substituicao_2"
        (strcat "   (" (rtos tc 2 3)
                (if (< b 0.0) " - " " + ") (rtos (abs b) 2 3)
                ")^" (rtos c 2 3)))
      (set_tile "resultado"
        (strcat "i = " (if intensidade (rtos intensidade 2 3) "?") " mm/h"))

      (action_tile "accept" "(done_dialog 1)")
      (action_tile "cancel" "(done_dialog 0)")

      (setq result (start_dialog))
      (unload_dialog dcl_id)
      result
    )
  )
)

;;; ------------------------------------------------------------
;;; COMANDOS
;;; ------------------------------------------------------------
(defun c:IDF (/ par tc tr)
  (setq par (PREC:Params))
  (setq tc (HYDRO:Get "HYDRO.TC.MINIMO" 10.0))
  (setq tr (PREC:Tr))
  (cond
    ((not par)
      (alert "IDF Viewer\nParametros IDF nao definidos. Use ATUALIZAIDF.")
    )
    ((not tr)
      (alert "IDF Viewer\nTempo de retorno nao definido. Use ATUALIZATR.")
    )
    (T (PREC:Dialog par tc tr))
  )
  (princ)
)

(defun c:ATUALIZAIDF ()
  (PREC:AskParams)
  (princ)
)

(defun c:ATUALIZATR ()
  (PREC:AskTr)
  (princ)
)

(HYDRO:Provide "precipitacao" "1.0")
(princ)
