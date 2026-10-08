;;; ============================================================
;;; models/objetos_tipos.lsp - MODELOS BASICOS DE OBJETO HIDRAULICO (OTP:)
;;;
;;; Cada tipo e apenas um CADASTRO no catalogo "objeto-hidraulico" (ver
;;; plugins/objetos.lsp): para um tipo novo, crie outro arquivo em models/ com
;;; outro cadastro; nada daqui muda.
;;;
;;; Tipos incluidos
;;;   trecho      linha/polilinha de rede: diametro e rugosidade
;;;   estrutura   poco de visita, boca de lobo, caixa, ponto de descarga
;;;               (estrutura do Civil 3D, bloco, circulo ou ponto)
;;;   tubo-c3d    tubo (Pipe) do Civil 3D
;;; A bacia esta em models/bacia.lsp e a sarjeta em models/sarjeta.lsp.
;;;
;;; Nomes DXF dos objetos do Civil 3D ("AECC_PIPE", "AECC_STRUCTURE") devem
;;; ser conferidos no seu desenho: (cdr (assoc 0 (entget (car (entsel))))).
;;; ============================================================
(vl-load-com)

(OBJ:RegistrarTipo
  "trecho"
  "Trecho de rede"
  "Linha ou polilinha usada como trecho de rede (galeria, canal, tubo)."
  '("LINE" "LWPOLYLINE" "POLYLINE" "SPLINE")
  (list (list "DIAM" "Diametro" 0.6 "m")
        (list "N" "Rugosidade de Manning" 0.013 ""))
  T
  T
  nil
)

(OBJ:RegistrarTipo
  "estrutura"
  "Estrutura"
  "Poco de visita, boca de lobo, caixa ou ponto de descarga."
  '("AECC_STRUCTURE" "INSERT" "CIRCLE" "POINT")
  (list (list "FUNCAO" "Funcao" "poco-de-visita" "" "opcoes"
              '("poco-de-visita" "boca-de-lobo" "caixa" "ponto-de-descarga")))
  T
  T
  nil
)

(OBJ:RegistrarTipo
  "tubo-c3d"
  "Tubo (Civil 3D)"
  "Tubo (Pipe) de uma rede do Civil 3D."
  '("AECC_PIPE")
  (list (list "N" "Rugosidade de Manning" 0.013 ""))
  T
  T
  nil
)

(HYDRO:Provide "objetos-tipos" "1.0")
(princ)
