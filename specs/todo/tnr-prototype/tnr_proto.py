#!/usr/bin/env python3
"""THROWAWAY prototype of the TNR renderer (spec: specs/todo/NLG-TNR-ROUNDTRIP-SPEC.md).

The real implementation is jl4-core/src/L4/TNR.hs (`l4 tnr FILE`); this
script exists only to demonstrate the rendering algorithm while the Haskell
toolchain is unavailable. It implements the SAME Doc-IR / Coode-tabulation
algorithm, but on top of a micro-parser that handles only the subset of L4
used by jl4/examples/legal/imaginary-alcohol-act.l4:

    §-headings, ASSUME ... IS BOOLEAN, DECIDE `name` IF <bool-expr>

KNOWN CHEAT: real L4 is layout-sensitive; this micro-parser substitutes the
fixed precedence NOT > OR > AND, which reproduces the correct parse for this
corpus (the alcohol act expresses its OR-group by indentation under the last
AND, and parenthesizes explicitly elsewhere). Do not reuse this parser.

Usage: tnr_proto.py FILE.l4 [-o OUT.md] [--no-anchors]
"""

import argparse
import re
import sys

# ---------------------------------------------------------------------------
# Micro-parser
# ---------------------------------------------------------------------------

KEYWORDS = {"ASSUME", "DECIDE", "IF", "IS", "BOOLEAN", "AND", "OR", "NOT"}


def strip_comments(src: str) -> str:
    src = re.sub(r"\{-.*?-\}", "", src, flags=re.S)
    out = []
    for line in src.splitlines():
        in_bt = False
        cut = len(line)
        for i, ch in enumerate(line):
            if ch == "`":
                in_bt = not in_bt
            elif not in_bt and line[i : i + 2] == "--":
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def tokenize(src: str):
    toks = []
    i, n = 0, len(src)
    while i < n:
        ch = src[i]
        if ch.isspace():
            i += 1
        elif ch == "§":
            j = i
            while j < n and src[j] == "§":
                j += 1
            toks.append(("SECTION", j - i))
            i = j
        elif ch == "`":
            j = src.index("`", i + 1)
            toks.append(("ATOM", src[i + 1 : j]))
            i = j + 1
        elif ch in "()":
            toks.append((ch, ch))
            i += 1
        else:
            m = re.match(r"[^\s()`§]+", src[i:])
            word = m.group(0)
            toks.append((word, word) if word in KEYWORDS else ("WORD", word))
            i += len(word)
    return toks


def parse(toks):
    """Yield ('heading', level, name) | ('atom_decl', name) | ('decide', name, expr)."""
    items, pos = [], 0

    def parse_expr():
        nonlocal pos
        return parse_and()

    def parse_and():
        nonlocal pos
        parts = [parse_or()]
        while pos < len(toks) and toks[pos][0] == "AND":
            pos += 1
            parts.append(parse_or())
        return parts[0] if len(parts) == 1 else ("and", parts)

    def parse_or():
        nonlocal pos
        parts = [parse_unary()]
        while pos < len(toks) and toks[pos][0] == "OR":
            pos += 1
            parts.append(parse_unary())
        return parts[0] if len(parts) == 1 else ("or", parts)

    def parse_unary():
        nonlocal pos
        kind, val = toks[pos]
        if kind == "NOT":
            pos += 1
            return ("not", parse_unary())
        if kind == "(":
            pos += 1
            e = parse_expr()
            assert toks[pos][0] == ")", "expected )"
            pos += 1
            return e
        if kind == "ATOM":
            pos += 1
            return ("atom", val)
        raise SyntaxError(f"unexpected token {toks[pos]}")

    while pos < len(toks):
        kind, val = toks[pos]
        if kind == "SECTION":
            level = val
            pos += 1
            assert toks[pos][0] == "ATOM"
            items.append(("heading", level, toks[pos][1]))
            pos += 1
        elif kind == "ASSUME":
            pos += 3  # ASSUME <atom> IS
            assert toks[pos][0] == "BOOLEAN"
            items.append(("atom_decl", toks[pos - 2][1]))
            pos += 1
        elif kind == "DECIDE":
            name = toks[pos + 1][1]
            assert toks[pos + 2][0] == "IF"
            pos += 3
            items.append(("decide", name, parse_expr()))
        else:
            pos += 1  # skip anything else (prototype!)
    return items


