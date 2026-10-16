# Make rules read like law

Write rules whose calls read like sentences, and whose rendered document reads like legal drafting.

**Before you start:** [Install L4 and write your first rule](../getting-started/first-l4-file.md).

This page has two parts:

1. **Infix, postfix and mixfix functions**: put a rule's name and its inputs in natural word order, so `` `the applicant` `is eligible for` `the programme` `` is valid L4.
2. **Rendering**: L4 can turn your rules back into an English document. Names, the shape of the code, and `@nlg` annotations decide how well it reads.

---

## Infix, postfix and mixfix functions

Most programming languages put the function name first: `isEligible(person, programme)`. In L4 the inputs can go before, between or after the words of the name:

| Pattern | Definition                                         | Call                          |
| ------- | -------------------------------------------------- | ----------------------------- |
| Prefix  | `` `plus` a b MEANS ... ``                         | `` `plus` 3 5 ``              |
| Infix   | ``a `plus` b MEANS ...``                           | ``3 `plus` 5``                |
| Postfix | ``amount `percent` MEANS ...``                     | ``50 `percent` ``             |
| Mixfix  | ``value `is between` lower `and` upper MEANS ...`` | ``5 `is between` 0 `and` 10`` |

The inputs are the names declared with `GIVEN`; every other word in the definition is part of the function's name. A call uses the same word order as the definition.

**Complete example:** [natural-language-example.l4](natural-language-example.l4)

### Infix: one input on each side

```l4
GIVEN a IS A NUMBER
      b IS A NUMBER
GIVETH A NUMBER
a `plus` b MEANS a + b

#EVAL 3 `plus` 5
#EVAL `plus` 3 5
```

Both calls return `8`: a function defined in infix form can also be called in prefix form.

Names in backticks can contain spaces, so the name can be a whole phrase:

```l4
DECLARE Person
    HAS `name`   IS A STRING
        `age`    IS A NUMBER
        `income` IS A NUMBER

GIVEN `the person` IS A Person
      `the threshold` IS A NUMBER
GIVETH A BOOLEAN
`the person` `has income above` `the threshold` MEANS
    `the person`'s `income` > `the threshold`

`Alice` MEANS Person WITH
    `name`   IS "Alice"
    `age`    IS 30
    `income` IS 50000

#EVAL `Alice` `has income above` 40000
```

### Postfix: the input before the name

```l4
GIVEN `the person` IS A Person
GIVETH A BOOLEAN
`the person` `is an adult` MEANS `the person`'s `age` >= 18

#EVAL `Alice` `is an adult`
```

For a one-word name, the backticks are optional at the call site: with ``n `squared` MEANS n * n``, both `5 squared` and ``5 `squared` `` work.

### Mixfix: words and inputs interleaved

A mixfix name has several words, with inputs between them:

```l4
GIVEN value IS A NUMBER
      lower IS A NUMBER
      upper IS A NUMBER
GIVETH A BOOLEAN
value `is between` lower `and` upper MEANS
    lower <= value AND value <= upper

#EVAL 5 `is between` 0 `and` 10

GIVEN principal IS A NUMBER
      rate      IS A NUMBER
      term      IS A NUMBER
GIVETH A NUMBER
`simple interest on` principal `at` rate `percent for` term `years` MEANS
    principal * rate / 100 * term

#EVAL `simple interest on` 1000 `at` 5 `percent for` 3 `years`
```

The calls return `TRUE` and `150`. There is no limit on the number of inputs.

### Points to watch

- **List the inputs in `GIVEN` in the order they appear in the definition.** For ``value `is between` lower `and` upper``, the `GIVEN` must list `value`, `lower`, `upper`, in that order.
- **An input cannot share a name with a word of the function name.** `` `percent for` years `years` `` is an error; call the input `term`.
- **Use parentheses** when an argument is itself an expression: ``(1 + 2) `plus` (3 + 4)``.
- **Define local helpers in `WHERE`.** A `WHERE` block can hold a full `GIVEN ... MEANS` definition, mixfix ones included; the complete example shows one.

