# Name-resolution diagnostics: no second error after a name fails to resolve, and the EVENT export (as built)

As built on `unstable` by the pull request that adds this page.
Source spec: none.
The behaviour began on `unstable` with legalese/l4-ide#152 (`5a51f825d`): `a4471aeb6` made the type `EVENT` and the constructor `EVENT` both resolvable (smucclaw/l4-ide#915), and `daa7ee180` removed the follow-on errors of a failed name from the finished error list, in `suppressResolutionCascade` (smucclaw/l4-ide#920).
This change keeps the first and replaces the second: the unifier lets a type that stands for a name that did not resolve match anything, so the follow-on errors are never raised, and the filter and its two helpers are deleted.
The same change is on `main` as legalese/l4-ide#769 (merged 2026-10-30 as `7a997532c`); the page that PR adds describes what `main` has, and its unifier guard is the same code as here.
Line numbers are in this change's tree, `unstable` at `bcbec1419` with this change on it.

Scope: the unifier (`jl4-core/src/L4/TypeCheck/Unify.hs`), the sentinel helpers and `getEntityInfo` (`jl4-core/src/L4/TypeCheck/Types.hs`), the type-mismatch messages and the arity check (`jl4-core/src/L4/TypeCheck.hs`), the refusal of an `EVENT` in an `@export` (`jl4-core/src/L4/Export.hs`), the Blawx step-over (`jl4/app/L4/Cli/Blawx.hs`) and the deploy gate in `jl4-service/src/Compiler.hs`.

## What it does

- After a name that cannot be resolved (not in scope, or ambiguous), the checker reports that error and nothing that follows only from it.
  `unstable` already did this by dropping the follow-on mismatch from the finished list; it now never raises it, so the same errors are reported and the code that dropped them is gone.
  The 17 examples that pinned the old behaviour hold with their assertions unchanged.
- A type name that did not resolve is not counted against the arguments written after it, so `GIVEN p IS A Duo OF NUMBER, NUMBER` with no `Duo` gives the undeclared-type error and no arity error.
  `unstable` gave both.
- A module that imports a module in which a type failed to resolve is not given a mismatch against that type.
  `unstable` gave it one; see the limits.
- An `@export` rule that takes or returns an `EVENT` is an error at the `@export` line, whether the `EVENT` is a `GIVEN`, an `ASSUME` that the body reads, or the result (written, or inferred when there is no `GIVETH`), and whether it is named directly, inside a `LIST OF` or a `MAYBE OF`, or through a type you declared as another name for it.
  `unstable` accepted such a rule (`l4 check` exited 0) and it would be published with an input or result typed `object`, which no request can fill.
  It is an error of the same kind as the refusal of a function-typed input, so the file does not check: `l4 check`, `l4 run` and `l4 batch` exit 1 and evaluate nothing, the `#EVAL`s of the other rules included.
  A type of your own called `EVENT`, and an `EVENT` that the body builds or reads but the signature does not name, are not refused.
  `l4 export blawx` still exports such a module: the refusal is one of those that Blawx steps over, because a Blawx interview sends nothing in a request.
- `jl4-service` refuses to deploy a module that names a type nothing declares, with the undeclared-type error.
  With no second error raised for the use of that type, nothing else would stop it, and the module would be published with a required input called after the type.

## Where it lives

- `jl4-core/src/L4/TypeCheck/Environment.hs`: `initialEnvironment` (`:937`) is built with `Map.fromListWith (flip List.union)`, so the type and the constructor `EVENT` (`:962`, `:963`) both survive.
  Unchanged here.
- `jl4-core/src/L4/TypeCheck/Types.hs`: `isOutOfScope` (`:1504`) recognises the sentinel that `outOfScope`, `ambiguousTerm` and `ambiguousType` hand back after they report a failure; `typeHeads` (`:1514`) lists the names a type is built from; `getEntityInfo` (`:2204`) returns `Nothing` for a sentinel without raising `MissingEntityInfo`.
  `mentionsOutOfScope` and `sameModuloOutOfScope` are deleted; `typeHeads` stays, for `prettyMismatchedTypes` and for the check for cycles among type synonyms.
- `jl4-core/src/L4/TypeCheck/Unify.hs`: `unify'` (`:150`) does not unify a type whose head is a sentinel, it accepts it (`poisoned`, `:171`).
  The cases for inference variables come first, so a variable bound to such a type carries the sentinel on.
  Only the head counts: `LIST OF Typo` against `NUMBER` still fails, because the outer types differ.
- `jl4-core/src/L4/TypeCheck.hs`: `inferType` checks the number of a type's arguments against its kind only when the name resolved (`:2330`); `standardTypeMismatch` (`:8998`) and `prettyMismatchedTypes` (`:9029`) add the place of declaration when two renderings are equal, as before.
- `jl4-core/src/L4/Export.hs`: `validateExportInputs` (`:688`) takes the entity info and calls `checkEventTypes` (`:928`) next to the function-type checks; `mentionsEvent` (`:403`) and the function-type test share one walk of a type, `typeContains` (`:410`), which expands synonyms and looks into type arguments; the inferred result comes from `inferredReturnType` (`:214`), which `enrichReturnTypes` uses too.
  A read `ASSUME` is found through the read-set `unstable` already has for the app-form `ASSUME` checks.
  The error is `ExportEventType` (`jl4-core/src/L4/TypeCheck/Types.hs:233`), ranged at the `@export` (`:904`) and worded at `jl4-core/src/L4/TypeCheck.hs:8114`.
  `doCheckProgramWithDependencies` hands the validator the entity info with the substitution applied (`jl4-core/src/L4/TypeCheck.hs:288`), because the result of a definition without a `GIVETH` is still an inference variable until then; that is not computed unless an `@export` needs an inferred result.
