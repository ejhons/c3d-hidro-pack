;;; ============================================================
;;; registry/hidrograma_tipos.lsp - TIPOS DE HIDROGRAMA (HID:)
;;;
;;; Catalogo: cada tipo e um CADASTRO no catalogo "hidrograma-tipo" (mecanismo,
;;; contrato e geracao em plugins/hidrograma.lsp). Para um tipo novo, crie
;;; outro arquivo em registry/ com outro HID:RegistrarTipo; nada daqui muda.
;;;
;;; Tipos incluidos: triangular-scs, adimensional-scs, racional-trapezoidal,
;;; triangular-usuario, tabela-usuario. Usam os utilitarios numericos de
;;; hidrograma.lsp (HID:_Interp, HID:_Amostra, HID:_Dt...).
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; LEITURA DE TABELA CSV DO USUARIO
;;; ------------------------------------------------------------
(defun HID:_Split (s sep / pos out)
  (while (setq pos (vl-string-search sep s))
    (setq out (append out (list (substr s 1 pos))))
    (setq s (substr s (+ pos 1 (strlen sep))))
  )
  (append out (list s))
)

;; Uma linha "a;b", "a,b", "a<TAB>b" ou "a b" -> (a . b) ; invalida -> nil
;; Com ";" ou tab, a virgula e decimal (Excel pt-BR).
(defun HID:_ParseLinha (linha / l sep partes a b)
  (setq l (vl-string-trim " \t" linha))
  (cond
    ((= l "") nil)
    ((= (substr l 1 1) "#") nil)
    (T
      (setq sep
        (cond
          ((vl-string-search ";" l) ";")
          ((vl-string-search "\t" l) "\t")
          ((vl-string-search "," l) ",")
          (T " ")
        )
      )
      (if (= sep " ")
        (while (vl-string-search "  " l)
          (setq l (vl-string-subst " " "  " l))
        )
      )
      (setq partes (HID:_Split l sep))
      (if (>= (length partes) 2)
        (progn
          (setq a (nth 0 partes))
          (setq b (nth 1 partes))
          (if (/= sep ",")
            (setq a (vl-string-subst "." "," a)
                  b (vl-string-subst "." "," b))
          )
          (setq a (distof (vl-string-trim " \t" a) 2))
          (setq b (distof (vl-string-trim " \t" b) 2))
          (if (and a b) (cons a b) nil)
        )
        nil
      )
    )
  )
)

;; Le o arquivo e devolve os pontos ordenados por t (ou nil)
(defun HID:_LerTabela (arq / f l p out)
  (setq f (open arq "r"))
  (if f
    (progn
      (while (setq l (read-line f))
        (setq p (HID:_ParseLinha l))
        (if p (setq out (cons p out)))
      )
      (close f)
      (vl-sort
        (reverse out)
        (function (lambda (a b) (< (car a) (car b))))
      )
    )
    nil
  )
)

;;; ------------------------------------------------------------
;;; TIPOS DE HIDROGRAMA
;;; ------------------------------------------------------------
;; HU curvilineo adimensional do SCS/NRCS (t/tp , q/qp)
(defun HID:_TabelaScs ()
  '((0.0 . 0.0) (0.1 . 0.015) (0.2 . 0.075) (0.3 . 0.16) (0.4 . 0.28)
    (0.5 . 0.43) (0.6 . 0.60) (0.7 . 0.77) (0.8 . 0.89) (0.9 . 0.97)
    (1.0 . 1.0) (1.1 . 0.98) (1.2 . 0.92) (1.3 . 0.84) (1.4 . 0.75)
    (1.5 . 0.66) (1.6 . 0.56) (1.7 . 0.49) (1.8 . 0.42) (1.9 . 0.36)
    (2.0 . 0.31) (2.2 . 0.22) (2.4 . 0.15) (2.6 . 0.107) (2.8 . 0.077)
    (3.0 . 0.055) (3.2 . 0.04) (3.4 . 0.029) (3.6 . 0.021) (3.8 . 0.015)
    (4.0 . 0.011) (4.5 . 0.005) (5.0 . 0.0))
)

;; Area (adimensional) sob uma tabela (t/tp , q/qp)
(defun HID:_AreaAdim (tab / v a b)
  (setq v 0.0)
  (while (cdr tab)
    (setq a (car tab))
    (setq b (cadr tab))
    (setq v (+ v (* (/ (+ (cdr a) (cdr b)) 2.0) (- (car b) (car a)))))
    (setq tab (cdr tab))
  )
  v
)

;; Volume do escoamento (m3) a partir do contexto: do metodo ou de Pe x area
(defun HID:_VolumeCtx (ctx / vol pe area)
  (setq vol  (cdr (assoc "VOLUME" ctx)))
  (setq pe   (cdr (assoc "PE" ctx)))
  (setq area (cdr (assoc "AREA" ctx)))
  (cond
    (vol vol)
    ((and pe area) (* (/ pe 1000.0) area))
    (T nil)
  )
)

