#!/usr/bin/env python3
"""Fix Phase-4 yield: OpenAlex oa_url is a landing page; the DIRECT pdf is in
best_oa_location.pdf_url / locations[].pdf_url. Re-fetch those for ALL tight-core DOIs
(may also surface OA PDFs for some 'paywalled' ones). Emit key->direct_pdf_url."""
import json, os, subprocess, time, re

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
DATA = os.path.join(ROOT, "data")
UA = "l4-corpus-survey/0.1 (mengwong@gmail.com)"

sl = json.load(open(os.path.join(DATA, "shortlist.json")))
enr = {p["key"]: p for p in json.load(open(os.path.join(DATA, "enriched.json")))}
def tight(r): return r["relevance"]=="core" and r["confidence"]!="low" and r["has_abstract"]
core = [r for r in sl if tight(r)]
doi2key = {}
for r in core:
    d = (enr.get(r["key"], {}).get("doi") or "").lower()
    if d: doi2key[d] = r["key"]
dois = list(doi2key)
print(f"tight-core with DOI: {len(dois)}")

def curl_json(url, tries=5):
    for a in range(1, tries+1):
        p = subprocess.run(["curl","-s","--max-time","60","-A",UA,url], capture_output=True, text=True)
        if p.stdout.strip():
            try: return json.loads(p.stdout)
            except: pass
        time.sleep(a*3)
    return None

def arxiv_pdf(u):
    m = re.search(r'arxiv\.org/abs/([^\s?]+)', u or '')
    return f"https://arxiv.org/pdf/{m.group(1)}.pdf" if m else None

direct = {}
B = 50
for i in range(0, len(dois), B):
    batch = dois[i:i+B]
    filt = "|".join(batch)
    d = curl_json(f"https://api.openalex.org/works?filter=doi:{filt}"
                  f"&per-page={B}&mailto=mengwong@gmail.com"
                  f"&select=doi,open_access,best_oa_location,locations")
    if not d: continue
    for w in d.get("results", []):
        doi = (w.get("doi") or "").replace("https://doi.org/","").lower()
        key = doi2key.get(doi)
        if not key: continue
        url = None
        b = w.get("best_oa_location") or {}
        if b.get("pdf_url"): url = b["pdf_url"]
        if not url:
            for loc in (w.get("locations") or []):
                if loc.get("pdf_url"): url = loc["pdf_url"]; break
        if not url:  # arxiv landing -> pdf
            oa = (w.get("open_access") or {}).get("oa_url")
            url = arxiv_pdf(oa) or arxiv_pdf((b or {}).get("landing_page_url"))
        if url:
            direct[key] = url
    time.sleep(1)
    print(f"  batch {i//B+1}: direct urls so far {len(direct)}")

json.dump(direct, open(os.path.join(DATA, "acquire-direct.json"), "w"), indent=1)
print(f"DONE: {len(direct)}/{len(dois)} tight-core have a DIRECT pdf url -> acquire-direct.json")