;;; ============================================================
;;; views/secao_tubo_view.lsp - VISUALIZADOR E COMANDOS DAS SECOES DE TUBO/CANAL (STB:)
;;;
;;;   SECAOTUBO        abre o VISUALIZADOR (resources/dcl/secao_tubo.dcl): lista as secoes, desenha a
;;;                    secao em forma real, ESCALA COMUM opcional, escoamento de Manning (Q e S ->
;;;                    altura da lamina, velocidade, Froude, capacidade) e "Inserir no desenho"
;;;   CRIASECAOTUBO    cria uma secao (circular, retangular ou trapezoidal) e a torna a atual
;;;   EDITASECAOTUBO   edita uma secao do catalogo (os valores atuais vem como padrao)
;;;   REMOVESECAOTUBO  remove uma secao (recusa se algum tubo a usa; nunca a ultima)
;;;
;;; Como o visualizador das sarjetas (views/secao_view.lsp), sem o exagero vertical: o circulo
;;; precisa continuar circulo, entao o desenho e sempre em escala 1:1 (a escala se ajusta para caber).
;;; Dados, catalogo e ultimo calculo ficam em plugins/secao_tubo.lsp (como plugins/secao.lsp
;;; das sarjetas); a hidraulica (TUB:Resolver) em plugins/models/tubo.lsp.
;;; Depende de "secao-tubo" e "tubo-obj". Sem variaveis globais.
;;; ============================================================
(vl-load-com)

;; verifica o model; alerta e devolve nil se ele nao esta carregado
(defun STB:_Ok ()
  (if (and (HYDRO:Has "tubo-obj") (HYDRO:Has "secao-tubo"))
    T
    (progn (alert "Modelo e plugin de secoes de tubo/canal (tubo.lsp, secao_tubo.lsp) nao carregados.") nil)
  )
)

;;; ------------------------------------------------------------
;;; PEDIDOS NA LINHA DE COMANDO
;;; ------------------------------------------------------------
;; Pergunta a forma. Enter mantem a atual (padrao circular).
(defun STB:_PedeForma (atual / r)
  (initget "Circular Retangular Trapezoidal")
  (setq r
    (getkword
      (strcat "\nForma [Circular/Retangular/Trapezoidal] <"
              (cond ((equal atual "retangular") "Retangular")
                    ((equal atual "trapezoidal") "Trapezoidal")
                    (T "Circular"))
              ">: ")))
  (cond
    ((equal r "Retangular") "retangular")
    ((equal r "Trapezoidal") "trapezoidal")
    ((equal r "Circular") "circular")
    (T (if atual atual "circular"))
  )
)

;; Pergunta as dimensoes da forma. sec = secao atual (padroes) ou nil.
;; Retorna (d b h z n) (nil nos que a forma nao usa).
(defun STB:_PedeDims (forma sec / d b h z n)
  (cond
    ((equal forma "circular")
      (setq d (HYDRO:AskReal "Diametro D (m)" (if (and sec (STB:Val "d" sec)) (STB:Val "d" sec) 0.6))))
    (T
      (setq b (HYDRO:AskReal "Largura da base b (m)" (if (and sec (STB:Val "b" sec)) (STB:Val "b" sec) 1.0)))
      (setq h (HYDRO:AskReal "Altura h (m)" (if (and sec (STB:Val "h" sec)) (STB:Val "h" sec) 1.0)))
      (if (equal forma "trapezoidal")
        (setq z (HYDRO:AskReal "Talude z (H : 1 V)" (if (and sec (STB:Val "z" sec)) (STB:Val "z" sec) 1.5)))
      )
    )
  )
  (setq n
    (HYDRO:AskReal "Rugosidade de Manning n"
      (if (and sec (STB:Val "n" sec))
        (STB:Val "n" sec)
        (cond ((equal forma "circular") 0.013) ((equal forma "retangular") 0.015) (T 0.025)))))
  (list d b h z n)
)

