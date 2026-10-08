# Tutorial: PackageContents.xml e distribuição (Autoloader)

Baseado na documentação oficial da Autodesk sobre *plug-in bundles*
("About Installing and Uninstalling Plug-In Applications" e as referências de
`PackageContents.xml`). Os atributos citados foram conferidos nessa
documentação; o comportamento no seu AutoCAD/Civil 3D deve ser confirmado com
o checklist do fim deste arquivo.

---

## 1. Como o Autoloader funciona

O **Autoloader** é o mecanismo do AutoCAD (e dos produtos baseados nele, como
o Civil 3D) para instalar plug-ins por **cópia de pasta**, sem instalador.

1. Um plug-in é uma pasta com extensão `.bundle`.
2. Dentro dela há um `PackageContents.xml` que descreve o plug-in: nome,
   versão, quais produtos/versões suportam e quais arquivos carregar.
3. Ao iniciar, o AutoCAD **procura bundles** em três pastas:

   | Escopo | Pasta (Windows) |
   |---|---|
   | Instalação geral | `%PROGRAMFILES%\Autodesk\ApplicationPlugins` |
   | Todos os usuários | `%ALLUSERSPROFILE%\Autodesk\ApplicationPlugins` |
   | Usuário atual | `%APPDATA%\Autodesk\ApplicationPlugins` |

4. Para cada bundle, lê o XML, **confere os requisitos** (sistema, produto,
   versão) e, se atender, **registra e carrega** os componentes.
5. Se o bundle for copiado com o AutoCAD **aberto**, ele é registrado na hora
   (sem reiniciar), conforme o valor da variável `APPAUTOLOAD`. Com
   `APPAUTOLOAD = 0` nada carrega a menos que você use o comando
   `APPAUTOLOADER`.
6. **Desinstalar** = apagar a pasta `.bundle`.

## 2. A estrutura do bundle do Hydro

```
Hydro.bundle/
├─ PackageContents.xml
└─ Contents/
    ├─ hydro.lsp            ← único componente carregado pelo Autoloader
    ├─ core/core.lsp
    ├─ plugins/*.lsp
    ├─ plugins/registry/*.lsp
    ├─ views/*.lsp
    └─ resources/
        ├─ dcl/             (.dcl)
        └─ slides/          (.sld)
```

