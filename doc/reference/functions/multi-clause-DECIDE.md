# Multi-clause DECIDE

A function can be written as several `DECIDE` lines, one per case, instead of one `DECIDE` with a `CONSIDER` or an `IF` inside it.
Each line is called a **clause**.
Where an argument goes, a clause can put a value to match, such as `0`, `TRUE` or `Water`.
L4 tries the clauses from top to bottom and uses the first one that matches.

This is how a table of cases in a statute or a contract reads: one row per case.

## Syntax

```l4
GIVEN input IS A Type
GIVETH A ResultType
DECIDE name pattern IS result
DECIDE name pattern IS result
```

The clauses of one function must:

- come one after another, under a single `GIVEN`/`GIVETH`, each starting in the same column;
- use the same function name and the same number of arguments.

`name pattern MEANS result` works too.

## Examples

**Example file:** [multi-clause-decide-example.l4](multi-clause-decide-example.l4)

### Numbers

```l4
GIVEN n IS A NUMBER
GIVETH A NUMBER
DECIDE factorial 0 IS 1
DECIDE factorial n IS n TIMES factorial (n MINUS 1)
```

The first clause matches only `0`.
In the second clause `n` is the `GIVEN` input itself, so it matches any number.
`#EVAL factorial 5` gives `120`.

### Values of an enumeration

```l4
DECLARE Peril IS ONE OF Water, Fire, Cosmetic

GIVEN p IS A Peril
GIVETH A BOOLEAN
DECIDE covered Water    IS TRUE
DECIDE covered Fire     IS TRUE
DECIDE covered Cosmetic IS FALSE
```

### A table over two inputs

```l4
GIVEN weekend IS A BOOLEAN
      day IS A STRING
GIVETH A NUMBER
DECIDE `parking fee` TRUE  day        IS 0
DECIDE `parking fee` FALSE "Saturday" IS 5
DECIDE `parking fee` FALSE day        IS 10
```

`` `parking fee` FALSE "Saturday" `` gives `5`, and `` `parking fee` FALSE "Monday" `` gives `10`: the second clause does not match `"Monday"`, so the third one is used.

### Lists and MAYBE values

A pattern that takes an argument goes in parentheses:

```l4
GIVEN xs IS A LIST OF NUMBER
GIVETH A NUMBER
DECIDE total EMPTY IS 0
DECIDE total (x FOLLOWED BY rest) IS x PLUS total rest

GIVEN amount IS A MAYBE NUMBER
GIVETH A NUMBER
DECIDE `amount or zero` NOTHING IS 0
DECIDE `amount or zero` (JUST a) IS a
```

## What it means

L4 turns the clauses into one function whose body is a [CONSIDER](../control-flow/CONSIDER.md).
The factorial above means the same as:

```l4
GIVEN n IS A NUMBER
GIVETH A NUMBER
DECIDE factorial n IS
  CONSIDER n
  WHEN 0 THEN 1
  OTHERWISE n TIMES factorial (n MINUS 1)
```

In each argument position:

- a value (`0`, `"Saturday"`, `TRUE`, `Water`, `EMPTY`, `(JUST a)`) matches only that value, and becomes a `WHEN`;
- the name of the `GIVEN` input for that position matches anything, and needs no test;
- any other name matches anything and stands for that argument inside its own clause, like `x` and `rest` above.

Clauses after the first are reached only when the earlier ones do not match, like the `OTHERWISE` above.

## Limits

These were measured with the `l4` built from this version of L4.

**No `_` wildcard.**
`DECIDE f _ IS 2` is a syntax error, `unexpected '_'`.
To match anything, use the `GIVEN` input's name instead, as `factorial n` does.

**Names and the `GIVEN`.**
In a group of two or more clauses, a name in an argument position that differs from the `GIVEN` is accepted and stands for that argument.
With `GIVEN x IS A NUMBER` and `y IS A NUMBER`, the clauses `DECIDE f 0 q IS q` and `DECIDE f p q IS p PLUS q` are accepted, and `f 2 5` gives `7`.
A single `DECIDE` line whose arguments are all plain names, or enumeration values like `Water`, is an ordinary definition, and its names must match the `GIVEN`.
For this `double.l4`:

```l4
GIVEN a IS A NUMBER
GIVETH A NUMBER
DECIDE double b IS a TIMES 2
```

`l4 check double.l4` reports:

```
The names in a type signature must match those in the definition.

However, this name `a` appears in the signature,
and the corresponding name in the definition is

  b (at double.l4:3:15-16)
```

**No warning for a missing case.**
Nothing warns when a group of clauses does not cover every value.
When no clause matches, evaluation stops with an error.
For this `describe.l4`:

```l4
GIVEN n IS A NUMBER
GIVETH A STRING
DECIDE describe 0 IS "zero"
DECIDE describe 1 IS "one"

#EVAL describe 1
#EVAL describe 2
```

`l4 check describe.l4` succeeds with no warning, and `l4 run describe.l4` reports for `describe 2`:

```
The value
  2
reached a CONSIDER that has no branch for it.
Add a WHEN branch for this case, or a catch-all OTHERWISE branch.
The typechecker's exhaustiveness warning lists all missing branches.
```

Its last sentence does not apply here, because no such warning is shown for a group of clauses.
To be safe, end the group with a clause that matches anything.

**Clauses after a catch-all are not checked.**
A clause that matches anything ends the group for checking.
In `DECIDE f n IS 7` followed by `DECIDE f 0 IS "oops" PLUS TRUE`, the second clause is never type-checked: `l4 check` succeeds, and `f 0` gives `7`.
Put the catch-all clause last.

## Related Keywords

- **[DECIDE](DECIDE.md)** - Defines a named value or function
- **[GIVEN](GIVEN.md)** - Declares the inputs
- **[CONSIDER](../control-flow/CONSIDER.md)** - Pattern matching inside an expression
