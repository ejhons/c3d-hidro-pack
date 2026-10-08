;;; ============================================================
;;; template_metodo.lsp - MODELO PARA CADASTRAR UM METODO CHUVA-VAZAO E UM
;;; TIPO DE HIDROGRAMA
;;;
;;; Copie para Hydro.bundle/Contents/plugins/<nome>.lsp, troque o prefixo
;;; EXM por o seu e inclua "plugins/<nome>" em HYDRO:Manifest (core/core.lsp).
;;;
;;; ATENCAO: os dois exemplos abaixo existem so para mostrar o CONTRATO. A
;;; formula do metodo e um exemplo generico (regressao potencial Q = a.A^b);
;;; NAO foi validada hidrologicamente. Use as suas formulas e limites.
;;;
;;; Regras (veja docs/arquitetura.md):
;;;   - prefixo proprio em todo simbolo; nenhuma variavel global
;;;   - declare TODAS as variaveis locais depois da barra
;;;   - (and ...) e (or ...) devolvem T ou nil, nunca o valor
;;;   - so ASCII; nao inclua pares com valor nil nos resultados
;;;   - funcoes de calculo sao puras (sem getXXX, alert ou princ)
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; 1) METODO CHUVA-VAZAO
;;; fn recebe (ctx params):
;;;   ctx    "AREA" (m2) "COMP" (m) "DECL" (m/m) "TC" (min) "TR" (anos) "DUR" (min)
;;;   params alist (chave . valor) das respostas do usuario
;;; devolve alist com o que calculou, ou (("ERRO" . "mensagem")).
;;; ------------------------------------------------------------
(defun EXM:Regressao (ctx params / area a b qp)
  (setq area (cdr (assoc "AREA" ctx)))
  (setq a    (cdr (assoc "A" params)))
  (setq b    (cdr (assoc "B" params)))
  (cond
    ((or (not a) (<= a 0.0) (not b))
      (list (cons "ERRO" "Informe a > 0 e b."))
    )
    (T
      (setq qp (* a (expt (/ area 1.0e6) b)))      ; A em km2
      (list
        (cons "QP" qp)
        (cons "TP" (cdr (assoc "TC" ctx)))
        (cons "DUR" (cdr (assoc "TC" ctx)))
      )
    )
  )
)

;; id nome descricao requer usa-dur params fn
(MET:Registrar
  "exemplo-regressao"
  "Exemplo: regressao potencial"
  "Q = a.A^b (A em km2). So um exemplo de cadastro."
  nil                                   ; funcionalidades exigidas, ex.: '("idf")
  nil                                   ; T = pergunta a duracao da chuva
  (list (list "A" "Coeficiente a" 1.0 "m3/s")
        (list "B" "Expoente b" 0.8 ""))
  'EXM:Regressao
)

;;; ------------------------------------------------------------
;;; 2) TIPO DE HIDROGRAMA
;;; fn recebe (ctx params); ctx = contexto da bacia + "METODO" + resultado do
;;; metodo ("QP" "PE" "TP" "VOLUME" ...). Devolve os PONTOS (t_min . q_m3s)
;;; ordenados por t, comecando em t = 0; ou (("ERRO" . "mensagem")).
;;; QP, TP, TB e VOLUME sao calculados pelo plugin a partir dos pontos.
;;; ------------------------------------------------------------
(defun EXM:Simetrico (ctx params / qp tc dt)
  (setq qp (cdr (assoc "QP" ctx)))
  (setq tc (cdr (assoc "TC" ctx)))
  (setq dt (cdr (assoc "DT" params)))
  (if (or (not qp) (<= qp 0.0) (not tc) (<= tc 0.0))
    (list (cons "ERRO" "Vazao de pico ou tc invalidos."))
    (list
      (cons "PONTOS"
        ;; HID:_Amostra reamostra em passo uniforme sem perder o pico
        (HID:_Amostra
          (list (cons 0.0 0.0) (cons tc qp) (cons (* 2.0 tc) 0.0))
          (if (and dt (> dt 0.0)) dt (HID:_DtAuto (* 2.0 tc)))
          (list tc)))
    )
  )
)

;; id nome descricao base requer-res params fn
(HID:RegistrarTipo
  "exemplo-simetrico"
  "Exemplo: triangular simetrico"
  "Sobe ate tc e desce em tc. So um exemplo de cadastro."
  "area"
  '("QP" "TC")                          ; chaves do resultado que o tipo exige
  (list (list "DT" "Passo de tempo (0 = automatico)" 0.0 "min"))
  'EXM:Simetrico
)

(HYDRO:Provide "exemplo-metodo" "1.0")
(princ)
