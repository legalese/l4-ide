#!/usr/bin/env python3
"""Is a candidate enum's type name found in its subject's source text?
A name absent from the source was invented by the encoder."""
import glob, os, re, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(__file__))
import census as C

def norm(s):
    return re.sub(r"\s+", " ", re.sub(r"[^\w\s]", " ", s.lower())).strip()

roots = sys.argv[1:]
files, _ = C.load(roots)
toks, results = C.census(files)
cands = [(d, s) for d, s in results if d.kind == "enum" and C.bucket(d, s) in ("one-field", "one-payload")]
c = Counter(); ex = []
for d, s in cands:
    m = re.match(r"(.*/subjects/[^/]+/[^/]+)/", d.file) or re.match(r"(.*/subjects/[^/]+/[^/]+/[^/]+)/encodings", d.file)
    if not m: c["no subject (l4-ide)"] += 1; continue
    srcs = [p for p in glob.glob(m.group(1) + "/source/**/*", recursive=True) if p.endswith((".txt", ".md")) and "PROVENANCE" not in p and "LICENSE" not in p]
    if not srcs: c["no source text"] += 1; continue
    text = norm(" ".join(open(p, errors="replace").read() for p in srcs))
    nm = norm(d.name)
    found = nm in text
    c["type name in source" if found else "type name NOT in source"] += 1
    if not found and len(ex) < 12: ex.append(d.name)
for k, v in c.most_common(): print(f"{v:4} {k}")
print("examples not in source:", ex)
