# LET and WHERE

`LET` and `WHERE` give names to values that are used only inside one expression.
`LET` puts the definitions before the expression; `WHERE` puts them after it.
Use whichever matches the order of the legal text.

## Syntax

```text
LET name IS expression IN body

LET
  name1 IS expression1
  name2 IS expression2
IN body

body
WHERE
  name1 MEANS expression1
  name2 MEANS expression2
```

Several definitions go one per line, lined up in the same column; commas between them are a syntax error.

**Example files:** [let-example.l4](let-example.l4), [where-example.l4](where-example.l4)

## LET

```l4
GIVEN price IS A NUMBER
GIVETH A NUMBER
`total price` price MEANS
  LET
    `the tax` IS price TIMES 0.2
    `the fee` IS 5
  IN price PLUS `the tax` PLUS `the fee`
```

After `LET`, a definition can use `IS`, `BE`, `MEAN`, `MEANS` or `=`:

```l4
DECIDE `the sum` IS
  LET
    a IS 1
    b BE 2
    c MEAN 3
    d MEANS 4
    e = 5
  IN a PLUS b PLUS c PLUS d PLUS e
```

## WHERE

```l4
GIVEN radius IS A NUMBER
GIVETH A NUMBER
`area of a circle` radius MEANS
  `pi` TIMES radius TIMES radius
  WHERE
    `pi` MEANS 3.14159
```

A definition under `WHERE` can take inputs, so it can be a local function, with or without its own `GIVEN` and `GIVETH`:

```l4
GIVEN a IS A NUMBER
      b IS A NUMBER
GIVETH A NUMBER
`sum of squares` a b MEANS
  `square of` a PLUS `square of` b
  WHERE
    GIVEN n IS A NUMBER
    GIVETH A NUMBER
    `square of` n MEANS n TIMES n
```

A `WHERE` can be nested inside a definition under another `WHERE`.

## Scope

- The names are visible only in the expression they belong to: after `IN` for `LET`, and in the body above for `WHERE`.
- Definitions in one `LET` or one `WHERE` can refer to each other, in any order.
- They can use the function's `GIVEN` inputs and any name defined outside.
- A rule written as [several clauses](DECIDE.md#several-clauses) cannot be defined inside `LET` or `WHERE`.

## Related pages

- [DECIDE](DECIDE.md) and [MEANS](MEANS.md): top-level definitions
- [Error messages: I could not find a definition for the identifier](../errors/README.md#i-could-not-find-a-definition-for-the-identifier)
