# Type checker soundness: unification and directive ambiguity (as built)

As built on unstable at 73a953821. Line numbers are in this PR's tree (main plus this change) unless marked. Source spec: none. Differences from the source spec: not applicable.

Scope: PR #55 (`e6975cd9b9`, `fix/unify-sibling-rebinding`) and PR #56 (`f16e0ad667`, `fix/tc-ambiguity-crash`).
Code comments and fixture headers from #56 cite the label "T4", and #55's first commit message cites "T1"; both labels are defined in §7 of `REVIEW-PART1-CODEBASE-MAP.md` on unstable, a root file that reaches unstable with #59 and is not on main.
No spec under `specs/` or page under `doc/` describes either fix (searched on main).

## What it does

- #55: unification no longer accepts ill-typed programs or loops.
  An inference variable that occurs twice in one type (`Pair OF a, a` against `Pair OF STRING, NUMBER`) could be silently rebound mid-unification; swapped arguments could build a cyclic substitution and hang; a type synonym that refers to itself sent expansion into an infinite loop.
- #56: an ambiguous but well-typed expression under `#ASSERT` or `TIMEZONE IS` is reported as an ambiguity diagnostic instead of crashing the checker with `internal error: expected unique result, got several`.

Measured 2026-10-12 with `l4 check` on the six fixtures below, once with an `l4` built from main without this change (`00298eb60`) and once with this PR's build, each under a 4 GiB memory cap and a 20 s timeout:

| fixture                                     | main without this change                              | with this change                                        |
| ------------------------------------------- | ----------------------------------------------------- | ------------------------------------------------------- |
| `ok/unify-swapped-pair-args.l4`             | killed by the cap at 4.08 GiB before the timeout      | `Check succeeded.`                                      |
| `not-ok/tc/unify-sibling-rebind.l4`         | `Check succeeded.` (the ill-typed module is accepted) | two type errors: the definition is a STRING, not NUMBER |
| `not-ok/tc/type-synonym-cycle.l4`           | killed by the cap at 4.25 GiB before the timeout      | `Circular dependency detected between type synonyms:`   |
| `not-ok/tc/assert-directive-ambiguity.l4`   | `internal error: expected unique result, got several` | `There are multiple definitions for the identifier`     |
| `not-ok/tc/timezone-directive-ambiguity.l4` | the same internal error                               | the same ambiguity message                              |
| `not-ok/tc/timezone-mixed-ambiguity.l4`     | the same internal error                               | the same ambiguity message                              |

So each fixture fails on main for the reason its header gives, and passes with the change.

## Where it lives

- `jl4-core/src/L4/TypeCheck/Unify.hs`: `synonymExpansionFuel = 1000` (`:39-40`), `unify`/`unifyFuel` (`:88-95`), `unify'` (`:100-111`), `plainTypeEq` (`:118-129`), `expandAndUnify` (`:137-153`), `unifyBase` (`:161-174`), `bind` and its precondition comment (`:184-193`).
- `jl4-core/src/L4/Desugar.hs`: `detectTypeSynonymCycles` (`:456`) and `synonymsInSection` (`:489`).
- `jl4-core/src/L4/TypeCheck.hs`:
  - cycle wiring in `doCheckProgramWithDependencies`: `synonymCycles` (`:170`), the `CyclicTypeSynonyms` errors (`:167-168`), `cyclicSynonyms` in the `CheckEnv` (`:136, 173`);
  - quarantine in `inferTypeNameAndSynonym` (`:876-890`);
  - fuelled synonym chase in `matchFunTy` (`:2004-2061`, the fuel is set at `:2012`);
  - `runCheckUnique` and its INVARIANT comment (`:342-362`);
  - `prune` on `inferDirective (Assert …)` (`:475-479`) and on `inferTopDecl (Timezone …)`, which also gains an `errorContext` (`:530-536`);
  - the strict `error` for the projection case (`:1397-1405`);
  - `prettyCheckError (CyclicTypeSynonyms …)` (`:3302-3309`).
- `jl4-core/src/L4/TypeCheck/Types.hs`: `CyclicTypeSynonyms [Name]` (`:95`); `CheckEnv.cyclicSynonyms` (`:380`), carried by `extendEnv` (`:976`) and reset to empty at an import boundary in `unionImportedCheckEnv` (`:432`).
- The positional `MkCheckEnv` pattern in `withExtraMixfix` gains a field (`TypeCheck.hs:225-227`; 12 fields).

## Behaviour and rules

