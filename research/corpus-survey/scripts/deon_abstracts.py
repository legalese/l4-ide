#!/usr/bin/env python3
"""DEON abstract backfill: the DEON DOIs are all Springer, but abstracts aren't in
OpenAlex/S2/Crossref. They ARE free on the SpringerLink chapter landing page (dc.description
meta), only the PDF is paywalled. Fetch politely, one at a time, cache + resume. Metadata only."""
import json, os, subprocess, time, re, html, sys

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
DATA = os.path.join(ROOT, "data")
CACHE = os.path.join(DATA, "enrich", "deon-springer")
os.makedirs(CACHE, exist_ok=True)
OUT = os.path.join(DATA, "deon-abstracts.json")
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

enriched = json.load(open(os.path.join(DATA, "enriched.json")))
targets = [p for p in enriched if p["venue"] == "DEON" and p.get("doi") and not p.get("abstract")]
print(f"DEON abstract targets (DOI, no abstract): {len(targets)}")

def extract_abstract(hcontent):
    for pat in (r'<meta\s+name="dc\.description"\s+content="([^"]+)"',
                r'<meta\s+content="([^"]+)"\s+name="dc\.description"'):
        m = re.search(pat, hcontent, re.I)
        if m and len(m.group(1)) > 40:
            return html.unescape(m.group(1)).strip()
    # fallback: Abstract section
    m = re.search(r'id="Abs1(?:-content)?"[^>]*>(.*?)</(?:div|section)>', hcontent, re.S)
    if m:
        txt = re.sub(r'<[^>]+>', ' ', m.group(1))
        txt = html.unescape(re.sub(r'\s+', ' ', txt)).strip()
        if len(txt) > 40:
            return txt
    return None

results = json.load(open(OUT)) if os.path.exists(OUT) else {}
ok = sum(1 for v in results.values() if v)
for i, p in enumerate(targets):
    key, doi = p["key"], p["doi"]
    if key in results:
        continue
    cf = os.path.join(CACHE, re.sub(r'[^A-Za-z0-9]', '_', doi) + ".html")
    if os.path.exists(cf):
        hc = open(cf, encoding="utf-8", errors="replace").read()
    else:
        url = f"https://link.springer.com/chapter/{doi}"
        pr = subprocess.run(["curl", "-s", "--max-time", "40", "-A", UA, "-L", url],
                            capture_output=True, text=True)
        hc = pr.stdout
        if hc:
            open(cf, "w").write(hc)
        time.sleep(2.5)  # polite
    abs = extract_abstract(hc) if hc else None
    results[key] = abs
    if abs:
        ok += 1
    if (i + 1) % 10 == 0:
        json.dump(results, open(OUT, "w"), ensure_ascii=False, indent=1)
        print(f"  {i+1}/{len(targets)}  recovered={ok}")

json.dump(results, open(OUT, "w"), ensure_ascii=False, indent=1)
got = sum(1 for v in results.values() if v)
print(f"DONE: {got}/{len(results)} abstracts recovered -> {OUT}")