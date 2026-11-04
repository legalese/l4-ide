# Numeric domain errors, trace post-processing and export schemas (as built)

As built on `main` by this PR, measured on `main` at `4c887e0db`.
Source spec: none.
Differences from the source spec: not applicable.
The work came from `unstable`; this page describes only what `main` has.

Source: PR #53 (`ed09c65ea`, landed on `unstable` through batch #77).
The labels T7 and T8 in #53's comments and fixture name targets of a review log that is not on `main`, and are left out here.

## What it does

- `SQRT` of a negative number, and an `EXPONENT` whose result is not a finite number, stop with an error instead of returning an enormous meaningless number.
- A crash in trace post-processing degrades only the trace. The stack-overflow case that caused it no longer happens.
- A negative date serial with a fraction gives the right day.
- `jl4-schema` writes builtin types as JSON types, instead of a `$ref` to a definition that does not exist, and no longer lists a `MAYBE` record field as required.

Measured with `main`'s `l4` and this PR's:

| Input                                                  | `main`                                                                          | this PR                                         |
| ------------------------------------------------------ | ------------------------------------------------------------------------------- | ----------------------------------------------- |
| `#EVAL SQRT (-1)`                                      | a number more than a hundred digits long                                        | `SQRT expects input greater than or equal to 0` |
| `#EVAL EXPONENT 0 (-1)`                                | a number more than a hundred digits long                                        | `EXPONENT produced a non-finite result (...)`   |
| `#EVAL DATE_FROM_SERIAL (-0.5)`                        | `DATE OF 2, 1, 0`, the day of serial `0.5`                                      | `DATE OF 1, 1, 0`, the day of serial `-1`       |
| `l4 trace` on an `#EVALTRACE` that overflows the stack | prints `splitEvalTraceActions: internal error`; killed at 180 s, still printing | exit 0 in 46 s, a graph whose root is `<error>` |

## Where it lives

- `SQRT`: `jl4-core/src/L4/EvaluateLazy/Machine.hs:1962`. `EXPONENT`: `Machine.hs:2036`.
- `pushFrame` records the trace `Push` only after the stack-depth check, so a `StackOverflow` leaves no dangling `Push` (`Machine.hs:286`).
- `safePostprocessTrace` catches `ErrorCall` only, so asynchronous exceptions still propagate, and substitutes `tracePostprocessFailed` (`jl4-core/src/L4/EvaluateLazy.hs:222`, used at `:151`). Its root is then overwritten by `rootCarriesOutcome` when the directive raised, so the fallback's text shows only for a directive that answered.
- `serialToUTCTime` splits with `floor` (`Machine.hs:2849`). `floor` and `truncate` agree on a non-negative serial, so no such input changes.
- `typeToJsonSchema` matches the lower-cased builtin name, plus the spellings `int`, `float`, `double`, `text`, `bool`, `time`, `listof` and `optional`, unless the module itself declares a type with that name (`jl4-core/src/L4/JsonSchema.hs:193`).
  Without the exception, #53's list made `DECLARE Text HAS ...` a JSON string; `DECLARE Date HAS ...` was already a date on `main`, and is now the record it declares. `isMaybeOrOptionalType` lower-cases too (`JsonSchema.hs:332`).

## Measured against `main`

`l4 run` with both binaries over 3,453 files with a directive (`ok/`, `legal/`, `doc/`, and `legalese/commons` at `d468311a6`), each under `JL4_FIXED_NOW=2025-01-31T15:45:30Z` with `JL4_LIBRARY_PATH` unset: 3,246 ran on both sides, 207 stop before evaluating on both sides, and no output or exit code changed.
So no file in that corpus relied on the meaningless numbers.
The instrument can see a change: the same comparison found 16 changed files for the breach change, and `ok/numeric-domain-errors.l4` differs as in the table.

## Tests that pin it

- `jl4/examples/ok/numeric-domain-errors.l4` and its four goldens.
- `jl4-core/test/TracePostprocessSpec.hs`. Its first example is its own red: the raw `postprocessTrace` still crashes on a malformed action list.
- `jl4/examples/ok/export-declared-builtin-name.l4` pins a declared type named like a builtin.
- Eight `.schema.golden` files move from `$ref` to JSON types: `legal/ceo-performance-award`, and `ok/assume-as-given`, `export-explicit-default`, `export-no-explicit-default`, `export-non-ascii`, `mixfix-garden-path`, `pattern-matching-export-given` and `pattern-matching-first-clause-annotations`.
- Nothing pins `serialToUTCTime` or the `pushFrame` order; each was measured by hand as above, because the overflow takes more than a minute.

## Limits

- `jl4-mlir/runtime/jl4-runtime.mjs` does not follow this PR: by reading, not run, `__l4_sqrt` and `__l4_pow` (`:2864`, `:2706`) go through `Math.sqrt` and `Math.pow` and raise nothing.
- `isMaybeOrOptionalType` does not look at what the module declares, so a record field typed with a type the module itself calls `Maybe` or `Optional` is not required.
- The printer still spells `BinOpExponent` as `TO THE POWER OF`; see [exponent-removal.md](exponent-removal.md).
