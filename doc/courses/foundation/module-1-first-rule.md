# Module 1: Your First Legal Rule

**Prerequisites:** Module 0

In this module, you'll write your first legal rule in L4—a simple legal obligation with conditions, deadlines, and consequences.

## Learning Objectives

By the end of this module, you will be able to:

- Write a basic legal obligation using PARTY and MUST
- Add conditions using IF
- Set deadlines using WITHIN
- Define consequences using HENCE and LEST
- Test your rule using #EVAL

---

## A Simple Legal Obligation

Let's start with something every lawyer understands: a simple legal obligation. Find the complete working example later in this document.

**The annual return obligation:** "A registered charity must file an annual return."

In L4, we write this as:

```l4
GIVEN charity IS A `Registered Charity`
`the annual return obligation` MEANS
    PARTY `the charity`
    MUST `file the annual return`
```

Let's break this down:

| Code                                        | Meaning                                    |
| ------------------------------------------- | ------------------------------------------ |
| ``GIVEN charity IS A `Registered Charity``` | This rule applies to registered charities  |
| `` `the annual return obligation` MEANS ``  | The name of this rule                      |
| `` PARTY `the charity` ``                   | The charity is the one with the obligation |
| `MUST`                                      | This creates a legal obligation            |
| `` `file the annual return` ``              | This is what they must do                  |

### Backtick Names

Notice the backticks around `file the annual return`. In L4, backticks let you use spaces and special characters in names. These are called **quoted identifiers**.

```l4
-- Without backticks, names cannot contain spaces:
return              -- a single word
-- With backticks, names read like natural language:
`file the return`         -- quoted identifier (with spaces)
`file the annual return`  -- more descriptive
```

Use backticks liberally, so your names read like natural language.

---

## Try It Yourself

Write a rule that says "A solicitor must maintain client confidentiality."

Every obligation needs to know **who** can act and **what** they can do. Copy this scaffold for now—`DECLARE` is taught fully in Module 2, and `DEONTIC` (the type of obligations) in Module 6:

```l4
DECLARE Party IS ONE OF
    `the solicitor`
    `the client`

DECLARE Action IS ONE OF
    `maintain client confidentiality`

GIVETH A DEONTIC Party Action
`the confidentiality obligation` MEANS
    -- your PARTY ... MUST ... goes here
    PARTY `the solicitor`
    MUST `maintain client confidentiality`
```

Your job: read the scaffold and make sure the `PARTY ... MUST ...` part matches the rule in plain English. Then try changing the action name or adding a second action to the `Action` list.

---

## Adding Conditions

Real legal rules have conditions. Let's add one:

```l4
IF charity's `the status` EQUALS Active
THEN PARTY `the charity`
     MUST `file the annual return`
ELSE FULFILLED
```

The `IF` keyword adds a condition that must be true for the obligation to apply. The `ELSE FULFILLED` says: if the condition doesn't hold, there is nothing to do.

### Multiple Conditions

Use `AND` and `OR` for multiple conditions:

```l4
IF charity's `the status` EQUALS Active
   AND charity's `the annual income` > 10000
```

### Accessing Fields

The `'s` syntax accesses fields of a record:

```l4
charity's `the status`         -- the status field of charity
charity's `the annual income`  -- the annual income field of charity
```

---

## Setting Deadlines

Legal obligations usually have deadlines. Use `WITHIN`:

```l4
PARTY `the charity`
MUST `file the annual return`
WITHIN 60
```

`WITHIN 60` means "within 60 days." L4 uses days as the default time unit.

---

## Consequences: HENCE and LEST

What happens when someone complies or doesn't comply? Use `HENCE` and `LEST`:

```l4
PARTY `the charity`
MUST `file the annual return`
WITHIN 60
HENCE FULFILLED
LEST BREACH
```

| Keyword | Meaning                               |
| ------- | ------------------------------------- |
| `HENCE` | What happens if they **comply**       |
| `LEST`  | What happens if they **don't comply** |

### Chaining Obligations

`HENCE` can trigger another obligation:

```l4
PARTY `the seller`
MUST `deliver the goods`
WITHIN 14
HENCE
    PARTY `the buyer`
    MUST `pay the invoice` 1000
    WITHIN 30
    HENCE FULFILLED
    LEST BREACH
LEST BREACH
```

This creates a chain: if the seller delivers, the buyer must pay.

---

## Complete Example

[module-1-examples.l4](module-1-examples.l4)

Included are:

- Type definitions for charities, actors, and actions
- The annual return obligation with conditions and deadlines
- A chained sale contract
- Test data and `#TRACE` simulations

### Understanding GIVETH A DEONTIC

When a function returns an obligation (not just a value), we use `GIVETH A DEONTIC`:

