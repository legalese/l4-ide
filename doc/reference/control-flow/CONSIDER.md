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

Use `_` to ignore values:

```l4
GIVEN xs IS A LIST OF NUMBER
firstElement xs MEANS
  CONSIDER xs
  WHEN EMPTY THEN 0
  WHEN head FOLLOWED BY _ THEN head
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
A number repeated in another spelling (`WHEN 1.0` after `WHEN 1`) is a redundant branch.
A CONSIDER reads these exactly as a rule written as clauses does ([Multi-clause DECIDE](../functions/multi-clause-DECIDE.md#limits)), so the two spellings of one rule warn alike.
BOOLEAN (just TRUE/FALSE) is checked normally; the builtin container types MAYBE, EITHER, and LIST are not yet analysed.

The analysis applies wherever the CONSIDER appears, including inside WHERE- and LET-bound local definitions. Warnings do not stop the file from evaluating — `#EVAL` directives still run.

See [Troubleshooting: Compiler Warnings](../errors/README.md#compiler-warnings) for the warning messages and fixes.

## Related Keywords

- **[IF](IF.md)** - Simple conditional alternative
- **[Multi-clause DECIDE](../functions/multi-clause-DECIDE.md)** - One `DECIDE` clause per case, which L4 turns into a CONSIDER
- **[CONTROL-FLOW](README.md)** - All control flow keywords

> Note: WHEN, OTHERWISE, and BRANCH are part of the CONSIDER syntax.
