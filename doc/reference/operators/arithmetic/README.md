# Arithmetic

The arithmetic operators work on `NUMBER`. Each has a word form and a symbol form, except `MODULO`, which has only the word.

| Word         | Symbol | Operation                | Example              |
| ------------ | ------ | ------------------------ | -------------------- |
| `PLUS`       | `+`    | addition                 | `5 PLUS 3` is `8`    |
| `MINUS`      | `-`    | subtraction              | `10 - 4` is `6`      |
| `TIMES`      | `*`    | multiplication           | `6 TIMES 7` is `42`  |
| `DIVIDED BY` | `/`    | division                 | `10 / 4` is `2.5`    |
| `MODULO`     |        | remainder after division | `17 MODULO 5` is `2` |

**Example file:** [arithmetic-example.l4](arithmetic-example.l4)

## Exact numbers

Arithmetic is exact: `(1 / 3) * 3 = 1` and `0.1 + 0.2 = 0.3` are both TRUE.
A result that has no finite decimal form, such as `1 / 3`, is shown rounded (`0.3333333333333333`), but the value itself is exact.

`MODULO` works on whole numbers only: `7 MODULO 2.5` stops evaluation with an error.
A negative number in an expression needs parentheses: `(-3) * 4`.

## Precedence

`TIMES`, `DIVIDED BY` and `MODULO` bind more tightly than `PLUS` and `MINUS`, and operators of the same level are applied from left to right:

```l4
#EVAL 2 + 3 * 4        -- 14
#EVAL (2 + 3) * 4      -- 20
#EVAL 10 - 4 - 3       -- 3
```

The full table, with comparisons and logical operators, is in [Operators: Precedence](../README.md#precedence).

## More functions

Rounding (`ROUND`, `FLOOR`, `CEILING`, `TRUNC`) and functions such as `SQRT` are [built-in functions](../../builtins/README.md). The [math](../../libraries/math.md) library adds more.

## Related pages

- [Comparisons](../comparisons/README.md)
- [Types](../../types/README.md): `NUMBER`
