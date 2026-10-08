# Arquitetura do Hydro

Documento de referência: **o que cada peça oferece** e **os contratos entre os
plugins** (eventos, chaves de configuração, códigos de XData). Atualize-o
sempre que criar um plugin, evento ou chave nova.

## 1. Visão geral

```
hydro.lsp ──► core/core ──► plugins/* (sistema) ──► views/* (interface)   (conforme HYDRO:Manifest)

core        registro de funcionalidades, eventos, configuração, rótulos,
            localização de arquivos, carregador
persistence DB:      persistência no desenho (dicionário de objetos nomeados)
relacao     XD:      XData e relacionamento entre entidades
idf         PREC:    equação IDF (parâmetros, intensidade); diálogo em views/idf_view
precipitacao HIET:   hietogramas de projeto: consome a IDF e gera o hietograma do tipo pedido
sarjetas    SARJ:    cálculo direto de sarjeta (fluxo antigo: bacia + talvegue + seção atual), comandos e texto no desenho
secao       SJT:     visualização de seções de sarjeta (exagero vertical, lâmina d'água)
models/     OBJETOS DO SISTEMA (só a funcionalidade do objeto; sem perguntas, comandos nem texto no desenho):
  bacia           BAC:   bacia: registro, caracterização, tc, vazão; declara o tipo "bacia"
  sarjeta         SOB:   sarjeta: seções, geometria, hidráulica (Izzard); declara o tipo "sarjeta"
  objetos_tipos   OTP:   tipos básicos: trecho, estrutura, tubo-c3d
registry/   CATÁLOGOS (só cadastros de métodos e tipos; carregam depois do sistema):
  metodos         MET:   métodos chuva-vazão (racional, SCS-CN, vazão informada)
  tempo_conc      TCM:   métodos de tempo de concentração (Kirpich, Ventura, Pasini...)
  hidrograma_tipos HID:  tipos de hidrograma (triangular, adimensional, trapezoidal, usuário)
  hietograma_tipos HIET: tipos de hietograma (bloco único, blocos alternados, Chicago)
bacia_view  BAC:     (views/) perguntas, comandos e etiquetagem da bacia (BACIACAD, BACIA, TEXTOBACIA...)
bacia_tabela BTB:    (views/) tabela das bacias do desenho (detalhes, ações, CSV)
objetos     OBJ:     objetos hidráulicos genéricos: catálogo de TIPOS e cadastro em qualquer entidade
ligacao     LIG:     ligações de descarga entre objetos (o receptor guarda os montantes em `PARAMS`), tc acumulado e integridade
objetos_tabela OBT:  tabela de objetos e ligações (LIGACOES)
hidrograma  HID:     geração e armazenamento de hidrogramas (os tipos estão em registry/); gráfico e CSV em views/
viewer      VIEW:    visualização dos dados persistidos
painel      PNL:     (views/) painel de botões (HYDRO), gerado do catálogo de ações; exporta macros p/ ribbon
painel_acoes -       (views/) botões dos comandos existentes (cadastro em PNL:Acao)
menu        MNU:     (views/) menu suspenso "Hydro" na barra de menus (ActiveX), do mesmo catálogo de ações
toolbar     TLB:     (views/) barras de ferramentas "Hydro - <grupo>" (AcadToolbars) com ícones, do mesmo catálogo
```

Plugins são **independentes entre si**, mas todos dependem do `core`.

## 2. Regras de convivência

1. **Prefixo por plugin** em todo símbolo público (`SARJ:Calcular`) e `_`
   para internos (`SARJ:_Area`). Comandos (`c:XXX`) são globais por definição
   do AutoLISP.
2. **Sem variáveis globais.** Estado vai para `HYDRO:Get` / `HYDRO:Set`.
   Únicas globais do conjunto: `HYDRO:*features*`, `HYDRO:*hooks*`,
   `HYDRO:*session*`, `HYDRO:*labels*`, `HYDRO:*registry*`, `HYDRO:*dir*`,
   `HYDRO:*embedded*`.
3. **Declare todas as variáveis locais** depois da `/`. AutoLISP tem escopo
   dinâmico: variável não declarada vira global e vaza.
4. **Funções de cálculo são puras** (sem `getXXX`, `alert`, `princ`). A
   interação fica nos comandos.
5. **Nada que dependa de outro plugin roda no momento do load.** Tudo é
   resolvido quando o comando executa.
6. **Código em ASCII** (sem acentos nas strings).
7. **`and` e `or` devolvem `T` ou `nil`, nunca o valor.** Em AutoLISP,
   `(or (findfile "a") (findfile "b"))` devolve `T`, não o caminho. Para obter
   o primeiro valor não nulo use `cond`/`if` com `setq`, ou `HYDRO:FirstFile`
   para caminhos de arquivo. `and`/`or` servem só como **teste**.

## 3. Registro de funcionalidades

```lisp
(HYDRO:Provide "xdata" "2.0")        ; no fim do plugin
(HYDRO:Has "xdata")                  ; dependência OPCIONAL
(HYDRO:Require "idf")                ; dependência OBRIGATÓRIA (avisa se faltar)
```

Nomes registrados: `core`, `hydro`, `persistencia`, `xdata`, `idf`, `precipitacao`,
`sarjetas`, `secao`, `metodos`, `tempo-conc`, `hidrograma-tipos`, `hietograma-tipos`,
`bacia`, `bacia-tabela`, `hidrograma`,
`objetos`, `ligacao`, `objetos-tipos`, `sarjeta-obj`, `objetos-tabela`, `visualizador`,
`painel`, `painel-acoes`, `menu`, `toolbar`.

## 4. Eventos

```lisp
(HYDRO:On   "evento" "id-do-assinante" 'MINHA-FUNCAO)  ; assinar
(HYDRO:Emit "evento" dados)                            ; publicar (dados = alist)
(HYDRO:Off  "evento" "id-do-assinante")
```

Um assinante com erro não derruba o emissor nem os demais.

### Catálogo

