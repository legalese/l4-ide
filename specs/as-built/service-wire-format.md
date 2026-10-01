# jl4-service result encoding and per-id deployment dedup (as built)

As built on unstable at 73a953821. Source spec: none. Differences from the source spec: not applicable.

Scope: the two jl4-service hunks of PR #162 (`632366e63c`, branch `feat/regcf-projections`), from its commit `a9caf2f69`.
The rest of #162 is Reg CF projection work (state graph, BPMN/DMN exporters, corpus, figures); its `StateGraph.hs` and `Syntax.hs` hunks are separate changes on unstable, and its backends and the Reg CF subject are not carried.

## What it does

- A function result that is a constructor is returned under the name the service's own `returnSchema` declares, without L4 source quoting: an enum value named with spaces comes back as `financial statements reviewed …`, not backtick-quoted.
- `NOTHING` is returned as JSON `null`, and `JUST x` as the encoding of `x`.
- Deploying a bundle whose sources equal an existing deployment's, under a different id, now creates that deployment; before, the service answered "ready" naming the other deployment and created nothing.

## Where it lives

- `jl4-service/src/Backend/Jl4.hs @ 73a953821`: `valueToFnLiteral` (`:1061`) uses `constructorText` for nullary and applied constructors (`:1127`, `:1147`); the `NOTHING` arm (`:1137`) and the `JUST` arm (`:1144`); `constructorText = rawNameToText . rawName . getActual` (`:1177-1178`).
- `jl4-service/src/ControlPlane.hs:178 @ 73a953821`: `postDeploymentHandler`'s shortcut for already-deployed sources also requires `did == deployId`.

## Behaviour and rules

- Constructor names come from `getActual`, matching `L4.FunctionSchema`, so values and the declared enum agree by construction.
- `TRUE` and `FALSE` (any casing) are still JSON booleans; other nullary constructors are strings.
- A record constructor still becomes an object keyed by field names when the entity info has them.
- On unstable the code comment also says the `JUST` unwrapping matches `L4.Evaluate.ValueLazyJSON`; that module (which serves `l4 batch --json`) is not on main, so this PR drops the sentence (on unstable the module came with #57).
- The dedup shortcut is keyed on content hash AND requested id.

## Tests and fixtures that pin it

- No jl4-service test pins either change (none was added by #162).
- The jl4-mlir differential harness compares the WASM backend's results with these encodings; jl4-mlir's commit `598f60d28` (inside #190, on unstable) moved the WASM runtime to them.
  On main jl4-mlir still emits the old encodings, so with this change `jl4-mlir/scripts/parity-harness.mjs` reports those cells as differences.

## Limits and known defects on unstable and with this change

- Unstable only: `jl4-service/README.md:119` still says matching sources return "the existing deployment"; in this PR that line says the match is per requested id.
- Unstable only: `ControlPlane.hs:168-169 @ 73a953821` says the old shortcut "returned HTTP 200"; the route answers 202 (`:123`), and this PR's comment says so.
- Both, read in code, not run: on the wrapper-evaluation path (any `null` or uncertain argument, every deontic call, the source-text path; `requiresWrapperEvaluation`, `Backend/Jl4.hs:527 @ 73a953821`, `:519` with this change), the generated `#EVAL` yields `JUST (f args)`, and `handleEvalResult` (`:851 @ 73a953821`, `:853` with this change) now (a) reports "Evaluation produced unknown value" when a MAYBE-returning function's answer is `NOTHING`, because `JUST NOTHING` becomes `FnUnknown`; (b) unwraps a one-element LIST result to its element through its backwards-compatibility arm (`:880 @ 73a953821`, `:881` with this change), so the direct and wrapper paths disagree; (c) never reaches its `FnObject [("JUST", …)]` arms; (d) when the wrapper's JSON decode fails it returns bare `NOTHING` (`CodeGen.hs:292, 303, 313` with this change), which was the string `"NOTHING"` with a success status and now throws "Evaluation produced unknown value", indistinguishable from (a).
