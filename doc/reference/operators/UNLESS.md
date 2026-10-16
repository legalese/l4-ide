# UNLESS

`UNLESS` states an exception: `A UNLESS B` means `A AND NOT B`.
It binds more loosely than `AND` and `OR`, so the exception applies to the whole condition before it, as "unless" does in legal text.

## Syntax

```text
condition UNLESS exception
```

**Example file:** [unless-example.l4](unless-example.l4)

## Truth table

| A     | B     | A UNLESS B |
| ----- | ----- | ---------- |
| TRUE  | TRUE  | FALSE      |
| TRUE  | FALSE | TRUE       |
| FALSE | TRUE  | FALSE      |
| FALSE | FALSE | FALSE      |

## Example

"The applicant is eligible if they are a citizen and have resided here for 5 years, unless they have been disqualified."

```l4
ASSUME `is a citizen` IS A BOOLEAN
ASSUME `has resided for 5 years` IS A BOOLEAN
ASSUME `has been disqualified` IS A BOOLEAN

DECIDE `is eligible` IF
      `is a citizen`
  AND `has resided for 5 years`
  UNLESS `has been disqualified`
```

This means `` (`is a citizen` AND `has resided for 5 years`) AND NOT `has been disqualified` ``.

## Precedence

| Written                | Means                     |
| ---------------------- | ------------------------- |
| `a AND b UNLESS c`     | `(a AND b) AND NOT c`     |
| `a OR b UNLESS c`      | `(a OR b) AND NOT c`      |
| `a IMPLIES b UNLESS c` | `a IMPLIES (b AND NOT c)` |
| `a UNLESS b IMPLIES c` | `a AND NOT (b IMPLIES c)` |

`UNLESS` and `IMPLIES` share the lowest precedence and group to the right, so put parentheses around the part you mean when both appear.
Without `UNLESS`, the first two rows need parentheses: `(a OR b) AND NOT c`.

## Related pages

- [AND, OR, NOT, IMPLIES](logical.md)
- [Operators: Precedence](README.md#precedence)
- [Exceptions and defaults](../../concepts/legal-modeling/default-reasoning.md): modelling exceptions in legal rules
