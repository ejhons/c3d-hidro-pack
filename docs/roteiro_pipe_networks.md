# Roteiro: compatibilização com Pipe Networks do Civil 3D

Rascunho para avaliação. Nada aqui foi implementado nem testado no AutoCAD/Civil 3D.

## Objetivo e limites

Aproveitar o que o Pipe Networks já sabe (geometria, cotas, peças do catálogo, conexões entre
tubos e estruturas) para **preencher** e **ligar** os objetos do Hydro, do mesmo jeito que a área
de uma polilinha fechada alimenta a área da bacia.

- **Sem dependência:** o Hydro continua funcionando sem Pipe Networks. Tudo que lê o Civil 3D fica
  numa camada opcional (`HYDRO:Has "c3d"`); sem ela, nada muda.
- **Sem tipo novo:** `tubo`, `escada` e `estrutura` passam a aceitar `AECC_PIPE` / `AECC_STRUCTURE`.
  Para o Hydro, um tubo do Civil **é o mesmo `tubo`** de uma `LINE` ou `POLYLINE` 3D: mesmo
  registro, mesmo cálculo, mesmos comandos. A única diferença é **como se capturam** comprimento,
  cotas, declividade e seção (`CARACT` e padrões de `ATRIB`): da curva do AutoCAD ou das propriedades
  do Pipe. Os tipos básicos `tubo-c3d` e `trecho` saem (o `tubo` cobre os dois casos).
- **O Hydro continua dono da hidrologia e da hidráulica:** escoamento superficial, captação,
  dissipação, cenários e resultados são nossos. Do Civil só lemos (por enquanto não escrevemos nada
  de volta no Pipe Networks).
- **O usuário prevalece:** valor digitado (`CARACT/MANUAL`, `ATRIB` editado) não é sobrescrito pelo
  que vem do Civil.

## Arquitetura proposta

```
models/tubo.lsp, models/estrutura.lsp     (sem saber de Civil 3D)
        |  CARACTERIZA / PADROES consultam o catálogo "adaptador-entidade" pelo nome DXF
        v
plugins/c3d.lsp  (C3D:, opcional)          leitura segura via ActiveX (vl-catch-all-apply)
        |  registra adaptadores para "AECC_PIPE" e "AECC_STRUCTURE"
        v
Civil 3D (AeccPipe, AeccStructure)         geometria, cotas, peça, conexões
```

- **Catálogo `adaptador-entidade`** (aberto/fechado): `(HYDRO:RegAdd "adaptador-entidade" "AECC_PIPE" ...)`
  com funções `GEOMETRIA`, `SECAO`, `CONEXOES`, `PECA`. Os models perguntam ao catálogo pelo DXF da
  entidade; se não houver adaptador, seguem como hoje (curva do AutoCAD). Um adaptador futuro para
  outra fonte (ex.: rede importada de outro programa) entra do mesmo jeito.
- **Comandos e diálogos** da compatibilização ficam em `views/c3d_view.lsp`.
- **Sem reatores nem atualização automática:** a sincronização é **preguiçosa** (lazy), feita só na
  hora de calcular (F6), por desempenho e para não reagir a cada edição do Civil.

## Fases

### F0. Diagnóstico no Civil 3D (antes de tudo)

Tudo no Hydro até aqui é análise estática; a camada do Civil é a parte mais incerta. Primeiro um
comando de diagnóstico (`HYDROC3DINFO`) que, para um tubo e uma estrutura selecionados, lista o
que o ActiveX realmente expõe na versão do usuário. Confirmar:

- nomes DXF (`AECC_PIPE`, `AECC_STRUCTURE`) e se `vlax-ename->vla-object` dá o objeto do Pipe;
- propriedades de tubo: comprimento 2D/3D, cotas de **fundo** (invert) inicial e final, declividade,
  diâmetro/largura/altura interna, forma da seção, família e tamanho da peça, estruturas inicial e
  final e o **sentido do escoamento definido no Civil** (decisão 1: é ele que manda);
- propriedades de estrutura: cota de tampa e de fundo, família/tamanho, tubos conectados (quantos e
  quais, com o lado da conexão);
- unidades (m ou mm) e se gravar na extensão de `AECC_PIPE`/`AECC_STRUCTURE` sobrevive a salvar,
  reabrir, trocar a peça e regenerar a rede (já está no "Status honesto").

