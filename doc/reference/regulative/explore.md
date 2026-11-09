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
(One exploration is made for each distinct contract and starting day among the file's traces.
To explore a rule no trace names, give `--contract NAME`, with `--at T` for the day it starts, 0 if left out.)

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
      `WAIT UNTIL` OF 4
    ledgers: nothing kept
s3  depth 2, residual r3, terminal
    first reached by:
      PARTY Seller DOES delivery AT 0
      PARTY Buyer DOES payment OF 100 AT 0
    ledgers: nothing kept
s4  depth 2, residual r4
    first reached by:
      PARTY Seller DOES delivery AT 0
      `WAIT UNTIL` OF 8
    ledgers: nothing kept
s5  depth 3, residual r5, terminal
    first reached by:
      PARTY Seller DOES delivery AT 0
      `WAIT UNTIL` OF 8
      `WAIT UNTIL` OF 22
    ledgers: nothing kept

Transitions (9):
  s0 -> s1  PARTY Seller DOES delivery
  s0 -> s2  time passes the deadline 3 (WAIT UNTIL 4)
  s1 -> s3  PARTY Buyer DOES payment OF 100
  s1 -> s4  time passes the deadline 7 (WAIT UNTIL 8)
  s2 -> s2  terminal
  s3 -> s3  terminal
  s4 -> s3  PARTY Buyer DOES payment OF 120
  s4 -> s5  time passes the deadline 21 (WAIT UNTIL 22)
  s5 -> s5  terminal

Residuals (6):
  r0  PARTY Seller MUST delivery WITHIN 3 HENCE (…)
  …

Coverage: 6 states, 9 transitions; frontier exhausted; nothing refused; nothing untried; 0 acts passed over; no write-only cell dropped; time by regions (the instant of the last event, one between it and the next deadline, the deadline; the clock is not in the state)
```

Reading it from the top:

- **A state** is a position, numbered in the order the explorer found it.
  `s0` is the outset.
  `depth` is the number of events on the shortest path that reaches it, and `first reached by` is that path, written as a `#TRACE` writes events.
  A state may be reached by other paths too; only the first is printed.
- **A transition** is one move the contract took: an act by the party who owes it, or time passing.
  `s0 -> s2` is the seller missing the delivery deadline of day 3: the explorer lets the clock run to just past the deadline (`WAIT UNTIL 4`) with nothing happening, and the contract answers that the seller is in breach.
  A deadline passing is a move like any other.
- **A terminal state** is one where nothing more can happen: here `s2` (the seller is in breach), `s3` (fulfilled) and `s5` (the buyer is in breach).
  The explorer gives each one a self-loop labelled `terminal`, so that a tool reading the graph does not take it for a deadlock.
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
4. **Which of the live deadlines the clock has already passed.** The clock itself is not kept (unless you ask for `--grid`, below).

