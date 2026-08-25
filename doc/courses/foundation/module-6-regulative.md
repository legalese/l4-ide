# Module 6: Regulative Rules

**Prerequisites:** Modules 1–5

In this module, you'll learn how to model legal obligations, permissions, and prohibitions—the core of contract and regulatory law.

## Learning Objectives

By the end of this module, you will be able to:

- Define Actor and Action types
- Create obligations with MUST
- Create permissions with MAY
- Create prohibitions with SHANT
- Chain obligations with HENCE and LEST
- Test regulative rules with #TRACE

---

## What Are Regulative Rules?

**Regulative rules** define what parties must, may, or must not do. They're the building blocks of contracts and regulations:

- **Obligations** (MUST): "The seller must deliver goods"
- **Permissions** (MAY): "The buyer may inspect goods"
- **Prohibitions** (SHANT): "The employee shall not disclose confidential information"
- **Option** (DO): "The employee discloses confidential information"

L4 represents these using the **DEONTIC** type.

---

## The DEONTIC Type

A DEONTIC value represents an obligation, permission, or prohibition. It has:

- **Who** (PARTY): The actor with the duty/permission
- **What** (action): The action to be performed
- **When** (WITHIN): The deadline
- **Consequences** (HENCE/LEST): What happens next

The complete working example:

[module-6-examples.l4](module-6-examples.l4)

### Defining Actor and Action Types

First, define who can act and what actions exist:

```l4
-- Who can act
DECLARE `Contract Party` IS ONE OF
    `the buyer`
    `the seller`

-- What actions exist
DECLARE `Sale Action` IS ONE OF
    `deliver the goods`
    `pay the invoice` HAS amount IS A NUMBER
    `inspect the goods`
```

---

## Creating Obligations with MUST

```l4
GIVETH A DEONTIC `Contract Party` `Sale Action`
`the delivery obligation` MEANS
    PARTY `the seller`
    MUST `deliver the goods`
    WITHIN 14
    HENCE FULFILLED
    LEST BREACH
```

| Part                                                  | Meaning                                               |
| ----------------------------------------------------- | ----------------------------------------------------- |
| `` GIVETH A DEONTIC `Contract Party` `Sale Action` `` | Returns a deontic value with these actors and actions |
| `` PARTY `the seller` ``                              | The seller has this obligation                        |
| `` MUST `deliver the goods` ``                        | They must deliver goods                               |
| `WITHIN 14`                                           | Within 14 days                                        |
| `HENCE FULFILLED`                                     | If they do, the obligation is fulfilled               |
| `LEST BREACH`                                         | If they don't, it's a breach                          |

---

## Creating Permissions with MAY

Permissions don't create breaches if unused:

```l4
GIVETH A DEONTIC `Contract Party` `Sale Action`
`the inspection right` MEANS
    PARTY `the buyer`
    MAY `inspect the goods`
    HENCE FULFILLED
```

Note: MAY doesn't need LEST because not exercising a permission isn't a breach.

---

## Creating Prohibitions with SHANT

Prohibitions say what must NOT happen. From the wedding vows example in [module-6-examples.l4](module-6-examples.l4):

```l4
GIVETH A DEONTIC Spouse Vow
`the fidelity clause` MEANS
    PARTY Spouse1
    SHANT `be unfaithful`
    HENCE FULFILLED
    LEST BREACH BY Spouse1 BECAUSE "was unfaithful"
```

`SHANT` is equivalent to "shall not" or "must not."

---

## Chaining Obligations with HENCE

Real contracts have sequences of obligations. Use HENCE to chain them:

```l4
GIVETH A DEONTIC `Contract Party` `Sale Action`
`the complete sale contract` MEANS
    PARTY `the seller`
    MUST `deliver the goods`
    WITHIN 14
    HENCE
        PARTY `the buyer`
        MUST `pay the invoice` 1000
        WITHIN 30
        HENCE FULFILLED
        LEST BREACH
    LEST
        PARTY `the seller`
        MAY `cancel the order`
        HENCE BREACH
```

This creates a chain:

1. Seller must deliver within 14 days
2. **If delivered**: Buyer must pay within 30 days
3. **If buyer pays**: Contract fulfilled
4. **If either fails**: Breach

---

## Alternative Consequences with LEST

LEST specifies what happens on non-compliance:

```l4
GIVETH A DEONTIC `Contract Party` `Sale Action`
`the payment with late fee` MEANS
    PARTY `the buyer`
    MUST `pay the invoice` 1000
    WITHIN 30
    HENCE FULFILLED
    LEST
        PARTY `the buyer`
        MUST `pay the invoice` 1100  -- 10% late fee
        WITHIN 14
        HENCE FULFILLED
        LEST BREACH
```

This gives the buyer a second chance with a penalty before reaching breach.

---

## Conditional Obligations with PROVIDED

Add conditions to obligations:

```l4
PARTY `the buyer`
MUST `pay the invoice` amount PROVIDED amount >= 100
WITHIN 30
HENCE FULFILLED
LEST BREACH
```

