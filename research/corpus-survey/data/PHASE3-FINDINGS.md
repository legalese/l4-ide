# Phase 3 — Abstract-filter findings (Sonnet judge fan-out)

**Run date:** 2026-07-20 · **Judges:** 16× Sonnet, ~110 papers each, over the full 1,758-paper
corpus in pre-rank order. Judge input **excluded** pre-rank signals (independent second signal).
**Outputs:** `data/phase3-verdicts.json` (all 1,758), `data/shortlist.json` (keep-set),
`data/shortlist-core.csv` (tight core), `data/deon-provisional.json`, `data/PHASE3-SHORTLIST.md`
(facet buckets). Rubric: `scripts/phase3-rubric.md`; merge `scripts/merge_phase3.py`.

## Verdict distribution (1,758 judged)

| relevance | n |
|-----------|--:|
| core | 479 |
| adjacent | 238 |
| peripheral | 255 |
| off-topic | 770 |
| unknown | 16 |
| **keep (core+adjacent)** | **717** |

By venue kept: ICAIL 278/840, JURIX 214/680, **DEON 225/238**.

## The trustworthy set is smaller than 717

DEON's 225 keeps are almost all **title-only** (223 have no abstract, 206 confidence=low) — the
Phase-1 DEON abstract hole surfacing exactly as predicted. They're real deontic-logic papers, but
the judge kept them on titles alone, so they're **provisional**. Applying a trust filter
(**core + confidence ≥ med + has abstract**) gives the working set:

- **Tight core = 250 papers** — ICAIL 134, JURIX 114, DEON **2**.
- Facets (multi-tag): intro 130, bounded-deontics 105, determinacy-frontier 54, fm-in-law 43, **cnl 19**.
- `deon-provisional.json` = 223 DEON title-only keeps, parked until abstracts are acquired.

**CNL is the thinnest facet (19).** That's the Wyner co-authored paper's facet — so the venue
corpus under-supplies it and we should lean on **Wyner's own oeuvre** (W0) + a targeted CNL/ACE/
LegalRuleML sweep to build that related-work, rather than the venue sweep alone.

## The two-signal cross-check paid off (main methodological result)

Because the judge never saw the pre-rank, the two signals disagree in informative ways:

- **Pre-rank false-positives: 78 of the pre-rank top-150 were CUT by the judge.** These are the
  Bench-Capon/Atkinson **CBR / factors / argumentation-schemes** papers — cluster-authored and
  heavily intra-corpus-cited (so the graph floated them), but *peripheral* to L4's exec/deontic/
  CNL/FM facets. Citation-proximity alone would have front-loaded the wrong 150.
- **Pre-rank misses: 261 judge-core papers sat below rank 600.** Two clusters: (a) **DEON
  no-abstract** papers (thin graph+lexical signal) and (b) **recent 2025 JURIX/ICAIL** papers
  (few citations yet) — e.g. Hohfeldian KB for LLMs, criminal-offence identification, a
  conveyances formal system, REALM. The judge rescued them from the tail.
- **Seed retention = 102/223 (45%)** — and this is a *feature*, not a recall failure: the judge
  correctly rejected 55% of cluster-authored papers as off-topic to L4. Cluster membership ≠ L4
  relevance. (A true recall check needs a gold set; the seed number just shows the judge
  discriminates rather than rubber-stamping the cluster.)

Net: neither signal alone is adequate — the graph pre-rank orders and rescues, the LLM judge
discriminates. Keep both columns in the shortlist so Phase 4/5 can see where they diverge.

## Caveats logged

- **DEON is provisional** (see above) — do not treat the 225 as a settled result.
- **`unknown` = 16** — no abstract + generic title; parked, not judged either way.
- Judge calls are single-pass, single-model. High-value borderline cases (esp. the 78 cut
  pre-rank favourites and the CNL facet) deserve a second look in Phase 5 deep-read.

## UPDATE — DEON abstract backfill DONE (2026-07-21)

Recovered **122/122** missing DEON abstracts from **SpringerLink** chapter landing pages
(`dc.description` meta — free metadata; only the PDF is paywalled; Crossref/OpenAlex/S2 had none).
Merged into `enriched.json` (DEON abstracts 3 → 125) and **re-judged the 122 on real abstracts**
(2 Sonnet judges; verdicts overlay the original title-only ones via `merge_phase3.py`).

Effect:
- **Tight-core 250 → 327** (DEON **2 → 79**; ICAIL/JURIX unchanged at 134/114).
- **bounded-deontics** tight-core facet 105 → **180**; fm-in-law 43 → 54.
- Keep-set 717 → 713: the re-judge **cut ~11** DEON papers titles had falsely kept — deontic logic
  applied to security/access-control, pure modal axiomatics/completeness, and non-legal domains.
- Still-provisional DEON: **142** (the no-DOI early-edition / workshop papers SpringerLink can't
  reach by DOI). Lower priority; parked in `deon-provisional.json`.

DEON is now trustworthy where it has DOIs. Script: `scripts/deon_abstracts.py` +
`scripts/update_and_prep_deon.py`.

## Next

- **Phase 4 — acquire the tight core (327)** open-first: ~40% ICAIL / ~60% JURIX already carry an
  OA url in `enriched.json`; paywalled residue sparingly (§5).
- **CNL widening**: CNL is still the thinnest facet (19) — fold Wyner W0 + a LegalRuleML/ACE sweep
  into the CNL bucket rather than rely on the venue corpus alone.
