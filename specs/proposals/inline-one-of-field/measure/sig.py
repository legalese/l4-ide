import os, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(__file__))
import census as C
files, _ = C.load(sys.argv[1:])
toks, results = C.census(files)
c = Counter()
for d, s in results:
    if d.kind == "enum" and C.bucket(d, s) == "one-signature":
        x = C.real_sites(s)[0]; c[x[2] + ("+wrapped" if x[3] else "")] += 1
print(dict(c))
# subject concentration of single-GIVEN enums
c2 = Counter()
for d, s in results:
    if d.kind == "enum" and C.bucket(d, s) == "one-signature" and C.real_sites(s)[0][2] == "given":
        c2[os.path.dirname(d.file).split("/subjects/")[-1]] += 1
print(len(c2), c2.most_common(5))
