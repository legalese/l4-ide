# feat(cli,service): l4 export/verify/nlg subcommands, a richer l4 batch, and the jl4-service ladder endpoint

**What this adds**

This is the front door for a lot of machinery that already existed as library code with no way to reach it from a shell or over HTTP. The `l4` executable gains four subcommands — `l4 export` (write a module out as DMN 1.3 XML, dmnmd markdown or BPMN 2.0, always with a fidelity report), `l4 verify` (look for unsatisfiable rules, dead branches, vacuous guards and unreachable outcomes in a decision's boolean skeleton), `l4 nlg` (linearize a module's directives to the same prose payload the `.nlg` goldens hold), and `l4 openfisca` (wired here, owned by the openfisca-export theme) — while `l4 batch` grows `--format json|csv|yaml|ndjson`, `--output FILE`, `--continue-on-error` and `--validate-only`. On the service side, `jl4-service` gains `GET /deployments/{id}/functions/{fn}/ladder`, so a client can fetch a decision's AND/OR diagram without posting an argument set, and that diagram's leaf `atomId`s are now the same ids `POST .../query-plan` accepts as binding keys. `l4 check` and `l4 run` also stop reporting success on a broken import closure or a crashed `#EVAL`.

**Why**

Three separate gaps drove this. First, the DMN and BPMN exporters were reachable only from the test suite, so "DMN + BPMN out, each with its fidelity report" (milestone M4 of the lexipedia-superset programme) had no user-facing surface at all. Second, two stages of the `go` demo pipeline were footings-first: `p7-tnr` hashed prose it had not produced (there was no way to regenerate an `.nlg.golden` short of running `cabal test`, which the orchestrator will not do), and `p8-verify` refused outright with "no CLI exposes the ROBDD to a script". Third, upstream `smucclaw/l4-ide#935`: the ladder and the query planner minted `atomId`s in two different namespaces, so a wizard that drew the diagram and posted answers keyed by its leaf ids got a `200` and a silent no-op. Building the ladder route also uncovered two live service bugs — every restarted deployment was answering `400` for `/query-plan`, and a four-line L4 file was a denial of service — both fixed here. `smucclaw/l4-ide#850` (stale bundle after an interrupted deploy) and `smucclaw/l4-ide#932` (`l4 batch`'s misleading format summary) are also touched.

**What's in it**

43 files, roughly +4,477 / −345.

_New CLI subcommands (3 new modules, ~1,460 lines)_

- `jl4/app/L4/Cli/Export.hs` — `l4 export --to=dmn|dmn-md|bpmn`, `-o FILE`, `--rule NAME`, `--model-name`, `--deadline-unit`, `--fidelity-report`, `--fail-on=none|blocking|lossy|advisory`. A one-line loss tally always goes to stderr; the located list goes to `<out>.fidelity.txt`, or to stderr when the document owns stdout. `Blocking` is deliberately *not* a failure by default — it means "the target notation cannot express this at all", which fires for every task in every BPMN export. Misplaced flags (`--model-name` on BPMN, `--rule` on DMN) are refused rather than ignored.
- `jl4/app/L4/Cli/Verify.hs` — `l4 verify FILE [--format text|json]`, exit 0 clean / 1 with findings. Four finding families over the boolean skeleton: `unsat`, `dead-branch`, `vacuous-guard`, `unreachable-outcome`. It reaches the ROBDD by the wizard's own path (`doVisualize` → `vizExprToBoolExpr` → `compileDecisionQuery`) so the two cannot disagree about what a rule's atoms are, and reports `analysed` / `skipped` / `nestedNotVisited` as three separate counts rather than folding the last into "clean". The module exports `propositionalBound`, a five-paragraph statement of what a clean run does and does not prove, printed both as the `--help` footer and at the foot of the text report.
- `jl4/app/L4/Cli/Nlg.hs` — a deliberately thin wrapper around `L4.Nlg.simpleLinearizer`, emitting byte-for-byte the payload `jl4-test`'s `jl4NlgAnnotationsGolden` writes, so `p7-tnr` can regenerate and diff instead of hashing a committed file against itself.

_Existing CLI (6 files: `Batch`, `Check`, `Common`, `Run`, `Trace`, `Main`)_

- `Batch.hs` (+485): four output formats, `--output`, `--continue-on-error`, `--validate-only`, a `{input, output, status, diagnostics}` envelope per row, and CSV type inference (`inferCsvCell`, which types cells at parse time with deliberate guards for `007` and `1E5`, rather than coercing against the declared parameter type). Shell-injection and backslash-corruption fixes from the same lineage ride along. The `progDesc` was corrected — `json|yaml|csv` in, NDJSON out, since the old summary read as if `--input-format ndjson` existed (`smucclaw/l4-ide#932`).
- `Common.hs` gains `runOneshotWithDiagnostics` and `hasBlockingError`; `Check.hs` and `Run.hs` use them, so an import cycle whose diagnostic attaches to a transitively-imported file no longer passes. `Run.hs` additionally fails on a crashed `#EVAL` (commit `d7aa1631`, "ruled by Meng 2026-08-01" — this reverses the judgement call #189 recorded during the main merge, where the `Run.hs` conflict was resolved in favour of the then-documented "eval diagnostics never change the exit code"; the widest consequence, called out in the source, is that `ASSUME`-style modules that cannot evaluate now exit 1). Import-resolution log lines at Warning/Error priority are no longer filtered as progress chatter, so `LIBRARY-RESOLUTION-SHADOW-SPEC`'s shadow warning reaches the user.
- `Trace.hs` — `l4 trace --format png|svg` no longer shells out through `callCommand`. `dot` runs as a bare process with an explicit argument list, so a path containing a space or `$(...)` or `;rm -rf` is passed verbatim instead of word-split or executed, and a missing `dot` or a non-zero exit now fails loudly.
- `Main.hs` registers the new subcommands and adds `footerDoc` so a multi-paragraph footer keeps its line breaks (`footer` is `fillSep . words`, which reflowed the bound into one wall of prose).

_jl4-service (1 README, 9 src modules, 10 test specs)_

- `DataPlane.hs` — the `GET .../ladder` route and `requireDecisionQueryCache`, shared with `query-plan` so both read one memoised structure and whichever is hit first pays the one-time cost.
- `Backend/DecisionQueryPlan.hs` — calls `annotateLadderWithAtomIdsUsing` so ladder leaves land in the query planner's `atomId` namespace, plus a fuel-limited `exceedsNodeBudget` that costs `O(budget)` rather than `O(size)`.
- `Options.hs` / README — `--max-ladder-nodes` / `JL4_MAX_LADDER_NODES`, default 10000, documented in the options table and the Resource Limits section.
- `Compiler.hs` — `buildFromCborBundle` now takes module, environment, entity info and DECIDE from the typecheck it was already running. `L4.Instances.Serialise` encodes every `Anno_` as `()`, which discards `resolvedInfo`; `hasBooleanType` reads a DECIDE's result type off exactly that field, so a CBOR-rehydrated deployment looked non-boolean and `/query-plan` answered 400 after every restart.
- `BundleStore.hs` — clear the deterministic `<id>.tmp` staging dir before writing, so an interrupted deploy cannot merge old and new sources into the atomic swap (`smucclaw/l4-ide#850`).
- `ControlPlane.hs` — the recompile shortcut is keyed on content hash *and* requested id; deploying identical bytes under a second name used to return 200 naming the first deployment and create nothing.
- `OpenApiDoc.hs` / `Schema.hs` — `/ladder` documented under the same `X-Include-Evaluate` gate as `query-plan`, since it returns a strict subset of that payload.
- Tests: 10 spec files, +57 `it` blocks and **zero removed**, including new `describe` groups `ladder`, `ladder node budget`, `atom identity`, `atom identity, across shapes`, `TYPICALLY question ordering (end-to-end)`, `BImplies — verdict, not truth value`, and `IMPLIES — the wizard must not report a vacuous TRUE as compliance`. `IntegrationSpec` gains `withServiceRestartedFromCbor`, which comes back through the production `DeploymentLoader.loadAndRegister` and fails if `bundle.cbor` is gone afterwards (the loader silently recompiles from source on CBOR failure, and a test that quietly took that branch would prove nothing).

_jl4-core and jl4-query-plan support (10 modules, 2 goldens)_

- `L4/JsonSchema.hs` — builtin type names are matched case-insensitively (and the alias set widened to `int/float/double/text/bool/listof/time`). L4's resolved builtins are ALL-CAPS, so the old case-sensitive `"Number"` arm never fired and every builtin emitted a dangling `$ref: "#/$defs/NUMBER"`. The two `*.schema.golden` files in this PR are that repair: `$ref` → `"type": "number"` (plus a leading-space fix in the description).
- `L4/FunctionSchema.hs`, `L4/Export.hs` — `TYPICALLY` defaults surface as a JSON Schema `default` (`typicallyToJson`, literals and TRUE/FALSE only); `enrichParamTypes` fills bare-head DECIDE parameter types from `EntityInfo`, refusing to guess when the inferred type still has an inference variable; `@nonexhaustive` joins the `@desc` flag vocabulary.
- `L4/API/EmbeddedLibraries.hs` + `TH.hs` — the TH splice now `fail`s instead of embedding `[]`, so a stdlib-less binary is a build error rather than a binary that answers "Module not found: prelude" for every `IMPORT`. `L4/API.hs` and the not-found diagnostic name the embedded tier and deduplicate the path list.
- `jl4-query-plan/src/L4/Decision/{BooleanDecisionQuery,QueryPlan}.hs` — `binaryEntropy` + memoized `prob`, expected-posterior information-gain ranking mirroring the TypeScript `decision-query.ts`, priors threaded from `TYPICALLY`, a `Verdict` field (`Undetermined | Holds | Fails | Complies | InBreach | NotApplicable`), and `atomIdByUnique` inverted with a multimap rather than last-wins `Map.fromList` — an `atomId` names a *question*, and answering it must bind every occurrence.
- `jl4-repl/app/Main.hs`, `jl4-wasm/app/QueryPlanWasm.hs`, `L4/Nlg.hs`, `L4/Export/Document.hs` — mechanical follow-through for AST changes owned by other themes (see Independence).

**Evidence**

These are the numbers the source PRs reported, each at its own point on the branch; suite totals grew across the window, so they are not directly comparable to each other.

From #154 (`l4 export` + `/ladder`):

- `l4-cli-test` 64 → **87 examples, 0 failures** (+23, all `l4 export`); `jl4-service-test` 295 → **311, 0 failures** (+16: 13 `/ladder`, 3 budget); `jl4-test` **1801, 0** — untouched by that branch.
- "across `jl4-service/test` and `jl4/tests-cli` the diff deletes **zero** `it "…"` lines and adds 41."
- Ladder blow-up, measured on this service: "**8 variables → 12 KB, 16 → 366 KB, 32 → still streaming past 36 MB after five minutes.**" 32 variables take ~0.5 s to build; 64 do not finish.
- Byte equality of the CLI's artifacts against the same artifacts built through the library API (`checkWithImports`) by `jl4/tests/BpmnExport.hs` and `DmnExport.hs` — two different front ends, same bytes.

From #210 (atomId join):

- `GET /ladder` ∩ planner atoms on Reg CF: **0/2 → 2/2**; on the Jersey Charities corpus across three exports: **0/11 → 11/11**; on the `charities-cleanroom` corpus: **3/3**, all six bindings move the decision.
- Controls shown red on the pre-fix source with the tests in place: `QueryPlanSpec` "atom identity" **7 examples, 5 failures**; `IntegrationSpec` "ladder" **22 examples, 5 failures**; the new cross-shape property red on **3 of 10** shapes.
- Payload stability: across `/query-plan` only the *values* of `impactByAtomId` change, and only for atomIds naming more than one occurrence — `impact`, `ranked`, `stillNeeded`, `asks`, `inputs` byte-identical on both corpora. Latency on the twin-heavy function **~0.117 s pre-fix, ~0.118 s post-fix** over 8–10 warm runs.
- Suites at that point: `jl4-service-test` **341/0**, `jl4-test` **2250/0**, `l4-cli-test` 180/0 (79 pending), `jl4-core-test` 269/0, `jl4-lsp-test` 10/0.

From #207 (`l4 verify` + `l4 nlg`):

- Suites: `l4-cli-test` **202 examples, 0 failures, 79 pending**; `jl4-service-test` 311; `jl4-test` 2238; `jl4-core-test` 269; `jl4-lsp-test` 10.
- `l4 verify` on Reg CF: `regcf.l4` **102 decisions / 42 analysed / 60 skipped / 0 findings**; `regcf-wizard.l4` **52 / 1 / 51 / 0**. Bounded by three measurements rather than left as a bare zero: **25 of the 42 analysed decisions have exactly one atom** and the widest has 6; **`merged_atom_occurrences = 0`**, so atom coalescing is a measured no-op on this corpus; **111 of 154 decisions are skipped** as non-`BOOLEAN`, counted and named rather than folded into "clean".
- The accounting repair found **7 decisions across the Reg CF corpus** (regcf 5, regcf-wizard 2) that were in neither the analysed nor the skipped column, one of them a boolean.
- Negative controls: five `verify-*.l4` fixtures reproduce their declared verdicts by finding *kind*, not exit code; the whole status lattice was exercised (corpus-with-findings → `DEGRADED` exit 1, neutralised control → `BROKEN` exit 4). Perturbing `regcf-wizard.nlg.golden` drops `p7-tnr` to `DEGRADED` with distinct hashes and a `.diff` artifact, so the differential oracle is real.
- The propositional bound was tested against itself: `x > 5 AND x < 3`, `x > 5 AND x > 1` and a date-shaped pair each report **zero findings** — the tool does not claim an arithmetic contradiction it cannot see — while `x > 5 AND NOT (x > 5)` *is* found.
- Full G1 run `2026-08-02-1733c452-005`: thirteen declared legs unperturbed, hash chain verifies, **51/51 artifacts still hash as recorded**, `VERDICT: g1 COMPLETE`.

From #167 (embedded stdlib): jl4-core's sdist goes from **0 → 22** `.l4` files; a `cabal install`-built `l4` goes from exit 1 to exit 0 on `IMPORT prelude` with `JL4_LIBRARY_PATH` unset. Tests 1826 + 311 + 269 + 96 examples, 0 failures.

From #110 (question ordering): TS and Haskell agree on the parity fixture to **< 1e-3**; with `TYPICALLY` priors a presumed-FALSE atom declared *first* ranks **last** (`["a","b","presumed"]` against the prior-free `["presumed","a","b"]`), and the service and LSP paths return the identical ranking. `jl4-service` suite **271 examples, 0 failures** at that point.

**Independence**

This PR is **not** standalone. It is the surface layer over several other themes, and it needs them to compile:

- **Hard build dependency, and a gap in the split.** `jl4/app/Main.hs` here imports `L4.Cli.OpenFisca`, whose module lives in the **openfisca-export** theme. Separately, **no theme's manifest carries `jl4/jl4.cabal` or `jl4-service/jl4-service.cabal`** — but the executable will not build without the `jl4.cabal` hunk that adds `L4.Cli.{Export,Nlg,OpenFisca,Verify}` to `other-modules` and `jl4-query-plan`, `containers`, `optics` to `build-depends` (and `jl4-service-test` needs `servant-server`). Those stanza edits must ride with this PR or be landed as an explicit prerequisite.
- **dmn-export** and **bpmn-export** own the exporters `L4.Cli.Export` drives (`L4.Dmn.Lower/Emit/Markdown`, `L4.StateGraph`, `L4.Bpmn.Lower/Emit`, `L4.Interchange.Fidelity`). `l4 export` cannot be built or tested without them.
- **ladder-viz** owns `L4.Viz.VizExpr`, `L4.Viz.Ladder`, `LSP.L4.Viz.{Ladder,QueryPlan}`. `l4 verify` reaches the ROBDD through them; the atomId join calls `annotateLadderWithAtomIdsUsing`, which lives there; the `Verdict`/`Implies` seam the query planner reports is defined there.
- **tests-cli** owns every CLI-level test of this PR's new commands: `jl4/tests-cli/Main.hs` and the `verify-*.l4`, `export-two-rules`, `export-advisory-only` fixtures. This PR ships the code; that PR ships its proof. The `+23 l4 export` and `l4 verify` control-fixture counts quoted above are measurements of *that* theme's files.
- **lang-syntax-typecheck** owns the AST shape changes this PR tracks mechanically: `MkTypedName` / `MkOptionallyTypedName` / `MkAssume` gaining a `TYPICALLY` field, `TStringLit` gaining a field, and the removal of the `Exponent` constructor. Every arity edit in `L4/Nlg.hs`, `L4/Export/Document.hs`, `L4/API.hs` and `L4/FunctionSchema.hs` is downstream of that.
- **lang-eval-ledger** owns `EvalDirectiveResult` gaining its `ledger` field. `jl4-repl/app/Main.hs` and the `renderEvalOutput` hunk in `Cli/Common.hs` exist only to track it.
- **go-pipeline** consumes `l4 verify` and `l4 nlg` from the other side (`etc/go/phases/p7-tnr.sh`, `p8-verify`). Landing this PR without it leaves two working commands nobody calls; landing that one without this leaves two stages with no footing. Note also, verbatim from #207: `go.sh` still lists `p8-verify` in `UNIMPLEMENTED_STAGES` and `G1_STAGES` does not name it — declaring it is a one-line driver change outside this PR's file ownership.

What this PR *does* own outright: the two `*.schema.golden` files it carries are produced by the `JsonSchema.hs` fix in this same PR, so that pair is internally consistent and needs nothing from a sibling.

**Risk if rejected**

Drop this and the DMN/BPMN exporters, the ROBDD verifier and the NLG linearizer go back to being library code with no front door — `l4 export`, `l4 verify` and `l4 nlg` disappear, `p7-tnr` and `p8-verify` lose their footings, and the **tests-cli** theme's `l4 export`/`l4 verify` cases fail against a binary with no such subcommand. On the service side, restarted deployments keep answering `400` for `/query-plan`, an unauthenticated GET stays a denial-of-service vector, and any client keying bindings off ladder `atomId`s keeps getting a silent no-op (`smucclaw/l4-ide#935`). The `jl4.cabal` hunk is the sharpest edge: without it nothing in this PR compiles at all.

**Provenance**

Folded from these `unstable` PRs, taking only the CLI and service parts of the ones that span several themes. The ones that carry the substance here are **#154**, **#167**, **#207** and **#210**; the rest contribute one-file follow-through.

| PR | title | what it contributes here |
| --- | --- | --- |
| #110 | TYPICALLY priors for question ordering (v2) | `prob`/info-gain ranking in `jl4-query-plan`, priors threaded into `Backend.DecisionQueryPlan`, the parity fixture in `QueryPlanSpec` |
| #116 | ladder-core: the viz-expr adapter, the TYPICALLY bridge, the Markdown carriers — and IMPLIES as a seam (§24, §25) | the `Verdict` field on the query plan, and the `BImplies` / vacuous-TRUE spec groups |
| #130 | fix(format): l4 format identity for TIMEZONE/UNLESS/unicode/multi-clause DECIDE + corpus invariant | `TStringLit` gaining its raw-slice field; the `L4/API.hs` match arity |
| #134 | Library resolution: embedded stdlib outranks ambient XDG/bundle copies (B′) + shadow warning + dev/prod docs | Warning-level import-resolution lines reaching CLI stderr |
| #154 | feat(surfaces): l4 export CLI (S0) + jl4-service /ladder (S1) | `L4.Cli.Export`, the `/ladder` route, `--max-ladder-nodes`, the CBOR-rehydration fix in `Compiler.hs` |
| #159 | fix(state-graph): derive the LEST edge's caption from the modal and the deadline | 11 lines of `IntegrationSpec` only — the state-graph change itself belongs to bpmn-export |
| #160 | fix(dmn): two engine flavors (R7), with both engines checking answers not just liveness | the `--flavor` axis `l4 export` exposes |
| #162 | feat(regcf): cut BPMN from the corpus itself; triage every projection finding | the `ControlPlane.hs` fix — the recompile shortcut keyed on requested id as well as content hash |
| #167 | fix(build): restore the embedded stdlib, and make its absence a build error | `EmbeddedLibraries.hs` + `TH.hs` failing loudly, and the embedded tier named in the not-found diagnostic |
| #180 | feat(dmn): hydration for computed fields + MAYBE→null (R8-d′) + isJust recognition | export-side follow-through |
| #182 | Phase 0.5: land the exhaustiveness oracle on unstable | `@nonexhaustive` in `L4.Export`'s `@desc` flag vocabulary |
| #183 | DMN Phase 4: un-lifting analysis + totality + R6 population filter | `isNonexhaustiveDecide`, export-side follow-through |
| #185 | exhaustiveness for multi-clause DECIDEs: analyse the clause matrix before desugaring (OPEN-6) | export-side follow-through |
| #189 | Merge main into unstable: absorb docs overhaul, VS Code MCP tooling, batch CSV fix — oracle preserved | the `Batch.hs` and `Run.hs` conflict resolutions, and `Export/Document.hs` adapted to the 4-field `OptionallyTypedName` |
| #190 | MLIR parity campaign: land the fail-loud bugfix ledger on unstable | `enrichParamTypes` (bare-head DECIDE parameter types from `EntityInfo`) |
| #198 | feat(bpmn): wire each guarded gateway to the emitted DMN — form G measured against jBPM, all 6 BPMN goldens resolve, one contradiction found and fixed | what `l4 export --to=bpmn` now emits |
| #207 | feat(cli): l4 verify + l4 nlg — P8 measures 5/5 controls and 0 findings over 43 analysed decisions; p7-tnr regenerates and diffs | `L4.Cli.Verify`, `L4.Cli.Nlg`, `footerDoc` in `Main.hs` |
| #210 | fix(atomid): ladder ∩ query-plan atom ids 0/2 → 2/2 on Reg CF, 0/11 → 11/11 on Charities; twin bindings reach every occurrence | the atomId join, the twin multimap, the README and `DataPlane` prose corrections |
| #214 | fix(print): make prettyLayout round-trip, and stop it silently changing the answer | `l4 batch` — the reported `#932` failure was in the filter→print→parse path `batchCmd` drives |

Not attributable to any PR in the list above: several of the older `l4 batch` and JSON Schema commits predate this numbering and reached `unstable` through earlier merges — `582b956c` (batch output formats, `--output`, `--continue-on-error`, CSV type inference), `291cd005` (unbuffered ndjson, exponent CSV cells, MAYBE param validation), `3a8d77e7` (shell injection in `l4 trace`, backslash corruption in `l4 batch`), `4be7553d` (fail `l4 check`/`run` on cyclic imports), `87c8b2e4` (valid JSON Schema for builtin types, T3), `04d5c5b5` (leftover tmp staging dir on redeploy, `smucclaw/l4-ide#850`), and `d7aa1631` (a crashed `#EVAL` fails `l4 run`).
