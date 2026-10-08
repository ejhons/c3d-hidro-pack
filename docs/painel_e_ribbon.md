# Painel de botões, menu, barras de ferramentas e ribbon

## 1. O painel do Hydro (`HYDRO`)

```
HYDRO            (ou HYDROPAINEL)
```

Abre um diálogo com os comandos agrupados em caixas. Clique em um botão e o
comando roda; com **"Manter o painel aberto depois de executar"** (padrão) o
painel **reabre** quando o comando termina. Botões de plugins não carregados
aparecem **desabilitados**.

### Limite importante

O diálogo (DCL) é **modal**: ele não fica aberto enquanto você desenha. É um
**lançador** de comandos, não uma paleta flutuante. Para botões que ficam sempre
visíveis, use as barras de ferramentas (seção 4), o menu (seção 3) ou a ribbon (seção 5).

### Como é feito

O painel **não tem DCL fixo**: a cada abertura o `painel.lsp` escreve um DCL
temporário com um botão por ação do catálogo `acao-painel` (grupos em ordem, 3
grupos por linha, largura do botão = maior rótulo do grupo). Por isso um plugin
novo ganha botão **sem alterar nenhum arquivo existente**:

```lisp
;; no arquivo do seu plugin (depois de painel.lsp no manifesto)
(PNL:Acao "bueiro.calcular" "Objetos e ligacoes" 40 90 "Calcular bueiro" "CALCULABUEIRO" '("objetos"))
;;        id               grupo (caixa)         ordem-grupo ordem rotulo (ASCII) comando         exige
```

Grupo novo? Use um nome novo e uma `ordem-grupo` (10, 20, ... 90 já usados). O
`python build/verificar.py` **avisa** quando existe um comando `c:XXX` sem botão.

## 2. Botões incluídos

