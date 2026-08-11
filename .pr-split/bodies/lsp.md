# fix(lsp): one import resolver, an unforgeable embedded-stdlib URI, and the first jl4-lsp test suite

**What this adds**

This is the language-server half of the `IMPORT` story: how `jl4-lsp` (and therefore the `l4`
CLI, the VS Code extension and the web IDE, all of which drive the same Shake build) decides
_which file_ a bare `IMPORT prelude` actually loads. Before this change there were two separate
copies of that logic — one inside `GetMixfixRegistry`, one inside `GetImports` — that could drift
into loading different sources for the same module name; the stdlib compiled into the binary was
registered mid-build at a `file:`-shaped URI that a speculative probe could forge; and a
machine-global `~/.local/share/jl4/libraries` copy silently outranked it. After this PR there is a
single shared resolver with a documented precedence order, the embedded stdlib lives under a
`jl4-embedded:` scheme no file path can produce, and when several differing copies of one module
are visible the server names them all and says which one it chose. It also adds the first
`jl4-lsp` test suite, normalises inference variables in hover types, stops warnings from failing a
typecheck, and refreshes the ladder's module snapshot on auto-refresh.

**Why**

Four distinct incidents, all filed upstream. **smucclaw/l4-ide#906**: a transitively imported
embedded library vanished from the typecheck environment, so `Days in month` came out of scope in
`actus-library-test.l4` — because a probe on a not-yet-registered URI memoized "missing" and
`addVirtualFile` does not invalidate an already-memoized key. **The shadow class** (PR #134's
`LIBRARY-RESOLUTION-SHADOW-SPEC`): an ambient XDG symlink into another checkout overrode the
stdlib the binary was built with, costing two debugging sessions to "my prelude edit didn't take
effect". **smucclaw/l4-ide#313**: hover over an un-annotated lambda parameter showed the raw
inference-variable id `x10` instead of a clean `a`. **smucclaw/l4-ide#557**: after adding a
`DECIDE`, the ladder's `+`/unfold affordance did not appear until you clicked **Visualize** again
— documented at the time only as a workaround in a README.

## What's in it

Eleven files: **7 Haskell modules** under `jl4-lsp`, **3 new test files**, and **1 golden**
(+745 / −218 lines).

### Import resolution, rebuilt (`src/LSP/L4/Rules.hs`, the bulk of the diff)

- **One resolver.** `resolveImportShared` is now the single code path used by both
  `GetMixfixRegistry` (parser-hint resolution) and `GetImports` (typecheck-dependency
  resolution). Two rules can no longer parse a module against source A while typechecking it
  against source B (`LIBRARY-RESOLUTION-SHADOW-SPEC` §3.3), and both emit identical logs.
- **Precedence flip (Option B′).** `resolveLibraryFromFilesystem` becomes `resolveLibrary`, whose
  candidate list is explicit and ordered:
  `JL4_LIBRARY_PATH → project root → importer-relative → EMBEDDED → XDG → VSCode bundle`.
  Project-scoped overrides keep working; ambient machine-global tiers can now only supply modules
  the embed does not carry. With `JL4_LIBRARY_PATH` set the embedded tier is not consulted at all.
- **A `LibraryCandidate` type** (`FileCandidate label path` | `EmbeddedCandidate`) and a
  `LibraryResolution` that records the winner _with its ordinal_, **every** candidate that exists
  (not just the first), the full ordered probe list, and whether the env var was set. Keeping the
  losers is what makes the shadow warning possible.
- **The shadow warning (Option E).** When two or more copies of a module are visible **and their
  bytes differ**, one `Warning`-level line names each copy — symlinks dereferenced to their real
  target via `canonicalizePath` — marks `[chosen]` / `[shadowed]`, and says how to override.
  Byte-identical copies stay silent. Warned once per distinct configuration per session, via an
  `IORef (Set (String, [Text]))` created in `jl4Rules`.
- **Log gating.** The candidate table (Debug) and the shadow warning run only when
  `JL4_LIBRARY_PATH` is unset — the golden suites always pin it, and their captured logs must stay
  machine-independent, while the ambient state this reporting exists to expose is precisely the
  machine-dependent part.
