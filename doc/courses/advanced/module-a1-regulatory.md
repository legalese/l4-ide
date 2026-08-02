# Module A1: Real Regulatory Schemes

In this module, you'll learn how to model complete legislative frameworks using a systematic three-layer approach. Find a working example at the end.

## Learning Objectives

By the end of this module, you will be able to:

- Apply the three-layer approach to legislative encoding
- Extract type definitions from statutory text
- Model deontic rules with proper actors and triggers
- Track state transitions and register events

---

## The Three-Layer Approach

When encoding legislation, we organize rules into three layers:

| Layer             | What It Contains                       | L4 Constructs     |
| ----------------- | -------------------------------------- | ----------------- |
| **A: Structural** | Definitions, types, enums              | DECLARE, glossary |
| **B: Deontic**    | Obligations, permissions, prohibitions | MUST, MAY, SHANT  |
| **C: Events**     | State transitions, register updates    | Actions, effects  |

This mirrors how legislation is typically structured:

- Early sections define terms
- Middle sections create duties and powers
- Later sections specify procedures and consequences

---

## Case Study: Charity Registration

We'll use the Jersey Charities Law as a running example. This real legislation covers:

- What qualifies as a charity
- Who can be a governor
- Filing requirements
- Enforcement powers

### Starting Point: The Legislation

From the Charities (Jersey) Law 2014:

> **Article 2 - Definitions**
> "charitable purpose" means any of the purposes specified in Schedule 1
> "governor" means any person who is responsible for the control and management of the administration of a registered charity
> "misconduct" includes mismanagement or misapplication of charity property

> **Article 11 - Registration**
> A charity may apply to the Commissioner for registration by providing:
> (a) its constitution
> (b) a statement of its charitable purposes
> (c) evidence of public benefit
> (d) core financial information

---

## Layer A: Structural Definitions

First, encode the definitions and types:

```l4
§ `Structural Layer - Definitions`

-- Article 2(10): "misconduct" includes mismanagement or misapplication
DECLARE `Misconduct Type` IS ONE OF
    Mismanagement
    Misapplication
    `other misconduct` HAS `the description` IS A STRING

-- Schedule 1: Charitable purposes (13 statutory heads)
DECLARE `Charitable Purpose` IS ONE OF
    `prevention or relief of poverty`
    `advancement of education`
    `advancement of religion`
    `advancement of health or saving of lives`
    `advancement of citizenship or community development`
    `advancement of arts, culture, heritage or science`
    `advancement of amateur sport`
    `advancement of human rights, conflict resolution, reconciliation`
    `advancement of environmental protection or improvement`
    `relief of those in need`
    `advancement of animal welfare`
    `purposes analogous to charitable purposes`
    `other charitable purpose` HAS `the description` IS A STRING

-- Article 2: Governor definition
DECLARE Governor HAS
    `the name` IS A STRING
    `the date of birth` IS A DATE
    `the address` IS A STRING
    `is bankrupt` IS A BOOLEAN
    `the convictions` IS A LIST OF Conviction

-- Core financial information (Regulation 1, Core Info Regs 2018)
DECLARE `Core Financial Information` HAS
    `the income` IS A Money
    `the expenditure` IS A Money
    `the opening assets` IS A Money
    `the closing assets` IS A Money
    `the other assets` IS A LIST OF Asset

-- Register sections
DECLARE `Register Section` IS ONE OF
    `the general section`
    `the restricted section`

-- Charity status
DECLARE `Charity Status` IS ONE OF
    Pending
    Active
    Suspended HAS
        `the reason` IS A STRING
        `the date` IS A DATE
    Deregistered HAS
        `the reason` IS A STRING
        `the date` IS A DATE
        `is retrospective` IS A BOOLEAN

-- Main charity record
DECLARE `Registered Charity` HAS
    `the name` IS A STRING
    `the registration number` IS A STRING
    `the register section` IS A `Register Section`
    `the status` IS A `Charity Status`
    `the constitution` IS A STRING
    `the purposes` IS A LIST OF `Charitable Purpose`
    `the public benefit statement` IS A STRING
    `the governors` IS A LIST OF Governor
    `the financials` IS A `Core Financial Information`
    `the registration date` IS A DATE
```

### Key Principle: Glossary-First

Notice how we encode the statutory glossary (Article 2) as types. This:

1. **Prevents ambiguity** - `Misconduct Type` has exactly three variants
2. **Enables validation** - Can only use defined purposes
3. **Documents the source** - Comments link to legislation

---

## Layer B: Deontic Rules

Now encode the obligations, permissions, and prohibitions.

### Actors and the Performer Rule

L4 enforces **actor-correctness**: a `PARTY p MUST a` obligation requires `p`
to be the _performer_ of action `a`. The performer is the first actor-typed
field of the action record (the subject-first canon). The older flat-union
action style (`DECLARE Action IS ONE OF fileReturn, issueNotice`) remains valid;
the performer check applies when an action record carries an actor field.