;; tp do SCS (min): D/2 + 0.6 tc
(defun HID:_TpScs (ctx)
  (+ (/ (cdr (assoc "DUR" ctx)) 2.0) (* 0.6 (cdr (assoc "TC" ctx))))
)

;; --- triangular SCS: Qp = 2V/tb (conserva o volume; = 0.208.A.Pe/tp p/ tb = 2.67.tp)
(defun HID:TriangularScs (ctx params / vol tbtp tp tb qp dt)
  (setq vol  (HID:_VolumeCtx ctx))
  (setq tbtp (cdr (assoc "TBTP" params)))
  (cond
    ((not vol)
      (HID:_Erro "O metodo do calculo nao fornece chuva efetiva/volume.")
    )
    ((<= vol 0.0)
      (HID:_Erro "Volume escoado nulo (chuva menor que a abstracao inicial).")
    )
    ((or (not tbtp) (<= tbtp 1.0))
      (HID:_Erro "A relacao tb/tp deve ser maior que 1.")
    )
    (T
      (setq tp (HID:_TpScs ctx))
      (setq tb (* tbtp tp))
      (setq qp (/ (* 2.0 vol) (* tb 60.0)))
      (setq dt (HID:_Dt params tb))
      (list
        (cons "PONTOS"
          (HID:_Amostra (list (cons 0.0 0.0) (cons tp qp) (cons tb 0.0)) dt (list tp)))
      )
    )
  )
)

;; --- adimensional SCS: escala a tabela para conservar o volume
(defun HID:AdimensionalScs (ctx params / vol tab ar tp qp dt pts)
  (setq vol (HID:_VolumeCtx ctx))
  (setq tab (HID:_TabelaScs))
  (cond
    ((not vol)
      (HID:_Erro "O metodo do calculo nao fornece chuva efetiva/volume.")
    )
    ((<= vol 0.0)
      (HID:_Erro "Volume escoado nulo (chuva menor que a abstracao inicial).")
    )
    (T
      (setq ar (HID:_AreaAdim tab))
      (setq tp (HID:_TpScs ctx))
      (setq qp (/ vol (* ar tp 60.0)))
      (setq pts
        (mapcar
          (function (lambda (p) (cons (* (car p) tp) (* (cdr p) qp))))
          tab
        )
      )
      (setq dt (HID:_Dt params (car (last pts))))
      (list
        (cons "PONTOS" (HID:_Amostra pts dt (list tp)))
        (cons "NOTA" "Volume conservado; Qp ligeiramente diferente de 0.208.A.Pe/tp")
      )
    )
  )
)

;; --- trapezoidal do metodo racional: sobe ate tc, patamar ate D, desce em tc
(defun HID:RacionalTrapezoidal (ctx params / qp tc dur d dt)
  (setq qp  (cdr (assoc "QP" ctx)))
  (setq tc  (cdr (assoc "TC" ctx)))
  (setq dur (cdr (assoc "DUR" ctx)))
  (if (or (not qp) (<= qp 0.0) (not tc) (<= tc 0.0))
    (HID:_Erro "Vazao de pico ou tc invalidos.")
    (progn
      (setq d (max tc (if dur dur tc)))
      (setq dt (HID:_Dt params (+ d tc)))
      (list
        (cons "PONTOS"
          (HID:_Amostra
            (list (cons 0.0 0.0) (cons tc qp) (cons d qp) (cons (+ d tc) 0.0))
            dt
            (list tc d)))
      )
    )
  )
)

;; --- triangular definido pelo usuario: Qp, tp e tb/tp
(defun HID:TriangularUsuario (ctx params / qp tp tbtp tb dt)
  (setq qp   (cdr (assoc "QP" params)))
  (setq tp   (cdr (assoc "TP" params)))
  (setq tbtp (cdr (assoc "TBTP" params)))
  (cond
    ((or (not qp) (<= qp 0.0)) (HID:_Erro "Qp deve ser maior que zero."))
    ((or (not tp) (<= tp 0.0)) (HID:_Erro "tp deve ser maior que zero."))
    ((or (not tbtp) (<= tbtp 1.0)) (HID:_Erro "A relacao tb/tp deve ser maior que 1."))
    (T
      (setq tb (* tbtp tp))
      (setq dt (HID:_Dt params tb))
      (list
        (cons "PONTOS"
          (HID:_Amostra (list (cons 0.0 0.0) (cons tp qp) (cons tb 0.0)) dt (list tp)))
        (cons "NOTA" "Forma triangular informada pelo usuario (volume nao e conservado).")
      )
    )
  )
)

