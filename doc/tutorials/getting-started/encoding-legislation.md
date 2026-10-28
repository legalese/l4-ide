# Encode legislation

Turn a legal provision into L4 that mirrors the text, test it, and use an AI assistant to draft larger pieces.

**Before you start:** [Install L4 and write your first rule](first-l4-file.md) and [Test your rules](testing-your-rules.md).

**Complete example:** [encoding-legislation-example.l4](encoding-legislation-example.l4)

---

## The provision

We will encode this section of an imaginary Alcohol Act:

> **Section 3.** A person must not sell alcohol if:
> (a) the person is a body corporate;
> (b) the person engages in business for profit;
> (c) the person is not a public house or hotel; and
> (d) any of the following applies:
> (i) the person has an unspent conviction for fraud;
> (ii) the person has an unspent conviction for providing misleading information; or
> (iii) the person has an alcohol banning order.

---

## Step 1: Analyse the structure

Before writing code, find:

1. **The outcome**: "must not sell alcohol".
2. **The conditions**: (a), (b), (c) and (d), which must all hold.
3. **The alternatives**: (d)(i), (d)(ii) and (d)(iii), of which any one is enough.

The logical shape is:

```
(a) AND (b) AND (c) AND ((d)(i) OR (d)(ii) OR (d)(iii))
```

---

## Step 2: Write the rule

Each fact the section depends on becomes an input, named in the words of the statute. Each condition becomes one line, with a comment pointing to its paragraph:

```l4
§ `Imaginary Alcohol Act 2024, section 3`

GIVEN `the person is a body corporate`                                            IS A BOOLEAN
      `the person engages in business for profit`                                 IS A BOOLEAN
      `the person is a public house`                                              IS A BOOLEAN
      `the person is a hotel`                                                     IS A BOOLEAN
      `the person has an unspent conviction for fraud`                            IS A BOOLEAN
      `the person has an unspent conviction for providing misleading information` IS A BOOLEAN
      `the person has an alcohol banning order`                                   IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `the person must not sell alcohol` IF
        `the person is a body corporate`                                              -- (a)
    AND `the person engages in business for profit`                                   -- (b)
    AND NOT (`the person is a public house` OR `the person is a hotel`)               -- (c)
    AND (    `the person has an unspent conviction for fraud`                         -- (d)(i)
         OR  `the person has an unspent conviction for providing misleading information` -- (d)(ii)
         OR  `the person has an alcohol banning order`)                               -- (d)(iii)
```

| Legal text                                  | L4                                                                  |
| ------------------------------------------- | ------------------------------------------------------------------- |
| "the person is a body corporate"            | `` `the person is a body corporate` ``                              |
| "the person is not a public house or hotel" | ``NOT (`the person is a public house` OR `the person is a hotel`)`` |
| "any of the following applies"              | `( ... OR ... OR ... )`                                             |

The facts are `GIVEN` inputs, so a caller, a test or a deployed API supplies them. If you prefer to declare them once at the top of a file, see [ASSUME](../../reference/types/ASSUME.md).

---

## Step 3: Test it

Add tests that state the expected outcome. A rule can be called with its inputs named, ``rule WITH `input` IS value``, one input per line, which keeps long test cases readable:

```l4
-- A corporate pub is exempt under (c), even with a fraud conviction.
#ASSERT NOT `the person must not sell alcohol` WITH
    `the person is a body corporate`                                            IS TRUE
    `the person engages in business for profit`                                 IS TRUE
    `the person is a public house`                                              IS TRUE
    `the person is a hotel`                                                     IS FALSE
    `the person has an unspent conviction for fraud`                            IS TRUE
    `the person has an unspent conviction for providing misleading information` IS FALSE
    `the person has an alcohol banning order`                                   IS FALSE

-- A company with a banning order is prohibited.
#ASSERT `the person must not sell alcohol` WITH
    `the person is a body corporate`                                            IS TRUE
    `the person engages in business for profit`                                 IS TRUE
    `the person is a public house`                                              IS FALSE
    `the person is a hotel`                                                     IS FALSE
    `the person has an unspent conviction for fraud`                            IS FALSE
    `the person has an unspent conviction for providing misleading information` IS FALSE
    `the person has an alcohol banning order`                                   IS TRUE
```

`l4 run` prints `assertion satisfied` for each. Use `#ASSERT` (or `#EVAL` and compare the result yourself), not `#CHECK`: `#CHECK` only type-checks and never evaluates the rule.

Cover at least:

- each exemption on its own;
- each disqualifying factor on its own;
- the case where nothing in (d) applies;
- a person outside the section altogether, for example not a body corporate.

---

## Step 4: Name the parts

For longer provisions, give each part of the test a name. `WHERE` defines the parts after the rule, so the main condition reads like a summary of the section:

```l4
GIVEN `the person is a body corporate`                                            IS A BOOLEAN
      `the person engages in business for profit`                                 IS A BOOLEAN
      `the person is a public house`                                              IS A BOOLEAN
      `the person is a hotel`                                                     IS A BOOLEAN
      `the person has an unspent conviction for fraud`                            IS A BOOLEAN
      `the person has an unspent conviction for providing misleading information` IS A BOOLEAN
      `the person has an alcohol banning order`                                   IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `the person must not sell alcohol` IF
        `is a commercial enterprise`          -- (a) and (b)
    AND NOT `is an exempt establishment`      -- (c)
    AND `has a disqualifying factor`          -- (d)
    WHERE
        `is a commercial enterprise` MEANS
                `the person is a body corporate`
            AND `the person engages in business for profit`

        `is an exempt establishment` MEANS
                `the person is a public house`
            OR  `the person is a hotel`

        `has a disqualifying factor` MEANS
                `the person has an unspent conviction for fraud`
            OR  `the person has an unspent conviction for providing misleading information`
            OR  `the person has an alcohol banning order`
```

