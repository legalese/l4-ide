# AKA

`AKA` ("also known as") gives a function, a value, a type or a section more than one name. Every name refers to the same thing.

## Syntax

```text
name AKA alias1, alias2 MEANS expression
DECLARE TypeName AKA Alias HAS ...
DECLARE TypeName AKA Alias IS ...
§ `Section name` AKA alias
```

**Example file:** [aka-example.l4](aka-example.l4)

## Values

```l4
`the borrower` AKA `the debtor` MEANS "Acme Ltd"

#EVAL `the debtor`
```

## Types

A statute and the people who apply it often use different words for the same thing:

```l4
DECLARE `Authorised Representative` AKA Agent
  HAS
    name IS A STRING
    `licence number` IS A STRING

GIVEN agent IS AN Agent
GIVETH A STRING
`licence of` agent MEANS agent's `licence number`
```

A type synonym can have aliases too: ``DECLARE `Value Added Tax rate` AKA `VAT rate` IS NUMBER``.

## Sections

An alias on a section heading gives a shorter name for qualified references:

```l4
§ `Definitions for Part VII` AKA defs
`taxable income` MEANS 50000

#EVAL defs's `taxable income`
```

See [Syntax and directives: Sections](../syntax/README.md#sections).

## Related pages

- [DECLARE](../types/DECLARE.md): type declarations
- [DECIDE](DECIDE.md) and [MEANS](MEANS.md): value definitions
