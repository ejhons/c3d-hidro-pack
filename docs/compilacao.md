# Tutorial: compilando o Hydro (FAS e VLX)

Este tutorial usa as informações da documentação oficial da Autodesk (funções
`vlisp-compile`, comando `MAKELISPAPP`, variável `LISPSYS`). Nada foi executado
em um AutoCAD real durante a escrita; siga a seção "Checklist de verificação"
no fim para validar no seu ambiente.

---

## 1. Os três formatos

| Formato | O que é | Quando usar |
|---|---|---|
| `.lsp` | Código-fonte em texto | Desenvolvimento |
| `.fas` | Um `.lsp` compilado (binário) | Distribuição simples; funciona também no Mac |
| `.vlx` | Pacote que junta vários `.lsp` (e opcionalmente `.dcl`) compilados | Distribuição em um arquivo; **só Windows** |

Compilar **não é criptografia forte**: serve para dificultar leitura e edição
acidental e para acelerar o carregamento. Guarde sempre os `.lsp` originais
(do `.fas`/`.vlx` não dá para recuperar o fonte).

## 2. Antes de compilar

1. **Teste a partir do `.lsp`.** Rode `HYDROTESTE` e os comandos principais.
2. **Código em ASCII.** Os arquivos do Hydro não têm acentos de propósito.
   Isso evita problemas de codificação entre o fonte e o compilado.
3. **Escolha o `LISPSYS`.** Ele define o formato do que será gerado:

   | LISPSYS | Efeito |
   |---|---|
   | `0` | Ambiente clássico (MBCS). Compila com o Visual LISP IDE. Roda também em AutoCAD 2020 e anteriores |
   | `1` | Unicode (padrão atual). **Arquivos compilados não carregam no AutoCAD 2020 e anteriores.** `MAKELISPAPP` só funciona neste modo |
   | `2` | Unicode no editor, mas compila em MBCS (compatível com versões antigas) |

   Como o código é ASCII puro, compilar com `0` ou `2` não perde nada e dá a
   maior compatibilidade. Se todos os seus usuários têm AutoCAD/Civil 3D 2021
   ou mais novo, `1` é aceitável. Depois de mudar `LISPSYS`, **reinicie** o
   programa.

## 3. Caminho A (recomendado): um `.fas` por arquivo

É o caminho que o `build/build.lsp` automatiza. Ele mantém o bundle com a
mesma estrutura de pastas e o `HYDRO:FindModule` do core já prefere `.fas`
quando existir.

### Passo a passo

1. No AutoCAD, carregue o script de build:
   ```lisp
   (load "C:/Dev/Hydro/build/build.lsp")
   ```
2. Gere o bundle compilado:
   ```lisp
   (HB:Build "C:/Dev/Hydro" "fas")
   ```
3. O resultado fica em `Hydro/dist/Hydro.bundle`:
   ```
   dist/Hydro.bundle/
   ├─ PackageContents.xml        (ModuleName trocado para hydro.fas)
   └─ Contents/
       ├─ hydro.fas
       ├─ core/core.fas
       ├─ plugins/*.fas
       ├─ plugins/registry/*.fas
       ├─ views/*.fas
       └─ resources/dcl, slides  (copiados)
   ```