`PROVIDED` adds a guard condition—the obligation only applies if the condition is true.

---

## Parallel Obligations with RAND

Use `RAND` (regulative AND) for obligations that must all be fulfilled:

```l4
(PARTY `the seller` MUST `deliver the goods` WITHIN 14 HENCE FULFILLED LEST BREACH)
RAND
(PARTY `the buyer` MUST `pay the invoice` 1000 WITHIN 30 HENCE FULFILLED LEST BREACH)
```

Both obligations must be fulfilled for the contract to be fulfilled.

---

## Alternative Paths with ROR

Use `ROR` (regulative OR) when either path fulfills the contract. Each branch must carry
its own `HENCE`/`LEST` consequences — there is no shared trailing `LEST` outside the
`ROR`:

```l4
(PARTY `the seller` MUST `deliver the goods` WITHIN 14 HENCE FULFILLED LEST BREACH)
ROR
(PARTY `the seller` MUST `arrange a pickup` WITHIN 7 HENCE FULFILLED LEST BREACH)
```

The seller can choose either option.

---

## Testing with #TRACE

`#TRACE` simulates scenarios to see what happens:

### Basic Trace

```l4
#TRACE `the complete sale contract` AT 0 WITH
    PARTY `the seller` DOES `deliver the goods` AT 10
    PARTY `the buyer` DOES `pay the invoice` 1000 AT 35
```

This simulates:

- Start at day 0
- Seller delivers at day 10 (within 14-day deadline ✓)
- Buyer pays at day 35 (25 days after delivery—within the 30-day deadline ✓)

Note that a `WITHIN` deadline starts running when its obligation becomes active: the buyer's 30 days count from the delivery on day 10.

Result: `FULFILLED`

### Breach Scenario

```l4
#TRACE `the delivery obligation` AT 0 WITH
    PARTY `the seller` DOES `deliver the goods` AT 20  -- Late! Deadline was 14
```

Result: `BREACH` (seller delivered late)

---

## Real-World Example: Wedding Vows

See the wedding vows example which demonstrates:

- Mutual exchange of vows
- Prohibitions (fidelity clause)
- Using `BREACH BY ... BECAUSE ...` for clear blame assignment

---

## The Performer Rule: Who May Do What

When your Action type carries an **actor field**, L4 enforces that the party named in
`PARTY p MUST a` is also the action `a`'s **performer** — the actor in the first
actor-typed field (the "subject-first" canon). A Drinker obligated to eat is a
type error.

This applies to the **value-actor encoding**, where actors are values of one type and
actions are records that carry their actor(s):

```l4
DECLARE Actor IS ONE OF Eater, Drinker

DECLARE Action HAS
  actor IS AN Actor
  verb  IS A STRING

eat   MEANS Action OF Eater,   "eat"
drink MEANS Action OF Drinker, "drink"
```

✅ **Works** — each actor is obligated to its own action:

```l4
GIVETH A DEONTIC Actor Action
`eater eats`     MEANS PARTY Eater   MUST eat   WITHIN 30
`drinker drinks` MEANS PARTY Drinker MUST drink WITHIN 10
```

❌ **Rejected** — a Drinker cannot be obligated to an Eater action:

```l4
GIVETH A DEONTIC Actor Action
bad MEANS PARTY Drinker MUST eat WITHIN 30
```

```
An actor may only perform its own actions.

  `eat` is performed by `Eater`, not by `Drinker`.
```

> **Note:** The flat-union style used in most of this module (`DECLARE Action IS ONE OF deliver, pay`)
> carries no actor field, so the performer rule does not apply to it — existing flat-union
> contracts are unaffected.

### Who may perform: the simple cases

This is the **simple, common case** — a _single-actor_ action whose performer is
**pinned** (`eat` belongs to `Eater`, so only an Eater may be obligated to eat):

```l4
eat MEANS Action OF Eater, "eat"        -- only Eater performs eat
```

The actor _type_ you `DECLARE` is the **cast** — everyone who may take part. A
one-line `DECLARE Actor IS ONE OF Eater, Drinker` says exactly who the players
are; a party outside that type is a plain type error.

The **richer cases live in the advanced course**: actions _any_ actor can
perform and **duplex** actions (one type, both directions) in
[Module A2](../advanced/module-a2-cross-cutting.md), and **procurement** — "X
undertakes to procure that Y performs an action" — in
[Module A3](../advanced/module-a3-contracts.md). The complete reference, with
every ✅/❌ case (one / some / any actor), is
[Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md).

---

## State Graphs

L4 can visualize regulative rules as state transition diagrams:

```bash
l4 state-graph mycontract.l4

# Or from a Haskell checkout
cabal run l4 -- state-graph mycontract.l4
```

This generates a graph showing:

- **States**: Initial, intermediate, Fulfilled, Breach
- **Transitions**: Actions that move between states
- **Deadlines**: When actions must occur

The graph makes complex contracts easier to understand.

---

## Best Practices

### 1. Define Clear Actors and Actions