Regras do formato: caminhos usam `/` (nunca `\`) e são **relativos à pasta
`.bundle`** (por isso `./Contents/hydro.lsp`).

## 3. O `PackageContents.xml` do Hydro, linha por linha

```xml
<ApplicationPackage
    SchemaVersion="1.0"
    AppVersion="1.0.0"
    ProductCode="{GUID}"
    UpgradeCode="{GUID}"
    Name="Hydro - Drenagem para Civil 3D"
    Description="..."
    Author="...">
```

| Atributo | Para que serve | Observação |
|---|---|---|
| `SchemaVersion` | Versão do formato do XML | Sempre `1.0` |
| `AppVersion` | Versão do seu plug-in | Use 4 partes se quiser (`1.0.0.0`). O AutoCAD compara este valor para saber se há versão mais nova |
| `ProductCode` | GUID desta **versão** | **Gere um novo a cada `AppVersion`** (para atualizações funcionarem) |
| `UpgradeCode` | GUID do **produto** | **Nunca mude.** Identifica "o mesmo plug-in" entre versões |
| `Name`, `Description`, `Author` | Textos exibidos | Recomendados; `Author` é opcional em instalação local |

Gerar GUIDs: PowerShell `[guid]::NewGuid()` ou o `GuidGen.exe`.

```xml
  <Components>
    <RuntimeRequirements
        OS="Win64"
        Platform="AutoCAD*"
        SeriesMin="R21.0"
        SupportPath="./Contents;./Contents/resources/dcl;./Contents/resources/slides" />
```

| Atributo | Significado |
|---|---|
| `OS` | `Win64`, `Win32`, `Mac` (separe com `\|`). O Hydro usa DCL e `vla-*`, então: Windows |
| `Platform` | `AutoCAD*` = todos os produtos baseados em AutoCAD (inclui Civil 3D). Para limitar só ao Civil 3D use `Civil3D` |
| `SeriesMin` / `SeriesMax` | Faixa de versões suportadas. A versão aparece em `(getvar "ACADVER")` ou no Registro. Se omitir um dos dois, aquele lado fica sem limite |
| `SupportPath` | Pastas (relativas ao bundle, separadas por `;`) **acrescentadas ao caminho de suporte** enquanto o plug-in está carregado |

Alguns números de série: AutoCAD 2017 = `R21.0`, 2018 = `R22.0`,
2019 = `R23.0`, 2020 = `R23.1`, 2021 = `R24.0`, 2022 = `R24.1`,
2023 = `R24.2`, 2024 = `R24.3`. Confirme o da sua versão com `ACADVER`.

O `SupportPath` é o que permite ao `hydro.lsp` se localizar com
`(findfile "hydro.lsp")` e ao `viewer.dcl` ser achado só pelo nome.

```xml
    <ComponentEntry
        AppName="Hydro"
        Version="1.0.0"
        ModuleName="./Contents/hydro.lsp"
        AppDescription="..."
        PerDocument="True" />
  </Components>
</ApplicationPackage>
```

| Atributo | Significado |
|---|---|
| `AppName` | Nome do componente (opcional para AutoLISP) |
| `ModuleName` | Arquivo a carregar. A extensão define o tipo: `.lsp`, `.fas` ou `.vlx` (VLX só Windows) |
| `PerDocument` | **AutoLISP: carrega uma vez por documento** (padrão `True`). Necessário: cada desenho tem o seu ambiente AutoLISP, então as funções e variáveis precisam existir em cada um |
| Carregamento | Sem `LoadReasons`, vale o padrão: **carrega na inicialização** |

### Por que carregar na inicialização (e não sob demanda)?

O Autoloader permite `LoadOnCommandInvocation`: o código só carrega quando um
comando registrado é digitado (a documentação recomenda isso por desempenho).
Para isso você lista cada comando em um elemento `<Commands>`.

No Hydro isso **não compensa agora**: os plugins dependem uns dos outros e
registram eventos e rótulos ao carregar. Carregar tudo de uma vez é mais
simples e confiável. O custo de carga é pequeno (poucos arquivos, sem leitura
de desenho). Se um dia crescer, a evolução natural é separar em bundles
(um por plugin) com `<Dependencies>`.

### Quando trocar a extensão

Para a versão compilada, `ModuleName` deve apontar para `hydro.fas` ou
`hydro.vlx`. O `build/build.lsp` faz essa troca ao copiar o XML para `dist/`.

Outros elementos opcionais úteis: `<CompanyDetails>` (nome, e-mail, site),
`Icon` e `HelpFile` no `ApplicationPackage` (arquivo de ajuda: texto, HTML
ou PDF dentro do bundle), `<SystemVariables>`, `<EnvironmentVariables>` e
`<RegistryEntries>`.

## 4. Formas de distribuir

### 4.1 Cópia manual (testes internos)

1. Copie `Hydro.bundle` para `%APPDATA%\Autodesk\ApplicationPlugins`.
2. Reabra o AutoCAD/Civil 3D (ou use `APPAUTOLOADER`).

### 4.2 `instalar.bat` / `desinstalar.bat` (equipe pequena)

Em `build/`. O `instalar.bat` copia o bundle para a pasta do usuário atual:

```
build\instalar.bat                        (versão de desenvolvimento)
build\instalar.bat "..\dist\Hydro.bundle" (versão compilada)
```

Não pede administrador, porque usa `%APPDATA%`.

### 4.3 ZIP + instruções

Compacte `dist/Hydro.bundle` (a **pasta** inteira) e envie junto com o
`instalar.bat` ou com as instruções da seção 4.1. É o jeito mais simples de
compartilhar.

### 4.4 Instalador (MSI, Inno Setup, etc.)

Um instalador só precisa copiar a pasta `.bundle` para uma das três pastas do
Autoloader. Instalar em `%PROGRAMFILES%\Autodesk\ApplicationPlugins` exige
administrador, mas tem uma vantagem (próxima seção).

### 4.5 Rede da empresa

Para várias máquinas, use a implantação de TI (GPO/script) copiando o bundle
para `%PROGRAMFILES%` ou `%ALLUSERSPROFILE%`. Mantenha **uma única fonte**
na rede e um script que sincroniza.

### 4.6 Autodesk App Store

Possível, mas exige mais campos no XML (`Author`, `Name`, `Description`,
`Icon`, `HelpFile`, `ProductCode`, `UpgradeCode`, contato da empresa) e o
pacote é entregue por MSI. Só avalie quando o plug-in estiver estável.

## 5. Segurança (SECURELOAD e TRUSTEDPATHS)

Desde o AutoCAD 2014, aplicativos devem funcionar em **modo seguro**
(`SECURELOAD` = 1 ou 2): só carregam código de **locais confiáveis**, listados
em `TRUSTEDPATHS`.

- `%PROGRAMFILES%\Autodesk\ApplicationPlugins` é **confiável por padrão**, sem
  exigir assinatura digital.
- Em `%APPDATA%` ou `%ALLUSERSPROFILE%`, a pasta precisa ser confiável pelas
  preferências do aplicativo e, idealmente, o código deve ser **assinado**.

Para o seu uso pessoal, o caminho mais prático é adicionar a pasta
`...\Hydro.bundle\Contents` (com `...` no final, para incluir subpastas) em
**OPÇÕES → Arquivos → Locais confiáveis** ou na variável `TRUSTEDPATHS`.

Para distribuir a outras pessoas, a boa prática é assinar os `.fas`/`.vlx`
(veja `docs/compilacao.md`, seção 5).

## 6. Atualizações

1. Altere o código e rode o build.
2. Aumente `AppVersion` (ex.: `1.0.0` → `1.1.0`).
3. Gere um **novo `ProductCode`**; **mantenha** o `UpgradeCode`.
4. Atualize também `Version` do `ComponentEntry` (boa prática).
5. Substitua a pasta `.bundle` (o `instalar.bat` já remove a anterior).

## 7. Problemas comuns

| Sintoma | O que verificar |
|---|---|
| Nada carrega | `APPAUTOLOAD` = 0? Bundle está em uma das três pastas? Nome termina em `.bundle`? XML bem formado? |
| Carrega só em alguns produtos | `RuntimeRequirements`: `Platform`, `SeriesMin/Max`, `OS` |
| Aviso de segurança | Pasta fora de `TRUSTEDPATHS` (seção 5) |
| `findfile "hydro.lsp"` devolve nil | `SupportPath` com caminho errado ou bundle não carregado |
| Hydro carrega de uma pasta inesperada | Sobrou uma escolha antiga do `HYDRODIR` no Registro (`HKEY_CURRENT_USER\Software\Hydro`, valor `Dir`). Rode `HYDRODIR` → `Limpar` |
| Funciona no 1º desenho, não nos próximos | `PerDocument` ausente ou `False` |
| Editei o XML e nada mudou | Feche e reabra o AutoCAD (o descritor é lido quando o bundle é registrado) |
| `HYDROPLUGINS` não mostra tudo | Veja a linha de histórico `[HYDRO] ...` que o `core` imprime por módulo |

## 8. Checklist de teste da distribuição

1. Máquina (ou perfil de Windows) limpa, sem o Hydro.
2. Copie o bundle para `%APPDATA%\Autodesk\ApplicationPlugins`.
3. Abra o Civil 3D → histórico do comando deve mostrar `[HYDRO] Modulo carregado: ...`.
4. `HYDROPLUGINS` lista `core, persistencia, xdata, precipitacao, sarjetas, secao, metodos, bacia, hidrograma, visualizador, hydro`.
5. Abra um segundo desenho: repita 4.
6. Com `APPAUTOLOAD = 0`, use o comando `APPAUTOLOADER` para carregar o bundle manualmente.
7. Apague a pasta `.bundle`, reabra: nenhum comando do Hydro deve existir.
