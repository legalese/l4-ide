# Unknown inputs and defaults: what a backend has to do

**Status:** a description of the tree, written 2026-10-08.
It rules nothing, and it is not a design.
Every row says which tree it describes:

- **today** is `unstable` at `f3dc2b4f5`;
- **after the stack** is legalese/l4-ide#556's head `e1d26be8f`, which carries #553 (unknowns step 1), #554 (step 2) and #556 (step 3); it is open, not merged, and branches from `3bce21d7d`, which is older than today's `unstable`;
- **parked** is UNKNOWN-EVALUATION-SPEC §8 steps 4 to 7, which Meng parked on 2026-10-02 (MOTHBALL) until a user asks for them.

A cell marked _measured_ was run on 2026-10-08, on `l4` and `jl4-service` built from the tree named; every other cell was read from the code at the function it cites.
Line numbers drift, so a citation leads with the function's name.

**This page owns no decision.**
The semantics of an unknown are [`UNKNOWN-EVALUATION-SPEC.md`](UNKNOWN-EVALUATION-SPEC.md) §4, with its rulings U1 to U13 recorded in its §9, and defaults and the presumption switch are [`TYPICALLY-ONE-BEHAVIOUR-SPEC.md`](TYPICALLY-ONE-BEHAVIOUR-SPEC.md) §5, rulings T1 to T6.
Where this page disagrees with either, the spec wins and this page is wrong: fix it here, in the same change.
Below, the two specs are called UES and TY.

---

## 1. Who this is for

Anyone writing or changing a place where an L4 rule is evaluated or translated: the evaluator, the CLI, jl4-service and its MCP server, the ladder diagram and query planner, jl4-mlir, and the exporters to DMN, BPMN, Catala, OpenFisca, docassemble, Blawx and yscript.
Each of them meets the same situation: a rule needs an input, and the caller has not given it a value.
L4 answers that in four stages, in a fixed order, and a backend has to say what it does at each one.
§2 to §5 describe the stages, §6 sets out each backend against them, §7 lists the places where the answer is wrong with no error, §8 the questions only Meng can settle, and §9 how to keep this page true.

## 2. Stage 1: what the caller sent

A caller says one of four things about an input (TY T3, ruled 2026-10-01):

| on the wire | meaning                                                              |
| ----------- | -------------------------------------------------------------------- |
| a value     | answered                                                             |
| left out    | not asked; may take a default                                        |
| `null`      | "I don't know"; **never** takes a default                            |
| `{}`        | "uncertain"; treated exactly as `null` until a ruling says otherwise |

Keeping left-out and `null` apart is the backend's job from the moment it parses the request.
jl4-service keeps the difference by decoding `arguments` as `Map Text (Maybe FnLiteral)` (`FnArguments`, `jl4-service/src/Backend/Api.hs`), so a key with `null` is present with no value, and reads the cells with `suppliedIn` (`Backend/Jl4.hs`).
`l4 batch` keeps it in the JSON and YAML it reads; CSV has no way to spell `null`, and an empty cell is _left out_ (TY T3c, ruled; `rowToJson`, `jl4/app/L4/Cli/Batch.hs`).