| Evento                | Emitido por                                    | Assinado por                                                                  | Dados                                                                                                                                                                                                                                                                                                             |
| --------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sarjeta.calculada` | `sarjetas`                                   | `relacao` (grava XData), `secao` (guarda último Q/S)                     | `"BACIA"` `"TALVEGUE"` (enames), `"AREA"`, `"COMPRIMENTO"`, `"DECLIVIDADE"`, `"TC"`, `"CASOS"` (lista de `(rotulo tr intensidade vazao)`), `"Q"` (vazão do primeiro caso, m³/s), `"LAMINA"`, `"LARGURA"`, `"AREA-MOLHADA"`, `"VELOCIDADE"`, `"SECAO"`, `"SECAO-ID"`, `"AVISOS"` |
| `objeto.cadastrado` | `objetos`                                    | —                                                                            | `"OBJETO"` (ename), `"TIPO"`                                                                                                                                                                                                                                                                                  |
| `hydro.carregado`   | `core` (fim de `HYDRO:LoadAll`; e `hydro.lsp` no modo VLX) | `menu` (cria o menu), `toolbar` (cria as barras) | nenhum. Indica que **todos** os plugins já cadastraram catálogos, ações e rótulos |
| `objeto.removido`   | `objetos` (e `models/bacia`, para a bacia) | `ligacao` (desfaz as ligações do objeto)                                  | `"OBJETO"`. Emitido **antes** de apagar o cadastro                                                                                                                                                                                                                                                        |
| `bacia.removida`    | `models/bacia`                               | `models/bacia` (reemite como `objeto.removido`)                           | `"BACIA"` (ename). Emitido antes de apagar o cadastro                                                                                                                                                                                                                                                           |
| `ligacao.criada`    | `ligacao`                                    | — (ponto de conexão futuro)                                                 | `"ORIGEM"`, `"DESTINO"` (enames), `"ANTERIOR"` (ename ou nil: destino de onde foi movida)                                                                                                                                                                                                                   |
| `ligacao.removida`  | `ligacao`                                    | —                                                                            | `"ORIGEM"`, `"DESTINO"`                                                                                                                                                                                                                                                                                       |
| `objeto.calculado`  | `ligacao` (CALCULAOBJETO)                    | —                                                                            | `"OBJETO"`, `"TIPO"`, `"METODO"`, `"TR"`, `"RES"`                                                                                                                                                                                                                                                       |
| `bacia.cadastrada`  | `bacia`                                      | `relacao` (relaciona contorno↔talvegue, XData `DREN-BACIA`)              | `"BACIA"` `"TALVEGUE"` (enames), `"NOME"`, `"AREA"`, `"COMP"`, `"DESNIVEL"`, `"DECL"`, `"TC"`, `"TC-ORIGEM"`, ...                                                                                                                                                                               |
| `bacia.calculada`   | `bacia`                                      | `relacao` (relaciona contorno↔talvegue e grava Qp em XData `DREN-BACIA`) | `"BACIA"` `"TALVEGUE"` (enames), `"AREA"`, `"COMP"`, `"DECL"`, `"TC"`, `"METODO"`, `"TR"`, `"DUR"`, `"QP"`, `"PE"`, `"VOLUME"`                                                                                                                                                            |
| `hidrograma.gerado` | `hidrograma`                                 | — (ponto de conexão futuro)                                                 | `"BACIA"` (ename), `"TIPO"`, `"METODO"`, `"TR"`, `"DUR"`, `"QP"`, `"TP"`, `"TB"`, `"VOLUME"`, `"PONTOS"` (lista de `(t_min . q_m3s)`)                                                                                                                                                       |

## 5. Configuração compartilhada

`HYDRO:Get path padrao` / `HYDRO:Set path valor` / `HYDRO:Del path`.
Com o plugin `persistencia`, grava no desenho; sem ele, só na sessão.

### Catálogo de chaves

| Chave                                                       | Tipo             | Dono                  | Descrição                                                                                  |
| ----------------------------------------------------------- | ---------------- | --------------------- | -------------------------------------------------------------------------------------------- |
| `HYDRO.IDF.K/A/B/C/S/P`                                   | real             | `idf`               | Parâmetros da equação IDF                                                                 |
| `HYDRO.TR`                                                | real             | `idf`               | Tempo de retorno atual (anos)                                                                |
| `HYDRO.RUNOFF`                                            | real             | `sarjetas`          | Coeficiente de escoamento superficial                                                        |
| `HYDRO.TC.MINIMO`                                         | real             | `sarjetas`          | Tc mínimo (min). Padrão 10                                                                 |
| `HYDRO.TEXT.HEIGHT`                                       | real             | `sarjetas`          | Altura do texto de resultado                                                                 |
| `HYDRO.TEXT.ROTATION`                                     | real             | `sarjetas`          | Rotação do texto (graus)                                                                   |
| `HYDRO.SURFACE.HANDLE`                                    | string           | `sarjetas`          | Handle da superfície TIN                                                                    |
| `HYDRO.SECOES`                                            | lista            | `sarjetas`          | Seções cadastradas`(id ("h" . x) ("s" . x) ("w" . x) ("n" . x))`                         |
| `HYDRO.VAZAO.PRESERVA`                                    | inteiro          | `ligacao`           | 1 = preservar a maior vazão entre entrada e saída (flag geral; padrão 1)                       |
| `HYDRO.SECAO.ATUAL`                                       | inteiro          | `sarjetas`          | Id da seção em uso (o plugin`secao` também a altera ao "Selecionar")                    |
| `HYDRO.SECAO.EXAG`                                        | inteiro          | `secao`             | Exagero vertical da visualização (1, 2, 5 ou 10)                                           |
| `HYDRO.SECAO.COMUM`                                       | inteiro          | `secao`             | 1 = escala comum a todas as seções                                                         |
| `HYDRO.ULTIMO.Q`                                          | real             | `secao`             | Vazão (m³/s) do último cálculo de sarjeta                                                |
| `HYDRO.ULTIMO.DECL`                                       | real             | `secao`             | Declividade longitudinal (m/m) do último cálculo                                           |
| `HYDRO.ULTIMO.SECAO`                                      | inteiro          | `secao`             | Id da seção usada no último cálculo                                                      |
| `HYDRO.TC.MINIMO`, `HYDRO.TR`, `HYDRO.SURFACE.HANDLE` | real/real/string | `sarjetas`, `idf` | **Compartilhadas** também pelo plugin `bacia`                                       |
| `HYDRO.BACIAS`                                            | lista de strings | `bacia`             | Handles das bacias cadastradas (índice para listar)                                         |
| `HYDRO.BACIA.METODO`                                      | string           | `bacia`             | Último método chuva-vazão usado                                                           |
| `HYDRO.BACIA.TCMETODO`                                    | string           | `bacia`             | Último método de tc escolhido                                                              |
| `HYDRO.OBJETOS`                                           | lista de strings | `objetos`           | Handles dos objetos cadastrados (índice)                                                    |
| `HYDRO.PAINEL.MANTER` | inteiro | `painel` | 1 = o painel reabre depois de cada comando |
| `HYDRO.MENU.AUTO` | inteiro | `menu` | 1 = cria o menu "Hydro" sozinho ao carregar |
| `HYDRO.MACRO.ESTILO` | string | `painel` | Formato da macro de menu/barras: `lisp` (padrão, `(c:NOME)`), `cancela-lisp`, `nome`, `cancela` (`^C^CNOME`), `espaco` |
| `HYDRO.TOOLBAR.AUTO` | inteiro | `toolbar` | 1 = cria as barras sozinho ao carregar |
| `HYDRO.TOOLBAR.DOCK` | string | `toolbar` | Posição inicial das barras NOVAS: `left` (padrão), `top`, `bottom`, `right`, `float` |
| `HYDRO.TOOLBAR.EXT` | string | `toolbar` | Formato dos ícones: `bmp` (padrão) ou `png` |
| `HYDRO.OBJ.<tipo>.<param>`                                | variado          | `objetos`           | Último valor usado em cada dado de cada tipo de objeto                                      |
| `HYDRO.OBJ.<tipo>.calc.<param>`                           | variado          | `ligacao`           | Último valor usado nos parâmetros de cálculo do tipo                                      |
| `HYDRO.TC.<id>.<param>`                                   | variado          | `tempo_conc`        | Último valor usado em cada parâmetro de cada método de tc (ex.:`HYDRO.TC.giandotti.HM`) |
| `HYDRO.TEXT.HEIGHT`, `HYDRO.TEXT.ROTATION`              | real             | `sarjetas`          | **Compartilhadas** com o texto de resultado da bacia                                   |
| `HYDRO.MET.<id>.<param>`                                  | variado          | `metodos`           | Último valor usado em cada parâmetro de cada método (ex.:`HYDRO.MET.scs-cn.CN`)         |
| `HYDRO.HID.TIPO`                                          | string           | `hidrograma`        | Último tipo de hidrograma usado                                                             |
| `HYDRO.HID.<id>.<param>`                                  | variado          | `hidrograma`        | Último valor usado em cada parâmetro de cada tipo                                          |

> Limitação do `DB:`: um valor que seja **lista** é gravado como folha; não
> use esse caminho como intermediário (ex.: não grave `HYDRO.SECOES.X`).

## 6. XData

Aplicação padrão: `DREN-SARJETA`. Convenção: **nomes de aplicação de XData
começam com `DREN-`**, assim o visualizador os encontra sozinho.

| Código  | Significado                                        | Escrito por                       |
| -------- | -------------------------------------------------- | --------------------------------- |
| `1005` | Handle da entidade relacionada (bacia ↔ talvegue) | `XD:Link`                       |
| `1040` | Vazão Q (m³/s) na polilinha da bacia             | assinante de`sarjeta.calculada` |

Limitação: um valor por código, por entidade e por aplicação.

## 7. Rótulos (para o visualizador)

```lisp
(HYDRO:SetLabel "HYDRO.RUNOFF" "Coeficiente de runoff (C)" "")
(HYDRO:SetLabel "xdata:DREN-SARJETA:1040" "Vazao Q" "m3/s")
```

Chaves de XData: `xdata:<APP>:<codigo>`. Chaves de DB: o próprio path.

## 8. Comandos

| Comando                                                                                       | Plugin         | Função                                                                                                                          |
| --------------------------------------------------------------------------------------------- | -------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `HYDROPLUGINS`                                                                              | core           | Lista raiz e plugins ativos                                                                                                       |
| `HYDRODIR`                                                                                  | hydro.lsp      | Escolhe/limpa a pasta do Hydro (caixa de diálogo; grava no Registro)                                                             |
| `HYDRORELOAD`                                                                               | hydro.lsp      | Recarrega core e plugins a partir da raiz atual                                                                                   |
| `HYDRODADOS` / `HYDRODUMP`                                                                | viewer         | Diálogo / texto com dados persistidos                                                                                            |
| `IDF`, `ATUALIZAIDF`, `ATUALIZATR`                                                      | idf            | Visualiza e atualiza a IDF e o TR                                                                                                 |
| `CALCULASARJETA`, `CALCULASARJETAMULTITR`                                                 | sarjetas       | Calcula e mostra                                                                                                                  |
| `CRIARSARJETARESULTADO`, `CRIARSARJETARESULTADOMULTITR`                                   | sarjetas       | Calcula e insere MTEXT                                                                                                            |
| `ATUALIZARUNOFF`, `ATUALIZASUPERFICIE`, `ATUALIZAROTACAOTEXTO`, `ATUALIZAALTURATEXTO` | sarjetas       | Parâmetros                                                                                                                       |
| `CRIASECAO`                                                                             | secao-view     | Cadastra seção de sarjeta (h, s, w, n), torna atual e desenha opcionalmente (`SJT:Adicionar`)                                   |
| `EDITASECAO`, `REMOVESECAO` | secao-view | Editam / removem seção cadastrada (`SJT:Editar`, `SJT:Remover`, `SJT:EmUso`) |
| `BACIACAD`                                                                                  | bacia          | **Cadastra** (ou edita) a bacia: nome, tc por método, C e CN. Sem calcular vazão                                          |
| `BACIA`                                                                                     | bacia          | Calcula a vazão por um método cadastrado e guarda na entidade (usa o cadastro; cadastra se preciso)                             |
| `CRIARBACIARESULTADO`                                                                       | bacia          | Calcula a bacia e insere o resultado como texto (MTEXT)                                                                           |
| `TEXTOBACIA`                                                                                | bacia          | Insere como texto um (ou todos) os cálculos já cadastrados                                                                      |
| `BACIAS`, `BACIAINFO`                                                                     | bacia          | Lista em texto / mostra os dados de uma bacia                                                                                     |
| `BACIATABELA`                                                                               | bacia_tabela   | Tabela das bacias do desenho com detalhes, ações e CSV                                                                          |
| `OBJETO`                                                                                    | objetos        | Cadastra/edita uma entidade como objeto hidráulico (escolhe o tipo entre os que aceitam a entidade)                              |
| `OBJETOINFO`, `OBJETOREMOVER`                                                             | objetos        | Dados do objeto / remove o cadastro (desfaz as ligações dele)                                                                   |
| `OBJETOS`, `OBJETOZOOM`, `OBJETOVINCULOS` | objetos-padrao-view | Lista objetos de um tipo / localiza qualquer objeto (zoom) / realça os vínculos de `PARAMS` (seção 18b) |
| `SARJETACAD`, `SARJETAS`, `SARJETAINFO`, `SARJETAZOOM`, `BACIAZOOM` | sarjeta, bacia | Comandos padrão do objeto (seção 18b) |
| `HYDROAUDIT` | auditoria-view | Audita o desenho, pergunta e corrige (seção 18b) |
| `LIGAR`                                                                                     | ligacao        | Origens (várias) → destino. Enter no destino usa o destino padrão da origem (a bacia sugere o próprio talvegue)               |
| `DESLIGAR`                                                                                  | ligacao        | Tira a(s) origem(ns) do destino atual                                                                                             |
| `PRESERVAVAZAO`                                                                             | ligacao        | Liga/desliga a flag geral de preservação da maior vazão entre entrada e saída (15.4)                                          |
| `VALIDARLIGACOES`                                                                           | ligacao        | Verifica e corrige a integridade das ligações                                                                                   |
| `CALCULAOBJETO`                                                                             | ligacao        | Calcula um objeto: entrada (saídas dos montantes), saída (precipitação no maior tempo) e o cálculo do tipo                                                       |
| `LIGACOES`                                                                                  | objetos_tabela | Tabela de objetos e ligações: destino, afluentes, árvore a montante, cadeia a jusante, ações                                 |
| `HYDRO`, `HYDROPAINEL` | painel | Painel de botões com todos os comandos agrupados |
| `HYDROBARRAS`, `HYDROBARRASREMOVER` | toolbar | Cria/atualiza e mostra as barras "Hydro - *" / apaga |
| `HYDROMENU`, `HYDROMENUREMOVER` | menu | (Re)cria o menu "Hydro" na barra de menus (oferece mostrar a barra) / remove |
| `HYDROMACROESTILO` | painel | Escolhe o estilo da macro e reconstrói menu e barras |
| `HYDROMACROS` | painel | Exporta as macros de todas as ações, para montar a ribbon |
| `HIDROGRAMA`                                                                                | hidrograma     | Gera um hidrograma (tipo escolhido), guarda na bacia e abre o visualizador                                                        |
| `HIDROGRAMAVER`                                                                             | hidrograma     | Visualizador: vários hidrogramas sobrepostos, tabela, CSV e exclusão                                                            |
| `SECAO`                                                                                     | secao          | Diálogo visual das seções; "Selecionar" define a seção atual; "Inserir no desenho" desenha a seção (camada`HYDRO-SECAO`) |
| `SETUSERVALUE`, `GETUSERVALUE`                                                            | persistence    | Depuração do`DB:`                                                                                                             |
| `HYDROTESTE`                                                                                | tests          | Testes das funções puras                                                                                                        |

## 9. Como criar um plugin novo

1. Copie `docs/template_plugin.lsp` para `Contents/plugins/<nome>.lsp` (dialogos e comandos em `Contents/views/<nome>_view.lsp`).
2. Troque o prefixo e implemente (siga a seção 2).
3. Inclua `"plugins/<nome>"` em `HYDRO:Manifest` (`core/core.lsp`).
4. Registre rótulos dos seus dados (`HYDRO:SetLabel`).
5. Documente aqui os eventos e chaves novos.
6. Se for compilar em VLX, inclua o arquivo **antes** do `hydro.lsp` no projeto.

## 10. Catálogos de extensões (métodos e tipos)

O core guarda **catálogos**: qualquer plugin cadastra itens, qualquer outro
lista e usa, sem se conhecerem.

```lisp
(HYDRO:RegAdd  "catalogo" "id" dados)     ; dados = alist
(HYDRO:RegList "catalogo")                ; -> (("id" . dados) ...), na ordem de cadastro
(HYDRO:RegGet  "catalogo" "id")           ; -> dados
```

| Catálogo              | Quem cadastra                                         | Quem consome     |
| ---------------------- | ----------------------------------------------------- | ---------------- |
| `metodo-chuva-vazao` | `registry/metodos` (e qualquer plugin seu)          | `bacia`        |
| `hidrograma-tipo`    | `registry/hidrograma_tipos` (e qualquer plugin seu) | `hidrograma`   |
| `hietograma-tipo`    | `registry/hietograma_tipos` (e qualquer plugin seu) | `precipitacao` |
| `acao-painel`        | `views/painel_acoes` (e qualquer plugin seu, com `PNL:Acao`) | `painel`, `menu`, `toolbar` |

### Descrição de parâmetros (usada nos dois catálogos)

Lista de `(chave rotulo padrao unidade [tipo [opcoes]])`:

| `tipo`             | Pergunta                              | Valor            |
| -------------------- | ------------------------------------- | ---------------- |
| omitido ou`"real"` | número (Enter mantém o padrão)     | real             |
| `"int"`            | número inteiro                       | inteiro          |
| `"arquivo"`        | caixa de abrir arquivo                | caminho (string) |
| `"opcoes"`         | menu numerado sobre a lista`opcoes` | string escolhida |

`HYDRO:AskParams defs prefixo sobrescritas` faz as perguntas, **lembra o último
valor** em `<prefixo><chave>` e devolve uma alist `(chave . valor)`.
`sobrescritas` é um alist de padrões válidos só daquela vez (não memorizado).

## 11. Bacia: dados guardados na entidade

Uma bacia = polilinha de **contorno** (fechada) + polilinha de **talvegue**.
Os dados ficam no **dicionário de extensão do contorno**, chave `HYDRO-OBJ`,
no **envelope padrão dos objetos** (seção 18, com a tabela de como cada campo
da bacia é distribuído em `PARAMS`/`ATRIB`/`CARACT`/`RESULT`); acompanham a
entidade ao copiar, colar e salvar.

O plugin trabalha **diretamente** com esse registro (não há estrutura
intermediária): `BAC:Ler` devolve o registro, `BAC:Gravar` grava.

```
(("VERSAO" . 2) ("TIPO" . "bacia") ("NOME" . "B1") ("DESCRICAO" . "texto")
 ("SPARAMS" . (("TALVEGUE" . "handle")))
 ("ATRIB"  . (("C" . 0.6) ("CN" . 80.0)))
 ("CARACT" . (("AREA" . m2) ("COMP" . m) ("DESNIVEL" . m) ("DECL" . m/m)))
 ("RESULT" . (("TC" . (("MIN" . min) ("ORIGEM" . "kirpich"|"usuario") ("PARAMS" . alist)))
              ("VAZAO" . (vazao ...))
              ("HIDROGRAMAS" . (hidrograma ...)))))

