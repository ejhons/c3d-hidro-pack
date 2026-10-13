;;; ============================================================
;;; registry/escada_siscooh.lsp - METODO "SISCOOH" DE ESCADAS HIDRAULICAS (ESS:)
;;;
;;; Metodo "siscooh" do catalogo "metodo-escada" (models/escada.lsp). Referencia:
;;; docs/referencia-escadas-hidraulicas-siscooh.md (Manual Tecnico do SisCCoH 1.1, secao 4.2; Chanson
;;; 1994/2001, Yasuda et al. 2001, Ohtsu et al. 2004, Simoes 2008). Calha RETANGULAR; g = 9.81.
;;; Notacao: S = altura do degrau (a REAL da escada), l = piso, t = S/l = tan(teta), q = Q/B,
;;; yc = (q^2/g)^(1/3), Hd = desnivel total, N = numero de degraus.
;;;
;;; REGIME (secao 4.2.1) - validade: 0.05 <= S/l <= 1.43 (teta 2.86 a 55 graus), senao erro.
;;;   0.05 <= S/l < 0.1 (Chanson 2001): nappe se yc <= (0.89 - 0.4 S/l) S (4.17), senao transicao.
;;;   0.1 <= S/l <= 1.43: nappe se S/yc >= 0.57 t^3 + 1.3 (4.18); skimming se S/yc <=
;;;   (7/6) t^(1/6) (4.21); entre os dois, transicao.
;;;   Subtipos do nappe: ressalto COMPLETO (5.7 a 10.2 graus, S/yc >= -12.5537 t^3 + 21.436 t^2 +
;;;   15.7799 t - 0.4583, eq. 4.19); PARCIAL (11.31 a 30.96 graus, S/yc >= t^1.276/0.0916, eq. 4.20);
;;;   senao sem ressalto. Subtipos do skimming (5.7 a 19 graus): B se S/yc > 13 t^2 - 2.73 t + 0.373
;;;   (4.22), senao A (acima de 19 graus, A). Angulos comparados com tolerancia de 0.01 grau.
;;;   Vazoes limite: nappe ate Q = B sqrt(g yc^3) com yc = S/(0.57 t^3 + 1.3) (ou (4.17));
;;;   skimming a partir de yc = S/((7/6) t^(1/6)).
;;; NAPPE (4.2.2): DN = q^2/(g S^3) (4.23); Ld = 4.3 S DN^0.27 (4.24); y1 = 0.54 S DN^0.425;
;;;   y2 = 1.66 S DN^0.27; Lj = 6.9 (y2 - y1) com y2 de Belanger (3.13); Hmax = Hd + 1.5 yc (4.29);
;;;   completo: Hr = Hmax (0.54 (yc/S)^0.275 + 1.715 (yc/S)^-0.55)/(1.5 + Hd/yc) (4.30); parcial:
;;;   DH/Hmax = 1 - ((1-a)(1 + 1.5 yc/S) + soma_{i=1..N-1}(1-a)^i)/(N + 1.5 yc/S), a = 0.54 (CALIBRADO
;;;   no exemplo 4.2; o manual nao o define) (4.31); parede minima 1.4 y2 (com ressalto, 4.28) ou
;;;   2 tanh(0.02^2.5 + 0.65) yc 1.4 (sem ressalto, 4.27; grafia duvidosa). Estado final: raiz
;;;   supercritica de Hr = d + q^2/(2 g d^2). Nappe SEM ressalto: sem formula de energia (so geometria).
;;; SKIMMING (4.2.3, Ohtsu et al. 2004; teta 5.7 a 55 graus; Hdam = Hd): He/yc (4.33), f (4.34 a
;;;   4.39), dw = (f/(8 sen teta))^(1/3) yc (4.40), Eru (4.41/4.42), Er (4.43/4.44), Cmed (4.45/4.46),
;;;   Y0.9 = dw/(1 - Cmed) (4.47), Hw = 1.4 Y0.9 (4.48), inicio da aeracao (4.49 a 4.52).
;;;   NAO implementado: risco de cavitacao (eq. 4.53 incompleta no manual). Skimming valido para
;;;   0.1 <= S/yc <= (S/yc)s (aviso fora).
;;; TRANSICAO: o manual nao da energia residual: so o regime e as vazoes limite.
;;; Exemplos do manual reproduzidos nos testes: 4.1 (regime), 4.2 (nappe parcial), 4.3 (skimming).
;;; CONFIRA os coeficientes dos polinomios nas fontes originais antes de usar em projeto.
;;; Grupos devolvidos: REGIME, VAZAO_LIMITE_NAPPE, VAZAO_LIMITE_SKIMMING, e (conforme o regime)
;;;   ENERGIA_MAXIMA, ENERGIA_RESIDUAL, DISSIPACAO, ALTURA_PAREDE, ALTURA_LAMINA, VELOCIDADE,
;;;   FROUDE (estado final, lidos pelos objetos a jusante, como um dissipador), AVISOS.
;;; ============================================================
(vl-load-com)

