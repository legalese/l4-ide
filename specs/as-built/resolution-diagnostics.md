# Name-resolution diagnostics: the EVENT type, and no second error after a name fails to resolve (as built)

As built on `main` by the pull request that adds this page.
Source spec: none.
The change came from `unstable`: legalese/l4-ide#103 (`80217614c`, issue smucclaw/l4-ide#915) and legalese/l4-ide#152 (`a4471aeb6` and `daa7ee180`, issue smucclaw/l4-ide#920).
`unstable` removes the follow-on errors from the finished error list (`suppressResolutionCascade`).
`main` does not: it makes the unifier let a type that stands for a name that did not resolve match anything, so the follow-on errors are never raised.
This page describes only what `main` has.
Line numbers are in this PR's tree, on `main` at `b179dc5de`.

Scope: the builtin scope in `jl4-core/src/L4/TypeCheck/Environment.hs`, the sentinel helpers and `getEntityInfo` in `jl4-core/src/L4/TypeCheck/Types.hs`, unification in `jl4-core/src/L4/TypeCheck/Unify.hs`, the type-mismatch messages in `jl4-core/src/L4/TypeCheck.hs`, the refusal of an `EVENT` in an `@export` (`jl4-core/src/L4/Export.hs`), and the deploy gate in `jl4-service/src/Compiler.hs`.

## What it does

- `GIVEN e IS AN EVENT Party Act` type-checks.
  The EVENT type was hidden behind its own constructor: both are spelled `EVENT`, and the table of builtin names kept only the last entry for a name.
- After a name that cannot be resolved (not in scope, or ambiguous), the checker reports that error and nothing that follows only from it.
  It used to add an error saying "This is an error in this system and should be reported as a bug", and a mismatch between the type the name stood for and whatever it was used as, which printed as the same type twice.
- A type name that did not resolve is not counted against the arguments written after it, so `GIVEN p IS A Duo OF NUMBER, NUMBER` with no `Duo` gives the undeclared-type error and no arity error.
- A type of your own named `EVENT` with two parameters is ambiguous with the built-in type, wherever the name is written.
  Every built-in type name behaves so (`DECLARE MAYBE a` against `MAYBE`).
  A type named `EVENT` with no parameters is not ambiguous, because the number of parameters rules the built-in one out.
- When the two types of a mismatch are spelled the same (two `DECLARE Verdict`s), the message says where each was declared.
- An `@export` rule that takes or returns an `EVENT` is an error at the `@export` line, whether the `EVENT` is a `GIVEN`, an `ASSUME` that the body reads, or the result (written, or inferred when there is no `GIVETH`), and whether it is named directly, inside a `LIST OF` or a `MAYBE OF`, or through a type you declared as another name for it.
  The EVENT type could not be named before this change, so such a rule failed to check by accident; once it can be named, nothing else stops it, and it would be published with an input or result typed `object`, which no request can fill.
  It is an error of the same kind as the refusal of a function-typed input, so the file does not check: `l4 check`, `l4 run` and `l4 batch` exit 1 and evaluate nothing, the `#EVAL`s of the other rules included.
  A type of your own called `EVENT`, and an `EVENT` that the body builds or reads but the signature does not name, are not refused.
- `jl4-service` refuses to deploy a module that names a type nothing declares, with the undeclared-type error.
  It refused one before only because of the follow-on errors that are no longer raised, and it accepted one when the type was a `GIVEN` input that the body did not use.

## Where it lives

- `jl4-core/src/L4/TypeCheck/Environment.hs`: `initialEnvironment` (`:844`) is built with `Map.fromListWith (flip List.union)`, so the type and the constructor `EVENT` (`:869`, `:870`) both survive.
- `jl4-core/src/L4/TypeCheck/Types.hs`: `isOutOfScope` (`:726`) recognises the sentinel that `outOfScope`, `ambiguousTerm` and `ambiguousType` hand back after they report a failure; `typeHeads` (`:736`) lists the names a type is built from; `getEntityInfo` (`:934`) returns `Nothing` for a sentinel without raising `MissingEntityInfo`.
- `jl4-core/src/L4/TypeCheck/Unify.hs`: `unify'` (`:149`) does not unify a type whose head is a sentinel, it accepts it.
  The cases for inference variables come first, so a variable bound to such a type carries the sentinel on.
  Only the head counts: `LIST OF Typo` against `NUMBER` still fails, because the outer types differ.
