# Legislative Ingestion with a Large Language Model

Use a large language model (**"LLM"**) to help encode legislation in L4.

**Prerequisites:** [Getting Started with Large Language Models](llm-getting-started.md), intermediate L4 knowledge

---

## The words this page uses

A rule is told some facts about the case in front of it — the names listed
after `GIVEN` (its **"inputs"**) — and works out one answer from them (its
**"output"**, whose kind of thing is named after `GIVETH`). An input written
immediately above one rule is that rule's own (a **"rule GIVEN"**); an input
written once under a section heading, indented past the `§`, is shared by every
rule in the section (a **"section GIVEN"**).

Every example person on this page has a name — Alex — for the same reason a
law-school problem question names its parties: a worked example that says "the
person" six times is one nobody can follow. Where the statute's own words are
quoted, the statute's wording stands.

---

## The Challenge

Converting legislation to L4 involves four jobs:

1. **Understanding** the legal text
2. **Identifying** the kinds of thing it talks about, and the rules it lays down
3. **Writing** it out in L4
4. **Verifying** the encoding

An LLM can help with the first three. A person must do the fourth.

---

## The Workflow

```
┌──────────────────────────────────────────────┐
│ 1. SEGMENT: Break legislation into chunks    │
└──────────────────────────────────────────────┘
                      │
                      ▼
┌──────────────────────────────────────────────┐
│ 2. EXTRACT: LLM finds the kinds and the rules│
└──────────────────────────────────────────────┘
                      │
                      ▼
┌──────────────────────────────────────────────┐
│ 3. TRANSLATE: LLM generates L4 draft         │
└──────────────────────────────────────────────┘
                      │
                      ▼
┌──────────────────────────────────────────────┐
│ 4. VALIDATE: a person reviews; L4 accepts it │
└──────────────────────────────────────────────┘
                      │
                      ▼
┌──────────────────────────────────────────────┐
│ 5. ITERATE: Fix issues, re-validate          │
└──────────────────────────────────────────────┘
```

---

## Step 1: Segment the Legislation

Break legislation into manageable chunks. Each chunk should be:

- Self-contained (one concept)
- Referenced by section/article number
- Small enough for the LLM to hold in view at once

