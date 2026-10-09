;;; ============================================================
;;; objetos.lsp - OBJETOS HIDRAULICOS (OBJ:)
;;;
;;; MECANISMO GENERICO para transformar qualquer entidade do desenho em um
;;; "objeto hidraulico" de um TIPO. Os tipos ficam no catalogo
;;; "objeto-hidraulico" do core. Para criar um tipo novo basta CADASTRA-LO
;;; (em um .lsp novo): nenhum arquivo existente precisa ser alterado
;;; (principio aberto/fechado). Modelo em docs/template_objeto.lsp.
;;;
;;; O QUE E UM TIPO (catalogo "objeto-hidraulico")
;;;   (OBJ:RegistrarTipo id nome descricao aceita params recebe emite extras)
;;;     id         string unica ("sarjeta", "trecho"...)
;;;     aceita     nomes DXF das entidades que podem ser deste tipo
;;;                ("LWPOLYLINE" "LINE" "AECC_PIPE" ...)
;;;     params     dados proprios do objeto: lista de
;;;                (chave rotulo padrao unidade [tipo [opcoes]])
;;;     recebe     T se o tipo pode receber afluentes (outros objetos
;;;                descarregando nele)
;;;     emite      T se o tipo pode descarregar em outros objetos
;;;     extras     alist OPCIONAL de capacidades (todas sao opcionais):
;;;       ("CADASTRAVEL" . nil)    nao aparece em OBJETO (ex.: bacia, que tem
;;;                                cadastro proprio)
;;;       ("DETECTA" . fn)         (fn en) -> T se reconhece a entidade sem
;;;                                cadastro de objeto (ex.: bacia)
;;;       ("NOME-FN" . fn)         (fn en) -> nome para exibir
;;;       ("RESUMO" . fn)          (fn en) -> lista de linhas de texto
;;;       ("TOSTRING" . fn)        (fn en) -> UMA string (linhas separadas por
;;;                                newline) descrevendo o objeto, como toString()
;;;       ("PADROES" . fn)         (fn en) -> alist de padroes dos params
;;;       ("REGRA" . fn)           (fn tipo-origem tipo-destino) -> nil/T (ok)
;;;                                ou STRING com o motivo da recusa
;;;       ("VAZAO-EM" . fn)        (fn en metodo tr tc) -> resultado do metodo
;;;                                chuva-vazao (alist com "QP", opcional "VOLUME")
;;;                                gerado por ESTE objeto sozinho, reavaliado no tc
;;;                                dado, ou nil (sem calculo). Ex.: bacia
;;;       ("RECALCULA" . fn)       (fn en metodo tr) -> nil se recalculou, ou STRING com o
;;;                                erro; recalculo SEM perguntas, usado para atualizar os
;;;                                montantes (sem ela, o tipo usa o calculo generico de
;;;                                ligacao.lsp). Ex.: bacia
;;;       ("TEMPO-MODO" . texto)   "concentracao" (bacia) ou "percurso" (padrao):
;;;                                como o tempo de saida combina os montantes
;;;                                (ver ligacao.lsp)
;;;       ("AREA-PROPRIA" . fn)    (fn en) -> area contribuinte (m2) ou nil
;;;       ("DESTINO-PADRAO" . fn)  (fn en) -> ename sugerido como destino
;;;       ("EDITAR" . fn)          (fn en) -> edicao propria do tipo (usada
;;;                                pelas tabelas; sem ela, usa OBJETO)
;;;       ("PARAMS-CALCULO" . defs) params extras do calculo
;;;       ("CALCULA" . fn)         (fn en ctx params) -> alist de resultado
;;;                                ou (("ERRO" . msg)); ver CALCULAOBJETO
;;;       ("FORMATA" . fn)         (fn res) -> lista de linhas do resultado
;;;
;;; INTERFACE PADRAO DO OBJETO (portas e adapters; docs/arquitetura.md secao 18)
;;; Cada objeto do desenho guarda o MESMO registro (envelope HYDRO-OBJ):
;;;     (("VERSAO" . 2) ("TIPO" . id) ("NOME" . n) ("DESCRICAO" . texto)
;;;      ("PARAMS" . alist)   ligacoes com OUTROS objetos: "TALVEGUE" . handle (so a
;;;                           bacia) e "MONTANTE" . ((handle . flag) ...) de qualquer objeto
;;;                           que receba (flag T = compartilha o talvegue; ver ligacao.lsp)
;;;      ("ATRIB"  . alist)   valores definidos pelo usuario, nao extraidos do desenho
;;;      ("CARACT" . alist)   o que se obtem do desenho (area, comprimento...)
;;;      ("RESULT" . alist)   tudo que e CALCULADO, em GRUPOS com nome:
;;;                           ("TC" . alist) ("ENTRADA" . (entrada ...))
;;;                           ("VAZAO" . (entrada ...)) = SAIDA (vazao e tempo entregues)
;;;                           ("HIDROGRAMAS" . (...)) ("HIDRAULICA" . (entrada ...))
;;;   entrada = campos calculados PLANOS, com METODO e TR como identidade:
;;;             (("METODO" . id) ("TR" . x) ("QP" . m3/s) ("LAMINA" . m) ...)
;;;   Leitura generica (qualquer tipo): OBJ:Registro, OBJ:NomeGravado,
;;;   OBJ:DescricaoDe, OBJ:ParamsDe, OBJ:AtribDe, OBJ:CaractDe, OBJ:ResultDe,
;;;   OBJ:GrupoDe (um grupo de RESULT), OBJ:VazaoDe. Gravacao: OBJ:GravarResultado.
;;;
;;;   PORTA DE ARMAZENAMENTO. Padrao (classe base): grava o envelope. Um tipo
;;;   que precisa de gravacao, indice ou remocao proprios (ex.: bacia, que
;;;   indexa em HYDRO.BACIAS e emite "bacia.removida") fornece as operacoes
;;;   dele; o REGISTRO continua sendo o padrao. Declara
;;;       ("ARMAZENAMENTO" . (("LER" . fn) ("GRAVAR" . fn) ("LISTAR" . fn)
;;;                           ("REINDEXAR" . fn) ("REMOVER" . fn)))
;;;       LER        (fn en)        -> registro padrao ou nil
;;;       GRAVAR     (fn en reg)    -> reg ou nil (grava e indexa)
;;;       LISTAR     (fn)           -> enames dos objetos do tipo
;;;       REINDEXAR  (fn)           -> quantidade (varre o desenho)
;;;       REMOVER    (fn en)        -> T (emite o evento antes de apagar)
;;;   OBJ:RegistrarTipo recusa o tipo com armazenamento incompleto e avisa
;;;   quais operacoes faltam. Uso: OBJ:GravaRegistro, OBJ:ListaTipo,
;;;   OBJ:ReindexaTipo, OBJ:Remover.
;;;   Capacidade opcional ("CARACTERIZA" . fn): (fn en) -> alist gravada em
;;;   CARACT ao cadastrar (ex.: comprimento e declividade da sarjeta).
;;;   O argumento `params` de OBJ:RegistrarTipo DESCREVE os campos de ATRIB
;;;   (fica no catalogo sob a chave "ATRIB-DEFS").
;;;
;;; DADOS GUARDADOS: chave "HYDRO-OBJ" (qualquer entidade, inclusive Civil 3D;
;;; ver HYDRO:DadoGravar no core). Indice: HYDRO.OBJETOS (handles).
;;;
;;; EVENTOS EMITIDOS
;;;   "objeto.cadastrado"  "OBJETO" (ename) "TIPO"
;;;   "objeto.removido"    "OBJETO" (ename)      (emitido ANTES de apagar)
;;;
;;; COMANDOS
;;;   OBJETO         cadastra/edita uma entidade como objeto hidraulico
;;;   OBJETOINFO     mostra os dados de um objeto
;;;   OBJETOREMOVER  remove o cadastro de objeto
;;; (as ligacoes entre objetos estao em ligacao.lsp)
;;; ============================================================
(vl-load-com)

;;; ------------------------------------------------------------
;;; UTILITARIOS
;;; ------------------------------------------------------------

;; Remove de uma alist os pares cujo valor e nil.
;;   pares : alist ((chave . valor) ...)
;;   retorno: a mesma alist sem os pares de valor nil
;; Existe porque NUNCA se grava par com valor nil nos dados persistidos
;; (ldata/extensao da entidade): usada antes de gravar o registro.
(defun OBJ:_Limpa (pares)
  (vl-remove-if (function (lambda (x) (null (cdr x)))) pares)
)

;; Le o valor de uma chave numa alist.
;;   chave : chave a procurar (normalmente string)
;;   dados : alist (pode ser nil: nesse caso devolve nil)
;;   retorno: o valor do par, ou nil se a chave nao existir
;; Atalho de (cdr (assoc chave dados)); e a base de todas as leituras do registro.
(defun OBJ:_Val (chave dados)
  (cdr (assoc chave dados))
)

;; Devolve uma copia da alist com a chave trocada (ou removida).
;;   dados : alist original
;;   chave : chave a definir
;;   valor : novo valor; se for nil a chave e REMOVIDA (nao grava par nil)
;;   retorno: nova alist; o par novo vai para o FIM da lista
;; Nao altera a lista original (AutoLISP e funcional aqui).
(defun OBJ:_SetChave (dados chave valor)
  (if valor
    (append (vl-remove (assoc chave dados) dados) (list (cons chave valor)))
    (vl-remove (assoc chave dados) dados)
  )
)

;; Comparador "menor que" para handles (strings hexadecimais), usado no vl-sort.
;;   h1, h2 : handles como string
;;   retorno: T se h1 vem antes de h2
;; Handles hexadecimais de tamanhos diferentes nao se comparam como texto
;; ("A" > "10" no texto, mas 10 hex > A hex). Por isso compara primeiro o
;; tamanho e so depois o texto, o que da a ordem numerica correta.
(defun OBJ:_HandleLt (h1 h2)
  (if (= (strlen h1) (strlen h2))
    (< h1 h2)
    (< (strlen h1) (strlen h2))
  )
)

;; Formata um valor qualquer como texto para mostrar ao usuario.
;;   v : nil, real, inteiro, string ou qualquer outro tipo
;;   retorno: "-" para nil; real via HYDRO:FmtReal (formato do core);
;;            inteiro com itoa; string como esta; o resto como texto de prin1
(defun OBJ:_FmtVal (v)
  (cond
    ((null v) "-")
    ((= (type v) 'REAL) (HYDRO:FmtReal v))
    ((= (type v) 'INT) (itoa v))
    ((= (type v) 'STR) v)
    (T (vl-prin1-to-string v))
  )
)

;;; ------------------------------------------------------------
;;; CATALOGO DE TIPOS
;;; ------------------------------------------------------------

;; Lista as operacoes que um ARMAZENAMENTO proprio deve implementar.
;;   retorno: ("LER" "GRAVAR" "LISTAR" "REINDEXAR" "REMOVER")
;; E o "contrato" da porta de armazenamento (ver o cabecalho do arquivo).
(defun OBJ:OpsContrato ()
  '("LER" "GRAVAR" "LISTAR" "REINDEXAR" "REMOVER")
)

;; Operacoes do contrato que faltam no armazenamento proprio declarado
;; (sem ARMAZENAMENTO: usa o padrao e nada falta)
;;   extras : alist de capacidades passada a OBJ:RegistrarTipo
;;   retorno: lista com os nomes das operacoes ausentes, ou nil se o tipo
;;            nao declara ARMAZENAMENTO ou declara todas
(defun OBJ:OpsFaltando (extras / ops)
  (setq ops (assoc "ARMAZENAMENTO" extras))
  (if ops
    (vl-remove-if
      (function (lambda (op) (cdr (assoc op (cdr ops)))))
      (OBJ:OpsContrato))
    nil
  )
)

;; PONTO DE ENTRADA para cadastrar um tipo de objeto hidraulico no catalogo.
;;   id, nome, descricao, aceita, params, recebe, emite, extras : ver o
;;   cabecalho do arquivo ("O QUE E UM TIPO")
;;   retorno: o id se cadastrou; nil se recusou
;; Antes de cadastrar valida o contrato de armazenamento: se o tipo declarou
;; ARMAZENAMENTO incompleto, registra no log quais operacoes faltam e NAO
;; cadastra (evita falha so em tempo de uso). O cadastro de fato e feito por
;; OBJ:_RegistrarTipo.
(defun OBJ:RegistrarTipo (id nome descricao aceita params recebe emite extras / falta)
  (setq falta (OBJ:OpsFaltando extras))
  (if falta
    (progn
      (HYDRO:Log
        (strcat "Tipo de objeto '" id "' NAO registrado: faltam "
                (HYDRO:Join falta ", ") "."))
      (setq id nil)
    )
  )
  (if id (OBJ:_RegistrarTipo id nome descricao aceita params recebe emite extras))
  id
)

;; Grava o tipo no catalogo "objeto-hidraulico" (sem validar o contrato).
;;   mesmos argumentos de OBJ:RegistrarTipo
;;   retorno: o id
;; Cada tipo vira uma entrada (id . alist) com NOME, DESC, ACEITA, ATRIB-DEFS
;; (os params), RECEBE, EMITE, seguidos das capacidades extras. Alem disso
;; registra um rotulo (HYDRO:SetLabel) para cada param, na chave
;; "HYDRO.OBJ.<id>.<param>", que as telas usam para mostrar nome e unidade.
(defun OBJ:_RegistrarTipo (id nome descricao aceita params recebe emite extras / p)
  (HYDRO:RegAdd "objeto-hidraulico" id
    (append
      (list
        (cons "NOME" nome)
        (cons "DESC" descricao)
        (cons "ACEITA" aceita)
        (cons "ATRIB-DEFS" params)
        (cons "RECEBE" recebe)
        (cons "EMITE" emite)
      )
      extras
    )
  )
  (foreach p params
    (HYDRO:SetLabel
      (strcat "HYDRO.OBJ." id "." (car p))
      (strcat nome " - " (cadr p))
      (nth 3 p)
    )
  )
  id
)

;; Lista todos os tipos cadastrados.
;;   retorno: lista de (id . dados), na ordem do catalogo
(defun OBJ:Tipos ()
  (HYDRO:RegList "objeto-hidraulico")
)

;; Dados de um tipo.
;;   id : id do tipo (string)
;;   retorno: alist do tipo (NOME, DESC, ACEITA, ... e capacidades), ou nil
(defun OBJ:TipoDados (id)
  (HYDRO:RegGet "objeto-hidraulico" id)
)

;; valor de uma capacidade do tipo (flag, funcao, lista...)
;;   id    : id do tipo
;;   chave : nome da capacidade ("RESUMO", "EDITAR", "ATRIB-DEFS"...)
;;   retorno: o valor, ou nil se o tipo nao tem essa capacidade
;; Quem chama costuma testar o retorno antes de aplicar (apply fn ...).
(defun OBJ:Cap (id chave)
  (cdr (assoc chave (OBJ:TipoDados id)))
)

;; Nome amigavel do tipo, para mensagens.
;;   id : id do tipo (pode ser nil)
;;   retorno: "-" se id for nil; o NOME do catalogo; ou "<id> (tipo ausente)"
;;            se a entidade guarda um tipo que nao esta carregado
(defun OBJ:_NomeTipo (id / d)
  (setq d (OBJ:TipoDados id))
  (cond
    ((not id) "-")
    (d (cdr (assoc "NOME" d)))
    (T (strcat id " (tipo ausente)"))
  )
)

;; "CADASTRAVEL" so e falso se estiver presente e valer nil
;;   dados : alist de dados do tipo
;;   retorno: T ou nil (nunca o valor): ausente => T; presente e nil => nil
(defun OBJ:_Cadastravel (dados / a)
  (setq a (assoc "CADASTRAVEL" dados))
  (if a (if (cdr a) T nil) T)
)

;; Tipos cadastraveis que aceitam o nome DXF dado (puro). (id . dados)
;;   dxf : nome DXF da entidade, ex.: "LWPOLYLINE"
;;   retorno: lista de (id . dados) dos tipos que aceitam esse DXF e que nao
;;            estao marcados como nao cadastraveis (ex.: bacia fica de fora)
(defun OBJ:TiposPara (dxf / out t1)
  (foreach t1 (OBJ:Tipos)
    (if (and (OBJ:_Cadastravel (cdr t1))
             (member dxf (OBJ:_Val "ACEITA" (cdr t1))))
      (setq out (append out (list t1)))
    )
  )
  out
)

;; Texto de uma opcao de tipo para a lista de escolha.
;;   item : (id . dados) de um tipo
;;   retorno: "NOME  -  DESCRICAO"
(defun OBJ:_RotuloTipo (item)
  (strcat (cdr (assoc "NOME" (cdr item))) "  -  " (cdr (assoc "DESC" (cdr item))))
)

;;; ------------------------------------------------------------
;;; REGISTRO NA ENTIDADE
;;; ------------------------------------------------------------

;; Le o registro cru gravado na entidade (chave "HYDRO-OBJ").
;;   en : ename
;;   retorno: o envelope (alist) ou nil se a entidade nao tem cadastro
;; Leitura direta, sem passar pelo ARMAZENAMENTO do tipo; para leitura
;; generica use OBJ:Registro.
(defun OBJ:Ler (en)
  (HYDRO:DadoLer en "HYDRO-OBJ")
)

;; Inclui o handle da entidade no indice HYDRO.OBJETOS (sem duplicar).
;;   en : ename
;; O indice evita varrer o desenho inteiro para listar os objetos.
(defun OBJ:_Indexar (en / h lista)
  (setq h (HYDRO:Handle en))
  (setq lista (HYDRO:Get "HYDRO.OBJETOS" nil))
  (if (not (member h lista))
    (HYDRO:Set "HYDRO.OBJETOS" (append lista (list h)))
  )
)

;; Tira o handle da entidade do indice HYDRO.OBJETOS.
;;   en : ename
(defun OBJ:_Desindexar (en)
  (HYDRO:Set "HYDRO.OBJETOS"
    (vl-remove (HYDRO:Handle en) (HYDRO:Get "HYDRO.OBJETOS" nil)))
)

;; Tipo reconhecido automaticamente (sem cadastro de objeto), ex.: bacia
;;   en : ename
;;   retorno: id do primeiro tipo cuja capacidade DETECTA devolve T, ou nil
;; Percorre os tipos na ordem do catalogo e para no primeiro que reconhecer.
(defun OBJ:_Detecta (en / out t1 fn)
  (foreach t1 (OBJ:Tipos)
    (setq fn (cdr (assoc "DETECTA" (cdr t1))))
    (if (and (not out) fn)
      (if (apply fn (list en)) (setq out (car t1)))
    )
  )
  out
)

;; id do tipo da entidade: cadastro de objeto (se o tipo existe) ou deteccao
;;   en : ename
;;   retorno: id do tipo, ou nil se a entidade nao e um objeto hidraulico
;; Se o TIPO gravado na entidade nao esta mais no catalogo (plugin nao
;; carregado), cai na deteccao automatica em vez de devolver um tipo invalido.
(defun OBJ:TipoDe (en / id)
  (setq id (OBJ:_Val "TIPO" (OBJ:Ler en)))
  (if (and id (OBJ:TipoDados id))
    id
    (OBJ:_Detecta en)
  )
)

;;; ------------------------------------------------------------
;;; PORTA DE ARMAZENAMENTO: DESPACHO E IMPLEMENTACAO PADRAO (classe base)
;;; ------------------------------------------------------------

;; Implementacao propria do tipo para a operacao (ou nil = usar o padrao)
;;   id : id do tipo
;;   op : "LER", "GRAVAR", "LISTAR", "REINDEXAR" ou "REMOVER"
;;   retorno: a funcao declarada em ARMAZENAMENTO, ou nil
(defun OBJ:Op (id op)
  (cdr (assoc op (cdr (assoc "ARMAZENAMENTO" (OBJ:TipoDados id)))))
)

;; Executa uma operacao de armazenamento (despacho).
;;   id   : id do tipo (pode ser nil: usa o padrao)
;;   op   : nome da operacao
;;   args : lista de argumentos da operacao (ver o contrato no cabecalho)
;;   retorno: o que a operacao devolver
;; Se o tipo fornece a operacao, chama a dele; senao usa a implementacao
;; padrao (OBJ:_Padrao). E o unico ponto por onde o resto do codigo deve
;; ler/gravar/listar/remover, para respeitar tipos com armazenamento proprio.
(defun OBJ:Chama (id op args / fn)
  (setq fn (if id (OBJ:Op id op) nil))
  (if fn
    (apply fn args)
    (OBJ:_Padrao id op args)
  )
)

;; Implementacao padrao das 5 operacoes (a "classe base").
;;   id, op, args : como em OBJ:Chama
;;   retorno: resultado da operacao padrao; nil para operacao desconhecida
(defun OBJ:_Padrao (id op args)
  (cond
    ((equal op "LER") (OBJ:Ler (car args)))
    ((equal op "GRAVAR") (OBJ:_GravarPadrao (car args) (cadr args)))
    ((equal op "LISTAR") (OBJ:_ListarTipoPadrao id))
    ((equal op "REINDEXAR") (OBJ:_ReindexarTipoPadrao id))
    ((equal op "REMOVER") (OBJ:_RemoverPadrao (car args)))
    (T nil)
  )
)

;; GRAVAR padrao: grava o envelope na entidade e a coloca no indice.
;;   en  : ename
;;   reg : registro completo (alist)
;;   retorno: reg se gravou; nil se a gravacao falhou (e nao indexa)
(defun OBJ:_GravarPadrao (en reg)
  (if (HYDRO:DadoGravar en "HYDRO-OBJ" reg)
    (progn (OBJ:_Indexar en) reg)
    nil
  )
)

;; LISTAR padrao: enames dos objetos de um tipo, a partir do indice.
;;   id : id do tipo
;;   retorno: lista de enames validos cujo registro tem TIPO igual a id
;; Ignora handles de entidades apagadas (handent pode devolver ename morto,
;; por isso confere com HYDRO:EntValida).
(defun OBJ:_ListarTipoPadrao (id / out h en)
  (foreach h (HYDRO:Get "HYDRO.OBJETOS" nil)
    (setq en (handent h))
    (if (and en (HYDRO:EntValida en)
             (equal (OBJ:_Val "TIPO" (OBJ:Ler en)) id))
      (setq out (append out (list en)))
    )
  )
  out
)

;; reconstroi o indice geral e devolve quantos objetos o tipo tem
;;   id : id do tipo
;;   retorno: quantidade de objetos do tipo apos reindexar
(defun OBJ:_ReindexarTipoPadrao (id)
  (OBJ:Reindexar)
  (length (OBJ:_ListarTipoPadrao id))
)

;; Registro padrao do objeto (via LER do tipo) ou nil
;;   en : ename
;;   retorno: envelope padrao; nil se a entidade nao e objeto hidraulico
;; Diferente de OBJ:Ler, respeita o armazenamento proprio do tipo (a bacia
;; guarda de outro jeito mas devolve o mesmo formato).
(defun OBJ:Registro (en / id)
  (setq id (OBJ:TipoDe en))
  (if id (OBJ:Chama id "LER" (list en)) nil)
)

;; Grava o registro padrao pelo contrato do tipo (GRAVAR).
;;   id  : id do tipo
;;   en  : ename
;;   reg : registro completo
;;   retorno: reg ou nil
(defun OBJ:GravaRegistro (id en reg)
  (OBJ:Chama id "GRAVAR" (list en reg))
)

;; Lista os enames dos objetos de um tipo (operacao LISTAR do tipo).
;;   id : id do tipo
(defun OBJ:ListaTipo (id)
  (OBJ:Chama id "LISTAR" nil)
)

;; Reconstroi o indice do tipo varrendo o desenho (operacao REINDEXAR).
;;   id : id do tipo
;;   retorno: quantidade de objetos do tipo
(defun OBJ:ReindexaTipo (id)
  (OBJ:Chama id "REINDEXAR" nil)
)

;; Leitura dos campos padrao (iguais para todos os tipos)
;; Cada funcao recebe o ename e devolve o campo do registro (ou nil):
;;   NomeGravado = NOME digitado   DescricaoDe = DESCRICAO   ParamsDe = PARAMS (ligacoes)
;;   AtribDe = ATRIB (definidos pelo usuario)   CaractDe = CARACT (vem do desenho)
;;   ResultDe = RESULT inteiro      GrupoDe = um grupo de RESULT (ex.: "VAZAO")
;;   VazaoDe = atalho do grupo "VAZAO"
(defun OBJ:NomeGravado (en)   (OBJ:_Val "NOME" (OBJ:Registro en)))
(defun OBJ:DescricaoDe (en)   (OBJ:_Val "DESCRICAO" (OBJ:Registro en)))
(defun OBJ:ParamsDe (en)      (OBJ:_Val "PARAMS" (OBJ:Registro en)))
(defun OBJ:AtribDe (en)       (OBJ:_Val "ATRIB" (OBJ:Registro en)))
(defun OBJ:CaractDe (en)      (OBJ:_Val "CARACT" (OBJ:Registro en)))
(defun OBJ:ResultDe (en)      (OBJ:_Val "RESULT" (OBJ:Registro en)))
(defun OBJ:GrupoDe (en grupo) (OBJ:_Val grupo (OBJ:ResultDe en)))
(defun OBJ:VazaoDe (en)       (OBJ:GrupoDe en "VAZAO"))

;; Nome para exibir
;;   en : ename
;;   retorno: string, nunca nil. Ordem de preferencia: nome gravado pelo
;;            usuario; capacidade NOME-FN do tipo; "<tipo>-<handle>"
;;            (com "?" no lugar do tipo se nao for objeto)
(defun OBJ:Nome (en / id fn gravado)
  (setq id (OBJ:TipoDe en))
  (setq gravado (OBJ:NomeGravado en))
  (cond
    (gravado gravado)
    (T
      (setq fn (if id (OBJ:Cap id "NOME-FN") nil))
      (if fn
        (apply fn (list en))
        (strcat (if id id "?") "-" (HYDRO:Handle en))
      )
    )
  )
)

;; dados = valores de ATRIB. Mantem DESCRICAO, PARAMS e RESULT se o tipo e o mesmo;
;; CARACT vem da capacidade CARACTERIZA do tipo (se houver).
;;   en      : ename da entidade
;;   tipo-id : id do tipo escolhido
;;   dados   : alist de ATRIB (valores definidos pelo usuario)
;;   nome    : nome do objeto (nil = automatico)
;;   retorno: o registro gravado, ou nil se a gravacao falhou
;; Se a entidade ja era deste tipo, preserva o que nao e ATRIB (descricao,
;; ligacoes, resultados). Se mudou de tipo, descarta PARAMS e RESULT antigos
;; porque nao fazem sentido no tipo novo. CARACTERIZA roda dentro de
;; vl-catch-all-apply: se falhar ou nao devolver nada, reaproveita o CARACT
;; anterior (mesmo tipo) ou fica sem. Emite "objeto.cadastrado" ao final.
(defun OBJ:Cadastrar (en tipo-id dados nome / reg mesmo fn caract novo)
  (setq reg (OBJ:Ler en))
  (setq mesmo (equal (OBJ:_Val "TIPO" reg) tipo-id))
  (setq fn (OBJ:Cap tipo-id "CARACTERIZA"))
  (setq caract (if fn (vl-catch-all-apply fn (list en)) nil))
  (if (vl-catch-all-error-p caract) (setq caract nil))
  (if (null caract)
    (setq caract (if mesmo (OBJ:_Val "CARACT" reg) nil))
  )
  (setq novo
    (OBJ:_Limpa
      (list
        (cons "VERSAO" 2)
        (cons "TIPO" tipo-id)
        (cons "NOME" nome)
        (cons "DESCRICAO" (if mesmo (OBJ:_Val "DESCRICAO" reg) nil))
        (cons "PARAMS" (if mesmo (OBJ:_Val "PARAMS" reg) nil))
        (cons "ATRIB" dados)
        (cons "CARACT" caract)
        ;; resultados de outro tipo nao fazem sentido neste
        (cons "RESULT" (if mesmo (OBJ:_Val "RESULT" reg) nil))
      )
    )
  )
  (if (OBJ:_GravarPadrao en novo)
    (progn
      (HYDRO:Emit "objeto.cadastrado" (list (cons "OBJETO" en) (cons "TIPO" tipo-id)))
      novo
    )
    nil
  )
)

;; Remove o cadastro de objeto pelo contrato do tipo (padrao: _RemoverPadrao).
;;   en : ename
;;   retorno: o que a operacao REMOVER devolver (T no padrao)
;; Se a entidade nao tem tipo conhecido, ainda assim usa a remocao padrao
;; para limpar dados orfaos.
(defun OBJ:Remover (en / id)
  (setq id (OBJ:TipoDe en))
  (if id
    (OBJ:Chama id "REMOVER" (list en))
    (OBJ:_RemoverPadrao en)
  )
)

;; REMOVER padrao: emite o evento, apaga o registro e desindexa.
;;   en : ename
;;   retorno: T
;; O evento sai ANTES para que quem guarda ligacoes (plugin ligacao) possa
;; desfaze-las com o tipo ainda conhecido.
(defun OBJ:_RemoverPadrao (en)
  (HYDRO:Emit "objeto.removido" (list (cons "OBJETO" en)))
  (HYDRO:DadoApagar en "HYDRO-OBJ")
  (OBJ:_Desindexar en)
  T
)

;; Entradas de um grupo de RESULT com o mesmo METODO e TR sao a mesma entrada
;;   a, b : entradas (alists planas com "METODO" e "TR")
;;   retorno: T ou nil. TR e comparado com tolerancia 1e-9 (reais)
(defun OBJ:_MesmaEntrada (a b)
  (if (and (equal (OBJ:_Val "METODO" a) (OBJ:_Val "METODO" b))
           (equal (OBJ:_Val "TR" a) (OBJ:_Val "TR" b) 1e-9))
    T
    nil
  )
)

;; Grava uma entrada (campos calculados planos) no grupo de RESULT, por
;; exemplo "VAZAO" ou "HIDRAULICA". Substitui a de mesmo METODO e TR.
;;   en      : ename do objeto
;;   grupo   : nome do grupo de RESULT ("TC", "VAZAO", "HIDRAULICA"...)
;;   entrada : alist plana com os campos calculados (inclui METODO e TR)
;;   retorno: o registro gravado, ou nil se a entidade nao e objeto
;; A entrada nova vai para o fim do grupo; as demais sao preservadas.
(defun OBJ:GravarResultado (en grupo entrada / id reg res lista)
  (setq id (OBJ:TipoDe en))
  (setq reg (OBJ:Registro en))
  (if reg
    (progn
      (setq res (OBJ:_Val "RESULT" reg))
      (setq lista
        (append
          (vl-remove-if
            (function (lambda (x) (OBJ:_MesmaEntrada x entrada)))
            (OBJ:_Val grupo res))
          (list entrada)))
      (OBJ:GravaRegistro id en
        (OBJ:_SetChave reg "RESULT" (OBJ:_SetChave res grupo lista)))
    )
    nil
  )
)

;; Objetos conhecidos: cadastrados (indice) + nativos (tipos com LISTA)
;;   retorno: lista de enames sem repeticao. Primeiro os do indice
;;            HYDRO.OBJETOS (validos e com registro); depois os que cada tipo
;;            com LISTAR proprio informa (ex.: bacias) e ainda nao estao na lista
(defun OBJ:Listar (/ out h en t1 fn)
  (foreach h (HYDRO:Get "HYDRO.OBJETOS" nil)
    (setq en (handent h))
    (if (and en (HYDRO:EntValida en) (OBJ:Ler en))
      (setq out (append out (list en)))
    )
  )
  (foreach t1 (OBJ:Tipos)
    (setq fn (OBJ:Op (car t1) "LISTAR"))
    (if fn
      (foreach en (apply fn nil)
        (if (not (member en out))
          (setq out (append out (list en)))
        )
      )
    )
  )
  out
)

;; Uniao dos nomes DXF aceitos por todos os tipos
;;   retorno: lista de strings sem repeticao (usada para filtrar o ssget
;;            em OBJ:Reindexar)
(defun OBJ:DxfUniao (/ out t1 d)
  (foreach t1 (OBJ:Tipos)
    (foreach d (OBJ:_Val "ACEITA" (cdr t1))
      (if (not (member d out)) (setq out (append out (list d))))
    )
  )
  out
)

;; Reconstroi o indice varrendo o desenho (apos colar de outro desenho)
;;   retorno: quantidade de objetos com cadastro HYDRO-OBJ encontrados
;; Seleciona so as entidades dos tipos DXF aceitos (ssget "_X"), guarda os
;; handles das que tem registro, ordena pelo valor numerico do handle e
;; regrava HYDRO.OBJETOS. Depois pede a cada tipo com REINDEXAR proprio que
;; refaca o indice dele (ex.: HYDRO.BACIAS).
(defun OBJ:Reindexar (/ dxfs ss i en lista t1)
  (setq dxfs (OBJ:DxfUniao))
  (if dxfs
    (setq ss (ssget "_X" (list (cons 0 (HYDRO:Join dxfs ",")))))
  )
  (if ss
    (progn
      (setq i (sslength ss))
      (while (> i 0)
        (setq i (1- i))
        (setq en (ssname ss i))
        (if (OBJ:Ler en)
          (setq lista (cons (HYDRO:Handle en) lista))
        )
      )
    )
  )
  (setq lista (vl-sort lista 'OBJ:_HandleLt))
  (HYDRO:Set "HYDRO.OBJETOS" lista)
  ;; tipos com armazenamento proprio reconstroem o indice deles
  (foreach t1 (OBJ:Tipos)
    (if (OBJ:Op (car t1) "REINDEXAR")
      (apply (OBJ:Op (car t1) "REINDEXAR") nil)
    )
  )
  (length lista)
)

;;; ------------------------------------------------------------
;;; TEXTOS
;;; ------------------------------------------------------------

;; Rotulo de um param de ATRIB para exibir: "rotulo (unidade)".
;;   id    : id do tipo
;;   chave : chave do param
;;   retorno: rotulo definido em ATRIB-DEFS, com a unidade entre parenteses
;;            quando houver; se a chave nao estiver nas definicoes, a propria chave
(defun OBJ:_RotuloParam (id chave / d p)
  (setq d (OBJ:Cap id "ATRIB-DEFS"))
  (setq p (assoc chave d))
  (if p
    (strcat (cadr p) (if (and (nth 3 p) (/= (nth 3 p) "")) (strcat " (" (nth 3 p) ")") ""))
    chave
  )
)

;; Resumo padrao (usado quando o tipo nao tem a capacidade RESUMO).
;;   en : ename
;;   retorno: lista de linhas: Objeto, Tipo, Handle e uma linha por valor
;;            de ATRIB ("  rotulo: valor")
(defun OBJ:_ResumoPadrao (en / id out p)
  (setq id (OBJ:TipoDe en))
  (setq out
    (list
      (strcat "Objeto: " (OBJ:Nome en))
      (strcat "Tipo: " (OBJ:_NomeTipo id))
      (strcat "Handle: " (HYDRO:Handle en))
    )
  )
  (foreach p (OBJ:AtribDe en)
    (setq out
      (append out
        (list (strcat "  " (OBJ:_RotuloParam id (car p)) ": " (OBJ:_FmtVal (cdr p))))))
  )
  out
)

;; Linhas "Atributos:" com os valores de ATRIB do objeto (definidos pelo usuario),
;; com rotulo e unidade do tipo. nil se o objeto nao tem atributos.
(defun OBJ:LinhasAtrib (en / id out p)
  (setq id (OBJ:TipoDe en))
  (foreach p (OBJ:AtribDe en)
    (setq out
      (append out
        (list (strcat "  " (OBJ:_RotuloParam id (car p)) ": " (OBJ:_FmtVal (cdr p))))))
  )
  (if out (cons "Atributos:" out) nil)
)

;; Uma linha "<titulo>: k = v   k = v" para uma alist de parametros (nil se vazia)
(defun OBJ:LinhaParams (titulo params)
  (if params
    (list
      (strcat titulo ": "
              (HYDRO:Join
                (mapcar
                  (function (lambda (p) (strcat (car p) " = " (OBJ:_FmtVal (cdr p)))))
                  params)
                "   ")))
    nil
  )
)

;; Linhas de resumo do objeto (usa a capacidade RESUMO do tipo, se houver)
;;   en : ename
;;   retorno: lista de strings, uma por linha (para alert, tabelas...)
(defun OBJ:Resumo (en / id fn)
  (setq id (OBJ:TipoDe en))
  (setq fn (if id (OBJ:Cap id "RESUMO") nil))
  (if fn
    (apply fn (list en))
    (OBJ:_ResumoPadrao en)
  )
)

;; toString do objeto: UMA string com a descricao dele (linhas separadas por newline).
;;   en : ename
;;   retorno: string. Usa a capacidade TOSTRING do tipo (cada objeto define a
;;            sua, ex.: BAC:ToString, SOB:ToString); sem ela, junta as linhas
;;            de OBJ:Resumo.
(defun OBJ:ToString (en / id fn)
  (setq id (OBJ:TipoDe en))
  (setq fn (if id (OBJ:Cap id "TOSTRING") nil))
  (if fn
    (apply fn (list en))
    (HYDRO:Join (OBJ:Resumo en) "\n")
  )
)

;;; ------------------------------------------------------------
;;; CADASTRO INTERATIVO
;;; ------------------------------------------------------------

;; Posicao de um tipo numa lista de (id . dados).
;;   tipos : lista de (id . dados)
;;   id    : id procurado (pode ser nil)
;;   retorno: indice a partir de 0; 0 se nao achar (serve de opcao padrao
;;            na lista de escolha). Se houver repeticao, vale a ultima.
(defun OBJ:_IdxTipo (tipos id / i pos m)
  (setq i 0 pos 0)
  (foreach m tipos
    (if (equal (car m) id) (setq pos i))
    (setq i (1+ i))
  )
  pos
)

;; Pergunta o nome do objeto no prompt.
;;   atual : nome atual (string) ou nil
;;   retorno: o texto digitado; se der Enter (vazio), mantem `atual`
;;            (que pode ser nil = nome automatico, ver OBJ:Nome)
(defun OBJ:_PedeNome (atual / r)
  (setq r
    (getstring T
      (strcat "\nNome do objeto"
              (if atual (strcat " <" atual ">") " (Enter = automatico)")
              ": ")))
  (if (and r (/= r "")) r atual)
)

;; Escolhe o tipo (entre os que aceitam a entidade), pede nome e parametros
;; e grava. Retorna o registro ou nil.
;;   en : ename da entidade a cadastrar/editar
;;   retorno: registro gravado, ou nil se cancelou, nao ha tipo aplicavel ou
;;            a gravacao falhou
;; Fluxo: (1) recusa entidade invalida; (2) recusa entidade nativa (ex.:
;; bacia) e manda usar o comando proprio; (3) lista os tipos que aceitam o
;; DXF (se so um, usa direto; se varios, pergunta, sugerindo o ja gravado);
;; (4) pede o nome; (5) monta os valores iniciais dos params: padroes do
;; tipo (PADROES) e, por cima, os ja cadastrados se o tipo nao mudou;
;; (6) pergunta os params (HYDRO:AskParams) e grava com OBJ:Cadastrar.
(defun OBJ:CadastroInterativo (en)
  (OBJ:CadastroInterativoTipo en nil)
)

;; Igual a OBJ:CadastroInterativo, mas com o tipo FIXO quando `forcado` e o id de
;; um tipo (comandos <TIPO>CAD): nao pergunta o tipo, so nome e parametros.
;;   forcado : id do tipo, ou nil para escolher entre os que aceitam a entidade
(defun OBJ:CadastroInterativoTipo (en forcado /
                               dxf nativo tipos reg idx item id nome pad exist params novo)
  (setq dxf (HYDRO:DxfDe en))
  (setq nativo (OBJ:_Detecta en))
  (cond
    ((not (HYDRO:EntValida en)) nil)
    (nativo
      (alert
        (strcat "Esta entidade ja e do tipo '" (OBJ:_NomeTipo nativo)
                "' (reconhecida automaticamente).\nUse o comando proprio desse tipo."))
      nil
    )
    (T
      (setq tipos (OBJ:TiposPara dxf))
      (if forcado
        (setq tipos
          (vl-remove-if-not
            (function (lambda (x) (equal (car x) forcado)))
            tipos))
      )
      (cond
        ((not tipos)
          (alert
            (if forcado
              (strcat "O tipo '" (OBJ:_NomeTipo forcado) "' nao aceita entidades " dxf ".")
              (strcat "Nenhum tipo de objeto hidraulico aceita entidades " dxf ".")))
          nil
        )
        (T
          (setq reg (OBJ:Ler en))
          (setq idx
            (if (= (length tipos) 1)
              0
              (HYDRO:Escolher
                (strcat "Tipos de objeto hidraulico para " dxf ":")
                (mapcar 'OBJ:_RotuloTipo tipos)
                (OBJ:_IdxTipo tipos (OBJ:_Val "TIPO" reg)))))
          (setq item (nth idx tipos))
          (setq id (car item))
          (setq nome (OBJ:_PedeNome (OBJ:_Val "NOME" reg)))
          (setq pad (if (OBJ:Cap id "PADROES") (apply (OBJ:Cap id "PADROES") (list en)) nil))
          ;; valores ja cadastrados (mesmo tipo) tem prioridade sobre os padroes
          (setq exist (if (equal (OBJ:_Val "TIPO" reg) id) (OBJ:_Val "ATRIB" reg) nil))
          (setq params
            (HYDRO:AskParams
              (OBJ:Cap id "ATRIB-DEFS")
              (strcat "HYDRO.OBJ." id ".")
              (append exist pad)))
          (setq novo (OBJ:Cadastrar en id params nome))
          (if novo
            (progn
              ;; objeto NOVO: oferece ligar a outros objetos antes de seguir
              (if (and (null reg) (HYDRO:Has "ligacao"))
                (LIG:OferecerLigacao en)
              )
              novo
            )
            (progn (alert "Nao foi possivel gravar os dados na entidade.") nil)
          )
        )
      )
    )
  )
)

;; Edita o objeto: usa a capacidade EDITAR do tipo (ex.: bacia) ou o
;; cadastro generico
;;   en : ename
;;   retorno: o que a edicao devolver (registro ou nil)
(defun OBJ:Editar (en / id fn)
  (setq id (OBJ:TipoDe en))
  (setq fn (if id (OBJ:Cap id "EDITAR") nil))
  (if fn
    (apply fn (list en))
    (OBJ:CadastroInterativo en)
  )
)

;;; ------------------------------------------------------------
;;; COMANDOS
;;; ------------------------------------------------------------

;; Comando OBJETO: pede uma entidade e a cadastra (ou edita) como objeto
;; hidraulico; se o cadastro for concluido, mostra o resumo num alert.
(defun c:OBJETO (/ sel en)
  (setq sel (entsel "\nSelecione a entidade para cadastrar/editar como objeto hidraulico: "))
  (if sel
    (progn
      (setq en (car sel))
      (if (OBJ:CadastroInterativo en)
        (alert (OBJ:ToString en))
      )
    )
  )
  (princ)
)

;; Comando OBJETOINFO: pede uma entidade e mostra o resumo do objeto num
;; alert; se ela nao for objeto hidraulico, orienta a usar OBJETO.
(defun c:OBJETOINFO (/ sel en)
  (setq sel (entsel "\nSelecione o objeto: "))
  (if sel
    (progn
      (setq en (car sel))
      (if (OBJ:TipoDe en)
        (alert (OBJ:ToString en))
        (alert "Esta entidade nao e um objeto hidraulico. Use OBJETO.")
      )
    )
  )
  (princ)
)

;; Comando OBJETOREMOVER: remove o cadastro de um objeto (a entidade do
;; desenho permanece; so os dados do Hydro sao apagados). Pede confirmacao
;; [Sim/Nao] (Enter = Nao), pois as ligacoes do objeto sao desfeitas.
;; Bacias nao passam por aqui: tem comando proprio (BACIATABELA).
(defun c:OBJETOREMOVER (/ sel en r)
  (setq sel (entsel "\nSelecione o objeto: "))
  (if sel
    (progn
      (setq en (car sel))
      (if (OBJ:Ler en)
        (progn
          (initget "Sim Nao")
          (setq r
            (getkword
              (strcat "\nRemover o cadastro do objeto " (OBJ:Nome en)
                      " (as ligacoes dele serao desfeitas)? [Sim/Nao] <Nao>: ")))
          (if (equal r "Sim")
            (progn (OBJ:Remover en) (princ "\nCadastro removido."))
          )
        )
        (alert "Esta entidade nao tem cadastro de objeto (bacias: use BACIATABELA).")
      )
    )
  )
  (princ)
)

(HYDRO:SetLabel "HYDRO.OBJETOS" "Objetos hidraulicos cadastrados (handles)" "")

(HYDRO:Provide "objetos" "1.0")
(princ)