;; (puro) angulo teta em graus de S/l
(defun ESS:Teta (s l)
  (* (/ 180.0 pi) (atan (/ s l)))
)

;; (puro) profundidade critica (q^2/g)^(1/3)
(defun ESS:Yc (q)
  (expt (/ (* q q) 9.81) (/ 1.0 3.0))
)

;; (puro) conjugada de Belanger
(defun ESS:_Belanger (y1 f1)
  (* (/ y1 2.0) (- (sqrt (+ 1.0 (* 8.0 f1 f1))) 1.0))
)

;; (puro) classificacao do regime.
;;   retorno: (("TIPO" . "nappe"|"transicao"|"skimming") ("SUBTIPO" . txt) ("TETA" . graus)
;;             ("SL" . S/l) ("SY" . S/yc)) ou (("ERRO" . msg))
(defun ESS:Regime (s l yc / r th sy tipo sub)
  (setq r (/ s l))
  (setq th (ESS:Teta s l))
  (setq sy (/ s yc))
  (cond
    ((or (< r (- 0.05 1e-9)) (> r (+ 1.43 1e-9)))
      (list (cons "ERRO"
        "S/l fora de 0,05 a 1,43 (angulos de 2,86 a 55 graus): metodo SisCCoH nao se aplica.")))
    ;; declividades baixas (Chanson 2001): so nappe ou transicao
    ((< r 0.1)
      (list (cons "TIPO" (if (<= yc (* (- 0.89 (* 0.4 r)) s)) "nappe" "transicao"))
            (cons "SUBTIPO" "sem-ressalto") (cons "TETA" th) (cons "SL" r) (cons "SY" sy)))
    (T
      (cond
        ((>= sy (+ (* 0.57 r r r) 1.3))
          (setq tipo "nappe")
          (setq sub
            (cond
              ((and (>= th (- 5.7 0.01)) (<= th (+ 10.2 0.01))
                    (>= sy (+ (* -12.5537 r r r) (* 21.436 r r) (* 15.7799 r) -0.4583)))
                "ressalto-completo")
              ((and (>= th (- 11.31 0.01)) (<= th (+ 30.96 0.01))
                    (>= sy (/ (expt r 1.276) 0.0916)))
                "ressalto-parcial")
              (T "sem-ressalto"))))
        ((<= sy (* (/ 7.0 6.0) (expt r (/ 1.0 6.0))))
          (setq tipo "skimming")
          (setq sub
            (if (and (< th 19.0) (> sy (+ (* 13.0 r r) (* -2.73 r) 0.373))) "B" "A")))
        (T (setq tipo "transicao") (setq sub "transicao"))
      )
      (list (cons "TIPO" tipo) (cons "SUBTIPO" sub) (cons "TETA" th) (cons "SL" r) (cons "SY" sy))
    )
  )
)

;; (puro) vazoes limite (m3/s): (("NAPPE" . Q) ("SKIMMING" . Q|nil)). Q = B sqrt(g yc^3).
(defun ESS:LimitesVazao (b s l / r ycn ycs)
  (setq r (/ s l))
  (if (< r 0.1)
    (setq ycn (* (- 0.89 (* 0.4 r)) s) ycs nil)
    (setq ycn (/ s (+ (* 0.57 r r r) 1.3))
          ycs (/ s (* (/ 7.0 6.0) (expt r (/ 1.0 6.0)))))
  )
  (list
    (cons "NAPPE" (* b (sqrt (* 9.81 ycn ycn ycn))))
    (cons "SKIMMING" (if ycs (* b (sqrt (* 9.81 ycs ycs ycs))) nil))
  )
)

;; (puro) raiz SUPERCRITICA (d < yc) de hr = d + q^2/(2 g d^2) por bissecao; nil se hr < 1.5 yc
(defun ESS:_ProfFinal (q hr yc / lo hi mid i)
  (if (< hr (- (* 1.5 yc) 1e-9))
    nil
    (progn
      (setq lo 1e-6 hi yc i 0)
      (while (< i 80)
        (setq mid (/ (+ lo hi) 2.0))
        (if (> (+ mid (/ (* q q) (* 2.0 9.81 mid mid))) hr)
          (setq lo mid)
          (setq hi mid))
        (setq i (1+ i))
      )
      (/ (+ lo hi) 2.0)
    )
  )
)

