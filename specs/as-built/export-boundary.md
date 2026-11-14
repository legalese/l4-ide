# The export boundary: which types an `@export` may take and give back (as built)

Status: built on the branch `carve/export-boundary`, the pull request legalese/l4-ide#779 against `main`; it follows legalese/l4-ide#769, which merged into `main` on 2026-10-30; not on `main` or `unstable` yet.
Source spec: none.
The shape of the change is the second part of the review of legalese/l4-ide#738 (serrynaimo, 2026-10-29, sections 3 and 4), which Meng ruled to build as specified on 2026-10-30.
This page describes what the branch has.
Reading the inputs of an exported rule from its signature, with a record of which assumptions each definition reaches (the review's section 4), is not in this change: it is proposed, not landed, and is listed under "Not here".

Scope: `jl4-core/src/L4/Export/Shape.hs` (new), `jl4-core/src/L4/Export.hs`, the two schema generators (`jl4-core/src/L4/FunctionSchema.hs`, `jl4-core/src/L4/JsonSchema.hs`), the editor's rule `ExportCheck` (`jl4-lsp/src/LSP/L4/Rules.hs`), the commands `l4 check`, `l4 deploy` and `l4 batch`, `jl4-schema`, `jl4-mlir`, `l4_check` and the web editor's transport, the sidebar's list of exports, and the deploy gate in `jl4-service/src/Compiler.hs`.

## What it does

- One function, `jsonShape` (`jl4-core/src/L4/Export/Shape.hs:165`), decides whether a type has a form in JSON, and says why when it has none.
  The table is the header comment of that module.
  `NUMBER`, `BOOLEAN`, `STRING`, `DATE`, `TIME`, `DATETIME`, `LIST OF`, `MAYBE`, `EITHER` of two types that have shapes, a record, an enumeration, a synonym and a type with parameters have a shape.
  A function, an `EVENT`, a `DEONTIC`, a type variable and any other built-in type that nobody gave a row have none.
  A type that takes a type has none when what it is given has none, used or not (`Box OF (FUNCTION FROM NUMBER TO NUMBER)`; `UInArgument`). `main` refuses that of a function or an `EVENT` written in an input's type, and this refuses it inside a declaration too.
- `checkExports` (`jl4-core/src/L4/Export.hs:521`) asks it about every input and the result of every `@export`.
  An input is a `GIVEN`, or an `ASSUME` of the module that the body of the rule reads itself.
  The result is the written `GIVETH`, or the inferred type when there is none.
- A type with no shape is the error `ExportUnsendable`, ranged at the `@export`, saying which input or the result, what it is, and one line on what to do.
  The wording is "is ..., and @export does not support that yet", because the infrastructure that would carry these types is not built.
- A type that did not resolve, or was given the wrong number of arguments, is not reported: the type check says so already, in the module it is written in, and that is the error to read (`isUnresolved`).
- A `GIVEN` with no written type is the warning `ExportUntypedGiven`.
  A warning does not refuse the `@export`.
- The check is its own pass and not a part of type checking.
  An error of the type check stops the file from evaluating anything (`success` in `Rules.hs`, read by `SuccessfulTypeCheck`), so a refused `@export` that was a type error would blank the `#EVAL` and `#EVALTRACE` of every rule in the file, the contract rules that the author tests there included.
  Here the file still checks and its rules still evaluate.
- Where the errors show:
  - the editor publishes them as diagnostics with the source `export` (`exportErrorToDiagnostic`, `jl4-lsp/src/LSP/L4/Rules.hs:1438`), kicked with the type check (`jl4-lsp/app/LSP/L4/LanguageServer.hs:349`);
  - the Deploy button refuses on them, because `isBlockingDiagnostic` (`jl4-lsp/src/LSP/L4/BlockingErrors.hs:35`) blocks on every error except those with the source `eval` or `import`, and `l4/getExportedFunctions` runs the check itself before it reads the diagnostics (`jl4-lsp/app/LSP/L4/Handlers.hs`);
  - the sidebar's list of exports leaves a refused rule out (`Export.withoutRefused`), so a contract rule is no longer listed with `isDeontic` set; the text test for "DEONTIC" in the printed return type (`Inspector.hs`) is gone;
  - `l4 check` and `l4 deploy` run the rule (`jl4/app/L4/Cli/Check.hs:55`, `jl4/app/L4/Cli/Deploy.hs:286`) and exit 1 on an error; `l4 run` does not run it, so it still runs the file; `l4 batch` asks it about one thing, an input of the rule it is about to call with a function in it, which a row cannot hold, and refuses in the check's words (assumed, not ruled), and it still runs the rest of what the check refuses, a contract rule among them (`functionInputs`, `jl4/app/L4/Cli/Batch.hs`);
  - `jl4-mlir wasm` refuses on them with the same words (`typecheckL4File`, `jl4-mlir/src/L4/MLIR/Pipeline.hs`), except a result that is itself a `DEONTIC` (`isDeonticType`; a `MAYBE`, `LIST`, `EITHER` or synonym of one is refused, having no contract path): its JS runtime evaluates a contract from the schema, which `jl4-mlir/README.md` documents, so it is kept while the service's refusal is provisional (assumed, not ruled);
  - the web editor's WebAssembly build gets them from `l4_check` (`L4.API.l4Check`, `exportErrorsOf`), with the source `export`, and only for a file that type-checks, as in the language server, and its transport (`wasm-message-transports.ts`) still evaluates the file beside them;
  - `jl4-service` builds the same errors in its deploy gate (`jl4-service/src/Compiler.hs:194`) and refuses the bundle, with the same words, once the module has no type errors: as in the editor, a module that does not type-check is not asked what its exports take and give back.
- Both schema generators render the shape the check gives a type, so an `@export` that the check accepts is described as the check sees it:
  - `typeToParameter` (`jl4-core/src/L4/FunctionSchema.hs`) writes the schema that `jl4-service` publishes, that the editor's sidebar lists and that `jl4-mlir` writes for an input; `shapeToParameter` writes a shape out.
  - `generateJsonSchema` (`jl4-core/src/L4/JsonSchema.hs`) writes `jl4-schema`'s, with each declared type once under `$defs`; a type with parameters is named there with what it is given (`Box OF NUMBER`), since each of those has fields of its own.
  - Each reads the declarations the check reads, the module's and every module it imports, so an imported type has its definition (it was a `$ref` to a definition not in the file in 7,272 of the 33,904 exports of `legalese/commons`); a synonym is written as the type it stands for; a constructor that carries fields is one of the constructors' names in both, which is what the service has published (`jl4-schema` wrote a `oneOf` of objects with a `tag`, which no decoder reads); and the `@desc` of a declaration or a field is carried as before.
  - A type with no shape has no schema: `typeToParameter` and `generateJsonSchema` say why (`Left`). `jl4-schema` then exits 1 and names the input. The service, the sidebar and `jl4-mlir` publish `{"type": "object"}` for it (`uncheckedParameter`), which they reach only for an input the check did not look at: one read from a name the module never declared, or a type that did not resolve, whose own error stops the deploy.
  - An `EITHER` is `{"type": "object"}` in both, as the service has published it, with nothing said of its two sides (`eitherParameter`, `eitherSchema`; assumed, not ruled): how an `EITHER` is written is the wire-form bench's card J3, open.
- The two checks of the previous change, the function-typed input and the `EVENT`, are gone from the type check (`ExportFunctionTypeInput`, `ExportEventType`) and are cases of the one check.
  So a function-typed input no longer stops the file from checking either.

## Where it lives

- `jl4-core/src/L4/Export/Shape.hs`: `JsonShape`, `Unsendable`, `ShapeEnv`, `jsonShape`, and the two functions that word a reason, `unsendableWhat` and `unsendableHint`.
  Types are looked up in the declarations of the module and of everything it imports (`moduleDeclares`), and a record that contains itself stops at `JRecursive`.
  Whether a type has a shape is worked out by reading each declaration once, with its parameters taken as fine, and each type argument where it is written, whether or not the parameter is used (`firstUnsendable`). No type is instantiated, so the cost is that of reading the source.
  The shape itself (`expand`) is a tree that writes a declared type out, with its arguments filled in, on every path to it, so it is built only as far as something looks at it: the check discards it, `typeToParameter` walks all of it, and `generateJsonSchema` stops at a declared type, with its arguments, that it has written already.
- `jl4-core/src/L4/Export.hs`: `ExportError` and `ExportSite` (`:443`, `:434`), `checkExports`, `checkOneExport` (`:579`), `withoutRefused` (`:529`), `refusalsOf`, `prettyExportError` (`:493`); `inferredReturnType` (`:167`) gives the result of a definition without a `GIVETH`.
- `jl4-service/src/Compiler.hs`, `jl4-lsp/src/LSP/L4/Rules.hs` (the key `ExportCheck`, `:192`) and the two commands use it; none of them has a check of its own.

## How it is pinned

- `jl4-core/test/ExportValidationSpec.hs` is rewritten around `checkExports`.
  It refuses a function-typed `GIVEN`, an `ASSUME` of function type that the body reads, and a function inside `MAYBE OF` or behind a synonym; an `EVENT` input, a written and an inferred `EVENT` result, an `EVENT` in `LIST OF`, `MAYBE OF`, behind a synonym or in an `ASSUME` that the body reads; a `DEONTIC` result (and the file still type-checks) and a `DEONTIC` input; a record with a function among its fields (and says which); and an `EITHER` with a function on one side.
  It accepts value-typed inputs, a record, an enumeration, a `LIST OF`, a `MAYBE OF` and a `DATE`, a record that contains itself, an `EVENT` that the body builds but the signature does not name, an `EVENT` in a rule that is not `@export`, a type of the user's own called `EVENT`, an enumeration whose constructors carry fields, an `EITHER` of two types that have shapes, and a function-typed `ASSUME` that no export reads.
  It warns about a `GIVEN` with no written type, and does not refuse it.
- `jl4-core/test/SchemaBuiltinNameSpec.hs`, "both generators render the shape the export check gives a type": an `EITHER STRING NUMBER` input is an object in both, with no dangling `$ref`; `Box OF NUMBER` and `Box OF STRING` are two definitions with the fields of each, and the field's `@desc`; a constructor that carries fields is the constructors' names, with the declaration's `@desc`. The same file pins that an imported type has its definition, and that a module's own `Optional NUMBER` is a `$ref` to `Optional OF NUMBER`.
- Four `.schema.golden` files changed with the generators: `ok/export-schema-shapes` and `ok/schema-own-optional` (a constructor that carries fields is the constructors' names), and `ok/schema-synonym-chain` and `ok/schema-synonym-shapes` (a synonym is written as what it stands for, not as a `$ref` to a definition of it).
- `jl4/examples/not-ok/export-unsendable-types.l4` and its goldens: one error for each rule that cannot be sent (an `EVENT` input, an `EVENT` result, a `DEONTIC` result, a function input), one warning for the `GIVEN` with no written type, and nothing for the rule that publishes and the rule that only builds an `EVENT` in its body.
  The golden harness (`jl4/tests/Main.hs`) prints the export errors after the type-check errors, with the prefix `[export error]` or `[export warning]`, and the `#EVAL` at the end of the file still has its result there.
- `jl4/examples/ok/tests/desc.golden` and `pattern-matching-overloads-own-annotations.golden` gained the warning for a `GIVEN` with no written type.
- `jl4/examples/legal/ceo-performance-award.l4`: its `@export` on a rule that returns a `DEONTIC` became a comment, so that the file is not refused; see the revisit note below.
- `jl4-core/test/ExportValidationSpec.hs` also pins, under a timeout: records whose two fields share a record type at 64 levels, 14 records that each have a field of every one of them, and a type that passes what it was given on twice at 40 levels.
  It pins a type that passes two different types on at 64 levels and one that passes a function on twice and never uses it at 64, the shape of a record in a cycle from each place it is reached, a parameter given what has no shape, used or not, and the path named for `Box OF (Box OF ...)`.
  It pins the words for a generic rule, a generic `ASSUME` and a result with no `GIVETH`, and what `l4_check` reports (`L4.API.l4Check`).
- `jl4-mlir/test/Main.hs` compiles files through `compileToMLIR`: an `EVENT`, function or `DEONTIC` input, a record with a function field, a generic rule and a `MAYBE`, `LIST`, `EITHER` or synonym of a `DEONTIC` result are refused, and a `DEONTIC` result is compiled.
- `jl4/tests-cli/Main.hs` pins that `jl4-schema` refuses an export the check refuses, by default and by name, and writes the schema of another export of that file.
  It pins that `l4 batch` refuses an input with a function in it and still runs a `DEONTIC` result and an `EVENT` input, and that a broken import gives no export error.
- `jl4-service/test/IntegrationSpec.hs`: a bundle with an `@export` that takes an `EVENT`, returns an `EVENT` or returns a `DEONTIC` is refused, with the new words.
  The tests that deployed a contract rule are removed with the path they exercised: "deontic evaluation", "deontic answers spell a party and an action one way", "deontic evaluation with record-typed parties", the contract cases of the MAYBE-input bundle, and the missing-input case of a deontic rule.
  The path's code is still there.

## Measured

`l4 check` with a build of this branch against a build of `main` at `4c887e0db`, on 2026-11-04, over the files that contain `@export`, with every diagnostic compared.

- This repository, 92 files, 90 of which check on `main`: six change.
  They are the fixture `not-ok/export-unsendable-types.l4`, `ok/desc.l4` and `ok/pattern-matching-overloads-own-annotations.l4` (the untyped-`GIVEN` warning), and `jl4-mlir/test/fixtures/deontic-sale.l4`, `deontic-seatbelt.l4` and `deontic-breach.l4` (a `DEONTIC` result, which `jl4-mlir` still compiles).
- `legalese/commons` at `d468311a6`, 977 files, 905 of which check on `main` and with this change: no exit code changes.
  Seven Jersey charities files that already fail on `main`, because their imports write `TYPICALLY` on record fields, gain 42 `DEONTIC` export errors between them, which would stand once they check.
- Neither corpus has a file whose answer changes because a type argument with no shape is refused whether or not the parameter is used.
- Untyped-`GIVEN` warnings: none in `legalese/commons`, three in this repository (the two files above and the fixture).
- Refusing `EITHER` was measured on 2026-10-30 and broke one file in each of the two (the reason it is not refused, under "Limits").
- Not measured: stored deployments, which this session cannot count.
  Meng gave the count of those that export a `DEONTIC` result as 0 on 2026-10-30.

The schemas, measured on 2026-11-14 with a build of `6fe8598ae` against one of this change, over every file with an `@export` in this repository (99 files, 163 exports) and in `legalese/commons` at `bdc8fc5b9` (1,378 files, 33,904 exports), comparing what `jl4-service` publishes for each input and result and what `jl4-schema` writes, export by export:

- The service's schema changes for 49 exports, in 11 `legalese/commons` files whose imported modules have errors of their own (`je/charities-2014` g6 and g7, which import `g6-interpretation` and `g7-interpretation`; `il/hvac-work-licensing-2025` `int-sanction`, which imports `g1-adverse-action`). An input whose record has a field of a type with such an error is now `{"type": "object"}`, where it was the record written out; a bundle with those imports in it is refused at deploy, for their errors. Nothing else the service publishes changes, in either corpus.
- `jl4-schema` changes for 7,298 exports: 7,214 gain the definitions of the imported types they referred to, and no longer refer to a definition that is not in the file; 26 write a constructor that carries fields as the constructors' names (9 of them gain imported definitions too); 9 write a synonym as what it stands for, and are the same once every `$ref` is followed; and 49 are the 49 above, for which it now names the input and writes no schema.
- With every `$ref` followed, `jl4-schema` and the service now describe the inputs of every export alike, except three whose input has no written type, which `jl4-schema` calls a string and the service an object. Before, they differed for 7,292 exports.
- `EITHER` is the input of no export in either corpus, and the result of 7.

Types that nest, against `main`, measured on 2026-11-04: `l4 check` and `jl4-schema` are within 0.15 s of `main` on every size tried, from 0.03 s (a type that passes two different types on, `LIST OF a` and `MAYBE a`, 24 levels) to 1.3 s (records with two fields of the next one down, 4,000 levels).

## Revisit

The refusal of an `@export` on a rule that returns a `DEONTIC` is provisional.
Meng, 2026-10-30, ruling that part B be built as the reviewer specified:

> go ahead and do part B as specified by the reviewer, with a note that we may revisit this decision in the future when we have a better way of answering “here’s a view of the residual, shortened to immediate next actions — immediate obligations on parties and deadlines, plus your MAY options, and your SHANT prohibitions”

On the same day, about the example `ceo-performance-award.l4`, relayed through the general manager session:

> if/when we reopen this, we’ll come back to the ceo-performance-award. i’d still like to expose the head of the residuals.

The comment in that file, and the sentence "A contract can't be an @export input or result yet" in `unsendableHint`, are the two places to change when it is reopened.
The service's path for contract rules (`startTime` and `events` arguments, `runDeonticEvaluatorFor`, `jl4-service/src/DataPlane.hs`) is not removed by this change; Meng gave the count of stored deployments that export a `DEONTIC` result as 0 on 2026-10-30, which allows removing it as a change of its own.

## Limits

- The schema renders the shape, and the service's decoder and encoder do not follow it: they decide on their own, by reading the type, how a value is read and written (`jsonValueToWHNFTyped`, `jl4-core/src/L4/EvaluateLazy/Machine.hs:1301`; `fnLiteralToExprTyped` and `valueToFnLiteral`, `jl4-service/src/Backend/Jl4.hs`). Where they differ from the schema, read from the code and not measured:
  - No decoder reads an `EITHER`: `JSONDECODE` has no case for one, so an object decodes to `NOTHING` and a scalar is passed through as it is, and the direct path refuses an object that is not a record. The answer is written `{"RIGHT": [v]}` or `{"LEFT": [v]}`.
  - A record answer is written with its constructor's name around it (`{"Pair": {...}}`, `jl4-service/README.md`), which `returnSchema` does not say; that is the bench's card J2, open (smucclaw/l4-ide#1010).
  - A constructor that carries fields is read only by its name, with no fields, and answered as `{"Circle": {"radius": 2}}`; the schema lists the names. That is card J1, open.
  - A record that takes a type (`Box OF NUMBER`) is not read as a record by `JSONDECODE`, which looks only at a type with no arguments, so an object for one decodes to `NOTHING`.
- The schema `jl4-schema` writes for a type with parameters has one definition for each type it is given. A type that passes two different types on (`T OF (LIST OF a)` and `T OF (MAYBE a)` in each declaration) has twice as many at each level: measured on 2026-11-14, 220 KB at 8 levels, 4 MB at 12 and 75 MB in 3.4 s at 16, where `6fe8598ae` wrote 6 KB that referred to a definition, `a`, that is not in the file. The service's schema of that type doubled already (below).
- A constructor that carries fields has the shape of an enumeration of the constructors' names, which is what the schema publishes today, and is not refused.
  The review asked for it to be decided: a tagged shape or a refusal.
  It is not refused because `jl4-service-test` deploys a function whose result is such a type (smucclaw/l4-ide#1003, `wireProbeJL4`), and the wire-form bench (`l4-wire-form-1015`, card J1, open) counts 8 to 11 of 3,006 exports that take one.
  A tagged shape is that bench's to rule, not this change's.
  So a constructor with a field of a type that has no shape is not refused either: `DECLARE Carrier IS ONE OF Duty HAS d IS A DEONTIC Party Act` deploys, and its answer is `{"Duty":{"d":{"OBLIGATION":...}}}`.
- A built-in type nobody gave a row to is refused, as the review asked.
- The schema that the service publishes and the editor's sidebar lists (`typeToParameter`) writes a record out in full on every path to it, so it doubles at each level of the nesting that `jsonShape` no longer doubles on, as it does on `main`.
  Measured on 2026-11-04 through `jl4-core-test`, encoding one input's parameter: 14 MB in 0.5 s at 16 levels, 226 MB in 9.3 s at 20, 906 MB in 37 s at 22.
  A bundle of that kind is refused by the service from 18 levels with "compilation timed out or exceeded the memory limit", in under a second, on `main` and on this branch alike (at 12 and 16 levels it deploys, on both), and so is the type that passes two different types on, from 18 levels (at 14 it deploys, on both).
  That is consistent with the size of the schema measured here, and it was not confirmed.
  The wire form of the schema is what would have to change, and that is not done here.
- `jl4-mlir` accepts a rule whose result is itself a `DEONTIC` and the service refuses it (assumed, not ruled), so a `.schema.json` can list a function that the service does not.
  `jl4-mlir/scripts/parity-harness.mjs`, which is run by hand, deploys `deontic-sale.l4`, `deontic-seatbelt.l4` and `deontic-breach.l4` to the service by default, so its comparison of contract rules no longer has a service side (read from the harness, not run).
- `EITHER` has the shapes of its two sides and is not refused.
  The service writes an `EITHER` answer today, and the schema calls it an `object`; how it should be written is the wire-form bench's card J3, open.
  Refusing it was measured to break two files that check today: `subjects/il/hvac-work-licensing-2025/encodings/legalese-full-sonnet-5.5/g1-register.l4` in `legalese/commons` and `jl4/experiments/thailand-cosmetics/orchestrator.l4` in this repository.
- An `ASSUME` is looked at only when the body of the exported rule reads it itself; an `ASSUME` that the body reaches through a helper or an import is not looked at.
  That is the review's section 4, and it is not here.

## Not here

- The record of which assumptions each definition reaches, and the error that says "via helper reads ASSUME X through Y; pass it in as a GIVEN".
- A written type on every exported `GIVEN` as an error: it is a warning, until the count of stored deployments with an untyped exported `GIVEN` is taken (review, section 8).
- The decoder and the encoder following a `JsonShape`.
- The specification of exports of contract rules on stream infrastructure (the review's section 5), which extends `specs/todo/STATEFUL-CONTRACT-DEPLOYMENT.md` and is written after this change.
