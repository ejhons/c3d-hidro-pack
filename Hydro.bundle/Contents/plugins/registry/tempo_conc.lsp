;;; ============================================================
;;; tempo_conc.lsp - CATALOGO DE METODOS DE TEMPO DE CONCENTRACAO (TCM:)
;;;
;;; Cada metodo e CADASTRADO no catalogo "metodo-tc" do core; o plugin bacia
;;; apenas lista o catalogo. Para criar um metodo novo, cadastre-o aqui ou em
;;; qualquer outro .lsp (modelo em docs/template_metodo.lsp).
;;;
;;; CONTRATO
;;;   (TCM:Registrar id nome descricao params fn)
;;;     params = lista de (chave rotulo padrao unidade [tipo [opcoes]])
;;;     fn     = simbolo:  (fn ctx params) -> (("TC" . min)) ou (("ERRO" . msg))
;;;   ctx = alist da bacia:
;;;     "AREA" (m2)  "COMP" (m, talvegue)  "DESNIVEL" (m)  "DECL" (m/m)
;;;   TCM:Calcular id ctx params  executa o metodo (puro) e valida o resultado.
;;;
;;; METODOS INCLUIDOS (tc em minutos; A em km2, L em km, S em m/m, H em m)
;;;   kirpich          tc = 57 (L^3/H)^0.385      (Kirpich / California Culverts)
;;;   ventura          tc = 60 . 0.127 . (A/S)^0.5
;;;   pasini           tc = 60 . 0.107 . (A.L)^(1/3) / S^0.5
;;;   corps-engineers  tc = 60 . 0.191 . L^0.76 . S^-0.19
;;;   giandotti        tc = 60 . (4.A^0.5 + 1.5.L) / (0.8.Hm^0.5)
;;;   george-ribeiro   tc = 16.L / ((1.05 - 0.2.p) . (100.S)^0.04)
;;;   velocidade       tc = L[m] / (60 . v)       (metodo cinematico)
;;;   informado        tc informado pelo usuario
;;; Cada formula tem faixa de validade propria (tipo e tamanho de bacia):
;;; confira na literatura antes de adotar. Veja docs/arquitetura.md.
;;; ============================================================
(vl-load-com)

(defun TCM:_Erro (msg)
  (list (cons "ERRO" msg))
)

;;; ------------------------------------------------------------
;;; CADASTRO E EXECUCAO
;;; ------------------------------------------------------------
(defun TCM:Registrar (id nome descricao params fn / p)
  (HYDRO:RegAdd "metodo-tc" id
    (list
      (cons "NOME" nome)
      (cons "DESC" descricao)
      (cons "PARAMS" params)
      (cons "FN" fn)
    )
  )
  (foreach p params
    (HYDRO:SetLabel
      (strcat "HYDRO.TC." id "." (car p))
      (strcat nome " - " (cadr p))
      (nth 3 p)
    )
  )
  id
)

;; Executa um metodo (puro). Retorna (("TC" . min)) ou (("ERRO" . msg))
(defun TCM:Calcular (id ctx params / m r tc)
  (setq m (HYDRO:RegGet "metodo-tc" id))
  (if m
    (progn
      (setq r (apply (cdr (assoc "FN" m)) (list ctx params)))
      (setq tc (cdr (assoc "TC" r)))
      (cond
        ((assoc "ERRO" r) r)
        ((and tc (> tc 0.0)) (list (cons "TC" tc)))
        (T (TCM:_Erro "O metodo nao produziu um tc valido."))
      )
    )
    (TCM:_Erro (strcat "Metodo de tc nao cadastrado: " id))
  )
)

;;; ------------------------------------------------------------
;;; AUXILIARES (unidades)
;;; ------------------------------------------------------------
(defun TCM:_A (ctx)
  (/ (cdr (assoc "AREA" ctx)) 1.0e6)
)

(defun TCM:_L (ctx)
  (/ (cdr (assoc "COMP" ctx)) 1000.0)
)

(defun TCM:_S (ctx)
  (cdr (assoc "DECL" ctx))
)

(defun TCM:_H (ctx / h)
  (setq h (cdr (assoc "DESNIVEL" ctx)))
  (if h
    h
    (* (cdr (assoc "DECL" ctx)) (cdr (assoc "COMP" ctx)))
  )
)

;; area, comprimento e declividade positivos?
(defun TCM:_Ok (ctx)
  (if (and (cdr (assoc "AREA" ctx)) (> (cdr (assoc "AREA" ctx)) 0.0)
           (cdr (assoc "COMP" ctx)) (> (cdr (assoc "COMP" ctx)) 0.0)
           (cdr (assoc "DECL" ctx)) (> (cdr (assoc "DECL" ctx)) 0.0))
    T
    nil
  )
)

(defun TCM:_ErroBase ()
  (TCM:_Erro "Area, comprimento e declividade devem ser maiores que zero.")
)

;;; ------------------------------------------------------------
;;; METODOS
;;; ------------------------------------------------------------
(defun TCM:Kirpich (ctx params)
  (if (and (TCM:_Ok ctx) (> (TCM:_H ctx) 0.0))
    (list (cons "TC" (* 57.0 (expt (/ (expt (TCM:_L ctx) 3.0) (TCM:_H ctx)) 0.385))))
    (TCM:_ErroBase)
  )
)

