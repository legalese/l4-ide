# Operators

Operators combine values into expressions: arithmetic, comparisons and logic.
Most have a word form, which reads well in legal text, and a symbol form; the two mean the same and can be mixed. Words suit rules that lawyers read; symbols are shorter.

## Pages

- [AND, OR, NOT, IMPLIES](logical.md): logical operators and their truth table
- [UNLESS](UNLESS.md): exceptions
- [Arithmetic](arithmetic/README.md): `PLUS`, `MINUS`, `TIMES`, `DIVIDED BY`, `MODULO`
- [Comparisons](comparisons/README.md): `EQUALS`, `GREATER THAN`, `AT LEAST` and the others

## Word and symbol forms

| Word         | Symbol | Word                    | Symbol |
| ------------ | ------ | ----------------------- | ------ |
| `PLUS`       | `+`    | `EQUALS`                | `=`    |
| `MINUS`      | `-`    | `GREATER THAN`, `ABOVE` | `>`    |
| `TIMES`      | `*`    | `LESS THAN`, `BELOW`    | `<`    |
| `DIVIDED BY` | `/`    | `AT LEAST`              | `>=`   |
| `MODULO`     |        | `AT MOST`               | `<=`   |
| `AND`        | `&&`   | `OR`                    | `\|\|` |
| `IMPLIES`    | `=>`   | `NOT`, `UNLESS`         |        |

**Example file:** [textual-vs-symbolic-example.l4](textual-vs-symbolic-example.l4)

## Precedence

From the tightest-binding to the loosest:

| Level | Operators                                                                      | Grouping      |
| ----- | ------------------------------------------------------------------------------ | ------------- |
| 1     | function application, `'s`                                                     |               |
| 2     | `TIMES`, `DIVIDED BY`, `MODULO`                                                | left to right |
| 3     | `PLUS`, `MINUS`                                                                | left to right |
| 4     | `FOLLOWED BY`                                                                  | to the right  |
| 5     | `EQUALS`, `GREATER THAN`, `LESS THAN`, `AT LEAST`, `AT MOST` and their symbols |               |
| 6     | `AND`, `...`, `RAND`                                                           | to the right  |
| 7     | `OR`, `..`, `ROR`                                                              | to the right  |
| 8     | `IMPLIES`, `UNLESS`                                                            | to the right  |

- `2 + 3 * 4` is `14`, and `10 - 4 - 3` is `3`.
- `NOT` is not in the table: it reaches forward over everything after it on its line, so `NOT a AND b` would mean `NOT (a AND b)`, and L4 refuses that spelling. Write `NOT (a AND b)` for the wide reading or `(NOT a) AND b` for the narrow one. See [How far does NOT reach?](logical.md#how-far-does-not-reach).
- Parentheses override precedence: `(2 + 3) * 4` is `20`.
- When an expression spans several lines, an operator written further left than the lines above it applies to all of them together. See [Several lines](logical.md#several-lines).

**Example files:** [precedence-example.l4](precedence-example.l4), [associativity-example.l4](associativity-example.l4)

## Asyndetic AND and OR

Legal text often lists conditions with punctuation instead of "and" or "or". L4 has two such forms:

- `...` (three dots) means `AND`: `` `is a citizen` ... `is over 18` ... `has ID` ``
- `..` (two dots) means `OR`: `` approved .. pending .. `under review` ``

They have the same precedence as `AND` and `OR`.

**Example file:** [asyndetic-example.l4](asyndetic-example.l4)

## Other operators

- `FOLLOWED BY` adds an element to the front of a list: `1 FOLLOWED BY LIST 2, 3` is `LIST 1, 2, 3`.
- `'s` reads a field of a record: `` `the buyer`'s age ``. See [Syntax and directives: Genitive](../syntax/README.md#genitive).
- `%` after a number divides it by 100: `5%` is `0.05`.
- `AS STRING` converts a value to text; see [Coercions](../types/coercions.md).
- `CONCAT` joins text: `CONCAT "a", "b", "c"`. The [prelude](../libraries/prelude.md) adds `APPEND` (`"a" APPEND "b"`); see [Built-in functions](../builtins/README.md).
- `RAND` and `ROR` combine obligations; see [Deadlines and consequences](../regulative/consequences.md).
