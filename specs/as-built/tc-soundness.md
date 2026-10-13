# Type checker soundness: unification and directive ambiguity (as built)

As built on `main` by the type-checker soundness change, whose last follow-up on `unstable` is legalese/l4-ide#637.
Source spec: none.
The fixes came from `unstable`: #55 (`e6975cd9b9`), #56 (`f16e0ad667`), their follow-ups in #628 (`36f2bec91`), #634 (`8be0243b2`, `1e052b92d`) and #637 (`a889b9f5d`, `f44debb61`), and the `TIMEZONE IS` hunks of #130 (`bce739e9f`); this page describes only what `main` has.
Line numbers are in this PR's tree, on `main` at `00298eb60`.

Scope: unification (`TypeCheck/Unify.hs`), the detection of type synonym cycles (`TypeCheck.hs`), and the directives `#ASSERT` and `TIMEZONE IS`.
`doc/reference/types/DECLARE.md` states the synonym rules to users; no spec under `specs/` owns the checker fixes.

## What it does

- Unification no longer accepts ill-typed programs or loops.
  An inference variable that occurs twice in one type (`Pair OF a, a` against `Pair OF STRING, NUMBER`) could be silently rebound mid-unification; swapped arguments could build a cyclic substitution and hang.
- A cycle of type synonyms, which has no finite expansion, is reported, and its members are set aside so that no unification expands them.
  That includes a cycle hidden by a name: in `DECLARE W1 AKA B1 IS A Duo OF B1, B1` next to `DECLARE B1 a IS A LIST OF a`, the `B1` with no arguments is `W1`'s own alias.
  A synonym that merely shares its name with something else is not a cycle: `DECLARE Box IS A Box OF NUMBER` next to a record `DECLARE Box a HAS item IS AN a`, or next to a synonym `DECLARE Box a IS A LIST OF a`, is accepted whichever is declared first, and so is a synonym that shares its name with an imported record of the same number of parameters (the use is an ambiguity, which is reported as that and nothing more).
- Running out of the expansion limit (1000 synonyms in a row) is reported as a limit, not as a mismatch of types.
- Unification no longer substitutes the whole type at every step of the descent, nor compares whole subtrees at every level, so a check does not grow with the square of the depth of a type nested on either side (measured below).
- An ambiguous but well-typed expression under `#ASSERT` or `TIMEZONE IS` is reported as an ambiguity diagnostic instead of crashing the checker with `internal error: expected unique result, got several`.
- Exact-print keeps `TIMEZONE IS`: it used to give back only the expression, so `l4 format` dropped the declaration, and the editor's parse and check phases gave the two tokens no semantic token (`lsp/semantic-tokens/timezone.l4`).

Measured 2026-10-13 with `l4 check`, once with an `l4` built from `main` without this change and once with this PR's build, each under a 4 GiB memory cap and a 60 s timeout:

| program                                       | `main` without this change                            | with this change                                        |
| --------------------------------------------- | ----------------------------------------------------- | ------------------------------------------------------- |
| `ok/unify-swapped-pair-args.l4`               | killed by the 4 GiB cap before the timeout            | `Check succeeded.`                                      |
| `not-ok/tc/unify-sibling-rebind.l4`           | `Check succeeded.` (the ill-typed module is accepted) | two type errors: the definition is a STRING, not NUMBER |
| `not-ok/tc/type-synonym-cycle.l4`             | killed by the 4 GiB cap before the timeout            | `Circular dependency detected between type synonyms:`   |
| `not-ok/tc/type-synonym-alias-cycle.l4`       | killed by the 4 GiB cap before the timeout            | three cycle diagnostics (`W1`, `W2`, `W3`)              |
| `not-ok/tc/assert-directive-ambiguity.l4`     | `internal error: expected unique result, got several` | `There are multiple definitions for the identifier`     |
| `not-ok/tc/timezone-directive-ambiguity.l4`   | the same internal error                               | the same ambiguity message                              |
| `not-ok/tc/timezone-mixed-ambiguity.l4`       | the same internal error                               | the same ambiguity message                              |
| a chain of 1200 synonyms, each the one before | `Check succeeded.`                                    | ``I stopped following type synonyms at `S200`.``        |

For the cost of unifying, `l4 check` user plus system CPU of a type nested on the left (`P OF (P OF (… a …), a), a`) that a definition is used at fifty times, minus the same file with no uses, single runs on 2026-10-13:

| depth | `main` without this change | with this change |
| ----- | -------------------------- | ---------------- |
| 400   | 0.11 s                     | 0.19 s           |
| 800   | 0.46 s                     | 0.51 s           |
| 1600  | 1.56 s                     | 1.20 s           |
| 3200  | 3.50 s                     | 2.37 s           |

