;;; ============================================================
;;; metodos_chuva_vazao.lsp - CATALOGO DE METODOS CHUVA-VAZAO (MET:)
;;;
;;; Cada metodo e CADASTRADO no catalogo "metodo-chuva-vazao" do core. Quem
;;; calcula (plugin bacia) apenas lista o catalogo; nao conhece nenhum metodo.
;;; Para criar um metodo novo basta cadastra-lo (aqui ou em qualquer outro
;;; .lsp que seja carregado). Modelo em docs/template_metodo.lsp.
;;;
;;; CONTRATO DE UM METODO
;;;   (MET:Registrar id nome descricao requer usa-dur params fn)
;;;     id        string unica ("racional")
;;;     nome      texto para menus
;;;     descricao texto curto (formula e limites)
;;;     requer    lista de funcionalidades obrigatorias ("idf")
;;;     usa-dur   T se o metodo usa uma duracao de chuva PROPRIA (alem do tc);
;;;               nil se a duracao e o proprio tc
;;;     params    lista de (chave rotulo padrao unidade [tipo [opcoes]])
;;;     fn        simbolo da funcao:  (fn ctx params) -> alist de resultado
;;;
;;;   ctx    = alist  "AREA" (m2)  "COMP" (m)  "DECL" (m/m)  "TC" (min)
;;;                   "TR" (anos)  "DUR" (min)
;;;   params = alist (chave . valor) com as respostas do usuario
;;;
;;;   resultado (so inclua o que o metodo realmente calcula):
;;;     "QP" (m3/s, vazao de pico)   "I" (mm/h)   "P" (mm, chuva total)
;;;     "PE" (mm, chuva efetiva)     "VOLUME" (m3)  "DUR" (min)  "TP" (min)
;;;   em caso de erro:  (("ERRO" . "mensagem"))
;;;
;;; Metodos incluidos: racional, scs-cn, vazao-informada.
;;; ============================================================
(vl-load-com)

;; Remove pares sem valor (nil nao deve ir para o resultado/armazenamento)
(defun MET:_Res (pares)
  (vl-remove-if (function (lambda (x) (null (cdr x)))) pares)
)

(defun MET:_Erro (msg)
  (list (cons "ERRO" msg))
)

;; Cadastra um metodo no catalogo e descreve seus parametros (rotulos para o
;; visualizador de dados: chave HYDRO.MET.<id>.<parametro>)
(defun MET:Registrar (id nome descricao requer usa-dur params fn / p)
  (HYDRO:RegAdd "metodo-chuva-vazao" id
    (list
      (cons "NOME" nome)
      (cons "DESC" descricao)
      (cons "REQUER" requer)
      (cons "USA-DUR" usa-dur)
      (cons "PARAMS" params)
      (cons "FN" fn)
    )
  )
  (foreach p params
    (HYDRO:SetLabel
      (strcat "HYDRO.MET." id "." (car p))
      (strcat nome " - " (cadr p))
      (nth 3 p)
    )
  )
  id
)

;;; ------------------------------------------------------------
;;; RACIONAL
;;; Q = C * i * A / 360   (Q em m3/s, i em mm/h, A em ha)
;;; Duracao da chuva = tc. Hipotese: chuva uniforme e area pequena.
;;; ------------------------------------------------------------
(defun MET:Racional (ctx params / area tc tr c i qp p pe)
  (setq area (cdr (assoc "AREA" ctx)))
  (setq tc   (cdr (assoc "TC" ctx)))
  (setq tr   (cdr (assoc "TR" ctx)))
  (setq c    (cdr (assoc "C" params)))
  (setq i    (PREC:Intensidade tc tr))
  (cond
    ((not i)
      (MET:_Erro "Intensidade indisponivel (IDF incompleta ou tc/TR invalidos).")
    )
    ((or (not c) (<= c 0.0) (> c 1.0))
      (MET:_Erro "O coeficiente C deve estar entre 0 e 1.")
    )
    (T
      (setq qp (/ (* c i (/ area 10000.0)) 360.0))
      (setq p  (/ (* i tc) 60.0))
      (setq pe (* c p))
      (MET:_Res
        (list
          (cons "QP" qp)
          (cons "I" i)
          (cons "P" p)
          (cons "PE" pe)
          (cons "VOLUME" (* (/ pe 1000.0) area))
          (cons "DUR" tc)
          (cons "TP" tc)
        )
      )
    )
  )
)