| Grupo | Botão | Comando | Exige | Ícone |
|---|---|---|---|---|
| Dados e IDF | Equacao IDF (tr, tc, duracao) | `IDF` | precipitacao | `idf_calcular_16/24` |
| Dados e IDF | Parametros da IDF | `ATUALIZAIDF` | precipitacao | `idf_parametros_16/24` |
| Dados e IDF | Tempo de retorno | `ATUALIZATR` | precipitacao | `idf_tr_16/24` |
| Dados e IDF | Superficie (TIN) | `ATUALIZASUPERFICIE` | sarjetas | `superficie_16/24` |
| Bacias | Cadastrar bacia | `BACIACAD` | bacia | `bacia_cadastrar_16/24` |
| Bacias | Calcular vazao da bacia | `BACIA` | bacia | `bacia_calcular_16/24` |
| Bacias | Calcular e inserir texto | `CRIARBACIARESULTADO` | bacia | `bacia_calctexto_16/24` |
| Bacias | Inserir texto de resultado | `TEXTOBACIA` | bacia | `bacia_texto_16/24` |
| Bacias | Dados da bacia | `BACIAINFO` | bacia | `bacia_info_16/24` |
| Bacias | Listar bacias (texto) | `BACIAS` | bacia | `bacia_lista_16/24` |
| Bacias | Tabela de bacias | `BACIATABELA` | bacia-tabela | `bacia_tabela_16/24` |
| Hidrogramas | Gerar hidrograma | `HIDROGRAMA` | hidrograma | `hid_gerar_16/24` |
| Hidrogramas | Ver hidrogramas da bacia | `HIDROGRAMAVER` | hidrograma | `hid_ver_16/24` |
| Objetos e ligacoes | Cadastrar objeto hidraulico | `OBJETO` | objetos | `obj_cadastrar_16/24` |
| Objetos e ligacoes | Dados do objeto | `OBJETOINFO` | objetos | `obj_info_16/24` |
| Objetos e ligacoes | Ligar (origem -> destino) | `LIGAR` | ligacao | `lig_ligar_16/24` |
| Objetos e ligacoes | Desligar origem | `DESLIGAR` | ligacao | `lig_desligar_16/24` |
| Objetos e ligacoes | Calcular objeto | `CALCULAOBJETO` | ligacao | `obj_calcular_16/24` |
| Objetos e ligacoes | Tabela de objetos e ligacoes | `LIGACOES` | objetos-tabela | `lig_tabela_16/24` |
| Objetos e ligacoes | Validar ligacoes | `VALIDARLIGACOES` | ligacao | `lig_validar_16/24` |
| Objetos e ligacoes | Remover cadastro de objeto | `OBJETOREMOVER` | objetos | `obj_remover_16/24` |
| Sarjetas e secoes | Calcular sarjeta (1 TR) | `CALCULASARJETA` | sarjetas | `sarj_calc1_16/24` |
| Sarjetas e secoes | Calcular sarjeta (3 TR) | `CALCULASARJETAMULTITR` | sarjetas | `sarj_calc3_16/24` |
| Sarjetas e secoes | Calcular e inserir texto (1 TR) | `CRIARSARJETARESULTADO` | sarjetas | `sarj_txt1_16/24` |
| Sarjetas e secoes | Calcular e inserir texto (3 TR) | `CRIARSARJETARESULTADOMULTITR` | sarjetas | `sarj_txt3_16/24` |
| Sarjetas e secoes | Visualizar secoes | `SECAO` | secao | `secao_ver_16/24` |
| Sarjetas e secoes | Criar secao | `CRIASECAO` | sarjetas | `secao_criar_16/24` |
| Sarjetas e secoes | Selecionar secao atual | `SELECIONASECAO` | sarjetas | `secao_atual_16/24` |
| Sarjetas e secoes | Resumo dos parametros | `PARAMETROSSARJETA` | sarjetas | `sarj_params_16/24` |
| Texto e parametros | Coeficiente de runoff (C) | `ATUALIZARUNOFF` | sarjetas | `txt_runoff_16/24` |
| Texto e parametros | Altura do texto | `ATUALIZAALTURATEXTO` | sarjetas | `txt_altura_16/24` |
| Texto e parametros | Rotacao do texto | `ATUALIZAROTACAOTEXTO` | sarjetas | `txt_rotacao_16/24` |
| Sistema | Dados persistidos (DB e XData) | `HYDRODADOS` | visualizador | `sis_dados_16/24` |
| Sistema | Dados em texto | `HYDRODUMP` | visualizador | `sis_dump_16/24` |
| Sistema | Plugins ativos | `HYDROPLUGINS` | - | `sis_plugins_16/24` |
| Sistema | Recarregar o Hydro | `HYDRORELOAD` | - | `sis_reload_16/24` |
| Sistema | Escolher a pasta do Hydro | `HYDRODIR` | - | `sis_dir_16/24` |
| Sistema | Exportar macros (ribbon) | `HYDROMACROS` | painel | `sis_macros_16/24` |
| Sistema | Executar testes | `HYDROTESTE` | - | `sis_teste_16/24` |
| Sistema | Recriar o menu Hydro | `HYDROMENU` | menu | `sis_menu_16/24` |
| Sistema | Remover o menu Hydro | `HYDROMENUREMOVER` | menu | `sis_menuremover_16/24` |
| Sistema | Recriar as barras Hydro | `HYDROBARRAS` | toolbar | `sis_barras_16/24` |
| Sistema | Remover as barras Hydro | `HYDROBARRASREMOVER` | toolbar | `sis_barrasremover_16/24` |

Todos os botões acima também entram no menu "Hydro" (seção 3) e nas barras de ferramentas (seção 4).

Comandos sem botão de propósito: `SETUSERVALUE` e `GETUSERVALUE` (depuração do
DB) e `ATUALIZARUNFOFF` (nome antigo, com erro de digitação, mantido por
compatibilidade).

## 3. Menu "Hydro" na barra de menus

O plugin `menu.lsp` cria um **menu suspenso "Hydro"** na barra de menus, com um
submenu por grupo e um item por ação (o primeiro item abre o painel `HYDRO`).
Usa a API ActiveX de menus do Visual LISP (`AcadMenuGroup`, `AcadPopupMenu`) e
os **mesmos dados do painel** (catálogo `acao-painel`): comando novo com
`PNL:Acao` = item novo no menu, sem editar o `menu.lsp`.

- **Criação automática** depois que todos os plugins carregaram (evento
  `hydro.carregado`), se `HYDRO.MENU.AUTO` = 1 (padrão). Só entram ações
  **disponíveis** (comando definido e plugins exigidos carregados).
- **Sem duplicar:** se o menu já existe (outro desenho, `HYDRORELOAD`), ele é
  reaproveitado: itens apagados e recriados. Nada é gravado na personalização
  (não chamo `Save`); o menu é refeito a cada sessão.
