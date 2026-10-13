;;; ============================================================
;;; views/hidrograma_view.lsp - VIEW DOS HIDROGRAMAS (HID:)
;;;
;;; Visualizador (resources/dcl/hidrograma.dcl), grafico, exportacao CSV e
;;; comandos HIDROGRAMA e HIDROGRAMAVER. Calculo, catalogo de tipos e
;;; armazenamento ficam em plugins/hidrograma.lsp.
;;; Depende de "hidrograma" e "bacia".
;;; ============================================================
(vl-load-com)

(defun HID:_Cores ()
  '(5 1 3 6 4 2)
)

(defun HID:_NomesCores ()
  '("azul" "vermelho" "verde" "magenta" "ciano" "amarelo")
)

;;; ------------------------------------------------------------
;;; VISUALIZADOR (DCL)
;;; ------------------------------------------------------------
(defun HID:_ParseSel (s)
  (if (and s (/= (vl-string-trim " " s) ""))
    (read (strcat "(" s ")"))
    nil
  )
)

;; Linhas da tabela de um hidrograma (cabecalho + t, Q, volume acumulado)
(defun HID:_LinhasTabela (h / acum prev out p)
  (setq out (list "t (min)\tQ (m3/s)\tV acum. (m3)"))
  (setq acum 0.0)
  (foreach p (cdr (assoc "PONTOS" h))
    (if prev
      (setq acum
        (+ acum (* (/ (+ (cdr prev) (cdr p)) 2.0) (- (car p) (car prev)) 60.0)))
    )
    (setq out
      (append out
        (list (strcat (rtos (car p) 2 2) "\t" (rtos (cdr p) 2 4) "\t" (rtos acum 2 1))))
    )
    (setq prev p)
  )
  out
)

;; Grafico (varios hidrogramas, cada um com uma cor)
(defun HID:_Plota (key lista /
                   dx dy ml mr mt mb pw ph tmax qmax x0 y0 i px py txt
                   k h cor pts prev p cx cy pico)
  (setq dx (dimx_tile key))
  (setq dy (dimy_tile key))
  (setq ml 60 mr 16 mt 14 mb 26)
  (setq pw (- dx ml mr))
  (setq ph (- dy mt mb))
  (setq tmax 0.0 qmax 0.0)
  (foreach h lista
    (setq pts (cdr (assoc "PONTOS" h)))
    (setq tmax (max tmax (car (last pts))))
    (setq qmax (max qmax (cdr (HID:_Pico pts))))
  )
  (setq tmax (HID:_NiceMax tmax))
  (setq qmax (HID:_NiceMax qmax))
  (setq x0 ml)
  (setq y0 (- dy mb))

  (start_image key)
  (fill_image 0 0 dx dy -2)

  ;; grade e valores dos eixos (5 divisoes)
  (setq i 0)
  (while (<= i 5)
    (setq px (+ x0 (fix (/ (* pw i) 5.0))))
    (vector_image px y0 px (- y0 ph) 9)
    (setq txt (HYDRO:FmtReal (* tmax (/ i 5.0))))
    (HYDRO:ImgTexto txt (- px (/ (HYDRO:ImgTextoLargura txt) 2)) (+ y0 8) 8)
    (setq py (- y0 (fix (/ (* ph i) 5.0))))
    (vector_image x0 py (+ x0 pw) py 9)
    (setq txt (HYDRO:FmtReal (* qmax (/ i 5.0))))
    (HYDRO:ImgTexto txt (- x0 6 (HYDRO:ImgTextoLargura txt)) (- py 5) 8)
    (setq i (1+ i))
  )
  (vector_image x0 y0 (+ x0 pw) y0 7)
  (vector_image x0 y0 x0 (- y0 ph) 7)

  ;; curvas
  (setq k 0)
  (foreach h lista
    (setq cor (nth (rem k 6) (HID:_Cores)))
    (setq pts (cdr (assoc "PONTOS" h)))
    (setq prev nil)
    (foreach p pts
      (setq cx (+ x0 (fix (* pw (/ (car p) tmax)))))
      (setq cy (- y0 (fix (* ph (/ (cdr p) qmax)))))
      (if prev
        (progn
          (vector_image (car prev) (cdr prev) cx cy cor)
          (vector_image (car prev) (1- (cdr prev)) cx (1- cy) cor)
        )
      )
      (setq prev (cons cx cy))
    )
    ;; marca do pico
    (setq pico (HID:_Pico pts))
    (setq cx (+ x0 (fix (* pw (/ (car pico) tmax)))))
    (setq cy (- y0 (fix (* ph (/ (cdr pico) qmax)))))
    (fill_image (- cx 2) (- cy 2) 5 5 cor)
    (setq k (1+ k))
  )
  (end_image)
  T
)

