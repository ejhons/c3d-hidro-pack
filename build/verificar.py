#!/usr/bin/env python3
"""
verificar.py - verificacao ESTATICA do projeto Hydro (nao substitui testar no AutoCAD).

Uso:   python build/verificar.py          (a partir da raiz do repositorio)
Saida: codigo 0 se tudo passou, 1 se houve problema.

Confere:
  1. parenteses e aspas balanceados em todos os .lsp
  2. codigo ASCII puro (sem acentos) nos .lsp e .dcl do bundle
     (excecao: resources/dcl/idf.dcl, mantido como o autor escreveu)
  3. chamadas a funcoes com prefixo do Hydro (HYDRO:, BAC:...) sem defun
  4. (setq x (and ...)) e (setq x (or ...)): em AutoLISP and/or devolvem T/nil
  5. defun duplicado no mesmo arquivo
  6. manifesto (HYDRO:Manifest) x arquivos existentes
  7. DCL: dialogo existe, chaves {} balanceadas e tiles usados no LISP existem
  8. models/*.lsp (exceto objetos_tipos): as 9 secoes padrao, na ordem, e sem "CALCULOS"
     como grupo de RESULT (ver .claude/skills/hydro-model)
  9. (AVISO, nao erro) comandos c:XXX sem botao no painel (PNL:Acao)
 10. icones: o padrao (_padrao_16/24) deve existir (erro); acao/grupo sem icone (aviso)
"""
import glob
import os
import re
import sys

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
BUNDLE = os.path.join(RAIZ, 'Hydro.bundle', 'Contents')
PREFIXOS = ('HYDRO', 'DB', 'XD', 'PREC', 'SARJ', 'VIEW', 'SJT', 'MET', 'TCM', 'BAC',
            'BTB', 'HID', 'HIET', 'OBJ', 'LIG', 'OTP', 'SOB', 'OBT', 'PNL', 'MNU', 'TLB', 'EXM', 'EXO', 'HB', 'HT', 'OPD', 'OPV', 'AUD', 'PAD', 'SUP', 'ETQ')
# (arquivo DCL, dialogo, arquivos .lsp que o usam)
DIALOGOS = (
    ('idf.dcl', 'idf_dialog', ['views/idf_view.lsp']),
    ('secao.dcl', 'secao_dialog', ['views/secao_view.lsp']),
    ('viewer.dcl', 'view_dialog', ['views/viewer.lsp']),
    ('hidrograma.dcl', 'hidro_dialog', ['views/hidrograma_view.lsp']),
    ('bacia_tabela.dcl', 'bacias_dialog', ['views/bacia_tabela.lsp']),
    ('ligacoes.dcl', 'ligacoes_dialog', ['views/objetos_tabela.lsp']),
)

problemas = []


def erro(msg):
    problemas.append(msg)
    print('  PROBLEMA:', msg)


def ler(caminho):
    with open(caminho, encoding='utf-8', errors='replace') as f:
        return f.read()


def sem_strings_e_comentarios(s):
    s = re.sub(r'"(?:\\.|[^"\\])*"', '""', s)
    return re.sub(r';[^\n]*', '', s)


def balanceado(s):
    prof, i, em_str = 0, 0, False
    while i < len(s):
        c = s[i]
        if em_str:
            if c == '\\':
                i += 1
            elif c == '"':
                em_str = False
        else:
            if c == ';':
                while i < len(s) and s[i] != '\n':
                    i += 1
                continue
            if c == '"':
                em_str = True
            elif c == '(':
                prof += 1
            elif c == ')':
                prof -= 1
                if prof < 0:
                    return False
        i += 1
    return prof == 0 and not em_str