;;; ------------------------------------------------------------
;;; SCS-CN (NRCS) com hidrograma unitario triangular
;;;   S  = 25400/CN - 254                     (mm)
;;;   Ia = lambda * S                         (mm)
;;;   Pe = (P - Ia)^2 / (P - Ia + S),  P > Ia (mm)
;;;   tp = D/2 + 0.6 * tc                     (min)
;;;   Qp = 0.208 * A[km2] * Pe[mm] / tp[h]    (m3/s)
;;; D = duracao da chuva (informada pelo usuario). Chuva em bloco unico.
;;; ------------------------------------------------------------
(defun MET:ScsCn (ctx params / area tc tr dur cn lam i p s ia pe tp qp)
  (setq area (cdr (assoc "AREA" ctx)))
  (setq tc   (cdr (assoc "TC" ctx)))
  (setq tr   (cdr (assoc "TR" ctx)))
  (setq dur  (cdr (assoc "DUR" ctx)))
  (setq cn   (cdr (assoc "CN" params)))
  (setq lam  (cdr (assoc "LAMBDA" params)))
  (setq i    (PREC:Intensidade dur tr))
  (cond
    ((not i)
      (MET:_Erro "Intensidade indisponivel (IDF incompleta ou duracao/TR invalidos).")
    )
    ((or (not cn) (< cn 1.0) (> cn 100.0))
      (MET:_Erro "CN deve estar entre 1 e 100.")
    )
    ((or (not lam) (< lam 0.0))
      (MET:_Erro "Lambda (Ia/S) deve ser maior ou igual a zero.")
    )
    (T
      (setq p  (/ (* i dur) 60.0))
      (setq s  (- (/ 25400.0 cn) 254.0))
      (setq ia (* lam s))
      (setq pe (if (> p ia) (/ (expt (- p ia) 2.0) (+ (- p ia) s)) 0.0))
      (setq tp (+ (/ dur 2.0) (* 0.6 tc)))
      (setq qp (/ (* 0.208 (/ area 1.0e6) pe) (/ tp 60.0)))
      (MET:_Res
        (list
          (cons "QP" qp)
          (cons "I" i)
          (cons "P" p)
          (cons "PE" pe)
          (cons "VOLUME" (* (/ pe 1000.0) area))
          (cons "DUR" dur)
          (cons "TP" tp)
          (cons "S" s)
          (cons "IA" ia)
        )
      )
    )
  )
)

;;; ------------------------------------------------------------
;;; VAZAO INFORMADA
;;; O usuario fornece a vazao de pico (ex.: medida, de outro estudo).
;;; Nao calcula chuva efetiva nem volume; serve para gerar hidrogramas de
;;; forma (tipos que nao exigem PE).
;;; ------------------------------------------------------------
(defun MET:VazaoInformada (ctx params / qp tc)
  (setq qp (cdr (assoc "QP" params)))
  (setq tc (cdr (assoc "TC" ctx)))
  (if (or (not qp) (<= qp 0.0))
    (MET:_Erro "A vazao de pico deve ser maior que zero.")
    (MET:_Res
      (list
        (cons "QP" qp)
        (cons "DUR" tc)
        (cons "TP" tc)
      )
    )
  )
)

;;; ------------------------------------------------------------
;;; CADASTRO DOS METODOS INCLUIDOS
;;; ------------------------------------------------------------
(MET:Registrar
  "racional"
  "Racional"
  "Q = C.i.A/360 (pico). Duracao da chuva = tc. Areas pequenas."
  '("idf")
  nil
  (list (list "C" "Coeficiente de escoamento C" 0.6 ""))
  'MET:Racional
)

(MET:Registrar
  "scs-cn"
  "SCS-CN (HU triangular)"
  "Chuva efetiva pelo numero da curva CN; Qp = 0.208.A.Pe/tp; tp = D/2 + 0.6.tc."
  '("idf")
  T
  (list (list "CN" "Numero da curva CN (1 a 100)" 75.0 "")
        (list "LAMBDA" "Abstracao inicial Ia/S" 0.2 ""))
  'MET:ScsCn
)

(MET:Registrar
  "vazao-informada"
  "Vazao informada pelo usuario"
  "Usa a vazao de pico fornecida; sem chuva efetiva nem volume."
  nil
  nil
  (list (list "QP" "Vazao de pico" 1.0 "m3/s"))
  'MET:VazaoInformada
)

(HYDRO:Provide "metodos-chuva-vazao" "1.0")
(princ)
