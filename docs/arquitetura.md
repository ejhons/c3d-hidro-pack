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
  metodos_chuva_vazao MET:   métodos chuva-vazão (racional, SCS-CN, vazão informada)
  tempo_conc      TCM:   métodos de tempo de concentração (Kirpich, Ventura, Pasini...)
  hidrograma_tipos HID:  tipos de hidrograma (triangular, adimensional, trapezoidal, usuário)
  hietograma_tipos HIET: tipos de hietograma (bloco único, blocos alternados, Chicago)
bacia_view  BAC:     (views/) perguntas, comandos e etiquetagem da bacia (BACIACAD, BACIA, TEXTOBACIA...)
bacia_tabela BTB:    (views/) tabela das bacias do desenho (detalhes, ações, CSV)
objetos     OBJ:     objetos hidráulicos genéricos: catálogo de TIPOS e cadastro em qualquer entidade
ligacao     LIG:     ligações de descarga entre objetos (a origem guarda o destino em `PARAMS`; os montantes são derivados), tc acumulado e integridade
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
`sarjetas`, `secao`, `metodos-chuva-vazao`, `tempo-conc`, `hidrograma-tipos`, `hietograma-tipos`,
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
| `objeto.cadastrado` | `objetos` (`OBJ:Salvar`; também a bacia, via `BAC:Cadastrar`) | `etiqueta` (atualiza), `relacao` (se `TIPO` = `bacia`, relaciona contorno↔talvegue, XData `DREN-BACIA`) | `"OBJETO"` (ename), `"TIPO"` |
| `hydro.carregado`   | `core` (fim de `HYDRO:LoadAll`; e `hydro.lsp` no modo VLX) | `menu` (cria o menu), `toolbar` (cria as barras) | nenhum. Indica que **todos** os plugins já cadastraram catálogos, ações e rótulos |
| `objeto.removido`   | `objetos` (`OBJ:Remover`, para todos os tipos) | `ligacao` (desfaz as ligações do objeto)                                  | `"OBJETO"`. Emitido **antes** de apagar o cadastro                                                                                                                                                                                                                                                        |
| `ligacao.criada`    | `ligacao`                                    | — (ponto de conexão futuro)                                                 | `"ORIGEM"`, `"DESTINO"` (enames), `"ANTERIOR"` (ename ou nil: destino de onde foi movida)                                                                                                                                                                                                                   |
| `ligacao.removida`  | `ligacao`                                    | —                                                                            | `"ORIGEM"`, `"DESTINO"`                                                                                                                                                                                                                                                                                       |
| `objeto.calculado`  | `ligacao` (CALCULAOBJETO)                    | —                                                                            | `"OBJETO"`, `"TIPO"`, `"METODO"`, `"TR"`, `"RES"`                                                                                                                                                                                                                                                       |
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
| `HYDRO.CALC.AUTO`                                         | inteiro          | `ligacao`           | 1 = modo automático dos cálculos, sem perguntas (comando `CALCAUTO`; padrão 0)                |
| `HYDRO.PADRAO.*`                                          | qualquer         | `padroes-view`      | Padrões do projeto por parâmetro (`HYDRO.PADRAO.MET.racional.C`...); definidos por `PADROES`     |
| `HYDRO.SECAO.ATUAL`                                       | inteiro          | `sarjetas`          | Id da seção em uso (o plugin`secao` também a altera ao "Selecionar")                    |
| `HYDRO.SECAO.EXAG`                                        | inteiro          | `secao`             | Exagero vertical da visualização (1, 2, 5 ou 10)                                           |
| `HYDRO.SECAO.COMUM`                                       | inteiro          | `secao`             | 1 = escala comum a todas as seções                                                         |
| `HYDRO.ULTIMO.Q`                                          | real             | `secao`             | Vazão (m³/s) do último cálculo de sarjeta                                                |
| `HYDRO.ULTIMO.DECL`                                       | real             | `secao`             | Declividade longitudinal (m/m) do último cálculo                                           |
| `HYDRO.ULTIMO.SECAO`                                      | inteiro          | `secao`             | Id da seção usada no último cálculo                                                      |
| `HYDRO.TC.MINIMO`, `HYDRO.TR`, `HYDRO.SURFACE.HANDLE` | real/real/string | `sarjetas`, `idf` | **Compartilhadas** também pelo plugin `bacia`                                       |
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
| `HYDRO.MET.<id>.<param>`                                  | variado          | `metodos-chuva-vazao` | Último valor usado em cada parâmetro de cada método (ex.:`HYDRO.MET.scs-cn.CN`)         |
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
| `SARJETACAD`, `SARJETAS`, `SARJETAINFO`, `SARJETAZOOM`, `SARJETAEDITA`, `BACIAZOOM` | sarjeta, bacia | Comandos padrão do objeto (seção 18b); `<TIPO>EDITA` altera um campo |
| `CARACTAUTO` | objetos | Flag `HYDRO.CARACT.AUTO` (padrão 1): reler o desenho (`CARACTERIZA`) antes de calcular (seção 18d) |
| `ESTRUTURACAD`, `ESTRUTURAEDITA`, `ESTRUTURAS`, `ESTRUTURAINFO`, `ESTRUTURAZOOM` | estrutura | Comandos padrão da estrutura (seção 18g) |
| `CRIATIPOESTRUTURA`, `EDITATIPOESTRUTURA`, `REMOVETIPOESTRUTURA`, `TIPOESTRUTURA` | tipo-estrutura-view | Catálogo de tipos de estrutura |
| `ESCADACAD`, `ESCADAEDITA`, `ESCADAS`, `ESCADAINFO`, `ESCADAZOOM` | escada | Comandos padrão da escada hidráulica (seção 18h) |
| `TUBOCAD`, `TUBOEDITA`, `TUBOS`, `TUBOINFO`, `TUBOZOOM` | tubo | Comandos padrão do tubo/canal (seção 18f) |
| `CRIASECAOTUBO`, `EDITASECAOTUBO`, `REMOVESECAOTUBO`, `SECAOTUBO` | secao-tubo-view | Catálogo de seções de tubo/canal (circular, retangular, trapezoidal) |
| `LIGACOESVER` | ligacao-visual-view | Mostra na tela, **temporariamente** (`GRVECS`; some com REDRAW/REGEN), uma linha tracejada fraca com seta: **sai do fim** e **entra no início** da curva (talvegue da bacia, sarjeta, tubo); contorno fechado sem talvegue: do centro ao centro; também aparece após o `LIGAR` |
| `PROPAGAOBSOLETO` | objetos | Flag `HYDRO.OBSOLETO.PROPAGA` (padrão 1): editar marca o jusante como desatualizado (seção 18d) |
| `HYDROAUDIT` | auditoria-view | Audita o desenho, pergunta e corrige (seção 18b) |
| `LIGAR`                                                                                     | ligacao        | Origens (várias) → destino. Enter no destino usa o destino padrão da origem (a bacia sugere o próprio talvegue)               |
| `DESLIGAR`                                                                                  | ligacao        | Tira a(s) origem(ns) do destino atual                                                                                             |
| `ATUALIZASUPERFICIE` | superficie | Define a superfície TIN (cotas de bacia e sarjeta); Enter sem selecionar limpa |
| `ETIQUETA`, `ETIQUETAEDITA`, `TABELAVIVA`, `ATUALIZAETIQUETAS` | etiqueta-view | Etiquetas dinâmicas (relatório ou modelo) e tabela viva de objetos (seção 18c) |
| `PADROES`                                                                                   | padroes-view   | Define os padrões do projeto (TR, tc mínimo, método, C, CN, n de Manning...) (15.5)                                         |
| `CALCAUTO`                                                                                  | ligacao        | Liga/desliga o modo automático dos cálculos, sem perguntas (15.5)                                                           |
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
| `metodo-chuva-vazao` | `registry/metodos_chuva_vazao` (e qualquer plugin seu)          | `bacia`        |
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
intermediária). O armazenamento é **herdado** da classe base (`objetos.lsp`), igual ao
da sarjeta: `BAC:Ler` é a leitura tipada (`OBJ:RegistroDe en "bacia"`); grava-se com
`OBJ:GravaRegistro "bacia" en reg`; o cadastro é o **genérico** (`OBJ:CadastrarCom`, que termina em
`OBJ:Salvar` e emite `objeto.cadastrado`): talvegue em `PARAMS-DEFS` (opcional), `AREA/COMP/DECL` em
`CARACT-DEFS`, e o método do tc em `ATRIB` (`TC-METODO`, `TC-USUARIO`). **Cadastrar não calcula o tc**: ele
nasce em `BAC:Preparar` (no cálculo; relê o desenho, aplica `BAC:TcDe` e grava `RESULT/TC`).

