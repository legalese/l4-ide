# corpus(experiments): Housing Act 1988 Schedule 2 end-to-end, ledger and NAF demos, dmnmd→L4 worked example

**What this adds**

`jl4/experiments/` gains a complete, executable encoding of **Schedule 2 to the Housing Act 1988** — the grounds on which a court may order possession of a dwelling — as amended by the Renters' Rights Act 2025. Each ground lives in its own self-contained L4 module with its own `Claim` record and its own `Ground N made out` predicate; on top of them sit two entry points that did not exist before: a top-level `court possession decision` aggregator that calls the real per-ground predicates over real pleaded claims and preserves the s.7(3) *mandatory* / s.7(4) *discretionary* modality split, and a flat citizen-facing wizard façade over the three rent-arrears grounds exposing a single `@export default` function. The same directory gains runnable demos for the event-sourced ledger surface (`RECORD` / `COMMIT` / `ATTEST` / `RECALL` / `RECALL ALL`, including the cross-party and `OFFICIAL` forms), a negation-as-failure example file, and three curated `.cases.json` input sets for the MLIR differential parity sweep. Finally, `jl4/examples/experiments/miles-card/` adds a dmnmd→L4 worked example ("which credit card do I tap for this transaction?"), and a two-identifier correctness fix lands in a vendored copy of the prelude.

**Why**

Schedule 2 was picked because it is real, messy and *recently amended*: a whole statutory schedule, with two tiers of modality, a repealed Part, a higher-order amendment power and an interpretation selector that several grounds depend on. Single toy rules do not show whether L4's guarded-deontic modelling scales to that shape; this corpus does, and it is also the rules layer the housing wizard app (sibling theme **wizard-housing**) queries — the app has nothing to answer with unless these modules exist. The ledger demos are the runnable companions to `specs/todo/STATE-AS-LEDGER-SPEC.md`, which had spec sections but nothing you could execute. `negation-as-failure-examples.l4` is the renamed demo from the review of **PR #34**, which moved `holds` / `naf` / `presumed` out of the prelude into their own library — the rename was forced, because a `.l4` file cannot `IMPORT` a library sharing its own basename. The `.cases.json` files exist because the MLIR parity harness synthesises degenerate arguments (`number→1`, `bool→true`, `string→"x"`) when a file has no curated sidecar, which cannot reach the interesting branches; `britishcitizen5.cases.json` is the input that surfaced ledger **#7** (ordered comparison on STRING-typed dates). The prelude fix is the experiments-side half of **PR #140**.

## What's in it

**Housing Act 1988 Schedule 2 — 49 L4 modules**

