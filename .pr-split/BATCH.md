## Part of a 12-PR merge batch — measured by building, not inferred

**This PR cannot land on its own, and neither can the other eleven below.** `main` does not build
with any proper subset of them that was tried. They go into the merge queue as one batch, or land in
immediate succession accepting that `main` is broken in between.

| PR | theme | | PR | theme |
| --- | --- | --- | --- | --- |
| **#245** | `lang-syntax-typecheck` | | **#236** | `dmn-export` |
| **#241** | `lang-eval-ledger` | | **#232** | `bpmn-export` |
| **#242** | `lang-imports-stdlib` | | **#250** | `openfisca-export` |
| **#243** | `lang-printer` | | **#246** | `lsp` |
| **#240** | `ladder-viz` | | **#247** | `mlir` |
| **#252** | `service-cli` | | **#230** | `actus-archive` |

### Why the split cannot separate them

The partition is by file, but several of the changes are atomic at the *type* level.
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

Each row is `git merge` of the named slices onto `origin/main` followed by `cabal build all`, with
GHC 9.10.3. The conflict on `jl4/tests/Main.hs` is resolved to the union import
`(lookupEnv, setEnv)`, and the `.cabal` conflicts to the union of the added lines.

| slices under test | result |
| --- | --- |
| the five previously claimed here — 245, 241, 243, 252, 247 | **fails**, 4 errors |
| + 242, 240, 246 (eight) | **fails**, 1 error |
| + 230 (nine) | **fails**, 9 errors |
| nine, less 246 | **fails**, 5 errors |
| twelve, less 247 | **fails** |
| **all twelve** | **`cabal build all` exits 0** |

The first error of each failing run, verbatim, and the slice that supplies the fix:

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

app/L4/Cli/Export.hs:74:1: error: [GHC-87110]
    Could not load module ‘L4.Bpmn.Emit’.
                                                        -> dmn-export           #236
                                                           bpmn-export          #232
                                                           openfisca-export     #250
```

Two of these are worth calling out because no amount of reading would have found them:

- **`actus-archive` (#230) is a batch member.** `jl4-actus-analyzer` lives on `main`, is deleted by
  `unstable`, and its `FeatureExtractor.hs` pattern-matches `MkTypedName`. It is in `main`'s
  `cabal.project`, so `cabal build all` compiles it; the fix is that #230 removes the package. This
  is invisible to CI on any single PR, because the build dies inside `jl4-core` long before it
  reaches `jl4-actus-analyzer`.
- **The import-level dependency check cannot see any of this.** `depcheck.mjs` resolves module
  imports, and every type above lives in a module `main` already has. An earlier revision of this
  section named five PRs on the strength of the `Exponent` constructor alone; building shows the
  interlock is twelve.

### What is *not* in the batch

Everything else in the `aug2026` set is either independent or a one-way dependent that can follow.
In particular `tests-cli` (#253) needs this batch plus `corpus-regcf` (#235) for its fixtures, and
`ci-build` (#233) must merge **last** — its new jobs gate code that arrives with the feature PRs.
