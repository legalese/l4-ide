# Legal-AI Corpus Survey — Project Tracker

**Worktree:** `l4wt/corpus-survey` · **Branch:** `research/corpus-survey` · **Started:** 2026-07-20

A systematic survey of the **ICAIL**, **JURIX**, and **DEON** literature (plus a deep
single-author **Adam Wyner dossier**) to produce an L4-relevant, facet-mapped annotated
bibliography that feeds the L4 paper series.

> This file is the durable tracker across phases. Update the **Phase Status** checkboxes
> and append to the **Decision / Run Log** as we go. It is written to survive context
> compaction — anyone (human or agent) should be able to resume from here.

---

## 1. Goal & deliverables

1. **Complete metadata index** of every ICAIL, JURIX, DEON paper across all years.
2. **Relevance-filtered, facet-mapped shortlist** — each survivor tagged to which L4 paper
   facet it bears on and *how* (prior-art / supports / contrasts / method-to-borrow).
3. **Full-text acquisition** of the shortlist (open-first; paywalled only where we have
   rights, one-at-a-time — see ToS guardrails §5).
4. **Deep-read extractions** → an annotated bibliography keyed to the L4 facets (§6).
5. **Wyner collaborator dossier** — interest map over time + a *clearly-synthetic* persona
   rehearsal tool for previewing the co-authored CNL paper (guardrails §7).

## 2. Core insight driving the architecture

**The reading is the cheap part; acquisition is the constraint.** Filtering ~2,500
abstracts on Sonnet is ~5M tokens (hours). Deep-reading the survivors (~200–400 papers) is
another ~4–5M tokens. Neither stresses a Max20/Sonnet week. What breaks is brute-force PDF
download — ACM/Springer anti-bot + proxy-ToS. So: **harvest metadata first (free APIs),
filter on abstracts, acquire only survivors.** Do NOT download-then-read.

## 3. Corpus scope — Phase 0 actuals (DBLP core, harvested 2026-07-20)

| Venue | Cadence | Editions indexed | Papers (excl. eds.) | DBLP-open % | Access reality |
|-------|---------|-----------------:|--------------------:|------------:|----------------|
| ICAIL | biennial 1987–2025 | 20 | **840** | 1.7% | ACM DL — paywalled, **anti-bot**; every paper has a DOI → OA-copy lookup in P1 |
| JURIX | annual 2005–2025 | 21 | **680** | 20.3% | **Most open in practice** — jurix.nl loose PDFs (early yrs) + IOS Press FAIA (largely OA) |
| DEON  | biennial 1996–2025 | 12 (of ~17) | **238** | 0.0% | Sparse DBLP meta (113 no-ee); Springer LNCS (late) + College Publications (early) |
| **Total (modern core)** | | **53** | **1,758** | | |
| **MULL** → *Jurimetrics* | quarterly 1959–1966 | *deferred* | ~100–200 (est.) | — | **On JSTOR** via proxy — needs authenticated browser sub-run |

Full flat table in `data/index.csv`; per-edition counts + machine summary in `data/summary.json`;
narrative in `data/PHASE0-FINDINGS.md`.

**Coverage gaps logged (Phase 0):**
- **JURIX 1988–2004 (~16 editions)** — absent from DBLP *and* jurix.nl's PDF archive; largely
  undigitized. *Priority LOW* (Bench-Capon "50" seed covers the canonical early AI&Law).
- **DEON 1991/1994/1998/2000/2002 (~5 editions, ~90 papers)** — not in DBLP `conf/deon`;
  College Publications era. *Priority MED-LOW* — fill if the Bounded-Deontics thread needs them.
- **MULL/early-Jurimetrics** — JSTOR-gated; deferred to a browser sub-run (signpost `stable/29760800`).

**MULL — historical roots (added 2026-07-20).** *Modern Uses of Logic in Law* is the first
journal dedicated to computational law (inaugural issue Vol. 1 No. 1, Sept 1959; JSTOR
`stable/29760800` is its front matter / TOC). Layman Allen and the late-'50s cohort worked out
"law as logic" in its pages, and it **became *Jurimetrics*** (the ABA journal) in 1966 — a
continuous, JSTOR-hosted lineage. Maximally relevant to the **genealogy / deep-roots** thread
(ICAIL intro; complements the Mehl 1958 + Allen 1957 material already collected). Phase 0
harvests the full MULL run (→ early *Jurimetrics*) as a bounded historical target.

## 4. Pipeline (metadata-first)

- **Phase 0 — Index.** Harvest full venue TOCs from **DBLP** + **OpenAlex** (open, no key):
  title, authors, year, DOI, venue. Output: `data/index.{json,csv}`. Deliverable = exact
  counts + OA-availability % + how much is reachable *without* the proxy.
- **Phase 1 — Enrich.** For each paper, pull **abstract, TLDR, `openAccessPdf`, citations**
  from **Semantic Scholar Academic Graph API** + OpenAlex. No PDFs yet.
- **Phase 2 — Cheap pre-rank (no LLM).** Use the **citation graph** as a free relevance
  signal: papers citing/cited-by the known cluster (Governatori, Prakken, Sartor,
  Bench-Capon, Wyner, Gordon; defeasible / deontic / CNL / rules-as-code) float up.
