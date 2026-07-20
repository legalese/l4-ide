#!/usr/bin/env python3
"""Finalize Phase 3: split the keep-set into the trustworthy tight-core, the DEON-provisional
(title-only) set, and emit a facet-bucketed markdown for skimming."""
import json, os, csv, collections

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
DATA = os.path.join(ROOT, "data")
sl = json.load(open(os.path.join(DATA, "shortlist.json")))

def tight(r):  # trustworthy: core, non-low confidence, has an abstract
    return r["relevance"] == "core" and r["confidence"] != "low" and r["has_abstract"]

core = [r for r in sl if tight(r)]
deon_prov = [r for r in sl if r["venue"] == "DEON" and not tight(r)]  # title-only DEON keeps

# tight-core CSV
with open(os.path.join(DATA, "shortlist-core.csv"), "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["venue","year","facets","relation","confidence","prerank_rank","cited_by_count","oa_url","title","authors","why","key"])
    for r in sorted(core, key=lambda r: (r["venue"], -(r["cited_by_count"] or 0))):
        w.writerow([r["venue"], r["year"], "|".join(r["facets"]), r["relation"], r["confidence"],
                    r["prerank_rank"], r["cited_by_count"], r["oa_url"], r["title"],
                    "; ".join(r["authors"]), r["why"], r["key"]])

# DEON-provisional list (needs abstract acquisition before trusting)
json.dump([{k: r[k] for k in ("key","year","title","authors","facets","why","oa_url","doi")} for r in deon_prov],
          open(os.path.join(DATA, "deon-provisional.json"), "w"), ensure_ascii=False, indent=1)

# facet-bucketed markdown of the tight core (top by citations within facet)
FAC = ["intro","bounded-deontics","determinacy-frontier","cnl","fm-in-law"]
FAC_TITLE = {"intro":"intro (ICAIL) — languages/DSLs/rules-as-code for law",
             "bounded-deontics":"bounded-deontics (JURIX) — deontic/defeasible/temporal norms",
             "determinacy-frontier":"determinacy-frontier (Cambridge CLS) — ambiguity/interpretation limits",
             "cnl":"cnl (CNL workshop) — controlled NL / LegalRuleML / round-trip",
             "fm-in-law":"fm-in-law (ProLaLa) — verification/model-checking/theorem-proving"}
lines = ["# Phase 3 tight-core shortlist — facet buckets",
         "",
         f"Trustworthy core = relevance **core** + confidence ≥ med + has abstract = **{len(core)} papers**.",
         "(Full keep-set is 717; DEON-provisional title-only keeps are in `deon-provisional.json`.)",
         "Papers can appear under >1 facet. Within each facet, top ~12 by citation count.",
         ""]
for f in FAC:
    fp = [r for r in core if f in r["facets"]]
    fp.sort(key=lambda r: -(r["cited_by_count"] or 0))
    lines.append(f"## {FAC_TITLE[f]}  ({len(fp)})")
    lines.append("")
    for r in fp[:12]:
        au = ", ".join(r["authors"][:2]) + (" et al." if len(r["authors"]) > 2 else "")
        oa = " · [OA]" if r["oa_url"] else ""
        lines.append(f"- **{r['title']}** — {au}, {r['venue']} {r['year']} "
                     f"(cites {r['cited_by_count']}, {r['relation']}){oa}  \n  _{r['why']}_")
    lines.append("")
open(os.path.join(DATA, "PHASE3-SHORTLIST.md"), "w").write("\n".join(lines))

print(f"tight-core: {len(core)}  (ICAIL {sum(1 for r in core if r['venue']=='ICAIL')}, "
      f"JURIX {sum(1 for r in core if r['venue']=='JURIX')}, DEON {sum(1 for r in core if r['venue']=='DEON')})")
print(f"DEON-provisional (title-only, needs abstracts): {len(deon_prov)}")
print("facet tight-core counts:", dict(collections.Counter(f for r in core for f in r["facets"])))
print("wrote shortlist-core.csv, deon-provisional.json, PHASE3-SHORTLIST.md")