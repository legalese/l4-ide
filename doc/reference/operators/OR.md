# OR

Logical disjunction operator. Returns TRUE if either or both operands are TRUE.

## Syntax

```l4
expression1 OR expression2
expression1 || expression2
```

## Truth Table

| A     | B     | A OR B |
| ----- | ----- | ------ |
| TRUE  | TRUE  | TRUE   |
| TRUE  | FALSE | TRUE   |
| FALSE | TRUE  | TRUE   |
| FALSE | FALSE | FALSE  |

## Examples

**Example file:** [or-example.l4](or-example.l4)

## Asyndetic OR

Implicit operators using punctuation.

**Double dots** (`..`) - Implicit OR

**Example:** [asyndetic-example.l4](asyndetic-example.l4)

## Short-Circuit Evaluation

OR evaluates lazily - if the first operand is TRUE, the second is not evaluated.

In a trace (`#EVALTRACE`, or the reasoning a service returns), an OR appears as itself, with its first operand and that operand's value beneath it, followed by the second operand when it was needed.
An operand written as plain `TRUE` or `FALSE` is left out of the first place, since its value is already on the page, and a second operand that was not needed does not appear.

## Related Keywords

- **[AND](AND.md)** - Logical conjunction
- **[NOT](NOT.md)** - Logical negation
- **[IMPLIES](IMPLIES.md)** - Logical implication

## See Also

- **[Logical Operators](../operators/README.md#logical-operators)** - All logical operators
