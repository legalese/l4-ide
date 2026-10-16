# MEANS

`MEANS` gives the body of a function or a value, written without `DECIDE`.

## Syntax

```text
name MEANS expression
name input1 input2 ... MEANS expression
```

`name MEANS expression` defines the same thing as `DECIDE name IS expression`.
The two keywords do not mix: `DECIDE name MEANS ...` and a top-level `name IS ...` are syntax errors.

**Example file:** [means-example.l4](means-example.l4)

## Examples

```l4
`the greeting` MEANS "Hello, World!"

GIVEN n IS A NUMBER
GIVETH A NUMBER
`factorial of` n MEANS
  IF n EQUALS 0
  THEN 1
  ELSE n TIMES `factorial of` (n MINUS 1)
```

The inputs can sit before, between or after the words of the name, so a call reads like a sentence:

```l4
GIVEN buyer IS A STRING
      seller IS A STRING
GIVETH A STRING
buyer `buys from` seller MEANS CONCAT buyer, " buys from ", seller

#EVAL "Alice" `buys from` "Bob"
```

See [Mixfix functions](README.md#mixfix-functions).

## Other places MEANS appears

- Under `WHERE`, each local definition uses `MEANS`; see [LET and WHERE](LET.md#where).
- After `LET`, `MEANS` is one of the keywords that can introduce a definition, with `IS`, `BE`, `MEAN` and `=`.
- Inside a `DECLARE … HAS`, a field with `MEANS` is a computed field; see [DECLARE: Computed fields](../types/DECLARE.md#computed-fields).
- A function can be written as several `MEANS` lines, one per case; see [DECIDE: Several clauses](DECIDE.md#several-clauses).

## Related pages

- [DECIDE](DECIDE.md)
- [GIVEN and GIVETH](GIVEN.md)
