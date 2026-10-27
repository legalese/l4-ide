# jl4-service result encoding, wrapper answers, and per-id deployment dedup (as built)

As built on unstable at 73a953821 (the encoding and the dedup), 9c56c0ead (the wrapper answers) and 35d7b63b3 (the batch response). Source spec: none. Differences from the source spec: not applicable.

Scope: the two jl4-service hunks of PR #162 (`632366e63c`, branch `feat/regcf-projections`), from its commit `a9caf2f69`; the answer side of PR #562 (`9c56c0ead`, branch `fix/service-wrapper-unbox`), from its commits `eba40d689` and `079d6a616`; and, of #549 (`35d7b63b3`), only the batch endpoint returning an errored case with its `@error`.
The rest of #162 is Reg CF projection work (state graph, BPMN/DMN exporters, corpus, figures); its `StateGraph.hs` and `Syntax.hs` hunks are separate changes on unstable, and its backends and the Reg CF subject are not carried.
#562 was written on unstable and then merged with #549 (presumption and defaults, `35d7b63b3`), which rewrote how the wrapper reads a request; #549 is not on main.
This change keeps main's request handling and carries #562's handling of the wrapper's answer.

## What it does

- A function result that is a constructor is returned under the name the service's own `returnSchema` declares, without L4 source quoting: an enum value named with spaces comes back as `financial statements reviewed …`, not backtick-quoted.
- `NOTHING` is returned as JSON `null`, and `JUST x` as the encoding of `x`.
  Both are recognised by their uniques, so a rule's own constructor called `Nothing` or `Just` is an ordinary answer.
- A request evaluated through the generated wrapper is answered exactly as the direct path answers it: a `MAYBE` answer of `NOTHING` is `null`, and a one-element list stays a list.
- When the wrapper cannot call the function, the request is rejected with a message that names the input: a required input that is absent gets the direct path's message (`Parameter 'n': missing required parameter`, or `ASSUME 'n': …`), and a required `DATE`, `TIME` or `DATETIME` string that does not parse is quoted (`Parameter 'end date': could not read "garbage" as a DATE`).
  Before, main answered such a request 200 with the string `"NOTHING"`, as if the rule had.
- Deploying a bundle whose sources equal an existing deployment's, under a different id, now creates that deployment; before, the service answered "ready" naming the other deployment and created nothing.
  An upload with no id gets a fresh UUID, so it is never matched either: each one creates a new deployment, where main answered "ready" with the existing one whose sources matched.
  So a client that redeploys in a loop without an id now gains a deployment per upload, up to `--max-deployments` (default 1024); the README says so.
  The answer named the other deployment and carried its metadata: its functions and their schemas, its files and their exports, and its description.
