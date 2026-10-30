# TYPICALLY default values (as built)

As built at 73a953821. Source spec: specs/todo/TYPICALLY-DEFAULTS-SPEC.md. Differences from the source spec: the header cites `TypeCheck.hs:1268-1306`, but the checker is at `TypeCheck.hs:1724-1766`; the spec's grammar allows only Boolean, number and string literals, while the code accepts any nullary constructor (`NOTHING`, enum constructors); the spec's evaluation rule (`resolveParameter`), per-level nested defaults (edge case 3) and "innermost TYPICALLY wins" (edge case 5) are not built, because the default is metadata only in this slice; the spec's `getDefaults` helper (Phase 4) is not built under that name, and consumers read `ExportedParam.paramDefault` and the JSON Schema `default` instead; of Phase 5 (IDE), keyword highlighting and the type diagnostics exist, and whether hover or completion shows a default was not checked; the header's "not operational" is false at H for a section `GIVEN` only, which is #344's doing and is described elsewhere.

Scope: PR #92 (`53dda00225`, the feature) and PR #259 (`1ba35d0637`, which only rewrote the spec's status header).
PR #110 (wizard priors: the query planner reading Boolean defaults as priors) is a later position and is described elsewhere.

## What it does

`TYPICALLY <value>` attaches a default to a DECLARE field, a GIVEN input or an ASSUME.
The value is a rebuttable presumption: it is parsed, resolved, type-checked against the binder's declared type and kept in the AST.
In this slice it does not change what any rule evaluates to.
The JSON schema generated for an exported function publishes it as the JSON Schema `default` keyword where the value has a JSON form; jl4-service's deployed-function schema carries it only on record fields (see Limits).

## Where it lives

- Lexer: `TKTypically`, keyword `"TYPICALLY"` (`jl4-core/src/L4/Lexer.hs:262,371 @ 73a953821`).
- AST: an extra `Maybe (Expr n)` field on three constructors (`jl4-core/src/L4/Syntax.hs @ 73a953821`):
  - `MkTypedName` field 4, before the MEANS field (`:134-137`);
  - `MkOptionallyTypedName` field 4 (`:141-143`);
  - `MkAssume` field 5 (`:188-189`).
- Parser: `optionalHole (… TKTypically *> annoHole atomicExpr')` after the type in `assume`, `reqParam` and `param` (`jl4-core/src/L4/Parser.hs:835,1441,1450 @ 73a953821`).
  The value is an atomic expression, so a compound value must be parenthesised (and is then rejected as not a literal).
- Checker (`jl4-core/src/L4/TypeCheck.hs @ 73a953821`):
  - `checkTypically` (`:1727`) checks the value against the declared type under `ExpectTypicallyValueContext`, then requires `isTypicallyLiteral` (`:1737`);
  - `checkTypicallyOpt` (`:1752`) raises `TypicallyRequiresType` when the binder has no type, or its type is the `TYPE` kind marker;
  - `rejectTypicallyOnType` (`:1764`) drops the value and raises `TypicallyOnTypeVariable` on a type binder;
  - call sites: `inferSelector` for DECLARE fields (`:1769-1771`), `mkref` and `ensureNameConsistency` for GIVENs (`:1523-1603`), `inferAssume` (`:730`), `inferTyDeclAssume` for `ASSUME … IS A TYPE` (`:5211-5215`).
