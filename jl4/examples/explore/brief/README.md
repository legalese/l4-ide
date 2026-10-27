# The dinner race: fixtures for the regulative lowering

> **D1 and D2 are wrong on purpose.** > `d1-naive.l4` and `d2-reread.l4` are designs that let two dinners be bought, and the point of them is that a checker finds that.
> Do not fix them.
> If a tool says either one satisfies P1, suspect the tool or its encoding before you believe it.

Alice and Bob each mean to buy dinner tonight, and neither wants to buy it if the other already has.
Each checks whether dinner has been bought, finds it has not, and buys; if their checks and purchases interleave, two dinners are bought.
That is a classic race condition, and these files are how L4 states it, gets it wrong twice, and gets it right.
They are the fixtures of [REGULATIVE-LOWERING-SPEC.md](../../../../specs/proposals/REGULATIVE-LOWERING-SPEC.md) §7, work package WP0: the test material for an explorer, `l4 explore` (WP1, built 2026-10-26), that turns an L4 contract into an explicit transition system.

The model checks one side, Alice's.
Bob's purchase is the environment's act, recorded by the dinner ledger, and the message "I bought it" from Bob reaches Alice some time after it.
Bob's side is the same model with the names swapped.

## The files

| file                   | what it is                                                                        | expected                                                       |
| ---------------------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `d1-naive.l4`          | D1: Alice buys on what her check told her                                         | P1 violated by check, Bob's purchase, buy; 12 states, 21 steps |
| `d2-reread.l4`         | D2: Alice reads the ledger again, then buys as a second step                      | P1 violated by re-read, Bob's purchase, buy; 15, 30            |
| `d3-atomic.l4`         | D3: the ledger checks and accepts the purchase in one step                        | P1, P2, P4 hold; P3 reachable; 10, 21                          |
| `properties.l4`        | the ledger types every fixture uses, and P1 to P6 as boolean decisions over them  | its 14 `#ASSERT`s hold                                         |
| `mutants/d3-cancel.l4` | D3 plus an act that cancels a bought dinner                                       | P4 fails, and only P4                                          |
| `mutants/d3-double.l4` | D3 whose ledger records an accepted purchase twice                                | P2 fails, and only P2                                          |
| `refused-number.l4`    | D3 whose record of Bob's purchase carries its time as a `NUMBER`                  | an explorer refuses it (spec §4.2); `l4 run` runs it           |
| `reference/*.aut`      | the probes' hand models as labelled transition systems, relabelled to these names | the oracle for bisimulation; see `reference/PROVENANCE.md`     |

Every `.l4` file here runs with `l4 run <file>` on the installed `l4` of 2026-10-21, and exits 0.
`jl4/examples/explore/` is in no corpus golden glob, so no `.l4` here has the corpus's four goldens; the explorer's own goldens over these files are in `../expected/`, written by `jl4/tests/LtsExplore.hs`.

## How the brief becomes L4

The model is the one every verification probe was given: six state variables, a handful of transitions with a guard and an effect each, untimed, any enabled transition may fire next.
The fixtures encode it transition for transition.

**One chain, one acting party.**
Each fixture is one permission, `PARTY World MAY act`, that recurs on itself, and each act names its actor (`Alice buys dinner`, `ledger records Bob's purchase`).
This is option C of the spec (§4.3), ruled R-L2 on 2026-10-25.
It is sound only for a chain that is a `MAY` at every point, which these are: while a `MUST` or `SHANT` is pending in such a chain, the other parties' events are dropped, silently.

**A guard is a `PROVIDED`, an effect is the `CONSIDER` under `HENCE`.**
An act whose guard is false is passed over: the event does not count and nothing changes.
An act whose guard is true fires, and its branch writes the ledgers and returns to the evening.
A fired act can change nothing, which is how the brief's pauses and terminal self-loop appear: `Alice is done` once she has bought or stopped, and an unanswered request in D2 and D3.

