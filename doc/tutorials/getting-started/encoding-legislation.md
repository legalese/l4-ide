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

Test the rule with specific scenarios:

```l4
§ `Test Cases`

{-
Scenario 1: Corporate pub (exempt)
- Body corporate: Yes
- For profit: Yes
- Public house: Yes (exempt!)
Expected: FALSE (not prohibited because it's a public house)
-}
#CHECK `the person must not sell alcohol` WITH
    `the person is a body corporate` IS TRUE,
    `the person engages in business for profit` IS TRUE,
    `the person is a public house` IS TRUE,
    `the person is a hotel` IS FALSE,
    `the person has an unspent conviction for fraud` IS TRUE,
    `the person has an unspent conviction for providing misleading information` IS FALSE,
    `the person has an alcohol banning order` IS FALSE

{-
Scenario 2: Banned corporate (prohibited)
- Body corporate: Yes
- For profit: Yes
- Public house: No
- Hotel: No
- Banning order: Yes
Expected: TRUE (prohibited)
-}
#CHECK `the person must not sell alcohol` WITH
    `the person is a body corporate` IS TRUE,
    `the person engages in business for profit` IS TRUE,
    `the person is a public house` IS FALSE,
    `the person is a hotel` IS FALSE,
    `the person has an unspent conviction for fraud` IS FALSE,
    `the person has an unspent conviction for providing misleading information` IS FALSE,
    `the person has an alcohol banning order` IS TRUE

{-
Scenario 3: Clean corporate (not prohibited)
- Body corporate: Yes
- For profit: Yes
- No exemption, but no disqualifying factors
Expected: FALSE (not prohibited - no (d) condition met)
-}
#CHECK `the person must not sell alcohol` WITH
    `the person is a body corporate` IS TRUE,
    `the person engages in business for profit` IS TRUE,
    `the person is a public house` IS FALSE,
    `the person is a hotel` IS FALSE,
    `the person has an unspent conviction for fraud` IS FALSE,
    `the person has an unspent conviction for providing misleading information` IS FALSE,
    `the person has an alcohol banning order` IS FALSE
```

---

## Step 5: Refactor for Readability

For complex rules, break into named sub-rules:

```l4
§ `Refactored Version`

-- Sub-rule: Is this a commercial enterprise?
DECIDE `is commercial enterprise`
IF  `the person is a body corporate`
    AND `the person engages in business for profit`

-- Sub-rule: Is this an exempt establishment?
DECIDE `is exempt establishment`
IF  `the person is a public house`
    OR `the person is a hotel`

-- Sub-rule: Does person have disqualifying factors?
DECIDE `has disqualifying factors`
IF  `the person has an unspent conviction for fraud`
    OR `the person has an unspent conviction for providing misleading information`
    OR `the person has an alcohol banning order`

-- Main rule: Prohibition (refactored)
DECIDE `the person must not sell alcohol (refactored)`
IF  `is commercial enterprise`
    AND NOT `is exempt establishment`
    AND `has disqualifying factors`
```

This version is easier to understand and maintain.

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

Here's the full file:

```l4
§ `Imaginary Alcohol Act - Section 3`

{-
Implements Section 3 of the Imaginary Alcohol Act 2024.
Determines whether a person is prohibited from selling alcohol.
-}

-- External facts (from user input or database)
ASSUME `the person is a body corporate` IS BOOLEAN
ASSUME `the person engages in business for profit` IS BOOLEAN
ASSUME `the person is a public house` IS BOOLEAN
ASSUME `the person is a hotel` IS BOOLEAN
ASSUME `the person has an unspent conviction for fraud` IS BOOLEAN
ASSUME `the person has an unspent conviction for providing misleading information` IS BOOLEAN
ASSUME `the person has an alcohol banning order` IS BOOLEAN

§§ `Sub-rules`

DECIDE `is commercial enterprise`
IF  `the person is a body corporate`
    AND `the person engages in business for profit`

DECIDE `is exempt establishment`
IF  `the person is a public house`
    OR `the person is a hotel`

DECIDE `has disqualifying factors`
IF  `the person has an unspent conviction for fraud`
    OR `the person has an unspent conviction for providing misleading information`
    OR `the person has an alcohol banning order`

§§ `Main Rule`

DECIDE `the person must not sell alcohol`
IF  `is commercial enterprise`
    AND NOT `is exempt establishment`
    AND `has disqualifying factors`

§§ `Tests`

-- Exempt: public house
#CHECK NOT `the person must not sell alcohol` WITH
    `the person is a body corporate` IS TRUE,
    `the person engages in business for profit` IS TRUE,
    `the person is a public house` IS TRUE,
    `the person is a hotel` IS FALSE,
    `the person has an unspent conviction for fraud` IS TRUE,
    `the person has an unspent conviction for providing misleading information` IS FALSE,
    `the person has an alcohol banning order` IS FALSE

-- Prohibited: has banning order
#CHECK `the person must not sell alcohol` WITH
    `the person is a body corporate` IS TRUE,
    `the person engages in business for profit` IS TRUE,
    `the person is a public house` IS FALSE,
    `the person is a hotel` IS FALSE,
    `the person has an unspent conviction for fraud` IS FALSE,
    `the person has an unspent conviction for providing misleading information` IS FALSE,
    `the person has an alcohol banning order` IS TRUE
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
- How to use ASSUME for external facts
- How to encode AND/OR conditions
- How to carry inert recital/preamble text as a `hierarchy` outline
- How to refactor for readability
- How to test legislative rules

---

## Next Steps

- [Common Patterns](../../reference/patterns/common-patterns.md) - More L4 patterns
- [Foundation Course Module 1](../../courses/foundation/module-1-first-rule.md) - Deep dive on legal rules
- [LLM Integration](../llm-integration/llm-getting-started.md) - LLM-assisted encoding
