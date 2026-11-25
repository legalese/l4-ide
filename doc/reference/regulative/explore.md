# Every position a contract can reach: `l4 explore`

A contract is somewhere at every moment: the seller still owes delivery, or the buyer owes payment by day 9, or the contract is fulfilled, or someone is in breach.
Each thing that could happen next moves it somewhere else.
`l4 lts` ([What is owed now](lts-list.md)) shows one step from one position.
`l4 explore` keeps going.
From every position it reaches it tries every move, and it stops when no new position turns up.
What you get is the map: the positions the contract can get to, and every move between them.
How much of the contract that covers is what the coverage line at the end of every run is for.

Programming language theorists call that map a **"labelled transition system"**: the positions are its _states_, the moves are its _transitions_, and each transition is labelled with what happened.
This page says **graph**.

Every move is made by running the contract, the way `l4 lts` runs it, so the graph is what the evaluator does and not a second reading of your rules.
A trace shows what happened on one path.
The graph holds the paths the rules allow, so it can answer questions that one trace cannot: whether _any_ path puts the contract in a place it should never be, and, if one does, which path, printed as a `#TRACE` you can run.

**Status (2026-10-26):** built.
The outputs below are pasted from real runs of the `l4` built from the tree this page was written in.
The dinner files behind the later sections are in `jl4/examples/explore/brief/`, with a README that records the checks they were put through.

## A first run

**Example file:** [lts-list-example.l4](lts-list-example.l4), the sale from the page on `l4 lts`.
The seller must deliver within 3 days.
Once delivered, the buyer must pay 100 within 7 days, and if the buyer misses that, 120 within 14 more.

```bash
l4 explore lts-list-example.l4
```

The file has a `#TRACE` in which the seller delivers on day 2.
`l4 explore` does not replay that trace.
It takes from each `#TRACE` only the contract and the day it starts, and explores from the outset, so the delivery on day 2 is one path among the paths it tries.
The day it starts is read as the clock, whatever it is: negative (`AT -5`), a sum (`AT (10 + 5)`), or a date (`AT (DATE_SERIAL (YMD 2026 6 1))`), each evaluated once.
A start that is neither a number nor a date is refused with exit 1 and says so.
(Before 2026-11-23 the explorer read only a literal number, and took any other start for 0, and a start below 0 for 0 too: its clock began later than the contract's and every deadline was measured from the wrong place; one file among the 78 in the repository's examples and docs that carry a `#TRACE` explores a different graph for it, `every/run-anchors.l4` at `AT DATE_SERIAL (YMD 2026 7 1)`, from 2 states to 3.)
(One exploration is made for each distinct contract and starting day among the file's traces.
To explore a rule no trace names, give `--contract NAME`, with `--at T` for the day it starts, 0 if left out.
The rule can be at the top level or under a `§` heading, and it is found as [`l4 lts --contract`](lts-list.md) finds it.)

`l4 explore` does not read the time stamps of a trace's events.
From a `#TRACE` it takes the contract and the start, as above, and it chooses the instants it tries itself.
By default those are whole instants: a day is 3 or 4, and a time between two whole days, such as 3.8, is not one it chooses.
The exception is the clock where it already stands, which can be a fraction ("When", below): `AT 0.5` is explored from 0.5, and an act is tried there.
`--grid` steps by any N above 0 that you give it, and N need not be a whole number: `--grid 0.5` tries every half day as well (the section on `--grid`, below).
To reach a stamp such as 3.8 the step has to divide it, and 0.5 does not: `--grid 0.5` tries no act at 3.8 and says nothing about it, since the explorer never reads the stamp, while `--grid 0.2` does try one (measured 2026-11-24 on `jl4/tests-cli/fixtures/explore-instants/frac-stamp.l4`).
The note names such a step, one over the stamp's denominator: 0.2 for 3.8, 0.25 for 1.25.

A `#TRACE` can still write a time stamp that is not a whole number, and `l4 run` uses it as written.
So that it is not a surprise that `l4 explore` does not explore a run at such a time, `l4 run` and `l4 check` print a note (code `lint/fractional-trace-stamp`, severity Information) on each such stamp in an event: in a `WAITUNTIL`, or in the `AT` of an act.
A percentage of a number is read as the number it stands for, so `WAITUNTIL (350%)` is a stamp of 3.5 and gets the note, and `WAITUNTIL (400%)` is 4 and does not.
It is a note and not an error: nothing is refused and the exit status is not changed.
Two kinds of stamp get no note:

- a stamp that is not a literal number, such as `WAITUNTIL (7 / 2)`, has no value until it is evaluated;
- the start of the trace, such as `AT 0.5`.
  `l4 explore` reads it as its clock, so it is not a time the explorer ignores.
  It names for itself what that leaves untried: from a start of 0.5, an obligation `WITHIN 3` has its deadline at 3.5, which is not a whole instant, so the explorer tries the act at 0.5, says `an instant it needs (3.5) is not a whole number`, and exits 2 (measured 2026-11-24 on `jl4/tests-cli/fixtures/explore-instants/frac-start.l4`).

What comes back, abridged at the residuals (the contract as it stands in each state, which the next section explains):

```text
saleContract, explored from its outset at 0: 6 states, 9 transitions

s0  depth 0, residual r0
    at the outset
    ledgers: nothing kept
s1  depth 1, residual r1
    first reached by:
      PARTY Seller DOES delivery AT 0
    ledgers: nothing kept
s2  depth 1, residual r2, terminal
    first reached by:
      WAITUNTIL OF 4
    ledgers: nothing kept
s3  depth 2, residual r3, terminal
    first reached by:
      PARTY Seller DOES delivery AT 0
      PARTY Buyer DOES payment OF 100 AT 0
    ledgers: nothing kept
s4  depth 2, residual r4
    first reached by:
      PARTY Seller DOES delivery AT 0
      WAITUNTIL OF 8
    ledgers: nothing kept
s5  depth 3, residual r5, terminal
    first reached by:
      PARTY Seller DOES delivery AT 0
      WAITUNTIL OF 8
      WAITUNTIL OF 22
    ledgers: nothing kept

Transitions (9):
  s0 -> s1  PARTY Seller DOES delivery
  s0 -> s2  time passes the deadline 3 (WAITUNTIL 4)
  s1 -> s3  PARTY Buyer DOES payment OF 100
  s1 -> s4  time passes the deadline 7 (WAITUNTIL 8)
  s2 -> s2  terminal
  s3 -> s3  terminal
  s4 -> s3  PARTY Buyer DOES payment OF 120
  s4 -> s5  time passes the deadline 21 (WAITUNTIL 22)
  s5 -> s5  terminal

Residuals (6):
  r0  PARTY Seller MUST delivery WITHIN 3 HENCE (…)
  …

Coverage: 6 states, 9 transitions; frontier exhausted; nothing refused; nothing untried; 0 acts passed over; no write-only cell dropped; time by regions (whole instants: the last event, the deadline, window openings, the ties between a deadline an act starts and one already live, and one between each; the clock is not in the state); instants: 3 acts tried at 9 instants (0 ties, 3 gaps)
```

Reading it from the top:

- **A state** is a position, numbered in the order the explorer found it.
  `s0` is the outset.
  `depth` is the number of events on the shortest path that reaches it, and `first reached by` is that path, written as a `#TRACE` writes events.
  A state may be reached by other paths too; only the first is printed.