Each use still unifies the whole type, so the cost grows with the depth times the number of uses; what the change removes is the extra factor of the depth.
`UnifySpec` times a generic function at nesting depth 100 against 400, and a left-nested unification (no parsing or resolution) at 4000 against 16000.

## Where it lives

- `jl4-core/src/L4/TypeCheck/Unify.hs`: `synonymExpansionFuel = 1000` (`:49-50`), `unify`/`unifyFuel` (`:122-129`), `walkHead` (`:136-143`), `unify'` (`:149-156`), `sameUnderSubstitution` (`:166-180`), `isExpandableSynonym` (`:186-189`), `bindChecked` (`:196-199`), `plainTypeEqUnder` (`:214-229`), `expandAndUnify` (`:240-257`), `unifyBase` (`:265-278`), `bind` and its precondition comment (`:288-297`).
- `jl4-core/src/L4/TypeCheck.hs`:
  - the cycle check, `quarantineResolvedSynonymCycles` (`:2109-2184`), called from `checkProgram` between scanning the types and scanning the definitions (`:195-210`, the call at `:202`);
  - fuelled synonym chase in `matchFunTy` (`:1994-2054`, the fuel is set at `:2005`);
  - `runCheckUnique` and its INVARIANT comment (`:342-363`);
  - `prune` on `inferDirective (Assert …)` (`:475-480`) and on `inferTopDecl (Timezone …)`, which also gains an `errorContext` (`:531-537`);
  - the strict `error` for the projection case (`:1390-1399`);
  - `prettyCheckError` for `CyclicTypeSynonyms` (`:3372-3379`) and `SynonymExpansionLimit` (`:3380-3389`).
- `jl4-core/src/L4/TypeCheck/Types.hs`: `CyclicTypeSynonyms [Name]` (`:95`) and `SynonymExpansionLimit Int Resolved` (`:97-101`).
  `unionImportedCheckEnv` (`:419`) and `extendEnv` (`:954`) are as on `main`: no `CheckEnv` field was added.
- `jl4-core/src/L4/Parser.hs`: `timezone'` returns the `Timezone` declaration with its `TIMEZONE` and `IS` tokens kept in the annotation (`:606-612`), and `topdecl` tries it first (`:456`).
- `doc/reference/types/DECLARE.md:82-113`: the user-facing text on cycles, `AKA` names, shared names and the limit.

## Behaviour and rules

- **Look through the substitution at every descent.** `unifyFuel` resolves the head of both types (`walkHead`) before it compares them, and `unifyBase` recurses through `unifyFuel`, so later siblings see bindings made by earlier ones.
  Every inference variable reaching `bind` is therefore unbound, and `bind`'s `Map.insert` never overwrites a live binding.
- **Substitute the whole type only to bind.** `bindChecked` substitutes the type in full when a variable is about to be bound to it, because the occurs check needs every variable the type reaches.
  Elsewhere only the head is read (a generic function used fifty times at a type nested 400 deep checks in 0.46 s of user CPU on this build).
- **Short-circuit, only where it pays.** `sameUnderSubstitution` answers "the same type" without descending in three cases: the same inference variable (which must not be bound to itself), a type constructor with no arguments against itself, and the same type synonym applied to the same arguments, which `plainTypeEqUnder` compares structurally, ignoring annotations and argument names and reading bound variables through the substitution.
  The synonym case is what keeps a tower of synonyms from being expanded at exponential cost.
  Other type constructors are left to the descent, because a structural comparison walks to the first difference, and in a type nested on the left that is at the bottom, so trying it at every level cost the square of the depth (`Unify.hs:98-120`).
- **Fuel.** Each synonym expansion costs one unit from a budget of 1000 that is passed down, never reset, through constructor children.
  When it runs out with a synonym still to expand, `SynonymExpansionLimit` is reported and the two types are taken as unified, so the module fails once with that error and not twice.
  `matchFunTy` keeps a separate count of the same size for its synonym chain (`TypeCheck.hs:2005-2048`); substitution-chase steps there cost nothing.
  The fuel bounds the depth of an expansion, not its work: a synonym that names itself twice branches twice per expansion, so the cycle check below, and not the fuel, is what keeps a cycle from being expanded (`Unify.hs:26-47`).
