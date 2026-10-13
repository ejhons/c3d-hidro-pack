;;; ============================================================
;;; registry/captacao.lsp - METODOS DE CAPTACAO DA BOCA DE LOBO (CAP:)
;;;
;;; Catalogo "metodo-captacao": cada metodo diz quanto UMA ou VARIAS bocas de lobo captam.
;;;   (HYDRO:RegAdd "metodo-captacao" id (list ("NOME" . txt) ("DESC" . txt) ("FN" . 'funcao)))
;;;   (fn ctx) -> (("QCAP" . m3/s capacidade TOTAL) ["NOTA" . texto]) ou (("ERRO" . msg))
;;;   ctx = ("Q" . vazao afluente m3/s) ("QTD" . bocas) ("LAMINA" . m ou nil) ("TIPO" . tipo do catalogo)
;;;   Os parametros do metodo ficam como chaves a mais no TIPO (campos da classe boca-lobo).
;;;
;;; Incluido:
;;;   unitaria   Qcap = QTD x capacidade unitaria do tipo (proporcional; nao usa a lamina)
;;;
;;; PARA UM METODO POR EQUACAO (vertedouro, orificio): crie outro arquivo (ex.:
;;; registry/captacao_vertedouro.lsp), cadastre o metodo aqui no catalogo e inclua o arquivo em
;;; HYDRO:Manifest; use ctx "LAMINA". Nada deste arquivo nem do model muda. Equacoes e faixas de
;;; validade vem da norma adotada no projeto (nao ha formula embutida).
;;; ============================================================
(vl-load-com)

;; Metodo "unitaria": capacidade total = quantidade de bocas x capacidade unitaria do tipo
(defun CAP:Unitaria (ctx / tipo cap qtd)
  (setq tipo (cdr (assoc "TIPO" ctx)))
  (setq cap (cdr (assoc "cap" (cdr tipo))))
  (setq qtd (cdr (assoc "QTD" ctx)))
  (if (and cap qtd (> cap 0.0))
    (list (cons "QCAP" (* qtd cap)))
    (list (cons "ERRO" "Capacidade unitaria nao definida: edite o tipo (EDITATIPOESTRUTURA)."))
  )
)

(HYDRO:RegAdd "metodo-captacao" "unitaria"
  (list (cons "NOME" "Capacidade unitaria")
        (cons "DESC" "Q captavel = quantidade de bocas x capacidade unitaria do tipo (proporcional)")
        (cons "FN" 'CAP:Unitaria)))

(HYDRO:Provide "captacao" "1.0")
(princ)