vazao = (("METODO" . id) ("TR" . anos) ("DUR" . min) ("TC" . min) ("PARAMS" . alist)
         ("I" . mm/h) ("P" . mm) ("PE" . mm) ("QP" . m3/s) ("VOLUME" . m3))
    campos calculados PLANOS, sem sub-lista "RES"
    uma nova vazao com o mesmo METODO e TR substitui a anterior
hidrograma = (("TIPO" . id) ("METODO" . id) ("TR" . anos) ("DUR" . min)
              ("PARAMS" . alist) ("QP" . m3/s) ("TP" . min) ("TB" . min)
              ("VOLUME" . m3) ["NOTA" . texto] ("PONTOS" . ((t . q) ...)))
    um novo hidrograma com o mesmo TIPO, METODO e TR substitui o anterior
```

Acessos: `BAC:Nome`, `BAC:Descricao`, `BAC:Params`, `BAC:Talvegue`, `BAC:Atrib`,
`BAC:Caract`, `BAC:Result`, `BAC:Tc`, `BAC:Calculos`, `BAC:Hidrogramas`. Alterar um resultado: `BAC:_SetResult dados chave valor`.
Outras funções: `BAC:Listar`, `BAC:Caracterizar`, `BAC:ExecutarMetodo`,
`BAC:Contexto`, `BAC:Obter`. Chaves **não** guardam valores `nil`; use `T` ou
omita o par.

`BAC:Obter` e `BAC:CadastroInterativo` devolvem um **contexto de cálculo**
(`BAC:_Ctx`): características + `"TC"`, `"TC-ORIGEM"`, `"NOME"` e atributos
(C, CN). Ele **não** é o que fica gravado, só a entrada dos métodos.

**Preparação para conectar** (ainda não conectado): o plugin de sarjetas tem
sua própria cópia da geometria (área, comprimento, Kirpich). Quando as
informações forem conectadas, `SARJ:` passa a usar `BAC:Caracterizar`, e a
sarjeta pode ler `BAC:Ler` para obter a vazão de pico da bacia que a alimenta.
Os eventos `bacia.calculada` e `hidrograma.gerado` já existem para isso.

## 12. Como cadastrar um método chuva-vazão ou um tipo de hidrograma

Modelos comentados: `docs/template_metodo.lsp`.

**Método** (`MET:Registrar id nome descricao requer usa-dur params fn`):
`fn` recebe `(ctx params)` e devolve um alist com o que calculou
(`"QP"`, `"PE"`, `"VOLUME"`, `"TP"`, `"DUR"`, `"I"`, `"P"`), ou
`(("ERRO" . "mensagem"))`. `ctx` traz `"AREA"` (m²), `"COMP"`, `"DECL"`,
`"TC"` (min), `"TR"` (anos) e `"DUR"` (min). `usa-dur = T` faz o comando
`BACIA` perguntar a duração da chuva; senão a duração é o tc.

**Tipo de hidrograma** (`HID:RegistrarTipo id nome descricao base requer-res params fn`):
`fn` recebe `(ctx params)` e devolve `(("PONTOS" . ((t_min . q_m3s) ...)))`.
`ctx` = `ctx` da bacia + `"METODO"` + resultado do método. `requer-res` lista
as chaves do resultado que o tipo exige (o plugin avisa se faltarem). QP, TP,
TB e VOLUME são calculados a partir dos pontos pelo próprio plugin.
`HID:_Amostra pontos dt extras` reamostra em passo uniforme sem perder os
vértices em `extras` (ex.: o pico).

### Métodos e tipos incluídos

| Método             | Fórmulas                                                                                                    |
| ------------------- | ------------------------------------------------------------------------------------------------------------ |
| `racional`        | Q = C·i·A/360 (m³/s; i em mm/h; A em ha); duração = tc                                                  |
| `scs-cn`          | S = 25400/CN − 254; Ia = λ·S; Pe = (P−Ia)²/(P−Ia+S); tp = D/2 + 0,6·tc; Qp = 0,208·A[km²]·Pe/tp[h] |
| `vazao-informada` | Qp fornecido; sem Pe nem volume                                                                              |

| Tipo                     | Base     | Observação                                                                                                               |
| ------------------------ | -------- | -------------------------------------------------------------------------------------------------------------------------- |
| `triangular-scs`       | área    | tp = D/2 + 0,6·tc; tb = (tb/tp)·tp;**Qp = 2V/tb** (conserva o volume; com tb/tp = 2,67 equivale a 0,208·A·Pe/tp) |
| `adimensional-scs`     | área    | HU curvilíneo do SCS, escalado por tp e pelo volume (Qp ≈ 1,7 % maior que 0,208·A·Pe/tp para conservar o volume)       |
| `racional-trapezoidal` | método  | sobe até tc, patamar em Qp até D, desce em tc                                                                            |
| `triangular-usuario`   | usuário | Qp, tp e tb/tp informados (padrões vindos do cálculo)                                                                    |
| `tabela-usuario`       | usuário | CSV`t;q`, absolutos ou adimensionais (t/tp ; q/qp); aceita `;` `,` tab ou espaço                                    |

**Limitações atuais:** chuva em bloco único (sem hietograma); SCS usa tp = D/2 + 0,6·tc
(tc de Kirpich ou informado); sem composição de sub-bacias nem propagação.

## 13. Cadastro da bacia e uso pelas sarjetas

O plugin `bacia` guarda o cadastro no dicionário de extensão do **contorno**
(chave `HYDRO-OBJ`). A bacia **não guarda nada da sarjeta**: o plugin de sarjetas
apenas lê o cadastro (`BAC:Obter`) quando `bacia` está carregado (sem ele,
sarjetas continua funcionando sozinho). Resultados de sarjeta pertencem ao
objeto sarjeta.

Onde ficam os dados do cadastro (registro da seção 11):

```
NOME                      ("NOME" . "B1"); sem nome a tabela mostra "B-<handle>"
ATRIB                     C e CN (opcionais)
RESULT -> TC              ("MIN" . min) ("ORIGEM" . id | "usuario") ("PARAMS" . alist)
RESULT -> VAZAO           cada vazão guarda o tc usado e os campos calculados (QP, PE...)
```

Como os dois plugins compartilham:

| Quem                          | O que usa do cadastro                                                                                                                                                                                                                                                                                                 |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sarjetas`                  | `BAC:Obter contorno talvegue`: área, comprimento, declividade, **tc (pelo método cadastrado)** e **C**. Se a bacia não está cadastrada, cadastra sozinho (Kirpich com tc mínimo). Se o contorno, o talvegue ou a superfície mudaram, atualiza o cadastro mantendo nome, atributos e método de tc |
| `bacia` (comando `BACIA`) | Reutiliza o cadastro (tc, atributos). Atributos coincidentes viram**padrão dos parâmetros** do método (ex.: `CN` do cadastro preenche o `CN` do SCS; `C` preenche o `C` do racional)                                                                                                                 |

