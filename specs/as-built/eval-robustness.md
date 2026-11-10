# Numeric domain errors, trace post-processing and export schemas (as built)

As built on `main` by this PR, measured on `main` at `4c887e0db`.
Source spec: none.
Differences from the source spec: not applicable.
The work came from `unstable`; this page describes only what `main` has.

Source: PR #53 (`ed09c65ea`, landed on `unstable` through batch #77).
The labels T7 and T8 in #53's comments and fixture name targets of a review log that is not on `main`, and are left out here.
This PR goes beyond #53 in these places, each assumed, not ruled, and not on `unstable`: both schema generators decide from the resolved type, the trace split handles a force that raises before it pushes, and a trace that cannot be built says so.
Answering the review of 2026-11-09 added four more, also assumed, not ruled: a number past a double's range raises in every builtin computed on a double, a module's own `Optional` or `Maybe` is required in both generators, `JL4_MAX_FRAME_DEPTH` sets the stack limit, and `JL4_TEST_FAIL_TRACE_POSTPROCESS` makes trace post-processing fail for a test.

## What it does

- `SQRT` of a negative number, and an `EXPONENT` that overflows, has 0 to a negative power, or has a negative base with a fractional power, stop with an error that names which, instead of returning an enormous meaningless number.
- An input past the range of a double (about 1.8E308 either side of 0) to `EXPONENT`, `SQRT`, `LN`, `LOG10`, `SIN`, `COS`, `TAN`, `ASIN`, `ACOS` or `ATAN` stops with an error naming the input, as does `LN` or `LOG10` of a number too close to 0 to be a double. `EXPONENT` says the result is too large only when both inputs are finite doubles.
- `l4 trace` on an `#EVALTRACE` that overflows the stack through `IF`, `CONSIDER`, a plain recursive call, mutual recursion or a record chain, or on a definition that needs itself, gives a graph rooted at the call, instead of failing with `splitEvalTraceActions: internal error`. Those are the shapes measured below; a `WHERE` recursion and a recursion through a list did not finish, and see Limits.
- If a trace still cannot be built, its result is a node saying `trace unavailable`, and `l4 trace` prints an error and exits 1.
- A negative date serial with a fraction gives the right day.
- `jl4-schema` writes builtin types as JSON types, instead of a `$ref` to a definition that does not exist, and no longer lists a `MAYBE` record field as required. This holds for builtins only: see Limits.
- In both schema generators, a record field is left out of `required` only when its type is the builtin `MAYBE`, which is also the only one-argument type whose schema can be null; a module's own `Optional` or `Maybe` is its declared type, and required.
- `JL4_MAX_FRAME_DEPTH`, a positive whole number, replaces the stack limit of a million frames, and the stack-overflow message states the limit reached.
- A type named like a builtin, such as a record `Text` or an enum `Time`, is that type in both schema generators, declared here or imported.

Measured with `main`'s binaries and this PR's:

| Input                                                 | `main`                                     | this PR                                                             |
| ----------------------------------------------------- | ------------------------------------------ | ------------------------------------------------------------------- |
| `#EVAL SQRT (-1)`                                     | a number more than a hundred digits long   | `SQRT expects input greater than or equal to 0`                     |
| `#EVAL EXPONENT 0 (-1)`                               | a number more than a hundred digits long   | `EXPONENT of 0 to a negative power has no result`                   |
| `#EVAL EXPONENT (-1) 0.5`, `EXPONENT (-8) (1/3)`      | a number more than a hundred digits long   | `EXPONENT does not compute a negative number to a fractional power` |
| `EXPONENT` of about -10^400 to the power 0.5          | a 309-digit number                         | the same error                                                      |
| `EXPONENT` of about -10^400 to the power -0.5         | `0`                                        | the same error                                                      |
| `EXPONENT (-2) (3 + 1/10^49)`                         | `-8`                                       | the same error                                                      |
| `#EVAL EXPONENT 10 309`, and `exp 710` from `math`    | a 309-digit number                         | `EXPONENT overflowed: the result is too large (...)`                |
| `#EVAL DATE_FROM_SERIAL (-0.5)`                       | `DATE OF 2, 1, 0`, the day of serial `0.5` | `DATE OF 1, 1, 0`, the day of serial `-1`                           |
| service schema of `DECLARE Text HAS body IS A NUMBER` | `{"type":"string"}`                        | an object with `body`, which is what the service accepts            |
| service schema of an imported record `Date`           | `{"type":"string","format":"date"}`        | an object with its fields                                           |
| `jl4-schema` of an imported record `Text`             | a `$ref` to a definition not in the file   | the same `$ref`; see Limits                                         |

