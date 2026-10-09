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
  - [Curly quotes and dashes from a word processor](#curly-quotes-and-dashes-from-a-word-processor)
- [Indentation Errors](#indentation-errors)
  - [Body less indented than definition](#body-less-indented-than-definition)
  - [Multi-line function arguments](#multi-line-function-arguments)
  - [GIVEN at column 1 meant for the section](#given-at-column-1-meant-for-the-section)
  - [NOT followed by AND, OR or IMPLIES on one line](#not-followed-by-and-or-or-implies-on-one-line)
- [Type Errors](#type-errors)
  - [Branch type mismatch](#branch-type-mismatch)
  - [Undefined field access](#undefined-field-access)
  - [Wrong number of inputs](#wrong-number-of-inputs)
  - [Clauses with more or fewer patterns than the GIVEN names](#clauses-with-more-or-fewer-patterns-than-the-given-names)
  - [APPEND vs append](#append-vs-append)
  - [An @export input that is a rule, not a value](#an-export-input-that-is-a-rule-not-a-value)
  - [An @export of clauses with no GIVEN](#an-export-of-clauses-with-no-given)
- [Compiler Warnings](#compiler-warnings)
  - [Non-exhaustive pattern match](#non-exhaustive-pattern-match)
  - [Redundant pattern match branch](#redundant-pattern-match-branch)
  - [Clause that is never used](#clause-that-is-never-used)
  - [Annotation above a later clause](#annotation-above-a-later-clause)
  - [ASSUME is being retired](#assume-is-being-retired)
- [Runtime Errors](#runtime-errors)
  - [Circular definition](#circular-definition)
  - [Non-exhaustive patterns at runtime](#non-exhaustive-patterns-at-runtime)
  - [DEONTIC rule does not execute](#deontic-rule-does-not-execute)
  - [Needed the value of an assumed term](#needed-the-value-of-an-assumed-term)
  - [Refusal reported instead of a result](#refusal-reported-instead-of-a-result)
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

### Curly quotes and dashes from a word processor

**Error message:** ``This is ’ (Right Single Quotation Mark, U+2019). It looks like `'`, but L4 only understands the plain one.`` (or the same for another curly quote, dash or ellipsis)

**What you wrote:**

If you drafted your contract in Microsoft Word, Pages or Google Docs and pasted the text into L4, the word processor has quietly swapped some of your punctuation for fancier-looking lookalikes as you typed. A straight apostrophe (`'`) becomes a curly one (`‘` or `’`). A straight quotation mark (`"`) becomes a curly pair (`“` and `”`). Two hyphens (`--`) become a long dash (`—` or `–`). Three dots (`...`) become a single ellipsis character (`…`). None of these look wrong to a human reader — that is the whole point of AutoFormat — but L4 does not recognize them:

```l4
GIVEN p IS A Person
DECIDE `is adult` IF p’s age >= 18
```

That apostrophe looks ordinary, but it is a Right Single Quotation Mark (`’`), not the plain one L4's `'s` (the "read a field off something" operator) expects.

**What went wrong:** L4 tells you exactly which character is the problem, rather than the generic "unexpected token" you would otherwise get:

```
This is ’ (Right Single Quotation Mark, U+2019). It looks like `'`, but L4
only understands the plain one.

Word processors such as Word, Pages and Google Docs swap plain punctuation
for curly lookalikes as you type, so this usually means the text was pasted
in from one.

Replace it with `'`.
```

The message shows you the actual character on your screen, not just its name — so if your editor's font makes it hard to tell `'` and `’` apart, the message itself doesn't ask you to. It also names the Unicode code point and the plain character the glyph is standing in for. It never shows you the usual "expecting one of: ..." list, because that list is for someone who already knows the grammar — here the fix is simpler than that.

**How to fix it:** In the editor, click the lightbulb (or run the "Quick Fix" command) on the flagged character and choose the suggested replacement. For a whole file pasted in from a word processor, use "Straighten all smart punctuation in this file" instead — it walks the document fixing every occurrence in one go and tells you how many it changed. (If straightening would still leave the file with an error — most often an opening curly quote whose closer is on a different line than L4 looked for it — this whole-file action does not offer itself at all, so it never reports a count that implies a finished repair it did not make; fix the flagged character it does show you and try again.)

**The dash is genuinely ambiguous, and you may need to pick.** The message itself says which spelling it thinks you meant. Word turns both a minus sign surrounded by spaces and a double-hyphen comment marker into the same long dash, so L4 cannot always tell which one you meant. The quick fix on a single dash offers two choices — "Replace with `-`" (arithmetic) and "Replace with `--`" (start a comment) — and **the one that matches this dash's own position in the file is listed first and is the one your editor's default Quick Fix applies.** That is the same position rule the whole-file straighten uses: a dash that starts its line, or that has two or more spaces before it, is treated as the start of a comment and offered `--` first; anywhere else `-` is offered first. The other spelling is always there as the second choice, for the cases the heuristic cannot see (for instance a subtraction that happens to start a continuation line).

**What is deliberately left alone:** curly quotes that already sit inside a string literal (quoting a clause of a statute, say) or inside a backtick-quoted name are not flagged at all, and the whole-file straighten does not touch them either. Those are legitimate typographical quotation marks in the middle of quoted prose — L4's own example library uses them that way on over 350 lines — and L4 already lexes them without complaint. The diagnostic above fires only where the curly character is doing a job in the code itself: opening a string, standing in for `'s`, or replacing `...`. The one further exception is a name that fails to resolve — if straightening the curly characters out of it would make it match something already in scope, L4 offers that as a suggested fix too.

**A related, gentler warning: an invisible non-breaking space.** A word processor (or a browser you copied text from) sometimes inserts a _non-breaking space_ — U+00A0 — instead of an ordinary one, most often around a number or a unit, so a line does not wrap in the wrong place. It looks completely ordinary and L4 does not refuse it: L4 treats it as whitespace, your code keeps parsing, and indentation-sensitive layout still works. That is exactly why it is worth a warning rather than nothing at all — an invisible character that happens to work today is still a trap for a future search-and-replace or diff. You will see it as a yellow squiggle, not a red one:

```
non-breaking space (U+00A0) used where a normal space was expected — this
usually comes from pasted text; replace it with an ordinary space.
```

**How to fix it:** click the lightbulb on the flagged space and choose "Replace with an ordinary space" — or run "Straighten all smart punctuation in this file", which replaces every non-breaking space in the document as well as any curly quotes, dashes and ellipses it finds.

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

### GIVEN at column 1 meant for the section

**Error message:**

```
This GIVEN starts at column 1, so it is the signature of the declaration
below it -- and that declaration never uses

  `the rate`

If `the rate` was meant as an input for the whole of

  § S

indent the GIVEN so that it starts past the § of the heading:

  § <heading>
      GIVEN `the rate` IS A <type>
```

It arrives alongside a pair of "The names in a type signature must match those in the definition" errors, which have the same cause.

**What you wrote:**

```l4
§ S

GIVEN `the rate` IS A NUMBER
DECLARE Applicant
    HAS name IS A STRING
```

**What went wrong:** A `GIVEN` belongs to the section only when it starts at a column past the heading's `§`. At column 1 it lists the facts the declaration immediately below it is told about the case (its **"inputs"**) — so L4 tried to give `Applicant` an input called `the rate`, which `Applicant` never mentions. A paste, or a re-indent that straightened the file's left margin, is the usual way to arrive here.

**How to fix it:** Indent the `GIVEN` past the `§`, on the line after the heading:

```l4
§ S
    GIVEN `the rate` IS A NUMBER

DECLARE Applicant
    HAS name IS A STRING
```

**Note:** the check fires for a `DECLARE` or an `ASSUME` below the `GIVEN`, not for a `DECIDE`. A decision that ignores one of its own inputs is an ordinary thing to write, and is indistinguishable from a section `GIVEN` that has been pushed back to column 1. So if a rule that should read a section-wide name is asking whoever calls it for an input instead, check the column of its `GIVEN` yourself. See [The section `GIVEN`](../syntax/section-given.md).

---

### NOT followed by AND, OR or IMPLIES on one line

**Error message:**

```
On one line, NOT reaches to the end of the line, so this reads as

  NOT (`has a permit` AND `paid the fee`)

If that is the meaning, write those brackets in. If only

  `has a permit`

is negated, put the brackets around the NOT and that alone:

  (NOT `has a permit`) AND `paid the fee`

or move the AND to a line of its own, starting in the same
column as the NOT or further left.
```

**What you wrote:**

```l4
GIVEN `has a permit` IS A BOOLEAN
      `paid the fee` IS A BOOLEAN
DECIDE `must apply` IF NOT `has a permit` AND `paid the fee`
```

**What went wrong:** `NOT` has no place in the ranking of the other operators. It reaches forward and takes everything after it on its line, so the rule above would mean "it is not the case that (they have a permit and paid the fee)" — while most people read it as "they have no permit, and they paid the fee". The two disagree whenever the person has no permit. Rather than return the wrong answer silently, L4 stops and asks which you meant. Brackets around the first thing alone, `NOT (`has a permit`) AND …`, do not change this: that bracket closes around `has a permit`, not around the `NOT`, and the spelling is refused too.

**How to fix it:** say which reading you meant.

```l4
-- the whole of "has a permit and paid the fee" is negated
DECIDE `must apply` IF NOT (`has a permit` AND `paid the fee`)

-- only "has a permit" is negated
DECIDE `must apply` IF (NOT `has a permit`) AND `paid the fee`
```

Or move the `AND` to its own line. Over several lines nothing is refused, and the columns decide: an `AND` that starts in the same column as the `NOT`, or further left, stops the `NOT`; one that starts further right is reached over. `x AND NOT y` on one line is always fine, because the `NOT` is last and there is nothing after it to reach over. Comparisons are not refused either: `NOT n EQUALS 0` has only one sensible reading. See [How Far Does NOT Reach?](../operators/NOT.md#how-far-does-not-reach).

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

### Wrong number of inputs

**Error message:** `The function … expects 2 inputs, but here it is given 1 input.`

**What you wrote:** A rule used with too many or too few inputs.

**What went wrong:** The rule was defined with a certain number of `GIVEN` inputs, and a different number was supplied where it was used.

**How to fix it:** Check the rule's definition to see how many inputs it expects, and supply exactly that many. If you meant to supply fewer (partial application), make sure the context supports it.

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

### An @export input that is a rule, not a value

**Error message:** `Function type inputs are not supported for @export.` — or, for the other
spelling, `The @export rule … reads …, which is assumed and takes 1 input of its own.`

**What you wrote:** A published rule that depends on a rule somebody else is expected to supply.

```l4
ASSUME Person IS A TYPE

GIVEN p IS A Person
ASSUME `is eligible` p IS A BOOLEAN

@export Whether the person may apply
GIVEN who IS A Person
GIVETH A BOOLEAN
DECIDE `may apply` IF `is eligible` who
```

**What went wrong:** `@export` publishes a rule as a web endpoint, and a request reaches it as
JavaScript Object Notation (**"JSON"**). JSON carries **values** — a number, a date, a yes or no, a
record of those. It cannot carry a rule. So an input that is itself a rule can never be supplied,
and every request would stop on it.

Three ways of writing the same mistake, all refused:

| what you wrote                                                      | how many inputs it takes |
| ------------------------------------------------------------------- | ------------------------ |
| `GIVEN p IS A Person` above ``ASSUME `is eligible` p IS A BOOLEAN`` | 1                        |
| ``ASSUME `is eligible` IS A FUNCTION FROM Person TO BOOLEAN``       | 1                        |
| ``GIVEN `is eligible` IS A FUNCTION FROM Person TO BOOLEAN``        | 1                        |

An assumed name that takes **no** inputs is a value, and stays publishable: `ASSUME age IS A NUMBER`
is exactly the sort of thing a request supplies.

The check follows every rule the published one reaches, so moving the assumed rule behind a helper
does not silence it — that set is precisely what a request would have to fill in.

**How to fix it:** any of three moves, and the message names all three.

1. **Give the rule a definition** — `DECIDE` or `MEANS` — so nothing outside has to supply it.
2. **Take what it is asked about as an ordinary input.** If `` `is eligible` `` is really a fact
   about the person, make it a field of the person's record and let the request send that.
3. **Remove the `@export`.** The rule still checks, runs and compiles; it is simply not published.

Compiling to [Blawx](../../exports/blawx.md) is the one place this shape is fine as written, because
a Blawx interview asks a person for the answer instead of receiving it in a request. `l4 export blawx` will
still compile such a file even though `l4 check` refuses to publish it.

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
The error stops the whole file from checking: `l4 run`, the REPL, `l4 batch` and every exporter refuse the file, the `#EVAL`s of its other rules included, until you add the `GIVEN` or remove the `@export`.
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

A rule written as a list of clauses, one `DECIDE` line per case, is checked the same way:

```l4
GIVEN status IS A Status
GIVETH A STRING
DECIDE label Active IS "running"
DECIDE label Closed IS "stopped"
```

Here the warning lists the clauses still needed, ready to paste:

```
This multi-clause definition does not cover all cases. The following clauses are still needed:

  DECIDE `label` Suspended IS
```

When the rule has only one clause, the first line reads "This clause does not cover all cases." instead. The check works out the missing clauses only when no pattern in the rule contains a number or a piece of text, even nested as in `(JUST 1)`, or is an `EXACTLY` pattern, and gives up when there would be more than 64 of them to list. A rule of several clauses then gets no warning. A rule of one clause gets the warning for a CONSIDER instead, listing the WHEN branches its clause does not cover, but that warning has the same two limits: `DECIDE f (JUST 1) IS 1` on its own gets no warning at all.

**Note:** Exhaustiveness analysis is skipped when the scrutinee has type NUMBER, STRING, or DATE — these types have effectively infinite value sets, so the analysis (designed for algebraic data types with a finite constructor set) does not apply. Matches on such values get no warning even when incomplete; use OTHERWISE to be safe. BOOLEAN is analysed normally, and so are the builtin container types MAYBE, EITHER, and LIST; the analysis reaches CONSIDER expressions inside WHERE- and LET-bound local definitions. Whatever the type, a CONSIDER in which any branch's pattern contains a number or a piece of text, even nested (`WHEN JUST 1`), or is an `EXACTLY` pattern, gets no warning either way, and neither does one with more than 64 missing branches to list. Warnings never block evaluation — a file with warnings still runs its `#EVAL` directives.

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

A pattern that is not a value of its input's type is a new name, such as `other`, or `Gren` where `Green` was meant, and a new name matches anything too.
The clauses after such a clause get a second form of the warning, which names it:

```
This clause of `colour` is never used, because the clause above it with the new name `Gren` matches every input.
`Gren` is not a value of its input's type, so it is a new name, and a new name matches anything.
If you meant a value, correct the spelling; if you meant to match anything, move that clause below the others.
```

This form is given in rules that match numbers or text too.
It is not given when a pattern of the rule does not fit its input's type, and not for a new name inside a larger pattern: after `(JUST Gren)`, a clause for `(JUST Blue)` gets the third form below instead.
When the new name is very close to a value that no clause matches, as `Gren` is to `Green`, a hint at the pattern says so as well.

A third form, "Every input it matches is already matched by a clause above it", is for a clause that repeats an earlier one, or that is covered by a larger pattern above it. It is only given when no pattern in the rule contains a number or a piece of text, or is an `EXACTLY` pattern: in a table keyed by amounts or codes, a repeated clause draws no warning. (`TRUE` and `FALSE` are not numbers or text; a table keyed by them is checked.)

A clause that is never used is still checked against the rule's `GIVEN` and `GIVETH`, so a mistake inside it, such as a misspelt name or an answer of the wrong type, is still reported.

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

### ASSUME is being retired

**Warning message:**

```
ASSUME is an older way of introducing a name, and it is being retired.
Nothing is broken: the file still checks, runs and exports as before.
This one leaves

  `age`

open for somebody outside the file to supply. Say that
with a GIVEN indented under the heading of the section whose rules
read it (add a § heading if the file has none):

  § <heading>
      GIVEN age IS A NUMBER

(If this ASSUME instead marked a case the rules cannot answer, that is
REFUSE "<the reason>" -- see doc/reference/control-flow/REFUSE.md.)

The manual explains the move: doc/reference/types/ASSUME.md.
```

`l4 check` and `l4 run` print it under a `Severity: DiagnosticSeverity_Warning` header and still exit 0. In the editor it is a warning, not an error, and the declared name is marked as deprecated (most editors strike it through).

**What you wrote:**

```l4
ASSUME age IS A NUMBER

DECIDE `is adult` IF age >= 18
```

**What went wrong:** Nothing is broken. The file still checks, runs and exports exactly as it did, and it will until the keyword is removed. `ASSUME` was one keyword doing four unrelated jobs, three of which the warning can tell apart from the shape of the declaration alone ([ASSUME](../types/ASSUME.md) has the table). The warning reads that shape and names the spelling that replaces it:

- _A fact to be supplied for each case_ (`ASSUME age IS A NUMBER`, or a rule defined elsewhere, `ASSUME rate IS A FUNCTION FROM NUMBER TO NUMBER`): a [section `GIVEN`](../syntax/section-given.md), indented under the heading of the section whose rules read it. The suggested `GIVEN` line is pasteable as written; it carries a `TYPICALLY` default across, and spells the function type out when the `ASSUME` wrote its inputs on the head (`GIVEN n IS A NUMBER` above ``ASSUME `is large` n IS A BOOLEAN`` becomes ``GIVEN `is large` IS A FUNCTION FROM NUMBER TO BOOLEAN``). That rewrite is safe to take: since 2026-09-08 a published rule refuses to read an assumed rule in _either_ spelling ([the entry above](#an-export-input-that-is-a-rule-not-a-value)), so moving between them cannot cost you an export. Where the type cannot be written down at the destination — it names a type variable the `ASSUME` declared for itself with `GIVEN a IS A TYPE`, or an input was written without a type — the line shows a `<type>` hole for you to fill in. An `ASSUME` inside a `WHERE` has no section to move to, so the message offers the rule's own `GIVEN` instead; an `AKA` on the `ASSUME` is named, since a `GIVEN` cannot carry one; and a `@desc` or `@ref` above it is mentioned, since it moves with it.
- _A kind of thing with no stated parts_ (`ASSUME Person IS A TYPE`): a [`DECLARE Person`](../types/DECLARE.md#opaque-types) with nothing after the name — what the DECLARE page calls an **"opaque type"**, a type that is named but not described. That message ends "The manual explains the move: doc/reference/types/DECLARE.md, under Opaque Types".
- _A name that could be of any type_ (`GIVEN a IS A TYPE` followed by `ASSUME gap IS AN a`, with no inputs): no value can ever be supplied for it, so that message offers [`REFUSE`](../control-flow/REFUSE.md) alone and ends "The manual explains the move: doc/reference/control-flow/REFUSE.md." An `ASSUME` with no type written at all (`ASSUME w`) is a different case: the message asks you to write the type in, on a `GIVEN` line with a `<type>` hole.

**How to fix it:** Move the declaration under the heading of the section whose rules read it, and indent it past the `§`:

```l4
§ `Adults`
    GIVEN age IS A NUMBER

DECIDE `is adult` IF age >= 18
```

The warning is given once per `ASSUME`, on the declared name (for an infix pattern such as ``ASSUME a `plus` b IS A NUMBER``, that is the keyword `plus`). A `GIVEN` under a section heading never draws it — not even when an `ASSUME` in the same section happens to share its name.

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

Here `label` has a clause for `Active` and one for `Closed`, and was asked about `Suspended`. Add a clause for the missing case (the warning described under [Non-exhaustive pattern match](#non-exhaustive-pattern-match) lists the clauses still needed), or end the list with a clause whose pattern matches anything. A rule with only one clause says "The only clause of `label` does not match these inputs." instead.

A value that nobody supplied never produces this message: a `CONSIDER` on it stops with [Needed the value of an assumed term](#needed-the-value-of-an-assumed-term) instead, `OTHERWISE` or not.

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

### Needed the value of an assumed term

**Error message:**

```
I could not continue evaluating, because I needed to know the value of
  rate
but it is an assumed term.
```

**What went wrong:** The rule you evaluated reads a name that stands for a fact to be supplied for each case, and nothing supplied it for this run. Two spellings produce that kind of name: a section `GIVEN`, indented under a `§` heading, and, in older files, a module-level `ASSUME` (deprecated). Both are blanks in the rule rather than values, and the answer depends on the blank. The message names, one per line, each blank evaluation reached and needed before it stopped, and a field of a blank record by its path, such as `` `the applicant`'s age ``. A blank it never reached is not named: `#EVAL IF x THEN y ELSE FALSE` names only `x`, though `y` may be needed once `x` is known. Nor is one it would have reached after giving up: working a rule out over a blank may take at most 250,000 steps, and ``#EVAL x OR ((`count up from` 0 EQUALS 20000) OR y)``, which takes more, names only `x`. A directive that stops this way makes `l4 run` exit non-zero.

Evaluation carries a blank along where it can: a comparison (`EQUALS`, `GREATER THAN`, `LESS THAN`, `AT LEAST`, `AT MOST`), `PLUS`, `MINUS` and `TIMES`, and a field of a blank record are worked out in terms of the blank, and `AND`, `OR` and `NOT` combine such answers, so `x AND FALSE` is `FALSE` whatever `x` is. `DIVIDED BY`, `MODULO`, `EXPONENT` and the one-input built-ins such as `FLOOR` and `ROUND` stop at the blank instead, so `(n DIVIDED BY 2 GREATER THAN 1) AND FALSE` waits for `n` where `(n TIMES 2 GREATER THAN 1) AND FALSE` is `FALSE`. So does a field of a blank whose type is declared `IS ONE OF` several kinds, since it may be a kind without that field. It stops when the directive's answer still depends on the blank, and also wherever it would have to choose by the blank's value: to test it with `IF` or `CONSIDER`, to turn it into text with `AS STRING`, `TOSTRING` or `JSONENCODE`, or as the answer, day by day, of `EVER BETWEEN`, `ALWAYS BETWEEN`, `WHEN LAST` or `WHEN NEXT`. A `CONSIDER` stops even when it has an `OTHERWISE` branch, if a branch before the `OTHERWISE` could still match depending on the blank: `OTHERWISE` is not taken just because the blank is there, since the blank could be any value (see [CONSIDER](../control-flow/CONSIDER.md#otherwise)). An `#EVAL` whose answer _is_ the blank, such as `#EVAL rate`, or `#EVAL TRUE AND eligible` with `eligible` a blank, stops the same way rather than print the name as though it were the answer. A rule that only carries the blank along gives its answer with the name in it: `#EVAL LIST rate, 6` prints `LIST rate, 6`.

An answer that is waiting for a blank is not an error, and the tools say so, each in its own way:

| where           | what it shows                                                                                                                                                                                                                                                                                                               |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `l4 run`        | the message above, and the run exits non-zero                                                                                                                                                                                                                                                                               |
| `l4 run --json` | an `#EVAL` gets `"kind": "undetermined"`, with `"needs"`, the list of blanks it waits for, each spelled as the message spells it, and `"message"`; an `#ASSERT` keeps `"kind": "assertion"` with a null `"value"` and the two under `"undetermined"`                                                                        |
| `l4 batch`      | the row's `"status"` is `"undetermined"`; the batch does not stop on it, and exits non-zero once every row has run                                                                                                                                                                                                          |
| `jl4-service`   | a single evaluation answers with the message above, as the `422` it has always been, and an MCP tool with an error whose text is that `422`'s body; a batch keeps the case in `"cases"` with an `"@error"` carrying the message, and counts it in the summary's `"casesIgnored"`; every response says `"report": "default"` |

**How to fix it:** Decide which of three things you meant.

- _The fact genuinely varies from case to case._ Supply it from outside the file. `l4 batch rules.l4 --inputs cases.json` fills each blank from the case it is given, as do `jl4-service` and the web form generated from an `@export`ed rule; the published list of facts asks for exactly the blanks that rule reads, directly or through any rule it relies on, and requires every one of them.
- _The fact is fixed for everyone._ Define it instead of leaving it open — `` `rate` MEANS 0.2 `` — and it stops being a blank.
- _You only wanted to see the rule's shape._ Use `#CHECK`, which reports the type without evaluating anything, rather than `#EVAL`.

- _You want to try the rule on one case, inside the file._ Name the blank with `WITH` at the directive: `#EVAL isAdult WITH age IS 25` supplies a section `GIVEN` called `age` to the rule and to everything it relies on, and `#ASSERT isAdult WITH age IS 25` does the same for a test. This works only for a section `GIVEN`, not for an older `ASSUME` — written against one of those, the same line reports a check error, that `isAdult` is being given named inputs but is not a function, which is a sign the file wants migrating. A value written _before_ the `WITH`, as in ``#EVAL `tax on` 100 WITH rate IS 0.2``, does not parse (`unexpected WITH`): supply every input by name, or none.

See [The section `GIVEN`](../syntax/section-given.md) and [ASSUME (deprecated)](../types/ASSUME.md).

---

### Refusal reported instead of a result

**What you see:**

```
Result:
  The model refuses to answer:
    no Regulation Crowdfunding figure exists before commencement on 2016-05-16
```

**This is not an error.** Evaluation reached a `REFUSE`, which is how the author of the encoding says that the model does not cover this case. The sentence you are reading is theirs. It is not zero, not FALSE, and not "unknown": nobody is missing a fact, and nothing crashed. It is a claim about the encoding, not about the law.

**Where it came from:** search the file for the message. It is a string literal in a `REFUSE`, by house style inside one named definition whose name says the same thing, with an `@ref` above it giving the reason. `TBD`, the drafting placeholder from the prelude, is itself a `REFUSE`, and is not reported any differently from one written out by hand, so the message is what tells you which you have.

**What to do about it:** If the case ought to have an answer, the encoding has a gap, and filling it is a drafting job. There is nothing to deal with a refusal with and nothing to default it to: no `IF`, `CONSIDER`, `AND`/`OR`, `WHERE` or `LET` in any later rule can observe a refusal or turn it into an answer, so only the boundary — the directive, the command-line interface (CLI), the API, the form — ever sees one. If declining _is_ the right answer for this case, record that with `#ASSERT REFUSED`, so a later edit that quietly starts answering it is caught. See [REFUSE](../control-flow/REFUSE.md).

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

**Error message:**

```
I could not find a module with this name: modulename
Nothing it defines is in scope here; names you expected from it are reported as undefined.
I have tried the following locations:
...
```

This is an error, not a warning: it fails `l4 check` and `l4 run` even when nothing in your file reads anything from the missing module. The message lists every place that was searched, once each, in the same tier order as the resolution table. Other commands — `l4 render`, `l4 nlg` and the transpilers among them — print the same error and still exit 0; [When nothing resolves](../libraries/resolution.md#which-commands-fail-on-it) has the measured list.

**What went wrong:** L4 could not find the module you are trying to import. L4 searches for modules in this order (first match wins):

1. Virtual filesystem (VFS) provided by the integrated development environment (IDE) or by the service
2. `JL4_LIBRARY_PATH` environment variable (if set)
3. Project root directory
4. Relative to the importing file
5. Embedded standard libraries compiled into the binary
6. The user-wide data directory laid down by the Cross-Desktop Group (XDG) specification (`~/.local/share/jl4/libraries/`)
7. Bundled with the VSCode extension (`../../libraries/` from executable)

Project-scoped locations (2–4) outrank the embedded stdlib, so intentional overrides work; machine-global locations (6–7) rank below it, so they can only supply modules the embed does not carry. When `JL4_LIBRARY_PATH` is set, the embedded copy (step 5) is skipped entirely — the operator has full control over which libraries are available. See [Library Resolution](../libraries/resolution.md) for the full story, including the shadow warning emitted when several differing copies of a module are visible at once.

**How to fix it:**

- Check the module name for typos. This is usually not the first error on screen: a failed import also produces one "I could not find a definition for the identifier" per name it was meant to supply, so read the top of the output.
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