;; pergunta um id existente do catalogo (Enter = padrao); nil se invalido
(defun STB:_PedeId (msg padrao / id)
  (setq id (getint (strcat "\n" msg " <" (itoa padrao) ">: ")))
  (if (not id) (setq id padrao))
  (if (STB:PorId id)
    id
    (progn (princ (strcat "\nSecao " (itoa id) " nao existe (veja SECAOTUBO).")) nil)
  )
)

;;; ------------------------------------------------------------
;;; MEDIDAS E AUXILIARES DO VISUALIZADOR
;;; ------------------------------------------------------------
;; (puro) largura total (no topo) e altura da secao, em m: (largura altura)
(defun STB:_Dim (sec / f z)
  (setq f (STB:Val "forma" sec))
  (setq z (if (STB:Val "z" sec) (STB:Val "z" sec) 0.0))
  (if (equal f "circular")
    (list (STB:Val "d" sec) (STB:Val "d" sec))
    (list (+ (STB:Val "b" sec) (* 2.0 z (STB:Val "h" sec))) (STB:Val "h" sec))
  )
)

;; (puro) maior largura e maior altura entre as secoes (escala comum)
(defun STB:_MaxDim (lista / w h s d)
  (setq w 0.0 h 0.0)
  (foreach s lista
    (setq d (STB:_Dim s))
    (setq w (max w (car d)))
    (setq h (max h (cadr d)))
  )
  (list w h)
)

;; (puro) indice (posicao na lista) da secao de id dado; padrao se nao achar
(defun STB:_IndiceSecao (lista id padrao / i achou s)
  (setq i 0)
  (foreach s lista
    (if (and (not achou) id (= (car s) id)) (setq achou i))
    (setq i (1+ i))
  )
  (if achou achou padrao)
)

;; "0,045" ou "0.045" -> 0.045 ; vazio/invalido -> nil
(defun STB:_Real (s)
  (if (and s (/= (vl-string-trim " " s) ""))
    (distof (vl-string-subst "." "," s) 2)
    nil
  )
)

(defun STB:_Num (x)
  (if x (rtos x 2 4) "")
)

