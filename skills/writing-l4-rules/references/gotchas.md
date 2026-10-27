# L4 Gotchas

Things that will trip up a general-purpose LLM because they are not in any other language and are not visible in a naïve reading of the syntax.

**Canonical references:**

- Full keyword glossary: <https://legalese.com/l4/reference/GLOSSARY.md>
- Syntax overview: <https://legalese.com/l4/reference/syntax.md>

---

## Contents

- [`DECIDE`: IS vs MEANS vs IF](#decide-is-vs-means-vs-if)
- [The ditto operator `^`](#the-ditto-operator-)
- [Asyndetic operators `...` and `..`](#asyndetic-operators--and-)
- [Section markers `§` and `§§`](#section-markers--and-)
- [Computed fields in records](#computed-fields-in-records)
- [Backtick identifiers and mixfix](#backtick-identifiers-and-mixfix)
- [Layout sensitivity](#layout-sensitivity)
- [No implicit coercion](#no-implicit-coercion)
- [Genitive field access with `'s`](#genitive-field-access-with-s)
- [`AKA` aliases](#aka-aliases)
- [`LET … IN` vs `WHERE`](#let--in-vs-where)
- [`@export` placement](#export-placement)
- [An exported rule that takes a `DEONTIC` is refused](#an-exported-rule-that-takes-a-deontic-is-refused)
- [Annotation fence](#annotation-fence)
- [`@nlg` placement and language](#nlg-placement-and-language)
- [NLG and reference annotations](#nlg-and-reference-annotations)

---

## `DECIDE`: IS vs MEANS vs IF

L4 has three decision-defining forms. All are valid; pick the one that reads best for the rule you are writing.

```l4
-- Value or computed expression — use IS or MEANS
GIVEN x IS A NUMBER
DECIDE double x IS x TIMES 2

GIVEN n IS A NUMBER
DECIDE factorial n MEANS
    IF n EQUALS 0 THEN 1 ELSE n TIMES factorial (n MINUS 1)

-- Boolean-returning rule — use IF
GIVEN age IS A NUMBER
      income IS A NUMBER
DECIDE `is eligible` IF
    age AT LEAST 18 AND income GREATER THAN 30000

-- DECIDE is optional when using MEANS
GIVEN x IS A NUMBER
double x MEANS x TIMES 2
```

Rule of thumb: **`IF` for booleans, `IS` for values and records, `MEANS` when omitting `DECIDE` entirely.**

Reference: <https://legalese.com/l4/reference/functions/DECIDE.md>

---

## The ditto operator `^`

`^` copies the corresponding token from the line above, column-for-column. It is used to flatten repeated chained comparisons without repeating the subject.

```l4
GIVEN phase IS A STRING
sky_is_romantic phase MEANS
       phase EQUALS "full moon"
   OR  ^     ^       "new moon"
   OR  ^     ^       "new"
   OR  ^     ^       "full"
```

Each `^` stands for the token at the same column on the previous line. Without ditto you would repeat `phase EQUALS` four times. This is a legal-drafting affordance, not a general-purpose operator.

---

## Asyndetic operators `...` and `..`

The ellipsis operators are implicit conjunction/disjunction — they let you write a list of conditions without repeating `AND` / `OR` on every line.

- `...` (three dots) — implicit **AND**
- `..` (two dots) — implicit **OR**

```l4
DECIDE `eligible for discount` IF
    `is existing customer`
    ...
    `has clean payment history`
    ...
    `spent at least 1000 this year`
-- equivalent to: cond1 AND cond2 AND cond3
```

Use them when a clause list should read as a bulleted list rather than a prose "A and B and C".

---

## Section markers `§` and `§§`

`§` and `§§` are **structural section markers**, not comments. They are how you preserve the hierarchy of the source legislation or contract in the L4 file:

```l4
§ `Part I — Eligibility`

§§ `1.1 Definitions`

DECLARE Applicant HAS
    ...

§§ `1.2 Conditions for coverage`

GIVEN applicant IS An Applicant
DECIDE `coverage applies` IF
    ...
```

They compile away but show up in the IDE outline and in generated documentation. Use them whenever the source text has sections — it is how the isomorphic-encoding principle is expressed.

---

## Computed fields in records

A record's `HAS` block can include fields whose value is **computed** from other fields via `MEANS`. These are like derived attributes / methods / computed properties in other languages.

```l4
DECLARE Employee HAS
    -- stored fields
    `name`          IS A STRING
    `date of birth` IS A NUMBER
    `current year`  IS A NUMBER
    -- computed fields
    `age`           IS A NUMBER
        MEANS `current year` - `date of birth`
    `adult`         IS A BOOLEAN
        MEANS `age` AT LEAST 18
```

**Rules:**

- Computed fields are accessed with `'s` just like stored fields: `` employee's `age` ``.
- They are **pure** — they may only reference sibling fields of the same record. You cannot add `GIVEN` parameters to a computed field.
- When constructing with `WITH`, you supply **only the stored fields**; computed fields are derived automatically.
- Cycle detection is automatic; the compiler rejects any dependency cycle between computed fields.

Reference: <https://legalese.com/l4/reference/types/DECLARE.md>

---

## Backtick identifiers and mixfix

Any identifier containing spaces or punctuation must be backtick-quoted:

```l4
`the applicant`
`has valid identification`
`the person must not sell alcohol`
```

**Mixfix notation** lets the function name intersperse with its arguments. The argument positions are the backtick-quoted parameter names:

```l4
GIVEN employee IS AN Employee
      employer IS A Company
GIVETH A BOOLEAN
`employee` `works for` `employer` MEANS ...

-- Called as: `Alice` `works for` `Acme Corp`
```

Mixfix is the reason L4 code can read like legal prose. Use it for binary-ish relations. Use normal prefix-style function names for everything else.

---

## Layout sensitivity

L4 is layout-sensitive like Python and Haskell. **Indentation determines block structure.** There are no braces or semicolons.

```l4
GIVEN x IS A NUMBER
GIVETH A STRING
classify x MEANS
    IF x GREATER THAN 0
    THEN "positive"
    ELSE IF x EQUALS 0
        THEN "zero"
        ELSE "negative"
```

The `THEN`/`ELSE` alignment and the indentation of the inner `IF` matter. If you see a "parse error: unexpected token", check indentation first.

---

## No implicit coercion

L4 never silently converts between types. `"42" + 1` is a type error. Use the explicit coercions (`TOSTRING`, `TONUMBER`, `TODATE`, `TOTIME`, `TODATETIME`, `TRUNC`) from [builtins.md](builtins.md). `TONUMBER`/`TODATE`/etc. return `MAYBE` — you must pattern-match with `CONSIDER` to extract the value.

---

## Genitive field access with `'s`

Field access uses the English genitive, not a dot:

```l4
person's age
company's ceo's name          -- chaining
application's employee's nationality
```

This is the ONLY form of field access. No `.field`, no `->`, no `[]`.

---

## `AKA` aliases

`AKA` gives an existing name an alternate name. Both can be used interchangeably:

```l4
GIVEN p IS A Person
DECIDE `is of legal age` p IS p's age AT LEAST 18
    AKA `has reached majority`

-- both of these now work:
#ASSERT `is of legal age`    `Alice`
#ASSERT `has reached majority` `Alice`
```

Use it when the source text uses two names for the same concept and you want both to be searchable.

Reference: <https://legalese.com/l4/reference/functions/AKA.md>

---

## `LET … IN` vs `WHERE`

Both introduce local bindings. Pick by position:

- **`WHERE`** — trailing. Use for helper definitions read _after_ the main expression.
- **`LET … IN`** — leading. Use for a single binding consumed immediately.

```l4
-- WHERE: trailing helpers, indented under the body
GIVEN radius IS A NUMBER
GIVETH A NUMBER
`circle area` radius MEANS
    pi TIMES radius TIMES radius
    WHERE
        pi MEANS 3.14159

-- LET ... IN: inline
GIVEN price IS A NUMBER
GIVETH A NUMBER
`price with tax` price MEANS
    LET `tax rate` MEANS 0.08 IN
        price TIMES (1 PLUS `tax rate`)
```

`WHERE` must be indented under the body it belongs to; at column 1 it is a parse error (`unexpected WHERE`).

---

## `@export` placement

`@export` goes **directly above** the function (before `GIVEN` or the bare function name). Not between `GIVETH` and `DECIDE`.

```l4
-- ✘ Wrong — @export in the middle
GIVEN x IS A NUMBER
GIVETH A NUMBER
@export Square a number
squared x MEANS x TIMES x

-- ✔ Right — @export at the top
@export Square a number
GIVEN x IS A NUMBER
GIVETH A NUMBER
squared x MEANS x TIMES x
```

---

## An exported rule that takes a `DEONTIC` is refused

**A `DEONTIC` input is for use inside L4 only.**
**Never give a rule marked `@export` a `DEONTIC` input.**
**It may give a `DEONTIC` value as its answer.**

No request can supply the value, so the typechecker refuses the rule: `l4 check` fails with `DEONTIC inputs are not supported for @export`, naming the input, the editor shows it as an error, and the deploy is refused.
The same holds for any input whose type contains a `DEONTIC`, whether the type is written or L4 works it out, and for an `ASSUME` that the rule reads.
The message ends with what to do: give the rule the plain facts that the `DEONTIC` is made from as inputs, and build the `DEONTIC` inside it.

```l4
-- ✘ Wrong — `l4 check` refuses it, because no request can supply `duty`
@export Is a duty already fulfilled
GIVEN duty IS A DEONTIC Person Action
GIVETH A BOOLEAN
`already fulfilled` duty MEANS
  CONSIDER duty
  WHEN FULFILLED THEN TRUE
  OTHERWISE FALSE
```

Take the plain facts as inputs and build the duty inside the rule; the full pattern is in [SKILL.md](../SKILL.md#inputs-no-request-can-supply-event-and-deontic).
An `EVENT` input is refused in the same way, with `EVENT inputs are not supported for @export`.

An `ASSUME` that a helper of the same file reads counts too, when the exported rule calls that helper, and the error names the helper.
When it checks the inputs of an exported rule, L4 does not look inside the rules of an imported file, so give an imported helper its `DEONTIC` or `EVENT` as an input, not through an `ASSUME`.

---

## Annotation fence

All annotations begin with `@`. `@export`, `@ref` and `@desc` apply to the definition they sit with or precede; `@nlg` is described under its own heading below.

| Annotation | Purpose                                                            |
| ---------- | ------------------------------------------------------------------ |
| `@desc`    | Human-readable description (internal unless paired with `@export`) |
| `@export`  | Mark function for deployment via `jl4-service`                     |
| `@nlg`     | The wording `l4 nlg` and `l4 render` print; see below              |
| `@lang`    | The language an untagged `@nlg` in the module is written in        |
| `@ref`     | Cross-reference to a legal source                                  |
| `@ref-src` | Source of the legal reference                                      |
| `@ref-map` | Mapping table for references                                       |

`@ref` / `@ref-src` / `@ref-map` are the "link this rule to §3.2 of the statute" annotations — use them whenever the source document has stable citations.
An `@ref` on its own line binds to the next syntax node, whatever it is, so it goes above the rule it cites.
Measured with `l4 check` and `l4 ast`: one written under its rule attached to the next rule, with no message; one above a `§` heading attached to the heading.
Two above one rule are both kept, in the order written, and a tool that shows one citation shows the nearest, the lower.
One written at the end of a line of code attaches to nothing, and draws a warning that says to put it on the line above.
One at the end of a file, with nothing after it, draws a warning that there is nothing to attach it to.
Both warnings leave `l4 check` exiting 0.

---

## `@nlg` placement and language

`@nlg` describes the thing it sits with: **trailing a line, what is on that line; on a line of its own, what follows.**
Under an input of a `GIVEN` or a field of a `DECLARE`, an annotation indented further than the keyword describes the input or field above it.
A rule's own sentence goes trailing its head, or on its own line between the `GIVEN` block and the `DECIDE`.

The failures, sorted by whether L4 tells you:

| what you wrote                                                                          | what happens                                                           | does L4 say so? |
| --------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | --------------- |
| the rule's sentence on its own line above the `GIVEN`, nothing before it                | the wording is dropped                                                 | yes, a warning  |
| two wordings in the same language on one rule                                           | neither is used; the rule reads by its name                            | yes, a warning  |
| an `@nlg` with no text, or only a tag                                                   | ignored                                                                | yes, a warning  |
| two `@lang` lines that name different languages                                         | the last is used and the earlier has no effect                         | yes, a warning  |
| the rule's sentence above the `GIVEN`, with an `IMPORT` or `§` heading above            | that `IMPORT` or heading takes it; the rule reads by its name          | no              |
| the rule's sentence indented under the last input, even by one space                    | it becomes that input's gloss                                          | no              |
| `10%and%20` in a wording, with an input called `and`                                    | `and` is replaced by the input's value: `10520`                        | no              |
| `@nlg:the employee pays`, or `@nlg:en-route …`, on a rule with no other wording         | the first word is the language tag; the sentence reads `employee pays` | yes, a warning  |
| `@nlg:the …` beside a wording in another language, on the same rule                     | `the` is taken for a language; the sentence loses its first word       | no              |
| `% amount %` in a wording                                                               | it prints as plain text, and the slot is lost                          | yes, a warning  |
| a field's gloss that repeats its owner: `@nlg the employee's date of birth` under `dob` | it reads "the employee's the employee's date of birth"                 | no              |
| two wordings in one language on one field: `head [the first] IS AN a [an item]`         | neither is used; the field reads by its name                           | yes, a warning  |

Write `\%` and `\]` for a literal percent sign or close bracket.
A percent sign followed by a space is plain text, so `a 5% levy on %amount%` needs no escape.
A pair with spaces inside it around one word, `% amount %`, is plain text too and draws a warning: write `%amount%`.

**One wording per language.**
`@nlg:he …` tags a wording with its language, each further wording goes on a continuation line, and `l4 nlg --lang he` or `l4 render --lang he` picks it.
`@lang he` on a line of its own labels every untagged `@nlg` in the module.
A module that declares nothing is English, and `@lang en` draws a hint that the line can go.
Two `@lang` lines that name different languages draw a warning on the earlier one, and the last is used.

---

## NLG and reference annotations

In addition to the `@`-prefixed annotations above, L4 recognises two **inline** annotation bracket forms inside identifiers and expressions:

- `[...]` — NLG inline annotations (hints for rendering the rule as natural language)
- `<<...>>` — reference annotations (inline citations)
- `%...%` — NLG delimiter (wraps a phrase for the NLG renderer)

These are rare in hand-written rules but appear in machine-generated or NLG-bidirectional files. If you see them in existing code, leave them alone — they are meaningful.

---

## See also

- <https://legalese.com/l4/reference/GLOSSARY.md> — complete keyword list
- <https://legalese.com/l4/reference/syntax.md> — layout rules, comments, identifiers
- <https://legalese.com/l4/reference/cheat-sheet.md> — translation from other languages
