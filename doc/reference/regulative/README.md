# Regulative Rule Keywords

Regulative keywords express legal obligations, permissions, prohibitions, and their consequences. They form the core of L4's contract and regulation modeling.

> **See also:** [Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md) — how L4 decides _who may perform which action_ (the performer/agreement rule, duplex actions, `EXACTLY`-applied parameterised actions, and higher-order procurement), with worked ✅/❌ examples.

## Overview

### Deontic Modalities

| Keyword           | Meaning                    |
| ----------------- | -------------------------- |
| [MUST](MUST.md)   | Obligation (required)      |
| [MAY](MAY.md)     | Permission (allowed)       |
| [SHANT](SHANT.md) | Prohibition (forbidden)    |
| MUST NOT          | Synonym for SHANT          |
| DO                | Bare form; behaves as MUST |

`DO` is the bare form, with no modal word. Measured on the current release, it behaves exactly as `MUST` does: the same defaults when `HENCE` or `LEST` is omitted (`FULFILLED` and `BREACH`), and the same outcomes when the action is taken and when the deadline passes.

**Types:** **[DEONTIC](DEONTIC.md)** - the regulative rule type; **[EVENT](EVENT.md)** - the event type consumed by traces

### Rule Structure

| Keyword               | Purpose                           |
| --------------------- | --------------------------------- |
| [PARTY](PARTY.md)     | Who has the obligation/permission |
| [EVERY](EVERY.md)     | Every member of a group has it    |
| WITHIN                | Temporal deadline (relative)      |
| HENCE                 | Consequence on fulfillment        |
| LEST                  | Consequence on breach             |
| PROVIDED              | Guard condition on action         |
| EXACTLY               | Exact value matching on action    |
| BREACH                | Terminal violation state          |
| [BECAUSE](BECAUSE.md) | Reason for breach                 |
| FULFILLED             | Terminal success state            |

### Parallel Obligation Combinators

| Keyword | Purpose                               |
| ------- | ------------------------------------- |
| RAND    | Parallel AND -- all must be fulfilled |
| ROR     | Parallel OR -- any one sufficient     |

### Planned Keywords

| Keyword | Purpose                      | Status          |
| ------- | ---------------------------- | --------------- |
| BEFORE  | Temporal deadline (absolute) | Not implemented |

## Basic Rule Structure

```l4
PARTY partyName
MUST/MAY/SHANT/DO action
WITHIN deadline
```

### Example

```l4
DECLARE Person IS ONE OF Alice, Bob
DECLARE Action IS ONE OF pay HAS amount IS A NUMBER

paymentObligation MEANS
  PARTY Alice
  MUST pay 100
  WITHIN 30
```

## WITHIN (Temporal Deadline)

Specifies a time duration within which an action must/may be performed.

### Syntax

```l4
PARTY ...
MUST action
WITHIN duration [OF anchor]
```

The duration is a `NUMBER` of clock units — the same units the trace's timestamps use (days, if the trace is stamped in days). Written alone, it counts from where the language puts it: an obligation at the top level counts from when it was entered; an obligation under a `HENCE` counts from the moment the previous obligation was completed; an obligation under a `LEST` counts, today, from the event that revealed the miss.

The duration can be anchored with `OF`, and then the deadline is **absolute**: the anchor's instant plus the duration, whatever the clock read when the obligation was entered. The anchor is one of:

| Anchor            | Names                                                                                           |
| ----------------- | ----------------------------------------------------------------------------------------------- |
| `OF THE JOIN`     | the instant the enclosing obligation's `HENCE` fired (under `HENCE` this is the default, named) |
| `OF THE DEADLINE` | the enclosing obligation's deadline (its `WITHIN`)                                              |
| `OF THE ARMING`   | the instant the enclosing obligation was entered                                                |
| `OF expression`   | an instant: a `NUMBER` on the trace's clock, or a `DATE`                                        |

"The enclosing obligation" is the one whose `HENCE` or `LEST` this obligation is the continuation of — the one it is attached to when it runs. Usually that is the obligation it is written under; but a continuation can also arrive as a value (a rule with `GIVEN k IS A DEONTIC …` that ends `HENCE k`, or a `WHERE` local), and then the anchors name the obligation it is handed to, not the one it was written under. It is the _nearest_ enclosing obligation: two levels down, `THE ARMING` is the middle obligation's arming, not the outermost rule's, so "within 10 days of this agreement" (below) works from one level down, where the phrase is written.

