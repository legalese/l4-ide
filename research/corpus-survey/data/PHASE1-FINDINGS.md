# Phase 1 — Enrichment findings

**Run date:** 2026-07-20 · **Inputs:** `data/index.json` (1,758 papers, 1,515 with DOI).
**Sources:** OpenAlex (batch-by-DOI, 50/req) + Semantic Scholar (`/paper/batch`, 500/req).
**Output:** `data/enriched.json` (all 1,758 papers + abstract / tldr / oa_url / cited_by_count /
referenced_works / openalex_id / s2_id). Raw batches under `data/enrich/`. Script: `scripts/enrich.py`.

## Match rates

- OpenAlex resolved **1,505 / 1,515** DOIs; Semantic Scholar **1,476 / 1,515**.
- Merged coverage over all 1,758 papers: **abstracts 76%**, **TLDRs 68%**, **OA-PDF url 43%**.

## Headline: true OA is *far* higher than the DBLP flag suggested

The Phase-0 DBLP `access` flag was a floor. Real open-copy availability (OpenAlex `oa_url` +
S2 `openAccessPdf`):

| Venue | DBLP-open (P0) | **True OA (P1)** | Abstracts |
|-------|---------------:|-----------------:|----------:|
| ICAIL | 1.7%  | **39%** (329/840) | 767/840 (91%) |
| JURIX | 20.3% | **60%** (405/680) | 577/680 (85%) |
| DEON  | 0%    | **15%** (36/238)  | **3/238 (1%)** |

→ Acquisition (Phase 4) is much cheaper than feared: ~40% of ICAIL and ~60% of JURIX already
have a reachable open PDF before we touch a paywall.

## The DEON abstract hole (Phase-3 risk — LOGGED)

DEON has **3 abstracts out of 238**. Causes: only 125/238 have DOIs at all, and even the DOI'd
Springer-LNCS deontic-logic papers largely lack abstracts in OpenAlex/S2. **Consequence:** the
Phase-3 abstract filter will be nearly blind on DEON. Mitigations to weigh:
- Title-only classification for DEON (lower precision, flag as such).
- Pull abstracts from SpringerLink LNCS TOC pages for the DOI'd DEON years (adds a source).
- Accept lower DEON recall and lean on the citation-graph pre-rank (Phase 2) + known-cluster
  seeds (Governatori/Sartor/Prakken are heavy in DEON and well-cited).
DEON is the deontic-logic heartland (Bounded-Deontics facet), so we don't want it blind — but
title+citation signal may suffice to surface the ~20–30 that matter.

## Ready for Phase 2

`enriched.json` now carries `referenced_works` (OpenAlex outgoing citation edges) and
`cited_by_count` — the inputs for the free citation-graph pre-rank against the known cluster.