Measured with this PR's binary when it was reviewed (`7b122556b`) and this head's; the review's own example is the first row:

| Input                                                | at review                                                                                 | now                                                                       |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `EXPONENT` of about 10^400 to the power 0.5          | `EXPONENT overflowed: the result is too large (...)`                                      | `EXPONENT cannot compute this: the base is past the range (...)`          |
| `EXPONENT` of about 10^400 to the power -0.5         | `0`                                                                                       | the same error                                                            |
| `EXPONENT` of about 1/10^400 to the power -0.5       | `EXPONENT overflowed: the result is too large (...)`                                      | `EXPONENT cannot compute this: the base is too close to 0 (...)`          |
| `SQRT`, `LN` or `SIN` of about 10^400                | a 309-digit number                                                                        | `SQRT cannot compute this: the number is past the range (...)`, and so on |
| `LN` of about 1/10^400                               | a 309-digit negative number                                                               | `LN cannot compute this: the number is too close to 0 (...)`              |
| a record field of the module's own `Optional NUMBER` | not required in either generator, though `jl4-schema` writes a `$ref` that cannot be null | required in both                                                          |

`l4 trace`, one `#EVALTRACE` per file, 180 s limit on `main` and 590 s here, on a machine running other builds: A node is a definition line in the DOT output: an earlier revision of this page said 4,619 for `IF`, which also counted 770 edge labels. Five runs of `IF` gave identical output, so the count does not vary.

| Recursion                                     | `main`                                               | this PR                                                         |
| --------------------------------------------- | ---------------------------------------------------- | --------------------------------------------------------------- |
| `IF n EQUALS 0 THEN 0 ELSE 1 + f (n + 1)`     | prints the internal error; killed at 180 s, 10.1 GB  | exit 0 in 12 s, 5.5 GB, 3,849 nodes, root `viaIf OF 1`          |
| `CONSIDER n` with the same recursion          | prints the internal error; killed at 180 s, 11.0 GB  | exit 0 in 18 s, 4.9 GB, 5,006 nodes, root `viaCase OF 1`        |
| `1 + loop (n + 1)`                            | prints the internal error; killed at 180 s, 7.8 GB   | exit 0 in 60 s, 3.2 GB, 10,001 nodes, root `loop OF 0`          |
| `ping n` and `pong n`, each `1 +` the other   | not measured                                         | exit 0 in 48 s, 2.8 GB, 10,001 nodes, root `ping OF 1`          |
| `1 + depth (c's next)` down a record chain    | not measured                                         | exit 0 in 43 s, 2.5 GB, 10,001 nodes, root `depth OF (mk OF 0)` |
| `x MEANS x + 1`                               | prints the internal error; exit 1 at once            | exit 0 at once, one node, root `x`, `<error>`                   |
| `1 + rest WHERE rest MEANS f (n + 1)`         | prints the internal error; killed at 180 s, 8.9 GB   | not finished at 590 s; see Limits                               |
| `y + total ys`, `CONSIDER`ing an endless list | not finished at 150 s, 13.9 GB, by the second review | not finished at 240 s, 9.2 GB, nothing on stdout; see Limits    |

## Where it lives

