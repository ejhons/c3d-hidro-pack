;;; ============================================================
;;; _template_plugin.lsp - MODELO PARA NOVOS PLUGINS
;;;
;;; Copie este arquivo, troque BACIA por o prefixo do seu plugin
;;; (3 a 5 letras maiusculas) e inclua o nome do arquivo em
;;; HYDRO:Manifest (core.lsp).
;;;
;;; REGRAS
;;;  1. Todo simbolo publico comeca com o prefixo:  BACIA:Calcular
;;;     Internos comecam com prefixo + _ :           BACIA:_Area
;;;  2. NENHUMA variavel global. Dados entram por argumento, saem por retorno.
;;;     Configuracao: HYDRO:Get / HYDRO:Set ("HYDRO.BACIA.xxx").
;;;  3. Toda variavel de funcao e declarada depois da barra: (defun f (a / x y)
;;;     (AutoLISP tem escopo dinamico: variavel nao declarada vaza.)
;;;  4. Funcoes de calculo sao PURAS (sem getXXX, sem alert, sem princ).
;;;     Interacao com o usuario fica nos comandos c:XXX.
;;;  5. Dependencia obrigatoria -> HYDRO:Require, no momento de usar.
;;;     Dependencia opcional   -> (if (HYDRO:Has "xdata") ...) ou eventos.
;;;  6. Nada que dependa de outro plugin deve rodar no momento do load.
;;; ============================================================
(vl-load-com)

;;; ---------- configuracao (sem globais) ----------
(defun BACIA:CoefRunoff ()
  (HYDRO:Get "HYDRO.RUNOFF" nil)
)

;;; ---------- calculo puro ----------
;; Recebe dados, devolve alist. Nao pergunta nem imprime nada.
(defun BACIA:Calcular (area_m2 comp decl / tc)
  (setq tc (* 57.0 (expt (/ (expt (/ comp 1000.0) 3.0) (* decl comp)) 0.385)))
  (list
    (cons "AREA" area_m2)
    (cons "TC" tc)
  )
)

;;; ---------- uso de um servico de outro plugin (dependencia obrigatoria) ----------
(defun BACIA:VazaoPara (tc tr area_m2 / i)
  (if (HYDRO:Require "precipitacao")
    (progn
      (setq i (PREC:Intensidade tc tr))
      (if i (/ (* (BACIA:CoefRunoff) i (/ area_m2 10000.0)) 360.0) nil)
    )
    nil
  )
)

;;; ---------- uso opcional de outro plugin (pergunta antes) ----------
(defun BACIA:_MarcaEntidade (en texto)
  (if (HYDRO:Has "xdata")
    (XD:Set en 1000 texto nil)
  )
)

;;; ---------- comando: so interacao + chamada das funcoes puras ----------
(defun c:BACIATESTE (/ en res)
  (setq en (car (entsel "\nSelecione a polilinha da bacia: ")))
  (if en
    (progn
      (setq res (BACIA:Calcular (vla-get-area (vlax-ename->vla-object en)) 1000.0 0.01))
      ;; avisa quem estiver interessado, sem saber quem e
      (HYDRO:Emit "bacia.calculada" (append res (list (cons "BACIA" en))))
      (princ (strcat "\nTc: " (rtos (cdr (assoc "TC" res)) 2 2) " min"))
    )
  )
  (princ)
)

(HYDRO:Provide "bacia" "0.1")
(princ)
