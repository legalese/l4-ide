# Breach semantics at deadlines and in `RAND`/`ROR` (as built)

As built on `main` by this PR, measured on `main` at `4c887e0db`.
Source spec: none.
Differences from the source spec: not applicable.
The work came from `unstable`; this page describes only what `main` has.

Source: PR #57 (`bbe9be7ed`).
On `unstable` later PRs went further: #411 gives breaches a `Blame` record that names every failure, and #412 replaces the at-most-once rule below with a hand-on rule, and adds `THE DEADLINE` and the other anchors.
None of that is part of this PR.

Three things here differ from #57 by hand:

- The clock after a missed deadline starts at that deadline, not at the event that revealed it. #57 kept the revealing event; ruling R-Q7, with R-Q5, changed it (`specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md` §2.5 on `unstable`, ruled 2026-09-07, built by #412). Only that one clock is carried from #412. Carrying #57's rule alone turned a residual on `main` into a false `FULFILLED`: a payment on day 5000 discharged a grace period that closed on day 44.
- A rule inside an expression prints with `group` and `hang`, as `unstable` does, and in brackets under `HENCE` and `LEST`. #57 only fixed `#TRACE`'s `AT` and `WITH`, which left `l4 batch` unable to read back most files with a `#TRACE`.
- The docs are rewritten beyond #57's hunk, because `main`'s pages teach `main`'s behaviour.

## What it does

- A missed deadline no longer swallows the event that revealed it.
  The event is offered to the rule that follows, so a late payment that is the first thing recorded can discharge the `LEST` reparation it was written for, if it falls inside that reparation's window.
- The rule after a missed deadline counts from that deadline. With `MUST pay 1000 WITHIN 30 LEST (MUST pay 1100 WITHIN 14)`, the 14 days close on day 44, whenever the miss came to light.
- A lapsed `MAY` goes to its `LEST`, by default `FULFILLED`. `HENCE` is taken only when the permission is exercised.
- Two breached operands of `RAND` or `ROR`, of any kind, report one breach instead of a residual that prints `BREACH ... OR BREACH ...`.
- `l4 batch --json` labels the fields of a missed deadline by what they hold.
- `l4 batch`, which prints a module and parses it again, reads back most files with a `#TRACE`: see "Measured against `main`".

The late-fee rule from `doc/courses/foundation/module-6-regulative.md`, three binaries, the unstable one being `unstable-20261104-68498bc`. The last row of the column for #57 alone is by reading, not run.

| Trace                                     | `main`                       | this PR before the clock edit | this PR     | `unstable`  |
| ----------------------------------------- | ---------------------------- | ----------------------------- | ----------- | ----------- |
| pay 1100 at 5000, the first event         | residual `MUST pay 1100 ...` | `FULFILLED`                   | `BREACH`    | `BREACH`    |
| unrelated event at 31, then pay at 5000   | `BREACH`                     | `BREACH`                      | `BREACH`    | `BREACH`    |
| unrelated event at 4999, then pay at 5000 | `FULFILLED`                  | `FULFILLED`                   | `BREACH`    | `BREACH`    |
| pay 1100 at 40, inside the grace period   | residual `MUST pay 1100 ...` | `FULFILLED`                   | `FULFILLED` | `FULFILLED` |

## Behaviour and rules (read in code, and pinned by `ok/deontic-breach-semantics.l4`)

