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

### The decision graph and the query plan

A rule written as clauses that answers yes or no has a decision graph in the editor, as the `CONSIDER` it stands for has.
It also has a query plan from the service that publishes rules: the `/query-plan` route of `jl4-service`, which a wizard asks for the next question to put.
L4 reads the clauses as that `CONSIDER`.
These two rules are the same rule, and are drawn and planned alike:

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN c IS A Colour
GIVETH A BOOLEAN
DECIDE warm Red   IS TRUE
DECIDE warm Green IS FALSE
DECIDE warm Blue  IS FALSE

GIVEN c IS A Colour
GIVETH A BOOLEAN
DECIDE `warm, by hand` c IS
  CONSIDER c
    WHEN Red   THEN TRUE
    WHEN Green THEN FALSE
    WHEN Blue  THEN FALSE
```

Clauses may share an earlier input and differ in a later one, as the rows of a decision table do:

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN c IS A Colour
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `colour rule` Red   TRUE  IS TRUE
DECIDE `colour rule` Red   FALSE IS FALSE
DECIDE `colour rule` Green b     IS b
DECIDE `colour rule` Blue  b     IS NOT b
```

L4 reads each clause knowing what the clauses above it have already settled, so this is read as the nested `CONSIDER` a drafter would write: one question about the colour, and for `Red` one question about `b`.
A clause whose pattern is a new name, such as `DECIDE warm other IS FALSE`, matches anything that reaches it, and is read as `OTHERWISE`.

The decision graph draws a `CONSIDER` as one box, labelled with the `CONSIDER`, and a rule written as clauses is that same box, with the same label.
A `CONSIDER` that means the same but is written another way, such as `WHEN Red THEN b` in place of the nested `CONSIDER` on `b`, is a box with another label.

**Clauses too long to read.**
Clauses that come to more than 20,000 parts when written out as their CONSIDER are not drawn or planned.
This is reached most easily by a table over optional inputs whose clauses take values apart with JUST: each such clause is written out again under every answer to the inputs after it.
A table of eleven clauses over five MAYBE BOOLEAN inputs can reach it.
The decision graph and the query plan refuse them with this message (the service answers with a 400 error):

```
These clauses are too long to draw: written out as the CONSIDER they stand for, they come to more than 20000 parts. Split the rule into smaller groups of clauses, or into named sub-rules.
```

**At most 300 boxes.**
A rule written as clauses is also refused when its picture would come to more than 300 boxes.
Clauses that read as one `CONSIDER` are one box, however many rows they have, so this is reached by clauses that read as something else.
One way is a first clause that gives an input a new name, such as `DECIDE rule m a b IS …` for a rule whose `GIVEN` calls its first input `n`: L4 reads that as a test of the input, with the clauses after it as the other answer, and draws its result, which can be long.
The query plan reaches the limit sooner than the picture does, because the service simplifies the picture first, and an `OR` of `AND`s, rewritten as an `AND` of `OR`s, can grow far past its own size.
An `OR` of six `AND`s of two inputs each, as the result of such a first clause, is drawn in VS Code, and its query plan is refused with this message:

```
These clauses would draw a ladder of more than 300 boxes, too many to show. Split the rule into smaller groups of clauses, or into named sub-rules.
```

In VS Code, a rule that is refused keeps the lens above it, which then reads `No decision graph: these clauses are too long to draw`, or `No decision graph: these clauses would draw more than 300 boxes` when the picture as drawn comes to that many.
Clicking it shows the whole message.
Only the picture and the plan are refused: `#EVAL`, `l4 run` and the service's evaluation answer the rule as usual.

To bring such a rule back into the picture, give part of it a name of its own: move a group of clauses into a separate rule, named for what it decides, and use that rule in the clauses that remain.
A rule that uses another shows the use as one box, not the clauses behind it.
Or split one long list into smaller lists, each deciding one part of the question, and combine their answers with `AND` or `OR`.

The limits apply only to a rule written as clauses that L4 reads through.
A rule whose first clause names each input as its `GIVEN` does, or is `` `_` ``, is not read through, because the clauses after that one are never reached, so it is drawn and planned as a rule written without clauses is, however long it is.
A first clause that gives an input a new name is read through, and both limits apply to it.
`EXACTLY` of the input's own name, as in `DECIDE f (EXACTLY n) IS 1`, is not the bare name: drawn or planned, such a clause is read as a test, so the 20,000-part limit applies to it.
A `CONSIDER` you write yourself is drawn as you wrote it.
A rule that answers something other than yes or no, such as a number, is not drawn at all, however it is written, and L4 says that first.

## Related pages

- [GIVEN and GIVETH](GIVEN.md): inputs and result type
- [MEANS](MEANS.md): definitions without `DECIDE`
- [LET and WHERE](LET.md): local definitions
- [CONSIDER](../control-flow/CONSIDER.md): pattern matching inside an expression
- [Make rules read like law](../../tutorials/natural-language-functions/optimising-natural-language-generation.md): functions whose names read like natural language
