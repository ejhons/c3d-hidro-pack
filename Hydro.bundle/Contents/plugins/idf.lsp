;;; ============================================================
;;; idf.lsp - EQUACAO IDF (PREC:)  [funcionalidade "idf"]
;;;
;;; Equacao IDF:   i = K * (TR + s)^a / (tc + b)^c + p      [mm/h]
;;;
;;; API:
;;;   (PREC:Params)               -> alist (("K" . x) ("A" . x) ...) ou nil se incompleto
;;;   (PREC:Intensidade duracao tr) -> mm/h ou nil  (duracao da chuva em min; no
;;;                                metodo racional, duracao = tc)
;;;   (PREC:AskParams)            pergunta (linha de comando) e grava K a b c s p
;;;   (PREC:Tr) / (PREC:AskTr)    tempo de retorno atual
;;;
;;; Dialogo e comandos (IDF, ATUALIZAIDF, ATUALIZATR): views/idf_view.lsp
;;;
;;; Chaves usadas em HYDRO:Get/Set (mesmas de antes, desenhos antigos
;;; continuam funcionando):
;;;   HYDRO.IDF.K  .A  .B  .C  .S  .P   e   HYDRO.TR   HYDRO.TC.MINIMO
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; PARAMETROS
;;; ------------------------------------------------------------
(defun PREC:Params (/ par)
  (setq par
    (list
      (cons "K" (HYDRO:Get "HYDRO.IDF.K" nil))
      (cons "A" (HYDRO:Get "HYDRO.IDF.A" nil))
      (cons "B" (HYDRO:Get "HYDRO.IDF.B" nil))
      (cons "C" (HYDRO:Get "HYDRO.IDF.C" nil))
      (cons "S" (HYDRO:Get "HYDRO.IDF.S" nil))
      (cons "P" (HYDRO:Get "HYDRO.IDF.P" nil))
    )
  )
  (if (member nil (mapcar 'cdr par)) nil par)
)

(defun PREC:AskParams (/ n)
  (foreach n '("K" "A" "B" "C" "S" "P")
    (HYDRO:Set
      (strcat "HYDRO.IDF." n)
      (HYDRO:AskReal
        (strcat "IDF - Digite o valor de " (strcase n T))
        (HYDRO:Get (strcat "HYDRO.IDF." n) nil)
      )
    )
  )
  (princ)
)

(defun PREC:Tr ()
  (HYDRO:Get "HYDRO.TR" nil)
)

(defun PREC:AskTr (/ tr)
  (setq tr (HYDRO:AskReal "Digite o tempo de retorno (anos)" (PREC:Tr)))
  (if tr (HYDRO:Set "HYDRO.TR" tr))
  tr
)

;;; ------------------------------------------------------------
;;; CALCULO
;;; ------------------------------------------------------------
(defun PREC:Intensidade (duracao tr / par k a b c s p base)
  ;; duracao = duracao da chuva em min. No metodo racional a duracao e o tc;
  ;; em outros metodos (SCS, hidrogramas) ela pode ser diferente do tc.
  (setq par (PREC:Params))
  (if (and par duracao tr)
    (progn
      (setq k (cdr (assoc "K" par)))
      (setq a (cdr (assoc "A" par)))
      (setq b (cdr (assoc "B" par)))
      (setq c (cdr (assoc "C" par)))
      (setq s (cdr (assoc "S" par)))
      (setq p (cdr (assoc "P" par)))
      (setq base (abs (+ duracao b)))
      (if (> base 1e-9)
        (+ (/ (* k (expt (abs (+ tr s)) a)) (expt base c)) p)
        nil
      )
    )
    nil
  )
)

(HYDRO:SetLabel "HYDRO.IDF.K" "IDF - parametro K" "")
(HYDRO:SetLabel "HYDRO.IDF.A" "IDF - parametro a" "")
(HYDRO:SetLabel "HYDRO.IDF.B" "IDF - parametro b" "")
(HYDRO:SetLabel "HYDRO.IDF.C" "IDF - parametro c" "")
(HYDRO:SetLabel "HYDRO.IDF.S" "IDF - parametro s" "")
(HYDRO:SetLabel "HYDRO.IDF.P" "IDF - parametro p" "")
(HYDRO:SetLabel "HYDRO.TR" "Tempo de retorno" "anos")

(HYDRO:Provide "idf" "1.0")
(princ)