```
(("VERSAO" . 2) ("TIPO" . "bacia") ("NOME" . "B1") ("DESCRICAO" . "texto")
 ("SPARAMS" . (("TALVEGUE" . "handle")))
 ("ATRIB"  . (("C" . 0.6) ("CN" . 80.0) ("TC-METODO" . "kirpich") ("TC-USUARIO" . 0.0)))
 ("CARACT" . (("AREA" . m2) ("COMP" . m) ("DESNIVEL" . m) ("DECL" . m/m) ["MANUAL" . chaves]))
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
Outras funções: `BAC:Caracterizar`, `BAC:ExecutarMetodo`,
`BAC:Contexto`, `BAC:TcDe`, `BAC:Preparar`. Chaves **não** guardam valores `nil`; use `T` ou
omita o par.

`BAC:Preparar` devolve um **contexto de cálculo**
(`BAC:_Ctx`): características + `"TC"`, `"TC-ORIGEM"`, `"NOME"` e atributos
(C, CN). Ele **não** é o que fica gravado, só a entrada dos métodos.

**Preparação para conectar** (ainda não conectado): o plugin de sarjetas tem
sua própria cópia da geometria (área, comprimento, Kirpich). Quando as
informações forem conectadas, `SARJ:` passa a usar `OBJ:CaractDe`/`BAC:Preparar`, e a
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
apenas lê o cadastro (`OBJ:CaractDe`/`BAC:Ler`) quando `bacia` está carregado (sem ele,
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
| `sarjetas`                  | (legado, arquivo ausente) usava `BAC:Obter`, que **não existe mais**: a bacia deve estar cadastrada (`BACIACAD`) e o tc nasce em `BAC:Preparar` |
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

**Índice:** o da classe base, `HYDRO.OBJETOS` (só handles), para listar sem varrer o
desenho (`OBJ:ListaTipo "bacia"`). `BACIATABELA` reconstrói o índice sozinho se estiver
vazio (por exemplo, ao colar bacias de outro desenho) e há o botão **Reindexar**.

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
| `models/bacia.lsp`         | `BAC:` | registro`HYDRO-OBJ`, `BAC:Caracterizar`, tc (`BAC:CalcularTc`), `BAC:ExecutarMetodo`, cálculo e gravação (`BAC:_CalcularEGravar`), `BAC:Obter`, índice da classe base (`HYDRO.OBJETOS`), linhas de texto do cadastro (`BAC:LinhasCadastro`) e a declaração do tipo `bacia` (vazão, área, destino padrão, regra) | `views/bacia_view.lsp`: só etiquetagem (`BAC:_InsereTexto`, `TEXTOBACIA`, `CRIARBACIARESULTADO`). Os comandos `BACIACAD`, `BACIA`, `BACIAS`, `BACIAINFO` e `BAC:ToString` estão no model |
| `models/escada.lsp`        | `ESC:` | escada hidráulica (objeto linear): geometria dos degraus, altura crítica, hook `metodo-escada` | — |
| `plugins/tipo_estrutura.lsp` | `TES:` | **catálogo** de tipos de estrutura (`HYDRO.TIPOS.ESTRUTURA`: criar, editar, remover, em uso, tipo atual) e **registro de classes** (`classe-estrutura`) | `views/tipo_estrutura_view.lsp`: `CRIATIPOESTRUTURA`, `EDITATIPOESTRUTURA`, `REMOVETIPOESTRUTURA`, `TIPOESTRUTURA` |
| `plugins/registry/estrutura_passagem.lsp`, `estrutura_boca_lobo.lsp`, `estrutura_dissipador.lsp`, `captacao.lsp`, `dissipacao.lsp`, `dissipacao_usbr.lsp`, `dissipacao_enrocamento.lsp`, `escada_siscooh.lsp` | `ESP:`, `EBL:`, `EDI:`, `CAP:`, `DIS:`, `DUS:`, `DEN:`, `ESS:` | uma **classe** de estrutura por arquivo (passagem: perda de carga; boca de lobo: captação; dissipador: balanço de energia) e os catálogos `metodo-captacao` e `metodo-dissipacao` | — |
| `models/estrutura.lsp`     | `EST:` | só o **objeto** estrutura: despacha para a classe do tipo (`CALCULA`, `FORMATA`), dados dos montantes, resumo, auditoria `tipo-estrutura` | — |
| `plugins/secao_tubo.lsp`   | `STB:` | **gerenciamento** do catálogo de seções de tubo/canal (`HYDRO.SECOES.TUBO`): criar, editar, remover, em uso, hidráulica (adaptador), último cálculo, auditoria `secao-tubo-atual` | `views/secao_tubo_view.lsp` (visualizador e comandos) |
| `models/tubo.lsp`          | `TUB:` | tubo/canal circular, retangular ou trapezoidal: leitura do catálogo (`TUB:Secoes`), `TUB:Resolver` (altura por Manning, bissecção), `TUB:Calcular`, `TUB:Resumo`/`Formata`, auditoria `secao-tubo`, tipo `tubo` | `views/secao_tubo_view.lsp`: `CRIASECAOTUBO`, `EDITASECAOTUBO`, `REMOVESECAOTUBO`, `SECAOTUBO` |
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

A **origem** guarda o seu **destino único** (`JUSANTE`) no `PARAMS` do registro padrão dela
(seção 18). O destino **não guarda nada**: os montantes dele são *calculados* varrendo quem o
cita. Motivos:

| Alternativa                                | Problema                                                                                                         |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| O receptor guarda a lista de montantes     | Nada impede a mesma origem em dois receptores: a mesma água seria contada duas vezes (era a `DUPLICADA`)         |
| Os dois lados guardam                      | Dois valores que podem divergir; é preciso reconciliar                                                          |
| **A origem guarda o destino (adotado)**    | **Um campo escalar: dois destinos são impossíveis pela estrutura.** Religar é uma gravação só; apagar a origem não deixa referência |

Consequências: a bacia fica como era (aberto/fechado); um objeto novo pode receber bacias
sem que a bacia saiba de nada. É o modelo de nó de saída usado por SWMM e HEC-HMS. O custo é
achar os montantes de um objeto: `LIG:ListaMontante` varre os objetos cadastrados
(`OBJ:Listar`, via `LIG:Pares`); as consultas transitivas (`LIG:Montante`) montam o mapa
destino → origens **uma vez** por chamada. Não há índice próprio nem variável global.
Um destino apagado deixa a origem apontando para o nada: a auditoria `ligacoes` acha e
corrige (a origem fica sem destino).

```
PARAMS = (("TALVEGUE" . "2A")                 ; só a bacia: é componente dela, não montante
          ("JUSANTE"  . ("30" . T)))          ; par  handle-do-destino -> flag
                                              ; ("30") = ("30" . nil)
