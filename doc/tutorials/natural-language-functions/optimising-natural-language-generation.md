# Optimising for Natural Language Document Generation

L4 can render your rules back into formatted English prose — in the VS Code
**Render** tab, or with `l4 render`. The renderer is **deterministic**: it walks
your code and turns each construct into a sentence or an outline. That means the
quality of the generated prose is mostly in your hands. Well-named, well-shaped
rules read almost like professionally drafted legal writing with no extra effort; awkward ones read like a
transcript of an algorithm.

This tutorial shows how to get transparent English prose out of the renderer, using three increasingly powerful levers:

1. **Names** — backticked identifiers and parameter names.
2. **Shape** — mixfix word order, control flow, section titles, and arithmetic.
3. **`@nlg`** — an authored sentence that overrides the structural rendering.

It finishes with how **Legalese AI** can then apply drafting policies to refine
the result further.

## Prerequisites

- Basic L4 functions (see [Your First L4 File](../getting-started/first-l4-file.md))
- [Infix, Postfix, and Mixfix Functions](natural-language-functions.md) — the
  calling-syntax foundation this tutorial builds on

---

## Lever 1 — Choose Names Wisely

> *"Names reflect true understanding of a thing, and when you truly understand a thing you have power over it."*
>
> — Patrick Rothfuss, *The Wise Man's Fear*

The renderer prints identifiers and parameter names **verbatim**. Good names are
the single highest-leverage thing you can do.

### Name rules as the phrase you want to read

A backticked identifier can contain spaces. So you can spell out a noun phrase or clause:

```l4
-- Descriptive: "Monthly property tax means ..."
`monthly property tax` MEANS ...

-- Cryptic: "Mpt means ..."
mpt MEANS ...
```

> [!NOTE]
> Beginner programmers are routinely and pointedly reminded to use the first form whenever they reach for the latter. In the heat of the moment, short forms make sense; six months later, they don't.

### Name parameters as nouns, not letters

Parameters appear in the rendered prose and in every `@nlg` slot. Name them the
way they should read:

```l4
-- Descriptive: "... the buyer ... the seller ..."
GIVEN `the buyer`  IS A Person
      `the seller` IS A Person

-- Cryptic: "... p ... q ..."
GIVEN p IS A Person
      q IS A Person
```

To be fair: sometimes existing legal writing will deliberately adopt this "variable" form: "A person (A) discriminates against another (B) if ..." (Equality Act 2010, s.13). In that situation the renderer will aim to obey the "legislative variable" style.

> [!NOTE]
> If a parameter has a record type, the renderer promotes the type name into a noun phrase: ``GIVEN claim IS A `Payment Claim` `` renders as "the payment claim". This works cleanly only when one parameter has that type — two `Payment Claim` parameters would collide on the same phrase.

### Name record fields readably

Attribute accessors render as ``X's `fieldname` ``, so field names carry straight into the prose.

```l4
DECLARE Region IS ONE OF central, suburban, rural

DECLARE `Property` HAS
     `market value`       IS A NUMBER
     `school district`    IS A Region
```

A piece of code could refer as follows:

``` l4
GIVEN residence IS A `Property`
DECIDE `property tax` IS residence's `market value` TIMES `school district tax`
  WHERE `school district tax` MEANS
          CONSIDER residence's `school district`
            WHEN  central  THEN 6%
            ^     suburban THEN 4%
            ^     rural    THEN 2%
```

This renders as follows:

- Property tax equals the property's market value × school district tax, where:
  - School district tax is determined by the property's school district:
    - if it is central: 6%
    - if it is suburban: 4%
    - if it is rural: 2%

---

## Lever 2 — Shape the code so it reads naturally

### Use mixfix so calls read as sentences

Put the words and the argument holes where they belong in the sentence. (See the
[mixfix tutorial](natural-language-functions.md) for the full mechanics.)

```l4
DECLARE Person HAS
  name IS A STRING
  age  IS A NUMBER

DECLARE Programme HAS title IS A STRING

GIVEN `application date` IS A DATE
      `the applicant` IS A Person
      `the programme` IS A Programme
GIVETH A BOOLEAN
`as at` `application date` `the applicant` `is eligible for` `the programme` MEANS
  `the applicant`'s age >= 65
```

In a conventional programming language, this would be a function taking three arguments: `eligibility(date, applicant, programme)`.

