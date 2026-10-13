;;; ============================================================
;;; hidrograma.lsp - HIDROGRAMAS DA BACIA (HID:)
;;;
;;; Gera o hidrograma de um CENARIO ja calculado da bacia (comando BACIA), usando o TIPO
;;; definido na bacia (ATRIB HIDROGRAMA-TIPO), GUARDA-o no grupo HIDROGRAMA desse cenario (RESULT,
;;; ver models/bacia.lsp), mostra um grafico com varios hidrogramas sobrepostos e uma tabela, e
;;; exporta a tabela em CSV. Um hidrograma por cenario; recalcular a vazao do cenario o remove.
;;;
;;; TIPOS DE HIDROGRAMA (catalogo "hidrograma-tipo" do core; cadastravel;
;;; os tipos incluidos ficam em registry/hidrograma_tipos.lsp)
;;;   baseados na AREA (usam area, tc, duracao e a chuva efetiva do metodo):
;;;     triangular-scs        triangular, tp = D/2 + 0.6.tc, tb = (tb/tp).tp
;;;     adimensional-scs      HU curvilineo adimensional do SCS
;;;   baseados no METODO (usam a vazao de pico do calculo):
;;;     racional-trapezoidal  sobe ate tc, patamar ate D, desce em tc
;;;   DEFINIDOS PELO USUARIO:
;;;     triangular-usuario    Qp, tp e tb/tp informados
;;;     tabela-usuario        pontos lidos de um arquivo CSV (absolutos ou
;;;                           adimensionais t/tp, q/qp)
;;;
;;; CONTRATO DE UM TIPO
;;;   (HID:RegistrarTipo id nome descricao base requer-res params fn)
;;;     base       "area" ou "usuario" (so informativo)
;;;     requer-res lista de chaves do resultado do metodo que o tipo exige
;;;                (ex.: ("PE")); o plugin avisa se o calculo nao as tem
;;;     params     lista de (chave rotulo padrao unidade [tipo [opcoes]])
;;;     fn         simbolo:  (fn ctx params) -> (("PONTOS" . ((t . q) ...))
;;;                                              ["NOTA" . texto])
;;;                ou (("ERRO" . msg))
;;;   ctx = caracteristicas da bacia + "TR" "DUR" "METODO" + resultado do
;;;         metodo ("QP" "PE" "TP" "VOLUME" ...). t em min, q em m3/s.
;;;   O plugin calcula QP, TP, TB e VOLUME a partir dos pontos.
;;;
;;; EVENTO EMITIDO
;;;   "hidrograma.gerado"  dados = "BACIA" (ename) "CENARIO" "TIPO" "METODO" "TR" "DUR"
;;;                        "QP" "TP" "TB" "VOLUME" "PONTOS"
;;;
;;; COMANDOS E VISUALIZADOR (views/hidrograma_view.lsp)
;;;   HIDROGRAMA      gera (e guarda) um hidrograma e abre o visualizador
;;;   HIDROGRAMAVER   abre o visualizador dos hidrogramas de uma bacia
;;;
;;; Depende de "bacia" (e, para os metodos, do que eles exigirem).
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; UTILITARIOS NUMERICOS
;;; ------------------------------------------------------------
(defun HID:_Erro (msg)
  (list (cons "ERRO" msg))
)

;; Interpolacao linear em pontos (t . q) ordenados; fora do intervalo,
;; devolve o valor da extremidade
(defun HID:_Interp (pontos tt / a b out)
  (cond
    ((null pontos) 0.0)
    ((<= tt (car (car pontos))) (cdr (car pontos)))
    ((>= tt (car (last pontos))) (cdr (last pontos)))
    (T
      (while (and (cdr pontos) (not out))
        (setq a (car pontos))
        (setq b (cadr pontos))
        (if (<= tt (car b))
          (setq out
            (if (> (- (car b) (car a)) 1e-12)
              (+ (cdr a)
                 (* (- (cdr b) (cdr a))
                    (/ (- tt (car a)) (- (car b) (car a)))))
              (cdr b)
            )
          )
          (setq pontos (cdr pontos))
        )
      )
      out
    )
  )
)