- **Barra de menus oculta:** versões recentes mostram a ribbon e escondem a
  barra (`MENUBAR` = 0). `HYDROMENU` recria o menu e oferece mostrar a barra;
  ou digite `MENUBAR` e `1`.
- `HYDROMENUREMOVER` tira o menu da barra.

**Pontos a conferir no seu AutoCAD/Civil 3D** (não pude executar): o nome do grupo
de menus principal (o código usa `ACAD` e, se não achar, o primeiro grupo da
lista), se o menu aparece antes do item Ajuda e se não fica gravado depois de
fechar. Se a API de menus não estiver disponível, o plugin avisa e o painel
`HYDRO` continua funcionando.

## 3.1 Macros dos botões: estilos e solução de problemas

O menu e os botões das barras executam uma **macro** (texto). O formato é configurável
(`HYDRO.MACRO.ESTILO`, comando **`HYDROMACROESTILO`**, que também reconstrói o menu e as barras):

| Estilo | Macro de `BACIA` | Observação |
|---|---|---|
| `lisp` (padrão) | `(c:BACIA)` | chama a função direto; **sem caractere de controle** |
| `cancela-lisp` | `^C^C(c:BACIA)` | cancela um comando ativo antes |
| `nome` | `BACIA` + espaço | digita o nome e Enter |
| `cancela` | `^C^CBACIA` | formato clássico do editor CUI |
| `espaco` | `^C^CBACIA` + espaço | idem, com Enter explícito |

**Se um botão não faz nada ou dá erro:**

1. Rode `HYDROMACROESTILO` e escolha outro estilo (a lista mostra o texto da macro de cada um); depois
   clique de novo no botão. O comando reconstrói menu e barras na hora.
2. Teste o comando pelo painel `HYDRO`: **o painel não usa macro** (chama a função direto). Se o painel
   funciona e o botão não, o problema é o estilo da macro, não o código do comando.
3. Digite o comando na linha de comando (ex.: `BACIA`): se funciona, o Hydro está carregado naquele desenho.
4. Observe o histórico do comando ao clicar: "Comando desconhecido" indica que o texto da macro chegou
   (e o nome não foi reconhecido); nada no histórico indica que a macro não foi interpretada.
5. Um comando ativo (ex.: LINHA) recebe o texto da macro como entrada: use `cancela-lisp` ou pressione ESC
   antes. O estilo `lisp` (padrão) não cancela comandos ativos.

Para o **editor CUI** (ribbon), use a coluna "Macro para o editor CUI" de `HYDROMACROS`; ali o formato
clássico `^C^CNOME` é o esperado.

## 4. Barras de ferramentas "Hydro - ..."

O plugin `toolbar.lsp` cria **uma barra de ferramentas por grupo** ("Hydro - Bacias",
"Hydro - Hidrogramas"...), com um botão por ação e **ícone**, usando a API ActiveX
`AcadToolbars`. Usa o mesmo catálogo `acao-painel` do painel e do menu: comando novo com
`PNL:Acao` = botão novo, sem editar o `toolbar.lsp`.

- **Criação automática** quando todos os plugins terminaram de carregar (`hydro.carregado`), se
  `HYDRO.TOOLBAR.AUTO` = 1 (padrão). Só entram ações disponíveis.
- **Posição inicial das barras novas:** `HYDRO.TOOLBAR.DOCK` = `left` (padrão), `top`, `bottom`,
  `right` ou `float`. Barras que **já existem** são reaproveitadas (botões recriados) e **mantêm a
  posição que você deu**; só ficam visíveis.
- `HYDROBARRAS` recria/mostra; `HYDROBARRASREMOVER` apaga as barras "Hydro - *".
- Nada é salvo na personalização (não chamo `Save`); as barras são refeitas a cada sessão.

### 4.1 Ícones (`Hydro.bundle/Contents/resources/icons/`)

Cada botão procura, nesta ordem (tamanhos **16x16** e **24x24**):

1. `<id>_16.bmp` e `<id>_24.bmp` (o `.` do id vira `_`: `bacia_cadastrar_16.bmp`);
2. `_grupo_<ordem-do-grupo>_16/24.bmp` (ícone do grupo);
3. `_padrao_16/24.bmp` (genérico).

