;;; ============================================================
;;; bacia_tabela.lsp - TABELA DE BACIAS (BTB:)
;;;
;;; Comando:  BACIATABELA   (dialogo em resources/dcl/bacia_tabela.dcl)
;;;
;;; Mostra TODAS as bacias cadastradas no desenho (cadastro do plugin
;;; bacia): nome, handle, area, comprimento, declividade, tc e metodo do
;;; tc, numero de calculos e de hidrogramas e a maior vazao de pico. Ao
;;; selecionar uma bacia, o painel de detalhes mostra o cadastro, os
;;; calculos de vazao e os hidrogramas.
;;;
;;; Botoes: Ir para (zoom + selecao) | Hidrogramas | Texto | Editar cadastro
;;;         Exportar CSV (bacias ou calculos) | Remover cadastro | Reindexar
;;; O filtro procura em qualquer coluna da tabela.
;;;
;;; Depende de "bacia". Usa "hidrograma" so para abrir o visualizador de
;;; hidrogramas (botao desabilitado de fato se o plugin nao existir).
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; UTILITARIOS
;;; ------------------------------------------------------------
(defun BTB:_Trunc (s n)
  (if (> (strlen s) n)
    (strcat (substr s 1 (- n 2)) "..")
    s
  )
)

(defun BTB:_Num (x casas)
  (if x (rtos x 2 casas) "-")
)

;;; ------------------------------------------------------------
;;; REGISTROS DA TABELA
;;; ------------------------------------------------------------
(defun BTB:_RotuloHid (hid)
  (if (HYDRO:Has "hidrograma")
    (HID:RotuloHid hid)
    (strcat (HYDRO:Val "TIPO" hid) "  |  TR " (HYDRO:FmtReal (HYDRO:Val "TR" hid))
            "  |  Qp " (rtos (HYDRO:Val "QP" hid) 2 3))
  )
)

;; Linhas do painel de detalhes
(defun BTB:_Detalhe (dados h / out c)
  (setq out (BAC:LinhasCadastro dados h))
  (setq out
    (append out
      (list (strcat "Talvegue (handle): "
                    (if (BAC:Talvegue dados) (BAC:Talvegue dados) "-"))
            (strcat "Desnivel do talvegue: "
                    (BTB:_Num (HYDRO:Val "DESNIVEL" (BAC:Caract dados)) 2) " m")
            ""
            (strcat "VAZOES CALCULADAS (" (itoa (length (BAC:Vazao dados))) ")"))))
  (foreach c (BAC:Vazao dados)
    (setq out (append out (list (strcat "  " (BAC:RotuloVazao c)))))
  )
  (setq out
    (append out
      (list "" (strcat "HIDROGRAMAS (" (itoa (length (BAC:Hidrogramas dados))) ")"))))
  (foreach c (BAC:Hidrogramas dados)
    (setq out (append out (list (strcat "  " (BTB:_RotuloHid c)))))
  )
  out
)

;; Linhas de CSV (alists) dos calculos da bacia
(defun BTB:_CsvCalculos (dados h / out c res)
  (foreach c (BAC:Vazao dados)
    (setq res c)
    (setq out
      (append out
        (list
          (OBJ:Limpa
            (list
              (cons "Nome" (BAC:_NomeExib dados h))
              (cons "Handle" h)
              (cons "Metodo" (BAC:_NomeMetodo (HYDRO:Val "METODO" c)))
              (cons "TR (anos)" (HYDRO:Val "TR" c))
              (cons "Duracao (min)" (HYDRO:Val "DUR" c))
              (cons "tc (min)" (HYDRO:Val "TC" c))
              (cons "Qp (m3/s)" (HYDRO:Val "QP" res))
              (cons "i (mm/h)" (HYDRO:Val "I" res))
              (cons "P (mm)" (HYDRO:Val "P" res))
              (cons "Pe (mm)" (HYDRO:Val "PE" res))
              (cons "Volume (m3)" (HYDRO:Val "VOLUME" res))
            )
          )
        )
      )
    )
  )
  out
)