;; --- tabela do usuario (CSV): absoluta (t min, q m3/s) ou adimensional
(defun HID:TabelaUsuario (ctx params / arq modo tpu qpu dt pts qmax pico)
  (setq arq  (cdr (assoc "ARQ" params)))
  (setq modo (cdr (assoc "MODO" params)))
  (setq tpu  (cdr (assoc "TPU" params)))
  (setq qpu  (cdr (assoc "QPU" params)))
  (setq dt   (cdr (assoc "DT" params)))
  (cond
    ((or (not arq) (= arq "") (not (findfile arq)))
      (HID:_Erro "Arquivo CSV nao informado ou nao encontrado.")
    )
    (T
      (setq pts (HID:_LerTabela arq))
      (cond
        ((or (not pts) (< (length pts) 2))
          (HID:_Erro "O arquivo precisa ter ao menos 2 linhas numericas (t;q).")
        )
        ((equal modo "adimensional")
          (setq qmax (cdr (HID:_Pico pts)))
          (cond
            ((or (not tpu) (<= tpu 0.0) (not qpu) (<= qpu 0.0))
              (HID:_Erro "Informe tp e Qp (maiores que zero) para escalar a tabela.")
            )
            ((<= qmax 0.0)
              (HID:_Erro "A tabela nao tem vazao positiva.")
            )
            (T
              (setq pts
                (mapcar
                  (function
                    (lambda (p) (cons (* (car p) tpu) (* (/ (cdr p) qmax) qpu)))
                  )
                  pts
                )
              )
              (setq pico (HID:_Pico pts))
              (list
                (cons "PONTOS"
                  (if (and dt (> dt 0.0))
                    (HID:_Amostra pts dt (list (car pico)))
                    pts))
                (cons "NOTA" "Tabela adimensional escalada por tp e Qp informados.")
              )
            )
          )
        )
        (T
          (setq pico (HID:_Pico pts))
          (if (<= (cdr pico) 0.0)
            (HID:_Erro "A tabela nao tem vazao positiva.")
            (list
              (cons "PONTOS"
                (if (and dt (> dt 0.0))
                  (HID:_Amostra pts dt (list (car pico)))
                  pts))
              (cons "NOTA" "Tabela absoluta do usuario.")
            )
          )
        )
      )
    )
  )
)


;;; ------------------------------------------------------------
;;; CADASTRO DOS TIPOS INCLUIDOS
;;; ------------------------------------------------------------
(HID:RegistrarTipo
  "triangular-scs"
  "Triangular SCS"
  "tp = D/2 + 0.6.tc; Qp = 2V/tb (tb = relacao x tp). Usa area e chuva efetiva."
  "area"
  '("AREA" "TC" "DUR")
  (list (list "TBTP" "Relacao tb/tp (SCS = 2.67)" 2.67 "")
        (list "DT" "Passo de tempo (0 = automatico)" 0.0 "min"))
  'HID:TriangularScs
)

(HID:RegistrarTipo
  "adimensional-scs"
  "Adimensional curvilineo SCS"
  "HU curvilineo do SCS escalado por tp e pelo volume. Usa area e chuva efetiva."
  "area"
  '("AREA" "TC" "DUR")
  (list (list "DT" "Passo de tempo (0 = automatico)" 0.0 "min"))
  'HID:AdimensionalScs
)

(HID:RegistrarTipo
  "racional-trapezoidal"
  "Trapezoidal do metodo racional"
  "Sobe ate tc, patamar em Qp ate D, desce em tc. Usa a vazao de pico do calculo."
  "area"
  '("QP" "TC")
  (list (list "DT" "Passo de tempo (0 = automatico)" 0.0 "min"))
  'HID:RacionalTrapezoidal
)

(HID:RegistrarTipo
  "triangular-usuario"
  "Triangular definido pelo usuario"
  "Voce informa Qp, tp e tb/tp. Padroes vindos do calculo escolhido."
  "usuario"
  nil
  (list (list "QP" "Vazao de pico Qp" 1.0 "m3/s")
        (list "TP" "Tempo de pico tp" 10.0 "min")
        (list "TBTP" "Relacao tb/tp" 2.67 "")
        (list "DT" "Passo de tempo (0 = automatico)" 0.0 "min"))
  'HID:TriangularUsuario
)

(HID:RegistrarTipo
  "tabela-usuario"
  "Tabela do usuario (CSV)"
  "Pontos t;q lidos de arquivo, absolutos ou adimensionais (t/tp ; q/qp)."
  "usuario"
  nil
  (list (list "ARQ" "Arquivo CSV (colunas t;q)" "" "" "arquivo")
        (list "MODO" "Tabela em" "adimensional" "" "opcoes" '("absoluto" "adimensional"))
        (list "TPU" "tp para escalar (so adimensional)" 10.0 "min")
        (list "QPU" "Qp para escalar (so adimensional)" 1.0 "m3/s")
        (list "DT" "Passo de tempo (0 = manter pontos do arquivo)" 0.0 "min"))
  'HID:TabelaUsuario
)

(HYDRO:Provide "hidrograma-tipos" "1.0")
(princ)
