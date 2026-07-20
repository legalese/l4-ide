#!/usr/bin/env python3
"""Phase 4 acquisition audit: classify each tight-core paper by reachability channel and emit
a download list for the genuinely-open ones. No downloads here — audit + plan only."""
import json, os, csv, collections

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
DATA = os.path.join(ROOT, "data")

sl = json.load(open(os.path.join(DATA, "shortlist.json")))
enr = {p["key"]: p for p in json.load(open(os.path.join(DATA, "enriched.json")))}

def tight(r):
    return r["relevance"] == "core" and r["confidence"] != "low" and r["has_abstract"]
core = [r for r in sl if tight(r)]

def channel(r):
    e = enr.get(r["key"], {})
    oa = (e.get("oa_url") or "").strip()
    if oa:
        return "open", oa
    ee = e.get("ee") or ""
    if r["venue"] == "JURIX":
        return "jurix-archive", "jurix.nl / IOS FAIA (largely OA; fetch by hand)"
    if r["venue"] == "ICAIL":
        return "acm-paywall", ee or (("https://doi.org/" + e["doi"]) if e.get("doi") else "")
    if r["venue"] == "DEON":
        return "springer-paywall", ee or (("https://doi.org/" + e["doi"]) if e.get("doi") else "")
    return "unknown", ee

rows = []
for r in core:
    ch, url = channel(r)
    rows.append({**r, "channel": ch, "acq_url": url})

# acquire-plan.csv
with open(os.path.join(DATA, "acquire-plan.csv"), "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["channel","venue","year","facets","title","authors","acq_url","doi","key"])
    for r in sorted(rows, key=lambda r: (r["channel"], r["venue"])):
        e = enr.get(r["key"], {})
        w.writerow([r["channel"], r["venue"], r["year"], "|".join(r["facets"]), r["title"],
                    "; ".join(r["authors"]), r["acq_url"], e.get("doi"), r["key"]])

# open download list (key -> direct url) for the fetcher
openset = {r["key"]: r["acq_url"] for r in rows if r["channel"] == "open"}
json.dump(openset, open(os.path.join(DATA, "acquire-open.json"), "w"), indent=1)

# report
print(f"tight-core: {len(core)}")
by_ch = collections.Counter(r["channel"] for r in rows)
print("\nBy acquisition channel:")
for ch, n in by_ch.most_common():
    print(f"  {ch:16}: {n}")
print("\nOpen (direct OA url) by venue:")
ov = collections.Counter(r["venue"] for r in rows if r["channel"] == "open")
for v, n in ov.most_common():
    tot = sum(1 for r in rows if r["venue"] == v)
    print(f"  {v}: {n}/{tot}")
print("\nPaywalled residue (needs authenticated/sparing pulls):")
for v in ("ICAIL","JURIX","DEON"):
    pw = sum(1 for r in rows if r["venue"] == v and r["channel"].endswith(("paywall","archive")))
    print(f"  {v}: {pw}")
print(f"\nwrote acquire-plan.csv ({len(rows)} rows) + acquire-open.json ({len(openset)} direct-OA)")