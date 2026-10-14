#!/usr/bin/env python3
"""For each single-field candidate: the citation (an @ref, or a `src:`/section
comment) nearest above the enum's DECLARE and above the record's DECLARE."""
import os, re, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(__file__))
import census as C

CITE = re.compile(r"@ref\s+(.*)|--\s*(?:src:\S+\s*\|)?\s*((?:s|section|art|article|reg|rule|para|§)\.?\s*[0-9][0-9A-Za-z()]*)", re.I)

def cite_above(lines, ln, span=6):
    for k in range(ln - 2, max(-1, ln - 2 - span), -1):
        m = CITE.search(lines[k])
        if m:
            return (m.group(1) or m.group(2)).strip()
        if lines[k].strip() == "" and k < ln - 3:
            break
    return None

roots = sys.argv[1:]
files, _ = C.load(roots)
toks, results = C.census(files)
cands = [(d, s) for d, s in results if d.kind == "enum" and C.bucket(d, s) in ("one-field", "one-payload")]
c = Counter()
for d, s in cands:
    x = C.real_sites(s)[0]
    t = toks[d.file]
    lines = files[d.file].split("\n")
    j = x[5]
    while j >= 0 and not C.is_kw(t[j], "DECLARE"): j -= 1
    e = cite_above(lines, t[d.start].line)
    r = cite_above(lines, t[j].line) if j >= 0 else None
    k = ("enum cited" if e else "enum uncited") + ", " + ("record cited" if r else "record uncited")
    if e and r:
        k += ", SAME" if e == r else ", different"
    c[k] += 1
for k, v in c.most_common(): print(f"{v:4} {k}")
if os.environ.get("SHOW"):
    for d, s in cands:
        x = C.real_sites(s)[0]; t = toks[d.file]; lines = files[d.file].split("\n")
        j = x[5]
        while j >= 0 and not C.is_kw(t[j], "DECLARE"): j -= 1
        e = cite_above(lines, t[d.start].line); r = cite_above(lines, t[j].line)
        if e and r and e != r:
            print(f"{os.path.basename(d.file)}:{t[d.start].line} {d.name!r}: enum<{e[:60]}> record {x[4]!r}<{r[:60]}>")
