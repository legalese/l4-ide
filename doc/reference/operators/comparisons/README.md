# Comparisons

The comparison operators compare two values of the same type and give a BOOLEAN.

| Word                    | Symbol | TRUE when                     | Example             |
| ----------------------- | ------ | ----------------------------- | ------------------- |
| `EQUALS`                | `=`    | the values are equal          | `5 EQUALS 5`        |
| `GREATER THAN`, `ABOVE` | `>`    | the first is greater          | `10 GREATER THAN 5` |
| `LESS THAN`, `BELOW`    | `<`    | the first is smaller          | `3 BELOW 7`         |
| `AT LEAST`              | `>=`   | the first is greater or equal | `5 AT LEAST 5`      |
| `AT MOST`               | `<=`   | the first is smaller or equal | `4 AT MOST 10`      |

There is no "not equal" operator: write `NOT a EQUALS b`.

**Example file:** [comparisons-example.l4](comparisons-example.l4)

## Types

- `EQUALS` works on numbers, text, booleans, values of enumerations, records and lists.
- The ordering operators work on `NUMBER`, `STRING` (in character-code order, so `"B" < "a"`) and `BOOLEAN` (`FALSE` is less than `TRUE`).
- Dates can be compared once the [daydate](../../libraries/daydate.md) library is imported.

## Combining comparisons

Comparisons bind more tightly than `AND` and `OR`, so no parentheses are needed:

```l4
GIVEN age IS A NUMBER
      income IS A NUMBER
GIVETH A BOOLEAN
`is eligible` age income MEANS
      age AT LEAST 18
  AND age AT MOST 65
  AND income GREATER THAN 30000
```

See [Operators: Precedence](../README.md#precedence).

## Related pages

- [AND, OR, NOT, IMPLIES](../logical.md)
- [Arithmetic](../arithmetic/README.md)
- [IF](../../control-flow/IF.md)
