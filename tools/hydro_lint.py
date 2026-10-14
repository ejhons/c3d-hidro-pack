#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
hydro_lint.py - verifica a fronteira publico/privado entre plugins AutoLISP.

Convencao verificada
  - Cada plugin tem um prefixo (SAR:, BAC:, DB: ...). Os "donos" de um prefixo sao
    os arquivos que definem funcoes com ele (defun SAR:Calcular ...).
  - Nome iniciado por "_" apos o prefixo (SAR:_ParseSecao) e PRIVADO: so pode
    aparecer nos arquivos donos do prefixo. Uso em outro arquivo = ERRO.
  - O resto e publico. Entre plugins, o ideal e passar pelo registro (HYD:Send) e
    nao por chamada direta; --strict transforma chamada direta em erro, exceto para
    prefixos de infraestrutura declarados em --shared (ex.: DB, JSON).

Uso
  python hydro_lint.py [pasta] [--api] [--strict] [--shared DB,JSON,EXP,HYD]
  Codigo de saida 1 quando houver erros (serve para pre-commit / CI).

Config opcional: .hydrolint.json na pasta raiz
  {"shared": ["DB", "JSON"], "ignore_dirs": ["legado"]}

Limites
  - Chamadas montadas em tempo de execucao ((read (strcat "SAR:" nome))) nao sao vistas.
  - Referencias dentro de strings (ex.: "(SAR:OnOk)") e em .dcl contam como uso
    dinamico: entram no relatorio --api, mas nunca geram erro.
