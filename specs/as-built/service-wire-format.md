# jl4-service result encoding, wrapper answers, and per-id deployment dedup (as built)

As built on unstable at 73a953821 (the encoding and the dedup) and 9c56c0ead (the wrapper answers). Source spec: none. Differences from the source spec: not applicable.

Scope: the two jl4-service hunks of PR #162 (`632366e63c`, branch `feat/regcf-projections`), from its commit `a9caf2f69`; and the answer side of PR #562 (`9c56c0ead`, branch `fix/service-wrapper-unbox`), from its commits `eba40d689` and `079d6a616`.
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

## Where it lives

- `jl4-service/src/Backend/Jl4.hs`, with this change: `valueToFnLiteral` (`:1085`) recognises `NOTHING` (`:1149`) and `JUST` (`:1162`) by unique, and uses `constructorText` for nullary and applied constructors (`:1152`, `:1165`); `constructorText = rawNameToText . rawName . getActual` (`:1195-1196`).
- `jl4-service/src/Backend/Jl4.hs`, with this change: `handleEvalResult` (`:862`) opens the wrapper's envelope by unique (`openEnvelope`, `:879`) and hands the answer to `handleEvalResultDirect` (`:689`); `wrapperDeclined` (`:894`) builds the refusal.
- `jl4-service/src/Backend/CodeGen.hs`, with this change: `GeneratedCode` carries `answerShape` (`AnswerShape`, `:96`) and `requiredInputs` (`RequiredInput`, `:105`), computed by `isRequiredInput` and `requiredInputsOf` (`:116`, `:120`); they replace `decodeFailedSentinel`, which nothing read.
- `jl4-service/src/ControlPlane.hs:175`, with this change: `postDeploymentHandler`'s shortcut for already-deployed sources also requires `did == deployId`.

## Behaviour and rules

- Constructor names come from `getActual`, matching `L4.FunctionSchema`, so values and the declared enum agree by construction.
- `TRUE` and `FALSE` (any casing) are still JSON booleans; other nullary constructors are strings.
- A record constructor still becomes an object keyed by field names when the entity info has them.
- On unstable the code comment also says the `JUST` unwrapping matches `L4.Evaluate.ValueLazyJSON`; that module (which serves `l4 batch --json`) is not on main, so this change drops the sentence (on unstable the module came with #57).
- The wrapper answers `JUST answer`, or `NOTHING` without calling the function when a required input (one that is neither a `BOOLEAN` nor a `MAYBE`) is absent or is a temporal string its `TODATE`, `TOTIME` or `TODATETIME` rejects.
  A function with no inputs gets a bare `#EVAL` with no envelope (`Bare`).
- Absent means left out, `null` or `{}`. When an input is absent, the first absent required input in the wrapper's unwrapping order (rule `GIVEN`s, then `ASSUME`s) is named, even if the wrapper stopped earlier at a string it could not parse.
- A value of the wrong JSON type is not a decline: JSONDECODE stops with its own error (`Expected JSON number but got: String "abc"`), as on main.
- The dedup shortcut is keyed on content hash AND requested id.

## Tests and fixtures that pin it

- `jl4-service/test/IntegrationSpec.hs`, "answers on the direct and wrapper paths (smucclaw/l4-ide#1003)": `wireCases`, 34 requests against `wireProbeJL4` (`TestData.hs`), each answer shape on both paths; `trace=full` and batch on the wrapper path.
- The same block, "when the wrapper cannot call the function": an unreadable and a missing `DATE`, a missing `ASSUME` on both paths (`declineLabelsJL4`), and a missing input of a deontic rule (`deonticRecordPartyJL4`).
- `jl4-service/test/CodeGenSpec.hs`: a function with no inputs gets `Bare`, ordinary and deontic.
- With `Jl4.hs`, `CodeGen.hs` and `CodeGenSpec.hs` reverted to the encoding-only change, 14 of these fail; reverted to main's, 17 fail.
- No test pins the dedup change.
- The jl4-mlir differential harness compares the WASM backend's results with these encodings; jl4-mlir's commit `598f60d28` (inside #190, on unstable) moved the WASM runtime to them.
  On main jl4-mlir still emits the old encodings, so with this change `jl4-mlir/scripts/parity-harness.mjs` reports those cells as differences.

## Limits on main with this change

Measured 2026-10-07 against jl4-service built from main 838c92ed4, and unchanged by this change, which touches only the answer side:

- On the wrapper path, a function with a `BOOLEAN` input fails with a type error (`fromMaybe` is not in scope in the generated wrapper), and so does one with a required `TIME` or `DATETIME` input (`TOTIME` and `TODATETIME` are applied to an already-typed value).
  So the `TIME` and `DATETIME` refusals above are not reached on main; the `DATE` one is.
- On the wrapper path, a function with a `MAYBE` input followed by another input fails with a parser error in the generated input record (measured with `MAYBE NUMBER` and `MAYBE DATE`).
- On unstable, jl4-service-test answers such requests on the wrapper path ("MAYBE inputs on the wrapper path" in `jl4-service/test/IntegrationSpec.hs @ 9c56c0ead`); the fixes are in unstable's request handling, which this change does not carry.