```l4
-- ✅ Good: Clear, descriptive types
DECLARE `Lease Party` IS ONE OF
    `the landlord`
    `the tenant`

DECLARE `Lease Action` IS ONE OF
    `pay the rent` HAS amount IS A NUMBER
    `maintain the property`
    `provide access`
    `terminate the lease`
```

### 2. Use BREACH BY for Clear Blame

```l4
LEST BREACH BY `the seller` BECAUSE "failed to deliver on time"
```

### 3. Consider All Paths

Make sure every path leads to either FULFILLED or BREACH:

```l4
-- ✅ Good: All paths handled
MUST action
WITHIN deadline
HENCE FULFILLED
LEST BREACH

-- ❌ Bad: What happens if they don't comply?
MUST action
WITHIN deadline
HENCE FULFILLED
-- Missing LEST!
```

### 4. Test with Multiple Scenarios

```l4
-- Happy path
#TRACE `the complete sale contract` AT 0 WITH
    PARTY `the seller` DOES `deliver the goods` AT 5
    PARTY `the buyer` DOES `pay the invoice` 1000 AT 20

-- Late delivery
#TRACE `the complete sale contract` AT 0 WITH
    PARTY `the seller` DOES `deliver the goods` AT 20

-- No action
#TRACE `the complete sale contract` AT 0 WITH
    -- Empty: what happens at deadline?
```

---

## Exercises

### Exercise 1: Simple Obligation

Write a regulative rule: "The employee must submit a timesheet within 7 days."

<details>
<summary>Solution</summary>

```l4
DECLARE `Employment Party` IS ONE OF
    `the employee`
    `the employer`

DECLARE `Employment Action` IS ONE OF
    `submit the timesheet`

GIVETH A DEONTIC `Employment Party` `Employment Action`
`the timesheet obligation` MEANS
    PARTY `the employee`
    MUST `submit the timesheet`
    WITHIN 7
    HENCE FULFILLED
    LEST BREACH

#TRACE `the timesheet obligation` AT 0 WITH
    PARTY `the employee` DOES `submit the timesheet` AT 5
```

</details>

### Exercise 2: Chained Obligations

Write a contract: "Buyer must pay deposit within 7 days. After deposit, seller must deliver within 14 days."

<details>
<summary>Solution</summary>

```l4
DECLARE `Sale Party` IS ONE OF
    `the buyer`
    `the seller`

DECLARE `Deposit Action` IS ONE OF
    `pay the deposit`
    `deliver the goods`

GIVETH A DEONTIC `Sale Party` `Deposit Action`
`the deposit contract` MEANS
    PARTY `the buyer`
    MUST `pay the deposit`
    WITHIN 7
    HENCE
        PARTY `the seller`
        MUST `deliver the goods`
        WITHIN 14
        HENCE FULFILLED
        LEST BREACH
    LEST BREACH

#TRACE `the deposit contract` AT 0 WITH
    PARTY `the buyer` DOES `pay the deposit` AT 3
    PARTY `the seller` DOES `deliver the goods` AT 12
```

</details>

### Exercise 3: Permission and Prohibition

Write rules for: "Tenant may have pets. Tenant shall not smoke indoors."

<details>
<summary>Solution</summary>

```l4
DECLARE `Lease Party` IS ONE OF
    `the tenant`
    `the landlord`

DECLARE `Lease Action` IS ONE OF
    `keep a pet`
    `smoke indoors`

GIVETH A DEONTIC `Lease Party` `Lease Action`
`the pet permission` MEANS
    PARTY `the tenant`
    MAY `keep a pet`
    HENCE FULFILLED

GIVETH A DEONTIC `Lease Party` `Lease Action`
`the smoking prohibition` MEANS
    PARTY `the tenant`
    SHANT `smoke indoors`
    HENCE FULFILLED
    LEST BREACH BY `the tenant` BECAUSE "smoked indoors"

#TRACE `the pet permission` AT 0 WITH
    PARTY `the tenant` DOES `keep a pet` AT 1

#TRACE `the smoking prohibition` AT 0 WITH
    PARTY `the tenant` DOES `smoke indoors` AT 10
```

</details>

---

## Summary

| Concept              | Syntax                                       |
| -------------------- | -------------------------------------------- |
| Obligation           | `PARTY actor MUST action`                    |
| Permission           | `PARTY actor MAY action`                     |
| Prohibition          | `PARTY actor SHANT action`                   |
| Deadline             | `WITHIN days`                                |
| Compliance result    | `HENCE next obligation` or `HENCE FULFILLED` |
| Non-compliance       | `LEST consequence` or `LEST BREACH`          |
| Condition            | `PROVIDED condition`                         |
| Parallel obligations | `obligation1 RAND obligation2`               |
| Alternative paths    | `obligation1 ROR obligation2`                |
| Simulate             | `#TRACE rule AT start time WITH events`      |
| Event                | `PARTY actor DOES action AT time`            |

---

## What's Next?

In [Module 7: Putting It Together](module-7-capstone.md), you'll build a complete legal model combining everything you've learned.