;; Atualiza grafico, informacoes e tabela conforme a selecao
(defun HID:_Atualiza (hids sel / lista primario k linhas h)
  (setq lista (mapcar (function (lambda (i) (nth i hids))) sel))
  (setq primario (car lista))
  (if lista
    (HID:_Plota "img" lista)
    (progn
      (start_image "img")
      (fill_image 0 0 (dimx_tile "img") (dimy_tile "img") -2)
      (end_image)
    )
  )
  ;; informacoes dos selecionados (cor do grafico)
  (setq k 0)
  (foreach h lista
    (setq linhas
      (append linhas
        (list
          (strcat "[" (nth (rem k 6) (HID:_NomesCores)) "]  " (HID:RotuloHid h)
                  "  |  tp " (rtos (cdr (assoc "TP" h)) 2 1) " min"
                  "  |  tb " (rtos (cdr (assoc "TB" h)) 2 1) " min"
                  "  |  V " (rtos (cdr (assoc "VOLUME" h)) 2 0) " m3")
        )
      )
    )
    (setq k (1+ k))
  )
  (start_list "info")
  (mapcar 'add_list (if linhas linhas (list "(nenhum hidrograma selecionado)")))
  (end_list)
  ;; tabela do primeiro selecionado
  (start_list "tab")
  (mapcar 'add_list (if primario (HID:_LinhasTabela primario) (list "")))
  (end_list)
  (set_tile "t_eixos"
    (if primario
      (strcat "Eixo X: tempo (min)   |   Eixo Y: vazao (m3/s)   |   Qp = "
              (rtos (cdr (assoc "QP" primario)) 2 3) " m3/s em t = "
              (rtos (cdr (assoc "TP" primario)) 2 1) " min"
              (if (cdr (assoc "NOTA" primario))
                (strcat "\n" (cdr (assoc "NOTA" primario))) ""))
      "Selecione um hidrograma na lista."
    )
  )
)

(defun HID:_Preenche (hids sel)
  (start_list "lst")
  (mapcar 'add_list (mapcar 'HID:RotuloHid hids))
  (end_list)
  (set_tile "lst" (HYDRO:Join (mapcar 'itoa sel) " "))
  (mode_tile "csv" (if sel 0 1))
  (mode_tile "excluir" (if sel 0 1))
  (HID:_Atualiza hids sel)
)

;; CSV do primeiro hidrograma selecionado (separador ";" e virgula decimal)
(defun HID:_ExportaCsv (en h / arq f p acum prev)
  (setq arq
    (getfiled
      "Salvar hidrograma (CSV)"
      (strcat (getvar "DWGPREFIX") "hidrograma_" (HYDRO:Handle en) ".csv")
      "csv" 1))
  (if arq
    (progn
      (setq f (open arq "w"))
      (if f
        (progn
          (write-line (strcat "Bacia (handle);" (HYDRO:Handle en)) f)
          (write-line (strcat "Metodo;" (cdr (assoc "METODO" h))) f)
          (write-line (strcat "Tipo de hidrograma;" (HID:_NomeTipo (cdr (assoc "TIPO" h)))) f)
          (write-line (strcat "TR (anos);" (HYDRO:CsvNum (cdr (assoc "TR" h)))) f)
          (write-line (strcat "Duracao da chuva (min);" (HYDRO:CsvNum (cdr (assoc "DUR" h)))) f)
          (write-line (strcat "Qp (m3/s);" (HYDRO:CsvNum (cdr (assoc "QP" h)))) f)
          (write-line (strcat "tp (min);" (HYDRO:CsvNum (cdr (assoc "TP" h)))) f)
          (write-line (strcat "tb (min);" (HYDRO:CsvNum (cdr (assoc "TB" h)))) f)
          (write-line (strcat "Volume (m3);" (HYDRO:CsvNum (cdr (assoc "VOLUME" h)))) f)
          (write-line "" f)
          (write-line "t (min);Q (m3/s);V acum. (m3)" f)
          (setq acum 0.0)
          (foreach p (cdr (assoc "PONTOS" h))
            (if prev
              (setq acum
                (+ acum (* (/ (+ (cdr prev) (cdr p)) 2.0) (- (car p) (car prev)) 60.0)))
            )
            (write-line
              (strcat (HYDRO:CsvNum (car p)) ";" (HYDRO:CsvNum (cdr p)) ";" (HYDRO:CsvNum acum))
              f)
            (setq prev p)
          )
          (close f)
          (alert (strcat "Arquivo salvo:\n" arq))
        )
        (alert "Nao foi possivel gravar o arquivo.")
      )
    )
  )
)

(defun HID:_Exclui (en dados hids sel / h r)
  (if sel
    (progn
      (setq h (nth (car sel) hids))
      (initget "Sim Nao")
      (setq r
        (getkword
          (strcat "\nExcluir o hidrograma [" (HID:RotuloHid h) "]? [Sim/Nao] <Nao>: ")))
      (if (equal r "Sim")
        (OBJ:GravarResultado en (cdr (assoc "CENARIO" h)) "HIDROGRAMA" nil)
      )
    )
  )
)

;; Abre o visualizador. idx = indice inicial selecionado (ou nil = o ultimo)
(defun HID:Visualizar (en idx / dcl dcl_id dados hids sel cod ok)
  (setq dcl (HYDRO:FindFile "hidrograma.dcl"))
  (cond
    ((not dcl)
      (alert "Arquivo hidrograma.dcl nao encontrado.")
      nil
    )
    ((< (setq dcl_id (load_dialog dcl)) 0)
      (alert "Nao foi possivel carregar hidrograma.dcl.")
      nil
    )
    (T
      (setq ok T)
      (setq sel (if idx (list idx) nil))
      (while ok
        (setq dados (BAC:Ler en))
        (setq hids (BAC:Hidrogramas dados))
        (cond
          ((not hids)
            (alert "Esta bacia nao tem hidrogramas. Use HIDROGRAMA.")
            (setq ok nil)
          )
          ((not (new_dialog "hidro_dialog" dcl_id))
            (alert "Nao foi possivel abrir o dialogo.")
            (setq ok nil)
          )
          (T
            ;; selecao valida (padrao: o ultimo hidrograma)
            (setq sel
              (vl-remove-if
                (function (lambda (i) (or (< i 0) (>= i (length hids)))))
                sel))
            (if (not sel) (setq sel (list (1- (length hids)))))
            (HID:_Preenche hids sel)
            (action_tile "lst"
              "(setq sel (HID:_ParseSel $value)) (HID:_Atualiza hids sel) (mode_tile \"csv\" (if sel 0 1)) (mode_tile \"excluir\" (if sel 0 1))")
            (action_tile "csv" "(done_dialog 5)")
            (action_tile "excluir" "(done_dialog 7)")
            (action_tile "cancel" "(done_dialog 0)")
            (setq cod (start_dialog))
            (cond
              ((= cod 5)
                (if sel (HID:_ExportaCsv en (nth (car sel) hids)))
              )
              ((= cod 7)
                (HID:_Exclui en dados hids sel)
                (setq sel nil)
              )
              (T (setq ok nil))
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
;; Seleciona um contorno que ja tem cadastro de bacia
(defun HID:_SelBacia (/ en)
  (setq en (BAC:_SelLinha "\nSelecione o CONTORNO da bacia: "))
  (cond
    ((not en) nil)
    ((not (BAC:Ler en))
      (alert "Esta entidade nao tem cadastro de bacia. Use BACIA primeiro.")
      nil
    )
    (T en)
  )
)

;; Padroes das perguntas do tipo, vindos do calculo (nao memorizados)
(defun HID:_Sobrescritas (ctx / qp tp out)
  (setq qp (cdr (assoc "QP" ctx)))
  (setq tp (cdr (assoc "TP" ctx)))
  (if qp (setq out (append out (list (cons "QP" qp) (cons "QPU" qp)))))
  (if tp (setq out (append out (list (cons "TP" tp) (cons "TPU" tp)))))
  out
)

(defun c:HIDROGRAMA (/ en dados calcs calc idxc ctx tid tipo params hid lista idx tipos h)
  (setq en (HID:_SelBacia))
  (if en
    (progn
      (setq dados (BAC:Ler en))
      (setq calcs (BAC:Vazao dados))
      (setq tipos (HYDRO:RegList "hidrograma-tipo"))
      (cond
        ((not calcs)
          (alert "Esta bacia ainda nao tem calculo de vazao. Use BACIA primeiro.")
        )
        ((not tipos)
          (alert "Nenhum tipo de hidrograma cadastrado.")
        )
        (T
          ;; cenario: um por calculo; com varios, escolhe (padrao: o cenario em uso, se houver)
          (setq idxc
            (if (= (length calcs) 1)
              0
              (HYDRO:Escolher "Cenarios da bacia:"
                              (mapcar 'BAC:RotuloVazao calcs)
                              (1- (length calcs)))))
          (setq calc (nth idxc calcs))
          (setq ctx (BAC:Contexto dados calc))
          ;; o tipo e o definido na bacia (HIDROGRAMA-TIPO; troque com BACIAEDITA)
          (setq tid (HID:TipoDaBacia en))
          (setq tipo (HYDRO:RegGet "hidrograma-tipo" tid))
          (princ
            (strcat "\nCenario " (cdr (assoc "CENARIO" calc)) "; tipo de hidrograma da bacia: "
                    (cdr (assoc "NOME" tipo)) " (troque com BACIAEDITA)."))
          (setq params
            (if (HYDRO:CalcAuto)
              (HYDRO:ParamsPadrao (cdr (assoc "PARAMS" tipo))
                                  (strcat "HYDRO.HID." tid ".")
                                  (HID:_Sobrescritas ctx))
              (HYDRO:AskParams (cdr (assoc "PARAMS" tipo))
                               (strcat "HYDRO.HID." tid ".")
                               (HID:_Sobrescritas ctx))))
          (setq hid (HID:Gerar tid ctx params))
          (if (assoc "ERRO" hid)
            (alert (strcat "Erro: " (cdr (assoc "ERRO" hid))))
            (progn
              (HID:Armazenar en (cdr (assoc "CENARIO" calc)) hid)
              (HYDRO:Emit "hidrograma.gerado"
                (list
                  (cons "BACIA" en)
                  (cons "CENARIO" (cdr (assoc "CENARIO" calc)))
                  (cons "TIPO" tid)
                  (cons "METODO" (cdr (assoc "METODO" hid)))
                  (cons "TR" (cdr (assoc "TR" hid)))
                  (cons "DUR" (cdr (assoc "DUR" hid)))
                  (cons "QP" (cdr (assoc "QP" hid)))
                  (cons "TP" (cdr (assoc "TP" hid)))
                  (cons "TB" (cdr (assoc "TB" hid)))
                  (cons "VOLUME" (cdr (assoc "VOLUME" hid)))
                  (cons "PONTOS" (cdr (assoc "PONTOS" hid)))))
              (princ "\nHidrograma gravado no cenario da bacia.")
              ;; posicao do hidrograma deste cenario na lista do visualizador
              (setq lista (BAC:Hidrogramas (BAC:Ler en)))
              (setq idx 0)
              (foreach h lista
                (if (equal (cdr (assoc "CENARIO" h)) (cdr (assoc "CENARIO" calc)))
                  (setq idx (vl-position h lista))
                )
              )
              (HID:Visualizar en idx)
            )
          )
        )
      )
    )
  )
  (princ)
)

(defun c:HIDROGRAMAVER (/ en)
  (setq en (HID:_SelBacia))
  (if en (HID:Visualizar en nil))
  (princ)
)
(HYDRO:Provide "hidrograma-view" "1.0")
(princ)