- `SQRT`: `jl4-core/src/L4/EvaluateLazy/Machine.hs:1974`. `EXPONENT`: `Machine.hs:2047`, checking the exact base and power before any conversion to a double, then each input as a double, then the result. `viaDouble` (`Machine.hs:1936`) does the same for the unary builtins.
- `serialToUTCTime` splits with `floor` (`Machine.hs:2856`). `floor` and `truncate` agree on a non-negative serial, so no such input changes.
- `pushFrame` records the trace `Push` only after the stack-depth check, so an overflow leaves no dangling `Push` (`Machine.hs:288`). The limit is the eval state's `maxFrameDepth` (`Machine.hs:279`), read once per evaluation by `readMaxFrameDepthEnv` (`jl4-core/src/L4/EvaluateLazy.hs:555`), and `maximumFrameDepth` (`Exceptions.hs:238`) when `JL4_MAX_FRAME_DEPTH` is unset.
- That left a second cause, measured by printing the error `safePostprocessTrace` caught on `IF` recursion. `splitEvalTraceActions` opens an address frame at each `SetRef` and closes it when the depth falls back past that frame, which assumes a `Push` follows. A force that raises first (an overflow at the update frame, or a blackhole) never pushes, so the depth never reaches the frame and the split ends in `error`, at depth -1 with the frame still open. The split now opens no frame for a `SetRef` followed directly by an exception (`jl4-core/src/L4/EvaluateLazy/Trace.hs:167`).
- `safePostprocessTrace` catches `ErrorCall` only, so asynchronous exceptions still propagate, and substitutes `tracePostprocessFailed` (`jl4-core/src/L4/EvaluateLazy.hs:232`). With `JL4_TEST_FAIL_TRACE_POSTPROCESS` set it fails inside its own `try`, for the test of `l4 trace`'s exit 1.
- `rootCarriesOutcome` leaves that fallback alone (`EvaluateLazy.hs:167`). It used to overwrite its text with the directive's exception, which gave one node with an empty label and exit 0.
- `l4 trace` exits 1 on the fallback (`jl4/app/L4/Cli/Trace.hs:153`), assumed, not ruled. No known input reaches it now: over the 6 files with `#EVALTRACE` in the differential's corpus, none does. A file whose `#EVALTRACE` is the fallback's own text exits 0, so a one-node trace of a string is not taken for the fallback.
- `typeToJsonSchema` matches builtin uniques (`jl4-core/src/L4/JsonSchema.hs:188`), and so does `primitiveJsonType` (`jl4-core/src/L4/FunctionSchema.hs:180`). Each previously matched a lower-cased name; no builtin is called `Int`, `Float`, `Text` or the like, so the only types those spellings matched were declared or imported ones. The service, the language server and MLIR all use `FunctionSchema`; only `jl4-schema` and `jl4-test` use `JsonSchema`.
- `isMaybeOrOptionalType` (`JsonSchema.hs:319`), and in `FunctionSchema` `isMaybeFieldType` (`:313`) and the one-argument arm of `typeToParameter` (`:137`), match the uniques of `MAYBE` and `LIST`, as `isMaybeType` there and in `L4.Export` already did.

## Measured against `main`

`l4 run` with both binaries over 3,453 files with a directive (`ok/`, `legal/`, `doc/`, and `legalese/commons` at `d468311a6`), each under `JL4_FIXED_NOW=2025-01-31T15:45:30Z` with `JL4_LIBRARY_PATH` unset: 3,246 ran on both sides, 207 stop before evaluating on both sides, and no output or exit code changed.
So no file in that corpus relied on the meaningless numbers.
After the review, the same comparison of this PR's head when it was reviewed (`7b122556b`) and this head, over the 59 files in `ok/`, `legal/`, `doc/` and `legalese/commons` at `8f87743e4` that name one of the builtins computed on a double or import `math`, found one changed file, `ok/numeric-domain-errors.l4`, which pins the new errors; 57 exit 0 on both sides and one exits 1 on both.
The instrument can see a change: the same comparison found 16 changed files for the breach change, and `ok/numeric-domain-errors.l4` differs as in the table.

## Tests that pin it

- `jl4/examples/ok/numeric-domain-errors.l4` and its goldens: the three `EXPONENT` errors, `SQRT` of a negative, `EXPONENT 2 1023` as the largest power of 2 that fits, a negative `DATE_FROM_SERIAL`, and each input past the range. No directive prints a number whose digits come from the platform's floating-point library: `EXPONENT 2 1023` is compared with 8 × 10^307, not printed.
- `jl4/examples/ok/numeric-exp-overflow.l4`: `exp` from `math` either side of the limit, 709 as a comparison between 2^1022 and 2^1023, because a Windows build computes other digits for e to the power 709.
- `jl4/tests-cli/Main.hs` under "l4 trace", with `fixtures/trace-overflow.l4` and `fixtures/trace-loop.l4`: a real overflow and a real blackhole. The overflow runs at `JL4_MAX_FRAME_DEPTH=300`: the case takes 1.37 s and 232 MB maximum resident set, against 12.1 s and 5.79 GB at a million frames, by `/usr/bin/time -l`. At 300 the limit falls on the update frame, and the case fails with the split's fix reverted; at 301 it does not.
- Two cases there, DOT to stdout and to `--output-dir`, run `l4 trace` with `JL4_TEST_FAIL_TRACE_POSTPROCESS` set and require exit 1 and the error line; both fail with `finish` reverted to `exitSuccess`.
- `jl4-core/test/TracePostprocessSpec.hs`: the raw `postprocessTrace` still crashes on a malformed action list, and `traceUnavailable` tells the fallback from a trace.
- `jl4-core/test/SchemaBuiltinNameSpec.hs`: both generators, for a declared record, a declared enum, an imported record, an imported enum, and each builtin including `TIME` and `DATETIME`; and for record fields of a declared `Optional`, the prelude's `MAYBE` and a declared `maybe`, that `required` holds exactly the fields whose schema cannot be null.
- `jl4/examples/ok/export-schema-shapes.l4`: every builtin, a record with a `MAYBE` field, an enum and a `oneOf`.
- `jl4/examples/ok/export-declared-builtin-name.l4`.
- Eight `.schema.golden` files move from `$ref` to JSON types: `legal/ceo-performance-award`, and `ok/assume-as-given`, `export-explicit-default`, `export-no-explicit-default`, `export-non-ascii`, `mixfix-garden-path`, `pattern-matching-export-given` and `pattern-matching-first-clause-annotations`.

