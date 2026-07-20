#!/usr/bin/env python3
"""Download the direct-PDF tight-core urls (acquire-direct.json). Verify %PDF; resumable."""
import json, os, subprocess, time, re

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
DATA = os.path.join(ROOT, "data")
PDFS = os.path.join(ROOT, "pdfs")
os.makedirs(PDFS, exist_ok=True)
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

direct = json.load(open(os.path.join(DATA, "acquire-direct.json")))
sp = os.path.join(DATA, "acquire-direct-status.json")
status = json.load(open(sp)) if os.path.exists(sp) else {}
def fn(k): return re.sub(r'[^A-Za-z0-9]', '_', k) + ".pdf"

got = miss = 0
for i, (key, url) in enumerate(direct.items()):
    out = os.path.join(PDFS, fn(key))
    if os.path.exists(out) and os.path.getsize(out) > 1000:
        with open(out, "rb") as fh:
            if fh.read(5).startswith(b"%PDF"):
                status[key] = "pdf"; got += 1; continue
    if status.get(key) == "pdf" and os.path.exists(out):
        got += 1; continue
    subprocess.run(["curl","-s","--max-time","60","-A",UA,"-L","-o",out,url], capture_output=True)
    ok = os.path.exists(out) and os.path.getsize(out) > 1000 and open(out,"rb").read(5).startswith(b"%PDF")
    if ok:
        status[key] = "pdf"; got += 1
    else:
        if os.path.exists(out): os.remove(out)
        status[key] = "miss"; miss += 1
    time.sleep(1.0)
    if (i+1) % 20 == 0:
        json.dump(status, open(sp,"w"), indent=1); print(f"  {i+1}/{len(direct)} pdf={got} miss={miss}")

json.dump(status, open(sp,"w"), indent=1)
print(f"DONE: pdf={got} miss={miss} of {len(direct)}")