For the value-actor encoding (recommended for mixed-actor systems), declare
actors as an enum and actions as records carrying their performer:

```l4
-- Minimal example: regulatory system with two actors
DECLARE RegActor IS ONE OF
    Charity
    Commissioner

DECLARE RegAction HAS
    performer IS A RegActor
    verb      IS A STRING

-- Pinned actions: performer baked in
`file return`  MEANS RegAction OF Charity,      "file annual return"
`issue notice` MEANS RegAction OF Commissioner, "issue notice"

-- ✅ each actor is bound to its own action
GIVETH A DEONTIC RegActor RegAction
`charity files` MEANS
    PARTY Charity      MUST `file return`  WITHIN 60 HENCE FULFILLED LEST FULFILLED

GIVETH A DEONTIC RegActor RegAction
`commissioner issues` MEANS
    PARTY Commissioner MUST `issue notice` WITHIN 30 HENCE FULFILLED
    LEST BREACH BY Commissioner BECAUSE "failed to issue notice"

-- ❌ rejected: `file return` is performed by `Charity`, not by `Commissioner`
-- bad MEANS PARTY Commissioner MUST `file return` WITHIN 60 ...
```

The error the compiler emits when a performer check fails:

```
An actor may only perform its own actions.
  `file return` is performed by `Charity`, not by `Commissioner`.
```

See [Actors and Actions](../../concepts/legal-modeling/actors-and-actions.md) for
the full treatment including duplex actions, parameterised `EXACTLY`-applied
actions, and procurement / principal–agent chains.

### Flat-union style (also valid)

The charity example below uses flat-union actions (`DECLARE Action IS ONE OF …`).
This style carries no actor field, so no performer check fires — it is the
right choice when every action variant belongs to exactly one actor class and
you do not need mixed-actor event driving.

```l4
§ `Deontic Layer - Rules`

-- Actors in the regulatory system
DECLARE Actor IS ONE OF
    `the charity` HAS `the charity record` IS A `Registered Charity`
    `the governor` HAS `the governor record` IS A Governor
    `the Commissioner`
    `the applicant` HAS `the applicant record` IS A Applicant

-- Actions that can be performed
DECLARE Action IS ONE OF
    -- Charity obligations
    `file annual return`
    `report change of particulars`
    `report reportable matter` HAS
        `the matter` IS A `Reportable Matter`
    -- Commissioner powers
    `demand information`
    `issue Required Steps Notice`
    `suspend governor` HAS
        `the reason` IS A STRING
    `deregister charity` HAS
        `the reason` IS A STRING
    -- Governor obligations
    `act in best interests`
    `report conviction`
    -- Appeal actions
    `lodge appeal`
```

### Encoding Individual Rules

Each statutory rule becomes a function:

```l4
-- B-AR-01: Annual Return Obligation
-- Article 13(7)-(10) + Timing Order 2019
-- "A registered charity must file an annual return within 2 months of year end"

GIVEN charity IS A `Registered Charity`
GIVETH A DEONTIC Actor Action
`annual return obligation` MEANS
    IF charity's `the status` EQUALS Active
    THEN
        PARTY `the charity` charity
        MUST `file annual return`
        WITHIN 60  -- 2 months ≈ 60 days
        HENCE FULFILLED
        LEST `Commissioner may issue notice` charity
    ELSE FULFILLED

-- B-RSN-01: Commissioner's Power to Issue Notice
-- Article 27(1)-(4)

GIVEN charity IS A `Registered Charity`
GIVETH A DEONTIC Actor Action
`Commissioner may issue notice` MEANS
    PARTY `the Commissioner`
    MAY `issue Required Steps Notice`
    HENCE `charity must comply with notice` charity
```

### Rule Identification

Use consistent identifiers for traceability:

| ID       | Type      | Description              |
| -------- | --------- | ------------------------ |
| B-AR-01  | CONDUCT   | Annual return filing     |
| B-AR-02  | CONDUCT   | Commissioner publication |
| B-RSN-01 | PROCEDURE | Required Steps Notice    |
| B-GOV-01 | CONDUCT   | Governor best interests  |

---

## Layer C: Events and State Transitions

Track what happens when actions occur:

