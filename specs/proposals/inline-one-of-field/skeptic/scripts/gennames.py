import hashlib, os, re, sys, random
from collections import Counter, defaultdict
sys.path.insert(0, sys.argv[1])
import census as C
roots = sys.argv[2:]
files, _ = C.load(roots)
toks, results = C.census(files)
cands = [(d, s) for d, s in results if d.kind == "enum" and C.bucket(d, s) in ("one-field", "one-payload")]
art = 0; recart = 0; names = []; srcname_same = 0
for d, s in cands:
    x = C.real_sites(s)[0]
    line = files[x[0]].split("\n")[x[1]-1]
    m = re.match(r"\s*(`[^`]+`|[^\s`]+)\s+(IS|:)\b", line)
    field = m.group(1).strip("`") if m else "?"
    owner = x[4]
    g = f"{owner}'s {field}"
    names.append((len(g), g, d.name))
    if re.match(r"(?i)(the|a|an)\b", field): art += 1
    if re.match(r"(?i)(the|a|an)\b", owner or ""): recart += 1
print("candidates", len(cands), "field starts with article", art, "record starts with article", recart)
names.sort()
print("generated-name length: median", names[len(names)//2][0], "max", names[-1][0])
random.seed(1)
for n in random.sample(names, 12): print("  ", repr(n[1]), " <- was", repr(n[2]))
print("longest:"); [print("  ", repr(n[1])) for n in names[-4:]]
cit = re.compile(r"(?i)\b(section|s\.|art(icle)?|schedule|reg(ulation)?|para(graph)?|rule|clause|§)\b|\d")
a = sum(1 for _, g, n in names if cit.search(n)); b = sum(1 for _, g, n in names if cit.search(g))
lost = [(n, g) for _, g, n in names if cit.search(n) and not cit.search(g)]
print("enum names with citation-like token:", a, "; generated names with one:", b, "; citation lost:", len(lost))
for n, g in lost[:6]: print("   ", repr(n), "->", repr(g))
