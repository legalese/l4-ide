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

## 3. Corpus scope & estimates (to be replaced with hard numbers in Phase 0)

| Venue | Cadence | Editions | ~Papers | Access reality |
|-------|---------|----------|---------|----------------|
| ICAIL | biennial 1987–2025 | ~20 | ~900 | ACM DL — paywalled, **anti-bot** |
| JURIX | annual 1988–2025 | ~37 | ~1,000–1,200 | **Mostly open** (IOS Press FAIA / jurix.nl) |
| DEON  | biennial 1991– | ~16 | ~400 | Mixed (Springer LNCS + College Publications) |
| **MULL** → *Jurimetrics* | quarterly 1959–1966 (→ *Jurimetrics* after) | ~7 vols | ~100–200 (many short notes) | **On JSTOR** via proxy |

Rough total **~2,300–2,500 papers** for the three modern venues; **MULL** adds a small,
bounded **historical sub-corpus** on top. Phase 0 replaces all estimates with exact counts +
open-access percentages.

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

- [ ] **Phase 0 — Index** (DBLP + OpenAlex TOC harvest → exact counts + OA %; + MULL/early-*Jurimetrics* run via JSTOR) — *next*
- [ ] **Phase 1 — Enrich** (abstracts / OA links / citations via S2 + OpenAlex)
- [ ] **Phase 2 — Cheap pre-rank** (citation-graph proximity to known cluster)
- [ ] **Phase 3 — Abstract filter** (Sonnet, facet-mapped + recall check vs the "50")
- [ ] **Phase 4 — Acquire survivors** (open-first; paywalled sparingly, with rights)
- [ ] **Phase 5 — Deep-read + synthesize** (annotated bibliography keyed to facets)
- [ ] **W0 — Wyner harvest**
- [ ] **W1 — Wyner interest map**
- [ ] **W2 — Wyner persona rehearsal** (guardrails §7)

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
- **2026-07-20** — Added **MULL → *Jurimetrics*** as a bounded historical sub-corpus (§3),
  after spotting JSTOR `stable/29760800` = MULL Vol. 1 No. 1 front matter (Sept 1959, the
  field's founding issue). Phase 0 to harvest its full run via the JSTOR proxy; feeds the
  genealogy / deep-roots thread. (The front-matter item itself is a TOC, not a reading —
  it was the signpost to the venue.)