- `GIVETH A BOOLEAN` - returns true/false
- `GIVETH A NUMBER` - returns a number
- `GIVETH A DEONTIC Actor Action` - returns an obligation (specifying actor and action types)

Don't worry about mastering `DEONTIC` yet—copy the pattern for now; it is taught fully in Module 6.

> **Looking ahead.** When actions carry an actor field (the value-actor encoding), L4
> enforces that the party obligated in `PARTY p MUST a` matches `a`'s performer. This
> is covered fully in Module 6 and in
> [Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md).

---

## Testing with #EVAL

Use `#EVAL` to test expressions. These examples use the `Animal Welfare Society` test charity defined in [module-1-examples.l4](module-1-examples.l4):

```l4
#EVAL `Animal Welfare Society`'s `the name`
-- Result: "Animal Welfare Society"

#EVAL `Animal Welfare Society`'s `the status` EQUALS Active
-- Result: TRUE
```

In VS Code with the L4 extension, hover over `#EVAL` to see the result.

---

## Testing with #TRACE

For regulative rules (obligations), use `#TRACE` to simulate scenarios:

```l4
#TRACE `the annual return obligation` `Animal Welfare Society` AT 0 WITH
    PARTY `the charity` DOES `file the annual return` AT 30
```

This simulates:

- Starting at day 0
- The charity filing their return at day 30

The result shows whether the obligation was `FULFILLED` or `BREACH`.

---

## Common Mistakes

### 1. Missing Type Declaration

```l4
-- ❌ Wrong: Type not declared
GIVEN charity IS A `Registered Charity`

-- ✅ Right: Declare the type first
DECLARE `Registered Charity`
    HAS `the name` IS A STRING
```

### 2. Wrong Field Access

```l4
-- ❌ Wrong: Missing 's
IF charity `the status` EQUALS Active

-- ✅ Right: Use 's for field access
IF charity's `the status` EQUALS Active
```

### 3. Missing Backticks for Multi-Word Names

```l4
-- ❌ Wrong: Spaces without backticks
MUST file the annual return

-- ✅ Right: Use backticks
MUST `file the annual return`
```

## Exercises

### Exercise 1: Simple Obligation

Write an L4 rule for: "An employee must submit a timesheet every week."

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

### Exercise 2: Conditional Obligation

Write an L4 rule for: "If a tenant is more than 14 days late on rent, the landlord may issue an eviction notice."

<details>
<summary>Solution</summary>

```l4
DECLARE `Tenancy Party` IS ONE OF
    `the landlord`
    `the tenant`

DECLARE `Tenancy Action` IS ONE OF
    `issue an eviction notice`

GIVEN `the days the rent is late` IS A NUMBER
GIVETH A DEONTIC `Tenancy Party` `Tenancy Action`
`the eviction permission` MEANS
    IF `the days the rent is late` > 14
    THEN PARTY `the landlord`
         MAY `issue an eviction notice`
         HENCE FULFILLED
    ELSE FULFILLED

#TRACE `the eviction permission` 20 AT 0 WITH
    PARTY `the landlord` DOES `issue an eviction notice` AT 1
```

Note the `MAY`: the landlord is permitted to act, but not obliged. You'll meet `MAY` again in Module 6.

</details>

### Exercise 3: Chained Obligations

Write L4 rules for: "The seller must deliver goods within 14 days. If delivered, the buyer must pay within 30 days."

<details>
<summary>Solution</summary>

```l4
DECLARE `Sale Party` IS ONE OF
    `the seller`
    `the buyer`

DECLARE `Sale Action` IS ONE OF
    `deliver the goods`
    `pay the invoice`

GIVETH A DEONTIC `Sale Party` `Sale Action`
`the sale agreement` MEANS
    PARTY `the seller`
    MUST `deliver the goods`
    WITHIN 14
    HENCE
        PARTY `the buyer`
        MUST `pay the invoice`
        WITHIN 30
        HENCE FULFILLED
        LEST BREACH
    LEST BREACH

#TRACE `the sale agreement` AT 0 WITH
    PARTY `the seller` DOES `deliver the goods` AT 10
    PARTY `the buyer` DOES `pay the invoice` AT 25
```

</details>

---

## Summary

In this module, you learned:

| Concept               | Syntax                            |
| --------------------- | --------------------------------- |
| Declare parameters    | `GIVEN name IS A Type`            |
| Create obligation     | `PARTY actor MUST action`         |
| Add condition         | `IF condition`                    |
| Set deadline          | `WITHIN days`                     |
| Compliance result     | `HENCE consequence`               |
| Non-compliance result | `LEST consequence`                |
| Test expression       | `#EVAL expression`                |
| Simulate scenario     | `#TRACE rule AT time WITH events` |

---

## What's Next?

In [Module 2: Legal Entities and Relationships](module-2-entities.md), you'll learn how to model complex legal entities with proper types, including records, enums, and relationships between entities.
