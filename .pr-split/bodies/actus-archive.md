# chore(actus): remove jl4-actus-analyzer; preserved at branch archive/actus-analyzer

**What this adds.** This is a subtraction, not an addition: it deletes the whole
`jl4-actus-analyzer/` package — a standalone static analyzer that read FIBO/ACTUS RDF ontologies
and classified an L4 contract encoding by ACTUS contract type (FXOUT, SWAPS, OPTNS, PAM, FUTUR,
MasterAgreement) and by FIBO ontology class, emitting Markdown, JSON or RDF/Turtle. After this
change the tree no longer builds the `jl4-actus` executable and no longer carries its library,
its ontology cache, or its six hspec suites. Nothing else in the repo loses a capability: the
package is a leaf, so what the rest of the tree can do is unchanged, and the build has one fewer
target to resolve — along with `rdf4h`, which after this change is referenced nowhere else in the
tree.

**Why.** The analyzer was written for a demo that is no longer active. Its commit message and PR
both make the case on weight: ~6.2k LOC that nothing `build-depends` on, that is not wired into
nix, into CI, or into any `hie.yaml`, and that no non-ACTUS `.l4` file reaches. Carrying it means
every contributor pays its dependency-resolution and compile cost for code no one runs. Rather
than let it rot in place, it was pushed to a named archive ref so it can be revived if and when
there is a plug-in architecture to host it as an optional extension. The upstream commits do not
cite a `smucclaw/l4-ide` issue number for this work; the only issue-shaped reference in the
history is to the fork-side PR (`legalese/l4-ide#63`) and its follow-up.

## What's in it

**The package deletion** — 27 files, 6,669 lines, all under `jl4-actus-analyzer/`:

- **16 library modules** under `src/L4/ACTUS/`:
  - `Analyzer.hs` — the top-level `analyzeFile` entry point and config
  - `FeatureExtractor.hs` — the largest module (622 lines); pulls domain indicators, deontic
    patterns, state transitions and type patterns out of the L4 AST
  - `Ontology/{Types,Loader,Cache,Query}.hs` — RDF loading via `rdf4h` plus a binary on-disk cache
  - `Matching/{Rules,Scorer,ACTUS}.hs` — the weighted pattern rules, confidence scoring, and the
    ACTUS→FIBO class table
  - `Qualia/{ObligationGraph,Essence,Archetypes,Hybrid}.hs` — the later "qualia" classifier layer
    that consumed `L4.StateGraph` from jl4-core
  - `Report/{JSON,RDF,Markdown}.hs` — the three output formats
- **1 executable**, `app/Main.hs` — the `jl4-actus` CLI (`--json`, `--rdf`, `--fibo`, `--no-cache`,
  `--rebuild-cache`, `--min-confidence`)
- **6 hspec suites** under `test/` (`ArchetypesSpec`, `EssenceSpec`, `FeatureExtractorSpec`,
  `HybridSpec`, `MatchingSpec`, `ObligationGraphSpec`), plus the one-line `test/Spec.hs`
  `hspec-discover` shim — note the shim is not in this theme's file manifest but must be deleted
  with the rest, or the directory is left with an orphan
- **package metadata**: `jl4-actus-analyzer.cabal`, `LICENSE` (MIT), and the package's own 363-line
  `README.md`

**Deliberately kept — this PR does not touch any of it.** The ACTUS *language* work is a separate
thing from the analyzer and stays:

- `jl4-core/libraries/actus{,-core,-daycount,-events,-schedule,-state,-terms}.l4` and their goldens
- `jl4/examples/ok/actus-library-test.l4`
- `doc/reference/libraries/actus.md`
- the ACTUS/QUALIA specs under `specs/`
- `holdings.l4`, an independent cap-table library that is only "inspired by ACTUS"

**Recoverability.** The package is preserved on `origin` at branch **`archive/actus-analyzer`** and
tag **`archive/actus-analyzer-v0.1.0`**, both pinned at pre-removal commit `fbc90947`. Both refs
are present on the remote today.

## Evidence

