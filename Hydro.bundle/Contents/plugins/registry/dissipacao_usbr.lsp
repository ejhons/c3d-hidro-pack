;;; ============================================================
;;; registry/dissipacao_usbr.lsp - BACIAS POR RESSALTO HIDRAULICO, USBR (DUS:)
;;;
;;; Metodo "usbr" do catalogo "metodo-dissipacao". Referencia: docs/referencia-dissipadores-siscooh.md,
;;; secao 2 (SisCCoH 1.1, secao 4.3; Peterka, 1984, USBR Engineering Monograph 25). Canal retangular.
;;;
;;; Dados: Q (vazao afluente), B (largura da bacia: campo "largura" do tipo) e D1 (profundidade a
;;; montante, supercritica = ALTURA_LAMINA do montante).
;;;   V1 = Q / (B D1);  Fr1 = V1 / sqrt(g D1);  g = 9.81
;;;   Fr1 < 1.2: erro (fora do intervalo do metodo).
;;;   Tipo: 1.2 <= Fr1 < 2.5 -> I;  2.5 <= Fr1 <= 4.5 -> IV;  Fr1 > 4.5 e V1 >= 20 m/s -> II;
;;;         Fr1 > 4.5 e V1 < 20 m/s -> III   (corte II/III: V1 >= 20 e leitura do texto do manual).
;;;   D2: tipo I, D2 = 2 D1 (eq. 4.57, aproximacao do manual); demais, conjugada de Belanger
;;;       D2 = D1/2 (sqrt(1 + 8 Fr1^2) - 1).
;;;   L: I 4 D2 (4.58); II 4.3 D2; III 2.7 D2; IV D2 (2.0543 ln Fr1 + 2.8865) (4.65).
;;;   dE = (D2 - D1)^3 / (4 D1 D2) (4.59); U_saida = Q/(B D2) (4.60; tipo II: profundidade de
;;;   saida 1.05 D2); borda livre = 0.1 (V1 + D2) (4.61); H_parede = borda livre + D2 (4.62).
;;;   Tipo III: h3/D1 = 0.1652 Fr1 + 0.6768 (4.63), h4/D1 = 0.0542 Fr1 + 1.0167 (4.64).
;;; NAO implementado: dimensoes dos blocos e da soleira alem de h3 e h4 (vem de figuras/Peterka e o
;;; manual nao as valida); geometria dos blocos do tipo II e IV. Faixa de validade: Fr1 >= 1.2.
;;; Energia: E_in = D1 + V1^2/(2 g) e E_out = E_in - dE (balanco do ressalto). Exemplo 4.6 do manual
;;; (Q = 10, B = 2.5, D1 = 0.215): Fr1 12.81, tipo III, D2 3.79, L 10.23, dE 14.01, U 1.06.
;;; Campo do tipo: largura (B, m). Depende de "dissipacao" (catalogo).
;;; ============================================================
(vl-load-com)

;; (puro) conjugada de Belanger: D1/2 (sqrt(1 + 8 Fr^2) - 1)
(defun DUS:Conjugada (d1 fr)
  (* (/ d1 2.0) (- (sqrt (+ 1.0 (* 8.0 fr fr))) 1.0))
)

;; (puro) tipo da bacia ("I" "II" "III" "IV") ou nil se Fr1 < 1.2
(defun DUS:Tipo (fr v1)
  (cond
    ((< fr 1.2) nil)
    ((< fr 2.5) "I")
    ((<= fr 4.5) "IV")
    ((>= v1 20.0) "II")
    (T "III")
  )
)

