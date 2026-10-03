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

In a trace (`#EVALTRACE`, or the reasoning a service returns), an OR appears as itself, with its first operand and that operand's value beneath it.
When the second operand was needed it follows: in `#EVALTRACE` it is the next step, at the OR's own level, and in a service's reasoning it is the OR's last child.
A second operand that was not needed does not appear.
If the first operand is written as plain `TRUE` or `FALSE`, the trace does not show it, because its value is already in the rule.

A rule that calls itself without end through the second operand, such as `loop n MEANS FALSE OR loop n`, runs until it is stopped, as one that calls itself through an `IF`'s branch does.

### When the first operand is not known

The first operand may depend on a fact nobody has supplied yet, such as a section `GIVEN` the case leaves out.
Then OR looks at the second operand too.
If the second is `TRUE`, the answer is `TRUE`, whatever the missing fact turns out to be: `x OR TRUE` is `TRUE`.
Otherwise the answer is not known yet, and asking for it stops and names every fact it is waiting for, as [AND](AND.md#when-the-first-operand-is-not-known) does.
If the second operand stops with an error or a refusal, the answer is still reported as waiting for the first operand's facts.

## Related Keywords

- **[AND](AND.md)** - Logical conjunction
- **[NOT](NOT.md)** - Logical negation
- **[IMPLIES](IMPLIES.md)** - Logical implication

## See Also

- **[Logical Operators](../operators/README.md#logical-operators)** - All logical operators
