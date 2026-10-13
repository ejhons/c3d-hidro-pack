# Plano: RESULT por cenários

Rascunho para aprovação. Nada aqui foi implementado nem testado no AutoCAD.
Continua `docs/plano_esqueleto_unico.md` (etapas 1 a 5, já feitas).

## Decisões (do usuário)

1. **RESULT é organizado por cenário.** Cada objeto tem seus grupos específicos (bacia: `TC`,
   `PRECIPITACAO`, `VAZAO`, `HIDROGRAMA`...; sarjeta: `VAZAO`, `ALTURA_LAMINA`...). O cenário é só o
   contêiner; quem define os grupos é o tipo.
2. **Nome do cenário:** livre, escolhido pelo usuário; **padrão = o tempo de retorno** (`"TR25"`).
3. **Propagação entre objetos é por cenário:** calcular o cenário `X` de um objeto usa o cenário `X`
   dos montantes (e os recalcula antes, se for o caso), como hoje faz com `METODO + TR`.
4. **`ENTRADA` (o que chega dos montantes) é um grupo dentro do cenário.**
5. **Resultado desatualizado é por cenário:** editar o objeto marca todos os cenários dele; calcular
   o cenário `X` limpa só o `X`. Substitui a marca única `("OBSOLETO" . T)` do registro.
6. Sem compatibilidade com o formato antigo (como nos demais): desenho antigo precisa recalcular.

## Formato

```
("RESULT" .
  (("TR25" .
     (("CENARIO"      ("TR" . 25.0) ["OBSOLETO" . T])      ; metadados (grupo reservado)
      ("TC"           ("VALOR" . 15.0) ("METODO" . "kirpich") ("INPUT" ...))
      ("PRECIPITACAO" ("VALOR" . 21.3) ("I" . 150.2) ("P" . 35.5) ("DUR" . 15.0))
      ("ENTRADA"      ("VALOR" . 4.2) ("TC" . 18.0) ("AREA" . 250000.0))
      ("VAZAO"        ("VALOR" . 9.88) ("METODO" . "racional") ("TC" . 18.0) ("VOLUME" . 2556.0) ...)
      ("HIDROGRAMA"   ("TIPO" . "scs") ("QP" . 9.9) ("TP" . 12.0) ("PONTOS" . ((t . q) ...)))))
   ("TR10" . (...))))
```

- Dentro de cada grupo os campos são **planos**; `"VALOR"` é o número principal (unidade
  documentada pelo tipo: `VAZAO` m3/s, `TC` min, `ALTURA_LAMINA` m).
- `"CENARIO"` é reservado: `TR` (necessário porque o nome é livre), `OBSOLETO`, e opcionalmente
  `DESCRICAO`.
- `METODO` deixa de ser identidade: vira campo do grupo. Dentro de um cenário há **um** resultado
  por grupo; calcular de novo com outro método substitui.
- `TC` aparece em cada cenário (duplicado), porque o tc de saída depende do cenário (maior entre o
  próprio e o dos montantes).

## INPUT (antes `PARAMS` dentro do grupo de resultado)

Para não confundir com o `PARAMS` do registro (vínculos) nem inflar o cenário, o que o cálculo usou
passa a se chamar **`INPUT`** e guarda **só o que não está no objeto**: os parâmetros que o usuário
informou para o método naquele cálculo (ex.: parâmetros do SCS ou do método de tc). `C`, `CN`, área,
comprimento etc. **não** são copiados: estão em `ATRIB`/`CARACT`, e se mudarem o cenário já fica
obsoleto. Regra geral: o grupo de resultado guarda **saídas** + `METODO` + `INPUT` mínimo; nunca
cópias de `ATRIB` ou `CARACT`.

## Hidrograma

- Um hidrograma por cenário, grupo `HIDROGRAMA` com campos planos (`TIPO`, `QP`, `TP`, `TB`,
  `VOLUME`, `PASSO`, `PONTOS`). `PONTOS` é um campo cujo valor é lista; nada de exceção.
- **O tipo é definido na bacia** (`ATRIB` `HIDROGRAMA-TIPO`, lista dinâmica do catálogo de tipos), e o
  cenário, ao calcular, usa o que está definido nela. Outro tipo para a mesma bacia = mudar o atributo
  ou usar outro cenário.
