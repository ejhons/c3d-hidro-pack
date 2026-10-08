;;; ============================================================
;;; views/secao_view.lsp - VIEW DAS SECOES DE SARJETA (SJT:)
;;;
;;; Comando SECAO, dialogo (resources/dcl/secao.dcl), desenho da secao e
;;; insercao no modelo. Dados e hidraulica ficam em plugins/secao.lsp.
;;; Depende de "secao".
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; FONTE DE TRACOS
;;; A fonte agora vive no core (HYDRO:ImgTexto / HYDRO:ImgTextoLargura) e e
;;; compartilhada com outros plugins que desenham em imagens de DCL.
;;; ------------------------------------------------------------
(defun SJT:Texto (str x y cor)
  (HYDRO:ImgTexto str x y cor)
)

(defun SJT:TextoLargura (str)
  (HYDRO:ImgTextoLargura str)
)

;; Indice (posicao na lista) da secao de id dado; padrao se nao achar
(defun SJT:_IndiceSecao (lista id padrao / i achou s)
  (setq i 0)
  (foreach s lista
    (if (and (not achou) id (= (car s) id))
      (setq achou i)
    )
    (setq i (1+ i))
  )
  (if achou achou padrao)
)

(defun SJT:_MaxW (lista)
  (apply 'max (mapcar (function (lambda (x) (SJT:Val "w" x))) lista))
)

;; maior altura a representar: max entre h e o desnivel (w*s/100)
(defun SJT:_MaxY (lista)
  (apply 'max
    (mapcar
      (function
        (lambda (x)
          (max (SJT:Val "h" x) (/ (* (SJT:Val "w" x) (SJT:Val "s" x)) 100.0))
        )
      )
      lista
    )
  )
)

;; "0,045" ou "0.045" -> 0.045 ; vazio/invalido -> nil
(defun SJT:_Real (s)
  (if (and s (/= (vl-string-trim " " s) ""))
    (distof (vl-string-subst "." "," s) 2)
    nil
  )
)

(defun SJT:_Num (x)
  (if x (rtos x 2 4) "")
)

;;; ------------------------------------------------------------
;;; DESENHO NA IMAGEM DO DIALOGO
;;; ------------------------------------------------------------
;; y (pixel) do pavimento na coluna px (reta de (px0,py0) a (pxw,pyr))
(defun SJT:_YPav (px px0 pxw py0 pyr)
  (if (> pxw px0)
    (fix (+ py0 (/ (* (- pyr py0) (- px px0)) (float (- pxw px0)))))
    py0
  )
)

;; sec  = secao a desenhar
;; exag = exagero vertical (1, 2, 5, 10)  -> fixo, nunca "automatico"
;; wref / yref = referencias de escala (m). Sem escala comum: wref = w, yref = 0
;; hid  = resultado de SJT:Hidraulica ou nil
(defun SJT:Desenha
  (key sec exag wref yref hid /
   h s w dx dy mxl mxr myt myb tc rise ymax sxw sxh sx sy off x0 y0
   pxc px0 pxw py0 pyh pyr px pyp pyy tpx xl xr yb txt tw ya)

  (setq h (SJT:Val "h" sec))
  (setq s (SJT:Val "s" sec))
  (setq w (SJT:Val "w" sec))
  (setq wref (max wref w))
  (setq dx (dimx_tile key))
  (setq dy (dimy_tile key))
  (setq mxl 78 mxr 78 myt 26 myb 48)
  (setq tc 0.15)                              ; espessura do meio-fio (m)
  (setq rise (/ (* w s) 100.0))               ; desnivel ao longo de w
  (setq ymax (max h rise yref 0.001))
  (if hid (setq ymax (max ymax (cdr (assoc "Y" hid)))))

  ;; ESCALA: horizontal para caber na largura; vertical = horizontal * exag.
  ;; Se a altura nao couber, REDUZ A ESCALA INTEIRA (o exagero e mantido).
  (setq sxw (/ (- dx mxl mxr) (+ wref tc)))
  (setq sxh (/ (- dy myt myb) (* ymax exag)))
  (setq sx (min sxw sxh))
  (setq sy (* sx exag))
  (setq off (/ (- dx mxl mxr (* (+ wref tc) sx)) 2.0))     ; centraliza
  (setq x0 (+ mxl off (* tc sx)))
  (setq y0 (- dy myb))

  (setq pxc (fix (- x0 (* tc sx))))
  (setq px0 (fix x0))
  (setq pxw (fix (+ x0 (* w sx))))
  (setq py0 (fix y0))
  (setq pyh (fix (- y0 (* h sy))))
  (setq pyr (fix (- y0 (* rise sy))))

  (start_image key)
  (fill_image 0 0 dx dy -2)

  ;; hachura do terreno sob o pavimento
  (setq px px0)
  (while (<= px pxw)
    (setq pyp (SJT:_YPav px px0 pxw py0 pyr))
    (vector_image px pyp (- px 8) (+ pyp 8) 8)
    (setq px (+ px 12))
  )

  ;; meio-fio (preenchimento)
  (fill_image pxc pyh (max 1 (- px0 pxc)) (max 1 (- py0 pyh)) 8)

  ;; lamina d'agua (linhas verticais do pavimento ate o nivel da agua)
  (if hid
    (progn
      (setq tpx (fix (+ x0 (* (min (cdr (assoc "T" hid)) w) sx))))
      (setq pyy (fix (- y0 (* (cdr (assoc "Y" hid)) sy))))
      (setq px px0)
      (while (<= px tpx)
        (setq pyp (SJT:_YPav px px0 pxw py0 pyr))
        (if (< pyy pyp)
          (vector_image px pyp px pyy 5)
        )
        (setq px (1+ px))
      )
      (vector_image px0 pyy tpx pyy 4)
      (vector_image px0 (1+ pyy) tpx (1+ pyy) 4)
      ;; agua acima do meio-fio: marca a altura do meio-fio em vermelho
      (if (cdr (assoc "EXCEDE-H" hid))
        (vector_image pxc pyh (max tpx (+ px0 10)) pyh 1)
      )
      ;; agua alem da largura da secao: marca o limite em vermelho
      (if (cdr (assoc "EXCEDE-W" hid))
        (vector_image pxw pyr pxw pyy 1)
      )
    )
  )

  ;; contorno do meio-fio e pavimento
  (vector_image pxc pyh px0 pyh 7)
  (vector_image pxc pyh pxc py0 7)
  (vector_image pxc py0 px0 py0 7)
  (vector_image px0 pyh px0 py0 7)
  (vector_image px0 py0 pxw pyr 7)
  (vector_image px0 (1+ py0) pxw (1+ pyr) 7)

  ;; referencia horizontal tracejada
  (setq px px0)
  (while (< px pxw)
    (vector_image px py0 (min pxw (+ px 6)) py0 8)
    (setq px (+ px 10))
  )

  ;; cota de h (esquerda)
  (setq xl (- pxc 14))
  (vector_image xl py0 xl pyh 1)
  (vector_image (- xl 4) py0 (+ xl 4) py0 1)
  (vector_image (- xl 4) pyh (+ xl 4) pyh 1)
  (vector_image xl pyh pxc pyh 9)
  (vector_image xl py0 pxc py0 9)
  (setq txt (strcat "h " (rtos h 2 2)))
  (SJT:Texto txt (- xl 6 (SJT:TextoLargura txt)) (- (/ (+ py0 pyh) 2) 5) 8)

  ;; cota de w (embaixo)
  (setq yb (+ py0 18))
  (vector_image px0 yb pxw yb 1)
  (vector_image px0 (- yb 4) px0 (+ yb 4) 1)
  (vector_image pxw (- yb 4) pxw (+ yb 4) 1)
  (vector_image px0 py0 px0 yb 9)
  (vector_image pxw pyr pxw yb 9)
  (setq txt (strcat "w " (rtos w 2 2)))
  (SJT:Texto txt (- (/ (+ px0 pxw) 2) (/ (SJT:TextoLargura txt) 2)) (+ yb 8) 8)

  ;; cota do desnivel / declividade (direita)
  (setq xr (+ pxw 14))
  (vector_image xr py0 xr pyr 1)
  (vector_image (- xr 4) py0 (+ xr 4) py0 1)
  (vector_image (- xr 4) pyr (+ xr 4) pyr 1)
  (vector_image pxw pyr xr pyr 9)
  (vector_image pxw py0 xr py0 9)
  (SJT:Texto (strcat "s " (rtos s 2 1) "%") (+ xr 8) (- (/ (+ py0 pyr) 2) 5) 8)

  ;; rotulo da lamina d'agua
  (if hid
    (progn
      (setq txt (strcat "y " (rtos (cdr (assoc "Y" hid)) 2 3)))
      (setq tw (SJT:TextoLargura txt))
      (setq ya (+ tpx 8))
      (if (> (+ ya tw) (- dx 4))
        (setq ya (- dx 4 tw))
      )
      (SJT:Texto txt ya (max 2 (- pyy 14)) 5)
    )
  )

  ;; exagero vertical (sempre visivel)
  (SJT:Texto (strcat "V:H=" (itoa exag) ":1") 6 6 8)

  (end_image)
  sx
)

;;; ------------------------------------------------------------
;;; DIALOGO
;;; ------------------------------------------------------------
;; Atualiza textos e desenho (chamada a cada mudanca de selecao/controle)
(defun SJT:_Atualiza (lista pos exag comum q sl / sec hid wref yref h s w n rise)
  (setq sec (nth pos lista))
  (if sec
    (progn
      (setq h (SJT:Val "h" sec))
      (setq s (SJT:Val "s" sec))
      (setq w (SJT:Val "w" sec))
      (setq n (SJT:Val "n" sec))
      (setq rise (/ (* w s) 100.0))
      (setq hid (SJT:Hidraulica sec q sl))
      (if comum
        (setq wref (SJT:_MaxW lista) yref (SJT:_MaxY lista))
        (setq wref w yref 0.0)
      )
      (SJT:Desenha "img" sec exag wref yref hid)

      (set_tile "t_esc"
        (strcat
          (if (= exag 1)
            "Escala real (V:H = 1:1)"
            (strcat "Exagero vertical " (itoa exag) "x (V:H = " (itoa exag) ":1)")
          )
          (if comum "  |  escala comum a todas as secoes" "  |  escala ajustada a esta secao")
        )
      )
      (set_tile "t_par"
        (strcat "h = " (rtos h 2 3) " m    s = " (rtos s 2 2) " %    w = "
                (rtos w 2 3) " m    n = " (rtos n 2 4))
      )
      (set_tile "t_r"
        (strcat "Desnivel em w (s x w): " (rtos rise 2 3) " m")
      )
      (cond
        (hid
          (set_tile "t_res1"
            (strcat "Lamina y = " (rtos (cdr (assoc "Y" hid)) 2 3)
                    " m    Largura inundada T = " (rtos (cdr (assoc "T" hid)) 2 3) " m"))
          (set_tile "t_res2"
            (strcat "Area molhada = " (rtos (cdr (assoc "AM" hid)) 2 4)
                    " m2    Velocidade = " (rtos (cdr (assoc "V" hid)) 2 2) " m/s"))
          (set_tile "t_aviso"
            (cond
              ((and (cdr (assoc "EXCEDE-H" hid)) (cdr (assoc "EXCEDE-W" hid)))
                "ATENCAO: a lamina passa do meio-fio e da largura da secao")
              ((cdr (assoc "EXCEDE-H" hid))
                "ATENCAO: a lamina passa da altura do meio-fio")
              ((cdr (assoc "EXCEDE-W" hid))
                "ATENCAO: a largura inundada passa da largura da secao")
              (T "Escoamento contido na secao")
            )
          )
        )
        ((not (HYDRO:Has "sarjeta-obj"))
          (set_tile "t_res1" "Plugin sarjeta nao carregado: escoamento indisponivel.")
          (set_tile "t_res2" "")
          (set_tile "t_aviso" "")
        )
        (T
          (set_tile "t_res1" "Informe Q (m3/s) e S longitudinal (m/m) para ver a lamina d'agua.")
          (set_tile "t_res2" "")
          (set_tile "t_aviso" "")
        )
      )
    )
  )
)

;; Preenche os controles de uma abertura do dialogo
(defun SJT:_Preenche (lista pos exag comum q sl / ult)
  (start_list "lst")
  (mapcar 'add_list (mapcar 'SJT:Rotulo lista))
  (end_list)
  (set_tile "lst" (itoa pos))
  (set_tile (strcat "ex" (itoa exag)) "1")
  (set_tile "comum" (if comum "1" "0"))
  (set_tile "q" (SJT:_Num q))
  (set_tile "sl" (SJT:_Num sl))
  (if (not (HYDRO:Has "sarjeta-obj"))
    (progn
      (mode_tile "q" 1)
      (mode_tile "sl" 1)
      (mode_tile "ultimo" 1)
    )
  )
  (if (not (SJT:UltimoCalculo))
    (mode_tile "ultimo" 1)
  )
  (SJT:_Atualiza lista pos exag comum q sl)
)

