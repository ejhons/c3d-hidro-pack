;;; ============================================================
;;; secao_tubo.lsp - DADOS DO CATALOGO DE SECCOES DE TUBO/CANAL (STB:)
;;;
;;; Parte de sistema, como plugins/secao.lsp e as sarjetas: gerencia o catalogo
;;; HYDRO.SECOES.TUBO (criar, editar, remover, em uso), a seccao atual, a hidraulica de
;;; uma seccao (adaptador sobre TUB:Resolver) e o ultimo calculo. Comandos, dialogo e
;;; desenho: views/secao_tubo_view.lsp (SECAOTUBO, CRIASECAOTUBO, EDITASECAOTUBO,
;;; REMOVESECAOTUBO).
;;;
;;; Formato da seccao (id ("forma" . "circular"|"retangular"|"trapezoidal")
;;;                       ("d" . m)             circular: diametro
;;;                       ("b" . m) ("h" . m)   retangular/trapezoidal: base e altura
;;;                       ("z" . m/m)           trapezoidal: talude z H : 1 V
;;;                       ("n" . manning))
;;;
;;; Integracao (sem acoplamento forte; igual a secao.lsp das sarjetas)
;;;   - Seccoes: TUB:Secoes se "tubo-obj" estiver carregado; senao le HYDRO.SECOES.TUBO direto
;;;   - Hidraulica: STB:Hidraulica usa TUB:Resolver (models/tubo.lsp); sem ele, nil
;;;   - Assina "objeto.calculado" (tipo "tubo") e guarda o ultimo Q/S (HYDRO.ULTIMO.TUBO.*)
;;;     para o botao "Ultimo calculo" do visualizador
;;;   - Auditoria "secao-tubo-atual": a seccao atual precisa existir no catalogo
;;;     (a de "tubo com seccao inexistente" fica em models/tubo.lsp)
;;;
;;; Sem variaveis globais.
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; DADOS
;;; ------------------------------------------------------------
;; valor de uma chave de uma seccao (id ("k" . v) ...)
(defun STB:Val (chave sec)
  (cdr (assoc chave (cdr sec)))
)

(defun STB:Secoes ()
  (if (HYDRO:Has "tubo-obj")
    (TUB:Secoes)
    (HYDRO:Get "HYDRO.SECOES.TUBO" nil)
  )
)

(defun STB:SecaoAtualId ()
  (HYDRO:Get "HYDRO.SECAO.TUBO.ATUAL" 0)
)

;; Seccao pelo id, ou nil
(defun STB:PorId (id)
  (assoc id (STB:Secoes))
)

;; texto curto de uma seccao (o do model, se carregado)
(defun STB:Rotulo (sec)
  (if (HYDRO:Has "tubo-obj")
    (TUB:RotuloSecao sec)
    (strcat "Secao " (itoa (car sec)))
  )
)

;; (puro) seccao validada: (id ("forma" . f) ...) so com as chaves da forma, ou nil se algum
;; valor e invalido (<= 0; z < 0). forma: "circular" (d), "retangular" (b h),
;; "trapezoidal" (b h z). Valores nao usados pela forma sao ignorados.
(defun STB:_NovaSecao (id forma d b h z n)
  (cond
    ((or (not n) (<= n 0.0)) nil)
    ((equal forma "circular")
      (if (and d (> d 0.0))
        (list id (cons "forma" forma) (cons "d" d) (cons "n" n))
        nil))
    ((equal forma "retangular")
      (if (and b h (> b 0.0) (> h 0.0))
        (list id (cons "forma" forma) (cons "b" b) (cons "h" h) (cons "n" n))
        nil))
    ((equal forma "trapezoidal")
      (if (and b h z (> b 0.0) (> h 0.0) (>= z 0.0))
        (list id (cons "forma" forma) (cons "b" b) (cons "h" h) (cons "z" z) (cons "n" n))
        nil))
    (T nil)
  )
)

;; Cadastra uma seccao nova (id = maior id + 1), torna-a a atual e a devolve (nil se invalida)
(defun STB:Adicionar (forma d b h z n / lista id sec)
  (setq lista (STB:Secoes))
  (setq id (1+ (apply 'max (cons -1 (mapcar 'car lista)))))
  (setq sec (STB:_NovaSecao id forma d b h z n))
  (if sec
    (progn
      (HYDRO:Set "HYDRO.SECOES.TUBO" (append lista (list sec)))
      (HYDRO:Set "HYDRO.SECAO.TUBO.ATUAL" id)
      sec
    )
    nil
  )
)

;; Troca os valores da seccao id (mantem a posicao). Devolve a seccao nova ou nil.
(defun STB:Editar (id forma d b h z n / sec)
  (setq sec (STB:_NovaSecao id forma d b h z n))
  (if (and sec (STB:PorId id))
    (progn
      (HYDRO:Set "HYDRO.SECOES.TUBO"
        (mapcar (function (lambda (x) (if (= (car x) id) sec x))) (STB:Secoes)))
      sec
    )
    nil
  )
)

