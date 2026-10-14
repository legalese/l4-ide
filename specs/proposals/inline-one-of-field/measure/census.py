#!/usr/bin/env python3
"""Text-heuristic census: how is each `DECLARE X IS ONE OF` (and each
`DECLARE X HAS`) type name referenced outside its own declaration?

This is NOT a parse. It tokenises L4 source after stripping comments,
string literals and annotations, then classifies each occurrence of a
declared type name by the tokens around it and by layout.

Usage: census.py [--control] [--dump] ROOT...
"""
import hashlib
import os
import re
import sys
from collections import Counter, defaultdict

KEYWORDS = set("""
DECLARE HAS IS ONE OF A AN THE GIVEN GIVETH GIVES DECIDE MEANS ASSUME IF THEN ELSE
WHEN CONSIDER WITH WHERE LET IN OTHERWISE LIST MAYBE SET FUNCTION FROM TO AND OR
NOT TYPICALLY IMPORT TYPE FOR ALL AKA PARTY MUST MAY SHANT DO WITHIN HENCE LEST
YIELD BECAUSE WITHAL
""".split())

# Tokens a type reference may be wrapped in, walking backwards from the name.
WRAP_ARTICLES = {"A", "AN", "THE"}
WRAP_CTORS = {"LIST", "OF", "MAYBE", "SET", "FUNCTION", "FROM", "TO", "AND", "("}
GOVERNORS = {"HAS", "GIVEN", "ASSUME", "DECLARE", "GIVETH", "DECIDE", "MEANS", "WITH",
             "WHERE", "IF", "THEN", "ELSE", "WHEN", "CONSIDER", "LET", "OTHERWISE", "AKA", "§"}

TOKEN_RE = re.compile(r"""
    (?P<bt>`[^`\n]*`)
  | (?P<gen>'s\b)
  | (?P<dir>\#[A-Z]+)
  | (?P<id>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<num>[0-9]+(?:\.[0-9]+)?)
  | (?P<sect>§+)
  | (?P<p>[(),:])
  | (?P<other>\S)
""", re.X)


def strip(src: str) -> str:
    """Blank out block comments, line comments, strings and @annotations,
    preserving line/column positions."""
    out = []
    i, n = 0, len(src)
    depth = 0
    while i < n:
        c = src[i]
        two = src[i:i + 2]
        if depth:
            if two == "{-":
                depth += 1; out.append("  "); i += 2; continue
            if two == "-}":
                depth -= 1; out.append("  "); i += 2; continue
            out.append("\n" if c == "\n" else " "); i += 1; continue
        if two == "{-":
            depth = 1; out.append("  "); i += 2; continue
        if two == "--":
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j; continue
        if c == "@" and (i + 1 < n and src[i + 1].isalpha()):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j; continue
        if c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                if src[j] == "\\":
                    j += 1
                j += 1
            seg = src[i:j + 1]
            out.append("".join("\n" if ch == "\n" else " " for ch in seg)); i = j + 1; continue
        if c == "`":
            j = src.find("`", i + 1)
            if j < 0:
                j = n - 1
            out.append(src[i:j + 1]); i = j + 1; continue
        out.append(c); i += 1
    return "".join(out)


class Tok:
    __slots__ = ("kind", "text", "line", "col", "first", "idx")

    def __init__(self, kind, text, line, col):
        self.kind, self.text, self.line, self.col = kind, text, line, col
        self.first = False
        self.idx = -1

    def __repr__(self):
        return f"{self.text}@{self.line}:{self.col}"


def tokenize(src: str):
    toks = []
    for ln, line in enumerate(strip(src).split("\n"), 1):
        first = True
        for m in TOKEN_RE.finditer(line):
            kind = m.lastgroup
            text = m.group(0)
            if kind == "bt":
                kind, text = "id", text[1:-1]
            elif kind == "id" and text in KEYWORDS:
                kind = "kw"
            elif kind == "gen":
                kind = "gen"
            elif kind == "sect":
                kind, text = "kw", "§"
            t = Tok(kind, text, ln, m.start() + 1)
            t.first = first
            first = False
            toks.append(t)
    for i, t in enumerate(toks):
        t.idx = i
    return toks