- Propagação futura: objetos que recebem montantes terão `ENTRADA` com `PONTOS` (soma dos hidrogramas
  dos montantes, defasados) e `HIDROGRAMA` como saída (bacia: do método; sarjeta/trecho: entrada
  propagada). Mesmo desenho de `VAZAO` (hoje soma de picos).

## API (em `objetos.lsp`)

| Função | Faz |
|---|---|
| `OBJ:CenarioPadrao tr` | nome padrão a partir do TR (`25.0` -> `"TR25"`, `2.5` -> `"TR2.5"`) |
| `OBJ:CenarioAtual` | cenário em uso (`HYDRO.CENARIO.ATUAL`; padrão = o do último TR) |
| `OBJ:CenariosDe en` | nomes dos cenários do objeto |
| `OBJ:ResultGrupoDe en cenario grupo` | alist plana do grupo (substitui a versão sem cenário) |
| `OBJ:GravarResultado en cenario grupo campos` | grava/substitui o grupo no cenário |
| `OBJ:ConcluiCalculo en cenario` | limpa o `OBSOLETO` do cenário |
| `OBJ:Obsoleto en [cenario]` | marca de um cenário (sem argumento: algum cenário) |
| `OBJ:Invalidar en` | marca todos os cenários do objeto e, com `HYDRO.OBSOLETO.PROPAGA`, os de jusante |

Os comandos de cálculo perguntam `Cenário <TR25>` (Enter = o atual); no modo `CALCAUTO`, usam o atual.

## O que muda (impacto)

`OBJ:ResultGrupoDe` (10 usos), `OBJ:GravarResultado` (7), `BAC:Vazao/Tc/Hidrogramas/_SetResult`
(~64 usos) em `objetos`, `ligacao`, `bacia`, `sarjeta`, `etiqueta`, `hidrograma`, `hidrograma_view`,
`bacia_tabela`, testes. Campos de etiqueta (`{QP}`, `{TC}`, `{E.QP}`, `{H.LAMINA}`) passam a ler o
cenário atual (ou `{TR25.QP}`).

## Andamento

- Etapa 1 **feita** (só análise estática): formato, API em `objetos.lsp`, obsoleto por cenário, testes puros. As etapas 2 a 5 ainda não migraram os chamadores (`ligacao`, `sarjeta`, `bacia`, `hidrograma`, `etiqueta`, tabelas), então o cálculo ponta a ponta fica fora do ar até lá.

- Etapa 2 **feita** (só análise estática): ligação e sarjeta por cenário (ver `arquitetura.md` 18e). Nome do cenário: TR + nome opcional (`TR25-Nome`), comando `CENARIO` (Enter = só o TR).

- Etapa 3 **feita** (só análise estática): bacia por cenário (`TC`, `PRECIPITACAO`, `ENTRADA`, `VAZAO`); hidrograma fica para a etapa 4 (`BAC:Hidrogramas`/`BAC:_SetResult` ainda no formato antigo e não devem ser usados com o novo `RESULT`).

- Etapa 4 **feita** (só análise estática): hidrograma por cenário, tipo definido na bacia (`HIDROGRAMA-TIPO`).

- Etapa 5 **feita** (só análise estática): etiquetas e tabela viva por cenário, aviso de desatualizado, eventos `objeto.obsoleto`/`objetos.obsoletos`. Plano concluído.

## Etapas sugeridas

1. **Núcleo:** formato, API acima, obsoleto por cenário, testes de funções puras.
2. **Ligação e sarjeta:** `LIG:CalcularCore`/`Entrada`/`VazaoMontante` por cenário; grupos da sarjeta.
3. **Bacia:** `TC`, `PRECIPITACAO`, `VAZAO` por cenário; `BAC:Preparar`/`_CalcularEGravar`.
4. **Hidrograma** (estrutura do grupo, ver pontos em aberto).
5. **Etiquetas, tabelas e comandos** (perguntar cenário; campos).
6. **Docs.**

## Decisões fechadas nesta conversa

- Hidrograma como grupo plano por cenário; tipo em `ATRIB` da bacia.
- `PARAMS` dos resultados renomeado para `INPUT`, mínimo (sem copiar `ATRIB`/`CARACT`).
- Sem migração: desenho antigo recalcula.
