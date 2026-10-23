# Name-resolution diagnostics: the EVENT type, and no cascades after a resolution failure (as built)

As built on `main` by the pull request that adds this page.
Source spec: none.
The change came from `unstable`: legalese/l4-ide#103 (`80217614cf`, issue smucclaw/l4-ide#915) and the first two of the three commits of legalese/l4-ide#152, `a4471aeb6` ("merge, don't overwrite, colliding builtin environment keys") and `daa7ee180` ("stop name-resolution failures cascading into bogus diagnostics", issue smucclaw/l4-ide#920).
The deploy gate of `jl4-service` (below) was added for `main`.
This page describes only what `main` has.
Line numbers are in this PR's tree, merged with `main` at `b816b0c60`.

Scope: the builtin scope in `jl4-core/src/L4/TypeCheck/Environment.hs`, the sentinel helpers and `getEntityInfo` in `jl4-core/src/L4/TypeCheck/Types.hs`, the error list and the type-mismatch rendering in `jl4-core/src/L4/TypeCheck.hs`, and the deploy gate in `jl4-service/src/Compiler.hs`.
What L4 accepts changes in four ways.
`GIVEN e IS AN EVENT party action` now type-checks, and an `@export` rule whose input is, or holds, an EVENT is refused with an error of its own.
A type you declare yourself under the name `EVENT` with two parameters is now ambiguous with the built-in type, which could not be named before.
And the deploy gate of `jl4-service` now refuses a module that names a type nothing declares: it refused one before only because of the cascade that this change removes, and it accepted such a module when the undeclared type was a GIVEN input that the body did not use.
Everything else is which diagnostics are shown, and how a type mismatch reads.

## What it does

- `GIVEN e IS AN EVENT Party Act` resolves: the EVENT type is no longer hidden behind its own constructor.
- An `@export` rule whose input is, or holds, an EVENT is an error: `EVENT inputs are not supported for @export.`
  A request is JSON and JSON has no form for an event, so without this error the rule deployed and published an input schema of `{"type": "object"}` that no request could satisfy.
  `l4 check`, `l4 batch`, `jl4-schema` and the deploy of `jl4-service` all stop at it, as they stop at a function-typed input.
- After a name that cannot be resolved (out of scope or ambiguous), the checker reports the resolution error, without the internal "should be reported as a bug" error and without the type mismatches that the unresolved name accounts for.
  Other diagnostics built on the unresolved name are still reported (see the limits).
- A type name that did not resolve is not checked for its number of arguments: a use of it gives the resolution error and no arity error.
- When two different types print the same (two `DECLARE Verdict`s), a type-mismatch message says where each was declared.
- `jl4-service` refuses a deploy whose module names an undeclared type, with that error.

## Where it lives

- `jl4-core/src/L4/TypeCheck/Environment.hs`: `initialEnvironment` (`:844`) is built with `Map.fromListWith (flip List.union)` (`:846`); EVENT is two ordinary entries, the type (`:869`) and the constructor (`:870`).
- `jl4-core/src/L4/TypeCheck/Types.hs`: `isOutOfScope` (`:706`), `typeHeads` (`:716`), `outOfScopeHeads` (`:726`), `sameModuloOutOfScope` (`:754`) and `getEntityInfo` (`:974`).
- `jl4-core/src/L4/TypeCheck.hs`: `suppressResolutionCascade` (`:238`), applied to a module's final error list in `doCheckProgramWithDependencies` (`:190`); `prettyMismatchedTypes` (`:5060`), used by `standardTypeMismatch` (`:5028`) and by the `prettyTypeMismatch` arms for a clause input (`:4899`), a CONSIDER pattern scrutinee (`:4911`), IF branches (`:4926`), CONSIDER branches (`:4937`) and LIST literal elements (`:4948`).
- `jl4-service/src/Compiler.hs`: `isOutOfScope` (`:446`), used by the list of deploy-blocking errors `blockingErrs` (`:204`, `:208`).
- `jl4-core/src/L4/TypeCheck.hs`: `inferType` (`:1941`) counts the arguments of a type against its kind only when the name resolved; `resolveType` returns kind 0 for a name that did not.
- `jl4-core/src/L4/Export.hs`: `validateExportInputs` takes the module's entity table and runs one pass for function-typed inputs and one for EVENT; `typeCarriesEvent` reads the table.
  The error is `ExportEventTypeInput` (`jl4-core/src/L4/TypeCheck/Types.hs`), worded in `prettyCheckError` (`TypeCheck.hs`).

## Behaviour and rules (read in code)

