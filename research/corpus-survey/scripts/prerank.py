#!/usr/bin/env python3
"""Phase 2 — free citation-graph pre-rank (no LLM).

Builds the known-cluster work-set from OpenAlex (author.id -> all work ids), then scores every
corpus paper by graph proximity to the cluster + a cheap lexical facet signal. All inputs already
in enriched.json except the cluster work-ids (a light OpenAlex fetch). Transparent component
scores are kept so Phase 3 can re-weight.
"""
import json, os, subprocess, time, sys, re, math, collections

ROOT = "/Users/mengwong/src/legalese/l4wt/corpus-survey/research/corpus-survey"
DATA = os.path.join(ROOT, "data")
CACHE = os.path.join(DATA, "enrich", "cluster")
os.makedirs(CACHE, exist_ok=True)
UA = "l4-corpus-survey/0.1 (mengwong@gmail.com)"

CLUSTER = {  # name -> OpenAlex author id
    "Bench-Capon": "A5074094975", "Prakken": "A5020760288", "Sartor": "A5084837357",
    "Governatori": "A5058360953", "Gordon": "A5109053397", "Wyner": "A5063413613",
}

def curl(url, tries=6, timeout=60):
    for a in range(1, tries+1):
        p = subprocess.run(["curl","-s","--max-time",str(timeout),"-A",UA,url], capture_output=True, text=True)
        if p.stdout.strip():
            try: return json.loads(p.stdout)
            except json.JSONDecodeError: pass
        time.sleep(min(a*4, 30))
    return None

def norm_id(u):
    return (u or "").replace("https://openalex.org/", "")

# ---- 1. cluster work-id sets (cached per author) ----
cluster_works = {}   # name -> set(workids)
for name, aid in CLUSTER.items():
    fn = os.path.join(CACHE, f"{aid}.json")
    if os.path.exists(fn):
        ids = json.load(open(fn))
    else:
        ids, cursor = [], "*"
        while cursor:
            d = curl(f"https://api.openalex.org/works?filter=author.id:{aid}"
                     f"&per-page=200&cursor={cursor}&select=id&mailto=mengwong@gmail.com")
            if not d: break
            ids += [norm_id(w["id"]) for w in d.get("results", [])]
            cursor = d.get("meta", {}).get("next_cursor")
            time.sleep(1)
        json.dump(ids, open(fn, "w"))
    cluster_works[name] = set(ids)
    print(f"  {name}: {len(cluster_works[name])} works")

ALL_CLUSTER = set().union(*cluster_works.values())
print(f"CLUSTER_WORKS union: {len(ALL_CLUSTER)}")

# ---- 2. load corpus, build internal graph ----
papers = json.load(open(os.path.join(DATA, "enriched.json")))
for p in papers:
    p["_oid"] = norm_id(p.get("openalex_id"))
    p["_refs"] = set(norm_id(r) for r in (p.get("referenced_works") or []))
corpus_ids = {p["_oid"] for p in papers if p["_oid"]}

# in-corpus indegree + which seeds cite whom
indegree = collections.Counter()
cited_by_seed = collections.Counter()
for p in papers:
    is_seed = p["_oid"] in ALL_CLUSTER
    for r in p["_refs"]:
        if r in corpus_ids:
            indegree[r] += 1
            if is_seed:
                cited_by_seed[r] += 1

# ---- 3. lexical facet signal ----
FACETS = {
    "bounded-deontics": r"deontic|obligation|permission|prohibition|normative|\bnorm\b|contrary-to-duty|violation",
    "defeasible-fm":    r"defeasibl|non-?monotonic|argumentation scheme|model check|temporal logic|\bLTL\b|formal verif|theorem prov",
    "cnl":              r"controlled natural language|\bCNL\b|controlled english|attempto|\bACE\b|isomorphi|LegalRuleML|rule extraction|rules?[ -]as[ -]code|natural language generation",
    "determinacy":      r"ambigu|vaguen|open texture|interpret|indetermin|discretion",
    "intro-executable": r"executable|operational semantics|domain-specific language|\bDSL\b|formaliz|encoding of|smart contract",
}
FACET_RE = {k: re.compile(v, re.I) for k, v in FACETS.items()}