def is_kw(t, *ws):
    return t is not None and t.kind == "kw" and t.text in ws


class Decl:
    def __init__(self, f, kind, name, start, end, payload):
        self.file, self.kind, self.name = f, kind, name
        self.start, self.end = start, end  # token indices, inclusive
        self.payload = payload  # enum with a HAS inside

    @property
    def line(self):
        return self.toks[self.start].line


def find_decls(path, toks):
    decls = []
    for i, t in enumerate(toks):
        if not is_kw(t, "DECLARE"):
            continue
        if i + 1 >= len(toks) or toks[i + 1].kind != "id":
            continue
        name = toks[i + 1].text
        j = i + 2
        while j < len(toks) and toks[j].kind == "id" and toks[j].text[:1].islower() and not toks[j].first:
            j += 1  # type parameters
        kind = None
        if j + 2 < len(toks) and is_kw(toks[j], "IS") and is_kw(toks[j + 1], "ONE") and is_kw(toks[j + 2], "OF"):
            kind = "enum"
        elif j < len(toks) and is_kw(toks[j], "HAS"):
            kind = "record"
        if kind is None:
            continue
        # span: up to the next line-initial token at column <= DECLARE's column
        k = i + 1
        while k < len(toks) and not (toks[k].first and toks[k].col <= t.col):
            k += 1
        payload = kind == "enum" and any(is_kw(toks[m], "HAS") for m in range(j, k))
        d = Decl(path, kind, name, i, k - 1, payload)
        d.toks = toks
        decls.append(d)
    return decls


def line_tokens(toks, line):
    return [t for t in toks if t.line == line]


def governing_line(toks, b):
    """Nearest previous line whose first token is left of b's line start."""
    # first token on b's line
    i = b.idx
    while i > 0 and not toks[i].first:
        i -= 1
    head_col = toks[i].col
    j = i - 1
    while j >= 0:
        if toks[j].first and toks[j].col < head_col:
            return toks[j].line
        j -= 1
    return None


def governor(toks, b):
    """The keyword governing binder b: the last GOVERNORS keyword before b on
    its own line, else the last one on the governing line."""
    same = [t for t in toks[:b.idx] if t.line == b.line and t.kind == "kw" and t.text in GOVERNORS]
    if same:
        return same[-1]
    gl = governing_line(toks, b)
    if gl is None:
        return None
    on = [t for t in line_tokens(toks, gl) if t.kind == "kw" and t.text in GOVERNORS]
    return on[-1] if on else None


def has_owner(toks, has_tok):
    """For a HAS keyword: ('record', name) if it heads a DECLARE, else
    ('payload', constructor-name)."""
    j = has_tok.idx - 1
    names = []
    while j >= 0 and toks[j].kind == "id":
        names.append(toks[j]); j -= 1
    if j >= 0 and is_kw(toks[j], "DECLARE") and names:
        return "record", names[-1]
    return "payload", (names[0] if names else None)