- `jl4-core/src/L4/TypeCheck.hs`: `inferType` checks the number of a type's arguments against its kind only when the name resolved (`:1874`); `prettyMismatchedTypes` (`:5007`) adds the place of declaration when two renderings are equal, and `standardTypeMismatch` (`:4976`) and the messages for a clause input, a `CONSIDER` pattern, `IF` branches, `CONSIDER` branches and `LIST` elements use it.
- `jl4-core/src/L4/Export.hs`: `validateExportInputs` (`:448`) takes the entity info and calls `checkEventTypes` (`:524`) next to the function-type checks; `mentionsEvent` (`:282`) and the function-type test share one walk of a type, `typeContains` (`:289`), which expands synonyms and looks into type arguments; the inferred result comes from `inferredReturnType` (`:157`), which `enrichReturnTypes` uses too.
  The error is `ExportEventType` (`jl4-core/src/L4/TypeCheck/Types.hs:118`), ranged at the `@export` (`:316`) and worded at `jl4-core/src/L4/TypeCheck.hs:4621`.
  `doCheckProgramWithDependencies` (`jl4-core/src/L4/TypeCheck.hs:191`) hands the validator the entity info with the substitution applied, because the result of a definition without a `GIVETH` is still an inference variable until then; that is not computed unless an `@export` needs an inferred result.
- `jl4-service/src/Compiler.hs`: `isOutOfScope` (`:446`), used in the list of errors that block a deploy (`:208`), no longer tolerates an out-of-scope error whose type is `TYPE`, which is how an undeclared type is reported; an out-of-scope error for a name an expression reads is still tolerated, because the deploy turns it into an input.

## How it is pinned

- `jl4-core/test/ResolutionCascadeSpec.hs`, 30 examples: the follow-on errors are not raised; the genuine errors next to a failure still are; an importer is not given a second mismatch for a type that failed in its import; the arity cases; the same-spelled types.
- `jl4/examples/not-ok/tc/`: `resolution-cascade.l4` and `resolution-cascade-undefined-type.l4` (one error each), `same-name-types-by-constructor.l4` (two mismatches, each side with its place) and `user-declared-event.l4` (one ambiguity, two candidates); `jl4/examples/ok/event-type-resolves.l4` (`alice` and `42`).
- `jl4-core/test/ExportValidationSpec.hs`, 11 examples under "an EVENT in an @export": the input, the written and the inferred result, `LIST OF`, `MAYBE OF`, a synonym and an `ASSUME` are refused, each at its `@export` and with its message; an `EVENT` built or read in the body, one in a definition without `@export`, and a type of your own called `EVENT` are not; a record with an `EVENT` field is not looked into (the known limit below).
  The examples that expect no error also expect the module to check, so that a module that did not check cannot pass them.
- `jl4/examples/not-ok/tc/export-event-type.l4`: three errors, each at its `@export`, and none for the rule that only builds and reads an `EVENT`.
- `jl4-service/test/IntegrationSpec.hs`: a result type and an input type that nothing declares are refused, and an input that no `GIVEN` declares is still published; an `@export` that takes an `EVENT` and one that returns an `EVENT` are refused.

## Measured

- Every `.l4` file of the repository (589 files under `jl4`, `jl4-core`, `doc`, `specs` and `skills`), checked with a build of `main` and a build of this branch: 585 give the same exit code and the same diagnostics.
  The four that differ are the new examples: the follow-on errors are gone from the two cascade examples (3 diagnostics become 1, and 5 become 1), `event-type-resolves.l4` goes from 12 errors to none, and `user-declared-event.l4` goes from none to the one ambiguity.
- The 349 files of `legalese/commons` at `798b51452` that fail to check, checked with a build of `main` and a build of this branch: all 349 still fail, none has more diagnostics, and 91 have fewer (80,682 diagnostics in all become 60,705).
  Of the 19,979 diagnostics that go, 13,087 are "I've encountered a resolved name that has no additional information stored for it", 6,605 are mismatches of an argument or of a definition against a type that did not resolve, and 287 are ambiguity errors.
  Two diagnostics are new, both "There are multiple definitions for the identifier", in two files of one encoding that imports a module with an unresolved name: the overload limit below.
- The refusal of an `EVENT` in an `@export` was measured after those two runs, with a build that has it, against the build without it: the 589 files of the repository give the same exit code and diagnostics, and the 349 files of `legalese/commons` give the same diagnostics (60,705 in all, the same set; the order within a file differs between runs in 94 files).
  No file of `legalese/commons` has an `@export` that takes or returns an `EVENT`.

## Limits

- A file that fails to resolve a type name and reads an overloaded name through a value of that type gets the ambiguity of the overloaded name as well.
  Which `speak` is meant cannot be told from a value whose type is unknown, so every candidate fits.
  `ResolutionCascadeSpec` pins it ("known limit").
- A module that imports a module with an unresolved type name is not given a mismatch against that type: it cannot tell a sentinel it made from one it inherited, and it already fails on the import.
- The fields of a record are not looked into: a rule that takes a record you declared with an `EVENT` field passes `l4 check` (`ExportValidationSpec` pins it).
- An `@export` rule that takes a `DEONTIC` input still passes `l4 check`, as it does on `main`, and is published with an `object` input (`typeToParameter`, `jl4-core/src/L4/FunctionSchema.hs:170`, gives a type that it has no declaration for the schema type `object`).
  This change refuses an `EVENT` only; refusing a `DEONTIC` input or result is not part of it.
- The refusal is a type error, as the function-type refusal is, so it stops the file from checking and the `#EVAL`s of its other rules with it; a diagnostic of its own, published by a separate pass so that the file still checks, is not part of this change.
