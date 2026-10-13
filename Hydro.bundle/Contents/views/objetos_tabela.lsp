;;; ============================================================
;;; objetos_tabela.lsp - TABELA DE OBJETOS E LIGACOES (OBT:)
;;;
;;; Comando:  LIGACOES   (dialogo em resources/dcl/ligacoes.dcl)
;;;
;;; Lista todos os objetos hidraulicos do desenho (bacias, sarjetas,
;;; trechos, estruturas...): nome, tipo, handle, DESTINO (para onde
;;; descarrega), numero de AFLUENTES e area contribuinte a montante. O painel
;;; de detalhes mostra o resumo do objeto, a cadeia a jusante e a arvore de
;;; afluentes (quem descarrega nele, e quem descarrega nesses...).
;;;
;;; Botoes: Ir para | Ligar... | Desligar | Editar | Calcular | Validar
;;;         Exportar CSV | Reindexar
;;; Tudo vem do catalogo de tipos: um tipo novo aparece aqui sem mudancas.
;;; ============================================================
(vl-load-com)

(defun OBT:_Trunc (s n)
  (if (> (strlen s) n)
    (strcat (substr s 1 (- n 2)) "..")
    s
  )
)

;;; ------------------------------------------------------------
;;; REGISTROS
;;; ------------------------------------------------------------
(defun OBT:_Detalhe (en / out dest res r)
  (setq out (OBJ:Resumo en))
  (setq out
    (append out
      (list "" "JUSANTE" (strcat "  " (LIG:LinhaJusante en)) "" "MONTANTE (afluentes, derivados)")))
  (setq res (LIG:LinhasArvore en))
  (if res
    (foreach r res (setq out (append out (list (strcat "  " r)))))
    (setq out (append out (list "  (nenhum afluente)")))
  )
  out
)

;; colunas do CSV com os ATRIB do objeto: ("Atrib: <rotulo>" . valor)
(defun OBT:_ColunasAtrib (en / id out p)
  (setq id (OBJ:TipoDe en))
  (foreach p (OBJ:AtribDe en)
    (setq out
      (append out
        (list (cons (strcat "Atrib: " (OBJ:_RotuloParam id (car p)))
                    (if (numberp (cdr p)) (HYDRO:CsvNum (cdr p)) (OBJ:_FmtVal (cdr p)))))))
  )
  out
)

