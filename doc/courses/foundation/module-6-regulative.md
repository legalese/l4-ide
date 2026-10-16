# Module 6: Regulative rules

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

L4 represents these using the **DEONTIC** type. [How obligations unfold](../../concepts/legal-modeling/regulative-rules.md) explains how such a rule behaves over time.

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
    `resell the goods`
    `arrange a pickup`
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

MAY doesn't need a LEST: whether the buyer inspects the goods or lets the time pass, the result is the HENCE branch, because not exercising a permission isn't a breach.

---

## Creating Prohibitions with SHANT

Prohibitions say what must NOT happen:

```l4
GIVETH A DEONTIC `Contract Party` `Sale Action`
`the resale prohibition` MEANS
    PARTY `the buyer`
    SHANT `resell the goods`
    WITHIN 90
    HENCE FULFILLED
    LEST BREACH BY `the buyer` BECAUSE "resold the goods within 90 days"
```

`SHANT` means "shall not"; `MUST NOT` is accepted as another spelling. For a prohibition, the branches turn around: doing the forbidden act leads to `LEST`, and reaching the end of the `WITHIN` window without it leads to `HENCE`. In every case, `HENCE` is the outcome the law wants.

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
        LEST BREACH BY `the buyer`
    LEST BREACH BY `the seller`
```

This creates a chain:

1. Seller must deliver within 14 days
2. **If delivered**: Buyer must pay within 30 days
3. **If buyer pays**: Contract fulfilled
4. **If either fails**: Breach, by whoever failed

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

`PROVIDED` adds a condition to the action:

```l4
PARTY `the buyer`
MUST `pay the invoice` amount PROVIDED amount >= 100
WITHIN 30
HENCE FULFILLED
LEST BREACH
```

Here `amount` stands for whatever amount the buyer actually pays. An event counts only if the condition holds: a payment of 50 does not fulfil the obligation, and the contract keeps waiting for a payment of at least 100.

---

## Parallel Obligations with RAND

Use `RAND` (regulative AND) for obligations that must all be fulfilled:

```l4
GIVETH A DEONTIC `Contract Party` `Sale Action`
`delivery and payment` MEANS
    (PARTY `the seller` MUST `deliver the goods` WITHIN 14 HENCE FULFILLED LEST BREACH)
    RAND
    (PARTY `the buyer` MUST `pay the invoice` 1000 WITHIN 30 HENCE FULFILLED LEST BREACH)
```

Both obligations must be fulfilled for the contract to be fulfilled.

---

## Alternative Paths with ROR

Use `ROR` (regulative OR) when either path fulfills the contract:

```l4
GIVETH A DEONTIC `Contract Party` `Sale Action`
`delivery or pickup` MEANS
    (PARTY `the seller` MUST `deliver the goods` WITHIN 14 HENCE FULFILLED LEST BREACH)
    ROR
    (PARTY `the seller` MUST `arrange a pickup` WITHIN 7 HENCE FULFILLED LEST BREACH)
```

The seller can choose either option. Only if both fail is the contract breached.

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
- Seller delivers at day 10 (within the 14-day deadline)
- Buyer pays at day 35 (25 days after delivery, within the 30-day deadline)

Note that a `WITHIN` deadline starts running when its obligation becomes active: the buyer's 30 days count from the delivery on day 10.

Result: `FULFILLED`

### Breach Scenario

```l4
#TRACE `the delivery obligation` AT 0 WITH
    PARTY `the seller` DOES `deliver the goods` AT 20  -- Late! Deadline was 14
```

Result: `BREACH` (seller delivered late)

### No events yet

With no events, or only events that don't match, the result is neither `FULFILLED` nor `BREACH`. It is the obligation itself, still waiting, with whatever time is left. A missing event is not a breach: the contract only learns that a deadline has passed when an event arrives after it.

---

## Worked example: wedding vows

Traditional wedding vows make a small contract with all three kinds of rule:

> "I take you to be my wedded spouse, to have and to hold from this day forward, for better, for worse, for richer, for poorer, in sickness and in health, to love and to cherish, till death do us part."

**Complete example:** [wedding-vows-example.l4](wedding-vows-example.l4)

The parties are two spouses, and the actions are the ones the vows talk about:

```
DECLARE Person IS ONE OF Spouse1, Spouse2

DECLARE Action IS ONE OF
    `exchange vows`
    `love and cherish`
    `be unfaithful`
