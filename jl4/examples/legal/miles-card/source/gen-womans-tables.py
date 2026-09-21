# Preserved from the encoding session's scratchpad on 2026-09-21 so the ditto
# blocks in dbs-womans-world.l4 (cl.11 Tables 1 and 2) can be regenerated;
# run from the repository root: python3 <this file> <output-file>.
# -*- coding: utf-8 -*-
"""Emit DBS Woman's Card T&C cl.11 Table 1 and Table 2 as L4 ditto chains.

Reads the committed `pdftotext -layout` extraction; nothing is retyped.
Column widths and the caret columns are computed together here, so a caret
cannot drift off the token it dittoes (the silent failure mode).
"""
import re, sys, io

SRC = "jl4/examples/legal/miles-card/source/dbs-womans-card-tnc.txt"
lines = io.open(SRC, encoding="utf-8").read().split("\n")

t1_start = next(i for i, l in enumerate(lines) if l.strip() == "Table 1")
t1_end   = next(i for i, l in enumerate(lines) if l.strip() == "Table 2")
t2_end   = next(i for i, l in enumerate(lines) if l.strip().startswith("12."))

# ---- Table 1: a 4-digit MCC then its description, wrapped onto later lines --
rows, cur = [], None
for l in lines[t1_start:t1_end]:
    m = re.match(r"^\s{8,}(\d{4})\s{2,}(\S.*?)\s*$", l)
    if m:
        cur = [m.group(1), m.group(2)]
        rows.append(cur)
    elif cur is not None and re.match(r"^\s{20,}\S", l) and "Page " not in l and "Updated" not in l:
        cur[1] += " " + l.strip()

# ---- Table 2: three bulleted columns, each alphabetical downwards ----------
cols = [[], [], []]
for l in lines[t1_end:t2_end]:
    for m in re.finditer("\u2022\\s+(.+?)(?=\\s{3,}\u2022|\\s*$)", l):
        t = m.group(1).strip()
        if t:
            cols[0 if m.start() < 30 else 1 if m.start() < 60 else 2].append(t)
terms = cols[0] + cols[1] + cols[2]

sys.stderr.write("Table 1 rows: %d\nTable 2 columns: %s (total %d)\n"
                 % (len(rows), [len(c) for c in cols], len(terms)))
seen = {}
for t in terms:
    seen.setdefault(t.upper(), []).append(t)
for k, v in sorted(seen.items()):
    if len(v) > 1:
        sys.stderr.write("DUPLICATE once upper-cased: %s <- %r\n" % (k, v))

def chain(head, values, comments, indent=7, just="r"):
    hw = [len(t) for t in head]
    vw = max(len(v) for v in values)
    out = []
    for i, (v, c) in enumerate(zip(values, comments)):
        lead = " " * indent if i == 0 else " " * (indent - 4) + "OR" + "  "
        cells = [(t if i == 0 else "^").ljust(w) for t, w in zip(head, hw)]
        cell = v.rjust(vw) if just == "r" else v.ljust(vw)
        row = lead + " ".join(cells) + " " + cell
        out.append((row + "   -- " + c).rstrip() if c else row.rstrip())
    return out

def lit(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

with io.open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write("-- TABLE-1-BEGIN\n")
    for r in chain(["mcc", "EQUALS"], [str(int(c)) for c, _ in rows], [d for _, d in rows]):
        f.write(r + "\n")
    f.write("-- TABLE-1-END\n-- TABLE-2-BEGIN\n")
    for r in chain(["CONTAINS", "u"], [lit(t.upper()) for t in terms],
                   [("printed " + t) if t != t.upper() else "" for t in terms], just="l"):
        f.write(r + "\n")
    f.write("-- TABLE-2-END\n")
