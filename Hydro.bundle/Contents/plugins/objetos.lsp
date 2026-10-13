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
;;;       ("AO-REMOVER" . fn)      (fn en) -> limpeza propria do tipo; roda em OBJ:Remover
;;;                                depois do evento "objeto.removido" e antes de apagar
;;;                                o registro (ex.: bacia limpa o XData)
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
;;;                           bacia) e "JUSANTE" . (handle . flag), o destino unico de qualquer objeto
;;;                           que emita (flag T = compartilha o talvegue; ver ligacao.lsp)
;;;      ("ATRIB"  . alist)   valores definidos pelo usuario, nao extraidos do desenho
;;;      ("CARACT" . alist)   o que se obtem do desenho (area, comprimento...)
;;;      ("RESULT" . alist)   tudo que e CALCULADO, por CENARIO (docs/plano_resultados_cenarios.md):
;;;                           (("TR25" . cenario) ("TR10" . cenario) ...)
;;;   cenario = alist de GRUPOS; cada tipo define os seus (bacia: TC, PRECIPITACAO, VAZAO,
;;;             HIDROGRAMA; sarjeta: VAZAO, ALTURA_LAMINA...) e ha um grupo reservado:
;;;             ("CENARIO" ("TR" . 25.0) ["OBSOLETO" . T] ["DESCRICAO" . txt])
;;;   grupo   = campos PLANOS, com "VALOR" (numero principal), "METODO" e "INPUT" (so o que
;;;             o usuario informou ao metodo; nunca copias de ATRIB/CARACT):
;;;             ("VAZAO" ("VALOR" . 9.88) ("METODO" . "racional") ("INPUT" ...))
;;;   Nome do cenario: livre; padrao o TR (OBJ:CenarioPadrao). Cenario em uso: OBJ:CenarioAtual.
;;;   Leitura generica (qualquer tipo): OBJ:Registro, OBJ:NomeGravado,
;;;   OBJ:DescricaoDe, OBJ:ParamsDe, OBJ:AtribDe, OBJ:CaractDe, OBJ:ResultDe (todos os
;;;   cenarios), OBJ:CenariosDe, OBJ:ResultGrupoDe en cenario grupo, OBJ:VazaoDe en cenario.
;;;   Gravacao: OBJ:GravarResultado en cenario grupo campos, OBJ:DefineCenario, OBJ:ConcluiCalculo.
;;;
;;;   PORTA DE ARMAZENAMENTO. Padrao (classe base): grava o envelope e indexa em
;;;   HYDRO.OBJETOS. TODO tipo herda isso (bacia e sarjeta inclusive) e personaliza
;;;   so por GANCHOS: ("CARACTERIZA" . fn) e ("AO-REMOVER" . fn), e grava o proprio
;;;   registro com OBJ:Salvar. So um tipo que guarda em OUTRO lugar (nao na extensao
;;;   da entidade) deve fornecer as operacoes dele; o REGISTRO continua o padrao. Declara
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
;;;   Capacidade opcional ("CARACTERIZA" . fn): (fn en vinculos) -> alist gravada em
;;;   CARACT ao cadastrar (ex.: comprimento e declividade da sarjeta). `vinculos` e a
;;;   alist (chave-de-PARAMS . ename) dos vinculos informados (PARAMS-DEFS); sem valor
;;;   o dado nao entra em CARACT.
;;;   ("PARAMS-DEFS" . defs)  entidades de apoio a pedir no cadastro, gravadas em
;;;                           PARAMS como handles: (chave rotulo aceita [obrigatorio]);
;;;                           aceita = nomes DXF e/ou ids de tipo; Enter pula
;;;   ("CARACT-DEFS" . defs)  CARACT que o usuario digita quando o desenho nao informa
;;;                           (formato de ATRIB); as chaves vao em CARACT "MANUAL"
;;;   OBSOLETO: marca ("OBSOLETO" . T) no grupo "CENARIO" de CADA cenario = resultado
;;;   desatualizado (veja OBJ:Salvar, OBJ:Invalidar, OBJ:ConcluiCalculo). Evento
;;;   "objeto.obsoleto" "OBJETO".
;;;   O argumento `params` de OBJ:RegistrarTipo DESCREVE os campos de ATRIB
;;;   (fica no catalogo sob a chave "ATRIB-DEFS").
;;;
;;; DADOS GUARDADOS: chave "HYDRO-OBJ" (qualquer entidade, inclusive Civil 3D;
;;; ver HYDRO:DadoGravar no core). Indice: HYDRO.OBJETOS (handles).
;;;
;;; EVENTOS EMITIDOS
;;;   "objeto.cadastrado"  "OBJETO" (ename) "TIPO"
;;;   "objeto.removido"    "OBJETO" (ename)      (emitido ANTES de apagar)
;;;   "objeto.obsoleto"    "OBJETO" (ename)      (o resultado ficou desatualizado)
;;;   "objetos.obsoletos"  "OBJETO" (ename)      (UMA vez ao fim de uma edicao/invalidacao, depois da cadeia)
;;;
;;; COMANDOS
;;;   OBJETO         cadastra/edita uma entidade como objeto hidraulico
;;;   OBJETOINFO     mostra os dados de um objeto
;;;   OBJETOREMOVER  remove o cadastro de objeto
;;;   PROPAGAOBSOLETO  flag geral (HYDRO.OBSOLETO.PROPAGA, padrao 1): editar um objeto marca
;;;                    tambem os de jusante como desatualizados (so a marca, sem recalculo)
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

