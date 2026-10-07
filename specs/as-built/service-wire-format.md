# jl4-service result encoding, wrapper answers, and per-id deployment dedup (as built)

As built on unstable at 73a953821 (the encoding and the dedup) and 9c56c0ead (the wrapper answers). Source spec: none. Differences from the source spec: not applicable.

Scope: the two jl4-service hunks of PR #162 (`632366e63c`, branch `feat/regcf-projections`), from its commit `a9caf2f69`; the answer side of PR #562 (`9c56c0ead`, branch `fix/service-wrapper-unbox`), from its commits `eba40d689` and `079d6a616`; and, of #549 (`35d7b63b3`), only the batch endpoint returning an errored case with its `@error`.
The rest of #162 is Reg CF projection work (state graph, BPMN/DMN exporters, corpus, figures); its `StateGraph.hs` and `Syntax.hs` hunks are separate changes on unstable, and its backends and the Reg CF subject are not carried.
#562 was written on unstable and then merged with #549 (presumption and defaults, `35d7b63b3`), which rewrote how the wrapper reads a request; #549 is not on main.
This change keeps main's request handling and carries #562's handling of the wrapper's answer.

## What it does

- A function result that is a constructor is returned under the name the service's own `returnSchema` declares, without L4 source quoting: an enum value named with spaces comes back as `financial statements reviewed …`, not backtick-quoted.
- `NOTHING` is returned as JSON `null`, and `JUST x` as the encoding of `x`.
  Both are recognised by their uniques, so a rule's own constructor called `Nothing` or `Just` is an ordinary answer.
- A request evaluated through the generated wrapper is answered exactly as the direct path answers it: a `MAYBE` answer of `NOTHING` is `null`, and a one-element list stays a list.
- When the wrapper cannot call the function, the request is refused with a message that names the input: a required input that is absent gets the direct path's message (`Parameter 'n': missing required parameter`, or `ASSUME 'n': …`), and a required `DATE`, `TIME` or `DATETIME` string that does not parse is quoted (`Parameter 'end date': could not read "garbage" as a DATE`).
  Before, main answered such a request 200 with the string `"NOTHING"`, as if the rule had.
- Deploying a bundle whose sources equal an existing deployment's, under a different id, now creates that deployment; before, the service answered "ready" naming the other deployment and created nothing.
  An upload with no id gets a fresh UUID, so it is never matched either: each one creates a new deployment, where main answered "ready" with the existing one whose sources matched.
  So a client that redeploys in a loop without an id now gains a deployment per upload, up to `--max-deployments` (default 1024); the README says so.
  The answer named the other deployment and carried its metadata: its functions and their schemas, its files and their exports, and its description.
- A batch case that fails comes back in `cases` with its `@id` and, as `@error`, the message the single-case endpoint refuses it with, and is still counted in `casesIgnored`; before, it was left out of `cases` and only counted.
  This is the batch-response piece of #549 (`35d7b63b3`) and nothing else from it: main has no `REFUSE`, so no `@refused`, and no defaults, so no `@presumed`.

## Where it lives

