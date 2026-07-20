#!/usr/bin/env python3
"""Phase 1 enrichment: OpenAlex (abstracts, OA urls, citations, refs) + Semantic Scholar
(TLDR, abstract fallback, openAccessPdf) for the DBLP core, keyed by DOI.

Uses curl via subprocess (network confirmed working that way in this sandbox).
Resumable: skips batch files already on disk. Polite: sleeps + retries on failure/429.
"""
import json, os, subprocess, time, sys

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
DATA = os.path.join(ROOT, "data")
ENR = os.path.join(DATA, "enrich")
os.makedirs(ENR, exist_ok=True)
UA = "l4-corpus-survey/0.1 (mengwong@gmail.com)"
MAILTO = "mengwong@gmail.com"

def curl(url, method="GET", data=None, hdrs=None, tries=6, timeout=60):
    cmd = ["curl", "-s", "--max-time", str(timeout), "-A", UA]
    if method == "POST":
        cmd += ["-X", "POST"]
    for k, v in (hdrs or {}).items():
        cmd += ["-H", f"{k}: {v}"]
    if data is not None:
        cmd += ["--data-binary", data]
    cmd.append(url)
    for attempt in range(1, tries + 1):
        p = subprocess.run(cmd, capture_output=True, text=True)
        out = p.stdout
        if out.strip():
            try:
                return json.loads(out)
            except json.JSONDecodeError:
                pass
        wait = min(attempt * 5, 45)
        print(f"    retry {attempt} ({url[:70]}...) wait {wait}s", file=sys.stderr)
        time.sleep(wait)
    return None

def deinvert(inv):
    if not inv:
        return None
    pos = {}
    for tok, idxs in inv.items():
        for i in idxs:
            pos[i] = tok
    return " ".join(pos[i] for i in sorted(pos)) or None

# ---------- load core, collect DOIs ----------
core = json.load(open(os.path.join(DATA, "index.json")))
papers = [r for r in core if r["type"] != "Editorship"]
dois = [r["doi"] for r in papers if r.get("doi")]
print(f"papers={len(papers)} with_doi={len(dois)}")

# ---------- OpenAlex: batch 50 DOIs per request ----------
OA_SEL = "id,doi,title,publication_year,cited_by_count,open_access,referenced_works,abstract_inverted_index,authorships,primary_location,type"
oa = {}
B = 50
batches = [dois[i:i+B] for i in range(0, len(dois), B)]
for bi, batch in enumerate(batches):
    fn = os.path.join(ENR, f"openalex-{bi:03d}.json")
    if os.path.exists(fn):
        d = json.load(open(fn))
    else:
        filt = "|".join(x.lower() for x in batch)
        url = (f"https://api.openalex.org/works?filter=doi:{filt}"
               f"&per-page={B}&mailto={MAILTO}&select={OA_SEL}")
        d = curl(url)
        if d is None:
            print(f"  OpenAlex batch {bi} FAILED", file=sys.stderr); continue
        json.dump(d, open(fn, "w"))
        time.sleep(1)
    for w in d.get("results", []):
        doi = (w.get("doi") or "").replace("https://doi.org/", "").lower()
        if not doi:
            continue
        oa[doi] = {
            "openalex_id": w.get("id"),
            "abstract": deinvert(w.get("abstract_inverted_index")),
            "cited_by_count": w.get("cited_by_count"),
            "oa_is_oa": (w.get("open_access") or {}).get("is_oa"),
            "oa_url": (w.get("open_access") or {}).get("oa_url"),
            "referenced_works": w.get("referenced_works") or [],
            "oa_type": w.get("type"),
        }
    if bi % 10 == 0:
        print(f"  OpenAlex batch {bi+1}/{len(batches)} (matched so far {len(oa)})")
print(f"OpenAlex enriched: {len(oa)}/{len(dois)} DOIs")

# ---------- Semantic Scholar: batch endpoint, 500 ids per request ----------
s2 = {}
S2_FIELDS = "externalIds,title,abstract,tldr,openAccessPdf,citationCount,influentialCitationCount"
SB = 500
sbatches = [dois[i:i+SB] for i in range(0, len(dois), SB)]
for bi, batch in enumerate(sbatches):
    fn = os.path.join(ENR, f"s2-{bi:03d}.json")
    if os.path.exists(fn):
        arr = json.load(open(fn))
    else:
        url = f"https://api.semanticscholar.org/graph/v1/paper/batch?fields={S2_FIELDS}"
        body = json.dumps({"ids": [f"DOI:{x}" for x in batch]})
        arr = curl(url, method="POST", data=body, hdrs={"Content-Type": "application/json"}, timeout=90)
        if arr is None:
            print(f"  S2 batch {bi} FAILED (rate limit?) — rerun to resume", file=sys.stderr); continue
        json.dump(arr, open(fn, "w"))
        time.sleep(3)
    for i, item in enumerate(arr or []):
        if not item:
            continue
        doi = batch[i].lower()
        s2[doi] = {
            "s2_id": item.get("paperId"),
            "tldr": (item.get("tldr") or {}).get("text"),
            "abstract_s2": item.get("abstract"),
            "s2_oa_pdf": (item.get("openAccessPdf") or {}).get("url"),
            "s2_citations": item.get("citationCount"),
            "s2_influential": item.get("influentialCitationCount"),
        }
    print(f"  S2 batch {bi+1}/{len(sbatches)} (enriched {len(s2)})")
print(f"S2 enriched: {len(s2)}/{len(dois)} DOIs")

# ---------- merge ----------
enriched = []
for r in papers:
    doi = (r.get("doi") or "").lower()
    e = dict(r)
    o = oa.get(doi, {})
    s = s2.get(doi, {})
    e["abstract"] = o.get("abstract") or s.get("abstract_s2")
    e["tldr"] = s.get("tldr")
    e["oa_url"] = o.get("oa_url") or s.get("s2_oa_pdf")
    e["oa_is_oa"] = o.get("oa_is_oa")
    e["cited_by_count"] = o.get("cited_by_count")
    e["referenced_works"] = o.get("referenced_works", [])
    e["openalex_id"] = o.get("openalex_id")
    e["s2_id"] = s.get("s2_id")
    enriched.append(e)

json.dump(enriched, open(os.path.join(DATA, "enriched.json"), "w"), ensure_ascii=False, indent=1)

n_abs = sum(1 for e in enriched if e["abstract"])
n_tldr = sum(1 for e in enriched if e["tldr"])
n_oa = sum(1 for e in enriched if e["oa_url"])
print(f"\n=== MERGED data/enriched.json ({len(enriched)} papers) ===")
print(f"  abstracts : {n_abs} ({100*n_abs//len(enriched)}%)")
print(f"  TLDRs     : {n_tldr} ({100*n_tldr//len(enriched)}%)")
print(f"  OA pdf url: {n_oa} ({100*n_oa//len(enriched)}%)")
for v in ("ICAIL", "JURIX", "DEON"):
    vp = [e for e in enriched if e["venue"] == v]
    print(f"  {v}: abstracts {sum(1 for e in vp if e['abstract'])}/{len(vp)}, "
          f"OA {sum(1 for e in vp if e['oa_url'])}/{len(vp)}")