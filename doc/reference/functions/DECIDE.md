# DECIDE

`DECIDE` defines a named value or a function: a rule with a name, its inputs, and the expression that gives its result.

## Syntax

```text
DECIDE name IS expression
DECIDE name IF condition
DECIDE name input1 input2 ... IS expression
name input1 input2 ... MEANS expression
```

- After `DECIDE`, `IS` and `IF` mean the same. `IF` reads better for a rule that gives a BOOLEAN.
- Without `DECIDE`, the body is introduced by `MEANS` (see [MEANS](MEANS.md)). `DECIDE name MEANS ...` is a syntax error.
- A function's inputs are declared with [GIVEN](GIVEN.md) on the lines above it, and its result type with [GIVETH](GIVEN.md#giveth).

**Example file:** [decide-example.l4](decide-example.l4)

## Values

```l4
DECIDE `the standard rate` IS 0.2
DECIDE `the welcome message` IS "Welcome"
```

## Functions

```l4
GIVEN amount IS A NUMBER
GIVETH A NUMBER
DECIDE `the tax on` amount IS amount TIMES 0.2
```

The names after the function name are its `GIVEN` inputs, in order.
They can be left out: under the same `GIVEN`, ``DECIDE `the tax` IS amount TIMES 0.2`` also takes one input.
When they are written, they must match the `GIVEN` names.

A body can end with `WHERE` and use the names defined there; see [LET and WHERE](LET.md).

## DECIDE IF

`DECIDE name IF condition` means the same as `DECIDE name IS condition`: the rule is TRUE exactly when the condition is.
It is the usual way to write a legal test ("a person is eligible if ...").

```l4
GIVEN age IS A NUMBER
      income IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is eligible` age income IF
  age >= 18 AND income > 30000
```

For `IF … THEN … ELSE` inside a body, see [IF and BRANCH](../control-flow/IF.md).

## Several clauses

A function can be written as several `DECIDE` lines, one per case.
Each line is a **clause**. Where an input goes, a clause can put a value to match, such as `0`, `TRUE` or `Water`.
L4 tries the clauses from top to bottom and uses the first one that matches, the way a table of cases in a statute is read.

```l4
DECLARE Peril IS ONE OF Water, Fire, Cosmetic

GIVEN peril IS A Peril
GIVETH A BOOLEAN
DECIDE covered Water    IS TRUE
DECIDE covered Fire     IS TRUE
DECIDE covered Cosmetic IS FALSE
```

The clauses of one function must:

- follow one another under a single `GIVEN`/`GIVETH`, each starting in the same column;
- use the same function name and the same number of inputs.

`name pattern MEANS result` works as well as `DECIDE name pattern IS result`.
A function published with `@export` needs the `GIVEN`, naming and typing each input, even when it has a single clause: see [An @export of clauses with no GIVEN](../errors/README.md#an-export-of-clauses-with-no-given).

**Example file:** [decide-clauses-example.l4](decide-clauses-example.l4)

### What a clause can match

In each input position:

- a value (`0`, `"Saturday"`, `TRUE`, `Water`, `EMPTY`) matches only that value;
- the `GIVEN` name for that position matches anything;
- any other name also matches anything, and stands for that input inside its own clause;
- a constructor with an argument goes in parentheses: `(JUST a)`, `(x FOLLOWED BY rest)`.

```l4
GIVEN weekend IS A BOOLEAN
      day IS A STRING
GIVETH A NUMBER
DECIDE `parking fee` TRUE  day        IS 0
DECIDE `parking fee` FALSE "Saturday" IS 5
DECIDE `parking fee` FALSE day        IS 10
```

`` `parking fee` FALSE "Monday" `` gives `10`: the second clause does not match `"Monday"`, so the third is used.

The clauses mean the same as one `DECIDE` whose body is a [CONSIDER](../control-flow/CONSIDER.md) with one `WHEN` per clause; a clause that matches anything acts like `OTHERWISE`.

### Restrictions

- Clauses make one function only at the top level of a file or of a section, not inside `WHERE` or `LET`.
- A function whose name sits between or after its inputs, such as ``c `costs` n``, cannot be written as clauses. Use `CONSIDER` instead; see [A clause written like a rule with a word between its inputs](../errors/README.md#a-clause-written-like-a-rule-with-a-word-between-its-inputs).
- A bare `_` is a syntax error. To match anything, use the `GIVEN` name, or write `` `_` `` in backquotes.
- A single `DECIDE` line whose inputs are all plain names is an ordinary definition, so its names must match the `GIVEN`.

### Warnings and errors

- When the clauses leave a case out, `l4 check` warns and lists the clauses still needed: [Multi-clause DECIDE does not cover all cases](../errors/README.md#multi-clause-decide-does-not-cover-all-cases).
- A clause below one that matches every input is never reached, and `l4 check` warns: [Clause that is never used](../errors/README.md#clause-that-is-never-used).
- When no clause matches at run time, evaluation stops with "No clause of `name` matches these inputs": [Non-exhaustive patterns at runtime](../errors/README.md#non-exhaustive-patterns-at-runtime).

What the missing-case check can and cannot see is explained in [Exhaustiveness](../../concepts/type-system/exhaustiveness.md).

## Related pages

- [GIVEN and GIVETH](GIVEN.md): inputs and result type
- [MEANS](MEANS.md): definitions without `DECIDE`
- [LET and WHERE](LET.md): local definitions
- [CONSIDER](../control-flow/CONSIDER.md): pattern matching inside an expression
- [Make rules read like law](../../tutorials/natural-language-functions/optimising-natural-language-generation.md): functions whose names read like natural language
