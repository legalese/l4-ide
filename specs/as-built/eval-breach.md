# Breach semantics at deadlines and in `RAND`/`ROR` (as built)

As built on `main` by this PR, measured on `main` at `4c887e0db`.
Source spec: none.
Differences from the source spec: not applicable.
The work came from `unstable`; this page describes only what `main` has.

Source: PR #57 (`bbe9be7ed`).
On `unstable` later PRs went further: #411 gives breaches a `Blame` record that names every failure, and #412 adds `THE DEADLINE` and the other anchors.
None of that is part of this PR.

These differ from #57 by hand, all taken from #412 and its later repairs on `unstable`:

- The clock after a missed deadline starts at that deadline, not at the event that revealed it. #57 kept the revealing event; ruling R-Q7, with R-Q5, changed it (`specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md` §2.5 on `unstable`, ruled 2026-09-07). Carrying #57's rule alone turned a residual on `main` into a false `FULFILLED`: a payment on day 5000 discharged a grace period that closed on day 44.
- #57's at-most-once rule is gone. The event is handed on, layer by layer, and a chain whose deadlines stop advancing is refused after 1,000 hand-offs (the `Reoffered` mark and `maximumStalledReoffers` on `unstable`, without its log, its anchors or its `Blame`). With the new clock an event can properly pass several expired layers, and dropping it at the second gave false verdicts.
- The clock is floored at the failed rule's arming (spec row A2), so a computed negative `WITHIN` cannot count a cure from before the rule began. `unstable` also adds a note when the floor engages; there is no note here.
- A rule inside an expression prints on one line with `group` and `hang`, as `unstable` does, with every break an operand needs made hard, as `unstable` has them. It is also in brackets under `HENCE` and `LEST`, which goes beyond `unstable`'s hunk, assumed, not ruled.
- The docs are rewritten beyond #57's hunk, because `main`'s pages teach `main`'s behaviour.

## What it does

- A missed deadline no longer swallows the event that revealed it.
  The event is offered to the rule that follows, so a late payment that is the first thing recorded can discharge the `LEST` reparation it was written for, if it falls inside that reparation's window.
- The rule after a missed deadline counts from that deadline. With `MUST pay 1000 WITHIN 30 LEST (MUST pay 1100 WITHIN 14)`, the 14 days close on day 44, whenever the miss came to light.
- A lapsed `MAY` goes to its `LEST`, by default `FULFILLED`. `HENCE` is taken only when the permission is exercised.
- Two breached operands of `RAND` or `ROR`, of any kind, report one breach instead of a residual that prints `BREACH ... OR BREACH ...`.
- `l4 batch --json` labels the fields of a missed deadline by what they hold.
- `l4 batch`, which prints a module and parses it again, reads back most files with a `#TRACE`: see "Measured against `main`".

Three binaries, the unstable one being `unstable-20261104-68498bc`:

| Rule                                                                    | Trace                                              | `main`             | this PR      | `unstable`   |
| ----------------------------------------------------------------------- | -------------------------------------------------- | ------------------ | ------------ | ------------ |
| late fee, from `module-6-regulative.md`: 30 days, then 14               | pay at 5000, the first event                       | residual           | `BREACH`     | `BREACH`     |
|                                                                         | unrelated event at 31, pay at 5000                 | `BREACH`           | `BREACH`     | `BREACH`     |
|                                                                         | unrelated event at 4999, pay at 5000               | `FULFILLED`        | `BREACH`     | `BREACH`     |
|                                                                         | pay at 40, inside the grace period                 | residual           | `FULFILLED`  | `FULFILLED`  |
| three no-smoking windows, 0-5, 5-10, 10-15                              | smoke at 12, `WAITUNTIL` 20                        | residual           | breach at 12 | breach at 12 |
|                                                                         | `WAITUNTIL` 11, smoke at 12, `WAITUNTIL` 20        | breach at 12       | breach at 12 | breach at 12 |
| licence, from `module-a2-cross-cutting.md`, layers due at 335, 349, 409 | reinstate at 380, `WAITUNTIL` 500                  | residual           | `FULFILLED`  | `FULFILLED`  |
|                                                                         | `WAITUNTIL` 350, reinstate at 380, `WAITUNTIL` 500 | `BREACH` "revoked" | `FULFILLED`  | `FULFILLED`  |
| `WITHIN days - 30` at 20 days, then `MUST b WITHIN 3`                   | `b` at 1                                           | residual           | `FULFILLED`  | `FULFILLED`  |
| the same, then `SHANT b WITHIN 3`                                       | `b` at 1, then `a` at 2                            | residual           | breach at 1  | breach at 1  |

