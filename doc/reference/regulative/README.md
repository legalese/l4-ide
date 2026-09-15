# Regulative Rule Keywords

Regulative keywords express legal obligations, permissions, prohibitions, and their consequences. They form the core of L4's contract and regulation modeling.

> **See also:** [Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md) — how L4 decides _who may perform which action_ (the performer/agreement rule, duplex actions, parameterised actions applied by a rule, and higher-order procurement), with worked ✅/❌ examples.

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

| Keyword               | Purpose                                                                                                        |
| --------------------- | -------------------------------------------------------------------------------------------------------------- |
| [PARTY](PARTY.md)     | Who has the obligation/permission                                                                              |
| [EVERY](EVERY.md)     | Every member of a group has it                                                                                 |
| WITHIN                | Temporal deadline (relative)                                                                                   |
| HENCE                 | Consequence on fulfillment                                                                                     |
| LEST                  | Consequence on breach                                                                                          |
| PROVIDED              | Guard condition on action                                                                                      |
| EXACTLY (deprecated)  | See [below](#action-patterns-reference-or-wildcard) — a name in an action already refers to the thing it names |
| BREACH                | Terminal violation state                                                                                       |
| [BECAUSE](BECAUSE.md) | Reason for breach                                                                                              |
| FULFILLED             | Terminal success state                                                                                         |

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

Specifies a relative time duration within which an action must/may be performed.

### Syntax

```l4
PARTY ...
MUST action
WITHIN duration
```

The duration can optionally be anchored to an event with `OF`:

```l4
WITHIN 5 days OF notice
```

### Examples

```l4
-- Simple deadline
PARTY Alice MUST pay 100 WITHIN 30

-- Anchored to an event
PARTY Seller MUST deliver WITHIN 5 days OF `order confirmation`
```

### Boundary

The deadline boundary is inclusive: an action arriving _exactly at_ the deadline instant is timely. The failure/expiry path fires only once an event's timestamp is _strictly greater_ than the deadline (i.e. the deadline has _passed_).

### See Also

- **BEFORE** (planned, not yet implemented -- will support absolute deadlines)

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

- **Action Patterns** -- what a name in an action means, [below](#action-patterns-reference-or-wildcard)

## Action Patterns: Reference or Wildcard

A name written in an action slot means one of two things, and the checker
decides which by looking the name up:

1. **The name refers to something already in scope** -- a `GIVEN` input, a
   `WHERE` local, a name an outer action already bound, a same-module rule, an
   import. Then the action requires _that_ value: the event must equal it,
   the way `WHEN` does in `CONSIDER`.
2. **The name refers to nothing at all.** Then it is a fresh placeholder that
   matches any value in that position, usable afterwards in `PROVIDED`,
   `HENCE` and `LEST`. (A name that refers only to the action's own field
   selector -- `amount` naming the `amount` field being matched -- is treated
   the same way, because a selector is a function and can never be the value
   the slot wants.)

There is no keyword to choose between them: whichever is true of the name is
what it means.

```l4
-- pay is a pattern; amount matches any figure and is bound for later use
PARTY buyer MUST pay amount PROVIDED amount >= 20

-- price is a GIVEN input, so it must be paid exactly, not matched loosely
GIVEN price IS A NUMBER
GIVETH A DEONTIC Actor Action
`fixed payment` MEANS PARTY buyer MUST pay price WITHIN 30
```

**Whole actions and other expressions** are read the same way they always
were: evaluated, and compared against the event for equality. A compound
expression should be parenthesized so it does not swallow what follows it:

```l4
PARTY lender MUST (send capital to borrower)
PARTY Alice  MUST transfer (price PLUS 50) recip WITHIN 30
```

`recip` above still follows the rule at the top of this section: a reference
if something in scope is called `recip`, a placeholder otherwise.

### EXACTLY (deprecated)

`EXACTLY` used to be the keyword that spelled the first branch above -- "this
argument is a value to require," not a name to bind. It still parses and
still works exactly as it always did, but it is no longer needed: the checker
now takes the reference on its own. Where dropping it is safe, the checker's
warning says exactly what to write instead -- for a name, just the name; for
any other expression, the expression with its parentheses kept:

```l4
MUST EXACTLY (send capital to borrower)   -- deprecated
MUST (send capital to borrower)           -- means the same thing
```

One case keeps its warning without a suggested drop: an `EXACTLY` operand
that refers to nothing in scope (a typo, or a name not yet defined) would
become a silent placeholder if the keyword were simply removed, so the
checker flags it without offering that rewrite. Fix the name instead of
dropping the keyword there.

### See Also

- **PROVIDED** -- guard condition evaluated after the pattern matches

## BREACH (Terminal Violation State)

Terminal deontic value indicating that an obligation has been violated. Used as the consequence in LEST clauses. Can optionally specify the responsible party — one, or a `LIST` of several — and a reason.

### Syntax

```l4
LEST BREACH
LEST BREACH BY party
LEST BREACH BY LIST party, party
LEST BREACH BECAUSE reason
LEST BREACH BY party BECAUSE reason
LEST BREACH BY LIST party, party BECAUSE reason
```

### Examples

```l4
-- Simple breach
LEST BREACH

-- With responsible party
LEST BREACH BY Seller

-- With several responsible parties, one line of the answer each
LEST BREACH BY LIST Seller, Carrier BECAUSE "goods lost in transit"

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
