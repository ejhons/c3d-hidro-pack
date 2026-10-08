;;; ============================================================
;;; secao.lsp - DADOS E HIDRAULICA DAS SECOES DE SARJETA (SJT:)
;;;
;;; Parte de sistema: leitura das secoes, hidraulica (Izzard) e ultimo calculo.
;;; Comando, dialogo e desenho: views/secao_view.lsp (comando SECAO).
;;;
;;; O que o dialogo (view) mostra
;;;   - lista de secoes cadastradas (HYDRO.SECOES) e desenho da secao
;;;     transversal com cotas de h, w e s
;;;   - EXAGERO VERTICAL ESCOLHIDO PELO USUARIO (1x real, 2x, 5x, 10x) e
;;;     SEMPRE o mesmo para todas as secoes; o valor aparece no desenho
;;;     (V:H=5:1). A escala se ajusta para caber, o exagero nao.
;;;   - ESCALA COMUM (opcional): todas as secoes na mesma escala, para
;;;     comparar tamanhos
;;;   - ESCOAMENTO: dada a vazao Q e a declividade longitudinal S, calcula
;;;     (Izzard) e desenha a lamina d'agua na secao; avisa se a agua passa
;;;     do meio-fio ou da largura da secao
;;;   - "Selecionar" torna a secao a atual (HYDRO.SECAO.ATUAL)
;;;   - "Inserir no desenho" desenha a secao em escala real (com o exagero
;;;     escolhido) no modelo, na camada HYDRO-SECAO
;;;
;;; Integracao (sem acoplamento forte)
;;;   - Secoes:    SOB:Secoes se "sarjeta-obj" estiver carregado; senao le
;;;                HYDRO.SECOES direto
;;;   - Hidraulica: usa SOB:LaminaIzzard se "sarjeta-obj" estiver carregado;
;;;                sem ele, so desenha a secao
;;;   - Assina o evento "sarjeta.calculada" e guarda o ultimo Q/S
;;;     (HYDRO.ULTIMO.*) para o botao "Ultimo calculo"
;;;
;;; Sem variaveis globais.
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; DADOS
;;; ------------------------------------------------------------
;; Formato da secao: (id ("h" . m) ("s" . %) ("w" . m) ("n" . manning))
(defun SJT:Val (chave sec)
  (cdr (assoc chave (cdr sec)))
)

(defun SJT:Secoes ()
  (if (HYDRO:Has "sarjeta-obj")
    (SOB:Secoes)
    (HYDRO:Get "HYDRO.SECOES" nil)
  )
)

(defun SJT:Rotulo (sec)
  (strcat "Secao " (itoa (car sec))
          "  |  h=" (rtos (SJT:Val "h" sec) 2 2)
          "  s=" (rtos (SJT:Val "s" sec) 2 1) "%"
          "  w=" (rtos (SJT:Val "w" sec) 2 2))
)

;; Cadastra uma secao nova (id = maior id + 1), torna-a a atual e a devolve.
;; h = altura do meio-fio (m), s = caimento (%), w = largura (m), n = Manning
(defun SJT:Adicionar (h s w n / lista id sec)
  (setq lista (SJT:Secoes))
  (setq id (1+ (apply 'max (cons -1 (mapcar 'car lista)))))
  (setq sec (list id (cons "h" h) (cons "s" s) (cons "w" w) (cons "n" n)))
  (HYDRO:Set "HYDRO.SECOES" (append lista (list sec)))
  (HYDRO:Set "HYDRO.SECAO.ATUAL" id)
  sec
)

;; Secao pelo id, ou nil
(defun SJT:PorId (id)
  (assoc id (SJT:Secoes))
)

;; Troca os valores da secao id (mantem a posicao na lista). Devolve a secao nova ou nil.
(defun SJT:Editar (id h s w n / sec)
  (if (SJT:PorId id)
    (progn
      (setq sec (list id (cons "h" h) (cons "s" s) (cons "w" w) (cons "n" n)))
      (HYDRO:Set "HYDRO.SECOES"
        (mapcar (function (lambda (x) (if (= (car x) id) sec x))) (SJT:Secoes)))
      sec
    )
    nil
  )
)

;; Quantidade de sarjetas cadastradas que usam a secao id (0 se nao der para saber)
(defun SJT:EmUso (id / r)
  (setq r
    (if (and (HYDRO:Has "objetos") (HYDRO:Has "sarjeta-obj"))
      (vl-catch-all-apply
        (function
          (lambda (/ en n)
            (setq n 0)
            (foreach en (OBJ:ListaTipo "sarjeta")
              (if (equal (cdr (assoc "SECAO" (OBJ:AtribDe en))) id)
                (setq n (1+ n))
              )
            )
            n
          )
        )
        nil
      )
      0
    )
  )
  (if (numberp r) r 0)
)

