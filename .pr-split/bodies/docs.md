# docs: the language-design essays, the reviewer briefing, and reference pages for everything `unstable` added

**What this adds**

This is the prose half of the `unstable` divergence: 91 files under `doc/` plus `jl4/GRAMMAR.md` —
52 markdown pages, 7 `.l4` worked examples, 10 SVGs, 21 diagram source files, a BibTeX file and a
test-case JSON; 53 of the 92 are new. After this lands the repository can answer, in its own tree,
four questions it currently cannot: *why is L4 a language rather than a flowchart builder* (a
1,124-line language-design essay with a runnable companion `.l4`), *what does a domain expert
actually do when they review an encoding* (the HG1 reviewer briefing, 364 lines, with three
committed SVG figures), *how do I write the features that landed on `unstable`* (reference pages
for sets, `TYPICALLY`, the `•` bullet syntax, `YMD`, the regulative deontics, library resolution,
negation-as-failure and ROBDD query planning), and *what does a comma cost* (a grouping-and-precedence
tutorial built on three real appellate disputes, with seven generated ladder figures).

**Why**

Two gaps drove it. First, features were shipping without a place a non-author could learn them.
`SET OF`, `TYPICALLY`, `@infixl`, `•` bullets, `YMD`, `RULES EFFECTIVE DATE` and the reworked
library-resolution order all arrived on `unstable` with their reference prose written in the same
PR, and that prose has nowhere to live on `main`. Second, the two documents most likely to be read
by someone outside the project — the design rationale and the reviewer briefing — did not exist as
tracked files. PR #219 states the motivation for the latter plainly: the HG1 seat "is the part of
this system we most want outside expertise in", and "the document describing that seat existed only
as standalone HTML, which meant nobody could open a PR against it." PR #134's docs page exists for
a narrower reason it names: a silent library-shadow class that cost "two lost debugging sessions".

---

## What's in it

### The language-design essays — `doc/concepts/`, 15 files

