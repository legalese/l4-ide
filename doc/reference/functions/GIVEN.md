# GIVEN and GIVETH

`GIVEN` declares the inputs of a function, each with a name and a type.
`GIVETH` declares the type of its result.
Both go on the lines above the definition.

## Syntax

```text
GIVEN name IS A Type
GIVEN name1 IS A Type1, name2 IS A Type2
GIVEN name1 IS A Type1
      name2 IS A Type2
GIVETH A Type
```

A function has one `GIVEN`. Further inputs go on the same line, separated by commas, or on the lines below, lined up under the first name.
A second `GIVEN` line directly below the first is a syntax error.

Where the `GIVEN` is written decides who the inputs belong to.
At column 1 it lists the inputs of the one declaration below it: a **"rule `GIVEN`"**, which is what most of this page shows.
Indented under a section heading, it declares an input shared by every rule in the section: a **"section `GIVEN`"**, which has [its own page](../syntax/section-given.md).

**Example files:** [given-example.l4](given-example.l4), [giveth-example.l4](giveth-example.l4)

## GIVEN

```l4
GIVEN amount IS A NUMBER
      `days overdue` IS A NUMBER
GIVETH A NUMBER
`late fee` amount `days overdue` MEANS
  IF `days overdue` > 30 THEN amount TIMES 0.05 ELSE 0
```

The names after the function name are the `GIVEN` inputs in order; they may be left out of the definition, but if they are written they must match.
`A` and `AN` are interchangeable (`IS AN Invoice`); see [DECLARE](../types/DECLARE.md#a-and-an).

### Calling with named inputs

A call gives the inputs in the order of the `GIVEN`, or by name with `WITH`:

```l4
GIVEN amount IS A NUMBER
      `days overdue` IS A NUMBER
GIVETH A NUMBER
`late fee` amount `days overdue` MEANS
  IF `days overdue` > 30 THEN amount TIMES 0.05 ELSE 0

#EVAL `late fee` 1000 45
#EVAL `late fee` WITH amount IS 1000, `days overdue` IS 45
#ASSERT (`late fee` WITH `days overdue` IS 10, amount IS 1000) EQUALS 0
```

With `WITH`, the inputs can be given in any order. Put the call in parentheses when an operator follows it, as in the `#ASSERT`. This works only for a function with a `GIVEN`; a value declared with [ASSUME](../types/ASSUME.md) cannot be given a value this way.

### Type parameters

An input of type `TYPE` makes the function work for any type:

```l4
GIVEN a IS A TYPE
      xs IS A LIST OF a
GIVETH A NUMBER
`number of items in` xs MEANS
  CONSIDER xs
  WHEN EMPTY THEN 0
  WHEN first FOLLOWED BY rest THEN 1 PLUS `number of items in` rest
```

A type parameter is not passed when the function is called: `` `number of items in` (LIST 1, 2, 3) `` gives `3`.
[FOR ALL](../types/for-all.md) writes the same kind of type for an `ASSUME`.

### Descriptions of inputs

`@desc` after an input describes it. The description is shown when the function is deployed with `@export`:

```l4
@export Calculate the late fee for an overdue invoice
GIVEN amount IS A NUMBER @desc The invoice amount
      `days overdue` IS A NUMBER @desc How many days past the due date
GIVETH A NUMBER
`late fee` amount `days overdue` MEANS
  IF `days overdue` > 30 THEN amount TIMES 0.05 ELSE 0
```

### Words for an input

An input can carry an `@nlg` annotation: the words that `l4 nlg` uses for it in place of its name.
The document renderer, `l4 render`, does not use an input's annotation, except for an input declared in a section's `GIVEN`; the [placement table](../syntax/README.md#where-to-put-it) has the facts per projection.
Write it at the end of the input's line, or on a line of its own under the input:

```l4
GIVEN floor  IS A NUMBER @nlg the floor
      amount IS A NUMBER
      @nlg the sum of money
GIVETH A BOOLEAN
DECIDE `is large` IF amount GREATER THAN floor
```

`l4 nlg` then writes ``#EVAL `is large` WITH floor IS 100, amount IS 200`` as `` `is large` where the floor is 100 and the sum of money is 200 ``.
Under the LAST input, indent the annotation further than `GIVEN`: written at `GIVEN`'s column, it describes what follows instead, which is the rule when no `GIVETH` comes between.
The full placement rules are in [Where to put it](../syntax/README.md#where-to-put-it).

### Anonymous functions

`GIVEN … YIELD` makes a function without a name; see [YIELD](YIELD.md).

## GIVETH

`GIVETH` names the type of the result. `GIVES` is a synonym, and the article is optional (`GIVETH NUMBER`).

```l4
GIVEN xs IS A LIST OF NUMBER
GIVETH A MAYBE NUMBER
`the first of` xs MEANS
  CONSIDER xs
  WHEN EMPTY THEN NOTHING
  WHEN first FOLLOWED BY rest THEN JUST first
```

`GIVETH` is optional: without it, L4 infers the result type.
Writing it makes the rule easier to read and lets the type checker report a body that gives the wrong type.

A rule that returns obligations has the result type `DEONTIC Party Action`; see [DEONTIC](../regulative/DEONTIC.md).

## A GIVEN for a whole section

A `GIVEN` indented under a section heading belongs to the **section**, not to
the declaration below it: it declares a name once for every rule in that
section, instead of every rule repeating it. A `GIVEN` at column 1 lists the
inputs of the declaration below it, exactly as everywhere else on this page.
The indentation is the whole difference.

```l4
§ `1. Issuer eligibility`
    GIVEN issuer IS AN IssuerProfile
```

- [The section `GIVEN`](../syntax/section-given.md): the reference page: the
  column rule, which rules can see a section `GIVEN`, and what the tools do with
  it
- [What a section needs to know](../../tutorials/section-given/what-a-section-needs-to-know.md):
  the tutorial, working through one statute
- [Field opening](../syntax/field-opening.md): inside a rule whose input is a
  record, the record's fields can be read by their bare names

## Related pages

- [DECIDE](DECIDE.md): the definition that follows `GIVEN` and `GIVETH`
- [Types](../types/README.md): the types an input or result can have
- [ASSUME](../types/ASSUME.md): a name with a type and no definition
