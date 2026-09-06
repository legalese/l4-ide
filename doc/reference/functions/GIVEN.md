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

Inputs can carry natural language generation (NLG) annotations, which tell the
document renderer how to word them:

```l4
GIVEN customer IS A Person @nlg
GIVEN amount IS A NUMBER @nlg
processPayment customer amount MEANS ...
```

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

## Related Keywords

- **[GIVETH](GIVETH.md)** - Names the kind of thing a rule gives back (its output)
- **[DECIDE](DECIDE.md)** - Defines a rule
- **[MEANS](MEANS.md)** - Gives a rule its definition
- **[TYPE-KEYWORDS](../types/keywords.md)** - Type syntax (IS, etc.)

## See Also

- **[Types Reference](../types/README.md)** - Available types