Os incluídos foram **gerados** por `python build/gerar_icones.py`: quadrado colorido por grupo com
um código de até 3 letras (fonte de pixels própria). A coluna "Ícone" da tabela da seção 2 dá o nome
dos arquivos de cada botão.

**Para usar ícones seus:** coloque na pasta arquivos com **o mesmo nome** (ex.: `bacia_cadastrar_16.bmp`
e `bacia_cadastrar_24.bmp`); nenhum código muda. Para um **plugin novo**: crie `<id>_16/24` ou deixe
cair no ícone do grupo. Se a sua versão preferir PNG, grave `.png` com o mesmo nome e defina
`HYDRO.TOOLBAR.EXT` = `png` (o gerador aceita `--formato png`).

Comandos úteis do gerador:

```
python build/gerar_icones.py                   # gera tudo (sobrescreve)
python build/gerar_icones.py --so-faltantes    # só cria o que não existe (preserva os seus)
python build/gerar_icones.py --previa          # grava build/previa_icones.png (folha de contato)
```

**Pontos a conferir no seu AutoCAD/Civil 3D** (não pude executar): se `AddToolbarButton`/`SetBitmaps`
aceitam os BMP (24 bits) como estão, a posição inicial (`Dock`), o nome do grupo de menus principal
(o código usa `ACAD`, senão o primeiro) e se as barras não ficam gravadas depois de fechar.

## 5. Ribbon e atalhos (botões na faixa de opções)

Não gerei o arquivo `.cuix`: ele é um pacote binário do editor de
personalização, e escrevê-lo à mão sem poder abri-lo no AutoCAD seria arriscar
um arquivo que não carrega. O caminho confiável é montar a ribbon uma vez no
editor e distribuí-la junto com o bundle.

### 5.1 Obter as macros

Comando `HYDROMACROS` → salva `hydro_macros.txt` (colunas separadas por TAB:
grupo, rótulo, comando, macro no estilo atual, macro para o editor CUI), sempre em dia com o
catálogo. Para o CUI a macro é `^C^C` + o nome: por exemplo `^C^CBACIA`.

### 5.2 Montar a faixa de opções (o nome exato dos itens pode variar com a versão)

1. Comando `CUI`.
2. Aba **Personalizar**, em "Lista de comandos": **criar um novo comando** para cada
   ação (nome = rótulo, macro = a da planilha; imagem opcional).
3. Em **Faixa de opções > Painéis**: criar o painel "Hydro Bacias" e arrastar os
   comandos para ele (repita por grupo).
4. Em **Faixa de opções > Guias**: criar a guia "Hydro" e arrastar os painéis.
5. Em **Áreas de trabalho**: marcar a guia "Hydro" na área de trabalho em uso.
6. Atalho de teclado (opcional): em **Teclas de atalho**, comando com macro
   `^C^CHYDRO` (abre o painel).

### 5.3 Distribuir a ribbon com o bundle

1. Na aba **Transferir** do `CUI`, crie um arquivo novo (`Hydro.cuix`) e
   **arraste** o painel e a guia do arquivo principal para ele. Salve.
2. Copie `Hydro.cuix` para `Hydro.bundle/Contents/resources/`.
3. Acrescente ao `PackageContents.xml` (dentro de `<Components>`):

```xml
<ComponentEntry
    AppName="HydroUI"
    Version="1.0.0"
    ModuleName="./Contents/resources/Hydro.cuix"
    AppDescription="Faixa de opcoes do Hydro" />
```

O Autoloader aceita personalização parcial (`.cuix`) como componente
(`AppType` "Cui"/"CuiX", deduzido da extensão). Relatos de usuários indicam
que ele copia o `.cuix` para a pasta de suporte do usuário e que a **ordem de
várias guias parciais** pode surpreender; **teste em um perfil limpo**.

### 5.4 Lembrete

Os botões da ribbon só funcionam se o Hydro estiver carregado. Como o bundle
carrega na inicialização (`PerDocument="True"`), isso já vale para todo desenho.

## 6. Paleta flutuante de verdade (se um dia valer a pena)

Uma paleta que fica aberta enquanto você trabalha exige **.NET** (`PaletteSet`)
ou uma **guia de ribbon**; AutoLISP/DCL não oferece isso. Dado o objetivo de
manter tudo em AutoLISP, as barras de ferramentas (seção 4), o menu (seção 3) e a ribbon (seção 5) são o equivalente prático.