;;; ------------------------------------------------------------
;;; DESENHO NA IMAGEM DO DIALOGO (escala 1:1, forma real)
;;; ------------------------------------------------------------
;; key = tile da imagem; sec = secao; wref/href = referencias de escala (m; secao propria ou
;; maior de todas, com escala comum); hid = resultado de STB:_Hid ou nil
(defun STB:Desenha
  (key sec wref href hid /
   forma dx dy mxl mxr myt myb dim sx cx y0 b h z r rp cyc k ang px py prevx prevy
   hw hh j yw xl xr ytop tw txt wtop ya)

  (setq forma (STB:Val "forma" sec))
  (setq dx (dimx_tile key))
  (setq dy (dimy_tile key))
  (setq mxl 70 mxr 70 myt 26 myb 46)
  (setq dim (STB:_Dim sec))
  (setq wref (max wref (car dim)))
  (setq href (max href (cadr dim)))
  (setq sx (min (/ (- dx mxl mxr) wref) (/ (- dy myt myb) href)))
  (setq cx (+ mxl (/ (- dx mxl mxr) 2.0)))
  (setq y0 (- dy myb))
  (setq yw (if hid (cdr (assoc "Y" hid)) nil))

  (start_image key)
  (fill_image 0 0 dx dy -2)

  (cond
    ;; ---- circular: contorno de 72 segmentos; lamina por linhas horizontais ----
    ((equal forma "circular")
      (setq r (/ (STB:Val "d" sec) 2.0))
      (setq rp (* r sx))
      (setq cyc (- y0 rp))
      (if yw
        (progn
          (setq j 0)
          (while (<= j (fix (* yw sx)))
            (setq hh (/ j sx))
            (setq hw (sqrt (max 0.0 (- (* r r) (* (- r hh) (- r hh))))))
            (vector_image (fix (- cx (* hw sx))) (- (fix y0) j) (fix (+ cx (* hw sx))) (- (fix y0) j) 5)
            (setq j (1+ j))
          )
        )
      )
      (setq k 0)
      (while (<= k 72)
        (setq ang (/ (* 2.0 pi k) 72.0))
        (setq px (fix (+ cx (* rp (cos ang)))))
        (setq py (fix (- cyc (* rp (sin ang)))))
        (if prevx (vector_image prevx prevy px py 7))
        (setq prevx px prevy py)
        (setq k (1+ k))
      )
      ;; cota do diametro (embaixo)
      (setq txt (strcat "D " (rtos (STB:Val "d" sec) 2 3)))
      (HYDRO:ImgTexto txt (- (fix cx) (/ (HYDRO:ImgTextoLargura txt) 2)) (+ (fix y0) 14) 8)
    )
    ;; ---- retangular / trapezoidal: paredes em U, topo tracejado ----
    (T
      (setq b (STB:Val "b" sec))
      (setq h (STB:Val "h" sec))
      (setq z (if (STB:Val "z" sec) (STB:Val "z" sec) 0.0))
      (setq wtop (+ b (* 2.0 z h)))
      (setq ytop (fix (- y0 (* h sx))))
      (if yw
        (progn
          (setq j 0)
          (while (<= j (fix (* yw sx)))
            (setq hw (/ (+ b (* 2.0 z (/ j sx))) 2.0))
            (vector_image (fix (- cx (* hw sx))) (- (fix y0) j) (fix (+ cx (* hw sx))) (- (fix y0) j) 5)
            (setq j (1+ j))
          )
        )
      )
      (setq xl (fix (- cx (* (/ wtop 2.0) sx))))
      (setq xr (fix (+ cx (* (/ wtop 2.0) sx))))
      ;; parede esquerda, fundo, parede direita
      (vector_image xl ytop (fix (- cx (* (/ b 2.0) sx))) (fix y0) 7)
      (vector_image (fix (- cx (* (/ b 2.0) sx))) (fix y0) (fix (+ cx (* (/ b 2.0) sx))) (fix y0) 7)
      (vector_image (fix (+ cx (* (/ b 2.0) sx))) (fix y0) xr ytop 7)
      ;; nivel maximo (h) tracejado
      (setq px xl)
      (while (< px xr)
        (vector_image px ytop (min xr (+ px 6)) ytop 8)
        (setq px (+ px 10))
      )
      ;; cota da base (embaixo) e da altura (esquerda)
      (setq txt (strcat "b " (rtos b 2 3)))
      (HYDRO:ImgTexto txt (- (fix cx) (/ (HYDRO:ImgTextoLargura txt) 2)) (+ (fix y0) 14) 8)
      (setq txt (strcat "h " (rtos h 2 3)))
      (HYDRO:ImgTexto txt (max 2 (- xl 12 (HYDRO:ImgTextoLargura txt))) (- (/ (+ ytop (fix y0)) 2) 5) 8)
      (if (equal forma "trapezoidal")
        (progn
          (setq txt (strcat "z " (rtos z 2 2) ":1"))
          (HYDRO:ImgTexto txt (+ xr 8) (- (/ (+ ytop (fix y0)) 2) 5) 8)
          (setq txt (strcat "B " (rtos wtop 2 3)))
          (HYDRO:ImgTexto txt (- (fix cx) (/ (HYDRO:ImgTextoLargura txt) 2)) (max 2 (- ytop 16)) 8)
        )
      )
    )
  )

  ;; superficie e rotulo da lamina d'agua
  (if yw
    (progn
      (setq py (- (fix y0) (fix (* yw sx))))
      (setq hw (/ (cdr (assoc "T" hid)) 2.0))
      (if (> hw 0.0)
        (progn
          (vector_image (fix (- cx (* hw sx))) py (fix (+ cx (* hw sx))) py 4)
          (vector_image (fix (- cx (* hw sx))) (1+ py) (fix (+ cx (* hw sx))) (1+ py) 4)
        )
      )
      (setq txt (strcat "y " (rtos yw 2 3)))
      (setq tw (HYDRO:ImgTextoLargura txt))
      (setq ya (+ (fix (+ cx (* hw sx))) 8))
      (if (> (+ ya tw) (- dx 4)) (setq ya (- dx 4 tw)))
      (HYDRO:ImgTexto txt ya (max 2 (- py 14)) 5)
    )
  )

  (HYDRO:ImgTexto "V:H=1:1" 6 6 8)
  (end_image)
  sx
)

