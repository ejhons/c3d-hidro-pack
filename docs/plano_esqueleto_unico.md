# Plano: esqueleto único para todos os objetos

Rascunho para aprovação. Nada aqui foi implementado nem testado no AutoCAD.
Referência viva do esqueleto: `docs/objeto_generico.lsp`.

## Decisões

1. **Cadastrar nunca calcula.** Cadastro grava só `ATRIB`, `CARACT` e `PARAMS`. tc, vazão e
   hidráulica nascem em `CALCULAOBJETO` e vão para `RESULT`.
2. **tc na bacia:** o *método* e os parâmetros dele ficam em `ATRIB` (`TC-METODO`, `TC-PARAMS`,
   ou `TC-USUARIO` para valor manual). O número calculado fica em `RESULT/TC`.
3. **Vínculos declarados.** Entidades de apoio (talvegue da bacia) entram em `PARAMS` e são
   descritas por uma definição no tipo (`"PARAMS-DEFS"`: `chave rotulo aceita [obrigatorio]`,
   `aceita` = nomes DXF e/ou ids de tipo). O cadastro percorre a lista e pede cada seleção;
   Enter pula.
4. **Campos manuais.** O que o desenho não informa (vínculo pulado, ponto fora da superfície) é
   perguntado ao usuário via `"CARACT-DEFS"` e marcado em `CARACT/MANUAL`, para uma nova
   caracterização não sobrescrever.
5. **Um único cadastro interativo:** `OBJ:CadastroInterativoTipo`. O `CARACTERIZA` passa a
   receber `(en vinculos)`.

6. **Edição e resultado desatualizado.** Editar um objeto (`ATRIB`, `PARAMS` ou `CARACT` que mudou)
   marca o objeto como desatualizado: campo `("OBSOLETO" . T)` no registro, sem apagar o `RESULT`.
   `OBJ:GravarResultado` limpa a marca. Etiqueta, tabela e `ToString` mostram "resultado
   desatualizado" enquanto ela existir. Só marca se algo realmente mudou (compara o registro novo
   com o antigo). **Nenhum recálculo na edição**: recalcula só quando alguém chama o cálculo do
   objeto ou de outro que o use como montante (o cálculo já recalcula os montantes antes).
7. **Propagação para jusante (só a marca).** Como a origem guarda `JUSANTE`, `OBJ:Invalidar en`
   marca o objeto e segue pela cadeia de `JUSANTE` até o fim, gravando apenas a tag. Custo: uma
   leitura e uma gravação de `ldata` por objeto da cadeia. Proteções: para ao encontrar um objeto
   que já está `OBSOLETO` (o resto da cadeia já foi marcado antes) e guarda os handles visitados
   contra ciclo. Chave de projeto `HYDRO.OBSOLETO.PROPAGA` (comando `PROPAGAOBSOLETO`, padrão 1,
   como `PRESERVAVAZAO`): 0 marca só o objeto editado.
8. **Comando `<TIPO>EDITA`.** Pergunta qual campo alterar e pergunta só esse. Fluxo genérico
   `OPV:EditaCampo` (como os demais `OPV:*`); cada modelo define uma linha
   `(defun c:<TIPO>EDITA () (<PFX>:_Padrao 'OPV:EditaCampo))`. Fluxo: seleciona o objeto →
   lista os campos de `ATRIB-DEFS`, `PARAMS-DEFS` (Trocar/Remover vínculo) e `CARACT-DEFS`
   (valor manual) com o valor atual → o usuário escolhe um → pergunta só ele → grava com
   `OBJ:Cadastrar` (recaracteriza, marca obsoleto e propaga conforme item 7). Ganha botão no
   painel (regra do projeto para todo `c:`) e entra em `verificar.py` junto de CAD/S/INFO/ZOOM.

## Fluxo padrão

selecionar entidade → pedir vínculos (`PARAMS-DEFS`) → `CARACTERIZA` → perguntar `ATRIB` e
`CARACT` faltantes → `OBJ:Salvar` (evento `objeto.cadastrado`).

## O que sai de `bacia.lsp`

| Hoje | Destino |
|---|---|
| `BAC:CadastroInterativo`, `BAC:EditarCadastro`, `BAC:_SelTalvegue`, `BAC:_PedeNome/_PedeAtrib` | fluxo genérico `OBJ:CadastroInterativoTipo` + `PARAMS-DEFS` |
| `BAC:Cadastrar` (monta registro com `TC`) | `OBJ:Cadastrar` genérico |
| `BAC:Obter` (auto-cadastra e calcula tc; usado fora) | removido; chamadores usam `OBJ:Ler` / `OBJ:CaractDe` e pedem cálculo explícito |
| `BAC:_EscolheTc` (pergunta método no cadastro) | vira definição de `ATRIB` (`TC-METODO`, `TC-PARAMS`) |
| `BAC:CalcularTc` chamado no cadastro | chamado só dentro do cálculo da bacia (`CALCULA`/`RECALCULA`) |
| `BAC:Ler`, `BAC:Nome/Atrib/Caract/Params` | `OBJ:RegistroDe`, `OBJ:AtribDe`, `OBJ:CaractDe`... (sem duplicar) |
| `c:BACIACAD/BACIAS/BACIAINFO/BACIAZOOM` | mesmo padrão `<TIPO>CAD/S/INFO/ZOOM` da sarjeta (`OPV:*`) |

