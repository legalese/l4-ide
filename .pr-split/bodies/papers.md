# docs(papers): the L4 papers series, case studies, and worked exhibits under `paper/`

**What this adds**

This PR lands the whole academic-writing side of L4 in one place: a new top-level `paper/`
directory holding seven paper facets, two worked case studies of real Jersey legislation, and one
fully reproducible exhibit. `main` has no `paper/` directory at all today — the repository carries
source code and specifications but no home for the writing that explains what the system is *for*,
so the drafts have been living on personal branches and in a separate `legalese/sandbox` repo.
After this, a reader can go from `paper/README.md` to any facet, read its draft or design note, and
in one case (`the-letter-and-the-spirit/`) run a single script that re-derives the paper's central
claim from Z3, Espresso and an L4 model. The diff is purely additive — 67 files, no deletions — and
none of it is code: no Haskell, no TypeScript, no build wiring changes.

**Why**

The papers are the artefact that makes the engineering legible to the people it is aimed at —
ICAIL, JURIX, ProLaLa, the Cambridge computational-legal-studies forum — and they were scattered
across personal branches and a separate `legalese/sandbox` repository, where they drifted out of
step with the system they describe and could not be reviewed alongside it. Consolidating them here
is also the first step of an eventual *Book of L4*: `paper/README.md` is explicitly written as the
assembly index for that book, and each facet directory is self-contained so it can be lifted into
a chapter. The Jersey case studies came with a second motive — they are after-action reports
written for an external reader (Matthew Waddington), and they had no durable home. The source
commits name no upstream issue.

## What's in it

**67 files, ~24.8k added lines, all under `paper/`.** By kind: 23 Markdown, 17 `.l4`, 9 LaTeX,
6 PDF, 3 Python, 2 shell, 2 BibTeX, 1 SVG, 1 PNG, 1 Makefile.

### The assembly index

- `paper/README.md` — the *Book of L4* index. A table of the seven facets, a "Planned —
  placeholder, not yet started" row for the self-reference facet (*Who May Change the Rules*,
  spanning the SAFE / corporate-resolutions / Gödel arcs) with a written-in discipline note saying
  why it has no directory yet, the case-study pointer, and links out to the concept notes in
  `doc/concepts/` that belong in the book.

### Facet 1 — the ICAIL introduction paper (`paper/icail/`)

The broad intro paper in English and Japanese: `l4-icail.tex` (~1.6k lines), `l4-icail-ja.tex`
(~1.2k lines), a shared 570-line `.bib`, rendered PDFs, and a `Makefile` whose `qpdf --linearize`
step is documented as required rather than cosmetic — the LaTeX build emits a duplicate
`/ToUnicode` key that poppler tolerates and GitHub's in-browser viewer, Acrobat and strict PDF.js
can refuse. This is the one facet with pre-existing history on `unstable`: five direct commits
from June 2026 built it at `paper/l4-icail.*` (CNL surface-syntax expansion, PDF linearisation,
proof actions + the event-sourced burden-of-proof factbase, and the A.9 pass naming
`RECORD`/`RECALL`/`COMMIT`/`ATTEST` as implemented) before it was moved into `icail/`.

### Facet 2 — *Deontics as Domination* (`paper/bounded-deontics/`)

The largest drafting effort here. `draft/` carries the assembled `bd-draft.tex` plus four section
files, a 747-line `.bib`, and `section-permission-and-explosion.tex`. `OUTLINE.md` records the
title reasoning (a `MUST` precondition *is* the graph dominator of any LTS leading to the goal);
`related-work.md` opens by conceding that the core reduction is not novel and naming Anderson
(1958) as the earliest form, then states what the defensible residue is. Eight research notes sit
under `notes/` — citation verification, the FCA verdict, illustrations, per-party ordering,
static-vs-runtime, the spec delta, the §6 prior-art verdict, and a reading of Kolt 2026 on
superintelligence and law — and `sources/` keeps one captured ChatGPT transcript with its
provenance header, its known transcription gap stated in the header rather than papered over.

Two later increments are folded in:

