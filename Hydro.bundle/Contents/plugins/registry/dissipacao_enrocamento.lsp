;;; ============================================================
;;; registry/dissipacao_enrocamento.lsp - BACIA EM ENROCAMENTO, FHWA HEC-14 (DEN:)
;;;
;;; Metodo "enrocamento" do catalogo "metodo-dissipacao". Referencia:
;;; docs/referencia-dissipadores-siscooh.md, secao 3 (SisCCoH 1.1, secao 4.4; FHWA, 2006, HEC-14;
;;; Taylor, 1973). Canal retangular com escoamento supercritico.
;;;
;;; Dados: W0 (largura do canal na saida: campo "largura"), ye (profundidade ao fim do canal =
;;; ALTURA_LAMINA do montante), V0 (velocidade = VELOCIDADE do montante), D50, TW (nivel a jusante),
;;; hs (profundidade da cavidade de erosao: ENTRADA do projetista, nao ha equacao no manual),
;;; curva ("best" ou "envelope"), z (talude lateral H:V da saida).
;;;   Dmax = D100 = D50 (4)^(1/3);  Dmin = D50 (1/4)^(1/3)                         (4.66, 4.67)
;;;   Co: TW/ye < 0.75 -> best 1.4 / envelope 2.0;  0.75 a 1.0 -> best 0.7 / envelope 1.0
;;;       (HEC-14; fora de TW/ye <= 1.0 a tabela nao cobre: erro)
;;;   Verificacoes (erro se falhar): 0.1 <= D50/ye <= 0.7;  hs/D50 >= 2.
;;;   Ls = max(10 hs, 3 W0);  LB = max(15 hs, 4 W0);  LA = LB - Ls;  WB = W0 + (2/3) LB
;;;   Espessuras: max(2 D50, 1.5 Dmax) e 3 D50.   Fr0 = V0 / sqrt(g ye).
;;;   Profundidade na saida (trapezio; eq. 4.68): Q^2/g = [(WB + z y)y]^3 / (WB + 2 z y), por
;;;   bissecao (profundidade critica da saida) e velocidade Q/A.
;;; Notas do documento de referencia: LA = LB - Ls e WB = W0 + 2/3 LB foram deduzidos do exemplo 4.7
;;; (W0 2.44, ye 1.22, D50 0.55, TW 0.85, V0 7.63, hs 1.147: Ls 11.465, LB 17.197, LA 5.732, WB 13.905);
;;; a eq. 4.68 nao tem exemplo numerico. A tabela de Co e de memoria (HEC-14).
;;; O metodo nao tem energia de saida (nao entra no balanco do dissipador); so devolve grupos.
;;; Campos do tipo: largura, d50, tw, hs, curva, talude. Depende de "dissipacao" (catalogo).
;;; ============================================================
(vl-load-com)

;; (puro) parametro de tailwater Co (HEC-14) ou nil se TW/ye fora da tabela (0 a 1.0)
(defun DEN:Co (tw-ye curva)
  (cond
    ((or (< tw-ye 0.0) (> tw-ye 1.0)) nil)
    ((< tw-ye 0.75) (if (equal curva "best") 1.4 2.0))
    (T (if (equal curva "best") 0.7 1.0))
  )
)

;; (puro) profundidade da saida trapezoidal (eq. 4.68) por bissecao: Q^2/g = A^3/T
(defun DEN:ProfSaida (q wb z / lo hi mid i a tt)
  (setq lo 1e-6 hi 100.0 i 0)
  (while (< i 80)
    (setq mid (/ (+ lo hi) 2.0))
    (setq a (* (+ wb (* z mid)) mid))
    (setq tt (+ wb (* 2.0 z mid)))
    (if (< (/ (* a a a) tt) (/ (* q q) 9.81))
      (setq lo mid)
      (setq hi mid))
    (setq i (1+ i))
  )
  (/ (+ lo hi) 2.0)
)

;; (puro) dimensionamento. Retorna alist (DMIN DMAX CO D50-YE FR0 HS-D50 LS LB LA WB E1 E2 Y3 V3)
;; ou (("ERRO" . msg)).
(defun DEN:Bacia (q w0 ye d50 tw v0 hs curva z / dmax dmin co lb ls la wb y3 a3)
  (cond
    ((or (not q) (not w0) (not ye) (not d50) (not tw) (not v0) (not hs)
         (<= q 0.0) (<= w0 0.0) (<= ye 0.0) (<= d50 0.0) (<= v0 0.0) (<= hs 0.0))
      (list (cons "ERRO" "Dados incompativeis para a resolucao do problema (Q, W0, ye, D50, V0 e hs devem ser maiores que zero).")))
    ((< (/ d50 ye) 0.1) (list (cons "ERRO" "D50/ye < 0,1. Tente outro D50!")))
    ((> (/ d50 ye) 0.7) (list (cons "ERRO" "D50/ye > 0,7. Tente outro D50!")))
    ((< (/ hs d50) 2.0) (list (cons "ERRO" "hs/D50 < 2. Tente outro D50 ou outra profundidade de erosao hs!")))
    ((not (DEN:Co (/ tw ye) curva))
      (list (cons "ERRO" "TW/ye fora da tabela de Co (0 a 1,0): use outro nivel a jusante.")))
    (T
      (setq dmax (* d50 (expt 4.0 (/ 1.0 3.0))))
      (setq dmin (* d50 (expt 0.25 (/ 1.0 3.0))))
      (setq co (DEN:Co (/ tw ye) curva))
      (setq ls (max (* 10.0 hs) (* 3.0 w0)))
      (setq lb (max (* 15.0 hs) (* 4.0 w0)))
      (setq la (- lb ls))
      (setq wb (+ w0 (* (/ 2.0 3.0) lb)))
      (setq y3 (DEN:ProfSaida q wb z))
      (setq a3 (* (+ wb (* z y3)) y3))
      (list
        (cons "DMIN" dmin) (cons "DMAX" dmax) (cons "CO" co)
        (cons "D50-YE" (/ d50 ye)) (cons "FR0" (/ v0 (sqrt (* 9.81 ye)))) (cons "HS-D50" (/ hs d50))
        (cons "LS" ls) (cons "LB" lb) (cons "LA" la) (cons "WB" wb)
        (cons "E1" (max (* 2.0 d50) (* 1.5 dmax))) (cons "E2" (* 3.0 d50))
        (cons "Y3" y3) (cons "V3" (/ q a3)))
    )
  )
)