For a `MUST`, `DO` or `MAY`, the join is the act that completed it. For a prohibition (`SHANT`) that was kept, the `HENCE` fires when the machine _learns_ it was kept — the first event after its deadline, not the deadline itself — and `THE JOIN` is that instant, the same one an unanchored `WITHIN` counts from. To count from the day a prohibition was discharged, anchor to `THE DEADLINE`.

`THE` is a keyword; `JOIN`, `DEADLINE` and `ARMING` are matched by spelling in this one position and are not reserved, so a program may still name a value `DEADLINE`.

Inside the duration, `OF` is always the anchor — everywhere in it, not only at the front — so `WITHIN f OF x` means `f` anchored at `x`, and so does an `OF` inside an `IF` branch, an operator's operand or a `WHERE` in the duration. To apply a function there, bracket the call (`WITHIN (f OF x) OF THE JOIN`) or juxtapose its arguments (`WITHIN f x OF THE JOIN`); the checker's message says so when the duration turns out to be a function.

### Examples

**Example file:** [within-example.l4](within-example.l4) — these rules, each with a trace showing the deadline its anchor produces.

```l4
DECLARE Person IS ONE OF Buyer, Seller
DECLARE Action IS ONE OF pay HAS amount IS A NUMBER
                         deliver
closingDate MEANS 20

-- Simple deadline: 30 units from when the obligation is entered
GIVETH A DEONTIC Person Action
simple MEANS PARTY Buyer MUST pay 100 WITHIN 30

-- The cure period runs from when payment fell due, not from the day the
-- buyer finally paid
GIVETH A DEONTIC Person Action
cure MEANS
  PARTY Buyer MUST pay 100 WITHIN 30
  HENCE (PARTY Seller MUST deliver WITHIN 5 OF THE DEADLINE)
  LEST  BREACH

-- "Within 10 days of this agreement": counts from when the outer obligation
-- was entered, however long the buyer took to pay. (One level down only:
-- an obligation nested a level deeper would count from the seller's
-- arming, the nearest enclosing obligation.)
GIVETH A DEONTIC Person Action
`of this agreement` MEANS
  PARTY Buyer MUST pay 100 WITHIN 30
  HENCE (PARTY Seller MUST deliver WITHIN 10 OF THE ARMING)
  LEST  BREACH

-- An absolute deadline on the trace's own clock: due at 20 + 5 = 25
GIVETH A DEONTIC Person Action
absolute MEANS PARTY Seller MUST deliver WITHIN 5 OF closingDate
```

A unit word is ordinary L4, not syntax: `WITHIN 5 days OF THE DEADLINE` checks once `days` is defined (`GIVEN n IS A NUMBER GIVETH A NUMBER DECIDE n days IS n`). Until it is, the file fails — how depends on what else is in scope. In a file with no imports and no other mixfix definition, like the one above, `5 days` parses as an application and the checker reports _could not find a definition for the identifier `days`_; once any mixfix operator is in scope (after `IMPORT prelude`, say, or one `DECIDE a plus b IS …`), the parser only accepts operator words it knows, and stops at `days` with _unexpected days_. Either way the fix is the one-line definition.

An anchored deadline may already be in the past when the obligation is entered — `WITHIN 5 OF closingDate` on a contract that begins after `closingDate + 5`. That is not an error: the first event reveals the expiry, exactly as if the deadline had been missed by waiting.

### Dates as anchors

A `DATE` anchor is lowered to its serial (what `DATE_SERIAL` computes), so `WITHIN 0 OF (YMD 2026 6 30)` means _by 30 June 2026_ on a trace whose timestamps are date serials — start it `AT (DATE_SERIAL (YMD 2026 6 1))` and stamp its events the same way (`IMPORT daydate` for `YMD`). Nothing checks that the trace _is_ on that scale: a `DATE` anchor on a trace that starts `AT 0` counts from a serial in the hundreds of thousands, silently.

### Where an anchor is refused

The type checker refuses a lifecycle anchor where the position it names does not exist, and says so:

