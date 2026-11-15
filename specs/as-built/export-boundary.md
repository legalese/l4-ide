# The export boundary: which types an `@export` may take and give back (as built)

Status: built on the branch `carve/export-boundary`, the pull request legalese/l4-ide#779 against `main`; it follows legalese/l4-ide#769, which merged into `main` on 2026-10-30; not on `main` or `unstable` yet.
Source spec: none.
The shape of the change is the second part of the review of legalese/l4-ide#738 (serrynaimo, 2026-10-29, sections 3 and 4), which Meng ruled to build as specified on 2026-10-30.
This page describes what the branch has.
Reading the inputs of an exported rule from its signature, with a record of which assumptions each definition reaches (the review's section 4), is not in this change: it is proposed, not landed, and is listed under "Not here".

Scope: `jl4-core/src/L4/Export/Shape.hs` (new), `jl4-core/src/L4/Export.hs`, the two schema generators (`jl4-core/src/L4/FunctionSchema.hs`, `jl4-core/src/L4/JsonSchema.hs`), the editor's rule `ExportCheck` (`jl4-lsp/src/LSP/L4/Rules.hs`), the commands `l4 check`, `l4 deploy` and `l4 batch`, `jl4-schema`, `jl4-mlir`, `l4_check` and the web editor's transport, the sidebar's list of exports, and the deploy gate in `jl4-service/src/Compiler.hs`.

## What it does

- One function, `jsonShape` (`jl4-core/src/L4/Export/Shape.hs:207`), decides whether a type has a form in JSON, and says why when it has none.
  The table is the header comment of that module.
  `NUMBER`, `BOOLEAN`, `STRING`, `DATE`, `TIME`, `DATETIME`, `LIST OF`, `MAYBE`, `EITHER` of two types that have shapes, a record, an enumeration, a synonym and a type with parameters have a shape.
  A function, an `EVENT`, a `DEONTIC`, a type variable and any other built-in type that nobody gave a row have none.
  A type that takes a type has none when what it is given has none, used or not (`Box OF (FUNCTION FROM NUMBER TO NUMBER)`; `UInArgument`). `main` refuses that of a function or an `EVENT` written in an input's type, and this refuses it inside a declaration too.
- `checkExports` (`jl4-core/src/L4/Export.hs:557`) asks it about every input and the result of every `@export`.
  An input is a `GIVEN`, or an `ASSUME` of the module that the body of the rule reads itself.
  The result is the written `GIVETH`, or the inferred type when there is none.
- A result that is a `DEONTIC` itself is not asked about: it is a contract, and is published (`isContractResult`, `Export.hs:538`; ROCKINGCHAIR, see "Revisit").
  The test is the one the service uses to decide that a function is a contract, and takes it to its `startTime` and `events` path: a `TyApp` of the `DEONTIC` built-in with two arguments, by unique, so `PROVISION` too.
  It reads the type as written, so a result written with a declared name for a `DEONTIC` (`GIVETH A Duty`, `DECLARE Duty IS A DEONTIC Party Act`) is not a contract to the service: `main` deploys one as a plain function and answers `startTime` with "startTime and events are only valid for functions returning DEONTIC" (measured on 2026-11-15).
  The check refuses it with words of its own, which say to write the `DEONTIC` type out (`contractUnderName`).
  The service's and `jl4-mlir`'s `isDeonticType` now call it.
  A `DEONTIC` input, and a `DEONTIC` inside a `MAYBE`, a `LIST`, an `EITHER`, a declared synonym, a record's or a constructor's field, or a type's argument, have no shape and are refused, with the code `check/export-deontic-type`.
- A type with no shape is the error `ExportUnsendable`, ranged at the `@export`, saying which input or the result, what it is, and one line on what to do.
  The wording is "is ..., and @export does not support that yet", because the infrastructure that would carry these types is not built.
- A type that did not resolve, or was given the wrong number of arguments, is not reported: the type check says so already, in the module it is written in, and that is the error to read (`isUnresolved`).
- A `GIVEN` with no written type is the warning `ExportUntypedGiven`.
  A warning does not refuse the `@export`.
- The check is its own pass and not a part of type checking.
  An error of the type check stops the file from evaluating anything (`success` in `Rules.hs`, read by `SuccessfulTypeCheck`), so a refused `@export` that was a type error would blank the `#EVAL` and `#EVALTRACE` of every rule in the file, the contract rules that the author tests there included.
  Here the file still checks and its rules still evaluate.
- Where the errors show:
  - the editor publishes them as diagnostics with the source `export` (`exportErrorToDiagnostic`, `jl4-lsp/src/LSP/L4/Rules.hs:1441`), kicked with the type check (`jl4-lsp/app/LSP/L4/LanguageServer.hs:349`);
  - the Deploy button refuses on them, because `isBlockingDiagnostic` (`jl4-lsp/src/LSP/L4/BlockingErrors.hs:35`) blocks on every error except those with the source `eval` or `import`, and `l4/getExportedFunctions` runs the check itself before it reads the diagnostics (`jl4-lsp/app/LSP/L4/Handlers.hs`);
  - the sidebar's list of exports leaves a refused rule out (`Export.withoutRefused`), and sets `isDeontic` for a contract rule with `isContractResult`, where `main` looked for the text "DEONTIC" in the printed return type (`Inspector.hs`), so a `PROVISION` result is now flagged as the service flags it (assumed, not ruled);
  - `l4 check` and `l4 deploy` run the rule (`jl4/app/L4/Cli/Check.hs:55`, `jl4/app/L4/Cli/Deploy.hs:286`) and exit 1 on an error; `l4 run` does not run it, so it still runs the file; `l4 batch` asks it about one thing, an input of the rule it is about to call with a function in it, which a row cannot hold, and refuses in the check's words (assumed, not ruled), and it still runs the rest of what the check refuses (`functionInputs`, `jl4/app/L4/Cli/Batch.hs`);
  - `jl4-mlir wasm` refuses on them with the same words (`typecheckL4File`, `jl4-mlir/src/L4/MLIR/Pipeline.hs`), so it accepts what the service accepts: a result that is a `DEONTIC` itself compiles, and its JS runtime evaluates the contract from the schema, which `jl4-mlir/README.md` documents;
  - the web editor's WebAssembly build gets them from `l4_check` (`L4.API.l4Check`, `exportErrorsOf`), with the source `export`, and only for a file that type-checks, as in the language server, and its transport (`wasm-message-transports.ts`) still evaluates the file beside them;
  - `jl4-service` builds the same errors in its deploy gate (`jl4-service/src/Compiler.hs:194`) and refuses the bundle, with the same words, once the module has no type errors: as in the editor, a module that does not type-check is not asked what its exports take and give back.
- Both schema generators render the shape the check gives a type, so an `@export` that the check accepts is described as the check sees it:
  - `typeToParameter` (`jl4-core/src/L4/FunctionSchema.hs`) writes the schema that `jl4-service` publishes, that the editor's sidebar lists and that `jl4-mlir` writes for an input; `shapeToParameter` writes a shape out.
  - `generateJsonSchema` (`jl4-core/src/L4/JsonSchema.hs`) writes `jl4-schema`'s, with each declared type once under `$defs`; a type with parameters is named there with what it is given (`Box OF NUMBER`), since each of those has fields of its own.
  - A record that contains itself refers to its own definition. One that contains itself given a larger type (`next IS A MAYBE (Grows OF (LIST OF a))` in `Grows a`) would need a definition for each size; in `jl4-schema` it is `{"type": "object"}` past the first, as the service writes it, rather than a `$ref` to a definition that is not there (assumed, not ruled).
  - Each reads the declarations the check reads, the module's and every module it imports, so an imported type has its definition (it was a `$ref` to a definition not in the file in 7,272 of the 33,904 exports of `legalese/commons`); a synonym is written as the type it stands for; a constructor that carries fields is one of the constructors' names in both, which is what the service has published (`jl4-schema` wrote a `oneOf` of objects with a `tag`, which no decoder reads); and the `@desc` of a declaration or a field is carried as before.
  - A type with no shape has no schema: `typeToParameter` and `generateJsonSchema` say why (`Left`). `jl4-schema` then exits 1 and names the input. The service, the sidebar and `jl4-mlir` publish `{"type": "object"}` for it (`uncheckedParameter`), which they reach only for an input the check did not look at: one read from a name the module never declared, or a type that did not resolve, whose own error stops the deploy.
  - An `EITHER` is written as the encoder writes it, `{"LEFT": [v]}` or `{"RIGHT": [v]}`: the wire-form bench ("Wire Form of Sums"), card J3, ruled by Meng on 2026-10-15 as option B.
    In `jl4-schema` it is a `oneOf` of `{"LEFT": array of a}`, `LEFT` required, and `{"RIGHT": array of b}`, `RIGHT` required (`eitherSchema`).
    A `Parameter` has no `oneOf`, and adding one would change the format of the schemas the service stores, so in the service's schema it is an object with the two keys, each an array of its side, and neither required (`eitherParameter`).
    It was `{"type": "object"}` in both.
- The two checks of the previous change, the function-typed input and the `EVENT`, are gone from the type check (`ExportFunctionTypeInput`, `ExportEventType`) and are cases of the one check.
  So a function-typed input no longer stops the file from checking either.

## Where it lives

- `jl4-core/src/L4/Export/Shape.hs`: `JsonShape`, `Unsendable`, `ShapeEnv`, `jsonShape`, and the two functions that word a reason, `unsendableWhat` and `unsendableHint`.
  Types are looked up in the declarations of the module and of everything it imports (`moduleDeclares`), and a record that contains itself stops at `JRecursive`.
  Whether a type has a shape is worked out by reading each declaration once, with its parameters taken as fine, and each type argument where it is written, whether or not the parameter is used (`firstUnsendable`). No type is instantiated, so the cost is that of reading the source.
  The shape itself (`expand`) is a tree that writes a declared type out, with its arguments filled in, on every path to it, so it is built only as far as something looks at it: the check discards it, `typeToParameter` walks all of it, and `generateJsonSchema` stops at a declared type, with its arguments, that it has written already.
- `jl4-core/src/L4/Export.hs`: `ExportError` and `ExportSite` (`:461`, `:452`), `checkExports`, `checkOneExport` (`:615`), `isContractResult` (`:538`), `withoutRefused` (`:565`), `refusalsOf`, `prettyExportError` (`:514`); `inferredReturnType` (`:175`) gives the result of a definition without a `GIVETH`.
- `jl4-service/src/Compiler.hs`, `jl4-lsp/src/LSP/L4/Rules.hs` (the key `ExportCheck`, `:192`) and the two commands use it; none of them has a check of its own.

## How it is pinned

- `jl4-core/test/ExportValidationSpec.hs` is rewritten around `checkExports`.
  It refuses a function-typed `GIVEN`, an `ASSUME` of function type that the body reads, and a function inside `MAYBE OF` or behind a synonym; an `EVENT` input, a written and an inferred `EVENT` result, an `EVENT` in `LIST OF`, `MAYBE OF`, behind a synonym or in an `ASSUME` that the body reads; a `MAYBE`, `LIST`, `EITHER` or declared synonym of a `DEONTIC` result, and a `DEONTIC` input; a record with a function among its fields (and says which); a constructor with a `DEONTIC`, a function or an `EVENT` among its fields (and says which); and an `EITHER` with a function on one side.
  It accepts a result that is a `DEONTIC` itself, written, inferred or a `PROVISION` (and the file still type-checks), value-typed inputs, a record, an enumeration, a `LIST OF`, a `MAYBE OF` and a `DATE`, a record that contains itself, an `EVENT` that the body builds but the signature does not name, an `EVENT` in a rule that is not `@export`, a type of the user's own called `EVENT`, an enumeration whose constructors carry fields, an `EITHER` of two types that have shapes, and a function-typed `ASSUME` that no export reads.
  It pins the words for a result written with a declared name for a `DEONTIC`, through two names or one with a parameter, and that a synonym of a `MAYBE` of one, or such an input, keeps the words of a `DEONTIC`.
  It warns about a `GIVEN` with no written type, and does not refuse it.
- `jl4-core/test/SchemaBuiltinNameSpec.hs`, "both generators render the shape the export check gives a type": an `EITHER STRING NUMBER` input is a `oneOf` of `LEFT` with an array of strings and `RIGHT` with an array of numbers in `jl4-schema`, and an object with the two arrays, neither required, in the service's, with no dangling `$ref`; `Box OF NUMBER` and `Box OF STRING` are two definitions with the fields of each, and the field's `@desc`; a constructor that carries fields is the constructors' names, with the declaration's `@desc`. The same file pins that an imported type has its definition, and that a module's own `Optional NUMBER` is a `$ref` to `Optional OF NUMBER`.
- Four `.schema.golden` files changed with the generators: `ok/export-schema-shapes` and `ok/schema-own-optional` (a constructor that carries fields is the constructors' names), and `ok/schema-synonym-chain` and `ok/schema-synonym-shapes` (a synonym is written as what it stands for, not as a `$ref` to a definition of it).
- `jl4/examples/ok/export-unsendable-types.l4` and its goldens (in `ok/` because the file type-checks, with the three export-placement fixtures that were in `not-ok/` beside it): one error for each rule that cannot be sent (an `EVENT` input, an `EVENT` result, a `MAYBE` of a `DEONTIC` result, a function input), one warning for the `GIVEN` with no written type, and nothing for the rule that publishes, the contract rule whose result is a `DEONTIC` itself, and the rule that only builds an `EVENT` in its body.
  The golden harness (`jl4/tests/Main.hs`) prints the export errors after the type-check errors, with the prefix `[export error]` or `[export warning]`, and the `#EVAL` of the refused `MAYBE` of a `DEONTIC` at the end of the file still has its result there.
- `jl4/examples/ok/tests/desc.golden` and `pattern-matching-overloads-own-annotations.golden` gained the warning for a `GIVEN` with no written type.
- `jl4/examples/legal/ceo-performance-award.l4`: its `@export` on a rule that returns a `DEONTIC` is as on `main`, and its schema golden is byte-identical to `main`'s and to what `main`'s `jl4-schema` writes for it; see the revisit note below.
- `jl4-core/test/ExportValidationSpec.hs` also pins, under a timeout: records whose two fields share a record type at 64 levels, 14 records that each have a field of every one of them, and a type that passes what it was given on twice at 40 levels.
  It pins a type that passes two different types on at 64 levels and one that passes a function on twice and never uses it at 64, the shape of a record in a cycle from each place it is reached, a parameter given what has no shape, used or not, and the path named for `Box OF (Box OF ...)`.
  It pins the words for a generic rule, a generic `ASSUME` and a result with no `GIVETH`, and what `l4_check` reports (`L4.API.l4Check`).
- `jl4-mlir/test/Main.hs` compiles files through `compileToMLIR`: an `EVENT`, function or `DEONTIC` input, a record with a function field, a generic rule and a `MAYBE`, `LIST`, `EITHER` or synonym of a `DEONTIC` result are refused, and a `DEONTIC` result is compiled, as the service deploys it.
- `jl4/tests-cli/Main.hs` pins that `jl4-schema` refuses an export the check refuses, by default and by name, and writes the schema of another export of that file.
  It pins that `l4 batch` refuses an input with a function in it and still runs a `DEONTIC` result and an `EVENT` input, and that a broken import gives no export error.
- `jl4-service/test/IntegrationSpec.hs`: a bundle with an `@export` that takes an `EVENT`, returns an `EVENT`, or returns a `MAYBE` or a `LIST` of a `DEONTIC`, or a type with a constructor whose field is a `DEONTIC`, is refused, with the new words.
  The tests that deploy a contract rule are as on `main` (21 `it` blocks, 26 examples: "deontic evaluation", "deontic answers spell a party and an action one way", "deontic evaluation with record-typed parties", the contract cases of the MAYBE-input bundle, and the missing-input case of a deontic rule); `25fc9d3c9` removed them with the refusal, and they are back with ROCKINGCHAIR.
  An `EITHER` input is read as `{"RIGHT": [5]}` and `{"LEFT": ["x"]}` on the direct path and in a record's field on the wrapper path, and an object in neither form is refused.

## Measured

`l4 check` with a build of this change against a build of `main` at `8500b4d21`, on 2026-11-14, over the files that contain `@export`, with every diagnostic compared.

- This repository, 97 files, 95 of which check on `main`: no exit code changes, and three files change: the fixture `ok/export-unsendable-types.l4`, and `ok/desc.l4` and `ok/pattern-matching-overloads-own-annotations.l4` (the untyped-`GIVEN` warning).
  `jl4-mlir/test/fixtures/deontic-sale.l4`, `deontic-seatbelt.l4` and `deontic-breach.l4`, whose results are a `DEONTIC` itself, do not change.
- `legalese/commons` at `bdc8fc5b9`, 1,378 files, 1,306 of which check on `main`: no exit code changes, and no export diagnostic is added or removed.
  13 files' output differs, in the order of their imports' diagnostics, and two runs of the same binary differ the same way (measured on one of them with `main`'s build and on another with this change's).
  The seven Jersey charities files that, measured on 2026-11-04 with the refusal, gained 42 `DEONTIC` export errors gain none: each `DEONTIC` that an `@export` in `subjects/je/charities-2014` returns is the result itself.
- No `@export` in either corpus returns a `MAYBE` or a `LIST` of a `DEONTIC` (a search of the source three lines below each `@export`).
- Neither corpus has a file whose answer changes because a type argument with no shape is refused whether or not the parameter is used.
- Untyped-`GIVEN` warnings: none in `legalese/commons`, three in this repository (the two files above and the fixture).
- Refusing `EITHER` was measured on 2026-10-30 and broke one file in each of the two (the reason it is not refused, under "Limits").
- Stored deployments are not counted here.
  The reviewer's production verification found 2 that export a `DEONTIC` result, in 2 orgs, on 2026-11-14.
  The service compiles each stored deployment afresh at startup, as a deploy compiles it (`jl4-service/src/DeploymentLoader.hs:38-46`), so a deployment that the check refused would be registered as failed after a restart.

The service, measured on 2026-11-14 with a build of this change against one of `main` at `8500b4d21`, over 10 bundles: the three `jl4-mlir` contract fixtures above, `jl4/examples/legal/ceo-performance-award.l4`, and the six bundles of the contract tests in `jl4-service/test/IntegrationSpec.hs`.
`main` deployed them, and then this change served them three ways: recompiled at startup from a copy of `main`'s store, then `PUT` over themselves through the compatibility gate, and deployed afresh to an empty store.
Compared each time: each deployment's metadata (with `functions=full`), its functions and each function's schema, its `openapi.json` and the org's, MCP `tools/list`, and 34 evaluations with `startTime` and `events`, 19 batches and 34 MCP `tools/call`s, with the same requests on both sides (the cases of the `jl4-mlir` fixtures and of the tests, and otherwise arguments built from the published schema).
Nothing differs but `createdAt`, the server's URL, and, after the `PUT`, the deployment version, from `0.0.0` to `0.0.1`: every `PUT` was applied, and counted as not breaking.
Of the 34 evaluations, 32 answer and 2 fail alike on both: a missing input that the test expects, and the `ceo-performance-award` rule given made-up events, which fails with a type error in the generated code.

What stays refused does not come back after a restart, measured the same day the same way: `main` deploys an `@export` whose result is a `MAYBE`, a `LIST` or a declared synonym of a `DEONTIC`, as a function that is not a contract (no `startTime` or `events`, `isDeontic` false, a `returnSchema` of `{"type": "object"}` or an array of objects), and answers it with the contract as it stands.
This change, started on a copy of that store, registers each of the three as `failed`, "Compilation failed".
The same holds, measured on 2026-11-15, for a result whose constructor has a `DEONTIC` field, which `main` answers with the contract inside it.
So a stored deployment of that kind would stop answering after a restart; whether either of the 2 the reviewer found is one is not known here.

The schemas, measured on 2026-11-14 with a build of `6fe8598ae` against one of this change, over every file with an `@export` in this repository (99 files, 163 exports) and in `legalese/commons` at `bdc8fc5b9` (1,378 files, 33,904 exports), comparing what `jl4-service` publishes for each input and result and what `jl4-schema` writes, export by export:

- The service's schema changes for 49 exports, in 11 `legalese/commons` files whose imported modules have errors of their own (`je/charities-2014` g6 and g7, which import `g6-interpretation` and `g7-interpretation`; `il/hvac-work-licensing-2025` `int-sanction`, which imports `g1-adverse-action`). An input whose record has a field of a type with such an error is now `{"type": "object"}`, where it was the record written out; a bundle with those imports in it is refused at deploy, for their errors. Nothing else the service publishes changes, in either corpus.
- `jl4-schema` changes for 7,298 exports: 7,214 gain the definitions of the imported types they referred to, and no longer refer to a definition that is not in the file; 26 write a constructor that carries fields as the constructors' names (9 of them gain imported definitions too); 9 write a synonym as what it stands for, and are the same once every `$ref` is followed; and 49 are the 49 above, for which it now names the input and writes no schema.
- With every `$ref` followed, `jl4-schema` and the service now describe the inputs of every export alike, except three whose input has no written type, which `jl4-schema` calls a string and the service an object. Before, they differed for 7,292 exports.
- `EITHER` is the input of no export in either corpus, and the result of 7.
  These schemas were measured before card J3's form of an `EITHER` was built (`761ca37ff`), which changes the service's `returnSchema` of those 7 exports, and before ROCKINGCHAIR: the comparison skipped the exports that the check refused then, the contract rules among them, and was not re-run over the corpora; the contract rules' schemas are compared with `main` in the service measurement above, over its 10 bundles.

Types that nest, against `main`, measured on 2026-11-04: `l4 check` and `jl4-schema` are within 0.15 s of `main` on every size tried, from 0.03 s (a type that passes two different types on, `LIST OF a` and `MAYBE a`, 24 levels) to 1.3 s (records with two fields of the next one down, 4,000 levels).

## Revisit

The refusal of an `@export` on a rule that returns a `DEONTIC` was built as provisional.
Meng, 2026-10-30, ruling that part B be built as the reviewer specified:

> go ahead and do part B as specified by the reviewer, with a note that we may revisit this decision in the future when we have a better way of answering “here’s a view of the residual, shortened to immediate next actions — immediate obligations on parties and deadlines, plus your MAY options, and your SHANT prohibitions”

On the same day, about the example `ceo-performance-award.l4`, relayed through the general manager session:

> if/when we reopen this, we’ll come back to the ceo-performance-award. i’d still like to expose the head of the residuals.

Meng, 2026-11-14, typed the word ROCKINGCHAIR to rule:

> Option B (defer the refusal): an @export whose result is a bare DEONTIC is accepted on every surface (service via its existing contract path, l4 check, editor, jl4-mlir as now), until the residual view of Meng's 10-30 note exists; a MAYBE/LIST/EITHER/synonym of a DEONTIC stays refused; restore the service tests removed for the refusal; README, errors page and as-built spec say so, with the count 2. MCP and batch still drop a contract's trace on main (10-26 report; #766 closed 10-30 on the count of 0) and that stays a Limit, not fixed here.

So a result that is a `DEONTIC` itself is accepted (`isContractResult`), `ceo-performance-award.l4` has its `@export` again, and `unsendableHint` speaks of a `DEONTIC` input or one inside another type.
The count of stored deployments that export a `DEONTIC` result is 2, found by the reviewer's production verification on 2026-11-14, in 2 orgs.
The service's path for contract rules (`startTime` and `events` arguments, `runDeonticEvaluatorFor`, `jl4-service/src/DataPlane.hs`) is what those deployments, and any new one, deploy through.

## Limits

- The schema renders the shape, and the service's decoder and encoder do not follow it: they decide on their own, by reading the type, how a value is read and written (`jsonValueToWHNFTyped`, `jl4-core/src/L4/EvaluateLazy/Machine.hs:1301`; `fnLiteralToExprTyped` and `valueToFnLiteral`, `jl4-service/src/Backend/Jl4.hs`). Where they differ from the schema (`JSONDECODE` measured on 2026-11-14 with `l4 run` of a build of this change; the rest read from the code):
  - An `EITHER` input is read in the form the schema gives it, `{"RIGHT": [5]}` or `{"LEFT": ["x"]}`, by the service's direct path (`fnLiteralToExprTyped`) and by `JSONDECODE`, which the wrapper path uses (assumed, not ruled: it implements J3-B on input; measured on 2026-11-15 on the running service and with `l4 run`).
    A bare value is read as on `main`: `5` reaches the rule as the number, without its side, so a `CONSIDER` on it finds no branch.
    An object in neither form is refused on the direct path ("an EITHER is written {"LEFT": [value]} or {"RIGHT": [value]}") and is `NOTHING` to `JSONDECODE`, as on `main`.
    On `main` and here alike, the wrapper path fails for an `EITHER` input itself, before it decodes anything: its generated code writes the type as `MAYBE EITHER OF STRING, NUMBER`, which does not parse, so a contract rule with an `EITHER` input, and any call that takes the wrapper (a `null` among the values, in `/evaluation` or a batch case), fails with that parse error (measured); an `EITHER` in a record's field is read there.
    `JSONENCODE` writes an `EITHER` without the array, `{"RIGHT": 5}`, which `JSONDECODE` does not read as one (measured with `l4 run`).
    The answer is written `{"RIGHT": [v]}` or `{"LEFT": [v]}`, as the schema says.
  - The service's schema of an `EITHER` cannot say that exactly one of `LEFT` and `RIGHT` is there, because a `Parameter` has no `oneOf`; `jl4-schema`'s says so.
  - Card J2 is ruled (J2-A, Meng, 2026-10-15: `returnSchema` takes the record envelope `{"Rec": {...}}` that the encoder writes, at every depth), and not built: `returnSchema` does not show the envelope the encoder writes at every depth (`{"Pair": {"left": 2, "right": 2}}` is answered where `returnSchema` lists `left` and `right` at the top; smucclaw/l4-ide#1010).
    It is not built because it would refuse redeploys: a stored deployment's metadata keeps its `returnSchema`, and the compatibility gate (`detectBreakingChanges`, `jl4-service/src/Compatibility.hs`) reports each field of the old schema that is not a field of the new one as "no longer returned" (`checkOld` in `diffObject`, `:184-189`), so a `PUT` of an unchanged bundle that returns a record would be refused as breaking, and a `POST` over it would bump its BREAKING version (`isBreaking`, `jl4-service/src/ControlPlane.hs:476-479`).
    That is read from the code, not run.
    A record input sent in the envelope is not accepted either: `{"p": {"Pair": {"left": 5, "right": 6}}}` is refused with "Parameter 'p': missing required parameter", where `{"p": {"left": 5, "right": 6}}` answers (measured).
  - Card J1 is ruled (J1-A, Meng, 2026-10-15: a constructor that carries data is tagged externally, `{"Circle": {"radius": 2}}`), and not built: the schema lists the constructors' names, as the service publishes them today.
    Of those names, `JSONDECODE` reads one that carries no fields (`"Dot"` is `Dot`); one that carries fields comes back as the string (`"Circle"` is `"Circle"`), and `{"Circle":{"radius":2}}` as `NOTHING`.
    The service, on `main` and here alike (measured on 2026-11-15), reads `"Dot"`, gives the rule `"Circle"` as a constructor without its field, or on the wrapper path as the string, so that no `WHEN` matches it, and refuses `{"Circle": {"radius": 2}}` and `{"radius": 2}` on the direct path ("FnObject but expected type is not a known record"), where the wrapper path makes them `NOTHING`.
    The answer is written in the tagged form, `{"Circle": {"radius": 2}}`.
  - A record that takes a type (`Box OF NUMBER`) is not read as a record by `JSONDECODE`, which looks only at a type with no arguments: `{"contents":5}` decodes to `NOTHING`.
- The schema `jl4-schema` writes for a type with parameters has one definition for each type it is given. A type that passes two different types on (`T OF (LIST OF a)` and `T OF (MAYBE a)` in each declaration) has twice as many at each level: measured on 2026-11-14, 220 KB at 8 levels, 4 MB at 12 and 75 MB in 3.4 s at 16, where `6fe8598ae` wrote 6 KB that referred to a definition, `a`, that is not in the file. The service's schema of that type doubled already (below).
- A constructor that carries fields has the shape of an enumeration of the constructors' names, which is what the schema publishes today.
  The wire-form bench (`l4-wire-form-1015`) ruled the tagged shape as the target (card J1, option A, 2026-10-15), and this change does not build it (above).
  Its fields are looked at, as a record's are: one with a field of a type that has no shape, a `DEONTIC` among them, is refused (`UInConstructor`).
  A constructor whose fields all have shapes is not refused: `jl4-service-test` deploys a function whose result is one (smucclaw/l4-ide#1003, `wireProbeJL4`), and `legalese/commons` at `bdc8fc5b9` has 130 `@export` inputs and 1,868 results of such a type, directly or inside another, and this repository 2 inputs (measured on 2026-11-15 with a build that refused them all).
- A built-in type nobody gave a row to is refused, as the review asked.
- The schema that the service publishes and the editor's sidebar lists (`typeToParameter`) writes a record out in full on every path to it, so it doubles at each level of the nesting that `jsonShape` no longer doubles on, as it does on `main`.
  Measured on 2026-11-04 through `jl4-core-test`, encoding one input's parameter: 14 MB in 0.5 s at 16 levels, 226 MB in 9.3 s at 20, 906 MB in 37 s at 22.
  A bundle of that kind is refused by the service from 18 levels with "compilation timed out or exceeded the memory limit", in under a second, on `main` and on this branch alike (at 12 and 16 levels it deploys, on both), and so is the type that passes two different types on, from 18 levels (at 14 it deploys, on both).
  That is consistent with the size of the schema measured here, and it was not confirmed.
  The wire form of the schema is what would have to change, and that is not done here.
- On `main` and here alike, an MCP `tools/call` and `/evaluation/batch` ignore a contract's `startTime` and `events`, with no error, and answer with its opening obligation; only `/evaluation` replays them (measured on 2026-11-14, on both builds: the events that make `/evaluation` answer `FULFILLED` give the opening `OBLIGATION` through both).
  ROCKINGCHAIR keeps that a limit, not fixed here (the 10-26 report; legalese/l4-ide#766 was closed on 2026-10-30 on the count of 0).
- `EITHER` has the shapes of its two sides and is not refused.
  The schema writes it as the service answers it (card J3, option B), and the decoders read it in that form (above).
  `jl4-mlir` answers an `EITHER` input wrongly and fails on an `EITHER` result, with the schema of this change and with the one before it alike (measured on 2026-11-14 with `jl4-mlir run` of a build of this change, the earlier schema written into the `.schema.json` by hand): a rule that answers `n` for `RIGHT n` answers `0` for `{"RIGHT": [5]}` and for `5`, and a rule that returns `RIGHT n` stops with "unresolved runtime symbol 'RIGHT'".
  Refusing it was measured to break two files that check today: `subjects/il/hvac-work-licensing-2025/encodings/legalese-full-sonnet-5.5/g1-register.l4` in `legalese/commons` and `jl4/experiments/thailand-cosmetics/orchestrator.l4` in this repository.
- An `ASSUME` is looked at only when the body of the exported rule reads it itself; an `ASSUME` that the body reaches through a helper or an import is not looked at.
  That is the review's section 4, and it is not here.

## Not here

- The record of which assumptions each definition reaches, and the error that says "via helper reads ASSUME X through Y; pass it in as a GIVEN".
- A written type on every exported `GIVEN` as an error: it is a warning, until the count of stored deployments with an untyped exported `GIVEN` is taken (review, section 8).
- The decoder and the encoder following a `JsonShape`.
- The specification of exports of contract rules on stream infrastructure (the review's section 5), which extends `specs/todo/STATEFUL-CONTRACT-DEPLOYMENT.md` and is written after this change.