## Behaviour and rules (read in code, and pinned by `ok/deontic-breach-semantics.l4`)

- Expiry is strict: an event exactly at the deadline is in time (`jl4-core/src/L4/EvaluateLazy/Machine.hs:946`).
- On expiry, `reoffer` (`Machine.hs:989`) copies the event, marks the copy in `reofferedEvents`, puts it back on the event list and hands the list to the continuation, whose clock starts at the missed deadline, or at the rule's arming if that is later.
- A re-offered event is handed on to every layer it is past, until the first whose window is open. The mark holds the latest deadline it has revealed and how many hand-offs in a row failed to pass it; past `maximumStalledReoffers`, 1,000 (`Machine.hs:355`), the run stops with an error, which is what ends a rule that names itself with a window never open.
- Routing at expiry: `SHANT` to `HENCE`; `MAY` to `LEST`, default `FULFILLED` (`Machine.hs:1011`); `MUST` and `DO` to `LEST`, or a `DeadlineMissed` breach when there is none. All of them count from the missed deadline, including the `HENCE` of a kept `SHANT`.
- A violated `SHANT` with no `LEST` breaches with its deadline equal to the event's time, a sentinel that reaches the wire (`Machine.hs:1070`). Its `LEST` counts from that act.
- Both operands breached (`Machine.hs:1110`): a breach is dated at the event that revealed it, not at its deadline. If separate events revealed the two, `RAND` reports the earlier and `ROR` the later. If one event revealed both, the usual case, they tie, and a tie, or a pair with a `LEST BREACH` (`ExplicitBreach`, which records no time), reports the left operand for `RAND` and the right for `ROR`, whichever deadline came first.
- A rule inside an expression prints on one line, with a rule under its `HENCE` or `LEST` in brackets (`jl4-core/src/L4/Print.hs:544`), and `#TRACE` prints with `AT`, `WITH` and one event to a line (`Print.hs:410`). `WITH`, `WHERE`, `BRANCH`, `LET` and an event use hard breaks, so such an operand keeps its lines, indented under `PARTY`. A rule's own value, as a residual, keeps its clause lines.
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

**Against `unstable`, generated.** 590,744 comparisons of a trace on a rule, on this PR's binary and the `unstable` one: three levels exhaustively over the modals, `HENCE` and `LEST`, four levels and windows of 0 and -1 sampled, rules with both branches filled, and `RAND`/`ROR` over two levels. Traces are events on and off the recomputed deadlines, with and without a later clock event, and clock events alone.
583,411 are identical, ignoring brackets and line breaks, and ignoring a phrase `unstable` adds when the floor engages (`but was only entered at`).
7,024 are `RAND`/`ROR` breaches where `unstable` names every failure, and this PR's one is among them.
309 differ only in printing.
None is unexplained.
Generators: `mgen3.py` and `mcmp3.py`, kept with the review, not in this tree.
The differences kept are those two: one breach against every failure named, and no note or phrase when the floor engages.

`l4 batch` against `l4 run`: each file with a `#TRACE` in that corpus, with an `@export` added.
241 files give `#TRACE` results under `l4 run`; `main` reads back 0 of the 24 in this repository's `ok/`, `legal/` and `doc/` (measured), and 230 of the 241 read back now, with 1,290 `#TRACE` results and no verdict different (fulfilled, breached or open).
Of the 11 that do not, 3 are in this repository: `legal/promissory-note.l4` and `doc/courses/advanced/module-a3-contracts-examples.l4` (`check/wrong-argument-count`), and `doc/courses/foundation/module-7-examples.l4` (`check/unknown-identifier`).
`CLAUDE.md` section 3.2.1's differential needs a harness `main` does not have, so this comparison stands in for it.

## Tests that pin it