- **Phase 3 — Abstract filter (Sonnet).** Judge over abstracts scoring **relevance to which
  L4 facet** (§6) and the **relation** (prior-art / supports / contrasts / method). Output a
  ranked, facet-bucketed shortlist. Recall check: does it rediscover the Bench-Capon "50"?
- **Phase 4 — Acquire survivors only (~200–400).** Open PDFs via S2/OpenAlex/arXiv/JURIX
  first; paywalled residue fetched sparingly, with rights, one at a time (§5).
- **Phase 5 — Deep-read + synthesize.** Structured per-paper extraction → annotated
  bibliography keyed to facets; feeds each target paper's related-work.

## 5. Acquisition / ToS guardrails (non-negotiable)

- **Open-first.** OpenAlex / Semantic Scholar / arXiv / JURIX (IOS Press FAIA is largely OA).
- **No bulk proxy scraping.** Systematic/bulk download through the NLB proxy violates
  publisher agreements and risks flagging the *institution's* access. Paywalled items are
  fetched **only where we have the right, sparingly, one at a time** — never a fleet.
- **Respect anti-bot.** ACM/Springer throttle; do not hammer. If a venue is only reachable
  via a wall, prefer the OA author copy (institutional repositories, author homepages).
- **Log every cap.** If a phase bounds coverage (top-N, sampling, no-retry), say so — silent
  truncation reads as "covered everything" when it didn't.

## 6. Relevance model — the L4 paper-series facets

Every filtered paper is tagged to one or more facets and a relation. Facets (from the
papers-series plan):

- **ICAIL (intro)** — introducing L4.
- **Bounded Deontics → JURIX** — derived necessity, the boundary, deontic-as-lattice.
- **Determinacy-frontier / detect≠resolve → Cambridge CLS** — empirical; incl. the
  avoidable-ambiguity-tax sub-analysis.
- **CNL syntactic affordances → CNL workshop** — HCI/linguistics; **co-author Adam Wyner**.
- **FM-in-law → ProLaLa** — the "white-hat Bad Man" ladder.
- **Poh Yuan Nie** — keystone worked example (overload-resolution + defeasible-coercion).

Relation vocabulary: `prior-art` · `supports` · `contrasts` · `method-to-borrow` · `example`.

## 7. Wyner sub-project (dossier + persona)

**Handles:** dblp `73/3639` · <https://azwyner.info/> · Google Scholar `SzgOFVgAAAAJ` (~3,950 cites).
Swansea Univ., Law + Computer Science. Threads: argumentation mining, legal KR, **controlled
natural language**, deontic logic, case-based reasoning, ontologies (LKIF), text analytics.

- **W0 — Harvest** his full oeuvre (dblp + OpenAlex + azwyner.info).
- **W1 — Interest map** over time; recurring co-authors; venues; the CNL/argumentation
  threads that intersect L4.
- **W2 — Persona rehearsal tool.** A *grounded* model of what Adam would likely care about /
  push back on, from his actual corpus — used to prep the co-authored paper.

**Guardrails (persona):** it stays **clearly synthetic**; generated text is **never**
attributed to or passed off as the real Adam; it's preparation for a paper written **with the
real him**, whose input validates anything the model produces. Loop him in early.

## 8. Feasibility / budget

- Target: ~**a week on Max20 / Sonnet**. Model tokens are *not* the binding constraint;
  acquisition throttling + weekly-cap pacing are. Keep abstract-filtering cheap; spend the
  budget on deep-reading survivors.
- Parallelism: embarrassingly parallel per-paper; run filter/read as fan-out workflows.

## 9. Seed assets already in hand (this session, 2026-07-20)

- **Bench-Capon et al. 2012 — "A History of AI and Law in 50 Papers: 25 Years of ICAIL"**
  (open-access, 93 pp). Use as (a) the pre-2012 ICAIL canon and (b) a **recall benchmark**
  for the Phase-3 filter (does it rediscover the 50?).
- **Allen corpus** (Allen & Saxon A-Hohfeld/MINT, Allen 1957 razor-edged lineage, the
  Summers/Allen exchange, Allen & Engholm query method) — historical + CNL/determinacy roots.
- Printed set staged/printed from `to-print/` — see the L4 project's print queue.

---

## Phase Status

- [x] **Phase 0 — Index** — DBLP core harvested: **1,817 records / 1,758 papers** (ICAIL 840,
  JURIX 680, DEON 238). Outputs in `data/` (`index.json`, `index.csv`, `summary.json`,
  `PHASE0-FINDINGS.md`); scripts in `scripts/`. **Gaps logged** (JURIX <2005, DEON early
  editions, MULL/JSTOR) — see below. *MULL/Jurimetrics deferred to a browser sub-run.*
- [x] **Phase 1 — Enrich** — `data/enriched.json` (all 1,758 papers). OpenAlex 1,505/1,515 +
  S2 1,476/1,515. Abstracts 76% / TLDRs 68% / OA-url 43%. **True OA ≫ DBLP flag** (ICAIL
  1.7%→39%, JURIX 20%→60%). **DEON abstract hole logged** (3/238 — Phase-3 risk). Details in
  `data/PHASE1-FINDINGS.md`; script `scripts/enrich.py`.
