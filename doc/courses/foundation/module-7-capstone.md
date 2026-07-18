# Module 7: Putting It Together

**Prerequisites:** Modules 1–6

In this capstone module, you'll build a complete legal model combining everything you've learned.

## Learning Objectives

By the end of this module, you will be able to:

- Design a complete L4 model from requirements
- Organize code with sections
- Apply best practices
- Debug common issues
- Know where to go next

---

## Capstone Project: Charity Registration

We'll build a simplified charity registration system based on real legislation. This combines:

- Type definitions
- Eligibility rules
- Classification and fee calculations
- Regulative obligations and prohibitions
- Testing

The complete working implementation:

[module-7-examples.l4](module-7-examples.l4)

### Requirements

1. **Charities** have names, registration numbers, statuses, purposes, and governors
2. **Purposes** must be from an approved list
3. **Governors** must be adults without disqualifying convictions
4. **Charities** are classified by income into size bands, which determine the filing fee
5. **Registered charities** must file annual returns within 60 days of year-end
6. **Late filing** triggers a Required Steps Notice
7. **Charities** must not distribute profits to their governors

---

## Step 1: Define Types

Start by modeling the domain:

```l4
-- Charitable purposes (from legislation)
DECLARE Purpose IS ONE OF
    `prevention or relief of poverty`
    `advancement of education`
    `advancement of religion`
    `advancement of health`
    `advancement of animal welfare`
    `other purpose` HAS `the description` IS A STRING

-- Legal status of a charity
DECLARE Status IS ONE OF
    Active
    Suspended HAS `the reason` IS A STRING
    Deregistered

-- Criminal conviction record
DECLARE Conviction
    HAS `the description` IS A STRING
        `the conviction is spent` IS A BOOLEAN

-- Governor of a charity
DECLARE Governor
    HAS `the governor's name` IS A STRING
        `the governor's age` IS A NUMBER
        `the governor is bankrupt` IS A BOOLEAN
        `the governor's convictions` IS A LIST OF Conviction

-- The main charity record
DECLARE `Registered Charity`
    HAS `the charity's name` IS A STRING
        `the registration number` IS A STRING
        `the charity's status` IS A Status
        `the charity's purposes` IS A LIST OF Purpose
        `the charity's governors` IS A LIST OF Governor
```

Key design decisions:

1. **Use natural language field names:** `` `the governor's name` `` reads like legal text
2. **Use enumerations for fixed categories:** Prevents typos and invalid values
3. **Use lists for multiple items:** governors, purposes, convictions

---

## Step 2: Define Eligibility Rules

Rules for who can be a governor and what makes a valid charity:

```l4
-- A governor must be an adult (at least 18)
GIVEN governor IS A Governor
GIVETH A BOOLEAN
DECIDE `the governor is an adult` IF
    governor's `the governor's age` >= 18

-- Check for disqualifying convictions (unspent convictions)
GIVEN governor IS A Governor
GIVETH A BOOLEAN
DECIDE `the governor has a disqualifying conviction` IF
    any (GIVEN c YIELD c's `the conviction is spent` EQUALS FALSE) (governor's `the governor's convictions`)

-- A person can be a governor if they meet all criteria
GIVEN governor IS A Governor
GIVETH A BOOLEAN
DECIDE `the person can be a governor` IF
    `the governor is an adult` governor
    AND NOT governor's `the governor is bankrupt`
    AND NOT `the governor has a disqualifying conviction` governor

