import os, sys, random
sys.path.insert(0, os.path.dirname(__file__))
import census as C
files, _ = C.load(sys.argv[1:])
toks, results = C.census(files)
xs = [(d, s) for d, s in results if d.kind == "enum" and C.bucket(d, s) == "one-signature" and C.real_sites(s)[0][2] == "given"]
random.seed(7)
for d, s in random.sample(xs, 6):
    x = C.real_sites(s)[0]
    print(repr(d.name), "|", os.path.dirname(d.file).split('/subjects/')[-1], "|", files[x[0]].split("\n")[x[1]-1].strip()[:100])