;; (puro) tangente hiperbolica
(defun ESS:_Tanh (x / e)
  (setq e (exp (* 2.0 x)))
  (/ (- e 1.0) (+ e 1.0))
)

;; (puro) soma de (1-a)^i, i = 1..n
(defun ESS:_SomaPot (a n / s i)
  (setq s 0.0 i 1)
  (while (<= i n)
    (setq s (+ s (expt (- 1.0 a) i)))
    (setq i (1+ i))
  )
  s
)

;; (puro) regime NAPPE (4.2.2). sub = "ressalto-completo" / "ressalto-parcial" / "sem-ressalto".
;;   retorno: (("DN" ..) ("LD" ..) ("Y1" ..) ("Y2" ..) ("LJ" ..) ("PAREDE" ..) ("HMAX" ..)
;;             ["HR" ..] ["D" ..] ["V" ..] ["FR" ..] ["ETA" ..])
(defun ESS:Nappe (q b s l hd n sub / qq yc dn y1 y2 y2b f1 lj hmax hr a d r)
  (setq qq (/ q b))
  (setq yc (ESS:Yc qq))
  (setq r (/ s l))
  (setq dn (/ (* qq qq) (* 9.81 s s s)))
  (setq y1 (* s 0.54 (expt dn 0.425)))
  (setq y2 (* s 1.66 (expt dn 0.27)))
  (setq f1 (/ qq (sqrt (* 9.81 y1 y1 y1))))
  (setq y2b (ESS:_Belanger y1 f1))
  (setq lj (* 6.9 (- y2b y1)))
  (setq hmax (+ hd (* 1.5 yc)))
  (cond
    ((equal sub "ressalto-completo")
      (setq hr
        (* hmax
           (/ (+ (* 0.54 (expt (/ yc s) 0.275)) (* 1.715 (expt (/ yc s) -0.55)))
              (+ 1.5 (/ hd yc))))))
    ((equal sub "ressalto-parcial")
      (setq a 0.54)
      (setq hr
        (* hmax
           (/ (+ (* (- 1.0 a) (+ 1.0 (* 1.5 (/ yc s)))) (ESS:_SomaPot a (1- n)))
              (+ n (* 1.5 (/ yc s)))))))
  )
  (if hr (setq d (ESS:_ProfFinal qq hr yc)))
  (append
    (list
      (cons "DN" dn) (cons "LD" (* s 4.3 (expt dn 0.27))) (cons "Y1" y1) (cons "Y2" y2)
      (cons "LJ" lj) (cons "HMAX" hmax)
      (cons "PAREDE"
        (if hr
          (* 1.4 y2b)
          (* 2.0 (ESS:_Tanh (+ (expt 0.02 2.5) 0.65)) yc 1.4)))
    )
    (if hr
      (append
        (list (cons "HR" hr) (cons "ETA" (/ (- hmax hr) hmax)))
        (if d
          (list (cons "D" d) (cons "V" (/ qq d)) (cons "FR" (/ (/ qq d) (sqrt (* 9.81 d)))))
          nil))
      nil)
  )
)

