;;; ============================================================
;;; registry/estrutura_boca_lobo.lsp - CLASSE DE ESTRUTURA "BOCA-LOBO" (EBL:)
;;;
;;; Boca de lobo: CAPTACAO por um metodo do catalogo "metodo-captacao"
;;; (registry/captacao.lsp; hoje "unitaria": capacidade unitaria x quantidade de bocas,
;;; PROPORCIONAL; simples = 1, dupla = 2, tripla = 3, atributo QTD do objeto). O metodo recebe
;;; vazao afluente, quantidade, LAMINA (maior ALTURA_LAMINA dos montantes, ou nil) e o tipo: e a
;;; brecha para vertedouro / orificio, cadastrados em arquivo novo sem alterar este.
;;;
;;; Vazao afluente maior que a capacidade: AVISO "Boca de lobo afogada". NAO divide a vazao
;;; (a saida segue igual a entrada, para nao mexer na integridade das ligacoes: uma origem, um
;;; destino); a parte que nao entra fica registrada em PASSAGEM.
;;;
;;; Campos do tipo: metodo (id do catalogo "metodo-captacao"), cap (m3/s, capacidade UNITARIA
;;; de uma boca, > 0; as demais chaves dependem do metodo).
;;; Grupos calculados: CAPACIDADE ("VALOR" . m3/s total) ("QTD" ..) ("METODO" ..),
;;;   CAPTACAO ("VALOR" . min(Q, Qcap)), PASSAGEM ("VALOR" . resto), RAZAO_CAPACIDADE
;;;   ("VALOR" . Q/Qcap), AVISOS ("VALOR" . lista).
;;; Sem fator de reducao por obstrucao/interferencia entre bocas (a capacidade informada ja e a
;;; do projetista). Catalogo "classe-estrutura" (plugins/tipo_estrutura.lsp).
;;; ============================================================
(vl-load-com)

