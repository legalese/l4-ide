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
- [Indentation Errors](#indentation-errors)
  - [Body less indented than definition](#body-less-indented-than-definition)
  - [Multi-line function arguments](#multi-line-function-arguments)
- [Type Errors](#type-errors)
  - [Branch type mismatch](#branch-type-mismatch)
  - [Undefined field access](#undefined-field-access)
  - [Function arity mismatch](#function-arity-mismatch)
  - [Clauses with more or fewer patterns than the GIVEN names](#clauses-with-more-or-fewer-patterns-than-the-given-names)
  - [APPEND vs append](#append-vs-append)
- [Compiler Warnings](#compiler-warnings)
  - [Non-exhaustive pattern match](#non-exhaustive-pattern-match)
  - [Multi-clause DECIDE does not cover all cases](#multi-clause-decide-does-not-cover-all-cases)
  - [Redundant pattern match branch](#redundant-pattern-match-branch)
  - [Clause that is never used](#clause-that-is-never-used)
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
L4 then works out the type of each input from the patterns, and where it has to name an input, as `l4 render` does, it calls them `input 1`, `input 2`, and so on.

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

**Note:** Exhaustiveness analysis is skipped when the scrutinee has type NUMBER, STRING, or DATE — these types have effectively infinite value sets, so the analysis (designed for algebraic data types with a finite constructor set) does not apply. Matches on such values get no warning even when incomplete; use OTHERWISE to be safe. BOOLEAN is analysed normally, and the analysis reaches CONSIDER expressions inside WHERE- and LET-bound local definitions; the builtin container types MAYBE, EITHER, and LIST are not yet analysed. Warnings never block evaluation — a file with warnings still runs its `#EVAL` directives.

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

**Note:** Only rules whose clauses match enumeration values or `TRUE`/`FALSE` are checked. Rules that match numbers, text, lists or `MAYBE` values, or an enumeration declared in another file, get no warning, and neither does a rule that would need more than 64 clauses listed. A rule of one clause that is not checked keeps whatever warning a CONSIDER would give (see [Non-exhaustive pattern match](#non-exhaustive-pattern-match)), listing WHEN branches, now at the clause; a CONSIDER over a number or a piece of text gives none. See [Multi-clause DECIDE](../functions/multi-clause-DECIDE.md#missing-cases).

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

A repeated clause is not flagged, and neither is a clause after one whose pattern is a new name such as `other`, although a new name matches anything too.

**How to fix it:** Put the clauses for particular cases first and the clause that matches anything last, or remove the clause that can never be reached.

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

**Error message:** `Error: cannot resolve import 'modulename'`

**What went wrong:** L4 could not find the module you are trying to import. L4 searches for modules in this order:

1. Virtual filesystem (VFS) provided by the IDE or service
2. `JL4_LIBRARY_PATH` environment variable (if set)
3. Project root directory / relative to the importing file
4. XDG data directory (`~/.local/share/jl4/libraries/`)
5. Bundled with the VSCode extension (`../../libraries/` from executable)
6. Embedded standard libraries compiled into the binary

When `JL4_LIBRARY_PATH` is set, embedded libraries (step 6) are skipped. This gives operators full control over which libraries are available.

**How to fix it:**

- Check the module name for typos.
- For your own modules, place them in the project directory or set `JL4_LIBRARY_PATH`.
- For third-party libraries, install them to `~/.local/share/jl4/libraries/`
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