;; (puro) dimensionamento da bacia USBR.
;;   retorno: (("V1" ..) ("FR" ..) ("TIPO" . "I".."IV") ("D2" ..) ("L" ..) ("DE" ..) ("U" ..)
;;             ("BL" . borda livre) ("H" . altura da parede) ["H3" ..] ["H4" ..] ("EIN" ..) ("EOUT" ..))
;;   ou (("ERRO" . msg))
(defun DUS:Bacia (q b d1 / v1 fr tipo d2 l de dsaida u bl ein)
  (cond
    ((or (not q) (not b) (not d1) (<= q 0.0) (<= b 0.0) (<= d1 0.0))
      (list (cons "ERRO" "Dados incompativeis para a resolucao do problema (Q, B e D1 devem ser maiores que zero).")))
    (T
      (setq v1 (/ q (* b d1)))
      (setq fr (/ v1 (sqrt (* 9.81 d1))))
      (setq tipo (DUS:Tipo fr v1))
      (if (not tipo)
        (list (cons "ERRO"
          (strcat "Froude de montante " (rtos fr 2 2)
                  " menor que 1,2: fora do intervalo de calculo da bacia USBR.")))
        (progn
          (setq d2 (if (equal tipo "I") (* 2.0 d1) (DUS:Conjugada d1 fr)))
          (setq l
            (cond
              ((equal tipo "I") (* 4.0 d2))
              ((equal tipo "II") (* 4.3 d2))
              ((equal tipo "III") (* 2.7 d2))
              (T (* d2 (+ (* 2.0543 (log fr)) 2.8865)))))
          (setq de (/ (expt (- d2 d1) 3.0) (* 4.0 d1 d2)))
          (setq dsaida (if (equal tipo "II") (* 1.05 d2) d2))
          (setq u (/ q (* b dsaida)))
          (setq bl (* 0.1 (+ v1 d2)))
          (setq ein (+ d1 (/ (* v1 v1) (* 2.0 9.81))))
          (append
            (list
              (cons "V1" v1) (cons "FR" fr) (cons "TIPO" tipo) (cons "D2" d2) (cons "L" l)
              (cons "DE" de) (cons "U" u) (cons "BL" bl) (cons "H" (+ bl d2))
              (cons "EIN" ein) (cons "EOUT" (- ein de)))
            (if (equal tipo "III")
              (list (cons "H3" (* d1 (+ (* 0.1652 fr) 0.6768)))
                    (cons "H4" (* d1 (+ (* 0.0542 fr) 1.0167))))
              nil)
          )
        )
      )
    )
  )
)

;; (puro) valores validos: largura > 0
(defun DUS:_Valida (valores / b)
  (setq b (cdr (assoc "largura" valores)))
  (if (and b (numberp b) (> b 0.0)) T nil)
)

;; Metodo "usbr": FN do catalogo. Devolve EIN, EOUT e os GRUPOS da bacia, ou (("ERRO" . msg))
(defun DUS:Metodo (ctx / tipo r)
  (setq tipo (cdr (assoc "TIPO" ctx)))
  (setq r
    (DUS:Bacia (cdr (assoc "Q" ctx)) (cdr (assoc "largura" (cdr tipo))) (cdr (assoc "Y" ctx))))
  (if (assoc "ERRO" r)
    r
    (list
      (cons "EIN" (cdr (assoc "EIN" r)))
      (cons "EOUT" (cdr (assoc "EOUT" r)))
      (cons "GRUPOS"
        (append
          (list
            (cons "BACIA_USBR"
              (list (cons "VALOR" (cdr (assoc "TIPO" r))) (cons "FROUDE" (cdr (assoc "FR" r)))))
            (cons "PROFUNDIDADE_CONJUGADA" (list (cons "VALOR" (cdr (assoc "D2" r)))))
            (cons "COMPRIMENTO_BACIA" (list (cons "VALOR" (cdr (assoc "L" r)))))
            (cons "VELOCIDADE_SAIDA" (list (cons "VALOR" (cdr (assoc "U" r)))))
            (cons "ALTURA_PAREDE"
              (list (cons "VALOR" (cdr (assoc "H" r))) (cons "BORDA_LIVRE" (cdr (assoc "BL" r))))))
          (if (cdr (assoc "H3" r))
            (list
              (cons "BLOCOS_AMORTECIMENTO"
                (list (cons "VALOR" (cdr (assoc "H3" r))) (cons "H4_SOLEIRA" (cdr (assoc "H4" r))))))
            nil)))
    )
  )
)

(HYDRO:RegAdd "metodo-dissipacao" "usbr"
  (list (cons "NOME" "Bacia por ressalto (USBR, tipos I a IV)")
        (cons "DESC" "Peterka (1984) / SisCCoH 4.3: tipo, D2, comprimento, dE, velocidade de saida, parede")
        (cons "PARAMS" (list (list "largura" "Largura da bacia B" 0.0 "m")))
        (cons "VALIDA" 'DUS:_Valida)
        (cons "FN" 'DUS:Metodo)))

(HYDRO:Provide "dissipacao-usbr" "1.0")
(princ)