- Expiry is strict: an event exactly at the deadline is in time (`jl4-core/src/L4/EvaluateLazy/Machine.hs:918`).
- On expiry, `reoffer` (`Machine.hs:952`) copies the event, marks the copy in `reofferedEvents`, puts it back on the event list and hands the list to the continuation, whose clock starts at the missed deadline.
- An event is re-offered at most once. A marked event that reveals a second expiry is dropped, which is what ends a rule whose `LEST` names itself with a non-positive `WITHIN`.
- Routing at expiry: `SHANT` to `HENCE`; `MAY` to `LEST`, default `FULFILLED` (`Machine.hs:973`); `MUST` and `DO` to `LEST`, or a `DeadlineMissed` breach when there is none. All of them count from the missed deadline, including the `HENCE` of a kept `SHANT`.
- A violated `SHANT` with no `LEST` breaches with its deadline equal to the event's time, a sentinel that reaches the wire (`Machine.hs:1032`). Its `LEST` counts from that act.
- Both operands breached (`Machine.hs:1072`): a breach is dated at the event that revealed it, not at its deadline. If separate events revealed the two, `RAND` reports the earlier and `ROR` the later. If one event revealed both, the usual case, they tie, and a tie, or a pair with a `LEST BREACH` (`ExplicitBreach`, which records no time), reports the left operand for `RAND` and the right for `ROR`, whichever deadline came first.
- A rule inside an expression prints on one line, with a rule under its `HENCE` or `LEST` in brackets (`jl4-core/src/L4/Print.hs:542`), and `#TRACE` prints with `AT`, `WITH` and one event to a line (`Print.hs:410`). A rule's own value, as a residual, keeps its clause lines.
- The `ToJSON` instances of `NF`, `Value` and `ReasonForBreach` moved to the orphan module `L4.Evaluate.ValueLazyJSON`, because the breach renders its action with `prettyLayout` and `L4.Print` imports `L4.Evaluate.ValueLazy`.
- A `deadline_missed` object carries `eventParty`, `eventAction`, `timestamp`, `obligatedParty`, `obligationAction` and `deadline`. The old labels `deadline`, `now`, `elapsed`, `action` and `limit` named the wrong slots, and `action` was a derived `Show` of the AST.

## Measured against `main`

`l4 run` with `main`'s binary and this PR's over 3,453 files with a directive (`ok/`, `legal/`, `doc/`, and `legalese/commons` at `d468311a6`), each under `JL4_FIXED_NOW=2025-01-31T15:45:30Z` with `JL4_LIBRARY_PATH` unset.
3,246 ran on both sides; the other 207 stop at a parse, check or import error before evaluating on both sides, and so say nothing.
26 files changed, in 39 results, of five kinds:

| Kind                                                                                | Results | Example                                                                                       |
| ----------------------------------------------------------------------------------- | ------- | --------------------------------------------------------------------------------------------- |
| Printing only: a rule under `HENCE` or `LEST` on one line, bracketed                | 13      | `` LEST BREACH BY `the employer` `` becomes ``LEST (BREACH BY `the employer`)``               |
| One breach where two printed                                                        | 10      | `BREACH BY the transferee ... OR BREACH BY another party ...` becomes the right operand alone |
| The re-offer reached a residual, whose `WITHIN` now counts from the missed deadline | 8       | `` WITHIN `the days to pay` `` becomes `WITHIN 60`, one less than its 61                      |
| The re-offered event, or the new clock, moves the verdict                           | 4       | `contracts.l4`: `FULFILLED` becomes a breach at 9 of the fine due at 8                        |
| An `#ASSERT ... EQUALS FULFILLED` now meets a breach, so it cannot be evaluated     | 4       | commons `rtw-cases-core.l4:677`, a payment at 18 against a deadline of 17                     |

The exit code moved from 0 to 1 in the 3 files with that last kind (`rtw-cases-core.l4`, `qlt-cases-owner.l4`, `voca-cases-applicant.l4`), all in commons, whose encodings count from the revealing event; they exit 1 on `unstable` too.
The other verdicts are `gva-cases-core.l4` [195] and `probate-administration-act.l4` [433], a waiting `MAY` to `FULFILLED`, and `module-a2-cross-cutting-examples.l4` Test 4, a waiting `MAY` to the `BREACH` under its `HENCE`.
No changed result comes from a lapsed `MAY` taking `LEST` instead of `HENCE`, so `deontic-breach-semantics.l4` is the only evidence for that routing.

