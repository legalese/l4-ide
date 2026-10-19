#!/usr/bin/env python3
"""Census without first-copy dedupe: classify every copy in its own directory,
then merge byte-identical copies, taking the MOST-shared classification."""
import hashlib, os, sys
from collections import Counter, defaultdict
sys.path.insert(0, sys.argv[1])
import census as C
roots = sys.argv[2:]
files = {}
for root in roots:
    for dp, dn, fn in os.walk(root):
        dn.sort()
        for f in sorted(fn):
            if f.endswith(".l4") and not f.endswith(".evaldiff.l4"):
                p = os.path.join(dp, f)
                files[p] = open(p, encoding="utf-8", errors="replace").read()
print("files (no dedupe):", len(files))
toks, results = C.census(files)
rank = {"shared": 6, "one-signature": 5, "one-other": 4, "one-field-wrapped": 3, "one-payload": 2, "one-field": 1, "zero": 0}
groups = defaultdict(list)
for d, s in results:
    h = hashlib.sha256(files[d.file].encode()).hexdigest()
    groups[(d.kind, h, d.start)].append((d, s, C.bucket(d, s)))
for kind in ("enum", "record"):
    c = Counter(); sig = Counter(); field_plus_sig = 0
    for (k, h, st), g in groups.items():
        if k != kind: continue
        best = max(g, key=lambda x: rank[x[2]])
        c[best[2]] += 1
        if best[2] == "one-signature":
            sig[C.real_sites(best[1])[0][2]] += 1
    print(kind, sum(c.values()), dict(c.most_common()), "one-signature split:", dict(sig))