Prioridade do coeficiente de escoamento na sarjeta: **C do cadastro da bacia**
→ `HYDRO.RUNOFF` global. Com o plugin `bacia` carregado, a sarjeta não exige
mais o runoff global (se faltar os dois, o cálculo avisa).

Sem o plugin `bacia`: sarjetas calcula a geometria localmente (Kirpich + `HYDRO.TC.MINIMO`)
e usa `HYDRO.RUNOFF`, como antes.

**Cadastro rápido** (`BACIACAD`): contorno → talvegue → nome (Enter = automático)
→ tc (`[Aceitar/Outro método/Informar]`, Enter aceita o padrão) → C e CN (Enter pula).
Rodar de novo edita o cadastro, mantendo os cálculos e hidrogramas.

**Texto no desenho:** `CRIARBACIARESULTADO` (calcula e insere) e `TEXTOBACIA`
(insere cálculos já cadastrados; pergunta qual ou todos). Usam a altura e a
rotação de `ATUALIZAALTURATEXTO` e `ATUALIZAROTACAOTEXTO` (as mesmas das sarjetas).

**Índice:** `HYDRO.BACIAS` guarda só os handles, para listar sem varrer o
desenho. `BACIATABELA` reconstrói o índice sozinho se estiver vazio (por
exemplo, ao colar bacias de outro desenho) e há o botão **Reindexar**.

## 14. Métodos de tempo de concentração

Catálogo `metodo-tc`, cadastrado em `plugins/registry/tempo_conc.lsp`:

```lisp
(TCM:Registrar id nome descricao params fn)
;; fn recebe (ctx params) e devolve (("TC" . min)) ou (("ERRO" . msg))
;; ctx = "AREA" (m2) "COMP" (m) "DESNIVEL" (m) "DECL" (m/m)
```

Incluídos (tc em minutos; A km², L km, S m/m, H m):

| id                  | Fórmula                                          | Parâmetros                                            |
| ------------------- | ------------------------------------------------- | ------------------------------------------------------ |
| `kirpich`         | 57·(L³/H)^0,385 (Kirpich / California Culverts) | —                                                     |
| `ventura`         | 60·0,127·(A/S)^0,5                              | —                                                     |
| `pasini`          | 60·0,107·(A·L)^(1/3)/S^0,5                     | —                                                     |
| `corps-engineers` | 60·0,191·L^0,76·S^−0,19                       | —                                                     |
| `giandotti`       | 60·(4·A^0,5 + 1,5·L)/(0,8·Hm^0,5)             | `HM` altitude média da bacia acima do exutório (m) |
| `george-ribeiro`  | 16·L/((1,05 − 0,2·p)·(100·S)^0,04)           | `P` fração da área com vegetação (0 a 1)        |
| `velocidade`      | L[m]/(60·v) (cinemático)                        | `V` velocidade média (m/s)                          |
| `informado`       | tc fornecido                                      | `TC` (min)                                           |

Observações:

- As fórmulas conferem com as expressões publicadas em fontes brasileiras e
  italianas de hidrologia (Kirpich 0,0663·L^0,77·S^−0,385 em horas equivale a
  57·(L³/H)^0,385 em minutos; George Ribeiro 0,222 h ≈ 13,3 min). **A faixa de
  validade de cada fórmula** (tamanho e tipo de bacia: rural, urbana, declividade) **é
  da literatura; confira antes de adotar.** Algumas fontes usam 0,108 no lugar de
  0,107 em Pasini (diferença de ~1 %).
- A declividade usada é a do **talvegue** (desnível entre o início e o fim ÷
  comprimento), como no cálculo atual. Fórmulas definidas com a declividade
  média da bacia (ex.: algumas versões de Ventura) ficam aproximadas.
- **tc mínimo:** `HYDRO.TC.MINIMO` (padrão 10 min) é aplicado ao valor calculado
  para sugerir o tc. Se você **informar** um valor (`Informar`), ele é respeitado.
- O método e os parâmetros ficam gravados no cadastro (`TC-ORIGEM`, `TC-PARAMS`).
  Se o cadastro for atualizado automaticamente por mudança de geometria, o mesmo
  método e parâmetros são reaplicados (um tc "informado" volta ao padrão Kirpich).

## 14b. Hietogramas (plugin `precipitacao`)

Gera a distribuição da chuva no tempo. **Consome** `idf` (`PREC:Intensidade`):
a chuva total é sempre `H(D) = i(D)·D/60` (mm), qualquer que seja o tipo.
Catálogo `hietograma-tipo`; os tipos incluídos ficam em
`plugins/registry/hietograma_tipos.lsp`.

```lisp
(HIET:Gerar tipo-id tr dur params)
;; -> (("TIPO" . id) ("TR" . anos) ("DUR" . min) ("DT" . min) ("TOTAL" . mm)
;;     ("BLOCOS" . ((t-ini t-fim mm mm/h) ...)) ["NOTA" . texto])   ou (("ERRO" . msg))
(HIET:RegistrarTipo id nome descricao params fn)   ; fn (ctx params) -> (("BLOCOS" . ...))
```

O passo `DT` do usuário é ajustado para dividir a duração em `N` intervalos
iguais (`DUR = N·DT`); sem `DT`, um único bloco.

| id                  | Método                                                                                                                                                                                                                                                                       | Parâmetros                                  |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| `bloco-unico`     | toda a chuva em um bloco de duração D (intensidade constante; é o que o método racional supõe)                                                                                                                                                                           | —                                           |
| `bloco-alternado` | incrementos`P(k·DT) − P((k−1)·DT)`, `P(d) = i(d)·d/60`; o maior na posição do pico (índice `fix(R·N)`) e os demais, em ordem decrescente, alternando direita e esquerda (Chow, Maidment e Mays, 1988)                                                          | `DT`, `R` (0 a 1; padrão 0,5)           |
| `chicago`         | Keifer e Chu (1957): com`H(x) = i(x)·x`, a acumulada antes do pico (tempo `tb` para trás a partir dele) é `r·H(tb/r)/60` e depois (`ta`) é `(1−r)·H(ta/(1−r))/60`; pico em `t = r·D`; blocos pela diferença exata da acumulada, o que preserva `H(D)` | `DT`, `R` (0 a 1 exclusive; padrão 0,4) |

**Validade:** vale só na faixa de durações em que a IDF foi ajustada. A posição
do pico (`R`) é escolha de projeto; confira a literatura antes de adotar.
Valores de teste calculados fora do AutoCAD (IDF K=1000, a=0,15, b=10, c=0,8;
TR=10, D=60, DT=10): total 47,1978 mm; blocos alternados
2,704 / 3,309 / 5,938 / 21,430 / 9,557 / 4,259 mm; Chicago (r=0,4)
3,197 / 7,110 / 21,430 / 8,255 / 4,310 / 2,896 mm.

