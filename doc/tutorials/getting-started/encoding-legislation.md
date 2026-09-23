# Encoding Legislation

Turn a legal provision into L4 code.

**Prerequisites:** Basic L4 knowledge ([Your First L4 File](first-l4-file.md))

---

## What You'll Build

We'll encode this provision from an imaginary Alcohol Act:

> **Section 3.** A person must not sell alcohol if:
> (a) the person is a body corporate;
> (b) the person engages in business for profit;
> (c) the person is not a public house or hotel; and
> (d) any of the following applies:
> (i) the person has an unspent conviction for fraud;
> (ii) the person has an unspent conviction for providing misleading information; or
> (iii) the person has an alcohol banning order.

---

## Step 1: Analyze the Structure

Before writing code, identify:

1. **Outcome:** "must not sell alcohol"
2. **Conditions:** (a), (b), (c), (d) - all must be true
3. **Sub-conditions:** (d)(i), (d)(ii), (d)(iii) - any one triggers

The logical structure:

```
(a) AND (b) AND (c) AND ((d)(i) OR (d)(ii) OR (d)(iii))
```

---

## Step 2: Declare the Inputs

First, declare the facts we need. These are **assumptions** because their truth comes from outside L4:

```l4
§ `Imaginary Alcohol Act - Section 3`

-- Facts about the person
ASSUME `the person is a body corporate` IS BOOLEAN
ASSUME `the person engages in business for profit` IS BOOLEAN
ASSUME `the person is a public house` IS BOOLEAN
ASSUME `the person is a hotel` IS BOOLEAN

-- Criminal history and orders
ASSUME `the person has an unspent conviction for fraud` IS BOOLEAN
ASSUME `the person has an unspent conviction for providing misleading information` IS BOOLEAN
ASSUME `the person has an alcohol banning order` IS BOOLEAN
```

### Why ASSUME?

`ASSUME` declares facts that come from outside L4:

- User input
- Database lookup
- Another system

L4 doesn't know or check these values—it just uses them.

### Where the Values Come From

Nothing inside the file supplies a value for an `ASSUME`. If you `#EVAL` a rule that
needs one, evaluation stops at the first assumed fact:

```
I could not continue evaluating, because I needed to know the value of
  `the person is a body corporate`
but it is an assumed term.
```