- **42 ground files.** 38 distinct grounds (1, 1A, 1B, 2, 2ZA–2ZD, 3, 4, 4A, 5, 5A–5H, 6, 6A, 6B, 7, 7A, 7B, 8, 9, 10, 11, 12, 13, 14, 14A, 14ZA, 15, 17, 18) plus four alternative treatments of Ground 1 kept side by side: `-limbs` (limbs (a)/(b) as separate predicates), `-full` (the full predicate set), `-amended-2025` (the RRA 2025 text, with the occupier relationship as a checkbox relation), and `-traced` (a trace-driven ledger demo). Ground 3 is a repealed stub carrying the omitted text as inert prose; Ground 6 is the "table ground" (redevelopment).
- **Structural tail.** `housing-act-part-5-interpretation.l4` (para. 12 — the shared definitions plus the **`relevant date` selector**), `housing-act-part-6-powers-to-amend.l4` (para. 13 — the Secretary of State's amendment power, modelled as a permissive `PARTY SecretaryOfState MAY amend the Schedule` guarded by an amendable-target list *and* the draft-affirmative procedure), and `housing-act-part-4-repealed.l4` (Part IV omitted by RRA 2025, former paras 7–11 kept as prose).
- **Shared vocabulary.** `housing-act-common.l4` hoists the `Actor` / `Action` enums that 37 ground files had been declaring identically. Its header names the three files that deliberately do *not* import it, and why their vocabulary genuinely differs.
- **Two entry points.** `housing-act-possession-decision.l4` — the aggregator, showing **Form A** (the two-tier s.7(3)/s.7(4) guarded deontic; the header explains at length why a flat `MUST IF (g1 OR … OR g14)` would wrongly promote the discretionary grounds) beside **Form B** (the landlord's election to plead, as `ROR`, which is a genuine regulative choice and yields a residuation trace). And `housing-act-wizard.l4` — a thin façade that re-implements no law, routing one flat `Situation` record into Grounds 8/10/11 and returning one flat `PossessionAssessment` with the mandatory/discretionary distinction, reasons and statutory citations.
- **`housing-act-schedule2-aspect.l4`** — Schedule 2 modelled as an *aspect* woven onto a vanilla lease with `RAND`: the notice obligation is the ledger write, and a separate court thread reads the trace back with `RECALL`, so a lease with no notice aspect at all still fits (the court goes discretionary).

**Ledger and negation-as-failure demos — 7 files**

`state-ledger.l4` (writes return the value recorded; per-directive isolation; presumption by `fromMaybe`), `state-ledger-m45.l4` (cross-party and `OFFICIAL` reads inside a deontic chain), `recall-all.l4` and `recall-all-usages.l4` (the collect-all read: `RECALL ALL`, `RECALL ALL <party>'s`, `RECALL ALL OFFICIAL's`, and the deliberate contrast that an unwritten cell reads back as `[]` rather than `NOTHING`), `record-hence-block.l4` (proving the layout-block sugar for `RECORD` continuations residuates identically to the explicit flat `HENCE` chain), `notify-v1.l4` (a content-bearing, court-queryable notice as a recipient-qualified `RECORD`, with its v1 caveats written down rather than solved), and `negation-as-failure-examples.l4` (the three epistemic states, `holds` / `naf` / `presumed`, and the `decided` axis NAF throws away).

**dmnmd→L4 worked example — 4 files**

`jl4/examples/experiments/miles-card/`: two `.dmn.md` decision tables as the source of truth, the generated `miles-card.l4`, and a `README.md` recording the regeneration pipeline and provenance. The README says outright this is "the worked example that motivated the display-width / ditto (`^`) column work in the dmnmd→L4 backend" — the `^` token copies the token at the same start column on the previous line, and the alignment is display-width-accurate. The `#EVAL` block at the bottom demonstrates the 2026-07 split of Tesla charging into two categories.

**MLIR parity inputs — 3 `.cases.json`**

`britishcitizen5.cases.json` (and its `classic/` twin, byte-identical) and `query-planner-tests/04-alcohol-purchase.cases.json`: curated argument sets that deliberately separate branches instead of taking the harness's synthesised defaults.

**One-line-per-site prelude fix — 1 file**

`jl4/experiments/thailand-cosmetics/prelude.l4` is a 1045-line vendored copy of the standard prelude, created when a symlink was replaced by a real file so a nix store derivation would include the content. It carried the same defect as the original: the `MAYBE NUMBER` overload of `maximum` delegated to `minimum1`, and `maximum1` folded with `min`. Two identifiers corrected here (lines 330 and 339).

## Evidence

Quoted from the source commits and PRs.

- Aggregator Stage C (`da417b75`): **"Whole-corpus sweep (45 files): 1500 `#ASSERT`s, 0 failures, 0 errors."** Ten direct `#ASSERT`s prove each real predicate fires — TRUE on the made-out claim, FALSE on the not-made-out one.
- Common-vocabulary hoist (`1580e805`): "every `#ASSERT` still passes (whole-corpus sweep: 0 failures, 0 errors)."
- Part 5 selector wiring (`6137d55b`, Ground 2ZA): "Green: 46 `#ASSERT`s pass, check succeeds." Extended to 2ZB and 5F in `13acd7e0`: "Whole-corpus sweep: 0 failures, 0 errors."
- Aggregator PoC (`3d988d87`): "15 `#ASSERT`, 11 `#TRACE`, all green."
- RRA 2025 Grounds 1A/1B (`3232cbcf`): "22 `#ASSERT`s, all passing" and "26 `#ASSERT`s, all passing."
- Per-ground assert counts are recorded in each encoding commit — e.g. Ground 6 (the table ground) "61 asserts"; Grounds 5E/5F "10 asserts" and "31 asserts"; Grounds 7A/7B "23 asserts" and "17 asserts".
- Prelude clone, from **PR #140**: comparing the vendored copy with `jl4-core/libraries/prelude.l4` declaration by declaration, with `@nlg` annotations and whitespace normalised away, gives "100 shared names with **zero** body differences and **zero** local edits"; at the commit that created it (`d4b5755f`) the copy was "byte-for-byte identical". After the fix, "`l4 check` passes on it. It is in no test glob, so it gets no fixture."
- `britishcitizen5.cases.json`, from **PR #190**'s parity ledger: ledger row **#7**, "`britishcitizen5` — ordered comparison on STRING-typed dates", cleared by `__l4_str_cmp` + synonym unfolding, evidenced by "`britishcitizen5.cases.json` (5 cells) + `str-ordering-probe`". The sweep these inputs feed reported **"227 byte-identical, 0 differs, 0 wasm-error, 5 refused-unsupported — PARITY OK"**, with the committed CI Tier-2 gate at "97 byte-identical, 0 refused, exit 0". Those two figures are the whole sweep, not these three files alone.

No golden files are added or changed by this PR, and no suite counts are claimed for it: nothing here is inside a `jl4-test` glob (see Independence).

## Independence

**Not in any test glob.** `jl4/tests/Main.hs` globs `ok/**`, `legal/**`, `not-ok/**`, `lsp/**` under `jl4/examples`, plus `jl4-core/libraries/*.l4`. Neither `jl4/experiments/` nor `jl4/examples/experiments/` matches any of them, and `etc/check-corpus-goldens.mjs` is kept in step with exactly those roots. So this PR ships **no goldens**, correctly, and cannot turn the Haskell suite red on its own or on anyone else's branch. The flip side is that nothing in CI is watching these files, which is precisely how the vendored-prelude defect survived.

**What it needs from siblings.**

- **lang-eval-ledger** — required by 9 files. The six ledger demos (`state-ledger*.l4`, `recall-all*.l4`, `record-hence-block.l4`, `notify-v1.l4`) plus three Housing Act files that use the ledger (`housing-act-ground-1-full.l4`, `housing-act-ground-1-traced.l4`, `housing-act-schedule2-aspect.l4`). `RECORD` / `COMMIT` / `ATTEST` / `RECALL` do not exist on `main` at all — `jl4-core/src/L4/Evaluate/Ledger.hs` is absent there — so these files will not even lex without that theme.
- **lang-syntax-typecheck** — `record-hence-block.l4` exists to demonstrate the layout-block sugar for `RECORD` continuations (`implicitSeq`); without the parser change it is a file about a feature that is not there.
- **lang-imports-stdlib** — `negation-as-failure-examples.l4` opens with `IMPORT \`negation-as-failure\``, and `jl4-core/libraries/negation-as-failure.l4` is new on `unstable` and belongs to that theme.
- **mlir** — the three `.cases.json` are inert data by themselves. They only do work when `jl4-mlir/scripts/parity-harness.mjs` reads them.

**What it does not need.** The other 46 Housing Act modules import only `prelude` and `daydate`, both already on `main`, and depend on nothing in the other 24 themes. The miles-card example is four self-contained files (two markdown tables, one generated `.l4`, one README) — the dmnmd generator that produced the `.l4` lives in a different repository and is explicitly **not** a build dependency of this one. The `thailand-cosmetics/prelude.l4` fix is a two-line edit to a leaf file with no importers in this corpus.

**Direction of the wizard dependency.** `housing-act-wizard.l4` is the L4 backing for the SvelteKit app in theme **wizard-housing**; that app needs this PR, not the reverse. Landing this without the app leaves a perfectly good `@export default` entry point with no browser front end. Landing the app without this leaves a form with nothing to ask.

## Risk if rejected

The largest single-statute L4 corpus in the tree disappears, and with it the only worked demonstration that the two-tier mandatory/discretionary split, the Part 5 `relevant date` selector and cross-file `IMPORT` of sibling ground modules actually compose end-to-end; the **wizard-housing** app would land with no rules to query. Smaller but real: the ledger and `RECALL ALL` features in **lang-eval-ledger** would ship with their spec but without any runnable demonstration, the MLIR parity sweep would lose the curated inputs behind ledger #7, and the vendored prelude in `thailand-cosmetics/` would silently keep computing minima when asked for maxima.

## Provenance

Unstable PRs folded into this one:

- **#140** — `fix(prelude): maximum over MAYBE NUMBER returned the minimum` (experiments-side half only: the `thailand-cosmetics/prelude.l4` clone. The `jl4-core/libraries/prelude.l4` fix and the new `jl4/examples/ok/prelude-min-max.l4` fixture belong to **lang-imports-stdlib**.)
- **#190** — `MLIR parity campaign: land the fail-loud bugfix ledger on unstable` (experiments-side half only: the three curated `.cases.json` inputs. The backend, harness and parity documentation belong to **mlir**.)

The Housing Act corpus, the ledger and NAF demos and the miles-card example reached `unstable` as direct commits rather than through numbered PRs; the commits are `23d12d64`, `bb425581`, `b71c6a08`, `b1d9e792`, `3232cbcf`, `cd1b9664`, `e6f7dff7`, `9748d916`, `9df2abe2`, `468d703e`, `175a754a`, `14381567`, `0d12e463`, `25c2f805`, `b21228fa`, `1a1266ff`, `5885aa56`, `f210df5e`, `3d988d87`, `1580e805`, `6137d55b`, `13acd7e0`, `da417b75`, `c8452a58`, `b530206e`, `60bde3a7`, `917adedb`, `341eebeb`, `76833434`, `6183ef0c`, `7a7b8836` and `5cf5d611`.