;; Abre o dialogo. Retorna alist (ACAO POS EXAG COMUM Q SL) ou nil (cancelou)
;;   ACAO = "selecionar" ou "inserir"
(defun SJT:Dialogo (lista idx exag comum q sl / dcl dcl_id pos cod ult ok sai)
  (setq dcl (HYDRO:FindFile "secao.dcl"))
  (cond
    ((null lista)
      (alert "Nenhuma secao cadastrada. Use CRIASECAO.")
      nil
    )
    ((not dcl)
      (alert "Arquivo secao.dcl nao encontrado.")
      nil
    )
    ((< (setq dcl_id (load_dialog dcl)) 0)
      (alert "Nao foi possivel carregar secao.dcl.")
      nil
    )
    (T
      (setq pos idx)
      (setq ok T)
      (while ok
        (if (not (new_dialog "secao_dialog" dcl_id))
          (progn
            (alert "Nao foi possivel abrir o dialogo.")
            (setq ok nil)
          )
          (progn
            (SJT:_Preenche lista pos exag comum q sl)
            ;; os callbacks alteram as variaveis locais desta funcao
            (action_tile "lst"
              "(setq pos (atoi $value)) (SJT:_Atualiza lista pos exag comum q sl) (if (= $reason 4) (done_dialog 1))")
            (action_tile "ex1"
              "(setq exag 1) (SJT:_Atualiza lista pos exag comum q sl)")
            (action_tile "ex2"
              "(setq exag 2) (SJT:_Atualiza lista pos exag comum q sl)")
            (action_tile "ex5"
              "(setq exag 5) (SJT:_Atualiza lista pos exag comum q sl)")
            (action_tile "ex10"
              "(setq exag 10) (SJT:_Atualiza lista pos exag comum q sl)")
            (action_tile "comum"
              "(setq comum (= $value \"1\")) (SJT:_Atualiza lista pos exag comum q sl)")
            (action_tile "q"
              "(setq q (SJT:_Real $value)) (SJT:_Atualiza lista pos exag comum q sl)")
            (action_tile "sl"
              "(setq sl (SJT:_Real $value)) (SJT:_Atualiza lista pos exag comum q sl)")
            (action_tile "ultimo" "(done_dialog 5)")
            (action_tile "accept" "(done_dialog 1)")
            (action_tile "inserir" "(done_dialog 6)")
            (action_tile "cancel" "(done_dialog 0)")
            (setq cod (start_dialog))
            (cond
              ;; "Ultimo calculo": carrega Q, S e secao e reabre o dialogo
              ((= cod 5)
                (setq ult (SJT:UltimoCalculo))
                (if ult
                  (setq q   (cdr (assoc "Q" ult))
                        sl  (cdr (assoc "DECL" ult))
                        pos (SJT:_IndiceSecao lista (cdr (assoc "SECAO" ult)) pos))
                )
              )
              ((or (= cod 1) (= cod 6))
                (setq ok nil)
                (setq sai
                  (list
                    (cons "ACAO" (if (= cod 6) "inserir" "selecionar"))
                    (cons "POS" pos)
                    (cons "EXAG" exag)
                    (cons "COMUM" comum)
                    (cons "Q" q)
                    (cons "SL" sl)
                  )
                )
              )
              (T (setq ok nil))
            )
          )
        )
      )
      (unload_dialog dcl_id)
      sai
    )
  )
)