- **A transition** is one move the contract took: an act by the party who owes it, or time passing.
  `s0 -> s2` is the seller missing the delivery deadline of day 3: the explorer lets the clock run to just past the deadline (`WAITUNTIL 4`) with nothing happening, and the contract answers that the seller is in breach.
  A deadline passing is a move like any other.
- **A terminal state** is one where nothing more can happen: here `s2` (the seller is in breach), `s3` (fulfilled) and `s5` (the buyer is in breach).
  The explorer gives each one a self-loop labelled `terminal`, so that a tool reading the graph does not take it for a deadlock.
  A breach is terminal only when nothing is still waiting behind it: [one side of a `RAND` can be breached while the other is still being held to what happens next](#a-breach-with-a-part-still-waiting).
- **Positions, not paths.** `s3` is reached by paying 100 on time and by paying 120 late.
  The two histories differ, and the position they leave is the same one: `FULFILLED`.
  So the graph has one `s3`, with two arrows into it.

The graph is a picture waiting to be drawn.
`--dot` prints it in GraphViz's DOT language, and `l4 explore lts-list-example.l4 --dot | dot -Tsvg -o sale.svg` draws these six states and nine arrows (checked 2026-10-26 with GraphViz 14.1.0).
`l4 state-graph` also draws a rule, but from the text of the rule and without running it; [What the graph is not](#what-the-graph-is-not) says how the two differ.

## What a state is

Two positions are **the same state** when four things agree:

1. **The contract as it now stands**, called the _residual_: what is still owed, by whom, by when.
   In the sale above every state has its own residual.
   In the dinner example below every state has the same one, because the rule renews itself, and the ledgers tell the states apart.
2. **The ledgers**, but only the cells that some rule or property reads.
   Records made with `RECORD` and `COMMIT` go into ledgers, and `RECALL` reads them back.
   A cell that a `RECALL ALL` reads is kept with its whole history, in the order it was written.
   A cell that only a `RECALL` reads is kept as its latest entry, which is all that read can see.
   A cell nothing reads is dropped from the state and named on the coverage line.
3. **The answer of any rule with no inputs that reads a ledger**, if it has been asked.
   L4 keeps such a rule's first answer, so it is part of where the run stands.
4. **Which of the live deadlines the clock has already passed, and which of the live deadlines and window openings comes first.** The clock itself is not kept (unless you ask for `--grid`, below), and a clock at a deadline is the same state as one before it.
   The order of the deadlines and openings is kept because the printed contract does not always say it: a deadline anchored to another (`WITHIN 3 OF THE DEADLINE`) prints the same wherever it falls.

Two positions that agree on all four are merged into one, and that is what makes the exploration stop.
A contract that renews itself would otherwise never finish: each lap would be a new position.
The merge is also the one place the graph can quietly be wrong, and [the failures below](#loud-and-silent-failures) are mostly about it.

## A breach with a part still waiting

`A RAND B` is breached as soon as `A` is, and the contract is then decided: it can no longer be fulfilled.
But `B` is still held to everything that happens after, and what happens to `B` changes who is blamed.
In `jl4/tests-cli/fixtures/explore-breached/sale.l4` the buyer must pay within 2 days and the seller must deliver within 5, as the two sides of a `RAND`.
When the clock passes day 2 with no payment, the buyer is in breach, and `l4 run` shows the contract is still watching the seller: with the clock then passing day 5 as well, the blame is `BY Buyer BY Seller`.

The explorer used to call the state after the buyer's breach terminal, so that the path from it to the seller's blame was not in the graph, and a property about who is blamed afterwards was checked against a graph that did not contain the path.
It now keeps what is still waiting, and prints it with the state:

```text
r7  DEONTIC BREACHED:
      BREACH
      BY Buyer
      [still waiting on: Seller MUST deliver WITHIN 2]
```

That state is not terminal.
It has the seller's act and the tick past the seller's deadline as moves, and each is run on the evaluator like any other: the act leaves the same breach with nothing waiting (terminal), and the tick leaves `BY Buyer BY Seller`.
The remaining time is counted from the state's own clock (day 3, so 2 days left), and the deadline keeps its place among the other deadlines in the state's key, like any live one.
Two breached states that blame the same party are two states when one has a part waiting and the other has not.
On the fixture the graph grows from 11 states and 24 transitions to 12 and 26 (measured 2026-11-23); `resell.l4`, the contract of smucclaw/l4-ide#1087 (the seller SHANT resell), from 4 and 6 to 8 and 15.

**What it cannot read.**
The explorer carries the obligations the contract held before the breach.
A part that was armed only after the breach, by the continuation of one that was then taken, was never held: a breached value keeps its blame and nothing of the other side.
The same note also names a part of the contract that the evaluator is waiting on and that the explorer cannot match to anything it held before: on `jl4/examples/ok/every/run-lest.l4` it names the members of an `EVERY` (measured 2026-11-23), where the cause is not a continuation, and the sentence says "usually" for that reason.
`jl4/tests-cli/fixtures/explore-breached/continuation.l4` is the seller's delivery with an invoice due 3 days after it.
After the buyer's breach and the delivery, the evaluator is waiting on the invoice, and a later tick adds the seller's blame (`l4 run` on `(WAITUNTIL 3)`, the delivery at 4, `(WAITUNTIL 8)` gives `BY Buyer BY Seller`).
The explorer names that state and says so, and exits 2:

```text
UNTRIED 1: (unread) Seller (as written) MUST (at continuation.l4:19:32-44) (it is waiting behind a breach and is not one the explorer held before it: usually armed after the breach, by the continuation of a part that was then taken (a breached value keeps only its blame), so what it asks and when cannot be read back)
```

The state is listed, is not marked terminal, and has no moves, because none can be built for it.
So for a contract whose seller's side has a continuation, the graph is not complete after a breach on the other side, and the line says it is not.
Completing it needs the evaluator to hand over the other side's residual, which is a change to the evaluator's value type and is not made here.
Of the 78 files measured, 7 name such a norm, and all 7 already exited 2 for another reason; no file changed its exit status for this (2026-11-23).

## What the explorer tries

**Acts.**
Each obligation, permission or prohibition in force offers its own act, done by the party it names, and for each distinct deadline there is one move to just past it, which this page calls a _tick_.
These are the same candidates `l4 lts` tries, and [that page](lts-list.md#the-sections-and-when-each-appears) says which.
An event that no obligation in force offers is never tried: the graph is the graph of what the contract's own rules allow.

**Acts the rule leaves open.**
When a rule leaves part of the act open, as in `MAY act` or `MUST payment amount`, `l4 lts` runs one example act and says so ([Acts the rule leaves open](lts-list.md#acts-the-rule-leaves-open)).
`l4 explore` cannot stop at one: it has to try them all.
It does so when the open part has a finite set of values, which means a `BOOLEAN`, a `DECLARE … IS ONE OF`, or a record whose fields are all finite in the same sense.
It **refuses** when the open part is a `NUMBER`, a `STRING`, a `LIST`, or a type with type arguments (a `MAYBE`), or any other type whose values cannot be listed (a recursive type, say), or when the acts it would have to list number more than `--max-acts` (4096).
A refusal names the variable the rule leaves open, its type, and the field that cannot be listed, and the finite constructors beside it are still explored.
It never tries a sample in the place of a refused act: `0` for every number would be a claim about numbers it never tried.

**When.**
By default an act is tried at whole instants, because contract time is discrete: a day, an hour, whatever unit the contract's numbers are in.
The one other instant is the clock where the position already stands.
It is a fraction after a start such as `AT 0.5`, and after time passes a deadline that is itself a fraction: when `WITHIN 2.5` lapses the explorer lets time pass to 3.5, and an act that follows is tried at 3.5 (measured 2026-11-24 on `jl4/tests-cli/fixtures/explore-instants/frac-wait.l4`, which shows `PARTY Q DOES b AT 3.5`).
`--grid` is the way to try the instants between whole ones (below).
Which whole instants is the question the page "[Where the region scheme stops being exact](#silent-not-on-the-coverage-line-either)" answers the other way round, so here is what is tried and why.
After an act at some instant, the deadlines the contract is then waiting for are of two kinds.
Some were already running, or are fixed to an instant that was already fixed (`WITHIN 3 OF THE DEADLINE`): they do not move with the act.
Others are started by the act itself (`HENCE … WITHIN 5`): they fall five units after it.
Which comes first, and above all whether two fall on the same instant, depends on when the act was done, and a breach on a day when two deadlines fall together names both parties.
So the explorer tries an act at:

- the instant of the last event;
- the earliest live deadline itself, and never past it, because the contract would expire the deadline first and the arrow would carry the act's name for the deadline's effect (a later instant is reached by the tick past the deadline, then the act);
- the instant its own window opens, when it has one that has not opened yet (`AFTER`), and the instants other live windows open, since an act is taken or not according to which side of an opening it falls on;
- each **tie**: the instant at which a deadline the act starts would fall on one already fixed, and the instant at which one already fixed, that only the position the act leads to holds (`WITHIN 3 OF THE ARMING`), is reached;
- and one whole instant between each two of those, when there is one.

The ties are found by running the contract, as everything else here is: the act is tried at the instants the position names, and the deadlines of the positions it leads to say, for each obligation, which moved with the act and which did not.
It is never tried past `--until`.

**A tie that needs a chain of acts is named and not searched, unless you ask.**
An act is never tried past the earliest live deadline, and the deadline the first act starts is one of those, so where the first act falls decides whether a second act's tie can be reached at all.
The first act's boundary is then the fixed instant minus both offsets, and a longer chain adds more.
By default the explorer searches the ties of one act's own offsets only, and the coverage line says what it did not search: `UNTRIED 1: ties through chains of acts, for <acts> …`, with the instants that could put a tie in reach, and the exit status is 2.
The note also says what `--chains` does not reach and that `--grid 1` tries every whole instant up to a deadline or `--until`; the cases are listed under "Where the region scheme stops being exact" below.
It says so only for an act that a later act's offset could reach, so a contract with no chain says nothing about chains.
`--chains` searches them as well: the explorer runs again with what the acts that can follow each one were found to do, up to three times, until that stops growing.
It costs a larger graph, so it is not the default.
Measured on the 78 files in this repository's examples and docs that carry a `#TRACE` (2026-11-23, against `unstable` before the instants and the breached-position changes, with both in):

- by default, 3 files exit 2 where they exited 0 before.
  `jl4/examples/ok/every/run-in.l4` and `run-modals.l4` name a chain, and `--chains` finds what they left out (1068 states become 3138, and 68 become 203, in the larger graphs of each file), and `run-in.l4` still exits 2 under it, for the norms behind a breach that [the section above](#a-breach-with-a-part-still-waiting) names.
  `doc/reference/regulative/must-example.l4` names a chain that adds nothing: `--chains` explores the same 8 states and exits 0, because the line says what _could_ put a tie in reach and does not know that it does.
  `jl4/examples/explore/ledger/d3-reopen.l4` takes about five minutes before and after, at the 300 second limit the sweep ran under (it ended at that limit before and at the state bound in one run after), so its exit status is not a comparison;
- of the 405 graphs those files explore (leaving out the one that timed out), 342 have the same number of states as before, 58 have more and 5 have fewer.
  The five that have fewer are in three files (`breach-clocks.l4`, `deontic-breach-semantics.l4` and `every/run-lest.l4`), and none of the three changed its exit status;
  The largest growth is a block of `run-after.l4`, `EVERY Tenant t IN tenants MUST Sign t AFTER 3 WITHIN 30`, from 1 state to 11: the old explorer passed both acts over at every instant it tried and stopped at the outset, and the new one tries them at the instant the window opens;
- `--chains` costs states, and some time: the wall-clock figures this machine gave were too noisy to quote (the whole set took 505 and 593 seconds on two runs by default and 720 and 1169 on two under `--chains`, four files at a time, under a load that changed between them; `run-in.l4` under `--chains` took 254 seconds on one and ran past the sweep's 300 second limit on the other), so read the states and not the seconds.
  `run-modals.l4` still exits 2 under it, because the offsets kept growing after three passes, and the line says so.
  With no live deadline and no `--until`, the instants are the first one the act's window is open and the one after it.
  The boundaries matter: a rule that treats an act at exactly the deadline differently from one just before it is only visible if the explorer tries the deadline itself, and a breach that names two parties is only visible if it tries the instant at which the deadlines meet.
  The coverage line says which scheme was used (`time by regions`) and how many acts were tried at how many instants (`instants: …`).
  By default a fraction is not an instant it chooses: a deadline or window opening that is not a whole number leaves the instants it needs untried, and the line says so.
  The clock where the position already stands is tried even when it is a fraction (a start of `AT 0.5`, or the instant after a deadline that is one), and `--grid` with a step that is not a whole number, such as `--grid 0.5`, tries the fractions that are multiples of it.

**What the cap and the window mean for a long deadline.**
Take `room.l4` with its numbers changed to deadlines of 365, 400 and 400 days (R, `a` and `u`) and acts that start deadlines of 30 and 14 days (Q and V), measured 2026-11-23.
Under regions it has 503 states and exits 2, in about 6 seconds; with `--chains` it has 818 states and exits 2, in about 16 seconds (measured 2026-11-23; the exit is 2 under both because of the norms behind a breach, and under regions also because of the chain).
`--grid 1` on the same contract tries every day of every window, so each act in each state needs more than the cap of 256 instants, the clock tells states apart, and the run was stopped by the state bound (10000 states, 423,356 more not added) after 18 minutes, with the instant cap named for three acts (measured before the breached-position change and not run again: it is the one measurement here that takes that long).
A long deadline is therefore cheap under regions and expensive under a grid: `--grid` is for a contract that is short, or for the one rule that reads the clock arithmetically.

**What the regions graph is.**
It is an abstraction of contract time, and it says what it skipped.
Two positions with the same order of deadlines and different gaps between them have different futures, so the order alone is not enough, and the only exact abstraction is the graph of every whole instant: `--grid 1`, below.
Regions is the cheaper graph that tries to find every position the evaluator can reach, and where it knows it may not have (a chain tie, a fraction, the instant cap, a norm waiting behind a breach) the line says "UNTRIED" and never "nothing untried".
What `nothing untried` promises is narrower than that: every move the contract offers in a state was tried at every instant the scheme chose, and whatever was not tried is named.
It does not promise that the graph holds every position the evaluator can reach: the scheme tries a sample of the instants and its state does not hold the clock, and the cases it is known to miss without saying so are listed under "Where the region scheme stops being exact".
`--grid 1 --until N` is the graph of every whole instant up to a deadline or `N`, for a contract small enough.

`--grid N` is the alternative, for a rule whose guard reads the clock arithmetically: it tries every multiple of N from the first instant the act's window is open up to the next deadline, and keeps the clock in the state.
It explores the model in which every event happens at a multiple of N, so an act at any other instant is outside it, and the explorer cannot say what it did not try: `--grid 2` on a contract whose numbers are all even does not hold the position an act at 1 reaches (a review found one, 2026-11-23); use `--grid 1` to hold every whole instant.
N must be above 0: `--grid 0` is refused with `N must be a positive number` and exit 1, and a negative one is refused as not a number (measured 2026-11-24).
The step need not be a whole number: `--grid 0.5` on `half.l4`, whose deadline is 2.5, tried acts at 0, 0.5, 1, 1.5, 2 and 2.5 and exited 0 (measured 2026-11-24).
What it does check is the other half of the condition: a clock, a deadline or a window opening that is not a multiple of N, in a position it reaches, is named as untried, and so is a run with no deadline and no `--until`, because a grid has no end to try up to then.
The cost is the whole window: `--grid 1` on an obligation that is `WITHIN 365` tries 366 instants per act in each state, and the clock tells states apart, so the graph is several times larger than the regions graph for the same contract.
**One act is tried at no more than 256 instants in one state**, so that run exits 2 and says how many it did not try; `--max-instants 400` lifts the bound.
(On the dinner example below, `--grid 50` gives 20 states against 8; measured 2026-10-26, before the grid tried every multiple.)

**How far.**
Exploration is breadth first and every move is a full re-run of the contract, so a large contract takes time in proportion to its states.
`--until T` bounds the clock: no event later than T, and a tick past T is not taken.
`--max-depth N` (default 100) stops expanding states reached by more than N events, and `--max-states N` (default 10000) stops adding states.

### A deadline written as a name

A `WITHIN` written as a name or as arithmetic is worked out by the evaluator, as a run of the contract would work it out, whenever it is _closed_: when it reads nothing that only a run decides, which is no input of the rule, no name local to it, no value an event carried, no anchor word such as `THE JOIN`, no ledger, no section's `GIVEN`, no clock (`TODAY`, `NOW`, `CURRENTTIME`, `RULES EFFECTIVE DATE`) and nothing outside the file (`ENV`, `FETCH`, `POST`), either itself or through a rule of the file it names.
Numbers are closed, and so are rules of the file or its imports applied to numbers, when the rules read none of these.
A statutory period written once and named is the usual case:

```
DECLARE Person IS ONE OF Buyer, Seller
DECLARE Action IS ONE OF refund

`the refund period` MEANS 14

GIVETH A DEONTIC Person Action
`the refund duty` MEANS
  PARTY Seller MUST refund WITHIN `the refund period`
  HENCE FULFILLED
  LEST BREACH BY Seller BECAUSE "refund late"
```

`l4 explore --contract "the refund duty"` explores it as it explores `WITHIN 14`: 3 states and 4 transitions, among them `time passes the deadline 14 (WAITUNTIL 15)`, and exit 0 (measured 2026-11-25).
The same holds for `WITHIN 5 PLUS 5`, for a name for `5 PLUS 5`, for a constant an imported file defines, for an `OF` anchor that is a name, for a deadline beside a literal `AFTER`, and for one armed by a `HENCE` or carried past a breach: each explores to the graph of its literal twin (`jl4/tests-cli/fixtures/explore-deadlines/`).
Before 2026-11-25 the explorer worked out a `WITHIN` only when it was a literal number (it already worked out a closed `OF` anchor with no `AFTER` beside it), so this contract explored to 2 states, its breach was never reached, and the line said `UNTRIED 1: time runs out on refund (the WITHIN was never evaluated and is not a literal, so its deadline is not known here)`.

What is still not worked out is listed as untried (exit 2), and the reason in brackets says which it is:

- a `WITHIN` that reads an input of the rule (`GIVEN period … WITHIN period`), a name a `WHERE` or `LET` defines, or a value an event carried (`PARTY Alice MUST Pay n … HENCE PARTY Bob MUST ship WITHIN n`), and the reason says which: ``the WITHIN reads `period`, an input of the rule, which the contract has not worked out yet, so its deadline is not known here``, ``… reads `period`, a name the rule defines with WHERE or LET, …``, or ``… reads `n`, a value an event carried, …`` (a name bound any other way, such as a `CONSIDER` pattern's, is called a name local to the rule);
- one that reads a ledger with `RECALL`, written in the `WITHIN` itself (`the WITHIN reads a ledger with RECALL, so it is worked out only in a run and its deadline is not known here`) or in a rule of the file it names, directly or through another rule (``the WITHIN reads `recorded period`, which reads a ledger, …``), because outside a run the ledger is empty (a rule of an imported file is not checked: see [the silent failures](#silent-not-on-the-coverage-line-either)).
  An `OF` anchor that reads a ledger is not worked out either (`the anchor of the WITHIN reads a ledger with RECALL, …`), and that is a change: before smucclaw/l4-ide#1107 the explorer worked out ``WITHIN 2 OF fromMaybe 3 (RECALL `start`)`` against the empty ledger, explored to the deadline 5 and exited 0; it is now untried, and the exit status is 2 (`jl4/tests-cli/fixtures/explore-deadlines/ledger.l4`, measured 2026-11-26 on a build of `unstable` and on this change);
- one that reads the clock or the world outside the file, itself or through a rule of the file: ``the WITHIN reads `clocky`, which reads the clock (TODAY), so it is worked out only in a run and its deadline is not known here``, or `the WITHIN reads the world outside the file (ENV), …`, because a run on another day, or in another environment, gets another answer; worked out, `` `clocky` MEANS ((DATE_SERIAL TODAY) MODULO 7) PLUS 3 `` explored to the deadline 8 under one `--fixed-now` and 5 under another (`jl4/tests-cli/fixtures/explore-deadlines/clock.l4`, measured 2026-11-26);
- one whose working out fails, such as a name for `10 DIVIDED BY 0`: `working out the WITHIN failed (Division by zero in the operation: DIVIDED BY), so its deadline is not known here`, and the exploration carries on;
- one that reads a section's `GIVEN`, itself or through a rule of the file, whether a `WITH` supplies it or its `TYPICALLY` default is left to stand: ``the WITHIN reads `the period`, a section GIVEN, which a WITH can supply, so it is worked out only in a run and its deadline is not known here``, or ``the WITHIN reads `the window`, which reads `rate`, a section GIVEN, …``.
  Worked out outside a run, the `GIVEN` would read its default and not what the `WITH` supplied: under `` `the duty` WITH `the period` IS 10 PLUS 10 `` the run's deadline is 20, and the explorer, while it still worked this out, explored to the deadline 30 and exited 0.
  An `OF` anchor that reads a section's `GIVEN` is not worked out either; the explorer before smucclaw/l4-ide#1107 did work one out, and got 35 where the run's deadline is 20, which is fixed too.
  A `WITHIN` naming a rule that reads one was untried too while the explorer still worked it out, but with the evaluator's `Internal error: … given signatures' values' lengths do not match … Please report this as a bug.` as its reason; it now has the reason above (`jl4/tests-cli/fixtures/explore-deadlines/section-reader.l4`).
  The cost is a deadline whose `GIVEN` nothing supplies, which a run counts from the default: it is untried as well (`jl4/tests-cli/fixtures/explore-deadlines/section-given.l4`, measured 2026-11-26);
- an `AFTER` written as a name (``AFTER `five days` WITHIN 10``): the window's opening is not worked out, and so neither is its deadline (`the AFTER was never evaluated and is not a literal (a date, or a computed offset), so its deadline is not known here`).

A deadline whose working out is stopped at a limit is not listed as untried: the explorer refuses the contract and exits 1 (`the evaluator stopped at a limit working out a deadline: I stopped evaluating: it took more than 20000 steps, …` under `--max-steps 20000`, measured 2026-11-25), because a graph without that deadline's tick would be missing positions.

## The coverage line

Every run ends with one line that says how much of the contract the graph covers.
A graph without it is a picture without a scale.
Here it is for the sale, with each clause labelled:

| clause                                                                                                  | what it says                                                                                                                                                                                                                           | when it is not the quiet form                                                                                                                                                                                                          |
| ------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `6 states, 9 transitions`                                                                               | the size of the graph                                                                                                                                                                                                                  |                                                                                                                                                                                                                                        |
| `frontier exhausted`                                                                                    | every state found was expanded, and no new one turned up                                                                                                                                                                               | `frontier NOT exhausted: …` names the bound that stopped it, `--max-depth` or `--max-states`, and a count of the states it left; for `--max-states` the count is of refusals, so a state reached twice is counted twice. Exit status 3 |
| `nothing refused`                                                                                       | every act the rules leave open was listed                                                                                                                                                                                              | `REFUSED n: …` names each variable, its type and the field. Exit status 2                                                                                                                                                              |
| `nothing untried`                                                                                       | every move offered could be run, at every instant the scheme chose                                                                                                                                                                     | `UNTRIED n: …` names each move and why it could not be run, and each act at instants it could not try (a fraction, the instant cap, a grid's end). Exit status 2                                                                       |
| `0 acts passed over`                                                                                    | how many (state, act) pairs the contract declined at every instant tried. A declined act is no arrow                                                                                                                                   | a count only: it does not say which acts                                                                                                                                                                                               |
| `no write-only cell dropped`                                                                            | no ledger cell was thrown away from the state                                                                                                                                                                                          | `write-only cells dropped: …` names the ledger cells that were written and never read. Positions that differ only in those cells are one state                                                                                         |
| `time by regions (…)`                                                                                   | which way of choosing instants was used (the section above), and, with `--until`, `clock bounded at T`; with a bound, `n ticks past the clock bound not taken` says how many moves the bound cut                                       | `time on a grid of N (the clock is in the state)` with `--grid`                                                                                                                                                                        |
| `instants: n acts tried at m instants (k ties, g gaps)`                                                 | how many (state, act) pairs were tried, at how many instants in all, and why those: `k` of them because a deadline the act starts fell on one already live, `g` as the whole instant between two others. A grid prints no ties or gaps | an account, not a verdict: what the scheme could not try is among the `UNTRIED` entries, which is why this clause comes last                                                                                                           |
| _(only when present)_ `compared by name only: …`                                                        | a residual held a local value the run never worked out, so two positions that differ only in it would be merged                                                                                                                        | it names each such local                                                                                                                                                                                                               |
| _(only when present)_ `n ledger values compared by printed form`, `answers compared by printed form: …` | a ledger value, or a rule's answer, has no literal form (a function, say), so the state compares how it prints                                                                                                                         | two different values that print alike would be merged                                                                                                                                                                                  |

Two cautions on reading it.
**"Frontier exhausted" does not mean complete.**
It says only that every state the explorer found was expanded.
A run with `REFUSED 1` or `UNTRIED 2` prints it too, beside the clause that says the graph is partial.
**"Complete" in `--json` does not mean faithful.**
The `complete` flag in the JSON is true when nothing was refused, nothing untried and the frontier was exhausted.
It is true with ticks cut by `--until`, and true when write-only cells merged states, as the next section shows.

## The exit status

The exit status is for scripts, so that a CI job cannot read a partial run as a green one.

| status | means                                                                                                                                                                                                                                                                                                                                                                                   |
| ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0      | the frontier was exhausted with nothing refused and nothing untried, and every property named holds                                                                                                                                                                                                                                                                                     |
| 1      | the file does not type-check; an option names nothing (a property, a `--contract`, a `--fair`); a property input named for a cell nothing writes; an `--until` before the outset; a property, `--emit` or `--fair` asked of a file with nothing to explore; a contract cannot be run at its outset; working out a deadline was stopped at a limit; an emitted file could not be written |
| 2      | an act was refused, or a move could not be tried, or an act could not be tried at an instant the scheme chose (including a tie through a chain of acts, below)                                                                                                                                                                                                                          |
| 3      | nothing refused or untried, but `--max-depth` or `--max-states` stopped the exploration                                                                                                                                                                                                                                                                                                 |
| 4      | a property is violated (its counterexample is printed, and is real whatever else the run did)                                                                                                                                                                                                                                                                                           |
| 5      | the exploration was complete but a property's verdict is unknown (every liveness property)                                                                                                                                                                                                                                                                                              |

When a run has more than one of these, the order of the table is not the order of precedence: 1 wins, then 4, then 2, then 3, then 5.
A tick past `--until` is the exploration you asked for, not a failure of it, and does not change the status.

## Checking properties

A property can be checked against every state of the graph.
**Example file:** [explore-example.l4](explore-example.l4).
Alice and Bob each mean to buy dinner tonight, and neither wants to buy it if the other already has.
Alice checks whether dinner is bought and, if her check found it unbought, buys.
If Bob's purchase is recorded between her check and her purchase, two dinners are bought.
That is a race condition, and the file is written wrong on purpose so that there is something to find.
Everything that can happen is an act of one party, `World`, in one permission that recurs, and each act names its actor.
Bob's purchase is an act in the contract, because otherwise no exploration could vary when it lands.

A property is an ordinary rule that gives a `BOOLEAN`.
It takes the ledger cells it reads as inputs, each input named for its cell.
An input that is a `LIST` is filled with the cell's whole history, as `RECALL ALL` would; an input that is a `MAYBE` is filled with its latest entry, as `RECALL` would.
There is no property syntax, so the flag carries the property's class:

| flag                             | asks                                                                                                                                                              | verdicts                                                     |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `--always P`                     | is `P` true in every reachable state (safety)?                                                                                                                    | holds; violated, with a counterexample                       |
| `--reachable P`                  | is `P` true in some reachable state?                                                                                                                              | holds, with a witness; violated                              |
| `--stays P`                      | does no move go from a state where `P` is true to one where it is false (once true, always true)?                                                                 | holds; violated, with the move                               |
| `--eventually P [--if-always Q]` | does `P` eventually hold (if `Q` always does)? Liveness needs a fairness assumption and a model checker, so the states are labelled and the answer is left to one | unknown, always: `unknown (liveness: run the emitted model)` |

A property input named for a cell that no `RECORD`, `COMMIT` or `ATTEST` in the file or its imports writes is refused, with exit status 1, naming the property and the cell.
The cell is empty in every state, which is also what a typo in the input's name gives, and nothing else tells the two apart.
`--unwritten CELL` lifts the refusal for that cell alone, and may be repeated.
Use it for a cell written by something the text cannot show, or empty by design in this file: one set of properties serves several designs.

The property of the example says that a dinner is bought only if the ledger said unbought at the instant the purchase took effect.

```bash
l4 explore explore-example.l4 --until 100 --always 'every dinner was accepted while open'
```

```text
`the arrangement`, explored from its outset at 0: 8 states, 7 transitions

Checks (1): 1 violated

always `every dinner was accepted while open`: violated after 3 events (state s6)
  reads `open at acceptance` (every entry, in OFFICIAL's ledger)

-- `every dinner was accepted while open` is FALSE after the 3 events below (l4 explore; replayed on the evaluator)
#TRACE `the arrangement` AT 0 WITH
    PARTY World DOES `Alice checks whether dinner is bought` AT 0
    PARTY World DOES `Bob buys dinner` AT 0
    PARTY World DOES `Alice buys dinner` AT 0

Coverage: 8 states, 7 transitions; frontier exhausted; nothing refused; nothing untried; 17 acts passed over; 8 ticks past the clock bound not taken; no write-only cell dropped; time by regions (whole instants: the last event, the deadline, window openings, the ties between a deadline an act starts and one already live, and one between each; the clock is not in the state), clock bounded at 100; instants: 24 acts tried at 72 instants (0 ties, 24 gaps)
```

The counterexample is a `#TRACE`, and it is real: before printing it the explorer replays it on the evaluator afresh and evaluates the property on the ledgers that replay leaves, and prints it only if the answer is the one the graph gave.
A path that does not replay is reported as `unknown` with the path marked `NOT reproduced on replay`, which means the explorer merged two positions the property tells apart.
Pasted at the end of `explore-example.l4`, the trace runs under `l4 run` and the official record ends ``COMMIT `open at acceptance` IS FALSE`` (checked 2026-10-26): Alice's purchase took effect after Bob's.
The file's own `#TRACE` is the same three steps at days 10, 11 and 12.

**The times in a printed counterexample are not times anyone chose.**
Every event carries the instant of the outset (`AT 0`), because the explorer tries an act first at the instant of the last event.
The order of the events is the finding.
The clock times are not, and a rule whose guard reads the clock would not reproduce at them.

With `--json` the object also carries `checks`, each verdict with its path, and `labels`, each property's value state by state.

## Handing the graph to other tools

`--json` prints the graph as JSON, one object per contract explored: `contract`, `at`, `states` (each with `id`, `depth`, `path`, `residual`, `ledger` and `terminal`), `transitions` (`from`, `to`, `label`, and `kind`: `act`, `tick` or `terminal`) and `coverage`.
The coverage object carries every clause of the line as a key, and `line` holds the line itself.
`--dot` prints GraphViz.
With either, the coverage line also goes to standard error, so that a run piped into another program still says where a person will see it how much it covered.

`--emit DIR` writes the graph for model checkers, one set of files per contract explored.
For `explore-example.l4` and one property it writes `explore_example.aut` (Aldebaran, which mCRL2 reads), `explore_example.tla` with `explore_example.cfg` and one `.cfg` per property (TLC), `explore_example.smv` (NuSMV), `explore_example.dot` and `explore_example.pnml` (a Petri net, for TAPAAL).
The properties named become the models' predicates and properties, each the set of states the evaluator labelled true, so a checker never interprets L4.
The liveness properties that the in-process checker leaves `unknown` are for those tools to decide.

A liveness property needs to know which actors are assumed to keep acting.
`--fair NAME` gives weak fairness, in the TLA+ and NuSMV models, to every act of that actor that moves (name a party, an act's constructor, or the first words of a constructor's name, as `Alice` in `Alice buys dinner`).
No other act is fair, and a pause (an act that changes nothing) never is.
Without `--fair`, nothing is fair, so a liveness property that needs fairness fails, loudly, until you name the actor.
A `--fair` that names no act of the graph exits with status 1 and writes no file (measured 2026-10-26), because a typo would otherwise leave the actor unfair without a word.
How the three model checkers behaved on the dinner files, and the harness that compares them, are recorded in `jl4/examples/explore/brief/README.md` and `jl4/examples/explore/harness/README.md`; none of it runs in CI yet.

## Loud and silent failures

A failure is worth the words in proportion to how little it announces itself.
These are sorted by which signal carries them.

### Loud: the exit status is not 0, and the line says why

- **Refused (exit 2).** An act the rules leave open has a `NUMBER`, `STRING`, `LIST` or `MAYBE` in it.
  The coverage line has `REFUSED n` and the text before it names the variable, its type and the field.
  On the dinner fixture whose record of Bob's purchase carries its time: `` `act` of type Act, constructor `ledger records Bob's purchase` (its field `recorded at` is a NUMBER, and a NUMBER has no finite set of values) `` (`jl4/examples/explore/brief/refused-number.l4`, 3 states, 4 transitions, exit 2).
- **Untried (exit 2).** A move was offered and could not be run.
  A `BEFORE` date in a contract explored from `AT 0` gave `UNTRIED 2` (measured 2026-10-26), because 0 is not a date serial.
  The run had 1 state and 0 transitions, and the same line says `frontier exhausted`.
  Nothing beyond the outset was explored.
  A move whose run stopped because the two sides of a compound read each other's records in an order L4 cannot settle is untried too, and the reason in brackets is that error, naming the record and both sides ([Deadlines and consequences](consequences.md)).
  On `jl4/tests-cli/fixtures/sibling-reads/one-event.l4`, a `RAND` whose two sides take one event, one side making a record and the other reading it at the same instant, `--until 20` gave 2 states, `UNTRIED 3` (three `PARTY P DOES go` moves) and exited 2 (measured 2026-11-13).
  The two sides of a `RAND` that read each other's records at different events are run in step and explored like any other contract: on `jl4/tests-cli/fixtures/sibling-reads/dinner-ab.l4`, Alice and Bob as the two sides of a `RAND`, `--until 100 --always "every dinner was accepted while open"` gave 18 states, `violated after 3 events` with Alice checking, Bob buying and Alice buying, and exited 4 (measured 2026-11-13).
- **A deadline it cannot work out (exit 2).** A `WITHIN` that reads an input of the rule, a local name, a ledger, a section's `GIVEN`, the clock or the world outside the file, or whose working out fails, has no tick: the line has `UNTRIED` and `time runs out on …`, with the reason in brackets ([A deadline written as a name](#a-deadline-written-as-a-name), above).
  One whose working out is stopped at a limit refuses the contract instead (exit 1).
- **A norm armed behind a breach (exit 2).** The coverage line has `UNTRIED` and `(unread)`, as above: a part of the contract that the evaluator is still waiting on after a breach, and that the explorer holds no obligation for.
  Nothing was explored from it, and the state is not called terminal.
- **A bound stopped it (exit 3).** `frontier NOT exhausted`, with the number of states left.
  `--max-states 5` on `jl4/examples/explore/brief/d1-naive.l4`, a 20-state graph, printed `frontier NOT exhausted: 6 new states past the state bound 5 not added` and exited 3 (measured 2026-11-23).
  The number is of states the bound kept out, each once; before that date the same run printed 12, because the code added one for each move that reached such a state.
- **An act could not be tried at an instant the scheme chose (exit 2).** The coverage line has `UNTRIED n` and the text before it names the act and why:
  - _an instant that is not a whole number_: a deadline in the file is a fraction (`WITHIN 2.5`), or a trace starts at one (`AT 0.5`) and a deadline counted from it falls on one, so an instant the scheme needs is not whole, and only whole instants, and the instant the clock already stands at, are tried.
    The line says so in its own words, `by default only whole instants, and the clock where it stands, are tried; --grid N tries the multiples of N`: with `--grid 0.5` the 2.5 is a multiple of the step and is tried (`half.l4` under `--grid 0.5` exits 0, measured 2026-11-24).
    `jl4/tests-cli/fixtures/explore-instants/half.l4` gives 3 states, 4 transitions and `UNTRIED 1` (measured 2026-11-22);
  - _the instant cap_: one act in one state would need more than `--max-instants` instants (256 unless you say otherwise), which a grid reaches quickly: `--grid 1` on an obligation that is `WITHIN 365` needs 366;
  - _the grid's end_: with `--grid`, no deadline and no `--until`, so the clock has no end to try up to; or a clock, deadline or window opening that is not a multiple of the step.
    `--grid 1` with no `--until` used to exit 0 on such a contract; it now exits 2, which is a change to say plainly (2026-11-22).
  - _a tie through a chain of acts_: an act that starts a deadline sets the limit for the next act, so where the first act falls decides whether the second can tie with a deadline already fixed.
    The line names the acts and the instants that could put such a tie in reach (`ties through chains of acts, for PARTY U DOES u, …`), and says `--chains` tries them.
    `jl4/tests-cli/fixtures/explore-instants/room.l4` gives 308 states and `UNTRIED 5` by default (the chain, and four norms behind a breach) and 366 states and `UNTRIED 4` under `--chains` (measured 2026-11-23).
    This is a change to say plainly: the explorer before these changes printed `nothing untried` and exited 0 on that file (244 states, measured 2026-11-23).
- **A property is violated (exit 4)**, or **unknown (exit 5)**: every liveness property, and any path that fails its replay.
- **An option names nothing (exit 1).** A property that is not a rule in the file or its imports; one that takes no inputs, or that reads a ledger itself (a `RECALL` inside it would read nothing, outside a run); a `--contract` that is not a rule with no inputs; a `--fair` that names no act; an `--until` earlier than the outset (`--until 0 is before the outset at 64800, so no act could fire`); a property, `--emit` or `--fair` asked of a file with no `#TRACE` and no `--contract`.
- **A property input is named for a cell nothing writes (exit 1).**
  The error names the property and the cell, and says to correct the name or to name the cell with `--unwritten`.
  On `jl4/examples/explore/brief/d1-naive.l4`, `dinners cancelled` is such a cell for the properties `at most one dinner is bought` and `one dinner is bought`, because none of the brief's designs cancels a purchase.
  A run that names either property says `--unwritten 'dinners cancelled'`, and then explores as before.
  A misspelt `--unwritten` leaves the real refusal in place, since it lifts only the cell it names.
  Nothing is refused in a file where some write names its cell by an expression that is not a literal, because any cell may be written there.

### Silent unless you read the output: the exit status can be 0, and the JSON says `complete`

These are all in the output, on the coverage line or the property's own line, and a script keyed on the exit status alone misses every one of them.

- **Write-only cells dropped.** A ledger cell that is written and never read is not in the state.
  Run the dinner example without naming the property:

  ```bash
  l4 explore explore-example.l4 --until 100
  ```

  It gives 7 states and 7 transitions and exits 0, and its coverage line says ``write-only cells dropped: OFFICIAL's `open at acceptance` ``.
  Two histories have become one state: `s3 -> s6` is Alice buying after Bob's purchase (the bad one), and `s4 -> s6` is Bob buying after Alice's (the good one).

  ```text
  Transitions (7):
    s0 -> s1  PARTY World DOES `Alice checks whether dinner is bought`
    s0 -> s2  PARTY World DOES `Bob buys dinner`
    s1 -> s3  PARTY World DOES `Bob buys dinner`
    s1 -> s4  PARTY World DOES `Alice buys dinner`
    s2 -> s5  PARTY World DOES `Alice checks whether dinner is bought`
    s3 -> s6  PARTY World DOES `Alice buys dinner`
    s4 -> s6  PARTY World DOES `Bob buys dinner`
  ```

  Name the property and the explorer keeps the cells it reads, and the same run has 8 states and exits 4, as above.
  `--keep CELL` and `--keep-latest CELL` keep a cell without naming a property.
  `--emit DIR` with no property named keeps the cell that every property of the file or its imports reads, and lists them on standard error, because the emitted model goes to a checker whose properties the run cannot see.
  A property is any rule that gives a `BOOLEAN`, takes only `LIST` and `MAYBE` inputs named for cells, and reads no ledger itself.
  A cell that no write names is left out of the list: it is empty in every state, and keeping it changes nothing.
  `d1-naive.l4` with `--until 75600 --emit DIR` and nothing else writes a `.aut` of 12 states, and the same run without `--emit` is 10.
  With `--emit` and a property named, only that property's cells are kept.
  On the fixture `jl4/examples/explore/brief/d1-naive.l4` the difference is 10 states against 12.

- **Ticks cut by the clock bound.** With `--until 100` the explorer does not take the move to just past the closing time.
  The line says `8 ticks past the clock bound not taken` and the JSON says `"complete": true`.
  "Complete" is relative to the bound you gave.
- **A property reads a cell that no state explored writes.** The property's line says `never written in any state explored`.
  The file's text does write the cell (a cell that no write names is refused, above), but no state the exploration reached has it written, so the property reads an empty cell and can hold vacuously.
  The verdict is `holds` and the exit status is 0.
- **Compared by name only; compared by printed form.** The clauses in the coverage table that appear only when they apply.
  Each means two positions that differ in one value could be merged.
  None of the files on this page produces them, so what they say here is taken from the explorer's source and not from a run.

### Silent: not on the coverage line either

- **A `MUST` or `SHANT` pending in a one-party chain hides the other actors.** Every file on this page is a `MAY` at every point, which is the shape that works.
  While a `MUST` or `SHANT` is pending, the obligation waits for its one act, and an event of any other party is dropped by the evaluator.
  The explorer reproduces that faithfully, which is the trouble: in those states there is no arrow for the other actors, and nothing on the line says so.
  Measured 2026-10-26, by adding to the example a payment Alice owes the restaurant within 5 after her purchase (`PARTY World MUST` an act `Alice pays the restaurant`, `WITHIN 5`).
  In the explored graph there is no `Bob buys dinner` arrow out of a state where the payment is pending.
  The explorer offers there only the act the pending obligation names, so the other actors' acts are neither arrows nor part of the `acts passed over` count.
  Under `l4 run`, a trace in which Bob's purchase is recorded while the payment is pending never records it (`taken` is absent from the official record), and one in which it is recorded after the payment does.
  So the graph of such a contract is the graph of a world in which Bob cannot buy while Alice owes the restaurant, and a property checked on it is checked on that world.
  Keep the recurring permission a `MAY` throughout, as the files on this page do.
- **A deadline that names an imported rule reading a ledger.** Only the rules of the file itself are checked for a `RECALL` before a deadline is worked out.
  A deadline that names a rule of an imported file that reads a ledger is worked out as if the ledger were empty: with `` `recorded period` MEANS fromMaybe 10 (RECALL `period`) `` in an imported file, `` WITHIN `recorded period` `` explores as `WITHIN 10`, 3 states, exit 0 (measured 2026-11-25).
  That is the right deadline only while nothing has recorded `period` by the time the deadline is read.
  When a deadline worked out this way is later than the one the run would use, the tick past it shows the breach and is labelled with the wrong deadline, and nothing says so (read from the code, not measured); when it is earlier, the tick shows nothing and is listed as untried.
  Define such a rule in the file that uses it, where it is caught.
- **Two rules of one name.** When two sections each define a rule called `NAME`, `--contract NAME` explores the first in the file and says nothing about the other; `l4 lts --contract` lists the same one.
  Give one of them another name to explore it.
- **No `#TRACE` and no `--contract`.** `Nothing to explore: the file has no #TRACE directive.` is printed on standard output and the exit status is 0, so a script that reads only the status sees a green run in which nothing ran.
  When a property, `--emit` or `--fair` was asked for, the status is 1 instead, because none of them could be answered.
- **An always-false guard.** An act whose guard never holds is passed over in every state, so it appears in no state and no arrow, and the only trace of it is the `acts passed over` count, which does not say which.
  The same count includes the ordinary pass-overs of a recurring permission (a purchase after the dinner is bought).
  Read the transitions for the acts you expect.
- **An event that no obligation offers.** The graph is the graph of the contract's own rules.
  If Bob's purchase is not written into the contract, no exploration varies it, and no line says it was left out.
  The cure is to write it in, as `explore-example.l4` does.
- **The times in a counterexample.** See above: the order is real and the clock times are the outset's.
- **Where the region scheme stops being exact.** Positions that differ only in the clock are merged under `time by regions` when the same deadlines have passed and the deadlines and openings come in the same order, and an act is tried only at the instants where something can change.
  Both are right while no guard reads the clock arithmetically, or compares it against a value the contract recorded, and the explorer does not check that none does.
  The line names the scheme and that is all it does.
  What it does say, loudly (exit 2): a tie that needs a chain of acts (above), a deadline or window opening that is not a whole number, and a state that needs more instants than the cap.
  What it does not say: an act whose behaviour changes at some instant for a reason that is neither a deadline nor a window opening, and a window opening the explorer cannot read (an `AFTER` that names a date).
  Two cases a review found (2026-11-23) were silent and are now handled, and are listed so that the next one is looked for in the same places.
  A deadline started by a lapse (a `LEST` that arms a cure) is not started by an act, so no act's own offset named the tie it makes.
  Ticks are now read the way an act's successors are: what a lapse arms is learned at the tick that reveals it, and the acts tried in that state are tied with it, whether the deadline that lapsed was started by an act or was fixed at the outset (a second review found the fixed case still silent, 2026-11-23).
  A tie that needs a chain of acts through a lapse is named by default and searched by `--chains`, like any other chain.
  An act whose own deadline lapses is tied with the cure that lapse arms, in the chain note as in its instants: the cure exists only if the act is never done, unless the act's continuation arms the same deadline and the same cure again, and then the tie is real and only a chain reaches it (a case a review found, `succ4.l4`).
  The explorer cannot tell the two apart without one more step of lookahead, so the note is raised for both and `--chains` clears the one that is not real: a loud false alarm, chosen over a silent miss (`own-lapse.l4` is the one that is not real).
  Checked against the enumeration of every act at every whole instant, by default and under `--chains`: the lapse of a deadline fixed at the outset (the cure of a lapse at 6 that an act ties with, including inside an `EVERY` fork and an `EVERY` barrier, a cure anchored to `THE DEADLINE`, and an act whose continuation arms the same deadline and the same cure again), and two lapses in a row from one when the act is done after the first lapse.
  Checked under `--chains` (by default the chain it needs is named, exit 2): a lapse of a deadline an act started, a recurring rent with a guarantor's cure, and an outset that is a literal date serial.
  Not checked, and silent: (1) two lapses in a row from a deadline fixed at the outset when the act is done BEFORE the first lapse, because the tie is with the cure of the second lapse, which no state the act is tried in has seen yet; (2) a state whose text is the same at every clock although it holds an instant fixed in absolute time (a `WITHIN 10 OF 0` anchor, running or not, or the cure a lapse will arm) beside a fresh countdown: neither clock can do everything the other can, and only an earlier one is explored again; (3) a lapse whose cure reads the clock arithmetically.
  For (1) and (2) the graph misses positions and the coverage line says `nothing untried`, by default and under `--chains`. The exception is a contract in which a chain is also left out: its note then says that `--chains` does not reach them and that `--grid 1` tries every whole instant up to a deadline or `--until`, but a contract without such a chain gets no warning. On the contracts that showed them (two lapses in a row; `WITHIN 10 OF 0` under a later branch, and the same anchor already running beside a fresh countdown; a cure armed by a lapse) `--grid 1` missed none (measured 2026-11-23), and where its window has no end it names the act whose grid points it could not finish.
  Two positions with one state key can be at different clocks, and a deadline anchored in absolute time prints the same at every clock, so the later one first found stood for the earlier one, which can still do more: a state reached again at an earlier clock is explored again from there.
  The converse is not covered: a state first reached at an earlier clock and again at a later one is not explored again, and the later clock can do more when the state holds an instant fixed in absolute time that its text does not count down, beside a fresh countdown (the second gap above).
  (Read from the code, not measured, 2026-11-22: a deadline the explorer cannot read is listed as untried, so that case is loud; an opening it cannot read is left out without a word.)
  The exact graph, for a contract small enough, is `--grid 1`.

## What the graph is not

- It is **not `l4 state-graph`**.
  That command draws the shape of one rule, from every `HENCE` and `LEST` in it, and does not run the contract, so it can draw an arrow that no run takes.
  See [State graph](STATE-GRAPH.md).
  `l4 explore` draws only what runs.
- It is **not a position marked on a map**.
  `l4 lts` says where one trace stands; `l4 explore` says where every path can stand.
  A picture of one position marked on the shape of the rule, "you are here", is still only designed, not built (the Limits section of the page on `l4 lts` says so).
- It is **not a proof for a contract it could not finish**.
  A graph that stopped at a bound, or refused an act, or left a move untried, is a graph of part of the contract, and the coverage line is how you know which part.
- It **does not decide liveness**.
  "Eventually" needs cycles under a fairness assumption, which a model checker does and this does not.
  The states are labelled, and `--emit` hands them over.
- It **does not pick an ordering**.
  Alice's check and Bob's purchase can come in either order, and both orders are paths.

## Related pages

- **[What is owed now: `l4 lts`](lts-list.md)**: one position, as a list, and the candidates the explorer tries from every position
- **[State graph and `--dominators`](STATE-GRAPH.md)**: the shape of a rule, drawn from its `HENCE` and `LEST`
- **[Regulative rules](README.md)**: the keywords, and `#TRACE`
- **[Deadlines and consequences](consequences.md)**: `WITHIN`, `HENCE`, `LEST`, and `RAND`/`ROR`
