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

## OTHERWISE

`OTHERWISE` matches anything, so it ends a `CONSIDER` that should have an answer whatever the value is.

**`OTHERWISE` does not catch an input nobody supplied.**
If the value being considered is an input that this run was not given, a section `GIVEN` the directive left out, say, `CONSIDER` cannot tell which branch it belongs to.
Evaluation stops and names the input, exactly as `IF` does:

```text
I could not continue evaluating, because I needed to know the value of
  n
but it is an assumed term.
```

Taking the `OTHERWISE` branch would give an answer the facts do not support, since the input could turn out to be `0`.
The same holds for a field read on a record nobody supplied, such as `d's age`: it stops on `d`.
A branch that another part of the same value rules out for certain is still skipped as usual.
In `CONSIDER Claim k 5 WHEN Claim Retail 0 THEN "first", WHEN Claim kk a THEN "second"`, the `5` rules out `0`, so the answer is `"second"` whatever `k` is.
L4 looks only at parts written as a literal or already worked out; it works nothing new out to decide.
Whether a part counts as already worked out can depend on what the rule has worked out elsewhere, so the same `CONSIDER` can stop in one rule and answer in another.
Either way it never gives a wrong answer: when it stops, it is asking for the input.

## Missing and redundant branches

`l4 check` looks at every `CONSIDER` and warns about two things:

- **Missing branches:** a value of the type that no branch matches. The warning lists the branches still needed:

  ```text
  The following branches still need to be considered:

    WHEN Suspended THEN
  ```

- **Redundant branches:** a branch that can never be reached, because the branches above it already match everything it could.

The check knows every value of an enumeration declared in the same file, and `TRUE` and `FALSE`. A `CONSIDER` over an enumeration declared in an imported file gets no missing-branch warning.

**Numbers, text and dates:** a `NUMBER`, a `STRING` or a `DATE` has no end of values, so a `WHEN` with a number or a piece of text, even nested (`WHEN JUST 1`), matches one value, and a `CONSIDER` over such a scrutinee is complete only with an `OTHERWISE`, which the warning suggests.
`EXACTLY` of a number, a piece of text or a value of an enumeration is read as that value; any other `EXACTLY` counts for nothing over a number, a piece of text or a date, and stops the check over any other type.
An `EXACTLY` of the scrutinee's own name, `WHEN EXACTLY n` in `CONSIDER n`, matches every value, as `OTHERWISE` does, so the branches after it are reported as redundant.
A branch that matches anything (an `OTHERWISE`, a name such as `WHEN v`, `` WHEN `_` ``, or `WHEN EXACTLY n` in `CONSIDER n`) is reported as redundant when it follows another such branch.
An `OTHERWISE` after branches that between them name every constructor is not reported, so a defensive catch-all there is allowed.
An `EXACTLY` of any other expression that mentions the scrutinee, such as `WHEN EXACTLY (n PLUS 1)`, stops the check over any type, with no warning, since such a branch may match any number of the scrutinee's values.
A number repeated in another spelling (`WHEN 1.0` after `WHEN 1`) is a redundant branch.
A `CONSIDER` reads these exactly as a rule written as clauses does ([Non-exhaustive pattern match](../errors/README.md#non-exhaustive-pattern-match)), so the two spellings of one rule warn alike.
One limit, which warns rather than stays silent: an `EXACTLY` of a name that a `WHERE` or a `LET` defines as the scrutinee itself (`WHEN EXACTLY y` in `CONSIDER x`, with `y MEANS x`) is read as a value the check cannot name, so the check asks for an `OTHERWISE` that would never be used; write that branch as `OTHERWISE`.
`BOOLEAN` (just `TRUE` and `FALSE`) is checked normally, and so are the builtin container types `MAYBE`, `EITHER` and `LIST`.
The check also applies inside `WHERE` and `LET`.

The warnings do not stop the file from running. If evaluation reaches a value that no branch matches, it stops with "The value … reached a CONSIDER that has no branch for it."

The messages and their fixes are in [Error messages: Non-exhaustive pattern match](../errors/README.md#non-exhaustive-pattern-match). Why L4 checks this, and the details of what it can and cannot see, are in [Exhaustiveness](../../concepts/type-system/exhaustiveness.md).

## Related pages

- [DECIDE: Several clauses](../functions/DECIDE.md#several-clauses): a function written as one clause per case, which means the same as a `CONSIDER`
- [IF](IF.md) and [BRANCH](BRANCH.md): choose by conditions
- [Control flow](README.md)
