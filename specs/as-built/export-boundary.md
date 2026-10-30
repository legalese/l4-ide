# The export boundary: which types an `@export` may take and give back (as built)

Status: built on the branch `carve/export-boundary`, a draft pull request stacked on `carve/resolution-diagnostics-v2` (legalese/l4-ide#769); not on `main` or `unstable`.
Source spec: none.
The shape of the change is the second part of the review of legalese/l4-ide#738 (serrynaimo, 2026-10-29, sections 3 and 4), which Meng ruled to build as specified on 2026-10-30.
This page describes what the branch has.
Reading the inputs of an exported rule from its signature, with a record of which assumptions each definition reaches (the review's section 4), is not in this commit: it is proposed, not landed, and is listed under "Not here".

Scope: `jl4-core/src/L4/Export/Shape.hs` (new), `jl4-core/src/L4/Export.hs`, the editor's rule `ExportCheck` (`jl4-lsp/src/LSP/L4/Rules.hs`), the commands `l4 check` and `l4 deploy`, the sidebar's list of exports, and the deploy gate in `jl4-service/src/Compiler.hs`.

## What it does

- One function, `jsonShape` (`jl4-core/src/L4/Export/Shape.hs:131`), decides whether a type has a form in JSON, and says why when it has none.
  The table is the header comment of that module.
  `NUMBER`, `BOOLEAN`, `STRING`, `DATE`, `TIME`, `DATETIME`, `LIST OF`, `MAYBE`, a record, an enumeration, a synonym and a type with parameters have a shape.
  A function, an `EVENT`, a `DEONTIC`, a type variable, `EITHER` and any other built-in type that nobody gave a row have none.
- `checkExports` (`jl4-core/src/L4/Export.hs:492`) asks it about every input and the result of every `@export`.
  An input is a `GIVEN`, or an `ASSUME` of the module that the body of the rule reads itself.
  The result is the written `GIVETH`, or the inferred type when there is none.
- A type with no shape is the error `ExportUnsendable`, ranged at the `@export`, saying which input or the result, what it is, and one line on what to do.
  The wording is "is ..., and @export does not support that yet", because the infrastructure that would carry these types is not built.
- A `GIVEN` with no written type is the warning `ExportUntypedGiven`.
  A warning does not refuse the `@export`.
- The check is its own pass and not a part of type checking.
  An error of the type check stops the file from evaluating anything (`success` in `Rules.hs`, read by `SuccessfulTypeCheck`), so a refused `@export` that was a type error would blank the `#EVAL` and `#EVALTRACE` of every rule in the file, the contract rules that the author tests there included.
  Here the file still checks and its rules still evaluate.
- Where the errors show:
  - the editor publishes them as diagnostics with the source `export` (`exportErrorToDiagnostic`, `jl4-lsp/src/LSP/L4/Rules.hs:1387`), kicked with the type check (`jl4-lsp/app/LSP/L4/LanguageServer.hs:349`);
  - the Deploy button refuses on them, because `isBlockingDiagnostic` (`jl4-lsp/src/LSP/L4/BlockingErrors.hs:40`) blocks on every error except those with the source `eval` or `import`, and `l4/getExportedFunctions` runs the check itself before it reads the diagnostics (`jl4-lsp/app/LSP/L4/Handlers.hs`);
  - the sidebar's list of exports leaves a refused rule out (`Export.withoutRefused`), so a contract rule is no longer listed with `isDeontic` set; the text test for "DEONTIC" in the printed return type (`Inspector.hs`) is gone;
  - `l4 check` and `l4 deploy` run the rule (`jl4/app/L4/Cli/Check.hs:55`, `jl4/app/L4/Cli/Deploy.hs:286`) and exit 1 on an error; `l4 run` and `l4 batch` do not run it, so they still run the file;
  - `jl4-service` builds the same errors in its deploy gate (`jl4-service/src/Compiler.hs:192`) and refuses the bundle, with the same words, once the module has no type errors: as in the editor, a module that does not type-check is not asked what its exports take and give back.
- The two checks of the previous change, the function-typed input and the `EVENT`, are gone from the type check (`ExportFunctionTypeInput`, `ExportEventType`) and are cases of the one check.
  So a function-typed input no longer stops the file from checking either.

## Where it lives

- `jl4-core/src/L4/Export/Shape.hs`: `JsonShape`, `Unsendable`, `ShapeEnv`, `jsonShape`, and the two functions that word a reason, `unsendableWhat` and `unsendableHint`.
  Types are looked up in the declarations of the module and of everything it imports (`moduleDeclares`), and a record that contains itself stops at `JRecursive`.
- `jl4-core/src/L4/Export.hs`: `ExportError` and `ExportSite` (`:427`, `:436`), `checkExports`, `checkOneExport` (`:539`), `withoutRefused` (`:500`), `prettyExportError` (`:464`); `inferredReturnType` (`:165`) gives the result of a definition without a `GIVETH`.
- `jl4-service/src/Compiler.hs`, `jl4-lsp/src/LSP/L4/Rules.hs` (the key `ExportCheck`, `:187`) and the two commands use it; none of them has a check of its own.

## How it is pinned

- `jl4-core/test/ExportValidationSpec.hs` is rewritten around `checkExports`.
  It refuses a function-typed `GIVEN`, an `ASSUME` of function type that the body reads, and a function inside `MAYBE OF` or behind a synonym; an `EVENT` input, a written and an inferred `EVENT` result, an `EVENT` in `LIST OF`, `MAYBE OF`, behind a synonym or in an `ASSUME` that the body reads; a `DEONTIC` result (and the file still type-checks) and a `DEONTIC` input; a record with a function among its fields (and says which); and `EITHER`.
  It accepts value-typed inputs, a record, an enumeration, a `LIST OF`, a `MAYBE OF` and a `DATE`, a record that contains itself, an `EVENT` that the body builds but the signature does not name, an `EVENT` in a rule that is not `@export`, a type of the user's own called `EVENT`, an enumeration whose constructors carry fields, and a function-typed `ASSUME` that no export reads.
  It warns about a `GIVEN` with no written type, and does not refuse it.
- `jl4/examples/not-ok/export-unsendable-types.l4` and its goldens: one error for each rule that cannot be sent (an `EVENT` input, an `EVENT` result, a `DEONTIC` result, a function input), one warning for the `GIVEN` with no written type, and nothing for the rule that publishes and the rule that only builds an `EVENT` in its body.
  The golden harness (`jl4/tests/Main.hs`) prints the export errors after the type-check errors, with the prefix `[export error]` or `[export warning]`, and the `#EVAL` at the end of the file still has its result there.
- `jl4/examples/ok/tests/desc.golden` and `pattern-matching-overloads-own-annotations.golden` gained the warning for a `GIVEN` with no written type.
- `jl4/examples/legal/ceo-performance-award.l4`: its `@export` on a rule that returns a `DEONTIC` became a comment, so that the file is not refused; see the revisit note below.
- `jl4-service/test/IntegrationSpec.hs`: a bundle with an `@export` that takes an `EVENT`, returns an `EVENT` or returns a `DEONTIC` is refused, with the new words.
  The tests that deployed a contract rule are removed with the path they exercised: "deontic evaluation", "deontic answers spell a party and an action one way", "deontic evaluation with record-typed parties", the contract cases of the MAYBE-input bundle, and the missing-input case of a deontic rule.
  The path's code is still there.

## Revisit

The refusal of an `@export` on a rule that returns a `DEONTIC` is provisional.
Meng, 2026-10-30, ruling that part B be built as the reviewer specified:

> go ahead and do part B as specified by the reviewer, with a note that we may revisit this decision in the future when we have a better way of answering “here’s a view of the residual, shortened to immediate next actions — immediate obligations on parties and deadlines, plus your MAY options, and your SHANT prohibitions”

On the same day, about the example `ceo-performance-award.l4`, relayed through the general manager session:

> if/when we reopen this, we’ll come back to the ceo-performance-award. i’d still like to expose the head of the residuals.

The comment in that file, and the sentence "A contract can't be an @export input or result yet" in `unsendableHint`, are the two places to change when it is reopened.
The service's path for contract rules (`startTime` and `events` arguments, `runDeonticEvaluatorFor`, `jl4-service/src/DataPlane.hs`) is not removed by this change; Meng gave the count of stored deployments that export a `DEONTIC` result as 0 on 2026-10-30, which allows removing it as a change of its own.

## Limits

- The schema is still produced by `typeToParameter` (`jl4-core/src/L4/FunctionSchema.hs`), which falls back to `object` for a type it has no declaration for; it does not render a `JsonShape`.
  So `jsonShape` and the schema can disagree for a type that `typeToParameter` handles differently, and `jl4-schema` still writes a schema for a default export that the check refuses.
  Making the schema render the shape, and the service's decoder follow it, is not done.
- A constructor that carries fields has the shape of an enumeration of the constructors' names, which is what the schema publishes today, and is not refused.
  The review asked for it to be decided: a tagged shape or a refusal.
  It is not refused because `jl4-service-test` deploys a function whose result is such a type (smucclaw/l4-ide#1003, `wireProbeJL4`), and the wire-form bench (`l4-wire-form-1015`, card J1, open) counts 8 to 11 of 3,006 exports that take one.
  A tagged shape is that bench's to rule, not this change's.
- A built-in type nobody gave a row to is refused, as the review asked.
  `EITHER` is one.
- An `ASSUME` is looked at only when the body of the exported rule reads it itself; an `ASSUME` that the body reaches through a helper or an import is not looked at.
  That is the review's section 4, and it is not here.

## Not here

- The record of which assumptions each definition reaches, and the error that says "via helper reads ASSUME X through Y; pass it in as a GIVEN".
- A written type on every exported `GIVEN` as an error: it is a warning, until the count of stored deployments with an untyped exported `GIVEN` is taken (review, section 8).
- The schema generator and the decoder rendering a `JsonShape`.
- The specification of exports of contract rules on stream infrastructure (the review's section 5), which extends `specs/todo/STATEFUL-CONTRACT-DEPLOYMENT.md` and is written after this change.