In L4, it is also a function taking three arguments, but the arguments are interspersed together with the function name for improved readability.

The function would be called thusly:
``` l4
#EVAL `as at` (January 1 2010) `Alice Apple` `is eligible for` `retirement benefits`
```

And the natural language would generate like:

```
As at application date the applicant is eligible for the programme if the person's age is at least 65.
```

### End helper names in a preposition

When a function name does not end in a preposition, the renderer joins it with its
arguments -- using the word "with". That can read naturally for past-participle names:

```l4
DECLARE `Base Benefit` HAS amount IS A NUMBER
DECLARE Supplement     ^   ^      ^  ^ ^

GIVEN x IS A `Base Benefit`
      y IS A Supplement
`augmented` x y MEANS x's amount + y's amount
-- definition renders as: "Augmented equals the base benefit's amount + the supplement's amount."

`standard pension`          MEANS `Base Benefit` WITH amount IS 1000
`cost of living allowance`  MEANS Supplement     WITH amount IS 200

DECIDE `total benefit` IS
  `augmented` `standard pension` `cost of living allowance`
-- call site renders as: "Total benefit means augmented with standard pension and cost of living allowance."
```

The call site surfaces the argument names, but the word order is still driven by the function name. In Lever 3 we will return to this example and use `@nlg` to rearrange the words so the sentence reads more naturally.

The "with" convention becomes awkward when the name is a noun phrase:

```l4
`the later` x y MEANS IF x >= y THEN x ELSE y
-- by default, the call site renders as: "the later with start date and end date". Awkward.
```

The solution: end the name in a preposition (`of`, `for`, `to`,
`between`, …).

That preposition eliminates the "with" and lets the arguments
slot in naturally:

```l4
`the later of` x y MEANS IF x >= y THEN x ELSE y
-- call site renders as: "the later of start date and end date". Natural.
```

### Let control flow stay structured

`CONSIDER`, `IF`/`THEN`/`ELSE`, and `AND`/`OR` render as indented outlines, not
run-on sentences. Keep operative logic where the renderer can see it as
structure rather than burying it inside an unrelated expression:

```l4
CONSIDER claim's status
WHEN Paid    THEN ...
WHEN Overdue THEN ...
```

renders as

```
depending on the claim's status:
- if it is Paid: ...
- if it is Overdue: ...
```

### Keep arithmetic as arithmetic

Numeric expressions render in **formula mode** — with `+ − × ÷` and parentheses —
not as nested "the sum of the product of …". Write the maths directly instead of
wrapping it in prose helpers:

```l4
(`base rent` PLUS `service charge`) TIMES `months` PLUS `deposit`
-- "(base rent + service charge) × months + deposit"
```

Beyond three terms, you will get "sum" and "product".

### Group rules into titled sections

Section markers organise a document into titled, numbered sections — they become
headings in the rendered output and entries in the table of contents.

- `` § `Section Name` `` starts a top-level section.
- `` §§ `Subsection Name` `` nests one level deeper (`§§§` deeper still).

The name is backtick-quoted, so it can be a full phrase. Every declaration after
a marker belongs to that section until the next marker:

```l4
§ `Eligibility`

GIVEN `the applicant` IS A Person
`the applicant` `qualifies for EP` IF ...

§§ `Age requirements`

GIVEN `the applicant` IS A Person
`the applicant` `is of working age` IF ...
```

renders as

```
§ 1  Eligibility
    • The applicant qualifies for EP if ...
    1.1  Age requirements
        • The applicant is of working age if ...
```

The `§` numbers appear when **Number sections** is enabled in the Render tab
(or `--number-sections` on the CLI); the headings and table-of-contents entries
appear either way.

A flat file with no markers still gets sensible structure — its type
definitions and rules are grouped into automatic **Definitions** and
**Provisions** sections — but explicit `§`/`§§` markers let you name and order
the parts the way a reader of the contract or statute would expect. Imported
modules that carry their own section titles keep them, rendering under their own
heading rather than a generic one.

