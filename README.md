# Hydro — cálculos de drenagem para Civil 3D em AutoLISP

Conjunto de **plugins em AutoLISP** para fazer cálculos hidrológicos e
hidráulicos dentro do Civil 3D/AutoCAD, com foco em **simplicidade** e em
**comunicação entre plugins**: cada plugin funciona sozinho e, quando outro
está carregado, aproveita o que ele oferece.

Exemplo: o módulo de sarjetas calcula e mostra o resultado em qualquer caso;
se o plugin de XData estiver carregado, a vazão também é gravada na polilinha
da bacia — sem o módulo de sarjetas saber que o XData existe.

> **Status:** em desenvolvimento. O código foi escrito e revisado, mas ainda
> deve ser validado no AutoCAD/Civil 3D. Rode `HYDROTESTE` (seção 5) e teste os
> comandos em um desenho de exemplo antes de usar em projeto.

## 1. Estrutura

```
Hydro/
├─ README.md
├─ Hydro.bundle/                  ← o que é instalado/distribuído
│   ├─ PackageContents.xml        ← descritor do Autoloader
│   └─ Contents/
│       ├─ hydro.lsp              ← ponto de entrada (único arquivo carregado)
│       ├─ core/core.lsp          ← registro, eventos, configuração, carregador
│       ├─ plugins/                   ← SISTEMA: dados, cálculo, catálogos, eventos
│       │   ├─ persistence.lsp    ← DB:   persistência no desenho
│       │   ├─ relacao.lsp        ← XD:   XData e relacionamentos
│       │   ├─ idf.lsp            ← PREC: equação IDF
│       │   ├─ precipitacao.lsp   ← HIET: hietogramas (consome a IDF; tipos em registry/)
│       │   ├─ sarjetas.lsp       ← SARJ: cálculo direto de sarjeta (fluxo antigo), comandos, texto
│       │   ├─ secao.lsp          ← SJT:  dados e hidráulica das seções de sarjeta
│       │   ├─ hidrograma.lsp     ← HID:  geração e armazenamento de hidrogramas
│       │   ├─ objetos.lsp        ← OBJ:  objetos hidráulicos genéricos (catálogo de tipos)
│       │   ├─ ligacao.lsp        ← LIG:  ligações de descarga entre objetos + integridade
│       │   ├─ objetos_padrao.lsp ← OPD:  consultas padrão dos objetos (busca, vínculos de PARAMS)
│       │   ├─ auditoria.lsp      ← AUD:  catálogo de verificações/correções do desenho
│       │   ├─ models/            ← OBJETOS: só a funcionalidade do objeto
│       │   │   ├─ bacia.lsp          ← BAC:  bacia (contorno + talvegue): registro, tc, vazão, tipo
│       │   │   ├─ sarjeta.lsp        ← SOB:  sarjeta: seções, geometria, Izzard, tipo
│       │   │   └─ objetos_tipos.lsp  ← OTP:  trecho, estrutura, tubo-c3d
│       │   └─ registry/          ← CATÁLOGOS: só cadastros de métodos e tipos
│       │       ├─ metodos.lsp          ← MET:  métodos chuva-vazão
│       │       ├─ tempo_conc.lsp       ← TCM:  métodos de tempo de concentração
│       │       ├─ hidrograma_tipos.lsp ← HID:  tipos de hidrograma
│       │       └─ hietograma_tipos.lsp ← HIET: tipos de hietograma
│       ├─ views/                     ← INTERFACE: diálogos, comandos c:, desenho
│       │   ├─ idf_view.lsp       ← PREC: diálogo IDF, comandos IDF/ATUALIZAIDF/ATUALIZATR
│       │   ├─ secao_view.lsp     ← SJT:  comando SECAO, desenho e inserção da seção
│       │   ├─ bacia_view.lsp     ← BAC:  perguntas, comandos e etiquetagem da bacia
│       │   ├─ bacia_tabela.lsp   ← BTB:  tabela de bacias
│       │   ├─ hidrograma_view.lsp← HID:  visualizador, gráfico, CSV, comandos HIDROGRAMA*
│       │   ├─ objetos_tabela.lsp ← OBT:  tabela de objetos e ligações
│       │   ├─ viewer.lsp         ← VIEW: visualização dos dados
│       │   ├─ painel.lsp         ← PNL:  painel de botões HYDRO e HYDROMACROS (ribbon)
│       │   ├─ painel_acoes.lsp   ←       botões dos comandos existentes (PNL:Acao)
│       │   ├─ menu.lsp           ← MNU:  menu "Hydro" na barra de menus
│       │   └─ toolbar.lsp        ← TLB:  barras de ferramentas "Hydro - *"
│       └─ resources/
│           ├─ dcl/               ← idf.dcl, secao.dcl, hidrograma.dcl, bacia_tabela.dcl, ligacoes.dcl, viewer.dcl
│           ├─ slides/            ← idf_formula.sld
│           └─ icons/             ← ícones .bmp 16/24 das barras (build/gerar_icones.py)
├─ build/                         ← só desenvolvimento (não vai no bundle)
│   ├─ build.lsp                  ← gera dist/ compilado (FAS)
│   ├─ vlx_flag.lsp               ← 1º arquivo do projeto VLX
│   ├─ gerar_icones.py            ← gera os ícones das barras
│   ├─ instalar.bat
│   └─ desinstalar.bat
├─ dist/                          ← saída do build (ignorada pelo git)
├─ docs/
│   ├─ arquitetura.md             ← contratos: eventos, chaves, XData
│   ├─ compilacao.md              ← tutorial FAS/VLX
│   ├─ distribuicao.md            ← tutorial PackageContents.xml + distribuição
│   └─ template_plugin.lsp        ← modelo para plugins novos
└─ tests/
    └─ teste_manual.lsp           ← comando HYDROTESTE
```