- **The not-found diagnostic now mentions the embedded tier.** A new `EmbedStatus`
  (`EmbedSkipped` / `EmbedEmpty` / `EmbedMissing n`) is carried separately from the path list,
  because the embed has no path — so the one tier that can be silently empty used to be the one
  tier the error could not name. `EmbedEmpty` prints a build-defect explanation pointing at
  `data-files` and `cabal check`. The path list is also `nub`bed: the CLI sets the project root to
  the importing file's own directory, so root and importer-relative coincided and every path was
  printed twice.
- **`unionImportedCheckEnv`.** The hand-rolled `unionCheckEnv` in `GetTypeCheckedModule` is
  replaced by jl4-core's shared merge, so the LSP and the pure resolver stop drifting.
- **`SWarn` is non-fatal.** The partition changes from `(== SInfo)` to `(/= SError)`, so a module
  whose typecheck emits only warnings (e.g. `CONSIDER` exhaustiveness) still yields
  `SuccessfulTypeCheck` and still evaluates its directives. All diagnostics are published to the
  editor either way — the partition only decides what blocks downstream rules.
- **New resolve-warning renderings** for `@ref` (`RefUnattached`, `RefNoLocation`) and fixity
  annotations (`FixityAnnotationMisplaced`, `FixityAnnotationNoLocation`), with source ranges, so
  a misplaced `@infixl` is reported instead of silently ignored.

### The embedded stdlib gets a real address (`src/LSP/Core/Shake.hs`)

- `embeddedLibraryUri :: Text -> NormalizedUri` mints `jl4-embedded:/<name>.l4` — a scheme no file
  path can produce. The old `./<name>.l4` key was forgeable twice over: `l4 check main.l4` makes
  `rootDirectory` `"."`, so the root candidate for `prelude` _was_ the embedded key; and an
  embedded importer's own URI was `file://<name>.l4`, whose `takeDirectory` is `"."`, so its
  dependencies' sibling candidates hit the same keys — one module name bound to two sources in one
  build.
- `embeddedLibraryVfs` is a pure map of every embedded library keyed by that URI, consulted as a
  fallback by `getVirtualFile`. A built-in is readable from the moment the build starts rather
  than from whenever some rule happened to register it, which is what closes #906's cache
  poisoning. The live VFS is still checked first, and the two key spaces are disjoint by
  construction, so the fallback can never shadow a real or user-edited file.
- `addVirtualFileUri` generalises `addVirtualFile` to non-file-path sources.
- Resolution no longer writes to the VFS on an embedded win — the mid-rule mutation whose
  ordering-dependence caused #906 is gone.

### Hover, ladder, oneshot, tokens

