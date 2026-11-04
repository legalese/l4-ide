# Breach semantics at deadlines and in `RAND`/`ROR` (as built)

As built on `main` by this PR, measured on `main` at `4c887e0db`.
Source spec: none.
Differences from the source spec: not applicable.
The work came from `unstable`; this page describes only what `main` has.

Source: PR #57 (`bbe9be7ed`).
On `unstable` later PRs went further: #411 gives breaches a `Blame` record that names every failure, and #412 starts a `LEST` clock at the missed deadline and replaces the at-most-once rule below.
Neither is part of this PR.

## What it does

- A missed deadline no longer swallows the event that revealed it.
  The event is offered to the rule that follows, so a late payment that is the first thing recorded can discharge the `LEST` reparation it was written for.
- A lapsed `MAY` goes to its `LEST`, by default `FULFILLED`. `HENCE` is taken only when the permission is exercised.
- Two breached operands of `RAND` or `ROR`, of any kind, report one breach instead of a residual that prints `BREACH ... OR BREACH ...`.
- `l4 batch --json` labels the fields of a missed deadline by what they hold.
- `#TRACE` prints with its `AT` and `WITH`, one event to a line, so `l4 batch`, which prints a module and parses it again, accepts a file that has one.

## Behaviour and rules (read in code, and pinned by `ok/deontic-breach-semantics.l4`)

- Expiry is strict: an event exactly at the deadline is in time (`jl4-core/src/L4/EvaluateLazy/Machine.hs:918`).
- On expiry, `reoffer` (`Machine.hs:948`) copies the event, marks the copy in `reofferedEvents`, puts it back on the event list and hands the list to the continuation, whose clock starts at the event's time.
- An event is re-offered at most once. A marked event that reveals a second expiry is consumed, which is what ends a rule whose `LEST` names itself with a non-positive `WITHIN`.
- Routing at expiry: `SHANT` to `HENCE`; `MAY` to `LEST`, default `FULFILLED` (`Machine.hs:968`); `MUST` and `DO` to `LEST`, or a `DeadlineMissed` breach when there is none.
- A violated `SHANT` with no `LEST` breaches with its deadline equal to the event's time, a sentinel that reaches the wire (`Machine.hs:1027`).
- Both operands breached (`Machine.hs:1067`): the earlier breach for `RAND`, the later for `ROR`. A tie, or a pair with a `LEST BREACH` (`ExplicitBreach`, which records no time), reports the left operand for `RAND` and the right for `ROR`.
- The `ToJSON` instances of `NF`, `Value` and `ReasonForBreach` moved to the orphan module `L4.Evaluate.ValueLazyJSON`, because the breach renders its action with `prettyLayout` and `L4.Print` imports `L4.Evaluate.ValueLazy`.
- A `deadline_missed` object carries `eventParty`, `eventAction`, `timestamp`, `obligatedParty`, `obligationAction` and `deadline`. The old labels `deadline`, `now`, `elapsed`, `action` and `limit` named the wrong slots, and `action` was a derived `Show` of the AST.

## Measured against `main`

`l4 run` with `main`'s binary and this PR's over 3,453 files with a directive (`ok/`, `legal/`, `doc/`, and `legalese/commons` at `d468311a6`), each under `JL4_FIXED_NOW=2025-01-31T15:45:30Z` with `JL4_LIBRARY_PATH` unset.
3,246 ran on both sides; the other 207 stop at a parse, check or import error before evaluating on both sides, and so say nothing.
No exit code changed.
16 files changed, in 20 results, of three kinds:

| Kind                                                                         | Results | Example                                                                                       |
| ---------------------------------------------------------------------------- | ------- | --------------------------------------------------------------------------------------------- |
| One breach where two printed                                                 | 10      | `BREACH BY the transferee ... OR BREACH BY another party ...` becomes the right operand alone |
| The re-offer reached a residual, so its `PARTY` and `WITHIN` print evaluated | 7       | `` WITHIN `the days to pay` `` becomes `WITHIN 61`; the duty is the same                      |
| The re-offered event performed the next rule: the verdict moves              | 3       | a `MAY` left waiting becomes `FULFILLED`, or the `HENCE` it leads to                          |

No changed result comes from a lapsed `MAY` taking `LEST` instead of `HENCE`.
The differential found no such result, so `deontic-breach-semantics.l4` is the only evidence for that routing.

## Tests that pin it

- `jl4/examples/ok/deontic-breach-semantics.l4` and its four goldens. Each `#TRACE` says in a comment which rule it pins.
- `legal/promissory-note.l4` (a comment re-synced to the new output) and two of its goldens.
- `jl4/tests-cli/Main.hs` ("serializes a #TRACE breach with correctly-labeled fields") with `fixtures/breach-trace.l4` and `fixtures/breach-inputs.json`.

## Limits and known defects

- `RAND` and `ROR` report one breach, so the other party to a both-breached `ROR` is no longer named.
- `ExplicitBreach` carries no time, so its order against another breach is never consulted.
- By reading, not run: surfaces outside the core evaluator do not follow this PR. `jl4-mlir/runtime/jl4-runtime.mjs:610-617` sends a past-deadline event to `lest || BREACH` for every modal, so a lapsed `MAY` with no `LEST` breaches there and is `FULFILLED` here, and an expired `SHANT` takes `LEST` there and `HENCE` here. It also leaves the event on the list without moving the next rule's clock to it.
- `L4.StateGraph` draws no timeout edge for a `MAY` with no `LEST` (`jl4-core/src/L4/StateGraph.hs:365`), though the evaluator now has that path, ending in `FULFILLED`.