- **Substitute on every descent.** `unifyFuel` applies the substitution to both sides at entry, and `unifyBase` recurses through `unifyFuel`, so later siblings see bindings made by earlier ones.
  Every inference variable reaching `bind` is therefore unbound, and `bind`'s `Map.insert` never overwrites a live binding.
- **Short-circuit.** `plainTypeEq` compares types structurally, ignoring annotations and argument names, and returns success before any synonym is expanded.
- **Fuel.** Each synonym expansion costs one unit from a budget of 1000 that is passed down, never reset, through constructor children; at zero the two types are treated as not unifiable.
  `matchFunTy` keeps a separate count of the same size for its synonym chain (`TypeCheck.hs:2012-2055`); substitution-chase steps there cost nothing.
- **Cycle detection.** `detectTypeSynonymCycles` builds a graph over the module's synonym declarations, including those in nested sections, and reports each cyclic strongly connected component.
  Primary names win over AKA aliases (left-biased union), so an alias that collides with a sibling's primary name cannot manufacture a false cycle.
  Members of a cycle are installed as bodyless `KnownType`s, so expansion never touches them; their bodies are still checked for other errors.
  The code comments say a cycle can still arrive through an import, with the fuel as the backstop (`Desugar.hs:444-447`, `Unify.hs:33-37`); none of the fixtures in this PR constructs one.
- **Directive ambiguity.** `#ASSERT` and `TIMEZONE IS` now `prune` their candidates like the other directives, so an ambiguity becomes `AmbiguousTermError`.
  `runCheckUnique` still calls `error` on zero or several results; the INVARIANT comment makes a missing `prune` a compiler bug, not a reachable user error.

## Diagnostics

- `Circular dependency detected between type synonyms:`, then each member quoted on its own line, then `A type synonym must not refer to itself, directly or via other` / `synonyms, because it could then never be fully expanded.` (`TypeCheck.hs:3302-3309`), reported at the first member's declaration.
- Directive ambiguity uses the existing message: `There are multiple definitions for the identifier` … `and I do not have sufficient information to make a choice between them.`

## Tests and fixtures that pin it

- `jl4-core/test/UnifySpec.hs` (17 `it` blocks) and `jl4-core/test/DirectiveAmbiguitySpec.hs` (4).
- `jl4/examples/not-ok/tc/unify-sibling-rebind.l4`, `not-ok/tc/type-synonym-cycle.l4`, `ok/unify-swapped-pair-args.l4`.
- `jl4/examples/not-ok/tc/assert-directive-ambiguity.l4`, `timezone-directive-ambiguity.l4`, `timezone-mixed-ambiguity.l4`.
- Each fixture has four goldens under its `tests/` directory.
- The `.ep.golden` of the two timezone fixtures prints `foo TRUE` where the source reads `TIMEZONE IS foo TRUE`.
  That is an exact-print defect already on main, which main's `ok/legal-persons-tests.ep.golden` and `ok/excel-date-tests.ep.golden` pin in the same way; unstable prints the keyword (#130), so these goldens change with that fix.

## Limits and known defects (verified)

- The fuel is a count, not a cost bound: the code's own comment says two different spellings of the same exponentially large expansion can still be slow (`Unify.hs:77-86`); not measured here.
- The `CyclicTypeSynonyms` diagnostic and the 1000-expansion bound are documented nowhere under `doc/` (a search for the message text and for `synonymExpansionFuel` under `doc/` finds nothing).

## Related changes on unstable (none of them on main)

- #50, #182, #344, #369, #407 and #411 widened the positional `MkCheckEnv` pattern in `withExtraMixfix` to 19 fields at 73a953821; #50 (`6a33968b6`) also flips one `UnifySpec` expectation, because lexical scoping resolves a synonym's own type parameter to the parameter, so `tcdSuccess` becomes `True`.
- #55 wrote the import-boundary `cyclicSynonyms = mempty` in `Import/Resolution.hs` and `jl4-lsp/src/LSP/L4/Rules.hs`; on unstable it sits in `unionImportedCheckEnv` (`TypeCheck/Types.hs:1080 @ 73a953821`), moved there by #182. On main `unionImportedCheckEnv` already exists (#543), so this PR sets the field there (`Types.hs:432`) and touches neither of those files.
- #333 changed `synonymsInSection` for the five-field `MkSection`; #358 (`d86d17350`) rewrote the `Timezone` arm's head line to `inferTopDecl _ (Timezone …)`.
- #337 moved the ambiguity fixtures from `ASSUME` to section `GIVEN`, #130 fixed the `TIMEZONE IS` exact-print in their `.ep.golden` files, and #349 reworded "argument" to "input" in `unify-sibling-rebind.golden`.
