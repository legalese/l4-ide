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
A function published with `@export` needs that `GIVEN`, naming and typing each input, even when it has a single clause: see [An @export of clauses with no GIVEN](../errors/README.md#an-export-of-clauses-with-no-given).

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

A number or a piece of text in a clause is checked for missing cases, where the same value in a `CONSIDER` written by hand is not: see [Numbers and text](#limits) below.

Clauses after the first are reached only when the earlier ones do not match, like the `OTHERWISE` above.

## Missing cases

When the clauses match only some of the values of an enumeration, or only one of `TRUE` and `FALSE`, or match particular numbers or texts with no clause for the rest, `l4 check` warns and lists the clauses still needed.
For this `colour.l4`:

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN c IS A Colour
GIVETH A NUMBER
DECIDE price Red   IS 1
DECIDE price Green IS 2
```

`l4 check colour.l4` succeeds, with this warning, which an editor underlines from the first clause's name to the last's:

```
This multi-clause definition does not cover all cases. The following clauses are still needed:

  DECIDE `price` Blue IS
```

Each line is a clause you can paste in and finish by writing its result after `IS`.
When a function has several inputs, an input that any value would do for is written with its `GIVEN` name, which matches anything, or as `` `_` `` if the function has no `GIVEN` for it.
A group of one clause, such as `DECIDE area (Circle Red) IS 1`, is checked the same way, and its warning begins "This clause does not cover all cases." instead.

## Clauses that are never used

L4 tries the clauses from the top, so a clause below one that matches every input is never reached.
`l4 check` warns at the first such clause, and says how many follow it.
For this `never.l4`:

```l4
DECLARE Status IS ONE OF Active, Suspended, Closed

GIVEN status IS A Status
GIVETH A STRING
DECIDE describe status IS "some status"
DECIDE describe Active IS "running"
DECIDE describe Closed IS "stopped"
```

`l4 check never.l4` succeeds, with this warning on the second clause:

```
This clause of `describe` is never used, and neither is the clause after it.
The clause above it matches every input, so `describe` never gets this far.
Move these clauses above that one, or remove them.
```

`describe Active` gives `"some status"`.
A clause that is never used is still checked: a body of the wrong type, or a name that does not exist, is reported there as in any other clause.

## Limits

These were measured with the `l4` built from this version of L4.

**Only at the top level, and only with a plain name first.**
Clauses make one rule only where the rule is defined at the top level of a file or of a section, not inside `WHERE` or `LET`: there, `DECIDE rank Red IS 1` and `DECIDE rank x IS 2` are two definitions, and the first is reported for not matching its `GIVEN`.
A rule whose name sits between or after its inputs, such as ``c `costs` n MEANS n``, cannot be written as clauses either: a line ``Red `costs` 0 MEANS 1`` below it is not read as a clause of that rule, and ``Red `costs` 0`` gives `0`.
Write such a rule with `CONSIDER` instead.

**A bare `_` is not a wildcard.**
`DECIDE f _ IS 2` is a syntax error, `unexpected '_'`.
To match anything, use the `GIVEN` input's name, as `factorial n` does, or write `` `_` `` in backquotes, which is how the missing-case warning writes an input that has no `GIVEN`.

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

**Numbers and text.**
A number or a piece of text matches one value, and there is no end of the others, so a group that matches numbers or texts is complete only with a clause written with the `GIVEN` name, and the warning suggests that clause.
The other inputs of the group are still checked: with `DECIDE charge Red 0 IS 0`, `DECIDE charge Red n IS n` and `DECIDE charge Green n IS n TIMES 2`, the warning lists ``DECIDE `charge` Blue n IS``, since the clause for `0` is one value of `n`, the clause below it covers the rest of `Red`, and `Blue` is still missing.
In a table keyed by a number, the gaps under each number come first, then the clause for every other number: `DECIDE charge 1 Basic IS 10`, `DECIDE charge level Basic IS 30` and `DECIDE charge level Premium IS 40`, over a `Tier` that also has `Gold`, list ``DECIDE `charge` 1 Gold IS`` and then ``DECIDE `charge` level Gold IS``.
A number is written in the warning as the clauses spelled it (`1.50`, `0.1234567890123456789`), by the first clause that names it; a piece of text as L4 writes it, every printable character as it is (`"São Paulo"`) and `"` and `\` escaped.
An input or a field of a record declared under another name for a number, a piece of text or a date (`DECLARE Age IS A NUMBER`) is one to the check.
`EXACTLY` of a number, a piece of text or a value of an enumeration is read as that value: `DECIDE price (EXACTLY Red) IS 1` and `DECIDE price Green IS 2` draw the warning for `Blue`, as `Red` in place of `(EXACTLY Red)` does.
`EXACTLY` of the input's own name, as in `DECIDE f (EXACTLY n) IS 1`, matches every input, like the bare name.
Any other `EXACTLY` (`EXACTLY someConstant`, `EXACTLY (m PLUS 1)` with `m` another input) is a clause the check cannot count: on a number, text or date input it counts for nothing, since only the clause with the input's name can cover the rest of the numbers, and that clause covers it too; on an enumeration input it stops the check for the group.
The same holds inside a pattern: `DECIDE f (Box (EXACTLY zero)) IS 1` with `DECIDE f (Box 1) IS 2`, where `Box` has a number field, counts the first clause for nothing and lists ``DECIDE `f` (Box `_`) IS``.
An `EXACTLY` whose expression mentions the input itself, such as `EXACTLY (n PLUS 0)`, stops the check for the group on any input, since such a clause may match any number of the input's values.
The same values in a `CONSIDER` written by hand draw no warning: a `CONSIDER` over a number or a piece of text is not checked, so a rule warns when written as clauses and not when written as the `CONSIDER` it compiles to.

**Lists, `MAYBE` values and enumerations declared in another file are not read.**
The check cannot tell such values apart, so where a missing case could be found only by telling them apart, the group gets no warning, not even for a number nested inside such a value: `DECIDE show NOTHING IS "none"` and `DECIDE show (JUST 0) IS "zero"` draw none, and neither do `DECIDE f (JUST 0) IS "zero"` and `DECIDE f (JUST n) IS "other"`.
Where the other inputs settle the question first, the warning still comes: `DECIDE t Red EMPTY IS 0`, `DECIDE t Red xs IS 1` and `DECIDE t Green xs IS 2` list ``DECIDE `t` Blue xs IS``, and `DECIDE f Red (JUST 0) IS 0` with `DECIDE f Green m IS 1` lists ``DECIDE `f` Red m IS`` and ``DECIDE `f` Blue m IS``, the clauses that the clauses without a number leave open.
When every clause of such a group has a number or a piece of text in it, as `DECIDE f (JUST 0) IS "zero"` on its own does, the warning suggests the one clause with every input's name, ``DECIDE `f` m IS``, and nothing finer.

The check also gives up, with no warning, when it would list more than 64 clauses, or when it takes more than 10000 steps to find them.
Five inputs over a five-day week, with one clause for each day on all five (`DECIDE same Mon Mon Mon Mon Mon IS 1`, and so on to `Fri`), would need more than 64 clauses listed, and get no warning; the same table with four inputs lists 60.
A clause whose patterns all match anything ends the search, so a table of nine inputs, each tested for `Red` in one clause and for `Green` in another, which used to take more than 10000 steps, lists its one missing clause, `Blue` nine times over.
When the clauses match numbers or texts, the check does not fall silent at those limits: it lists instead only the clauses that the clauses without a number or a piece of text leave open, which, when every clause names a number or a text, is the clause with every input's `GIVEN` name alone, and a gap inside the table is then not listed.
Sixty-four clauses `DECIDE f 1 Basic IS 1` to `DECIDE f 64 Basic IS 64`, over `GIVEN n IS A NUMBER` and `t IS A Tier` of `Basic` and `Premium`, would need 65 clauses listed (`1 Premium` to `64 Premium`, then `n t`), so the warning lists ``DECIDE `f` n t IS`` alone; with 63 such clauses it lists all 64.
There is no `@nonexhaustive` in this version, so a group over numbers or texts that is partial on purpose is silenced only by a clause that matches anything.

When no clause matches at run time, evaluation stops with an error.
For this `describe.l4`:

```l4
GIVEN n IS A NUMBER
GIVETH A STRING
DECIDE describe 0 IS "zero"
DECIDE describe 1 IS "one"

#EVAL describe 1
#EVAL describe 2
```

`l4 check describe.l4` warns ``DECIDE `describe` n IS``; left as written, `l4 run describe.l4` reports for `describe 2`:

```
No clause of `describe` matches these inputs.
The value that the last clause could not match is
  2
Add a clause for this case, or end the clauses with one that matches every input.
```

To be safe, end a group over numbers or texts with a clause that matches anything.

**Only the clauses after one that matches every input are reported as never used.**
That is a clause whose every pattern is its input's `GIVEN` name, `` `_` ``, or a new name: a name that is not a value of its input's type, such as `other`, or `Gren` where `Green` was meant.
When a new name is the cause, the warning names it: "This clause of `colour` is never used, because the clause above it with the new name `Gren` matches every input."
There is no warning for a clause that repeats one above it.
With `DECIDE r Red IS 1`, `DECIDE r Red IS 2` and `DECIDE r other IS 3` followed by `DECIDE r Blue IS 4`, `l4 check` warns that the `Blue` clause is never used, and says nothing about the second `Red` clause; `r Red` gives `1` and `r Blue` gives `3`.

## Related Keywords

- **[DECIDE](DECIDE.md)** - Defines a named value or function
- **[GIVEN](GIVEN.md)** - Declares the inputs
- **[CONSIDER](../control-flow/CONSIDER.md)** - Pattern matching inside an expression
