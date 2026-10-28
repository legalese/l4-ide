# CONSIDER

`CONSIDER` looks at a value and chooses a result by its shape: which value of an enumeration it is, whether a `MAYBE` holds something, whether a list is empty, and so on. Other languages call this `case` or `match`.

## Syntax

```text
CONSIDER expression
WHEN pattern1 THEN result1
WHEN pattern2 THEN result2
OTHERWISE default-result
```

The branches are tried from top to bottom, and the first that matches gives the result.
`OTHERWISE` matches anything and is optional. On one line, separate the branches with commas.

**Example file:** [consider-example.l4](consider-example.l4)

## Patterns

### Values of an enumeration

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN colour IS A Colour
GIVETH A STRING
`name of` colour MEANS
  CONSIDER colour
  WHEN Red THEN "red"
  WHEN Green THEN "green"
  WHEN Blue THEN "blue"
```

### Values with fields

A pattern names the fields it takes apart, in the order they are declared:

```l4
DECLARE Shape IS ONE OF
  Circle HAS radius IS A NUMBER
  Rectangle HAS width IS A NUMBER, height IS A NUMBER

GIVEN shape IS A Shape
GIVETH A NUMBER
`area of` shape MEANS
  CONSIDER shape
  WHEN Circle r THEN 3.14159 TIMES r TIMES r
  WHEN Rectangle w h THEN w TIMES h
```

### Lists

```l4
GIVEN xs IS A LIST OF NUMBER
GIVETH A NUMBER
`total of` xs MEANS
  CONSIDER xs
  WHEN EMPTY THEN 0
  WHEN first FOLLOWED BY rest THEN first PLUS `total of` rest
```

### MAYBE values

```l4
GIVEN amount IS A MAYBE NUMBER
GIVETH A NUMBER
`amount or zero` amount MEANS
  CONSIDER amount
  WHEN NOTHING THEN 0
  WHEN JUST a THEN a
```

### Numbers and text

A number or a piece of text matches only itself. Such a `CONSIDER` needs an `OTHERWISE` for the rest:

```l4
GIVEN n IS A NUMBER
GIVETH A STRING
`count word for` n MEANS
  CONSIDER n
  WHEN 0 THEN "none"
  WHEN 1 THEN "one"
  OTHERWISE "many"
```

### Names and wildcards

- A name in a pattern matches anything and stands for that part of the value, like `r` and `first` above.
- `` `_` ``, an underscore in backquotes, matches anything without naming it. A bare `_` is a syntax error.
- `EXACTLY expression` matches a value equal to the expression, for example ``WHEN EXACTLY `the limit` THEN …``.

## Missing and redundant branches

`l4 check` looks at every `CONSIDER` and warns about two things:

- **Missing branches:** a value of the type that no branch matches. The warning lists the branches still needed:

  ```text
  The following branches still need to be considered:

    WHEN Suspended THEN
  ```

- **Redundant branches:** a branch that can never be reached, because the branches above it already match everything it could.

The check knows every value of an enumeration declared in the same file, and `TRUE` and `FALSE`. A `CONSIDER` over an enumeration declared in an imported file gets no missing-branch warning.
A number, a piece of text or a date has no end of values, so the check asks for an `OTHERWISE`.
For `MAYBE`, `EITHER` and lists, it checks what they hold but does not ask for each of `JUST`/`NOTHING`, `LEFT`/`RIGHT` or `EMPTY`/`FOLLOWED BY`.
The check also applies inside `WHERE` and `LET`.

The warnings do not stop the file from running. If evaluation reaches a value that no branch matches, it stops with "The value … reached a CONSIDER that has no branch for it."

The messages and their fixes are in [Error messages: Non-exhaustive pattern match](../errors/README.md#non-exhaustive-pattern-match). Why L4 checks this, and the details of what it can and cannot see, are in [Exhaustiveness](../../concepts/type-system/exhaustiveness.md).

## Related pages

- [DECIDE: Several clauses](../functions/DECIDE.md#several-clauses): a function written as one clause per case, which means the same as a `CONSIDER`
- [IF](IF.md) and [BRANCH](BRANCH.md): choose by conditions
- [Control flow](README.md)
