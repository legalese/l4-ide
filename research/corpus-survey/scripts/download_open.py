#!/usr/bin/env python3
"""Phase 4: download the direct-OA tight-core PDFs (acquire-open.json). Verify %PDF magic;
route landing-pages/non-PDFs to a residue list. Polite, resumable, PDFs stay gitignored."""
import json, os, subprocess, time, re

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
DATA = os.path.join(ROOT, "data")
PDFS = os.path.join(ROOT, "pdfs")
os.makedirs(PDFS, exist_ok=True)
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

openset = json.load(open(os.path.join(DATA, "acquire-open.json")))
status_path = os.path.join(DATA, "acquire-open-status.json")
status = json.load(open(status_path)) if os.path.exists(status_path) else {}

def fname(key):
    return re.sub(r'[^A-Za-z0-9]', '_', key) + ".pdf"

got = notpdf = fail = 0
for i, (key, url) in enumerate(openset.items()):
    if status.get(key) in ("pdf", "notpdf"):
        if status[key] == "pdf": got += 1
        continue
    if not url:
        status[key] = "nourl"; fail += 1; continue
    out = os.path.join(PDFS, fname(key))
    subprocess.run(["curl", "-s", "--max-time", "60", "-A", UA, "-L", "-o", out, url],
                   capture_output=True)
    ok = False
    if os.path.exists(out) and os.path.getsize(out) > 1000:
        with open(out, "rb") as fh:
            ok = fh.read(5).startswith(b"%PDF")
    if ok:
        status[key] = "pdf"; got += 1
    else:
        if os.path.exists(out):
            os.remove(out)
        status[key] = "notpdf"; notpdf += 1
    time.sleep(1.2)
    if (i + 1) % 20 == 0:
        json.dump(status, open(status_path, "w"), indent=1)
        print(f"  {i+1}/{len(openset)}  pdf={got} notpdf={notpdf} fail={fail}")

json.dump(status, open(status_path, "w"), indent=1)
# residue: OA urls that didn't yield a PDF (landing pages) -> for later resolution
residue = [k for k, v in status.items() if v != "pdf"]
json.dump(residue, open(os.path.join(DATA, "acquire-open-residue.json"), "w"), indent=1)
print(f"DONE: pdf={got}  notpdf/residue={len(residue)}  of {len(openset)} -> {PDFS}")