;;; ============================================================
;;; views/bacia_view.lsp - ETIQUETAGEM DA BACIA NO DESENHO (BAC:)
;;;
;;; So o que DESENHA texto da bacia. Os comandos de linha de comando (BACIACAD,
;;; BACIA, BACIAS, BACIAINFO), as perguntas e o toString (BAC:ToString) estao em
;;; plugins/models/bacia.lsp, para o objeto funcionar com um unico .lsp.
;;;
;;; COMANDOS
;;;   CRIARBACIARESULTADO   calcula e insere o resultado como texto no desenho
;;;   TEXTOBACIA            insere como texto um calculo ja cadastrado
;;; Depende de "bacia".
;;; ============================================================
(vl-load-com)

;; Insere o texto no desenho (mesma altura/rotacao do texto das sarjetas)
(defun BAC:_InsereTexto (linhas / pt)
  (setq pt (getpoint "\nSelecione o local de insercao do texto: "))
  (if pt
    (HYDRO:Mtext
      pt
      (HYDRO:Join linhas "\\P")
      (HYDRO:Get "HYDRO.TEXT.HEIGHT" 1.8)
      (HYDRO:Get "HYDRO.TEXT.ROTATION" 0.0))
    nil
  )
)

(defun c:CRIARBACIARESULTADO (/ r)
  (setq r (BAC:_FluxoCalculo))
  (if r
    (progn
      (BAC:_Mostra (BAC:_Resumo (car r) (cdr r)))
      (BAC:_InsereTexto
        (BAC:LinhasTexto (BAC:Ler (car r)) (HYDRO:Handle (car r)) (list (cdr r))))
    )
  )
  (princ)
)

;; Insere como texto os calculos ja cadastrados da bacia
(defun BAC:TextoInterativo (en / dados)
  (setq dados (BAC:Ler en))
  (BAC:_InsereTexto
    (BAC:LinhasTexto dados (HYDRO:Handle en) (BAC:_EscolheCalculos dados)))
)

(defun c:TEXTOBACIA (/ en)
  (setq en (BAC:_SelBaciaCad))
  (if en (BAC:TextoInterativo en))
  (princ)
)

(HYDRO:Provide "bacia-view" "1.0")
(princ)