> [!NOTE]
> Section symbols are used for more than rendering text. Identifiers are organized into lexical scope under the section hierarchy. See [Section Markers (§)](../../reference/syntax/README.md#section-markers-) in the syntax reference.

---

## Lever 3 — `@nlg`: author the exact sentence

When structure and naming aren't enough — a recursive helper, domain
jargon, or a formula you'd rather state in words — attach an `@nlg`
annotation.

This gives you full control over the authoritative natural-language
form of that definition.

### Revisiting `augmented`

Recall from Lever 2 that the call site rendered as:

```
Total benefit means augmented with standard pension and cost of living allowance.
```

The argument names appear, but the word order is dictated by the function name. Adding an `@nlg` annotation with `%param%` slots lets you rearrange freely:

```l4
GIVEN x IS A `Base Benefit`
      y IS A Supplement
GIVETH A NUMBER
`augmented` x y   @nlg %y% based on %x%
  MEANS x's amount + y's amount
```

Now the definition renders as _"Augmented means y based on x"_, and the call site renders as:

```
Total benefit means cost of living allowance based on standard pension.
```

The arguments slot into exactly the positions you chose.

### Where it goes: end of the line

Write `@nlg` at the **end of the construct's line**, trailing the signature, with
the body on the next line:

```l4
GIVEN x IS A NUMBER, y IS A NUMBER
GIVETH A NUMBER
`the greater of` x y @nlg the greater of %x% and %y%
  MEANS IF x >= y THEN x ELSE y
```

### `%param%` slots

Inside the sentence, `%name%` refers to a parameter. The renderer fills each slot
with:

- the **parameter name** when it shows the definition itself, and
- the **actual argument** at each call site.

So the rule above renders as _"The greater of means the greater of x and y"_ in
its own definition, and a call `` `the greater of` `start date` `end date` ``
renders as _"the greater of the start date and the end date"_.

### It replaces the implementation

A function with an `@nlg` renders **as its sentence**, not as its body. This is
what makes recursive library functions readable — for example `filter` ships
with:

```l4
filter f list @nlg the items of %list% for which %f% holds
  MEANS ...
```

so ``filter `is eligible` applicants`` reads _"the items of applicants for
which is eligible holds"_ instead of exposing the recursion.

### When to reach for it

| Situation                                             | Why `@nlg` helps                                 |
| ----------------------------------------------------- | ------------------------------------------------ |
| Recursive / higher-order helpers                      | Hide the implementation behind a description     |
| Math you'd rather phrase in words                     | "the pro-rated premium" instead of the formula   |
| Domain terms of art                                   | Match the exact statutory or contractual wording |
| A name that can't be both valid code _and_ good prose | Decouple the two                                 |

### Tips

- Keep slots to the function's own parameters; the sentence should make sense
  with each slot read as a noun phrase.
- Prefer **naming and shape first**, `@nlg` second — an `@nlg` is a maintenance
  cost (it can drift from the logic), so reserve it for where it earns its keep.
- One sentence per definition. If you need branching prose, let the structure
  (`CONSIDER`/`IF`) render and annotate the leaves.

---

## Putting it together

Before — terse names, no annotations:

```l4
GIVEN p IS A NUMBER, r IS A NUMBER, n IS A NUMBER
GIVETH A NUMBER
pmt p r n MEANS p TIMES r DIVIDED BY (1 MINUS (1 PLUS r) EXPONENT (0 MINUS n))
```

renders as a bare formula with opaque single letters.

After — descriptive names plus one `@nlg`:

```l4
GIVEN `the principal` IS A NUMBER
      `the monthly rate` IS A NUMBER
      `the term in months` IS A NUMBER
GIVETH A NUMBER
`the monthly repayment on` `the principal`
    `at` `the monthly rate` `over` `the term in months`
    @nlg the level monthly repayment on %the principal% at %the monthly rate% over %the term in months%
  MEANS ...
```

Now both the definition and every call site read as a sentence a lawyer can check.

---

## Refining further with Legalese AI

The renderer gives you a faithful, deterministic baseline — the same input always
produces the same prose, and it never invents facts. That baseline is the right
foundation, but house style, tone, and jurisdiction conventions are editorial
choices that go beyond what deterministic rules should decide.

That is where **Legalese AI** comes in. Once your rendered output is accurate,
you can apply **drafting policies** — reusable style and language rules such as
"use plain English", "prefer active voice", "expand defined terms on first use",
or a firm's house style — and Legalese AI rewrites the rendered prose to match,
while staying anchored to the deterministic output so the meaning is preserved.

In other words: **names, shape, and `@nlg` get the content right; drafting
policies get the _style_ right.** See
[Composing L4 with AI](../llm-integration/composing-l4-with-ai.md) for how
Legalese AI fits into the authoring loop.