;; Quantos tubos cadastrados usam a seccao id (0 se nao der para saber)
(defun STB:EmUso (id / r)
  (setq r
    (if (and (HYDRO:Has "objetos") (HYDRO:Has "tubo-obj"))
      (vl-catch-all-apply
        (function
          (lambda (/ en n)
            (setq n 0)
            (foreach en (OBJ:ListaTipo "tubo")
              (if (equal (cdr (assoc "SECAO" (OBJ:AtribDe en))) id) (setq n (1+ n)))
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

;; Remove a seccao id (nunca a ultima). Se era a atual, a primeira restante passa a atual.
(defun STB:Remover (id / resto)
  (setq resto (vl-remove (STB:PorId id) (STB:Secoes)))
  (if (and (STB:PorId id) resto)
    (progn
      (HYDRO:Set "HYDRO.SECOES.TUBO" resto)
      (if (equal (STB:SecaoAtualId) id)
        (HYDRO:Set "HYDRO.SECAO.TUBO.ATUAL" (car (car resto)))
      )
      T
    )
    nil
  )
)

;;; ------------------------------------------------------------
;;; HIDRAULICA (adaptador; puro). Retorna o resultado de TUB:Resolver ou nil
;;; ------------------------------------------------------------
(defun STB:Hidraulica (sec q sl / r)
  (if (and (HYDRO:Has "tubo-obj") sec q sl (> q 0.0) (> sl 0.0))
    (progn
      (setq r (TUB:Resolver sec sl (STB:Val "n" sec) q))
      (if (assoc "ERRO" r) nil r)
    )
    nil
  )
)

;;; ------------------------------------------------------------
;;; ULTIMO CALCULO (evento do core de ligacao; nunca atrapalha o calculo)
;;; ------------------------------------------------------------
;; (("Q" . m3/s) ("DECL" . m/m) ("SECAO" . id)) do ultimo tubo calculado, ou nil
(defun STB:UltimoCalculo (/ q d)
  (setq q (HYDRO:Get "HYDRO.ULTIMO.TUBO.Q" nil))
  (setq d (HYDRO:Get "HYDRO.ULTIMO.TUBO.DECL" nil))
  (if (and q d)
    (list (cons "Q" q) (cons "DECL" d)
          (cons "SECAO" (HYDRO:Get "HYDRO.ULTIMO.TUBO.SECAO" nil)))
    nil
  )
)

(defun STB:_Reage (dados / en cen q d id)
  (if (equal (cdr (assoc "TIPO" dados)) "tubo")
    (progn
      (setq en (cdr (assoc "OBJETO" dados)))
      (setq cen (cdr (assoc "CENARIO" dados)))
      (setq q (HYDRO:Val "VALOR" (OBJ:ResultGrupoDe en cen "ENTRADA")))
      (setq d (cdr (assoc "DECL" (OBJ:CaractDe en))))
      (setq id (cdr (assoc "SECAO" (OBJ:AtribDe en))))
      (if (and q d)
        (progn
          (HYDRO:Set "HYDRO.ULTIMO.TUBO.Q" q)
          (HYDRO:Set "HYDRO.ULTIMO.TUBO.DECL" d)
          (if id (HYDRO:Set "HYDRO.ULTIMO.TUBO.SECAO" id))
        )
      )
    )
  )
)

(defun STB:_OnCalculado (dados)
  (vl-catch-all-apply 'STB:_Reage (list dados))
)

;;; ------------------------------------------------------------
;;; INTEGRACAO
;;; ------------------------------------------------------------
(HYDRO:On "objeto.calculado" "secao-tubo" 'STB:_OnCalculado)

(HYDRO:SetLabel "HYDRO.ULTIMO.TUBO.Q" "Ultima vazao calculada em um tubo" "m3/s")
(HYDRO:SetLabel "HYDRO.ULTIMO.TUBO.DECL" "Ultima declividade calculada em um tubo" "m/m")
(HYDRO:SetLabel "HYDRO.ULTIMO.TUBO.SECAO" "Ultima secao de tubo calculada (id)" "")

;; Auditoria: a seccao atual precisa existir no catalogo
(defun STB:_AudAtual (/ id)
  (setq id (HYDRO:Get "HYDRO.SECAO.TUBO.ATUAL" nil))
  (if (and id (not (STB:PorId id)))
    (list (list "SECAO-TUBO-ATUAL" id))
    nil
  )
)

(defun STB:_TxtAtual (p)
  (strcat "A secao de tubo atual (" (itoa (cadr p)) ") nao esta cadastrada")
)

(defun STB:_ReparaAtual (problemas)
  (HYDRO:Set "HYDRO.SECAO.TUBO.ATUAL" (car (car (STB:Secoes))))
  (length problemas)
)

(HYDRO:RegAdd "auditoria" "secao-tubo-atual"
  (list (cons "NOME" "Secao de tubo atual")
        (cons "VERIFICA" 'STB:_AudAtual)
        (cons "TEXTO" 'STB:_TxtAtual)
        (cons "REPARA" 'STB:_ReparaAtual)))

(HYDRO:Provide "secao-tubo" "1.0")
(princ)
