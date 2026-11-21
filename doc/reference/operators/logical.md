# AND, OR, NOT, IMPLIES

The logical operators combine BOOLEAN values.

## Forms

| Operator  | Symbol | Asyndetic | Meaning                                |
| --------- | ------ | --------- | -------------------------------------- |
| `AND`     | `&&`   | `...`     | both are TRUE                          |
| `OR`      | `\|\|` | `..`      | at least one is TRUE                   |
| `NOT`     |        |           | the opposite                           |
| `IMPLIES` | `=>`   |           | if the first is TRUE, so is the second |

The word and the symbol mean the same and can be mixed. For `...` and `..`, see [Operators: Asyndetic AND and OR](README.md#asyndetic-and-and-or).
For exceptions ("… unless …"), see [UNLESS](UNLESS.md).

**Example files:** [and-example.l4](and-example.l4), [or-example.l4](or-example.l4), [not-example.l4](not-example.l4), [implies-example.l4](implies-example.l4)

## Truth table

| A     | B     | A AND B | A OR B | NOT A | A IMPLIES B |
| ----- | ----- | ------- | ------ | ----- | ----------- |
| TRUE  | TRUE  | TRUE    | TRUE   | FALSE | TRUE        |
| TRUE  | FALSE | FALSE   | TRUE   | FALSE | FALSE       |
| FALSE | TRUE  | FALSE   | TRUE   | TRUE  | TRUE        |
| FALSE | FALSE | FALSE   | FALSE  | TRUE  | TRUE        |

## AND

```l4
GIVEN age IS A NUMBER
      `has a licence` IS A BOOLEAN
GIVETH A BOOLEAN
`may drive` age `has a licence` MEANS age >= 16 AND `has a licence`
```

## OR

```l4
GIVEN `is an employee` IS A BOOLEAN
      `is a contractor` IS A BOOLEAN
GIVETH A BOOLEAN
`may enter` `is an employee` `is a contractor` MEANS `is an employee` OR `is a contractor`
```

## NOT

`NOT` negates everything after it on its line, and any lines below that are indented further than the `NOT`.
So on one line `NOT a AND b` would mean `NOT (a AND b)`, though most people read it as `(NOT a) AND b`.
Because the two readings give different answers, L4 refuses a `NOT` followed on its own line by `AND`, `OR` or `IMPLIES`, and the message shows both:

```
On one line, NOT reaches to the end of the line, so this reads as

  NOT (a AND b)

If that is the meaning, write those brackets in. If only

  a

is negated, put the brackets around the NOT and that alone:

  (NOT a) AND b

or move the AND to a line of its own, starting in the same
column as the NOT or further left.
```

| Written                        | Means                                                 |
| ------------------------------ | ----------------------------------------------------- |
| `NOT a AND b` (one line)       | refused                                               |
| `NOT (a) AND b` (one line)     | refused: the bracket closes around `a`, not the `NOT` |
| `a AND NOT b AND c` (one line) | refused                                               |
| `NOT (a AND b)`                | `NOT (a AND b)`                                       |
| `(NOT a) AND b`                | `(NOT a) AND b`                                       |
| `a AND NOT b`                  | `a AND (NOT b)`                                       |
| `NOT n EQUALS 0`               | `NOT (n EQUALS 0)`                                    |

To negate only one operand on a line, put the `NOT` and its operand in parentheses: `(NOT a) AND b`.
A `NOT` last on its line, as in `a AND NOT b`, has nothing after it to reach over, and a comparison such as `NOT n EQUALS 0` has only one sensible reading, so neither is refused.
In the vertical layout below, each line is a separate operand, so `NOT` applies to its own line only.

## IMPLIES

`A IMPLIES B` is FALSE only when `A` is TRUE and `B` is FALSE. It means the same as `(NOT A) OR B`: "if A, then B".

```l4
GIVEN age IS A NUMBER
      `has parental consent` IS A BOOLEAN
GIVETH A BOOLEAN
`consent rule is met` age `has parental consent` MEANS
  age < 18 IMPLIES `has parental consent`
```

`IMPLIES` groups to the right: `a IMPLIES b IMPLIES c` means `a IMPLIES (b IMPLIES c)`.

## Several lines

A long condition can be written one operand per line, with the operator at the start of each line:

```l4
GIVEN age IS A NUMBER
      income IS A NUMBER
      `has a criminal record` IS A BOOLEAN
GIVETH A BOOLEAN
`is eligible` age income `has a criminal record` MEANS
      age >= 18
  AND income > 30000
  AND NOT `has a criminal record`
```

When the operators are in one column, the usual [precedence](README.md#precedence) applies.
An operator written further left than the lines above it applies to all of them together:

```l4
GIVEN a IS A BOOLEAN
      b IS A BOOLEAN
      c IS A BOOLEAN
GIVETH A BOOLEAN
`grouped by layout` a b c MEANS
         a
      OR b
  AND    c
```

This means `(a OR b) AND c`; on one line, `a OR b AND c` means `a OR (b AND c)`.

## Evaluation order

The left operand is evaluated first, and the right one only when it is needed: `FALSE AND x` is FALSE, `TRUE OR x` is TRUE and `FALSE IMPLIES x` is TRUE without looking at `x`.

## Related pages

- [UNLESS](UNLESS.md): exceptions
- [Operators](README.md): precedence and asyndetic forms
- [IF](../control-flow/IF.md): use a condition to choose a value