The values arrive when the rule is deployed: `jl4-service` turns every `ASSUME` an
`@export`ed rule refers to into a parameter of that rule and fills it from each request
(see [ASSUME and `@export`](../../reference/types/ASSUME.md#assume-and-export)). To
exercise the rule _inside_ the file, Step 4 gives it its inputs as a `GIVEN` parameter
instead.

---

## Step 3: Encode the Rule

Now translate the legal text directly:

```l4
-- Section 3: Prohibition on selling alcohol
DECIDE `the person must not sell alcohol`
IF  `the person is a body corporate`
    AND `the person engages in business for profit`
    AND NOT `the person is a public house`
    AND NOT `the person is a hotel`
    AND (
        `the person has an unspent conviction for fraud`
        OR `the person has an unspent conviction for providing misleading information`
        OR `the person has an alcohol banning order`
    )
```

### Matching the Legal Text

Notice how the L4 mirrors the legislation:

| Legal Text                                  | L4 Code                                                |
| ------------------------------------------- | ------------------------------------------------------ |
| "the person is a body corporate"            | `` `the person is a body corporate` ``                 |
| "the person is not a public house or hotel" | `` NOT `..is a public house` AND NOT `..is a hotel` `` |
| "any of the following applies"              | `(...OR...OR...)`                                      |

---

## Step 4: Add Test Cases

Test the rule with specific scenarios.

There is a catch. The rule in Step 3 takes no parameters—its inputs are `ASSUME`s—and no
directive can supply a value for an `ASSUME`. `WITH` passes _named arguments to a
function_, so ``#EVAL `the person must not sell alcohol` WITH ...`` is a type error
("You are trying to apply ... of type BOOLEAN (which is not a function) to (named)
arguments"). To test the rule here, give it its inputs as a parameter. As in
[Your First L4 File](first-l4-file.md), bundle the facts into a record and pass it as one
`GIVEN`. This is also the house style for the larger encodings in this repository, for the
same reason: a rule over a `GIVEN` record can be evaluated in full, while one over
`ASSUME`s cannot be evaluated at all until it is deployed.

```l4
§ `Testable Version`

DECLARE Person
    HAS `is a body corporate` IS A BOOLEAN
        `engages in business for profit` IS A BOOLEAN
        `is a public house` IS A BOOLEAN
        `is a hotel` IS A BOOLEAN
        `has an unspent conviction for fraud` IS A BOOLEAN
        `has an unspent conviction for providing misleading information` IS A BOOLEAN
        `has an alcohol banning order` IS A BOOLEAN

GIVEN person IS A Person
DECIDE `must not sell alcohol`
IF  person's `is a body corporate`
    AND person's `engages in business for profit`
    AND NOT person's `is a public house`
    AND NOT person's `is a hotel`
    AND (
        person's `has an unspent conviction for fraud`
        OR person's `has an unspent conviction for providing misleading information`
        OR person's `has an alcohol banning order`
    )
```

Each scenario is now a `Person`, and `#ASSERT` pins the outcome you expect:

```l4
§ `Test Cases`

{-
Scenario 1: Corporate pub (exempt)
- Body corporate: Yes
- For profit: Yes
- Public house: Yes (exempt!)
Expected: FALSE (not prohibited because it's a public house)
-}
`the corporate pub` MEANS Person WITH
    `is a body corporate` IS TRUE
    `engages in business for profit` IS TRUE
    `is a public house` IS TRUE
    `is a hotel` IS FALSE
    `has an unspent conviction for fraud` IS TRUE
    `has an unspent conviction for providing misleading information` IS FALSE
    `has an alcohol banning order` IS FALSE

#ASSERT NOT `must not sell alcohol` `the corporate pub`

{-
Scenario 2: Banned corporate (prohibited)
- Body corporate: Yes
- For profit: Yes
- Public house: No
- Hotel: No
- Banning order: Yes
Expected: TRUE (prohibited)
-}
`the banned corporate` MEANS Person WITH
    `is a body corporate` IS TRUE
    `engages in business for profit` IS TRUE
    `is a public house` IS FALSE
    `is a hotel` IS FALSE
    `has an unspent conviction for fraud` IS FALSE
    `has an unspent conviction for providing misleading information` IS FALSE
    `has an alcohol banning order` IS TRUE

#ASSERT `must not sell alcohol` `the banned corporate`

{-
Scenario 3: Clean corporate (not prohibited)
- Body corporate: Yes
- For profit: Yes
- No exemption, but no disqualifying factors
Expected: FALSE (not prohibited - no (d) condition met)
-}
`the clean corporate` MEANS Person WITH
    `is a body corporate` IS TRUE
    `engages in business for profit` IS TRUE
    `is a public house` IS FALSE
    `is a hotel` IS FALSE
    `has an unspent conviction for fraud` IS FALSE
    `has an unspent conviction for providing misleading information` IS FALSE
    `has an alcohol banning order` IS FALSE

#ASSERT NOT `must not sell alcohol` `the clean corporate`
```

A failing `#ASSERT` reports `assertion failed` when you run the file. See
[Testing Your Rules](testing-your-rules.md) for `#EVAL`, `#ASSERT` and `#CHECK`.

---

## Step 5: Refactor for Readability

For complex rules, break into named sub-rules:

```l4
§ `Refactored Version`

-- Sub-rule: Is this a commercial enterprise?
GIVEN person IS A Person
DECIDE `is commercial enterprise`
IF  person's `is a body corporate`
    AND person's `engages in business for profit`

-- Sub-rule: Is this an exempt establishment?
GIVEN person IS A Person
DECIDE `is exempt establishment`
IF  person's `is a public house`
    OR person's `is a hotel`

-- Sub-rule: Does person have disqualifying factors?
GIVEN person IS A Person
DECIDE `has disqualifying factors`
IF  person's `has an unspent conviction for fraud`
    OR person's `has an unspent conviction for providing misleading information`
    OR person's `has an alcohol banning order`

-- Main rule: Prohibition (refactored)
GIVEN person IS A Person
DECIDE `must not sell alcohol (refactored)`
IF  `is commercial enterprise` person
    AND NOT `is exempt establishment` person
    AND `has disqualifying factors` person
```

This version is easier to understand and maintain—and the Step 4 scenarios run against it
unchanged, so you can check that the refactor changed nothing:

```l4
#ASSERT NOT `must not sell alcohol (refactored)` `the corporate pub`
#ASSERT `must not sell alcohol (refactored)` `the banned corporate`
#ASSERT NOT `must not sell alcohol (refactored)` `the clean corporate`
```

---

## Step 6: Add Documentation

Link back to the source legislation:

```l4
{-
Imaginary Alcohol Act 2024
==========================

Section 3 - Prohibition on Sale of Alcohol

This section implements the prohibition in s.3 which prevents
certain commercial entities from selling alcohol if they have
disqualifying factors (fraud, misleading info, or banning orders).

Exemptions:
- Public houses (s.3(c))
- Hotels (s.3(c))

Note: "unspent conviction" follows the Rehabilitation of Offenders
Act interpretation - see s.2 for definitions.
-}
```

---

## Complete Example

Here's the full file. It is also saved beside this tutorial as
[alcohol-act-example.l4](alcohol-act-example.l4), which `doc/test-docs.sh` runs:

```l4
§ `Imaginary Alcohol Act - Section 3`

{-
Implements Section 3 of the Imaginary Alcohol Act 2024.
Determines whether a person is prohibited from selling alcohol.

The facts about the person are bundled into one record and passed as a
GIVEN parameter, so the rule can be tested in this file (see `Tests`).
Facts declared with ASSUME instead have no value until the rule is
deployed via jl4-service, which binds them from each request.
-}

-- Facts about the person (from user input or database)
DECLARE Person
    HAS `is a body corporate` IS A BOOLEAN
        `engages in business for profit` IS A BOOLEAN
        `is a public house` IS A BOOLEAN
        `is a hotel` IS A BOOLEAN
        `has an unspent conviction for fraud` IS A BOOLEAN
        `has an unspent conviction for providing misleading information` IS A BOOLEAN
        `has an alcohol banning order` IS A BOOLEAN

§§ `Sub-rules`

GIVEN person IS A Person
DECIDE `is commercial enterprise`
IF  person's `is a body corporate`
    AND person's `engages in business for profit`

GIVEN person IS A Person
DECIDE `is exempt establishment`
IF  person's `is a public house`
    OR person's `is a hotel`

GIVEN person IS A Person
DECIDE `has disqualifying factors`
IF  person's `has an unspent conviction for fraud`
    OR person's `has an unspent conviction for providing misleading information`
    OR person's `has an alcohol banning order`

§§ `Main Rule`

GIVEN person IS A Person
DECIDE `must not sell alcohol`
IF  `is commercial enterprise` person
    AND NOT `is exempt establishment` person
    AND `has disqualifying factors` person

§§ `Tests`

`the corporate pub` MEANS Person WITH
    `is a body corporate` IS TRUE
    `engages in business for profit` IS TRUE
    `is a public house` IS TRUE
    `is a hotel` IS FALSE
    `has an unspent conviction for fraud` IS TRUE
    `has an unspent conviction for providing misleading information` IS FALSE
    `has an alcohol banning order` IS FALSE

`the banned corporate` MEANS Person WITH
    `is a body corporate` IS TRUE
    `engages in business for profit` IS TRUE
    `is a public house` IS FALSE
    `is a hotel` IS FALSE
    `has an unspent conviction for fraud` IS FALSE
    `has an unspent conviction for providing misleading information` IS FALSE
    `has an alcohol banning order` IS TRUE

-- Exempt: public house
#ASSERT NOT `must not sell alcohol` `the corporate pub`

-- Prohibited: has banning order
#ASSERT `must not sell alcohol` `the banned corporate`
```

---

## Tips for Encoding Legislation

### 1. Preserve Legal Language

Use the exact terms from the legislation where possible:

```l4
-- ✅ Good: matches statute
ASSUME `the person is a body corporate` IS BOOLEAN

-- ❌ Less good: paraphrased
ASSUME isCompany IS BOOLEAN
```

### 2. Carry Inert Text — Recitals, Preambles, Purpose Clauses

Not every part of a legal document is a rule. Recitals, preambles, "WHEREAS"
clauses, purpose statements, statements of principle — the throat-clearing at
the start of a chapter — gate no decision and compute nothing. But an
_isomorphic_ encoding (one that mirrors the source, so a lawyer can check it
line-by-line) still has to carry them, verbatim and correctly numbered.

Reach for the `hierarchy` library. An outline is a tree of **strings**
(`item "…"`), authored as a bullet list and rendered with automatic numbering.
Each item is just text — never evaluated — so it may say anything, including
wording that would never be valid L4 logic:

```l4
IMPORT hierarchy

`recital scheme` MEANS LIST UpperAlpha, Decimal, LowerRoman

`recitals` MEANS
  item "RECITALS"
    • item "the Company is engaged in the business of software development;"
    • item "the Consultant has expertise in legal engineering; and"
    • item "the parties wish to record the terms of their engagement, namely"
      • item "the scope of services;"
      • item "the fees payable; and"
      • item "the term and termination."

#EVAL `render outline` `recital scheme` `recitals`
```

The heading is carried verbatim; the rest is numbered by depth — you pick the
_style_ per level (`recital scheme` is upper-alpha, then decimal, then
lower-roman) and the renderer assigns the actual markers:

```
RECITALS
A      the Company is engaged in the business of software development;
B      the Consultant has expertise in legal engineering; and
C      the parties wish to record the terms of their engagement, namely
C.1    the scope of services;
C.2    the fees payable; and
C.3    the term and termination.
```

**The rule of thumb.** Ask of each passage: _does it gate any decision, or
compute any value?_ If no — it's inert. Don't force it into a `DECIDE` or an
`ASSUME` (there's no proposition to decide, no fact to assume); don't drop it
either (you'd lose fidelity). Capture it as a `hierarchy` outline instead. The
`•` bullet nests children under a parent to any depth with no `LIST` literal
and no parentheses; when drafting needs an irregular sequence — an inserted
"2A", a restart — `labeled`, `numbered`, and `restartAt` pin or reset a marker
without disturbing its neighbours. See
[Optimising Natural-Language Generation](../natural-language-functions/optimising-natural-language-generation.md#literal-recitals--carrying-prose-that-isnt-computed)
for the contrast with `@nlg` (which renders prose _from_ logic; recitals are
prose that simply _is_).

### 3. Handle "And/Or" Carefully

Legal "or" is often inclusive (any one or more):

```l4
-- "A, B, or C" usually means "A OR B OR C"
condition1 OR condition2 OR condition3
```

### 4. Watch for Implicit Negation

"not a public house or hotel" can be ambiguous:

```l4
-- Could mean: NOT (public house OR hotel)
NOT (`is public house` OR `is hotel`)

-- Or: (NOT public house) OR (NOT hotel)  -- usually not intended
```

### 5. Test Edge Cases

- All conditions true
- All conditions false
- Each exemption independently
- Each disqualifying factor independently

---

## What You Learned

- How to analyze legal text structure
- How to use ASSUME for external facts—and where their values come from
- How to encode AND/OR conditions
- How to carry inert recital/preamble text as a `hierarchy` outline
- How to refactor for readability
- How to test legislative rules with a `GIVEN` record and `#ASSERT`

---

## Next Steps

- [Common Patterns](../../reference/patterns/common-patterns.md) - More L4 patterns
- [Foundation Course Module 1](../../courses/foundation/module-1-first-rule.md) - Deep dive on legal rules
- [LLM Integration](../llm-integration/llm-getting-started.md) - LLM-assisted encoding