def main():
    lsps = sorted(glob.glob(os.path.join(RAIZ, '**', '*.lsp'), recursive=True))
    print('[1/10] parenteses e aspas (%d arquivos .lsp)' % len(lsps))
    for f in lsps:
        if not balanceado(ler(f)):
            erro('desbalanceado: ' + os.path.relpath(f, RAIZ))

    print('[2/10] ASCII')
    alvo = lsps + sorted(glob.glob(os.path.join(BUNDLE, 'resources', 'dcl', '*.dcl')))
    for f in alvo:
        if os.path.basename(f) == 'idf.dcl':
            continue
        if any(ord(ch) > 127 for ch in ler(f)):
            erro('caractere nao-ASCII: ' + os.path.relpath(f, RAIZ))

    print('[3/10] chamadas sem defun')
    defs, chamadas = set(), {}
    padrao = r"[\(']\s*((?:%s):[^\s()]+)" % '|'.join(PREFIXOS)
    for f in lsps:
        s = sem_strings_e_comentarios(ler(f))
        defs |= {m.upper() for m in re.findall(r'\(defun\s+([^\s()]+)', s)}
        for m in re.findall(padrao, s):
            chamadas.setdefault(m.upper(), set()).add(os.path.relpath(f, RAIZ))
    # funcoes aceitas sem defun: variaveis globais do core e conhecidas
    ignora = {'VIEW:_CSVCELULA'}   # falso positivo: definida com outro espacamento
    for nome, arqs in sorted(chamadas.items()):
        if nome not in defs and not nome.endswith('*') and nome not in ignora:
            erro('%s chamada e nao definida (%s)' % (nome, ', '.join(sorted(arqs))))

    print('[4/10] and/or usados como valor')
    for f in lsps:
        s = sem_strings_e_comentarios(ler(f))
        for m in re.finditer(r'\(setq\s+\S+\s+\((?:and|or)\b', s):
            erro('%s: %s  (and/or devolvem T/nil, nunca o valor)'
                 % (os.path.relpath(f, RAIZ), m.group(0)))

    print('[5/10] defun duplicado')
    for f in lsps:
        nomes = re.findall(r'^\(defun\s+(\S+)', ler(f), re.M)
        for n in sorted({n for n in nomes if nomes.count(n) > 1}):
            erro('defun duplicado em %s: %s' % (os.path.relpath(f, RAIZ), n))

    print('[6/10] manifesto')
    core = ler(os.path.join(BUNDLE, 'core', 'core.lsp'))
    m = re.search(r"\(defun HYDRO:Manifest \(\)\s*'\((.*?)\)\s*\)", core, re.S)
    mods = re.findall(r'"((?:plugins|views)/[^"]+)"', m.group(1)) if m else []
    if not mods:
        erro('nao consegui ler HYDRO:Manifest')
    for mod in mods:
        if not os.path.exists(os.path.join(BUNDLE, mod + '.lsp')):
            erro('modulo do manifesto sem arquivo: ' + mod)
    existentes = {os.path.splitext(os.path.relpath(f, BUNDLE))[0].replace(os.sep, '/')
                  for pasta in ('plugins', 'plugins/models', 'plugins/registry', 'views')
                  for f in glob.glob(os.path.join(BUNDLE, pasta, '*.lsp'))}
    for sobra in sorted(existentes - set(mods)):
        erro('plugin/view fora do manifesto: ' + sobra)

    print('[7/10] DCL x LISP')
    for dcl, dialogo, usuarios in DIALOGOS:
        caminho = os.path.join(BUNDLE, 'resources', 'dcl', dcl)
        if not os.path.exists(caminho):
            erro('DCL ausente: ' + dcl)
            continue
        txt = ler(caminho)
        if not re.search(r'\b%s\s*:\s*dialog' % dialogo, txt):
            erro('%s: dialogo %s nao definido' % (dcl, dialogo))
        if txt.count('{') != txt.count('}'):
            erro('%s: chaves {} desbalanceadas' % dcl)
        chaves = set(re.findall(r'key\s*=\s*"([^"]+)"', txt))
        for u in usuarios:
            s = ler(os.path.join(BUNDLE, u))
            usados = set()
            for fn in ('set_tile', 'action_tile', 'mode_tile', 'start_list', 'get_tile'):
                usados |= set(re.findall(r'\(%s\s+\\?"([^"\\]+)' % fn, s))
            for lista in re.findall(r"\(foreach k '\(([^)]*)\)", s):
                usados |= set(re.findall(r'"([^"]+)"', lista))
            for k in sorted(usados - chaves):
                # chaves montadas por strcat (ex.: "ex" + numero) nao sao conferidas
                if k not in ('ex',):
                    erro('%s usa o tile "%s" que nao existe em %s' % (u, k, dcl))

    print('[8/10] secoes dos models')
    secoes = ('UTILITARIOS', 'GEOMETRIA (CARACTERIZACAO)', 'LER, GRAVAR, EDITAR, REMOVER',
              'CAMPOS (CARACT, PARAMS e ATRIB)', 'RESULTADOS (RESULT)', 'CALCULOS',
              'RESUMO E FORMATACAO', 'TIPO NO CATALOGO', 'COMANDOS E INTERACAO')
    for caminho in sorted(glob.glob(os.path.join(BUNDLE, 'plugins', 'models', '*.lsp'))):
        nome = os.path.basename(caminho)
        if nome == 'objetos_tipos.lsp':
            continue
        txt = ler(caminho)
        pos = 0
        for i, sec in enumerate(secoes, 1):
            m = re.search(r'^;;; %d\. %s' % (i, re.escape(sec)), txt[pos:], re.M)
            if not m:
                erro('models/%s: secao "%d. %s" ausente ou fora de ordem' % (nome, i, sec))
                break
            pos += m.end()
        # comandos padrao do objeto (docs/arquitetura.md secao 18b): <P>CAD, <P>S, <P>INFO, <P>ZOOM
        # (P = nome do arquivo em maiusculas; bacia.lsp -> BACIACAD, BACIAS, BACIAINFO, BACIAZOOM)
        pref = os.path.splitext(nome)[0].upper()
        defs = {m.upper() for m in re.findall(r'^\(defun c:([A-Za-z0-9_]+)', txt, re.M)}
        for suf in ('CAD', 'S', 'INFO', 'ZOOM'):
            if pref + suf not in defs:
                erro('models/%s: falta o comando padrao c:%s%s' % (nome, pref, suf))
        if re.search(r'\(cons "CALCULOS"|"CALCULOS" \. \(', txt):
            erro('models/%s: RESULT nao usa mais o grupo "CALCULOS" (use VAZAO, HIDRAULICA...)' % nome)

    print('[9/10] comandos sem botao no painel (aviso)')
    comandos = set()
    for f in glob.glob(os.path.join(BUNDLE, '**', '*.lsp'), recursive=True):
        comandos |= {m.upper() for m in re.findall(r'^\(defun c:([A-Za-z0-9_]+)', ler(f), re.M)}
    com_botao = set()
    for f in glob.glob(os.path.join(BUNDLE, '**', '*.lsp'), recursive=True):
        for m in re.findall(r'\(PNL:Acao\s+"[^"]*"\s+"[^"]*"\s+\d+\s+\d+\s+"[^"]*"\s+"([^"]+)"', ler(f)):
            com_botao.add(m.upper())
    # de proposito sem botao: depuracao do DB e alias com typo mantido por compatibilidade
    sem_botao_ok = {'SETUSERVALUE', 'GETUSERVALUE', 'ATUALIZARUNFOFF', 'HYDRO', 'HYDROPAINEL'}
    # comandos de tests/ (ex.: HYDROTESTE) existem, mas fora do bundle
    comandos_tests = set()
    for f in glob.glob(os.path.join(RAIZ, 'tests', '*.lsp')):
        comandos_tests |= {m.upper() for m in re.findall(r'^\(defun c:([A-Za-z0-9_]+)', ler(f), re.M)}
    for c in sorted(comandos - com_botao - sem_botao_ok):
        print('  AVISO: comando %s sem botao no painel (painel_acoes.lsp ou PNL:Acao no proprio plugin)' % c)
    for c in sorted(com_botao - comandos - comandos_tests):
        erro('botao do painel aponta para comando inexistente: ' + c)

    print('[10/10] icones das barras de ferramentas')
    pasta = os.path.join(BUNDLE, 'resources', 'icons')
    for base in ('_padrao',):
        for tam in (16, 24):
            if not (os.path.exists(os.path.join(pasta, '%s_%d.bmp' % (base, tam)))
                    or os.path.exists(os.path.join(pasta, '%s_%d.png' % (base, tam)))):
                erro('icone padrao ausente: %s_%d' % (base, tam))
    ogs = set()
    for f in glob.glob(os.path.join(BUNDLE, '**', '*.lsp'), recursive=True):
        for m in re.finditer(r'\(PNL:Acao\s+"([^"]*)"\s+"[^"]*"\s+(\d+)\s+\d+', ler(f)):
            ident, og = m.group(1), m.group(2)
            ogs.add(og)
            nome = ident.replace('.', '_').replace(' ', '_')
            tem = lambda b: any(os.path.exists(os.path.join(pasta, '%s_%d.%s' % (b, t, e)))
                                for t in (16, 24) for e in ('bmp', 'png'))
            if not tem(nome):
                print('  AVISO: acao "%s" sem icone proprio (rode python build/gerar_icones.py --so-faltantes)' % ident)
    for og in sorted(ogs):
        if not any(os.path.exists(os.path.join(pasta, '_grupo_%s_%d.%s' % (og, t, e)))
                   for t in (16, 24) for e in ('bmp', 'png')):
            print('  AVISO: grupo de ordem %s sem icone de grupo' % og)

    print()
    if problemas:
        print('%d problema(s).' % len(problemas))
        return 1
    print('Tudo certo (verificacao estatica). Falta testar no AutoCAD: HYDROTESTE.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