```

**The ceremony** is a chain. Spouse1 must exchange vows on the day; once they have, Spouse2 must too. Each `LEST` names who breached and why:

```
GIVETH A DEONTIC Person Action
`wedding ceremony` MEANS
    PARTY Spouse1
    MUST `exchange vows`
    WITHIN 1
    HENCE
        PARTY Spouse2
        MUST `exchange vows`
        WITHIN 1
        HENCE FULFILLED
        LEST BREACH BY Spouse2 BECAUSE "failed to exchange vows"
    LEST BREACH BY Spouse1 BECAUSE "failed to exchange vows"
```

**"To love and to cherish"** binds both spouses at once, so the two obligations are joined with `RAND`. **"Forsaking all others"** becomes two prohibitions, also joined with `RAND`:

```
GIVETH A DEONTIC Person Action
`fidelity clause` MEANS
    (PARTY Spouse1 SHANT `be unfaithful` HENCE FULFILLED LEST BREACH BY Spouse1 BECAUSE "was unfaithful")
    RAND
    (PARTY Spouse2 SHANT `be unfaithful` HENCE FULFILLED LEST BREACH BY Spouse2 BECAUSE "was unfaithful")
```

The tests at the end of the file give three results:

| Scenario                                       | Result                                         |
| ---------------------------------------------- | ---------------------------------------------- |
| Both spouses exchange vows on day 0            | `FULFILLED`                                    |
| Spouse1 never does; the next event is on day 2 | `BREACH BY Spouse1`, "failed to exchange vows" |
| Spouse1 is unfaithful on day 100               | `BREACH BY Spouse1`, "was unfaithful"          |

The same patterns run through employment contracts (the employee must report for work), leases (the tenant shall not sublet without permission) and regulatory filings (the company must file a report within 60 days).

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
-- Good: Clear, descriptive types
DECLARE `Lease Party` IS ONE OF
    `the landlord`
    `the tenant`

DECLARE `Lease Action` IS ONE OF
    `pay the rent` HAS amount IS A NUMBER
    `maintain the property`
    `provide access`
    `terminate the lease`
```

### 2. Name Actions Like the Legal Text

`` MUST `deliver goods in accordance with the specification` `` keeps the legal nuance that `MUST deliver` loses.

### 3. Use BREACH BY and BECAUSE for Clear Blame

```l4
LEST BREACH BY `the seller` BECAUSE "failed to deliver on time"
```

The reason is what a reviewer or a downstream system reads.

### 4. Write Both Paths

`MUST` and `SHANT` have defaults (`HENCE FULFILLED`, `LEST BREACH`), but writing both `HENCE` and `LEST` makes the intent plain to a legal reviewer. Where the text gives a remedy ("pay within 30 days, or pay extra within 60"), write the remedy as an obligation in `LEST` rather than ending in a bare `BREACH`.

### 5. Test with Multiple Scenarios

```
-- Happy path
#TRACE `the complete sale contract` AT 0 WITH
    PARTY `the seller` DOES `deliver the goods` AT 5
    PARTY `the buyer` DOES `pay the invoice` 1000 AT 20

-- Late delivery
#TRACE `the complete sale contract` AT 0 WITH
    PARTY `the seller` DOES `deliver the goods` AT 20

-- No action: the result is the contract, still waiting
#TRACE `the complete sale contract` AT 0 WITH
```

---

## Exercises

### Exercise 1: Obligation with a Condition

Write a regulative rule: "The buyer must pay at least 500 within 30 days." Test it with a payment of 200 on day 10 and a payment of 600 on day 20.

<details>
<summary>Solution</summary>

```l4
DECLARE `Sale Party` IS ONE OF
    `the buyer`
    `the seller`

DECLARE `Sale Action` IS ONE OF
    `pay` HAS amount IS A NUMBER

GIVETH A DEONTIC `Sale Party` `Sale Action`
`the minimum payment` MEANS
    PARTY  `the buyer`
    MUST   `pay` amount PROVIDED amount AT LEAST 500
    WITHIN 30
    HENCE  FULFILLED
    LEST   BREACH BY `the buyer` BECAUSE "did not pay at least 500 within 30 days"

#TRACE `the minimum payment` AT 0 WITH
    PARTY `the buyer` DOES `pay` 200 AT 10
    PARTY `the buyer` DOES `pay` 600 AT 20
```

The payment of 200 does not meet the condition, so it is skipped; the payment of 600 fulfils the obligation.

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

Next, [Module 7: Putting it together](module-7-capstone.md) builds a complete legal model that combines everything so far.
