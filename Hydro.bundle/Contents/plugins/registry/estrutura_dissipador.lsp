;;; ============================================================
;;; registry/estrutura_dissipador.lsp - CLASSE DE ESTRUTURA "DISSIPADOR" (EDI:)
;;;
;;; Dissipador de energia no fim de um tubo, canal ou escada: recebe a vazao e REPASSA (o core de
;;; ligacao grava ENTRADA e VAZAO) e aplica o METODO do tipo (catalogo "metodo-dissipacao"):
;;;   informado, usbr, enrocamento (ver registry/dissipacao*.lsp). O tipo guarda o metodo e os
;;;   PARAMETROS que o metodo declara (campos dinamicos: CRIATIPOESTRUTURA pergunta primeiro o
;;;   metodo e depois os parametros dele).
;;;
;;; BALANCO DE ENERGIA (certo; sem equacao empirica), quando o metodo informa a energia de saida:
;;;   E_in = y + V^2/(2 g), g = 9.81, com y e V do montante (maior ALTURA_LAMINA e maior VELOCIDADE
;;;   entre os objetos de montante, no cenario) ou o E_in que o proprio metodo redefina;
;;;   dissipacao dE = E_in - E_out; potencia P = 9.81 x Q x dE (kW; rho g Q dH).
;;; Metodo sem energia de saida (enrocamento) so devolve os grupos dele.
;;;
;;; Campo fixo do tipo: metodo (id do catalogo "metodo-dissipacao"); os demais vem do metodo.
;;; Grupos calculados: ENERGIA_ENTRADA ("VALOR" . m) ("INPUT" ("Y" ..) ("V" ..)),
;;;   ENERGIA_SAIDA ("VALOR" . m) ("METODO" ..), DISSIPACAO ("VALOR" . m) ("EFICIENCIA" ..),
;;;   POTENCIA_DISSIPADA ("VALOR" . kW), os GRUPOS do metodo e AVISOS ("VALOR" . lista).
;;; Catalogo "classe-estrutura" (plugins/tipo_estrutura.lsp). Depende de "tipo-estrutura".
;;; ============================================================
(vl-load-com)