- `jl4-service/src/Backend/Jl4.hs`, with this change: `valueToFnLiteral` (`:1106`) recognises `NOTHING` (`:1170`) and `JUST` (`:1183`) by unique, and uses `constructorText` for nullary and applied constructors (`:1173`, `:1186`); `constructorText = rawNameToText . rawName . getActual` (`:1216-1217`).
- `jl4-service/src/Backend/Jl4.hs`, with this change: `handleEvalResult` (`:877`) opens the wrapper's envelope by unique (`openEnvelope`, `:895`) and hands the answer to `handleEvalResultDirect` (`:689`); `wrapperDeclined` (`:910`) builds the refusal. The comment above `handleEvalResult` says why a top-level `null` is answered with 200 rather than refused, as the old handler did.
- `jl4-service/src/Backend/CodeGen.hs`, with this change: `GeneratedCode` carries `answerShape` (`AnswerShape`, `:96`) and `requiredInputs` (`RequiredInput`, `:105`), computed by `isRequiredInput` and `requiredInputsOf` (`:116`, `:120`); they replace `decodeFailedSentinel`, which nothing read.
- `jl4-core/src/L4/EvaluateLazy/Machine.hs:25-29`, with this change: exports `parseDateText`, `parseTimeText` and `parseDatetimeText`, the parsers of `TODATE`, `TOTIME` and `TODATETIME`, for `wrapperDeclined` (from #570, `a982e3060`, on unstable).
- `jl4-service/src/ControlPlane.hs:175`, with this change: `postDeploymentHandler`'s shortcut for already-deployed sources looks up the requested id (`Map.lookup deployId`) and compares its version, where main scanned the registry for any deployment with the same version.
- `jl4-service/src/DataPlane.hs:312`, with this change: the batch handler's `outputCase`; `CaseOutcome` and the `@error` key in `jl4-service/src/Types.hs:421` and `:524`.

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
  JSONDECODE answers `LEFT`, which the wrapper also turns into `NOTHING`, only when the JSON text does not parse (`decodeJsonToValueTyped`, `jl4-core/src/L4/EvaluateLazy/Machine.hs:1365-1369`); the service writes that text itself.
- A `MAYBE (MAYBE x)` answer cannot tell `NOTHING` from `JUST NOTHING`: both are `null`. Main answered `"NOTHING"` and `{"JUST": ["NOTHING"]}`.
- The dedup shortcut is keyed on content hash AND requested id.
  Unstable at 9c56c0ead has the same condition (`jl4-service/src/ControlPlane.hs:178 @ 9c56c0ead`) and also gives an id-less upload a fresh UUID, so it behaves the same; #UNSTABLE corrects its README line on duplicate detection, which described the content-only match, and adds the same test.
- A top-level `null` on the wrapper path is an answer (`NOTHING` or `JUST NOTHING`), answered 200 as on the direct path; main's old wrapper handler refused any top-level unknown with a 422.
  Neither path can produce the evaluator's `Omitted` truncation marker at the top level: `nf` starts at depth `maximumStackSize` (200) and marks `Omitted` only below 0.

## Tests and fixtures that pin it

- `jl4-service/test/IntegrationSpec.hs`, "answers on the direct and wrapper paths (smucclaw/l4-ide#1003)": `wireCases`, 35 requests against `wireProbeJL4` (`TestData.hs`), each answer shape on both paths; `trace=full` and batch on the wrapper path.
- The same block, "when the wrapper cannot call the function": an unreadable and a missing `DATE`; two `DATE`s where only the second is unreadable to `TODATE` (`twoDatesJL4`, from #570); a batch case the wrapper declines, returned with its `@error` and counted, which the direct path would have answered; a missing `ASSUME` on both paths (`declineLabelsJL4`); and a missing input of a deontic rule (`deonticRecordPartyJL4`).
- `jl4-service/test/CodeGenSpec.hs`: a function with no inputs gets `Bare`, ordinary and deontic; `requiredInputs` leaves out `BOOLEAN` and `MAYBE` inputs, lists `GIVEN`s before `ASSUME`s, and marks a `DATE`.
- With `Jl4.hs`, `CodeGen.hs` and `CodeGenSpec.hs` as they are with the encoding change alone, 15 of these fail; as on main, 19 fail; with `Jl4.hs` checking dates with the service's ISO parsers instead of `TODATE`'s, only the two-`DATE` test fails.
- `jl4-service/test/IntegrationSpec.hs`, "skips recompiling identical sources only under the same id": a POST for `beta` with `alpha`'s bytes answers `beta`, `GET /deployments/beta` is then 200, and the same bytes posted again under `beta` answer `ready` with no `updateId`. With main's content-only match it fails at the first; with no shortcut at all, at the third.
- The same file, "batch, where null takes the wrapper" and "returns a batch case the wrapper declines with its `@error`": the errored case's `@id` and `@error`. With main's batch handler both fail.
- The jl4-mlir differential harness compares the WASM backend's results with these encodings; jl4-mlir's commit `598f60d28` (inside #190, on unstable) moved the WASM runtime to them.
  On main jl4-mlir still emits the old encodings, so with this change `jl4-mlir/scripts/parity-harness.mjs` reports those cells as differences.

## Limits on main with this change

Measured 2026-10-07 against jl4-service built from main 838c92ed4, run with `XDG_DATA_HOME` pointed at an empty directory (on a machine whose `~/.local/share/jl4/libraries` holds a newer prelude, the wrapper's `IMPORT prelude` resolves to it instead and fails to parse it). None of these is changed by this change, which touches only the answer side:

- On the wrapper path, a name the module gets by `IMPORT` is not found (measured with `prelude`'s `range`), so every function in a module that uses one fails with "I could not find a definition"; a function with a `BOOLEAN` input fails the same way, on the `fromMaybe` the generated wrapper uses to read it.
- On the wrapper path, a required `LIST OF NUMBER` input fails with a type error (the wrapper reads it as `LIST OF MAYBE OF NUMBER`), and so does a required `TIME` or `DATETIME` input (`TOTIME` and `TODATETIME` are applied to an already-typed value).
  So the `TIME` and `DATETIME` refusals above are not reached on main; the `DATE` one is.
- On the wrapper path, a function with a `MAYBE` input followed by another input fails with a parser error in the generated input record (measured with `MAYBE NUMBER` and `MAYBE DATE`).
- On the direct path, a `DATE` string that does not parse is not refused: the rule receives the text (`date first` with `"garbage"` answers `"garbage"`).
- A list answer of more than 200 elements comes back as its first 200 elements followed by two `null`s (measured with 201, on the direct path, identically on main).
- The published `returnSchema` gives a record's fields at the top level, without the constructor key the answer has, and a `MAYBE` as its inner type, without `null` (smucclaw/l4-ide#ISSUE).
- On unstable, jl4-service-test answers such requests on the wrapper path ("MAYBE inputs on the wrapper path" in `jl4-service/test/IntegrationSpec.hs @ 9c56c0ead`); the fixes are in unstable's request handling, which this change does not carry.
