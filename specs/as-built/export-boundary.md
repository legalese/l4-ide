# The export boundary: which types an `@export` may take and give back (as built)

Status: built on the branch `carve/export-boundary`, the draft pull request legalese/l4-ide#779 against `main`, and, stacked on it, the branch `carve/export-reach` (the "ASSUMEs" bullets below); #779 follows legalese/l4-ide#769, which merged into `main` on 2026-10-30; not on `main` or `unstable` yet.
Source spec: none.
The shape of the change is the second part of the review of legalese/l4-ide#738 (serrynaimo, 2026-10-29, sections 3 and 4), which Meng ruled to build as specified on 2026-10-30.
This page describes what the branch has.
The "ASSUMEs" bullets below, which are the second half of the review's section 4, are in `carve/export-reach` only.

Scope: `jl4-core/src/L4/Export/Shape.hs` (new), `jl4-core/src/L4/Export.hs`, the editor's rule `ExportCheck` (`jl4-lsp/src/LSP/L4/Rules.hs`), the commands `l4 check` and `l4 deploy`, the sidebar's list of exports, and the deploy gate in `jl4-service/src/Compiler.hs`.

## What it does

- One function, `jsonShape` (`jl4-core/src/L4/Export/Shape.hs:131`), decides whether a type has a form in JSON, and says why when it has none.
  The table is the header comment of that module.
  `NUMBER`, `BOOLEAN`, `STRING`, `DATE`, `TIME`, `DATETIME`, `LIST OF`, `MAYBE`, `EITHER` of two types that have shapes, a record, an enumeration, a synonym and a type with parameters have a shape.
  A function, an `EVENT`, a `DEONTIC`, a type variable and any other built-in type that nobody gave a row have none.
- `checkExports` (`jl4-core/src/L4/Export.hs:492`) asks it about every input and the result of every `@export`.
  An input is a `GIVEN`, or an `ASSUME` of the module that the body of the rule reads itself.
  The result is the written `GIVETH`, or the inferred type when there is none.
- A type with no shape is the error `ExportUnsendable`, ranged at the `@export`, saying which input or the result, what it is, and one line on what to do.
  The wording is "is ..., and @export does not support that yet", because the infrastructure that would carry these types is not built.
- A `GIVEN` with no written type is the warning `ExportUntypedGiven`.
  A warning does not refuse the `@export`.
- ASSUMEs: an `ASSUME` that the exported rule reaches and cannot be given is the error `ExportAssumeReached`.
  The rule reaches it through another rule (of its own file or of an imported one), or reads one that an imported module declares.
  `assumeReach` (`jl4-core/src/L4/Export.hs:583`) follows the rules that the exported body calls, breadth first and once each, and keeps the shortest path to each `ASSUME` for the message.
  The review asked for this to be recorded for each definition and exported with the module's check result, so that an importer merges it.
  This change computes it each time the check runs, from the modules that the file imports (`checkExports` takes them), which gives the same answer without storing anything.
- Why the service cannot take such an `ASSUME`: it binds the `ASSUME`s it publishes around the call of the exported rule (`wrapWithAssumes`, `jl4-service/src/Backend/CodeGen.hs:304`), so a helper's read of one is not bound.
  Measured on 2026-10-30 with a temporary integration test (not kept), on a rule `helper` that reads the `ASSUME` `rate`: an exported rule that reads `rate` itself answered 200 with the value; one that only calls `helper` answered 422 "I needed to know the value of rate but it is an assumed term" on every request, `rate` supplied or not; one that reads `rate` and calls `helper` answered 422 the same way.
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
- `jl4-core/src/L4/Export.hs`: `ExportError` and `ExportSite`, `checkExports` (`:515`), `checkOneExport` (`:612`), `assumeReach` (`:583`), `allDecidesFromModule` (`:569`), `withoutRefused`, `prettyExportError`; `inferredReturnType` gives the result of a definition without a `GIVETH`.
- `jl4-service/src/Compiler.hs`, `jl4-lsp/src/LSP/L4/Rules.hs` (the key `ExportCheck`, `:187`) and the two commands use it; none of them has a check of its own.

## How it is pinned

- `jl4-core/test/ExportValidationSpec.hs` is rewritten around `checkExports`.
  It refuses a function-typed `GIVEN`, an `ASSUME` of function type that the body reads, and a function inside `MAYBE OF` or behind a synonym; an `EVENT` input, a written and an inferred `EVENT` result, an `EVENT` in `LIST OF`, `MAYBE OF`, behind a synonym or in an `ASSUME` that the body reads; a `DEONTIC` result (and the file still type-checks) and a `DEONTIC` input; a record with a function among its fields (and says which); and an `EITHER` with a function on one side.
  It accepts value-typed inputs, a record, an enumeration, a `LIST OF`, a `MAYBE OF` and a `DATE`, a record that contains itself, an `EVENT` that the body builds but the signature does not name, an `EVENT` in a rule that is not `@export`, a type of the user's own called `EVENT`, an enumeration whose constructors carry fields, an `EITHER` of two types that have shapes, and a function-typed `ASSUME` that no export reads.
  It warns about a `GIVEN` with no written type, and does not refuse it.
  Under "an ASSUME reached through another rule", seven examples: an `ASSUME` that only a helper reads, one that the body and a helper both read, a path of two helpers (named outermost first), a rule that calls itself (followed once), an `ASSUME` read directly and a helper that reads none (accepted), an `ASSUME` that an imported module declares and the body reads, and an imported helper that reads one.