- `jl4/examples/ok/deontic-breach-semantics.l4` and its four goldens. Each `#TRACE` says in a comment which rule it pins: the clock after a missed deadline with the late-fee traces, the `HENCE` of a kept `SHANT`, `MAY ... LEST BREACH`, two breaches at separate events and at one, mixed `RAND` and `ROR` in both orders, an event handed on through several layers to a third, a middle `WITHIN 0`, three prohibitions, and the floor.
- `jl4/examples/ok/deontic-stalled-chain.l4`: a rule naming itself with `WITHIN 0` and with a negative `WITHIN`, refused, and with a window of its own, which ends.
- `legal/promissory-note.l4` (a comment re-synced to the new output) and two of its goldens, `ok/contracts.golden` and `legal/ceo-performance-award.golden`.
- `jl4/tests-cli/Main.hs` under "l4 batch": "serializes a #TRACE breach with correctly-labeled fields", with `fixtures/breach-trace.l4` and `fixtures/breach-inputs.json`, "agrees with l4 run on every #TRACE of the deontic breach fixture", which also pins the printing of `#TRACE` with several events and of a rule under `HENCE` and `LEST`, and "reads back a rule whose clauses hold WITH, WHERE, BRANCH and LET", with `fixtures/batch-rule-operands.l4`.

## Limits and known defects

- A both-breached `ROR` names only one party until #411 reaches `main`. `qda-cases-buyer.l4` [81], `BREACH BY the transferee ... OR BREACH BY another party to the transaction`, now says only `another party to the transaction`.
- A branching rule can cost far more, here and on `unstable` alike, because a late event now walks every layer it is past. These are the rule's own branches, at events 10 apart, with `WITHIN 100` both are as fast as `main`:

  | Rule                                                        | `main` | this PR         | `unstable`      |
  | ----------------------------------------------------------- | ------ | --------------- | --------------- |
  | `WITHIN 1 HENCE (x RAND x) LEST x`, 14 events               | 0.02 s | 1.3 s           | 18 s            |
  | the same, 18 events                                         | 0.04 s | 21 s, 18 MB     | past 60 s       |
  | `WITHIN 7 HENCE (x RAND x) LEST x`, 14 events               | 0.03 s | 1.3 s           | 18 s            |
  | the same, 18 events                                         | 0.05 s | 20 s, 18 MB     | past 60 s       |
  | `WITHIN 1 HENCE (x RAND x) LEST (x RAND x)`, 2 events       | 0.02 s | past 60 s       | past 60 s       |
  | `MAY ... WITHIN 1 HENCE (x ROR x) LEST (x ROR x)`, 4 events | 0.02 s | past 60 s       | past 60 s       |
  | `WITHIN 0 - 1 LEST (x RAND x)`, 9 events                    | 0.07 s | refused at once | refused at once |

  A `LEST (x RAND x)` doubles at each layer the event walks, so its cost grows with how many windows fit between two events, not only with how many events there are.

- A rule that names itself with a window never open used to leave a residual on `main`; it is now an error.
- `jl4-mlir`'s runtime routes neither way. Run directly through `runDeontic` in `jl4-mlir/runtime/jl4-runtime.mjs` (`:610-617`, `:646-649`), the compiled backend not being run: a lapsed `MAY` with no `LEST`, and a kept `SHANT`, each answer `BREACH`, where the core answers `FULFILLED`; a `LEST` counts from the rule's own start, so `MUST ... WITHIN 30 LEST (MUST ... WITHIN 100)` is due at 100 there and 130 here. All of this is the same on `main`, except that a lapsed `MAY`'s `LEST` is new to the core.
- `L4.StateGraph` draws no timeout edge for a `MAY` with no `LEST` (`jl4-core/src/L4/StateGraph.hs:365`), though the evaluator now has that path, ending in `FULFILLED`.
- `-- expect:` comments in commons now describe `main`'s old output, and 4 of its `#ASSERT`s now fail. See the stale list in this PR's description; commons pins a released `l4`, so nothing there moves until a release carries this.
- For a `WAITUNTIL`, `l4 batch --json` gives `eventParty` as `NEVERMATCHESPARTY` and `eventAction` as `NEVERMATCHESACT`. `obligationAction` is the action as written: `MUST pay n`, with the input's name and not its value. `doc/tutorials/getting-started/l4-cli.md` says so.
