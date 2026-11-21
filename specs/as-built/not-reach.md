# The one-line NOT refusal (as built)

Status, 2026-11-21: on the local branch `fix/not-single-line-main`, not merged to `main` and not pushed.
Verified on that branch by `cabal test all` (with `JL4_LIBRARY_PATH` pinned) and `doc/test-docs.sh` with the branch's `l4` first on `PATH`, which is what `main`'s CI runs (`main` has no `etc/verify-branch.sh`), and by a run of the branch's `l4 check` over every `.l4` file the repository tracks.
Source spec: `specs/todo/SET-OPERATORS-SPEC.md` §18.1 to §18.3 (ruling R-NOT-1), which lives on `unstable` and not on `main`.
This page describes only what the port gives `main`.
Ported from `unstable` 1d0610096, 2eee7eb2e and 5171acee2 (legalese/l4-ide#356).

Scope: the check that refuses a `NOT` whose operand runs over an `AND`, `OR` or `IMPLIES` on the `NOT`'s own line, its message and code, and the printer change it forced.
No other spec on `main` owns `NOT`'s reach.

## What it does

`NOT` has no precedence; its operand is delimited by layout.
The parser keeps adding operators to the operand for as long as they start to the right of the `NOT`, and on one line everything after the `NOT` is to its right.
So `NOT a AND b` and `NOT (a) AND b` both mean `NOT (a AND b)`, while most readers take them as `(NOT a) AND b`.
Before the port both parsed, checked and gave the wide answer with no diagnostic.
Now both are a check error, which shows both readings printed from the real expressions and names the two ways to write the narrow one.

Not refused: `(NOT a) AND b`, `NOT (a AND b)`, every multi-line form (the columns decide), a `NOT` last on its line (`a AND NOT b`), comparisons (`NOT n EQUALS 0`), the `NOT` that `UNLESS` produces (no keyword on the page), and the statutory-label idiom `NOT "(3)" ... x`, where the left operand of the implicit `AND` is an inert string.

## Where it lives

- `jl4-core/src/L4/Lint/NotReach.hs`: `NotReachSite` (`:68`), `detectSameLineNotReach` (`:88`), `sameLineNotReach` (`:98`), `firstSameLineConnective` (`:115`) and `isLabel` (`:152`).
  It walks the parsed module, before desugaring and name resolution, and reads token positions off the annotations.
- `jl4-core/src/L4/TypeCheck.hs:192-193`: the sites are added to the structural errors of `doCheckProgramWithDependencies`, beside the computed-field cycle errors, so the rest of the module is still checked.
- `jl4-core/src/L4/TypeCheck.hs:4952`: the message, in `prettyCheckError`.
- `jl4-core/src/L4/TypeCheck/Types.hs:140`, `:344`, `:446`: the `NotReachesConnective` constructor, its code, and its range (from the `NOT` to the end of the connective it reaches over).
- `jl4-core/src/L4/Print.hs:503-504`: `NOT` prints its operand through `parensIfOpenTailed`, so `Not (And a b)` comes back as `NOT (a AND b)`; see `specs/as-built/printer-bracket.md`.

## What the port changed against `unstable`

- **A diagnostic code.** `main` gives every checker diagnostic a code, and `checkErrorCode` has no wildcard, so the constructor could not build without one.
  The port uses `check/negation-reaches-over-connective`, listed in `jl4-lsp/DIAGNOSTIC-CODES.md` and anchored on the error page.
  `unstable` prints `Code: <none>` for this error, so its two `not-ok/tc` goldens differ from `main`'s in that line only.
  The name is assumed, not ruled.
- **The wiring.** `main`'s `doCheckProgramWithDependencies` has no section-`GIVEN` or type-synonym checks, so the refusal joins the computed-field cycle errors, the one structural list `main` has.
- **The text linter is not ported.** `unstable` also runs `etc/check-not-precedence.mjs` in CI (#341 and a26d1d85a) over files that no test type-checks; `main` has neither the script nor its CI job.
  On `main` the check runs only where a file is type-checked.
- **The docs are `main`'s own.** `unstable`'s `NOT.md`, `IMPLIES.md` and their sections do not exist on `main`; the refusal is described in `doc/reference/operators/logical.md`, `doc/reference/operators/README.md`, `doc/reference/errors/README.md` and `doc/courses/foundation/module-3-control-flow.md`.

## Sites on `main` that the refusal found

Measured 2026-11-21 by running the branch's `l4 check` over all 702 tracked `.l4` files; each is bracketed in a commit of its own family, before the commit that adds the check.

- `jl4-core/libraries/excel-date.l4`, `ExcelWorkday` and `ExcelNetworkDays`: `isWorkday MEANS NOT weekend AND NOT holiday` meant `NOT (weekend AND NOT holiday)`, so both functions counted a weekday holiday as a working day.
  Two value goldens move, January 2024 with one holiday: 23 working days before, 22 after (`ok/tests/excel-date-tests.golden`, `ok/excel-date/tests/workdays.golden`).
  `unstable` made the same fix in cf58afa29.
  Every file that imports the library was flagged through it until it was fixed.
- The XOR snippet `OR NOT x AND y`, which meant `OR NOT (x AND y)`: `ok/xor.l4`, `ok/ref.l4`, `lsp/semantic-tokens/annotations.l4`, `tests-cli/fixtures/clean.l4`, and the copy in `jl4/README.md`.
- `jl4/experiments/query-planner-tests/03-dont-care-branch.l4` and `06-reactive-relevance.l4`: `(NOT c AND alt)` meant `NOT (c AND alt)`; their header comments state the narrow formula.
- `doc/reference/operators/implies-example.l4`: `NOT a OR b`, offered as equivalent to `a IMPLIES b`, meant `NOT (a OR b)`.

Markdown that no check reads carried the same spellings and is corrected with them: `doc/concepts/legal-modeling/default-reasoning.md`, `doc/tutorials/getting-started/encoding-legislation.md`, the `IMPLIES` sentence in `logical.md`, `specs/done/BOOLEAN-MINIMIZATION-SPEC.md`, and module 3 of the foundation course, which said `NOT` binds tightest and that `NOT a AND b` means `(NOT a) AND b`.

## Diagnostics

| Code                                     | Severity | When                                                                  |
| ---------------------------------------- | -------- | --------------------------------------------------------------------- |
| `check/negation-reaches-over-connective` | Error    | A written `NOT` whose operand has a bare connective on the NOT's line |

## Tests and fixtures that pin it

- `jl4/examples/not-ok/tc/not-same-line-connective.l4` (six sites) and `not-bracketed-operand.l4` (three) pin the refused spellings and the message.
- `jl4/examples/ok/not-reach-accepted.l4` evaluates every accepted spelling, with `unstable`'s six-row table of readings as assertions.
- `jl4-service/test/QueryPlanSpec.hs` spells its narrow case `(NOT a) AND b`.
- No test on `main` pins the printer change: `main`'s `jl4/tests/Main.hs` has no `prettyLayout` round-trip block, which is what pins it on `unstable`.
  What needs it on `main` is `l4 batch`, which re-prints a module and checks the printed text, so a printed `NOT a AND b` would now be refused.
  Probed by hand on 2026-11-21 with the branch's `l4`: `l4 batch` and `l4 run` give the same answer for `NOT (p AND q)`, `(NOT p) IMPLIES q`, `NOT (p IMPLIES q)`, `(NOT p) OR q`, `r AND NOT (p OR q)` and the two-line `NOT p` / `AND q`, each with `"status":"success"`.

## Limits

- The printer change has no automated guard on `main` (see above), and the evaluation differential that `unstable` runs by hand after a `Print.hs` change (`JL4_EVALDIFF`) does not exist on `main`, so it was not run.
- Files that no test type-checks are not covered: on `main` nothing reads `jl4/experiments/` or other unchecked `.l4` files for this trap, because the text linter was not ported.
- A file with a parse error is never checked, so its sites are not reported until it parses.
- The refusal is structural: it does not ask whether the two readings differ for the inputs a file actually uses.