## Limits

Added by this PR:

- `jl4-schema` still writes a `$ref` to a definition that does not exist for an imported type, for prelude `PAIR` (`#/$defs/PAIR`), and for the field of a parameterised type such as `DECLARE Box a` used as `Box OF NUMBER` (`#/$defs/a`). Its context holds only the module's own declarations. `main` does the same for all three.
- A declared `Optional` or `Maybe` of one argument, which on `main` `jl4-schema` read by its name, is now a `$ref` with that dangling `a`, and a required field.
- `exp` from `math` now stops with an error above about 709.78, where it used to return a 309-digit number. It is a plain `NUMBER`, not a `MAYBE`.
- A trace of `1 + rest WHERE rest MEANS f (n + 1)` overflowing the stack did not finish in 590 s. It was not stuck in post-processing, which no longer fails: `l4 trace` was still writing the trace's text into a diagnostic on stderr, 414 MB by then at about 0.7 MB/s.
- A trace of `total (nats 0)`, a recursion through an endless list, overflowing the stack did not finish in 240 s, with nothing on stdout and 777 bytes on stderr, so it was not writing a diagnostic; it is unfinished on `main` too. `l4 run` reports the same overflow in about 3 s.
- The overflow traces above cost several GB, measured in the table. Below a million frames the cost is not linear: at `JL4_MAX_FRAME_DEPTH` 300, 1,000 and 1,500, `l4 trace` of `fixtures/trace-overflow.l4` took 0.23 s, 1.9 s and 4.2 s.

The same on `main`, measured on both binaries:

- `SQRT` and `EXPONENT` go through a 64-bit double and lose exactness above about 15 digits: `EXPONENT 10 25` gives `10000000000000000905969664`, and `SQRT` of 10^48 gives `999999999999999983222784`.
- A result too small for a double is `0` with no error: `EXPONENT 10 (-400)` and `EXPONENT 0.5 1075`. So is `SQRT` of 1/10^400, whose answer 10^-200 a double holds, because the input is 0 as a double.
- `format: date-time` over-promises against the service: it refuses the RFC 3339 input `2025-01-31T10:30:00+00:00` with `Unknown timezone: '+00:00'`, accepts `2025-01-31T10:30:00Z`, and answers `"2025-01-31 10:30:00 UTC"`, which is not RFC 3339.
- The service refuses the `{"tag": ...}` shape that `oneOf` describes for a `ONE OF` with fields (`FnObject but expected type is not a known record`), and refuses `[["a", null]]` for a `LIST OF (LIST OF (MAYBE STRING))`.
- `jl4-mlir/runtime/jl4-runtime.mjs` raises for these inputs with its own message: by reading, and by the refuter feeding it `Math.sqrt(-1)`, `Math.pow(0, -1)`, `Math.pow(-1, 0.5)` and `Math.pow(10, 309)`, `ratFromNumber` (`:167`) throws `rational: non-finite ...`. The compiled backend was not run.
- `EXPONENT` of a negative base to a whole power goes through a double too: -1 to the power 10^400 + 1 gives `1`, not -1.
- The printer still spells `BinOpExponent` as `TO THE POWER OF`; see [exponent-removal.md](exponent-removal.md).
