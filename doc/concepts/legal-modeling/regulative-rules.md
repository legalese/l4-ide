# How obligations unfold

A regulative rule says who must, may or must not do what, by when, and what follows. This page explains how such a rule behaves over time: what it waits for, how it moves forward, and what it can end in. For the keywords themselves, see the reference: [Regulative rules](../../reference/regulative/README.md), [PARTY, MUST, MAY, SHANT](../../reference/regulative/PARTY.md) and [Deadlines and consequences](../../reference/regulative/consequences.md).

> **Reading order.** If you would rather start from one lease and one screen at a time, the tutorial series [One Obligation](../../tutorials/obligations/one-obligation.md) → [What Follows](../../tutorials/obligations/what-follows.md) → [Several Parties](../../tutorials/obligations/several-parties.md) builds the same material up in that order, and [The Regulative Layer, Whole](regulative-layer-whole.md) lays out how the separate ideas behind regulative rules fit together and which are still proposed.

Regulative rules sit beside constitutive rules, which define what things are. A constitutive rule answers "is the borrower a small business?". A regulative rule answers "what does the borrower have to do now, given everything that has happened so far?". [Definitions and duties](constitutive-vs-regulative.md) explains why L4 keeps the two apart.

---

## A contract awaiting events

This is the most important idea in the regulative part of L4, and the one most often missed:

> **A regulative rule decides nothing by itself. It is a contract that waits until it is given a start time and a sequence of events.**

A `DEONTIC` value behaves like a function of two inputs:

```
contract  ×  (start time, events)  →  verdict
```

- The **start time** places "now" on a timeline. Deadlines and event times are measured on the same timeline.
- The **events** are what actually happened, in order. Each records who acted, what they did, and when.
- The **verdict** is `FULFILLED`, a breach, or a _residual obligation_: the contract, partly advanced and still waiting.

So a regulative rule is more than a yes-or-no check. It watches a timeline, moves forward as events arrive, and keeps enough state to be resumed later.

**Example:** [delivery-obligation.l4](delivery-obligation.l4)

The four `#TRACE` runs in the example give four different results from one rule:

| Events                         | Result                                                  |
| ------------------------------ | ------------------------------------------------------- |
| The seller delivers on day 10  | `FULFILLED`                                             |
| The next event is on day 20    | `BREACH BY` the seller, with the reason given in `LEST` |
| The buyer "delivers" on day 10 | A residual obligation: the seller must deliver within 4 |
| No events                      | A residual obligation: the rule itself, still waiting   |

The last two rows surprise most people. A missing event is not a breach. Nothing has happened yet that shows the deadline passed, so the contract is still open.

---

## Events and the timeline

An event is a triple:

```
(party, action, time)
```

> **The party must be the action's performer.** When actors are modelled as values and actions carry their actor(s), a `PARTY p DOES a` event — and a `PARTY p MUST a` obligation — is rejected at type-check time unless `p` is the action `a`'s _performer_. So `PARTY Drinker DOES eat` does not type-check if `eat`'s performer is the Eater. See [Actors, Actions, and Agreement](actors-and-actions.md) for the full rule (the subject-first canon, duplex actions, parameterised actions, and higher-order procurement).

The contract reads events in order. With each event, two things move: the contract's clock advances to the event's time, and the remaining window of the current `WITHIN` shrinks by the time that has passed. Then:

- If the event comes **after the deadline**, the contract takes the branch for a missed deadline, without looking at what the event was.
- If the event is **in time and matches** the duty (right party, right action, any `PROVIDED` condition true), the contract takes the branch for the action being done.
- If the event is **in time but does not match**, it is skipped. The next event is tried, with the clock further on.

If the event's action holds a fact the case has not supplied, at a place where the action written in the `MUST`, `MAY` or `SHANT` line names one particular kind of thing — a delivery of goods of a kind nobody has stated, against `MUST Deliver Retail` — the contract cannot tell whether it matches, so the run stops and names the missing fact rather than skipping the event. An event that plainly cannot match, whatever that fact turns out to be, is still skipped: a different action, or a quantity written out as a number that differs from the number the obligation writes, as long as everything between the missing fact and that number is written out too. Where the run would have to work something out first to see the mismatch, it stops instead.

