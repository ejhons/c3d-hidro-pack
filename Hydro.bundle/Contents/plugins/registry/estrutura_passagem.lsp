;;; ============================================================
;;; registry/estrutura_passagem.lsp - CLASSE DE ESTRUTURA "PASSAGEM" (ESP:)
;;;
;;; Poco de visita, caixa e ala: REPASSAM a vazao e o tempo dos montantes (o core de
;;; ligacao grava ENTRADA e VAZAO) e, se o tipo tem K > 0, calculam a PERDA DE CARGA
;;; localizada  dH = K V^2 / (2 g),  g = 9.81 m/s2  (Chow, Open-Channel Hydraulics, 1959;
;;; Porto, Hidraulica Basica), com V = maior velocidade dos tubos de montante no cenario
;;; (grupo VELOCIDADE; ctx "MONTANTES"). K e do projetista (depende da geometria do poco,
;;; do angulo das entradas...): nao ha valor padrao embutido (K = 0: sem perda).
;;;
;;; Campo do tipo:  k  coeficiente de perda localizada (>= 0)
;;; Grupos calculados: PERDA_CARGA ("VALOR" . m) ("METODO" . "localizada")
;;;                    ("INPUT" ("K" ..) ("V" ..)), AVISOS ("VALOR" . lista)
;;;
;;; Catalogo "classe-estrutura" (plugins/tipo_estrutura.lsp). Depende de "tipo-estrutura".
;;; ============================================================
(vl-load-com)

;; (puro) perda de carga localizada dH = K V^2 / (2 g), em m; nil se faltar dado ou K <= 0
(defun ESP:PerdaCarga (k v)
  (if (and k v (> k 0.0) (>= v 0.0))
    (/ (* k v v) (* 2.0 9.81))
    nil
  )
)

;; (puro) valores validos: K numero >= 0
(defun ESP:_Valida (valores / k)
  (setq k (cdr (assoc "k" valores)))
  (if (and k (numberp k) (>= k 0.0)) T nil)
)

(defun ESP:_Rotulo (tipo)
  (strcat "passagem, K = " (rtos (TES:Val "k" tipo) 2 3))
)

;; Capacidade CALCULA da classe: grupos PERDA_CARGA (se K > 0 e ha velocidade) e AVISOS
(defun ESP:_Calcula (en ctx tipo dados / k v dh avisos)
  (setq k (TES:Val "k" tipo))
  (setq v (cdr (assoc "V" (cdr (assoc "MONTANTES" ctx)))))
  (setq dh (ESP:PerdaCarga k v))
  (if (and k (> k 0.0) (null v))
    (setq avisos
      (list "perda de carga nao calculada: nenhum tubo de montante com velocidade no cenario"))
  )
  (append
    (if dh
      (list
        (cons "PERDA_CARGA"
          (list (cons "VALOR" dh) (cons "METODO" "localizada")
                (cons "INPUT" (list (cons "K" k) (cons "V" v))))))
      nil)
    (list (cons "AVISOS" (list (cons "VALOR" avisos))))
  )
)

;; linhas so da classe (capacidade FORMATA: (fn en cenario))
(defun ESP:_Formata (en cenario / dh)
  (setq dh (OBJ:_Val "VALOR" (OBJ:ResultGrupoDe en cenario "PERDA_CARGA")))
  (if dh
    (list (strcat "Perda de carga: " (rtos dh 2 4) " m"))
    nil
  )
)

(if (HYDRO:Has "tipo-estrutura")
  (TES:RegistrarClasse
    "passagem"
    "Passagem (poco de visita, caixa, ala)"
    (list (list "k" "Coeficiente de perda localizada K (0 = sem perda)" 0.0 ""))
    'ESP:_Valida 'ESP:_Rotulo 'ESP:_Calcula 'ESP:_Formata)
)

(HYDRO:Provide "estrutura-passagem" "1.0")
(princ)
