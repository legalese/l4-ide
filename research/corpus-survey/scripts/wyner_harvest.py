#!/usr/bin/env python3
"""W0 — Adam Wyner oeuvre harvest (OpenAlex author A5063413613 + DBLP pid 73/3639).
Produces dossiers/wyner/works.json + a W1-seed interest map (venues, coauthors, concepts, years)."""
import json, os, subprocess, time, sys, collections

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
WY = os.path.join(ROOT, "dossiers", "wyner")
os.makedirs(WY, exist_ok=True)
UA = "l4-corpus-survey/0.1 (mengwong@gmail.com)"
AUTHOR = "A5063413613"

def curl(url, tries=6, timeout=60):
    for a in range(1, tries+1):
        p = subprocess.run(["curl","-s","--max-time",str(timeout),"-A",UA,url], capture_output=True, text=True)
        if p.stdout.strip():
            try: return json.loads(p.stdout)
            except json.JSONDecodeError: pass
        time.sleep(min(a*4, 30))
    return None

def deinvert(inv):
    if not inv: return None
    pos = {}
    for tok, idxs in inv.items():
        for i in idxs: pos[i] = tok
    return " ".join(pos[i] for i in sorted(pos)) or None

# ---- OpenAlex author works (cursor paginated) ----
SEL = "id,doi,title,publication_year,type,cited_by_count,open_access,authorships,primary_location,concepts,abstract_inverted_index"
works, cursor = [], "*"
while cursor:
    url = (f"https://api.openalex.org/works?filter=author.id:{AUTHOR}"
           f"&per-page=200&cursor={cursor}&mailto=mengwong@gmail.com&select={SEL}")
    d = curl(url)
    if not d: print("OpenAlex fetch failed", file=sys.stderr); break
    works.extend(d.get("results", []))
    cursor = d.get("meta", {}).get("next_cursor")
    time.sleep(1)
print(f"OpenAlex works: {len(works)}")

recs = []
for w in works:
    auths = [a.get("author", {}).get("display_name") for a in w.get("authorships", [])]
    src = (w.get("primary_location") or {}).get("source") or {}
    recs.append({
        "title": (w.get("title") or "").rstrip(". "),
        "year": w.get("publication_year"),
        "type": w.get("type"),
        "venue": src.get("display_name"),
        "doi": (w.get("doi") or "").replace("https://doi.org/","") or None,
        "cited_by_count": w.get("cited_by_count"),
        "oa_url": (w.get("open_access") or {}).get("oa_url"),
        "coauthors": [a for a in auths if a and a != "Adam Wyner" and "Wyner" not in a],
        "concepts": [c.get("display_name") for c in (w.get("concepts") or []) if c.get("score",0) >= 0.3],
        "abstract": deinvert(w.get("abstract_inverted_index")),
    })
recs.sort(key=lambda r: (r["year"] or 0))
json.dump(recs, open(os.path.join(WY, "works.json"), "w"), ensure_ascii=False, indent=1)

# ---- DBLP pid (canonical venue/coauthor list) ----
dblp = curl("https://dblp.org/pid/73/3639.xml".replace(".xml",".xml"))  # xml not json; fetch raw instead
p = subprocess.run(["curl","-s","--max-time","45","-A",UA,"https://dblp.org/pid/73/3639.xml"], capture_output=True, text=True)
open(os.path.join(WY, "dblp-73-3639.xml"), "w").write(p.stdout)
print(f"DBLP xml bytes: {len(p.stdout)}")

# ---- W1 seed: interest map ----
years = [r["year"] for r in recs if r["year"]]
venues = collections.Counter(r["venue"] for r in recs if r["venue"])
concepts = collections.Counter(c for r in recs for c in r["concepts"])
coauth = collections.Counter(c for r in recs for c in r["coauthors"])
by_year = collections.Counter(r["year"] for r in recs if r["year"])

imap = {
    "author": "Adam Wyner", "openalex": AUTHOR, "dblp_pid": "73/3639",
    "n_works": len(recs), "year_span": [min(years), max(years)] if years else None,
    "total_citations": sum(r["cited_by_count"] or 0 for r in recs),
    "top_venues": venues.most_common(15),
    "top_concepts": concepts.most_common(25),
    "top_coauthors": coauth.most_common(20),
    "works_per_year": dict(sorted(by_year.items())),
    "most_cited": sorted(recs, key=lambda r:-(r["cited_by_count"] or 0))[:15],
}
json.dump(imap, open(os.path.join(WY, "interest-map.json"), "w"), ensure_ascii=False, indent=1)

print(f"\n=== Wyner W0 ===  works={len(recs)}  span={imap['year_span']}  citations={imap['total_citations']}")
print("top venues:", ", ".join(f"{v}({n})" for v,n in venues.most_common(8)))
print("top concepts:", ", ".join(f"{c}({n})" for c,n in concepts.most_common(12)))
print("top coauthors:", ", ".join(f"{c}({n})" for c,n in coauth.most_common(10)))
print("most cited:")
for r in imap["most_cited"][:8]:
    print(f"  [{r['cited_by_count']}] {r['year']} {r['title'][:70]}")