# Design principles

The principles that guide L4's design, and the style of writing L4 that follows from them.

---

## Overview

L4 is designed around five principles:

1. **Legal Isomorphism** - L4 structure mirrors legal text structure
2. **Human Readability** - Code should be readable by lawyers
3. **Formal Precision** - Unambiguous, machine-checkable semantics
4. **Accessibility** - Usable by non-programmers
5. **Composability** - Small pieces combine into larger systems

These principles sometimes pull against each other. The art of language design is finding the right balance.

---

## Principle 1: Legal Isomorphism

**L4 code should look like the legal text it encodes.**

### Why?

- **Traceability**: Easy to map code to source legislation
- **Review**: Lawyers can verify correctness without learning to code
- **Maintenance**: Changes in law map to changes in code

### Example

Legal text:

> Alcohol prohibition rule:
> A person shall not buy alcohol if the person is not at least 18 years of age.

L4 code:

```l4
DECLARE Person HAS
    age IS A NUMBER

DECLARE Action IS ONE OF `buy alcohol`

GIVEN person IS A Person
GIVETH A DEONTIC Person Action
`Alcohol prohibition rule` MEANS
    IF      NOT person's age AT LEAST 18
    THEN    PARTY  person
            SHANT  `buy alcohol`
    ELSE    FULFILLED
```

The wording of the L4 can follow the wording of the original.

### Implications

- Keywords read like legal English (MUST, MAY, SHANT)
- Backtick identifiers allow natural-language names
- Conditions use legal phrasing, not programmer conventions

[Reading like the law](linguistic-syntax.md) shows the features that make this possible.

---

## Principle 2: Human Readability

**Code should be understandable by legal professionals.**

### Why?

- **Domain experts** should validate the encoding
- **Stakeholders** need to understand what rules do
- **Auditors** must verify compliance

### Design Choices

**Layout sensitivity.** As in Python, indentation shows the structure:

```l4
DECLARE Person
    HAS name IS A STRING
        age IS A NUMBER
```

**Words rather than symbols.** L4 writes `IS A` where other languages write `:`, `MEANS` where they write `=`, and offers `AND`, `OR`, `NOT`, `EQUALS`, `AT LEAST` and `PLUS` beside `&&`, `||`, `>=` and `+`:

```l4
GIVEN `the applicant's age` IS A NUMBER
      `the applicant has valid identification` IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `the applicant may apply` IF
        `the applicant's age` AT LEAST 18
    AND `the applicant has valid identification`
```

### Trade-offs

- More typing than terse syntax
- Longer files
- But: far more accessible to non-programmers

---

## Principle 3: Formal Precision

**Every L4 program has unambiguous, machine-checkable meaning.**

### Why?

- **Computation**: Rules can be executed to get decisions
- **Verification**: Rules can be checked for consistency
- **Explanation**: Traces of the reasoning can be produced

### Design Choices

**Strong static typing.** `GIVEN` and `GIVETH` state what goes in and what comes out, and the type checker holds every rule to them before anything runs.

**Exhaustive pattern matching.** A `CONSIDER` over an enumeration should handle every case, and L4 warns when one is missing:

```l4
DECLARE `account status` IS ONE OF Active, Suspended, Terminated

GIVEN status IS AN `account status`
GIVETH A STRING
`the status message` MEANS
    CONSIDER status
    WHEN Active     THEN "The account is active"
    WHEN Suspended  THEN "The account is suspended"
    WHEN Terminated THEN "The account is closed"
```

Leave out a `WHEN` and L4 lists the missing case. Over a `NUMBER`, a `STRING` or a `DATE`, whose values cannot be listed, it asks for an `OTHERWISE`. See [Exhaustiveness](../type-system/exhaustiveness.md).

**No implicit behaviour.** An `IF` always has an `ELSE`; there is no "null" to fall back on.

### Trade-offs

- More explicit code
- Sometimes verbose
- But: no surprises, and every rule can be audited

---

## Functional purity

L4 decision logic is written as functions: every fact a decision depends on comes in through its `GIVEN`. This is a feature, not a limitation.

### The signature lists the factors

A rule's signature says exactly what information it needs:

```
GIVEN `the applicant` IS A Person
      `today` IS A DATE
GIVETH A BOOLEAN
DECIDE `the application is timely` IF ...
```

To decide whether an application is timely, this rule needs to know who the applicant is and what today's date is, and nothing else.

### "It depends", on what exactly?

Legal text often leaves its dependencies implicit: "the applicant is eligible if they are a resident". Resident of where, and for how long? L4 makes you answer, and the answer becomes part of the rule:

```l4
DECLARE Person HAS
    `country of residence` IS A STRING
    `years of residence` IS A NUMBER

GIVEN `the applicant` IS A Person
      `the jurisdiction` IS A STRING
GIVETH A BOOLEAN
DECIDE `the applicant is eligible` IF
    `the applicant is a resident of the jurisdiction`
    WHERE
        `the applicant is a resident of the jurisdiction` MEANS
                `the applicant`'s `country of residence` EQUALS `the jurisdiction`
            AND `the applicant`'s `years of residence` AT LEAST 5
