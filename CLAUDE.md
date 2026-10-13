# Hydro: cálculos de drenagem em AutoLISP para Civil 3D

Conjunto de plugins AutoLISP (hidrologia e hidráulica dentro do Civil 3D/AutoCAD).
O usuário é desenvolvedor Python full stack, escolheu AutoLISP de propósito
(simples, leve, sem C#) e **conversa em português**. Comentários e strings do
código ficam em **ASCII, sem acentos**; a documentação (`docs/`, README) tem acentos.

## Status honesto

**Nada foi executado no AutoCAD/Civil 3D.** Todo o código foi escrito e conferido
só por análise estática (`python build/verificar.py`) e por simulações em Python.
Não afirme que algo "funciona" sem dizer isso. Ao receber relato de erro do
AutoCAD, trate-o como informação nova e prioritária.

Pontos mais incertos, a testar primeiro no AutoCAD:
- `vlax-ldata-put/get` com listas grandes (hidrogramas, vários objetos) e depois de salvar, fechar e reabrir.
- Gravação de dados em objetos do Civil 3D (`AECC_PIPE`, `AECC_STRUCTURE`); nomes DXF a confirmar.
- Descoberta da raiz via Autoloader (`hydro.lsp`, `SupportPath`, `TRUSTEDPATHS`).
- Diálogos DCL: larguras de `tabs`, margens dos gráficos em `HID:_Plota` e `SJT:Desenha`.
- `vlisp-compile` e `MAKELISPAPP` (ver `docs/compilacao.md`).
- Painel `HYDRO`: o DCL é gerado em arquivo temporário (`PNL:_GerarDcl`); conferir se abre, se os
  botões executam e se reabre depois do comando. É modal (não é paleta flutuante).
- **Macros de menu/barras:** o usuario relatou que o formato `^C^CNOME` NAO funcionou ao clicar no botao
  (causa nao identificada). O padrao passou a `(c:NOME)` e ha 5 estilos em `PNL:_MacroDe`
  (`HYDROMACROESTILO`). Descobrir qual estilo funciona e por que o `^C^C` falha (ActiveX x CUI?) e pedir
  o resultado ao usuario; o painel `HYDRO` nao usa macro (chama `c:NOME` direto).
- Barras de ferramentas (`toolbar.lsp`, `AcadToolbars`): `AddToolbarButton`/`SetBitmaps` aceitam os BMP 24 bits?
  `Dock` (0 top, 1 bottom, 2 left, 3 right) e `Float`; posição mantida ao recriar; nome do grupo principal.
- Menu "Hydro" (`menu.lsp`, API ActiveX `AcadMenuGroup`/`AcadPopupMenu`): nome do grupo principal no
  Civil 3D (usa `ACAD`, senão o primeiro), posição antes de Ajuda, `MENUBAR`, e se não persiste na personalização.
- `JUSANTE` em `PARAMS` (gravação via `OBJ:GravaRegistro`, `ldata` com `("31")` sem valor; **mudou de MONTANTE no receptor para JUSANTE na origem**, ainda não testado), `LIG:` sem
  índice (varre `OBJ:Listar`; custo com muitos objetos), `BAC:_CalcularEGravar` composto, `VAZAO-EM` reavaliando o método,
  `LIGAR` perguntando o flag, sarjeta recebendo sarjeta em cadeia. Desenhos antigos com `HYDRO-LIG` **não migram**.
- Recálculo automático dos montantes, `LIG:OferecerLigacao` (prompt `getkword` com `initget` montado), `PADROES`
  (`HYDRO:_AskUm`), modo `CALCAUTO` e `sssetfirst`/`ssget` na oferta de ligação: nada disso foi executado.
- Etiquetas/tabela viva: `vla-addtable`/`vla-settext`/`vla-insertrows` e `vla-put-textstring` no MTEXT, `ssget "_X"` por camada
  (camada congelada?), assinatura dos eventos e a atualização a cada cálculo (custo com muitos objetos).
- **Armazenamento padronizado da bacia** (sem `ARMAZENAMENTO` proprio): `OBJ:Salvar`/`OBJ:RegistroDe`, gancho `AO-REMOVER`, indice unico `HYDRO.OBJETOS`
  (sumiu `HYDRO.BACIAS`; desenhos antigos precisam de Reindexar), relacao XData agora via `objeto.cadastrado` (sumiram `bacia.cadastrada`/`bacia.removida`). Nada executado.
- **LIGACOESVER** (`views/ligacao_visual_view.lsp`): nada executado. Incertos: `grvecs` (lista `(cor p1 p2 ...)`; se os pontos sao em UCS ou WCS: o codigo converte WCS->UCS com `trans`), se some em REGEN/zoom, `VIEWSIZE` como escala dos tracos, `vla-getboundingbox` em contornos.
- **Escada hidráulica** (`models/escada.lsp`, método `registry/escada_siscooh.lsp`) e **dissipador** (`registry/estrutura_dissipador.lsp`, métodos `dissipacao.lsp`/`_usbr`/`_enrocamento`): nada executado no AutoCAD; equações do SisCCoH 1.1 conferidas só contra os exemplos do manual (testes em `HYDROTESTE`, valores do próprio manual). Itens calibrados/deduzidos no manual: α = 0,54 (eq. 4.31), eq. 4.27, `LA`/`WB` do enrocamento; tabela de `Co` de memória; risco de cavitação não implementado; polinômios devem ser conferidos nas fontes originais. Incertos: seção retangular do catálogo de tubo, campos dinâmicos do dissipador (`CAMPOS-FN`), estado final da escada lido pelo dissipador.
- **Estrutura** (atomizada: `models/estrutura.lsp`, `plugins/tipo_estrutura.lsp`, `registry/estrutura_passagem|estrutura_boca_lobo|captacao.lsp`, `tipo_estrutura_view.lsp`): nada executado. Incertos: despacho pela classe (`classe-estrutura`), `HYDRO:AskParams` com `opcoes` dinâmicas nos campos da classe, `OBJ:ResultGrupoDe` dos montantes (VELOCIDADE/ALTURA_LAMINA), captação (a boca afogada só avisa, nao divide a vazao).
- **Tubo/canal** (`models/tubo.lsp`, `plugins/secao_tubo.lsp`, `secao_tubo_view.lsp`): nada executado. Incertos: `vlax-curve-getStartPoint/EndPoint` em `POLYLINE` 3D/`LINE` (Z das pontas), bissecção de Manning (testada só em Python), comandos do catálogo de seções; visualizador `SECAOTUBO` (DCL `secao_tubo.dcl`, desenho em `vector_image`/`fill_image`, margens e textos da imagem).
- **RESULT por cenário** (etapas 1 a 5): nada executado. Incertos: `OBJ:GravarCalculo` e a leitura de cenários com listas aninhadas em `ldata`, nomes de cenário com `-`, etiquetas lendo o registro uma vez, tabela `*`, `getstring` do comando `CENARIO`.
- **Esqueleto único** (etapas 1 a 5 do plano): cadastro genérico com `PARAMS-DEFS`/`CARACT-DEFS`, `<TIPO>EDITA`, `OBSOLETO` e sua propagação, `CARACTAUTO`, tc da bacia só no cálculo (`BAC:Preparar`), `OBJ:_Igual`. Nada executado: `vl-catch-all-apply` em `OBJ:_Caracteriza`, `getkword` `[Usar/Trocar/Remover]`, tipo `"opcoes"` com símbolo dinâmico (`BAC:_IdsTc`) em `HYDRO:AskParams`, comparação de reais em `ldata`.
- Rodar `HYDROTESTE` (carregar `tests/teste_manual.lsp`).

## Estrutura

```
Hydro.bundle/PackageContents.xml   descritor do Autoloader
Hydro.bundle/Contents/
  hydro.lsp                        ponto de entrada (HYDRODIR, HYDRORELOAD)
  core/core.lsp                    registro, eventos, config, catalogos, utilitarios, manifesto
  plugins/*.lsp                    SISTEMA: dados, calculo, eventos (lista em HYDRO:Manifest)
  plugins/models/*.lsp             OBJETOS do sistema (bacia, sarjeta...): so a funcionalidade do objeto
                                   (inclui seus comandos c: de linha de comando e um ToString; texto no desenho e dialogos vao em views/)
  plugins/registry/*.lsp           CATALOGOS: so cadastros de metodos e tipos (MET, TCM, tipos de hidrograma e hietograma)
  views/*.lsp                      INTERFACE: dialogos DCL, comandos c:, desenho (depende dos plugins)
  views/painel, painel_acoes, menu, toolbar   painel HYDRO, menu e barras de ferramentas (catalogo "acao-painel")
  resources/dcl, slides, icons     dialogos, imagem e icones .bmp das barras
build/  build.lsp  verificar.py  instalar.bat  vlx_flag.lsp     (so desenvolvimento)
docs/   arquitetura.md (REFERENCIA)  compilacao.md  distribuicao.md  template_*.lsp
tests/  teste_manual.lsp           comando HYDROTESTE
```

Fonte da verdade da arquitetura, dos contratos e dos formatos de dados:
**`docs/arquitetura.md`**. Leia antes de mexer em eventos, chaves ou catalogos.

## Princípios de arquitetura (decididos com o usuário)

1. **Plugins independentes que se aproveitam uns dos outros** quando carregados.
   Dependência opcional: `(HYDRO:Has "x")`. Obrigatória: `(HYDRO:Require "x")` no momento de usar.
2. **Sem variáveis globais** nos plugins. Únicas do conjunto: `HYDRO:*features*`,
   `*hooks*`, `*session*`, `*labels*`, `*registry*`, `*dir*`, `*embedded*`.
   Estado vai para `HYDRO:Get/Set` (grava no desenho se o plugin `persistencia` existir).
3. **Funções de cálculo puras** (sem `getXXX`, `alert`, `princ`); interação só nos comandos `c:`.
4. **Eventos** entre plugins (`HYDRO:On` / `HYDRO:Emit`): quem calcula não conhece quem reage.
5. **Catálogos extensíveis** (`HYDRO:RegAdd/RegGet/RegList`) para métodos chuva-vazão,
   métodos de tc, tipos de hidrograma e **tipos de objeto hidráulico**.
   **Aberto/fechado:** coisa nova = arquivo novo com um cadastro; não altere o que já existe.
6. **A origem guarda o destino**: campo `JUSANTE` do `PARAMS` dela, par `(handle-do-destino . flag)` com flag T = "contribui diretamente ao talvegue" (nil = ausente); o destino não guarda nada e os montantes são derivados (`LIG:ListaMontante` varre o desenho). Um par escalar impede dois destinos (dupla contagem). `TALVEGUE` é componente da bacia, não montante, e fica em campo próprio.
   Uma única fonte de verdade; montantes calculados. Detalhes e integridade em `arquitetura.md` seção 15.
7. **Bacia continua sendo a bacia** (plugin `bacia`, cadastro no contorno, registro padrão `HYDRO-OBJ`; sem compatibilidade com formatos anteriores).
   Não altere o comportamento dela para acomodar objetos; use eventos e capacidades do catálogo.
8. Dados em entidades via `HYDRO:DadoLer/Gravar/Apagar` (extensão da entidade, com reserva central).
9. **Interface padrão do objeto** (portas e adapters; `docs/arquitetura.md` seção 18): todo objeto do desenho guarda `VERSAO TIPO NOME DESCRICAO ATRIB CARACT RESULT` (+ `PARAMS` só para ligar a outro objeto). `ATRIB` = o usuário define; `CARACT` = o desenho informa (ou o usuário digita, `CARACT-DEFS`, marcado em `CARACT/MANUAL`); `RESULT` = tudo que é calculado, em **grupos com nome** (`TC`, `VAZAO`, `HIDRAULICA`, `HIDROGRAMAS`) com os campos calculados **planos** na entrada (nunca uma lista `CALCULOS` nem sub-lista `RES`). Tipo novo herda o armazenamento da classe base `objetos.lsp`; **nenhum model declara `ARMAZENAMENTO`** (bacia e sarjeta herdam igual; `verificar.py` recusa). Personaliza por ganchos (`CARACTERIZA (en vinculos)`, `PARAMS-DEFS`, `CARACT-DEFS`, `PADROES`, `AO-REMOVER`) e **usa o cadastro genérico** (`OBJ:CadastrarCom`/`OBJ:CadastroInterativoTipo`, que termina em `OBJ:Salvar` e emite `objeto.cadastrado`); **cadastrar nunca calcula** (tc, vazão e hidráulica nascem no cálculo). Lê com `OBJ:RegistroDe`. Esqueleto: `docs/objeto_generico.lsp`; plano: `docs/plano_esqueleto_unico.md`. `ARMAZENAMENTO` (5 operações) só para quem guarda fora da extensão da entidade. Nenhum plugin guarda estrutura própria.

10. **Comandos padrão do objeto** (`docs/arquitetura.md` seção 18b): todo modelo em `plugins/models/` define
   `<TIPO>CAD` (cadastra/edita), `<TIPO>EDITA` (altera um campo), `<TIPO>S` (lista), `<TIPO>INFO` e `<TIPO>ZOOM` (localiza), chamando os
   fluxos genéricos `OPV:*` (`views/objetos_padrao_view.lsp`); `verificar.py` confere. `PARAMS` só guarda
   handles de outras entidades (vira vínculo, realçado por `OBJETOVINCULOS`). Cada plugin que guarda
   dados com referências **cadastra uma verificação** no catálogo `auditoria` (`HYDRO:RegAdd "auditoria"`)
   para o `HYDROAUDIT` achar e corrigir referências quebradas.

11. **RESULT por cenário** (`docs/plano_resultados_cenarios.md`, `arquitetura.md` 18e): `RESULT` = `(("TR25" . cenario) ...)`; cada cenário
   tem os grupos do tipo (bacia: `TC`, `PRECIPITACAO`, `ENTRADA`, `VAZAO`, `HIDROGRAMA`; sarjeta: `ENTRADA`, `VAZAO`, `ALTURA_LAMINA`...) com
   campos planos (`VALOR`, `METODO`, `INPUT` mínimo; nunca copiar `ATRIB`/`CARACT`) e o grupo reservado `CENARIO` (`TR`, `OBSOLETO`).
   O cenário nasce do TR (`TR25`; `CENARIO` define um nome: `TR25-Nome`). Calcular o cenário X usa o X dos montantes; um calculo
   inteiro e gravado com `OBJ:GravarCalculo` (uma gravacao). `CALCULA` do tipo devolve **grupos**.

12. **Resultado desatualizado** (`docs/arquitetura.md` 18d): editar `ATRIB`/`PARAMS`/`CARACT` de um objeto com `RESULT` grava
   `("OBSOLETO" . T)` (sem apagar o resultado); ligar/desligar/remover marcam o destino. Com `HYDRO.OBSOLETO.PROPAGA` = 1
   (`PROPAGAOBSOLETO`) a marca segue a jusante (`OBJ:Invalidar`, só a tag, sem recalcular). Só calcular remove a marca.
   `HYDRO.CARACT.AUTO` = 1 (`CARACTAUTO`) relê o desenho antes de calcular (`OBJ:AtualizaCaract`; bacia: `BAC:Preparar`).

## Regras de código AutoLISP (aprendidas aqui)

- **Prefixo por plugin** em todo símbolo público (`BAC:`, `LIG:`...); `_` para internos.
- **Declare todas as locais** depois da `/`. Escopo é **dinâmico**: variável não declarada vira global e vaza.
  Callbacks de `action_tile` (strings) enxergam as locais da função que chamou `start_dialog`.
- **`and` e `or` devolvem `T` ou `nil`, NUNCA o valor.** Já causou bug real:
  `(setq f (or (findfile a) (findfile b)))` dá `T`. Use `cond`/`if` + `setq` ou `HYDRO:FirstFile`.
  Use `and`/`or` só como teste.
- **Nunca grave pares com valor `nil`** em `ldata`/dados persistidos (`BAC:_Limpa`, `OBJ:_Limpa`).
- Comparar string que pode ser `nil`: use `equal`, não `=`.
- `getkword`/`getreal` devolvem `nil` no Enter; trate como "manter o padrão".
- `vl-catch-all-apply` em tudo que pode falhar (COM, `entget`, `ldata`, `handent` de apagado:
  use `HYDRO:EntValida`).
- Handles são **strings**; `handent` pode devolver ename de entidade apagada.
- Imagens de DCL só têm `vector_image` e `fill_image`; texto em imagem usa a fonte de traços
  do core (`HYDRO:ImgTexto`).
- Nada de `COMMAND` quando houver alternativa (`entmakex`, `vla-*`, `vlax-curve-*`).
- Arquivos novos em ASCII puro. Não use `*load-truename*` (não existe em AutoLISP).
- Nenhum módulo pode executar, no momento do load, algo que dependa de outro plugin
  (exceção: cadastro em catálogo, que exige `objetos.lsp` antes na ordem do manifesto).

## Como verificar

```
python build/verificar.py        # estática: parênteses, ASCII, chamadas sem defun, and/or, manifesto, DCL
```
No AutoCAD: `(load ".../Hydro.bundle/Contents/hydro.lsp")`, `HYDRODIR` para apontar a pasta,
`HYDRORELOAD` após editar, depois `(load ".../tests/teste_manual.lsp")` e `HYDROTESTE`.
Na pasta de código-fonte **não deixe `.fas`**: o carregador prefere `.fas` a `.lsp`.

## Ao fazer uma mudança

1. Siga os princípios acima; funções de cálculo com teste em `tests/teste_manual.lsp`
   (valores esperados calculados fora do AutoCAD, por exemplo em Python).
2. Objeto novo (skill `hydro-model`, `docs/template_objeto.lsp`): criar em `plugins/models/` com as **9 seções padrão na ordem** (Utilitários, Geometria, Ler/Gravar/Editar/Remover, Campos, Resultados, Cálculos, Resumo e formatação, Tipo no catálogo, Comandos e interação; `verificar.py` confere). O objeto traz seus comandos `c:` de linha de comando (para funcionar com um único .lsp) e uma função `XXX:ToString (en)` que devolve uma string (capacidade `"TOSTRING"`); a etiquetagem (texto no desenho) e os diálogos ficam em `views/`. Plugin novo: criar em `plugins/` (a parte de dialogo/comando vai em `views/<nome>_view.lsp`, feature `<nome>-view`), incluir em `HYDRO:Manifest` (`core/core.lsp`),
   terminar com `(HYDRO:Provide "nome" "versao")`, registrar rótulos (`HYDRO:SetLabel`).
3. Atualizar `docs/arquitetura.md` (eventos, chaves, formatos), README e a ordem do projeto VLX
   em `docs/compilacao.md`.
4. Rodar `python build/verificar.py`.
5. Fórmulas hidrológicas: cite a fonte nos comentários e registre a **faixa de validade**.
   Não invente fórmulas; se não tiver certeza, diga e pergunte.
6. **Todo comando `c:XXX` novo ganha um botao no painel** (`PNL:Acao`; os botoes dos comandos de models e
   plugins ficam em `views/painel_acoes.lsp`, para o objeto funcionar sem o painel; `requer` = feature do comando). O botao vira tambem item do menu e
   botao de barra de ferramentas. **Icone:** `resources/icons/<id>_16.bmp` e `_24.bmp` (ou deixe cair
   no icone do grupo; `python build/gerar_icones.py --so-faltantes`). O `verificar.py` avisa se faltar.

## Decisões já tomadas (não reabrir sem motivo)

- Estrutura de pastas com bundle (Autoloader) para distribuir; `.fas` por arquivo é o caminho de
  compilação recomendado; VLX só com **namespace compartilhado** (ver `docs/compilacao.md`).
- Raiz do conjunto: `HYDRO:*dir*`, escolha gravada no Registro com `HYDRODIR`.
- Exagero vertical das seções é **escolhido pelo usuário** (nunca automático); escala se ajusta, o exagero não.
- Cadastro **comum** e genérico para todo objeto (`OBJ:CadastrarCom`; `docs/plano_esqueleto_unico.md`): **cadastrar nunca calcula**;
  tc da bacia nasce em `BAC:Preparar`; atributos C e CN da bacia viram padrão dos métodos. Editar marca `OBSOLETO` (propaga a jusante
  com `HYDRO.OBSOLETO.PROPAGA`); `HYDRO.CARACT.AUTO` relê o desenho antes de calcular.
- **Objeto = mecanismo entrada → saída** (`docs/arquitetura.md` 15.4): entrada = soma das saídas gravadas dos
  montantes e maior tempo de saída; saída = precipitação sempre no maior tempo (bacias a montante reavaliadas
  por `VAZAO-EM`; racional composto exato). Tempo de saída da bacia: máximo se o montante não contribui ao talvegue,
  soma se contribui; sarjeta: `max tc_k + L/V`. Flag geral `HYDRO.VAZAO.PRESERVA` (`PRESERVAVAZAO`, padrão 1):
  `Q_saida = max(Q_entrada, Q_calc)`. Sarjeta/estrutura exigem montante. Calcular de montante para jusante.
- Calcular um objeto **recalcula os montantes antes** (ordem montante→jusante, capacidade `RECALCULA` ou
  `LIG:CalcularCore`, sem perguntas); objeto novo **oferece ligação** (`LIG:OferecerLigacao`); parâmetros têm
  **padrão do projeto** (`HYDRO.PADRAO.*`, comando `PADROES`) acima do último usado; `HYDRO.CALC.AUTO`
  (`CALCAUTO`) calcula sem perguntar. Detalhes em `arquitetura.md` 15.5.
- **Etiquetas dinâmicas e tabela viva** (`plugins/etiqueta.lsp`, `arquitetura.md` 18c): MTEXT/TABLE do desenho
  reescritos pelos eventos de cadastro/cálculo/ligação (nada de `FIELD`); modo `FIXO` = relatório (`OBJ:Resumo`),
  modo `MODELO` = campos `{CAMPO}` editáveis. Janela ancorável/modeless **não** existe em AutoLISP (DCL é modal;
  `PaletteSet` é .NET): a tabela viva é a alternativa escolhida.
- Uma origem tem um único destino (sem divisão de vazão) por enquanto.
- CSV para Excel pt-BR: separador `;` e vírgula decimal.
- Painel de botões = lançador modal gerado do catálogo `acao-painel`; o **menu da barra de menus**
  (`views/menu.lsp`) e as **barras de ferramentas** (`views/toolbar.lsp`, ícones em `resources/icons`) vêm do mesmo catálogo; ribbon fica a cargo do editor CUI (macros exportadas por
  `HYDROMACROS`); não escrever `.cuix` à mão.
- Ações que precisam do conjunto completo usam o evento `hydro.carregado` (não a ordem do manifesto).

## Pendências e ideias (ordem aproximada)

- Validar tudo no AutoCAD/Civil 3D (ver "Status honesto") e corrigir o que aparecer.
- Migrar `SARJ:Calcular` para usar o tipo `sarjeta` / `LIG:` (hoje coexistem; `plugins/sarjetas` está fora desta árvore e pode chamar `BAC:Obter`, que não existe mais).
- Propagação de hidrogramas pela rede (`PONTOS` somados em `ENTRADA`); hidrograma gerado automaticamente em `BACIA` (a decidir).
- Testar no AutoCAD o `RESULT` por cenário (ver Status honesto).
- Propagação de hidrogramas pela rede (hoje só soma de picos); hietograma em vez de chuva em bloco único.
- Fração de escoamento nas ligações (o formato do afluente já comporta).
- Ícones desenhados à mão no lugar dos gerados (o usuário se ofereceu a criar; basta usar os mesmos nomes).
- Mais tipos de objeto (bueiro, bacia de detenção, canal) via `docs/template_objeto.lsp`.
- Composição de sub-bacias; assinatura digital dos `.fas`/`.vlx`; testar o bundle em perfil limpo.
