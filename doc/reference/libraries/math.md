# math

Exponentials, logarithms, square roots and trigonometry. Import it with `IMPORT math`.

The functions are lowercase wrappers around the [built-in](../builtins/README.md#numbers) `LN`, `SQRT`, `ASIN` and so on. Where the built-in stops with an error on bad input, the wrapper gives `NOTHING`, so the result is a `MAYBE NUMBER`.

**Example:** [math-example.l4](math-example.l4)

## Constants

| Constant      | Value                                                                  |
| ------------- | ---------------------------------------------------------------------- |
| `EULER`       | Euler's number, 2.718281828459045                                      |
| `TAN_EPSILON` | 0.000000001, the threshold below which `tan` treats the cosine as zero |

## Functions

| Function    | Input       | Gives        | What it does                                       |
| ----------- | ----------- | ------------ | -------------------------------------------------- |
| `exp`       | `x`: NUMBER | NUMBER       | e to the power `x`                                 |
| `ln`        | `x`: NUMBER | MAYBE NUMBER | Natural logarithm; `NOTHING` if `x` is 0 or less   |
| `log10`     | `x`: NUMBER | MAYBE NUMBER | Base-10 logarithm; `NOTHING` if `x` is 0 or less   |
| `sqrt`      | `x`: NUMBER | MAYBE NUMBER | Square root; `NOTHING` if `x` is negative          |
| `absNumber` | `x`: NUMBER | NUMBER       | Absolute value                                     |
| `sin`       | `x`: NUMBER | MAYBE NUMBER | Sine; always `JUST`                                |
| `cos`       | `x`: NUMBER | MAYBE NUMBER | Cosine; always `JUST`                              |
| `tan`       | `x`: NUMBER | MAYBE NUMBER | Tangent; `NOTHING` where the cosine is almost zero |
| `asin`      | `x`: NUMBER | MAYBE NUMBER | Arc sine; `NOTHING` outside -1 to 1                |
| `acos`      | `x`: NUMBER | MAYBE NUMBER | Arc cosine; `NOTHING` outside -1 to 1              |
| `atan`      | `x`: NUMBER | MAYBE NUMBER | Arc tangent; always `JUST`                         |

Angles are in radians.