**The six variables are ledger cells.**

| brief variable | ledger cell                                                           | how it is read                  | initially                |
| -------------- | --------------------------------------------------------------------- | ------------------------------- | ------------------------ |
| `ledger`       | official `dinner status record`: `opened`, then perhaps `taken`       | `RECALL ALL OFFICIAL's`         | `opened`, at the opening |
| `dinners`      | official `dinners bought`, less official `dinners cancelled`          | `RECALL ALL OFFICIAL's`         | none                     |
| `okAtBuy`      | official `open at acceptance`, one per purchase as it takes effect    | `RECALL ALL OFFICIAL's`         | none (vacuously true)    |
| `belief`       | Alice's `belief`: `opened` or `taken`                                 | `RECALL Alice's` (latest entry) | nothing: Unknown         |
| `alice`        | Alice's `plan`: `planning`, `checked`, `reading`, `bought`, `stopped` | `RECALL Alice's` (latest entry) | nothing: planning        |
| `message`      | the `message` of Messages: `in transit`, `delivered`                  | `RECALL Messages's` (latest)    | nothing: not sent        |

The dinner ledger's records are `COMMIT`s to the official record, because they bind every party; what Alice knows and where she is are `RECORD`s in her own ledger.

**The acts, and the reference labels they stand for.**

| act in the fixture                                  | D1            | D2                       | D3                        |
| --------------------------------------------------- | ------------- | ------------------------ | ------------------------- |
| `ledger records Bob's purchase`                     | `BobBuys`     | `BobBuys`                | `BobBuys`                 |
| `Messages delivers the message`                     | `Deliver`     | `Deliver`                | `Deliver`                 |
| `Alice checks whether dinner is bought`             | `CheckBought` | `CheckBought`            | `CheckBought`             |
| `Alice is done`                                     | `Done`        | `Done`                   | `Done`                    |
| `Alice buys dinner`                                 | `Buy`         | `Send`                   |                           |
| `Alice gives up`                                    | `Abandon`     | `AbandonR`               |                           |
| `Alice reads the ledger again` `TRUE` / `FALSE`     |               | `ReadAgain` / `NoAnswer` |                           |
| `Alice buys dinner` `TRUE` / `FALSE`                |               |                          | `BuyChecked` / `NoAnswer` |
| `Alice cancels the dinner` (`mutants/d3-cancel.l4`) |               |                          | `Cancel`                  |

The `BOOLEAN` payload `ledger answered` is the brief's split between an answered and an unanswered request: `FALSE` is `NoAnswer`, a pause that changes nothing.
Each reference label is written `step(<label>)` in the `.aut` files.

**Time.**
The brief is untimed, and so are the guards: no act carries a time, and nothing reads one.
Times appear only in the traces, as seconds after midnight: the arrangement opens at 18:00 (64800), Alice checks at 18:05 (65100), Bob's purchase is recorded at 18:06 (65160), Alice buys at 18:07 (65220), the message arrives at 18:08 (65280).
The evening closes at 21:00 (75600) with an anchored deadline, `WITHIN 0 OF closing`, so ``(`WAIT UNTIL` 75601)`` ends a trace.

## Reading a trace

Read each trace's ledgers, not its `FULFILLED` line.
Every trace ends `FULFILLED`, wrong purchase or not, because the evening is a permission and a permission that lapses at closing is fulfilled.
The official record lists the dinner ledger's `COMMIT`s in the order they happened, so a purchase that took effect after Bob's shows as `taken` before `dinners bought`, followed by `open at acceptance IS FALSE`.
The first trace of `d1-naive.l4` is the three-step counterexample, and `l4 run` prints:

```text
Official record:
  COMMIT `dinner status record` IS opened
  COMMIT `dinner status record` IS taken
  COMMIT `dinners bought` IS `dinner for two`
  COMMIT `open at acceptance` IS FALSE
```

