#!/usr/bin/env python3
"""Prep Phase 5 synthesis: bundle the tight-core by facet (anchors first) for per-facet
related-work synthesis agents."""
import json, os

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
DATA = os.path.join(ROOT, "data")
SP = "/private/tmp/claude-502/-Users-mengwong-src-legalese-l4-ide/7c74365c-e8cf-487b-a5ba-00ebbcbd6c57/scratchpad/phase5"
BUN = os.path.join(SP, "bundles"); SEC = os.path.join(SP, "sections")
os.makedirs(BUN, exist_ok=True); os.makedirs(SEC, exist_ok=True)

sl = json.load(open(os.path.join(DATA, "shortlist.json")))
enr = {p["key"]: p for p in json.load(open(os.path.join(DATA, "enriched.json")))}
def tight(r): return r["relevance"]=="core" and r["confidence"]!="low" and r["has_abstract"]
core = [r for r in sl if tight(r)]

FACETS = ["intro","bounded-deontics","determinacy-frontier","cnl","fm-in-law"]
manifest = []
for f in FACETS:
    fp = [r for r in core if f in r["facets"]]
    bundle = []
    for r in fp:
        e = enr.get(r["key"], {})
        bundle.append({
            "key": r["key"], "title": r["title"], "authors": e.get("authors", []),
            "venue": r["venue"], "year": r["year"], "relation": r["relation"],
            "judge_note": r["why"], "cited_by_count": e.get("cited_by_count") or 0,
            "abstract": (e.get("abstract") or "")[:1300], "tldr": e.get("tldr") or "",
        })
    bundle.sort(key=lambda x: -x["cited_by_count"])  # anchors first
    bp = os.path.join(BUN, f"{f}.json")
    json.dump(bundle, open(bp, "w"), ensure_ascii=False, indent=1)
    manifest.append({"facet": f, "bundle": bp, "section": os.path.join(SEC, f"{f}.md"), "n": len(bundle)})

json.dump(manifest, open(os.path.join(SP, "manifest.json"), "w"), indent=1)
for m in manifest:
    print(f"  {m['facet']:22} n={m['n']}  -> {m['bundle']}")