4. Teste: copie `dist/Hydro.bundle` para
   `%APPDATA%\Autodesk\ApplicationPlugins\` (ou rode
   `build\instalar.bat "..\dist\Hydro.bundle"`), reabra o AutoCAD e digite
   `HYDROPLUGINS`.

### O que o script faz por baixo

Para cada arquivo ele chama:

```lisp
(vlisp-compile 'st "origem.lsp" "destino.fas")
```

Modos do compilador:

| Modo | Significado | Para o Hydro |
|---|---|---|
| `'st` | Padrão; menor arquivo de saída | **Usado** |
| `'lsm` | Otimiza e liga indiretamente | Possível, teste antes |
| `'lsa` | Otimiza e liga **diretamente** às funções compiladas | Evite: o Hydro depende de ligação tardia por símbolo entre plugins |

> Nas versões antigas da documentação, `vlisp-compile` exigia o Visual LISP IDE
> aberto. A documentação atual não repete essa nota, mas se o seu AutoCAD
> devolver erro, abra o IDE (`VLISP`) e rode o build pelo console dele
> (com `LISPSYS` = 0 ou 2).

## 4. Caminho B: um único `hydro.vlx`

Vale a pena se você quiser distribuir **um arquivo só**. O custo é manter um
projeto de build (arquivo `.prv`) e cuidar do namespace.

### 4.1 Namespace: use o padrão (compartilhado)

No assistente existe a opção **Separate Namespace**. **Deixe desmarcada.**

- Com namespace separado, as funções do VLX **não ficam visíveis** ao
  desenho; cada função pública precisaria de `(vl-doc-export 'NOME)`.
  O Hydro tem dezenas de funções públicas (`HYDRO:`, `DB:`, `XD:`, `PREC:`,
  `SARJ:`, `VIEW:`) e os plugins chamam uns aos outros. Seria um retrabalho
  grande e frágil.
- Com o namespace padrão, tudo se comporta exatamente como com os `.lsp`.

### 4.2 Ordem dos arquivos no projeto

A ordem importa no VLX, porque tudo é executado em sequência na carga:

1. `build/vlx_flag.lsp` — define `HYDRO:*embedded*` (diz ao `hydro.lsp` que
   o código já está dentro do VLX)
2. `Contents/core/core.lsp`
3. `Contents/plugins/persistence.lsp`
4. `Contents/plugins/relacao.lsp`
5. `Contents/plugins/idf.lsp`, `precipitacao.lsp` e `superficie.lsp`
6. `Contents/plugins/secao.lsp` e `sarjetas.lsp`
7. `Contents/plugins/hidrograma.lsp`, `objetos.lsp`, `ligacao.lsp`, `objetos_padrao.lsp`, `auditoria.lsp` e `etiqueta.lsp`
8. `Contents/plugins/models/` (`bacia`, `sarjeta`, `objetos_tipos`; depois de `objetos`)
9. `Contents/plugins/registry/` (`metodos_chuva_vazao`, `tempo_conc`, `hidrograma_tipos`, `hietograma_tipos`)
10. `Contents/views/idf_view.lsp`, `secao_view.lsp`, `bacia_view.lsp`, `bacia_tabela.lsp`, `hidrograma_view.lsp`, `objetos_tabela.lsp`, `objetos_padrao_view.lsp`, `auditoria_view.lsp`, `padroes_view.lsp`, `etiqueta_view.lsp`, `viewer.lsp`, `painel.lsp`, `painel_acoes.lsp`, `menu.lsp`, `toolbar.lsp` (nessa ordem, depois de todos os plugins; ver `HYDRO:Manifest`)
11. `Contents/hydro.lsp` — **por último** (localiza a raiz para achar DCL/SLD)

Novos plugins entram **antes** do `hydro.lsp`.

### 4.3 Gerando com o comando MAKELISPAPP (`LISPSYS = 1`)

1. Digite `MAKELISPAPP`, escolha **Properties** (abre o assistente).
2. Local e nome: `C:\Dev\Hydro\build\hydro` → gera `hydro.prv` e `hydro.vlx`.
3. **Separate Namespace: desmarcado.**
4. Adicione os arquivos na ordem da seção 4.2.
5. Recursos: **não** embuta os `.dcl`/`.sld`; deixe em `resources/` (o código
   os localiza pelo nome com `HYDRO:FindFile`).
6. Compilação: Standard (ou Optimize and Link, se testar).
7. Marque **Build Application** e finalize.

No dia a dia, use `MAKELISPAPP` → **Make** (recompila só os `.lsp` alterados)
ou **Rebuild** (recompila tudo; obrigatório se você mudou as opções do
projeto).

### 4.4 Gerando com o Visual LISP IDE (`LISPSYS = 0` ou `2`)

Menu **File → Make Application → New Application Wizard**, com as mesmas
escolhas acima (modo Expert, namespace padrão, mesma ordem de arquivos).

### 4.5 Colocando o VLX no bundle

```
(HB:Build "C:/Dev/Hydro" "vlx")
```

prepara `dist/Hydro.bundle` com os recursos e o `PackageContents.xml`
apontando para `hydro.vlx`. Copie o `hydro.vlx` gerado para
`dist/Hydro.bundle/Contents/`.

Nesse modo as pastas `core/` e `plugins/` **não** vão para o bundle: tudo está
dentro do VLX.

## 5. Assinatura digital (opcional, recomendada ao distribuir)

Arquivos `LSP`, `MNL`, `FAS` e `VLX` podem ser assinados digitalmente com a
ferramenta `AcSignApply.exe` (pasta de instalação do AutoCAD) ou, sem precisar
do AutoCAD, com a linha de comando:

```
AcSignTool -sign /file:hydro.fas /cert:meucertificado.pfx /time:<servidor> /comment:"Hydro 1.0"
```

Com assinatura, o usuário vê o nome do editor e pode confiar nele uma vez só.
Dois cuidados:

- Foi relatado um defeito nas primeiras versões de AutoCAD 2016 e 2018 que
  impedia carregar **VLX assinado**. Prefira assinar `.fas` se precisar dar
  suporte a essas versões.
- VLX assinado não carrega em AutoCAD 2015 ou anterior.

Você precisa de um certificado de assinatura de código (autoassinado serve só
para testes internos).

## 6. Armadilhas comuns

| Sintoma | Causa provável | Solução |
|---|---|---|
| Edito o `.lsp` e nada muda | Sobrou um `.fas` antigo ao lado; o core **prefere `.fas`** | Apague os `.fas` da árvore de desenvolvimento (a pasta `Hydro.bundle` de código-fonte nunca deve ter `.fas`) |
| `.fas` não carrega em AutoCAD mais antigo | Compilado com `LISPSYS = 1` | Recompile com `LISPSYS` 0 ou 2 |
| "Módulo não encontrado" após compilar | Esqueceu de copiar `core/` e `plugins/` (modo FAS) | Use o `HB:Build`, que mantém a estrutura |
| Funções `XD:`/`DB:` "indefinidas" no VLX | Plugin ficou fora do projeto ou depois do `hydro.lsp` | Confira a ordem (seção 4.2) |
| Dialogo não abre no VLX | `.dcl` fora do alcance | Mantenha `resources/dcl` no bundle e o `SupportPath` no `PackageContents.xml` |
| Warning de segurança ao carregar | Pasta não confiável (`SECURELOAD`) | Veja `docs/distribuicao.md`, seção "Segurança" |

## 7. Checklist de verificação (faça no seu ambiente)

1. Instale a versão compilada em uma máquina/perfil limpo.
2. Abra um desenho e digite `HYDROPLUGINS`: devem aparecer
   `core`, `persistencia`, `xdata`, `precipitacao`, `sarjetas`, `secao`, `metodos-chuva-vazao`, `bacia`, `hidrograma`, `visualizador`
   (e `hydro`).
3. Abra um **segundo desenho** na mesma sessão e repita: o `PerDocument` deve
   ter carregado o Hydro nele também.
4. Rode `HYDROTESTE` (carregue antes `tests/teste_manual.lsp`).
5. Rode `HYDRODADOS`, abra o diálogo e exporte um CSV.
6. Teste em um desenho com a pasta fora dos caminhos de suporte para validar a
   descoberta da raiz.
