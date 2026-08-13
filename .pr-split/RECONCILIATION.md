# Reconciling the branches with #257

`#257 lang-core` consolidated eight PRs (#230, #240, #241, #242, #243, #244, #245, #246) that the
compiler proved inseparable. Its body states the new boundary for the PRs that survive. The
branches did not initially match that boundary; this note records bringing them into line.

## What was re-cut

| PR | was | now | dropped |
| --- | --- | --- | --- |
| **#252** `service-cli` | 45 files | **14** | 31 files that moved to #257 (`jl4-service/`, `jl4-query-plan/`, `jl4-repl/`, and the `jl4-core` library modules) — exactly the count #257's body states |
| **#247** `mlir` | 54 files | **48** | the 4 `L4.MLIR.*` source modules, `test/Main.hs` and `app/Main.hs` |
| **#236** `dmn-export` | 101 files | **93** | 8 goldens #257 now carries |
| **#234** `corpus-legal-new` | 46 files | **44** | 2 goldens #257 now carries |

The rule applied was mechanical: *remove whatever `lang-core` now carries, except the deliberately
line-sliced spine files.* `service-cli` landing on exactly 14 is the confirmation that the rule is
the right one.

## The rule missed one file — corrected 2026-08-13, `service-cli` is now 13

`jl4-wasm/app/QueryPlanWasm.hs` stayed in `service-cli` and should not have. The rule was applied by
**path prefix**, and the three prefixes it swept — `jl4-service/`, `jl4-query-plan/`, `jl4-repl/` —
do not cover the WASM entry point that *consumes* `jl4-query-plan`. So the file's two edits, the
`priorsByUnique` field and the `UBoolVar` 5→6 pattern, were separated from the modules that define
them.

That made #257 and #252 a **cycle, not an ordering**: #257 had `unstable`'s `VizExpr` against
`main`'s five-argument pattern; #252 had the updated call site against `main`'s `VizExpr`. Both
failed their WASM job, in mirror image, and no merge sequence cleared it.

Why it survived every check we ran:

- `jl4-wasm` is **not in `cabal.project`**, so `cabal build all` — the measurement behind the
  15-PR batch and behind #257's own fixed point — never compiled it.
- `depcheck.mjs` reads module imports, and this is an arity edge, invisible to it (the limitation
  already recorded in `DEPENDENCIES.md`, biting once more).
- The byte-identity sweep passed: **both** branches held a file byte-identical to some baseline —
  #257 to `main`, #252 to `unstable`. Identity against *a* baseline is not consistency *within* a
  branch, and only the second would have caught this.

Corrected by moving the file to #257 and re-shipping both. Verified at blob level: for all three of
`jl4-wasm/app/QueryPlanWasm.hs`, `jl4-core/src/L4/Viz/VizExpr.hs` and
`jl4-query-plan/src/L4/Decision/QueryPlan.hs`, #257 now holds `unstable`'s copy and #252 holds
`main`'s. Awaiting the WASM job on both.

**The generalisable check.** The root cause is narrower than it looks, and it is now bounded. What
made this file invisible was not the prefix rule by itself but that **`cabal build all` could not
see it** — so the exposure is exactly the Haskell packages outside `cabal.project`. Measured on
`origin/main`: `cabal.project` lists nine packages, and the top-level directories holding a `.hs`
file changed between `main` and `unstable` are `jl4-core` (75), `jl4-actus-analyzer` (23),
`jl4-service` (19), `jl4` (17), `jl4-lsp` (12), `jl4-mlir` (8), `jl4-proleg` (6), `jl4-query-plan`
(2), `jl4-wasm` (1) and `jl4-repl` (1).

Only two of those are not in `main`'s `cabal.project`:

- **`jl4-proleg`** — added to `cabal.project` by #249, which is therefore built whenever it is
  present. #249's CI is green, so it is covered.
- **`jl4-wasm`** — one file, which is the one this note is about.

So there is **no second instance of this defect in the Haskell layer**. The TypeScript and Nix
surfaces are gated separately by CI and are not covered by this argument.

## Two small discrepancies in #257's body, not in the code

- It says `mlir` keeps **49** files; the rule gives **48**. The difference is
  `jl4-mlir/app/Main.hs`, which `lang-core` carries — so "its 4 source modules + test move here"
  undercounts by one. 48 is correct.
- It says `promissory-note.ep.golden` is re-blessed by **`dmn-export`** later. It is actually
  **`corpus-legal-new` (#234)** that carries the final version. Measured: `lang-core` holds the
  intermediate, `#234` holds `unstable`'s final. The staging is real and intentional; only the
  theme name is wrong.

## State after reconciliation — 19 open PRs

All 2,045 changed files are covered exactly once, with these deliberate exceptions:

| file | PRs | why |
| --- | --- | --- |
| `cabal.project` | 257, 249 | each adds/removes its own one line |
| `jl4-core/jl4-core.cabal` | 257, 250, 236, 232 | spine, line-sliced |
| `jl4/jl4.cabal` | 257, 252, 250, 236, 232 | spine, line-sliced |
| `jl4-service/jl4-service.cabal` | 257, 252 | spine, line-sliced |
| `jl4/tests/Main.hs` | 257, 236, 232 | spine, line-sliced |
| `package-lock.json` | 254, 233 | wizard-housing regenerates it so it installs standalone |
| `promissory-note.ep.golden` | 257, 234 | intentional staging: intermediate, then final |

Nothing else appears in two PRs; nothing in the delta appears in none.
