(defun c:IDF (/ resultado);k a b c s tc tr resultado)
  ;; ============================================================
  ;; EXEMPLO
  ;;
  ;; Substitua este bloco pela sua função atual que obtém
  ;; os parâmetros fornecidos pelo usuário.
  ;; ============================================================
  ; (setq k 781.0)
  ; (setq a 0.173)
  ; (setq b 10.0)
  ; (setq c 0.745)
  ; (setq s -2.07)

  ; (setq tc 10.0)
  ; (setq tr 5.0)
  (if (not (and k a b c s p __tc-minimo tr))
    (progn
      (alert "IDF Viewer\nNem todos os parâmetros estão definidos.")
      )
    (princ)
	)
  ;; ============================================================
  ;; Abre o diálogo
  ;; ============================================================
  (setq resultado (IDF-DIALOG k a b c s p __tc-minimo tr))

  (princ)
)

(defun IDF-DIALOG
  (
    k
    a
    b
    c
    s
	  p
    tc
    tr
    /
    dcl_file
    dcl_id
    result
    intensidade
  )

  ;; -----------------------------------------------
  ;; Calcula a intensidade
  ;; -----------------------------------------------
  (if calcula-intensidade-tr
	(setq intensidade (calcula-intensidade-tr tc tr))
	(setq intensidade 1.0)
	)

  ;; -----------------------------------------------
  ;; Localiza o DCL
  ;; -----------------------------------------------
  (setq dcl_file
    (findfile "./Sarjetas/idf.dcl")
  )

  (if (not dcl_file)
    (progn
      (alert "Arquivo equacao.dcl não encontrado.")
      (exit)
    )

  )

  ;; -----------------------------------------------
  ;; Carrega o DCL
  ;; -----------------------------------------------

  (setq dcl_id
    (load_dialog dcl_file)
  )

  (if (< dcl_id 0)

    (progn
      (alert "Não foi possível carregar o arquivo DCL.")
      (exit)
    )

  )

  ;; -----------------------------------------------
  ;; Cria o diálogo
  ;; -----------------------------------------------

  (if
    (not
      (new_dialog
        "idf_dialog"
        dcl_id
      )
    )

    (progn
      (alert "Não foi possível abrir o diálogo.")
      (unload_dialog dcl_id)
      (exit)
    )

  )

  ;; -----------------------------------------------
  ;; Desenha a fórmula
  ;; -----------------------------------------------

  (IDF-DesenhaFormula "idf_formula.sld")

  ;; -----------------------------------------------
  ;; Parâmetros
  ;; -----------------------------------------------

  (set_tile "k_val" (rtos k 2 3))
  (set_tile "a_val" (rtos a 2 3))
  (set_tile "b_val" (rtos b 2 3))
  (set_tile "c_val" (rtos c 2 3))
  (set_tile "s_val" (rtos s 2 3))
  (set_tile "p_val" (rtos p 2 3))

  ;; -----------------------------------------------
  ;; Variáveis
  ;; -----------------------------------------------

  (set_tile "tc_val" (rtos tc 2 3))
  (set_tile "tr_val" (rtos (fix tr) 2 3));(rtos tr 2 3))

  ;; -----------------------------------------------
  ;; Equação substituída
  ;; -----------------------------------------------

  (set_tile
    "substituicao_1"
    (strcat
      "i = "
      (rtos k 2 3)
      " * ("
      (rtos (fix tr) 2 3);(rtos tr 2 3)
      (if (< s 0.0) " - " " + ")
      (rtos (abs s) 2 3)
      ")^"
      (rtos a 2 3)
    )
  )

  (set_tile
    "substituicao_2"
    (strcat
      "   ("
      (rtos tc 2 3)
      (if (< b 0.0) " - " " + ")
      (rtos (abs b) 2 3)
      ")^"
      (rtos c 2 3)
    )
  )

  ;; -----------------------------------------------
  ;; Resultado
  ;; -----------------------------------------------

  (set_tile
    "resultado"
    (strcat
      "i = "
      (rtos intensidade 2 3)
	  " mm/h"
    )
  )

  ;; -----------------------------------------------
  ;; Botões
  ;; -----------------------------------------------

  (action_tile
    "accept"
    "(done_dialog 1)"
  )

  (action_tile
    "cancel"
    "(done_dialog 0)"
  )

  ;; -----------------------------------------------
  ;; Exibe diálogo
  ;; -----------------------------------------------

  (setq result
    (start_dialog)
  )

  (unload_dialog dcl_id)

  result
)

(defun IDF-DesenhaFormula (slide_file /)

  ;; Procura o arquivo SLD
  (setq slide_file
    (findfile "./Sarjetas/idf_formula.sld")
  )

  (if slide_file
    (progn

      ;; Desenha o slide dentro do image_button
      (start_image "formula")

      (slide_image
        0
        0
        (dimx_tile "formula")
        (dimy_tile "formula")
        slide_file
      )

      (end_image)

    )

    (progn

      ;; Caso não encontre o arquivo
      (start_image "formula")

      (fill_image
        0
        0
        (dimx_tile "formula")
        (dimy_tile "formula")
        -2
      )

      (end_image)

    )

  )

)