```

O **flag** diz se a origem **contribui diretamente para o talvegue** do destino (`T`, compartilha
o talvegue) ou não (`nil` = ausente); ele decide entre somar ou tomar o máximo dos tempos (15.4).
`JUSANTE` vale para **qualquer** objeto que emite e o destino pode ser qualquer objeto que recebe
(sarjeta recebe bacia *e* sarjeta; bacia recebe bacia). Como o valor é um par, a fração do
escoamento (divisão de vazão, futura) pode virar um terceiro elemento ou uma lista de pares
com soma 1. Trocar o tipo do objeto (`OBJETO`) descarta `PARAMS` e, com ele, o destino dele.
Recadastrar a bacia (`BACIACAD`) preserva `JUSANTE` e só troca o `TALVEGUE`.

Os dados vão para o **dicionário de extensão da entidade** e acompanham a
entidade ao copiar, colar e salvar. Se a entidade **não aceitar** dados
(objeto bloqueado ou tipo sem dicionário de extensão, possível em objetos do
Civil 3D), o core grava na **reserva central** (dicionário `HYDRO-CENTRAL`,
chave `<chave>:<handle>`); a leitura procura nos dois lugares
(`HYDRO:DadoLer`, `HYDRO:DadoGravar`, `HYDRO:DadoApagar`).

### 15.3 Regras de integridade

1. **Uma origem tem no máximo um destino**, garantido pela estrutura (`JUSANTE` é um par).
   Ligar de novo a outro destino *substitui* o par numa gravação só; ao mesmo destino só
   atualiza o flag.
2. **Sem auto-ligação e sem ciclos**: o destino não pode estar a montante da origem.
3. **Os tipos precisam permitir**: a origem `EMITE`, o destino `RECEBE` e a
   `REGRA` opcional de cada tipo (cada tipo só fala de si; ex.: "só bacias
   descarregam em bacias").
4. **Remover o cadastro de um objeto** (`objeto.removido`) desfaz as ligações
   dele; o evento sai antes de apagar. O mesmo vale para a **bacia**: ao remover o
   cadastro dela (botão da tabela de bacias), `OBJ:Remover` emite
   `objeto.removido` e roda o gancho `AO-REMOVER` do tipo (a bacia limpa o XData),
   sem que a bacia conheça o mecanismo de ligações.
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

### 15.5 Recálculo dos montantes, oferta de ligação, padrões do projeto e modo automático

**Recálculo dos montantes.** Calcular um objeto (`BACIA`, `CALCULAOBJETO`) **recalcula antes todos os
montantes**, do mais a montante para jusante (`LIG:RecalcularMontantes`, ordem de `LIG:_Ordem`), com o
mesmo método e TR, **sem perguntas**. Cada montante usa os parâmetros do último cálculo daquele
método/TR (ou os padrões do projeto, se nunca foi calculado). Bacia: capacidade `RECALCULA`
(`BAC:_ObjRecalcula`; prepara com `BAC:Preparar`: relê o desenho e recalcula o tc). Demais tipos: cálculo genérico
`LIG:CalcularCore`. Para no primeiro erro e diz qual objeto falhou.

**Oferta de ligação ao criar.** Ao cadastrar um objeto **novo** (`OBJETO`, `<TIPO>CAD`, `BACIACAD`) o
Hydro pergunta `[Montante/Destino/Nao]` antes de seguir (`LIG:OferecerLigacao`): *Montante* seleciona os
objetos que descarregam nele (e pergunta se contribuem ao talvegue, se ele concentra); *Destino* usa o
`LIGAR`. Não pergunta ao editar nem se o objeto já tem ligação.

**Padrões do projeto** (`PADROES`, `views/padroes_view.lsp`). Valores gravados no desenho em
`HYDRO.PADRAO.<chave do parâmetro>` (ex.: `HYDRO.PADRAO.MET.racional.C`, `...scs-cn.CN`), mais `HYDRO.TR`,
`HYDRO.TC.MINIMO` e o método padrão. Prioridade ao sugerir (`HYDRO:AskParams`, `HYDRO:ParamsPadrao`):

```
atributo da bacia (C, CN) > padrão do projeto > último valor usado > padrão do método
```

No `BACIACAD`, Enter em C/CN deixa a bacia **sem** o atributo, e vale o padrão do projeto na hora de
calcular (mudar o padrão depois muda o cálculo; digitar um valor fixa o atributo naquela bacia).

**Modo automático** (`HYDRO.CALC.AUTO` = 1, comando `CALCAUTO`; padrão desligado). Ligado, `BACIA` e
`CALCULAOBJETO` usam o último TR, o último método e os parâmetros conhecidos **sem perguntar**, escrevem
o resultado na linha de comando (sem `alert`) e não oferecem inserir texto. Se não há TR ou método
conhecido ainda, perguntam normalmente.

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
| `ARMAZENAMENTO`       | alist`(("LER" . fn) ("GRAVAR" . fn) ("LISTAR" . fn) ("REINDEXAR" . fn) ("REMOVER" . fn))` | só para quem guarda **fora** da extensão da entidade; **exige** as 5 operações (seção 18). Bacia e sarjeta não usam |
| `AO-REMOVER`          | `(fn en)`                                                                                 | limpeza própria; roda em `OBJ:Remover` depois de `objeto.removido` e antes de apagar o registro (a bacia limpa o XData) |
| `CARACTERIZA`         | `(fn en)` → alist                                                                        | obtém do desenho o que vai em`CARACT` ao cadastrar (ex.: comprimento e declividade da sarjeta) |
| `NOME-FN`, `RESUMO` | `(fn en)`                                                                                 | nome e linhas de texto nas tabelas                                                                |
| `PADROES`             | `(fn en)` → alist                                                                        | padrões dos parâmetros ao cadastrar                                                             |
| `REGRA`               | `(fn tipo-origem tipo-destino)`                                                           | `nil`/`T` = permitido; **string** = motivo da recusa                                    |
| `VAZAO-EM`            | `(fn en metodo tr tc)` → alist do método (`QP`, `VOLUME`) ou nil                         | o objeto**gera** vazão: reavaliada**só dele** no tc dado (a bacia refaz o método com os parâmetros gravados) |
| `RECALCULA`           | `(fn en metodo tr)` → nil (ok) ou texto do erro                                          | recálculo**sem perguntas** usado para atualizar montantes (bacia); sem ele vale o cálculo genérico (15.5) |
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

> **Atenção:** o campo `RESULT` descrito nesta seção e nas anteriores (grupos soltos `VAZAO`/`HIDRAULICA`/`HIDROGRAMAS`
> com `METODO` + `TR`) é o formato **antigo**. O vigente é o **por cenário** (seção 18e): `RESULT` = lista de cenários
> (`"TR25"`), cada um com os grupos do tipo (`TC`, `PRECIPITACAO`, `ENTRADA`, `VAZAO`, `HIDROGRAMA`, `ALTURA_LAMINA`...).

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
                   ("JUSANTE"  . ("30" . T))))             ; destino: handle -> flag (seção 15.2)
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
| `PARAMS` | **ligações com outros objetos**, necessárias para calcular ou extrair informação: `"TALVEGUE"` (só a bacia; componente dela) e `"JUSANTE"` (qualquer objeto que emita; par handle do destino → flag "contribui diretamente ao talvegue"; os montantes são derivados)                                                                                                                                                                                                 | Evitar. Só entra quando o objeto de fato depende de outro. É opcional: sem ligação, não existe             |
| `ATRIB`  | valores que**precisam ser definidos** pelo usuário e **não podem ser obtidos do desenho** (C, CN, seção, rugosidade)                                                                                                                                                                                       | Se o desenho não sabe responder, é`ATRIB`                                                                   |
| `CARACT` | o que**pode ser obtido do objeto no desenho** (área, comprimento, desnível, declividade)                                                                                                                                                                                                                           | Mesmo que o usuário possa informar o valor, ele continua em`CARACT`                                          |
| `RESULT` | **tudo que é calculado**: em **grupos com nome**: vazões (`"VAZAO"`), tempo de concentração (`"TC"`), hidrogramas (`"HIDROGRAMAS"`) e, na sarjeta, `"HIDRAULICA"` (lâmina, velocidade...). Os campos calculados ficam **planos** na entrada do grupo; não há lista genérica de cálculos | Se saiu de uma conta, é`RESULT`. Hidrogramas também ficam aqui                                              |

Efeito buscado: **a forma de acessar resultados é igual para todos os objetos**
(`OBJ:ResultDe`, `OBJ:ResultGrupoDe`), seja bacia, sarjeta ou o que vier.
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
| `OBJ:ResultDe`, `OBJ:CenariosDe`, `OBJ:ResultGrupoDe en cenario grupo`, `OBJ:VazaoDe en cenario` | `RESULT` (todos os cenários), nomes dos cenários, os campos de um grupo num cenário, o grupo `"VAZAO"` |
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
| `bacia`     | padrão (gancho `AO-REMOVER` limpa o XData) | `TALVEGUE` | `C`, `CN`    | `AREA`, `COMP`, `DESNIVEL`, `DECL` | `TC` (`MIN`, `ORIGEM`, `PARAMS`), `VAZAO`, `HIDROGRAMAS`, `SARJETAS`                                                                            |
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
4. **Não declare `ARMAZENAMENTO`** só para ter índice, evento ou limpeza própria:
   use os ganchos (`CARACTERIZA`, `AO-REMOVER`) e, se o tipo monta o próprio registro
   (como a bacia, com talvegue e tc), termine em `OBJ:Salvar en tipo reg`, que grava
   pelo contrato e emite `objeto.cadastrado`. Só quem guarda fora da extensão da
   entidade fornece as cinco operações; o registro continua sendo o padrão.
   Leitura tipada: `OBJ:RegistroDe en tipo` (nil se a entidade é de outro tipo).
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
comandos genéricos abaixo) define **cinco comandos de linha de comando**, com o nome do arquivo em
maiúsculas como prefixo (`verificar.py` confere):

| Comando        | Faz                                                                                          | Fluxo genérico |
|----------------|----------------------------------------------------------------------------------------------|----------------|
| `<TIPO>CAD`    | cadastra **ou edita** (se a entidade já é do tipo, abre a edição dele)                       | `OPV:Cadastrar tipo` |
| `<TIPO>EDITA`  | escolhe o objeto e **um campo** (ATRIB, vínculo de `PARAMS` ou CARACT manual); pergunta só ele (18d) | `OPV:EditaCampo tipo` |
| `<TIPO>S`      | lista os cadastrados (nome, tipo, handle, afluentes, destino)                                | `OPV:Listar tipo` |
| `<TIPO>INFO`   | mostra as informações de um objeto (`ToString`)                                              | `OPV:Info tipo` |
| `<TIPO>ZOOM`   | procura por nome (ou parte) ou handle, dá zoom e seleciona; Enter lista tudo para escolher   | `OPV:Zoom tipo` |

`BACIACAD/BACIAEDITA/BACIAS/BACIAINFO/BACIAZOOM` e `SARJETACAD/SARJETAEDITA/SARJETAS/SARJETAINFO/SARJETAZOOM` seguem o padrão.
O modelo só diz de que tipo é (`(OPV:Zoom "sarjeta")`); os fluxos estão em
`views/objetos_padrao_view.lsp` (feature `objetos-padrao-view`) sobre as consultas puras de
`plugins/objetos_padrao.lsp` (feature `objetos-padrao`, prefixo `OPD:`). `OBJ:CadastroInterativoTipo`
é o cadastro com **tipo fixo** (não pergunta o tipo).

Comandos **gerais**, válidos para qualquer tipo: `OBJETO` (cadastra/edita), `OBJETOS` (lista um tipo ou
todos), `OBJETOINFO`, `OBJETOZOOM` (localiza qualquer objeto), `OBJETOREMOVER`, `OBJETOVINCULOS`.

### Vínculos (`PARAMS`) e `OBJETOVINCULOS`

`PARAMS` guarda ligações com **outras entidades** como `(chave . handle)` (ex.: `("TALVEGUE" . "2F")`);
todo valor string de `PARAMS` é tratado como handle, e o handle de `"JUSANTE"` também. `OBJETOVINCULOS` **realça e seleciona** as entidades
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
| `params`        | `objetos_padrao.lsp`     | vínculo de `PARAMS` (exceto `JUSANTE`) para entidade apagada/inexistente | escolher outra entidade ou `[Remover]` o vínculo (Enter deixa como está) |
| `tipo-ausente`  | `objetos_padrao.lsp`     | cadastro de um tipo que não está carregado                           | nenhuma (só informa; não apaga dados) |
| `ligacoes`      | `ligacao.lsp`            | afluente apagado/sem tipo, origem em vários receptores, ciclo        | `LIG:Reparar` (ciclo: manual) |
| `secao-atual`   | `secao.lsp`              | `HYDRO.SECAO.ATUAL` fora do cadastro                                 | usa a primeira seção |
| `secao-sarjeta` | `models/sarjeta.lsp`     | sarjeta com `SECAO` inexistente                                      | escolhe uma seção para todas |
| `secao-tubo`    | `models/tubo.lsp`        | tubo com `SECAO` inexistente                                         | escolhe uma seção para todos |
| `tipo-estrutura`| `models/estrutura.lsp`   | estrutura com `TIPO-EST` inexistente                                 | escolhe um tipo para todas |
| `secao-escada`  | `models/escada.lsp`      | escada com `SECAO` inexistente ou não retangular                     | escolhe uma seção retangular para todas |
| `superficie`    | `auditoria.lsp`          | `HYDRO.SURFACE.HANDLE` aponta para entidade apagada                  | limpa o handle |

`VALIDARLIGACOES` continua existindo (só ligações). Corrigir um vínculo ou uma seção **não recalcula**
nada: rode `CALCULAOBJETO` / `BACIA` depois.

## 18c. Etiquetas dinâmicas e tabela viva

Para o Hydro não ficar "silencioso", dois elementos do desenho se **atualizam sozinhos** (plugin
`etiqueta`, comandos em `views/etiqueta_view.lsp`). Não usam campos (`FIELD`) do AutoCAD, que não leem
os dados do Hydro: o plugin reescreve o texto quando recebe os eventos `bacia.calculada`,
`objeto.calculado`, `objeto.cadastrado`, `ligacao.criada` e `ligacao.removida` (e, para o aviso de resultado desatualizado,
`objeto.obsoleto` -> só as etiquetas do objeto, e `objetos.obsoletos` -> as tabelas, **uma vez** ao fim da cadeia)
(todas as ações são protegidas: um erro na etiqueta nunca interrompe o cálculo).

**Etiqueta** (`ETIQUETA`, `ETIQUETAEDITA`): MTEXT na camada `HYDRO-ETIQUETA` ligado ao objeto
(chave `HYDRO-ETQ` na etiqueta: `ALVO` = handle, `MODO`, `MODELO`, `CENARIO` opcional: fixa um cenário; sem ele,
segue o cenário em uso e, se o objeto não o tem, o último calculado).

| Modo       | Texto                                                                                         |
|------------|-----------------------------------------------------------------------------------------------|
| `FIXO`     | **relatório do objeto**: o mesmo texto de `OBJ:Resumo` (cadastro, atributos, cálculos)        |
| `MODELO`   | **identificação / prancha**: texto seu com campos `{CAMPO}`, um modelo por etiqueta           |

Campos (sem diferenciar maiúsculas; `?` se não existir): `{NOME} {TIPO} {HANDLE}`, `{AREA}` (ha),
`{CENARIO}`, qualquer chave de `ATRIB` (`{C} {CN} {N}`), depois de `CARACT` (`{COMP} {DECL}`), depois dos campos do
**cenário** (`VAZAO`, `PRECIPITACAO`, `INPUT`) e **`{GRUPO.CAMPO}`** de qualquer grupo (`{VAZAO.VALOR}`, `{ENTRADA.TC}`,
`{ALTURA_LAMINA}` = `{ALTURA_LAMINA.VALOR}`). Atalhos: `{QP}`=`VAZAO.VALOR`, `{TC}`=`VAZAO.TC` (saída), `{TCP}`=`TC.VALOR`,
`{TR}`, `{METODO}`, `{E.QP} {E.TC}` (entrada), `{H.LAMINA} {H.VELOCIDADE} {H.LARGURA} {H.PERCURSO}`. Com resultado
desatualizado o texto ganha "(resultado desatualizado)". `\P` quebra a linha. Modelo padrão por tipo:
`HYDRO.ETIQUETA.MODELO.<tipo>` (o `ETIQUETAEDITA` pode gravar o modelo editado como padrão).

**Tabela viva** (`TABELAVIVA`): objeto `TABLE` na camada `HYDRO-TABELA` (chave `HYDRO-TBL`) com
todos os objetos: nome, tipo, A, L, S, atributos, **cenário**, Q de entrada, Q de saída (`*` = desatualizado), tc e destino. Cada
atualização refaz as linhas. `ATUALIZAETIQUETAS` força a atualização de tudo.

**Limites:** mostram o que está **gravado**; mover a geometria sem recalcular não muda o resultado. A
etiqueta fica no ponto onde foi inserida (não acompanha a entidade). A verificação `etiquetas` do
`HYDROAUDIT` acha etiquetas cujo objeto não existe mais e as apaga.

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

## 18d. Esqueleto único: vínculos, CARACT manual e resultado desatualizado

Plano e decisões: `docs/plano_esqueleto_unico.md`; exemplo comentado: `docs/objeto_generico.lsp`.
Implementado em `plugins/objetos.lsp` (etapa 1; a bacia migra na etapa 3).

- **Capacidades novas:** `"PARAMS-DEFS"` (`chave rotulo aceita [obrigatorio]`, entidades de apoio gravadas em
  `PARAMS` como handles; `aceita` = nomes DXF e/ou ids de tipo) e `"CARACT-DEFS"` (formato de `ATRIB`; o que
  o usuário digita quando o desenho não informa; chaves em `CARACT/MANUAL`). `"CARACTERIZA"` passa a ser
  `(fn en vinculos)`, com `vinculos` = alist `(chave . ename)`.
- **Funções:** `OBJ:CadastrarCom en tipo atrib nome vinculos manual` (`OBJ:Cadastrar` chama com nil nil),
  `OBJ:CadastroInterativoTipo` pede os vínculos (`[Usar/Trocar/Remover]`) e os CARACT manuais,
  `OBJ:EditaCampoInterativo` (comando `<TIPO>EDITA` via `OPV:EditaCampo`) altera um campo só.
- **Obsoleto (por cenário, plano `docs/plano_resultados_cenarios.md`):** `("OBSOLETO" . T)` no grupo `"CENARIO"` de cada cenário do `RESULT`. `OBJ:Salvar` marca quando o objeto tinha `RESULT` e
  `ATRIB`/`PARAMS`/`CARACT` mudaram (e mantém a marca existente); `OBJ:GravarResultado` dos grupos `VAZAO` e
  `HIDRAULICA` (e a gravação de vazão da bacia) remove. Com `HYDRO.OBSOLETO.PROPAGA` = 1,
  `OBJ:InvalidaJusante` segue `PARAMS/JUSANTE`, só gravando a marca (para ao achar um já obsoleto ou um ciclo).
  Nenhum recálculo na edição. Evento `objeto.obsoleto` (`OBJETO`). Leitura: `OBJ:Obsoleto`.
- **Reler o desenho ao calcular:** `LIG:CalcularCore` chama `OBJ:AtualizaCaract`: com `HYDRO.CARACT.AUTO` = 1 recaracteriza e regrava só o `CARACT` se mudou (manuais preservados; sem marcar obsoleto). A bacia faz o mesmo em `BAC:Preparar`.
- `LIG:Conectar`/`LIG:Desconectar` (e, por eles, remover objeto) chamam `OBJ:Invalidar` no destino novo, no anterior e no destino perdido: marcam esses objetos e, só com `HYDRO.OBSOLETO.PROPAGA` = 1, a jusante deles. A origem não é marcada (a saída dela não mudou). Repetir a chamada é barato: ao achar objeto já obsoleto a cadeia para.

## 18e. RESULT por cenário (em implantação)

Plano e decisões: `docs/plano_resultados_cenarios.md`. **Etapa 1 feita** (núcleo em `plugins/objetos.lsp`);
as etapas 2 a 5 migram `ligacao`, `sarjeta`, `bacia`, `hidrograma`, `etiqueta` e as tabelas. Até lá,
quem ainda usa o formato antigo (grupos soltos com `METODO` + `TR`) **não funciona** com este núcleo.

```
("RESULT" . (("TR25" . (("CENARIO" ("TR" . 25.0) ["OBSOLETO" . T])
                        ("TC" ("VALOR" . 15.0) ("METODO" . "kirpich"))
                        ("VAZAO" ("VALOR" . 9.88) ("METODO" . "racional") ("INPUT" ...))))
             ("TR10" . (...))))
