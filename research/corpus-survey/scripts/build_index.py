#!/usr/bin/env python3
"""Phase 0 index builder: read raw DBLP pages -> normalized index.json + index.csv + summary."""
import json, csv, glob, os, collections

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
RAW = os.path.join(ROOT, "data", "raw")
OUT = os.path.join(ROOT, "data")

def norm_authors(info):
    a = info.get("authors", {}).get("author")
    if a is None:
        return []
    if isinstance(a, dict):
        a = [a]
    out = []
    for x in a:
        t = x.get("text", "") if isinstance(x, dict) else str(x)
        # strip dblp homonym disambiguation suffix like " 0001"
        out.append(t.rsplit(" ", 1)[0] if t[-4:].isdigit() and t[-4:].strip().isdigit() else t)
    return out

records = {}
for venue in ("icail", "jurix", "deon"):
    for path in sorted(glob.glob(os.path.join(RAW, f"{venue}-f*.json"))):
        with open(path) as fh:
            try:
                d = json.load(fh)
            except Exception as e:
                print("skip", path, e); continue
        hits = d.get("result", {}).get("hits", {}).get("hit", [])
        if isinstance(hits, dict):
            hits = [hits]
        for h in hits:
            info = h.get("info", {})
            key = info.get("key")
            if not key:
                continue
            year = info.get("year")
            records[key] = {
                "venue": venue.upper(),
                "key": key,
                "year": int(year) if year and str(year).isdigit() else None,
                "title": (info.get("title") or "").rstrip(". "),
                "type": info.get("type"),
                "access": info.get("access"),
                "doi": info.get("doi"),
                "ee": info.get("ee"),
                "pages": info.get("pages"),
                "authors": norm_authors(info),
                "url": info.get("url"),
            }

recs = sorted(records.values(), key=lambda r: (r["venue"], r["year"] or 0, r["key"]))

# JSON
with open(os.path.join(OUT, "index.json"), "w") as fh:
    json.dump(recs, fh, ensure_ascii=False, indent=1)

# CSV
cols = ["venue", "year", "type", "access", "title", "authors", "doi", "ee", "pages", "key", "url"]
with open(os.path.join(OUT, "index.csv"), "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(cols)
    for r in recs:
        w.writerow([r["venue"], r["year"], r["type"], r["access"], r["title"],
                    "; ".join(r["authors"]), r["doi"], r["ee"], r["pages"], r["key"], r["url"]])

# ---- Summary ----
def is_paper(r):
    # Editorship = proceedings volume; everything else is a content item.
    return r["type"] != "Editorship"

summary = {"generated": "phase0", "total_records": len(recs), "by_venue": {}}
print(f"TOTAL records: {len(recs)}\n")
for venue in ("ICAIL", "JURIX", "DEON"):
    vr = [r for r in recs if r["venue"] == venue]
    papers = [r for r in vr if is_paper(r)]
    types = collections.Counter(r["type"] for r in vr)
    access = collections.Counter(r["access"] for r in papers)
    years = sorted({r["year"] for r in vr if r["year"]})
    editions = collections.Counter(r["year"] for r in papers if r["year"])
    oa = access.get("open", 0)
    denom = sum(access.values()) or 1
    summary["by_venue"][venue] = {
        "records": len(vr), "papers_excl_editorship": len(papers),
        "editorship_volumes": types.get("Editorship", 0),
        "year_span": [min(years), max(years)] if years else None,
        "distinct_years": len(years),
        "types": dict(types), "access": dict(access),
        "open_pct": round(100*oa/denom, 1),
    }
    print(f"== {venue} ==  records={len(vr)}  papers(excl. editorship)={len(papers)}  "
          f"editorship_vols={types.get('Editorship',0)}")
    print(f"   years: {min(years)}–{max(years)} ({len(years)} editions)")
    print(f"   types: {dict(types)}")
    print(f"   access(papers): {dict(access)}  -> open={summary['by_venue'][venue]['open_pct']}%")
    print(f"   papers/edition: " + ", ".join(f"{y}:{editions[y]}" for y in sorted(editions)))
    print()

with open(os.path.join(OUT, "summary.json"), "w") as fh:
    json.dump(summary, fh, indent=2)
print("wrote data/index.json, data/index.csv, data/summary.json")