;; Reamostra em passo uniforme dt (min), incluindo o ultimo ponto e os
;; tempos "extras" (vertices que nao podem se perder, como o pico)
(defun HID:_Amostra (pontos dt extras / tmax ts t0 out tt)
  (setq tmax (car (last pontos)))
  (setq t0 0.0)
  (while (< t0 tmax)
    (setq ts (cons t0 ts))
    (setq t0 (+ t0 dt))
  )
  (setq ts (cons tmax ts))
  (setq ts
    (append
      ts
      (vl-remove-if
        (function (lambda (x) (or (< x 0.0) (> x tmax))))
        extras
      )
    )
  )
  (setq ts (vl-sort ts '<))
  (foreach tt ts
    (if (or (null out) (> (- tt (car out)) 1e-6))
      (setq out (cons tt out))
    )
  )
  (mapcar
    (function (lambda (x) (cons x (HID:_Interp pontos x))))
    (reverse out)
  )
)

;; Volume (m3) sob o hidrograma (t em min, q em m3/s)
(defun HID:_Volume (pontos / v a b)
  (setq v 0.0)
  (while (cdr pontos)
    (setq a (car pontos))
    (setq b (cadr pontos))
    (setq v (+ v (* (/ (+ (cdr a) (cdr b)) 2.0) (- (car b) (car a)) 60.0)))
    (setq pontos (cdr pontos))
  )
  v
)

;; Ponto de maior vazao (t . q)
(defun HID:_Pico (pontos / best p)
  (setq best (car pontos))
  (foreach p (cdr pontos)
    (if (> (cdr p) (cdr best)) (setq best p))
  )
  best
)

;; Passo "redondo" que de ~40 pontos ao longo da base
(defun HID:_DtAuto (tb / alvo c out)
  (setq alvo (/ tb 40.0))
  (foreach c '(0.5 1.0 2.0 5.0 10.0 15.0 30.0 60.0)
    (if (and (not out) (>= c alvo)) (setq out c))
  )
  (if out out 120.0)
)

;; Limite "bonito" para eixo: 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8 ou 10 x potencia de 10
(defun HID:_NiceMax (v / ex k e m f out)
  (if (<= v 0.0)
    1.0
    (progn
      (setq ex (/ (log v) (log 10.0)))
      (setq k (fix ex))
      (if (> k ex) (setq k (1- k)))
      (setq e (expt 10.0 k))
      (setq m (/ v e))
      (foreach f '(1.0 1.5 2.0 2.5 3.0 4.0 5.0 6.0 8.0 10.0)
        (if (and (not out) (>= f (- m 1e-9))) (setq out f))
      )
      (* out e)
    )
  )
)

;; Passo escolhido: o informado (>0) ou automatico a partir da base tb
(defun HID:_Dt (params tb / dt)
  (setq dt (cdr (assoc "DT" params)))
  (if (and dt (> dt 0.0)) dt (HID:_DtAuto tb))
)

;;; ------------------------------------------------------------
;;; CADASTRO DE TIPOS
;;; ------------------------------------------------------------
(defun HID:RegistrarTipo (id nome descricao base requer-res params fn / p)
  (HYDRO:RegAdd "hidrograma-tipo" id
    (list
      (cons "NOME" nome)
      (cons "DESC" descricao)
      (cons "BASE" base)
      (cons "REQUER-RES" requer-res)
      (cons "PARAMS" params)
      (cons "FN" fn)
    )
  )
  (foreach p params
    (HYDRO:SetLabel
      (strcat "HYDRO.HID." id "." (car p))
      (strcat nome " - " (cadr p))
      (nth 3 p)
    )
  )
  id
)

;;; ------------------------------------------------------------
;;; GERACAO (pura) E ARMAZENAMENTO
;;; ------------------------------------------------------------
(defun HID:_Limpa (pares)
  (vl-remove-if (function (lambda (x) (null (cdr x)))) pares)
)

;; Gera um hidrograma. Retorna a entrada (alist) ou (("ERRO" . msg))
(defun HID:Gerar (tipo-id ctx params / tipo falta r res pts pico)
  (setq tipo (HYDRO:RegGet "hidrograma-tipo" tipo-id))
  (cond
    ((not tipo)
      (HID:_Erro (strcat "Tipo de hidrograma nao cadastrado: " tipo-id))
    )
    (T
      (foreach r (cdr (assoc "REQUER-RES" tipo))
        (if (and (not falta) (not (assoc r ctx)))
          (setq falta r)
        )
      )
      (if falta
        (HID:_Erro
          (strcat "Este tipo exige o resultado '" falta
                  "' no calculo escolhido (ex.: metodo SCS-CN).")
        )
        (progn
          (setq res (apply (cdr (assoc "FN" tipo)) (list ctx params)))
          (if (assoc "ERRO" res)
            res
            (progn
              (setq pts (cdr (assoc "PONTOS" res)))
              (setq pico (HID:_Pico pts))
              (HID:_Limpa
                (list
                  (cons "CENARIO" (cdr (assoc "CENARIO" ctx)))
                  (cons "TIPO" tipo-id)
                  (cons "METODO" (cdr (assoc "METODO" ctx)))
                  (cons "TR" (cdr (assoc "TR" ctx)))
                  (cons "DUR" (cdr (assoc "DUR" ctx)))
                  (cons "PARAMS" params)
                  (cons "QP" (cdr pico))
                  (cons "TP" (car pico))
                  (cons "TB" (car (last pts)))
                  (cons "VOLUME" (HID:_Volume pts))
                  (cons "NOTA" (cdr (assoc "NOTA" res)))
                  (cons "PONTOS" pts)
                )
              )
            )
          )
        )
      )
    )
  )
)

;; (puro) Campos do grupo HIDROGRAMA do cenario, a partir do hidrograma plano de HID:Gerar.
;; VALOR = Qp; METODO e TR nao sao copiados (estao em VAZAO e CENARIO); PARAMS vira INPUT.
(defun HID:_Grupo (hid)
  (HID:_Limpa
    (list
      (cons "VALOR" (cdr (assoc "QP" hid)))
      (cons "TIPO" (cdr (assoc "TIPO" hid)))
      (cons "DUR" (cdr (assoc "DUR" hid)))
      (cons "TP" (cdr (assoc "TP" hid)))
      (cons "TB" (cdr (assoc "TB" hid)))
      (cons "VOLUME" (cdr (assoc "VOLUME" hid)))
      (cons "NOTA" (cdr (assoc "NOTA" hid)))
      (cons "INPUT" (cdr (assoc "PARAMS" hid)))
      (cons "PONTOS" (cdr (assoc "PONTOS" hid)))
    )
  )
)

;; Tipo de hidrograma definido na bacia (ATRIB HIDROGRAMA-TIPO); se ausente ou nao cadastrado,
;; "triangular-scs" (ou o primeiro cadastrado)
(defun HID:TipoDaBacia (en / id)
  (setq id (OBJ:_Val "HIDROGRAMA-TIPO" (OBJ:AtribDe en)))
  (cond
    ((and id (HYDRO:RegGet "hidrograma-tipo" id)) id)
    ((HYDRO:RegGet "hidrograma-tipo" "triangular-scs") "triangular-scs")
    (T (car (car (HYDRO:RegList "hidrograma-tipo"))))
  )
)

;; Guarda o hidrograma no grupo HIDROGRAMA do CENARIO (substitui o que havia)
(defun HID:Armazenar (en cenario hid)
  (OBJ:GravarResultado en cenario "HIDROGRAMA" (HID:_Grupo hid))
)

;;; ------------------------------------------------------------
;;; ROTULOS
;;; ------------------------------------------------------------
(defun HID:_NomeTipo (id / t1)
  (setq t1 (HYDRO:RegGet "hidrograma-tipo" id))
  (if t1 (cdr (assoc "NOME" t1)) id)
)

(defun HID:RotuloHid (h)
  (strcat (if (cdr (assoc "CENARIO" h)) (cdr (assoc "CENARIO" h))
            (strcat "TR " (HYDRO:FmtReal (cdr (assoc "TR" h)))))
          "  |  " (HID:_NomeTipo (cdr (assoc "TIPO" h)))
          "  |  Qp " (rtos (cdr (assoc "QP" h)) 2 3))
)

(defun HID:_RotuloTipo (item)
  (strcat
    "[" (if (equal (cdr (assoc "BASE" (cdr item))) "area") "area" "usuario") "] "
    (cdr (assoc "NOME" (cdr item))) "  -  "
    (cdr (assoc "DESC" (cdr item)))
  )
)


(HYDRO:SetLabel "HYDRO.HID.TIPO" "Ultimo tipo de hidrograma usado" "")

(HYDRO:Provide "hidrograma" "1.0")
(princ)