- [ ] **Phase 2 — Cheap pre-rank** (citation-graph proximity to known cluster) — *next*
- [ ] **Phase 3 — Abstract filter** (Sonnet, facet-mapped + recall check vs the "50")
- [ ] **Phase 4 — Acquire survivors** (open-first; paywalled sparingly, with rights)
- [ ] **Phase 5 — Deep-read + synthesize** (annotated bibliography keyed to facets)
- [x] **W0 — Wyner harvest** — `dossiers/wyner/{works.json,interest-map.json,dblp-73-3639.xml}`;
  154 works 1991–2025, 2,152 cites. Script `scripts/wyner_harvest.py`.
- [~] **W1 — Wyner interest map** — seed built (`interest-map.json`: venues/concepts/coauthors/
  most-cited). Narrative synthesis still to write.
- [ ] **W2 — Wyner persona rehearsal** (guardrails §7)
- [~] **MULL sub-corpus** — issue-level skeleton captured; **article-level harvest blocked** by
  JSTOR SPA + MCP read-redaction (`data/MULL-STATUS.md`). Deferred to on-demand acquisition.

## Open questions / decisions pending

- Wyner harvest timing: **now** vs **after** the venue-wide Phase 0. *(user leaning: TBD)*
- Semantic Scholar API key: request one for higher rate limits, or run keyless + OpenAlex?
- Output home for the annotated bibliography: keep here under `research/corpus-survey/`, or
  promote into the paper worktrees per facet?
- Filter tooling: single Sonnet judge vs. multi-lens panel per facet.

## Decision / Run Log

- **2026-07-20** — Tracker created in new worktree `l4wt/corpus-survey` (branch
  `research/corpus-survey`), off `unstable` @ dea9bc6c. Architecture locked as metadata-first
  (§2, §4). ToS guardrails locked (§5). Next action after user's context compaction:
  **start Phase 0** (harvest DBLP + OpenAlex TOCs for ICAIL/JURIX/DEON → `data/index.*`).
- **2026-07-20** — **Phase 1 COMPLETE + Wyner W0 COMPLETE.** Enriched all 1,758 papers via
  OpenAlex + Semantic Scholar → `data/enriched.json` (abstracts 76%, TLDRs 68%, OA-url 43%).
  Big finding: true OA far exceeds the DBLP flag (ICAIL 1.7%→39%, JURIX 20%→60%) — Phase-4
  acquisition is cheap. Risk logged: DEON abstracts 3/238 → Phase-3 filter near-blind on DEON
  (mitigations in `PHASE1-FINDINGS.md`). Wyner W0: 154 works (1991–2025, 2,152 cites); home
  venues LNCS/JURIX/AI&Law; threads argumentation-mining + LegalRuleML + CNL; cluster
  Bench-Capon(31)/Atkinson(21)/Sartor/Governatori. **MULL:** captured journal identity + issue
  skeleton (slug `moduseloglaw`, Vols 1–7 1959–66, → Jurimetrics) but article-level TOC blocked
  by JSTOR SPA + MCP read-redaction (read-side, not fixable by a user click); deferred to
  on-demand pulls (`data/MULL-STATUS.md`). Next: **Phase 2** citation-graph pre-rank.
- **2026-07-20** — **Phase 0 COMPLETE (modern core).** Harvested DBLP per-stream TOCs
  (`stream:streams/conf/<venue>:`, 100-hit/page → paginated). Result **1,817 records / 1,758
  papers**: ICAIL 840 (1987–2025), JURIX 680 (2005–2025), DEON 238 (1996–2025). Outputs:
  `data/index.{json,csv}`, `data/summary.json`, `data/PHASE0-FINDINGS.md`; scripts in `scripts/`.
  Key findings: (a) OpenAlex does **not** group these confs under one source (ICAIL source = 14
  works) → **DBLP is the authoritative index**, OpenAlex is enrichment-only. (b) DBLP-open flag
  = ICAIL 1.7% / JURIX 20.3% / DEON 0% — a *floor*; true OA higher (P1 refines). (c) Acquisition
  recon: ICAIL = hard ACM wall but all DOI'd; JURIX = open via jurix.nl/pdf (early) + IOS FAIA;
  DEON = sparse (113/238 no ee). Gaps LOGGED: JURIX <2005 (~16 eds, undigitized, LOW), DEON
  1991/94/98/00/02 (~5 eds, MED-LOW), MULL/JSTOR (deferred to browser sub-run).
- **2026-07-20** — Added **MULL → *Jurimetrics*** as a bounded historical sub-corpus (§3),
  after spotting JSTOR `stable/29760800` = MULL Vol. 1 No. 1 front matter (Sept 1959, the
  field's founding issue). Phase 0 to harvest its full run via the JSTOR proxy; feeds the
  genealogy / deep-roots thread. (The front-matter item itself is a TOC, not a reading —
  it was the signpost to the venue.)