Entregável: o comando e uma tabela de nomes confirmados em `arquitetura.md`. Rodar `HYDROTESTE`
junto.

**Ponto de partida: `civilinfo.lsp`** (biblioteca `CIV:` trazida pelo usuário, só leitura). Já cobre
quase tudo da F0: `CIVCAPS`, `CIVTUBO`, `CIVESTRUTURA`, `CIVSONDAR` (testa nomes candidatos e faz o
`vlax-dump-object`), `CIVREDES` (grafo e exutórios) e `CIVRELATORIO` (grava tudo num `.txt`). Uso
proposto:

1. Rodar **como está**, fora do Hydro (ferramenta de diagnóstico, não entra no manifesto), e trazer
   o `civilinfo_relatorio.txt` e o `CIVSONDAR` de um tubo e de uma estrutura. Isso confirma as
   PREMISSAS marcadas no arquivo e substitui o `HYDROC3DINFO`.
2. Antes de rodar, corrigir três usos de `or` como valor (regra do projeto: `or` devolve `T`):
   `CIV:Redes` (`(or (CIV:NomeRede o) "(sem rede)")`), `CIV:SecaoDoRecord` (`"wall"`) e
   `c:CIVCATALOGO` (`getfiled` recebe `T` como pasta).
3. Na F1, o `plugins/c3d.lsp` aproveita as funções de leitura (`_Prop`, `Ponto`, `Tubo`,
   `Estrutura`, `Grafo`, `RecCampo`, `SecaoDoRecord`) adaptadas às regras do Hydro: prefixo `C3D:`,
   sem `vl-bb-set` (estado em `HYDRO:Get/Set` ou nenhum), valores convertidos para metros, e
   **leitura por entidade** (o cálculo nunca faz `ssget "X"` de `AECC_*`; a varredura fica para o
   `LIGARREDE` e o diagnóstico).

**Resultado do primeiro `CIVSONDAR` (tubo, 2026-10-13).** Bueiro duplo `BDTC 600 x 75 mm`
(família `BDTC`, descrição `2%%c 600`), desenho em metros.

| Item | Confirmado | Observação |
|---|---|---|
| Objeto | `AeccDbPipe` / `IAeccPipe` | `vlax-ename->vla-object` funciona |
| Comprimento | `Length2D`, `Length3D` (m) | |
| Declividade | `Slope` = 0.000217 | sinal x sentido a confirmar |
| Seção | `InnerDiameterOrWidth` 0.6, `InnerHeight` 0.6, `WallThickness` 0.075 | **por célula**: a peça é dupla |
| Forma | `SweptShape` = 2 numa peça circular | tabela do enum a confirmar com uma peça retangular |
| Sentido | `FlowDirection` (RO) = 1, `FlowDirectionMethod` = 1 | significado dos valores a confirmar |
| Conexões | `StartStructure`, `EndStructure` (objetos), `Connectors` | |
| Pontas | `StartPoint`, `EndPoint`, `Position`: objetos (`IAeccPoint3d`?) | leitura de X/Y/Z a confirmar no `CIVTUBO` |
| Cota de fundo | **não há propriedade direta** | derivar de `Z - InnerHeight/2` (a confirmar) |
| Peça | `PartFamily` (`Name`, `Guid`, `Type`, `SizeFilters`), `PartSizeName` | chave do mapa da F3 |
| Registro da peça | `PartDataRecord`: `Count` 28, `Item`, `Find`, `FindByContext`, `FindByContextAndIndex` | campos a listar no `CIVTUBO` |
| Extras | `HGLUp/Down`, `EGLUp/Down` (graváveis), `MinimumCover`/`MaximumCover`, `Surface` | HGL/EGL: futuro (F7) |
| Extensão | `HasExtensionDictionary` = 0 | o `ldata` do Hydro vai criar a primeira; testar salvar/reabrir |

Consequência: **o `tubo` precisa de número de células** (bueiro duplo/triplo). Hoje o catálogo de
seções do tubo não tem esse campo; entra na F2/F3 (Manning por célula, vazão dividida igualmente,
`N` lido do `PartDataRecord`, ex.: `Catalog_SubType`, ou digitado).

Pontos do `civilinfo` a confirmar com os dumps:
- Ler um tubo não exige o `AeccApplication`: `vlax-ename->vla-object` basta. O `CIV:RaizCivil`
  (laço por ProgIDs) só é preciso para part lists; fica fora do caminho do cálculo.
