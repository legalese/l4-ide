# CONSIDER

Pattern matching construct that examines a value and executes different branches based on its structure.

## Syntax

```l4
CONSIDER expression
WHEN pattern1 THEN result1
WHEN pattern2 THEN result2
...
```

## Purpose

CONSIDER enables pattern matching on algebraic types (enums and records), lists, and other structured data. It's similar to `case` or `match` in other functional languages.

## Examples

**Example file:** [consider-example.l4](consider-example.l4)

### Matching Enums

```l4
DECLARE Colour IS ONE OF red, green, blue

GIVEN c IS A Colour
colourName c MEANS
  CONSIDER c
  WHEN red THEN "Red"
  WHEN green THEN "Green"
  WHEN blue THEN "Blue"
```

### Matching Lists

```l4
GIVEN xs IS A LIST OF NUMBER
GIVETH A NUMBER
sumList xs MEANS
  CONSIDER xs
  WHEN EMPTY THEN 0
  WHEN head FOLLOWED BY tail THEN head PLUS sumList tail
```

### Matching MAYBE Values

```l4
GIVEN mx IS A MAYBE NUMBER
getOrDefault mx MEANS
  CONSIDER mx
  WHEN NOTHING THEN 0
  WHEN JUST x THEN x
```

### Matching Constructors with Fields

```l4
DECLARE Shape IS ONE OF
  Circle HAS radius IS A NUMBER
  Rectangle HAS width IS A NUMBER, height IS A NUMBER

GIVEN s IS A Shape
area s MEANS
  CONSIDER s
  WHEN Circle r THEN 3.14159 TIMES r TIMES r
  WHEN Rectangle w h THEN w TIMES h
```

### Using Wildcards

Use `` `_` ``, an underscore in backquotes, to ignore a value:

```l4
GIVEN xs IS A LIST OF NUMBER
firstElement xs MEANS
  CONSIDER xs
  WHEN EMPTY THEN 0
  WHEN head FOLLOWED BY `_` THEN head
```

## OTHERWISE

Use OTHERWISE for a catch-all pattern:

```l4
GIVEN n IS A NUMBER
describe n MEANS
  CONSIDER n
  WHEN 0 THEN "zero"
  WHEN 1 THEN "one"
  OTHERWISE "many"
```

## Exhaustiveness Checking

The typechecker analyzes every CONSIDER expression and emits **warnings** (not errors) for two situations:

- **Missing branches:** the branches do not cover all constructors of the scrutinee's type. The warning lists the uncovered patterns. The program still compiles, but matching an uncovered value raises a runtime error.
- **Redundant branches:** a branch can never be reached because earlier branches (or an earlier OTHERWISE) already cover everything it could match.

```l4
DECLARE Status IS ONE OF Active, Suspended, Closed

GIVEN s IS A Status
describe s MEANS
  CONSIDER s
  WHEN Active THEN "running"
  WHEN Closed THEN "stopped"
  -- Warning: missing branch for Suspended
```

Adding the missing constructor branch or an OTHERWISE catch-all silences the warning.

**Numbers, text and dates:** a NUMBER, a STRING or a DATE has no end of values, so a WHEN with a number or a piece of text matches one value, and a CONSIDER over such a scrutinee is complete only with an OTHERWISE, which the warning suggests.
`EXACTLY` of a number, a piece of text or a value of an enumeration is read as that value; any other `EXACTLY` counts for nothing over a number, a piece of text or a date, and stops the check over any other type.
An `EXACTLY` of the scrutinee's own name, `WHEN EXACTLY n` in `CONSIDER n`, matches every value, as `OTHERWISE` does, so the branches after it are reported as redundant.
A branch that matches anything (an `OTHERWISE`, a name such as `WHEN v`, `` WHEN `_` ``, or `WHEN EXACTLY n` in `CONSIDER n`) is reported as redundant when it follows another such branch.
An `OTHERWISE` after branches that between them name every constructor is not reported, so a defensive catch-all there is allowed.
An `EXACTLY` of any other expression that mentions the scrutinee, such as `WHEN EXACTLY (n PLUS 1)`, stops the check over any type, with no warning, since such a branch may match any number of the scrutinee's values.
A number repeated in another spelling (`WHEN 1.0` after `WHEN 1`) is a redundant branch.
A CONSIDER reads these as a rule written as clauses does ([Multi-clause DECIDE](../functions/multi-clause-DECIDE.md#limits)), so the two spellings of one rule warn alike about missing cases over enumerations declared in the same file, numbers, text and `EXACTLY`.
They differ on branches that are never used: a CONSIDER reports `WHEN 1.0` after `WHEN 1`, or `WHEN Red` twice, as redundant, while a rule written as clauses reports a clause as never used only when a clause above it matches every input, so `DECIDE f 1.0` after `DECIDE f 1`, or `DECIDE f Red` twice, draws no warning.
They can also differ where a branch or clause names a constructor of a `MAYBE`, an `EITHER`, a list or a type declared in another file: a CONSIDER then keeps the older check described below, and a rule written as clauses is read only as far as the check need not tell such values apart, so one spelling can warn where the other is silent, in either direction.
With `DECLARE Colour IS ONE OF Red, Green, Blue` and an input that is a `MAYBE Colour`, the clauses `DECIDE f (JUST Red) IS 1` and `DECIDE f NOTHING IS 0` draw no warning, while `WHEN JUST Red` and `WHEN NOTHING` in a CONSIDER ask for `WHEN JUST Green` and `WHEN JUST Blue`.
One limit, which warns rather than stays silent: an `EXACTLY` of a name that a `WHERE` or a `LET` defines as the scrutinee itself (`WHEN EXACTLY y` in `CONSIDER x`, with `y MEANS x`) is read as a value the check cannot name, so the check asks for an `OTHERWISE` that would never be used; write that branch as `OTHERWISE`.
BOOLEAN (just TRUE/FALSE) is checked normally.
The builtin container types MAYBE, EITHER and LIST are checked only inside: their own constructors are not listed, so a CONSIDER with only `WHEN JUST x`, only `WHEN NOTHING`, only `WHEN LEFT x` or only `WHEN EMPTY` gets no warning, but what they hold is, so `WHEN JUST Basic` over a `MAYBE Tier` asks for `WHEN JUST Premium` and `WHEN JUST Gold`, and not for `WHEN NOTHING`.
A CONSIDER with no number, text or `EXACTLY` in it whose missing branches are too many for that check to list (more than 64, or more than 10000 steps to find them, the [limits](../functions/multi-clause-DECIDE.md#limits) at which a rule written as clauses with no number or text gets no warning) still warns: it is checked the older way instead, which lists some of the missing branches, not always all of them, and on such tables can take a long time: from 30 seconds to over two minutes for the widest tried, records of five fields of four to eight values each.
A nest of CONSIDERs many levels deep, each without an `OTHERWISE`, is also slow to check: see [Limits](../functions/multi-clause-DECIDE.md#limits).

The analysis applies wherever the CONSIDER appears, including inside WHERE- and LET-bound local definitions. Warnings do not stop the file from evaluating — `#EVAL` directives still run.

See [Troubleshooting: Compiler Warnings](../errors/README.md#compiler-warnings) for the warning messages and fixes.

## Related Keywords

- **[IF](IF.md)** - Simple conditional alternative
- **[Multi-clause DECIDE](../functions/multi-clause-DECIDE.md)** - One `DECIDE` clause per case, which L4 turns into a CONSIDER
- **[CONTROL-FLOW](README.md)** - All control flow keywords

> Note: WHEN, OTHERWISE, and BRANCH are part of the CONSIDER syntax.