The same holds when the missing fact is checked by a rule that uses `CONSIDER`, whether in the action or in a `PROVIDED` condition: an `OTHERWISE` line is not taken just because the fact is missing, so where a line before it could still match, the run stops and names it.

For `MUST`, doing the action leads to `HENCE` and a missed deadline to `LEST`. For `MAY`, both lead to `HENCE`, because not using a permission is no breach. A prohibition, `SHANT`, turns `MUST` around: doing the forbidden act leads to `LEST`, and reaching the deadline without it leads to `HENCE`. In every case, `HENCE` names the outcome the law wants, and `LEST` the one it does not. `DO` is the bare form, with no modal word; on the current release it behaves exactly as `MUST` does — the same defaults, and the same outcomes when the action is taken and when the deadline passes.

The timeline is just numbers. It can stand for days, hours or business days, as long as deadlines and event times use the same unit.

A plain `WITHIN` window starts when its obligation becomes active. In a chain, under `HENCE` the next duty's window starts at the act that completed the one before: if the buyer confirms an order on day 10 and the seller then has `WITHIN 5`, the seller's deadline is day 15. Under `LEST`, the window starts from the outer obligation's failure — the deadline that was missed for a `MUST`, `DO` or `MAY`, the forbidden act itself for a `SHANT` — and not from whatever later event brought the miss to light. A deadline can also be anchored outright, with `WITHIN d OF THE JOIN`, `OF THE DEADLINE`, `OF THE ARMING` or `OF` an instant; [Deadlines and consequences](../../reference/regulative/consequences.md#anchoring-a-deadline-with-of) has the table.

A window can also have an _opening_ edge — _after a three-day cooling-off period, within 30 days_ is `AFTER 3 WITHIN 30`, and an act before the window opens does not count (the run says so) — and either edge has an absolute form: `AFTER (YMD 2026 6 1)`, `BEFORE (YMD 2026 12 31)`. `WITHIN` takes a duration and `BEFORE` a date, as in English. A date lands on the contract's clock only when the trace is stamped in date serials; on a trace that starts at 0 it is refused by name rather than silently misread. The [AFTER](../../reference/regulative/AFTER.md) page has the two readings of a two-edged window and the limit in full.

---

## Three possible outcomes

After a contract has read its events, it is in one of three states.

**`FULFILLED`.** Every duty was discharged. Nobody has anything left to do under this contract.

**Breach.** A party failed a duty, or did something forbidden, and no fallback took over. The breach records who breached and, if `BECAUSE` was used, why. That reason is what a reviewer or a downstream system reads, so it is worth writing.

**A residual obligation.** The events ran out before the contract was fulfilled or breached. The result is a new `DEONTIC` value: the contract in its current state, with the clock where the events stopped, any `WITHIN` window shortened, and any chain ready to resume from its current step. It is a first-class value, so you can:

- inspect it: what is still owed, by whom, and how much time is left?
- store it, to keep a long-running contract between sessions;
- give it more events later, to resume where it left off.

This is what makes L4 a contract language rather than only a checking language. A contract can be partly performed and picked up again at any time.

> **Sidebar:** the word _residual_ leads parallel lives in economics (residual control rights, the incomplete-contracts work behind the 2016 Nobel Prize) and in public law (residual discretionary powers — who decides when the statute runs out). The three senses illuminate each other: see [Residual: One Word, Three Disciplines](residual.md).

---

## Chains, fallbacks and repeating duties

Larger contracts are built by putting rules inside rules.

