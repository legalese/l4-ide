#!/usr/bin/env python3
"""Merge Phase 3 judge verdicts -> shortlist + cross-check vs the citation pre-rank.

Verifies every chunk's verdict count matches its input, joins verdicts back to metadata +
pre-rank, writes the facet-bucketed shortlist, and reports where the LLM judge and the graph
pre-rank DISAGREE (the interesting misses / false-positives)."""
import json, os, csv, glob, collections, sys

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
DATA = os.path.join(ROOT, "data")
SP = "/private/tmp/claude-502/-Users-mengwong-src-legalese-l4-ide/7c74365c-e8cf-487b-a5ba-00ebbcbd6c57/scratchpad/phase3"

manifest = json.load(open(os.path.join(SP, "manifest.json")))
prerank = {r["key"]: r for r in json.load(open(os.path.join(DATA, "prerank.json")))}
enriched = {p["key"]: p for p in json.load(open(os.path.join(DATA, "enriched.json")))}

# ---- collect + verify ----
verdicts = {}
missing = []
for m in manifest:
    op = m["out"]
    if not os.path.exists(op):
        missing.append((m["i"], "NO FILE", m["n"])); continue
    try:
        arr = json.load(open(op))
    except Exception as e:
        missing.append((m["i"], f"BAD JSON: {e}", m["n"])); continue
    if len(arr) != m["n"]:
        missing.append((m["i"], f"count {len(arr)} != {m['n']}", m["n"]))
    for v in arr:
        if v.get("key"):
            verdicts[v["key"]] = v

if missing:
    print("!! INCOMPLETE CHUNKS (re-run these):")
    for i, why, n in missing:
        print(f"   chunk-{i:02d}: {why}")
    print(f"   have {len(verdicts)} verdicts; proceeding with what exists.\n")

# ---- overlay: DEON re-judge on recovered abstracts (overrides original title-only verdicts) ----
DEON_SP = os.path.join(os.path.dirname(SP), "phase3", "deon")
deon_manifest = os.path.join(DEON_SP, "manifest.json")
if os.path.exists(deon_manifest):
    overlaid = 0
    for m in json.load(open(deon_manifest)):
        if os.path.exists(m["out"]):
            for v in json.load(open(m["out"])):
                if v.get("key"):
                    verdicts[v["key"]] = v
                    overlaid += 1
    print(f"DEON overlay: {overlaid} verdicts re-judged on recovered abstracts (override title-only).\n")

# ---- join ----
rows = []
for key, v in verdicts.items():
    pr = prerank.get(key, {})
    en = enriched.get(key, {})
    rows.append({
        "key": key, "venue": pr.get("venue"), "year": pr.get("year"),
        "title": pr.get("title"), "authors": en.get("authors", []),
        "relevance": v.get("relevance"), "keep": v.get("keep"),
        "facets": v.get("facets", []), "relation": v.get("relation"),
        "confidence": v.get("confidence"), "why": v.get("why"),
        "prerank_rank": pr.get("rank"), "prerank_composite": pr.get("composite"),
        "is_seed": pr.get("is_seed"), "cites_cluster": pr.get("cites_cluster"),
        "doi": en.get("doi"), "oa_url": en.get("oa_url"),
        "cited_by_count": en.get("cited_by_count"), "has_abstract": bool(en.get("abstract")),
    })

REL_ORDER = {"core": 0, "adjacent": 1, "peripheral": 2, "off-topic": 3, "unknown": 4}
rows.sort(key=lambda r: (REL_ORDER.get(r["relevance"], 9), -(r["prerank_composite"] or 0)))

json.dump(rows, open(os.path.join(DATA, "phase3-verdicts.json"), "w"), ensure_ascii=False, indent=1)

shortlist = [r for r in rows if r["keep"]]
json.dump(shortlist, open(os.path.join(DATA, "shortlist.json"), "w"), ensure_ascii=False, indent=1)
with open(os.path.join(DATA, "shortlist.csv"), "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["relevance","venue","year","facets","relation","confidence","prerank_rank",
                "cited_by_count","oa_url","title","authors","why","key"])
    for r in shortlist:
        w.writerow([r["relevance"], r["venue"], r["year"], "|".join(r["facets"]), r["relation"],
                    r["confidence"], r["prerank_rank"], r["cited_by_count"], r["oa_url"],
                    r["title"], "; ".join(r["authors"]), r["why"], r["key"]])

# ---- summary ----
total = len(rows)
rel = collections.Counter(r["relevance"] for r in rows)
print(f"=== PHASE 3 ({total} judged) ===")
for k in ("core","adjacent","peripheral","off-topic","unknown"):
    print(f"  {k:11}: {rel.get(k,0)}")
print(f"  SHORTLIST (keep): {len(shortlist)}")
print()
print("By venue (kept / judged):")
for vn in ("ICAIL","JURIX","DEON"):
    vr = [r for r in rows if r["venue"]==vn]
    print(f"  {vn}: {sum(1 for r in vr if r['keep'])}/{len(vr)}")
print()
print("Facet buckets (kept papers; papers can appear in >1):")
fac = collections.Counter(f for r in shortlist for f in r["facets"])
for f, n in fac.most_common():
    print(f"  {f:22}: {n}")
print()
# ---- cross-check judge vs pre-rank ----
seeds = [r for r in rows if r["is_seed"]]
seed_kept = sum(1 for r in seeds if r["keep"])
print(f"Recall proxy — cluster seeds kept: {seed_kept}/{len(seeds)} "
      f"({100*seed_kept//max(len(seeds),1)}%)")
# false positives: pre-rank top-150 but judge cut
top150 = sorted(rows, key=lambda r: (r["prerank_rank"] or 99999))[:150]
fp = [r for r in top150 if not r["keep"]]
print(f"Pre-rank top-150 that the judge CUT (false-positives): {len(fp)}")
for r in fp[:12]:
    print(f"    ~#{r['prerank_rank']:>4} {r['relevance']:10} {r['venue']} {r['year']} | {r['title'][:52]}")
# misses: judge core but pre-rank buried (rank > 600)
misses = [r for r in rows if r["relevance"]=="core" and (r["prerank_rank"] or 0) > 600]
misses.sort(key=lambda r: -(r["prerank_rank"] or 0))
print(f"\nJudge-CORE that pre-rank buried (rank>600) — pre-rank misses: {len(misses)}")
for r in misses[:12]:
    print(f"    #{r['prerank_rank']:>4} {r['venue']} {r['year']} {'|'.join(r['facets']) or '-':22} | {r['title'][:50]}")