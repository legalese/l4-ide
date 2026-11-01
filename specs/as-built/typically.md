# TYPICALLY default values (as built)

As built in this tree, checked 2026-10-30 on a build of the branch cut from main f9cb513d6: every behaviour below marked "measured" was run on that build.
The branch was then rebased onto a newer main, and on 2026-11-01 the `l4 check` probes, the `l4 batch` probes and the `jl4-service` probe were run again on the rebased build with the same answers, apart from the stable `Code:` line that main's diagnostics now carry.
Functions are cited by name and file, not by line, because the lines move.
Source spec: `specs/todo/TYPICALLY-DEFAULTS-SPEC.md`.
User page: `doc/reference/types/TYPICALLY.md`.

Differences from the source spec:

- The spec's grammar allows only Boolean, number and string literals; the code accepts any nullary constructor (`NOTHING`, an enum constructor).
- The spec's evaluation rule (`resolveParameter`), per-level nested defaults (edge case 3) and "innermost TYPICALLY wins" (edge case 5) are not built, because the default is metadata only.
- The spec's `getDefaults` helper (Phase 4) is not built under that name; consumers read `ExportedParam.paramDefault` and the JSON Schema `default` instead.
- Of Phase 5 (IDE), keyword highlighting (`ts-shared/l4-highlight/src/tokens.ts`) and the type diagnostics exist; whether hover or completion shows a default was not checked.
- The spec's `PEVAL` and `PASSERT` directives are not built.

## What it does

`TYPICALLY <value>` attaches a default to a DECLARE field, a GIVEN input or an ASSUME.
The value is a rebuttable presumption: it is parsed, resolved, type-checked against the declared type and kept in the syntax tree.
It does not change what any rule evaluates to, and nothing fills a left-out input with it.
The JSON Schema generated for an exported function publishes it as the JSON Schema `default` keyword where the value has a JSON form.
`jl4-service`'s deployed-function schema carries it only on the fields of a record input (see Limits).

## Where it lives

- Lexer: `TKTypically` and the keyword `"TYPICALLY"` (`jl4-core/src/L4/Lexer.hs`).
- Syntax tree: an extra `Maybe (Expr n)` field on three constructors (`jl4-core/src/L4/Syntax.hs`):
  - `MkTypedName` field 4, before the MEANS field;
  - `MkOptionallyTypedName` field 4;
  - `MkAssume` field 5.
- Parser: `optionalHole (… TKTypically *> annoHole atomicExpr')` after the type, in `assume`, `reqParam` and `param` (`jl4-core/src/L4/Parser.hs`).
  The value is an atomic expression, so a compound value must be parenthesised, and is then rejected as not a literal.
- Checker (`jl4-core/src/L4/TypeCheck.hs`):
  - `checkTypically` checks the value against the declared type under `ExpectTypicallyValueContext`, then requires `isTypicallyLiteral`;
  - `checkTypicallyOpt` raises `TypicallyRequiresType` when the input has no type, or its type is the `TYPE` kind marker;
  - `rejectTypicallyOnType` drops the value and raises `TypicallyOnTypeVariable` on a type variable;
  - `checkFieldDefaults` checks a DECLARE field's value in phase 4, once every constructor is in scope; `inferSelector` leaves it unchecked in phase 1, where an enum constructor does not resolve yet;
  - the GIVEN sites are `mkref`, `ensureNameConsistency` and `ensureTypeNameConsistency`, with `inferOptionallyTypedName` (under `inferLamGivens`) for a GIVEN inside a function without a name; `inferAssume` and `inferTyDeclAssume` are the ASSUME sites.
- Error constructors: `TypicallyValueNotALiteral`, `TypicallyRequiresType`, `TypicallyOnTypeVariable` and the mismatch context `ExpectTypicallyValueContext` (`jl4-core/src/L4/TypeCheck/Types.hs`).
- Printer: ` TYPICALLY <e>` after the type, and before a MEANS line (`jl4-core/src/L4/Print.hs`).
  Measured: `l4 format` keeps every default of a file that has fields, inputs and a `NOTHING` default.
- Export and schema:
  - `ExportedParam.paramDefault`, filled for GIVENs and ASSUMEs (`jl4-core/src/L4/Export.hs`);
  - `typicallyToJson` (`jl4-core/src/L4/FunctionSchema.hs`), used for GIVENs, ASSUMEs and record fields;
  - `jl4-core/src/L4/JsonSchema.hs`, the generator behind the `jl4-schema` executable and the golden harness's `.schema.golden` files.
- Every other pattern match on the three constructors gained the field: core modules, backends, `jl4-lsp`, `jl4-mlir` and `jl4-service`.
  This is mechanical threading and carries no behaviour.
- The annotation pass (`jl4-core/src/L4/Parser/ResolveAnnotation.hs`) does not traverse a default: an `@nlg` written after one attaches to the field or the input, never to the default.

## Behaviour and rules

- A value is a literal when it is a `Lit` (number or string) or a zero-argument application of a name whose entity is a constructor (`isTypicallyLiteral`).
  So `TRUE`, `FALSE`, `NOTHING` and enum constructors qualify; `(TRUE AND FALSE)` does not.
  Measured: `GIVEN x IS A NUMBER TYPICALLY -5` checks clean.
- The type check runs first: `x IS A BOOLEAN TYPICALLY 42` is a type mismatch, not a literal error.
- A rule's GIVEN with no type and a default is rejected (`TypicallyRequiresType`), rather than checked against a fresh inference variable.
  Measured: an ASSUME with no type takes its type from the default (`ASSUME foo TYPICALLY "five"` makes `foo + 1` a type error), and so does a GIVEN inside a function without a name (`GIVEN y TYPICALLY 5 YIELD y + 1` applied to a string is a type error).