;; (puro) regime SKIMMING (4.2.3). hdam = desnivel total.
;;   retorno: (("TETA" ..) ("HE" ..) ("F" ..) ("DW" ..) ("ERU" ..) ("ER" ..) ("CMED" ..) ("Y09" ..)
;;             ("HW" ..) ("VA" ..) ("VF" ..) ("LA" ..) ("YA" ..) ("TIPO-B" . T|nil) ("UNIFORME" . T|nil)
;;             ("HMAX" ..))
(defun ESS:Skimming (q b s l hdam / qq yc r th rad sy hey a fmax f dw tipob eru he er m dd cmed y09 k fp)
  (setq qq (/ q b))
  (setq yc (ESS:Yc qq))
  (setq r (/ s l))
  (setq th (ESS:Teta s l))
  (setq rad (* th (/ pi 180.0)))
  (setq sy (/ s yc))
  (setq hey
    (/ (+ 5.7 (* 6.7 (exp (* -6.5 sy))))
       (+ (* -1.21e-5 th th th) (* 1.6e-3 th th) (* -7.13e-2 th) 1.3)))
  (if (<= th 19.0)
    (setq a (+ (* -1.7e-3 th th) (* 6.4e-2 th) -1.5e-1)
          fmax (+ (* -4.2e-4 th th) (* 1.6e-2 th) 3.2e-2))
    (setq a 0.452
          fmax (+ (* 2.32e-5 th th) (* -2.75e-3 th) 2.31e-1))
  )
  (setq f (if (< sy 0.5) (- fmax (* a (expt (- 0.5 sy) 2.0))) fmax))
  (setq dw (* (expt (/ f (* 8.0 (sin rad))) (/ 1.0 3.0)) yc))
  (setq tipob (if (and (< th 19.0) (> sy (+ (* 13.0 r r) (* -2.73 r) 0.373))) T nil))
  (setq eru
    (* yc (+ (* (/ dw yc) (if tipob 1.0 (cos rad))) (* 0.5 (expt (/ yc dw) 2.0)))))
  (setq he (* hey yc))
  (if (>= hdam he)
    (setq er eru)
    (progn
      (setq m (+ (/ (- th) 25.0) 4.0))
      (setq er
        (* yc (+ 1.5 (* (- (/ eru yc) 1.5) (- 1.0 (expt (- 1.0 (/ hdam he)) m))))))
    )
  )
  (setq dd
    (if (< th 19.0)
      0.3
      (+ (* -2e-4 th th) (* 2.14e-2 th) -3.57e-2)))
  (setq cmed (- dd (* 0.3 (exp (- (* -5.0 sy sy) (* 4.0 sy))))))
  (setq y09 (/ dw (- 1.0 cmed)))
  (setq k (* s (cos rad)))
  (setq fp (/ qq (sqrt (* 9.81 k k k (sin rad)))))
  (list
    (cons "TETA" th) (cons "HE" he) (cons "F" f) (cons "DW" dw) (cons "ERU" eru) (cons "ER" er)
    (cons "CMED" cmed) (cons "Y09" y09) (cons "HW" (* 1.4 y09)) (cons "VA" (/ qq y09))
    (cons "VF" (/ qq dw))
    (cons "LA" (* 9.719 (expt (sin rad) 0.0796) (expt fp 0.713) k))
    (cons "YA" (/ (* 0.4034 (expt fp 0.592) k) (expt (sin rad) 0.04)))
    (cons "TIPO-B" tipob) (cons "UNIFORME" (if (>= hdam he) T nil))
    (cons "HMAX" (+ hdam (* 1.5 yc)))
  )
)

;; grupos do estado final (lidos por quem esta a jusante): ALTURA_LAMINA, VELOCIDADE, FROUDE
(defun ESS:_GruposFinal (d v)
  (list
    (cons "ALTURA_LAMINA" (list (cons "VALOR" d) (cons "METODO" "siscooh")))
    (cons "VELOCIDADE" (list (cons "VALOR" v)))
    (cons "FROUDE" (list (cons "VALOR" (/ v (sqrt (* 9.81 d))))))
  )
)

