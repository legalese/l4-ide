# Single import-boundary CheckEnv merge (as built)

As built on unstable at 73a953821. Source spec: none. Differences from the source spec: not applicable.

## What it does

Nothing changes for users.
Both places that fold an imported, already type-checked module into the importer's checker environment call one function, `unionImportedCheckEnv`, instead of each building a `MkCheckEnv` record by hand.
Before this change the two sites looked different and behaved the same at `-O`: the core path left-biased colliding `entityInfo` entries after a structural `Eq` test, and the LSP path used `assert (t1 == t2)`, which GHC compiles out (commit message of `e1342bf7b`).
The commit reports no behaviour change at `-O1`.

## Where it lives

- `unionImportedCheckEnv`: `jl4-core/src/L4/TypeCheck/Types.hs:1068-1091 @ 73a953821`, with its design comment at `:1040-1067`.
- Core caller: `combineOne` inside `combineResolvedImports`, `jl4-core/src/L4/Import/Resolution.hs:355, 382-410 @ 73a953821` (call at `:409`).
  This path serves `checkWithImports`, i.e. the API and WASM entry points.
- LSP caller: `unionCheckEnv`, `jl4-lsp/src/LSP/L4/Rules.hs:880-881 @ 73a953821`, folded over the dependencies at `:884`.
  This path serves the language server, the `l4` CLI and the golden suite.

## Behaviour and rules (read in code on unstable)

Signature on unstable: `CheckEnv -> Environment -> EntityInfo -> MixfixRegistry -> Set Unique -> CheckEnv`.
The result is built field by field from the accumulator (`accEnv`) and one dependency:

- `moduleUri` is the importer's.
- `environment` is `Map.unionWith List.union`, a set-like union of each name's candidates.
- `entityInfo` is `Map.union`, left-biased, with no equality test.
  The comment's argument: a `Unique` embeds its defining module and each module is checked once per session, so a key that arrives by two import paths (builtins, diamonds) carries identical entries.
- `mixfixRegistry` is `unionMixfixRegistry`.
- `importedImplicitReaders` is the union of the accumulator's set and the dependency's `implicitReaders` (the fifth argument); it is the only section-binder field carried across the boundary.
- Reset to empty: the frame-local by-`SrcRange` maps `functionTypeSigs`, `declTypeSigs`, `declareDeclarations`, `assumeDeclarations`, whose readers only look up nodes of the module being checked.
- Reset to empty: `computedFields`, because it is keyed by `RawName` and a union could conflate same-named records from different modules; the comment puts the cost at error-message quality only.
- Also reset: `cyclicSynonyms`, `sectionBinderNames`, `sectionBinderDecls`, `localBindings`, `sectionStack`, and `inNonexhaustiveDecide = False`, `enclosingObligation = Nothing`, `errorContext = None`, `actionPatternPos = NotInActionPattern`.

Precondition, documented and not checked: the imported `EntityInfo` is already zonked.
`Resolution.hs` zonks it with `applyFinalSubstitution` just before the call (`:390`); `Rules.hs` relies on `TypeCheckResult.entityInfo` being stored zonked (comment at `:877-879`).
The old LSP site copied the importer's `errorContext`; the function sets `None`, which is what `initialCheckEnv` holds anyway (`jl4-core/src/L4/TypeCheck.hs:143, 178-179 @ 73a953821`; `:129, 156-157` on main).

## Where the design comment points

On unstable the comment's last sentence cites "the exhaustiveness design doc".
That is `specs/todo/consider-exhaustiveness-scope-hardening.md`, item "T3b `computedFields` cross-module" under "Still deferred" (`:172-177 @ 73a953821`).
It records the same reasoning, and names re-keying `computedFields` by `Unique` as the real fix.
That file is absent at main `66c30f987`: it arrived with main's #45 (`f0f35ecdc`) and left with #45's revert (`9ec57df0b`, 2026-07-13).
So in this PR the comment points at this extract instead.

## Tests and fixtures that pin it

There is no dedicated test.
The LSP path runs for every `jl4-test` golden whose file has an `IMPORT`.
The core path runs in the `jl4-core-test` specs that call `checkWithImports` on a source with an `IMPORT`: on main, `jl4-core/test/DirectiveRenameSpec.hs:33`; on unstable also `jl4-core/test/LtsMarkingSpec.hs:69 @ 73a953821`, whenever its source imports an embedded library.
The commit reports jl4-test 927/0, jl4-core-test 46/0 and l4-cli-test 20/0 at its own base.

## Later changes

The function reached unstable's first-parent line inside #182, with 4 arguments and the fields above minus the later ones.
Fields added to it later, each by the PR that added the `CheckEnv` field:

- #182's merge text also carries `inNonexhaustiveDecide` (#182's own), `cyclicSynonyms` (#55) and `localBindings` (#50); #183 respelled `localBindings = mempty` as `Set.empty`.
- #344: `sectionBinderNames`.
- #369: `sectionBinderDecls`, `importedImplicitReaders`, and the fifth argument `Set Unique` at both call sites.
- #407: `actionPatternPos`.
- #411: `enclosingObligation`.
