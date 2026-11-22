# IF

`IF … THEN … ELSE` chooses between two values by a BOOLEAN condition.
It is an expression: it always gives a value, so the `ELSE` is required.

## Syntax

```text
IF condition THEN value-if-true ELSE value-if-false

IF condition
THEN value-if-true
ELSE value-if-false
```

Both branches must have the same type ([Branch type mismatch](../errors/README.md#branch-type-mismatch)). An `IF` without `ELSE` is a syntax error ([IF without ELSE](../errors/README.md#if-without-else)).

**Example file:** [if-example.l4](if-example.l4)

## Examples

```l4
GIVEN age IS A NUMBER
GIVETH A STRING
`age group of` age MEANS IF age >= 18 THEN "adult" ELSE "minor"

GIVEN x IS A NUMBER
GIVETH A NUMBER
`absolute value of` x MEANS
  IF x >= 0
  THEN x
  ELSE 0 MINUS x
```

The condition can be any BOOLEAN expression, built with [AND, OR, NOT](../operators/logical.md):

```l4
GIVEN age IS A NUMBER
      `has a licence` IS A BOOLEAN
GIVETH A STRING
`driving status` age `has a licence` MEANS
  IF age >= 16 AND `has a licence`
  THEN "may drive"
  ELSE "may not drive"
```

## Several conditions

An `IF` can go inside the `ELSE` of another. Each inner `IF` must be indented further than the one it belongs to:

```l4
GIVEN score IS A NUMBER
GIVETH A STRING
`grade for` score MEANS
  IF score >= 90 THEN "A"
  ELSE IF score >= 80 THEN "B"
       ELSE IF score >= 70 THEN "C"
            ELSE "F"
```

Lining up every `ELSE IF` in one column is an indentation error from the second one on. For more than two conditions, [BRANCH](BRANCH.md) is flatter.

A rule that is only a condition, such as "a person is eligible if …", is better written `DECIDE … IF`; see [DECIDE IF](../functions/DECIDE.md#decide-if).

## Related pages

- [BRANCH](BRANCH.md): several conditions, tried in order
- [CONSIDER](CONSIDER.md): choose by the shape of a value
- [Control flow](README.md)