"""
import argparse
import bisect
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

NAME = r"[^\s()'\"`;]+"
DEFUN_RE = re.compile(r"\(\s*defun(?:-q)?\s+(" + NAME + r")", re.I)
REF_RE = re.compile(r"(?<![\w:.\-])([A-Za-z][\w\-]*):([^\s()'\"`;:]+)")
IGNORE_DIRS = {".git", "node_modules", "__pycache__", ".venv", "build", "dist"}


def blank(s):
    """Troca tudo por espacos, preservando quebras de linha (mantem as posicoes)."""
    return re.sub(r"[^\n]", " ", s)


def mask(src):
    """Devolve (codigo sem comentarios/strings, [(pos, conteudo_da_string)])."""
    out, strings = [], []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            j = min(j, n)
            strings.append((i + 1, src[i + 1:j]))
            out.append('"' + blank(src[i + 1:j]) + ('"' if j < n else ""))
            i = j + 1
        elif src.startswith(";|", i):
            j = src.find("|;", i + 2)
            j = n if j < 0 else j + 2
            out.append(blank(src[i:j]))
            i = j
        elif c == ";":
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(blank(src[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out), strings


def read_text(p):
    try:
        return p.read_text(encoding="utf-8-sig")
    except UnicodeDecodeError:
        return p.read_text(encoding="cp1252", errors="replace")


def collect_files(root, ignore):
    files = []
    for p in sorted(root.rglob("*")):
        if p.suffix.lower() not in (".lsp", ".dcl") or not p.is_file():
            continue
        if set(p.relative_to(root).parts[:-1]) & ignore:
            continue
        files.append(p)
    return files


def scan(root, files):
    defs = {}          # PREFIXO -> {"label", "files", "funcs"}
    uses = []          # (arquivo, linha, PREFIXO, nome, tipo) tipo: code | dyn | dcl
    noprefix = []      # (arquivo, linha, nome) defun sem prefixo e que nao e c:
    for p in files:
        rel = p.relative_to(root).as_posix()
        text = read_text(p)
        nl = [m.start() for m in re.finditer("\n", text)]

        def line_of(pos):
            return bisect.bisect_left(nl, pos) + 1

        if p.suffix.lower() == ".dcl":
            for m in REF_RE.finditer(text):
                if m.group(1).lower() != "c":
                    uses.append((rel, line_of(m.start()), m.group(1).upper(), m.group(2), "dcl"))
            continue

        code, strings = mask(text)
        skip = set()
        for m in DEFUN_RE.finditer(code):
            full = m.group(1)
            skip.add(m.start(1))
            line = line_of(m.start(1))
            if ":" in full:
                pre, name = full.split(":", 1)
                if pre.lower() == "c" or not name:
                    continue
                d = defs.setdefault(pre.upper(), {"label": pre, "files": set(), "funcs": {}})
                d["files"].add(rel)
                d["funcs"][name.upper()] = {"name": name, "file": rel, "line": line}
            else:
                noprefix.append((rel, line, full))
        for m in REF_RE.finditer(code):
            if m.start(1) in skip or m.group(1).lower() == "c":
                continue
            uses.append((rel, line_of(m.start(1)), m.group(1).upper(), m.group(2), "code"))
        for pos, s in strings:
            for m in REF_RE.finditer(s):
                if m.group(1).lower() != "c":
                    uses.append((rel, line_of(pos + m.start()), m.group(1).upper(), m.group(2), "dyn"))
    return defs, uses, noprefix


def analyze(defs, uses, shared, strict):
    errors, warns = [], []
    ext = defaultdict(lambda: defaultdict(set))   # PREFIXO -> NOME -> {(arquivo, tipo)}
    dcl = defaultdict(set)                         # PREFIXO -> {NOME} usados por callback DCL
    dep = defaultdict(lambda: defaultdict(set))    # arquivo -> PREFIXO -> {nomes} (so codigo)
    for f, line, pre, name, kind in uses:
        d = defs.get(pre)
        if d is None:
            if kind == "code" and name.startswith("_"):
                warns.append(f"{f}:{line}  {pre}:{name}  (prefixo sem nenhum defun nos arquivos analisados)")
            continue
        if kind == "dcl":
            dcl[pre].add(name.upper())
            continue
        if f in d["files"]:
            continue
        if kind == "code" and name.startswith("_"):
            errors.append(f"{f}:{line}  {d['label']}:{name}  e privada de {', '.join(sorted(d['files']))}")
            continue
        ext[pre][name.upper()].add((f, kind))
        if kind == "code":
            dep[f][pre].add(name)
            if strict and pre not in shared:
                errors.append(f"{f}:{line}  chamada direta a {d['label']}:{name} "
                              f"(plugin {', '.join(sorted(d['files']))}); use o registro")
    return errors, warns, ext, dcl, dep


def print_api(defs, ext, dcl, shared):
    print("\n== API por plugin ==")
    for pre in sorted(defs):
        d = defs[pre]
        tag = "  [infra]" if pre in shared else ""
        print(f"\n{d['label']}:  ({', '.join(sorted(d['files']))}){tag}")
        pub = sorted((v["name"] for k, v in d["funcs"].items() if not k.startswith("_")), key=str.lower)
        priv = sorted((v["name"] for k, v in d["funcs"].items() if k.startswith("_")), key=str.lower)
        used, internal = [], []
        for name in pub:
            users = sorted({f for f, _ in ext[pre].get(name.upper(), ())})
            if users:
                used.append(f"{name} <- {', '.join(users)}")
            elif name.upper() in dcl[pre]:
                internal.append(f"{name} (callback DCL)")
            else:
                internal.append(f"{name} (candidata a _privada)")
        print("  publicas usadas fora:")
        print("".join(f"    {u}\n" for u in used) or "    -\n", end="")
        print("  publicas so internas:")
        print("".join(f"    {u}\n" for u in internal) or "    -\n", end="")
        print(f"  privadas: {len(priv)}")


def main():
    ap = argparse.ArgumentParser(description="Lint de fronteira publico/privado para plugins AutoLISP")
    ap.add_argument("root", nargs="?", default=".", help="pasta raiz (padrao: atual)")
    ap.add_argument("--api", action="store_true", help="lista a API publica de cada plugin")
    ap.add_argument("--strict", action="store_true",
                    help="chamada direta entre plugins (fora de --shared) vira erro")
    ap.add_argument("--shared", default="", help="prefixos de infraestrutura, separados por virgula")
    args = ap.parse_args()

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    root = Path(args.root).resolve()
    cfg = {}
    cfg_path = root / ".hydrolint.json"
    if cfg_path.is_file():
        cfg = json.loads(read_text(cfg_path))
    shared = {s.strip().upper() for s in args.shared.split(",") if s.strip()}
    shared |= {s.upper() for s in cfg.get("shared", [])}
    ignore = IGNORE_DIRS | set(cfg.get("ignore_dirs", []))

    files = collect_files(root, ignore)
    if not files:
        print(f"Nenhum .lsp encontrado em {root}")
        return 0
    defs, uses, noprefix = scan(root, files)
    errors, warns, ext, dcl, dep = analyze(defs, uses, shared, args.strict)

    print(f"{len(files)} arquivo(s), {len(defs)} prefixo(s): "
          + ", ".join(f"{d['label']}:" for _, d in sorted(defs.items())))

    if errors:
        print("\n== ERROS ==")
        print("\n".join(sorted(errors)))
    if warns or noprefix:
        print("\n== AVISOS ==")
        for w in sorted(warns):
            print(w)
        for f, line, name in noprefix:
            print(f"{f}:{line}  defun sem prefixo: {name}")

    print("\n== Dependencias entre arquivos (chamadas diretas) ==")
    if not dep:
        print("(nenhuma)")
    for f in sorted(dep):
        parts = [f"{defs[pre]['label']}: {', '.join(sorted(names, key=str.lower))}"
                 for pre, names in sorted(dep[f].items())]
        print(f"{f} -> " + " | ".join(parts))

    if args.api:
        print_api(defs, ext, dcl, shared)

    print(f"\n{len(errors)} erro(s), {len(warns) + len(noprefix)} aviso(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
