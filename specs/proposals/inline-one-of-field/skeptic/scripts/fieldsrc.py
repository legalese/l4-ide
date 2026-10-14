import glob, os, re, sys
from collections import Counter
sys.path.insert(0, sys.argv[1])
import census as C
def norm(s): return re.sub(r"\s+", " ", re.sub(r"[^\w\s]", " ", s.lower())).strip()
def strip_art(s): return re.sub(r"^(the|a|an) ", "", s)
files, _ = C.load(sys.argv[2:]); toks, results = C.census(files)
cands = [(d, s) for d, s in results if d.kind == "enum" and C.bucket(d, s) in ("one-field", "one-payload")]
c = Counter()
for d, s in cands:
    m = re.match(r"(.*/subjects/[^/]+/[^/]+)/", d.file)
    if not m: continue
    srcs = [p for p in glob.glob(m.group(1) + "/source/**/*", recursive=True) if p.endswith((".txt", ".md")) and "PROVENANCE" not in p and "LICENSE" not in p]
    if not srcs: continue
    text = norm(" ".join(open(p, errors="replace").read() for p in srcs))
    x = C.real_sites(s)[0]; line = files[x[0]].split("\n")[x[1]-1]
    mm = re.match(r"\s*(`[^`]+`|[^\s`]+)\s+(IS|:)\b", line); field = mm.group(1).strip("`") if mm else "?"
    tn = norm(d.name) in text; fn = strip_art(norm(field)) in text; rn = strip_art(norm(x[4] or "")) in text
    c[(("type" if tn else "-type"), ("field" if fn else "-field"), ("rec" if rn else "-rec"))] += 1
print(c)