(defun OBT:_Registro (en / destino afl area)
  (setq destino (LIG:Destino en))
  (setq afl (length (LIG:Afluentes en)))
  (setq area (LIG:AreaMontante en))
  (list
    (cons "EN" en)
    (cons "LINHA"
      (strcat
        (OBT:_Trunc (OBJ:Nome en) 14) "\t"
        (OBT:_Trunc (OBJ:_NomeTipo (OBJ:TipoDe en)) 12) "\t"
        (HYDRO:Handle en) "\t"
        (if destino (OBT:_Trunc (OBJ:Nome destino) 14) "-") "\t"
        (itoa afl) "\t"
        (if (> area 0.0) (rtos (/ area 10000.0) 2 3) "-")
      )
    )
    (cons "DETALHE" (OBT:_Detalhe en))
    (cons "CSV"
      (OBJ:_Limpa
        (append
        (list
          (cons "Nome" (OBJ:Nome en))
          (cons "Tipo" (OBJ:_NomeTipo (OBJ:TipoDe en)))
          (cons "Handle" (HYDRO:Handle en))
          (cons "Destino" (if destino (OBJ:Nome destino) nil))
          (cons "Afluentes" (itoa afl))
          (cons "Afluentes (nomes)"
                (if (> afl 0)
                  (HYDRO:Join (mapcar 'OBJ:Nome (LIG:Afluentes en)) " | ")
                  nil))
          (cons "Area a montante (ha)"
                (if (> area 0.0) (HYDRO:CsvNum (/ area 10000.0)) nil))
        )
        (OBT:_ColunasAtrib en)
        )
      )
    )
  )
)

(defun OBT:_Filtra (rows filtro / out r)
  (if (= filtro "")
    rows
    (progn
      (foreach r rows
        (if (vl-string-search (strcase filtro) (strcase (cdr (assoc "LINHA" r))))
          (setq out (cons r out))
        )
      )
      (reverse out)
    )
  )
)

(defun OBT:Rows (filtro / rows en)
  (foreach en (OBJ:Listar)
    (setq rows (append rows (list (OBT:_Registro en))))
  )
  (OBT:_Filtra rows filtro)
)

;;; ------------------------------------------------------------
;;; CSV
;;; ------------------------------------------------------------
(defun OBT:_Celula (v)
  (cond
    ((null v) "")
    ((or (vl-string-search ";" v) (vl-string-search "\"" v))
      (strcat "\"" (vl-string-subst "\"\"" "\"" v) "\"")
    )
    (T v)
  )
)

(defun OBT:_ExportaCsv (rows / arq f cols l c)
  (if (not rows)
    (alert "Nao ha objetos para exportar.")
    (progn
      (foreach l rows
        (foreach c (cdr (assoc "CSV" l))
          (if (not (member (car c) cols))
            (setq cols (append cols (list (car c))))
          )
        )
      )
      (setq arq
        (getfiled "Salvar tabela (CSV)"
          (strcat (getvar "DWGPREFIX") "ligacoes.csv") "csv" 1))
      (if arq
        (progn
          (setq f (open arq "w"))
          (if f
            (progn
              (write-line (HYDRO:Join (mapcar 'OBT:_Celula cols) ";") f)
              (foreach l rows
                (write-line
                  (HYDRO:Join
                    (mapcar
                      (function
                        (lambda (col) (OBT:_Celula (cdr (assoc col (cdr (assoc "CSV" l))))))
                      )
                      cols
                    )
                    ";"
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
  )
)

;;; ------------------------------------------------------------
;;; DIALOGO
;;; ------------------------------------------------------------
(defun OBT:_Mostra (rows sel / r)
  (setq r (if rows (nth sel rows) nil))
  (start_list "det")
  (mapcar 'add_list
    (if r (cdr (assoc "DETALHE" r)) (list "(nenhum objeto selecionado)")))
  (end_list)
)

(defun OBT:_Preenche (rows sel filtro / k)
  (set_tile "filtro" filtro)
  (set_tile "titulo" (strcat (itoa (length rows)) " objeto(s)"))
  (set_tile "t_cols"
    "Nome | Tipo | Handle | Destino | Afl. | Area a montante (ha)")
  (start_list "lst")
  (mapcar 'add_list (mapcar (function (lambda (r) (cdr (assoc "LINHA" r)))) rows))
  (end_list)
  (if rows (set_tile "lst" (itoa sel)))
  (OBT:_Mostra rows sel)
  (foreach k '("ir" "ligar" "desligar" "editar" "calcular" "csv")
    (mode_tile k (if rows 0 1))
  )
)

(defun OBT:Abrir (/ dcl dcl_id filtro sel rows cod ok r en n)
  (setq dcl (HYDRO:FindFile "ligacoes.dcl"))
  (cond
    ((not dcl)
      (alert "Arquivo ligacoes.dcl nao encontrado.")
      nil
    )
    ((< (setq dcl_id (load_dialog dcl)) 0)
      (alert "Nao foi possivel carregar ligacoes.dcl.")
      nil
    )
    (T
      (setq filtro "")
      (setq sel 0)
      (setq ok T)
      (while ok
        (setq rows (OBT:Rows filtro))
        (if (>= sel (length rows)) (setq sel 0))
        (if (not (new_dialog "ligacoes_dialog" dcl_id))
          (progn
            (alert "Nao foi possivel abrir o dialogo.")
            (setq ok nil)
          )
          (progn
            (OBT:_Preenche rows sel filtro)
            ;; os callbacks alteram as variaveis locais desta funcao
            (action_tile "lst" "(setq sel (atoi $value)) (OBT:_Mostra rows sel)")
            (action_tile "filtrar" "(setq filtro (get_tile \"filtro\")) (done_dialog 12)")
            (action_tile "ir" "(done_dialog 3)")
            (action_tile "ligar" "(done_dialog 4)")
            (action_tile "desligar" "(done_dialog 5)")
            (action_tile "editar" "(done_dialog 6)")
            (action_tile "calcular" "(done_dialog 7)")
            (action_tile "validar" "(done_dialog 8)")
            (action_tile "csv" "(done_dialog 9)")
            (action_tile "reindexar" "(done_dialog 10)")
            (action_tile "cancel" "(done_dialog 0)")
            (setq cod (start_dialog))
            (setq r (if rows (nth sel rows) nil))
            (setq en (if r (cdr (assoc "EN" r)) nil))
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
              ((= cod 4) (if en (LIG:LigarInterativo (list en))))
              ((= cod 5)
                (if en
                  (progn
                    (setq n (LIG:Desconectar en))
                    (princ (strcat "\n" (itoa n) " ligacao(oes) removida(s)."))
                  )
                )
              )
              ((= cod 6) (if en (OBJ:Editar en)))
              ((= cod 7) (if en (LIG:CalcularInterativo en)))
              ((= cod 8) (c:VALIDARLIGACOES))
              ((= cod 9) (OBT:_ExportaCsv rows))
              ((= cod 10)
                (princ
                  (strcat "\n[HYDRO] Indices reconstruidos: "
                          (itoa (OBJ:Reindexar)) " objeto(s)."))
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

(defun c:LIGACOES ()
  (OBT:Abrir)
  (princ)
)

(HYDRO:Provide "objetos-tabela" "1.0")
(princ)