Segment inert passages — recitals, preambles, purpose clauses — _separately_
from operative rules, and flag them as such. They gate no decision and compute
nothing, so they are encoded as a `hierarchy` outline rather than as a `DECIDE`
or a `GIVEN`. See
[Encoding Legislation → Carry Inert Text](../getting-started/encoding-legislation.md#2-carry-inert-text--recitals-preambles-purpose-clauses).

### Example Legislation

```
Charities (Jersey) Law 2014

Article 2 - Interpretation
In this Law –
"charitable purpose" means any of the purposes specified in Schedule 1;
"charity" means an entity that is established for charitable purposes only;
"governor" means any person who is responsible for the control and
management of the administration of a registered charity;

Article 5 - Charity test
An entity meets the charity test if –
(a) all of its purposes are charitable purposes; and
(b) it satisfies the public benefit requirement.

Article 7 - Public benefit
(1) The public benefit requirement is that –
    (a) any benefit that may result from carrying out the purposes is
        a benefit to the public or a section of the public; and
    (b) any benefit to persons who are not members of the public but
        who have a material connection to the entity is not unduly
        favourable.
```

---

## Step 2: Extract Structure with LLM

### Prompt for Type Extraction

```
You are analyzing legislation to extract data types for encoding in L4.

Legislation text:
"""
Article 2 - Interpretation
In this Law –
"charitable purpose" means any of the purposes specified in Schedule 1;
"charity" means an entity that is established for charitable purposes only;
"governor" means any person who is responsible for the control and
management of the administration of a registered charity;
"""

Extract all defined terms as types. For each type, identify:
1. Name of the type
2. Whether it's an enumeration (fixed list) or record (has fields)
3. The fields or variants
4. Any referenced types

Output as JSON:
```

### Expected LLM Response

```json
{
  "types": [
    {
      "name": "CharitablePurpose",
      "kind": "enumeration",
      "note": "Variants from Schedule 1 - not defined here",
      "reference": "Schedule 1"
    },
    {
      "name": "Charity",
      "kind": "record",
      "fields": [
        {
          "name": "purposes",
          "type": "LIST OF CharitablePurpose",
          "constraint": "charitable only"
        }
      ]
    },
    {
      "name": "Governor",
      "kind": "record",
      "fields": [
        { "name": "person", "type": "Person" },
        { "name": "charity", "type": "RegisteredCharity" }
      ],
      "note": "responsible for control and management"
    }
  ]
}
```

---

## Step 3: Generate L4 Draft

### Prompt for L4 Generation

```
You are generating L4 code from legislative requirements.

L4 reference:
- Kinds of thing: DECLARE TypeName HAS field IS A FieldType
- Fixed lists of choices: DECLARE TypeName IS ONE OF Variant1, Variant2
- Rules: DECIDE `rule name` IF condition1 AND condition2
- Facts every rule in an article needs: a GIVEN on the line after the
  § heading, indented past the §

Requirement:
"""
Article 5 - Charity test
An entity meets the charity test if –
(a) all of its purposes are charitable purposes; and
(b) it satisfies the public benefit requirement.
"""

Types already defined:
- Charity: has purposes (LIST OF Purpose)
- Purpose: enumeration of charitable purposes

Generate L4 code with:
1. Declarations for any new kinds of thing
2. The main rule
3. Comments citing the article
```

### Expected LLM Response

```l4
-- Article 5: Charity test
-- An entity meets the charity test if:
-- (a) all of its purposes are charitable purposes; and
-- (b) it satisfies the public benefit requirement.

-- Both facts the Article works from, declared once for the whole Article:
-- the GIVEN is indented past the §, so it belongs to the section rather
-- than to the declaration below it.
§ `Article 5 - Charity test`
    GIVEN entity IS A Charity
          `satisfies public benefit` IS A BOOLEAN

GIVETH A BOOLEAN
DECIDE `meets charity test` IF
    `all purposes are charitable`        -- Art 5(a)
    AND `satisfies public benefit`       -- Art 5(b), see Art 7

-- Art 5(a): All purposes must be charitable
GIVETH A BOOLEAN
`all purposes are charitable` MEANS
    all (GIVEN p YIELD `is charitable purpose` p) (entity's purposes)

-- Art 5(b) is not encoded yet. Until Article 7 is written, the public
-- benefit requirement is a fact the caller supplies for each case.
```

`satisfies public benefit` is left as an unfilled blank on purpose. L4 accepts
the file as it stands, and a rule marked `@export` — published as a service
people and other programs can ask — asks the caller for that fact alongside the
entity. The blank is honest: it says the public benefit requirement has not been
encoded yet, rather than pretending an answer.

Earlier drafts of this tutorial declared such blanks with `ASSUME` at the left
margin. `ASSUME` is deprecated for that job (ruled 2026-09-04) and still works,
so files written that way keep running; new encodings put the blank under the
heading of the article that reads it, as a section `GIVEN`. See
[the section `GIVEN`](../../reference/syntax/section-given.md).

---

## Step 4: Validate and Refine

### Check That L4 Accepts It

Run the checker:

```bash
l4 check charity-test.l4

# Or from a Haskell checkout
cabal run l4 -- check charity-test.l4
```

### Common Issues

| LLM Output              | Problem                             | Fix                                        |
| ----------------------- | ----------------------------------- | ------------------------------------------ |
| `purposes IS A Purpose` | Should be a list                    | `purposes IS A LIST OF Purpose`            |
| Missing GIVETH          | The rule's output has no kind named | Add `GIVETH A BOOLEAN`                     |
| `IF x = TRUE`           | Redundant                           | Write `IF x`                               |
| Wrong field access      | Missing 's                          | `entity's purposes`, not `entity purposes` |

### Human Review Checklist

- [ ] Types match legislation definitions
- [ ] Rules capture all conditions
- [ ] Inert text (recitals, preambles) is carried as an outline, not dropped
- [ ] Cross-references are correct
- [ ] Edge cases are handled
- [ ] L4 accepts the file with no errors

---

## Step 5: Iterate

Feed validation errors back to LLM:

```
The L4 checker reported this error:

Error: Type 'Purpose' not in scope
Location: line 12

Current code:
all (GIVEN p YIELD `is charitable purpose` p) (entity's purposes)

Available types:
- CharitablePurpose
- Charity
- Entity

Fix the type name.
```

---

## Complete Example

### Input Legislation

```
Article 19 - Disqualification of governors
(1) A person is disqualified from acting as a governor of a charity if –
    (a) the person is an undischarged bankrupt;
    (b) the person has an unspent conviction for an offence involving
        dishonesty or deception;
    (c) the person is disqualified from acting as a company director; or
    (d) the person is subject to a disqualification order under Article 23.
```

### LLM-Generated L4 (After Refinement)

```l4
§ `Article 19 - Governor Disqualification`

-- Types for disqualification grounds
DECLARE DisqualificationGround IS ONE OF
    Bankruptcy                           -- Art 19(1)(a)
    UnspentConviction HAS offence IS A STRING  -- Art 19(1)(b)
    DirectorDisqualification             -- Art 19(1)(c)
    DisqualificationOrder HAS orderRef IS A STRING  -- Art 19(1)(d)

-- Person record for governors
DECLARE Person
    HAS name IS A STRING
        isBankrupt IS A BOOLEAN
        convictions IS A LIST OF Conviction
        isDirectorDisqualified IS A BOOLEAN
        disqualificationOrders IS A LIST OF STRING

DECLARE Conviction
    HAS offence IS A STRING
        isSpent IS A BOOLEAN
        involvesDishonesty IS A BOOLEAN

-- Article 19(1)(a): Bankruptcy
GIVEN alex IS A Person
GIVETH A BOOLEAN
`is undischarged bankrupt` MEANS alex's isBankrupt

-- Article 19(1)(b): Unspent conviction for dishonesty
GIVEN alex IS A Person
GIVETH A BOOLEAN
`has disqualifying conviction` MEANS
    any (GIVEN c YIELD
        c's involvesDishonesty
        AND NOT c's isSpent
    ) (alex's convictions)

-- Article 19(1)(c): Director disqualification
GIVEN alex IS A Person
GIVETH A BOOLEAN
`is director disqualified` MEANS alex's isDirectorDisqualified

-- Article 19(1)(d): Disqualification order
GIVEN alex IS A Person
GIVETH A BOOLEAN
`has disqualification order` MEANS
    length (alex's disqualificationOrders) > 0

-- Main rule: Article 19(1)
GIVEN alex IS A Person
GIVETH A BOOLEAN
DECIDE `is disqualified as governor` IF
    `is undischarged bankrupt` alex          -- (a)
    OR `has disqualifying conviction` alex   -- (b)
    OR `is director disqualified` alex       -- (c)
    OR `has disqualification order` alex     -- (d)
```

Note the name. `GIVEN alex IS A Person` reads as a name and a kind — Alex, who
is a person — where `GIVEN person IS A Person` reads as a tautology and hides
which of the two words is the name. Article 19 itself says "a person", and
keeps saying it, because the Article is addressed to whoever turns up. A worked
encoding is addressed to a reader, and a reader needs somebody to picture.

---

## Best Practices

### 1. Chunk Size

- One article/section per prompt
- Include cross-references in context

### 2. Iterative Refinement

- Start with types
- Then rules
- Then edge cases

### 3. Human-in-the-Loop

- Always check the LLM's output yourself
- Run the checker
- Try real cases with `#EVAL` and `#EVALTRACE`

### 4. Version Control

- Track both source legislation and L4
- Document which LLM/version used
- Keep prompts for reproducibility

---

## Limitations

- An LLM can invent a legal interpretation that sounds right and is not
- Complicated cross-references are often missed
- Human expertise is still essential
- Every output needs checking

---

## What You Learned

- A workflow for encoding legislation with an LLM's help
- How to prompt for the kinds of thing a statute talks about
- How to prompt for the L4 itself
- How to check the result and go round again

---

## Next Steps

- [Getting Started with Large Language Models](llm-getting-started.md) - The basics
- [Advanced Course Module A1](../../courses/advanced/module-a1-regulatory.md) - Manual legislative encoding
- Practice with real legislation from your jurisdiction