- `THE JOIN` and `THE DEADLINE` on an obligation that is not inside any `HENCE` or `LEST` — there is no enclosing obligation. `THE ARMING` is allowed there: it is the obligation's own arming, which is the default.
- `THE JOIN` under `LEST` — the enclosing obligation was not completed, so its join never fired.
- `THE DEADLINE` where the enclosing obligation has no `WITHIN` at all.
- An `OF` expression that is neither a `NUMBER` nor a `DATE`.

The checker sees only where an anchor is _written_. A top-level rule referenced by name inside a `HENCE` (`HENCE cure`), and a `WHERE` local, are checked where they are written — outside any `HENCE` or `LEST` — and so cannot use `THE JOIN` or `THE DEADLINE`: write the anchored obligation inline under the `HENCE`. `THE ARMING` is accepted there, and when the rule runs it names the arming of the obligation the continuation is attached to (its own, when there is none), so factoring an inline continuation out into a `WHERE` does not move its deadline.

Two refusals only a run can make, because the checker cannot see them, are reported when the rule runs, naming the cause:

- `THE DEADLINE` in the `HENCE` of a barrier (`ONCE ALL HAVE`) whose group turned out to be _empty_ and whose `ONCE` line has no `WITHIN` — nobody had a deadline to meet, so there is none to name.
- An obligation written under one `HENCE` and handed on as a value to a place where the position does not exist — `THE JOIN` attached under a `LEST`, `THE DEADLINE` attached under an obligation with no `WITHIN`.