The same 39 results on the `unstable` binary, with `WAITUNTIL` respelled for it: 22 are equal, ignoring brackets and line breaks.
10 are the one-breach kind, where `unstable` names every failure (#411); it raises an internal error on the rule's name in 2 of them.
4 are the `#ASSERT` kind, with the same outcome but different addresses in the message.
3 could not be compared, because `unstable` raises that internal error (2) or refuses the file (1).

Differences this PR keeps from `unstable`, each from `deontic-breach-semantics.l4`:

- Two breaches: one is reported here, and every failure is named there.
- `three layers` (delivery at 7, layers due at 2, 5 and 105): the event has used its one re-offer, so layer 3 stays open here; there it is `FULFILLED`.
- `nested peel`: the same verdict and deadline, dated at 30 here and at 20 there.
- `recursive lest` with a `WITHIN` below zero: a residual here; there, a refusal after 1,000 hand-offs.

`l4 batch` against `l4 run`: each file with a `#TRACE` in that corpus, with an `@export` added.
241 files give `#TRACE` results under `l4 run`; `main` reads back 0 of the 24 in this repository's `ok/`, `legal/` and `doc/` (measured), and 228 of the 241 read back now, with 1,273 `#TRACE` results and no verdict different (fulfilled, breached or open).
Of the 13 that do not, 3 are in this repository: `legal/promissory-note.l4` (`parse/unexpected-IS`), `doc/courses/advanced/module-a3-contracts-examples.l4` (`check/wrong-argument-count`) and `doc/courses/foundation/module-7-examples.l4` (`parse/indentation`).
`CLAUDE.md` section 3.2.1's differential needs a harness `main` does not have, so this comparison stands in for it.

## Tests that pin it

- `jl4/examples/ok/deontic-breach-semantics.l4` and its four goldens. Each `#TRACE` says in a comment which rule it pins: the clock after a missed deadline with the late-fee traces, the `HENCE` of a kept `SHANT`, `MAY ... LEST BREACH`, two breaches at separate events and at one, mixed `RAND` and `ROR` in both orders, and at-most-once with several events.
- `legal/promissory-note.l4` (a comment re-synced to the new output) and two of its goldens, `ok/contracts.golden` and `legal/ceo-performance-award.golden`.
- `jl4/tests-cli/Main.hs` under "l4 batch": "serializes a #TRACE breach with correctly-labeled fields", with `fixtures/breach-trace.l4` and `fixtures/breach-inputs.json`, and "agrees with l4 run on every #TRACE of the deontic breach fixture", which also pins the printing of `#TRACE` with several events and of a rule under `HENCE` and `LEST`.

## Limits and known defects

- A both-breached `ROR` names only one party until #411 reaches `main`. `qda-cases-buyer.l4` [81], `BREACH BY the transferee ... OR BREACH BY another party to the transaction`, now says only `another party to the transaction`.
- An event reaches at most two rules, so a timely act can be missed by a third: `three layers` above stays open though the delivery at 7 was inside layer 3's window. A second event reaches it.
- A branching rule costs more: an event can now advance two levels, not one. `x MEANS MUST deliver WITHIN 1 HENCE (x RAND x) LEST (x RAND x)`, with 8 events 10 apart, goes from 0.05 s and 19 KB on `main` to 5.4 s and 4.9 MB; at 9 events, to 23 s and 20 MB; at 10, past 60 s. That is 2^n becoming 4^n. `MAY ... (x ROR x)` (9 events: 22 s) and `WITHIN 0 - 1 LEST (x RAND x)` (9 events: 24 s) grow the same way. The branching is the rule's own. `HENCE (x RAND x) LEST x` stays linear, 0.5 s at 20 events on both binaries, because the second expiry drops the event before it reaches that `HENCE`; with `WITHIN 100` both binaries take the same time. The `unstable` binary is slower: past 60 s at 4 events on the first.
- `jl4-mlir`'s runtime routes neither way. Run directly through `runDeontic` in `jl4-mlir/runtime/jl4-runtime.mjs` (`:610-617`, `:646-649`), the compiled backend not being run: a lapsed `MAY` with no `LEST`, and a kept `SHANT`, each answer `BREACH`, where the core answers `FULFILLED`; a `LEST` counts from the rule's own start, so `MUST ... WITHIN 30 LEST (MUST ... WITHIN 100)` is due at 100 there and 130 here. All of this is the same on `main`, except that a lapsed `MAY`'s `LEST` is new to the core.
- `L4.StateGraph` draws no timeout edge for a `MAY` with no `LEST` (`jl4-core/src/L4/StateGraph.hs:365`), though the evaluator now has that path, ending in `FULFILLED`.
- `-- expect:` comments in commons now describe `main`'s old output, and 4 of its `#ASSERT`s now fail. See the stale list in this PR's description; commons pins a released `l4`, so nothing there moves until a release carries this.
- For a `WAITUNTIL`, `l4 batch --json` gives `eventParty` as `NEVERMATCHESPARTY` and `eventAction` as `NEVERMATCHESACT`. `obligationAction` is the action as written: `MUST pay n`, with the input's name and not its value. `doc/tutorials/getting-started/l4-cli.md` says so.