Quoted from PR `legalese/l4-ide#63`:

> `cabal build all --dry-run` resolves all eight remaining packages cleanly after removal.

and its safety argument, verbatim:

> `jl4-actus-analyzer` is a **leaf package**:
>
> - nothing `build-depends` on it
> - not wired into nix, CI, or any `hie.yaml`
> - no non-ACTUS `.l4` file imports the `actus-*.l4` libraries

Size, read off `git diff --stat origin/main...origin/unstable -- jl4-actus-analyzer/`: 27 files
changed, 6,669 deletions. The PR itself reports 17 additions / 6,675 deletions over 30 files, but
that count spans commits belonging to other themes that happened to ride the same branch (a webview
sidebar fix and a tutorial URL edit) — only the 27-file, 6,669-line figure is this theme's.

No performance, coverage or agreement numbers were claimed, because none apply to a deletion.

## Independence

Not standalone. This PR deletes a directory that three files outside its manifest still point at,
and those three files belong to sibling themes:

- **`cabal.project`** — resolved: **this PR carries its own one-line deletion** of
  `./jl4-actus-analyzer`. The file is not owned by any single theme; the proleg PR separately adds
  its own `./jl4-proleg` line. Neither PR can leave `cabal build all` pointing at a directory that
  is not there.
  This is not speculation: it is exactly what happened on `unstable`. PR #63 merged with its
  `cabal.project` edit left uncommitted, and commit `f2f646fc` (`fix(#63): remove dangling
  jl4-actus-analyzer refs from cabal.project/README/AGENTS`) had to repair it the next day.
  **The safest resolution is for this PR to carry the one-line `cabal.project` deletion itself**;
  failing that, it must not merge before proleg.
- **`README.md`** and **`AGENTS.md`** each carry a package-table row for `jl4-actus-analyzer`. Both
  files are owned by the **agent-tooling** theme. A stale row is cosmetic, not a build break, but
  it makes the tables lie until that sibling lands.
- **`specs/todo/QUALIA-BASED-CONTRACT-CLASSIFICATION-SPEC.md`** is the spec that the archived
  `Qualia/*.hs` modules implement. On `unstable` it gained an archive note pointing at the branch
  and tag, and was later moved to `specs/done/`. Those edits are owned by the **specs** theme. Per
  §4 of `CLAUDE.md` ("a decision is recorded in its owning document in the same PR"), that pointer
  is what stops a later reader from acting on a spec whose implementation has silently vanished —
  so specs should land with or shortly after this one.

It needs nothing from any other theme in the *other* direction: no sibling's code, goldens, or CI
config depends on the deleted package. It also does not conflict with **lang-imports-stdlib**,
which touches `jl4-core/libraries/actus-schedule.l4` — a different, retained artifact.

## Risk if rejected

Dropping this leaves ~6.7k lines of unbuilt, untested demo code in `main`, with `rdf4h` — a
dependency nothing else in the tree uses — still on the critical path of `cabal build all`, and
leaves `main` and `unstable` diverging on a whole package directory, which will keep producing
conflicts in
`cabal.project`, `README.md` and `AGENTS.md` for as long as the divergence lasts. Nothing breaks
functionally; the cost is carrying weight and merge friction indefinitely.

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


## Provenance

- **legalese/l4-ide#63** — *chore: remove jl4-actus-analyzer from main (archived)*, merged
  2026-07-06 into `unstable`. Substantive commits taken from it here:
  - `62d0fd8b` — `chore: remove jl4-actus-analyzer package from main`
  - `9c474726` — `docs: add archive pointer to Qualia classification spec` (this hunk belongs to
    the **specs** theme, listed for completeness)
- Follow-up on `unstable`, not part of PR #63: `f2f646fc` — `fix(#63): remove dangling
  jl4-actus-analyzer refs from cabal.project/README/AGENTS`. Its `cabal.project` hunk is the one
  called out under Independence above.

Preserved refs on `origin`: branch `archive/actus-analyzer`, tag `archive/actus-analyzer-v0.1.0`,
both at `fbc90947`.