- `src/LSP/L4/Actions.hs`: hover renders types through `L4.Print.prettyTypeForDisplay` instead of
  raw `prettyLayout`, normalising residual inference variables to `a`, `b`, … and matching the
  deployed schema's `returnType` (#313). `updateVizConfig` is promoted from a `where`-binding to a
  top-level function (so it is unit-testable) and now also refreshes `#module'` from the current
  typecheck result, which is what `Ladder.collectDefsForInlining` reads for `canInline` (#557).
- `src/LSP/L4/Oneshot.hs`: new `oneshotL4ActionWithDiags` returns every diagnostic published to
  the Shake store across the whole import closure, not just the entry file — needed by callers
  that must fail on a structural error (an import cycle) whose diagnostic is attached to a
  transitively imported module.
- `src/LSP/L4/SemanticTokens.hs`: no-token instances for `RecallMode` and `Bool`, so the new
  `RECALL ALL` mode and the `RECORD`/`COMMIT` `isOfficial` flag do not break highlighting.
- `src/LSP/L4/Inspector.hs`, `app/LSP/L4/Handlers.hs`: constructor-arity follow-through for the
  4th fields added upstream to `MkEvalDirectiveResult` (ledger), `MkAssume` and
  `MkOptionallyTypedName` (TYPICALLY defaults), plus `parameterDefault` in the exported-function
  summary.

### The first `jl4-lsp` test suite

- `test/Spec.hs` — one-line `hspec-discover` shim.
- `test/LibraryResolutionSpec.hs` (171 lines) — 9 table-driven cases over `resolveLibrary`, each in
  a fresh sandbox with `XDG_DATA_HOME` redirected and `JL4_LIBRARY_PATH` saved/restored: the
  candidate order itself; env wins and disables the embed; env set but empty still lets ambient
  tiers resolve; project root beats the embed; importer-relative beats the embed; the embed beats
  XDG (the §3.1 incident) while the shadowed copy is still reported as existing; XDG still serves
  a module the embed does not carry; not-found reports 4 searched filesystem paths; a symlinked
  XDG entry canonicalizes to its real target.
- `test/HoverDisplaySpec.hs` (75 lines) — feeds `infoToHover` the exact `Type'` from the #313 bug
  report (`FUNCTION FROM x10 TO x10`) and asserts the markdown reads `FUNCTION FROM a TO a` with
  no `x10`.

### Golden

- `jl4/examples/lsp/hover/tests/desc-hover.hover.golden` — four lines lose a leading space in the
  `@desc` text. See **Independence**: this is not caused by any code in this PR.

## Evidence

Quoted from the source PRs.

- **#148** (`fix(lsp): give embedded libraries a URI scheme no file path can forge (#906)`):
  green in **both** regimes, with and without `JL4_LIBRARY_PATH` — `jl4:jl4-test` 1505 examples /
  0 failures, `jl4:l4-cli-test` 64 / 0, `jl4-service:jl4-service-test` 293 / 0. Four new
  `l4-cli-test` cases. The PR also refutes #906's own hypothesis mechanically: the two URI
  constructions were **identical** (`hash A = NormalizedUri 2647415761475516628 "file://daydate.l4"`,
  same for B), so the defect was a collision, not a mismatch. Before/after transcripts show
  `l4 check jl4/examples/ok/actus-library-test.l4` going from "could not find a definition for
  `Days in month`" to `Check succeeded. EXIT=0`.
- **#134** (`Library resolution: embedded stdlib outranks ambient XDG/bundle copies (B′)`):
  `jl4-lsp-test` **10/10** (the new `LibraryResolutionSpec`), `l4-cli-test` **60/60** with 5 new
  black-box regressions, `jl4-test` **1471/1471** (two tc-fail goldens re-blessed because the
  resolution-log block now appears for both resolver passes — the parity feature),
  `jl4-core-test` 219/219, `jl4-service-test` 293/293, `jl4-mlir-test` 19/19, `doc/test-docs.sh`
  green (858 links, 81 L4 files, 0 orphans). Plus a live-fire run on the real incident
  configuration: "embed wins, warning names the symlink's real target".
- **#93** (hover, #313): new `jl4-lsp:test:jl4-lsp-test` 1 example / 0 failures; `jl4-test`
  1079 / 0. Verified by reverting the one-line renderer swap — the test then fails with
  ``predicate failed on: "```\nFUNCTION FROM x10 TO x10\n```\n"`` and passes once restored.
- **#88** (ladder auto-refresh, #557): full suite 1080 examples / 0 failures; the new regression
  is **red before** the one-line fix and **green after**.
- **#82** (`SWarn` non-fatal): `jl4-core-test` 150 / 0, `jl4-test` 1071 / 0, `l4-cli-test` 54 / 0.
- **#64** (VFS seeding): the minimal repro and the previously failing golden
  `jl4/examples/ok/actus-library-test.l4` both type-check cleanly; full `cabal test all` — all 7
  suites green, 0 failures.
- **#167** (embedded-stdlib sdist): the jl4-core sdist goes from **0 → 22** `.l4` files;
  "Tests: 1826 + 311 + 269 + 96 examples, 0 failures."
- **#182 / #183 / #189** each re-ran `jl4-lsp-test` at **10 examples, 0 failures** after the
  oracle cherry-pick, Phase 4, and the `main`→`unstable` merge respectively.

## Independence

**This PR does not compile on its own.** It is the language-server surface of work whose types
live in `jl4-core`, and it needs those siblings first:

- **lang-syntax-typecheck** — `TypeCheck.unionImportedCheckEnv` and the `CheckState` fields
  `constBodies` / `sectionPaths`; the 4th field on `MkAssume` and `MkOptionallyTypedName`
  (TYPICALLY defaults); and the `Resolve` warning constructors `RefUnattached`, `RefNoLocation`,
  `FixityAnnotationMisplaced`, `FixityAnnotationNoLocation` in `L4/Parser/ResolveAnnotation.hs`.
  None of these exist on `main`.
- **lang-eval-ledger** — the 4th (`ledger`) field on `EL.MkEvalDirectiveResult`, and the
  `RecallMode` type / `Bool` `isOfficial` flag the two new `ToSemTokens` instances exist to
  absorb.
- **service-cli** — `FSchema.parameterDefault`. Also `jl4-core/src/L4/API/EmbeddedLibraries.hs`,
  whose TH `fail` guard is what makes this PR's `EmbedEmpty` branch unreachable-in-practice; the
  branch itself is written to be harmless if that guard has not landed.
- **lang-imports-stdlib** — `L4/Import/Resolution.hs` is the other consumer of
  `unionImportedCheckEnv`; landing only one of the two leaves the drift this PR removes.

Two things it does **not** need: `L4.Print.prettyTypeForDisplay` (already on `main`) and
`VizConfig.module'` (already on `main`), so the hover and ladder fixes are self-contained given
the constructor-arity siblings above.

**Two honest caveats a reviewer should not have to discover:**

1. **The one golden here is not ours.** `desc-hover.hover.golden` changed because `getDesc` in
   `L4.Syntax` learned to trim — the lexer keeps the annotation line verbatim for exact printing,
   so every `@desc` was reaching JSON Schema, deployed function schemas and hovers with a leading
   space. That change is in **lang-syntax-typecheck** (commit `a9caf2f6`). Landing this golden
   without it turns the hover golden red; landing that fix without this golden does the same. They
   must go together, in whichever direction the assembler prefers.
2. **The cabal stanza is in no theme's manifest.** `jl4-lsp/jl4-lsp.cabal` gains the
   `test-suite jl4-lsp-test` block (`hspec-discover`, `other-modules: HoverDisplaySpec,
   LibraryResolutionSpec`), and that file appears in no theme's `.files` list — along with
   `cabal.project`, `jl4/jl4.cabal`, `jl4-core/jl4-core.cabal`, `jl4-service/jl4-service.cabal`
   and `jl4/tests/Main.hs`. Without it the three new test files are dead code that never compiles
   and `jl4-lsp-test` does not exist, so every "10 examples, 0 failures" above is unverifiable.

## Risk if rejected

Dropping this leaves the editor and CLI with two divergent import resolvers, an embedded stdlib
addressed at a forgeable `file:` path — so `l4 check main.l4` from a project directory silently
prefers the built-in `prelude` over the project's own — and no warning when a stray XDG symlink
shadows the stdlib, which is the exact configuration that already cost two debugging sessions.
smucclaw/l4-ide#906, #313 and #557 all regress, warnings become fatal again (blocking evaluation,
schema generation and deploys for any module with a non-exhaustive `CONSIDER`), and `jl4-lsp`
returns to having no test suite at all.

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