- **Cycle detection, by Unique.** `quarantineResolvedSynonymCycles` runs once every synonym body is resolved.
  A body names the `Unique` of the synonym each type application in it resolved to, whatever it was spelled: an alias, or a name at the wrong number of arguments (`DECLARE B a IS A PAIR OF B, B`, a kind error that the checker still resolves to the synonym).
  A name that did not resolve, an ambiguity or an unknown name, names none.
  A cycle among those Uniques is a cycle of expansions, so its members are given no body, and each cycle is reported once as `CyclicTypeSynonyms` at its first member's declaration.
  It cannot reject a program the checker accepts correctly, because a reference cycle among synonyms has no finite expansion, and it is the only cycle check: a name is never read before it is resolved, so two synonyms of one name and different arities, a synonym spelled like a record, and a synonym that shares a name with an imported type are told apart as the checker tells them apart.
  Because it is the only cycle check, every cycle case in `UnifySpec` and the `type-synonym-cycle` and `type-synonym-alias-cycle` fixtures depend on it; the wrong-arity self-reference and the same cycle imported from another module are the cases a pass over spellings could not see.
- **Quarantine.** Members of a cycle are installed as bodyless `KnownType`s, so expansion never touches them; their bodies are still checked for other errors.
  An imported module's cyclic synonyms were quarantined when that module was checked, and modules are acyclic, so imports need no care of their own (`Unify.hs:26-47`).
- **Directive ambiguity.** `#ASSERT` and `TIMEZONE IS` now `prune` their candidates like the other directives, so an ambiguity becomes `AmbiguousTermError`.
  `runCheckUnique` still calls `error` on zero or several results; the INVARIANT comment makes a missing `prune` a compiler bug, not a reachable user error.
- **Exact-print of `TIMEZONE IS`.** The two tokens live in the declaration's annotation, so exact-print and `l4 format` reproduce the line.

## Diagnostics

- `Circular dependency detected between type synonyms:`, then each member quoted on its own line, then `A type synonym must not refer to itself, directly or via other` / `synonyms, because it could then never be fully expanded.` (`TypeCheck.hs:3372-3379`), reported at the first member's declaration.
- ``I stopped following type synonyms at `S200`.``, then the explanation and what to do (`TypeCheck.hs:3380-3389`).
- Directive ambiguity uses the existing message: `There are multiple definitions for the identifier` … `and I do not have sufficient information to make a choice between them.`

## Tests and fixtures that pin it

- `jl4-core/test/UnifySpec.hs` (36 `it` blocks, among them the cycle, alias, wrong-arity, shared-name, import, expansion-limit and nesting-depth cases, and a timing guard for a type nested on the left) and `jl4-core/test/DirectiveAmbiguitySpec.hs` (4).
- `jl4/examples/not-ok/tc/unify-sibling-rebind.l4`, `not-ok/tc/type-synonym-cycle.l4`, `not-ok/tc/type-synonym-alias-cycle.l4`, `ok/unify-swapped-pair-args.l4`, `ok/synonym-shares-record-name.l4`, `ok/synonym-same-name-two-arities.l4`.
- `jl4/examples/not-ok/tc/assert-directive-ambiguity.l4`, `timezone-directive-ambiguity.l4`, `timezone-mixed-ambiguity.l4`.
- Each fixture has four goldens under its `tests/` directory; `lsp/semantic-tokens/timezone.l4` has one, listing the tokens of a `TIMEZONE IS` line in the lexer, parse and check phases.
- The `.ep.golden` of every file with a `TIMEZONE IS` line (`ok/tests/{datetime-tests,excel-date-tests,legal-persons-tests,timezone-tests}`, `ok/excel-date/tests/serials` and the two timezone fixtures) shows that line whole.

## Limits and known defects (verified)

- The fuel is a count, not a cost bound: two different spellings of the same exponentially large expansion, as two acyclic towers of the same shape under different names, can still be slow (`Unify.hs:106-109`); not measured here.
- A synonym applied to a type nested deeply on the left is still compared as a whole at every synonym on the way down (`Unify.hs:118-120`); not measured here.
- A chain of more than 1000 synonyms, each defined as the one before, is rejected with the limit message.
  `main` without this change accepts a chain of 1200 (measured above).
- A program that uses an aliased synonym which collides with an imported record of the same number of parameters (`IMPORT lib` declaring `Money`, then `DECLARE Cash AKA Money IS A Money` and a definition that uses `Cash` and `Money`) gets the two ambiguity errors followed by "I've encountered a resolved name that has no additional information stored for it".
  The output is the same on `main` and here; this change does not touch it, and it adds no cycle error to it.
- `TIMEZONE IS` infers its expression with no expected type (`TypeCheck.hs:536`), so `TIMEZONE IS 42` checks clean.
  This is as it was before the change; `timezone-mixed-ambiguity.l4` pins the other side of the same fact.
- `ok/tests/legal-persons-tests.ep.golden` still differs from its source file in the escaping of a non-ASCII string (`\206le` for `Île`); that comes from string-literal exact-print, which this change does not touch.