The `[party=…, at=…]` stamp after each line is the wall-clock time of the run, not the time of the event.

## What was checked, and how

On 2026-10-26, with the installed `l4` of 2026-10-21, a throwaway explorer in the session's scratch directory, not in this tree, explored each fixture breadth first through `l4 run`.
From every state it reached, it appended each act of the design to a `#TRACE`, ran the evaluator, and read back whether the act fired or was passed over and what the ledgers then held.
It knew nothing of the brief: the graph it found is the evaluator's.

| fixture                | states | transitions | acts passed over | P1                                              | P2                                | P3        | P4                   |
| ---------------------- | ------ | ----------- | ---------------- | ----------------------------------------------- | --------------------------------- | --------- | -------------------- |
| `d1-naive.l4`          | 12     | 21          | 51               | violated: CheckBought, BobBuys, Buy             | holds                             | reachable | holds                |
| `d2-reread.l4`         | 15     | 30          | 90               | violated: CheckBought, ReadAgain, BobBuys, Send | holds                             | reachable | holds                |
| `d3-atomic.l4`         | 10     | 21          | 39               | holds                                           | holds                             | reachable | holds                |
| `mutants/d3-cancel.l4` | 13     | 29          | 62               | holds                                           | holds                             | reachable | violated by `Cancel` |
| `mutants/d3-double.l4` | 10     | 21          | 39               | holds                                           | violated: CheckBought, BuyChecked | reachable | holds                |

Each graph of `d1`, `d2` and `d3`, written with the labels above, is strongly and branching bisimilar to its reference (`ltscompare -ebisim` and `-ebranching-bisim` print `true`; D1's graph against D2's reference prints `false`).
The properties were evaluated by `#EVAL` of the decisions in `properties.l4` on every state's ledgers.
P5 and P6 are liveness properties, which need a fairness assumption and a model checker (spec §5.3), and that explorer did not check them; TLC and NuSMV did, on the models `l4 explore --emit` writes (below).
That throwaway explorer was not a test in the tree.
`l4 explore` (WP1) now reproduces its state, transition and pass-over counts for all five rows, and `jl4/tests/LtsExplore.hs` asserts them as numbers; the bisimulation against the references is run by the harness in [`../harness/`](../harness/README.md) (WP4).
The run that reproduces the table bounds the clock at closing and keeps the cells `properties.l4` reads, which no `RECALL` in a contract names (`--keep` for a cell a property reads whole, `--keep-latest` for one it reads as a `MAYBE`):

```sh
l4 explore d1-naive.l4 --until 75600 \
  --keep 'open at acceptance' --keep 'dinners bought' --keep 'dinners cancelled' \
  --keep 'dinner status record' --keep-latest belief --keep-latest plan
```

Without the kept cells `d1-naive.l4` gives 10 states and 18 transitions, and its coverage line names `dinners bought` and `open at acceptance` as write-only cells it dropped: the bad purchase of Sequence A and the good one of Sequence B are then one state.
Without `--until`, each state's tick past closing reaches a `FULFILLED` twin, so `d1-naive.l4` gives 24 states and 45 transitions.

The P1 to P4 columns are reproduced by `l4 explore`'s own checks (WP2), which keep the cells the properties read without being told, so the graph is the same 12 states and 21 transitions:

```sh
l4 explore d1-naive.l4 --until 75600 \
  --always 'every dinner was accepted while open' --always 'at most one dinner is bought' \
  --reachable "Alice's belief is stale" --stays 'one dinner is bought' \
  --unwritten 'dinners cancelled'
```

P2 and P4 read `dinners cancelled`, which none of the three designs writes: one set of properties serves several.
A property input named for a cell nothing writes is refused, exit 1, because a misspelt input would look the same; `--unwritten` says the cell is empty by design here.