(defun TCM:Ventura (ctx params)
  (if (TCM:_Ok ctx)
    (list (cons "TC" (* 60.0 0.127 (sqrt (/ (TCM:_A ctx) (TCM:_S ctx))))))
    (TCM:_ErroBase)
  )
)

(defun TCM:Pasini (ctx params)
  (if (TCM:_Ok ctx)
    (list
      (cons "TC"
        (* 60.0 0.107
           (/ (expt (* (TCM:_A ctx) (TCM:_L ctx)) (/ 1.0 3.0))
              (sqrt (TCM:_S ctx)))))
    )
    (TCM:_ErroBase)
  )
)

(defun TCM:CorpsEngineers (ctx params)
  (if (TCM:_Ok ctx)
    (list
      (cons "TC"
        (* 60.0 0.191 (expt (TCM:_L ctx) 0.76) (expt (TCM:_S ctx) -0.19)))
    )
    (TCM:_ErroBase)
  )
)

(defun TCM:Giandotti (ctx params / hm)
  (setq hm (cdr (assoc "HM" params)))
  (cond
    ((not (TCM:_Ok ctx)) (TCM:_ErroBase))
    ((or (not hm) (<= hm 0.0))
      (TCM:_Erro "Hm (altitude media da bacia acima do exutorio) deve ser maior que zero.")
    )
    (T
      (list
        (cons "TC"
          (* 60.0
             (/ (+ (* 4.0 (sqrt (TCM:_A ctx))) (* 1.5 (TCM:_L ctx)))
                (* 0.8 (sqrt hm)))))
      )
    )
  )
)

(defun TCM:GeorgeRibeiro (ctx params / p)
  (setq p (cdr (assoc "P" params)))
  (cond
    ((not (TCM:_Ok ctx)) (TCM:_ErroBase))
    ((or (not p) (< p 0.0) (> p 1.0))
      (TCM:_Erro "p (fracao da area com vegetacao) deve estar entre 0 e 1.")
    )
    (T
      (list
        (cons "TC"
          (/ (* 16.0 (TCM:_L ctx))
             (* (- 1.05 (* 0.2 p)) (expt (* 100.0 (TCM:_S ctx)) 0.04))))
      )
    )
  )
)

(defun TCM:Velocidade (ctx params / v comp)
  (setq v (cdr (assoc "V" params)))
  (setq comp (cdr (assoc "COMP" ctx)))
  (if (and v (> v 0.0) comp (> comp 0.0))
    (list (cons "TC" (/ comp (* 60.0 v))))
    (TCM:_Erro "Informe a velocidade media (> 0) e um comprimento valido.")
  )
)

(defun TCM:Informado (ctx params / tc)
  (setq tc (cdr (assoc "TC" params)))
  (if (and tc (> tc 0.0))
    (list (cons "TC" tc))
    (TCM:_Erro "Informe um tc maior que zero.")
  )
)

;;; ------------------------------------------------------------
;;; CADASTRO DOS METODOS INCLUIDOS
;;; ------------------------------------------------------------
(TCM:Registrar
  "kirpich"
  "Kirpich / California Culverts"
  "tc = 57 (L^3/H)^0.385 (L km, H m). Pequenas bacias, declividade media/alta."
  nil
  'TCM:Kirpich
)

(TCM:Registrar
  "ventura"
  "Ventura"
  "tc = 0.127 (A/S)^0.5 em horas (A km2, S m/m)."
  nil
  'TCM:Ventura
)

(TCM:Registrar
  "pasini"
  "Pasini"
  "tc = 0.107 (A.L)^(1/3) / S^0.5 em horas (A km2, L km, S m/m)."
  nil
  'TCM:Pasini
)

(TCM:Registrar
  "corps-engineers"
  "Corps of Engineers (US)"
  "tc = 0.191 L^0.76 S^-0.19 em horas (L km, S m/m)."
  nil
  'TCM:CorpsEngineers
)

(TCM:Registrar
  "giandotti"
  "Giandotti"
  "tc = (4 A^0.5 + 1.5 L) / (0.8 Hm^0.5) em horas. Hm = altitude media sobre o exutorio."
  (list (list "HM" "Hm: altitude media da bacia acima do exutorio" 10.0 "m"))
  'TCM:Giandotti
)

(TCM:Registrar
  "george-ribeiro"
  "George Ribeiro"
  "tc = 16 L / ((1.05 - 0.2 p)(100 S)^0.04) em min (L km). p = fracao com vegetacao."
  (list (list "P" "p: fracao da area coberta por vegetacao (0 a 1)" 0.5 ""))
  'TCM:GeorgeRibeiro
)

(TCM:Registrar
  "velocidade"
  "Cinematico (velocidade media)"
  "tc = L / (60 v), com a velocidade media do escoamento no talvegue."
  (list (list "V" "Velocidade media do escoamento" 1.0 "m/s"))
  'TCM:Velocidade
)

(TCM:Registrar
  "informado"
  "Informado pelo usuario"
  "Usa o tc fornecido."
  (list (list "TC" "Tempo de concentracao" 10.0 "min"))
  'TCM:Informado
)

(HYDRO:Provide "tempo-conc" "1.0")
(princ)
