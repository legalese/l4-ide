# Measured dependencies between the aug2026 PRs

Derived mechanically by `depcheck.mjs`: for every Haskell module a theme ships, resolve its
imports against the modules the other themes ship, ignoring anything `main` already has.
Five edges exist. Everything not listed here has no compile-time dependency on a sibling.

    ladder-viz  <--  dmn-export  <--  bpmn-export  <--  service-cli
                          ^                                 |
                          +---------------------------------+
                     openfisca-export  <--------------------+

| edge | why |
| --- | --- |
| `dmn-export` needs `ladder-viz` | `L4.Dmn.Lower` imports `L4.Viz.GuardedRows`, the guarded-chain normaliser |
| `bpmn-export` needs `dmn-export` | `L4.Bpmn.Wiring` imports `L4.Dmn.IR`; `L4.Bpmn.IR`/`Lower` import `L4.Interchange.Fidelity`; the BPMN test imports the DMN test module. This is the "BPMN delegates decisions to DMN" mandate, not an accident of packaging. |
| `service-cli` needs `dmn-export`, `bpmn-export`, `openfisca-export` | `l4 export` is the CLI surface over all three back ends |

Suggested merge order: `ladder-viz` -> `dmn-export` -> `bpmn-export` / `openfisca-export` -> `service-cli`.

**These five edges are real but they are not the binding constraint.** All five of those themes, and
seven more, turn out to be in a single indivisible merge batch — see *"The edge `depcheck.mjs`
cannot see"* below and `.pr-split/BATCH.md`. Ordering within the batch is moot; it merges as a unit.
Every PR outside the batch may merge in any order.

`ci-build` should merge **last**: the workflow it ships references check scripts that arrive
with the feature PRs, so landing it early would redden `main` for checks whose subjects are
not there yet.

## A pre-existing golden gap on `main`, and what it means for merge order

`etc/check-corpus-goldens.mjs` (shipped by **ci-build**) fails on **plain `origin/main`**, today,
before any of this work: three fixtures carry no goldens —

    jl4/examples/not-ok/export-after-giveth.l4
    jl4/examples/not-ok/export-before-decide.l4
    jl4/examples/not-ok/export-between-given-giveth.l4

The twelve goldens that close that gap are in **lang-syntax-typecheck**, which is the only
slice that passes the check standalone. Every other slice merely inherits main's existing gap;
none of them introduce one.

So: **`ci-build` must merge after `lang-syntax-typecheck`.** Landing the checker first would
turn `main` red for a defect that predates all of these PRs.

## Two more edges, found by building and installing rather than by reading

- **`wizard-regcf` needs `ladder-viz`.** `ts-apps/regcf-wizard` depends on the workspace packages
  `@repo/ladder-core` and `@repo/ladder-svg`, and *both directories are new on unstable* — they do
  not exist on `main`. `npm ci` on the wizard slice alone fails with
  `404 Not Found - GET .../@repo%2fladder-core`. This is why the wizards are two PRs and not one:
  **`wizard-housing` needs nothing that is not already on `main`** (it uses `jl4-client-rpc`, which
  main has), so it ships a regenerated root lockfile and stands alone.

- **`cabal.project` is no longer a shared file.** It carried two unrelated one-line edits: dropping
  `./jl4-actus-analyzer` and adding `./jl4-proleg`. Each PR now makes its own edit, so neither can
  leave `cabal build all` pointing at a directory that is not there. (On `unstable` that exact
  mistake happened once already — PR #63 landed without its `cabal.project` edit and `f2f646fc`
  had to repair it the next day.)

## Note on the root lockfile

`package-lock.json` is touched by both **ci-build** (which adds `lint-staged`) and
**wizard-housing** (which adds a workspace). Whichever lands second needs a plain `npm install`
to reconcile. That is ordinary lockfile traffic, not a design problem.

## ci-build's own preconditions (both found by running the checks against plain `main`)

- The Haskell job's *"The sdist must carry the standard library"* step fails against `main` today:
  `data-files: libraries/*.l4` still sits **after** the flag stanzas, which is the exact defect the
  step detects. The reordering travels with **lang-imports-stdlib** (verified — that branch's
  `jl4-core.cabal` slice is precisely the `data-files` move).
- The corpus-goldens job fails against `main` today for the three `not-ok/export-*.l4` fixtures.
  Their goldens travel with **lang-syntax-typecheck**.
- `package-lock.json` names four workspace directories that only exist once **ladder-viz**,
  **wizard-housing** and **wizard-regcf** land.

So `ci-build` merges **after** lang-imports-stdlib, lang-syntax-typecheck, ladder-viz and both
wizards — which is the same conclusion as "merge it last", now with reasons.

## A build break caught by the spine attribution, and fixed

The spine agent flagged a line-level hazard the file-level partition could not see:
`jl4/tests/Main.hs` gained `import System.Environment (lookupEnv, setEnv)` on `unstable`, but
**two themes need it for different reasons** — `lang-imports-stdlib` calls `setEnv` to default
`JL4_LIBRARY_PATH`, and `lang-printer` calls `lookupEnv` for `JL4_PRETTY_DUMP_DIR` and
`JL4_EVALDIFF`. The import line was attributed to `lang-imports-stdlib`, which left
**`lang-printer`'s branch calling `lookupEnv` with no import at all** — a hard compile failure
under `-Wall -Werror`.

