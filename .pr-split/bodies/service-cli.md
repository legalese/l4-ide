# feat(cli): l4 export, l4 verify and l4 nlg subcommands; a richer l4 batch; and a build-time guard on the embedded stdlib

**What this adds**

The user-facing command line grows three subcommands that until now existed only as library code
reachable from the test suite: `l4 export` (write a module out as DMN 1.3 XML, dmnmd markdown or
BPMN 2.0, always with a fidelity report), `l4 verify` (look for unsatisfiable rules, dead branches,
vacuous guards and unreachable outcomes in a decision's boolean skeleton), and `l4 nlg` (linearize
a module's directives to the same prose payload the `.nlg` goldens hold). `l4 batch` grows
`--format json|csv|yaml|ndjson`, `--output FILE`, `--continue-on-error` and `--validate-only`.
`l4 check` and `l4 run` stop reporting success on a broken import closure or a crashed `#EVAL`.
`l4 trace` stops shelling out through `callCommand`. And the embedded standard library becomes a
build-time invariant: a binary that would have shipped with no stdlib now refuses to build, loudly,
instead of answering "Module not found: prelude" at runtime.

**This PR is the `l4` executable and nothing else.** Thirteen files: ten under `jl4/app/`, the two
`EmbeddedLibraries` modules in `jl4-core`, and two one-line-sliced `.cabal` registrations. An
earlier cut of this theme also carried the `jl4-service` ladder endpoint, the `jl4-query-plan`
ranking work and several `jl4-core` library modules; all of that now rides in
[#257](https://github.com/legalese/l4-ide/pull/257), which owns the type changes it was entangled
with. What answers to this PR is the command-line surface over that machinery.

**Why**

Three gaps drove the CLI work. First, the DMN and BPMN exporters were reachable only from the test
suite, so "DMN + BPMN out, each with its fidelity report" (milestone M4 of the lexipedia-superset
programme) had no user-facing surface at all. Second, two stages of the `go` demo pipeline were
footings-first: `p7-tnr` hashed prose it had not produced (there was no way to regenerate an
`.nlg.golden` short of running `cabal test`, which the orchestrator will not do), and `p8-verify`
refused outright with "no CLI exposes the ROBDD to a script". Third, exit codes lied: `l4 run`
exited 0 on a crashed `#EVAL`, and `l4 check` passed a module whose import cycle attached its
diagnostic to a transitively-imported file. `smucclaw/l4-ide#932` (`l4 batch`'s misleading format
summary) is also touched.

## What's in it

**13 files, +2,145 / −105.**

_Three new subcommands (1,464 lines)_

- `jl4/app/L4/Cli/Export.hs` (603 lines) — `l4 export --to=dmn|dmn-md|bpmn`, `-o FILE`,
  `--rule NAME`, `--model-name`, `--deadline-unit`, `--fidelity-report`,
  `--fail-on=none|blocking|lossy|advisory`, and the `--flavor` axis (KIE vs Camunda). A one-line
  loss tally always goes to stderr; the located list goes to `<out>.fidelity.txt`, or to stderr
  when the document owns stdout. `Blocking` is deliberately _not_ a failure by default — it means
  "the target notation cannot express this at all", which fires for every task in every BPMN
  export. Misplaced flags (`--model-name` on BPMN, `--rule` on DMN) are refused rather than
  ignored.
- `jl4/app/L4/Cli/Verify.hs` (753 lines) — `l4 verify FILE [--format text|json]`, exit 0 clean / 1
  with findings. Four finding families over the boolean skeleton: `unsat`, `dead-branch`,
  `vacuous-guard`, `unreachable-outcome`. It reaches the ROBDD by the wizard's own path
  (`doVisualize` → `vizExprToBoolExpr` → `compileDecisionQuery`) so the two cannot disagree about
  what a rule's atoms are, and reports `analysed` / `skipped` / `nestedNotVisited` as three
  separate counts rather than folding the last into "clean". The module exports
  `propositionalBound`, a five-paragraph statement of what a clean run does and does not prove,
  printed both as the `--help` footer and at the foot of the text report.
- `jl4/app/L4/Cli/Nlg.hs` (108 lines) — a deliberately thin wrapper around
  `L4.Nlg.simpleLinearizer`, emitting byte-for-byte the payload `jl4-test`'s
  `jl4NlgAnnotationsGolden` writes, so `p7-tnr` can regenerate and diff instead of hashing a
  committed file against itself.

_Existing CLI (6 files: `Batch`, `Check`, `Common`, `Run`, `Trace`, `Main`)_

- `Batch.hs` (+417/−68): four output formats, `--output`, `--continue-on-error`,
  `--validate-only`, a `{input, output, status, diagnostics}` envelope per row, and CSV type
  inference (`inferCsvCell`, which types cells at parse time with deliberate guards for `007` and
  `1E5`, rather than coercing against the declared parameter type). Shell-injection and
  backslash-corruption fixes from the same lineage ride along. The `progDesc` was corrected —
  `json|yaml|csv` in, NDJSON out, since the old summary read as if `--input-format ndjson` existed
  (`smucclaw/l4-ide#932`).
- `Common.hs` (+78/−8) gains `runOneshotWithDiagnostics` and `hasBlockingError`; `Check.hs` and
  `Run.hs` use them, so an import cycle whose diagnostic attaches to a transitively-imported file
  no longer passes. `Run.hs` additionally fails on a crashed `#EVAL` (commit `d7aa1631`, "ruled by
  Meng 2026-08-01" — this reverses the judgement call #189 recorded during the main merge, where
  the `Run.hs` conflict was resolved in favour of the then-documented "eval diagnostics never
  change the exit code"; the widest consequence, called out in the source, is that `ASSUME`-style
  modules that cannot evaluate now exit 1). Import-resolution log lines at Warning/Error priority
  are no longer filtered as progress chatter, so `LIBRARY-RESOLUTION-SHADOW-SPEC`'s shadow warning
  reaches the user. `Common.hs` also renders the state ledger a directive produced
  (`prettyLedger`, dropped when empty) — the CLI half of the STATE-AS-LEDGER surface whose
  evaluator half is in #257.
- `Trace.hs` (+39/−7) — `l4 trace --format png|svg` no longer shells out through `callCommand`.
  `dot` runs as a bare process with an explicit argument list, so a path containing a space or
  `$(...)` or `;rm -rf` is passed verbatim instead of word-split or executed, and a missing `dot`
  or a non-zero exit now fails loudly.
- `Main.hs` (+51/−1) registers the new subcommands (including `l4 openfisca`, whose module is
  owned by **openfisca-export**) and adds `footerDoc` so a multi-paragraph footer keeps its line
  breaks (`footer` is `fillSep . words`, which reflowed `propositionalBound` into one wall of
  prose).

_The embedded stdlib guard (2 files in `jl4-core`)_

- `L4/API/EmbeddedLibraries.hs` (+29/−2) + `TH.hs` (+13/−2) — the TH splice now `fail`s instead
  of embedding `[]`, so a stdlib-less binary is a build error rather than a binary that answers
  "Module not found: prelude" for every `IMPORT`. The failure message names the three probed
  locations and the usual root cause (a `data-files` field silently disabled by a section inserted
  above it in the `.cabal`), with the two commands that confirm it.

_Build registration (2 line-sliced files)_

- `jl4/jl4.cabal` — registers `L4.Cli.{Export,Nlg,Verify}` and adds `jl4-query-plan`,
  `containers`, `optics` to the executable's `build-depends`.
- `jl4-service/jl4-service.cabal` — a single line adding `servant-server` to the
  `jl4-service-test` dependency list. The test code that needs it rides in #257; the line is
  carried here so the per-slice edits to this shared file still sum to `unstable`'s version.

## Evidence

These are the numbers the source PRs reported, each at its own point on the branch; suite totals
grew across the window, so they are not directly comparable to each other. Where a figure measures
code that has since moved to #257, it is marked.

From #154 (`l4 export`):

- `l4-cli-test` 64 → **87 examples, 0 failures** (+23, all `l4 export`) — the fixtures live in
  **tests-cli**.
- Byte equality of the CLI's artifacts against the same artifacts built through the library API
  (`checkWithImports`) by `jl4/tests/BpmnExport.hs` and `DmnExport.hs` — two different front ends,
  same bytes.

From #207 (`l4 verify` + `l4 nlg`):

- Suites: `l4-cli-test` **202 examples, 0 failures, 79 pending**; `jl4-service-test` 311;
  `jl4-test` 2238; `jl4-core-test` 269; `jl4-lsp-test` 10.
- `l4 verify` on Reg CF: `regcf.l4` **102 decisions / 42 analysed / 60 skipped / 0 findings**;
  `regcf-wizard.l4` **52 / 1 / 51 / 0**. Bounded by three measurements rather than left as a bare
  zero: **25 of the 42 analysed decisions have exactly one atom** and the widest has 6;
  **`merged_atom_occurrences = 0`**, so atom coalescing is a measured no-op on this corpus;
  **111 of 154 decisions are skipped** as non-`BOOLEAN`, counted and named rather than folded into
  "clean".
- The accounting repair found **7 decisions across the Reg CF corpus** (regcf 5, regcf-wizard 2)
  that were in neither the analysed nor the skipped column, one of them a boolean.
- Negative controls: five `verify-*.l4` fixtures (in **tests-cli**) reproduce their declared
  verdicts by finding _kind_, not exit code. Perturbing `regcf-wizard.nlg.golden` drops `p7-tnr`
  to `DEGRADED` with distinct hashes and a `.diff` artifact, so the differential oracle is real.
- The propositional bound was tested against itself: `x > 5 AND x < 3`, `x > 5 AND x > 1` and a
  date-shaped pair each report **zero findings** — the tool does not claim an arithmetic
  contradiction it cannot see — while `x > 5 AND NOT (x > 5)` _is_ found.

From #167 (embedded stdlib): jl4-core's sdist goes from **0 → 22** `.l4` files; a
`cabal install`-built `l4` goes from exit 1 to exit 0 on `IMPORT prelude` with `JL4_LIBRARY_PATH`
unset. Tests 1826 + 311 + 269 + 96 examples, 0 failures.

Measured on code now in #257, quoted here because this CLI is its surface: the `/ladder` ∩
query-plan atomId join went **0/2 → 2/2** on Reg CF and **0/11 → 11/11** on the Jersey Charities
corpus (#210), and the ladder blow-up that motivated `--max-ladder-nodes` was **8 variables →
12 KB, 16 → 366 KB, 32 → still streaming past 36 MB after five minutes** (#154).

## Blast radius

**3 new files**, 10 modified.

Build registration only:

- `jl4/jl4.cabal` — registers the new modules and their dependencies
- `jl4-service/jl4-service.cabal` — one test-suite dependency line (see above)

Within the CLI and the embedded-library loader (this PR's own surface):

- `jl4-core/src/L4/API/EmbeddedLibraries.hs`
- `jl4-core/src/L4/API/EmbeddedLibraries/TH.hs`
- `jl4/app/L4/Cli/Batch.hs`
- `jl4/app/L4/Cli/Check.hs`
- `jl4/app/L4/Cli/Common.hs`
- `jl4/app/L4/Cli/Run.hs`
- `jl4/app/L4/Cli/Trace.hs`
- `jl4/app/Main.hs`

**No library semantics change here.** The two `jl4-core` files alter when a build fails, not what
any program evaluates to.

## Independence

This PR is **not** standalone. It is a surface layer, and its imports name their owners exactly:

- **#257 (the language core)** — `Common.hs` imports `prettyLedger` from `L4.EvaluateLazy`
  (today's CI failure, verbatim: `Module 'L4.EvaluateLazy' does not export 'prettyLedger'`);
  `Verify.hs` imports `L4.Decision.{BooleanDecisionQuery,QueryPlan}` and
  `LSP.L4.Viz.{Ladder,QueryPlan,VizExpr}` in their post-#257 shapes. #257 also owns the
  `jl4-service` and `jl4-query-plan` sources this theme used to carry.
- **dmn-export (#236)** and **bpmn-export (#232)** — `Export.hs` imports `L4.Dmn.{Emit,IR,Lower,Markdown}`,
  `L4.Bpmn.{Emit,IR,Lower,Wiring}` and `L4.Interchange.Fidelity`. `l4 export` cannot compile
  without both.
- **openfisca-export (#250)** — `Main.hs` imports `L4.Cli.OpenFisca`, and the `jl4.cabal` line
  registering that module rides in #250's slice of the same file.
- **tests-cli (#253)** — owns every CLI-level test of the new commands: `jl4/tests-cli/Main.hs`
  and the `verify-*.l4`, `export-two-rules`, `export-advisory-only` fixtures. This PR ships the
  code; that PR ships its proof.
- **go-pipeline (#239)** — consumes `l4 verify` and `l4 nlg` from the other side
  (`etc/go/phases/p7-tnr.sh`, `p8-verify`). Landing this PR without it leaves two working commands
  nobody calls; landing that one without this leaves two stages with no footing.

What this PR owns outright: the embedded-stdlib guard is self-contained, and the `Trace.hs` /
`Batch.hs` hardening compiles against any tree that has the CLI at all.

## Risk if rejected

The DMN/BPMN exporters, the ROBDD verifier and the NLG linearizer stay library code with no front
door — `l4 export`, `l4 verify` and `l4 nlg` do not exist, `p7-tnr` and `p8-verify` lose their
footings, and the **tests-cli** theme's fixtures fail against a binary with no such subcommands.
Exit codes keep lying: `l4 run` keeps exiting 0 on a crashed `#EVAL` and `l4 check` keeps passing
broken import closures. A `cabal install`-built binary can once again ship without a standard
library and fail only at the first `IMPORT`. And `l4 trace` keeps passing user paths through a
shell.

## This PR was part of an interlock that has since been consolidated

An earlier revision of this section named a **15-PR merge batch** that had to land as one unit. That
is no longer the shape of the work, and the roster it listed is now largely closed. What happened:

Twelve of those PRs could not build separately, because the entangling changes are to *types* in
modules `main` already has — `Syntax.hs` removes the `Expr` constructor `Exponent`, widens
`MkAssume` 4→5, `MkTypedName` 4→5 and `MkOptionallyTypedName` 3→4, and adds strict fields to
`MkCheckState`; the evaluator widens `MkEvalDirectiveResult` 3→4. Every consumer had to change in
the same commit, in **both** directions, and the consumers were spread across six packages. No
ordering resolved it.

**Eight of them were therefore consolidated into [#257](https://github.com/legalese/l4-ide/pull/257),
the language core** — `lang-syntax-typecheck` (#245), `lang-eval-ledger` (#241), `ladder-viz`
(#240), `lang-printer` (#243), `lsp` (#246), `lang-sets` (#244), `lang-imports-stdlib` (#242) and
`actus-archive` (#230), all now closed. #257 was built by taking `unstable`'s version of whatever
the compiler rejected, to a fixed point, so it contains no hand-written intermediate code. It is
green: `cabal build all` clean, 7/7 suites, `jl4-test` 2039 examples 0 failures.

**What remains for this PR is a one-way dependency**, which ordering does resolve. It no longer has
to merge simultaneously with anything — it simply has to merge *after* its prerequisites. Those are
named in the metadata line at the top of this body and in the merge-order guide.

The full measurement — six builds, with the verbatim first error of each failing one — is recorded
in `.pr-split/DEPENDENCIES.md` on the branch `claude/unstable-branch-reorganization-6cle91`.

## Provenance

This theme was re-cut twice after its first shipping: the 12 August reconciliation moved 31 files
(the `jl4-service/`, `jl4-query-plan/`, `jl4-repl/` sources and several `jl4-core` library
modules) into #257, and `jl4-wasm/app/QueryPlanWasm.hs` followed on 13 August, because keeping it
here made this PR and #257 a cycle at the WASM build rather than an ordering. The upstream PRs
below are the ones whose work is **still in this diff**; the ladder endpoint, query-plan ranking
and schema work that #110, #116, #154, #159, #160, #162, #180, #182, #183, #185 and #210
contributed to the original 43-file cut now reach `main` through #257.

| PR   | title                                                                                                                                  | what it contributes here                                                                                              |
| ---- | -------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| #134 | Library resolution: embedded stdlib outranks ambient XDG/bundle copies (B′) + shadow warning + dev/prod docs                            | Warning-level import-resolution lines reaching CLI stderr                                                              |
| #154 | feat(surfaces): l4 export CLI (S0) + jl4-service /ladder (S1)                                                                           | `L4.Cli.Export` (the `/ladder` half is in #257)                                                                        |
| #167 | fix(build): restore the embedded stdlib, and make its absence a build error                                                             | `EmbeddedLibraries.hs` + `TH.hs` failing loudly                                                                        |
| #189 | Merge main into unstable: absorb docs overhaul, VS Code MCP tooling, batch CSV fix — oracle preserved                                   | the `Batch.hs` and `Run.hs` conflict resolutions                                                                       |
| #207 | feat(cli): l4 verify + l4 nlg — P8 measures 5/5 controls and 0 findings over 43 analysed decisions; p7-tnr regenerates and diffs        | `L4.Cli.Verify`, `L4.Cli.Nlg`, `footerDoc` in `Main.hs`                                                                |
| #214 | fix(print): make prettyLayout round-trip, and stop it silently changing the answer                                                      | `l4 batch` — the reported `#932` failure was in the filter→print→parse path `batchCmd` drives                          |

Not attributable to any PR in the list above: several of the older `l4 batch` commits predate this
numbering and reached `unstable` through earlier merges — `582b956c` (batch output formats,
`--output`, `--continue-on-error`, CSV type inference), `291cd005` (unbuffered ndjson, exponent
CSV cells, MAYBE param validation), `3a8d77e7` (shell injection in `l4 trace`, backslash
corruption in `l4 batch`), `4be7553d` (fail `l4 check`/`run` on cyclic imports), and `d7aa1631`
(a crashed `#EVAL` fails `l4 run`).