;;; ------------------------------------------------------------
;;; INSERCAO NO DESENHO (entmakex; sem COMMAND)
;;; Escala real em unidades do desenho (assume metros), com exagero vertical.
;;; Assume UCS com plano paralelo ao XY do WCS.
;;; ------------------------------------------------------------
(defun SJT:_GarantirCamada ()
  (if (not (tblsearch "LAYER" "HYDRO-SECAO"))
    (entmakex
      (list '(0 . "LAYER")
            '(100 . "AcDbSymbolTableRecord")
            '(100 . "AcDbLayerTableRecord")
            '(2 . "HYDRO-SECAO")
            '(70 . 0)
            '(62 . 7)
            '(6 . "Continuous"))
    )
  )
)

;; ponto local (x y) em relacao a pt (UCS) -> WCS
(defun SJT:_Wcs (pt p)
  (trans (list (+ (car pt) (car p)) (+ (cadr pt) (cadr p)) (caddr pt)) 1 0)
)

(defun SJT:_Pline (pt pts cor fechada / w)
  (setq w (mapcar (function (lambda (p) (SJT:_Wcs pt p))) pts))
  (entmakex
    (append
      (list '(0 . "LWPOLYLINE")
            '(100 . "AcDbEntity")
            '(8 . "HYDRO-SECAO")
            (cons 62 cor)
            '(100 . "AcDbPolyline")
            (cons 90 (length pts))
            (cons 70 (if fechada 1 0))
            (cons 38 (caddr (car w))))
      (mapcar (function (lambda (p) (cons 10 (list (car p) (cadr p))))) w)
    )
  )
)

;; SOLID: pts = 4 pontos na ordem 1,2,3,4 do SOLID (o desenho segue 1,2,4,3)
(defun SJT:_Solid (pt pts cor / w)
  (setq w (mapcar (function (lambda (p) (SJT:_Wcs pt p))) pts))
  (entmakex
    (list '(0 . "SOLID")
          '(8 . "HYDRO-SECAO")
          (cons 62 cor)
          (cons 10 (nth 0 w))
          (cons 11 (nth 1 w))
          (cons 12 (nth 2 w))
          (cons 13 (nth 3 w)))
  )
)

(defun SJT:_Texto (pt p ht str cor)
  (entmakex
    (list '(0 . "TEXT")
          '(8 . "HYDRO-SECAO")
          (cons 62 cor)
          (cons 10 (SJT:_Wcs pt p))
          (cons 40 ht)
          (cons 1 str))
  )
)

(defun SJT:Inserir (sec pt exag q sl / hid h s w n tc rise ht y larg yr)
  (SJT:_GarantirCamada)
  (setq h (SJT:Val "h" sec))
  (setq s (SJT:Val "s" sec))
  (setq w (SJT:Val "w" sec))
  (setq n (SJT:Val "n" sec))
  (setq tc 0.15)
  (setq rise (/ (* w s) 100.0))
  (setq ht (/ (max w 1.0) 35.0))
  (setq hid (SJT:Hidraulica sec q sl))

  ;; meio-fio
  (SJT:_Solid pt
    (list (list (- tc) 0.0) (list 0.0 0.0)
          (list (- tc) (* h exag)) (list 0.0 (* h exag)))
    8)
  (SJT:_Pline pt
    (list (list (- tc) 0.0) (list (- tc) (* h exag))
          (list 0.0 (* h exag)) (list 0.0 0.0))
    7 T)

  ;; pavimento
  (SJT:_Pline pt (list (list 0.0 0.0) (list w (* rise exag))) 7 nil)

  ;; lamina d'agua
  (if hid
    (progn
      (setq y (* (cdr (assoc "Y" hid)) exag))
      (setq larg (cdr (assoc "T" hid)))
      (setq yr (* rise exag))
      (if (<= larg w)
        (SJT:_Solid pt
          (list (list 0.0 0.0) (list larg y) (list 0.0 y) (list 0.0 y))
          5)
        (SJT:_Solid pt
          (list (list 0.0 0.0) (list w yr) (list 0.0 y) (list w y))
          5)
      )
      (SJT:_Pline pt (list (list 0.0 y) (list (min larg w) y)) 4 nil)
    )
  )

  ;; legenda abaixo da secao
  (SJT:_Texto pt (list (- tc) (* -2.0 ht)) ht
    (strcat "SECAO " (itoa (car sec)) "   V:H = " (itoa exag) ":1") 7)
  (SJT:_Texto pt (list (- tc) (* -4.0 ht)) ht
    (strcat "h = " (rtos h 2 3) " m   s = " (rtos s 2 2) " %   w = "
            (rtos w 2 3) " m   n = " (rtos n 2 4))
    7)
  (if hid
    (progn
      (SJT:_Texto pt (list (- tc) (* -6.0 ht)) ht
        (strcat "Q = " (rtos q 2 4) " m3/s   S = " (rtos sl 2 4)
                "   y = " (rtos (cdr (assoc "Y" hid)) 2 3)
                " m   T = " (rtos larg 2 3) " m   V = "
                (rtos (cdr (assoc "V" hid)) 2 2) " m/s")
        5)
      (if (or (cdr (assoc "EXCEDE-H" hid)) (cdr (assoc "EXCEDE-W" hid)))
        (SJT:_Texto pt (list (- tc) (* -8.0 ht)) ht
          "ATENCAO: lamina fora do meio-fio ou da largura da secao" 1)
      )
    )
  )
  T
)

;;; ------------------------------------------------------------
;;; COMANDO
;;; ------------------------------------------------------------
(defun SJT:Abrir (/ lista idx exag comum ult q sl res sec pt)
  (setq lista (SJT:Secoes))
  (cond
    ((not lista)
      (alert "Nenhuma secao cadastrada. Use CRIASECAO.")
    )
    (T
      (setq idx (SJT:_IndiceSecao lista (HYDRO:Get "HYDRO.SECAO.ATUAL" 0) 0))
      (setq exag (HYDRO:Get "HYDRO.SECAO.EXAG" 1))
      (if (not (member exag '(1 2 5 10))) (setq exag 1))
      (setq comum (= (HYDRO:Get "HYDRO.SECAO.COMUM" 0) 1))
      (setq ult (SJT:UltimoCalculo))
      (setq q  (if ult (cdr (assoc "Q" ult)) nil))
      (setq sl (if ult (cdr (assoc "DECL" ult)) nil))

      (setq res (SJT:Dialogo lista idx exag comum q sl))
      (if res
        (progn
          (setq exag (cdr (assoc "EXAG" res)))
          (setq q    (cdr (assoc "Q" res)))
          (setq sl   (cdr (assoc "SL" res)))
          (setq sec  (nth (cdr (assoc "POS" res)) lista))
          ;; lembra as escolhas de visualizacao
          (HYDRO:Set "HYDRO.SECAO.EXAG" exag)
          (HYDRO:Set "HYDRO.SECAO.COMUM" (if (cdr (assoc "COMUM" res)) 1 0))
          ;; a secao escolhida passa a ser a atual
          (HYDRO:Set "HYDRO.SECAO.ATUAL" (car sec))
          (princ (strcat "\nSecao selecionada: " (itoa (car sec))))
          (if (= (cdr (assoc "ACAO" res)) "inserir")
            (progn
              (setq pt (getpoint "\nPonto de insercao da secao (canto do meio-fio, na base): "))
              (if pt
                (progn
                  (SJT:Inserir sec pt exag q sl)
                  (princ "\nSecao inserida na camada HYDRO-SECAO.")
                )
                (princ "\nInsercao cancelada.")
              )
            )
          )
        )
      )
      res
    )
  )
)

(defun c:SECAO ()
  (SJT:Abrir)
  (princ)
)

;; Pede um real positivo; Enter mantem o padrao
(defun SJT:_PedeReal (msg padrao / v)
  (initget 6)
  (setq v (getreal (strcat "\n" msg " <" (rtos padrao 2 4) ">: ")))
  (if v v padrao)
)

;; Lista as secoes e pede um id existente (Enter = a atual). nil se cancelar/invalido
(defun SJT:_PedeId (acao / sec atual id)
  (setq atual (HYDRO:Get "HYDRO.SECAO.ATUAL" 0))
  (princ "
Secoes cadastradas:")
  (foreach sec (SJT:Secoes)
    (princ (strcat "
  " (SJT:Rotulo sec) (if (= (car sec) atual) "  (atual)" "")))
  )
  (initget 4)
  (setq id (getint (strcat "
Id da secao a " acao " <" (itoa atual) ">: ")))
  (if (not id) (setq id atual))
  (if (SJT:PorId id)
    id
    (progn (princ (strcat "
Secao " (itoa id) " nao existe.")) nil)
  )
)

;; EDITASECAO: altera h, s, w, n de uma secao cadastrada
(defun c:EDITASECAO (/ id sec h s w n emuso)
  (setq id (SJT:_PedeId "editar"))
  (if id
    (progn
      (setq sec (SJT:PorId id))
      (setq h (SJT:_PedeReal "Altura do meio-fio h (m)" (SJT:Val "h" sec)))
      (setq s (SJT:_PedeReal "Caimento transversal s (%)" (SJT:Val "s" sec)))
      (setq w (SJT:_PedeReal "Largura da secao w (m)" (SJT:Val "w" sec)))
      (setq n (SJT:_PedeReal "Rugosidade de Manning n" (SJT:Val "n" sec)))
      (setq sec (SJT:Editar id h s w n))
      (princ (strcat "
Secao atualizada: " (SJT:Rotulo sec)))
      (setq emuso (SJT:EmUso id))
      (if (> emuso 0)
        (princ (strcat "
" (itoa emuso)
                       " sarjeta(s) usam esta secao: rode CALCULAOBJETO para recalcular."))
      )
    )
  )
  (princ)
)

;; REMOVESECAO: apaga uma secao cadastrada (pede confirmacao se houver sarjeta usando)
(defun c:REMOVESECAO (/ id emuso ok)
  (setq id (SJT:_PedeId "remover"))
  (cond
    ((not id))
    ((< (length (SJT:Secoes)) 2)
      (princ "
Nao e possivel remover a unica secao cadastrada.")
    )
    (T
      (setq ok T)
      (setq emuso (SJT:EmUso id))
      (if (> emuso 0)
        (progn
          (initget "Sim Nao")
          (setq ok
            (equal "Sim"
              (getkword (strcat "
" (itoa emuso)
                                " sarjeta(s) usam esta secao. Remover mesmo assim? [Sim/Nao] <Nao>: "))))
        )
      )
      (if ok
        (progn
          (SJT:Remover id)
          (princ (strcat "
Secao " (itoa id) " removida. Secao atual: "
                         (itoa (HYDRO:Get "HYDRO.SECAO.ATUAL" 0))))
        )
        (princ "
Remocao cancelada.")
      )
    )
  )
  (princ)
)

;; CRIASECAO: cadastra uma secao de sarjeta (h, s, w, n); opcionalmente a desenha
(defun c:CRIASECAO (/ base h s w n sec pt exag)
  (setq base (cond ((cdr (assoc (HYDRO:Get "HYDRO.SECAO.ATUAL" 0) (SJT:Secoes))))
                   (T (cdr (car (SJT:Secoes))))))
  (setq h (SJT:_PedeReal "Altura do meio-fio h (m)" (cond ((cdr (assoc "h" base))) (T 0.15))))
  (setq s (SJT:_PedeReal "Caimento transversal s (%)" (cond ((cdr (assoc "s" base))) (T 3.0))))
  (setq w (SJT:_PedeReal "Largura da secao w (m)" (cond ((cdr (assoc "w" base))) (T 3.5))))
  (setq n (SJT:_PedeReal "Rugosidade de Manning n" (cond ((cdr (assoc "n" base))) (T 0.013))))
  (setq sec (SJT:Adicionar h s w n))
  (princ (strcat "\nSecao " (itoa (car sec)) " criada e definida como atual: "
                 (SJT:Rotulo sec)))
  (setq pt (getpoint "\nPonto de insercao para desenhar a secao (Enter = nao desenhar): "))
  (if pt
    (progn
      (setq exag (HYDRO:Get "HYDRO.SECAO.EXAG" 1))
      (if (not (member exag '(1 2 5 10))) (setq exag 1))
      (SJT:Inserir sec pt exag nil nil)
      (princ "\nSecao inserida na camada HYDRO-SECAO.")
    )
  )
  (princ)
)

(HYDRO:SetLabel "HYDRO.SECAO.EXAG" "Exagero vertical da visualizacao de secoes" "x")
(HYDRO:SetLabel "HYDRO.SECAO.COMUM" "Escala comum nas secoes (1 = sim)" "")

(HYDRO:Provide "secao-view" "1.0")
(princ)