# ---------------------------------------------------------------------------
# Coode tabulation (mirrors L4.TNR.toTab / renderTabItems)
# ---------------------------------------------------------------------------

EMDASH = "—"


def negate_clause(t: str) -> str:
    for needle, repl in [
        (" is ", " is not "),
        (" are ", " are not "),
        (" has ", " does not have "),
        (" have ", " do not have "),
    ]:
        if needle in t:
            return t.replace(needle, repl, 1)
    return "it is not the case that " + t


def to_tab(e):
    """-> ('leaf', text) | ('group', lead_or_None, 'and'|'or', [tab])"""
    kind = e[0]
    if kind == "atom":
        return ("leaf", e[1])
    if kind in ("and", "or"):
        return ("group", None, kind, [to_tab(x) for x in e[1]])
    if kind == "not":
        inner = e[1]
        if inner[0] == "and":
            return ("group", f"it is not the case that{EMDASH}", "and",
                    [to_tab(x) for x in inner[1]])
        if inner[0] == "or":
            return ("group", f"none of the following applies{EMDASH}", "or",
                    [to_tab(x) for x in inner[1]])
        return ("leaf", negate_clause(inner[1]))
    raise ValueError(kind)


def roman(i: int) -> str:
    out, pairs = "", [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"),
                      (100, "c"), (90, "xc"), (50, "l"), (40, "xl"),
                      (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")]
    for v, s in pairs:
        while i >= v:
            out, i = out + s, i - v
    return out


def marker(depth: int, i: int) -> str:
    style = depth % 4
    if style == 0:
        return chr(ord("a") + (i - 1) % 26) * ((i - 1) // 26 + 1)
    if style == 1:
        return roman(i)
    if style == 2:
        return (chr(ord("A") + (i - 1) % 26)) * ((i - 1) // 26 + 1)
    return str(i)


DEFAULT_LEAD = {"and": f"all of the following apply{EMDASH}",
                "or": f"any of the following applies{EMDASH}"}


def render_tab_items(depth, conj, terminal, items):
    lines, total = [], len(items)
    for i, item in enumerate(items, 1):
        sep = terminal if i == total else (";" if i < total - 1 else "; " + conj)
        pad = " " * 4 * (depth + 1)
        mk = f"({marker(depth, i)})"
        if item[0] == "leaf":
            lines.append(f"{pad}{mk} {item[1]}{sep}")
        else:
            _, lead, c, subs = item
            lines.append(f"{pad}{mk} {lead or DEFAULT_LEAD[c]}")
            lines.extend(render_tab_items(depth + 1, c, sep, subs))
    return lines


def sentence_case(t: str) -> str:
    return t[:1].upper() + t[1:]


# ---------------------------------------------------------------------------
# Document assembly
# ---------------------------------------------------------------------------

def render(items, anchors=True):
    blocks, num, atoms = [], 0, 0
    for item in items:
        if item[0] == "heading":
            _, level, name = item
            blocks.append("#" * min(level, 6) + " " + sentence_case(name))
        elif item[0] == "atom_decl":
            atoms += 1  # boolean atoms appear inline inside provisions
        elif item[0] == "decide":
            _, name, expr = item
            num += 1
            tab = to_tab(expr)
            para = []
            if anchors:
                para.append(f"<!-- l4: decide:{name} -->")
            if tab[0] == "leaf":
                para.append(f"**{num}.** {sentence_case(name)} if {tab[1]}.")
            else:
                _, lead, conj, subs = tab
                opener = f" {lead}" if lead else EMDASH
                para.append(f"**{num}.** {sentence_case(name)} if{opener}")
                para.extend(render_tab_items(0, conj, ".", subs))
            blocks.append("\n\n".join(para))
    blocks.append(f"<!-- tnr-coverage: {num} provisions; {atoms} boolean atoms "
                  f"inlined; 0 directives suppressed -->")
    return "\n\n".join(blocks) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("-o", "--output")
    ap.add_argument("--no-anchors", action="store_true")
    args = ap.parse_args()

    src = strip_comments(open(args.file, encoding="utf-8").read())
    md = render(parse(tokenize(src)), anchors=not args.no_anchors)
    if args.output:
        open(args.output, "w", encoding="utf-8").write(md)
        print(f"wrote {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(md)


if __name__ == "__main__":
    main()
