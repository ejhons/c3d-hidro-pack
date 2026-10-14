;;; ============================================================
;;; views/tipo_estrutura_view.lsp - COMANDOS DO CATALOGO DE TIPOS DE ESTRUTURA (TEV:)
;;;
;;;   TIPOESTRUTURA        lista o catalogo e escolhe o tipo atual (padrao do ESTRUTURACAD)
;;;   CRIATIPOESTRUTURA    cria um tipo: pede o nome, a CLASSE (passagem, boca de lobo...) e os
;;;                        campos que a classe declara
;;;   EDITATIPOESTRUTURA   edita um tipo (os valores atuais vem como padrao)
;;;   REMOVETIPOESTRUTURA  remove um tipo (recusa se alguma estrutura o usa; nunca o ultimo)
;;;
;;; Os dados e as regras ficam em plugins/tipo_estrutura.lsp (TES:); os campos de cada tipo vem
;;; da CLASSE (catalogo "classe-estrutura"): classe nova = pergunta nova, sem mexer aqui.
;;; Linha de comando, sem dialogo. Depende de "tipo-estrutura".
;;; ============================================================
(vl-load-com)

(defun TEV:_Ok ()
  (if (HYDRO:Has "tipo-estrutura")
    T
    (progn (alert "Plugin do catalogo de tipos de estrutura (tipo_estrutura.lsp) nao carregado.") nil)
  )
)

;; Escolhe a classe entre as cadastradas (uma so = usa direto). atual = id ou nil. nil se nenhuma.
(defun TEV:_PedeClasse (atual / lista idx i pos m)
  (setq lista (HYDRO:RegList "classe-estrutura"))
  (cond
    ((null lista)
      (alert "Nenhuma classe de estrutura carregada (plugins/registry/estrutura_*.lsp).")
      nil)
    ((= (length lista) 1) (car (car lista)))
    (T
      (setq i 0 pos 0)
      (foreach m lista
        (if (equal (car m) atual) (setq pos i))
        (setq i (1+ i))
      )
      (setq idx
        (HYDRO:Escolher "Classe da estrutura:"
          (mapcar (function (lambda (m) (cdr (assoc "NOME" (cdr m))))) lista)
          pos))
      (car (nth idx lista))
    )
  )
)

;; Pergunta os dados do tipo. tipo = atual (padroes) ou nil. Retorna (nome classe valores) ou nil
(defun TEV:_PedeDados (tipo / nome classe cl valores dyn pref atual)
  (setq nome (getstring T (strcat "\nNome" (if tipo (strcat " <" (TES:Val "nome" tipo) ">") "") ": ")))
  (if (or (not nome) (equal nome ""))
    (setq nome (if tipo (TES:Val "nome" tipo) nil))
  )
  (setq classe (TEV:_PedeClasse (if tipo (TES:Val "classe" tipo) nil)))
  (if classe
    (progn
      (setq cl (TES:Classe classe))
      (setq pref (strcat "HYDRO.TIPOEST." classe "."))
      ;; os valores atuais (so se a classe nao mudou) viram o padrao
      (setq atual (if (and tipo (equal classe (TES:Val "classe" tipo))) (cdr tipo) nil))
      ;; campos fixos da classe; depois os dinamicos (dependem do que acabou de ser escolhido)
      (setq valores (HYDRO:AskParams (cdr (assoc "CAMPOS" cl)) pref atual))
      (setq dyn (if (cdr (assoc "CAMPOS-FN" cl)) (apply (cdr (assoc "CAMPOS-FN" cl)) (list valores)) nil))
      (if dyn
        (setq valores (append valores (HYDRO:AskParams dyn pref atual)))
      )
      (list nome classe valores)
    )
    nil
  )
)

;; pergunta um id existente do catalogo (Enter = padrao); nil se invalido
(defun TEV:_PedeId (msg padrao / id)
  (setq id (getint (strcat "\n" msg " <" (itoa padrao) ">: ")))
  (if (not id) (setq id padrao))
  (if (TES:Tipo id)
    id
    (progn (princ (strcat "\nTipo " (itoa id) " nao existe (veja TIPOESTRUTURA).")) nil)
  )
)

(defun c:CRIATIPOESTRUTURA (/ d tipo)
  (if (TEV:_Ok)
    (progn
      (setq d (TEV:_PedeDados nil))
      (setq tipo (if d (TES:Adicionar (nth 0 d) (nth 1 d) (nth 2 d)) nil))
      (if tipo
        (princ (strcat "\nCriado e definido como atual: " (TES:Rotulo tipo)))
        (princ "\nValores invalidos para a classe escolhida (ex.: nome vazio; K < 0; capacidade <= 0): nada foi criado.")
      )
    )
  )
  (princ)
)

(defun c:EDITATIPOESTRUTURA (/ id tipo d novo)
  (if (TEV:_Ok)
    (progn
      (setq id (TEV:_PedeId "Id do tipo a editar" (TES:TipoAtualId)))
      (if id
        (progn
          (setq tipo (TES:Tipo id))
          (setq d (TEV:_PedeDados tipo))
          (setq novo (if d (TES:Editar id (nth 0 d) (nth 1 d) (nth 2 d)) nil))
          (if novo
            (princ
              (strcat "\nTipo atualizado: " (TES:Rotulo novo)
                      "\nRode CALCULAOBJETO nas estruturas deste tipo: os resultados antigos ficaram desatualizados."))
            (princ "\nValores invalidos: o tipo nao foi alterado.")
          )
        )
      )
    )
  )
  (princ)
)

(defun c:REMOVETIPOESTRUTURA (/ id em r)
  (if (TEV:_Ok)
    (progn
      (setq id (TEV:_PedeId "Id do tipo a remover" (TES:TipoAtualId)))
      (if id
        (progn
          (setq em (TES:EmUso id))
          (cond
            ((> em 0)
              (alert (strcat "O tipo " (itoa id) " e usado por " (itoa em)
                             " estrutura(s). Troque o tipo delas (ESTRUTURAEDITA) antes de remover.")))
            ((< (length (TES:Tipos)) 2)
              (alert "Nao e possivel remover o ultimo tipo do catalogo."))
            (T
              (initget "Sim Nao")
              (setq r (getkword (strcat "\nRemover " (TES:Rotulo (TES:Tipo id)) "? [Sim/Nao] <Nao>: ")))
              (if (equal r "Sim")
                (progn (TES:Remover id) (princ "\nTipo removido."))
              )
            )
          )
        )
      )
    )
  )
  (princ)
)

(defun c:TIPOESTRUTURA (/ tipo atual novo)
  (if (TEV:_Ok)
    (progn
      (setq atual (TES:TipoAtualId))
      (princ "\n=== TIPOS DE ESTRUTURA ===")
      (foreach tipo (TES:Tipos)
        (princ (strcat "\n" (if (equal (car tipo) atual) " * " "   ") (TES:Rotulo tipo)
                       "   (" (itoa (TES:EmUso (car tipo))) " estrutura(s))"))
      )
      (setq novo (getint (strcat "\nTipo atual <" (itoa atual) ">: ")))
      (if (and novo (TES:Tipo novo))
        (progn
          (HYDRO:Set "HYDRO.TIPO.ESTRUTURA.ATUAL" novo)
          (princ (strcat "\nTipo atual: " (TES:Rotulo (TES:Tipo novo))))
        )
        (if novo (princ (strcat "\nTipo " (itoa novo) " nao existe.")))
      )
    )
  )
  (princ)
)

(HYDRO:Provide "tipo-estrutura-view" "2.0")
(princ)
