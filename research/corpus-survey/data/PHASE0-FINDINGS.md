# Phase 0 — Index harvest findings

**Run date:** 2026-07-20 · **Source of record:** DBLP per-stream search API
(`stream:streams/conf/<venue>:`, 100-hit/page cap, paginated with `f` offset).
Raw pages archived under `data/raw/`. Derived index: `data/index.json`, `data/index.csv`,
machine summary: `data/summary.json`.

## Headline counts (DBLP-catalogued core)

| Venue | Records | Papers (excl. editorship) | Proc. vols | Year span | Editions |
|-------|--------:|--------------------------:|-----------:|-----------|---------:|
| ICAIL |     864 |                       840 |         24 | 1987–2025 | 20 biennial |
| JURIX |     703 |                       680 |         23 | 2005–2025 | 21 annual |
| DEON  |     250 |                       238 |         12 | 1996–2025 | 12 (of ~17) |
| **Total** | **1,817** | **1,758** | 59 | | |

"Papers" excludes DBLP `Editorship` entries (the proceedings volumes themselves).
Per-edition paper counts are in `summary.json` (`papers/edition`).

## Open-access signal (first pass = DBLP `access` flag only)

DBLP's `access` flag is a **floor**, not the true OA rate — it marks a paper "open" only when
DBLP itself has an OA link. Real reachability is higher once OpenAlex `openAccessPdf`, author
copies, and the venue archives (below) are folded in (that's Phase 1).

| Venue | open | closed | unavailable | DBLP-open % |
|-------|-----:|-------:|------------:|------------:|
| ICAIL |   14 |    819 |           7 | **1.7%** |
| JURIX |  138 |    540 |           2 | **20.3%** |
| DEON  |    0 |    125 |         113 | **0.0%** |

## Acquisition-channel reconnaissance (feeds Phase 4)

- **ICAIL = the hard wall.** ACM DL, ~98% closed on the DBLP flag. Every paper has a DOI, so
  Phase 1 can look each up in OpenAlex/Unpaywall for an OA author copy; the paywalled residue
  is fetched sparingly and with rights (§5).
- **JURIX = the open one.** Better than its 20% flag suggests:
  - `jurix.nl/pdf/jNN-NN.pdf` serves **open loose PDFs** for the earlier volumes (verified
    `j05-01.pdf` → 200 `application/pdf`). Newer years 404 there and redirect to IOS Press.
  - 2005–2025 volumes are IOS Press **FAIA** (`ebooks.iospress.nl`), a largely-OA series.
  - Net: JURIX 2005–2025 is essentially fully acquirable open, no proxy needed.
- **DEON = sparse metadata.** 113/238 papers have **no ee link at all** in DBLP ("unavailable").
  Publisher split: early = College Publications, later = Springer LNCS/LNAI. Acquisition will
  need per-edition work (Springer LNCS TOCs for the DOI-bearing years; College Publications /
  author copies for the rest).

## Coverage gaps (LOGGED — do not read the core counts as "complete")

1. **JURIX 1988–2004 (~16 early editions) — not indexed anywhere clean.** DBLP `conf/jurix`
   starts 2005 (confirmed: `jurix year:1999` → 0 hits). jurix.nl's loose-PDF archive also
   starts at 2005 (`j05-`). Pre-2005 JURIX was book-published by assorted houses and is largely
   **undigitized**. *Priority: LOW* — early JURIX is less L4-relevant and the Bench-Capon "50"
   seed already carries the canonical early AI&Law. Revisit only if a specific citation demands.
2. **DEON pre-1996 + missing mid editions (1991, 1994, 1998, 2000, 2002) — ~5 editions, ~90 papers.**
   Not in DBLP `conf/deon`. Early DEON = College Publications workshop volumes. *Priority: MED-LOW.*
   Fill via the DEON community proceedings list / individual TOCs if the deontic-logic thread
   (Bounded Deontics facet) needs them.
3. **MULL → early *Jurimetrics* (1959–1966) — historical sub-corpus, JSTOR-gated.** Requires the
   authenticated browser session (JSTOR via NLB proxy), not an open API. *Deferred to a dedicated
   browser sub-run* (same pipeline as last session's Allen-corpus pulls; needs the user to
   authorize the JSTOR tab). Signpost: `stable/29760800` = MULL 1(1) front matter.

## What Phase 0 does NOT yet have (→ Phase 1)

- Abstracts / TLDRs (Semantic Scholar + OpenAlex).
- True OA PDF links per paper (OpenAlex `openAccessPdf`, Unpaywall by DOI).
- Citation edges for the free pre-rank (Phase 2).

## Reproduce

```
zsh    research/corpus-survey/scripts/harvest_dblp.sh   # paginate DBLP -> data/raw/*.json
python3 research/corpus-survey/scripts/build_index.py   # data/raw/* -> index.{json,csv}+summary.json
```
(Both scripts are version-controlled under `scripts/`.)
