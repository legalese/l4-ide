# math

Exponentials, logarithms, square roots and trigonometry. Import it with `IMPORT math`.

The functions are lowercase wrappers around the [built-in](../builtins/README.md#numbers) `LN`, `SQRT`, `ASIN` and so on. Where the built-in stops with an error on bad input, the wrapper gives `NOTHING`, so the result is a `MAYBE NUMBER`.
`exp` is the exception: it gives a plain `NUMBER`, and stops with the built-in's error when the result is too large.
Every function here but `absNumber` stops with the built-in's error, not with `NOTHING`, for an input past the range of a floating-point number (about 1.8E308 either side of 0), and `ln` and `log10` do so for an input too close to 0 to be held as one (about 4.9E-324).

**Example:** [math-example.l4](math-example.l4)

## Constants

| Constant      | Value                                                                  |
| ------------- | ---------------------------------------------------------------------- |
| `EULER`       | Euler's number, 2.718281828459045                                      |
| `TAN_EPSILON` | 0.000000001, the threshold below which `tan` treats the cosine as zero |

## Functions

| Function    | Input       | Gives        | What it does                                       |
| ----------- | ----------- | ------------ | -------------------------------------------------- |
| `exp`       | `x`: NUMBER | NUMBER       | e to the power `x`; an error above about 709.78    |
| `ln`        | `x`: NUMBER | MAYBE NUMBER | Natural logarithm; `NOTHING` if `x` is 0 or less   |
| `log10`     | `x`: NUMBER | MAYBE NUMBER | Base-10 logarithm; `NOTHING` if `x` is 0 or less   |
| `sqrt`      | `x`: NUMBER | MAYBE NUMBER | Square root; `NOTHING` if `x` is negative          |
| `absNumber` | `x`: NUMBER | NUMBER       | Absolute value                                     |
| `sin`       | `x`: NUMBER | MAYBE NUMBER | Sine; never `NOTHING`                              |
| `cos`       | `x`: NUMBER | MAYBE NUMBER | Cosine; never `NOTHING`                            |
| `tan`       | `x`: NUMBER | MAYBE NUMBER | Tangent; `NOTHING` where the cosine is almost zero |
| `asin`      | `x`: NUMBER | MAYBE NUMBER | Arc sine; `NOTHING` outside -1 to 1                |
| `acos`      | `x`: NUMBER | MAYBE NUMBER | Arc cosine; `NOTHING` outside -1 to 1              |
| `atan`      | `x`: NUMBER | MAYBE NUMBER | Arc tangent; never `NOTHING`                       |

Angles are in radians.
