#!/usr/bin/env python3
"""
gerar_icones.py - gera os icones das barras de ferramentas do Hydro.

Uso:   python build/gerar_icones.py                 (BMP, 16x16 e 24x24)
       python build/gerar_icones.py --formato png    (PNG em vez de BMP)
       python build/gerar_icones.py --previa         (tambem grava uma folha de contato PNG)

Saida: Hydro.bundle/Contents/resources/icons/
         <id>_16.bmp / <id>_24.bmp    um par por acao do painel ("." do id vira "_")
         _grupo_<ordem>_16/24         icone do grupo (usado quando a acao nao tem icone)
         _padrao_16/24                icone generico (ultimo recurso)

COMO SAO OS ICONES
  Quadrado colorido por GRUPO com um codigo de ate 3 caracteres (fonte de
  pixels 3x5 propria, sem depender de fontes do sistema). Os codigos estao no
  dicionario CODIGOS abaixo; acao sem codigo recebe as iniciais do rotulo.

SUBSTITUIR POR ICONES SEUS
  Basta colocar na pasta arquivos com o MESMO NOME (ex.: bacia_cadastrar_16.bmp
  e bacia_cadastrar_24.bmp). Depois de criar os seus, nao rode este script de
  novo sobre eles sem --so-faltantes (que so cria o que nao existe).
  Para botao de plugin novo: crie <id>_16/24 ou deixe cair no icone do grupo.
"""
import argparse
import glob
import os
import re
import sys

from PIL import Image, ImageDraw

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CONTENTS = os.path.join(RAIZ, 'Hydro.bundle', 'Contents')
DESTINO = os.path.join(CONTENTS, 'resources', 'icons')

# ---- fonte de pixels 3x5 (cada linha: 3 bits) ----
FONTE = {
    'A': '010 101 111 101 101', 'B': '110 101 110 101 110', 'C': '011 100 100 100 011',
    'D': '110 101 101 101 110', 'E': '111 100 110 100 111', 'F': '111 100 110 100 100',
    'G': '011 100 101 101 011', 'H': '101 101 111 101 101', 'I': '111 010 010 010 111',
    'J': '001 001 001 101 010', 'K': '101 101 110 101 101', 'L': '100 100 100 100 111',
    'M': '101 111 111 101 101', 'N': '110 101 101 101 101', 'O': '010 101 101 101 010',
    'P': '110 101 110 100 100', 'Q': '010 101 101 110 011', 'R': '110 101 110 101 101',
    'S': '011 100 010 001 110', 'T': '111 010 010 010 010', 'U': '101 101 101 101 111',
    'V': '101 101 101 101 010', 'W': '101 101 111 111 101', 'X': '101 101 010 101 101',
    'Y': '101 101 010 010 010', 'Z': '111 001 010 100 111',
    '0': '111 101 101 101 111', '1': '010 110 010 010 111', '2': '111 001 111 100 111',
    '3': '111 001 111 001 111', '4': '101 101 111 001 001', '5': '111 100 111 001 111',
    '6': '111 100 111 101 111', '7': '111 001 001 010 010', '8': '111 101 111 101 111',
    '9': '111 101 111 001 111',
    '+': '000 010 111 010 000', '-': '000 000 111 000 000', '>': '100 010 001 010 100',
    '/': '001 001 010 100 100', '=': '000 111 000 111 000', '?': '111 001 011 000 010',
}

# ---- cor por grupo (ordem-grupo -> RGB) ----
CORES = {
    10: (41, 98, 168),     # Dados e IDF       azul
    20: (24, 128, 106),    # Bacias            verde-agua
    30: (214, 117, 28),    # Hidrogramas       laranja
    40: (112, 72, 160),    # Objetos e ligacoes roxo
    50: (176, 58, 58),     # Sarjetas e secoes vermelho
    60: (96, 112, 128),    # Texto e parametros cinza-azulado
    90: (64, 64, 64),      # Sistema           cinza escuro
}
COR_PADRAO = (80, 80, 80)

# ---- codigos de ate 3 caracteres por id de acao ----
CODIGOS = {
    'idf.calcular': 'IDF', 'idf.parametros': 'PAR', 'idf.tr': 'TR', 'superficie': 'TIN',
    'bacia.cadastrar': 'CAD', 'bacia.calcular': 'QP', 'bacia.calctexto': 'Q+T',
    'bacia.texto': 'TXT', 'bacia.info': 'INF', 'bacia.lista': 'LST', 'bacia.tabela': 'TAB',
    'hid.gerar': 'HID', 'hid.ver': 'VER',
    'obj.cadastrar': 'OBJ', 'obj.info': 'INF', 'lig.ligar': 'LIG', 'lig.desligar': 'DES',
    'obj.calcular': 'CAL', 'lig.tabela': 'TAB', 'lig.validar': 'VAL', 'obj.remover': 'DEL',
    'sarj.calc1': 'SA1', 'sarj.calc3': 'SA3', 'sarj.txt1': 'TX1', 'sarj.txt3': 'TX3',
    'secao.ver': 'SEC', 'secao.criar': 'NEW', 'secao.atual': 'SEL', 'sarj.params': 'PAR',
    'txt.runoff': 'RUN', 'txt.altura': 'ALT', 'txt.rotacao': 'ROT',
    'sis.dados': 'DB', 'sis.dump': 'TXT', 'sis.plugins': 'PLG', 'sis.reload': 'RLD',
    'sis.dir': 'DIR', 'sis.macros': 'MAC', 'sis.macroestilo': 'MST', 'sis.teste': 'TST',
    'sis.menu': 'MNU', 'sis.menuremover': 'MN-', 'sis.barras': 'TLB', 'sis.barrasremover': 'TL-',
}


