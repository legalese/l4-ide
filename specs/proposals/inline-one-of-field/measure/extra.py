#!/usr/bin/env python3
"""More detail on census.py's single-field candidates."""
import os, re, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(__file__))
import census as C

def norm(s):
    s = s.strip("`").lower()
    s = re.sub(r"^(the|a|an)\s+", "", s)
    return re.sub(r"[^a-z0-9]+", " ", s).strip()

roots = sys.argv[1:]
files, _ = C.load(roots)
toks, results = C.census(files)
enums = [(d, s) for d, s in results if d.kind == "enum"]
cands = [(d, s) for d, s in enums if C.bucket(d, s) in ("one-field", "one-payload")]
same = contains = 0
typ = pay = 0
chars_named = chars_anon = 0
for d, s in cands:
    x = C.real_sites(s)[0]
    line = files[x[0]].split("\n")[x[1]-1]
    m = re.match(r"\s*(`[^`]+`|[^\s`]+)\s+IS\b", line)
    field = m.group(1) if m else ""
    if norm(field) == norm(d.name): same += 1
    elif norm(field) and (norm(field) in norm(d.name) or norm(d.name) in norm(field)): contains += 1
    if "TYPICALLY" in C.strip(line): typ += 1
    if d.payload: pay += 1
    nm = d.name if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", d.name) else f"`{d.name}`"
    # status quo spends: "DECLARE <nm> IS ONE OF" header + "A <nm>" at the field
    # C (anonymous): field says "ONE OF"; saves "DECLARE <nm> IS " + "A <nm>"
    chars_anon += len("DECLARE ") + len(nm) + len(" IS ") + len("A ") + len(nm)
    # B (named, `IS A <nm> WHICH IS ONE OF`): saves only "DECLARE " + one newline
    chars_named += len("DECLARE ") + 1
print(f"candidates {len(cands)}: field name == type name (modulo case/article/punct): {same}; one contains the other: {contains}; unrelated: {len(cands)-same-contains}")
print(f"candidate fields carrying TYPICALLY on the field line: {typ}")
print(f"candidate enums with a payload-carrying alternative: {pay}")
print(f"characters saved over all candidates: named-inline ~{chars_named}, anonymous-inline ~{chars_anon} (mean {chars_anon/len(cands):.0f}/candidate)")
# shared-with-one-'other' check (recall)
two_other = [(d, s) for d, s in enums if C.bucket(d, s) == "shared" and len(C.real_sites(s)) == 2
             and sum(1 for x in C.real_sites(s) if x[2].startswith("other")) == 1
             and sum(1 for x in C.real_sites(s) if x[2] in ("field", "payload") and not x[3]) == 1]
print(f"shared enums = one field + one 'other' site (recall risk): {len(two_other)}")
for d, s in two_other[:8]:
    o = [x for x in C.real_sites(s) if x[2].startswith("other")][0]
    print("   ", repr(d.name), f"{o[0]}:{o[1]}", files[o[0]].split("\n")[o[1]-1].strip()[:110])