- **Hohfeld as §7.** `section-powers-as-higher-order-deontics.tex` (196 lines) plus
  `hohfeld-higher-order/DESIGN.md`. The design note records why this stopped being a standalone
  paper: a verified prior-art pass found the higher-order reading is the received view (Fitch
  1967, Makinson 1986, Markovich 2020), formalised four ways (Kanger–Lindahl; Lindahl's
  *Spielraum*; Jones & Sergot counts-as; Gelati/Governatori/Rotolo/Sartor potestative), already
  executable (eFLINT), and already published on the square-of-opposition angle (Lima et al. 2021).
  The residue claimed is typed + functional + compiled-to-LTL + model-checked. Shared prior art
  was then de-duplicated into a new §2 background subsection and §7 slimmed from six subsections
  to four, with `fitch1967` and `dongroy2021` verified against sources. A footnote honours
  Shannon's logic↔switching-circuits unification (conductor/resistor/insulator =
  liability/contest/immunity; estoppel = diode).
- **The MAY dual and state explosion.** A new `sec:explosion` subsection wired into the necessity
  section, answering two review questions: the `MAY` of a dominator `MUST` is the existential
  companion — an edge on *some* accepting run, the Anderson/Meyer `◇(A∧¬V)` specialised to a goal
  automaton, with **no novelty claimed for the duality** — and how three strata of prior art meet
  state-space explosion (classical deontic logic never enumerates a model; normative-MAS checkers
  use generic OBDD/POR/BMC; AI-planning landmarks dodge the state-space product via
  delete-relaxation). It also *corrects* an over-sharpened earlier characterisation: van der
  Meyden's DLP classifies **executions**, not states, is about **free-choice permission** rather
  than goal-indexed reachability, and is EXPTIME-complete.

### Facets 3, 4, 6 — design notes

`cls-determinacy-frontier/DESIGN.md` (extract the computational skeleton of a judgment, deploy it
over an appellate corpus, map the determinacy frontier — detect ≠ resolve),
`cnl-affordances/DESIGN.md` (L4's surface syntax as HCI affordances; co-author named), and
`political-economy/DESIGN.md` ("Seeing Like a Citizen" — legal legibility as civic infrastructure,
grown out of the lived experience of prising *Re Best* and *Royal Trust* out of paywalled and
anti-scraped databases while verifying AND-ambiguity citations). Each states its own status,
target venue and draft date in its header.

### Facet 5 — formal methods in law, plus one reproducible exhibit

`FORMAL-PAPER.md` is the "white-hat Bad Man" working paper: each recurring legal pathology is a
known software bug class with a matching verification technique (comma/scope → parse ambiguity;
the PDPA breach-notice study → race condition; *Poh Yuan Nie* → logic minimisation), unified by
reading Holmes's Bad Man as a threat model and a loophole as a counterexample.

`the-letter-and-the-spirit/` is its worked exhibit and the only executable thing in this PR:
the essay, a `REPRODUCE.md` manifest, `reproduce.sh` running four checks that SKIP cleanly when a
tool is absent, `cheating-415-surplusage.z3.py` (Z3 proof that concealment is a don't-care across
the no-property region — surplusage as a theorem), `cheating-415-espresso.py` (the minimiser that
deletes the dead literal, cross-checked against Quine–McCluskey), a relay-ladder rendering in
`.py`/`.svg`/`.png`, and a bundled copy of the L4 model so the directory reproduces standalone.

### Case studies — two Jersey instruments (`paper/case-studies/`)

- **Covid-19 (Gathering Control) (Jersey) Order 2020** — R&O.166/2020 encoded across three
  temporal snapshots (`GCO-first-version.l4`, `GCO-as-at-20210115.l4`, `GCO-as-repealed.l4`, plus
  `MHO-as-at-20210115.l4`), with a 490-line after-action report and two PDFs. A later commit
  repairs a modelling defect found by re-reading: `takes place outdoors` had been *derived* as
  `NOT takes place indoors` in all three files, which is a reading and not a definition — vows on
  the lawn and a reception in the restaurant is one gathering that took place both ways. Because
  Article 3's outdoor (>20) and indoor (>10) caps read the same head count, exactly one could ever
  fire, so a 15-person mixed gathering breached or cleared purely on which box was ticked. The
  complement is replaced by a stated field in 24 fixtures, the dead `VenueKind` type is removed,
  a `mixed-venue party of 15` record is added, and what is *not* fixed (one head count still
  cannot apply two caps to two phases of one gathering) is stated at the declaration.
- **Charities (Jersey) Law 2014** — a part-by-part whole-statute encoding: twelve `.l4` files
  (a shared `charities-common.l4` plus one per Part) covering interpretation, the Commissioner,
  the charity test, the register and applications, effects and deregistration, governors, use of
  terms, information, appeals, final provisions and the schedules; an 824-line README and two
  PDFs. The two largest parts are ~2.1k and ~1.8k lines of L4 apiece.

## Evidence

Quoted faithfully from the source PRs:

- **PR #132** — "Assembled draft (`bd-draft.tex`) **compiles clean: 0 LaTeX errors, 0 undefined
  references, 16 pp**."
- **PR #171** — "Full draft builds clean: **17pp, 0 errors, 0 undefined refs**." Three citations
  verified and marked `status=verified` in the bib: van der Meyden 1996, *The Dynamic Logic of
  Permission*, JLC 6(3):465–479; van der Meyden 2005, *Reduction from DLP to PDL*, JLC
  15(5):767–782; van der Meyden & Maher 2025, *SAFE: Smart Contracts for Venture Finance*
  (Springer). Identity confirmed as one Ron van der Meyden (UNSW) spanning both.
- **PR #129** — reported that the branch was rebuilt fresh off `unstable` so that "~2.3k lines of
  unrelated code churn" from three older paper branches did **not** ride along; the merged PR was
  paper-only.
- **PR #132** on the Hohfeld restructure — `fitch1967` and `dongroy2021` verified (Fitch's
  "capacitative modalities"; Dong & Roy free preprint arXiv:2110.04454 added), all citations
  preserved across the de-duplication.
