# feat(openfisca): L4 → OpenFisca bridge — `l4 openfisca` compiles decision rules to a runnable Python module

**What this adds**

A new backend and CLI command, `l4 openfisca FILE`, that compiles the `@export` decision-rule subset of an L4 file into a single, self-contained, runnable [OpenFisca](https://openfisca.org) Python module. Before this, L4 could type-check and evaluate a benefit or tax rule in its own engine but had no way to hand that rule to the rules-as-code engine most tax-and-benefit agencies already run; the only route was to re-implement the rule in Python by hand. After this, the L4 file stays the human-validated source and the OpenFisca module is a generated artifact — one `.py` per module, with entities, roles, input variables, formulas, enums, dated formulas and a legislation parameter store all derived from the L4. The mapping is close to isomorphic: an L4 `DECIDE`/`MEANS` over a subject and a `period` parameter *is* an OpenFisca `Variable` with a `formula(entity, period)`.

**Why**

OpenFisca is the de-facto engine for tax-and-benefit microsimulation, but its models are hand-written Python: readable to programmers, not to the lawyers and policy analysts who own the rules, and not type-checked. L4 is the readable, type-checked layer that was missing. Making L4 compile *to* OpenFisca rather than compete with it means an existing OpenFisca deployment can adopt L4 as a source language without replacing its engine, and it gives L4 an independent oracle: every example here is checked against the real engine rather than only against L4's own evaluator. The coverage target was deliberately concrete — essentially all of the OpenFisca `country-template`, the reference model every OpenFisca country package is forked from.

No upstream issue number is named in the commits or in PR #40.

**What's in it**

*Backend (4 Haskell modules, ~1,350 lines)*

- `jl4-core/src/L4/OpenFisca/IR.hs` — the target IR: `OFEntity` (with `OFRole`), `OFVariable` (undated `formula` plus dated `formula_YYYY_MM` overrides), `OFExpr`, `OFType` (including `OFEnum`), `OFScaleParam`/`OFBracket`, `OFScalarParam`, `OFEnumDef`, `OFPackage`. Deliberately small, mirroring the structure of `L4.Export`.
- `jl4-core/src/L4/OpenFisca/Lower.hs` — `Module Resolved` → IR, driven off `getExportedFunctions`. Carries the selection rules (subject record → entity, conventional `period` param → OpenFisca period, stored fields and free scalars → input variables), group-entity/role derivation from `LIST OF Person` fields, enum collection, dated-formula splitting, the parameter-store readers, and the post-lowering collision check.
- `jl4-core/src/L4/OpenFisca/Emit.hs` — IR → one self-contained Python module: entity construction, `Variable` classes, the inline `_PARAMETERS` tree, and conditional `ParameterNode` import / 3-argument `formula(p, period, parameters)` when parameters are in play.
- `jl4/app/L4/Cli/OpenFisca.hs` — the CLI command and its options parser, mirroring `l4 render`.

*Language surface covered*

- **Scalar decisions** — `@export` `DECIDE`/`MEANS` over subject + `period`; `p's field` → `entity('field', period)`; a call to another `@export` decision → `entity('that_decision', period)`.
- **Group entities and aggregation** — a `LIST OF Person` field makes the subject a group entity, one role per list field; `sum` / `count` / `any` / `all` → `household.sum` / `nb_persons` / `any` / `all`, role-restricted or all-members via `members of`.
- **Marginal-rate scales and a parameter store** — a `@desc scale <dotted.path>` value whose body is `LIST (band OF t, r), …` or a time-varying `BRANCH IF y AT LEAST <year> …` cascade becomes a real OpenFisca `ParameterNode`; a `scale tax OF <income>, <scaleRef>` call becomes `parameters(period).<path>.calc(<income>)`, so the engine resolves brackets by date and the period stays opaque.
- **Scalar legislation parameters** — a `@desc parameter <dotted.path>` value becomes a date-indexed value series read as `parameters(period).<path>`.
- **Enums** — `DECLARE X IS ONE OF a, b, …` → an OpenFisca `Enum` class with `possible_values` and `default_value`; `CONSIDER … WHEN … THEN … OTHERWISE …` → nested `np.where`.
- **Dated formulas** — a top-level `BRANCH IF period reaches OF period, Y, M THEN … OTHERWISE d` becomes the undated `formula` plus one `formula_YYYY_MM` per arm, selected by the engine.
- **Arithmetic and logic** — operators arrive desugared; `AND`/`OR`/`NOT` → numpy `&`/`|`/`~`, **fully parenthesised** so comparison precedence stays correct; `IF/THEN/ELSE` → `np.where`; `max`/`min` → `np.maximum`/`np.minimum`; `period's year`/`month` → `period.start.year`/`.month`.

*Rejections that were bugs first (commit `f514f032`, from adversarial review)*

Four silent-wrong or invalid-output cases are now diagnosed rather than emitted: keyword-unsafe identifiers (`class`, `return`) that produced invalid Python; two distinct L4 names that sanitise to the same OpenFisca variable (previously silently conflated, or a decision's formula dropped in favour of a like-named input) — now rejected with a diagnostic naming both; a time-varying scale whose `OTHERWISE` was bound and never used, so pre-first-date periods returned 0; and `BRANCH` arm ordering, where L4 is first-match but OpenFisca resolves dated formulas and parameters by latest date — non-strictly-descending arms are now rejected. Shrinking scales (a bracket that vanishes in a later year, which OpenFisca cannot represent because it carries values forward) are rejected too.

*Corpus and docs (11 examples, 10 committed goldens, 2 negative fixtures)*

- `jl4/examples/openfisca/*.l4` — `flat-tax`, `benefit`, `household`, `roles`, `housing`, `dated`, `agecheck`, `incometax`, `scale`, `basic-income`.
- `jl4/examples/openfisca/expected/*.py` — 10 committed golden Python modules.
- `jl4/examples/openfisca/not-ok/{branch-misordered,name-collision}.l4` — negative fixtures pinning the two rejections.
- `roundtrip_check.py` — runs a generated module in real OpenFisca and asserts the results equal the L4 `#EVAL` values.
- `L4-OPENFISCA.md` — correspondence table, toolchain, the state-of-the-art argument, and a "Caveats — and what the tests prove" section covering the float32 numeric model, the enum-default / `members of` / BRANCH-order conventions, and the verification tiers.
- `README.md` — the quick tour and the regeneration commands.
- `site/build_site.py` plus vendored Highlight.js core and an L4 grammar (`site/vendor/`) — a self-contained demo-site generator showing L4 source ↔ generated OpenFisca ↔ live test numbers per example, with highlighting scoped so the ASCII diagram and output panels stay plain.

**Evidence**

Quoted from the source commits and PR #40:

- **Golden CLI tests.** The suite grew with each phase, as the commit messages record it: 26/26 → 27/27 → 28/28 → 29/29 → 30/30 → 31/31 → 33/33 → **34/34 cli tests**. PR #40's own summary says "30 golden CLI tests in `jl4/tests-cli/Main.hs` over 8 examples"; the final two commits added the negative fixtures and `basic-income.l4` on top of that.
- **Round-trips in the real engine.** "Every example round-trips in real OpenFisca (`roundtrip_check.py`)." Per-example figures named in the commits: flat-tax → 500; benefit → TRUE / 700 / 0; household → 2500; roles → 2 / 2500 / True / True; housing → 400 / 0 / 1000 / `owns_or_rents=False`; dated → 0 / 600 / 0 / 600 across periods; agecheck → age=6, `has_young_child` True/False.
- **Cross-engine agreement.** For the scale leg: "Verified cross-engine: openfisca-core == policyengine-core == golden on all six `social_security_contribution` vectors (60/660/80/824/40/816)." For the scalar parameter store: "cross-engine of-core == pe-core == golden (260/300/320)."
- **Upstream oracle.** `basic-income.l4` "reproduc[es] the six upstream golden vectors" of the real country-template `basic_income`, and the phase-2 contract "now binds to the BRIDGE output (not the hand-written reference) and passes on openfisca-core AND policyengine-core — closing the 'phase 2 is a paper proof' gap the review flagged."
- **Repaired-bug measurement.** The dropped-`OTHERWISE` fix is recorded as "verified: was 0, now 500 == L4".

`L4-OPENFISCA.md` is explicit about how much each tier proves: golden tests are regression-only, round-trips prove L4 == OpenFisca (consistency), and only the upstream-oracle variables are validated against the real country-template law. That distinction should survive review intact.

**Independence**

This PR is close to standalone but **not fully self-contained as manifested** — it needs three pieces of wiring that live outside its 35 files:

- `jl4-core/jl4-core.cabal` must list `L4.OpenFisca.IR`, `L4.OpenFisca.Lower`, `L4.OpenFisca.Emit`, and `jl4/jl4.cabal` must list `L4.Cli.OpenFisca`. **Neither cabal file appears in any of the 25 theme manifests**, so these two edits have no owner and must be carried here (or the modules do not build). Both are pure additive `other-modules`/`exposed-modules` entries.
- `jl4/app/Main.hs` carries the `openfisca` subcommand registration (the `CmdOpenFisca` constructor, the `command "openfisca"` block and its dispatch arm). That file is assigned to the **service-cli** theme. Without it the library and CLI module compile but the command is unreachable.
- `jl4/tests-cli/Main.hs` carries the golden test cases (29 OpenFisca-related lines in the combined diff). That file is assigned to the **tests-cli** theme. The `expected/*.py` goldens in this PR are the fixtures those cases read, so the goldens land here and the assertions land there.

Beyond that it is genuinely independent: the backend reads a typechecked `Module Resolved` through the existing `getExportedFunctions` entry point and touches no shared evaluator, printer or type-checker code. It does not depend on **dmn-export** or **bpmn-export** despite being a sibling exporter — the three share no code. It does not touch the parallel `jl4/experiments/openfisca/` corpus (the **experiments** theme). One caveat inherited from the language side: the examples use current L4 surface syntax, so if **lang-syntax-typecheck** changes how `DECLARE … IS ONE OF`, `CONSIDER`, `BRANCH` or `@desc` parse, these `.l4` files and their goldens move with it.

The two vendored files under `site/vendor/` (Highlight.js core, an L4 grammar, a theme CSS) are third-party minified assets, checked in so the demo site is self-contained and needs no network. Worth a reviewer's eye on licensing even though nothing in the build depends on them.

**Risk if rejected**

L4 loses its only bridge to the dominant rules-as-code engine, and with it the only external oracle in the tree — the cross-engine checks against openfisca-core and policyengine-core are the sole place where an L4 answer is confirmed by software Legalese did not write. The backend is additive and unreferenced by the rest of the compiler, so dropping it breaks nothing else, provided the `jl4-core.cabal` / `jl4.cabal` module entries and the `Main.hs` subcommand block are dropped with it — leaving those in place without the modules is a build failure.

**Provenance**

- legalese/l4-ide#40 — `feat(openfisca): L4 → OpenFisca bridge` (branch `mengwong/openfisca-backend`, merged into `unstable` 2026-07-06; 10 commits, 39 changed files, +4292)

The nine commits behind the theme's 35 files:

| commit | subject |
| --- | --- |
| `50376f65` | feat(openfisca): L4 → OpenFisca backend (scalar + group-entity aggregation) |
| `82bcb49e` | feat(openfisca): Phase 1 — parameter store + marginal-rate scale; L4 syntax highlighting |
| `f1f9af6b` | feat(openfisca): group aggregation sub-steps — count/any/all + roles |
| `65de2b3f` | feat(openfisca): enums — DECLARE IS ONE OF + CONSIDER; plus max/min |
| `86286f43` | feat(openfisca): dated formulas + general BRANCH |
| `9ca4a489` | feat(openfisca): member decision-calls + period field access |
| `acffce81` | feat(openfisca): scalar legislation-parameter store |
| `f514f032` | fix(openfisca): adversarial-review CRITICALs — name collisions, scale OTHERWISE, BRANCH order |
| `ac626d80` | docs+feat(openfisca): caveats from the review; country-template basic_income example |

The theme's `.prs` manifest is empty; the PR number above was recovered from the merge commit `b3715710 Merge pull request #40 from legalese/mengwong/openfisca-backend`.