;;; ------------------------------------------------------------
;;; DIALOGO
;;; ------------------------------------------------------------
;; texto da forma e dimensoes para o dialogo
(defun STB:_Par (sec / f)
  (setq f (STB:Val "forma" sec))
  (strcat
    (cond
      ((equal f "circular") (strcat "Circular   D = " (rtos (STB:Val "d" sec) 2 3) " m"))
      ((equal f "retangular")
        (strcat "Retangular   b = " (rtos (STB:Val "b" sec) 2 3) " m   h = " (rtos (STB:Val "h" sec) 2 3) " m"))
      (T
        (strcat "Trapezoidal   b = " (rtos (STB:Val "b" sec) 2 3) " m   h = " (rtos (STB:Val "h" sec) 2 3)
                " m   z = " (rtos (STB:Val "z" sec) 2 2) " (H:V)")))
    "    n = " (rtos (STB:Val "n" sec) 2 4))
)

;; Atualiza textos e desenho (chamada a cada mudanca de selecao/controle)
(defun STB:_Atualiza (lista pos comum q sl / sec hid dim ref g a p fr av)
  (setq sec (nth pos lista))
  (if sec
    (progn
      (setq hid (STB:Hidraulica sec q sl))
      (setq dim (STB:_Dim sec))
      (setq ref (if comum (STB:_MaxDim lista) (list (car dim) (cadr dim))))
      (STB:Desenha "img" sec (car ref) (cadr ref) hid)
      (set_tile "t_esc"
        (strcat "Forma real (V:H = 1:1)"
                (if comum "  |  escala comum a todas as secoes" "  |  escala ajustada a esta secao")))
      (set_tile "t_par" (STB:_Par sec))
      ;; secao cheia (ou ate h): area, perimetro, raio hidraulico
      (setq g (TUB:Geom sec (TUB:YMax sec)))
      (setq a (cdr (assoc "A" g)))
      (setq p (cdr (assoc "P" g)))
      (set_tile "t_r"
        (strcat "Secao cheia: A = " (rtos a 2 4) " m2   P = " (rtos p 2 3) " m   R = "
                (rtos (/ a p) 2 4) " m"))
      (cond
        (hid
          (setq fr (cdr (assoc "FR" hid)))
          (set_tile "t_res1"
            (strcat "Altura y = " (rtos (cdr (assoc "Y" hid)) 2 3) " m   enchimento = "
                    (rtos (* 100.0 (cdr (assoc "RAZAO" hid))) 2 1) " %   Velocidade = "
                    (rtos (cdr (assoc "V" hid)) 2 2) " m/s"))
          (set_tile "t_res2"
            (strcat "Area molhada = " (rtos (cdr (assoc "A" hid)) 2 4) " m2   Froude = "
                    (if fr (rtos fr 2 2) "-") "   Capacidade (cheia) = "
                    (rtos (cdr (assoc "QCAP" hid)) 2 3) " m3/s"))
          (setq av (cdr (assoc "AVISOS" hid)))
          (set_tile "t_aviso"
            (if av (strcat "ATENCAO: " (car av)) "Escoamento com lamina livre"))
        )
        (T
          (set_tile "t_res1" "Informe Q (m3/s) e S longitudinal (m/m) para ver a altura da lamina d'agua.")
          (set_tile "t_res2" "")
          (set_tile "t_aviso" "")
        )
      )
    )
  )
)

;; Preenche os controles de uma abertura do dialogo
(defun STB:_Preenche (lista pos comum q sl)
  (start_list "lst")
  (mapcar 'add_list (mapcar 'STB:Rotulo lista))
  (end_list)
  (set_tile "lst" (itoa pos))
  (set_tile "comum" (if comum "1" "0"))
  (set_tile "q" (STB:_Num q))
  (set_tile "sl" (STB:_Num sl))
  (if (not (STB:UltimoCalculo)) (mode_tile "ultimo" 1))
  (STB:_Atualiza lista pos comum q sl)
)

