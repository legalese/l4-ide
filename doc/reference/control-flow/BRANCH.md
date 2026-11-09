# BRANCH

`BRANCH` chooses between several values by a list of conditions. The conditions are tried from top to bottom, and the first one that holds gives the result. `OTHERWISE` gives the result when none holds.

## Syntax

```text
BRANCH IF condition1 THEN value1
       IF condition2 THEN value2
       OTHERWISE default-value

BRANCH
  IF condition1 THEN value1
  IF condition2 THEN value2
  OTHERWISE default-value
```

- Each `IF … THEN` and the `OTHERWISE` must be indented further than the `BRANCH` keyword. Put them in one column, either after `BRANCH` on its line or on the lines below.
- `OTHERWISE` is required.
- Every value must have the same type.

**Example file:** [branch-example.l4](branch-example.l4)

## Example

```l4
GIVEN `annual income` IS A NUMBER
GIVETH A NUMBER
`tax rate for` `annual income` MEANS
  BRANCH
    IF `annual income` > 120000 THEN 0.4
    IF `annual income` > 50000  THEN 0.3
    IF `annual income` > 20000  THEN 0.2
    OTHERWISE 0
```

`` `tax rate for` 150000 `` gives `0.4`: 150000 is above 50000 as well, but the first condition that holds wins.

## BRANCH, IF or CONSIDER

| Situation                                                                      | Use                     |
| ------------------------------------------------------------------------------ | ----------------------- |
| one condition, two outcomes                                                    | [IF](IF.md)             |
| several conditions, tried in order                                             | `BRANCH`                |
| the value's shape: enumeration values, `JUST`/`NOTHING`, list or record fields | [CONSIDER](CONSIDER.md) |

`BRANCH` gives the same result as `IF … ELSE IF … ELSE`, without nesting each `IF` deeper.

## Related pages

- [IF](IF.md)
- [CONSIDER](CONSIDER.md)
- [Control flow](README.md)