;; Remove a secao id. Nunca remove a ultima. Se era a atual, a primeira restante
;; passa a atual. Devolve T se removeu.
(defun SJT:Remover (id / resto)
  (setq resto (vl-remove (SJT:PorId id) (SJT:Secoes)))
  (if (and (SJT:PorId id) resto)
    (progn
      (HYDRO:Set "HYDRO.SECOES" resto)
      (if (equal (HYDRO:Get "HYDRO.SECAO.ATUAL" 0) id)
        (HYDRO:Set "HYDRO.SECAO.ATUAL" (car (car resto)))
      )
      T
    )
    nil
  )
)

;; Ultimo calculo de sarjeta (gravado pelo assinante do evento)
(defun SJT:UltimoCalculo (/ q d)
  (setq q (HYDRO:Get "HYDRO.ULTIMO.Q" nil))
  (setq d (HYDRO:Get "HYDRO.ULTIMO.DECL" nil))
  (if (and q d)
    (list (cons "Q" q)
          (cons "DECL" d)
          (cons "SECAO" (HYDRO:Get "HYDRO.ULTIMO.SECAO" nil)))
    nil
  )
)

(defun SJT:_OnSarjetaCalculada (dados / q d id)
  (setq q  (cdr (assoc "Q" dados)))
  (setq d  (cdr (assoc "DECLIVIDADE" dados)))
  (setq id (cdr (assoc "SECAO-ID" dados)))
  (if (and q d)
    (progn
      (HYDRO:Set "HYDRO.ULTIMO.Q" q)
      (HYDRO:Set "HYDRO.ULTIMO.DECL" d)
      (if id (HYDRO:Set "HYDRO.ULTIMO.SECAO" id))
    )
  )
)

;;; ------------------------------------------------------------
;;; HIDRAULICA (puro). Retorna alist ou nil
;;; ------------------------------------------------------------
(defun SJT:Hidraulica (sec q sl / h s w n z y larg am)
  (if (and (HYDRO:Has "sarjeta-obj") sec q sl (> q 0.0) (> sl 0.0))
    (progn
      (setq h (SJT:Val "h" sec))
      (setq s (SJT:Val "s" sec))
      (setq w (SJT:Val "w" sec))
      (setq n (SJT:Val "n" sec))
      (if (and s (> s 0.0) n (> n 0.0))
        (progn
          (setq z    (/ 100.0 s))
          (setq y    (SOB:LaminaIzzard q z n sl))
          (setq larg (* y z))
          (setq am   (/ (* y larg) 2.0))
          (list
            (cons "Y" y)
            (cons "T" larg)
            (cons "AM" am)
            (cons "V" (/ q am))
            (cons "EXCEDE-H" (> y h))
            (cons "EXCEDE-W" (> larg w))
          )
        )
        nil
      )
    )
    nil
  )
)

;;; ------------------------------------------------------------
;;; INTEGRACAO
;;; ------------------------------------------------------------
(HYDRO:On "sarjeta.calculada" "secao" 'SJT:_OnSarjetaCalculada)

(HYDRO:SetLabel "HYDRO.ULTIMO.Q" "Vazao do ultimo calculo de sarjeta" "m3/s")
(HYDRO:SetLabel "HYDRO.ULTIMO.DECL" "Declividade longitudinal do ultimo calculo" "m/m")
(HYDRO:SetLabel "HYDRO.ULTIMO.SECAO" "Secao usada no ultimo calculo (id)" "")

;; Auditoria: a secao atual precisa existir na lista
(defun SJT:_AudAtual (/ id)
  (setq id (HYDRO:Get "HYDRO.SECAO.ATUAL" nil))
  (if (and id (not (SJT:PorId id)))
    (list (list "SECAO-ATUAL" id))
    nil
  )
)

(defun SJT:_TxtAtual (p)
  (strcat "A secao atual (" (itoa (cadr p)) ") nao esta cadastrada")
)

(defun SJT:_ReparaAtual (problemas)
  (HYDRO:Set "HYDRO.SECAO.ATUAL" (car (car (SJT:Secoes))))
  (length problemas)
)

(HYDRO:RegAdd "auditoria" "secao-atual"
  (list (cons "NOME" "Secao atual")
        (cons "VERIFICA" 'SJT:_AudAtual)
        (cons "TEXTO" 'SJT:_TxtAtual)
        (cons "REPARA" 'SJT:_ReparaAtual)))

(HYDRO:Provide "secao" "1.0")
(princ)