Ainda **não há comando** nem integração com o cálculo de vazão: o hietograma
é uma API (`HIET:Gerar`). A propagação por hietograma no `hidrograma` é a
próxima etapa.

## 14c. Pasta `plugins/models/`: objetos do sistema

`models/` guarda **só a funcionalidade do objeto** (o que o objeto é e calcula):
registro no desenho, caracterização, cálculo e a declaração do tipo no catálogo
`objeto-hidraulico`. Também traz os **comandos `c:` de linha de comando** e as perguntas deles (seção 9) e um
`ToString` (capacidade `"TOSTRING"`, `OBJ:ToString`), para o objeto funcionar com um único
`.lsp`. Texto no desenho e diálogos DCL ficam fora, em `views/`.

| Arquivo                      | Prefixo  | Conteúdo                                                                                                                                                                                                                                                                                                                | Fora da pasta                                                                                                                                                                                                |
| ---------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `models/bacia.lsp`         | `BAC:` | registro`HYDRO-OBJ`, `BAC:Caracterizar`, tc (`BAC:CalcularTc`), `BAC:ExecutarMetodo`, cálculo e gravação (`BAC:_CalcularEGravar`), `BAC:Obter`, índice `HYDRO.BACIAS`, linhas de texto do cadastro (`BAC:LinhasCadastro`) e a declaração do tipo `bacia` (vazão, área, destino padrão, regra) | `views/bacia_view.lsp`: só etiquetagem (`BAC:_InsereTexto`, `TEXTOBACIA`, `CRIARBACIARESULTADO`). Os comandos `BACIACAD`, `BACIA`, `BACIAS`, `BACIAINFO` e `BAC:ToString` estão no model |
| `models/sarjeta.lsp`       | `SOB:` | seções (`HYDRO.SECOES`), superfície, geometria do desenho, `SOB:LaminaIzzard`, `SOB:Calcular`, `SOB:Resumo`, `SOB:Formata` e a declaração do tipo `sarjeta`                                                                                                                                             | `plugins/sarjetas.lsp`: cálculo direto antigo, comandos e texto no desenho                                                                                                                                |
| `models/objetos_tipos.lsp` | `OTP:` | tipos`trecho`, `estrutura`, `tubo-c3d`                                                                                                                                                                                                                                                                             | —                                                                                                                                                                                                           |

### Seções padrão de um modelo

Todo arquivo de `models/` (exceto `objetos_tipos`, que é só cadastro) segue as mesmas
9 seções, **nesta ordem**, com o cabeçalho `;;; N. NOME` (o `verificar.py` confere):

| # | Seção                             | O que entra                                                                                                                                                |
| - | ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | `UTILITARIOS`                     | `_Try`, `_Erro`, `_Limpa`, `_Val`, `_SetChave`, nomes para exibir. Sem regra de negócio                                                         |
| 2 | `GEOMETRIA (CARACTERIZACAO)`      | leitura do desenho (área, comprimento, desnível...) e`Caracterizar` → `CARACT`                                                                      |
| 3 | `LER, GRAVAR, EDITAR, REMOVER`    | porta de armazenamento:`Ler`, `Gravar`, `Listar`, `Reindexar`, `Cadastrar`/`Obter`, `Remover`. Tipo que herda a classe base só comenta isso |
| 4 | `CAMPOS (CARACT, PARAMS e ATRIB)` | acessos (`Nome`, `Atrib`, `Caract`, `Params`...), padrões de `ATRIB`, contexto de cálculo montado dos campos                                   |
| 5 | `RESULTADOS (RESULT)`             | acessos aos**grupos** de `RESULT` (`Tc`, `Vazao`, `Hidrogramas`...), gravação e substituição de entradas                                 |
| 6 | `CALCULOS`                        | funções que**produzem** os campos de `RESULT` (puras; devolvem alist ou `(("ERRO" . msg))`)                                                    |
| 7 | `RESUMO E FORMATACAO`             | linhas de texto (`Resumo`, `Formata`, `Linhas...`), `ToString`; quem desenha é a view                                                             |
| 8 | `TIPO NO CATALOGO`                | rótulos, assinatura de eventos e`OBJ:RegistrarTipo`                                                                                                     |
| 9 | `COMANDOS E INTERACAO`            | comandos`c:` de linha de comando, seleção e perguntas; `HYDRO:Provide` fecha o arquivo                                                               |

`RESULT` guarda **grupos com nome** (`TC`, `VAZAO`, `HIDRAULICA`, `HIDROGRAMAS`...) e,
dentro de cada grupo, os campos calculados **planos** (`QP`, `PE`, `LAMINA`...).
Não existe grupo genérico `CALCULOS` nem sub-lista `RES`. Entradas de lista (`VAZAO`,
`HIDRAULICA`) se identificam por `METODO` + `TR`.

Como a bacia depende de `objetos` só para se declarar, a declaração do tipo
fica protegida por `(HYDRO:Has "objetos")`; sem o plugin, a bacia funciona
sozinha. Os modelos carregam **depois** de `objetos` e `ligacao` no manifesto.

Um modelo novo = um arquivo novo em `models/` com as funções do objeto e o
`OBJ:RegistrarTipo`; interação e etiquetagem em `views/<nome>_view.lsp`.

## 15. Objetos hidráulicos e ligações

### 15.1 O que é cada coisa

- **Bacia**: continua sendo a bacia como conhecemos (plugin `bacia`); só o
  armazenamento mudou, para o envelope `HYDRO-OBJ` (seção 18).
- **Objeto hidráulico**: qualquer entidade do desenho (polilinha, linha, bloco,
  estrutura ou tubo do Civil 3D...) que tem um **tipo** do catálogo
  `objeto-hidraulico`. A bacia é reconhecida como tipo `bacia` pelo próprio
  cadastro dela (`TIPO` do envelope; `DETECTA` para desenhos antigos), sem
  passar por `OBJETO`. Todos os objetos seguem a mesma interface (seção 18).
- **Ligação**: "a origem descarrega no destino". Qualquer objeto que emite pode
  ligar em qualquer objeto que recebe, respeitando as regras dos tipos.

```
bacia B1 ─┐
bacia B2 ─┴─► sarjeta S1 ─► trecho T1 ─► estrutura E1 ─► tubo P1
bacia B3 ──► bacia B2          (bacias também recebem bacias)
```

A **mesma polilinha** pode ser o talvegue da bacia e a sarjeta: cadastre-a como
`sarjeta` (comando `OBJETO`) e ligue a bacia nela. Em `LIGAR`, **Enter** no
destino usa o destino padrão da origem, que para a bacia é o próprio talvegue.

### 15.2 Onde fica a informação (decisão de projeto)

O **receptor** guarda a lista de **montantes** no `PARAMS` do registro padrão dele (campo
`"MONTANTE"`, seção 18). A origem **não guarda nada**. Motivos:

| Alternativa                           | Problema                                                                                                |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| A origem guarda o destino             | Muitas origens → um destino: ao apagar/copiar o destino, as origens ficam apontando para o nada        |
| Os dois lados guardam                 | Dois valores que podem divergir; é preciso reconciliar                                                 |
| **O receptor guarda (adotado)** | **Uma única fonte de verdade.** O destino de uma origem é *calculado* procurando quem a lista |

Consequências: a bacia fica exatamente como era (princípio aberto/fechado); um
objeto novo pode receber bacias sem que a bacia saiba de nada; apagar o receptor
leva a lista junto. O custo é achar o destino de uma origem: `LIG:Destino`
varre os objetos cadastrados (`OBJ:Listar`); não há índice próprio.

```
PARAMS = (("TALVEGUE" . "2A")                 ; só a bacia: é componente dela, não montante
          ("MONTANTE" . (("30" . T)           ; dicionário  handle-do-montante -> flag
                         ("31"))))            ; ("31") = ("31" . nil)
```

O **flag** diz se o montante **contribui diretamente para o talvegue** do receptor (`T`, compartilha
o talvegue) ou não (`nil` = ausente); ele decide entre somar ou tomar o máximo dos tempos (15.4). `MONTANTE` vale para **qualquer** objeto que recebe (sarjeta recebe bacia
*e* sarjeta; bacia recebe bacia). Cada entrada é um par, então campos novos (ex.:
fração do escoamento) podem virar sub-lista depois. Trocar o tipo do objeto (`OBJETO`)
descarta `PARAMS` e, com ele, os montantes. Recadastrar a bacia (`BACIACAD`) preserva
`MONTANTE` e só troca o `TALVEGUE`.

Os dados vão para o **dicionário de extensão da entidade** e acompanham a
entidade ao copiar, colar e salvar. Se a entidade **não aceitar** dados
(objeto bloqueado ou tipo sem dicionário de extensão, possível em objetos do
Civil 3D), o core grava na **reserva central** (dicionário `HYDRO-CENTRAL`,
chave `<chave>:<handle>`); a leitura procura nos dois lugares
(`HYDRO:DadoLer`, `HYDRO:DadoGravar`, `HYDRO:DadoApagar`).

### 15.3 Regras de integridade

1. **Uma origem tem no máximo um destino.** Ligar de novo a outro destino
   *move* a ligação: o plugin acrescenta no novo receptor e só então remove do
   antigo; se a remoção falhar, o novo é desfeito (não fica nem duplicada nem
   perdida).