- `jl4/examples/not-ok/export-unsendable-types.l4` and its goldens: one error for each rule that cannot be sent (an `EVENT` input, an `EVENT` result, a `DEONTIC` result, a function input), one warning for the `GIVEN` with no written type, and nothing for the rule that publishes and the rule that only builds an `EVENT` in its body.
  The golden harness (`jl4/tests/Main.hs`) prints the export errors after the type-check errors, with the prefix `[export error]` or `[export warning]`, and the `#EVAL` at the end of the file still has its result there.
- `jl4/examples/not-ok/export-assume-reach.l4` and its goldens: the error for the rule that reaches `rate` through a helper, the rule that reads it directly and gives no error, and the `#EVAL` of a rule that reads none, which still runs.
- `jl4/examples/ok/tests/desc.golden` and `pattern-matching-overloads-own-annotations.golden` gained the warning for a `GIVEN` with no written type.
- `jl4/examples/legal/ceo-performance-award.l4`: its `@export` on a rule that returns a `DEONTIC` became a comment, so that the file is not refused; see the revisit note below.
- `jl4-service/test/IntegrationSpec.hs`: a bundle with an `@export` that takes an `EVENT`, returns an `EVENT` or returns a `DEONTIC` is refused, with the new words.
  The tests that deployed a contract rule are removed with the path they exercised: "deontic evaluation", "deontic answers spell a party and an action one way", "deontic evaluation with record-typed parties", the contract cases of the MAYBE-input bundle, and the missing-input case of a deontic rule.
  The path's code is still there.

## Measured

`l4 check` with a build of this branch against a build of legalese/l4-ide#769's head (`3a5e280db`), on 2026-10-30, over the files that contain `@export`.

- This repository, 71 `.l4` files outside test directories: the same exit code and diagnostics, except the new fixture and the two files that gain the untyped-`GIVEN` warning (`ok/desc.l4`, `ok/pattern-matching-overloads-own-annotations.l4`).
- `legalese/commons` at `798b51452`, 943 files, 675 of which check today: five fail with this change, and each exports a rule that returns a `DEONTIC`.
  They are `bdm-registration.l4`, `cta-community.l4`, `sta-strata.l4` and `aa-estates.l4` (Western Australia) and `pb2-seat.l4` (Brazil).
  Nothing else among the files that check changes.
- Four Jersey charities files (`g6-art17-after-deregistration.l4`, `g6-art18-governor-duties.l4`, `g6-art20-court-orders.l4`, `g7-art24-25-powers.l4`) already fail on a build of `main` (they use `TYPICALLY`) and carry 18 more `DEONTIC` export errors between them.
- Untyped-`GIVEN` warnings: none in `legalese/commons`, three in this repository (the two files above and the fixture).
- The check on the `ASSUME`s that an exported rule reaches (the "ASSUMEs" bullets above) refuses none of the same 71 and 943 files: the exit code and diagnostics are those of the build without it.
  Its own fixture is flagged by the build with it and not by the build without it, so the zero is not a build that lacks the check.
- Refusing `EITHER` was measured first and broke one file in each of the two (the reason it is not refused, under "Limits").
- Not measured: stored deployments, which this session cannot count.
  Meng gave the count of those that export a `DEONTIC` result as 0 on 2026-10-30.

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
- `EITHER` has the shapes of its two sides and is not refused.
  The service writes an `EITHER` answer today, and the schema calls it an `object`; how it should be written is the wire-form bench's card J3, open.
  Refusing it was measured to break two files that check today: `subjects/il/hvac-work-licensing-2025/encodings/legalese-full-sonnet-5.5/g1-register.l4` in `legalese/commons` and `jl4/experiments/thailand-cosmetics/orchestrator.l4` in this repository.
- Only the rules that sit at the top of a module are followed.
  A name that the exported rule reads and nothing declares is published by the service as an input of its own (`extractImplicitAssumeParams`), and is not followed through helpers.

## Not here

- The record of which assumptions each definition reaches, kept with the module's check result (see above: it is computed from the imported modules each time instead).
- A written type on every exported `GIVEN` as an error: it is a warning, until the count of stored deployments with an untyped exported `GIVEN` is taken (review, section 8).
- The schema generator and the decoder rendering a `JsonShape`.
- The specification of exports of contract rules on stream infrastructure (the review's section 5), which extends `specs/todo/STATEFUL-CONTRACT-DEPLOYMENT.md` and is written after this change.