Each violated property prints its counterexample as a `#TRACE` that `l4 run` reproduces when it is pasted into the file, and each reached one its witness; every one is run as printed before it is reported.
The events of a printed trace are all at 18:00 (64800), because the explorer fires an act first at the instant of the last event: the order is Sequence A's, the clock times are not, and the fixtures' guards do not read the clock.
The exit status is 4 when a property is violated, so the D1 and D2 runs exit 4 by design.
`--eventually` labels the states for P5, P6 (`--eventually 'one dinner is bought' --if-always 'the ledger is open'`) and the non-vacuity control, and answers each `unknown (liveness: run the emitted model)`; a run with nothing else wrong then exits 5.
`jl4/tests/LtsExplore.hs` asserts every verdict and counterexample path on all five rows, and pins the checks' text under `../expected/*.check.txt`.

### The emitted models (WP3)

`--emit DIR` writes each design for other tools: `<base>.aut` for mCRL2, `<base>.tla` with `<base>.cfg` and one `.cfg` per property for TLC, `<base>.smv` for NuSMV, `<base>.dot`, and `<base>.pnml` (spec §6.1).
`--fair Alice` names the actor whose acts are assumed fair:

```sh
l4 explore d3-atomic.l4 --until 75600 \
  --always 'every dinner was accepted while open' --always 'at most one dinner is bought' \
  --reachable "Alice's belief is stale" --stays 'one dinner is bought' \
  --eventually 'Alice has bought or stopped' \
  --eventually 'one dinner is bought' --if-always 'the ledger is open' \
  --eventually 'Bob has bought' \
  --unwritten 'dinners cancelled' \
  --emit out --fair Alice
```

Weak fairness then goes to each of Alice's acts that moves, and to nothing else: in D3 her check and her answered purchase; never Bob's purchase or the message, which are the environment's; never a pause such as the unanswered purchase or `Alice is done`.
The ledger answering her is inside her act in these fixtures, so it is fair with it.

On 2026-10-26, with the files loaded unedited by mCRL2 202607.0 (`ltsinfo`, `ltsconvert`), TLC 2.19 on JDK 21 (one run per property configuration) and NuSMV 2.7.0, the verdicts were:

| property                                      | D1                                   | D2                                            | D3        |
| --------------------------------------------- | ------------------------------------ | --------------------------------------------- | --------- |
| P1, always                                    | violated: check, Bob's purchase, buy | violated: check, re-read, Bob's purchase, buy | holds     |
| P2, always                                    | holds                                | holds                                         | holds     |
| P3, reachable                                 | reachable                            | reachable                                     | reachable |
| P4, stays                                     | holds                                | holds                                         | holds     |
| P5, eventually, under `--fair Alice`          | holds                                | holds                                         | holds     |
| P6, eventually if always open, `--fair Alice` | holds                                | holds                                         | holds     |
| control, eventually `Bob has bought`, same    | violated                             | violated                                      | violated  |

TLC and NuSMV agreed on every cell, and both agree with the in-process checker on P1 to P4 and on the two counterexample paths.
TLC reports P3 as its invariant `Never_…` violated, which is how it finds a state: the configuration says so.

Two controls show that the fairness is doing the work.
With no `--fair`, nothing is fair: P5 and P6 hold on D1, which has no pause, and fail on D2 and D3 by a run that pauses forever, in both tools, which is the probes' table without fairness.
With `--fair World`, every act that moves is fair, Bob's purchase included, and the control then holds on all three designs in both tools: the runs in which Bob never buys are gone, so P6 would pass on none of them.
The control being violated is what shows P6 was checked on something.

Each `.aut`, relabelled by the table of acts above, is strongly and branching bisimilar to its reference in `reference/` (`ltscompare` prints `true`, and D1's against D3's reference prints `false`), and TAPAAL's `verifypn` 4.4.2 reads each `.pnml` as a net of 12, 15 and 10 reachable markings.
None of these tools runs in CI: the emitted text is pinned under `../expected/*.emit.txt`, and the harness in [`../harness/`](../harness/README.md) (WP4) runs the tools where they are installed and compares their verdicts, which no CI job does yet.