- **`language-design/logic-not-flowcharts.md`** (1,124 lines) with
  **`logic-not-flowcharts-example.l4`** (58 lines) — the central argument, built across four PRs.
  The thesis: a flowchart commits a category error for regulatory logic, drawing a *timeless
  material conditional* as a *sequential process*, which says more than the law (an invented
  evaluation order) and less (the lost AND/OR shape). Worked throughout on GPDO 2015 Class A A.3,
  the obscure-glazed window rule from the 2021 "write this legislation as a flowchart a 9-year-old
  can understand" challenge. Sections that accreted later on the branch: the flowchart vendors'
  own concessions, a rewritten decision-tables section (its commit message: "three of our four
  criticisms were false"), the Lexipedia Reg CF (2026) BPMN case study (#135), and the Rulemapping
  (von Cossel 2026) section (#222) — deliberately the *strongest* rival, because it gets the
  picture right and keeps it as the source.
- **`language-design/dmn-analysis-prior-art.md`** (262 lines, #166) — a survey of who actually
  detects gaps and overlaps in DMN, declaring itself the canonical copy so a future correction has
  one place to land. It also **retracts** a claim made earlier in `logic-not-flowcharts.md` (that
  the Calvanese hyper-rectangle algorithm is what runs inside Drools and Trisotech), in place with
  strikethrough rather than by silent deletion. Sources read directly are listed separately from
  sources verified only by metadata, and four specific claims are marked unverified.
- **`language-design/related-work.md`** (213) and +33 lines to **`linguistic-syntax.md`**.
- **`legal-modeling/`** — `actors-and-actions.md` (380), `ACTOR-ACTIONS-THEORY.md` (204) and a
  292-line BibTeX bibliography `actor-actions.bib`, plus a small `regulative-rules.md` fix.
- **`reviewing/reviewing-encoded-law.md`** (364, #219) with three committed SVGs — the Rule 501(a)
  OR-ladder (regenerated tool output), a schematic decision requirements graph, and the resale
  restriction as emitted BPMN, each extracted with its palette inlined so it renders standalone in
  light and dark. Fifteen sections: the HG1 seat and what a detached signature over a content
  digest claims; inert style; the pipeline stage by stage; the two reviewer jobs (choosing
  interpretations where the law under-determines, checking isomorphism); a translation table for
  reviewers arriving from OPA/OIA; ladders, DMN, BPMN, interviews and MCP as projections; the
  conversion report; and how to issue a `go` yourself.
- Index entries in `concepts/README.md` and `concepts/SUMMARY.md`, including a new **Reviewing**
  heading.

### The reference — `doc/reference/`, 28 files

New pages:

- **`libraries/sets.md`** (84) and **`libraries/sets-example.l4`** (57) — the `SET OF a` vocabulary
  from #122, kept current across three later reversals: the variadic-`SET OF` caveats removed and
  the **singleton boundary** documented once it was found (#127 — `SET OF x` with one argument
  reads `x` as the contents *list*, so `SET OF "carol"` is a type error and singletons stay
  `setFromList (LIST "carol")`); the `AND`/`OR` set overloads removed and the example rewritten to
  `UNION` (#168); and the reinstatement question repointed at #169 as semantic rather than
  performance (#170).
- **`libraries/resolution.md`** (249, #134) — the resolution order with per-tier rationale, a
  dev/prod playbook (stdlib consumers do nothing; stdlib developers pin `JL4_LIBRARY_PATH` at the
  worktree, never symlink farms), how to read the resolver output, the Template Haskell
  embed-staleness mechanics, and the incident history. `errors/README.md` is corrected in the same
  change, where it carried the stale ordering.
- **`libraries/negation-as-failure.md`** (65), **`types/TYPICALLY.md`** (90) with
  **`typically-example.l4`** (21), and **`query-planning/README.md`** (117) +
  **`query-planning/robdd.md`** (100).

Modified: `syntax/README.md` (+81 — the `•` bullet syntax from #109), `cheat-sheet.md`,
`builtins/README.md` (+38 — EVAL clause signatures corrected and the deep pin stated, from #211),
the six `regulative/` pages (`DEONTIC`, `MAY`, `MUST`, `PARTY`, `SHANT`, `README`),
`patterns/common-patterns.md`, `patterns/README.md`, `types/type-theory.md`,
`functions/yield-example.l4`, `libraries/README.md`, `libraries/daydate.md` (`YMD`),
`libraries/prelude.md`, `GLOSSARY.md`, `README.md`, `SUMMARY.md`.

### The tutorials — `doc/tutorials/`, 40 files

- **`getting-started/grouping-and-precedence.md`** (329) + **`.l4`** (102) + **28 figure files**
  (seven figures × `.mmd` / `.sentences` / `.svg` / `.txt`), from #224. Answers the question a
  formal language must settle before it can mean anything — given `a OR b AND c`, what binds
  tighter — with **layout**, not a precedence table, and shows why layout is the right mechanism:
  it cannot be omitted, so the encoding cannot stay silent on a question the source was silent on.
  Three real disputes, each a different failure with a different repair: *Chew* (bracketing, where
  the compiler's same-column `AND`/`OR` warning fires twice and the repair is to commit to a
  shape), *Oakhurst* (tokenization — a missing serial comma, one leaf against two, and the rule
  that generalises: never put a disjunction inside a field name), and *Rogers* (attachment — where
  a second authoritative French text resolved it, which is the argument for the whole approach,
  made from the bench rather than from a manifesto). Every snippet lives in the sibling `.l4` with
  `#EVAL` directives so the page cannot drift, and the figures are generated from that file through
  the LSP rather than drawn.
- **`multi-temporal-modeling/multi-temporal-rule-modeling.md`** (321) +
  **`gst-rate-change-example.l4`** (127) — the tutorial for the rule-version temporal axis made
  load-bearing in #89 (`RULES EFFECTIVE DATE`), including the fallback chain and its floor.
- **`set-operators/sets-and-the-two-ands.md`** (143) — including the "Sets in one minute" primer
  for the non-mathematician, and the Poh Yuan Nie segue that reframes the otiosity canon as a
  Boolean-minimization presumption: courts presume statutory text is already minimized, so an
  otiose-term reading is evidence of the wrong reading.
- **`natural-language-functions/optimising-natural-language-generation.md`** (93),
  **`deploying-rules/insurance-premium.cases.json`** (48), plus edits to
  `getting-started/encoding-legislation.md` (+63 — the recitals-as-inert-outline workflow from
  #109), `getting-started/wedding-vows.md`, `llm-integration/legislative-ingestion.md`, and the two
  index files.

### The courses, and the grammar

Eight files under `doc/courses/` — `foundation/module-1-first-rule`, `module-6-regulative` (+78),
`module-7-capstone`, and `advanced/module-a1` through `module-a4` including
`module-a2-cross-cutting-examples.l4`. Mostly deontic/performer-rule refreshes plus the
English-article agreement pass of #104 (`GIVETH A DEONTIC`; `IS AN Actor / Action / Item` before
vowel-initial type names), which is prose-only with no behaviour change. `jl4/GRAMMAR.md` gains six
lines for the `•` bullet production.

---

## Evidence

Quoted from the source PRs, not recomputed here:

- **#134** (whose docs page is `libraries/resolution.md`): "`doc/test-docs.sh` fully green (858
  links, 81 L4 files, 0 orphans)."
- **#127** (sets docs follow-up): "Doc example re-validated against merged unstable: **13/13
  `#EVAL`s green.**"
- **#166**: "`prettier@3.4.2 --check` clean on all four files. Docs-only; no code paths touched."
- **#219**: "`prettier@3.4.2 --check` clean on all three touched/added markdown files"; "all links
  resolve (absolute URLs, plus the three sibling SVGs)"; "`xmllint --noout` clean on all three
  SVGs; no non-XML named entities"; "docs only — no code, no build, no workflow touched."
- **#170**: "Markdown-only; prettier@3.4.2 clean."
- **#222**: "Docs only; no code paths touched." Its Rulemapping section reports von Cossel's own
  § 130(1) StGB experiment over 868 posts — Rulemapping precision 0.80–0.86 and recall 0.82–0.89,
  against long-context CoT 0.34–0.49 / 0.69–1.00 and zero-context 0.28–0.37 / 0.89–1.00 — and the
  PR is explicit that "this is the first measured support for this page's thesis, and it is **not
  ours**."
- **#189** (the `main` → `unstable` merge that reconciled the two doc trees): "**No regeneration
  was needed.** `jl4-test` passed 2129/2129 on the first run after the build went green."

The golden-suite figures reported by the feature PRs these pages ride along with (#89, #109, #116,
#122, #128, #168, #172, #174, #190, #211, #224) are measurements of *code that lands in sibling
themes*, not of this documentation, and are deliberately not restated here as evidence for this PR.

**One caution carried over verbatim from #219**, because it is the most likely defect in this PR:
`reviewing-encoded-law.md` "is dense with measurements — test counts, engine-agreement figures,
build times, dates. Each was true when its sentence was written, and **nothing re-checks them on
read**." That page opens by asking that a drifted number be fixed in the same PR as the work that
revealed it. Since this lands the page against `main` rather than the `unstable` tree those figures
were measured on, **every number inside it should be re-checked against whatever actually ships**,
and the same applies to the counts in `dmn-analysis-prior-art.md`.

## Independence

Not standalone. This one has a measurable CI dependency, and it is worth stating precisely rather
than hedging.

**`doc/**` is a paths filter on `main` today.** In `origin/main`'s `.github/workflows/pr-checks.yml`
the `docs` filter is `doc/**`, and the `haskell` job runs when
`needs.changes.outputs.haskell == 'true' || needs.changes.outputs.docs == 'true'`. Its last step is
`./doc/test-docs.sh`, which is unchanged between `main` and `unstable` and which (a) validates every
markdown link and anchor under `doc/`, (b) runs the built `l4` CLI over **every `.l4` file under
`doc/`**, and (c) reports orphans. So this PR is not "prose that cannot break the build" — it
triggers a full Haskell build and is checked by a real tool.

Three concrete consequences, each verified against `origin/main` rather than assumed:

1. **Three of the seven doc `.l4` files use language features `main` does not have.**
   `gst-rate-change-example.l4` calls `RULES EFFECTIVE DATE`, `EVAL UNDER RULES EFFECTIVE AT` and
   `EVAL UNDER VALID TIME` (**lang-eval-ledger**, with the type-environment entry in
   **lang-syntax-typecheck**); `sets-example.l4` uses `SET OF`, `UNION` and `setSize`
   (**lang-imports-stdlib**, which carries `jl4-core/libraries/prelude.l4`); `typically-example.l4`
   uses `TYPICALLY` (**lang-syntax-typecheck**). None of those three strings appears anywhere in
   `origin/main`'s `jl4-core/`. Landed alone, those files fail `l4` and turn the docs job red.
   `logic-not-flowcharts-example.l4`, `grouping-and-precedence.l4`,
   `module-a2-cross-cutting-examples.l4` and `yield-example.l4` use only features `main` already
   has.
2. **Five out-of-tree relative links do not resolve against `main`**, and the link checker treats a
   missing target as an error: `specs/todo/SET-OPERATORS-SPEC.md`,
   `specs/todo/TEMPORAL-RULE-VERSION-DESIGN.md`, `specs/todo/QUESTION-ORDERING-SPEC.md` and
   `specs/done/DEONTIC-PARTY-ACTION-AGREEMENT-SPEC.md` (all **specs**), and
   `jl4-core/src/L4/Evaluate/Ledger.hs` (**lang-eval-ledger**). A sixth,
   `specs/todo/BOUNDED-DEONTICS-SPEC.md`, already exists on `main`. Every *intra*-`doc/` link in
   these pages resolves to a file either already on `main` or included in this PR — checked
   exhaustively — so `doc/` is internally closed.
3. **The seven grouping figures are committed generator output**, produced by
   `ts-shared/ladder-svg/demo/grouping.ts`, which lives in **ladder-viz**. The SVGs render
   standalone; only *regenerating* them needs that sibling.

Beyond CI, several pages document code that lands elsewhere and would otherwise be accurate prose
about a feature `main` does not have: `syntax/README.md`, `cheat-sheet.md` and `jl4/GRAMMAR.md`
(the `•` production and `@infixl`/`@infixr`/`@infix` — **lang-syntax-typecheck**);
`libraries/resolution.md` and the `errors/README.md` correction (the B′ precedence flip —
**lang-imports-stdlib**, with the shadow warning in **lsp**); `builtins/README.md` (the deep EVAL
pin — **lang-eval-ledger**); `libraries/daydate.md` (`YMD` — **lang-imports-stdlib**);
`query-planning/` (the ROBDD planner — **ladder-viz**).

It does **not** need **corpus-regcf**, **go-pipeline**, **dmn-export**, **bpmn-export**, **mlir**,
**papers**, **proleg**, **experiments**, **service-cli**, **tests-cli**, or either wizard theme.
Suggested merge order: **lang-syntax-typecheck**, **lang-imports-stdlib**, **lang-eval-ledger** and
**specs** before this; **ladder-viz** whenever.

## Risk if rejected

`main` ships a language whose newest features — sets, `TYPICALLY`, `•` bullets, fixity
declarations, `YMD`, `RULES EFFECTIVE DATE`, the reworked library-resolution order — have no
user-facing documentation at all, and the two documents aimed at readers outside the project stay
absent, which specifically re-closes the contribution path #219 opened for the HG1 reviewer seat.
Nothing breaks, because nothing here compiles into a binary; what is lost is every answer to "why
is it like this" and "how do I use it", plus the #166 retraction, which means the incorrect
Calvanese/Drools attribution stands uncorrected wherever it has already been repeated.

## Provenance

Folded from these `unstable` PRs, taking only their `doc/` and `jl4/GRAMMAR.md` contents:

- **#89** — `feat(jl4-core): make the rule-version temporal axis load-bearing (RULES EFFECTIVE DATE)`
- **#104** — `docs: article-agreement polish for regulative performer-rule examples`
- **#105** — `docs(concepts): Flowcharts, Decision Tables, and Real Logic`
- **#109** — `feat: '•' bullet syntax + hierarchy library for isomorphic recitals/outlines`
- **#116** — `ladder-core: the viz-expr adapter, the TYPICALLY bridge, the Markdown carriers — and IMPLIES as a seam (§24, §25)`
- **#122** — `feat(prelude): SET OF a — set-theoretic operators (SET-OPERATORS-SPEC Phases 1+2)`
- **#127** — `docs(sets): variadic SET OF now live; document the singleton boundary; PYN segue`
- **#128** — `feat(fixity): @infixl/@infixr/@infix declarations for binary identifier operators`
- **#134** — `Library resolution: embedded stdlib outranks ambient XDG/bundle copies (B′) + shadow warning + dev/prod docs`
- **#135** — `docs: condensed Adoption Thesis (PRODUCT-STRATEGY) + Lexipedia Reg CF case study (logic-not-flowcharts)`
- **#166** — `docs(dmn): a gap analysis of gap analysis — and a retraction`
- **#168** — `feat(prelude): remove the AND/OR set overloads — write UNION explicitly`
- **#170** — `docs(sets): §16.3 condition met — #169 shifts un-un-overloading to semantic grounds`
- **#172** — `feat(regcf): the rule-version axis — C1 complete, temporally closed, OpenFisca-informed`
- **#174** — `feat(daydate): YMD — the ISO-ordered date constructor`
- **#189** — `Merge main into unstable: absorb docs overhaul, VS Code MCP tooling, batch CSV fix — oracle preserved` (this is where `main`'s doc tree structure and `unstable`'s technical corrections were reconciled)
- **#190** — `MLIR parity campaign: land the fail-loud bugfix ledger on unstable`
- **#211** — `fix(lang): the EVAL temporal pin is deep (#934); a local no longer shadows a selector at a projection label (#930)`
- **#219** — `docs(concepts): reviewing encoded law — the pipeline, and the HG1 seat`
- **#222** — `docs(language-design): Rulemapping (von Cossel 2026) as the strongest tree`
- **#224** — `The explainer stage, a BPMN renderer, the grouping tutorial, and the de novo Reg CF run`
