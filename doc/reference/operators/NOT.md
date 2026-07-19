# NOT

Logical negation operator. Inverts a boolean value.

## Syntax

```l4
NOT expression
```

## Purpose

NOT turns TRUE into FALSE and vice versa. In legal rules it typically encodes negative requirements ("has no criminal record", "is not disqualified") and pairs with AND/OR to express exceptions.

## Truth Table

| A     | NOT A |
| ----- | ----- |
| TRUE  | FALSE |
| FALSE | TRUE  |

## Examples

**Example file:** [not-example.l4](not-example.l4)

### Basic Negation

```l4
ASSUME hasCriminalRecord IS A BOOLEAN

DECIDE isClean IS NOT hasCriminalRecord
```

### Combined with AND

```l4
ASSUME personAge IS A NUMBER
ASSUME isBlocked IS A BOOLEAN

DECIDE canAccess IS personAge >= 18 AND NOT isBlocked
```

### Negating Compound Expressions

NOT binds tighter than AND and OR, so parenthesize compound expressions to negate them as a whole:

```l4
GIVEN a IS A BOOLEAN, b IS A BOOLEAN

-- NOT applies only to a
notAThenB a b MEANS NOT a AND b

-- NOT applies to the whole conjunction
notBoth a b MEANS NOT (a AND b)
```

### Negating Comparisons

```l4
GIVEN n IS A NUMBER
isNotZero n MEANS NOT (n EQUALS 0)
```

## Pitfalls

- **Precedence.** `NOT a AND b` means `(NOT a) AND b`, not `NOT (a AND b)`. Use parentheses when negating a compound expression.
- **Comparisons need parentheses.** Write `NOT (n EQUALS 0)`; without parentheses the NOT tries to apply to `n` alone.
- **Prefer UNLESS for exceptions.** `p AND NOT q` can be written `p UNLESS q`, which often reads closer to the legal source text.

## Related Keywords

- **[AND](AND.md)** - Logical conjunction
- **[OR](OR.md)** - Logical disjunction
- **[IMPLIES](IMPLIES.md)** - Logical implication
- **[UNLESS](UNLESS.md)** - Exception clause (`AND NOT`)

## See Also

- **[Logical Operators](../operators/README.md#logical-operators)** - All logical operators