;; Registro padrao da entidade SE ela e do tipo dado, senao nil.
;;   en      : ename
;;   tipo-id : id do tipo esperado
;; Leitura tipada para quem so aceita um tipo (ex.: funcoes da bacia): mesma
;; porta LER do tipo, sem acessar a extensao da entidade diretamente.
(defun OBJ:RegistroDe (en tipo-id)
  (if (equal (OBJ:TipoDe en) tipo-id)
    (OBJ:Chama tipo-id "LER" (list en))
    nil
  )
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
;; RESULT por cenario: ResultDe = todos; CenariosDe = nomes; CenarioDe = os grupos de um cenario;
;; ResultGrupoDe = os campos (planos) de um grupo de um cenario; VazaoDe = grupo "VAZAO".
(defun OBJ:ResultDe (en)      (OBJ:_Val "RESULT" (OBJ:Registro en)))
(defun OBJ:CenariosDe (en)    (mapcar 'car (OBJ:ResultDe en)))
(defun OBJ:CenarioDe (en cenario) (cdr (assoc cenario (OBJ:ResultDe en))))
(defun OBJ:ResultGrupoDe (en cenario grupo) (OBJ:_Val grupo (OBJ:CenarioDe en cenario)))
(defun OBJ:VazaoDe (en cenario) (OBJ:ResultGrupoDe en cenario "VAZAO"))
;; TR de um cenario (grupo "CENARIO"), ou nil
(defun OBJ:TrDoCenario (en cenario)
  (OBJ:_Val "TR" (OBJ:ResultGrupoDe en cenario "CENARIO")))

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
(defun OBJ:Cadastrar (en tipo-id dados nome)
  (OBJ:CadastrarCom en tipo-id dados nome nil nil)
)

;; Cadastrar com vinculos e CARACT manual (esqueleto unico; ver OBJ:Cadastrar).
;;   vinculos : alist (chave . handle) a gravar em PARAMS para chaves de PARAMS-DEFS;
;;              cdr nil REMOVE o vinculo; lista nil mantem os PARAMS como estao
;;   manual   : alist (chave . valor) de CARACT digitado pelo usuario (CARACT-DEFS);
;;              vale so onde o desenho nao informa; as chaves vao em CARACT "MANUAL"
;;   retorno: o registro gravado, ou nil se a gravacao falhou
;; CARACT = o que CARACTERIZA devolveu + os manuais que o desenho nao cobre (os
;; manuais anteriores continuam valendo). Se CARACTERIZA falha, mantem o CARACT antigo.
(defun OBJ:CadastrarCom (en tipo-id dados nome vinculos manual /
                         reg mesmo caract antigo params v novo)
  (setq reg (OBJ:Ler en))
  (setq mesmo (equal (OBJ:_Val "TIPO" reg) tipo-id))
  (setq antigo (if mesmo (OBJ:_Val "CARACT" reg) nil))
  (setq params (if mesmo (OBJ:_Val "PARAMS" reg) nil))
  (foreach v vinculos
    (setq params (OBJ:_SetChave params (car v) (cdr v)))
  )
  (setq manual (OBJ:_Limpa manual))
  (setq caract (OBJ:_MesclaCaract (OBJ:_Caracteriza en tipo-id params) antigo manual))
  (setq novo
    (OBJ:_Limpa
      (list
        (cons "VERSAO" 2)
        (cons "TIPO" tipo-id)
        (cons "NOME" nome)
        (cons "DESCRICAO" (if mesmo (OBJ:_Val "DESCRICAO" reg) nil))
        (cons "PARAMS" params)
        (cons "ATRIB" dados)
        (cons "CARACT" caract)
        ;; resultados de outro tipo nao fazem sentido neste
        (cons "RESULT" (if mesmo (OBJ:_Val "RESULT" reg) nil))
      )
    )
  )
  (OBJ:Salvar en tipo-id novo)
)

;; CARACT final = o que o desenho informa (`novo`) + manuais que ele nao cobre.
;;   novo   : retorno de CARACTERIZA (nil = nao leu / falhou)
;;   antigo : CARACT gravado (com "MANUAL" = chaves digitadas)
;;   manual : alist (chave . valor) digitada agora
;; Desenho vence o manual quando informa a chave; manuais antigos continuam valendo
;; onde o desenho nao informa. Se `novo` e nil, mantem `antigo` (aplicando `manual`).
(defun OBJ:_MesclaCaract (novo antigo manual / caract chaves k m)
  (if novo
    (progn
      (setq caract novo)
      (foreach k (OBJ:_Val "MANUAL" antigo)
        (if (and (not (assoc k manual)) (assoc k antigo))
          (setq manual (append manual (list (assoc k antigo))))
        )
      )
      (foreach m manual
        (if (not (assoc (car m) caract))
          (setq caract (append caract (list m))
                chaves (append chaves (list (car m))))
        )
      )
    )
    (progn
      (setq chaves (OBJ:_Val "MANUAL" antigo))
      (setq caract (vl-remove (assoc "MANUAL" antigo) antigo))
      (foreach m manual
        (setq caract (OBJ:_SetChave caract (car m) (cdr m)))
        (if (not (member (car m) chaves)) (setq chaves (append chaves (list (car m)))))
      )
    )
  )
  (if chaves (append caract (list (cons "MANUAL" chaves))) caract)
)

;; Flag geral: reler o desenho (CARACTERIZA) antes de calcular (padrao ligada)
(defun OBJ:CaractAuto ()
  (if (= (HYDRO:Get "HYDRO.CARACT.AUTO" 1) 1) T nil)
)

;; Antes de CALCULAR: se HYDRO.CARACT.AUTO, recaracteriza o objeto pelo desenho e
;; grava o CARACT se mudou (so ele; sem marcar obsoleto, o calculo vem em seguida).
;;   retorno: T se atualizou o CARACT, nil se nada mudou / flag desligada / sem CARACTERIZA
(defun OBJ:AtualizaCaract (en / id reg antigo novo)
  (setq id (OBJ:TipoDe en))
  (setq reg (if (and id (OBJ:CaractAuto) (OBJ:Cap id "CARACTERIZA")) (OBJ:Ler en) nil))
  (if reg
    (progn
      (setq antigo (OBJ:_Val "CARACT" reg))
      (setq novo
        (OBJ:_MesclaCaract
          (OBJ:_Caracteriza en id (OBJ:_Val "PARAMS" reg)) antigo nil))
      (if (and novo (not (OBJ:_IgualAlist novo antigo)))
        (if (OBJ:GravaRegistro id en (OBJ:_SetChave reg "CARACT" novo)) T nil)
        nil
      )
    )
    nil
  )
)

;; CARACT que o desenho informa, via capacidade CARACTERIZA (sem gravar).
;;   params : PARAMS (handles dos vinculos)
;;   retorno: alist ou nil (sem a capacidade, ou falhou)
(defun OBJ:_Caracteriza (en tipo-id params / fn r)
  (setq fn (OBJ:Cap tipo-id "CARACTERIZA"))
  (setq r
    (if fn
      (vl-catch-all-apply fn (list en (OBJ:_VinculosEnames tipo-id params)))
      nil))
  (if (vl-catch-all-error-p r) nil r)
)

;; T se o handle aponta para uma entidade existente
(defun OBJ:_HandleOk (h / e)
  (setq e (if h (handent h) nil))
  (if (and e (HYDRO:EntValida e)) T nil)
)

;; Vinculos do tipo (PARAMS-DEFS) que existem em PARAMS: alist (chave . ename)
(defun OBJ:_VinculosEnames (tipo-id params / out d h)
  (foreach d (OBJ:Cap tipo-id "PARAMS-DEFS")
    (setq h (cdr (assoc (car d) params)))
    (if (OBJ:_HandleOk h)
      (setq out (append out (list (cons (car d) (handent h)))))
    )
  )
  out
)

;; T se a entidade serve para um vinculo (nome DXF ou id de tipo em `aceita`)
(defun OBJ:_AceitaVinculo (en aceita)
  (if (or (member (HYDRO:DxfDe en) aceita) (member (OBJ:TipoDe en) aceita)) T nil)
)

;; PONTO UNICO de gravacao de um cadastro: grava pelo contrato do tipo e avisa.
;;   en      : ename
;;   tipo-id : id do tipo
;;   reg     : registro padrao completo
;;   retorno: reg se gravou; nil se a gravacao falhou (e nao emite o evento)
;; Todo tipo que monta o proprio registro (ex.: a bacia, que tambem guarda o
;; talvegue e o tc) termina aqui, para que o evento "objeto.cadastrado" saia
;; igual para qualquer objeto. Quem reage (etiqueta, relacao) filtra por TIPO.
;; Obsolescencia: se o objeto tinha RESULT e ATRIB, PARAMS ou CARACT mudaram, marca TODOS os
;; cenarios como desatualizados ("OBSOLETO" no grupo "CENARIO"; o RESULT nao e apagado) e,
;; com HYDRO.OBSOLETO.PROPAGA, marca os de jusante. Marcas que ja existiam sao mantidas
;; (o registro novo traz o RESULT antigo); so OBJ:ConcluiCalculo as remove.
(defun OBJ:Salvar (en tipo-id reg / ant mudou)
  (setq ant (OBJ:Ler en))
  (if (and ant (equal (OBJ:_Val "TIPO" ant) tipo-id) (OBJ:_Val "RESULT" ant))
    (progn
      (setq mudou (OBJ:_MudouCadastro ant reg))
      (if mudou
        (setq reg
          (OBJ:_SetChave reg "RESULT" (OBJ:_ResultObsoleto (OBJ:_Val "RESULT" reg))))
      )
    )
  )
  (if (OBJ:GravaRegistro tipo-id en reg)
    (progn
      (HYDRO:Emit "objeto.cadastrado" (list (cons "OBJETO" en) (cons "TIPO" tipo-id)))
      (if mudou
        (progn
          (HYDRO:Emit "objeto.obsoleto" (list (cons "OBJETO" en)))
          (if (OBJ:PropagaObsoleto) (OBJ:InvalidaJusante en))
          ;; avisa UMA vez que terminou a cadeia (tabelas se atualizam so aqui)
          (HYDRO:Emit "objetos.obsoletos" (list (cons "OBJETO" en)))
        )
      )
      reg
    )
    nil
  )
)

;;; ------------------------------------------------------------
;;; OBSOLESCENCIA (RESULT desatualizado)
;;; ------------------------------------------------------------
;; Igualdade de valores de registro: reais com tolerancia, listas e pares por estrutura.
(defun OBJ:_Igual (a b)
  (cond
    ((and (numberp a) (numberp b)) (equal a b 1e-9))
    ((and (listp a) (listp b))
      (cond
        ((or (null a) (null b)) (if (and (null a) (null b)) T nil))
        ((OBJ:_Igual (car a) (car b)) (OBJ:_Igual (cdr a) (cdr b)))
        (T nil)
      )
    )
    (T (equal a b))
  )
)

;; Igualdade de alists sem depender da ordem das chaves
(defun OBJ:_IgualAlist (a b)
  (if (and (= (length a) (length b))
           (vl-every
             (function (lambda (p) (OBJ:_Igual (cdr p) (cdr (assoc (car p) b)))))
             a))
    T
    nil
  )
)

;; T se ATRIB, PARAMS ou CARACT diferem entre dois registros (erro de leitura = T)
(defun OBJ:_MudouCadastro (a b / r)
  (setq r
    (vl-catch-all-apply
      (function
        (lambda ()
          (vl-some
            (function
              (lambda (k) (not (OBJ:_IgualAlist (OBJ:_Val k a) (OBJ:_Val k b)))))
            '("ATRIB" "PARAMS" "CARACT"))))
      nil))
  (if (vl-catch-all-error-p r) T (if r T nil))
)

;; (puro) T se o cenario de `result` esta marcado; sem cenario, se algum esta
(defun OBJ:_ObsoletoR (result cenario)
  (if cenario
    (if (OBJ:_Val "OBSOLETO" (OBJ:_Val "CENARIO" (cdr (assoc cenario result)))) T nil)
    (if (vl-some
          (function
            (lambda (c) (OBJ:_Val "OBSOLETO" (OBJ:_Val "CENARIO" (cdr c)))))
          result)
      T nil)
  )
)

;; (puro) T se ha cenarios e TODOS estao marcados
(defun OBJ:_TodosObsoletosR (result)
  (if (and result
           (vl-every
             (function
               (lambda (c) (OBJ:_Val "OBSOLETO" (OBJ:_Val "CENARIO" (cdr c)))))
             result))
    T nil)
)

;; (puro) `result` com TODOS os cenarios marcados como desatualizados
(defun OBJ:_ResultObsoleto (result / out c meta)
  (foreach c result
    (setq meta (OBJ:_SetChave (OBJ:_Val "CENARIO" (cdr c)) "OBSOLETO" T))
    (setq out
      (append out (list (cons (car c) (OBJ:_SetChave (cdr c) "CENARIO" meta)))))
  )
  out
)

;; T se o cenario esta desatualizado; sem cenario (nil), se ALGUM cenario esta.
(defun OBJ:Obsoleto (en cenario)
  (OBJ:_ObsoletoR (OBJ:_Val "RESULT" (OBJ:Registro en)) cenario)
)

;; Flag geral: propagar a marca de obsoleto para jusante (padrao ligada)
(defun OBJ:PropagaObsoleto ()
  (if (= (HYDRO:Get "HYDRO.OBSOLETO.PROPAGA" 1) 1) T nil)
)

;; Marca UM objeto como obsoleto (todos os cenarios dele). T se marcou; nil se nao tem
;; RESULT, todos ja estavam marcados ou a gravacao falhou. Emite "objeto.obsoleto".
(defun OBJ:_MarcaObsoleto (en / id reg res)
  (setq id (OBJ:TipoDe en))
  (setq reg (if id (OBJ:Registro en) nil))
  (setq res (OBJ:_Val "RESULT" reg))
  (if (and res (not (OBJ:_TodosObsoletosR res))
           (OBJ:GravaRegistro id en
             (OBJ:_SetChave reg "RESULT" (OBJ:_ResultObsoleto res))))
    (progn (HYDRO:Emit "objeto.obsoleto" (list (cons "OBJETO" en))) T)
    nil
  )
)

;; Destino (ename) gravado em PARAMS "JUSANTE" = (handle . flag), ou nil
(defun OBJ:_DestinoDe (en / j h e)
  (setq j (OBJ:_Val "JUSANTE" (OBJ:ParamsDe en)))
  (setq h (if (and j (= (type (car j)) 'STR)) (car j) nil))
  (setq e (if h (handent h) nil))
  (if (and e (HYDRO:EntValida e)) e nil)
)

;; Marca como obsoletos os objetos de JUSANTE de `en` (so a marca, sem recalcular).
;; Segue a cadeia ate o fim; para ao achar um ja obsoleto (o resto ja foi marcado)
;; ou um repetido (ciclo). Retorna quantos marcou.
(defun OBJ:InvalidaJusante (en / visit atual n)
  (setq visit (list en) n 0)
  (setq atual (OBJ:_DestinoDe en))
  (while (and atual (not (member atual visit))
              (not (OBJ:_TodosObsoletosR (OBJ:ResultDe atual))))
    (setq visit (cons atual visit))
    (if (OBJ:_MarcaObsoleto atual) (setq n (1+ n)))
    (setq atual (OBJ:_DestinoDe atual))
  )
  n
)

;; Marca `en` e (se a flag permite) os de jusante. Uso: quem muda algo que o
;; RESULT usa sem passar por OBJ:Salvar (ex.: ligar objetos).
(defun OBJ:Invalidar (en / a n)
  (setq a (OBJ:_MarcaObsoleto en))
  (setq n (if (OBJ:PropagaObsoleto) (OBJ:InvalidaJusante en) 0))
  (if (or a (> n 0))
    (HYDRO:Emit "objetos.obsoletos" (list (cons "OBJETO" en)))
  )
  n
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

;; REMOVER padrao: emite o evento, roda o gancho do tipo, apaga o registro e desindexa.
;;   en : ename
;;   retorno: T
;; O evento sai ANTES para que quem guarda ligacoes (plugin ligacao) possa
;; desfaze-las com o tipo ainda conhecido. O gancho opcional "AO-REMOVER"
;; (fn en) do tipo roda com o registro ainda gravado (ex.: bacia limpa o XData).
(defun OBJ:_RemoverPadrao (en / id fn)
  (setq id (OBJ:TipoDe en))
  (setq fn (if id (OBJ:Cap id "AO-REMOVER") nil))
  (HYDRO:Emit "objeto.removido" (list (cons "OBJETO" en)))
  (if fn (vl-catch-all-apply fn (list en)))
  (HYDRO:DadoApagar en "HYDRO-OBJ")
  (OBJ:_Desindexar en)
  T
)

;; (puro) `result` com o grupo substituido no cenario (criado se nao existe). campos nil
;; REMOVE o grupo; cenario sem grupos some. Pares nil dos campos sao descartados.
(defun OBJ:_ResultSetGrupo (result cenario grupo campos / cen)
  (setq cen (OBJ:_SetChave (cdr (assoc cenario result)) grupo (OBJ:_Limpa campos)))
  (cond
    ((null cen) (vl-remove (assoc cenario result) result))
    ((assoc cenario result)
      (mapcar
        (function (lambda (c) (if (equal (car c) cenario) (cons cenario cen) c)))
        result))
    (T (append result (list (cons cenario cen))))
  )
)

;; Grava um grupo de resultado no cenario (substitui o grupo anterior).
;;   en       : ename do objeto
;;   cenario  : nome do cenario ("TR25")
;;   grupo    : nome do grupo ("VAZAO", "TC", "ENTRADA"...)
;;   campos   : alist plana ("VALOR" . v) ("METODO" . id) ... ; nil remove o grupo
;;   retorno: o registro gravado, ou nil se a entidade nao e objeto / sem cenario
;; Nao mexe em "OBSOLETO": quem calcula chama OBJ:ConcluiCalculo ao terminar.
(defun OBJ:GravarResultado (en cenario grupo campos / id reg)
  (setq id (OBJ:TipoDe en))
  (setq reg (if id (OBJ:Registro en) nil))
  (if (and reg cenario)
    (OBJ:GravaRegistro id en
      (OBJ:_SetChave reg "RESULT"
        (OBJ:_ResultSetGrupo (OBJ:_Val "RESULT" reg) cenario grupo campos)))
    nil
  )
)

;; Cria/atualiza o cenario do objeto com o TR dele (grupo "CENARIO"), mantendo as outras
;; marcas (OBSOLETO...). Retorna o registro ou nil.
(defun OBJ:DefineCenario (en cenario tr)
  (OBJ:GravarResultado en cenario "CENARIO"
    (OBJ:_SetChave (OBJ:ResultGrupoDe en cenario "CENARIO") "TR" tr))
)

;; (puro) `result` apos um calculo: cenario com TR, sem OBSOLETO e com todos os grupos dados.
;;   grupos : alist (grupo . campos); campos nil remove o grupo
(defun OBJ:_ResultCalculo (result cenario tr grupos / meta g)
  (setq meta
    (OBJ:_SetChave
      (OBJ:_SetChave (OBJ:_Val "CENARIO" (cdr (assoc cenario result))) "TR" tr)
      "OBSOLETO" nil))
  (setq result (OBJ:_ResultSetGrupo result cenario "CENARIO" meta))
  (foreach g grupos
    (setq result (OBJ:_ResultSetGrupo result cenario (car g) (cdr g)))
  )
  result
)

;; Grava o resultado de UM calculo numa unica gravacao (desempenho): cria/atualiza o
;; cenario com o TR, remove "OBSOLETO" e grava todos os grupos.
;;   grupos : alist (grupo . campos), p. ex. (("ENTRADA" ("VALOR" . q) ..) ("VAZAO" ..))
;;   retorno: o registro gravado, ou nil
(defun OBJ:GravarCalculo (en cenario tr grupos / id reg)
  (setq id (OBJ:TipoDe en))
  (setq reg (if id (OBJ:Registro en) nil))
  (if (and reg cenario)
    (OBJ:GravaRegistro id en
      (OBJ:_SetChave reg "RESULT"
        (OBJ:_ResultCalculo (OBJ:_Val "RESULT" reg) cenario tr grupos)))
    nil
  )
)

;; Fim de um calculo: o cenario deixa de estar desatualizado (remove "OBSOLETO").
(defun OBJ:ConcluiCalculo (en cenario)
  (OBJ:GravarResultado en cenario "CENARIO"
    (OBJ:_SetChave (OBJ:ResultGrupoDe en cenario "CENARIO") "OBSOLETO" nil))
)

;; Nome padrao do cenario a partir do TR: 25.0 -> "TR25", 2.5 -> "TR2.5" (nil se TR nil)
(defun OBJ:CenarioPadrao (tr / txt)
  (if (and tr (numberp tr))
    (progn
      (setq txt (rtos tr 2 6))
      (if (vl-string-search "." txt)
        (progn
          (while (equal (substr txt (strlen txt)) "0")
            (setq txt (substr txt 1 (1- (strlen txt)))))
          (if (equal (substr txt (strlen txt)) ".")
            (setq txt (substr txt 1 (1- (strlen txt)))))
        )
      )
      (strcat "TR" txt)
    )
    nil
  )
)

;; Nome do cenario: o TR e, se o usuario deu um nome, "TR25-Nome" (nome nil = so o TR)
(defun OBJ:CenarioNome (tr nome)
  (if (and nome (/= nome ""))
    (if (OBJ:CenarioPadrao tr) (strcat (OBJ:CenarioPadrao tr) "-" nome) nil)
    (OBJ:CenarioPadrao tr)
  )
)

;; Nome dado pelo usuario ao cenario (HYDRO.CENARIO.NOME), ou nil (= so o TR)
(defun OBJ:NomeCenario (/ n)
  (setq n (HYDRO:Get "HYDRO.CENARIO.NOME" nil))
  (if (and n (/= n "")) n nil)
)

;; Cenario em uso: o ultimo TR (HYDRO.TR) mais o nome opcional; nil se ainda nao ha TR
(defun OBJ:CenarioAtual ()
  (OBJ:CenarioNome (HYDRO:Get "HYDRO.TR" nil) (OBJ:NomeCenario))
)

;; Define o nome do cenario (texto; nil volta a so o TR). Retorna o cenario em uso.
(defun OBJ:DefineNomeCenario (nome)
  (HYDRO:Set "HYDRO.CENARIO.NOME" (if nome nome ""))
  (OBJ:CenarioAtual)
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
;; refaca o indice dele (so os que guardam fora da extensao da entidade).
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

;; Pede a selecao de UM vinculo (definicao d = (chave rotulo aceita [obrigatorio])).
;;   retorno: handle da entidade escolhida, ou nil (Enter, so se nao obrigatorio)
(defun OBJ:_SelVinculo (d / sel ok h)
  (setq ok nil h nil)
  (while (not ok)
    (setq sel
      (entsel (strcat "\nSelecione " (cadr d) (if (nth 3 d) ": " " (Enter = pular): "))))
    (cond
      ((null sel)
        (if (nth 3 d) (princ "\nSelecao obrigatoria.") (setq ok T)))
      ((OBJ:_AceitaVinculo (car sel) (nth 2 d))
        (setq h (HYDRO:Handle (car sel)) ok T))
      (T
        (princ (strcat "\nEntidade " (HYDRO:DxfDe (car sel)) " nao e aceita aqui.")))
    )
  )
  h
)

;; Pede UM vinculo; `atual` = handle ja gravado (ou nil).
;;   retorno: handle final (nil = sem vinculo)
;; Com vinculo existente pergunta [Usar/Trocar/Remover] <Usar>; Remover so se nao
;; obrigatorio; Trocar e Enter mantem o atual.
(defun OBJ:_PedeUmVinculo (d atual / op h)
  (if (OBJ:_HandleOk atual)
    (progn
      (initget "Usar Trocar Remover")
      (setq op
        (getkword
          (strcat "\n" (cadr d) " atual (handle " atual "). [Usar/Trocar"
                  (if (nth 3 d) "" "/Remover") "] <Usar>: ")))
      (cond
        ((equal op "Trocar")
          (setq h (OBJ:_SelVinculo d))
          (if (null h) (setq h atual)))
        ((and (equal op "Remover") (not (nth 3 d))) (setq h nil))
        (T (setq h atual))
      )
    )
    (setq h (OBJ:_SelVinculo d))
  )
  h
)

;; Percorre PARAMS-DEFS do tipo e pede cada vinculo.
;;   params : PARAMS atual (handles)
;;   retorno: alist (chave . handle) com o resultado final de CADA chave (cdr nil =
;;            sem vinculo), ou nil se o tipo nao declara PARAMS-DEFS
(defun OBJ:_PedeVinculos (id params / out d)
  (foreach d (OBJ:Cap id "PARAMS-DEFS")
    (setq out
      (append out
        (list (cons (car d) (OBJ:_PedeUmVinculo d (cdr (assoc (car d) params)))))))
  )
  out
)

;; Pergunta os CARACT-DEFS que o desenho NAO informa (CARACTERIZA nao devolveu).
;;   exist : CARACT atual (valores viram o padrao)
;;   retorno: alist (chave . valor) ou nil
(defun OBJ:_PedeManuais (id en params exist / defs caract falta)
  (setq defs (OBJ:Cap id "CARACT-DEFS"))
  (if defs
    (progn
      (setq caract (OBJ:_Caracteriza en id params))
      (setq falta
        (vl-remove-if (function (lambda (d) (assoc (car d) caract))) defs))
      (if falta
        (progn
          (princ "\nO desenho nao informa alguns dados; digite-os (valores manuais).")
          (HYDRO:AskParams falta (strcat "HYDRO.OBJ." id ".CARACT.") exist)
        )
        nil
      )
    )
    nil
  )
)

;; Edita UM campo do objeto: lista os campos (ATRIB, vinculos de PARAMS e CARACT
;; manual) com o valor atual, o usuario escolhe um e so ele e perguntado.
;;   retorno: registro gravado, ou nil (cancelou, sem campos, nao e objeto)
;; Grava por OBJ:CadastrarCom: recaracteriza, marca obsoleto e propaga conforme
;; HYDRO.OBSOLETO.PROPAGA. Nao recalcula nada.
(defun OBJ:EditaCampoInterativo (en /
                                 id reg atrib params caract itens d it idx kind def chave
                                 v nome vinc manual novo)
  (setq id (OBJ:TipoDe en))
  (setq reg (if id (OBJ:Ler en) nil))
  (cond
    ((or (null id) (null reg))
      (alert "Esta entidade ainda nao esta cadastrada. Cadastre-a primeiro (<TIPO>CAD).")
      nil
    )
    (T
      (setq atrib (OBJ:_Val "ATRIB" reg))
      (setq params (OBJ:_Val "PARAMS" reg))
      (setq caract (OBJ:_Val "CARACT" reg))
      (foreach d (OBJ:Cap id "ATRIB-DEFS")
        (setq itens
          (append itens
            (list
              (list (strcat (OBJ:_RotuloParam id (car d)) ": "
                            (OBJ:_FmtVal (cdr (assoc (car d) atrib))))
                    "A" d))))
      )
      (foreach d (OBJ:Cap id "PARAMS-DEFS")
        (setq itens
          (append itens
            (list
              (list (strcat (cadr d) " (vinculo): "
                            (OBJ:_FmtVal (cdr (assoc (car d) params))))
                    "P" d))))
      )
      ;; CARACT so se for manual ou ainda sem valor; o que o desenho informa nao se digita
      (foreach d (OBJ:Cap id "CARACT-DEFS")
        (if (or (member (car d) (OBJ:_Val "MANUAL" caract)) (not (assoc (car d) caract)))
          (setq itens
            (append itens
              (list
                (list (strcat (cadr d) " (manual): "
                              (OBJ:_FmtVal (cdr (assoc (car d) caract))))
                      "C" d))))
        )
      )
      (cond
        ((null itens)
          (alert "Este tipo nao tem campos editaveis.")
          nil
        )
        (T
          (setq idx
            (HYDRO:Escolher
              (strcat "Campo a alterar em " (OBJ:Nome en) ":")
              (mapcar 'car itens) 0))
          (setq it (nth idx itens))
          (setq kind (nth 1 it))
          (setq def (nth 2 it))
          (setq chave (car def))
          (setq nome (OBJ:_Val "NOME" reg))
          (cond
            ((equal kind "A")
              (setq v
                (HYDRO:AskParams (list def) (strcat "HYDRO.OBJ." id ".")
                  (if (assoc chave atrib) (list (assoc chave atrib)) nil)))
              (setq atrib (OBJ:_SetChave atrib chave (cdr (assoc chave v))))
            )
            ((equal kind "P")
              (setq vinc
                (list (cons chave (OBJ:_PedeUmVinculo def (cdr (assoc chave params))))))
            )
            (T
              (setq manual
                (HYDRO:AskParams (list def) (strcat "HYDRO.OBJ." id ".CARACT.")
                  (if (assoc chave caract) (list (assoc chave caract)) nil)))
            )
          )
          (setq novo (OBJ:CadastrarCom en id atrib nome vinc manual))
          (if (null novo) (alert "Nao foi possivel gravar os dados na entidade."))
          novo
        )
      )
    )
  )
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
                               dxf nativo tipos reg idx item id nome pad exist params novo
                               vinc params1 v manual)
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
          ;; vinculos (PARAMS-DEFS) e, onde o desenho nao informa, CARACT manual
          (setq params1 (if (equal (OBJ:_Val "TIPO" reg) id) (OBJ:_Val "PARAMS" reg) nil))
          (setq vinc (OBJ:_PedeVinculos id params1))
          (foreach v vinc
            (setq params1 (OBJ:_SetChave params1 (car v) (cdr v)))
          )
          (setq manual
            (OBJ:_PedeManuais id en params1
              (if (equal (OBJ:_Val "TIPO" reg) id) (OBJ:_Val "CARACT" reg) nil)))
          (setq novo (OBJ:CadastrarCom en id params nome vinc manual))
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

;; Comando CENARIO: define o nome do cenario. O cenario e criado pelo TR do calculo
;; ("TR25"); com um nome fica "TR25-Nome". Enter = so o TR.
(defun c:CENARIO (/ atual n)
  (setq atual (OBJ:NomeCenario))
  (princ (strcat "\nCenario em uso: " (if (OBJ:CenarioAtual) (OBJ:CenarioAtual) "(defina o TR em um calculo)")
                 "\n(O cenario nasce do tempo de retorno; um nome gera TRxx-Nome.)"))
  (setq n
    (getstring T
      (strcat "\nNome do cenario" (if atual (strcat " <" atual ">") "")
              " (Enter = so o TR): ")))
  (OBJ:DefineNomeCenario (if (and n (/= n "")) n nil))
  (princ (strcat "\nCenario em uso: " (if (OBJ:CenarioAtual) (OBJ:CenarioAtual) "(so o TR, definido no calculo)")))
  (princ)
)

;; Flag geral: propagar a marca de resultado desatualizado para jusante
(defun c:PROPAGAOBSOLETO (/ op ativa)
  (setq ativa (OBJ:PropagaObsoleto))
  (princ
    (strcat "\nMarcar tambem os objetos de jusante como desatualizados ao editar: "
            (if ativa "SIM" "NAO")
            "\n(So a marca; nada e recalculado. Recalcule com CALCULAOBJETO.)"))
  (initget "Sim Nao")
  (setq op
    (getkword (strcat "\nPropagar para jusante? [Sim/Nao] <" (if ativa "Sim" "Nao") ">: ")))
  (if op
    (HYDRO:Set "HYDRO.OBSOLETO.PROPAGA" (if (equal op "Sim") 1 0))
  )
  (princ)
)

(defun c:CARACTAUTO (/ op ativa)
  (setq ativa (OBJ:CaractAuto))
  (princ
    (strcat "
Reler o desenho (comprimento, declividade...) antes de calcular: "
            (if ativa "SIM" "NAO")
            "
(Com NAO o calculo usa o CARACT gravado; atualize com <TIPO>CAD.)"))
  (initget "Sim Nao")
  (setq op
    (getkword (strcat "
Reler o desenho ao calcular? [Sim/Nao] <" (if ativa "Sim" "Nao") ">: ")))
  (if op
    (HYDRO:Set "HYDRO.CARACT.AUTO" (if (equal op "Sim") 1 0))
  )
  (princ)
)

(HYDRO:SetLabel "HYDRO.CARACT.AUTO" "Reler o desenho antes de calcular (1 = sim)" "")
(HYDRO:SetLabel "HYDRO.OBJETOS" "Objetos hidraulicos cadastrados (handles)" "")
(HYDRO:SetLabel "HYDRO.CENARIO.NOME" "Nome do cenario (vazio = so o TR; ex.: TR25-Nome)" "")
(HYDRO:SetLabel "HYDRO.OBSOLETO.PROPAGA" "Propagar resultado desatualizado para jusante (1 = sim)" "")

(HYDRO:Provide "objetos" "1.0")
(princ)
