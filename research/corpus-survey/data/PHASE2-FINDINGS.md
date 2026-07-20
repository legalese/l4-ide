# Phase 2 — Citation-graph pre-rank findings

**Run date:** 2026-07-20 · **Input:** `data/enriched.json` + OpenAlex cluster work-sets.
**Output:** `data/prerank.{json,csv}` (all 1,758 papers, transparent component scores, sorted).
**Cost:** no LLM. Script: `scripts/prerank.py`.

## Method (all signals kept separate so Phase 3 can re-weight)

The "known cluster" = 6 authors resolved to OpenAlex IDs, expanded to **all** their work IDs
(union = **1,771 works**): Bench-Capon (397), Sartor (472), Governatori (482), Prakken (233),
Gordon (164), Wyner (154). Because that set is the union of the cluster's works, **cluster
membership of a corpus paper is exact set-membership** (`openalex_id ∈ CLUSTER_WORKS`) — no fuzzy
name-matching.

Per-paper components:
- `is_seed` — paper is itself a cluster-authored work.
- `cites_cluster` — # of its references that are cluster works (outgoing edge into the cluster).
- `cited_by_seed_incorpus` — # of cluster-authored *corpus* papers that cite it (incoming; in-corpus only — see caveat).
- `in_corpus_indegree` — # of all corpus papers citing it (field influence).
- lexical facet hits — regex vocab per L4 facet (deontic / defeasible-fm / cnl / determinacy / intro-executable).

Composite deliberately weights **L4-relevance (cluster proximity + facet vocab) over raw fame**
(global `cited_by_count` is only a 0.3·log tiebreaker), so old-but-off-topic classics don't
crowd the top.

## Results

- **223 cluster seeds** in the corpus (ICAIL 105, JURIX 107, DEON 11).
- **576 papers** cite ≥1 cluster work; **560** have ≥1 facet-vocab hit.
- Top-100 composition: ICAIL 59, JURIX 36, DEON 5.
- The top of the ranking is exactly the L4 wheelhouse — temporal/defeasible **deontic** logic,
  **isomorphism**, **rule extraction**, factors/values CBR, argumentation schemes. Top 3:
  1. Governatori/Rotolo, "Temporalised Normative Positions in Defeasible Logic" (ICAIL'05)
  2. "On the relationship between Carneades and Defeasible Logic" (ICAIL'11)
  3. "Thou shalt is not you will" (ICAIL'15)

## Caveats (LOGGED)

- **`cited_by_seed` is in-corpus only.** True "cited by the cluster" would need the cluster works'
  *outgoing* references (not fetched — we only pulled cluster work *ids*). In-corpus incoming
  edges are a lower bound; fine as a ranking nudge, not a completeness claim.
- **DEON under-ranks structurally.** Only 11 DEON seeds + the 3/238 abstract hole (Phase 1) mean
  DEON's lexical + citation signal is thin. The pre-rank will *under-surface* relevant DEON work.
  → Phase 3 must treat DEON specially (title-based + don't trust a low pre-rank there).
- Pre-rank is a **sort, not a filter** — nothing is dropped. Phase 3 (Sonnet) reads abstracts to
  make the actual keep/cut + facet-tag decisions; the pre-rank just orders the queue and gives a
  cheap prior. Recall check vs the Bench-Capon "50" happens in Phase 3.