2. **Sem auto-ligação e sem ciclos**: o destino não pode estar a montante da origem.
3. **Os tipos precisam permitir**: a origem `EMITE`, o destino `RECEBE` e a
   `REGRA` opcional de cada tipo (cada tipo só fala de si; ex.: "só bacias
   descarregam em bacias").
4. **Remover o cadastro de um objeto** (`objeto.removido`) desfaz as ligações
   dele; o evento sai antes de apagar. O mesmo vale para a **bacia**: ao remover o
   cadastro dela (botão da tabela de bacias), o plugin `bacia` emite
   `bacia.removida` e `models/bacia` a traduz em `objeto.removido`, sem que a
   bacia conheça o mecanismo de ligações.
5. **`VALIDARLIGACOES`** detecta e corrige:

| Problema      | Causa típica                                                 | Correção                  |
| ------------- | ------------------------------------------------------------- | --------------------------- |
| `PENDENTE`  | origem apagada                                                | remove a referência        |
| `SEM-TIPO`  | cadastro removido ou plugin do tipo ausente                   | remove a referência        |
| `DUPLICADA` | origem listada em dois receptores (receptor copiado e colado) | pergunta em qual manter     |
| `CICLO`     | dados corrompidos ou editados à mão                         | só relata; use`DESLIGAR` |

**Limitações conhecidas:** colar objetos **em outro desenho** muda os handles e
quebra as referências (a validação as aponta); cada origem tem um único destino
(sem divisão de vazão); a vazão no receptor é **composta no tempo máximo** (seção 15.4),
sem amortecimento nem propagação de hidrogramas ainda. Os montantes precisam estar
calculados **antes**, de montante para jusante, com o mesmo método e TR; recalcular um
montante deixa o receptor desatualizado até ser recalculado.

### 15.4 O objeto como mecanismo: entrada, saída e tempo máximo

Todo objeto é um **mecanismo de transformação**: recebe dos montantes uma **entrada**
(vazão `Q`, tempo `tc`; hidrograma no futuro) e entrega uma **saída** (vazão, tempo). Bacia sem
montante só tem saída (a própria), usada pelos outros. Sarjeta e estruturas **precisam** de
montante (uma bacia ou outro objeto): a entrada alimenta o dimensionamento/verificação
hidráulica. Gravação, em `RESULT`:

| Grupo       | O que é                                   | Campos                                                             |
|-------------|-------------------------------------------|--------------------------------------------------------------------|
| `ENTRADA`   | o que chegou dos montantes diretos        | `METODO TR QP TC AREA`                                              |
| `VAZAO`     | a **saída** (o que o objeto entrega)      | `METODO TR QP TC` (+ `QP-CALC`, `PRESERVADA`, e os campos do método na bacia) |
| `HIDRAULICA`| o cálculo do tipo (sarjeta)               | `LAMINA`, `VELOCIDADE`, `PERCURSO`, `TC-ENTRADA`...                 |

**Entrada** (`LIG:Entrada`): `Q_entrada` = soma das **saídas gravadas** dos montantes diretos
(`LIG:Saida`); `tc_entrada` = maior tempo de saída entre eles. Os montantes devem ter sido
calculados antes, com o mesmo método e TR (senão `FALTAM` e o cálculo para).

**Tempo de saída** (`LIG:_TcPuro`), `tc_k` = tempo de saída do montante `k`, `tp` = tempo próprio:

```
concentracao (bacia, tp = tc dela):
    tc = max( tp ,  max_k( tc_k + (k contribui ao talvegue ? tp : 0) ) )
percurso (sarjeta/trecho, tp = tempo de escoamento):
    tc = max_k( tc_k ) + tp
```

Montante que **não contribui diretamente** para o talvegue da bacia corre em **paralelo**: vale
o maior tempo (`max`), sem somar. O que **contribui** (flag `T`) percorre o talvegue em **série**:
soma. Na sarjeta, `tp = COMP/VELOCIDADE/60`, calculado com a `Q_entrada` (por isso não há
circularidade).

**Precipitação sempre no maior tempo.** A vazão de saída é recalculada com o tempo de saída
(`LIG:VazaoMontante`): cada bacia a montante (transitivamente) e a própria são **reavaliadas**
com o mesmo `METODO` e `TR` nesse tempo (capacidade `VAZAO-EM`) e as vazões somam (`Q_calc`).
No **racional** é o racional composto, `Q = i(tc)·Σ(C·A)/360`; nos demais métodos o tempo é
propagado do mesmo jeito (cada bacia com os parâmetros gravados dela: `CN`, `DUR`...), uma
aproximação.

**Flag geral `HYDRO.VAZAO.PRESERVA`** (comando `PRESERVAVAZAO`; padrão **ligada**). O tempo maior
reduz a intensidade e pode fazer `Q_calc` ficar **abaixo** da entrada (ex.: bacias que não
contribuem umas para as outras, apenas comunicadas por jusante):

```
flag ligada:     Q_saida = max( Q_entrada , Q_calc )     (PRESERVADA = T quando a entrada vence)
flag desligada:  Q_saida = Q_calc
```

Comparação literal entre a entrada e o total calculado (que inclui a geração própria da bacia).
`Q_calc` fica em `QP-CALC` quando a preservação atuou. Tipos sem cálculo hidráulico (trecho,
estrutura) só repassam: `tp = 0`.

**Premissas a confirmar com casos reais:** a sarjeta repassa a vazão sem amortecimento; o
`VOLUME` de uma bacia com vazão preservada continua sendo o calculado; hidrogramas de uma bacia
composta usam o `QP` de saída mas não foram revistos para a composição; recalcular um montante
deixa o receptor desatualizado até recalcular.

## 16. Como criar um tipo de objeto (aberto/fechado)

Um tipo é um **cadastro** em um arquivo novo; nenhum arquivo existente muda.
Modelo comentado: `docs/template_objeto.lsp`.

```lisp
(OBJ:RegistrarTipo id nome descricao aceita params recebe emite extras)
```

| Argumento              | Significado                                                                                                                                                          |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `aceita`             | nomes DXF das entidades que podem ser deste tipo (`"LWPOLYLINE"`, `"AECC_PIPE"`...)                                                                              |
| `params`             | **descrição dos campos de `ATRIB`** (mesmo formato dos demais catálogos); viram as perguntas de `OBJETO`. No catálogo ficam sob a chave `ATRIB-DEFS` |
| `recebe` / `emite` | pode receber afluentes / descarregar em outros                                                                                                                       |
| `extras`             | alist de**capacidades opcionais**                                                                                                                              |

Capacidades opcionais (todas opcionais; o que o tipo não declara, ninguém assume):

| Chave                   | Assinatura                                                                                  | Para quê                                                                                         |
| ----------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `CADASTRAVEL`         | `nil`                                                                                     | não aparece em`OBJETO` (ex.: bacia)                                                            |
| `DETECTA`             | `(fn en)` → T                                                                            | reconhece a entidade sem cadastro de objeto                                                       |
| `ARMAZENAMENTO`       | alist`(("LER" . fn) ("GRAVAR" . fn) ("LISTAR" . fn) ("REINDEXAR" . fn) ("REMOVER" . fn))` | o tipo tem armazenamento próprio (adapter);**exige** as 5 operações (seção 18)         |
| `CARACTERIZA`         | `(fn en)` → alist                                                                        | obtém do desenho o que vai em`CARACT` ao cadastrar (ex.: comprimento e declividade da sarjeta) |
| `NOME-FN`, `RESUMO` | `(fn en)`                                                                                 | nome e linhas de texto nas tabelas                                                                |
| `PADROES`             | `(fn en)` → alist                                                                        | padrões dos parâmetros ao cadastrar                                                             |
| `REGRA`               | `(fn tipo-origem tipo-destino)`                                                           | `nil`/`T` = permitido; **string** = motivo da recusa                                    |
| `VAZAO-EM`            | `(fn en metodo tr tc)` → alist do método (`QP`, `VOLUME`) ou nil                         | o objeto**gera** vazão: reavaliada**só dele** no tc dado (a bacia refaz o método com os parâmetros gravados) |
| `TEMPO-MODO`          | `"concentracao"` \| `"percurso"` (padrão)                                                  | como o tempo de saída combina os montantes (seção 15.4)                                           |
| `AREA-PROPRIA`        | `(fn en)` → m²                                                                          | área contribuinte                                                                                |
| `DESTINO-PADRAO`      | `(fn en)` → ename                                                                        | destino sugerido em`LIGAR`                                                                      |
| `EDITAR`              | `(fn en)`                                                                                 | edição própria                                                                                 |
| `PARAMS-CALCULO`      | lista de parâmetros                                                                        | perguntas extras do cálculo                                                                      |
| `CALCULA`             | `(fn en ctx params)` → alist                                                             | habilita`CALCULAOBJETO` para o tipo                                                             |
| `FORMATA`             | `(fn res)` → linhas                                                                      | texto do resultado                                                                                |

Contrato de `CALCULA`: `ctx` = `(("TR" . anos) ("METODO" . id) ("VAZAO" . alist))`,
onde `VAZAO` é a **entrada** de `LIG:Entrada` (`"QP"` soma das saídas dos montantes, `"TC"` maior tempo de saída,
`"CHEGADAS"`, `"ORIGENS"`, `"FALTAM"`, `"AREA"`). `CALCULA` devolve também `"PERCURSO"` (min) se o tipo conduz. `CALCULAOBJETO`
grava `"ENTRADA"` (o que chegou), `"VAZAO"` (a **saída**: `QP`, `TC`, após a flag de preservação) e `"HIDRAULICA"`; tipos
sem `CALCULA` só repassam. O resultado é gravado no objeto, em `RESULT`, em grupos (ver 15.4)
e `"HIDRAULICA"` (o que o tipo calcula, campos planos: `LAMINA`, `VELOCIDADE`...),
ambos por `OBJ:GravarResultado en grupo entrada`.

**Por que isso é "aberto para extensão, fechado para modificação":** `LIGAR`,
`OBJETO`, `CALCULAOBJETO`, `VALIDARLIGACOES` e `LIGACOES` só conhecem o
*catálogo*, nunca um tipo específico. Um tipo novo traz suas próprias regras e
cálculo e aparece em todas as ferramentas.

### Tipos incluídos

| Tipo          | Aceita                                 | Dados                                                                               | Observação                                                                                           |
| ------------- | -------------------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `bacia`     | polilinhas (reconhecida pelo cadastro) | —                                                                                  | emite e recebe; gera vazão e área; só bacias descarregam em bacias; destino padrão = talvegue      |
| `sarjeta`   | LINE, LWPOLYLINE, POLYLINE, SPLINE     | `ATRIB`: `SECAO` (id), `N` (0 = a da seção). `CARACT`: `COMP`, `DECL` | recebe e emite;`CALCULAOBJETO` aplica Izzard com a vazão afluente e a declividade da própria linha |
| `trecho`    | LINE, LWPOLYLINE, POLYLINE, SPLINE     | `DIAM`, `N`                                                                     | trecho de rede                                                                                         |
| `estrutura` | AECC_STRUCTURE, INSERT, CIRCLE, POINT  | `FUNCAO`                                                                          | poço de visita, boca de lobo, caixa, ponto de descarga                                                |
| `tubo-c3d`  | AECC_PIPE                              | `N`                                                                               | tubo do Civil 3D                                                                                       |

Os nomes DXF dos objetos do Civil 3D (`AECC_PIPE`, `AECC_STRUCTURE`) devem ser
**conferidos no seu desenho**: `(cdr (assoc 0 (entget (car (entsel)))))`.

## 17. Fluxo típico

```
BACIACAD                 (cadastra a bacia: nome, tc, C, CN)
BACIA                    (calcula a vazão: método e TR)
OBJETO                   (seleciona o talvegue → tipo "sarjeta": seção e rugosidade)
LIGAR                    (origem = a bacia; Enter no destino = o talvegue)
CALCULAOBJETO            (entrada -> saida: Q composta no tempo maximo, flag de preservacao)
LIGACOES                 (tabela: destino, afluentes, árvore a montante)
```

Os comandos `CALCULASARJETA` e derivados continuam funcionando como antes
(contorno + talvegue + seção atual); o tipo `sarjeta` é um **caminho novo**, que
parte das ligações.

## 18. Interface padrão do objeto (portas e adapters)

Todo objeto que existe no desenho (bacia, sarjeta, trecho, estrutura, tubo e
os que ainda vamos criar) guarda **o mesmo registro**, e o resto do sistema só
conhece esse registro. É a ideia de *portas e adapters*: o registro padrão e as
cinco operações de armazenamento são a **porta**; o tipo usa a implementação
padrão (classe base) ou fornece a dele quando precisa de algo próprio (índice,
evento ao remover). Nenhum tipo guarda uma estrutura diferente do registro.

### 18.1 O registro (envelope `HYDRO-OBJ`)

```
(("VERSAO"    . 2)
 ("TIPO"      . "sarjeta")              ; id do tipo no catálogo
 ("NOME"      . "S1")
 ("DESCRICAO" . "texto livre")
 ("PARAMS"    . (("TALVEGUE" . "2A")     ; só a bacia
                   ("MONTANTE" . (("30" . T) ("31")))))  ; dicionário handle -> flag (seção 15.2)
 ("ATRIB"     . (("SECAO" . 1) ("N" . 0.0)))
 ("CARACT"    . (("COMP" . 85.0) ("DECL" . 0.012)))
 ("RESULT"    . (("VAZAO" . ((("METODO" . "racional") ("TR" . 10.0) ("QP" . 0.42))))
                  ("HIDRAULICA" . ((("METODO" . "racional") ("TR" . 10.0)
                                    ("LAMINA" . 0.09))))
                  ("HIDROGRAMAS" . (...)) ("TC" . (...)) ...)))
```

Todo objeto tem `VERSAO`, `TIPO`, `NOME`, `DESCRICAO`, `ATRIB`, `CARACT` e `RESULT`.
Valores `nil` não são gravados, então um campo vazio simplesmente não aparece.

| Campo      | O que guarda                                                                                                                                                                                                                                                                                                               | Regra para decidir                                                                                              |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `TIPO`   | **que objeto é este**: id do tipo no catálogo `objeto-hidraulico` (`"bacia"`, `"sarjeta"`...)                                                                                                                                                                                                                | Obrigatório. É por ele que`OBJ:TipoDe` escolhe o tipo e o sistema despacha regras, cálculo e armazenamento |
| `PARAMS` | **ligações com outros objetos**, necessárias para calcular ou extrair informação: `"TALVEGUE"` (só a bacia; componente dela) e `"MONTANTE"` (qualquer objeto que receba; dicionário handle → flag "contribui diretamente ao talvegue")                                                                                                                                                                                                 | Evitar. Só entra quando o objeto de fato depende de outro. É opcional: sem ligação, não existe             |
| `ATRIB`  | valores que**precisam ser definidos** pelo usuário e **não podem ser obtidos do desenho** (C, CN, seção, rugosidade)                                                                                                                                                                                       | Se o desenho não sabe responder, é`ATRIB`                                                                   |
| `CARACT` | o que**pode ser obtido do objeto no desenho** (área, comprimento, desnível, declividade)                                                                                                                                                                                                                           | Mesmo que o usuário possa informar o valor, ele continua em`CARACT`                                          |
| `RESULT` | **tudo que é calculado**: em **grupos com nome**: vazões (`"VAZAO"`), tempo de concentração (`"TC"`), hidrogramas (`"HIDROGRAMAS"`) e, na sarjeta, `"HIDRAULICA"` (lâmina, velocidade...). Os campos calculados ficam **planos** na entrada do grupo; não há lista genérica de cálculos | Se saiu de uma conta, é`RESULT`. Hidrogramas também ficam aqui                                              |

Efeito buscado: **a forma de acessar resultados é igual para todos os objetos**
(`OBJ:ResultDe`, `OBJ:GrupoDe`), seja bacia, sarjeta ou o que vier.
Uma entrada de grupo é `(("METODO" . id) ("TR" . anos) ("QP" . m3/s) ...)` com os
campos calculados direto nela; uma nova com o mesmo `METODO` e `TR` substitui a anterior.

Não confunda `TIPO` com a chave `"HYDRO-OBJ"`: a chave é o **endereço** do registro
na entidade (existir nela = "é um objeto do Hydro"); `TIPO` é um campo **dentro**
do registro ("que objeto é").

Não confunda também: o `PARAMS` do **registro** (ligações) não é o `"PARAMS"` **de um
cálculo** (parâmetros do método) nem o argumento `params` de `OBJ:RegistrarTipo`
(que descreve os campos de `ATRIB`).

### 18.2 Leitura genérica (vale para qualquer tipo)

| Função                                                    | Devolve                                                                            |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `OBJ:Registro en`                                         | registro completo, no formato padrão                                              |
| `OBJ:NomeGravado`, `OBJ:DescricaoDe`                    | `NOME`, `DESCRICAO`                                                            |
| `OBJ:ParamsDe`, `OBJ:AtribDe`, `OBJ:CaractDe`         | `PARAMS`, `ATRIB`, `CARACT`                                                  |
| `OBJ:ResultDe`, `OBJ:GrupoDe en grupo`, `OBJ:VazaoDe` | `RESULT`, um grupo de `RESULT`, o grupo `"VAZAO"`                            |
| `OBJ:Nome en`                                             | nome para exibir (o gravado ou o`NOME-FN` do tipo)                               |
| `OBJ:GravarResultado en grupo entrada`                    | acrescenta/substitui uma entrada (mesmo`METODO` e `TR`) no grupo de `RESULT` |

Como o formato é fixo, **não há** uma função de leitura por tipo para esses
campos: não existe "Atrib da bacia" versus "Atrib da sarjeta" para o resto do
sistema.

### 18.3 A porta de armazenamento

Cinco operações, que o tipo **herda** da classe base (`objetos.lsp`, que grava o
envelope e indexa em `HYDRO.OBJETOS`) ou **substitui** declarando
`("ARMAZENAMENTO" . alist)` no catálogo:

| Operação    | Assinatura                                                  | Padrão (classe base)                                      |
| ------------- | ----------------------------------------------------------- | ---------------------------------------------------------- |
| `LER`       | `(fn en)` → registro **no formato padrão** ou nil | `OBJ:Ler`                                                |
| `GRAVAR`    | `(fn en reg)` → reg ou nil                               | grava o envelope e indexa                                  |
| `LISTAR`    | `(fn)` → enames                                          | objetos do índice com este`TIPO`                        |
| `REINDEXAR` | `(fn)` → quantidade                                      | `OBJ:Reindexar` (varre o desenho)                        |
| `REMOVER`   | `(fn en)` → T                                            | emite`objeto.removido` **antes**, apaga, desindexa |

Uso, sem saber o tipo: `OBJ:GravaRegistro id en reg`, `OBJ:ListaTipo id`,
`OBJ:ReindexaTipo id`, `OBJ:Remover en`.

- **Regra:** se o tipo declara `ARMAZENAMENTO`, precisa fornecer **as cinco**.
  `OBJ:RegistrarTipo` recusa o tipo incompleto, registra no log quais faltam e
  devolve `nil`.
- O `LER` do tipo devolve **o registro padrão**. É assim que `OBJ:AtribDe` e os
  demais funcionam sem conhecer o tipo.
- Capacidade opcional `CARACTERIZA` `(fn en)` → alist: ao cadastrar, o tipo diz
  como obter do desenho o que vai em `CARACT`.

### 18.4 Aplicação nos tipos existentes

| Tipo          | Armazenamento                                                                                                                                    | `PARAMS`   | `ATRIB`        | `CARACT`                                 | `RESULT`                                                                                                                                                    |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------ | ---------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bacia`     | próprio (`BAC:Ler`, `BAC:Gravar`, `BAC:Listar`, `BAC:Reindexar`, `BAC:Remover`): índice `HYDRO.BACIAS` e evento `bacia.removida` | `TALVEGUE` | `C`, `CN`    | `AREA`, `COMP`, `DESNIVEL`, `DECL` | `TC` (`MIN`, `ORIGEM`, `PARAMS`), `VAZAO`, `HIDROGRAMAS`, `SARJETAS`                                                                            |
| `sarjeta`   | padrão                                                                                                                                          | —           | `SECAO`, `N` | `COMP`, `DECL` (via `CARACTERIZA`)   | `VAZAO` (vazão afluente) e `HIDRAULICA` (lâmina, largura, velocidade, área molhada, avisos). Hidrogramas da sarjeta: previsto, ainda não implementado |
| `trecho`    | padrão                                                                                                                                          | —           | `DIAM`, `N`  | —                                         | `VAZAO`, `HIDRAULICA`                                                                                                                                     |
| `estrutura` | padrão                                                                                                                                          | —           | `FUNCAO`       | —                                         | `VAZAO`, `HIDRAULICA`                                                                                                                                     |
| `tubo-c3d`  | padrão                                                                                                                                          | —           | `N`            | —                                         | `VAZAO`, `HIDRAULICA`                                                                                                                                     |

### 18.5 Regras para um tipo novo

1. Tipos simples **não declaram nada**: descrevem os campos de `ATRIB` (argumento
   `params`) e herdam a porta de armazenamento.
2. Valores que o desenho sabe responder vão em `CARACT` (declare `CARACTERIZA`);
   o que o usuário precisa informar vai em `ATRIB`; o que é calculado vai em
   `RESULT` (use `OBJ:GravarResultado`).
3. Só use `PARAMS` se o objeto depende de **outro objeto** para calcular.
4. Só declare `ARMAZENAMENTO` se o tipo precisar de gravação, índice ou remoção
   próprios (como a bacia). Neste caso forneça as cinco operações; o registro
   continua sendo o padrão.
5. Uma entidade tem **um** registro `HYDRO-OBJ`, logo **um** tipo. Uma polilinha
   que já é bacia não pode ser também trecho.

### 18.6 Compatibilidade

**Não há compatibilidade com formatos anteriores.** O registro descrito aqui é
o único lido: não existem leitura da chave `HYDRO-BACIA` nem do envelope com
`DADOS`/`RESULTADOS`. Nada foi gravado em desenho pelo AutoCAD até aqui; se
houver desenhos antigos, será preciso um conversor separado.

## 18b. Comandos padrão do objeto, vínculos e auditoria

### Comandos que todo modelo tem

Cada arquivo de `plugins/models/` (exceto `objetos_tipos.lsp`, que reúne tipos básicos e usa os
comandos genéricos abaixo) define **quatro comandos de linha de comando**, com o nome do arquivo em
maiúsculas como prefixo (`verificar.py` confere):

| Comando        | Faz                                                                                          | Fluxo genérico |
|----------------|----------------------------------------------------------------------------------------------|----------------|
| `<TIPO>CAD`    | cadastra **ou edita** (se a entidade já é do tipo, abre a edição dele)                       | `OPV:Cadastrar tipo` |
| `<TIPO>S`      | lista os cadastrados (nome, tipo, handle, afluentes, destino)                                | `OPV:Listar tipo` |
| `<TIPO>INFO`   | mostra as informações de um objeto (`ToString`)                                              | `OPV:Info tipo` |
| `<TIPO>ZOOM`   | procura por nome (ou parte) ou handle, dá zoom e seleciona; Enter lista tudo para escolher   | `OPV:Zoom tipo` |

`BACIACAD/BACIAS/BACIAINFO/BACIAZOOM` e `SARJETACAD/SARJETAS/SARJETAINFO/SARJETAZOOM` seguem o padrão.
O modelo só diz de que tipo é (`(OPV:Zoom "sarjeta")`); os fluxos estão em
`views/objetos_padrao_view.lsp` (feature `objetos-padrao-view`) sobre as consultas puras de
`plugins/objetos_padrao.lsp` (feature `objetos-padrao`, prefixo `OPD:`). `OBJ:CadastroInterativoTipo`
é o cadastro com **tipo fixo** (não pergunta o tipo).

Comandos **gerais**, válidos para qualquer tipo: `OBJETO` (cadastra/edita), `OBJETOS` (lista um tipo ou
todos), `OBJETOINFO`, `OBJETOZOOM` (localiza qualquer objeto), `OBJETOREMOVER`, `OBJETOVINCULOS`.

### Vínculos (`PARAMS`) e `OBJETOVINCULOS`

`PARAMS` guarda ligações com **outras entidades** como `(chave . handle)` (ex.: `("TALVEGUE" . "2F")`);
todo valor string de `PARAMS` é tratado como handle, e cada handle de `"MONTANTE"` também. `OBJETOVINCULOS` **realça e seleciona** as entidades
citadas: sem seleção, todas as que algum objeto cita (os talvegues das bacias); com um objeto, ele, o que
ele cita e quem o cita. Vínculos cujo alvo não existe são listados como `QUEBRADO` (corrija com `HYDROAUDIT`).
Funções: `OPD:Referencias`, `OPD:Alvo`, `OPD:Vinculos`, `OPD:Referenciando`.

### Auditoria (`HYDROAUDIT`)

Como o `AUDIT` do AutoCAD: **localiza** os problemas, **pergunta** se deve corrigir, **corrige** e confere
de novo (o que restar exige decisão do usuário). As verificações vêm do catálogo `auditoria`
(`plugins/auditoria.lsp`, comando em `views/auditoria_view.lsp`). Cada plugin cadastra as suas, sem
alterar o comando (aberto/fechado):

```lisp
(HYDRO:RegAdd "auditoria" "meu-id"
  (list (cons "NOME"     "Nome para exibir")
        (cons "VERIFICA" 'XXX:Verifica)   ; ()          -> lista de problemas
        (cons "TEXTO"    'XXX:Texto)      ; (problema)  -> string
        (cons "REPARA"   'XXX:Repara)))   ; (problemas) -> quantos corrigiu (opcional; pode perguntar)
```

Um problema é uma lista cujo primeiro elemento é o tipo (`("PENDENTE" receptor origem)`). Verificação
que dá erro não derruba as outras: vira `("ERRO-VERIFICACAO" mensagem)`.

| Id              | Arquivo                  | Detecta                                                              | Correção |
|-----------------|--------------------------|----------------------------------------------------------------------|----------|
| `indice`        | `objetos_padrao.lsp`     | handles de `HYDRO.OBJETOS` inexistentes; objetos do desenho fora do índice | `OBJ:Reindexar` |
| `params`        | `objetos_padrao.lsp`     | vínculo de `PARAMS` (exceto `MONTANTE`) para entidade apagada/inexistente | escolher outra entidade ou `[Remover]` o vínculo (Enter deixa como está) |
| `tipo-ausente`  | `objetos_padrao.lsp`     | cadastro de um tipo que não está carregado                           | nenhuma (só informa; não apaga dados) |
| `ligacoes`      | `ligacao.lsp`            | afluente apagado/sem tipo, origem em vários receptores, ciclo        | `LIG:Reparar` (ciclo: manual) |
| `secao-atual`   | `secao.lsp`              | `HYDRO.SECAO.ATUAL` fora do cadastro                                 | usa a primeira seção |
| `secao-sarjeta` | `models/sarjeta.lsp`     | sarjeta com `SECAO` inexistente                                      | escolhe uma seção para todas |
| `superficie`    | `auditoria.lsp`          | `HYDRO.SURFACE.HANDLE` aponta para entidade apagada                  | limpa o handle |

`VALIDARLIGACOES` continua existindo (só ligações). Corrigir um vínculo ou uma seção **não recalcula**
nada: rode `CALCULAOBJETO` / `BACIA` depois.

## 19. Painel, menu e barras de ferramentas (views)

`HYDRO` abre um diálogo com os comandos agrupados (detalhes, tabela de botões e como montar a
ribbon em `docs/painel_e_ribbon.md`). Tudo vem de **um catálogo**, `acao-painel`; painel, menu e
barras são **views** (`views/painel.lsp`, `menu.lsp`, `toolbar.lsp`) e os botões dos comandos
existentes estão em `views/painel_acoes.lsp`. Models e plugins **não conhecem** o painel: cada
objeto continua funcionando com um único `.lsp`, e o botão dele é cadastrado na camada de interface.

- O DCL do painel é **gerado** a cada abertura (arquivo temporário): comando novo = botão novo sem
  editar o painel, com `(PNL:Acao id grupo ordem-grupo ordem rotulo comando requer)`. `requer` é a
  feature que define o comando (model, view ou plugin: `"bacia"`, `"bacia-view"`, `"idf-view"`...).
- O diálogo é **modal**: fecha ao clicar, executa o comando (`c:XXX`) e, com "Manter o painel
  aberto" marcado, reabre ao fim. Botão fica **desabilitado** se `c:XXX` não existe ou se uma
  funcionalidade exigida não está carregada.
- **Menu** "Hydro" (ActiveX `AcadMenuGroup`/`AcadPopupMenu`) e **barras** "Hydro - <grupo>"
  (`AcadToolbars`) são criados quando o core emite `hydro.carregado`, por isso a ordem do manifesto
  não importa para os botões. Nada é salvo na personalização.
- **Ícones** em `resources/icons/` (16x16 e 24x24), procurados por `HYDRO:FindFile`:
  `<id>_16/24` (o `.` do id vira `_`) → `_grupo_<ordem>_16/24` → `_padrao_16/24`. Gerados por
  `python build/gerar_icones.py --so-faltantes`.
- **Regra do projeto:** todo comando novo ganha um botão (`python build/verificar.py` avisa quando falta).
- Os comandos do fluxo antigo de sarjetas (`CALCULASARJETA`, `ATUALIZARUNOFF`...) não têm
  botão aqui porque `plugins/sarjetas.lsp` não está nesta árvore.