def base(acao_id):
    """id da acao -> nome-base do arquivo (mesma regra do toolbar.lsp)."""
    return acao_id.replace('.', '_').replace(' ', '_')


def texto_para_icone(txt):
    return ''.join(c for c in txt.upper() if c in FONTE)[:3]


def iniciais(rotulo):
    palavras = [w for w in re.split(r'[^A-Za-z0-9]+', rotulo) if w]
    return texto_para_icone(''.join(w[0] for w in palavras)[:3] or '?')


def escurece(rgb, f=0.72):
    return tuple(int(c * f) for c in rgb)


def clareia(rgb, f=0.35):
    return tuple(int(c + (255 - c) * f) for c in rgb)


def desenha(codigo, cor, tam):
    """Quadrado colorido com borda, brilho no topo e o codigo em pixels."""
    img = Image.new('RGB', (tam, tam), cor)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, tam - 1, tam - 1], outline=escurece(cor))
    d.line([(1, 1), (tam - 2, 1)], fill=clareia(cor))          # brilho
    esc = 1 if tam <= 16 else 2                                # escala da fonte
    n = len(codigo)
    larg = n * 3 * esc + (n - 1) * esc
    alt = 5 * esc
    x0 = (tam - larg) // 2
    y0 = (tam - alt) // 2 + (1 if tam <= 16 else 1)
    for i, ch in enumerate(codigo):
        linhas = FONTE[ch].split()
        for r, bits in enumerate(linhas):
            for c, b in enumerate(bits):
                if b == '1':
                    x = x0 + i * (3 + 1) * esc + c * esc
                    y = y0 + r * esc
                    d.rectangle([x, y, x + esc - 1, y + esc - 1], fill=(255, 255, 255))
    return img


def acoes_do_projeto():
    """(id, ordem-grupo, rotulo, grupo) de todos os PNL:Acao do bundle."""
    achadas = []
    padrao = re.compile(
        r'\(PNL:Acao\s+"([^"]*)"\s+"([^"]*)"\s+(\d+)\s+(\d+)\s+"([^"]*)"\s+"([^"]+)"')
    for f in sorted(glob.glob(os.path.join(CONTENTS, '**', '*.lsp'), recursive=True)):
        with open(f, encoding='utf-8', errors='replace') as fh:
            for m in padrao.finditer(fh.read()):
                achadas.append((m[1], int(m[3]), m[5], m[2]))
    return achadas


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--formato', choices=('bmp', 'png'), default='bmp')
    ap.add_argument('--so-faltantes', action='store_true', help='nao sobrescreve icones existentes')
    ap.add_argument('--previa', action='store_true', help='grava build/previa_icones.png (folha de contato)')
    a = ap.parse_args()

    os.makedirs(DESTINO, exist_ok=True)
    acoes = acoes_do_projeto()
    if not acoes:
        print('Nenhum PNL:Acao encontrado.')
        return 1

    pedidos = []   # (nome_base, codigo, cor)
    grupos = {}
    for aid, og, rot, grupo in acoes:
        cor = CORES.get(og, COR_PADRAO)
        cod = texto_para_icone(CODIGOS[aid]) if aid in CODIGOS else iniciais(rot)
        if aid not in CODIGOS:
            print('  aviso: "%s" sem codigo proprio; usando iniciais "%s"' % (aid, cod))
        pedidos.append((base(aid), cod, cor))
        grupos.setdefault(og, (grupo, cor))
    for og, (grupo, cor) in sorted(grupos.items()):
        pedidos.append(('_grupo_%d' % og, texto_para_icone(grupo[:2]) or '?', cor))
    pedidos.append(('_padrao', '?', COR_PADRAO))

    n = 0
    folha = []
    for nome, cod, cor in pedidos:
        for tam in (16, 24):
            caminho = os.path.join(DESTINO, '%s_%d.%s' % (nome, tam, a.formato))
            if a.so_faltantes and os.path.exists(caminho):
                continue
            img = desenha(cod, cor, tam)
            img.save(caminho)
            n += 1
            if tam == 24:
                folha.append((nome, img))
    print('%d icone(s) gravado(s) em %s' % (n, os.path.relpath(DESTINO, RAIZ)))

    if a.previa and folha:
        colunas = 10
        lin = (len(folha) + colunas - 1) // colunas
        cel = 24 * 3 + 10
        tela = Image.new('RGB', (colunas * cel, lin * cel), (235, 235, 235))
        for i, (_, img) in enumerate(folha):
            grande = img.resize((72, 72), Image.NEAREST)
            tela.paste(grande, ((i % colunas) * cel + 5, (i // colunas) * cel + 5))
        saida = os.path.join(RAIZ, 'build', 'previa_icones.png')
        tela.save(saida)
        print('previa: build/previa_icones.png')
    return 0


if __name__ == '__main__':
    sys.exit(main())
