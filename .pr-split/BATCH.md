## Part of a 15-PR merge batch — measured by building and testing, not inferred

**This PR cannot land on its own, and neither can the other fourteen below.** They go into the merge
queue as one batch, or land in immediate succession accepting that `main` is broken in between.

| PR | theme | | PR | theme | | PR | theme |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **#245** | `lang-syntax-typecheck` | | **#252** | `service-cli` | | **#247** | `mlir` |
| **#241** | `lang-eval-ledger` | | **#236** | `dmn-export` | | **#230** | `actus-archive` |
| **#242** | `lang-imports-stdlib` | | **#232** | `bpmn-export` | | **#244** | `lang-sets` † |
| **#243** | `lang-printer` | | **#250** | `openfisca-export` | | **#234** | `corpus-legal-new` † |
| **#240** | `ladder-viz` | | **#246** | `lsp` | | **#235** | `corpus-regcf` † |

† The three marked themes are not needed to **compile** — they are needed to make the **golden suite
pass**. The distinction matters because the merge queue's required check is *Haskell Build **&
Test***, so the set that can actually merge is all fifteen. Twelve is only the build-green floor.

### Why the split cannot separate them

The partition is by file, but several changes are atomic at the *type* level.
`lang-syntax-typecheck` reshapes types that modules in ten other themes construct or pattern-match:
it removes the `Expr` constructor `Exponent` (upstream #83), widens `MkAssume` 4→5, `MkTypedName`
4→5 and `MkOptionallyTypedName` 3→4 (the `TYPICALLY` default), adds `Record` / `ReadCell` /
`RecallMode` and `unqualifiedNameToText`, and adds strict fields to `MkCheckState` and `MkCheckEnv`.
`lang-eval-ledger` widens `MkEvalDirectiveResult` 3→4; `service-cli` adds a field to
`FunctionSchema.Parameter` and owns the `L4.Dmn.*` / `L4.Bpmn.*` call sites in the CLI.

The dependency runs **both ways**, which is what makes it unbreakable at file granularity. Land
`lang-syntax-typecheck` alone and other themes' modules — still at `main`'s revision — name a
constructor that is gone or pass the wrong number of arguments. Land any of those alone and its
updated module meets `main`'s unchanged types. Neither direction compiles.

### The measurement

Each row is `git merge` of the named slices onto `origin/main`, then `cabal build all` under GHC
9.10.3. The `jl4/tests/Main.hs` conflict resolves to the union import `(lookupEnv, setEnv)`, and the
`.cabal` conflicts to the union of added lines.

| slices under test | result |
| --- | --- |
| the five previously claimed here — 245, 241, 243, 252, 247 | **fails to build**, 4 errors |
| + 242, 240, 246 (eight) | **fails to build**, 1 error |
| + 230 (nine) | **fails to build**, 9 errors |
| nine, less 246 | **fails to build**, 5 errors |
| twelve, less 247 | **fails to build**, 4 errors |
| **twelve** | **builds**; 6 of 7 suites pass, `jl4-test` **fails 39 of 2508** |
| **fifteen** (+ 244, 234, 235) | **builds**; `jl4-test` **2568 examples, 0 failures** |

The first error of each failing build, verbatim, and the slice that supplies the fix:

```
src/L4/Import/Resolution.hs:341:7: error: [GHC-95909]
    • Constructor ‘TypeCheck.MkCheckState’ does not have the required strict field(s):
        constBodies :: Map Unique (Expr Resolved)
        sectionPaths :: Map Unique [NonEmpty Text]
                                                        -> lang-imports-stdlib  #242

src/L4/Viz/Ladder.hs:310:18: error: [GHC-27346]
    • The data constructor ‘MkOptionallyTypedName’ should have 4 arguments, but has been given 3
                                                        -> ladder-viz           #240

src/L4/ACTUS/FeatureExtractor.hs:519:12: error: [GHC-27346]
    • The data constructor ‘MkTypedName’ should have 5 arguments, but has been given 4
                                                        -> actus-archive        #230

src/LSP/L4/Inspector.hs:141:43: error: [GHC-27346]
    • The data constructor ‘EL.MkEvalDirectiveResult’ should have 4 arguments, but has been given 3
                                                        -> lsp                  #246

src/L4/MLIR/Schema.hs:675:7: error: [GHC-76037]
    Not in scope: data constructor ‘Exponent’
                                                        -> mlir                 #247

app/L4/Cli/Export.hs:74:1: error: [GHC-87110]
    Could not load module ‘L4.Bpmn.Emit’.
                                                        -> dmn-export           #236
                                                           bpmn-export          #232
                                                           openfisca-export     #250
```

And the 39 golden failures at twelve, which is what adds the last three:

| failures | tests | supplied by |
| --- | --- | --- |
| 8 | `ok/mixfix-{basic,cross-module-*,multiline,over}.l4` — parses/exactprints | `lang-sets` **#244** |
| 3 | `legal/{promissory-note,ceo-performance-award}.l4` — exactprint, json schema | `corpus-legal-new` **#234** |
| 28 | DMN 1.3 export and BPMN export over *the Reg CF corpus* (§15, §16, PROCESS-TRACK §8.3) | `corpus-regcf` **#235** |

Three of these could not have been found by reading:

- **`actus-archive` (#230) is a batch member.** `jl4-actus-analyzer` lives on `main`, is deleted by
  `unstable`, and its `FeatureExtractor.hs` pattern-matches `MkTypedName`. It is in `main`'s
  `cabal.project`, so `cabal build all` compiles it. Invisible to CI on any single PR, because the
  build dies inside `jl4-core` long before reaching it.
- **The three corpus themes are load-bearing.** Their `.l4` files are the input the exporter tests
  read. They are also exactly the PRs whose own CI reports green without running a single test —
  the `haskell` paths-filter in `pr-checks.yml` does not match `jl4/examples/**`.
- **The import-level check cannot see any of this.** `depcheck.mjs` resolves module imports, and
  every type above lives in a module `main` already has. An earlier revision of this section named
  five PRs on the strength of the `Exponent` constructor alone.

### What is *not* in the batch

Everything else in the `aug2026` set is independent or a one-way dependent that can follow. In
particular `tests-cli` (#253) needs this batch for its 47 fixtures, and `ci-build` (#233) must merge
**last** — its new jobs gate code that arrives with the feature PRs.