> O `idf_formula.sld` (imagem da fórmula no diálogo da IDF) já está em
> `resources/slides/`. Sem ele, o diálogo abre com a área da fórmula em branco.

## 2. Instalação para desenvolvimento

**Opção A — Autoloader (recomendada).**
Rode `build\instalar.bat` ou copie `Hydro.bundle` para
`%APPDATA%\Autodesk\ApplicationPlugins\`. Reabra o Civil 3D. Se houver aviso
de segurança, adicione `...\Hydro.bundle\Contents...` em *Locais confiáveis*
(`TRUSTEDPATHS`).

**Opção B — rodar direto da pasta de trabalho (recomendada para desenvolver).**

1. Carregue **uma vez** o `hydro.lsp` da sua pasta de trabalho (`APPLOAD`, ou
   `(load "C:/Dev/Hydro/Hydro.bundle/Contents/hydro.lsp")`).
2. Digite `HYDRODIR` e escolha a pasta `Contents` (ou `Hydro.bundle`) na caixa
   de diálogo. A escolha fica gravada no Registro do Windows
   (`HKEY_CURRENT_USER\Software\Hydro`) e vale para todos os desenhos e
   sessões seguintes.
3. Edite os `.lsp` em `Hydro.bundle/Contents` e use `HYDRORELOAD` para
   recarregar core e plugins, sem fechar o AutoCAD.

Para voltar à descoberta automática: `HYDRODIR` → `Limpar`.

> **Não misture** a Opção A (cópia instalada em `%APPDATA%`) com a Opção B: a
> escolha do `HYDRODIR` tem prioridade, mas você pode acabar editando um
> arquivo e testando outro. Durante o desenvolvimento use só a Opção B.

> Na pasta de código-fonte **não deixe arquivos `.fas`**: o carregador prefere
> `.fas` a `.lsp`, e um compilado antigo esconderia as suas edições.

## 3. Comandos principais

| Comando | O que faz |
|---|---|
| `HYDRODIR` | Escolhe (caixa de diálogo de pasta) ou limpa a pasta do Hydro |
| `HYDRORELOAD` | Recarrega core e plugins a partir da raiz atual |
| `HYDROPLUGINS` | Lista a raiz e os plugins ativos |
| `HYDRODADOS` | Diálogo com os dados persistidos (DB e XData) e exportação CSV |
| `ATUALIZAIDF`, `ATUALIZATR`, `IDF` | Parâmetros e visualização da equação IDF |
| `CALCULASARJETA`, `CALCULASARJETAMULTITR` | Calcula sarjeta (um TR ou três) |
| `CRIARSARJETARESULTADO` (e `...MULTITR`) | Calcula e insere o resultado como MTEXT |
| `CRIASECAO`, `SELECIONASECAO`, `PARAMETROSSARJETA` | Seções de sarjeta |
| `SECAO` | Diálogo visual das seções: exagero vertical escolhido, escala comum, lâmina d'água e inserção no desenho |
| `IDF` | Calcula a intensidade para **tr, tc e duração** informados (duração = tc ou outra) |
| `BACIACAD` | **Cadastro rápido** da bacia: nome, tc (vários métodos), C e CN |
| `BACIA` | Calcula a vazão por um método cadastrado e guarda na entidade |
| `CRIARBACIARESULTADO`, `TEXTOBACIA` | Insere o resultado da bacia como texto no desenho |
| `BACIATABELA` | Tabela das bacias do desenho (detalhes, ir para, hidrogramas, texto, editar, CSV) |
| `BACIAS`, `BACIAINFO` | Lista em texto / dados de uma bacia |
| `OBJETO` | Transforma uma entidade (polilinha, bloco, estrutura/tubo do Civil 3D...) em objeto hidráulico de um tipo |
| `LIGAR`, `DESLIGAR` | Liga origens a um destino (bacia → sarjeta, bacia → bacia, sarjeta → trecho...) / desfaz |
| `LIGACOES` | Tabela de objetos e ligações (destino, afluentes, árvore a montante) |
| `CALCULAOBJETO` | Calcula um objeto como mecanismo entrada → saída: entrada = saídas dos montantes (bacias e sarjetas), saída = precipitação no maior tempo (ex.: sarjeta) |
| `PRESERVAVAZAO` | Flag geral: manter a maior vazão entre a de entrada e a de saída |
| `VALIDARLIGACOES` | Verifica e corrige a integridade das ligações |
| `HYDROAUDIT` | Auditoria geral do desenho (como o `AUDIT`): vínculos quebrados, índices, seções e ligações; pergunta e corrige |
| `OBJETOS`, `OBJETOZOOM` | Lista objetos de um tipo (ou todos) / localiza qualquer objeto por nome ou handle (zoom e seleção) |
| `OBJETOVINCULOS` | Realça as entidades vinculadas em `PARAMS` (ex.: o talvegue de cada bacia) |
| `BACIAZOOM` | Localiza uma bacia por nome ou handle |
| `SARJETACAD`, `SARJETAS`, `SARJETAINFO`, `SARJETAZOOM` | Cadastrar/editar, listar, dados e localizar sarjetas |
| `HIDROGRAMA` | Gera um hidrograma (tipo à escolha), guarda na bacia e abre o visualizador |
| `HIDROGRAMAVER` | Visualizador: vários hidrogramas sobrepostos, tabela, exportação CSV, exclusão |

Lista completa em `docs/arquitetura.md`.

## 4. Como funciona (resumo)

- **Registro de funcionalidades:** cada plugin anuncia o que oferece
  (`HYDRO:Provide`) e os outros perguntam (`HYDRO:Has`) ou exigem
  (`HYDRO:Require`).
- **Eventos:** quem calcula publica (`HYDRO:Emit`); quem se interessa assina
  (`HYDRO:On`). O emissor não conhece os assinantes.
- **Configuração:** `HYDRO:Get` / `HYDRO:Set`. Grava no desenho se o plugin de
  persistência estiver carregado; senão, só na sessão.
- **Sem variáveis globais** nos plugins; funções de cálculo são puras.
- **Rótulos:** cada plugin descreve seus dados (`HYDRO:SetLabel`) e o
  visualizador os mostra de forma legível, sem depender do plugin.

Detalhes e contratos: `docs/arquitetura.md`.

## 5. Testes

```lisp
(load "C:/Dev/Hydro/tests/teste_manual.lsp")
```

Depois, o comando `HYDROTESTE`. Ele verifica as funções puras (Kirpich, método
racional, Izzard, IDF, utilitários do core, helpers do `DB:` e do visualizador)
contra valores calculados fora do AutoCAD e restaura qualquer configuração que
tenha alterado.

## 6. Compilar e distribuir

- Compilar para `.fas`/`.vlx`: `docs/compilacao.md`
- `PackageContents.xml`, instalação, segurança e atualização: `docs/distribuicao.md`

Resumo:

```lisp
(load "C:/Dev/Hydro/build/build.lsp")
(HB:Build "C:/Dev/Hydro" "fas")      ; gera dist/Hydro.bundle
```

Depois compacte `dist/Hydro.bundle` e distribua com `build/instalar.bat`.

## 7. Bacias, métodos e hidrogramas (resumo)

1. `ATUALIZAIDF` (parâmetros da IDF) e, se tiver, `ATUALIZASUPERFICIE` (TIN).
2. `BACIACAD`: contorno, talvegue, nome, **método de tc** (Kirpich, Ventura,
   Pasini, Corps, Giandotti, George Ribeiro, cinemático ou informado), C e CN.
   Fica gravado **na polilinha do contorno** e é o **cadastro comum** usado
   também pelas sarjetas.
3. `BACIA`: usa o cadastro; informe o TR, escolha o **método chuva-vazão**
   (catálogo) e responda os parâmetros (C e CN do cadastro já vêm como padrão).
   `CRIARBACIARESULTADO` faz o mesmo e insere o resultado como texto.
4. `BACIATABELA`: veja todas as bacias do desenho numa tabela.
5. `HIDROGRAMA`: escolha o cálculo da bacia e o **tipo** de hidrograma
   (baseado na área ou definido por você). Ele é gravado na bacia e aberto no
   visualizador, onde você sobrepõe vários, vê a tabela e exporta o CSV.
6. **Conectar:** `OBJETO` no talvegue (tipo sarjeta: seção e rugosidade), `LIGAR`
   (a bacia sugere o próprio talvegue como destino; ao ligar em uma bacia ele
   pergunta se o montante contribui diretamente ao talvegue), `CALCULAOBJETO` (entrada,
   saída e tempo máximo) e `LIGACOES` (tabela e árvore). Calcule **de montante para
   jusante** (bacias, sarjetas), com o mesmo método e TR.
   O **receptor** guarda a lista `MONTANTE` no `PARAMS` dele (uma única fonte de verdade).
7. Métodos novos (chuva-vazão, **tempo de concentração**), tipos de hidrograma e
   **tipos de objeto hidráulico** entram por cadastro, sem alterar nada que já
   existe: `docs/template_metodo.lsp` e `docs/template_objeto.lsp`.
   Detalhes em `docs/arquitetura.md` (seções 10 a 17).

## 8. Criando um plugin novo

1. Copie `docs/template_plugin.lsp` para `Contents/plugins/<nome>.lsp`.
2. Troque o prefixo (3 a 5 letras maiúsculas).
3. Inclua `"plugins/<nome>"` (ou `"views/<nome>"` para interface) em `HYDRO:Manifest` (`core/core.lsp`).
4. Termine o arquivo com `(HYDRO:Provide "<nome>" "1.0")`.
5. Documente eventos/chaves novos em `docs/arquitetura.md`.

## 9. Requisitos

- Windows, AutoCAD ou Civil 3D com AutoLISP (o código usa DCL e ActiveX).
- `RuntimeRequirements` do bundle: `SeriesMin="R21.0"` (AutoCAD 2017).
  Ajuste conforme as versões que você testou.
