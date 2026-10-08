---
name: hydro-model
description: Cria ou reorganiza um arquivo de MODELO (objeto do sistema) em Hydro.bundle/Contents/plugins/models/ do projeto Hydro (AutoLISP, Civil 3D). Use ao criar um objeto novo (bueiro, canal, bacia de detencao...), ao mexer em bacia.lsp ou sarjeta.lsp, ou ao decidir onde uma funcao de objeto deve ficar e como RESULT e organizado.
---

# Modelo (objeto) do Hydro

Um arquivo em `plugins/models/` e **so a funcionalidade do objeto**. Traz os
comandos `c:` de linha de comando e as perguntas deles (secao 9), para funcionar com um unico
.lsp, e um `ToString`. Texto no desenho e dialogos DCL ficam em `views/<nome>_view.lsp`.
Referencia completa: `docs/arquitetura.md` secoes 14c, 16 e 18. Modelo para copiar:
`docs/template_objeto.lsp`. Exemplos reais: `models/bacia.lsp` (armazenamento proprio)
e `models/sarjeta.lsp` (herda a classe base).

## As 9 secoes (nesta ordem)

Cada secao abre com o cabecalho `;;; N. NOME` entre linhas `;;; ----`. `python
build/verificar.py` (passo 8) recusa arquivo sem alguma delas ou fora de ordem.

| # | Cabecalho | O que entra |
|---|---|---|
| 1 | `UTILITARIOS` | `_Try`, `_Erro`, `_Limpa`, `_Val`, `_SetChave`, nomes para exibir. Nada de regra de negocio |
| 2 | `GEOMETRIA (CARACTERIZACAO)` | leitura do desenho (area, comprimento, desnivel, superficie) e `Caracterizar` -> `CARACT` |
| 3 | `LER, GRAVAR, EDITAR, REMOVER` | `Ler`, `Gravar`, `Listar`, `Reindexar`, `Cadastrar`/`Obter`, `Remover`. Tipo que herda a classe base so deixa um comentario dizendo isso |
| 4 | `CAMPOS (CARACT, PARAMS e ATRIB)` | acessos (`Nome`, `Atrib`, `Caract`, `Params`), padroes de `ATRIB`, contexto de calculo montado dos campos |
| 5 | `RESULTADOS (RESULT)` | acessos aos **grupos** de `RESULT`, gravar/substituir entradas, `Contexto` para quem consome |
| 6 | `CALCULOS` | funcoes **puras** que produzem os campos de `RESULT` (devolvem alist ou `(("ERRO" . msg))`) |
| 7 | `RESUMO E FORMATACAO` | `Resumo`, `Formata`, `Linhas...` (listas de strings; a view desenha) e **`ToString (en)`**: uma string, capacidade `"TOSTRING"` |
| 8 | `TIPO NO CATALOGO` | `HYDRO:SetLabel`, `HYDRO:On`, funcoes `_Obj...` das capacidades, `OBJ:RegistrarTipo` |
| 9 | `COMANDOS E INTERACAO` | `c:` de linha de comando, selecao e perguntas (`getXXX`, `alert`); no fim do arquivo `HYDRO:Provide` e `(princ)` |

Secao vazia continua no arquivo, com um comentario do motivo (ex.: "herda da classe base").
Se surgir algo que nao cabe em nenhuma, **acrescente uma secao 9+ ao final** e atualize esta
tabela, a secao 14c da arquitetura e o passo 8 do `verificar.py`. Nao espalhe funcao fora de secao.

## RESULT: grupos com nome, campos planos

`RESULT` nao tem uma lista generica `"CALCULOS"` nem sub-lista `"RES"`. Cada coisa calculada
e um **grupo com nome** e os campos calculados ficam **direto** na entrada:

```
("RESULT" . (("TC"          . (("MIN" . 14.2) ("ORIGEM" . "kirpich") ("PARAMS" . ...)))
             ("VAZAO"       . ((("METODO" . "racional") ("TR" . 10.0) ("DUR" . 14.2)
                                ("TC" . 14.2) ("I" . 150.2) ("PE" . 21.3)
                                ("QP" . 3.123) ("VOLUME" . 2556.0))))
             ("HIDRAULICA"  . ((("METODO" . "racional") ("TR" . 10.0)
                                ("LAMINA" . 0.09) ("VELOCIDADE" . 1.2) ...)))
             ("HIDROGRAMAS" . (...))))
```

- Grupo unico (ex.: `TC`) e uma alist. Grupo de lista (`VAZAO`, `HIDRAULICA`, `HIDROGRAMAS`)
  e lista de entradas; entrada = campos planos + `METODO` e `TR`. Mesmo `METODO`+`TR`
  **substitui** a entrada anterior (`OBJ:GravarResultado en grupo entrada`).
- Nome do grupo diz o que e: `VAZAO` (picos, volume, intensidade), `TC`, `HIDRAULICA`
  (lamina, velocidade, capacidade), `HIDROGRAMAS`. Grupo novo = nome novo, nunca "CALCULOS".
- Leitura generica: `OBJ:ResultDe`, `OBJ:GrupoDe en grupo`, `OBJ:VazaoDe`. Cada modelo pode ter
  atalhos na secao 5 (`BAC:Vazao`, `BAC:Tc`, `SOB:Hidraulica`).
- `ATRIB` = o usuario define; `CARACT` = o desenho informa; `PARAMS` = so para ligar a outro
  objeto (evite); `RESULT` = tudo que e calculado.

## Regras de codigo (resumo; completas no CLAUDE.md)

- Prefixo do modelo em todo simbolo publico; `_` para interno. Declare todas as locais.
- `and`/`or` so como teste; nunca grave pares com valor `nil` (`_Limpa`).
- Tudo que pode falhar (COM, `entget`, `ldata`, `handent`): `vl-catch-all-apply`.
- Nao execute no load nada que dependa de outro plugin, exceto o cadastro no catalogo
  (precisa de `objetos.lsp` antes na ordem do manifesto), protegido por `(HYDRO:Has "objetos")`.
- ASCII puro, sem acento, nos comentarios e strings do codigo.
- Formulas hidrologicas: cite a fonte e a faixa de validade. Nao invente formula.

## Roteiro para objeto novo

1. Copie `docs/template_objeto.lsp` para `plugins/models/<nome>.lsp`; troque o prefixo.
2. Preencha as 9 secoes; calcule em funcoes puras e devolva campos planos.
3. Inclua `"plugins/models/<nome>"` em `HYDRO:Manifest` (`core/core.lsp`), depois de `objetos`.
4. Interacao e texto no desenho: `views/<nome>_view.lsp` (feature `<nome>-view`).
5. Teste de cada funcao de calculo em `tests/teste_manual.lsp` (valor esperado calculado fora
   do AutoCAD, por exemplo em Python).
6. Atualize `docs/arquitetura.md` (tabela 14c, tipos incluidos, secao 18.4), README e a ordem
   em `docs/compilacao.md`.
7. Rode `python build/verificar.py`. Lembre: nada foi executado no AutoCAD ainda; diga isso.

## Ao reorganizar um modelo existente

Mova funcoes para a secao certa **sem renomear** (o resto do projeto chama pelo nome).
Renomear exige `grep` em `Hydro.bundle/`, `tests/` e `docs/` e atualizar todos os chamadores.
