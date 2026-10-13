;;; ============================================================
;;; registry/dissipacao.lsp - METODOS DE DISSIPACAO DE ENERGIA (DIS:)
;;;
;;; Catalogo "metodo-dissipacao": cada metodo diz o que acontece num dissipador de energia.
;;;   (HYDRO:RegAdd "metodo-dissipacao" id
;;;      (list ("NOME" . txt) ("DESC" . txt)
;;;            ("PARAMS" . defs)     campos que o metodo acrescenta ao TIPO (chave rotulo padrao
;;;                                  unidade [tipo [opcoes]]); perguntados pelo catalogo de tipos
;;;            ("VALIDA" . fn)       (fn valores) -> T se os valores (alist) servem; opcional
;;;            ("FN" . 'funcao)))
;;;   (fn ctx) -> alist com, todos opcionais:
;;;        ("EOUT" . m)     energia especifica de SAIDA
;;;        ("EIN" . m)      energia de ENTRADA do metodo (se ele a redefine; senao vale y + V^2/2g)
;;;        ("GRUPOS" . lista de (grupo . campos))   resultados proprios do metodo (gravados no cenario)
;;;        ("AVISOS" . lista de textos)
;;;      ou (("ERRO" . msg))
;;;   ctx = ("Q" . m3/s) ("Y" . m lamina de montante) ("V" . m/s) ("FR" . Froude ou nil)
;;;         ("EIN" . m = Y + V^2/(2 g) ou nil) ("TIPO" . tipo do catalogo, com os PARAMS do metodo)
;;;
;;; Incluidos (um arquivo cada):
;;;   informado       (este arquivo) a EFICIENCIA vem do projetista: EOUT = (1 - ef) x EIN
;;;   usbr            registry/dissipacao_usbr.lsp        bacias por ressalto, tipos I a IV
;;;   enrocamento     registry/dissipacao_enrocamento.lsp bacia em enrocamento (HEC-14)
;;; Referencia: docs/referencia-dissipadores-siscooh.md. METODO NOVO = arquivo novo + linha no
;;; HYDRO:Manifest; nada daqui nem do model muda.
;;; ============================================================
(vl-load-com)

;; (puro) valores validos do metodo "informado": eficiencia numero em [0, 1]
(defun DIS:_ValidaInformado (valores / ef)
  (setq ef (cdr (assoc "eficiencia" valores)))
  (if (and ef (numberp ef) (>= ef 0.0) (<= ef 1.0)) T nil)
)

;; Metodo "informado": energia de saida = (1 - eficiencia) x energia de entrada
(defun DIS:Informado (ctx / tipo ef ein)
  (setq tipo (cdr (assoc "TIPO" ctx)))
  (setq ef (cdr (assoc "eficiencia" (cdr tipo))))
  (setq ein (cdr (assoc "EIN" ctx)))
  (cond
    ((not ein)
      (list (cons "ERRO"
        "O metodo 'informado' precisa de montante com altura da lamina e velocidade (tubo ou sarjeta calculados no mesmo cenario).")))
    ((and ef (>= ef 0.0) (<= ef 1.0))
      (list (cons "EOUT" (* (- 1.0 ef) ein))))
    (T (list (cons "ERRO" "Eficiencia de dissipacao invalida (0 a 1): edite o tipo (EDITATIPOESTRUTURA).")))
  )
)

(HYDRO:RegAdd "metodo-dissipacao" "informado"
  (list (cons "NOME" "Eficiencia informada")
        (cons "DESC" "Energia de saida = (1 - eficiencia informada) x energia de entrada")
        (cons "PARAMS"
          (list (list "eficiencia" "Eficiencia de dissipacao informada (0 a 1)" 0.0 "")))
        (cons "VALIDA" 'DIS:_ValidaInformado)
        (cons "FN" 'DIS:Informado)))

(HYDRO:Provide "dissipacao" "2.0")
(princ)