- No test-suite numbers are claimed here, because nothing in this PR is executed by CI. The GCO
  repair and the two prettier-format commits rode inside larger PRs (#224, #172, #134) whose
  measurements are about their code, not about `paper/`, and are left with the themes that own
  that code.

## Independence

**Genuinely standalone.** Every path in this PR is under `paper/`, and nothing in the build, test
or CI configuration reads that directory:

- The golden suite's roots are `jl4/examples/{ok,legal,not-ok}` and `jl4-core/libraries` — the
  list is pinned in `etc/check-corpus-goldens.mjs` and mirrors `jl4/tests/Main.hs`. The 17 `.l4`
  files here sit outside all of them, so **this PR ships no goldens and cannot turn the golden
  suite red**.
- `paper/**` matches none of the `pr-checks.yml` paths filters (haskell / typescript / docs / mlir
  / dmn / bpmn / go), so the heavy jobs skip on a paper-only PR. This cuts both ways and is worth
  a reviewer's attention: `prettier --check .` lives in the typescript job, `.prettierignore` does
  **not** exclude `paper/`, and the Markdown here therefore merges ungated and surfaces on the
  next PR that touches a `.ts` file. That happened three times on `unstable`, and the three
  repair commits are folded in, so the tree as submitted is prettier-`3.4.2`-clean.
- The one cross-theme thread is cosmetic, not functional. `the-letter-and-the-spirit/README.md`
  says a canonical copy of `cheating-415-poh-yuan-nie.l4` also lives in the corpus (it writes the
  path as `jl4/ok/inert/`; the file is actually at `jl4/examples/ok/inert/`), and that corpus copy
  lands with the **ladder-viz** theme. The bundled copy is what `reproduce.sh` actually resolves —
  `./cheating-415-poh-yuan-nie.l4`, its first lookup path — so the exhibit reproduces whether or
  not ladder-viz lands. If ladder-viz is dropped, only that prose pointer goes stale.
- `paper/README.md` links to `specs/todo/{yc-safe,corporate-resolutions,godel-loophole}/SPEC-NOTES.md`
  and to `doc/concepts/language-design/logic-not-flowcharts.md`. Those live in the **specs** and
  **docs** themes. If either is dropped, this PR has dead relative links — it does not fail to
  build, and `doc/test-docs.sh` does not walk `paper/`.
- It needs nothing from `lang-*`, `dmn-export`, `service-cli` or any other code theme. The `.l4`
  files are read as prose exhibits, not compiled by anything in CI.

One honest wart, pre-existing on `unstable` and carried through unchanged:
`paper/icail/l4-icail-ja.pdf` is checked in **at zero bytes** — the Japanese build output was
emptied by the June A.9 commit and never regenerated. `make ja` in `paper/icail/Makefile`
rebuilds it (lualatex + bibtex + qpdf). The English PDF is intact.

## Risk if rejected

The system loses its explanation: seven paper facets, two whole-statute Jersey encodings and the
one end-to-end reproducible exhibit that demonstrates the formal-methods claim would stay on
personal branches and in `legalese/sandbox`, where they have already been observed to drift out of
step with the code. Nothing in the build breaks — no sibling PR imports, compiles or tests
anything under `paper/` — so the cost is entirely in lost writing and lost provenance, not in red
CI.

## This PR is prose only — its subject matter ships elsewhere

Everything here is under `paper/` — 67 files, the papers and worked exhibits. **This PR contains no code**, and no code PR
contains any of these files: `partition.mjs` matches the prose paths before any feature rule, so the
separation is total rather than incidental.

The features described here ship in #257 (language core) and the corpus PRs.

**The risk, stated plainly.** If this PR is approved and those are not, `main` acquires
documentation for behaviour it does not have. If those are approved and this is not, shipped
features go undocumented — and for `specs/`, a ruling that has been *decided* has nowhere to be
*recorded*, which is exactly the failure this repo's `CLAUDE.md` §4 was written against: *"A
decision is recorded in its owning document in the same PR, or it is not decided."*

So this PR should be approved **as part of a set, and landed after** the PRs above — not on its own
merits alone. If any of them is rejected, this one needs re-cutting to drop the corresponding pages
before it merges.

## Provenance

Unstable PRs folded into this one:

- **#129** — `docs(papers): consolidate the L4 papers series under paper/` (`docs/l4-papers-series`)
- **#132** — `docs(papers): Hohfeld higher-order section + Book-of-L4 index` (`mengwong/l4-papers`)
- **#134** — `Library resolution: embedded stdlib outranks ambient XDG/bundle copies (B′)…`
  (`docs/library-resolution-shadow`) — **paper-relevant part only**: one prettier-format commit
  over `paper/README.md` and the Hohfeld design note. The library-resolution substance belongs to
  the `lang-imports-stdlib` and `docs` themes.
- **#171** — `paper(bounded-deontics): MAY-dual + state-explosion related work (van der Meyden)`
  (`docs/bd-vdmeyden-relwork`)
- **#172** — `feat(regcf): the rule-version axis…` (`mengwong/regcf-rule-version`) —
  **paper-relevant part only**: one prettier-format commit over
  `bounded-deontics/notes/citation-verification.md`. The Reg CF substance belongs to
  `corpus-regcf`.
- **#224** — `The explainer stage, a BPMN renderer, the grouping tutorial, and the de novo Reg CF
  run` (`mengwong/go-explainer`) — **paper-relevant part only**: the GCO outdoors/indoors
  partition repair across the three Jersey Gathering Control snapshots. Its
  `specs/roadmap/future-features.md` companion entry belongs to the `specs` theme.

Also folded in, and predating all six PRs: five direct commits to `unstable` in June 2026 that
built the ICAIL paper before it was moved under `paper/icail/` (`2b5b71f2`, `39453e37`, `57504e74`,
`d02a7db8`, `70bfac34`), and two `paper/README.md` commits from 2026-07-27 (`ac48553a`, `a9d9d2f6`)
that added the self-reference placeholder row and dropped a since-obsolete branch caveat.