Fica na bacia o que é só dela: fórmulas de tc, composição racional, hidrogramas, regra de destino.

## Mudanças no núcleo (`objetos.lsp`)

- Capacidades novas: `"PARAMS-DEFS"`, `"CARACT-DEFS"`; `CARACTERIZA` com `(en vinculos)`
  (sarjeta ignora o 2º argumento).
- `OBJ:CadastroInterativoTipo` percorre `PARAMS-DEFS` e completa `CARACT-DEFS`.
- `OBJ:Cadastrar` compara `ATRIB`/`PARAMS`/`CARACT` novos com os gravados e grava `OBSOLETO`;
  `OBJ:GravarResultado` remove. Leitura: `OBJ:Obsoleto en`. `OBJ:Invalidar en` faz a propagação
  pela cadeia de `JUSANTE` (item 7); `HYDRO.OBSOLETO.PROPAGA` e `PROPAGAOBSOLETO` ficam aqui.
- Atualizar `verificar.py` (models sem `CadastroInterativo` próprio) e `arquitetura.md` 18/18b.

## Andamento

- Etapa 1 **implementada** (só análise estática + testes de `OBJ:_Igual`/`_MudouCadastro` em `HYDROTESTE`): capacidades, `OBJ:CadastrarCom`, `OBSOLETO`/`OBJ:Invalidar`, `PROPAGAOBSOLETO`, `OPV:EditaCampo`, `SARJETAEDITA`.
- Ligar/desligar/remover marcam o destino (e a jusante só com `PROPAGAOBSOLETO`).
- Fora da etapa 1: etiqueta/tabela ainda não mostram o aviso (reagir a `objeto.obsoleto`, atualizando só as etiquetas do objeto, sem refazer tabelas a cada evento da cadeia).

- Etapa 2 **implementada** (sarjeta, só análise estática): `CARACT-DEFS` (`COMP`, `DECL`); `SOB:Caracterizar` devolve parcial; `SOB:Calcular` e `SOB:Resumo` leem `CARACT` (sem reler o desenho). O desenho continua sendo relido ao calcular: `LIG:CalcularCore` chama `OBJ:AtualizaCaract` (recaracteriza e grava só o `CARACT`, sem marcar obsoleto) enquanto `HYDRO.CARACT.AUTO` = 1 (padrão; comando `CARACTAUTO`). Com 0, o cálculo usa o `CARACT` gravado.

- Etapa 3 **implementada** (bacia, só análise estática): cadastro genérico (talvegue em `PARAMS-DEFS`, `AREA/COMP/DECL` em `CARACT-DEFS`, `TC-METODO`/`TC-USUARIO` em `ATRIB`); `BAC:Preparar`/`BAC:TcDe` (tc só no cálculo); removidos `BAC:Obter`, `BAC:Cadastrar`, `BAC:CadastroInterativo`, `BAC:EditarCadastro` e perguntas próprias; `BACIAEDITA`; `BACIAS/INFO/ZOOM/CAD` pelos fluxos `OPV:*`. Bacia passa a ser cadastrável por `OBJETO`.

- Etapa 4 **conferida** (só análise estática): nenhuma chamada a `BAC:Obter`/`CadastroInterativo`/`EditarCadastro` restou (tabela, views, tests, docs). Tabela, etiquetas e resumos já toleram bacia sem `RESULT/TC` (mostram "-"). Teste de `OBJETO` atualizado (bacia agora é cadastrável). `plugins/sarjetas` (legado) continua fora desta árvore e no manifesto; seus testes `SARJ:` seguem sem definição.

- Etapa 5 **feita**: `CLAUDE.md` (princípios 9 a 11, status e pendências), `template_objeto.lsp`, skill `hydro-model`, `arquitetura.md` (18b/18d) e README.

## Etapas sugeridas (cada uma verificável com `verificar.py`)

1. Núcleo: capacidades novas, fluxo de cadastro, `OBSOLETO`/`OBJ:Invalidar` e `OPV:EditaCampo`
   (sarjeta continua igual).
2. Sarjeta no esqueleto (sem vínculos): valida o fluxo.
3. Bacia: talvegue em `PARAMS-DEFS`, tc fora do cadastro, remover `BAC:Obter`.
4. Chamadores de `BAC:Obter` (sarjetas legado, tabelas, etiquetas) e testes.
5. Docs (`arquitetura.md`, `template_objeto.lsp`, skill `hydro-model`, CLAUDE.md).

## Pontos de atenção

- Desenhos com cadastro antigo da bacia (tc dentro do cadastro) não migram.
- `HYDROTESTE` e as etiquetas hoje assumem `RESULT/TC` preenchido no cadastro; passarão a lidar com tc ausente.
- Tudo isso é análise estática; o fluxo de seleção e `ldata` seguem sem teste no AutoCAD.