```

When someone says "it depends", L4 makes them say what it depends on. Because the signature lists every factor that affects the decision, the rule is:

- **Auditable**: you can trace exactly what information influenced a decision.
- **Testable**: you know exactly which inputs to vary in your test cases.
- **Maintainable**: when requirements change, you know which dependencies to update.
- **Explainable**: you can show stakeholders exactly which factors matter.

### Passing facts along

If a sub-decision needs a fact, the rule that uses it must pass the fact in. A helper cannot quietly look up the date or a setting of its own. Prefer passing the date in as an input over reading the clock with `TODAY`, so the answer depends only on what the rule was given. This can feel verbose, but it is transparency, not bureaucracy: every fact that influences the outcome is visible in the code.

---

## Principle 4: Accessibility

**L4 should be usable by domain experts, not just programmers.**

### Why?

- **The knowledge is with lawyers**, not programmers
- **Validation requires understanding**: you can't validate what you can't read
- **Maintenance**: laws change, and updates shouldn't require programmers

### Design Choices

- **No installation to start.** The web editor runs L4 in a browser.
- **Familiar constructs.** `IF … THEN … ELSE`, lists written as `LIST 1, 2, 3`, and keywords that are English words.
- **Names in the reader's language.** Backtick identifiers let a rule use the same words as the text it encodes.

### Trade-offs

- May feel limiting to experienced programmers
- Some advanced patterns are not directly supported
- But: a much lower barrier to entry

---

## Principle 5: Composability

**Small pieces should combine predictably into larger systems.**

### Why?

- **Real legal systems are large**: thousands of rules
- **Reuse**: the same patterns appear again and again
- **Testing**: small parts can be tested on their own

### Design Choices

**Functions are first-class, and complex expressions decompose into named parts with `WHERE`:**

```l4
IMPORT prelude

GIVEN `the amounts` IS A LIST OF NUMBER
GIVETH A LIST OF NUMBER
`the amounts with tax` MEANS
    map (GIVEN amount YIELD amount TIMES `the tax factor`) `the amounts`
    WHERE
        `the tax rate`   MEANS 0.09
        `the tax factor` MEANS 1 PLUS `the tax rate`
```

**Modules.** `IMPORT` brings in libraries such as `prelude` and `daydate`, or another file of your own.

**Regulative combinators.** `RAND` joins two obligations that must both be fulfilled; `ROR` joins two of which either will do.

### Trade-offs

- More moving parts
- Needs good tooling support
- But: scales to real-world complexity

---

## Principle Tensions

### Readability vs Precision

Natural language is readable but ambiguous. In "a licence or a permit", is "or" inclusive (one or both) or exclusive (one but not both)? L4 keeps the natural keyword and gives it one precise meaning: `OR` is always inclusive.

### Accessibility vs Power

Simple syntax limits expressiveness. L4 offers simple syntax for the common cases (`IF`, `AND`, `OR`) and keeps the full power of a functional language (functions as values, recursion, `map` and `filter`) available when it is needed.

### Legal Isomorphism vs Consistency

Different drafters write differently: some texts say "shall not", others "must not". L4 accepts `SHANT` and `MUST NOT` as two spellings of one prohibition, so the code can follow whichever the source uses.

---

## Writing in the L4 style

The principles above lead to a few habits that make a rule easy to check against its source.

**Name things as the source does.** Write identifiers in natural language, inside backticks: `` `the applicant` ``, not `applicant`; `` `has valid identification` ``, not `hasValidID`. Do not use camelCase, snake_case or abbreviations. A function's name should read as a phrase: `` `the applicant is eligible for benefits` ``. A type is named after the legal category it models: `Person`, `` `registered charity` ``.

**Mirror the structure of the text.** One named rule per provision, `§` sections that follow the source's numbering, and a comment citing the article or section a rule encodes. When an exception refers to another provision, name that provision as its own rule (see [Exceptions and defaults](../legal-modeling/default-reasoning.md)).

**Prefer words in legal contexts.** `AND`, `OR`, `NOT`, `AT LEAST` and `PLUS` read better to a lawyer than `&&`, `||`, `>=` and `+`.

**Lay it out consistently.** Indent with spaces, never tabs, and align related items vertically. `l4 format` lays a file out for you; run it in a change of its own, so that reformatting never hides a change of meaning.

**Keep tests beside the rules.** Put a rule's `#EVAL`, `#ASSERT` and `#TRACE` checks in a `§§ Tests` section of the same file ([Test your rules](../../tutorials/getting-started/testing-your-rules.md)).

---

## Summary

| Principle         | Key Idea                 | Trade-off       |
| ----------------- | ------------------------ | --------------- |
| Legal Isomorphism | Mirror legal text        | Longer code     |
| Human Readability | Readable by lawyers      | More verbose    |
| Formal Precision  | Machine-checkable        | More explicit   |
| Functional purity | Every factor is an input | More parameters |
| Accessibility     | Domain-expert friendly   | Less "powerful" |
| Composability     | Small pieces combine     | More complexity |

---

## Further Reading

- [Reading like the law](linguistic-syntax.md) - The linguistic features behind legal isomorphism
- [Syntax and directives](../../reference/syntax/README.md) - Full syntax reference
- [Make rules read like law](../../tutorials/natural-language-functions/optimising-natural-language-generation.md) - Hands-on guide to readable rules
- [Foundation course](../../courses/foundation/README.md) - Learn L4 from scratch