def facet_hits(p):
    txt = f"{p.get('title','')} . {p.get('abstract') or ''}"
    return {k: len(rx.findall(txt)) for k, rx in FACET_RE.items()}

# ---- 4. score ----
ranked = []
for p in papers:
    oid = p["_oid"]
    is_seed = oid in ALL_CLUSTER
    cites_cluster = len(p["_refs"] & ALL_CLUSTER)
    cby_seed = cited_by_seed.get(oid, 0)
    indeg = indegree.get(oid, 0)
    fh = facet_hits(p)
    lex = sum(fh.values())
    seed_authors = [n for n, s in cluster_works.items() if oid in s]
    # composite: prioritise L4-relevance (cluster proximity + facet vocab), not raw fame
    composite = round(
        4.0 * (1 if is_seed else 0)
        + 1.2 * min(cites_cluster, 8)
        + 1.5 * min(cby_seed, 6)
        + 1.0 * min(lex, 8)
        + 0.8 * math.log1p(indeg)
        + 0.3 * math.log1p(p.get("cited_by_count") or 0), 2)
    ranked.append({
        "venue": p["venue"], "year": p["year"], "title": p["title"],
        "authors": p["authors"], "doi": p.get("doi"), "oa_url": p.get("oa_url"),
        "composite": composite, "is_seed": is_seed, "seed_authors": seed_authors,
        "cites_cluster": cites_cluster, "cited_by_seed_incorpus": cby_seed,
        "in_corpus_indegree": indeg, "cited_by_count": p.get("cited_by_count"),
        "facets": {k: v for k, v in fh.items() if v}, "lex_total": lex,
        "has_abstract": bool(p.get("abstract")), "key": p["key"],
    })
ranked.sort(key=lambda r: -r["composite"])
for i, r in enumerate(ranked):
    r["rank"] = i + 1

json.dump(ranked, open(os.path.join(DATA, "prerank.json"), "w"), ensure_ascii=False, indent=1)
import csv
with open(os.path.join(DATA, "prerank.csv"), "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["rank","composite","venue","year","is_seed","cites_cluster","cited_by_seed",
                "indegree","cited_by_count","lex","facets","title","authors","oa_url","key"])
    for r in ranked:
        w.writerow([r["rank"], r["composite"], r["venue"], r["year"], int(r["is_seed"]),
                    r["cites_cluster"], r["cited_by_seed_incorpus"], r["in_corpus_indegree"],
                    r["cited_by_count"], r["lex_total"], "|".join(r["facets"]),
                    r["title"], "; ".join(r["authors"]), r["oa_url"], r["key"]])

# ---- 5. summary ----
n_seed = sum(1 for r in ranked if r["is_seed"])
print(f"\n=== PRE-RANK ({len(ranked)} papers) ===")
print(f"cluster seeds in corpus: {n_seed}")
print(f"papers citing >=1 cluster work: {sum(1 for r in ranked if r['cites_cluster']>0)}")
print(f"papers with any facet-vocab hit: {sum(1 for r in ranked if r['lex_total']>0)}")
for v in ("ICAIL","JURIX","DEON"):
    vs = [r for r in ranked if r["venue"]==v]
    print(f"  {v}: seeds {sum(1 for r in vs if r['is_seed'])}/{len(vs)}, "
          f"top-100 share {sum(1 for r in ranked[:100] if r['venue']==v)}")
print("\nTop 25 overall:")
for r in ranked[:25]:
    tag = "SEED" if r["is_seed"] else "    "
    fac = ",".join(r["facets"]) or "-"
    print(f"  #{r['rank']:>4} {r['composite']:>5} [{tag}] {r['venue']} {r['year']} "
          f"cc{r['cites_cluster']} cbs{r['cited_by_seed_incorpus']} id{r['in_corpus_indegree']} "
          f"| {r['title'][:56]} | {fac}")