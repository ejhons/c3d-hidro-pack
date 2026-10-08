;;; ============================================================
;;; views/idf_view.lsp - VIEW DA PRECIPITACAO (PREC:)
;;;
;;; Dialogo da equacao IDF e comandos IDF, ATUALIZAIDF e ATUALIZATR.
;;; O calculo (PREC:Params, PREC:Intensidade) fica em plugins/idf.lsp.
;;; Depende de "idf".
;;; ============================================================
(vl-load-com)

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

;; Atualiza substituicao, resultado e o estado do campo "duracao".
;; igual = T  ->  duracao = tc (campo de duracao desabilitado e espelhando o tc)
(defun PREC:_Refresca (par tr tc dur igual / d k a b c s p i)
  (setq d (if igual tc dur))
  (setq k (cdr (assoc "K" par)))
  (setq a (cdr (assoc "A" par)))
  (setq b (cdr (assoc "B" par)))
  (setq c (cdr (assoc "C" par)))
  (setq s (cdr (assoc "S" par)))
  (setq p (cdr (assoc "P" par)))
  (setq i (if (and d tr) (PREC:Intensidade d tr) nil))
  (mode_tile "dur_val" (if igual 1 0))
  (if igual
    (set_tile "dur_val" (HYDRO:FmtReal tc))
  )
  (set_tile "substituicao_1"
    (strcat "i = " (rtos k 2 3)
            " * (" (if tr (HYDRO:FmtReal tr) "tr")
            (if (< s 0.0) " - " " + ") (rtos (abs s) 2 3)
            ")^" (rtos a 2 3)))
  (set_tile "substituicao_2"
    (strcat "   (" (if d (HYDRO:FmtReal d) "dur")
            (if (< b 0.0) " - " " + ") (rtos (abs b) 2 3)
            ")^" (rtos c 2 3)))
  (set_tile "resultado"
    (strcat "i = " (if i (rtos i 2 3) "?") " mm/h"))
  i
)

;; Dialogo de calculo da intensidade. O usuario informa tr, tc e duracao.
;;   par   = parametros da IDF (PREC:Params)
;;   tr tc dur = valores iniciais (podem ser nil); igual = T usa duracao = tc
;; Retorna alist (("TR" . x) ("TC" . x) ("DUR" . x) ("I" . x)) ou nil se nao abriu.
(defun PREC:Dialog (par tr tc dur igual / dcl_file dcl_id)
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

      (set_tile "k_val" (rtos (cdr (assoc "K" par)) 2 3))
      (set_tile "a_val" (rtos (cdr (assoc "A" par)) 2 3))
      (set_tile "b_val" (rtos (cdr (assoc "B" par)) 2 3))
      (set_tile "c_val" (rtos (cdr (assoc "C" par)) 2 3))
      (set_tile "s_val" (rtos (cdr (assoc "S" par)) 2 3))
      (set_tile "p_val" (rtos (cdr (assoc "P" par)) 2 3))

      (set_tile "tr_val" (HYDRO:FmtReal tr))
      (set_tile "tc_val" (HYDRO:FmtReal tc))
      (set_tile "dur_val" (HYDRO:FmtReal (if igual tc dur)))
      (set_tile "dur_igual" (if igual "1" "0"))
      (PREC:_Refresca par tr tc dur igual)

      ;; os callbacks alteram as variaveis locais desta funcao
      (action_tile "tr_val"
        "(setq tr (HYDRO:ParseReal $value)) (PREC:_Refresca par tr tc dur igual)")
      (action_tile "tc_val"
        "(setq tc (HYDRO:ParseReal $value)) (PREC:_Refresca par tr tc dur igual)")
      (action_tile "dur_val"
        "(setq dur (HYDRO:ParseReal $value)) (PREC:_Refresca par tr tc dur igual)")
      (action_tile "dur_igual"
        "(setq igual (= $value \"1\")) (PREC:_Refresca par tr tc dur igual)")
      ;; "Calcular" (botao padrao) apenas recalcula; o dialogo fecha em "Fechar"
      (action_tile "accept" "(PREC:_Refresca par tr tc dur igual)")
      (action_tile "cancel" "(done_dialog 0)")

      (start_dialog)
      (unload_dialog dcl_id)
      (list
        (cons "TR" tr)
        (cons "TC" tc)
        (cons "DUR" (if igual tc dur))
        (cons "I" (if (and (if igual tc dur) tr)
                    (PREC:Intensidade (if igual tc dur) tr)
                    nil))
      )
    )
  )
)

;;; ------------------------------------------------------------
;;; COMANDOS
;;; ------------------------------------------------------------
(defun c:IDF (/ par tr tc res)
  (setq par (PREC:Params))
  (cond
    ((not par)
      (alert "IDF\nParametros IDF nao definidos. Use ATUALIZAIDF.")
    )
    (T
      (setq tr (PREC:Tr))
      (setq tc (HYDRO:Get "HYDRO.TC.MINIMO" 10.0))
      (setq res (PREC:Dialog par tr tc nil T))
      (if (and res (cdr (assoc "I" res)))
        (princ
          (strcat "\n[IDF] tr = " (HYDRO:FmtReal (cdr (assoc "TR" res)))
                  " anos, duracao = " (HYDRO:FmtReal (cdr (assoc "DUR" res)))
                  " min  ->  i = " (rtos (cdr (assoc "I" res)) 2 3) " mm/h")
        )
      )
    )
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

(HYDRO:Provide "idf-view" "1.0")
(princ)