- **Chains.** `HENCE` can name another obligation: once the seller delivers, the buyer must pay. One stream of events runs through the whole chain, and each step starts reading where the last one stopped.
- **Fallbacks.** `LEST` can name another obligation instead of a breach: pay on time, or pay more within a further period. This is how reparation, penalties and grace periods are written. The contract walks down the fallbacks until something is fulfilled, or a step with no fallback is missed and breaches.
- **Repeating duties.** A function can return the next period's obligation and call itself in `HENCE`, so instalments or periodic reports need no fixed-length list of steps.
- **Parallel duties.** `RAND` runs two obligations side by side and needs both; `ROR` needs either.

[Deadlines and consequences](../../reference/regulative/consequences.md) gives the syntax and the exact rules for each.

---

## The lifecycle

```
                  ┌──────────────────────────┐
                  │      Contract starts     │
                  │ (with a start time and   │
                  │  an event stream)        │
                  └────────────┬─────────────┘
                               │
                               ▼
                  ┌──────────────────────────┐
                  │   Awaiting next event    │◄─────┐
                  └────────────┬─────────────┘      │
                               │                    │
              ┌────────────────┼────────────────┐   │
              ▼                ▼                ▼   │
        ┌──────────┐    ┌─────────────┐  ┌────────────────┐
        │ Matching │    │  Deadline   │  │ Non-matching   │
        │  event   │    │   passes    │  │  event arrives │
        │ arrives  │    │             │  │                │
        └────┬─────┘    └──────┬──────┘  └──────┬─────────┘
             │                 │                │
   (MUST/MAY: HENCE)   (MUST: LEST,            │
   (SHANT:    LEST)     SHANT/MAY: HENCE)      │
             │                 │           (skip, try next ─┘
             ▼                 ▼            with clock advanced)
       ┌──────────┐      ┌──────────┐
       │  HENCE   │      │   LEST   │
       │  branch  │      │  branch  │
       └────┬─────┘      └────┬─────┘
            │                 │
            ▼                 ▼
   ┌────────────────────────────────────┐
   │   FULFILLED  /  BREACH  /  another │
   │  obligation (which becomes the     │
   │  new waiting state — go to top)    │
   └────────────────────────────────────┘
```

If the events run out before the loop ends, the contract in progress is returned as a residual obligation.

---

## Running a contract

`#TRACE` runs a contract from a start time against a fixed list of events and reports the verdict, as in the example above. The same thing is available as a function, `EVALTRACE`, whose type states the mental model directly:

```
EVALTRACE  :  DEONTIC party action          -- the contract
           →  NUMBER                        -- start time
           →  LIST OF EVENT party action    -- events
           →  DEONTIC party action          -- the result: finished or residual
```

To advance a long-running contract step by step, call `EVALTRACE` again on the residual from the previous call, starting at the time where the previous events stopped. [EVENT](../../reference/regulative/EVENT.md) shows how to build the event list.

To see every path a rule can take rather than one run of it, `l4 state-graph` draws the rule as a graph of states, deadline transitions and the terminal `FULFILLED` and `BREACH` nodes. In the editor, **Show state graph** above a regulative rule opens the same graph in a pane; the [state graph reference page](../../reference/regulative/STATE-GRAPH.md) says how to read it and what it does not show.

---

## Further reading

- [One Obligation](../../tutorials/obligations/one-obligation.md), [What Follows](../../tutorials/obligations/what-follows.md), [Several Parties](../../tutorials/obligations/several-parties.md) and [What Is Coming](../../tutorials/obligations/what-is-coming.md): the tutorial series, one tenancy and one screen at a time.
- [The Regulative Layer, Whole](regulative-layer-whole.md): how the separate ideas fit together, and which are proposed rather than built.
- [Module 6: Regulative rules](../../courses/foundation/module-6-regulative.md): writing and testing regulative rules step by step.
- [Regulative rules](../../reference/regulative/README.md), [PARTY, MUST, MAY, SHANT](../../reference/regulative/PARTY.md) and [Deadlines and consequences](../../reference/regulative/consequences.md): the keyword reference.
- [DEONTIC](../../reference/regulative/DEONTIC.md): the type of a regulative rule.