;; Registro de uma bacia (en pode ser nil nos testes; h = handle)
(defun BTB:_Registro (en dados h / c atrib nome area ha comp decl tc origem nc nh qpm)
  (setq c (BAC:Caract dados))
  (setq atrib (BAC:Atrib dados))
  (setq nome (BAC:_NomeExib dados h))
  (setq area (HYDRO:Val "AREA" c))
  (setq ha (if area (/ area 10000.0) nil))
  (setq comp (HYDRO:Val "COMP" c))
  (setq decl (HYDRO:Val "DECL" c))
  (setq tc (HYDRO:Val "MIN" (BAC:Tc dados)))
  (setq origem (BAC:_NomeTc (HYDRO:Val "ORIGEM" (BAC:Tc dados))))
  (setq nc (length (BAC:Vazao dados)))
  (setq nh (length (BAC:Hidrogramas dados)))
  (setq qpm (BAC:_MaxQp dados))
  (list
    (cons "EN" en)
    (cons "HANDLE" h)
    (cons "LINHA"
      (strcat
        (BTB:_Trunc nome 12) "\t"
        h "\t"
        (BTB:_Num ha 3) "\t"
        (BTB:_Num comp 1) "\t"
        (BTB:_Num decl 4) "\t"
        (BTB:_Num tc 2) "\t"
        (BTB:_Trunc origem 14) "\t"
        (itoa nc) "\t"
        (itoa nh) "\t"
        (if (> qpm 0.0) (rtos qpm 2 3) "-")
      )
    )
    (cons "DETALHE" (BTB:_Detalhe dados h))
    (cons "CSV"
      (OBJ:Limpa
        (list
          (cons "Nome" nome)
          (cons "Handle" h)
          (cons "Area (ha)" ha)
          (cons "L (m)" comp)
          (cons "Desnivel (m)" (HYDRO:Val "DESNIVEL" c))
          (cons "S (m/m)" decl)
          (cons "tc (min)" tc)
          (cons "Metodo tc" origem)
          (cons "C" (HYDRO:Val "C" atrib))
          (cons "CN" (HYDRO:Val "CN" atrib))
          (cons "Calculos" nc)
          (cons "Hidrogramas" nh)
          (cons "Qp max (m3/s)" (if (> qpm 0.0) qpm nil))
        )
      )
    )
    (cons "CSV-CALC" (BTB:_CsvCalculos dados h))
  )
)

(defun BTB:_Filtra (rows filtro / out r)
  (if (= filtro "")
    rows
    (progn
      (foreach r rows
        (if (vl-string-search (strcase filtro) (strcase (HYDRO:Val "LINHA" r)))
          (setq out (cons r out))
        )
      )
      (reverse out)
    )
  )
)

;; Todas as bacias do desenho (reindexa se o indice estiver vazio)
(defun BTB:Rows (filtro / lista rows en)
  (setq lista (OBJ:ListaTipo "bacia"))
  (if (not lista)
    (progn
      (OBJ:ReindexaTipo "bacia")
      (setq lista (OBJ:ListaTipo "bacia"))
    )
  )
  (foreach en lista
    (setq rows
      (append rows
        (list (BTB:_Registro en (BAC:Ler en) (HYDRO:Handle en)))))
  )
  (BTB:_Filtra rows filtro)
)

;;; ------------------------------------------------------------
;;; CSV
;;; ------------------------------------------------------------
(defun BTB:_Celula (v)
  (cond
    ((null v) "")
    ((or (= (type v) 'REAL) (= (type v) 'INT)) (HYDRO:CsvNum v))
    ((or (vl-string-search ";" v) (vl-string-search "\"" v))
      (strcat "\"" (vl-string-subst "\"\"" "\"" v) "\"")
    )
    (T v)
  )
)

;; colunas = uniao das colunas dos registros, na ordem em que aparecem
(defun BTB:_Colunas (linhas / cols l c)
  (foreach l linhas
    (foreach c l
      (if (not (member (car c) cols))
        (setq cols (append cols (list (car c))))
      )
    )
  )
  cols
)