Under `EVERY` the same anchors work on the act's `WITHIN`, and a join line's own `WITHIN` may be anchored to `THE ARMING` or to an instant; see [EVERY](EVERY.md#anchored-deadlines-under-a-join).

### Boundary

The deadline boundary is inclusive: an action arriving _exactly at_ the deadline instant is timely. The failure/expiry path fires only once an event's timestamp is _strictly greater_ than the deadline (i.e. the deadline has _passed_).

### See Also

- **BEFORE** and **AFTER** (planned, not yet implemented -- the window's absolute closing edge and its opening edge)

## HENCE (Fulfillment Consequence)

Specifies what happens on the "success" path of a deontic rule. Chains obligations sequentially so that fulfilling one triggers the next.

The meaning of "success" depends on the deontic modal:

| Modal   | HENCE triggers when...                  | Default if omitted |
| ------- | --------------------------------------- | ------------------ |
| `DO`    | action is taken                         | `FULFILLED`        |
| `MUST`  | action is taken                         | `FULFILLED`        |
| `MAY`   | action is taken                         | `FULFILLED`        |
| `SHANT` | deadline passes (prohibition respected) | `FULFILLED`        |

### Syntax

```l4
PARTY ...
MUST action
WITHIN deadline
HENCE consequentRule
```

### Examples

```l4
-- Chain of obligations
PARTY Alice
MUST pay 500
WITHIN 7
HENCE (
  PARTY Bob
  MUST deliver "goods"
  WITHIN 14
)

-- Explicit fulfillment
PARTY Seller
MUST deliver
WITHIN 14
HENCE FULFILLED
```

### See Also

- **LEST** -- the "failure" path counterpart
- **FULFILLED** -- terminal success state

## LEST (Breach Consequence)

Specifies what happens on the "failure" path of a deontic rule. Typically used for penalty clauses or fallback obligations.

The meaning of "failure" depends on the deontic modal:

| Modal   | LEST triggers when...                      | Default if omitted |
| ------- | ------------------------------------------ | ------------------ |
| `DO`    | deadline passes                            | `BREACH`           |
| `MUST`  | deadline passes without action             | `BREACH`           |
| `MAY`   | deadline passes (permission not exercised) | `FULFILLED`        |
| `SHANT` | action is taken (prohibition violated)     | `BREACH`           |

Note that SHANT flips the polarity: for prohibitions, the action happening is the failure case (LEST), while the deadline passing without action is the success case (HENCE).

### Syntax

```l4
PARTY ...
MUST action
WITHIN deadline
LEST breachConsequence
```

### Examples

```l4
-- Simple breach
PARTY Alice
MUST pay 100
WITHIN 30
LEST BREACH

-- Penalty clause
PARTY Alice
MUST pay 100
WITHIN 30
LEST (
  PARTY Alice
  MUST pay 150
  WITHIN 60
)
```

### See Also

- **HENCE** -- the "success" path counterpart
- **BREACH** -- terminal failure state

## PROVIDED (Guard Condition)

Adds a guard condition to a deontic action. After an event matches the action pattern, the PROVIDED expression is evaluated. If it returns FALSE, the match is rejected and the system tries the next event. Defaults to TRUE if omitted.

Think of it as a pattern-match guard: the action shape must match first, then the guard condition is checked.

### Syntax

```l4
MUST action parameter PROVIDED condition
```

### Examples

```l4
-- Conditional payment
PARTY Bob
MUST payment price PROVIDED price >= 20
WITHIN 3

-- Guard on transferred amount
PARTY borrower
MUST `Amount Transferred`
  PROVIDED `is money at least equal` `Amount Transferred` `Payment Due`
```

### See Also

- **EXACTLY** -- controls pattern vs equality matching of the action itself

## EXACTLY (Exact Action Matching)

Changes how (part of) the action is matched against incoming events during contract execution. Without EXACTLY, the action is a pattern (matched structurally, like WHEN in CONSIDER -- can bind variables). With EXACTLY, the marked part is an expression that is evaluated to a value and compared for equality against the corresponding part of the event.

There are two placements:

1. **Whole-action**: `MUST EXACTLY expression` -- the entire action expression is evaluated and the event must equal the result.
2. **Per-argument**: `MUST action (EXACTLY expression) pattern...` -- the action's name and its other arguments are still matched as patterns, but the argument marked EXACTLY must equal the evaluated expression.

The per-argument form comes with two constraints:

- **Parenthesize the EXACTLY argument** whenever the action has more than one argument. EXACTLY greedily consumes everything to its right, so `MUST transfer EXACTLY 100 recipient` is read as a single EXACTLY expression spanning `100 recipient` and fails to typecheck ("transfer expects 2 inputs, but here it is given 1 input"). Write `MUST transfer (EXACTLY 100) recipient` instead. For a single-argument action, `MUST pay EXACTLY 100` needs no parentheses.
- **Order EXACTLY arguments before pattern names.** A pattern name to the left of an EXACTLY argument -- e.g. `MUST transfer amt (EXACTLY Bob)` -- is currently rejected at evaluation time with an internal "not in scope" error. Until that limitation is lifted, put the exact arguments first: `MUST transfer (EXACTLY 100) recip` works, matching the amount exactly while still binding `recip`.

### Syntax

```l4
MUST EXACTLY expression
MUST actionName EXACTLY expression             -- single-argument action
MUST actionName (EXACTLY expression) pattern   -- multi-argument action
```

### Examples

```l4
-- Without EXACTLY: "pay" is a pattern, matches any pay-shaped event
PARTY buyer MUST pay

-- Whole-action: the expression is evaluated, event must equal the result
PARTY lender MUST EXACTLY send capital to borrower

-- Per-argument, single argument: pay's amount must equal 100 exactly
PARTY Alice
MUST pay EXACTLY 100
WITHIN 30

-- Per-argument, multiple arguments: parenthesize EXACTLY and put it before
-- any pattern names; the amount must be exactly 100, the recipient is bound
-- as the pattern variable recip
PARTY Alice
MUST transfer (EXACTLY 100) recip
WITHIN 30
```

### See Also

- **PROVIDED** -- guard condition evaluated after the pattern matches

## BREACH (Terminal Violation State)

Terminal deontic value indicating that an obligation has been violated. Used as the consequence in LEST clauses. Can optionally specify the responsible party and a reason.

### Syntax

```l4
LEST BREACH
LEST BREACH BY party
LEST BREACH BECAUSE reason
LEST BREACH BY party BECAUSE reason
```

### Examples

```l4
-- Simple breach
LEST BREACH

-- With responsible party
LEST BREACH BY Seller

-- With reason
LEST BREACH BECAUSE "delivery deadline exceeded"

-- Full form
LEST BREACH BY Seller BECAUSE "failed to deliver within 14 days"
```

See **[BECAUSE](BECAUSE.md)** for detailed documentation on breach reasons.

### See Also

- **LEST** -- the clause where BREACH typically appears
- **FULFILLED** -- the success counterpart

## FULFILLED (Terminal Success State)

Terminal deontic value indicating that all obligations have been satisfied and no further action is needed. Commonly used as the consequence in HENCE clauses, and as the base case in conditional deontic rules.

### Syntax

```l4
HENCE FULFILLED
```

### Examples

```l4
-- After successful delivery
PARTY Seller
MUST deliver
WITHIN 14
HENCE FULFILLED

-- Base case in conditional rule
IF NOT `conditions precedent are met`
THEN FULFILLED
ELSE PARTY lender MUST ...
```

### See Also

- **HENCE** -- the clause where FULFILLED typically appears
- **BREACH** -- the failure counterpart

## RAND (Parallel AND of Obligations)

Parallel conjunction of deontic obligations. ALL component obligations must be fulfilled for the compound to be fulfilled. If either side breaches, the whole compound breaches (short-circuit).

In concurrency theory terms, this is parallel composition where all threads must complete successfully.

### Syntax

```l4
deonton1 RAND deonton2
```

### Examples

```l4
-- Both obligations must be fulfilled
(PARTY seller MUST deliver WITHIN 14 HENCE FULFILLED LEST BREACH)
RAND
(PARTY buyer MUST pay WITHIN 30 HENCE FULFILLED LEST BREACH)
```

### See Also

- **ROR** -- disjunctive choice (any one sufficient)
- **HENCE**, **LEST** -- consequence clauses within each component

---

## ROR (Parallel OR of Obligations)

Disjunctive choice between deontic obligations. EITHER obligation being fulfilled suffices for the compound to be fulfilled. If either side fulfills, the whole compound fulfills (short-circuit).

If ALL alternatives are breached, the compound is breached; the reported breach is the latest one (the last alternative "missed its chance"), falling back to the right operand when the breaches carry no distinguishing timestamps.

In concurrency theory terms, this is a race where the first to complete determines the outcome.

### Syntax

```l4
deonton1 ROR deonton2
```

### Precedence

RAND binds tighter than ROR, so `A ROR B RAND C` means `A ROR (B RAND C)`.

### Examples

```l4
-- Either obligation can fulfill the contract
(PARTY seller MUST ship WITHIN 14 HENCE FULFILLED LEST BREACH)
ROR
(PARTY seller MUST `arrange pickup` WITHIN 7 HENCE FULFILLED LEST BREACH)
```

### See Also

- **RAND** -- parallel conjunction (all must be fulfilled)
- **HENCE**, **LEST** -- consequence clauses within each component

---

## BEFORE (NOT YET IMPLEMENTED)

Planned temporal keyword for specifying absolute deadlines in deontic rules (as opposed to WITHIN, which specifies relative durations).

**Status:** Planned but not yet in the parser. Use WITHIN for relative durations in the meantime.

### Intended Syntax

```l4
PARTY ...
MUST action
BEFORE deadline
```

### See Also

- **WITHIN** -- implemented, for relative durations

---

## Testing with #TRACE

Use `#TRACE` to simulate contract execution.

### Syntax

```l4
#TRACE contractName AT startTime WITH
  PARTY partyName DOES action AT eventTime
  ...
```

### Example

```l4
#TRACE paymentObligation AT 0 WITH
  PARTY Alice DOES pay 100 AT 15
```

## Complete Example

```l4
DECLARE Person IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF
  delivery
  payment HAS amount IS A NUMBER

saleContract MEANS
  PARTY Seller
  MUST delivery
  WITHIN 3
  HENCE (
    PARTY Buyer
    MUST payment 100
    WITHIN 7
  )
  LEST BREACH

#TRACE saleContract AT 0 WITH
  PARTY Seller DOES delivery AT 2
  PARTY Buyer DOES payment 100 AT 5
```

## Related Pages

- **[PARTY](PARTY.md)** - Party declarations
- **[EVERY](EVERY.md)** - One obligation for every member of a group; the group is given as a list after `IN`, as `EVERY Tenant t IN tenants`
- **[MUST](MUST.md)** - Obligations
- **[MAY](MAY.md)** - Permissions
- **[SHANT](SHANT.md)** - Prohibitions (also written MUST NOT)
- **[DEONTIC](DEONTIC.md)** - The regulative rule type
- **[EVENT](EVENT.md)** - The event type consumed by traces

## See Also

- **[Foundation Course: Regulative Rules](../../courses/foundation/module-6-regulative.md)** - Tutorial
- **[Regulative Rules Concept](../../concepts/legal-modeling/regulative-rules.md)** - Conceptual overview