```

| Função | Faz |
|---|---|
| `OBJ:CenarioPadrao tr` | `25.0` → `"TR25"`, `2.5` → `"TR2.5"` |
| `OBJ:CenarioNome tr nome` | `"TR25"` ou, com nome, `"TR25-Nome"` |
| `OBJ:CenarioAtual`, `OBJ:NomeCenario`, `OBJ:DefineNomeCenario nome` | cenário em uso = último TR + nome opcional (`HYDRO.CENARIO.NOME`); comando `CENARIO` (Enter = só o TR) |
| `OBJ:GravarCalculo en cenario tr grupos` | grava um cálculo inteiro numa gravação só (TR, sem `OBSOLETO`, todos os grupos) |
| `OBJ:CenariosDe en`, `OBJ:CenarioDe en cenario`, `OBJ:TrDoCenario en cenario` | leitura |
| `OBJ:GravarResultado en cenario grupo campos` | grava/substitui o grupo (campos nil remove) |
| `OBJ:DefineCenario en cenario tr` | cria o cenário com seu TR |
| `OBJ:ConcluiCalculo en cenario` | remove `OBSOLETO` do cenário (quem calcula chama no fim) |
| `OBJ:Obsoleto en cenario` | cenário marcado? (`nil` = algum) |
| `OBJ:Invalidar en` | marca todos os cenários do objeto (+ jusante conforme `PROPAGAOBSOLETO`) |

`OBJ:GravarResultado` **não** limpa mais o `OBSOLETO` sozinho; quem calcula usa `OBJ:GravarCalculo` (uma gravação, desempenho)
ou `OBJ:ConcluiCalculo`.

**Etapa 2 (ligação e sarjeta, feita):** `LIG:Saida/Entrada/VazaoMontante/CalcularCore/Recalcular/RecalcularMontantes`
trabalham por cenário (`VAZAO-EM` agora `(fn en cenario tc)`, `RECALCULA` `(fn en cenario metodo tr)`). `CALCULA` do tipo devolve
**grupos** `((grupo . campos) ...)` (sarjeta: `ALTURA_LAMINA`, `LARGURA_INUNDADA`, `AREA_MOLHADA`, `VELOCIDADE`, `PERCURSO`,
`AVISOS`); `FORMATA` é `(fn en cenario)`. Core grava `ENTRADA` e `VAZAO` (`VALOR`, `TC`, `METODO`, `VALOR-CALC`, `PRESERVADA`,
`VOLUME`, `INPUT`). Etiqueta e tabelas ainda no formato antigo (etapa 5).

**Etapa 3 (bacia, feita):** `BAC:_CalcularEGravar` grava o cenário numa gravação só: `TC` (`VALOR`, `METODO`, `INPUT`),
`PRECIPITACAO` (`VALOR` = P em mm, ou I em mm/h, `UNIDADE`, `I`, `P`, `PE`), `ENTRADA` (só com montantes) e `VAZAO`
(`VALOR`, `TC`, `METODO`, `DUR`, `VOLUME`, `QP-PROPRIO`, `AREA-TOTAL`, `TC-PROPRIO`, `VALOR-CALC`, `PRESERVADA`, `INPUT`).
`BAC:Preparar` não grava mais (devolve o contexto com o tc); `VAZAO-EM` e `RECALCULA` são por cenário. Para textos e
menus há adaptadores no formato "plano" antigo: `BAC:Vazao dados` (lista, um por cenário), `BAC:CalcDe dados cenario`,
`BAC:Tc`, `BAC:TcDeCenario`; puros e testados: `BAC:_Grupos` / `BAC:_CalcFlat`. `BAC:Hidrogramas` (hidrogramas planos, um por cenário).
Funções puras (testadas): `OBJ:_ResultSetGrupo`, `OBJ:_ResultObsoleto`, `OBJ:_ObsoletoR`,
`OBJ:_TodosObsoletosR`.

**Etapa 4 (hidrograma, feita):** um hidrograma por cenário, no grupo `HIDROGRAMA` (`VALOR` = Qp, `TIPO`, `TP`, `TB`,
`VOLUME`, `DUR`, `NOTA`, `INPUT`, `PONTOS`; `METODO` e `TR` não são copiados: vêm de `VAZAO` e `CENARIO`). O **tipo é
definido na bacia** (`ATRIB` `HIDROGRAMA-TIPO`, `BACIAEDITA`); `HIDROGRAMA` gera o do cenário escolhido com o tipo da bacia
(`HID:TipoDaBacia`), guarda com `HID:Armazenar en cenario hid` e emite `hidrograma.gerado` (agora com `CENARIO`). Recalcular a
vazão do cenário **remove** o hidrograma dele (`BAC:_CalcularEGravar` grava `("HIDROGRAMA")` nil). Puros e testados:
`HID:_Grupo` e `BAC:_HidFlat` (ida e volta). A propagação de hidrogramas pela rede (somar `PONTOS` na `ENTRADA`) fica para depois.

**Etapa 5 (etiquetas e tabela, feita):** `ETQ:_CampoR` resolve os campos pelo cenário (lê o registro **uma vez** por etiqueta);
`ETQ:_CenarioR` escolhe o cenário (o da etiqueta, o em uso ou o último); `ETQ:_GC` lê `GRUPO.CAMPO`. A tabela viva mostra o
cenário e marca `*` o Q de saída desatualizado. Eventos novos `objeto.obsoleto` (um objeto) e `objetos.obsoletos` (fim da
cadeia, para as tabelas). **Plano de resultados por cenário concluído** (etapas 1 a 5), só com análise estática.

## 18f. Tubo / canal (`models/tubo.lsp`, tipo `tubo`)

Aceita `LINE`, `LWPOLYLINE` e `POLYLINE` (3D). **Declividade = |cota inicial − cota final| / comprimento**: só os pontos
inicial e final e o comprimento da entidade contam (vértices intermediários não). Linha 2D (cotas iguais) não tem
declividade no desenho: ela é digitada (`CARACT-DEFS`, `TUBOEDITA`). O tubo **recebe e emite**, precisa de montante e
o tempo de saída é `max tc dos montantes + percurso` (modo `percurso`).

**Catálogo de seções** `HYDRO.SECOES.TUBO` (padrão: circular D=0.6, retangular 1x1, trapezoidal b=1, h=1, z=1.5), **gerenciado em `plugins/secao_tubo.lsp`** (como `secao.lsp` das sarjetas); o model só lê (`TUB:Secoes`):
`(id ("forma" . "circular"|"retangular"|"trapezoidal") ("d"|"b" "h" "z") ("n" . manning))`. Comandos `CRIASECAOTUBO`,
`EDITASECAOTUBO`, `REMOVESECAOTUBO` (recusa seção em uso e a última), `SECAOTUBO` (visualizador). `ATRIB`: `SECAO` (id) e `N` (0 = o da seção).

**Visualizador** (`SECAOTUBO`, `views/secao_tubo_view.lsp`, DCL `resources/dcl/secao_tubo.dcl`, como o `SECAO` das sarjetas): lista as
seções; desenha a seção em **forma real 1:1** (sem exagero vertical, para o círculo continuar círculo) com as cotas (`D`; `b`, `h`; `z`, `B`);
`Escala comum a todas as seções` (lembrada em `HYDRO.SECAO.TUBO.COMUM`); campos **Q** e **S** → `TUB:Resolver` e desenho da
lâmina d'água com `y`, enchimento, velocidade, Froude, área molhada, capacidade e avisos; **Último cálculo** (último tubo calculado,
evento `objeto.calculado`: `HYDRO.ULTIMO.TUBO.*`); **Selecionar** (vira a seção atual) e **Inserir no desenho** (camada `HYDRO-SECAO`,
`entmakex`, centro da base; lâmina em `CIRCLE`/`LWPOLYLINE`/`SOLID`).

**Cálculo** (Manning, escoamento uniforme; Chow, *Open-Channel Hydraulics*, 1959): dada a vazão da `ENTRADA`, `TUB:Resolver`
acha a altura `y` por bissecção. Circular: a vazão cresce até `y = 0.9382 D` e depois cai até a seção plena; acima da
máxima não há lâmina livre (`y = D`, aviso de escoamento sob pressão). Retangular/trapezoidal: acima da capacidade em `y = h`,
`y = h` (aviso). Grupos gravados no cenário: `ALTURA_LAMINA`, `AREA_MOLHADA`, `VELOCIDADE`, `RAZAO_ENCHIMENTO`, `FROUDE`,
`CAPACIDADE` (seção cheia; `EXCEDIDA`), `PERCURSO`, `AVISOS`. **Faixa de validade:** `S > 0`, `n > 0`, `Q > 0`; Froude entre
0.9 e 1.1 avisa regime instável; não há limites de velocidade nem de enchimento embutidos.

Os tipos básicos `trecho` e `tubo-c3d` (`objetos_tipos.lsp`) continuam existindo, sem cálculo próprio; o `tubo` é o modelo
completo (polilinhas/linhas). Nada foi executado no AutoCAD.

## 18g. Estrutura (`models/estrutura.lsp`, tipo `estrutura`) — atomizada

Modelo **único** para poço de visita, caixa, ala e boca de lobo; o que muda é o **tipo**, definido num catálogo gerenciado em
arquivo próprio (`plugins/tipo_estrutura.lsp`, como `secao.lsp` das sarjetas), e a **classe** do tipo, que sabe calcular, cada
uma em **seu arquivo** em `plugins/registry/` (aberto/fechado: classe nova = arquivo novo, sem alterar o model):

| Peça | Arquivo | Papel |
|---|---|---|
| objeto | `models/estrutura.lsp` | `ATRIB` `TIPO-EST` e `QTD`; acha a classe do tipo e chama o `CALCULA`/`FORMATA` dela |
| catálogo de tipos + registro de classes | `plugins/tipo_estrutura.lsp` | `TES:Adicionar/Editar/Remover/EmUso`, `TES:RegistrarClasse`, tipo atual, auditoria `tipo-estrutura-atual` |
| classe `passagem` | `registry/estrutura_passagem.lsp` | poço, caixa, ala: repassa; perda de carga localizada `dH = K V²/(2g)` (V = maior velocidade dos tubos de montante; `K` do projetista) |
| classe `boca-lobo` | `registry/estrutura_boca_lobo.lsp` | captação por método; aviso **"Boca de lobo afogada"**; não divide a vazão (a saída segue igual à entrada; o excedente fica em `PASSAGEM`) |
| classe `dissipador` | `registry/estrutura_dissipador.lsp` | dissipador de energia: balanço de energia `E_in = y + V²/(2g)` (y, V dos montantes), `dE`, potência `9.81·Q·dE` (kW); `E_out` pelo método do tipo (`dissipacao.lsp`, hoje `informado`: eficiência 0 a 1) |
| métodos de dissipação | `registry/dissipacao.lsp` | catálogo `metodo-dissipacao`; brecha para bacia USBR, impacto etc. (arquivo novo) |
| métodos de captação | `registry/captacao.lsp` | catálogo `metodo-captacao`; hoje `unitaria` (`QCAP = QTD × cap`, proporcional) |

**Tipo** = `(id ("nome" . txt) ("classe" . id) + campos da classe)`: passagem `("k" . K)`; boca de lobo `("metodo" . id)` e `("cap" . m3/s)`.
Fábrica: Poço de visita, Caixa, Ala (K = 0) e Boca de lobo (**capacidade 0**: defina com `EDITATIPOESTRUTURA`).
**Classe** = `(TES:RegistrarClasse id nome campos valida rotulo calcula formata)`; `campos` = `(chave rotulo padrao unidade [tipo [opcoes]])`
perguntados pelo catálogo (`HYDRO:AskParams`; `opcoes` aceita símbolo de função para lista dinâmica); `calcula (en ctx tipo dados)` devolve
grupos e recebe `ctx` com `"MONTANTES"` (`V`, `Y`). **Brecha para equações:** um método novo (vertedouro, orifício) é um arquivo novo que faz
`(HYDRO:RegAdd "metodo-captacao" id (list ("NOME" ..) ("DESC" ..) ("FN" . 'fn)))`; `(fn ctx)` recebe `Q`, `QTD`, `LAMINA` (maior
`ALTURA_LAMINA` dos montantes, ou nil) e `TIPO` e devolve `(("QCAP" . m3/s))`. Comandos do catálogo: `CRIATIPOESTRUTURA`,
`EDITATIPOESTRUTURA`, `REMOVETIPOESTRUTURA` (recusa tipo em uso e o último), `TIPOESTRUTURA`. Nada foi executado no AutoCAD.

## 18h. Escada hidráulica (`models/escada.lsp`, tipo `escada`)

Objeto **linear** como o tubo e a sarjeta (`LINE`, `LWPOLYLINE`, `POLYLINE` 3D; só o ponto inicial, o final e o comprimento
contam; linha 2D tem a declividade digitada). A largura da calha vem da **seção do catálogo de tubo/canal** (`SECAOTUBO`; hoje só
**retangular**). `ATRIB`: `SECAO`, `DEGRAU` (altura **máxima** do degrau `h`) e `METODO-ESCADA` (`nenhum` ou um método do catálogo).

**Calcula (consenso, sem equação de regime):** `NDEG = ceil(desnível/h)`; altura real `hr = desnível/NDEG`; `Lh = √(COMP² − desnível²)`;
piso `l = Lh/NDEG`; inclinação `atan(hr/l)`; **altura crítica** retangular `yc = (q²/g)^(1/3)`, `q = Q/b` (Chow, 1959); razão `yc/hr`.
Grupos: `ALTURA_CRITICA`, `DEGRAUS` (`VALOR` = NDEG, `ALTURA`, `PISO`, `INCLINACAO`), `YC_H`, `AVISOS`.

**Método incluído `siscooh`** (`registry/escada_siscooh.lsp`, prefixo `ESS:`; referência `docs/referencia-escadas-hidraulicas-siscooh.md`,
SisCCoH 1.1 seção 4.2): regime (nappe / transição / skimming, com subtipos), vazões limite, e conforme o regime: nappe (número de queda, `Ld`, `Lj`,
parede, energia máxima e **residual** com ressalto completo ou parcial, dissipação, **estado final** lâmina/velocidade/Froude) ou skimming
(`He`, atrito, energia residual, concentração de ar, altura aerada e do muro, início da aeração). Validade `0,05 ≤ S/l ≤ 1,43`; a transição e o nappe
sem ressalto não têm energia residual (aviso). **Não implementado:** risco de cavitação (eq. 4.53 incompleta no manual). **Calibrados/deduzidos:**
α = 0,54 da eq. 4.31 (calibrado no exemplo 4.2), eq. 4.27 (grafia duvidosa); confira os coeficientes nas fontes originais antes de projetar. Exemplos
4.1, 4.2 e 4.3 do manual estão nos testes. O método devolve também `ALTURA_LAMINA`, `VELOCIDADE` e `FROUDE` (estado final), que um **dissipador a
jusante** lê como montante.

**Outros métodos** entram como arquivo novo no catálogo `metodo-escada`:
`(HYDRO:RegAdd "metodo-escada" id (list ("NOME" ..) ("DESC" ..) ("FN" . 'fn)))`; `(fn ctx)` recebe `Q`, `B`, `YC`, `H`, `L`, `NDEG`,
`TETA`, `YC-H`, `DESNIVEL`, `COMP` e devolve grupos (um `PERCURSO` define o tempo próprio, um `AVISOS` se junta ao da escada).
Escolha: `ATRIB` `METODO-ESCADA`.

## 18i. Dissipador de energia (classe `dissipador` da estrutura)

Classe de estrutura (`registry/estrutura_dissipador.lsp`), criada como tipo no `CRIATIPOESTRUTURA`: o tipo guarda o **método** e os **parâmetros do
método** (campos dinâmicos: o catálogo pergunta primeiro o método, depois `PARAMS` dele; `TES:ClasseExtra "CAMPOS-FN"`). Balanço de energia quando o
método dá a energia de saída: `E_in = y + V²/(2g)` (y e V do montante, ou o `EIN` do método), `dE = E_in − E_out`, potência `9.81·Q·dE` (kW);
os grupos do método (`GRUPOS`) são gravados junto. Catálogo `metodo-dissipacao` (cada método: `PARAMS`, `VALIDA`, `FN`):

| Método | Arquivo | O que faz |
|---|---|---|
| `informado` | `registry/dissipacao.lsp` | `E_out = (1 − eficiência)·E_in` (eficiência 0 a 1 informada) |
| `usbr` | `registry/dissipacao_usbr.lsp` (`DUS:`) | bacia por ressalto, tipos I a IV (Peterka 1984; SisCCoH 4.3): `V1`, `Fr1`, tipo, `D2`, comprimento, `dE`, velocidade de saída, borda livre e parede, `h3`/`h4` (tipo III). Campo `largura` (B); `D1` = lâmina do montante; `Fr1 ≥ 1,2`. Exemplo 4.6 nos testes |
| `enrocamento` | `registry/dissipacao_enrocamento.lsp` (`DEN:`) | bacia em enrocamento (HEC-14; SisCCoH 4.4): `Dmin/Dmax`, `Co`, verificações `0,1 ≤ D50/ye ≤ 0,7` e `hs/D50 ≥ 2`, `Ls`, `LB`, `LA`, `WB`, espessuras, profundidade e velocidade de saída (eq. 4.68). Campos `largura`, `d50`, `tw`, `hs` (**entrada**: o manual não traz equação), `curva`, `talude`. Sem energia de saída. Exemplo 4.7 nos testes |

Referência: `docs/referencia-dissipadores-siscooh.md`. **Não implementado:** dimensões dos blocos e soleira além de `h3`/`h4` (Peterka, não validadas no
manual), geometria das bacias II e IV. A tabela de `Co` é de memória do HEC-14 (cobre `TW/ye ≤ 1,0`; acima, erro). O montante precisa informar
`ALTURA_LAMINA` e `VELOCIDADE` (tubo, sarjeta ou escada com `siscooh`). Método novo = arquivo novo no catálogo.