```l4
§ `Event Layer - State Transitions`

-- Events that change the register
DECLARE `Register Event` IS ONE OF
    `charity registered` HAS
        `the charity record` IS A `Registered Charity`
        `the date` IS A DATE
    `charity moved to restricted` HAS
        `the charity record` IS A `Registered Charity`
        `the date` IS A DATE
    `charity deregistered` HAS
        `the charity record` IS A `Registered Charity`
        `the reason` IS A STRING
        `the date` IS A DATE
        `is retrospective` IS A BOOLEAN
    `annual return filed` HAS
        `the charity record` IS A `Registered Charity`
        `the year` IS A NUMBER
        `was late` IS A BOOLEAN
    `Required Steps Notice issued` HAS
        `the charity record` IS A `Registered Charity`
        `the notice id` IS A STRING
        `the deadline` IS A DATE
    `governor suspended` HAS
        `the governor record` IS A Governor
        `the charity record` IS A `Registered Charity`
        `the reason` IS A STRING
        `the period` IS A NUMBER

-- Effect of events on register
GIVEN event IS A `Register Event`
GIVETH A STRING  -- Describes the effect
`event effect` MEANS
    CONSIDER event
    WHEN `charity registered` c d THEN
        "New active entry created in register"
    WHEN `charity deregistered` c r d retro THEN
        IF retro
        THEN "Entry moved to historic; registration void from earlier date"
        ELSE "Entry moved to historic"
    WHEN `annual return filed` c y late THEN
        IF late
        THEN "Annual return logged with late flag"
        ELSE "Annual return logged"
    WHEN `Required Steps Notice issued` c nid deadline THEN
        "Notice reference stored under Art 8(3)(k)"
    OTHERWISE "Register updated"
```

---

## Handling Cross-References

Legislation often cross-references between sections. Model these explicitly:

```l4
-- The charity test (Article 5) references:
-- - Schedule 1 (purposes)
-- - Article 7 (public benefit)
-- - Regulations (core financial info)

GIVEN charity IS A `Registered Charity`
GIVETH A BOOLEAN
DECIDE `meets charity test` IF
    `has charitable purposes` charity              -- Schedule 1
    AND `provides public benefit` charity          -- Article 7
    AND `has valid constitution` charity           -- Article 11(2)(a)
    AND `has complete financial info` charity      -- Core Info Regs

-- Article 7: Public benefit factors
GIVEN charity IS A `Registered Charity`
GIVETH A BOOLEAN
DECIDE `provides public benefit` IF
    `has identifiable benefit` charity             -- Art 7(2)(a)
    AND `benefit outweighs detriment` charity      -- Art 7(2)(b)
    AND NOT `unduly restricts beneficiaries` charity  -- Art 7(3)
```

---

## Handling Amendments

Legislation changes over time. Track versions:

```l4
-- Original Law 2014 had 12 charitable purposes
-- R&O 27/2025 added "advancement of animal welfare"

-- Model with effective dates:
DECLARE `Dated Purpose` HAS
    `the purpose` IS A `Charitable Purpose`
    `effective from` IS A DATE

-- Check if purpose was valid at a given date
GIVEN purpose IS A `Charitable Purpose`
      `the reference date` IS A DATE
GIVETH A BOOLEAN
DECIDE `purpose valid at date` IF
    -- Animal welfare only valid from 2025
    IF purpose EQUALS `advancement of animal welfare`
    THEN `the reference date` >= Date 1 1 2025
    ELSE TRUE  -- Other purposes valid from 2014
```

---

## Exercise: Encode a Rule

Encode this statutory requirement:

> **Article 19(1)**: A governor must notify the Commissioner as soon as practicable if any of the following matters applies to them:
> (a) bankruptcy
> (b) disqualification as a company director
> (c) conviction for an offence involving dishonesty

<details>
<summary>Solution</summary>

```l4
-- Reportable matters under Article 19(1)
DECLARE `Reportable Matter` IS ONE OF
    Bankruptcy HAS
        `the date` IS A DATE
    `director disqualification` HAS
        `the date` IS A DATE
        `the jurisdiction` IS A STRING
    `dishonest conviction` HAS
        `the description` IS A STRING
        `the date` IS A DATE

-- B-GOV-02: Governor reporting obligation
GIVEN governor IS A Governor
      matter IS A `Reportable Matter`
GIVETH A DEONTIC Actor Action
`governor reporting obligation` MEANS
    PARTY `the governor` governor
    MUST `report reportable matter` matter
    WITHIN 14  -- "as soon as practicable" interpreted as 14 days
    HENCE FULFILLED
    LEST `Commissioner may suspend` governor
```

</details>

---

## Full Example

[module-a1-regulatory-examples.l4](module-a1-regulatory-examples.l4)

---

## Summary

| Layer             | Purpose     | L4 Approach                 |
| ----------------- | ----------- | --------------------------- |
| **A: Structural** | Definitions | DECLARE types from glossary |
| **B: Deontic**    | Rules       | MUST/MAY/SHANT functions    |
| **C: Events**     | Transitions | Event types + effects       |

Key practices:

- Start with the statutory glossary (definitions section)
- Assign rule IDs for traceability
- Model cross-references explicitly
- Track temporal validity for amendments

---

## What's Next?

In [Module A2: Cross-Cutting Concerns](module-a2-cross-cutting.md), you'll learn patterns for timing, notices, appeals, and other concerns that span multiple rules.