- Cota de fundo derivada como `Z do eixo - altura/2`: conferir se `StartPoint/EndPoint` são o eixo e
  se não existe propriedade direta de invert.
- `CIV:_RecLen` assume "> 10 = mm": frágil; usar a unidade declarada da coluna (`CIV:TabelaM`) ou
  `INSUNITS`.
- `FlowDirection`: nome e valores (decisão 1 depende dele).
- `Catalog_SubType` (`Duplo`/`Triplo`), `Misula_`, `Espacamento_`, `TipoConduto` são do catálogo
  próprio do usuário: úteis na F3 (número de células, mísula), mas não podem ser exigidos.

### F1. Camada de adaptação (`plugins/c3d.lsp`)

Funções puras sobre o objeto, todas protegidas, devolvendo `nil` no que não conseguir ler:

| Função | Devolve |
|---|---|
| `C3D:EhRede en` | T se é tubo ou estrutura do Pipe Networks |
| `C3D:GeometriaTubo en` | `COMP`, `COTA-INI`, `COTA-FIM` (fundo), `DECL` |
| `C3D:SecaoTubo en` | forma (circular/retangular...), `D` ou `b`/`h`, unidades convertidas para m |
| `C3D:PecaDe en` | família e tamanho da peça (chave do mapeamento da F3) |
| `C3D:ConexoesTubo en` | estrutura inicial e final (handles) |
| `C3D:ConexoesEstrutura en` | tubos conectados, com o lado de cada um |
| `C3D:CotasEstrutura en` | tampa e fundo |

Registra os adaptadores no catálogo. Testes: funções de conversão e decisão (puras), com dados
literais; a leitura do ActiveX só no AutoCAD.

### F2. `tubo`, `escada` e `estrutura` aceitam objetos do Civil

- `ACEITA` do `tubo` e da `escada` ganha `AECC_PIPE`; o da `estrutura` já tem `AECC_STRUCTURE`.
  Uma escada desenhada como tubo do Civil usa a seção retangular da peça como calha.
- `CARACTERIZA` do tubo consulta o adaptador: comprimento e declividade pelas cotas de fundo do
  Civil (mais corretas que o Z da linha). Estrutura ganha `CARACT` com cotas de tampa e fundo
  (base para perda de carga e, no futuro, linha piezométrica).
- `PADROES` sugerem a seção (F3) e o tipo de estrutura (F5) a partir da peça.
- Remover os tipos básicos `tubo-c3d` e `trecho` (`objetos_tipos.lsp`); o `tubo` passa a ser o
  único objeto para tubos, do Civil ou não. Dentro do `tubo`, a captura escolhe a fonte pelo DXF:
  `AECC_PIPE` → adaptador; `LINE`/`POLYLINE` → `vlax-curve-*` (como hoje). O resto do model não
  sabe a diferença.

### F3. Peças do catálogo do Civil ↔ catálogos de seções do Hydro

- Tabela de correspondência `HYDRO.MAPA.PECAS`: (família, tamanho) → id de seção do catálogo de
  tubo/canal (e n de Manning por material).
- Peça sem correspondência: o cadastro oferece **criar a seção** a partir das dimensões lidas
  (circular D; retangular b × h) e guarda a correspondência.
- Comando para revisar o mapa (`MAPAPECAS`) e auditoria: tubo cuja peça mudou no Civil e a seção
  do Hydro ficou diferente (oferece atualizar e marca obsoleto).
- Formas que o Hydro ainda não calcula (elíptica, ovoide) geram aviso, não erro de cadastro.

### F4. Ligações automáticas pela topologia da rede

Comando `LIGARREDE`, por **seleção** ou pela **rede inteira** do Civil (decisão 4: os dois):

1. Cadastra em lote, com padrões, os tubos e estruturas ainda sem cadastro (pergunta antes).
2. Deduz o `JUSANTE` de cada objeto: tubo → estrutura de jusante; estrutura → tubo de saída.
   O sentido é o **do escoamento definido no Civil** (decisão 1).
3. Mostra a prévia com `LIGACOESVER` e um resumo (quantas novas, quantas iguais, conflitos)
   **antes** de gravar.
4. Grava pelo `LIG:Conectar` de hoje (mesmas regras de integridade, obsolescência e eventos).