- Error constructors: `TypicallyValueNotALiteral`, `TypicallyRequiresType`, `TypicallyOnTypeVariable` and the mismatch context `ExpectTypicallyValueContext` (`jl4-core/src/L4/TypeCheck/Types.hs:304-311,546 @ 73a953821`).
- Printer: ` TYPICALLY <e>` after the type, and before a MEANS line (`jl4-core/src/L4/Print.hs:510-540,640-650 @ 73a953821`).
- Export and schema:
  - `ExportedParam.paramDefault` (`jl4-core/src/L4/Export.hs:72 @ 73a953821`), filled for GIVENs (`:262-270`) and ASSUMEs (`:496-506`); `extractAssumeParamsWithDefaults` (`:527-536`);
  - `typicallyToJson` (`jl4-core/src/L4/FunctionSchema.hs:338-348 @ 73a953821`), used for GIVENs (`:280`), ASSUMEs (`:292`) and record fields (`addDefault`, `:215,253`);
  - `jl4-core/src/L4/JsonSchema.hs:78-81,156,259-265,313-333 @ 73a953821` (the JSON Schema generator behind the `jl4-schema` executable, `jl4/app/Schema.hs`, and the golden harness's `.schema.golden` files).
- Every other pattern match on the three constructors gained the field: core modules, backends, `jl4-lsp`, `jl4-mlir` and `jl4-service`.
  This is mechanical threading and carries no behaviour.

## Behaviour and rules

- A value is a literal when it is a `Lit` (number or string) or a zero-argument application of a name whose entity is `KnownTerm _ Constructor` (`TypeCheck.hs:1738-1745`).
  So `TRUE`, `FALSE`, `NOTHING` and enum constructors qualify; `(TRUE AND FALSE)` and `(0 - 5)` do not.
  `TYPICALLY -5` checks clean (measured).
- The type check runs first: `x IS A BOOLEAN TYPICALLY 42` is a type mismatch, not a literal error.
- A rule's GIVEN with no type and a default is rejected (`TypicallyRequiresType`), rather than checked against a fresh inference variable.
  An ASSUME with no type, and a lambda GIVEN (`inferLamGivens`, `TypeCheck.hs:1898`), accept a default and take their type from it (measured: `ASSUME foo TYPICALLY "five"` makes `foo + 1` a type error).
- A default on a type binder (`GIVEN a IS A TYPE TYPICALLY 42`, `ASSUME T IS A TYPE TYPICALLY 42`) is an error, and the value is dropped.
- JSON form (`typicallyToJson`): a number becomes a JSON number (through `Double`), a string a JSON string, `TRUE`/`FALSE` a JSON Boolean.
  Anything else, including `NOTHING` and enum constructors, yields no `default` key.
- A defaulted input is still listed under `required`: `required` is derived from MAYBE-ness only (`Export.hs:269`, `FunctionSchema.hs:297-301`; pinned by `ok/tests/typically-basic.schema.golden`).
- The evaluator ignores the field (`scanAssume`, `jl4-core/src/L4/EvaluateLazy/Machine.hs:5519 @ 73a953821`, binds it as `_mTypically`).

## Diagnostics

- ``The TYPICALLY value for `x` must be a literal:`` / `a number, a string, or a nullary constructor such as TRUE, FALSE or NOTHING.` (`TypeCheck.hs:6880-6882`).
- `` `x` has a TYPICALLY default but no explicit type. `` / `Add a type annotation (for example IS A NUMBER) so the default can be type-checked.` (`:6884-6886`).
- `` `a` is a type, which cannot carry a TYPICALLY default value. `` / `TYPICALLY can give a default to a DECLARE field, a GIVEN input, or an ASSUME.` (`:6888-6890`).
- Mismatch: ``The TYPICALLY value for `x` is expected to be of type`` followed by the standard mismatch body (`:7467-7468`).

## Tests and fixtures that pin it

- `jl4/examples/ok/typically-basic.l4` and its four goldens; the `.schema.golden` pins the number and Boolean defaults and the `required` list.
- `jl4/examples/not-ok/tc/typically-non-literal.l4`, `typically-on-type.l4`, `typically-requires-type.l4`, `typically-type-mismatch.l4`, each with four goldens.
- `jl4-service/test/SchemaSpec.hs:63-74`: `parameterDefault` serialises as `"default"` only when set.
- `doc/reference/types/typically-example.l4` (type-checked by `doc/test-docs.sh`); pages `doc/reference/types/TYPICALLY.md` and `doc/courses/advanced/module-a4-production.md` §"Default values with TYPICALLY".

## Limits and known defects at H (verified)

- **Defect: a same-module enum constructor as a DECLARE-field default is rejected.**
  `DECLARE Colour IS ONE OF Red, Green` then `DECLARE Thing HAS c IS A Colour TYPICALLY Red` draws two errors: "must be a literal" (reported at `Thing`'s name, 2:9-2:14) and "could not find a definition for the identifier Red" at 3:27-3:30.
  Measured with an H-era `l4`, and reproduced on this branch.
  The same default on a GIVEN checks clean (measured), and the checker's own comment (`TypeCheck.hs:1734-1736`) says enum constructors are allowed.
  Read in code: field defaults are checked inside `inferSelector` during type-declaration checking, where `Red` does not resolve; the out-of-scope sentinel then fails `isTypicallyLiteral`.
  Before resolution-diagnostics (`daa7ee180`, a later position) the same input also drew an internal "resolved name that has no additional information … should be reported as a bug" error; three errors were measured on main plus #92.
- **Defect: a TYPICALLY on a computed (MEANS) field is discarded unchecked.**
  `t IS A NUMBER TYPICALLY "oops" MEANS p * 2` checks clean, while the same default on a stored field is a type error (both measured).
  Read in code: `desugarCFDeclare` removes computed fields before type checking and `makeComputedDecide` ignores the default (`jl4-core/src/L4/Desugar.hs:309,336 @ 73a953821`).
- The "must be a literal" error on a DECLARE field is reported at the record type's name, not at the value (`not-ok/tc/tests/typically-non-literal.golden`, range 4:9-4:14 on `Flags`).
- `NOTHING` and enum-constructor defaults never reach a schema (read in code; measured with `jl4-schema` on main plus #92).
- jl4-service's deployed-function schema drops top-level GIVEN and ASSUME defaults: `paramToParameter` never reads `paramDefault` (`jl4-service/src/Compiler.hs:509-518 @ 73a953821`, read in code, not run).
  Defaults on the fields of a record-typed input do reach it, through `typeToParameter`.
- Doc drift at H: `doc/reference/types/TYPICALLY.md:92-94` says the published list of facts carries the default as JSON Schema `default`, which the previous point contradicts for the service; `module-a4-production.md:353` says "the generator prefills the field", and no in-repo generator does; `TYPICALLY.md:28-29` and `:80` say the default is always type-checked against its type, which the computed-field defect above contradicts; `TYPICALLY.md:33-34` says a default always needs an explicit type, which the untyped ASSUME and lambda GIVEN cases contradict (corrected in this branch).
- Cosmetic: `HasRef (TypedName)` binds field 4 as `mExpr` and field 5 as `typically`, the reverse of their meaning (`jl4-core/src/L4/Parser/ResolveAnnotation.hs:1599 @ 73a953821`); both are traversed and rebuilt in place, so it is harmless.

## Later changes before H (one line each)

- #110 threads Boolean defaults into `jl4-query-plan` as priors and adds a `typically` field to VizExpr's `UBoolVar` (described elsewhere).
- #344 makes a section GIVEN's default operational (`Discharge.fillInDefault`); the comment "nothing consumes it at runtime" (`TypeCheck.hs:1725`) is stale at H for that reason.
- #358 carries a TYPICALLY clause across in the ASSUME deprecation warning's suggested `GIVEN` line (`assumeReplacementLine`, `TypeCheck.hs:874-891`).
- #53 (inside #77, sub-step 77.14) predates #92 on unstable but comes later in this carve; it is what makes `typically-basic.schema.golden` show `"type": "number"`, where main renders a builtin as a `$ref`.
- #336, #337, #349 and #357 edited fixture text and diagnostic wording; `typically-on-type.l4` now uses a section GIVEN.
