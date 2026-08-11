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
