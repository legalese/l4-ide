#!/usr/bin/env python3
"""Green-OA sweep over the tight-core via Unpaywall (legitimately-hosted author/repository
copies only). Look up every tight-core DOI, collect best_oa_location.url_for_pdf, download +
verify %PDF for those not already on disk. Polite, resumable."""
import json, os, subprocess, time, re

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
DATA = os.path.join(ROOT, "data")
PDFS = os.path.join(ROOT, "pdfs")
os.makedirs(PDFS, exist_ok=True)
EMAIL = "mengwong@gmail.com"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

sl = json.load(open(os.path.join(DATA, "shortlist.json")))
enr = {p["key"]: p for p in json.load(open(os.path.join(DATA, "enriched.json")))}
def tight(r): return r["relevance"]=="core" and r["confidence"]!="low" and r["has_abstract"]
core = [r for r in sl if tight(r)]
def fn(k): return re.sub(r'[^A-Za-z0-9]', '_', k) + ".pdf"

lk_path = os.path.join(DATA, "green-oa.json")
lookups = json.load(open(lk_path)) if os.path.exists(lk_path) else {}

# ---- 1. Unpaywall lookups ----
for i, r in enumerate(core):
    key = r["key"]
    doi = (enr.get(key, {}).get("doi") or "").strip()
    if not doi or key in lookups:
        continue
    p = subprocess.run(["curl","-s","--max-time","30","-A",UA,
                        f"https://api.unpaywall.org/v2/{doi}?email={EMAIL}"], capture_output=True, text=True)
    rec = {"is_oa": None, "pdf_url": None, "host": None, "version": None}
    try:
        d = json.loads(p.stdout)
        rec["is_oa"] = d.get("is_oa")
        loc = d.get("best_oa_location") or {}
        rec["pdf_url"] = loc.get("url_for_pdf")
        rec["host"] = loc.get("host_type")
        rec["version"] = loc.get("version")
    except Exception:
        pass
    lookups[key] = rec
    time.sleep(0.6)
    if (i+1) % 20 == 0:
        json.dump(lookups, open(lk_path,"w"), indent=1)
        print(f"  lookup {i+1}/{len(core)}  oa={sum(1 for v in lookups.values() if v.get('is_oa'))} pdf={sum(1 for v in lookups.values() if v.get('pdf_url'))}")
json.dump(lookups, open(lk_path,"w"), indent=1)

n_oa = sum(1 for v in lookups.values() if v.get("is_oa"))
n_pdf = sum(1 for v in lookups.values() if v.get("pdf_url"))
print(f"Unpaywall: is_oa={n_oa}/{len(lookups)}, with pdf_url={n_pdf}")

# ---- 2. download the new pdf_urls not already on disk ----
sp = os.path.join(DATA, "green-oa-status.json")
status = json.load(open(sp)) if os.path.exists(sp) else {}
got = miss = 0
todo = [(k, v["pdf_url"]) for k, v in lookups.items() if v.get("pdf_url")]
for i, (key, url) in enumerate(todo):
    out = os.path.join(PDFS, fn(key))
    if os.path.exists(out) and os.path.getsize(out) > 1000 and open(out,"rb").read(5).startswith(b"%PDF"):
        status[key] = "pdf"; got += 1; continue
    if status.get(key) == "pdf":
        got += 1; continue
    subprocess.run(["curl","-s","--max-time","60","-A",UA,"-L","-o",out,url], capture_output=True)
    ok = os.path.exists(out) and os.path.getsize(out) > 1000 and open(out,"rb").read(5).startswith(b"%PDF")
    status[key] = "pdf" if ok else "miss"
    if ok: got += 1
    else:
        if os.path.exists(out): os.remove(out)
        miss += 1
    time.sleep(1.0)
    if (i+1) % 15 == 0:
        json.dump(status, open(sp,"w"), indent=1); print(f"  dl {i+1}/{len(todo)} pdf={got} miss={miss}")
json.dump(status, open(sp,"w"), indent=1)
total_pdf = len([f for f in os.listdir(PDFS) if f.endswith('.pdf')])
print(f"DONE green-OA: downloaded ok={got} miss={miss}; total PDFs on disk now={total_pdf}")