def classify(toks, t):
    """Classify one occurrence of a type name. Returns (site, wrapped, owner)."""
    prev = toks[t.idx - 1] if t.idx > 0 else None
    nxt = toks[t.idx + 1] if t.idx + 1 < len(toks) else None
    if prev is not None and prev.kind == "gen":
        return ("pun-projection", False, None)
    if nxt is not None and (is_kw(nxt, "IS", "MEANS", "HAS") or (nxt.kind == "p" and nxt.text == ":")) \
            and not (prev is not None and (is_kw(prev, "IS", "A", "AN", "THE", "GIVETH", "OF") )):
        return ("pun-binder", False, None)
    j = t.idx - 1
    wrapped = False
    while j >= 0 and ((toks[j].kind == "kw" and toks[j].text in WRAP_ARTICLES | WRAP_CTORS)
                      or (toks[j].kind == "p" and toks[j].text == "(")):
        if toks[j].text in WRAP_CTORS:
            wrapped = True
        j -= 1
    land = toks[j] if j >= 0 else None
    if land is None:
        return ("other", wrapped, None)
    if is_kw(land, "GIVETH", "GIVES"):
        return ("giveth", wrapped, None)
    if is_kw(land, "IS") or (land.kind == "p" and land.text == ":"):
        b = toks[land.idx - 1] if land.idx > 0 else None
        if b is None or b.kind != "id":
            return ("other", wrapped, None)
        g = governor(toks, b)
        if g is None:
            return ("other", wrapped, None)
        if g.text == "HAS":
            kind, owner = has_owner(toks, g)
            return ("field" if kind == "record" else "payload", wrapped, owner)
        if g.text == "GIVEN":
            return ("given", wrapped, None)
        if g.text == "ASSUME":
            return ("assume", wrapped, None)
        if g.text == "DECLARE":
            return ("synonym", wrapped, None)
        return ("other:" + g.text, wrapped, None)
    return ("other", wrapped, None)


def imports_of(toks):
    out = set()
    for i, t in enumerate(toks):
        if is_kw(t, "IMPORT") and i + 1 < len(toks):
            out.add(toks[i + 1].text)
    return out


def load(roots):
    files, seen, dupes = {}, {}, 0
    for root in roots:
        for dp, dn, fn in os.walk(root):
            dn.sort()
            for f in sorted(fn):
                if not f.endswith(".l4") or f.endswith(".evaldiff.l4"):
                    continue
                p = os.path.join(dp, f)
                with open(p, encoding="utf-8", errors="replace") as h:
                    src = h.read()
                key = hashlib.sha256(src.encode()).hexdigest()
                if key in seen:
                    dupes += 1
                    continue
                seen[key] = p
                files[p] = src
    return files, dupes


def census(files):
    toks = {p: tokenize(s) for p, s in files.items()}
    imps = {p: imports_of(t) for p, t in toks.items()}
    bydir = defaultdict(list)
    for p in toks:
        bydir[os.path.dirname(p)].append(p)
    decls = []
    for p, t in toks.items():
        decls.extend(find_decls(p, t))
    results = []
    for d in decls:
        mod = os.path.splitext(os.path.basename(d.file))[0]
        universe = [d.file] + [q for q in bydir[os.path.dirname(d.file)] if q != d.file and mod in imps[q]]
        sites = []
        for q in universe:
            for tk in toks[q]:
                if tk.kind != "id" or tk.text != d.name:
                    continue
                if q == d.file and d.start <= tk.idx <= d.end:
                    continue
                site, wrapped, owner = classify(toks[q], tk)
                sites.append((q, tk.line, site, wrapped, owner.text if owner else None,
                              owner.idx if owner else None))
        results.append((d, sites))
    return toks, results


def real_sites(sites):
    return [s for s in sites if not s[2].startswith("pun")]


def bucket(d, sites):
    rs = real_sites(sites)
    if not rs:
        return "zero"
    if len(rs) == 1:
        s = rs[0]
        if s[2] in ("field", "payload") and not s[3]:
            return "one-" + s[2]
        if s[2] in ("field", "payload"):
            return "one-" + s[2] + "-wrapped"
        if s[2] in ("given", "giveth", "assume"):
            return "one-signature"
        return "one-other"
    return "shared"