Folded into this PR, from the theme manifest:

- **#128** — `feat(fixity): @infixl/@infixr/@infix declarations for binary identifier operators`
  (contributes the `FixityAnnotationMisplaced` / `FixityAnnotationNoLocation` renderings in
  `Rules.hs`, from its adversarial-review commit `8ba51c1d`)
- **#134** — `Library resolution: embedded stdlib outranks ambient XDG/bundle copies (B′) + shadow warning + dev/prod docs`
- **#167** — `fix(build): restore the embedded stdlib, and make its absence a build error`
  (contributes `EmbedStatus` and the deduplicated not-found path list)
- **#182** — `Phase 0.5: land the exhaustiveness oracle on unstable`
  (contributes `unionImportedCheckEnv` at the LSP merge site)
- **#183** — `DMN Phase 4: un-lifting analysis + totality + R6 population filter`
- **#189** — `Merge main into unstable: absorb docs overhaul, VS Code MCP tooling, batch CSV fix — oracle preserved`
  (audited that `main`'s revert of PR #45 did not re-inline `unionCheckEnv` here)

Earlier `unstable` PRs whose commits these files still carry, and whose measurements are quoted
above:

- **#48** — `feat(jl4-core): attach @ref annotations to AST nodes` (its finding 2, "warnings
  discarded", is what wired `RefUnattached` / `RefNoLocation` into LSP diagnostics here)
- **#64** — `fix(shake): seed embedded libraries into the VFS to prevent cache poisoning`
- **#82** — `fix(lsp): make SWarn non-fatal to typecheck success`
- **#88** — `fix(viz): ladder auto-refresh recomputes canInline against the fresh module (#557)`
- **#93** — `fix(lsp): normalise inference variables in hover types (#313)`
- **#148** — `fix(lsp): give embedded libraries a URI scheme no file path can forge (#906)`