Regras: ligação existente feita à mão não é trocada sem perguntar; estrutura com mais de um tubo
de saída (bifurcação) não tem destino único: vira aviso e o usuário escolhe, porque o Hydro não
divide vazão; ciclos detectados pela validação que já existe. O comando é idempotente: rodar de
novo só mostra o que mudou.

### F5. Escoamento superficial e captação na rede

- Tipo de estrutura sugerido pela família da peça (`HYDRO.MAPA.ESTRUTURAS`: família → tipo do
  catálogo, ex.: "Boca de lobo" → classe `boca-lobo`, "PV" → `passagem`).
- Bacias e sarjetas → boca de lobo/PV: sugestão por proximidade (fim do talvegue ou da sarjeta perto
  da estrutura), sempre confirmada pelo usuário.
- Dissipadores e escadas na saída da rede: a estrutura de saída (ala) pode ganhar um tipo
  dissipador; a lâmina e a velocidade do tubo de chegada já alimentam o dissipador.

### F6. Sincronização preguiçosa (lazy) e cálculo só do que mudou

Decisão 2: nada atualiza sozinho. Na hora de calcular um objeto (que hoje já recalcula os
montantes antes), o Hydro faz duas passadas pela rede a montante:

1. **Conferência.** Para cada objeto, relê do desenho/Civil os parâmetros que entram no cálculo
   (geometria, cotas, peça/seção, conexão de jusante) e compara com o que está gravado (`CARACT`,
   `ATRIB` derivado da peça, `JUSANTE`). Se algo mudou: atualiza o registro, marca o cenário como
   desatualizado e **invalida a jusante** (`OBJ:Invalidar`, que já existe). Comparação barata, sem
   cálculo hidráulico.
2. **Cálculo.** `LIG:RecalcularMontantes` passa a pular o montante cujo cenário está calculado e
   **não** desatualizado; só recalcula os marcados (e os que ainda não têm o cenário). Hoje ele
   recalcula todos.

Controle por variável do sistema (comando próprio, com botão): `HYDRO.CALC.SO-DESATUALIZADOS`
(1 = calcula só o desatualizado; 0 = recalcula tudo, como hoje) e a conferência continua ligada ao
`HYDRO.CARACT.AUTO`. Mudança de topologia (tubo que trocou de estrutura no Civil) entra na
conferência: o `JUSANTE` do Hydro é corrigido e as duas cadeias (antiga e nova) são invalidadas.

Auditoria `rede-c3d` (`HYDROAUDIT`) para o que a conferência não resolve sozinha: objeto do Civil
apagado, bifurcação nova, peça sem correspondência de seção.

### F7. Futuro (fora deste roteiro)

Linha piezométrica com perdas nas estruturas (usa as cotas da F2), verificação de recobrimento e
velocidades por norma, e **property sets** do Civil alimentados pelos resultados (decisão 5: úteis
para os rótulos do Civil, ficam para depois).

## Decisões tomadas (2026-10-13)

1. **Sentido do escoamento:** o definido no Civil.
2. **Atualização:** nunca automática; sincronização preguiçosa na hora de calcular, só do que mudou,
   controlada por variável do sistema (F6). Peça trocada no Civil entra por essa conferência.
3. **Objetos:** nenhum tipo novo; `tubo-c3d` e `trecho` saem; `tubo` e `escada` aceitam tubos do
   Civil. Um tubo do Civil é visto como uma linha ou polilinha 3D; só muda a captura dos dados.
4. **`LIGARREDE`:** por seleção e pela rede inteira.
5. **Property sets:** futuro (F7).
6. **Diagnóstico:** a F0 parte do `civilinfo.lsp` do usuário (ferramenta à parte, fora do manifesto).

## Riscos

- API ActiveX do Civil muda de versão; nomes de propriedades e unidades precisam da F0.
- Gravar dados na extensão de objetos do Civil e o comportamento ao regenerar/trocar peça.
- Desempenho em redes grandes (leitura de `ldata` e varredura de conexões); por isso sob demanda.
- Bifurcações e redes em malha não cabem na regra de destino único (avisos, não solução).

## Ordem sugerida

F0 → F1 → F2 → F4 → F6 → F3 → F5. A F4 (ligação automática) vem antes do mapeamento fino de peças
porque é o maior ganho e só precisa de geometria e conexões; a F6 vem logo depois porque é ela que
torna o cálculo de redes grandes viável. O mapeamento (F3) pode começar com a seção criada a partir
das dimensões lidas.
