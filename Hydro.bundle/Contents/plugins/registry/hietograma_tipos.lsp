;;; ============================================================
;;; registry/hietograma_tipos.lsp - TIPOS DE HIETOGRAMA (HIET:)
;;;
;;; Catalogo: cada tipo e apenas um CADASTRO no catalogo "hietograma-tipo"
;;; (mecanismo em plugins/precipitacao.lsp). Para um tipo novo, crie outro
;;; arquivo em registry/ com outro HIET:RegistrarTipo; nada daqui muda.
;;;
;;; Todos usam a chuva total da IDF, H(D) = i(D) . D / 60, e preservam esse
;;; total. Duracao D = N . DT. Tipos incluidos:
;;;
;;;   bloco-unico       toda a chuva em um bloco de duracao D (intensidade
;;;                     constante). E o que o metodo racional ja supoe.
;;;   bloco-alternado   Metodo dos blocos alternados (Chow, Maidment e Mays,
;;;                     1988). Incrementos dP_k = P(k.DT) - P((k-1).DT), com
;;;                     P(d) = i(d).d/60; o maior fica na posicao do pico e os
;;;                     seguintes se alternam a direita e a esquerda.
;;;                     R = posicao do pico (fracao da duracao; 0,5 = centro).
;;;   chicago           Hietograma de Chicago (Keifer e Chu, 1957). Com
;;;                     H(x) = i(x).x, a chuva acumulada ANTES do pico, medindo
;;;                     o tempo tb para tras a partir dele, e r.H(tb/r)/60; DEPOIS,
;;;                     com ta a partir do pico, e (1-r).H(ta/(1-r))/60. O pico
;;;                     fica em t = r.D. A intensidade e a derivada dessas
;;;                     curvas, que reproduzem a IDF exatamente; aqui os
;;;                     blocos usam a diferenca exata da acumulada.
;;;
;;; Faixa de validade: o hietograma so vale na faixa de duracoes em que a IDF
;;; foi ajustada. O valor de R (posicao do pico) e escolha de projeto; o
;;; Chicago exige 0 < R < 1. Confira na literatura antes de adotar.
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; BLOCO UNICO
;;; ------------------------------------------------------------
(defun HIET:BlocoUnico (ctx params / tr dur)
  (setq tr (cdr (assoc "TR" ctx)))
  (setq dur (cdr (assoc "DUR" ctx)))
  (list
    (cons "BLOCOS" (list (HIET:_Bloco 0.0 dur (HIET:Profundidade dur tr))))
    (cons "NOTA" "Chuva em bloco unico (intensidade constante).")
  )
)

;;; ------------------------------------------------------------
;;; BLOCOS ALTERNADOS
;;; ------------------------------------------------------------
(defun HIET:_Faixa (a b / out)
  (while (<= a b)
    (setq out (append out (list a)))
    (setq a (1+ a))
  )
  out
)

;; lista com o item i trocado por v
(defun HIET:_SetNth (lista i v / k out x)
  (setq k 0)
  (foreach x lista
    (setq out (append out (list (if (= k i) v x))))
    (setq k (1+ k))
  )
  out
)

