# docs: the language-design essays, the reviewer briefing, and the reference pages for everything `unstable` added

**What this adds**

This is the prose half of the `unstable` divergence: 92 files under `doc/` plus `jl4/GRAMMAR.md`,
53 of them new. After this lands the repository can answer, in its own tree, four questions it
previously could not: *why is L4 a language rather than a flowchart builder* (a 1,124-line
language-design essay with a runnable companion `.l4`), *what does a domain expert actually do when
they review an encoding* (the HG1 reviewer briefing, with three committed SVG figures), *how do I
write the features that landed on `unstable`* (reference pages for sets, `TYPICALLY`, the `•`
bullet syntax, `YMD`, the regulative deontics, library resolution, negation-as-failure and ROBDD
query planning), and *what does a comma cost* (a 15-minute grouping-and-precedence tutorial built
on three real appellate disputes, with seven generated ladder figures).

**Why**

Two gaps drove it. First, features were shipping without a place a non-author could learn them —
`SET OF`, `TYPICALLY`, `@infixl`, `•` bullets, `YMD`, `RULES EFFECTIVE DATE` and the reworked
library-resolution order all arrived on `unstable` with reference prose written in the same PR, and
that prose has nowhere to live on `main`. Second, the two documents most likely to be read by
someone outside the project — the design rationale and the reviewer briefing — existed only as an
argument in people's heads and as standalone HTML respectively. PR #219 states the motivation for
the latter plainly: the HG1 seat "is the part of this system we most want outside expertise in",
and "the document describing that seat existed only as standalone HTML, which meant nobody could
open a PR against it."

---

## What's in it

### The language-design essays (`doc/concepts/`)