;; Abre o dialogo. Retorna alist (ACAO POS COMUM Q SL) ou nil (cancelou)
;;   ACAO = "selecionar" ou "inserir"
(defun STB:Dialogo (lista idx comum q sl / dcl dcl_id pos cod ult ok sai)
  (setq dcl (HYDRO:FindFile "secao_tubo.dcl"))
  (cond
    ((null lista)
      (alert "Nenhuma secao cadastrada. Use CRIASECAOTUBO.")
      nil
    )
    ((not dcl)
      (alert "Arquivo secao_tubo.dcl nao encontrado.")
      nil
    )
    ((< (setq dcl_id (load_dialog dcl)) 0)
      (alert "Nao foi possivel carregar secao_tubo.dcl.")
      nil
    )
    (T
      (setq pos idx)
      (setq ok T)
      (while ok
        (if (not (new_dialog "secao_tubo_dialog" dcl_id))
          (progn
            (alert "Nao foi possivel abrir o dialogo.")
            (setq ok nil)
          )
          (progn
            (STB:_Preenche lista pos comum q sl)
            ;; os callbacks alteram as variaveis locais desta funcao
            (action_tile "lst"
              "(setq pos (atoi $value)) (STB:_Atualiza lista pos comum q sl) (if (= $reason 4) (done_dialog 1))")
            (action_tile "comum"
              "(setq comum (= $value \"1\")) (STB:_Atualiza lista pos comum q sl)")
            (action_tile "q"
              "(setq q (STB:_Real $value)) (STB:_Atualiza lista pos comum q sl)")
            (action_tile "sl"
              "(setq sl (STB:_Real $value)) (STB:_Atualiza lista pos comum q sl)")
            (action_tile "ultimo" "(done_dialog 5)")
            (action_tile "accept" "(done_dialog 1)")
            (action_tile "inserir" "(done_dialog 6)")
            (action_tile "cancel" "(done_dialog 0)")
            (setq cod (start_dialog))
            (cond
              ;; "Ultimo calculo": carrega Q, S e secao e reabre o dialogo
              ((= cod 5)
                (setq ult (STB:UltimoCalculo))
                (if ult
                  (setq q   (cdr (assoc "Q" ult))
                        sl  (cdr (assoc "DECL" ult))
                        pos (STB:_IndiceSecao lista (cdr (assoc "SECAO" ult)) pos))
                )
              )
              ((or (= cod 1) (= cod 6))
                (setq ok nil)
                (setq sai
                  (list
                    (cons "ACAO" (if (= cod 6) "inserir" "selecionar"))
                    (cons "POS" pos)
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
;;; Escala real 1:1 em unidades do desenho (assume metros). Assume UCS com plano
;;; paralelo ao XY do WCS. pt = centro da BASE da secao.
;;; ------------------------------------------------------------
(defun STB:_GarantirCamada ()
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
(defun STB:_Wcs (pt p)
  (trans (list (+ (car pt) (car p)) (+ (cadr pt) (cadr p)) (caddr pt)) 1 0)
)

(defun STB:_Pline (pt pts cor fechada / w)
  (setq w (mapcar (function (lambda (p) (STB:_Wcs pt p))) pts))
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
(defun STB:_Solid (pt pts cor / w)
  (setq w (mapcar (function (lambda (p) (STB:_Wcs pt p))) pts))
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

(defun STB:_Circulo (pt centro raio cor)
  (entmakex
    (list '(0 . "CIRCLE")
          '(8 . "HYDRO-SECAO")
          (cons 62 cor)
          (cons 10 (STB:_Wcs pt centro))
          (cons 40 raio))
  )
)

(defun STB:_Texto (pt p ht str cor)
  (entmakex
    (list '(0 . "TEXT")
          '(8 . "HYDRO-SECAO")
          (cons 62 cor)
          (cons 10 (STB:_Wcs pt p))
          (cons 40 ht)
          (cons 1 str))
  )
)

;; (puro) pontos da lamina em secao circular: arco do fundo de y=0 ate a altura y, fechado
;; pela corda. r = raio, y = altura (limitada a D). Centro em (0, r).
(defun STB:_PontosLaminaCirc (r y / phi n k pts a)
  (setq y (min y (* 2.0 r)))
  (setq phi (TUB:Acos (/ (- r y) r)))
  (setq n 32)
  (setq k 0)
  (while (<= k n)
    (setq a (+ (- (/ pi -2.0) phi) (* (/ k (float n)) 2.0 phi)))
    (setq pts (append pts (list (list (* r (cos a)) (+ r (* r (sin a)))))))
    (setq k (1+ k))
  )
  pts
)

(defun STB:Inserir (sec pt q sl / hid f b h z d r y wtop ht)
  (STB:_GarantirCamada)
  (setq f (STB:Val "forma" sec))
  (setq hid (STB:Hidraulica sec q sl))
  (setq y (if hid (cdr (assoc "Y" hid)) nil))
  (cond
    ((equal f "circular")
      (setq d (STB:Val "d" sec))
      (setq r (/ d 2.0))
      (setq wtop d)
      (STB:_Circulo pt (list 0.0 r) r 7)
      (if y (STB:_Pline pt (STB:_PontosLaminaCirc r y) 5 T))
    )
    (T
      (setq b (STB:Val "b" sec))
      (setq h (STB:Val "h" sec))
      (setq z (if (STB:Val "z" sec) (STB:Val "z" sec) 0.0))
      (setq wtop (+ b (* 2.0 z h)))
      ;; paredes em U e nivel maximo (h)
      (STB:_Pline pt
        (list (list (- (/ wtop 2.0)) h) (list (- (/ b 2.0)) 0.0)
              (list (/ b 2.0) 0.0) (list (/ wtop 2.0) h))
        7 nil)
      (STB:_Pline pt (list (list (- (/ wtop 2.0)) h) (list (/ wtop 2.0) h)) 8 nil)
      (if y
        (progn
          (STB:_Solid pt
            (list (list (- (/ b 2.0)) 0.0) (list (/ b 2.0) 0.0)
                  (list (- (+ (/ b 2.0) (* z y))) y) (list (+ (/ b 2.0) (* z y)) y))
            5)
          (STB:_Pline pt
            (list (list (- (+ (/ b 2.0) (* z y))) y) (list (+ (/ b 2.0) (* z y)) y))
            4 nil)
        )
      )
    )
  )
  ;; legenda abaixo da secao
  (setq ht (/ (max wtop 1.0) 35.0))
  (STB:_Texto pt (list (- (/ wtop 2.0)) (* -2.0 ht)) ht
    (strcat "SECAO " (itoa (car sec)) "   (forma real 1:1)") 7)
  (STB:_Texto pt (list (- (/ wtop 2.0)) (* -4.0 ht)) ht (STB:_Par sec) 7)
  (if hid
    (STB:_Texto pt (list (- (/ wtop 2.0)) (* -6.0 ht)) ht
      (strcat "Q = " (rtos q 2 4) " m3/s   S = " (rtos sl 2 4) "   y = "
              (rtos y 2 3) " m   V = " (rtos (cdr (assoc "V" hid)) 2 2) " m/s")
      5)
  )
  T
)

;;; ------------------------------------------------------------
;;; COMANDOS
;;; ------------------------------------------------------------
(defun STB:Abrir (/ lista idx comum ult q sl res sec pt)
  (setq lista (STB:Secoes))
  (setq idx (STB:_IndiceSecao lista (STB:SecaoAtualId) 0))
  (setq comum (= (HYDRO:Get "HYDRO.SECAO.TUBO.COMUM" 0) 1))
  (setq ult (STB:UltimoCalculo))
  (setq q  (if ult (cdr (assoc "Q" ult)) nil))
  (setq sl (if ult (cdr (assoc "DECL" ult)) nil))
  (setq res (STB:Dialogo lista idx comum q sl))
  (if res
    (progn
      (setq q   (cdr (assoc "Q" res)))
      (setq sl  (cdr (assoc "SL" res)))
      (setq sec (nth (cdr (assoc "POS" res)) lista))
      ;; lembra a escolha de escala; a secao escolhida passa a ser a atual
      (HYDRO:Set "HYDRO.SECAO.TUBO.COMUM" (if (cdr (assoc "COMUM" res)) 1 0))
      (HYDRO:Set "HYDRO.SECAO.TUBO.ATUAL" (car sec))
      (princ (strcat "\nSecao selecionada: " (itoa (car sec))))
      (if (equal (cdr (assoc "ACAO" res)) "inserir")
        (progn
          (setq pt (getpoint "\nPonto de insercao da secao (centro da base): "))
          (if pt
            (progn
              (STB:Inserir sec pt q sl)
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

(defun c:SECAOTUBO ()
  (if (STB:_Ok) (STB:Abrir))
  (princ)
)

(defun c:CRIASECAOTUBO (/ forma dims sec pt)
  (if (STB:_Ok)
    (progn
      (setq forma (STB:_PedeForma nil))
      (setq dims (STB:_PedeDims forma nil))
      (setq sec
        (STB:Adicionar forma (nth 0 dims) (nth 1 dims) (nth 2 dims) (nth 3 dims) (nth 4 dims)))
      (if sec
        (progn
          (princ (strcat "\nCriada e definida como atual: " (STB:Rotulo sec)))
          (setq pt (getpoint "\nPonto de insercao para desenhar a secao (Enter = nao desenhar): "))
          (if pt
            (progn
              (STB:Inserir sec pt nil nil)
              (princ "\nSecao inserida na camada HYDRO-SECAO.")
            )
          )
        )
        (princ "\nValores invalidos (use dimensoes e n maiores que zero): nada foi criado.")
      )
    )
  )
  (princ)
)

(defun c:EDITASECAOTUBO (/ id sec forma dims novo)
  (if (STB:_Ok)
    (progn
      (setq id (STB:_PedeId "Id da secao a editar" (STB:SecaoAtualId)))
      (if id
        (progn
          (setq sec (STB:PorId id))
          (setq forma (STB:_PedeForma (STB:Val "forma" sec)))
          (setq dims (STB:_PedeDims forma (if (equal forma (STB:Val "forma" sec)) sec nil)))
          (setq novo
            (STB:Editar id forma (nth 0 dims) (nth 1 dims) (nth 2 dims) (nth 3 dims) (nth 4 dims)))
          (if novo
            (princ
              (strcat "\nSecao atualizada: " (STB:Rotulo novo)
                      "\nRode CALCULAOBJETO nos tubos que a usam: os resultados antigos ficaram desatualizados."))
            (princ "\nValores invalidos: a secao nao foi alterada.")
          )
        )
      )
    )
  )
  (princ)
)

(defun c:REMOVESECAOTUBO (/ id em r)
  (if (STB:_Ok)
    (progn
      (setq id (STB:_PedeId "Id da secao a remover" (STB:SecaoAtualId)))
      (if id
        (progn
          (setq em (STB:EmUso id))
          (cond
            ((> em 0)
              (alert (strcat "A secao " (itoa id) " e usada por " (itoa em)
                             " tubo(s). Troque a secao deles (TUBOEDITA) antes de remover.")))
            ((< (length (STB:Secoes)) 2)
              (alert "Nao e possivel remover a ultima secao do catalogo."))
            (T
              (initget "Sim Nao")
              (setq r (getkword (strcat "\nRemover a " (STB:Rotulo (STB:PorId id)) "? [Sim/Nao] <Nao>: ")))
              (if (equal r "Sim")
                (progn (STB:Remover id) (princ "\nSecao removida."))
              )
            )
          )
        )
      )
    )
  )
  (princ)
)

(HYDRO:Provide "secao-tubo-view" "3.0")
(princ)