;; Metodo "siscooh": FN do catalogo. ctx de models/escada.lsp (Q B YC H L NDEG DESNIVEL ...).
;; Devolve GRUPOS ((grupo . campos) ...) ou (("ERRO" . msg)).
(defun ESS:Metodo (ctx / q b s l n hd yc rg tipo sub lim r grupos avisos)
  (setq q (cdr (assoc "Q" ctx)))
  (setq b (cdr (assoc "B" ctx)))
  (setq s (cdr (assoc "H" ctx)))
  (setq l (cdr (assoc "L" ctx)))
  (setq n (cdr (assoc "NDEG" ctx)))
  (setq hd (cdr (assoc "DESNIVEL" ctx)))
  (setq yc (cdr (assoc "YC" ctx)))
  (setq rg (ESS:Regime s l yc))
  (if (assoc "ERRO" rg)
    rg
    (progn
      (setq tipo (cdr (assoc "TIPO" rg)))
      (setq sub (cdr (assoc "SUBTIPO" rg)))
      (setq lim (ESS:LimitesVazao b s l))
      (setq grupos
        (list
          (cons "REGIME"
            (list (cons "VALOR" tipo) (cons "SUBTIPO" sub)
                  (cons "INCLINACAO" (cdr (assoc "TETA" rg))) (cons "S_YC" (cdr (assoc "SY" rg)))))
          (cons "VAZAO_LIMITE_NAPPE" (list (cons "VALOR" (cdr (assoc "NAPPE" lim)))))
          (cons "VAZAO_LIMITE_SKIMMING" (list (cons "VALOR" (cdr (assoc "SKIMMING" lim)))))))
      (cond
        ((equal tipo "nappe")
          (setq r (ESS:Nappe q b s l hd n sub))
          (setq grupos
            (append grupos
              (list
                (cons "NUMERO_QUEDA" (list (cons "VALOR" (cdr (assoc "DN" r)))))
                (cons "COMPRIMENTO_QUEDA" (list (cons "VALOR" (cdr (assoc "LD" r)))))
                (cons "COMPRIMENTO_RESSALTO" (list (cons "VALOR" (cdr (assoc "LJ" r)))))
                (cons "ALTURA_PAREDE" (list (cons "VALOR" (cdr (assoc "PAREDE" r)))))
                (cons "ENERGIA_MAXIMA" (list (cons "VALOR" (cdr (assoc "HMAX" r)))))
                (cons "ENERGIA_RESIDUAL" (list (cons "VALOR" (cdr (assoc "HR" r)))))
                (cons "DISSIPACAO"
                  (list (cons "VALOR" (if (cdr (assoc "HR" r)) (- (cdr (assoc "HMAX" r)) (cdr (assoc "HR" r))) nil))
                        (cons "EFICIENCIA" (cdr (assoc "ETA" r)))))
              )
              (if (cdr (assoc "D" r)) (ESS:_GruposFinal (cdr (assoc "D" r)) (cdr (assoc "V" r))) nil)))
          (if (not (cdr (assoc "HR" r)))
            (setq avisos (list "nappe sem ressalto: o metodo nao traz energia residual (so a geometria da queda)")))
          (if (and (cdr (assoc "HR" r)) (not (cdr (assoc "D" r))))
            (setq avisos (list "energia residual menor que a minima: nao ha profundidade supercritica final")))
        )
        ((equal tipo "skimming")
          (setq r (ESS:Skimming q b s l hd))
          (setq grupos
            (append grupos
              (list
                (cons "ENERGIA_MAXIMA" (list (cons "VALOR" (cdr (assoc "HMAX" r)))))
                (cons "ENERGIA_RESIDUAL" (list (cons "VALOR" (cdr (assoc "ER" r)))))
                (cons "DISSIPACAO"
                  (list (cons "VALOR" (- (cdr (assoc "HMAX" r)) (cdr (assoc "ER" r))))
                        (cons "EFICIENCIA" (/ (- (cdr (assoc "HMAX" r)) (cdr (assoc "ER" r))) (cdr (assoc "HMAX" r))))))
                (cons "ALTURA_ESCADA_UNIFORME" (list (cons "VALOR" (cdr (assoc "HE" r)))))
                (cons "ATRITO" (list (cons "VALOR" (cdr (assoc "F" r)))))
                (cons "CONCENTRACAO_AR" (list (cons "VALOR" (cdr (assoc "CMED" r)))))
                (cons "ALTURA_AERADA"
                  (list (cons "VALOR" (cdr (assoc "Y09" r))) (cons "VELOCIDADE" (cdr (assoc "VA" r)))))
                (cons "ALTURA_PAREDE" (list (cons "VALOR" (cdr (assoc "HW" r)))))
                (cons "INICIO_AERACAO"
                  (list (cons "VALOR" (cdr (assoc "LA" r))) (cons "PROFUNDIDADE" (cdr (assoc "YA" r))))))
              (ESS:_GruposFinal (cdr (assoc "DW" r)) (cdr (assoc "VF" r)))))
          (if (< (cdr (assoc "SY" rg)) 0.1)
            (setq avisos (list "S/yc < 0,1: fora do intervalo de calculo do skimming (0,1 <= S/yc <= (S/yc)s)")))
          (if (not (cdr (assoc "UNIFORME" r)))
            (setq avisos
              (append avisos (list "escada mais baixa que a altura para escoamento quase uniforme: energia pela eq. 4.43"))))
        )
        (T
          (setq avisos
            (list "regime de transicao: o metodo nao traz energia residual (so o regime e as vazoes limite)"))
        )
      )
      (append grupos (list (cons "AVISOS" (list (cons "VALOR" avisos)))))
    )
  )
)

(HYDRO:RegAdd "metodo-escada" "siscooh"
  (list (cons "NOME" "SisCCoH 1.1 (secao 4.2)")
        (cons "DESC" "Regime (nappe/transicao/skimming), energia residual, dissipacao e estado final em degraus")
        (cons "FN" 'ESS:Metodo)))

(HYDRO:Provide "escada-siscooh" "1.0")
(princ)