;; Reordena os incrementos: o maior na posicao do pico (indice fix(r.n)) e os
;; demais, em ordem decrescente, alternando direita e esquerda; se um lado
;; acaba, o resto vai para o outro. (>= preserva valores repetidos.)
(defun HIET:_Alterna (inc r / n pk srt pos direita esquerda vez v)
  (setq n (length inc))
  (setq pk (min (1- n) (fix (* r n))))
  (setq srt (vl-sort inc '>=))
  (setq pos (mapcar (function (lambda (x) nil)) inc))
  (setq pos (HIET:_SetNth pos pk (car srt)))
  (setq direita (HIET:_Faixa (1+ pk) (1- n)))
  (setq esquerda (reverse (HIET:_Faixa 0 (1- pk))))
  (setq vez T)
  (foreach v (cdr srt)
    (cond
      ((and vez direita)
        (setq pos (HIET:_SetNth pos (car direita) v))
        (setq direita (cdr direita))
      )
      ((and (not vez) esquerda)
        (setq pos (HIET:_SetNth pos (car esquerda) v))
        (setq esquerda (cdr esquerda))
      )
      (direita
        (setq pos (HIET:_SetNth pos (car direita) v))
        (setq direita (cdr direita))
      )
      (T
        (setq pos (HIET:_SetNth pos (car esquerda) v))
        (setq esquerda (cdr esquerda))
      )
    )
    (setq vez (not vez))
  )
  pos
)

(defun HIET:BlocoAlternado (ctx params / tr n dt r k inc)
  (setq tr (cdr (assoc "TR" ctx)))
  (setq n (cdr (assoc "N" ctx)))
  (setq dt (cdr (assoc "DT" ctx)))
  (setq r (cdr (assoc "R" params)))
  (if (not r) (setq r 0.5))
  (cond
    ((or (< r 0.0) (> r 1.0))
      (HIET:_Erro "R (posicao do pico) deve estar entre 0 e 1.")
    )
    (T
      (setq k 1)
      (while (<= k n)
        (setq inc
          (append inc
            (list (- (HIET:Profundidade (* k dt) tr)
                     (HIET:Profundidade (* (1- k) dt) tr)))))
        (setq k (1+ k))
      )
      (list
        (cons "BLOCOS" (HIET:_Blocos (HIET:_Alterna inc r) dt))
        (cons "NOTA" "Blocos alternados (Chow, Maidment e Mays, 1988).")
      )
    )
  )
)

;;; ------------------------------------------------------------
;;; CHICAGO
;;; ------------------------------------------------------------
;; Chuva acumulada (mm) de 0 ate t0 no hietograma de Chicago, pico em r.dur
(defun HIET:_ChicagoAcum (t0 dur tr r / tp base)
  (setq tp (* r dur))
  (setq base (/ (* r (HIET:_H dur tr)) 60.0))
  (if (<= t0 tp)
    (- base (/ (* r (HIET:_H (/ (- tp t0) r) tr)) 60.0))
    (+ base (/ (* (- 1.0 r) (HIET:_H (/ (- t0 tp) (- 1.0 r)) tr)) 60.0))
  )
)

(defun HIET:Chicago (ctx params / tr dur n dt r k vals)
  (setq tr (cdr (assoc "TR" ctx)))
  (setq dur (cdr (assoc "DUR" ctx)))
  (setq n (cdr (assoc "N" ctx)))
  (setq dt (cdr (assoc "DT" ctx)))
  (setq r (cdr (assoc "R" params)))
  (if (not r) (setq r 0.4))
  (cond
    ((or (<= r 0.0) (>= r 1.0))
      (HIET:_Erro "R (posicao do pico) deve estar entre 0 e 1 (exclusive).")
    )
    (T
      (setq k 0)
      (while (< k n)
        (setq vals
          (append vals
            (list (- (HIET:_ChicagoAcum (* (1+ k) dt) dur tr r)
                     (HIET:_ChicagoAcum (* k dt) dur tr r)))))
        (setq k (1+ k))
      )
      (list
        (cons "BLOCOS" (HIET:_Blocos vals dt))
        (cons "NOTA" "Hietograma de Chicago (Keifer e Chu, 1957).")
      )
    )
  )
)

;;; ------------------------------------------------------------
;;; CADASTRO DOS TIPOS INCLUIDOS
;;; ------------------------------------------------------------
(HIET:RegistrarTipo
  "bloco-unico"
  "Bloco unico"
  "Toda a chuva da IDF em um bloco de duracao D (intensidade constante)."
  nil
  'HIET:BlocoUnico
)

(HIET:RegistrarTipo
  "bloco-alternado"
  "Blocos alternados"
  "Incrementos da IDF reordenados: maior no pico, demais alternados (Chow et al.)."
  (list (list "DT" "Passo de tempo" 10.0 "min")
        (list "R" "Posicao do pico (0 a 1; 0,5 = centro)" 0.5 ""))
  'HIET:BlocoAlternado
)

(HIET:RegistrarTipo
  "chicago"
  "Chicago"
  "Hietograma de Chicago (Keifer e Chu): pico em r.D, reproduz a IDF."
  (list (list "DT" "Passo de tempo" 10.0 "min")
        (list "R" "Posicao do pico r (0 a 1, exclusive)" 0.4 ""))
  'HIET:Chicago
)

(HYDRO:Provide "hietograma-tipos" "1.0")
(princ)