Two positions that agree on all four are merged into one, and that is what makes the exploration stop.
A contract that renews itself would otherwise never finish: each lap would be a new position.
The merge is also the one place the graph can quietly be wrong, and [the failures below](#loud-and-silent-failures) are mostly about it.

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
An act is tried at three instants: the instant of the last event; one instant halfway between that and the earliest live deadline; and that deadline itself.
It is never tried past `--until`, and never past a live deadline, because the contract would expire the deadline first and the arrow would carry the act's name for the deadline's effect.
With no live deadline and no `--until`, the instants are the last event and one after it.
The boundaries matter: a rule that treats an act at exactly the deadline differently from one just before it is only visible if the explorer tries the deadline itself.
The coverage line says which scheme was used (`time by regions`).
`--grid N` is the alternative, for a rule whose guard reads the clock arithmetically: it tries acts on multiples of N and keeps the clock in the state, which is sound only when every event time and deadline is a multiple of N.
(On the dinner example below, `--grid 50` gives 20 states against 8, since the clock now tells states apart; measured 2026-10-26.)

**How far.**
Exploration is breadth first and every move is a full re-run of the contract, so a large contract takes time in proportion to its states.
`--until T` bounds the clock: no event later than T, and a tick past T is not taken.
`--max-depth N` (default 100) stops expanding states reached by more than N events, and `--max-states N` (default 10000) stops adding states.

## The coverage line

Every run ends with one line that says how much of the contract the graph covers.
A graph without it is a picture without a scale.
Here it is for the sale, with each clause labelled:

| clause                                                                                                  | what it says                                                                                                                                                                                     | when it is not the quiet form                                                                                                                                                                                                          |
| ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `6 states, 9 transitions`                                                                               | the size of the graph                                                                                                                                                                            |                                                                                                                                                                                                                                        |
| `frontier exhausted`                                                                                    | every state found was expanded, and no new one turned up                                                                                                                                         | `frontier NOT exhausted: …` names the bound that stopped it, `--max-depth` or `--max-states`, and a count of the states it left; for `--max-states` the count is of refusals, so a state reached twice is counted twice. Exit status 3 |
| `nothing refused`                                                                                       | every act the rules leave open was listed                                                                                                                                                        | `REFUSED n: …` names each variable, its type and the field. Exit status 2                                                                                                                                                              |
| `nothing untried`                                                                                       | every move offered could be run                                                                                                                                                                  | `UNTRIED n: …` names each move and why it could not be run. Exit status 2                                                                                                                                                              |
| `0 acts passed over`                                                                                    | how many (state, act) pairs the contract declined at every instant tried. A declined act is no arrow                                                                                             | a count only: it does not say which acts                                                                                                                                                                                               |
| `no write-only cell dropped`                                                                            | no ledger cell was thrown away from the state                                                                                                                                                    | `write-only cells dropped: …` names the ledger cells that were written and never read. Positions that differ only in those cells are one state                                                                                         |
| `time by regions (…)`                                                                                   | which way of choosing instants was used (the section above), and, with `--until`, `clock bounded at T`; with a bound, `n ticks past the clock bound not taken` says how many moves the bound cut | `time on a grid of N (the clock is in the state)` with `--grid`                                                                                                                                                                        |
| _(only when present)_ `compared by name only: …`                                                        | a residual held a local value the run never worked out, so two positions that differ only in it would be merged                                                                                  | it names each such local                                                                                                                                                                                                               |
| _(only when present)_ `n ledger values compared by printed form`, `answers compared by printed form: …` | a ledger value, or a rule's answer, has no literal form (a function, say), so the state compares how it prints                                                                                   | two different values that print alike would be merged                                                                                                                                                                                  |

Two cautions on reading it.
**"Frontier exhausted" does not mean complete.**
It says only that every state the explorer found was expanded.
A run with `REFUSED 1` or `UNTRIED 2` prints it too, beside the clause that says the graph is partial.
**"Complete" in `--json` does not mean faithful.**
The `complete` flag in the JSON is true when nothing was refused, nothing untried and the frontier was exhausted.
It is true with ticks cut by `--until`, and true when write-only cells merged states, as the next section shows.

## The exit status

The exit status is for scripts, so that a CI job cannot read a partial run as a green one.

| status | means                                                                                                                                                                                                                                                                                                                                    |
| ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0      | the frontier was exhausted with nothing refused and nothing untried, and every property named holds                                                                                                                                                                                                                                      |
| 1      | the file does not type-check; an option names nothing (a property, a `--contract`, a `--fair`); a property input named for a cell nothing writes; an `--until` before the outset; a property, `--emit` or `--fair` asked of a file with nothing to explore; a contract cannot be run at its outset; an emitted file could not be written |
| 2      | an act was refused, or a move could not be tried                                                                                                                                                                                                                                                                                         |
| 3      | nothing refused or untried, but `--max-depth` or `--max-states` stopped the exploration                                                                                                                                                                                                                                                  |
| 4      | a property is violated (its counterexample is printed, and is real whatever else the run did)                                                                                                                                                                                                                                            |
| 5      | the exploration was complete but a property's verdict is unknown (every liveness property)                                                                                                                                                                                                                                               |

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

Coverage: 8 states, 7 transitions; frontier exhausted; nothing refused; nothing untried; 17 acts passed over; 8 ticks past the clock bound not taken; no write-only cell dropped; time by regions (the instant of the last event, one between it and the next deadline, the deadline; the clock is not in the state), clock bounded at 100
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
- **A bound stopped it (exit 3).** `frontier NOT exhausted`, with the number of states left.
  `--max-states 5` on `jl4/examples/explore/brief/d1-naive.l4`, a 10-state graph, printed `frontier NOT exhausted: 9 new states past the state bound 5 not added` and exited 3.
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
- **No `#TRACE` and no `--contract`.** `Nothing to explore: the file has no #TRACE directive.` is printed on standard output and the exit status is 0, so a script that reads only the status sees a green run in which nothing ran.
  When a property, `--emit` or `--fair` was asked for, the status is 1 instead, because none of them could be answered.
- **An always-false guard.** An act whose guard never holds is passed over in every state, so it appears in no state and no arrow, and the only trace of it is the `acts passed over` count, which does not say which.
  The same count includes the ordinary pass-overs of a recurring permission (a purchase after the dinner is bought).
  Read the transitions for the acts you expect.
- **An event that no obligation offers.** The graph is the graph of the contract's own rules.
  If Bob's purchase is not written into the contract, no exploration varies it, and no line says it was left out.
  The cure is to write it in, as `explore-example.l4` does.
- **The times in a counterexample.** See above: the order is real and the clock times are the outset's.
- **Where the region scheme stops being exact.** Positions that differ only in the clock are merged under `time by regions`, which is right while no guard reads the clock, and the explorer does not check that none does.
  The line names the scheme and that is all it does.

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
