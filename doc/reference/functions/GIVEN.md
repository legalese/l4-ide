# GIVEN

Lists the facts a rule is told about the case in front of it (its **"inputs"**),
and the kind of thing each one is.

## Syntax

```l4
GIVEN name IS A Type

GIVEN name IS A Type, name2 IS A Type2

GIVEN name1 IS A Type1
      name2 IS A Type2
```

## Purpose

A rule is told some inputs and works out one answer from them. `GIVEN` names the
inputs, ahead of the rule that reads them; each one has a name and a kind of
thing it must be.

Where the `GIVEN` is written decides who the inputs belong to. At column 1 it
lists the inputs of the one declaration below it — a **"rule `GIVEN`"**, which
is what most of this page shows. Indented under a section heading, it declares
an input shared by every rule in the section — a **"section `GIVEN`"**, which
has [its own page](../syntax/section-given.md).

## Examples

**Example file:** [given-example.l4](given-example.l4)

### One input

```l4
GIVEN x IS A NUMBER
double x MEANS x TIMES 2
```

### Several inputs on one line

```l4
GIVEN a IS A NUMBER, b IS A NUMBER
add a b MEANS a PLUS b
```

### Several inputs, one per line

Use indentation to continue the list:

```l4
GIVEN x IS A NUMBER
      y IS A NUMBER
      z IS A NUMBER
sum3 x y z MEANS x PLUS y PLUS z
```

### Inputs that are kinds of thing

```l4
GIVEN a IS A TYPE
GIVEN xs IS A LIST OF a
length xs MEANS
  CONSIDER xs
  WHEN EMPTY THEN 0
  WHEN _ FOLLOWED BY tail THEN 1 PLUS length tail
```

### An input that is a record

```l4
DECLARE Person HAS name IS A STRING, age IS A NUMBER

GIVEN p IS A Person
getName p MEANS p's name
```

## Annotations

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

## A GIVEN for a whole section

A `GIVEN` indented under a section heading belongs to the **section**, not to
the declaration below it: it declares a name once for every rule in that
section, instead of every rule repeating it. A `GIVEN` at column 1 lists the
inputs of the declaration below it, exactly as everywhere else on this page —
the indentation is the whole difference.

```l4
§ `1. Issuer eligibility`
    GIVEN issuer IS AN IssuerProfile
```

- [The section `GIVEN`](../syntax/section-given.md) — the reference page: the
  column rule, which rules can see a section `GIVEN`, and what the tools do with
  it
- [What a section needs to know](../../tutorials/section-given/what-a-section-needs-to-know.md)
  — the tutorial, working through one statute
- [Field opening](../syntax/field-opening.md) — inside a rule whose input is a
  record, the record's fields can be read by their bare names

## Related Keywords

- **[GIVETH](GIVETH.md)** - Names the kind of thing a rule gives back (its output)
- **[DECIDE](DECIDE.md)** - Defines a rule
- **[MEANS](MEANS.md)** - Gives a rule its definition
- **[TYPE-KEYWORDS](../types/keywords.md)** - Type syntax (IS, etc.)

## See Also

- **[Types Reference](../types/README.md)** - Available types