For the exact rules of how L4 matches mixfix calls, see [Mixfix definitions](../../reference/functions/README.md#mixfix-definitions).

---

## Render your rules as a document

L4 can render your rules as formatted English, in the VS Code **Render** tab or with `l4 render file.l4 --format text`. The renderer is deterministic: it walks your code and turns each construct into a sentence or an outline. So the quality of the prose is mostly in your hands. Well-named, well-shaped rules read almost like professional drafting with no extra effort; badly named ones read like a transcript of an algorithm.

Three levers, from the cheapest to the most precise:

1. **Names**: backticked identifiers and input names.
2. **Shape**: mixfix word order, control flow, arithmetic and section headings.
3. **`@nlg`**: a sentence you write that replaces the generated one.

---

## Names do most of the work

The renderer prints names as you wrote them. Good names are the most effective thing you can do.

**Name rules as the phrase you want to read.** A backticked name can contain spaces:

```l4
`monthly property tax` MEANS 250
mpt MEANS 250
```

The first renders as "Monthly property tax means 250."; the second as "Mpt means 250."

**Name inputs as nouns, not letters.** Inputs appear in the prose and in every `@nlg` slot:

```l4
GIVEN `the purchase price` IS A NUMBER
      `the deposit paid`   IS A NUMBER
GIVETH A NUMBER
`the balance due` MEANS `the purchase price` MINUS `the deposit paid`

GIVEN p IS A NUMBER
      d IS A NUMBER
GIVETH A NUMBER
`balance` MEANS p MINUS d
```

The first renders as "The balance due equals the purchase price − the deposit paid."; the second as "Balance equals p − d."

Legal writing sometimes uses letters on purpose, as in "A person (A) discriminates against another (B) if …" (Equality Act 2010, s.13). There, single letters are the right choice.

When an input has a record type, the renderer refers to it by the type's name: with `` GIVEN claim IS A `Payment Claim` ``, `` claim's `amount` `` renders as "the payment claim's amount". This works well when only one input has that type; two inputs of the same type would share the same phrase.

**Name record fields readably.** A field renders as "X's field", so field names go straight into the prose:

```l4
DECLARE `Property Details`
    HAS `market value`         IS A NUMBER
        `monthly property tax` IS A NUMBER
```

---

## Shape the code so it reads in order

**Use mixfix so calls read as sentences.** Put the words and the inputs where they belong in the sentence:

```l4
DECLARE Person    HAS `age`           IS A NUMBER
DECLARE Programme HAS `minimum age`   IS A NUMBER

GIVEN `the applicant` IS A Person
      `the programme` IS A Programme
GIVETH A BOOLEAN
DECIDE `the applicant` `is eligible for` `the programme` IF
    `the applicant`'s `age` AT LEAST `the programme`'s `minimum age`
```

**End helper names with a preposition.** When a function's name ends in a word such as `of`, `for`, `to` or `between`, its arguments are joined naturally:

```l4
GIVEN x IS A NUMBER
      y IS A NUMBER
GIVETH A NUMBER
`the later of` x y MEANS IF x >= y THEN x ELSE y

`start date` MEANS 3
`end date`   MEANS 7
`the deadline` MEANS `the later of` `start date` `end date`
```

The call renders as "the later of start date and end date". The same function named `` `maximum` `` renders as "maximum with start date and end date".

**Let control flow stay structured.** `CONSIDER`, `IF`/`THEN`/`ELSE` and `AND`/`OR` render as indented outlines, not run-on sentences, so keep the operative logic where the renderer can see it:

```l4
DECLARE Status IS ONE OF Paid, Overdue
DECLARE Claim HAS `status` IS A Status

GIVEN claim IS A Claim
GIVETH A STRING
`the reminder` MEANS
    CONSIDER claim's `status`
    WHEN Paid    THEN "none"
    WHEN Overdue THEN "send a reminder"
```

renders as

```
• The reminder is determined by:
    depending on the claim's status:
    - if it is Paid: none
    - if it is Overdue: send a reminder
```

**Keep arithmetic as arithmetic.** Numeric expressions render as formulas, with `+ − × ÷` and parentheses, not as "the sum of the product of …":

```l4
`base rent`      MEANS 1000
`service charge` MEANS 100
`months`         MEANS 12
`deposit`        MEANS 2000

`the total payable` MEANS (`base rent` PLUS `service charge`) TIMES `months` PLUS `deposit`
```

renders as "The total payable equals (base rent + service charge) × months + deposit."

**Group rules into titled sections.** `` § `Name` `` starts a section and `` §§ `Name` `` a subsection (`§§§` goes deeper). Every declaration after a marker belongs to that section until the next marker. Sections become headings in the rendered document and entries in its table of contents:

```l4
DECLARE Person HAS `age` IS A NUMBER

§ `Eligibility`

GIVEN `the applicant` IS A Person
GIVETH A BOOLEAN
DECIDE `the applicant` `qualifies` IF
    `the applicant` `is of working age`

§§ `Age requirements`

GIVEN `the applicant` IS A Person
GIVETH A BOOLEAN
DECIDE `the applicant` `is of working age` IF
    `the applicant`'s `age` AT LEAST 18
```

With **Number sections** turned on in the Render tab (or `--number-sections` on the command line), the headings are numbered: `§ 2  Eligibility`, then `2.1  Age requirements`. A file with no section markers is still grouped into automatic **Definitions** and **Provisions** sections, but your own markers let you name and order the parts the way a reader of the contract or statute expects.

---

## `@nlg` annotations

When names and shape are not enough (a recursive helper, a term of art, a formula you would rather state in words), add an `@nlg` annotation. It is the natural-language form of the definition and replaces the generated sentence.

Write `@nlg` at the end of the definition's line, after the name and inputs, with the body on the next line. Inside the sentence, `%name%` is a slot for an input; an input whose name has spaces keeps its backticks: ``%`the principal`%``.

```l4
GIVEN x IS A NUMBER
      y IS A NUMBER
GIVETH A NUMBER
`bigger` x y @nlg whichever is larger of %x% and %y%
  MEANS IF x >= y THEN x ELSE y

`start date` MEANS 3
`end date`   MEANS 7
`the deadline` MEANS `bigger` `start date` `end date`
```

Each slot is filled with the input's name in the definition itself, and with the actual argument at each call:

```
• Bigger means whichever is larger of x and y.
• The deadline means whichever is larger of start date and end date.
```

**It replaces the body.** A function with `@nlg` renders as its sentence, not as its implementation. That is what makes recursive library functions readable; the prelude's `filter` has `@nlg the items of %list% for which %f% holds`, so a call reads as a sentence instead of exposing the recursion.

| Situation                                            | Why `@nlg` helps                                   |
| ---------------------------------------------------- | -------------------------------------------------- |
| Recursive or higher-order helpers                    | Describes the result, hides the implementation     |
| A formula better said in words                       | "the pro-rated premium" instead of the arithmetic  |
| Terms of art                                         | Matches the exact statutory or contractual wording |
| A name that cannot be both valid code and good prose | Separates the two                                  |

Tips:

- Use only the function's own inputs as slots, and write the sentence so that it reads well with each slot as a noun phrase.
- Try names and shape first. An `@nlg` sentence can drift away from the logic it describes, so use it where it pays off.
- One sentence per definition. For branching prose, let `CONSIDER` or `IF` render as an outline instead.

---

## Putting it together

Before, with short names and no annotation:

```l4
GIVEN p IS A NUMBER
      r IS A NUMBER
      n IS A NUMBER
GIVETH A NUMBER
pmt p r n MEANS p TIMES r DIVIDED BY (1 MINUS EXPONENT (1 PLUS r) (0 MINUS n))
```

This renders as "Pmt equals p × r ÷ (1 − EXPONENT with the sum of 1 and r and the difference between n and 0)."

After, with descriptive names and one `@nlg`:

```l4
GIVEN `the principal`      IS A NUMBER
      `the monthly rate`   IS A NUMBER
      `the term in months` IS A NUMBER
GIVETH A NUMBER
`the monthly repayment` `the principal` `the monthly rate` `the term in months` @nlg the level monthly repayment on %`the principal`% at %`the monthly rate`% over %`the term in months`%
  MEANS     `the principal` TIMES `the monthly rate`
        DIVIDED BY (1 MINUS EXPONENT (1 PLUS `the monthly rate`) (0 MINUS `the term in months`))

`the loan`          MEANS 10000
`the interest rate` MEANS 0.01
`the term`          MEANS 12
`the repayment`     MEANS `the monthly repayment` `the loan` `the interest rate` `the term`
```

Now the call renders as "The repayment means the level monthly repayment on the loan at the interest rate over the term.", a sentence a lawyer can check.

---

## Refine the style with Legalese AI

The renderer gives a faithful, deterministic baseline: the same input always gives the same prose, and it never adds facts. House style, tone and jurisdiction conventions are editorial choices that deterministic rules should not make.

Once the rendered output is accurate, Legalese AI can apply **drafting policies** to it: reusable style rules such as "use plain English", "prefer the active voice", "expand defined terms on first use", or a firm's house style. It rewrites the rendered prose to match, while staying anchored to the deterministic output so the meaning is kept.

Names, shape and `@nlg` get the content right; drafting policies get the style right. See [Draft rules with Legalese AI](../llm-integration/composing-l4-with-ai.md) for how Legalese AI fits into writing rules.