-- A charity is valid if it has valid purposes and valid governors
GIVEN charity IS A `Registered Charity`
GIVETH A BOOLEAN
DECIDE `the charity is valid` IF
    charity's `the charity's status` EQUALS Active
    AND NOT null (charity's `the charity's purposes`)
    AND all (GIVEN p YIELD `the purpose is charitable` p) (charity's `the charity's purposes`)
    AND NOT null (charity's `the charity's governors`)
    AND all (GIVEN g YIELD `the person can be a governor` g) (charity's `the charity's governors`)
```

Key patterns:

1. **Simple predicates:** `` `the governor is an adult` ``
2. **Using `any` and `all` with predicates:** checking convictions, purposes, and governors
3. **Combining conditions:** using `AND` and `NOT`

**Note:** These functions require `IMPORT prelude` for `any`, `all`, `null`, etc.

---

## Step 3: Classification and Fees

Constitutive rules from Module 4 in action—a multi-way classification with `BRANCH`, and a calculation decomposed with `WHERE`:

```l4
-- Classify a charity by its annual income (multi-way decision with BRANCH)
GIVEN `the annual income` IS A NUMBER
GIVETH A STRING
DECIDE `the charity's size band` IS
    BRANCH
        IF `the annual income` < 10000 THEN "small"
        IF `the annual income` < 500000 THEN "medium"
        OTHERWISE "large"

-- The annual filing fee, decomposed with WHERE
GIVEN charity IS A `Registered Charity`
      `the annual income` IS A NUMBER
GIVETH A NUMBER
`the annual filing fee` MEANS
    `the base fee` + `the governor levy`
    WHERE
        `the base fee` MEANS
            BRANCH
                IF `the charity's size band` `the annual income` EQUALS "small" THEN 50
                IF `the charity's size band` `the annual income` EQUALS "medium" THEN 200
                OTHERWISE 500

        `the governor levy` MEANS
            10 * count (charity's `the charity's governors`)
```

Key patterns:

1. **BRANCH for classification:** conditions checked top-to-bottom, first match wins
2. **WHERE names each part of the formula:** the fee is transparently `base fee + governor levy`
3. **Reusing decisions:** the fee calculation calls the size-band classification
4. **`count` from the prelude:** the number of items in a list

---

## Step 4: Define Regulative Rules

The filing obligations and a prohibition:

```l4
-- Actors and actions for the regulatory system
DECLARE Actor IS ONE OF
    `the Charity`
    `the Commissioner`

DECLARE Action IS ONE OF
    `file the annual return`
    `issue a Required Steps Notice`
    `correct the deficiencies`
    `distribute profits to the governors`

-- Annual return filing obligation
GIVEN charity IS A `Registered Charity`
GIVETH A DEONTIC Actor Action
`the annual return obligation` MEANS
    IF charity's `the charity's status` EQUALS Active
    THEN
        PARTY `the Charity`
        MUST `file the annual return`
        WITHIN 60
        HENCE FULFILLED
        LEST
            PARTY `the Commissioner`
            MUST `issue a Required Steps Notice`
            WITHIN 14
            HENCE `the correction period`
            LEST BREACH BY `the Commissioner` BECAUSE "failed to issue notice"
    ELSE FULFILLED

-- After notice is issued, charity has time to correct
GIVETH A DEONTIC Actor Action
`the correction period` MEANS
    PARTY `the Charity`
    MUST `correct the deficiencies`
    WITHIN 30
    HENCE FULFILLED
    LEST BREACH BY `the Charity` BECAUSE "failed to correct after notice"

-- A prohibition: charities must not distribute profits to their governors
GIVETH A DEONTIC Actor Action
`the profit distribution prohibition` MEANS
    PARTY `the Charity`
    SHANT `distribute profits to the governors`
    HENCE FULFILLED
    LEST BREACH BY `the Charity` BECAUSE "distributed profits to governors"
```

Key patterns:

1. **Actor and Action types:** Define who can act and what actions exist
2. **Conditional obligations:** Only active charities must file
3. **Chained obligations:** Non-compliance triggers Commissioner action, then a correction period
4. **Prohibitions with SHANT:** what must NOT happen
5. **Clear blame assignment:** `BREACH BY ... BECAUSE ...`

---

## Step 5: Create Test Data

```l4
-- Valid governor
`Jane Smith` MEANS Governor "Jane Smith" 45 FALSE (LIST)

-- Governor with issues
`John Doe (bankrupt)` MEANS Governor "John Doe" 50 TRUE (LIST)

`unspent conviction` MEANS Conviction "Fraud conviction 2020" FALSE
`Bob Jones (with conviction)` MEANS Governor "Bob Jones" 40 FALSE (LIST `unspent conviction`)

`Young Person` MEANS Governor "Young Person" 16 FALSE (LIST)

-- Valid charity
`Jersey Animal Welfare` MEANS `Registered Charity` "Jersey Animal Welfare" "CH001" Active (LIST `advancement of animal welfare`, `advancement of education`) (LIST `Jane Smith`)

-- Charity with invalid governor
`Problem Charity` MEANS `Registered Charity` "Problem Charity" "CH002" Active (LIST `advancement of education`) (LIST `John Doe (bankrupt)`)

-- Suspended charity
`Suspended Charity` MEANS `Registered Charity` "Suspended Charity" "CH003" (Suspended "Financial irregularities") (LIST `advancement of health`) (LIST `Jane Smith`)
```

Create governors and charities with various characteristics for testing—including ones that should fail.

---

## Step 6: Test Everything

### Unit Tests with #EVAL

```l4
#EVAL `the governor is an adult` `Jane Smith`                      -- TRUE
#EVAL `the person can be a governor` `Jane Smith`                  -- TRUE
#EVAL `the person can be a governor` `John Doe (bankrupt)`         -- FALSE
#EVAL `the person can be a governor` `Bob Jones (with conviction)` -- FALSE
#EVAL `the charity is valid` `Jersey Animal Welfare`               -- TRUE
#EVAL `the charity is valid` `Problem Charity`                     -- FALSE

#EVAL `the charity's size band` 60000                              -- "medium"
#EVAL `the annual filing fee` `Jersey Animal Welfare` 60000        -- 210
```

### Scenario Tests with #TRACE

```l4
-- Happy path: charity files on time
#TRACE `the annual return obligation` `Jersey Animal Welfare` AT 0 WITH
    PARTY `the Charity` DOES `file the annual return` AT 30
-- Result: FULFILLED

-- Suspended charity: no filing required
#TRACE `the annual return obligation` `Suspended Charity` AT 0 WITH
-- Result: FULFILLED

-- Late filing: the charity misses the 60-day deadline (its day-65 filing
-- arrives too late), the Commissioner issues a notice, then the charity
-- corrects within the correction period
#TRACE `the annual return obligation` `Jersey Animal Welfare` AT 0 WITH
    PARTY `the Charity` DOES `file the annual return` AT 65
    PARTY `the Commissioner` DOES `issue a Required Steps Notice` AT 70
    PARTY `the Charity` DOES `correct the deficiencies` AT 90
-- Result: FULFILLED

-- Prohibition: distributing profits is a breach
#TRACE `the profit distribution prohibition` AT 0 WITH
    PARTY `the Charity` DOES `distribute profits to the governors` AT 10
-- Result: BREACH BY `the Charity` BECAUSE "distributed profits to governors"
```

---

## Organizing Code with Sections

Use sections (`§`) to organize larger files:

```l4
§ `Charity Registration System`

§§ `Type Definitions`
-- Types go here

§§ `Eligibility Rules`
-- Eligibility functions go here

§§ `Filing Obligations`
-- Regulative rules go here

§§ `Tests`
-- Test cases go here
```

Sections create a hierarchy:

- `§` - Top-level section
- `§§` - Sub-section
- `§§§` - Sub-sub-section

---

## Best Practices

### 1. Start with Types

```l4
-- ✅ Good: Clear domain model
DECLARE Application
    HAS `the applicant` IS A `Legal Entity`
        `the purposes` IS A LIST OF Purpose
        `the documents` IS A LIST OF Document
```

### 2. Small, Focused Functions

```l4
-- ✅ Good: Single responsibility
DECIDE `the governor is an adult` IF governor's `the governor's age` >= 18
DECIDE `the governor is not bankrupt` IF NOT governor's `the governor is bankrupt`

-- Combine them
DECIDE `the person can be a governor` IF
    `the governor is an adult` governor
    AND `the governor is not bankrupt` governor
```

### 3. Test Every Path

```l4
-- Happy path
#EVAL `the person can be a governor` `Jane Smith`             -- TRUE

-- Error cases
#EVAL `the person can be a governor` `John Doe (bankrupt)`    -- FALSE
#EVAL `the person can be a governor` `Young Person`           -- FALSE
```

### 4. Use Descriptive Names

```l4
-- ✅ Good: Clear, readable names
DECIDE `the charity meets filing requirements` IF ...

-- ❌ Bad: Cryptic names
DECIDE check1 IF ...
```

### 5. Document Complex Logic

```l4
-- The charity test requires:
-- 1. All purposes must be from the statutory list (Art 5)
-- 2. The charity must provide public benefit (Art 7)
-- 3. All governors must be fit and proper (Art 19)
DECIDE `meets charity test` IF ...
```

---

## Debugging Checklist

When something doesn't work:

| Error                  | Likely Cause            | Fix                                       |
| ---------------------- | ----------------------- | ----------------------------------------- |
| "Type not in scope"    | Type not declared       | Add DECLARE before use                    |
| "Unexpected 's"        | Missing parentheses     | `count (x's field)` not `count x's field` |
| "Expected BOOLEAN"     | Wrong type in condition | Check IF conditions return BOOLEAN        |
| "Not enough arguments" | Missing function args   | Count parameters in GIVEN                 |
| "Indentation error"    | Inconsistent spacing    | Align all fields under HAS                |

---

## Where to Go Next

### Immediate Next Steps

1. **[Advanced Course](../advanced/README.md)** - Complex patterns, real legislation, multi-instrument integration

2. **[Tutorials](../../tutorials/README.md)** - Task-focused guides:

   - Building web forms
   - LLM integration
   - Contract automation

3. **Practice** - Try encoding a real document:
   - Your employment contract
   - Your lease agreement
   - A regulation you work with

### Reference Materials

- **[Reference Guide](../../reference/README.md)** - Complete keyword and syntax reference
- **[Concepts](../../concepts/README.md)** - Deep dives into design principles

### Example Code

Explore the examples in the repository:

- `jl4/examples/legal/` - Real legal documents
- `jl4/examples/ok/` - Working syntax examples
- `jl4/experiments/` - Experimental features

---

## Summary: What You've Learned

### Module 1: Your First Legal Rule

- GIVEN, PARTY, MUST
- IF conditions
- WITHIN deadlines
- HENCE and LEST consequences

### Module 2: Legal Entities and Relationships

- DECLARE with HAS for records
- IS ONE OF for enumerations
- Field access with 's

### Module 3: Control Flow

- IF/THEN/ELSE and BRANCH
- CONSIDER pattern matching
- AND, OR, NOT operators
- List operations

### Module 4: Decision Logic

- Constitutive rules with DECIDE and MEANS
- WHERE for transparent calculations
- Optional values with MAYBE (NOTHING/JUST)
- Working with dates

### Module 5: Functions

- GIVEN and GIVETH signatures
- Recursion
- Higher-order functions: map, filter, foldl

### Module 6: Regulative Rules

- MUST, MAY, SHANT
- HENCE, LEST
- PROVIDED conditions
- RAND and ROR combinators
- #TRACE testing

### Module 7: Putting It Together

- Project structure
- Best practices
- Debugging

---

## Congratulations! 🎉

You've completed the L4 Foundation Course. You now have the skills to:

- Model legal entities and relationships
- Write legal rules and eligibility criteria
- Create contracts with obligations and consequences
- Test your models with simulations

**Next recommended step:** Try the [Advanced Course](../advanced/README.md) to learn about real regulatory schemes, cross-cutting concerns, and production patterns.