- **`language-design/logic-not-flowcharts.md`** (1,124 lines) with **`logic-not-flowcharts-example.l4`**
  (58 lines) — the central argument, built over four PRs. The thesis: a flowchart commits a
  category error for regulatory logic, drawing a *timeless material conditional* as a *sequential
  process*, which says more than the law (an invented evaluation order) and less (the lost AND/OR
  shape). Worked throughout on GPDO 2015 Class A A.3, the obscure-glazed window rule from the 2021
  "write this legislation as a flowchart a 9-year-old can understand" challenge. Sections added
  later in the branch: the Lexipedia Reg CF (2026) BPMN case study (#135), the DMN decision-tables
  section, and the Rulemapping (von Cossel 2026) section (#222) — which is deliberately the
  *strongest* rival, because it gets the picture right and keeps it as the source.
- **`language-design/dmn-analysis-prior-art.md`** (262 lines, #166) — a survey of who actually
  detects gaps and overlaps in DMN, declaring itself the canonical copy so a future correction has
  one place to land. It also **retracts** a claim made earlier in `logic-not-flowcharts.md` (that
  the Calvanese hyper-rectangle algorithm runs inside Drools and Trisotech), in place with
  strikethrough rather than by silent deletion. Sources read directly are listed separately from
  sources verified only by metadata, and four claims are marked unverified.
- **`language-design/related-work.md`** (213 lines) and a 33-line addition to
  **`linguistic-syntax.md`**.
- **`legal-modeling/`** — `actors-and-actions.md` (380), `ACTOR-ACTIONS-THEORY.md` (204) and a
  292-line BibTeX file `actor-actions.bib`, plus a small `regulative-rules.md` fix.
- **`reviewing/reviewing-encoded-law.md`** (364 lines, #219) with three committed SVGs — the
  Rule 501(a) OR-ladder, a schematic decision requirements graph, and the resale restriction as
  emitted BPMN. Fifteen sections: the HG1 seat and what a detached signature over a content digest
  claims; inert style; the pipeline stage by stage; the two reviewer jobs; a translation table for
  reviewers arriving from OPA/OIA; ladders, DMN, BPMN, interviews and MCP as projections; the
  conversion report; and how to issue a `go`.
- Index entries in `concepts/README.md` and `concepts/SUMMARY.md`, including a new **Reviewing**
  heading.

### The reference (`doc/reference/`)

Twenty-eight files. New pages:

- **`libraries/sets.md`** (84) and **`libraries/sets-example.l4`** (57) — the `SET OF a` vocabulary
  from #122, kept current across three later reversals: the variadic-`SET OF` caveats removed and
  the **singleton boundary** documented once it was found (#127: `SET OF x` with one argument reads
  `x` as the contents *list*, so `SET OF "carol"` is a type error and singletons stay
  `setFromList (LIST "carol")`); the `AND`/`OR` set overloads removed and rewritten to `UNION`
  (#168); and the §16.3 note repointed at #169 (#170).
- **`libraries/resolution.md`** (249, #134) — the resolution order with per-tier rationale, a
  dev/prod playbook, how to read the resolver output, the Template Haskell embed-staleness
  mechanics, and the incident history. `errors/README.md` is corrected in the same change, where it
  carried the stale ordering.
- **`libraries/negation-as-failure.md`** (65), **`types/TYPICALLY.md`** (90) with
  **`typically-example.l4`** (21), and **`query-planning/README.md`** (117) +
  **`query-planning/robdd.md`** (100).

Modified pages: `syntax/README.md` (+81, the `•` bullet syntax from #109), `cheat-sheet.md`,
`builtins/README.md` (+38 — the EVAL clause signatures corrected and the deep pin stated, from
#211), the five `regulative/` pages (`DEONTIC`, `MAY`, `MUST`, `PARTY`, `SHANT`, `README`),
`patterns/common-patterns.md`, `patterns/README.md`, `types/type-theory.md`, `libraries/README.md`,
`libraries/daydate.md`, `libraries/prelude.md`, `GLOSSARY.md`, `README.md`, `SUMMARY.md`.

### The tutorials (`doc/tutorials/`)

- **`getting-started/grouping-and-precedence.md`** (329) + **`.l4`** (102) + **28 figure files**
  (seven figures × `.mmd` / `.sentences` / `.svg` / `.txt`), from #224. Teaches the one question a
  formal language must answer before it can mean anything — given `a OR b AND c`, what binds
  tighter — and answers it with **layout**, not a precedence table. Three real disputes, each a
  different failure with a different repair: *Chew* (bracketing, where the compiler's same-column
  `AND`/`OR` warning fires twice), *Oakhurst* (tokenization — a missing serial comma, one leaf
  against two), and *Rogers* (attachment — where a second authoritative French text resolved it,
  which is the argument for the whole approach). Ends with a five-item practice list, including
  "never put a disjunction inside a field name". Every snippet lives in the sibling `.l4` with
  `#EVAL` directives, and the figures are generated from that file through the LSP rather than
  drawn.
- **`multi-temporal-modeling/multi-temporal-rule-modeling.md`** (321) +
  **`gst-rate-change-example.l4`** (127) — the tutorial for the rule-version temporal axis made
  load-bearing in #89 (`RULES EFFECTIVE DATE`).
- **`set-operators/sets-and-the-two-ands.md`** (143) — including the "Sets in one minute" primer
  for the non-mathematician and the Poh Yuan Nie / Boolean-minimization segue that reframes the
  otiosity canon as a presumption that statutory text is already minimized.
- **`natural-language-functions/optimising-natural-language-generation.md`** (93),
  **`deploying-rules/insurance-premium.cases.json`** (48), plus edits to
  `getting-started/encoding-legislation.md` (+63 — the recitals-as-inert-outline workflow from
  #109), `getting-started/wedding-vows.md`, `llm-integration/legislative-ingestion.md`, and the two
  index files.

### The courses (`doc/courses/`) and the grammar

Seven module files touched — `foundation/module-1`, `module-6-regulative` (+78),
`module-7-capstone`, and `advanced/module-a1` through `module-a4` including
`module-a2-cross-cutting-examples.l4`. Largely deontic/performer-rule refreshes plus the
English-article agreement pass of #104 (`GIVETH A DEONTIC`, `IS AN Actor / Action / Item`), which
is prose-only with no behaviour change. `jl4/GRAMMAR.md` gains six lines for the `•` bullet
production.

---

## Evidence

The source PRs reported these, and they are quoted rather than recomputed here:

- **#134** (library resolution, whose docs page is `libraries/resolution.md`): "`doc/test-docs.sh`
  fully green (858 links, 81 L4 files, 0 orphans)".
- **#127** (sets docs follow-up): "Doc example re-validated against merged unstable: **13/13
  `#EVAL`s green.**"
- **#166**: "`prettier@3.4.2 --check` clean on all four files. Docs-only; no code paths touched."
- **#219**: "`prettier@3.4.2 --check` clean on all three touched/added markdown files; all links
  resolve (absolute URLs, plus the three sibling SVGs); `xmllint --noout` clean on all three SVGs;
  no non-XML named entities; docs only — no code, no build, no workflow touched."
- **#170**: "Markdown-only; prettier@3.4.2 clean."
- **#222**: "Docs only; no code paths touched." The Rulemapping section quotes von Cossel's own
  §130(1) StGB experiment over 868 posts — Rulemapping precision 0.80–0.86 against long-context CoT
  0.34–0.49 and zero-context 0.28–0.37 — and the PR is explicit that "this is the first measured
  support for this page's thesis, and it is **not ours**."

For the tutorial and reference pages that ride along inside feature PRs (#89, #109, #122, #128,
#168, #172, #174, #211, #224), the golden-suite figures those PRs report are measurements of the
*code*, not of this documentation; they are not restated here as evidence for this PR.

**#219 additionally flags its own most likely bug, and that flag carries over verbatim:** the
reviewer briefing "is dense with measurements — test counts, engine-agreement figures, build times,
dates. Each was true when its sentence was written, and **nothing re-checks them on read**." The
page opens by asking that a drifted number be fixed in the same PR as the work that revealed it.
Because this PR lands that page against `main` rather than against the `unstable` tree those
numbers were measured on, **a reviewer should treat every figure inside `reviewing-encoded-law.md`
as needing a re-check against whatever ships**, and the same caution applies to the counts inside
`dmn-analysis-prior-art.md`.

## Independence

Largely standalone as a build artefact — nothing here compiles, links against, or is imported by
Haskell or TypeScript, and no CI job in the tree fails because of prose. But three honest
qualifications:

1. **Several pages document code that lands in sibling PRs.** `libraries/sets.md` and
   `sets-and-the-two-ands.md` describe the prelude `SET OF` type and its operators (**lang-sets**);
   `syntax/README.md`, `cheat-sheet.md` and `jl4/GRAMMAR.md` describe the `•` bullet production and
   `@infixl`/`@infixr`/`@infix` (**lang-syntax-typecheck**); `libraries/resolution.md` and the
   `errors/README.md` correction describe the B′ precedence flip
   (**lang-imports-stdlib**, with the shadow warning in **lsp**); `builtins/README.md` states the
   deep EVAL pin (**lang-eval-ledger**); `types/TYPICALLY.md` and `query-planning/` describe
   `TYPICALLY` and the ROBDD planner (**lang-syntax-typecheck** / **ladder-viz**);
   `libraries/daydate.md` documents `YMD` (**lang-syntax-typecheck**). Landed without those, these
   pages are accurate prose about a feature `main` does not have. That is a documentation-drift
   problem, not a build break.
2. **Six `.l4` files and one JSON ship with the docs**, and they are the ones a reviewer should
   look at: `logic-not-flowcharts-example.l4`, `grouping-and-precedence.l4`,
   `gst-rate-change-example.l4`, `sets-example.l4`, `typically-example.l4`,
   `module-a2-cross-cutting-examples.l4`, `yield-example.l4`, and
   `insurance-premium.cases.json`. These are under `doc/`, not under `jl4/examples/`, so they carry
   no `tests/*.golden` obligations and cannot turn `jl4-test` red (CLAUDE.md §3.1). They *can* stop
   evaluating correctly if their language features are absent — `sets-example.l4` in particular was
   edited by #168 when the `AND`/`OR` set overloads went away.
3. **The seven grouping figures are committed generator output**, produced by
   `ts-shared/ladder-svg/demo/grouping.ts`, which lives in **ladder-viz**. The SVGs render fine
   standalone; only regenerating them needs that sibling.

It does **not** need: **specs**, **corpus-regcf**, **go-pipeline**, **dmn-export**, **bpmn-export**,
**mlir**, **papers**, or either wizard theme. Cross-references into `specs/` from these pages are
relative markdown links, which degrade to a dead link rather than a failure.

## Risk if rejected

The repository ships a language whose newest features — sets, `TYPICALLY`, `•` bullets, fixity
declarations, `YMD`, `RULES EFFECTIVE DATE`, the reworked library-resolution order — have no
user-facing documentation on `main`, and the two documents aimed at people outside the project (the
design rationale and the HG1 reviewer briefing) stay unavailable, which specifically re-closes the
contribution path #219 opened. Nothing breaks; the code all still works. What is lost is every
answer to "why is it like this" and "how do I use it", and the retraction in
`dmn-analysis-prior-art.md` never lands, leaving the Calvanese/Drools attribution uncorrected
wherever it has already been repeated.

## Provenance

Folded from these `unstable` PRs (taking only their `doc/` and `jl4/GRAMMAR.md` contents):

- #89 — `feat(jl4-core): make the rule-version temporal axis load-bearing (RULES EFFECTIVE DATE)`
- #104 — `docs: article-agreement polish for regulative performer-rule examples`
- #105 — `docs(concepts): Flowcharts, Decision Tables, and Real Logic`
- #109 — `feat: '•' bullet syntax + hierarchy library for isomorphic recitals/outlines`
- #116 — `ladder-core: the viz-expr adapter, the TYPICALLY bridge, the Markdown carriers — and IMPLIES as a seam`
- #122 — `feat(prelude): SET OF a — set-theoretic operators`
- #127 — `docs(sets): variadic SET OF now live; document the singleton boundary; PYN segue`
- #128 — `feat(fixity): @infixl/@infixr/@infix declarations for binary identifier operators`
- #134 — `Library resolution: embedded stdlib outranks ambient XDG/bundle copies (B′) + shadow warning + dev/prod docs`
- #135 — `docs: condensed Adoption Thesis + Lexipedia Reg CF case study`
- #166 — `docs(dmn): a gap analysis of gap analysis — and a retraction`
- #168 — `feat(prelude): remove the AND/OR set overloads — write UNION explicitly`
- #170 — `docs(sets): §16.3 condition met — #169 shifts un-un-overloading to semantic grounds`
- #172 — `feat(regcf): the rule-version axis — C1 complete, temporally closed, OpenFisca-informed`
- #174 — `feat(daydate): YMD — the ISO-ordered date constructor`
- #189 — `merge: main into unstable` (absorbs the docs overhaul that moved these trees)
- #190 — `MLIR parity campaign: land the fail-loud bugfix ledger on unstable`
- #211 — `fix(lang): the EVAL temporal pin is deep (#934); a local no longer shadows a selector (#930)`
- #219 — `docs(concepts): reviewing encoded law — the pipeline, and the HG1 seat`
- #222 — `docs(language-design): Rulemapping (von Cossel 2026) as the strongest tree`
- #224 — `The explainer stage, a BPMN renderer, the grouping tutorial, and the de novo Reg CF run`
