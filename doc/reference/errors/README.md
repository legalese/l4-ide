# Troubleshooting L4 Errors

When something goes wrong in L4, the compiler tries to tell you what happened. This guide helps you understand those error messages and fix the underlying problems quickly.

If you already know what error you are looking at, use the table of contents below to jump to it. Otherwise, search this page for a keyword from your error message.

---

## Contents

- [Parse Errors](#parse-errors)
  - [Unexpected THEN](#unexpected-then)
  - [Missing ELSE branch](#missing-else-branch)
  - [Pipes in sum types](#pipes-in-sum-types)
  - [Bare positional payload in sum types](#bare-positional-payload-in-sum-types)
  - [Boolean literal case](#boolean-literal-case)
  - [Parentheses required for field access](#parentheses-required-for-field-access)
  - [A clause written like a rule with a word between its inputs](#a-clause-written-like-a-rule-with-a-word-between-its-inputs)
- [Indentation Errors](#indentation-errors)
  - [Body less indented than definition](#body-less-indented-than-definition)
  - [Multi-line function arguments](#multi-line-function-arguments)
- [Type Errors](#type-errors)
  - [Branch type mismatch](#branch-type-mismatch)
  - [Undefined field access](#undefined-field-access)
  - [Function arity mismatch](#function-arity-mismatch)
  - [Clauses with more or fewer patterns than the GIVEN names](#clauses-with-more-or-fewer-patterns-than-the-given-names)
  - [APPEND vs append](#append-vs-append)
  - [An @export of clauses with no GIVEN](#an-export-of-clauses-with-no-given)
- [Compiler Warnings](#compiler-warnings)
  - [Non-exhaustive pattern match](#non-exhaustive-pattern-match)
  - [Multi-clause DECIDE does not cover all cases](#multi-clause-decide-does-not-cover-all-cases)
  - [Redundant pattern match branch](#redundant-pattern-match-branch)
  - [Clause that is never used](#clause-that-is-never-used)
  - [Annotation above a later clause](#annotation-above-a-later-clause)
  - [A definition after clauses that is not another clause](#a-definition-after-clauses-that-is-not-another-clause)
- [Runtime Errors](#runtime-errors)
  - [Circular definition](#circular-definition)
  - [Non-exhaustive patterns at runtime](#non-exhaustive-patterns-at-runtime)
  - [DEONTIC rule does not execute](#deontic-rule-does-not-execute)
- [Common Gotchas](#common-gotchas)
  - [Equality uses single equals](#equality-uses-single-equals)
  - [Missing IMPORT prelude](#missing-import-prelude)
  - [Module not found](#module-not-found)
  - [WHERE scope issues](#where-scope-issues)
  - [Missing type annotations](#missing-type-annotations)
- [Coming from Other Languages?](#coming-from-other-languages)
- [See Also](#see-also)

---

## Parse Errors

Parse errors happen before your code runs. They mean L4 could not understand the structure of what you wrote.

### Unexpected THEN

**Error message:** `Parse error: unexpected THEN at line N`

**What you wrote:**

```l4
result MEANS
    IF a THEN 1
    ELSE IF b THEN 2
         ELSE IF c THEN 3
              ELSE 4
```

**What went wrong:** Nested IF/THEN/ELSE chains are fragile because each level adds more indentation, and L4's layout rules can get confused about which ELSE belongs to which IF.

**How to fix it:** Use `BRANCH` instead. It handles multiple conditions cleanly without nesting:

```l4
result MEANS
    BRANCH
        IF a THEN 1
        IF b THEN 2
        IF c THEN 3
        OTHERWISE 4
```

BRANCH evaluates conditions top-to-bottom and returns the result for the first one that is TRUE. The OTHERWISE clause catches everything else. See [Control Flow](../control-flow/README.md) for more on BRANCH.

---

### Missing ELSE branch

**Error message:** `Parse error: expected ELSE after THEN`

**What you wrote:**

```l4
result MEANS IF condition THEN value
```

**What went wrong:** In L4, IF/THEN/ELSE is an expression, not a statement. Every IF must produce a value regardless of whether the condition is TRUE or FALSE, so an ELSE branch is always required.

**How to fix it:** Provide an ELSE branch:

```l4
result MEANS IF condition THEN value ELSE default
```

If you genuinely only care about one case, consider using a guard or a BRANCH with an OTHERWISE in the surrounding context.

---

### Pipes in sum types

**Error message:** `Parse error` when defining a sum type with `|`

**What you wrote:**

```l4
DECLARE Color IS ONE OF
    Red | Green | Blue
```

**What went wrong:** L4 does not use the pipe character `|` to separate sum type constructors. If you are used to Haskell or similar languages, this is an easy mistake to make.

**How to fix it:** Use commas or newlines instead:

```l4
DECLARE Color IS ONE OF Red, Green, Blue
```

Or on separate lines:

```l4
DECLARE Color IS ONE OF
    Red
    Green
    Blue
```

See [Types](../types/README.md) for more on declaring sum types.

---

### Bare positional payload in sum types

**Error message:** `expecting HAS` when putting a bare type after a constructor

**What you wrote:**

```l4
DECLARE Shape IS ONE OF
    Circle NUMBER
```

**What went wrong:** Sum type constructors that carry data must use the `HAS` keyword with named fields. L4 does not support anonymous positional payloads like Haskell or Rust.

**How to fix it:** Name the field explicitly:

```l4
DECLARE Shape IS ONE OF
    Circle HAS radius IS A NUMBER
```

---

### Boolean literal case

**Error message:** `Parse error: unknown identifier 'True'`

**What you wrote:**

```l4
result MEANS True
```

**What went wrong:** Boolean literals in L4 must be fully uppercase. `True`, `true`, `False`, and `false` are not recognized.

**How to fix it:** Use `TRUE` and `FALSE`:

```l4
result MEANS TRUE
```

---

### Parentheses required for field access

**Error message:** Parse error when using field access as a function argument

**What you wrote:**

```l4
all (GIVEN g YIELD g's age >= 18) charity's governors
```

**What went wrong:** When a field access expression (using `'s`) appears as an argument to a function, L4's parser cannot tell where the expression boundaries are. The field access needs to be explicitly grouped.

**How to fix it:** Wrap the field access in parentheses:

```l4
all (GIVEN g YIELD g's age >= 18) (charity's governors)
```

---

### A clause written like a rule with a word between its inputs

**Error message:**

```
This clause is written the way a rule with a word between its inputs is written, like this one:

  c `costs` n

A rule written that way is one definition, so it cannot be split into clauses.
Write it once and tell the cases apart inside it with CONSIDER, or write the clauses with a name of their own first, one pattern for each input, as in DECIDE price Red 0 IS ...
```

**What you wrote:**

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN c IS A Colour
      n IS A NUMBER
GIVETH A NUMBER
c `costs` n MEANS n
Red `costs` 0 MEANS 1
```

**What went wrong:** A rule can be written with a word between its inputs, so that a call reads like a sentence: ``c `costs` n`` defines a rule, and ``Red `costs` 0`` calls it. This is called a **"mixfix"** rule. It is one definition, and L4 finds it by its word wherever it is called.
It has no clauses.
The last line looks like one more case of it, "when the colour is Red and the number is 0, the answer is 1", but it is not one.
A list of clauses is a different way of writing a rule: the rule's name comes first, then one pattern for each input (`DECIDE price Red 0 IS 1`).
A line with the word in the middle is the first kind, so L4 refuses it, once, at its first word, rather than read it as a clause of a rule named `Red`.

The same error appears when every line of the rule is written that way, with no one-definition form to compare with:

```l4
c `costs` 0 MEANS 0
c `costs` n MEANS n
```

There L4 recognises the form from the first word of the line being one of the `GIVEN` inputs (`c`), followed by a word that is none (`costs`).
That is how a rule with a word between its inputs begins. A clause begins with the rule's name instead, and a rule cannot be named like one of its own inputs.
This message begins "This clause begins with c, an input of the GIVEN, and then the word `costs`."

A line in the same form with a bare name for every input, and no literal, is not read as a clause, because nothing in it tells cases apart; it is read as a definition:

```l4
c `costs` n MEANS n
Red `costs` n MEANS 1
```

and is refused too, for the same reason. Its message begins "This definition is written the way the rule", shows the rule, and says which name in the line (`Red`) the `GIVEN` does not name.

**How to fix it:** Two ways, whichever reads better.

Write the rule once, and tell its cases apart inside it with `CONSIDER`:

```l4
GIVEN c IS A Colour
      n IS A NUMBER
GIVETH A NUMBER
c `costs` n MEANS
  CONSIDER c
  WHEN Red THEN IF n EQUALS 0 THEN 1 ELSE n
  OTHERWISE n

#EVAL Red `costs` 0
```

or write the cases as clauses with a name of their own in front, one pattern for each input, in the order of the `GIVEN`:

```l4
GIVEN c IS A Colour
      n IS A NUMBER
GIVETH A NUMBER
DECIDE price Red 0 IS 1
DECIDE price c n IS n

#EVAL price Red 0
```

The second way is called as `price Red 0`, not as ``Red `costs` 0``. Do not reuse the word of a rule that is written with a word between its inputs as the name of the clauses: in a file with both ``c `costs` n`` and a rule of clauses named `costs`, the call `costs Red 0` finds the one-definition rule.

**What this does not catch:** The check has to be able to see the rule. It sees a rule written with a word between its inputs when the file, or a file it imports, defines it in one piece; and it sees a line that begins with one of the `GIVEN` inputs followed by a word that is none.
Two shapes are not recognised.
A rule whose every line begins with a constructor, ``Red `costs` 0`` and ``Green `costs` n`` with no ``c `costs` n`` anywhere, is accepted as clauses of rules named `Red` and `Green`, and a call written ``Red `costs` 0`` does not find them.
A rule whose words come first, `` `tax on` x `item costing` y ``, written as clauses is still refused as having more patterns than the `GIVEN` names inputs ([Clauses with more or fewer patterns than the GIVEN names](#clauses-with-more-or-fewer-patterns-than-the-given-names)), in several messages.

**What is not refused:** a line whose `GIVEN` names an input where the rule has its word is an ordinary rule, however much it looks like the mixfix one.
Beside ``a `plus` b``, a rule `total plus y` with the `GIVEN` `plus` and `y` is a rule called `total` that takes two inputs, and so is ``decision `is eligible` `` when `` `is eligible` `` is one of its `GIVEN` inputs; the same goes for the clauses `DECIDE fee costs 0 IS 0` and `DECIDE fee costs n IS n` when the `GIVEN` names `costs`.
The definition lines are left alone, and the rules they define are called as usual, `total 3 4`.
A use of the word inside another rule is still read as a use of the mixfix rule: with ``a `plus` b`` in the file, the body `total plus y` of a rule whose inputs are `plus` and `y` is read as ``total `plus` y``, and fails to check ("The first argument of function `plus` is expected to be of type NUMBER but is here of type FUNCTION FROM NUMBER AND NUMBER TO NUMBER").
Give that input another name, and the body means what it says.

---

## Indentation Errors

L4 is layout-sensitive, like Python. Indentation determines how code is grouped, replacing the braces and semicolons used in languages like JavaScript or Java. Getting indentation wrong is one of the most common sources of errors.

**General rules:**

- Use spaces, not tabs.
- Continuation lines must be indented more deeply than the line that introduced them.
- WHERE bindings should align vertically.
- The body of MEANS or DECIDE must be indented relative to the definition line.

### Body less indented than definition

**Error message:** Parse error on the line after MEANS

**What you wrote:**

```l4
        result MEANS
    x + y
```

**What went wrong:** The body (`x + y`) is less indented than the keyword `MEANS` that introduces it. L4 expects the body to be indented further in.

**How to fix it:** Make sure the body is indented relative to the definition:

```l4
result MEANS
    x + y
```

**Tip:** If your definition is already deeply indented, consider refactoring to reduce nesting.

---

### Multi-line function arguments

**Error message:** Parse error on continuation lines of a function call

**What you wrote:**

```l4
r MEANS triple
    100
    200
```

**What went wrong:** When function arguments appear on continuation lines without the `OF` keyword, the parser cannot tell whether these lines are arguments to the function or new top-level expressions.

**How to fix it:** Use `OF` with commas for multi-argument calls:

```l4
r MEANS triple OF 100, 200, 300
```

**Tip:** The VS Code extension for L4 highlights layout boundaries, which helps catch these issues as you type.

---

## Type Errors

Type errors mean L4 understood the structure of your code but found a logical inconsistency in how values are used.

### Branch type mismatch

**Error message:** `Type error: branch returns T1 but expected T2`

**What you wrote:**

```l4
result MEANS
    BRANCH
        IF x < 0 THEN "negative"
        IF x = 0 THEN 0
        OTHERWISE "positive"
```

**What went wrong:** All branches of a BRANCH (or IF/THEN/ELSE, or CONSIDER) must return the same type. Here, the first and third branches return a STRING, but the second returns a NUMBER.

**How to fix it:** Make all branches return the same type:

```l4
result MEANS
    BRANCH
        IF x < 0 THEN "negative"
        IF x = 0 THEN "zero"
        OTHERWISE "positive"
```

---

### Undefined field access

**Error message:** `Error: record type T has no field 'fieldname'`

**What you wrote:** An expression like `person's fullname` where the field `fullname` does not exist on the type.

**What went wrong:** You are accessing a field that is not defined in the type's DECLARE block. This is usually a typo or a misremembering of the field name.

**How to fix it:** Check the DECLARE definition for the type and verify the exact field name. Common mistakes include singular vs. plural (`name` vs. `names`) and different word choices (`fullname` vs. `full name`).

---

### Function arity mismatch

**Error message:** `Error: function expects N arguments, got M`

**What you wrote:** A function call with too many or too few arguments.

**What went wrong:** The function was defined with a certain number of GIVEN parameters, and you provided a different number of arguments.

**How to fix it:** Check the function's definition to see how many arguments it expects, and provide exactly that many. If you intentionally want to supply fewer arguments (partial application), make sure the context supports it.

---

### Clauses with more or fewer patterns than the GIVEN names

**Error message:**

```
Each clause of `g` has 2 patterns, but its GIVEN names 1 input.
A clause needs one pattern for each input the GIVEN names, in the same order.
```

**What you wrote:**

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN c IS A Colour
GIVETH A NUMBER
DECIDE g Red   Red IS 1
DECIDE g Green c   IS 2
```

**What went wrong:** A rule written as a list of clauses takes its inputs from the `GIVEN` above the clauses, in order.
The first pattern in each clause is matched against the first input the `GIVEN` names, the second pattern against the second input, and so on.
Here each clause has two patterns, but the `GIVEN` names only one input, `c`, so L4 cannot tell which input each pattern is about.
The error appears once, at the first clause.
A clause body may still read an input the `GIVEN` names; L4 checks it against the type the `GIVEN` declares, so only a body that uses it as something else draws a second error.
L4 says nothing about missing or unused clauses until the counts agree.

A `GIVEN` that declares only a type, such as `GIVEN a IS A TYPE`, names no inputs, so clauses with patterns under it draw the same error, ending "its GIVEN names no inputs".

**How to fix it:** Name one input in the `GIVEN` for each pattern, in the order the patterns appear:

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN c IS A Colour
      d IS A Colour
GIVETH A NUMBER
DECIDE g Red   Red IS 1
DECIDE g Green d   IS 2
```

or give every clause one pattern for each input the `GIVEN` names.

A list of clauses with no `GIVEN` at all is allowed.
L4 then works out the type of each input from the patterns and the clause bodies, and where it has to name an input, as `l4 render` does, it calls them `input 1`, `input 2`, and so on.
Such clauses cannot be published with `@export`, even a single one; see [An @export of clauses with no GIVEN](#an-export-of-clauses-with-no-given).

---

### APPEND vs append

**Error message:** Unexpected type error involving strings or lists

**What you wrote:**

```l4
append "hello" "world"
```

**What went wrong:** L4's prelude defines two different functions that look similar but operate on different types:

| Function | Case      | Style  | Works on | Example                          |
| -------- | --------- | ------ | -------- | -------------------------------- |
| `APPEND` | uppercase | infix  | STRING   | `"hello" APPEND " world"`        |
| `append` | lowercase | prefix | LIST     | `append (LIST 1, 2) (LIST 3, 4)` |

Using the wrong one gives a type error because strings are not lists and vice versa.

**How to fix it:** Use uppercase `APPEND` (infix) for strings and lowercase `append` (prefix) for lists:

```l4
"hello" APPEND " world"
append (LIST 1, 2) (LIST 3, 4)
```

For string concatenation, you can also use `CONCAT`:

```l4
CONCAT "hello", " world"
```

---

### An @export of clauses with no GIVEN

**Error message:**

```
`size` is published with @export, but its inputs have no names: add a GIVEN that names and types each one.
```

**What you wrote:**

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

@export
DECIDE size Red   n IS n
DECIDE size Green n IS n + 1
DECIDE size Blue  n IS 0
```

**What went wrong:** `@export` publishes a rule as a web endpoint, and a request to it supplies each input by name, as a value of that input's type.
A rule written as clauses with patterns and no `GIVEN`, whether one clause or several, has neither.
L4 names its inputs itself, `input 1`, `input 2` and so on, and works out their types from the patterns and the clause bodies, so a request could not say which input a value is for, and there is no declared type to check the value against.
So an `@export` of such a rule is an error, reported at the `@export` line, because that is where the missing `GIVEN` goes.
The error stops the whole file from checking: `l4 run`, the REPL and `l4 batch` refuse the file, the `#EVAL`s of its other rules included, and jl4-service will not deploy it, until you add the `GIVEN` or remove the `@export`.
`@export default` is refused the same way.
Without `@export`, clauses with no `GIVEN` are fine.

**How to fix it:** Add a `GIVEN` below `@export` that names and types each input, in the order the patterns appear, and say what the rule gives back with `GIVETH`:

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

@export
GIVEN c IS A Colour
      n IS A NUMBER
GIVETH A NUMBER
DECIDE size Red   n IS n
DECIDE size Green n IS n + 1
DECIDE size Blue  n IS 0
```

The rule is then published with the inputs `c` and `n`.
Or remove the `@export`, if the rule is not meant to be published.

---

## Compiler Warnings

Warnings do not stop compilation, but they flag code that is likely to fail at runtime or that contains dead branches.

### Non-exhaustive pattern match

**Warning message:** pattern matches are missing (the warning lists the uncovered branches)

**What you wrote:**

```l4
CONSIDER status
WHEN Active THEN "running"
WHEN Closed THEN "stopped"
```

**What went wrong:** The CONSIDER expression does not cover all possible constructors of the scrutinee's type. If `status` could be `Suspended` (or any other constructor you did not list), there is no branch to handle it. This is a **compile-time warning** (not an error): the program still compiles and runs, but evaluating the match on an uncovered value raises a runtime error (see [Non-exhaustive patterns at runtime](#non-exhaustive-patterns-at-runtime)).

**How to fix it:** Either cover all constructors explicitly or add an OTHERWISE branch:

```l4
CONSIDER status
WHEN Active THEN "running"
WHEN Closed THEN "stopped"
OTHERWISE "unknown"
```

**Note:** A NUMBER, a STRING or a DATE has no end of values, so a CONSIDER over one is complete only with an OTHERWISE, and the warning suggests OTHERWISE; a WHEN with a number or a piece of text, and `EXACTLY` of one or of a value of an enumeration, is read as that value, exactly as in a [rule written as clauses](#multi-clause-decide-does-not-cover-all-cases), and a number repeated in another spelling is a redundant branch. BOOLEAN is analysed normally, and the analysis reaches CONSIDER expressions inside WHERE- and LET-bound local definitions; the builtin container types MAYBE, EITHER, and LIST are not yet analysed. Warnings never block evaluation — a file with warnings still runs its `#EVAL` directives.

---

### Multi-clause DECIDE does not cover all cases

**Warning message:**

```
This multi-clause definition does not cover all cases. The following clauses are still needed:

  DECIDE `price` Blue IS
```

**What you wrote:**

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN c IS A Colour
GIVETH A NUMBER
DECIDE price Red   IS 1
DECIDE price Green IS 2
```

**What went wrong:** The clauses of `price` match `Red` and `Green` but no clause matches `Blue`, so `price Blue` would stop evaluation with an error. This is a **compile-time warning** (not an error); an editor underlines it from the first clause's name to the last's.

**How to fix it:** Add each listed clause and write its result after `IS`:

```l4
DECIDE price Blue IS 3
```

Or end the group with a clause that matches anything, written with the `GIVEN` name:

```l4
DECIDE price c IS 0
```

When the rule has only one clause, the first line reads "This clause does not cover all cases." instead.

**Note:** Rules whose clauses match enumeration values or `TRUE`/`FALSE` are checked, and so are rules whose clauses match particular numbers or texts.
A number or a piece of text is one value of its input, and there is no end of the others, so such a rule is complete only with a clause written with the input's name, and the warning suggests that clause: ``DECIDE `describe` n IS`` for `DECIDE describe 0 IS "zero"` and `DECIDE describe 1 IS "one"`.
The other inputs of the same rule are still analysed, the gaps under each number first and then the clause for every other number.
Rules that match lists or `MAYBE` values, or an enumeration declared in another file, get no warning where the check would have to tell such values apart, not even for a number nested inside one; where the other inputs settle the question first it still warns, and when every clause of such a rule has a number or a piece of text in it, the warning suggests the one clause with every input's name and nothing finer.
`EXACTLY` of a number, a piece of text or a value of an enumeration is read as that value, and `EXACTLY` of the input's own name matches every input; any other `EXACTLY` counts for nothing on a number, text or date input, and in such a field of a record, stops the check on an enumeration input, and stops it on any input when its expression mentions the input itself.
An input or a field declared under another name for a number (`DECLARE Age IS A NUMBER`) is a number to the check.
When a clause counts for nothing that way, the warning lists only what the clauses without a number or a piece of text leave open, since a keyed gap could be one that clause covers.
A suggested number prints as the clauses spelled it, and a suggested piece of text as L4 writes it, with `"` and `\` escaped.
A rule whose clauses match enumeration values only gets no warning when it would need more than 64 clauses listed, or more than 10000 steps to find them; when its clauses match numbers or texts, the warning lists instead only the clauses that the clauses without a number or a piece of text leave open, which, when every clause names a number or a text, is the clause with every input's name alone.
[Multi-clause DECIDE](../functions/multi-clause-DECIDE.md#limits) gives an example of each.
A rule of one clause that is not checked keeps whatever warning a CONSIDER would give (see [Non-exhaustive pattern match](#non-exhaustive-pattern-match)), listing WHEN branches, now at the clause; a CONSIDER reads numbers, texts and `EXACTLY` the same way, so a missing case over them is reported in either spelling; the two can differ for a repeated value, and where a branch or clause names a constructor of a `MAYBE`, an `EITHER`, a list or a type from another file (see [CONSIDER](../control-flow/CONSIDER.md)).
See [Multi-clause DECIDE](../functions/multi-clause-DECIDE.md#missing-cases).

---

### Redundant pattern match branch

**Warning message:** pattern match branches are redundant (the warning lists the unreachable branches)

**What went wrong:** A WHEN branch can never be reached because earlier branches (or an earlier OTHERWISE) already cover every value it could match.

**How to fix it:** Delete the unreachable branch, or reorder branches if a more specific pattern was accidentally placed after a more general one.

---

### Clause that is never used

**Warning message:**

```
This clause of `describe` is never used, and neither is the clause after it.
The clause above it matches every input, so `describe` never gets this far.
Move these clauses above that one, or remove them.
```

**What you wrote:**

```l4
DECLARE Status IS ONE OF Active, Suspended, Closed

GIVEN status IS A Status
GIVETH A STRING
DECIDE describe status IS "some status"
DECIDE describe Active IS "running"
DECIDE describe Closed IS "stopped"
```

**What went wrong:** A rule written as a list of clauses tries them from the top, and the first clause that matches is the one that applies. The first clause here matches every status, because its pattern is `status`, the name of the input itself. So `describe Active` is `"some status"`, and the two clauses below it are never reached. The warning appears once, at the first clause that cannot be reached, and says how many more follow it.

A clause that is never used is still checked against the rule's `GIVEN` and `GIVETH`, so a mistake inside it, such as a misspelt name or an answer of the wrong type, is still reported.

Only the clauses after one that matches every input are warned about: a clause whose every pattern is its input's own name, `_`, or a new name.
A pattern that is not a value of its input's type is a new name, such as `other`, or `Gren` where `Green` was meant, and a new name matches anything.
The warning then names it:

```
This clause of `colour` is never used, because the clause above it with the new name `Gren` matches every input.
`Gren` is not a value of its input's type, so it is a new name, and a new name matches anything.
If you meant a value, correct the spelling; if you meant to match anything, move that clause below the others.
```

This holds in rules that match numbers or text too.
It is not given when a pattern of the rule does not fit its input's type, since the rule is then an error.
A new name inside a larger pattern draws no warning: after `(JUST Gren)`, a clause for `(JUST Blue)` is never used, and nothing says so.
There is no warning for a clause that repeats one above it.

**How to fix it:** Put the clauses for particular cases first and the clause that matches anything last, or remove the clause that can never be reached.

---

### Annotation above a later clause

**Warning message:**

```
This @export is above the second clause of `colour code`, where it is not used.
A rule written as clauses takes its @export from above its GIVEN only.
Move it there, or remove it.
```

**What you wrote:**

```l4
DECLARE Colour IS ONE OF Red, Green

GIVEN c IS A Colour
GIVETH A NUMBER
DECIDE `colour code` Red IS 1
@export the green code
DECIDE `colour code` Green IS 2
```

**What went wrong:** A rule written as clauses is one rule, and its annotations are written once, where a rule written as one definition has them.
An `@export` between two clauses does not publish the rule, a `@desc` there does not describe it, and an `@nlg` there is not used when the rule is put into words.
The warning appears once at each such annotation.

Definitions that share a name but are told apart by their types, such as `DECIDE show n IS n + 1` followed by `DECIDE show b IS b AND TRUE`, are separate definitions rather than one rule, and each keeps the annotations above it, so they draw no warning.

**How to fix it:** Move the annotation to where the rule's own annotations go, or remove it.
An `@desc` or `@export` goes above the rule's `GIVEN`, or above its first clause if it has no `GIVEN`.
An `@nlg` goes on the line above the first clause.

---

### A definition after clauses that is not another clause

**Warning message:**

```
This definition of `f` is not another clause of the clauses above it.
Each of those has 1 pattern, and this one has 2 inputs, `Red` and `Blue`, so it is a separate rule, and what follows its name is the names it gives its inputs, not patterns.
If it is meant as another clause, give it as many patterns as the others have; if it is a rule of its own, give it a GIVEN of its own.
```

**What you wrote:**

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN c IS A Colour
GIVETH A NUMBER
DECIDE f Red IS 1
DECIDE f c IS 2
DECIDE f Red Blue IS 3
```

**What went wrong:** Clauses that follow one another are gathered into one rule when they have the same name and the same number of patterns after it.
The first two clauses have one pattern each, so they are one rule.
The third has two, so it is not a clause of that rule: it is a rule of its own that takes two inputs and calls them `Red` and `Blue`, whatever else those words mean elsewhere.
It checks, and `f Green Red` gives 3, where a reader of the three lines might have expected L4 to be looking for the colour Red and the colour Blue.
The warning appears once, at the name in the definition, and only for a definition that has no `GIVEN` of its own and follows a rule written as clauses directly.

**How to fix it:** If the line was meant as another clause of the rule above, give it as many patterns as the clauses above have (here, one).
If it is a rule of its own, say so with a `GIVEN` of its own, which also gives its inputs their types:

```l4
GIVEN c IS A Colour
      d IS A Colour
GIVETH A NUMBER
f c d MEANS 3
```

---

## Runtime Errors

Runtime errors occur when the code is well-formed and well-typed but does something problematic during evaluation.

### Circular definition

**Symptom:** Evaluation hangs or produces a stack overflow

**What you wrote:**

```l4
x MEANS x + 1
```

**What went wrong:** The definition refers to itself without ever reaching a base case. When L4 tries to evaluate `x`, it needs `x + 1`, which needs `x`, which needs `x + 1`, and so on forever.

**How to fix it:** If you intend recursion, make sure there is a base case that stops the cycle:

```l4
factorial MEANS
    IF n <= 1 THEN 1
    ELSE n * (factorial (n - 1))
```

If you did not intend recursion, you probably meant to reference a different variable. Check your names.

---

### Non-exhaustive patterns at runtime

**Error message:**

```
The value
  Withdrawn
reached a CONSIDER that has no branch for it.
Add a WHEN branch for this case, or a catch-all OTHERWISE branch.
The typechecker's exhaustiveness warning lists all missing branches.
```

**What went wrong:** Evaluation reached a CONSIDER whose branches do not cover the actual value of the scrutinee (shown in the message). Either the compile-time warning was ignored, or the value escaped the analysis — in particular matches on NUMBER, STRING, or DATE scrutinees, for which exhaustiveness checking is skipped (see [Non-exhaustive pattern match](#non-exhaustive-pattern-match) under Compiler Warnings). A directive that crashes this way makes `l4 run` exit non-zero.

**How to fix it:** Add branches for the missing cases, or add an OTHERWISE branch as a catch-all. For matches on NUMBER, STRING, or DATE values, always include OTHERWISE.

When the rule was written as a list of clauses rather than with a CONSIDER, the message talks about its clauses instead:

```
No clause of `label` matches these inputs.
The value that the last clause could not match is
  Suspended
Add a clause for this case, or end the clauses with one that matches every input.
```

Here `label` has a clause for `Active` and one for `Closed`, and was asked about `Suspended`. Add a clause for the missing case (the warning described under [Multi-clause DECIDE does not cover all cases](#multi-clause-decide-does-not-cover-all-cases) lists the clauses still needed), or end the list with a clause whose pattern matches anything. A rule with only one clause says "The only clause of `label` does not match these inputs." instead.

---

### DEONTIC rule does not execute

**Symptom:** You defined a DEONTIC rule (MUST, MAY, SHANT) but nothing happens when you evaluate it.

**What went wrong:** DEONTIC rules produce effects (obligations, permissions, prohibitions) rather than plain values. They need to be evaluated using the `#TRACE` directive, which generates a state graph showing the obligations and their consequences.

**How to fix it:** Use `#TRACE` to evaluate your rule:

```l4
#TRACE ruleFunction context
```

See [Regulative Rules](../regulative/README.md) for more on deontic logic in L4.

---

## Common Gotchas

These are not always error messages per se, but they trip up many L4 users.

### Equality uses single equals

**What you wrote:**

```l4
result MEANS x == 5
```

**What went wrong:** L4 uses a single `=` for equality comparison. The double `==` from Python, JavaScript, Java, and many other languages does not exist in L4.

**How to fix it:**

```l4
result MEANS x = 5
```

This is consistent with mathematical notation and feels natural once you are used to it. L4 does not have variable assignment, so there is no ambiguity.

---

### Missing IMPORT prelude

**Error message:** `Error: undefined function 'map'` (or `filter`, `all`, `any`, etc.)

**What went wrong:** Standard library functions like `map`, `filter`, `all`, `any`, and `append` are defined in the prelude. If you are getting "undefined" errors for these common functions, the prelude may not be imported.

**How to fix it:** Add this line at the top of your file:

```l4
IMPORT prelude
```

See [Libraries](../libraries/README.md) for the full list of available libraries.

---

### Module not found

**Error message:** `I could not find a module with this name: modulename`, then `I have tried the following locations:` and the list of places that were tried, which ends with the standard library built into the binary, for example `the stdlib embedded in this binary (20 modules, not among them)`, or `the stdlib embedded in this binary (skipped: JL4_LIBRARY_PATH is set)` when that variable is set. On stderr `l4` also prints one line, `Warning | [Import Resolution] Module not found: modulename`.

**What went wrong:** L4 could not find the module you are trying to import. L4 searches for modules in this order (first match wins):

1. Virtual filesystem (VFS) provided by the IDE or service
2. `JL4_LIBRARY_PATH` environment variable (if set)
3. Project root directory
4. Relative to the importing file
5. Embedded standard libraries compiled into the binary
6. XDG data directory (`~/.local/share/jl4/libraries/`)
7. Bundled with the VSCode extension (`../../libraries/` from executable)

Project-scoped locations (2–4) outrank the embedded stdlib, so intentional overrides work; machine-global locations (6–7) rank below it, so they can only supply modules the embed does not carry. When `JL4_LIBRARY_PATH` is set, the embedded copy (step 5) is skipped entirely — the operator has full control over which libraries are available. See [Library Resolution](../libraries/resolution.md) for the full story, including the shadow warning emitted when several differing copies of a module are visible at once.

**How to fix it:**

- Check the module name for typos.
- For your own modules, place them in the project directory or set `JL4_LIBRARY_PATH`.
- For third-party (non-stdlib) libraries, install them to `~/.local/share/jl4/libraries/`
- If `JL4_LIBRARY_PATH` is set, ensure it contains the standard libraries you need (e.g., `prelude.l4`).

---

### WHERE scope issues

**Error message:** `Error: undefined variable in WHERE clause`

**What went wrong:** A variable you referenced in a WHERE binding does not exist. Note that WHERE bindings can see the outer scope and can reference each other, so the issue is usually a typo or a missing definition rather than a scoping limitation.

**How to fix it:** Double-check that the variable you are referencing is defined either in an enclosing scope or in another binding within the same WHERE block.

---

### Missing type annotations

**Symptom:** Yellow warning in the IDE, or confusing type error messages

**What went wrong:** L4 can infer types without annotations, but omitting them sometimes leads to ambiguous inference or unhelpful error messages when something goes wrong downstream.

**How to fix it:** Add GIVEN and GIVETH (or GIVES) annotations to top-level definitions:

```l4
GIVEN person IS A Person
GIVETH A BOOLEAN
DECIDE `the person is eligible` IF
    person's age >= 18
```

Explicit types serve as documentation, produce better error messages, and prevent inference ambiguity.

---

## Coming from Other Languages?

If you have experience with other programming languages, this translation table will help you avoid the most common syntax mistakes.

| What you might write      | What L4 uses                      | Notes                              |
| ------------------------- | --------------------------------- | ---------------------------------- |
| `==`                      | `=`                               | Single equals for equality         |
| `True` / `true`           | `TRUE`                            | Uppercase boolean literals         |
| `False` / `false`         | `FALSE`                           | Uppercase boolean literals         |
| `null` / `nil` / `None`   | `NOTHING`                         | Used with the MAYBE type           |
| `Nothing` / `Just`        | `NOTHING` / `JUST`                | Uppercase constructors             |
| `%`                       | `MODULO`                          | Keyword, not symbol                |
| `.` (dot access)          | `'s`                              | Genitive/possessive field access   |
| `++` / `+` (strings)      | `CONCAT` or `APPEND`              | String concatenation               |
| `def` / `fn` / `function` | `MEANS` or `DECIDE`               | Definition keywords                |
| `return`                  | (not needed)                      | L4 is expression-based             |
| `;`                       | (not needed)                      | Layout-sensitive, uses indentation |
| `{ }`                     | (not needed)                      | Uses indentation instead of braces |
| `\|` (sum types)          | `,` or newline                    | Sum type constructor separators    |
| `Constructor Type`        | `Constructor HAS field IS A Type` | Named fields, not positional       |

---

## See Also

- **[Syntax Reference](../syntax/README.md)** -- Layout rules, identifiers, annotations, and other structural syntax
- **[Types Reference](../types/README.md)** -- Type system, DECLARE, sum types, and polymorphic types
- **[Control Flow](../control-flow/README.md)** -- IF/THEN/ELSE, BRANCH, CONSIDER
- **[Operators Reference](../operators/README.md)** -- Arithmetic, comparison, logical, and string operators
- **[Functions Reference](../functions/README.md)** -- GIVEN, GIVETH, MEANS, DECIDE, WHERE
- **[Libraries Reference](../libraries/README.md)** -- Prelude and other importable libraries
- **[GLOSSARY](../GLOSSARY.md)** -- Master index of all language features