Verified on the pushed branch (`lookupEnv` used twice, `System.Environment` imported zero times,
and `main` does not import it either) and repaired: `lang-printer` now carries
`import System.Environment (lookupEnv)`. Neither PR can carry the union, because an unused import
is also fatal under `-Werror`. Whichever lands second resolves a one-line conflict by keeping
`(lookupEnv, setEnv)`.

Two softer ordering notes from the same attribution pass:

- `lang-imports-stdlib`'s `mkLibraryPathScrubber` scrubs `$JL4_LIBRARY_PATH` from golden output;
  three goldens carrying that token belong to `lang-syntax-typecheck`. Land the stdlib PR first.
- The `megaparsec >=9.7` bound sits in `lang-printer` — its in-file comment says "the lexer's
  ditto (^) column metric", which reads like a front-end concern, but
  `Text.Megaparsec.Unicode.isWideChar` has exactly one importer in the tree,
  `jl4-core/src/L4/Print/Columnar.hs`. The comment is worth rewording.

## The edge `depcheck.mjs` cannot see, and it is the load-bearing one

**`depcheck.mjs` resolves module imports. It is therefore known-incomplete for constructor-level
dependencies** — a theme can depend on another through a data constructor of a module that `main`
already has, and no import edge appears. There is exactly one such case here, found by the audit
pass and verified independently:

**`lang-syntax-typecheck` removes the `Expr` constructor `Exponent`** (present on `origin/main`
in `jl4-core/src/L4/Syntax.hs`, gone on `origin/unstable`). On `main`, that constructor is
pattern-matched by modules belonging to **five different themes**:

| module | theme | `Exponent` sites on main |
| --- | --- | --- |
| `L4/Syntax.hs`, `L4/Desugar.hs`, `L4/TypeCheck.hs`, `L4/TypeCheck/Annotation.hs`, `L4/Parser/ResolveAnnotation.hs` | lang-syntax-typecheck | 12 |
| `L4/EvaluateLazy/Machine.hs` | **lang-eval-ledger** | 1 |
| `L4/Nlg.hs`, `L4/Export/Document.hs` | **service-cli** | 3 |
| `L4/Print.hs` | **lang-printer** | 1 |
| `jl4-mlir/src/L4/MLIR/{Lower,Schema}.hs` | **mlir** | 9 |

The dependency runs **both ways**, which is what makes it unbreakable at file granularity:

- **`lang-syntax-typecheck` alone will not compile.** Deleting the constructor leaves four other
  themes' modules referring to a name that is no longer in scope — a hard error.
- **None of those four alone will compile either.** Each drops its `Exponent` arm while the
  constructor still exists, so an exhaustive `case` over `Expr` goes incomplete — and
  `-Wall … -Werror` (see `CLAUDE.md` §3) makes that fatal too.
- The same hazard is symmetric for the two constructors `unstable` **adds** (`Record`, `ReadCell`).

This is a property of splitting, at file level, a change that was semantically atomic (upstream
PR #83, *"refactor(jl4-core): remove dead Exponent AST constructor"*). It cannot be fixed by
reordering.

**Recommendation: merge these as one merge-queue batch**, or land them in immediate succession and
accept that `main` does not build in between.

> **Corrected 2026-08-11, by building.** This section previously named **five** themes
> (`lang-syntax-typecheck`, `lang-eval-ledger`, `lang-printer`, `service-cli`, `mlir`) and said
> "Every other PR in the set is unaffected." That is wrong. Merging those five onto `main` and
> running `cabal build all` under GHC 9.10.3 **fails**, and each successive repair pulled in another
> theme. The batch is **twelve**: the five above plus `lang-imports-stdlib`, `ladder-viz`,
> `dmn-export`, `bpmn-export`, `openfisca-export`, `lsp` and `actus-archive`.
>
> The reasoning here was sound but the survey was too narrow: `Exponent` is one of *several*
> type-level changes that cut across themes. `lang-syntax-typecheck` also widens `MkAssume` 4→5,
> `MkTypedName` 4→5 and `MkOptionallyTypedName` 3→4, adds strict fields to `MkCheckState` and
> `MkCheckEnv`, and adds `unqualifiedNameToText`; `lang-eval-ledger` widens `MkEvalDirectiveResult`
> 3→4; `service-cli` adds a field to `FunctionSchema.Parameter`. Each has its own set of consumers.
>
> Two members could not have been found by reading at all:
>
> - **`actus-archive`.** `jl4-actus-analyzer` is on `main` and in `main`'s `cabal.project`, so
>   `cabal build all` compiles it; its `FeatureExtractor.hs:519` matches `MkTypedName` with 4
>   arguments. The package is deleted by `unstable`, so the fix is that `actus-archive` lands. CI on
>   any single PR never sees this, because the build dies inside `jl4-core` first.
> - **`lsp`.** `jl4-lsp/src/LSP/L4/Inspector.hs` matches `EL.MkEvalDirectiveResult` with 3
>   arguments in five places.
>
> The full evidence chain — six builds, with the verbatim first error of each failing one — is in
> `.pr-split/BATCH.md`, which is spliced into all twelve PR bodies by
> `.pr-split/apply-batch.mjs`. Edit `BATCH.md` and re-run that script to update every member.

Everything outside those twelve is either independent or a one-way dependent that can follow.

The alternative, if they must land separately, is to re-cut `Syntax.hs` and the ten consumer
modules at hunk level the way `spine/hunks.json` already does for the `.cabal` files and
`jl4/tests/Main.hs` — carrying the constructor and every arm in one PR, and each theme's other
edits separately. That is a larger piece of work and was not attempted here.