;; ids dos metodos de dissipacao cadastrados (opcoes dinamicas do campo "metodo")
(defun EDI:_IdsMetodo (/ ids)
  (setq ids (mapcar 'car (HYDRO:RegList "metodo-dissipacao")))
  (if ids ids (list "informado"))
)

;; campos dinamicos: os PARAMS do metodo escolhido em `valores`
(defun EDI:_CamposMetodo (valores / m)
  (setq m (HYDRO:RegGet "metodo-dissipacao" (cdr (assoc "metodo" valores))))
  (if m (cdr (assoc "PARAMS" m)) nil)
)

;; (puro) energia especifica y + V^2/(2 g) (m); nil se faltar dado
(defun EDI:EnergiaEspecifica (y v)
  (if (and y v (>= y 0.0) (>= v 0.0))
    (+ y (/ (* v v) (* 2.0 9.81)))
    nil
  )
)

;; (puro) potencia dissipada em kW: 9.81 x Q x dE
(defun EDI:Potencia (q de)
  (if (and q de (>= q 0.0) (>= de 0.0)) (* 9.81 q de) nil)
)

;; (consulta o catalogo) valores validos: metodo cadastrado e, se ele tem VALIDA, aceito por ele
(defun EDI:_Valida (valores / id m fn)
  (setq id (cdr (assoc "metodo" valores)))
  (setq m (if (and id (/= id "")) (HYDRO:RegGet "metodo-dissipacao" id) nil))
  (setq fn (if m (cdr (assoc "VALIDA" m)) nil))
  (cond
    ((not m) nil)
    (fn (if (apply fn (list valores)) T nil))
    (T T)
  )
)

(defun EDI:_Rotulo (tipo / m)
  (setq m (HYDRO:RegGet "metodo-dissipacao" (TES:Val "metodo" tipo)))
  (strcat "dissipador, " (if m (cdr (assoc "NOME" m)) (TES:Val "metodo" tipo))
          (if (TES:Val "eficiencia" tipo)
            (strcat ", eficiencia " (rtos (* 100.0 (TES:Val "eficiencia" tipo)) 2 1) " %")
            ""))
)

;; (consulta o catalogo de metodos) balanco do dissipador.
;;   retorno: (("EIN" . m|nil) ("EOUT" . m|nil) ("DISSIPADA" . m|nil) ("EFICIENCIA" ..|nil)
;;             ("POTENCIA" . kW|nil) ("METODO" . id) ("GRUPOS" ..) ("AVISOS" ..)) ou (("ERRO" . msg))
(defun EDI:Balanco (tipo q y v fr / id m ein r eout)
  (setq id (TES:Val "metodo" tipo))
  (setq m (HYDRO:RegGet "metodo-dissipacao" id))
  (setq ein (EDI:EnergiaEspecifica y v))
  (if (not m)
    (list (cons "ERRO" (strcat "Metodo de dissipacao nao cadastrado: " (if id id "?"))))
    (progn
      (setq r
        (apply (cdr (assoc "FN" m))
          (list (list (cons "Q" q) (cons "Y" y) (cons "V" v) (cons "FR" fr)
                      (cons "EIN" ein) (cons "TIPO" tipo)))))
      (if (assoc "ERRO" r)
        r
        (progn
          (if (cdr (assoc "EIN" r)) (setq ein (cdr (assoc "EIN" r))))
          (setq eout (cdr (assoc "EOUT" r)))
          (cond
            ((and eout (or (not ein) (< eout 0.0) (> eout (+ ein 1e-9))))
              (list (cons "ERRO" "O metodo devolveu energia de saida invalida (negativa ou maior que a de entrada).")))
            (T
              (list
                (cons "EIN" ein)
                (cons "EOUT" eout)
                (cons "DISSIPADA" (if (and ein eout) (- ein eout) nil))
                (cons "EFICIENCIA" (if (and ein eout (> ein 0.0)) (/ (- ein eout) ein) nil))
                (cons "POTENCIA" (if (and ein eout) (EDI:Potencia q (- ein eout)) nil))
                (cons "METODO" id)
                (cons "GRUPOS" (cdr (assoc "GRUPOS" r)))
                (cons "AVISOS" (cdr (assoc "AVISOS" r)))
              )
            )
          )
        )
      )
    )
  )
)

;; Capacidade CALCULA da classe: grupos do balanco + os do metodo, ou (("ERRO" . msg))
(defun EDI:_Calcula (en ctx tipo dados / mont q r)
  (setq mont (cdr (assoc "MONTANTES" ctx)))
  (setq q (cdr (assoc "QP" (cdr (assoc "ENTRADA" ctx)))))
  (setq r
    (EDI:Balanco tipo q (cdr (assoc "Y" mont)) (cdr (assoc "V" mont)) (cdr (assoc "FR" mont))))
  (if (assoc "ERRO" r)
    r
    (append
      (if (cdr (assoc "EIN" r))
        (list
          (cons "ENERGIA_ENTRADA"
            (list (cons "VALOR" (cdr (assoc "EIN" r)))
                  (cons "INPUT" (list (cons "Y" (cdr (assoc "Y" mont))) (cons "V" (cdr (assoc "V" mont))))))))
        nil)
      (if (cdr (assoc "EOUT" r))
        (list
          (cons "ENERGIA_SAIDA"
            (list (cons "VALOR" (cdr (assoc "EOUT" r))) (cons "METODO" (cdr (assoc "METODO" r)))))
          (cons "DISSIPACAO"
            (list (cons "VALOR" (cdr (assoc "DISSIPADA" r))) (cons "EFICIENCIA" (cdr (assoc "EFICIENCIA" r)))))
          (cons "POTENCIA_DISSIPADA" (list (cons "VALOR" (cdr (assoc "POTENCIA" r))))))
        nil)
      (cdr (assoc "GRUPOS" r))
      (list (cons "AVISOS" (list (cons "VALOR" (cdr (assoc "AVISOS" r))))))
    )
  )
)

;; linhas so da classe (capacidade FORMATA: (fn en cenario))
(defun EDI:_Formata (en cenario / v linhas)
  (setq v (HYDRO:Val "VALOR" (OBJ:ResultGrupoDe en cenario "ENERGIA_ENTRADA")))
  (if (HYDRO:Val "VALOR" (OBJ:ResultGrupoDe en cenario "ENERGIA_SAIDA"))
    (setq linhas
      (list
        (strcat "Energia: entrada " (rtos v 2 3) " m -> saida "
                (rtos (HYDRO:Val "VALOR" (OBJ:ResultGrupoDe en cenario "ENERGIA_SAIDA")) 2 3)
                " m   dissipada " (rtos (HYDRO:Val "VALOR" (OBJ:ResultGrupoDe en cenario "DISSIPACAO")) 2 3)
                " m ("
                (rtos (* 100.0 (HYDRO:Val "EFICIENCIA" (OBJ:ResultGrupoDe en cenario "DISSIPACAO"))) 2 1) " %)")
        (strcat "Potencia dissipada: "
                (rtos (HYDRO:Val "VALOR" (OBJ:ResultGrupoDe en cenario "POTENCIA_DISSIPADA")) 2 2) " kW"))))
  linhas
)

(if (HYDRO:Has "tipo-estrutura")
  (progn
    (TES:RegistrarClasse
      "dissipador"
      "Dissipador de energia"
      (list
        (list "metodo" "Metodo de dissipacao" "informado" "" "opcoes" 'EDI:_IdsMetodo))
      'EDI:_Valida 'EDI:_Rotulo 'EDI:_Calcula 'EDI:_Formata)
    (TES:ClasseExtra "dissipador" "CAMPOS-FN" 'EDI:_CamposMetodo)
  )
)

(HYDRO:Provide "estrutura-dissipador" "2.0")
(princ)
