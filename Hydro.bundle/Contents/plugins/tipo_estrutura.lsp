;;; ============================================================
;;; tipo_estrutura.lsp - CATALOGO DE TIPOS DE ESTRUTURA E CLASSES (TES:)
;;;
;;; Parte de sistema (como plugins/secao.lsp das sarjetas): gerencia o catalogo
;;; HYDRO.TIPOS.ESTRUTURA (criar, editar, remover, em uso, tipo atual) e o catalogo
;;; "classe-estrutura", onde cada CLASSE de estrutura cadastra o que ela sabe fazer.
;;; Comandos: views/tipo_estrutura_view.lsp. O objeto: plugins/models/estrutura.lsp.
;;;
;;; TIPO (o que o usuario cadastra; ex.: "Poco de visita", "Boca de lobo dupla grelha")
;;;   (id ("nome" . texto) ("classe" . id-da-classe) + os CAMPOS da classe)
;;;   Fabrica: Poco de visita, Caixa, Ala (classe "passagem", k = 0) e Boca de lobo
;;;   (classe "boca-lobo", capacidade 0: o usuario define a dele).
;;;
;;; CLASSE (catalogo "classe-estrutura"; ABERTO/FECHADO: classe nova = arquivo novo em
;;; plugins/registry/, sem alterar este nem o model). Cada classe e o seu proprio arquivo:
;;;   registry/estrutura_passagem.lsp    poco de visita, caixa, ala: repassa; perda de carga
;;;   registry/estrutura_boca_lobo.lsp   boca de lobo: captacao por metodo (catalogo proprio)
;;;   (TES:RegistrarClasse id nome campos valida rotulo calcula formata)
;;;     campos   lista de (chave rotulo padrao unidade [tipo [opcoes]]): os dados proprios do
;;;              tipo, perguntados pelo catalogo (HYDRO:AskParams; "opcoes" aceita o SIMBOLO de
;;;              uma funcao sem argumentos que devolve a lista na hora da pergunta)
;;;     valida   (fn valores) -> T se os valores (alist chave . valor dos campos) servem
;;;     rotulo   (fn tipo) -> texto curto dos dados do tipo (para listas)
;;;     calcula  (fn en ctx tipo dados) -> GRUPOS ((grupo . campos) ...) ou (("ERRO" . msg));
;;;              ctx = ("CENARIO" ..) ("TR" ..) ("METODO" ..) ("ENTRADA" ("QP" ..) ("TC" ..))
;;;              ("MONTANTES" ("V" . maior velocidade) ("Y" . maior lamina)); dados = ATRIB do objeto
;;;     formata  (fn en cenario) -> linhas de texto SO da classe (o model poe cabecalho e avisos)
;;;   CAMPOS DINAMICOS (opcional): (TES:ClasseExtra id "CAMPOS-FN" fn) com (fn valores) -> defs
;;;   (mesmo formato de `campos`) que dependem do que ja foi escolhido (ex.: o metodo do
;;;   dissipador traz os parametros dele). O catalogo pergunta primeiro `campos`, depois estes.
;;;
;;; Sem variaveis globais.
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; CLASSES
;;; ------------------------------------------------------------
;; Cadastra uma classe de estrutura (ver o cabecalho). Retorna o id.
(defun TES:RegistrarClasse (id nome campos valida rotulo calcula formata / c)
  (HYDRO:RegAdd "classe-estrutura" id
    (list
      (cons "NOME" nome)
      (cons "CAMPOS" campos)
      (cons "VALIDA" valida)
      (cons "ROTULO" rotulo)
      (cons "CALCULA" calcula)
      (cons "FORMATA" formata)
    )
  )
  (foreach c campos
    (HYDRO:SetLabel
      (strcat "HYDRO.TIPOEST." id "." (car c))
      (strcat nome " - " (cadr c))
      (nth 3 c)
    )
  )
  id
)

;; entrada da classe (alist) pelo id, ou nil
(defun TES:Classe (id)
  (if id (HYDRO:RegGet "classe-estrutura" id) nil)
)

;; Acrescenta (ou troca) uma chave extra na entrada de uma classe ja registrada (ex.: "CAMPOS-FN")
(defun TES:ClasseExtra (id chave valor / cl)
  (setq cl (TES:Classe id))
  (if cl
    (HYDRO:RegAdd "classe-estrutura" id (OBJ:SetChave cl chave valor))
  )
  id
)

;; defs dos campos da classe: os fixos (CAMPOS) mais os dinamicos (CAMPOS-FN valores), se ha
(defun TES:CamposDe (cl valores / fn)
  (setq fn (cdr (assoc "CAMPOS-FN" cl)))
  (append
    (cdr (assoc "CAMPOS" cl))
    (if fn (apply fn (list valores)) nil)
  )
)

;;; ------------------------------------------------------------
;;; TIPOS
;;; ------------------------------------------------------------
;; valor de uma chave de um tipo (id ("k" . v) ...)
(defun TES:Val (chave tipo)
  (cdr (assoc chave (cdr tipo)))
)

;; (puro, mas consulta o catalogo de classes) tipo validado: (id ("nome" . n) ("classe" . c)
;; + so os campos da classe), ou nil se nome vazio, classe desconhecida ou a classe recusar.
;;   valores : alist (chave . valor) dos campos da classe
(defun TES:_NovoTipo (id nome classe valores / cl out c)
  (setq cl (TES:Classe classe))
  (cond
    ((or (not nome) (equal nome "")) nil)
    ((not cl) nil)
    (T
      (foreach c (TES:CamposDe cl valores)
        (if (assoc (car c) valores)
          (setq out (append out (list (assoc (car c) valores))))
        )
      )
      (if (apply (cdr (assoc "VALIDA" cl)) (list out))
        (append (list id (cons "nome" nome) (cons "classe" classe)) out)
        nil
      )
    )
  )
)