- A default on a type variable (`ASSUME T IS A TYPE TYPICALLY 42`) is an error, and the value is dropped.
- A DECLARE field may default to an enum constructor (`checkFieldDefaults`); a constructor of another enum is a type mismatch (`not-ok/tc/typically-enum-field.l4`).
- JSON form (`typicallyToJson`): a number becomes a JSON number, a string a JSON string, `TRUE`/`FALSE` a JSON Boolean.
  Anything else, including `NOTHING` and enum constructors, yields no `default` key.
  Measured with `jl4-schema`: numbers, strings and Booleans on inputs and on record fields appear as `default`; a `NOTHING`, an enum constructor and a `MAYBE` default do not.
- A defaulted input is still listed under `required`: `required` is derived from MAYBE-ness only (pinned by `ok/tests/typically-basic.schema.golden`).
- The evaluator ignores the field: `scanAssume` in `jl4-core/src/L4/EvaluateLazy/Machine.hs` binds it as `_mTypically`.

## What a left-out input does (measured 2026-10-30)

- `#EVAL f` with too few arguments is a check error ("expects 2 arguments, but you are applying it to 1 argument here"); `#EVAL f WITH a IS 1` that omits a defaulted input says "you forgot to supply the following arguments"; `#EVAL f` alone shows `<function>`.
- A record built without a defaulted field: "you forgot to supply the following arguments".
- `l4 batch`: a row without the input fails with "Missing required field 'x' in JSON object"; `--validate-only` says "Missing required field: 'x'".
- `jl4-service`, direct path: 422, "Parameter 'x': missing required parameter".
- `jl4-service`, wrapper path (a `{}` anywhere in the request): a left-out BOOLEAN binds a placeholder assumed term, `x (not supplied)`, declared by an ASSUME in the generated wrapper; evaluation stops, naming it, only if the rule reads it.
  A left-out input of another type is refused as missing.
- An ASSUME that evaluation needs stops it: "I needed to know the value of `applicable law` but it is an assumed term", with or without a `TYPICALLY` value.

## Diagnostics

Wording as it stands in `prettyCheckError` and `prettyTypeMismatch` (`jl4-core/src/L4/TypeCheck.hs`):

- ``The TYPICALLY value for `x` must be a literal:`` / `a number, a string, or a nullary constructor such as TRUE, FALSE or NOTHING.`
- `` `x` has a TYPICALLY default but no explicit type. `` / `Add a type annotation (for example IS A NUMBER) so the default can be type-checked.`
- `` `a` is a type, which cannot carry a TYPICALLY default value. `` / `TYPICALLY defaults apply to term-level fields, parameters and assumptions.`
- Mismatch: ``The TYPICALLY value for `x` is expected to be of type`` followed by the standard mismatch body.

## Tests and fixtures that pin it

- `jl4/examples/ok/typically-basic.l4` and its four goldens; the `.schema.golden` pins the number and Boolean defaults and the `required` list.
- `jl4/examples/ok/typically-enum-field.l4` and `jl4/examples/not-ok/tc/typically-enum-field.l4`, each with four goldens: an enum constructor as a field default, and a constructor of another enum.
- `jl4/examples/not-ok/tc/typically-non-literal.l4`, `typically-on-type.l4`, `typically-requires-type.l4`, `typically-type-mismatch.l4`, each with four goldens.
- `jl4/examples/ok/nlg-typically-default.l4` and its four goldens, with the "a TYPICALLY default takes no annotation" block of `jl4-core/test/NlgAttachmentSpec.hs`.
- `jl4-service/test/SchemaSpec.hs`: `parameterDefault` serialises as `"default"` only when set.
- `jl4-service/test/IntegrationSpec.hs`, "a missing BOOLEAN on the wrapper path": the placeholder, five cases.
- `doc/reference/types/typically-example.l4`, type-checked by `doc/test-docs.sh`; the page `doc/reference/types/TYPICALLY.md`.

## Limits and known defects (verified)

- **A TYPICALLY on a computed (MEANS) field is discarded unchecked.**
  Measured: `taxed IS A NUMBER TYPICALLY "oops" MEANS price * 2` checks clean and evaluates, while the same default on a stored field is a type error.
  Read in code: `desugarCFDeclare` removes computed fields before type checking, and `makeComputedDecide` ignores the default (`jl4-core/src/L4/Desugar.hs`).
- The "must be a literal" error on a DECLARE field is reported at the record type's name, not at the value (`not-ok/tc/tests/typically-non-literal.golden`, range 4:9-4:14 on `Flags`).
- `NOTHING` and enum-constructor defaults never reach a schema (measured with `jl4-schema`).
- `jl4-service`'s deployed-function schema drops top-level GIVEN and ASSUME defaults: `paramToParameter` in `jl4-service/src/Compiler.hs` never reads `paramDefault`.
  Measured: a deployed rule with `age IS A NUMBER TYPICALLY 18` publishes `{"type":"number"}` for `age`, and a record input publishes `default` on its number, string and Boolean fields but not on an enum field.
- Cosmetic: `HasRef (TypedName)` binds field 4 as `mExpr` and field 5 as `typically`, the reverse of their meaning (`jl4-core/src/L4/Parser/ResolveAnnotation.hs`); both are traversed and rebuilt in place, so it is harmless.
- Not built here, and not claimed: filling a left-out input from its default (the design is in the source spec), the query planner reading a default as a prior (nothing in `jl4-query-plan/`, `ts-shared/boolean-analysis/`, `jl4-service/src/Backend/DecisionQueryPlan.hs` or `jl4-lsp/src/LSP/L4/Viz/QueryPlan.hs` mentions TYPICALLY), and the section `GIVEN` of unstable (an input shared by every rule of a § section), whose code, `L4.Discharge`, is not in this tree.
