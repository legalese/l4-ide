# How obligations unfold

A regulative rule says who must, may or must not do what, by when, and what follows. This page explains how such a rule behaves over time: what it waits for, how it moves forward, and what it can end in. For the keywords themselves, see the reference: [Regulative rules](../../reference/regulative/README.md), [PARTY, MUST, MAY, SHANT](../../reference/regulative/PARTY.md) and [Deadlines and consequences](../../reference/regulative/consequences.md).

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

The contract reads events in order. With each event, two things move: the contract's clock advances to the event's time, and the remaining window of the current `WITHIN` shrinks by the time that has passed. Then:

- If the event comes **after the deadline**, the contract takes the branch for a missed deadline, without looking at what the event was.
- If the event is **in time and matches** the duty (right party, right action, any `PROVIDED` condition true), the contract takes the branch for the action being done.
- If the event is **in time but does not match**, it is skipped. The next event is tried, with the clock further on.

For `MUST`, doing the action leads to `HENCE` and a missed deadline to `LEST`. For `MAY`, both lead to `HENCE`, because not using a permission is no breach. A prohibition, `SHANT`, turns `MUST` around: doing the forbidden act leads to `LEST`, and reaching the deadline without it leads to `HENCE`. In every case, `HENCE` names the outcome the law wants, and `LEST` the one it does not.

The timeline is just numbers. It can stand for days, hours or business days, as long as deadlines and event times use the same unit.

A `WITHIN` window starts when its obligation becomes active. In a chain, the next duty's window starts at the event that fulfilled the one before: if the buyer confirms an order on day 10 and the seller then has `WITHIN 5`, the seller's deadline is day 15. There is no syntax for counting a deadline from some other named event, and none for a deadline on a fixed date; build the timing by chaining obligations with `HENCE`.

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

---

## Further reading

- [Module 6: Regulative rules](../../courses/foundation/module-6-regulative.md): writing and testing regulative rules step by step.
- [Regulative rules](../../reference/regulative/README.md), [PARTY, MUST, MAY, SHANT](../../reference/regulative/PARTY.md) and [Deadlines and consequences](../../reference/regulative/consequences.md): the keyword reference.
- [DEONTIC](../../reference/regulative/DEONTIC.md): the type of a regulative rule.
