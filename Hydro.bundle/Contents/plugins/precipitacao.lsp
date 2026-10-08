;;; ============================================================
;;; precipitacao.lsp - HIETOGRAMAS DE PROJETO (HIET:)
;;;
;;; Gera o hietograma (distribuicao da chuva no tempo) de uma chuva de
;;; projeto. CONSOME o plugin idf (PREC:Intensidade): a chuva total e a que a
;;; equacao IDF da para a duracao e o tempo de retorno pedidos.
;;;
;;; TIPOS DE HIETOGRAMA (catalogo "hietograma-tipo" do core; cadastravel)
;;; Os tipos incluidos ficam em registry/hietograma_tipos.lsp. Este arquivo so
;;; tem o mecanismo: catalogo, validacao e geracao.
;;;
;;; CONTRATO DE UM TIPO
;;;   (HIET:RegistrarTipo id nome descricao params fn)
;;;     params  lista de (chave rotulo padrao unidade [tipo [opcoes]])
;;;     fn      simbolo:  (fn ctx params) -> (("BLOCOS" . ((t1 t2 mm mmh) ...))
;;;                                           ["NOTA" . texto])
;;;                       ou (("ERRO" . msg))
;;;   ctx = (("TR" . anos) ("DUR" . min) ("DT" . min) ("N" . blocos))
;;;         DT ja ajustado: DUR = N . DT (N inteiro >= 1)
;;;   bloco = (t-inicio t-fim chuva-mm intensidade-mm/h), tempos em min
;;;
;;; API
;;;   (HIET:Profundidade dur tr)   chuva acumulada (mm) em dur min: i . dur / 60
;;;   (HIET:Gerar tipo-id tr dur params)  ->
;;;       (("TIPO" . id) ("TR" . anos) ("DUR" . min) ("DT" . min)
;;;        ("TOTAL" . mm) ("BLOCOS" . (...)) ["NOTA" . texto])
;;;       ou (("ERRO" . msg))
;;;   O total sempre vale i(dur) . dur / 60 (a IDF), em qualquer tipo.
;;;
;;; Funcoes puras: sem interacao. Depende de "idf".
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; UTILITARIOS
;;; ------------------------------------------------------------
(defun HIET:_Erro (msg)
  (list (cons "ERRO" msg))
)

(defun HIET:_Limpa (pares)
  (vl-remove-if (function (lambda (x) (null (cdr x)))) pares)
)

;; i . x (mm.min/h): "profundidade" da IDF antes de dividir por 60
(defun HIET:_H (x tr / i)
  (if (<= x 0.0)
    0.0
    (progn
      (setq i (PREC:Intensidade x tr))
      (if i (* x i) nil)
    )
  )
)

;; Chuva acumulada (mm) de uma chuva de duracao dur (min) com tempo de retorno tr
(defun HIET:Profundidade (dur tr / h)
  (setq h (HIET:_H dur tr))
  (if h (/ h 60.0) nil)
)

;; (t1 t2 mm) -> (t1 t2 mm mm/h)
(defun HIET:_Bloco (t1 t2 mm)
  (list t1 t2 mm (/ mm (/ (- t2 t1) 60.0)))
)

;; valores consecutivos -> blocos de largura dt a partir de t = 0
(defun HIET:_Blocos (vals dt / k out v)
  (setq k 0)
  (foreach v vals
    (setq out
      (append out (list (HIET:_Bloco (* k dt) (* (1+ k) dt) v))))
    (setq k (1+ k))
  )
  out
)

;;; ------------------------------------------------------------
;;; CATALOGO DE TIPOS
;;; ------------------------------------------------------------
(defun HIET:RegistrarTipo (id nome descricao params fn / p)
  (HYDRO:RegAdd "hietograma-tipo" id
    (list
      (cons "NOME" nome)
      (cons "DESC" descricao)
      (cons "PARAMS" params)
      (cons "FN" fn)
    )
  )
  (foreach p params
    (HYDRO:SetLabel
      (strcat "HYDRO.HIET." id "." (car p))
      (strcat nome " - " (cadr p))
      (nth 3 p)
    )
  )
  id
)

;;; ------------------------------------------------------------
;;; GERACAO
;;; ------------------------------------------------------------
;; Passo e numero de blocos: DT do usuario ajustado para dividir DUR em
;; N intervalos iguais. Sem DT valido, um unico bloco.
(defun HIET:_Passo (dur params / dt n)
  (setq dt (cdr (assoc "DT" params)))
  (if (not (and dt (> dt 0.0))) (setq dt dur))
  (setq n (max 1 (fix (+ 0.5 (/ dur dt)))))
  (list n (/ dur n))
)

(defun HIET:Gerar (tipo-id tr dur params / tipo passo n dt ctx res blocos)
  (setq tipo (HYDRO:RegGet "hietograma-tipo" tipo-id))
  (cond
    ((not (HYDRO:Has "idf"))
      (HIET:_Erro "Plugin idf nao carregado.")
    )
    ((not tipo)
      (HIET:_Erro (strcat "Tipo de hietograma nao cadastrado: " tipo-id))
    )
    ((not (PREC:Params))
      (HIET:_Erro "Parametros IDF nao definidos.")
    )
    ((not (and tr (> tr 0.0)))
      (HIET:_Erro "Tempo de retorno invalido.")
    )
    ((not (and dur (> dur 0.0)))
      (HIET:_Erro "Duracao invalida.")
    )
    ((not (PREC:Intensidade dur tr))
      (HIET:_Erro "A IDF nao tem valor para esta duracao (duracao + b = 0).")
    )
    (T
      (setq passo (HIET:_Passo dur params))
      (setq n (car passo))
      (setq dt (cadr passo))
      (setq ctx
        (list (cons "TR" tr) (cons "DUR" dur) (cons "DT" dt) (cons "N" n)))
      (setq res
        (vl-catch-all-apply (cdr (assoc "FN" tipo)) (list ctx params)))
      (cond
        ((vl-catch-all-error-p res)
          (HIET:_Erro (strcat "Falha ao gerar o hietograma: " (vl-catch-all-error-message res)))
        )
        ((assoc "ERRO" res) res)
        (T
          (setq blocos (cdr (assoc "BLOCOS" res)))
          (HIET:_Limpa
            (list
              (cons "TIPO" tipo-id)
              (cons "TR" tr)
              (cons "DUR" dur)
              (cons "DT" dt)
              (cons "TOTAL" (apply '+ (mapcar 'caddr blocos)))
              (cons "BLOCOS" blocos)
              (cons "NOTA" (cdr (assoc "NOTA" res)))
            )
          )
        )
      )
    )
  )
)

(HYDRO:Provide "precipitacao" "1.0")
(princ)