The inputs and the tests stay the same, so the tests from Step 3 confirm that the refactored rule still means the same thing.

---

## Tips

**Keep the statute's words.** `` `the person is a body corporate` `` lets a lawyer check the rule against the text; `isCompany` does not.

**Read "or" carefully.** In legislation, "A, B or C" usually means any one or more of them: `A OR B OR C`.

**Watch negations.** "Not a public house or hotel" normally means neither: `NOT (pub OR hotel)`. The other reading, `NOT pub OR NOT hotel`, is true for almost everyone and is rarely intended. When the text is ambiguous, write down which reading you chose, in a comment or a test.

**Keep the source next to the code.** The complete example puts the text of section 3 in a `{- ... -}` comment above the rule and marks each condition with its paragraph number.

---

## Drafting with an AI assistant

An AI assistant can draft L4 from legislation quickly, but it can also misread the law. Use it for the first draft, and let the type checker and a human reviewer decide whether the draft is right. In VS Code, Legalese AI already knows L4 syntax and sees the type checker's errors after every edit; see [Draft rules with Legalese AI](../llm-integration/composing-l4-with-ai.md). The prompts below work with any assistant.

### The workflow

1. **Segment.** Split the legislation into self-contained pieces: one article or section each, with its number, and with the definitions it uses.
2. **Extract.** Ask the assistant for the types and inputs the piece needs.
3. **Draft.** Ask for the L4 rule.
4. **Check.** Run `l4 check`, then the tests, then review the draft against the text.
5. **Iterate.** Give the errors and your review notes back to the assistant.

### Prompt: extract types

```
You are analysing legislation to encode it in L4, a programming language
for law.

Legislation:
"""
Article 2 - Interpretation
In this Law -
"charitable purpose" means any of the purposes specified in Schedule 1;
"charity" means an entity that is established for charitable purposes only;
"governor" means any person who is responsible for the control and
management of the administration of a registered charity;
"""

List every defined term that should become a type. For each, say:
1. its name;
2. whether it is a fixed list of choices or a record with fields;
3. its choices or fields, with their types;
4. which other types or provisions it refers to.
```

### Prompt: draft the rule

```
Write L4 for the provision below.

L4 basics:
- Records: DECLARE Charity HAS `purposes` IS A LIST OF Purpose
- Choices: DECLARE Purpose IS ONE OF `relief of poverty`, `advancement of education`
- Rules: GIVEN `the entity` IS A Charity
         GIVETH A BOOLEAN
         DECIDE `meets the charity test` IF ... AND ...
- Names with spaces go in backticks; fields are read with 's.
- List functions such as all, any, map and filter need IMPORT prelude.

Provision:
"""
Article 5 - Charity test
An entity meets the charity test if -
(a) all of its purposes are charitable purposes; and
(b) it satisfies the public benefit requirement.
"""

Types already defined:
- Charity, with `purposes` (a LIST OF Purpose)
- Purpose, a list of the charitable purposes

Use the words of the provision as names. Mark each condition with a
comment giving its paragraph, and add #ASSERT tests for each paragraph.
```

### Prompt: fix an error

Paste the checker's message exactly as `l4 check` printed it:

```
l4 check reported this error:

    I could not find a definition for the identifier

      Purpose

The types defined in the file are CharitablePurpose and Charity.
Fix the draft and explain the change.
```

### Problems to look for

| In the draft                                 | Problem                   | Fix                                  |
| -------------------------------------------- | ------------------------- | ------------------------------------ |
| `purposes IS A Purpose`                      | Should be a list          | `purposes IS A LIST OF Purpose`      |
| `entity purposes`                            | Field access without `'s` | `entity's purposes`                  |
| `IF x = TRUE`                                | Redundant comparison      | `IF x`                               |
| `x == 5`                                     | Not L4                    | `x = 5` or `x EQUALS 5`              |
| `any`, `all`, `map` without `IMPORT prelude` | Unknown name              | Add `IMPORT prelude` at the top      |
| `#CHECK rule WITH ...` used as a test        | `#CHECK` only type-checks | `#ASSERT rule WITH ...`              |
| An exception the text does not contain       | Invented law              | Remove it, or record why it is there |

### Review checklist

- Types and names match the definitions in the legislation.
- Every condition in the text appears in the rule, and nothing else does.
- Cross-references point to the right provisions.
- There are tests for each paragraph and for the edges (thresholds, empty lists, exemptions).
- `l4 check` passes and every `#ASSERT` is satisfied.

**Example:** a reviewed draft of a governor-disqualification article, with its tests: [governor-disqualification-example.l4](governor-disqualification-example.l4)

### Keep a record

Commit the source text, the prompts and the L4 together, and note which assistant produced the draft. [Manage rules in git and CI](version-control-for-rules.md) shows how.

An assistant can misread a legal structure, miss a cross-reference, or invent an interpretation. A draft that type-checks can still be wrong: only the tests and the review show whether it says what the law says.

---

## Next steps

- [Common patterns](common-patterns.md): more ways to structure rules.
- [Make rules read like law](../natural-language-functions/optimising-natural-language-generation.md): names and shapes that render as readable prose.
- [Real regulatory schemes](../../courses/advanced/module-a1-regulatory.md): a longer encoding exercise in the Advanced course.