(defun BTB:_GravaCsv (arq linhas / f cols l)
  (setq cols (BTB:_Colunas linhas))
  (setq f (open arq "w"))
  (if f
    (progn
      (write-line (HYDRO:Join (mapcar 'BTB:_Celula cols) ";") f)
      (foreach l linhas
        (write-line
          (HYDRO:Join
            (mapcar
              (function (lambda (col) (BTB:_Celula (cdr (assoc col l)))))
              cols
            )
            ";"
          )
          f
        )
      )
      (close f)
      T
    )
    nil
  )
)

(defun BTB:_ExportaCsv (rows / op arq linhas r)
  (if (not rows)
    (alert "Nao ha bacias para exportar.")
    (progn
      (initget "Bacias Calculos")
      (setq op (getkword "\nExportar [Bacias/Calculos] <Bacias>: "))
      (foreach r rows
        (setq linhas
          (append linhas
            (if (equal op "Calculos")
              (HYDRO:Val "CSV-CALC" r)
              (list (HYDRO:Val "CSV" r)))))
      )
      (if (not linhas)
        (alert "Nao ha dados para exportar (nenhum calculo cadastrado).")
        (progn
          (setq arq
            (getfiled "Salvar tabela (CSV)"
              (strcat (getvar "DWGPREFIX")
                      (if (equal op "Calculos") "calculos_bacias" "bacias") ".csv")
              "csv" 1))
          (if arq
            (if (BTB:_GravaCsv arq linhas)
              (alert (strcat "Arquivo salvo:\n" arq))
              (alert "Nao foi possivel gravar o arquivo.")
            )
          )
        )
      )
    )
  )
)

;;; ------------------------------------------------------------
;;; DIALOGO
;;; ------------------------------------------------------------
(defun BTB:_Mostra (rows sel / r)
  (setq r (if rows (nth sel rows) nil))
  (start_list "det")
  (mapcar 'add_list (if r (HYDRO:Val "DETALHE" r) (list "(nenhuma bacia selecionada)")))
  (end_list)
)

(defun BTB:_Preenche (rows sel filtro)
  (set_tile "filtro" filtro)
  (set_tile "titulo" (strcat (itoa (length rows)) " bacia(s)"))
  (set_tile "t_cols"
    "Nome | Handle | Area (ha) | L (m) | S (m/m) | tc (min) | Metodo tc | Calc. | Hid. | Qp max (m3/s)")
  (start_list "lst")
  (mapcar 'add_list (mapcar (function (lambda (r) (HYDRO:Val "LINHA" r))) rows))
  (end_list)
  (if rows (set_tile "lst" (itoa sel)))
  (BTB:_Mostra rows sel)
  (mode_tile "ir" (if rows 0 1))
  (mode_tile "hid" (if (and rows (HYDRO:Has "hidrograma-view")) 0 1))
  (mode_tile "texto" (if rows 0 1))
  (mode_tile "editar" (if rows 0 1))
  (mode_tile "csv" (if rows 0 1))
  (mode_tile "remover" (if rows 0 1))
)

(defun BTB:_Remove (en / dados r)
  (setq dados (BAC:Ler en))
  (initget "Sim Nao")
  (setq r
    (getkword
      (strcat "\nRemover o cadastro da bacia " (BAC:_NomeExib dados (HYDRO:Handle en))
              " (calculos e hidrogramas serao perdidos)? [Sim/Nao] <Nao>: ")))
  (if (equal r "Sim")
    (OBJ:Remover en)
  )
)

(defun BTB:Abrir (/ dcl dcl_id filtro sel rows cod ok r en)
  (setq dcl (HYDRO:FindFile "bacia_tabela.dcl"))
  (cond
    ((not dcl)
      (alert "Arquivo bacia_tabela.dcl nao encontrado. Use BACIAS para ver em texto.")
      nil
    )
    ((< (setq dcl_id (load_dialog dcl)) 0)
      (alert "Nao foi possivel carregar bacia_tabela.dcl.")
      nil
    )
    (T
      (setq filtro "")
      (setq sel 0)
      (setq ok T)
      (while ok
        (setq rows (BTB:Rows filtro))
        (if (>= sel (length rows)) (setq sel 0))
        (if (not (new_dialog "bacias_dialog" dcl_id))
          (progn
            (alert "Nao foi possivel abrir o dialogo.")
            (setq ok nil)
          )
          (progn
            (BTB:_Preenche rows sel filtro)
            ;; os callbacks alteram as variaveis locais desta funcao
            (action_tile "lst" "(setq sel (atoi $value)) (BTB:_Mostra rows sel)")
            (action_tile "filtrar" "(setq filtro (get_tile \"filtro\")) (done_dialog 12)")
            (action_tile "ir" "(done_dialog 3)")
            (action_tile "hid" "(done_dialog 4)")
            (action_tile "texto" "(done_dialog 5)")
            (action_tile "editar" "(done_dialog 6)")
            (action_tile "csv" "(done_dialog 7)")
            (action_tile "remover" "(done_dialog 8)")
            (action_tile "reindexar" "(done_dialog 9)")
            (action_tile "cancel" "(done_dialog 0)")
            (setq cod (start_dialog))
            (setq r (if rows (nth sel rows) nil))
            (setq en (if r (HYDRO:Val "EN" r) nil))
            (cond
              ((= cod 12) nil)
              ((= cod 3)
                (if en
                  (progn
                    (HYDRO:ZoomEnt en)
                    (sssetfirst nil (ssadd en (ssadd)))
                  )
                )
                (setq ok nil)
              )
              ((= cod 4) (if en (HID:Visualizar en nil)))
              ((= cod 5) (if en (BAC:TextoInterativo en)))
              ((= cod 6) (if en (OBJ:CadastroInterativoTipo en "bacia")))
              ((= cod 7) (BTB:_ExportaCsv rows))
              ((= cod 8) (if en (BTB:_Remove en)))
              ((= cod 9)
                (princ (strcat "\n[BACIA] Indice reconstruido: "
                               (itoa (OBJ:ReindexaTipo "bacia")) " bacia(s)."))
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

(defun c:BACIATABELA ()
  (BTB:Abrir)
  (princ)
)

(HYDRO:Provide "bacia-tabela" "1.0")
(princ)