;; ids dos metodos de captacao cadastrados (opcoes dinamicas do campo "metodo")
(defun EBL:_IdsMetodo (/ ids)
  (setq ids (mapcar 'car (HYDRO:RegList "metodo-captacao")))
  (if ids ids (list "unitaria"))
)

;; (puro) valores validos: capacidade unitaria > 0 e metodo texto nao vazio
(defun EBL:_Valida (valores / cap m)
  (setq cap (cdr (assoc "cap" valores)))
  (setq m (cdr (assoc "metodo" valores)))
  (if (and cap (numberp cap) (> cap 0.0) m (/= m "")) T nil)
)

(defun EBL:_Rotulo (tipo)
  (strcat "boca de lobo, " (TES:Val "metodo" tipo) ", cap. unit. "
          (rtos (TES:Val "cap" tipo) 2 4) " m3/s")
)

;; (puro, consulta o catalogo de metodos) captacao da boca de lobo.
;;   tipo : tipo do catalogo (classe "boca-lobo"); qtd : numero de bocas; q : vazao afluente
;;   lamina: altura da lamina (m) ou nil (so os metodos por equacao usam)
;;   retorno: (("QCAP" . total) ("CAPTADA" . min) ("PASSAGEM" . resto) ("RAZAO" . q/qcap)
;;             ("METODO" . id) ("AFOGADA" . T|nil) ("AVISOS" . lista)) ou (("ERRO" . msg))
(defun EBL:Captacao (tipo qtd q lamina / id m r qcap avisos afogada)
  (setq id (TES:Val "metodo" tipo))
  (setq m (HYDRO:RegGet "metodo-captacao" id))
  (cond
    ((not m) (list (cons "ERRO" (strcat "Metodo de captacao nao cadastrado: " (if id id "?")))))
    ((or (not qtd) (< qtd 1)) (list (cons "ERRO" "Quantidade de bocas deve ser 1 ou mais.")))
    ((or (not q) (<= q 0.0)) (list (cons "ERRO" "Nao ha vazao afluente.")))
    (T
      (setq r
        (apply (cdr (assoc "FN" m))
          (list (list (cons "Q" q) (cons "QTD" qtd) (cons "LAMINA" lamina)
                      (cons "TIPO" tipo)))))
      (setq qcap (cdr (assoc "QCAP" r)))
      (cond
        ((assoc "ERRO" r) r)
        ((or (not qcap) (<= qcap 0.0))
          (list (cons "ERRO"
            "Capacidade da boca de lobo nao definida: edite o tipo (EDITATIPOESTRUTURA).")))
        (T
          (setq afogada (if (> q qcap) T nil))
          (if afogada
            (setq avisos
              (list
                (strcat "Boca de lobo afogada: vazao afluente " (rtos q 2 3)
                        " m3/s maior que a capacidade " (rtos qcap 2 3) " m3/s ("
                        (itoa qtd) " boca(s)); " (rtos (- q qcap) 2 3) " m3/s nao entram"))))
          (list
            (cons "QCAP" qcap)
            (cons "CAPTADA" (min q qcap))
            (cons "PASSAGEM" (max 0.0 (- q qcap)))
            (cons "RAZAO" (/ q qcap))
            (cons "METODO" id)
            (cons "AFOGADA" afogada)
            (cons "AVISOS" avisos)
          )
        )
      )
    )
  )
)

;; Capacidade CALCULA da classe: grupos da captacao ou (("ERRO" . msg))
(defun EBL:_Calcula (en ctx tipo dados / qtd q y r)
  (setq qtd (cdr (assoc "QTD" dados)))
  (if (not qtd) (setq qtd 1))
  (setq q (cdr (assoc "QP" (cdr (assoc "ENTRADA" ctx)))))
  (setq y (cdr (assoc "Y" (cdr (assoc "MONTANTES" ctx)))))
  (setq r (EBL:Captacao tipo qtd q y))
  (if (assoc "ERRO" r)
    r
    (list
      (cons "CAPACIDADE"
        (list (cons "VALOR" (cdr (assoc "QCAP" r))) (cons "QTD" qtd)
              (cons "METODO" (cdr (assoc "METODO" r)))))
      (cons "CAPTACAO" (list (cons "VALOR" (cdr (assoc "CAPTADA" r)))))
      (cons "PASSAGEM" (list (cons "VALOR" (cdr (assoc "PASSAGEM" r)))))
      (cons "RAZAO_CAPACIDADE" (list (cons "VALOR" (cdr (assoc "RAZAO" r)))))
      (cons "AVISOS" (list (cons "VALOR" (cdr (assoc "AVISOS" r)))))
    )
  )
)

;; linhas so da classe (capacidade FORMATA: (fn en cenario))
(defun EBL:_Formata (en cenario / g)
  (setq g (OBJ:ResultGrupoDe en cenario "CAPACIDADE"))
  (if (OBJ:_Val "VALOR" g)
    (list
      (strcat "Capacidade: " (rtos (OBJ:_Val "VALOR" g) 2 3) " m3/s ("
              (itoa (OBJ:_Val "QTD" g)) " boca(s))   captada: "
              (rtos (OBJ:_Val "VALOR" (OBJ:ResultGrupoDe en cenario "CAPTACAO")) 2 3)
              " m3/s   passagem: "
              (rtos (OBJ:_Val "VALOR" (OBJ:ResultGrupoDe en cenario "PASSAGEM")) 2 3) " m3/s"))
    nil
  )
)

(if (HYDRO:Has "tipo-estrutura")
  (TES:RegistrarClasse
    "boca-lobo"
    "Boca de lobo"
    (list
      (list "metodo" "Metodo de captacao" "unitaria" "" "opcoes" 'EBL:_IdsMetodo)
      (list "cap" "Capacidade UNITARIA de uma boca" 0.0 "m3/s"))
    'EBL:_Valida 'EBL:_Rotulo 'EBL:_Calcula 'EBL:_Formata)
)

(HYDRO:Provide "estrutura-boca-lobo" "1.0")
(princ)
