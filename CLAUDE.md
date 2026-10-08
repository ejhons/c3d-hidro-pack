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
- `MONTANTE` em `PARAMS` (gravação via `OBJ:GravaRegistro`, `ldata` com `("31")` sem valor), `LIG:` sem o
  índice `HYDRO.LIGACOES` (varre `OBJ:Listar`), `BAC:_CalcularEGravar` composto, `VAZAO-EM` reavaliando o método,
  `LIGAR` perguntando o flag, sarjeta recebendo sarjeta em cadeia. Desenhos antigos com `HYDRO-LIG` **não migram**.
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
6. **O receptor guarda a ligação**: campo `MONTANTE` do `PARAMS` dele, dicionário `(handle . flag)` com flag T = "contribui diretamente ao talvegue" (nil = ausente); a origem não guarda nada. `TALVEGUE` é componente da bacia, não montante, e fica em campo próprio.
   Uma única fonte de verdade; destino calculado. Detalhes e integridade em `arquitetura.md` seção 15.
7. **Bacia continua sendo a bacia** (plugin `bacia`, cadastro no contorno, registro padrão `HYDRO-OBJ`; sem compatibilidade com formatos anteriores).
   Não altere o comportamento dela para acomodar objetos; use eventos e capacidades do catálogo.
8. Dados em entidades via `HYDRO:DadoLer/Gravar/Apagar` (extensão da entidade, com reserva central).
9. **Interface padrão do objeto** (portas e adapters; `docs/arquitetura.md` seção 18): todo objeto do desenho guarda `VERSAO TIPO NOME DESCRICAO ATRIB CARACT RESULT` (+ `PARAMS` só para ligar a outro objeto). `ATRIB` = o usuário define; `CARACT` = o desenho informa; `RESULT` = tudo que é calculado, em **grupos com nome** (`TC`, `VAZAO`, `HIDRAULICA`, `HIDROGRAMAS`) com os campos calculados **planos** na entrada (nunca uma lista `CALCULOS` nem sub-lista `RES`). Tipo novo herda o armazenamento da classe base `objetos.lsp`; só declara `ARMAZENAMENTO` (5 operações; LER devolve o registro padrão) se precisar de gravação, índice ou remoção próprios, como a bacia. Nenhum plugin guarda estrutura própria.

10. **Comandos padrão do objeto** (`docs/arquitetura.md` seção 18b): todo modelo em `plugins/models/` define
   `<TIPO>CAD` (cadastra/edita), `<TIPO>S` (lista), `<TIPO>INFO` e `<TIPO>ZOOM` (localiza), chamando os
   fluxos genéricos `OPV:*` (`views/objetos_padrao_view.lsp`); `verificar.py` confere. `PARAMS` só guarda
   handles de outras entidades (vira vínculo, realçado por `OBJETOVINCULOS`). Cada plugin que guarda
   dados com referências **cadastra uma verificação** no catálogo `auditoria` (`HYDRO:RegAdd "auditoria"`)
   para o `HYDROAUDIT` achar e corrigir referências quebradas.

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
- Cadastro **comum** de bacias e sarjetas (`BAC:Obter`); atributos C e CN da bacia viram padrão dos métodos.
- **Objeto = mecanismo entrada → saída** (`docs/arquitetura.md` 15.4): entrada = soma das saídas gravadas dos
  montantes e maior tempo de saída; saída = precipitação sempre no maior tempo (bacias a montante reavaliadas
  por `VAZAO-EM`; racional composto exato). Tempo de saída da bacia: máximo se o montante não contribui ao talvegue,
  soma se contribui; sarjeta: `max tc_k + L/V`. Flag geral `HYDRO.VAZAO.PRESERVA` (`PRESERVAVAZAO`, padrão 1):
  `Q_saida = max(Q_entrada, Q_calc)`. Sarjeta/estrutura exigem montante. Calcular de montante para jusante.
- Uma origem tem um único destino (sem divisão de vazão) por enquanto.
- CSV para Excel pt-BR: separador `;` e vírgula decimal.
- Painel de botões = lançador modal gerado do catálogo `acao-painel`; o **menu da barra de menus**
  (`views/menu.lsp`) e as **barras de ferramentas** (`views/toolbar.lsp`, ícones em `resources/icons`) vêm do mesmo catálogo; ribbon fica a cargo do editor CUI (macros exportadas por
  `HYDROMACROS`); não escrever `.cuix` à mão.
- Ações que precisam do conjunto completo usam o evento `hydro.carregado` (não a ordem do manifesto).

## Pendências e ideias (ordem aproximada)

- Validar tudo no AutoCAD/Civil 3D (ver "Status honesto") e corrigir o que aparecer.
- Migrar `SARJ:Calcular` para usar o tipo `sarjeta` / `LIG:` (hoje coexistem).
- Propagação de hidrogramas pela rede (hoje só soma de picos); hietograma em vez de chuva em bloco único.
- Fração de escoamento nas ligações (o formato do afluente já comporta).
- Ícones desenhados à mão no lugar dos gerados (o usuário se ofereceu a criar; basta usar os mesmos nomes).
- Mais tipos de objeto (bueiro, bacia de detenção, canal) via `docs/template_objeto.lsp`.
- Composição de sub-bacias; assinatura digital dos `.fas`/`.vlx`; testar o bundle em perfil limpo.