- **Builtin environment.** Two builtins that share a surface name keep both uniques, in table order, with no duplicates (`flip List.union`).
  The resolvers narrow the candidates: type resolution keeps only type candidates, term and constructor resolution only term candidates.
  EVENT is the only key that two entries of the table share: the table has 97 entries and 96 keys (counted at the time of writing), and the other keys that hold several uniques are the four comparison operators, which list them in one entry by design (measured by listing `initialEnvironment`'s keys that hold more than one unique).
- **Sentinels.** A failed resolution reports the real error and returns an `OutOfScope` sentinel whose unique is never registered in `EntityInfo`.
  `getEntityInfo` returns `Nothing` silently for a sentinel (`Types.hs:980`) and still reports `MissingEntityInfo` for any other miss (`Types.hs:982`).
- **Cascade suppression.** Drop each `TypeMismatch` that is the same on both sides once sentinels are treated as wildcards (`TypeCheck.hs:250`, `sameModuloOutOfScope`) and whose sentinels were all reported in this list.
  A sentinel carries the `Name` at which resolution failed, with its range and module, and the `OutOfScopeError`, `AmbiguousTermError` or `AmbiguousTypeError` that reported it carries the same `Name`; the filter collects those names from the list and looks each sentinel up (`TypeCheck.hs:243`).
  A sentinel that this module inherited through an import has the name from the other module, which the list does not hold, so a mismatch that mentions one is kept.
  A mismatch that differs somewhere else survives: NUMBER against `LIST OF <unresolved>` is kept, `LIST OF <unresolved>` against `LIST OF NUMBER` is dropped.
  Resolution failures themselves are never dropped, so a failing module still fails and still says why: `l4 check` still exits 1 on it, and the deploy gate refuses it.
  Filtering happens on the finished list, so resolution, pruning and overload selection are unchanged.
- **Same-name types.** If the two sides of a mismatch render identically, each side gets ` (<Name> defined at <file>:<range>, …)` for its user-defined type heads; predefined names (no range) and sentinels are skipped, and with nothing to say the plain rendering stays.
- **EVENT inputs of an `@export`.**
  `typeCarriesEvent` is true for the built-in EVENT type, for a type that has an EVENT among its arguments (`LIST OF EVENT …`, `MAYBE (EVENT …)`), for a synonym of such a type, and for a record or sum type with an EVENT in a field of one of its constructors.
  The synonyms and the fields are read from the checker's entity table, so a type declared in an imported module is looked through too.
  A function type is not looked into: an input of that type is refused as a function type already.
  The inputs examined are the GIVENs of an `@export` rule and the `ASSUME`s that its body uses, the same two places as for function types.
  No deploy-gate code was needed: the error is a checker error at error severity, and `blockingErrs` blocks every such error that is not an out-of-scope name.
- **Deploy gate.** `jl4-service` refuses a module that has an error at error severity, except an out-of-scope error for a name an expression reads, which becomes an implicit input of an `@export`.
  An undeclared type name raises the same error with the type `TYPE` (`TypeCheck.hs:1965`, the only place that does), and the gate now treats that one as blocking.
  Out-of-scope errors for terms carry an inference variable, not `TYPE`, and are still tolerated.

## Diagnostics

- New rendering, pinned by `not-ok/tc/tests/same-name-types-by-constructor.golden`: `Verdict (Verdict defined at same-name-types-by-constructor.l4:21:9-16)` against `Verdict (Verdict defined at same-name-types-by-constructor.l4:23:9-16)`, in the signature message and in the clause-input message.
- Removed from ordinary output: `The arities of the types do not match. I expected 0 arguments, but I found 2.` for a use of a type name that did not resolve, because kind 0 is the number `resolveType` makes up for a failure.
  On `main` it came with the resolution error whenever such a name was given arguments: a type of your own named like a built-in one (`DECLARE MAYBE a HAS …`, `DECLARE EVENT party action HAS …`), a parameterised type declared twice, and a type constructor that is not declared (`Duo OF NUMBER, NUMBER` with no `Duo`).
  A real arity mismatch, such as `MAYBE OF NUMBER, STRING`, is still reported.
- Removed from ordinary output: `I've encountered a resolved name that has no additional information stored for it: … This is an error in this system and should be reported as a bug.` for a sentinel (the text is at `TypeCheck.hs:4613`), and the matching "namely Verdict but is here of type Verdict" mismatches.
  The same lines also went from the output of the aliased-synonym case described in `tc-soundness.md`.

## Tests and fixtures that pin it

- `jl4-core/test/ResolutionCascadeSpec.hs` (18 examples), including an assertion that "should be reported as a bug" does not appear, cases on both sides of the mentions-versus-accounts-for boundary, and cases that type-check a module importing a module whose type failed to resolve, with and without an unknown name of the importer's own, and with an unknown type of its own as well (the sentinel from the import is kept, the one it reported itself is dropped).
- `jl4/examples/ok/event-type-resolves.l4` (EVENT in signatures, a CONSIDER on an EVENT, two `#EVAL`s: `alice` and `42`).
- `jl4/examples/not-ok/tc/resolution-cascade.l4` (an ambiguous type name; the golden holds exactly the one ambiguity error), `not-ok/tc/resolution-cascade-undefined-type.l4` (an undeclared type name; exactly one error), `not-ok/tc/same-name-types-by-constructor.l4` and `not-ok/tc/user-declared-event.l4` (a type of your own named `EVENT`, with two parameters: the ambiguity with both candidates, and no other error).
- Each fixture has four goldens under its `tests/` directory.
- `jl4-service/test/IntegrationSpec.hs`: three examples (an undeclared result type and an undeclared input type are refused; a name an expression reads is still published as an input) and three for EVENT inputs (an EVENT input is refused with the message; an input that is a `LIST OF EVENT …` or a record with an EVENT field is refused; a rule that takes the party, the action and the time and builds the event inside is published).
- `jl4-core/test/ExportValidationSpec.hs`: fifteen examples under "EVENT-typed inputs of an @export": the direct, list, MAYBE, synonym, record-field, sum-type-field, imported-record and ASSUME cases are refused, the message is pinned, and a rule that is not exported, one that builds the event inside, a record without an EVENT and a self-containing record are accepted.
- `jl4/examples/not-ok/tc/export-event-input.l4`: five refused rules, and two accepted (not exported; built inside).
- Measured on this change: `jl4-core-test` runs 538 examples with 0 failures, 18 of them new; `jl4-test` runs 1402 examples with 0 failures, 21 of them new; `jl4-service-test` runs 435 examples with 0 failures, 3 of them new.
  No golden outside the five new fixtures changed, among them the eight existing goldens whose check output holds an unresolved type or an ambiguity, which are the cases that arm the filter.
  Deploying each of the 565 tracked `.l4` files that have their imports to a service built from `main` and to one built from this tree gave the same verdict for 563; the two that differ are `ok/event-type-resolves.l4` (refused, then accepted) and `not-ok/tc/sing.l4` (accepted, then refused: its type `Person` is undeclared).
  The 160 variants of 40 of those files (the first `DECLARE` renamed or repeated, each with and without an added unrelated type error) were all refused by both; the 40 with a renamed `DECLARE` were accepted by a service built from this tree before the deploy gate was changed.

## Limits and known defects (verified)

- Suppression covers `TypeMismatch` only (read in code, `TypeCheck.hs:250`), so other diagnostics built on a sentinel are still reported after the resolution error:
  `GIVEN x IS A Typo` then `x 1 2` also gives "You are trying to apply x of type Typo (which is not a function) to 2 arguments".
- The filter acts on a module's own error list, and drops a mismatch only when every sentinel in it was reported there.
  A module that imports one whose type failed to resolve did not report that failure, so it reports its mismatches against that type (`The first argument of function ... is expected to be of type Money but is here of type NUMBER`), whether or not it has unknown names of its own.
  The imported module's own check says the type is unknown, and the importer says what it makes of the poisoned type.
- An ambiguous type name can hide a real mismatch until the ambiguity is fixed: with two `DECLARE Verdict`, `GIVEN x IS A Verdict`, `GIVETH A NUMBER` and `f x MEANS x` give the ambiguity and nothing else, and the `Verdict`-versus-`NUMBER` mismatch appears once one declaration is removed.
  The filter never empties the error list of a failing module (read in code), and every golden in `jl4-test` is unchanged, so no file under `not-ok/` that failed to check passes now.
- An `@export` input of type `DEONTIC party action` is not examined by this check: measured on a service built from this tree, it deploys and publishes `{"type": "object"}`, as it does on `main`.
  An EVENT as the result of an `@export` is not an input and is not examined: it evaluates and is returned as `{"EVENT": [party, action, time]}`.
- A type of your own named `EVENT` with two parameters is ambiguous with the built-in one, as a `DECLARE MAYBE a` is with `MAYBE`; before, it checked, because the built-in type could not be named (`not-ok/tc/user-declared-event.l4`).
  A declaration of `EVENT` with no parameters is not affected: the number of parameters rules the built-in type out (measured on a one-field record).
- `sameModuloOutOfScope` compares `Forall` bodies without alpha-renaming, so two foralls equal up to renaming compare unequal and the mismatch is kept, the conservative direction (read in code, `Types.hs:754`).
- Measured: a name that cannot be resolved as a term (`f MEANS undefinedname`) is reported once both with and without this change, so the cascade came from unresolved type names.
- `extractImplicitAssumeParams` (`jl4-core/src/L4/Export.hs`) still reports an undeclared type name as an implicit input of the type `TYPE`; the deploy no longer reaches it, and `parametersFromDecideWithErrors` (`jl4-core/src/L4/FunctionSchema.hs`) is unchanged and still calls it.
- The editor's completion list offers `EVENT` twice, once as a type and once as a constructor, as it offers a user's record type (measured on a record `Person`); before, only the constructor.
- Every type-mismatch message that prints both types goes through `prettyMismatchedTypes`; the `AS STRING` argument message prints only the given type and is not changed.