- `jl4-core/src/L4/TypeCheck/Types.hs:839`: `isExportPublicationRefusal` lists `ExportEventType` (`:843`), so the Blawx export (`jl4/app/L4/Cli/Blawx.hs:225`) and the relational lowering step over it as they do over the other publication refusals; the message Blawx prints about the stepped-over diagnostics names the `EVENT` as well as the assumed rule.
- `jl4-service/src/Compiler.hs`: `isOutOfScope` (`:514`), used in the list of errors that block a deploy (`:245`), no longer tolerates an out-of-scope error whose type is `TYPE`, which is how an undeclared type is reported; an out-of-scope error for a name an expression reads is still tolerated, because the deploy turns it into an input.

## How it is pinned

- `jl4-core/test/ResolutionCascadeSpec.hs`, 32 examples: the 17 that `unstable` had (three renamed, assertions unchanged) and 15 new ones.
  The follow-on errors are not raised; the genuine errors next to a failure still are; an importer is not given a second mismatch for a type that failed in its import; the arity cases; the same-spelled types; an operator or a call on a value of an unresolved type.
- `jl4/examples/not-ok/tc/`: `resolution-cascade.l4` and `same-name-type-mismatch.l4` (unstable's, untouched), and four new ones with their goldens: `resolution-cascade-undefined-type.l4` (one error), `same-name-types-by-constructor.l4` (two mismatches, each side with its place), `user-declared-event.l4` (one ambiguity, two candidates) and `export-event-type.l4` (three errors, each at its `@export`, and none for the rule that only builds and reads an `EVENT`); `jl4/examples/ok/event-type-resolves.l4` is unstable's, untouched.
- `jl4-core/test/ExportValidationSpec.hs`, 11 examples under "an EVENT in an @export": the input, the written and the inferred result, `LIST OF`, `MAYBE OF`, a synonym and an `ASSUME` are refused, each at its `@export` and with its message; an `EVENT` built or read in the body, one in a definition without `@export`, and a type of your own called `EVENT` are not; a record with an `EVENT` field is not looked into (the known limit below).
  The examples that expect no error also expect the module to check, so that a module that did not check cannot pass them.
- `jl4-service/test/IntegrationSpec.hs`, 5 new examples: a result type and an input type that nothing declares are refused, and an input that no `GIVEN` declares is still published; an `@export` that takes an `EVENT` and one that returns an `EVENT` are refused.

## Measured

- Every `.l4` file of the repository outside the `tests` directories (1,310 files under `jl4`, `jl4-core`, `doc`, `specs` and `skills`), checked with `l4 check` by a build of `unstable` (`bcbec1419`) and a build of this change (`637203eb6`), the exit code and the diagnostics compared as multisets: 1,308 are identical.
  The two that differ are examples this change adds.
  `export-event-type.l4` goes from exit 0 with no diagnostic to exit 1 with three errors, each at its `@export`.
  `user-declared-event.l4` goes from two diagnostics to one: "This type is given the wrong number of inputs" (`I expected 0, but I found 2`) goes, from the same place as the ambiguity of `EVENT`, where the two arguments had been counted against the name that could not be chosen.
- The 5,974 `.l4` files of `legalese/commons` at `798b51452`, checked the same way: the `unstable` build fails 1,139 of them.
  The files that can change are those that have a diagnostic already (the guard and the arity check act only after a name has failed) and those that mention `@export` or `EVENT` (the refusal); that is 2,256 files, and all 2,256 give the same exit code and the same diagnostics (62,423 in all, the same multiset) with this change.
  So on these files the guard and the filter it replaces report the same errors, and no file of `legalese/commons` has an `@export` that takes or returns an `EVENT`.
  One of them, `cp6-tests-statements-and-reports.l4`, did not finish in 120 seconds on either build in that run; rerun with a 15-minute limit it exits 1 with 86 diagnostics on both builds, the same multiset.

## Limits

- A file that fails to resolve a type name and reads an overloaded name through a value of that type gets the ambiguity of the overloaded name as well.
  Which `speak` is meant cannot be told from a value whose type is unknown, so every candidate fits.
  `unstable` did the same with the filter: the "known limit" example of `ResolutionCascadeSpec` passes on both.
- A module that imports a module with an unresolved type name is not given a mismatch against that type: it cannot tell a sentinel it made from one it inherited, and it already fails on the import.
  This is new on `unstable`, which gave the mismatch.
- The fields of a record are not looked into: a rule that takes a record you declared with an `EVENT` field passes `l4 check` (`ExportValidationSpec` pins it).
- An `@export` rule that takes a `DEONTIC` input still passes `l4 check` (measured on `unstable` before and after this change: "Check succeeded"), and is published with an `object` input (`typeNameToParameter`, `jl4-core/src/L4/FunctionSchema.hs:172`, gives a type that it has no declaration for the schema type `object`, `:178`).
  This change refuses an `EVENT` only; refusing a `DEONTIC` input or result is not part of it.
- The refusal is a type error, as the function-type refusal is, so it stops the file from checking and the `#EVAL`s of its other rules with it; a diagnostic of its own, published by a separate pass so that the file still checks, is not part of this change.