;; tipos de fabrica (a boca de lobo traz capacidade 0: o usuario define a dele)
(defun TES:_TiposPadrao ()
  (list
    (list 0 (cons "nome" "Poco de visita") (cons "classe" "passagem") (cons "k" 0.0))
    (list 1 (cons "nome" "Caixa") (cons "classe" "passagem") (cons "k" 0.0))
    (list 2 (cons "nome" "Ala") (cons "classe" "passagem") (cons "k" 0.0))
    (list 3 (cons "nome" "Boca de lobo") (cons "classe" "boca-lobo")
          (cons "metodo" "unitaria") (cons "cap" 0.0))
  )
)

(defun TES:Tipos ()
  (HYDRO:Get "HYDRO.TIPOS.ESTRUTURA" (TES:_TiposPadrao))
)

(defun TES:TipoAtualId ()
  (HYDRO:Get "HYDRO.TIPO.ESTRUTURA.ATUAL" 0)
)

;; tipo (id ("k" . v) ...) pelo id, ou nil
(defun TES:Tipo (id)
  (assoc id (TES:Tipos))
)

;; texto de um tipo para listas: "Tipo n | nome | <rotulo da classe>"
(defun TES:Rotulo (tipo / cl fn)
  (setq cl (TES:Classe (TES:Val "classe" tipo)))
  (setq fn (if cl (cdr (assoc "ROTULO" cl)) nil))
  (strcat "Tipo " (itoa (car tipo)) "  |  " (TES:Val "nome" tipo) "  |  "
          (if fn (apply fn (list tipo)) (strcat "classe " (TES:Val "classe" tipo) " (nao carregada)")))
)

;; Cadastra um tipo novo (id = maior id + 1), torna-o o atual e o devolve (nil se invalido)
(defun TES:Adicionar (nome classe valores / lista id tipo)
  (setq lista (TES:Tipos))
  (setq id (1+ (apply 'max (cons -1 (mapcar 'car lista)))))
  (setq tipo (TES:_NovoTipo id nome classe valores))
  (if tipo
    (progn
      (HYDRO:Set "HYDRO.TIPOS.ESTRUTURA" (append lista (list tipo)))
      (HYDRO:Set "HYDRO.TIPO.ESTRUTURA.ATUAL" id)
      tipo
    )
    nil
  )
)

;; Troca os valores do tipo id (mantem a posicao). Devolve o tipo novo ou nil.
(defun TES:Editar (id nome classe valores / tipo)
  (setq tipo (TES:_NovoTipo id nome classe valores))
  (if (and tipo (TES:Tipo id))
    (progn
      (HYDRO:Set "HYDRO.TIPOS.ESTRUTURA"
        (mapcar (function (lambda (x) (if (= (car x) id) tipo x))) (TES:Tipos)))
      tipo
    )
    nil
  )
)

;; Quantas estruturas cadastradas usam o tipo id (0 se nao der para saber)
(defun TES:EmUso (id / r)
  (setq r
    (if (HYDRO:Has "objetos")
      (vl-catch-all-apply
        (function
          (lambda (/ en n)
            (setq n 0)
            (foreach en (OBJ:ListaTipo "estrutura")
              (if (equal (cdr (assoc "TIPO-EST" (OBJ:AtribDe en))) id) (setq n (1+ n)))
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

;; Remove o tipo id (nunca o ultimo). Se era o atual, o primeiro restante passa a atual.
(defun TES:Remover (id / resto)
  (setq resto (vl-remove (TES:Tipo id) (TES:Tipos)))
  (if (and (TES:Tipo id) resto)
    (progn
      (HYDRO:Set "HYDRO.TIPOS.ESTRUTURA" resto)
      (if (equal (TES:TipoAtualId) id)
        (HYDRO:Set "HYDRO.TIPO.ESTRUTURA.ATUAL" (car (car resto)))
      )
      T
    )
    nil
  )
)

;;; ------------------------------------------------------------
;;; INTEGRACAO
;;; ------------------------------------------------------------
(HYDRO:SetLabel "HYDRO.TIPOS.ESTRUTURA" "Tipos de estrutura cadastrados" "")
(HYDRO:SetLabel "HYDRO.TIPO.ESTRUTURA.ATUAL" "Tipo de estrutura atual (id)" "")

;; Auditoria: o tipo atual precisa existir no catalogo
(defun TES:_AudAtual (/ id)
  (setq id (HYDRO:Get "HYDRO.TIPO.ESTRUTURA.ATUAL" nil))
  (if (and id (not (TES:Tipo id)))
    (list (list "TIPO-ESTRUTURA-ATUAL" id))
    nil
  )
)

(defun TES:_TxtAtual (p)
  (strcat "O tipo de estrutura atual (" (itoa (cadr p)) ") nao esta cadastrado")
)

(defun TES:_ReparaAtual (problemas)
  (HYDRO:Set "HYDRO.TIPO.ESTRUTURA.ATUAL" (car (car (TES:Tipos))))
  (length problemas)
)

(HYDRO:RegAdd "auditoria" "tipo-estrutura-atual"
  (list (cons "NOME" "Tipo de estrutura atual")
        (cons "VERIFICA" 'TES:_AudAtual)
        (cons "TEXTO" 'TES:_TxtAtual)
        (cons "REPARA" 'TES:_ReparaAtual)))

(HYDRO:Provide "tipo-estrutura" "1.0")
(princ)