;; (puro) valores validos: largura, d50, hs > 0; tw >= 0; curva "best"/"envelope"; talude >= 0
(defun DEN:_Valida (valores / w d tw hs cv z)
  (setq w (cdr (assoc "largura" valores)))
  (setq d (cdr (assoc "d50" valores)))
  (setq tw (cdr (assoc "tw" valores)))
  (setq hs (cdr (assoc "hs" valores)))
  (setq cv (cdr (assoc "curva" valores)))
  (setq z (cdr (assoc "talude" valores)))
  (if (and w d tw hs z (numberp w) (numberp d) (numberp tw) (numberp hs) (numberp z)
           (> w 0.0) (> d 0.0) (>= tw 0.0) (> hs 0.0) (>= z 0.0)
           (member cv '("best" "envelope")))
    T
    nil
  )
)

;; Metodo "enrocamento": FN do catalogo. Devolve os GRUPOS (sem energia de saida) ou ERRO
(defun DEN:Metodo (ctx / tipo v r q ye)
  (setq tipo (cdr (assoc "TIPO" ctx)))
  (setq q (cdr (assoc "Q" ctx)))
  (setq ye (cdr (assoc "Y" ctx)))
  (setq v (cdr (assoc "V" ctx)))
  (if (and (not v) q ye (> ye 0.0) (cdr (assoc "largura" (cdr tipo))))
    (setq v (/ q (* (cdr (assoc "largura" (cdr tipo))) ye))))
  (setq r
    (DEN:Bacia q (cdr (assoc "largura" (cdr tipo))) ye (cdr (assoc "d50" (cdr tipo)))
               (cdr (assoc "tw" (cdr tipo))) v (cdr (assoc "hs" (cdr tipo)))
               (cdr (assoc "curva" (cdr tipo))) (cdr (assoc "talude" (cdr tipo)))))
  (if (assoc "ERRO" r)
    r
    (list
      (cons "GRUPOS"
        (list
          (cons "COMPRIMENTO_BACIA"
            (list (cons "VALOR" (cdr (assoc "LB" r))) (cons "LS" (cdr (assoc "LS" r)))
                  (cons "LA" (cdr (assoc "LA" r)))))
          (cons "LARGURA_SAIDA" (list (cons "VALOR" (cdr (assoc "WB" r)))))
          (cons "ESPESSURA_ENROCAMENTO"
            (list (cons "VALOR" (cdr (assoc "E1" r))) (cons "OUTRA" (cdr (assoc "E2" r)))))
          (cons "DIAMETROS_ENROCAMENTO"
            (list (cons "VALOR" (cdr (assoc "DMAX" r))) (cons "DMIN" (cdr (assoc "DMIN" r)))))
          (cons "PARAMETRO_TAILWATER" (list (cons "VALOR" (cdr (assoc "CO" r)))))
          (cons "FROUDE_ENTRADA" (list (cons "VALOR" (cdr (assoc "FR0" r)))))
          (cons "PROFUNDIDADE_SAIDA" (list (cons "VALOR" (cdr (assoc "Y3" r)))))
          (cons "VELOCIDADE_SAIDA" (list (cons "VALOR" (cdr (assoc "V3" r)))))))
    )
  )
)

(HYDRO:RegAdd "metodo-dissipacao" "enrocamento"
  (list (cons "NOME" "Bacia em enrocamento (HEC-14)")
        (cons "DESC" "FHWA (2006) / SisCCoH 4.4: comprimentos, largura de saida, diametros e espessuras")
        (cons "PARAMS"
          (list
            (list "largura" "Largura do canal na saida W0" 0.0 "m")
            (list "d50" "Diametro mediano D50 do enrocamento" 0.0 "m")
            (list "tw" "Nivel a jusante TW" 0.0 "m")
            (list "hs" "Profundidade da cavidade de erosao hs (FHWA)" 0.0 "m")
            (list "curva" "Curva (best / envelope)" "envelope" "" "opcoes" '("best" "envelope"))
            (list "talude" "Talude lateral da saida z (H : 1 V)" 2.0 "")))
        (cons "VALIDA" 'DEN:_Valida)
        (cons "FN" 'DEN:Metodo)))

(HYDRO:Provide "dissipacao-enrocamento" "1.0")
(princ)
