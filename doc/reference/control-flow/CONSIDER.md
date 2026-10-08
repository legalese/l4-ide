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

**`OTHERWISE` does not catch an input nobody supplied.**
If the value being considered is an input that this run was not given — a section `GIVEN` the directive left out, say — `CONSIDER` cannot tell which branch it belongs to.
Evaluation stops and names the input, exactly as `IF` does:

```
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

**Primitive-type caveat:** the analysis is skipped when the scrutinee has type NUMBER, STRING, or DATE. These types have effectively infinite value sets, so exhaustiveness cannot be decided by enumerating constructors. Matches on such values are never warned about — include an OTHERWISE branch to avoid runtime failures. BOOLEAN (just TRUE/FALSE) is checked normally, and so are the builtin container types MAYBE, EITHER, and LIST. Whatever the type, a CONSIDER in which any branch's pattern contains a number or a piece of text, even nested (`WHEN JUST 1`), or is an `EXACTLY` pattern, is not analysed at all.

The analysis applies wherever the CONSIDER appears, including inside WHERE- and LET-bound local definitions. Warnings do not stop the file from evaluating — `#EVAL` directives still run.

See [Troubleshooting: Compiler Warnings](../errors/README.md#compiler-warnings) for the warning messages and fixes.

## Related Keywords

- **[IF](IF.md)** - Simple conditional alternative
- **[CONTROL-FLOW](README.md)** - All control flow keywords

> Note: WHEN, OTHERWISE, and BRANCH are part of the CONSIDER syntax.