## What the explorer must know

Three things these fixtures need from `l4 explore` (WP1) and its harness (WP4), each measured on the fixtures:

1. **A cell read only by `RECALL` is single-valued.**
   The explorer's state keeps the ledgers some rule or property reads (spec §4.1).
   For a cell read only by `RECALL`, which gives the latest entry, the state must keep only that entry.
   Kept whole, the histories of Alice's `belief` and `plan` split states the brief identifies: the same exploration gives 14 states and 23 transitions for D1, 22 and 39 for D2, 15 and 27 for D3, and no bisimulation with the references.
   The `RECALL ALL` cells here are written at most once per run (twice in the double-buy mutant), so keeping them whole splits nothing.
2. **The closing deadline is not in the brief.**
   Every state has a live deadline, closing, so every state has a tick to just past it as a candidate.
   From each of the 12, 15 and 10 states that tick reaches a distinct `FULFILLED` state with the same ledgers.
   An explorer that offers the tick finds those states beside the brief's; the harness bounds the clock at closing (`--until 75600`, in `../harness/fixtures.tsv`) before it compares counts or graphs.
   With the anchor named, the residual prints the same at every clock (`WITHIN 0 OF closing`), so the clock need not be in the state.
3. **Passed over is no edge; a fired act that changes nothing is a self-loop.**
   `Alice is done` and the unanswered requests are self-loops, and they are what makes 21, 30 and 21 transitions.
   An act whose guard is false is passed over (the what-if's `PassedOver GuardFalse`) and is no edge at all.
   No state here is without a candidate, so no state needs the explorer's own `terminal` self-loop.

## Traps for whoever writes the next fixture

- **A rule with no inputs that reads a ledger answers once.**
  Measured: a zero-input `` `ledger open` MEANS NOT (elem taken (RECALL ALL OFFICIAL's …)) `` used as a guard let Bob's purchase be recorded twice, because its first answer was kept and reused.
  Give every rule that reads a ledger an input; here every reader takes the cell's value as its input, and the call site does the `RECALL`.
- **A relative `WITHIN` on a recursive `MAY` restarts at every act.**
  Measured: with `WITHIN 10800` in place of the anchor, the counterexample trace of `d1-naive.l4` ends with the chain still open after `` `WAIT UNTIL` 75601 ``, 419 seconds left, counted from Alice's purchase at 65220; anchor it, `WITHIN 0 OF closing`.
- **Cell names in `RECORD` and `RECALL` must be in backticks.**
  `` RECALL `plan` `` parses and `RECALL plan` does not, and the parser's complaint points at the `(` before `RECALL`, not at the name.
- **A record's fields print as heap references in a ledger.**
  ``COMMIT `x` IS (`Acceptance check` b)`` prints as `` `Acceptance check` OF &140@file.l4 ``, so the cells here hold booleans and enumerations, which print as values.
  That is why P1 reads a list of `BOOLEAN` rather than the record type the spec's sketch (§5.1) uses.
- **An `IMPORT` cannot reach a parent directory**, so `mutants/properties.l4` is a link to `../properties.l4`.

## Why no fixture carries a time, except one

On the current evaluator the instant of an act is not a value a rule can read (card B1 of EVERY-EACH-QUANTIFIER-SPEC §2.6, not on `unstable`), so a record stamped with the time of the act that made it would need the act to carry its time as a payload.
These fixtures need no time: the brief is untimed, and the order of the official record is the order of events.
A payload of type `NUMBER` would also make every act that carries one unexplorable, since an explorer refuses an unbounded payload rather than sampling it (spec §4.2, ruled R-L4).
So only `refused-number.l4` carries one, on Bob's purchase: it is the fixture that must be refused, while Alice's acts beside it stay finite and explorable.