def adjacency(toks, d, sites):
    """For a single-field candidate: is the enum declared next to its record,
    with no other line-initial item at column <= theirs in between?"""
    s = real_sites(sites)[0]
    if s[0] != d.file:
        return "other-file", None
    t = toks[d.file]
    owner_idx = s[5]
    # the record's DECLARE token
    j = owner_idx
    while j >= 0 and not is_kw(t[j], "DECLARE"):
        j -= 1
    rec_start = j
    rec_end = rec_start + 1
    while rec_end < len(t) and not (t[rec_end].first and t[rec_end].col <= t[rec_start].col):
        rec_end += 1
    rec_end -= 1
    if s[2] == "payload":
        # the owner is a constructor; adjacency is to the DECLARE that holds it
        pass
    a, b = (d.start, d.end), (rec_start, rec_end)
    lo, hi = (a, b) if a[0] < b[0] else (b, a)
    col = min(t[d.start].col, t[rec_start].col)
    between = [x for x in t[lo[1] + 1:hi[0]] if x.first and x.col <= col]
    # a GIVEN/GIVETH line immediately before the second DECLARE belongs to it
    between = [x for x in between if not is_kw(x, "GIVEN", "GIVETH")]
    dist = t[hi[0]].line - t[lo[1]].line
    return ("adjacent" if not between else "separated"), dist


def main(argv):
    control = "--control" in argv
    dump = "--dump" in argv
    roots = [a for a in argv if not a.startswith("--")]
    files, dupes = load(roots)
    toks, results = census(files)
    print(f"files: {len(files)} (dropped {dupes} byte-identical duplicates)")
    for kind in ("enum", "record"):
        rs = [(d, s) for d, s in results if d.kind == kind]
        c = Counter(bucket(d, s) for d, s in rs)
        print(f"\n== {kind}: {len(rs)} declarations")
        for k, v in sorted(c.items(), key=lambda kv: -kv[1]):
            print(f"  {k:24} {v}")
        if kind == "enum":
            pay = sum(1 for d, s in rs if d.payload)
            print(f"  (enums with a payload-carrying alternative: {pay})")
        cands = [(d, s) for d, s in rs if bucket(d, s) in ("one-field", "one-payload")]
        adj = Counter(adjacency(toks, d, s)[0] for d, s in cands)
        print(f"  candidates by adjacency: {dict(adj)}")
        dists = sorted(adjacency(toks, d, s)[1] for d, s in cands if adjacency(toks, d, s)[1] is not None)
        if dists:
            print(f"  line distance enum-end to record-start: median {dists[len(dists)//2]}, max {dists[-1]}")
        sitec = Counter()
        for d, s in rs:
            for x in s:
                sitec[x[2] + ("+wrapped" if x[3] else "")] += 1
        print(f"  all reference sites: {dict(sitec.most_common())}")
        if dump:
            for d, s in rs:
                b = bucket(d, s)
                adjs = adjacency(toks, d, s) if b in ("one-field", "one-payload") else ("", None)
                print(f"    {b:20} {adjs[0]:10} {d.name!r} {d.file}:{toks[d.file][d.start].line} "
                      + "; ".join(f"{x[2]}{'+w' if x[3] else ''}@{os.path.basename(x[0])}:{x[1]}" for x in s))
    if control:
        expect = {
            "Solo": ("one-field", "separated"), "Near": ("one-field", "adjacent"),
            "Shared": ("shared", None), "OnlyOut": ("one-signature", None),
            "Listed": ("one-field-wrapped", None), "Pay": ("one-payload", "adjacent"),
            "Pun": ("one-field", "separated"), "Ghost": ("zero", None),
            "Exported": ("shared", None), "Syn": ("one-other", None),
            "Inline1": ("one-field", "adjacent"),
        }
        got = {}
        for d, s in results:
            if d.kind == "enum":
                b = bucket(d, s)
                a = adjacency(toks, d, s)[0] if b in ("one-field", "one-payload") else None
                got[d.name] = (b, a)
        bad = {k: (v, got.get(k)) for k, v in expect.items() if got.get(k) != v}
        print("\nCONTROL:", "PASS" if not bad else f"FAIL {bad}")
        return 1 if bad else 0
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
