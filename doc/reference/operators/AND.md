# AND

Logical conjunction operator. Returns TRUE only if both operands are TRUE.

## Syntax

```l4
expression1 AND expression2
expression1 && expression2
```

## Truth Table

| A     | B     | A AND B |
| ----- | ----- | ------- |
| TRUE  | TRUE  | TRUE    |
| TRUE  | FALSE | FALSE   |
| FALSE | TRUE  | FALSE   |
| FALSE | FALSE | FALSE   |

## Examples

**Example file:** [and-example.l4](and-example.l4)

### Basic Usage

```l4
#EVAL TRUE AND TRUE     -- TRUE
#EVAL TRUE AND FALSE    -- FALSE
#EVAL FALSE AND TRUE    -- FALSE
#EVAL FALSE AND FALSE   -- FALSE
```

### In Conditions

```l4
GIVEN age IS A NUMBER
GIVEN hasLicense IS A BOOLEAN
DECIDE canDrive IS age >= 16 AND hasLicense
```

### Symbolic Alternative

```l4
DECIDE result IS TRUE && FALSE
```

### Chaining Multiple Conditions

```l4
GIVEN a IS A BOOLEAN
GIVEN b IS A BOOLEAN
GIVEN c IS A BOOLEAN
allTrue a b c MEANS a AND b AND c
```

## Layout-Sensitive AND

L4 supports vertical AND with indentation:

```l4
DECIDE eligible IS
      age >= 18
  AND income > 30000
  AND NOT hasCriminalRecord
```

## Asyndetic AND

Implicit operators using punctuation.

**Ellipsis** (`...`) - Implicit AND

**Example:** [asyndetic-example.l4](asyndetic-example.l4)

## Short-Circuit Evaluation

AND evaluates lazily - if the first operand is FALSE, the second is not evaluated.

In a trace (`#EVALTRACE`, or the reasoning a service returns), an AND appears as itself, with its first operand and that operand's value beneath it.
When the second operand was needed it follows: in `#EVALTRACE` it is the next step, at the AND's own level, and in a service's reasoning it is the AND's last child.
A second operand that was not needed does not appear.
If the first operand is written as plain `TRUE` or `FALSE`, the trace does not show it, because its value is already in the rule.
The [#EVALTRACE](../syntax/README.md#evaltrace) entry shows one such trace in full.

A rule that calls itself without end through the second operand, such as `loop n MEANS TRUE AND loop n`, runs until it is stopped, as one that calls itself through an `IF`'s branch does.

### When the first operand is not known

The first operand may depend on a fact nobody has supplied yet, such as a section `GIVEN` the case leaves out.
Then AND looks at the second operand too.
If the second is `FALSE`, the answer is `FALSE`, whatever the missing fact turns out to be: `x AND FALSE` is `FALSE`.
Otherwise the answer is not known yet, and asking for it stops and names every fact it is waiting for, here both `x` and `y`:

```
#EVAL x AND y
```

```
I could not continue evaluating, because I needed to know the values of
  x
  y
but they are assumed terms.
```

If the second operand stops with an error or a refusal, the answer is still reported as waiting for the first operand's facts, because those decide whether the second operand matters at all.

## Related Keywords

- **[OR](OR.md)** - Logical disjunction
- **[NOT](NOT.md)** - Logical negation
- **[IMPLIES](IMPLIES.md)** - Logical implication

## See Also

- **[Logical Operators](../operators/README.md#logical-operators)** - All logical operators