- A batch case that fails comes back in `cases` with its `@id` and, as `@error`, the message its evaluation stopped with (`prettyEvaluatorError`), and is still counted in `casesIgnored`; before, it was left out of `cases` and only counted.
  The message can differ from the single-case endpoint's for the same input, since a batch case with a `null` takes the wrapper and a single request does not.
  A case that reaches `--eval-timeout` or `--max-eval-memory-mb` still fails the whole batch with `500`; unstable returns it with `@error` and `@limit`, from `0765fef5d` and `a09544dd6`, later commits of #549 that need its `EvalLimits` module and the threaded RTS, and are not carried.
  Because main runs every case of a batch at once on the non-threaded RTS, each case's clock counts its siblings' work: 40 cases of a rule that answers one request in about 0.12 s fail the batch at `--eval-timeout 3`, and 10 answer (measured 2026-10-07 on this branch's build).
  This is the batch-response piece of #549 (`35d7b63b3`) and nothing else from it.
  A case that refuses comes back with its `@id` and, as `@refused`, the refusal `{"kind": "refused", "reason": …}`, and is counted in `casesProcessed`, not in `casesIgnored`.
  Main has no defaults, so no `@presumed`.
- A refusal is written as the same value at every door that reaches it: a single request answers it with a `422` whose body is `{"tag": "Error", "contents": {"kind": "refused", "reason": …}}`, a batch case carries the inner value as `@refused`, and an MCP tool call answers it with `isError: true` and the `422`'s body as its text.
  The value is core's `refusalMarker` (`jl4-core/src/L4/EvaluateLazy/Exceptions.hs`), written for the service by `EvaluatorRefused`'s `ToJSON` (`jl4-service/src/Backend/Api.hs`).
  The reason is the rule's, verbatim: the MCP door does not rewrite input names in it, as it does in an error's message.
  A task, with which the service answers an MCP tool call from a client that asks for one while the deployment is still compiling, has as its result the text the call would have answered: `runEvalWorker` evaluates the call with `runMcpEvaluationIO`, as a call answered at once is evaluated.
  For a function that does not return `DEONTIC`, two doors read some inputs as main reads them, and so can answer without reaching a refusal that a batch case reaches.
  Its MCP tool drops an input that it lists as `startTime`, `events` or `arguments`, and answers the call as a call without that input is answered (`buildArgPairs`, `jl4-service/src/McpServer.hs`).
  The evaluation endpoint takes a function with inputs named `startTime` and `events` for one that returns `DEONTIC`, and answers with an error a request for it that does not give both at its top level (`evalFunctionHandler`, `jl4-service/src/DataPlane.hs`).

## Where it lives

- `jl4-service/src/Backend/Jl4.hs`, with this change: `valueToFnLiteral` (`:1106`) recognises `NOTHING` (`:1170`) and `JUST` (`:1183`) by unique, and uses `constructorText` for nullary and applied constructors (`:1173`, `:1186`); `constructorText = rawNameToText . rawName . getActual` (`:1216-1217`).
- `jl4-service/src/Backend/Jl4.hs`, with this change: `handleEvalResult` opens the wrapper's envelope by unique (`openEnvelope`) and hands the answer to `handleEvalResultDirect`; `wrapperDeclined` builds the rejection. The comment above `handleEvalResult` says why a top-level `null` is answered with 200 rather than rejected, as the old handler did.
- `jl4-service/src/Backend/CodeGen.hs`, with this change: `GeneratedCode` carries `answerShape` (`AnswerShape`, `:96`) and `requiredInputs` (`RequiredInput`, `:105`), computed by `isRequiredInput` and `requiredInputsOf` (`:116`, `:120`); they replace `decodeFailedSentinel`, which nothing read.
- `jl4-core/src/L4/EvaluateLazy/Machine.hs`, with this change: exports `parseDateText`, `parseTimeText` and `parseDatetimeText`, the parsers of `TODATE`, `TOTIME` and `TODATETIME`, for `wrapperDeclined` (from #570, `a982e3060`, on unstable).
- `jl4-service/src/ControlPlane.hs:175`, with this change: `postDeploymentHandler`'s shortcut for already-deployed sources looks up the requested id (`Map.lookup deployId`) and compares its version, where main scanned the registry for any deployment with the same version.
- `jl4-service/src/DataPlane.hs`, with this change: the batch handler's `outputCase`; `CaseOutcome` and the `@error` and `@refused` keys in `jl4-service/src/Types.hs`.

## Behaviour and rules

- Constructor names come from `getActual`, matching `L4.FunctionSchema`, so values and the declared enum agree by construction.
- `TRUE` and `FALSE` (any casing) are still JSON booleans; other nullary constructors are strings.
- A record constructor still becomes an object keyed by field names when the entity info has them.
- On unstable the code comment also says the `JUST` unwrapping matches `L4.Evaluate.ValueLazyJSON`; that module (which serves `l4 batch --json`) is not on main, so this change drops the sentence (on unstable the module came with #57).
- The wrapper answers `JUST answer`, or `NOTHING` without calling the function when a required input (one that is neither a `BOOLEAN` nor a `MAYBE`) is absent or is a temporal string its `TODATE`, `TOTIME` or `TODATETIME` rejects.
  A function with no inputs gets a bare `#EVAL` with no envelope (`Bare`).
- Absent means left out, `null` or `{}`. When an input is absent, the first absent required input in the wrapper's unwrapping order (rule `GIVEN`s, then `ASSUME`s) is named, even if the wrapper stopped earlier at a string it could not parse.
- Otherwise the required temporal string the wrapper's own parser rejects is quoted; when several are rejected, the message names them all, without quoting.
  The check uses the parsers `TODATE`, `TOTIME` and `TODATETIME` use, so a string the wrapper read is never blamed: with `"2026/01/31"` and `"2026-02-30"`, the second is named.
  #562 checked with the service's own ISO parsers (`parseIsoDate` and its siblings), which accept `2026-02-30` and reject `2026/01/31`; #570 (`a982e3060`) fixed that on unstable, and this change carries it.
- A value of the wrong JSON type is not a decline: JSONDECODE stops with its own error (`Expected JSON number but got: String "abc"`), as on main.
  JSONDECODE answers `LEFT`, which the wrapper also turns into `NOTHING`, only when the JSON text does not parse (`decodeJsonToValueTyped`, `jl4-core/src/L4/EvaluateLazy/Machine.hs:1373-1377`); the service writes that text itself.
- A `MAYBE (MAYBE x)` answer cannot tell `NOTHING` from `JUST NOTHING`: both are `null`. Main answered `"NOTHING"` and `{"JUST": ["NOTHING"]}`.
- The dedup shortcut is keyed on content hash AND requested id.
  Unstable at 9c56c0ead has the same condition (`jl4-service/src/ControlPlane.hs:178 @ 9c56c0ead`) and also gives an id-less upload a fresh UUID, so it behaves the same; legalese/l4-ide#574 corrects its README line on duplicate detection, which described the content-only match, and adds the same test.
- A top-level `null` on the wrapper path is an answer (`NOTHING` or `JUST NOTHING`), answered 200 as on the direct path; main's old wrapper handler rejected any top-level unknown with a 422.
  Neither path can produce the evaluator's `Omitted` truncation marker at the top level: `nf` starts at depth `maximumStackSize` (200) and marks `Omitted` only below 0.
- A list answer of more than 200 elements comes back cut short and ending in two `null`s, on the direct path, the wrapper path and in a batch alike.
  Each constructor around the list takes one element of that depth: a list inside a `MAYBE` or in a record's field is cut one element sooner, and a list in a record inside a record two sooner.
  The wrapper's `JUST` takes no level of the depth to which an answer is read: `evaluateModule` sets `answerInJust` in the evaluator's `EvalConfig` for a wrapper that answers `JUST (f args)`, and the evaluator reads the answer inside that `JUST` from the full depth, as the direct path reads `f args`.
  So a refusal or a division by zero at the end of a long list answer is reached at the same length on every path.

## Tests and fixtures that pin it

- `jl4-service/test/IntegrationSpec.hs`, "answers on the direct and wrapper paths (smucclaw/l4-ide#1003)": `wireCases`, 35 requests against `wireProbeJL4` (`TestData.hs`), each answer shape on both paths; `trace=full` and batch on the wrapper path.
- The same block, "when the wrapper cannot call the function": an unreadable and a missing `DATE`; two `DATE`s where only the second is unreadable to `TODATE` (`twoDatesJL4`, from #570); a batch case the wrapper declines, returned with its `@error` and counted, which the direct path would have answered; a missing `ASSUME` on both paths (`declineLabelsJL4`); and a missing input of a deontic rule (`deonticRecordPartyJL4`).
- The same file, "batch evaluation", "returns a case that refuses as refused and processed, and every door carries the same refusal": one case that refuses and one that answers, in a batch, as a single request and as an MCP tool call.
- The same block, "answers an MCP tool called as a task, while its deployment compiles, as a call is answered, a refusal among them": the same rule, its deployment held compiling while a client that asks for a task calls the tool, then compiled; the task's result, polled with `tasks/get`, is the evaluation request's body, for a case that refuses and for one that answers.
- The same file, "answers read to the same depth on every path": rules whose list answer ends in a `REFUSE` or a `1 DIVIDED BY 0`, as an element or as the rest, a rule that answers the first of those lists inside its own `JUST`, and one that answers it in a record inside a record, each called at the last length that reaches that end and at one past it, on the direct path, the wrapper path and in a batch.
- `jl4-core/test/RefuseSpec.hs`, "is reached one element sooner inside any other constructor, when the caller says the answer is wrapped": with `answerInJust` set, an answer whose head is a constructor other than `JUST` is read as it is without the setting, its constructor taking a level, and a constructor inside it one more.
- `jl4-service/test/SchemaSpec.hs`, "reads a refused case as neither an answer nor an error, and writes it back as it was", and "a refusal in the place of an error": a refused case, an `EvaluatorError` and a `SimpleResponse` that refused, each read and written back.
  `reads no case from an @refused whose kind is not "refused"`: an `@refused` of another kind is not read as a refusal.
- `jl4-service/test/CodeGenSpec.hs`: a function with no inputs gets `Bare`, ordinary and deontic; `requiredInputs` leaves out `BOOLEAN` and `MAYBE` inputs, lists `GIVEN`s before `ASSUME`s, and marks a `DATE`.
- With `Jl4.hs`, `CodeGen.hs` and `CodeGenSpec.hs` as they are with the encoding change alone, 15 of these fail; as on main, 19 fail; with `Jl4.hs` checking dates with the service's ISO parsers instead of `TODATE`'s, only the two-`DATE` test fails.
- `jl4-service/test/IntegrationSpec.hs`, "skips recompiling identical sources only under the same id": a POST for `beta` with `alpha`'s bytes answers `beta`, `GET /deployments/beta` is then 200, and the same bytes posted again under `beta` answer `ready` with no `updateId`. With main's content-only match it fails at the first; with no shortcut at all, at the third.
- The same file, "batch, where null takes the wrapper" and "returns a batch case the wrapper declines with its `@error`": the errored case's `@id` and `@error`, and, in the second, the outcomes a client reads by decoding the body as a `BatchResponse`. With main's batch handler both fail; with `FromJSON OutputCase` ignoring `@error`, the second does.
- `jl4-service/test/SchemaSpec.hs`, "OutputCase": an errored case is written as `@id` and `@error`, an answered one as `@id` and its result, and both read back as written. With `@error` neither written nor read, the first and third fail.
- The jl4-mlir differential harness compares the WASM backend's results with these encodings; jl4-mlir's commit `598f60d28` (inside #190, on unstable) moved the WASM runtime to them.
  On main jl4-mlir still emits the old encodings, so with this change `jl4-mlir/scripts/parity-harness.mjs` reports those cells as differences.

## Limits on main with this change

Measured 2026-10-07 against jl4-service built from main 838c92ed4, run with `XDG_DATA_HOME` pointed at an empty directory (on a machine whose `~/.local/share/jl4/libraries` holds a newer prelude, the wrapper's `IMPORT prelude` resolves to it instead and fails to parse it). None of these is changed by this change, which touches only the answer side:

- On the wrapper path, a name the module gets by `IMPORT` is not found (measured with `prelude`'s `range`), so every function in a module that uses one fails with "I could not find a definition"; a function with a `BOOLEAN` input fails the same way, on the `fromMaybe` the generated wrapper uses to read it.
- On the wrapper path, a required `LIST OF NUMBER` input fails with a type error (the wrapper reads it as `LIST OF MAYBE OF NUMBER`), and so does a required `TIME` or `DATETIME` input (`TOTIME` and `TODATETIME` are applied to an already-typed value).
  So the `TIME` and `DATETIME` rejections above are not reached on main; the `DATE` one is.
- On the wrapper path, a function with a `MAYBE` input followed by another input fails with a parser error in the generated input record (measured with `MAYBE NUMBER` and `MAYBE DATE`).
- On the direct path, a `DATE` string that does not parse is not rejected: the rule receives the text (`date first` with `"garbage"` answers `"garbage"`).
- The published `returnSchema` gives a record's fields at the top level, without the constructor key the answer has, and a `MAYBE` as its inner type, without `null` (smucclaw/l4-ide#1010).
- On unstable, jl4-service-test answers such requests on the wrapper path ("MAYBE inputs on the wrapper path" in `jl4-service/test/IntegrationSpec.hs @ 9c56c0ead`); the fixes are in unstable's request handling, which this change does not carry.