**One known leak** (smucclaw/l4-ide#1021, _measured_ today): MCP `tools/call` and the batch endpoint parse each argument with `FromJSON FnLiteral`, whose `Null` case is `FnUnknown`, so a top-level `null` there is not the "present, no value" cell the single endpoint sees.
It changes the answer only for a `BOOLEAN` input (_measured_ over MCP): a `NUMBER` sent `null` is refused at once by the wrapper path's decoder ("Field 'n' is null…"), a `DATE` by `wrapperDeclined` ("missing required parameter"), and a `MAYBE` is `NOTHING` on every route.
§4 says what that changes.

## 3. Stage 2: presumption, soft or hard

Soft and hard are the names of the presumption switch (TY T4, ruled; the names are Meng's, from the December 2025 Default design, and TY records them at "Soft and hard are T4's switch, under their original names").
The switch decides one thing only: **whether an input that was left out is given a value before evaluation starts.**
It never changes what an unknown does once evaluation has started; that is stage 4, and it has no mode (UES U7b: "Every evaluation is lifted").

- **Soft** (the default everywhere): an input left out takes its `TYPICALLY` default, and a `MAYBE` input left out with no default takes `NOTHING`.
  Each such fill is listed in `presumed` the first time the evaluation reads it, not when it is filled (`notePresumedForce`, from `evalRef`, `jl4-core/src/L4/EvaluateLazy/Machine.hs`; TY T6).
  Two parts of that were decided by Claude overnight on 2026-10-02, pending Meng's review: that a fill counts on its first read, and that the `NOTHING` fill is listed at all.
- **Hard:** neither fill happens, and the input goes on to stage 3 as having no value.

The decision is `L4.Presumption.fillDecision` (`jl4-core/src/L4/Presumption.hs`), byte-identical today and after the stack, which the JSON decoder and the direct path's root fills (`rootInputExpr`) both call.
Three places read the same switch with tests of their own instead: discharge (`dischargeModuleWith`, `jl4-core/src/L4/Discharge.hs`), which fills a section `GIVEN`'s default; the direct path, which leaves a section `GIVEN` that has a default to discharge under soft (`evaluateDirectAST`); and the wrapper path's `wrapperPlan`, whose `ownType` decides which inputs it sends to the decoder at all, which is where that path differs (§4).
A backend that fills defaults should implement this table:

| the caller sent | declared                           | soft                            | hard                            |
| --------------- | ---------------------------------- | ------------------------------- | ------------------------------- |
| a value         | anything                           | `UseValue`                      | `UseValue`                      |
| `null` or `{}`  | `MAYBE`                            | `NullIsNothing` (not presumed)  | `NullIsNothing`                 |
| `null` or `{}`  | not `MAYBE`                        | `RefuseNull`                    | `RefuseNull`                    |
| left out        | has a `TYPICALLY` (`MAYBE` or not) | `UseDefault d`                  | `RefuseMissing DefaultWithheld` |
| left out        | `MAYBE`, no default                | `UseNothing`                    | `RefuseMissing MaybeWithheld`   |
| left out        | neither                            | `RefuseMissing NothingWithheld` | `RefuseMissing NothingWithheld` |

`RefuseNull` and `RefuseMissing` are names for "this input has no value"; whether that refuses the request or becomes an unknown is stage 3, and it is not the same on every surface.
The messages are `nullRefusalText` and `withheldText` in the same module; the decoder, `l4 batch` and the direct path use them, while `wrapperDeclined` and one fallback in `rootInputExpr` build "missing required parameter" themselves.

Where the switch can be set, _read_ today and unchanged after the stack:

| surface                                         | how                                                                                                                                                                                              | default                                  |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------- |
| `l4 batch`                                      | `--presumption soft\|hard` (`presumptionReader`, `Batch.hs`)                                                                                                                                     | soft                                     |
| jl4-service, single and batch endpoints         | `"presumption": "soft" \| "hard"` beside `arguments` (`FnArguments`), and on the batch request for all its cases (`Types.hs`)                                                                    | soft                                     |
| MCP `tools/call`                                | none: `PresumeSoft` is passed in `McpServer.hs`'s evaluation call                                                                                                                                | soft                                     |
| `#EVAL`, `#ASSERT`, `l4 run`, the REPL, the LSP | none: `presumeDefaults` is `True` in `resolveEvalConfigWithSafeMode` (`EvaluateLazy.hs`)                                                                                                         | soft                                     |
| ladder-core (`nodeValue`, `verdictFor`)         | `ViewSpec.defaults`, with `respectDefaults` (true unless set); only the ladder-svg playground passes `defaults`; charge-generator, regcf-wizard and `LadderModel` (behind `LadderSvg`) pass none | never presumes, except in the playground |
| the IDE ladder (`LadderFlow`, `eval.ts`)        | none: a `TYPICALLY` only ranks the questions                                                                                                                                                     | never presumes                           |
| the query planner                               | none: a boolean `TYPICALLY` is a prior of 0.9 or 0.1 (`typicallyTrueWeight`, `jl4-core/src/L4/Viz/VizExpr.hs`), never a binding                                                                  | never presumes                           |

So every shipped ladder and the planner treat a defaulted input as unknown until it is answered, which is hard's reading, while `#EVAL`, `l4 run`, the REPL, the LSP and MCP always use soft.

What the switch reaches (TY T4b): a section `GIVEN`'s default through discharge (`dischargeModuleWith`), the direct path's root fills (`FillCtx.fcSoft`), and the request's own decode (`EvalConfig.requestRecord`, set by batch and the service wrapper).
A `JSONDECODE` the rules make of their own fills its defaults in both modes.
A written `ASSUME … TYPICALLY` is not a default for the evaluator, `l4 batch` or the service (`honouredDefault`, `jl4-core/src/L4/Export.hs`), although the ladder folds it into the planner's priors (`collectTypicallyDefaults`, `jl4-core/src/L4/Viz/Ladder.hs`) and #550's Catala exporter maps it to `context`.
TY's ruling T2 says it is honoured; its build, W6, is deferred by Meng's word, _"I'd be ok with skipping or deferring W6 as ASSUME is being deprecated"_, which is recorded only in #558's copy of TY (W10, open).

**Today a `TYPICALLY` takes only a literal**, so a `MAYBE` input can default only to `NOTHING`, and a `DATE` input cannot carry one at all (_measured_: `TYPICALLY JUST 7` and `TYPICALLY DATE OF 1, 2, 2026` are parse errors, and `TYPICALLY "2026-02-01"` on a `DATE` is a type error).
Expression defaults are W7, legalese/l4-ide#557, open.

**Today `#EVAL` honours a section `GIVEN`'s default but not a rule `GIVEN`'s at a named call**: `#EVAL withDefault WITH q IS TRUE`, where `r` is a rule `GIVEN` with `TYPICALLY TRUE`, is a check error (_measured_), while batch and the service fill the same default.
TY accepts that gap (its R1) until W4 and W5, legalese/l4-ide#551, open.

## 4. Stage 3: refuse now, or carry an unknown

An input still without a value after stage 2 is either **refused before evaluation** (eager), or **bound as an unknown**, which costs nothing unless the rule reads it (lazy).
TY T3b ruled the interim: "Eager refusal stays only on the direct path (`Jl4.hs:448`), and lazy binding there is its own work item."
UES's step 6, parked, depends on that unnumbered work item.

| surface                                              | an input with no value (not `MAYBE`)                                               | source                                                  |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `l4 batch`, every format                             | eager: the row is an error naming it, even if the rule never reads it              | `generateDecoder`, `missingFieldsMessage`; _measured_   |
| jl4-service single `/evaluation`, direct path        | eager: `422`, naming every such input                                              | `rootInputExpr`; _measured_                             |
| jl4-service wrapper path, a `BOOLEAN`                | lazy: bound to the assumed term `` `x (not supplied)` ``                           | `notSuppliedTerm`, `jl4-service/src/Backend/CodeGen.hs` |
| jl4-service wrapper path, `DATE`, `TIME`, `DATETIME` | eager: "missing required parameter"                                                | `wrapperDeclined`, `Backend/Jl4.hs`                     |
| jl4-service wrapper path, any other type             | eager: the decoder's "Missing required field"                                      | `ownType`, `wrapperPlan`                                |
| `#EVAL`, `#ASSERT`, `l4 run`                         | lazy: an `ASSUME`, or a section `GIVEN` discharge did not fill, is an assumed term | `ValAssumed`, `jl4-core/src/L4/Evaluate/ValueLazy.hs`   |

Which path a service request takes is `requiresWrapperEvaluation` (`Backend/Jl4.hs`): any `FnUnknown` or `FnUncertain` at any depth sends it to the wrapper, as does every `DEONTIC` function.
A key that is left out never does.

That is why one `null` on a `BOOLEAN` gets three treatments today (_measured_, smucclaw/l4-ide#1021):

| request, `p` sent as `null`, `q` false | single `/evaluation` | MCP `tools/call` | batch case          |
| -------------------------------------- | -------------------- | ---------------- | ------------------- |
| `p AND q`                              | `422`: `p` is null   | error: needs `p` | `@error`: needs `p` |
| `q AND p`                              | `422`: `p` is null   | **`false`**      | **`false`**         |

The single endpoint decodes `null` as "present, no value", so it stays on the direct path and refuses.
MCP and batch decode it as `FnUnknown`, which routes them to the wrapper, where `p` is lazy and today's two-valued `AND` (§5) decides `q AND p` without reading it.
The README's list of what takes the wrapper path ("Absent with no default, or `null`", `jl4-service/README.md`) names neither of them.

**Under hard, a defaulted `BOOLEAN` left out is eager on the direct path and lazy on the wrapper path** (_measured_ today).
That is not a rule of its own: T4 says hard treats "an absent input with a default … as absent with none", and absent-with-none is eager on the direct path and lazy on the wrapper path (T3b).
For `q AND r`, with `r` defaulted and left out, `q` false and `"presumption": "hard"`: sent with an unused `w` false, the request stays direct and is refused naming `r`; sent with `w` as `{}`, it takes the wrapper and answers `false`.
`IntegrationSpec.hs`'s "with presumption hard, stops on a left-out input on the wrapper path" pins only the case where the rule reads the input.

## 5. Stage 4: what an unknown does

UES §4 is the semantics, and §4.12 is its conformance table; this section only says what a backend must reproduce and where today's tree stands.

**The rule** (UES §4.1, ruled U1 and U1b): left-sequential strong Kleene with residual values.
In UES's own words: "Evaluate the left operand first. If it decides the connective (`FALSE` for `AND`, `TRUE` for `OR`, `FALSE` for `IMPLIES`), stop, as today. If it is known and does not decide, the answer is the right operand, as today. Only if it is unknown is the right operand evaluated and the K3 table applied."
An undecided result is not a bare "unknown" but the term it is waiting on, with `IMPLIES` kept as its own node.
In UES's target, nothing inside the evaluator decides a residual beyond §4.3's tables, the identity rule and the agreeing-arms rule (U3: no tautology is recognised mid-evaluation); the agreeing-arms rule is the parked step 5.
The identity rule (§4.6, U6 and U6b, extended by C1 to every term keyed by its structure) is built after the stack and is the one an implementer is likeliest to miss: an unknown equals itself, so `x EQUALS x` and `(n PLUS 1) EQUALS (n PLUS 1)` are `TRUE` (_measured_), while `x OR NOT x` is not decided until the boundary, at the parked step 4.

**The conformance table** is UES §4.12: 90 rows, each with the ruling it comes from, an input, today's answer and the expected one, which is often qualified by build step.
It is prose in a markdown table; no harness reads it.
After the stack, the rows are pinned by hand in `jl4/examples/ok/unknown-inputs-lifted.l4` and `jl4/examples/ok/unknown-inputs-two-valued.l4`, whose comments cite row numbers, and are exercised further by `jl4/tests-cli/fixtures/eval-assumed.l4`, `jl4/tests-cli/fixtures/eval-undetermined.l4` and `jl4-core/test/UnknownInputsSpec.hs`, which do not; none of these exists today.
A new backend should be checked against the rows, not against this page.

**Where the evaluator stands.**
`x`, `n`, an enum `s` and a record `d` are `ASSUME`d; each answer was _measured_ with `l4 run` on both trees.

| expression                                                                                                                                                   | today                                                      | after the stack               | UES's target, where it differs from the stack |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------- | ----------------------------- | --------------------------------------------- |
| `FALSE AND x`                                                                                                                                                | `FALSE`                                                    | `FALSE`                       |                                               |
| `x AND FALSE`                                                                                                                                                | stuck on `x`                                               | `FALSE`                       |                                               |
| `x OR TRUE`                                                                                                                                                  | stuck on `x`                                               | `TRUE`                        |                                               |
| `TRUE AND x`                                                                                                                                                 | prints `x`, exit 0                                         | undetermined: needs `x`       |                                               |
| `NOT x`                                                                                                                                                      | stuck on `x`                                               | undetermined: needs `x`       |                                               |
| `x OR NOT x`                                                                                                                                                 | stuck on `x`                                               | undetermined: needs `x`       | `TRUE` at the boundary (step 4)               |
| `x IMPLIES TRUE`                                                                                                                                             | stuck on `x`                                               | undetermined: needs `x`       | `TRUE` at the boundary (step 4)               |
| `n EQUALS 5`                                                                                                                                                 | stuck on `n`                                               | undetermined: needs `n`       |                                               |
| `x EQUALS x`                                                                                                                                                 | stuck on `x`                                               | `TRUE`, the identity rule     |                                               |
| `5 EQUALS n`                                                                                                                                                 | "Trying to check equality on types that do not support it" | undetermined: needs `n`       |                                               |
| `n PLUS 1`                                                                                                                                                   | stuck on `n`                                               | undetermined: needs `n`       |                                               |
| `IF x THEN 1 ELSE 1`                                                                                                                                         | stuck on `x`                                               | undetermined: needs `x`       | `1`, the arms agree (step 5)                  |
| `CONSIDER` an unknown, where a later branch's pattern at the unknown's position is a variable (`WHEN other`, `WHEN Claim kk a`) or the branch is `OTHERWISE` | **that branch**, with no error                             | undetermined                  | a join of the branches (step 5)               |
| `CONSIDER` an unknown, every branch a constructor                                                                                                            | "reached a CONSIDER that has no branch for it"             | undetermined                  | a join of the branches (step 5)               |
| `CONSIDER n WHEN 5 THEN … OTHERWISE …`                                                                                                                       | "Trying to check equality on types that do not support it" | undetermined: needs `n`       |                                               |
| `d's age AT LEAST 18`, `d` an unknown record                                                                                                                 | "reached a CONSIDER that has no branch for it"             | undetermined: needs `d's age` |                                               |

An empty last cell means UES expects what the stack already gives: undetermined, naming the inputs, in the default report (U7b).
A row whose answer is stuck today names one input; undetermined after the stack names every input the answer waits on.

How the connectives get there: today `AND`, `OR`, `IMPLIES` and `NOT` are rewritten to `IF` (`forwardExpr`, `Machine.hs`), so an unknown on the left meets `IfThenElse1` and stops.
After the stack they are frames of their own (`ConnectiveLeft`, `ConnectiveRight`; `connectiveLeft` and `connectiveRight`, `Machine.hs`), which is UES's build step 2 (U2, U2b).
After the stack, an error or a `REFUSE` in the right operand under an unknown left is reported as stuck on the left's inputs, not as the error (UES §4.3, U13's interim; `rewriteUnwinding`).

**What a caller gets back.**

- Today, `#EVAL` has `Reduced`, `ReducedRefused` and `ReducedErrored`; a stuck evaluation is `ReducedErrored`, and a result that is itself a bare assumed term is `Reduced` (`EvaluateLazy.hs`).
- After the stack there is a fourth outcome, `ReducedUndetermined (NonEmpty Term)`, and `#ASSERT` gains `Undetermined`; every consumer of these types needs an explicit arm for it, with no wildcard (UES U1b).
- `l4 run --json` gives `"kind": "undetermined"` with `needs` and `message` after the stack (`Run.hs`); `l4 batch` gives the row status `"undetermined"`, which never stops a batch but makes it exit 1 (`RowOutcome`, `Batch.hs`).
  No CLI test covers an undetermined batch row, and today no batch path leaves a read input unbound, so it cannot arise there yet.
- jl4-service, even after the stack, reports an undetermined answer as `422` with `"tag": "InterpreterError"` and prose, the same tag as a refusal of a missing input, plus `"report": "default"`.
  The core's `{"undetermined": {"needs": […], "message": …}}` shape is not used by the service; a machine-readable shape is the parked step 6.

## 6. Each backend, today, after the stack, and parked

### 6.1 The places that evaluate

| surface                                                                                                                                 | today                                                                                                                                                                                                                                                             | after the stack                                                                                                                                                                                                                                                                                                                                                                                                                        | parked                                                                                                         |
| --------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| evaluator: `#EVAL`, `#ASSERT`, `l4 run`, the REPL                                                                                       | connectives via `IF`, so left-sequential and two-valued; stuck on the first unknown read; `CONSIDER` on an unknown takes a later branch with a variable at its position, or `OTHERWISE`                                                                           | §5's table: connectives as frames, residual atoms for `+ − ×`, `EQUALS` and the comparisons, the identity rule, `ReducedUndetermined` naming every input                                                                                                                                                                                                                                                                               | the boundary decider and the K3 and residual reports (step 4); joins, step counter and guarded leaves (step 5) |
| `l4 batch`                                                                                                                              | no unknown reaches evaluation: every input the rule reads is a field of the generated `InputArgs` record, refused when the row is decoded                                                                                                                         | the same, plus a row status `"undetermined"`                                                                                                                                                                                                                                                                                                                                                                                           | a batch report route (step 6)                                                                                  |
| jl4-service, single `/evaluation`, direct path                                                                                          | eager refusal of a missing input or a top-level `null` (`rootInputExpr`)                                                                                                                                                                                          | unchanged                                                                                                                                                                                                                                                                                                                                                                                                                              | lazy binding on the direct path, which has no W number (TY T3b)                                                |
| jl4-service, wrapper path                                                                                                               | a missing `BOOLEAN` is lazy and evaluates as in the evaluator today; a stuck answer is `422` prose; an answer that is a bare unknown is `422` "#EVAL produced ASSUME" (_measured_)                                                                                | connectives as frames; `422` prose plus `"report": "default"`; a bare unknown in the wrapper's `JUST` is undetermined (#556's head commit, decided by Claude 2026-10-07, pending Meng's review)                                                                                                                                                                                                                                        | report routes, a machine-readable "undetermined", batch status (step 6)                                        |
| jl4-service batch endpoint, MCP `tools/call`                                                                                            | a top-level `null` takes the wrapper path (§4); MCP is always soft, and its errors are prose (`prettyEvaluatorError`)                                                                                                                                             | MCP's errors are the HTTP error JSON, `report` included                                                                                                                                                                                                                                                                                                                                                                                | MCP carries its report as "a separate tool or a listed capability" (UES, step 6)                               |
| IDE ladder (`LadderFlow`, `eval.ts`)                                                                                                    | values are order-independent strong Kleene (`evalAndChain`, `evalOrChain`), only the shading is left to right; a call with an unknown argument is unknown without asking the server ("Currently don't support eval-ing an App with Unknown args"); no error value | unchanged, except that a callee that comes back undetermined is an LSP response error (`Actions.hs`)                                                                                                                                                                                                                                                                                                                                   | replace `eval.ts`'s own evaluation with `l4/evalApp` (step 7)                                                  |
| ladder-core (`nodeValue`, `verdictFor`; `LadderSvg`, mounted in neither IDE, the ladder-svg playground, charge-generator, regcf-wizard) | order-independent strong Kleene with pins; presumes only when the caller passes `defaults`, which only the playground does                                                                                                                                        | unchanged                                                                                                                                                                                                                                                                                                                                                                                                                              | step 7                                                                                                         |
| query planner (`BooleanDecisionQuery.hs`)                                                                                               | an unknown is an absent binding in `Map v Bool`; the ROBDD decides a tautology over a shared atom, but each compound leaf gets a fresh `Unique` (`Ladder.hs`), so a repeated comparison is not shared; a `TYPICALLY` is a prior only                              | unchanged                                                                                                                                                                                                                                                                                                                                                                                                                              | a residual planner (step 6)                                                                                    |
| jl4-mlir / WASM (`jl4-runtime.mjs`)                                                                                                     | `marshalArg` turns `null` or a missing value into `0` before it looks at the type: a `BOOLEAN` reads `FALSE`, an enum its first constructor, a `STRING` `""`; a `MAYBE` is `NOTHING`; nothing is checked before the body runs                                     | a required input left out or `null` is refused with a `422` in the service's body shape (`refuseMissingInputs`, `suppliesRequired`; commit `e0de262a4`), though not always its message: a top-level `null` is "missing required parameter" (`MissingInputError`) where the service says it is null; an unrecognised enum string still becomes the first constructor, where the service refuses it ("unknown enum variant", _measured_) | UES steps 2 and 3 built jl4-mlir's connective mirror and its trace; steps 4 to 7 do not name it                |

How the ladder and the evaluator differ is recorded in UES (U10, U10b), and the survey behind this page found it still accurate: `x OR NOT x` and errors differ by design; `x IMPLIES TRUE` has the value `TRUE` and the verdict Undetermined in the ladder, which is what U10b expects, and is undetermined in the evaluator until the parked step 4, so there the evaluator is the side in its interim; a call whose body decides despite an unknown argument (UES rows 49 and 50) is a gap whose fix is the parked step 7.
One divergence UES does not mention: the ladder expands a Boolean `IF` or `CONSIDER` into Kleene connectives (`jl4-core/src/L4/Viz/GuardedRows.hs`), so it can answer `FALSE` where the evaluator is undetermined (_inferred_, not run).

### 6.2 The exporters

UES §4 excludes them in terms: "What the claim does not cover is anything that is not the evaluator: the printer, the traces, the exporters."
So nothing here is a contract yet; it is what each exporter does.
For defaults, TY T5 (ruled) says an exporter maps a `TYPICALLY` or emits a note saying it was dropped; legalese/l4-ide#550 (W9, open, draft) builds that.
There is no ruling for unknowns.
No exporter has a presumption switch: no exporter or `jl4-mlir` takes a flag or parameter for it, today or at #550's head, where the word appears only in comments, note text and the name of one s(CASP) predicate in Blawx's lowering.
Yscript, the one `l4 export` target not in the table (`dmn-md` shares DMN's notes): today it has no `TYPICALLY` handling, so a default is dropped silently, and #550 makes it refuse a module whose rule reads a defaulted input, as T5b rules; how it treats a missing input was not surveyed.

| exporter        | a missing or unknown input becomes                                                                                                                                                                                                                                                                                                                       | a `TYPICALLY`, today                                                                                                                                                                                   | after #550                                                                                                                                                                                                                       | against strong Kleene                                                                                                                                                                                                                                                                                                                                                                                                                             |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DMN             | FEEL `null`, which also stands for `NOTHING` and for a refusal (`Dmn/Lower.hs`); on KIE a missing top-level input is a model error and the decision is skipped; an imported `ASSUME` gets no input at all, so KIE will not load the model and Camunda reads `null`                                                                                       | dropped silently                                                                                                                                                                                       | a `D-TYPICALLY` lossy note for each default                                                                                                                                                                                      | FEEL's `and` and `or` are three-valued over `null` (the DMN standard; not measured here); a decision table over a `null` falls to its `OTHERWISE` row, and KIE reports a missing record component as `SUCCEEDED` (both recorded as measurements only in #550's `doc/exports/dmn-bpmn.md`); an `IF` on `null` takes its `else` arm (stated in UES U1b, which says the DMN limits page should record it; nothing measures it yet): **silent wrong** |
| BPMN            | whatever the process instance holds                                                                                                                                                                                                                                                                                                                      | dropped silently                                                                                                                                                                                       | a `P-TYPICALLY` note                                                                                                                                                                                                             | the engine decides                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Catala          | a mandatory `input` (_inferred_ from Catala's semantics)                                                                                                                                                                                                                                                                                                 | a rule `GIVEN`'s default becomes `context`, with a note; a section `GIVEN`'s, an `ASSUME`'s and a record field's are dropped silently                                                                  | section `GIVEN` and `ASSUME` become `context`; record and constructor fields are dropped with a note                                                                                                                             | **loud**: Catala has no unknown; a `context` is always soft                                                                                                                                                                                                                                                                                                                                                                                       |
| OpenFisca       | always a value: OpenFisca's `0`, `0.0`, `False` or `''`, or an enum's first member; a defaulted record field is never declared as a variable, though the formulas still name it                                                                                                                                                                          | dropped (an enum gets its first member)                                                                                                                                                                | `default_value` written; refused: a `NOTHING` default, a list default other than `EMPTY`, a default on the subject or the period, one whose type does not match, and the whole module if any constructor field has a `TYPICALLY` | **silent wrong** whenever the type's default is not what the rule meant; always soft                                                                                                                                                                                                                                                                                                                                                              |
| docassemble     | a question, asked until answered; a `MAYBE BOOLEAN` is a yes/no/maybe question whose "maybe" is `None`, that is `NOTHING`; a `MAYBE NUMBER` or `MAYBE DATE` gets a paired "is this known?" question, and "no" leaves the value undefined; an empty `MAYBE STRING` is `NOTHING`; a `MAYBE` of an enum, record, list or `MAYBE` is refused (`maybeReprAt`) | a `default:` prefill for a literal, with a `DA-TYPICALLY` advisory; a non-literal default, `NOTHING` included, or one on a record or list, stops the export; a constructor field's is dropped silently | constructor fields prefilled too                                                                                                                                                                                                 | never computes without the input; asks in Python's left-to-right short-circuit order, so it can ask for an input the answer no longer needs                                                                                                                                                                                                                                                                                                       |
| Blawx           | an input predicate neither asserted nor denied: no model                                                                                                                                                                                                                                                                                                 | silent (a note for `ASSUME` is computed but never printed)                                                                                                                                             | `R-TYPICALLY` on stderr, and in the `.pl` header when one is written (`--scasp` or `-o`); the `.blawx` file carries none                                                                                                         | **loud** for an input literal; `NOT` over a computed decision is negation as failure, so a decision that fails for want of an input makes its `NOT` true (_inferred_, untested): **silent**                                                                                                                                                                                                                                                       |
| jl4-mlir / WASM | see 6.1                                                                                                                                                                                                                                                                                                                                                  | ignored, and the input stays `required` in the WASM schema, while the service's schema lets a caller leave it out (`isRequiredInput`)                                                                  | unchanged                                                                                                                                                                                                                        | today **silent wrong**; after the stack **loud**                                                                                                                                                                                                                                                                                                                                                                                                  |

## 7. Silent failures, then loud ones

A silent failure returns a wrong answer, or a value where L4 has none, with no error and exit 0.
Those come first, because nothing else will tell you about them.

**Silent, today on `unstable`:**

1. `CONSIDER` on an unknown takes the first later branch whose pattern at the unknown's position is a variable, such as `WHEN other` or `WHEN Claim kk a`, or an `OTHERWISE`, with no error (_measured_ on `l4 run` and on the service's wrapper path; `patternMetUnknown`, `metUnknownHandled`, `Machine.hs`).
   `jl4-service/README.md` documents only the `OTHERWISE` case. #553 makes it stuck.
2. `#EVAL TRUE AND x` prints `x` and exits 0, so a bare unknown reads as a value (_measured_); `l4 run --json` calls it `"kind": "value"` (_read_). The stack makes it undetermined.
3. jl4-mlir reads a missing or `null` input as `0`: a missing `BOOLEAN` is `FALSE` (_read_; `e0de262a4`'s message records `{"x": true}` to `x AND y` answering `FALSE`), and a missing `NUMBER` takes whatever rational the call allocated first (_inferred_).
   #556 refuses a missing required input; after it, an unrecognised enum string still becomes the first constructor, which the service refuses.
4. OpenFisca gives every missing input a value, and drops a defaulted record field from the inputs.
5. DMN falls to a decision table's `OTHERWISE` row on a `null` and KIE reports a missing record component as `SUCCEEDED` (both measured in #550's copy of `doc/exports/dmn-bpmn.md`); an `IF` on a `null` takes its `else` arm (UES U1b; not measured); and every `TYPICALLY` is dropped with no note until #550.
6. Blawx's `NOT` over a computed decision is true when the decision fails for want of an input (_inferred_).

**Silent, and ruled neither way:** a `null` on a `MAYBE` input is `NOTHING` (`NullIsNothing`), so "I don't know" becomes "there is none", and the answer is a `200`.
`jl4-service/test/IntegrationSpec.hs` pins it (`"premium": null` answers `0`); TY's T6 shapes say "A `null` on a `MAYBE` is a value and is not listed", among its assumptions, and neither T3's ruling nor UES gives `MAYBE` a row of its own.
See Q2 in §8.

**Loud, but saying the wrong thing:**

- `5 EQUALS n` and `CONSIDER n WHEN 5 …` say "Trying to check equality on types that do not support it", where `n EQUALS 5` is stuck on `n` (_measured_ today; the stack makes all three undetermined).
- `CONSIDER` on an unknown whose branches are all constructors, and a field read on an unknown record, say they "reached a CONSIDER that has no branch for it" (_measured_ today; the stack makes both undetermined).
- The service reports "the answer depends on `x`" and "you left out `x`" under the same `"tag": "InterpreterError"`, today and after the stack, so a client has to parse prose to tell them apart.
- After the stack, an error or a `REFUSE` to the right of an unknown is reported as stuck on the left's inputs, not as itself (UES U13's interim).

**Different readings of one request:** `/evaluation` refuses a top-level `null` on a `BOOLEAN` that MCP and the batch endpoint evaluate (smucclaw/l4-ide#1021); the refusal is T3b's interim for the direct path, and which way they should converge is Q1.

**Different readings, by design:** every shipped ladder and the planner treat a defaulted input as unknown until it is answered, while `#EVAL`, `l4 run`, the REPL, the LSP and MCP take the default.
TY T4 makes presumption the caller's choice, and those callers have no switch.

## 8. Open questions for Meng

These are listed, not resolved, and each is a decision about the spec that owns it, not about this page.

**Q1. When should a top-level `null` stop being refused on `/evaluation`?**
Today `/evaluation` refuses it, while MCP and the batch endpoint carry a `BOOLEAN` one as an unknown (§4; smucclaw/l4-ide#1021, _measured_).
The rulings point one way.
T3's table gives `null` the row "an assumed term, **never** the default", and UES reads it as covering every input that is not a `MAYBE`, as TY's W1 says; UES calls extending the placeholder past `BOOLEAN` W1's unbuilt half.
T3b keeps eager refusal "**only** on the direct path" as an interim, with lazy binding there "its own work item".
So making MCP and batch refuse would extend the interim past the one path T3b allows it, and the question that is open is when the direct path gets lazy binding, and whether #1021 is fixed by that or by a stopgap first.
UES's parked step 6 assumes "one three-way parse … shared by `/evaluation`, batch and MCP", which is the same work.

**Q2. Is `null` on a `MAYBE` input "I don't know", or `NOTHING`?**
Today it is `NOTHING` everywhere (`fillDecision`'s `NullIsNothing`), by an assumption in TY's T6 shapes, so a caller that does not know whether there is a value gets an answer computed as if there were none (§7).
T3's ruling says a `null` means "I don't know" (the cell `Right Nothing` of the four-cell model in `RUNTIME-INPUT-STATE-SPEC.md`) and does not mention `MAYBE`; TY's W1 applies it to inputs that are not a `MAYBE`.
docassemble makes the same conflation when a `MAYBE BOOLEAN` is answered "maybe" (§6.2).
Keeping `NOTHING` matches how JSON usually spells an empty optional; making it an unknown matches T3's words and would make such a request undetermined where it now answers.

**Q3. Should the exporters come under the semantics at all?**
UES §4 excludes them, and T5 rules for a dropped default, but nothing rules for an unknown.
§6.2 shows four places that answer with no error where L4 would be undetermined: DMN's `OTHERWISE` row and `else` arm, OpenFisca's type defaults, Blawx's negation as failure, and jl4-mlir's `0` today; after #556 jl4-mlir still turns an enum string the service would refuse into the first constructor.
The choices are the ones T5 offers for defaults, map it or say it was lost, plus refusing to export a rule whose answer the target cannot keep unknown.

## 9. Keeping this page true

**Who updates it.** A change to any behaviour in §3 to §6 updates this page in the same PR.
When #553, #554 and #556 merge, their column becomes "today"; whichever of them lands last moves it.
When a parked step is unparked, its column moves the same way.

**How to re-measure.** Appendix A has the probe files.
The CLI rows of §5 are `l4 run` on a file that `ASSUME`s `x IS A BOOLEAN` and `n IS A NUMBER` and holds the one `#EVAL`; build `l4` from the tree you are describing, and copy it out of `dist-newstyle` before you run it (repo `CLAUDE.md` §3.2.1).
The service rows are `curl` against a local `jl4-service --port <p> --store-path <dir>` with Appendix A's module deployed.

**Drift found while writing this, not fixed here** (each is a short fix in a file this PR does not touch):

- UES §8 step 6, in its "_Assumed, not ruled_" block, says "An empty CSV cell stays `null`, so it is Declined and never defaulted"; TY's T3c, ruled (SOFTBOILED), says "In `l4 batch` CSV input an empty cell reads as absent, not `null`".
  The code follows T3c (`rowToJson`, `Batch.hs`; _measured_: an empty cell takes the default under soft and is refused naming the input under hard), and so do `doc/reference/types/TYPICALLY.md` and `doc/tutorials/getting-started/l4-cli.md`; a ruling outranks an assumption, so UES's sentence is stale.
- `jl4-service/README.md`'s limits list says a `CONSIDER` with an `OTHERWISE` does not stop; so does one with a variable pattern (§7).
- Meng's deferral of W6 is recorded only in #558's copy of TY; on `unstable` TY still lists W6 with no status.
- `doc/exports/dmn-bpmn.md` does not yet say that an `IF` on `null` takes its `else` arm, which UES U1b asks the DMN limits page to state.

- UES's status header says "Nothing in this document is in the tree", but its two LOUDHAILER sites landed in #541; the stack's header corrects it.
- TY's status header says W2 and W3 are built "in this branch (`feat/typically-w2w3`)"; that branch merged as #539 on 2026-10-06.
- UES cites about a dozen ladder and planner lines that have moved since `f9a504b77`; the stack's copy replaces most of them with function names.
- `specs/todo/ladder-diagrams-2026/DESIGN.md:3` says "no code yet", and its §25 heading "not built"; §25f's verdict table still matches `verdictFor` and `verdictOf`.
- `ts-shared/ladder-core/src/layout.ts`'s comment above `effectiveValuation` says the adapter "supplies no default value at all"; `viz-adapter.ts` now does.
- `jl4-service/README.md`'s list of what takes the wrapper path names neither a top-level `null` on MCP nor one in a batch case (#1021).
- The comment above the routing branch in `evaluateWithCompiled` (`Backend/Jl4.hs`) lists `FnObject` and "missing non-MAYBE" as reasons to take the wrapper path; neither is one (`requiresWrapperEvaluation`; _measured_: an input left out is refused on the direct path).
- `jl4-mlir/README.md` says its wire format is "byte-identical to jl4-service", but a defaulted input is optional in one schema and required in the other (_inferred_).
- docassemble's `DA-TYPICALLY` note says "L4's evaluator would have asked with no prefill", and Catala's note on a rule `GIVEN`'s default says "an L4 caller may not" omit it; under soft the service and batch take the default without asking (`honouredDefault`).

## Appendix A. The probes

The service module, deployed as one file with `POST /deployments -F id=<id> -F sources=@<zip>`:

```l4
@export default both inputs hold, p first
GIVEN p IS A BOOLEAN
      q IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE bothHold IF p AND q

@export both inputs hold, q first
GIVEN p IS A BOOLEAN
      q IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE bothHoldRev IF q AND p

@export r has a default
GIVEN r IS A BOOLEAN TYPICALLY TRUE
      q IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE withDefault IF r AND q
```

The hard-mode probe of §4 is a fourth function in the same shape, `q AND r` with `r IS A BOOLEAN TYPICALLY TRUE` and an unused `w IS A BOOLEAN`, sent `"presumption": "hard"` with `w` as `false` (direct path) and as `{}` (wrapper path).

The CSV probe of §9 is `l4 batch <file> -i rows.csv -c --presumption soft|hard` over `withDefault`'s shape, with a CSV whose `r` cell is empty.

The requests and responses for the `null` cases are verbatim in smucclaw/l4-ide#1021.
