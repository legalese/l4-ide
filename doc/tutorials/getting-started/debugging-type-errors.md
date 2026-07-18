# Debugging Type Errors

Read, understand, and fix the errors the L4 compiler reports most often to beginners.

**Prerequisites:** [Your First L4 File](first-l4-file.md), [Using the l4 CLI](l4-cli.md)

---

## How Errors Are Reported

Run `l4 check myfile.l4` (or open the file in VS Code — same compiler, same messages as red underlines). Each problem is printed as a diagnostic block:

```
File:     myfile.l4
  Range:    4:1-4:1
  Source:   parser
  Severity: DiagnosticSeverity_Error
  Message:  ...
```

Three things to read, in order:

1. **Range** — `line:column-line:column` of the offending code. Go there first.
2. **Source** — `parser` means the file could not even be read as L4 (usually layout/indentation); `check` means it parsed but the types do not line up.
3. **Message** — the explanation. L4's messages are written in prose; read them fully before guessing.

When there are several errors, **fix the first one and re-check**: later errors are often knock-on effects of the first.

The exit code is `0` when the file is valid and `1` otherwise, so `l4 check` slots straight into scripts and CI.

This page walks through the errors beginners hit most. For the systematic catalog of error messages and fixes, see the [error troubleshooting reference](../../reference/errors/README.md).

---

## 1. Incorrect Indentation (Parse Error)

L4 is layout-sensitive: the body of a definition must be indented further than the line that introduces it.

```l4
-- ❌ Wrong: the body starts at column 1
GIVEN x IS A NUMBER
GIVETH A NUMBER
DECIDE `twice` IS
x TIMES 2
```

```
File:     err-layout.l4
  Range:    4:1-4:1
  Source:   parser
  Severity: DiagnosticSeverity_Error
  Message:
      |
    4 | x TIMES 2
      | ^
    incorrect indentation (got 1, should be greater than 1)
```

The message tells you exactly what the layout rule wanted: the continuation had to be indented more than column 1. Fix by indenting the body (or keeping it on the same line):

```l4
-- ✅ Right
GIVEN x IS A NUMBER
GIVETH A NUMBER
DECIDE `twice` IS
    x TIMES 2
```

Any `Source: parser` error with "incorrect indentation" or "unexpected <token>" is a layout problem. Check that continuation lines are indented deeper than the construct they belong to, and that `THEN`/`ELSE` chains stair-step consistently.

---

## 2. Type Mismatch Against the Signature

The declared `GIVETH` type is a promise; the body has to keep it.

```l4
-- ❌ Wrong: the signature promises a BOOLEAN, the body computes a NUMBER
GIVEN x IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is large` IS x PLUS 1
```

```
File:     err-mismatch.l4
  Range:    3:22-3:30
  Source:   check
  Severity: DiagnosticSeverity_Error
  Message:
    The type of this definition must match its type signature at err-mismatch.l4:2:8-17, namely

      BOOLEAN

    but is here of type

      NUMBER
```

The message names both sides: what the signature (at the quoted location) requires, and what the body actually produced. Decide which one is wrong — here, presumably the body:

```l4
-- ✅ Right
GIVEN x IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is large` IF x GREATER THAN 1000
```

L4 never coerces types implicitly. If you genuinely need to convert, do it explicitly (`TOSTRING`, `TONUMBER`, ...).

---

## 3. Unknown Identifier (Usually a Typo)

```l4
DECLARE Person
    HAS `name` IS A STRING
        `age`  IS A NUMBER

GIVEN person IS A Person
GIVETH A BOOLEAN
DECIDE `is an adult` IF
    person's `age` AT LEAST 18

`Alice` MEANS Person WITH
    `name` IS "Alice"
    `age`  IS 30

#EVAL `is an adutl` `Alice`     -- ❌ typo: adutl
```

```
File:     err-typo.l4
  Range:    14:7-14:20
  Source:   check
  Severity: DiagnosticSeverity_Error
  Message:
    I could not find a definition for the identifier

      `is an adutl`

    which I have inferred to be of type:

      FUNCTION FROM Person TO res11
```

Note the second half: even though the name is unknown, the compiler inferred _how it is being used_ — as a function from `Person` to something. That inferred type is your clue for finding the definition you meant. (`res11` is a placeholder for "a type I could not determine".)

Fixes, in order of likelihood:

- **Spelling** — including spaces and punctuation inside backticks: `` `is an adult` `` and `` `is an adult ` `` (trailing space) are different names.
- **Definition order in expressions is not the issue** — top-level definitions can be used before they appear — but the definition must exist _somewhere_ in the file or an imported module.
- **Missing backticks** — `is an adult` without backticks is three separate tokens, not one name.

---

## 4. Missing IMPORT

Library names like `Date` only exist after you import the library that defines them:

```l4
-- ❌ Wrong: Date needs the daydate library
`the closing date` MEANS Date 15 1 2025

#EVAL `the closing date`
```

```
File:     err-import.l4
  Range:    1:26-1:30
  Source:   check
  Severity: DiagnosticSeverity_Error
  Message:
    I could not find a definition for the identifier

      Date

    which I have inferred to be of type:

      FUNCTION FROM NUMBER AND NUMBER AND NUMBER TO res7
```

It looks like a typo error, but the name is spelled correctly — it is simply not in scope. The fix is an import at the top of the file:

```l4
-- ✅ Right
IMPORT daydate

`the closing date` MEANS Date 15 1 2025

#EVAL `the closing date`
```

If an unknown identifier is a name you did not define yourself, check the [library reference](../../reference/libraries/README.md) for which `IMPORT` provides it. Imports must be the first declarations in the file.

---

## 5. Ambiguous Operator (Mixed Types in a Comparison)

Comparison operators like `AT LEAST` are overloaded — they work on numbers, strings, and booleans, as long as _both sides agree_. Compare a number to a string and the compiler cannot pick an overload:

```l4
-- ❌ Wrong: comparing a NUMBER field to the STRING "18"
DECLARE Person
    HAS `name` IS A STRING
        `age`  IS A NUMBER

GIVEN person IS A Person
GIVETH A BOOLEAN
DECIDE `is an adult` IF
    person's `age` AT LEAST "18"
```

```
File:     err-type.l4
  Range:    8:5-8:33
  Source:   check
  Severity: DiagnosticSeverity_Error
  Message:
    There are multiple definitions for the identifier

      `__GEQ__`

    and I do not have sufficient information to make a choice between them.
    The options are:

      `__GEQ__` (predefined) of type FUNCTION FROM NUMBER AND NUMBER TO BOOLEAN
      `__GEQ__` (predefined) of type FUNCTION FROM STRING AND STRING TO BOOLEAN
      `__GEQ__` (predefined) of type FUNCTION FROM BOOLEAN AND BOOLEAN TO BOOLEAN
```

`__GEQ__` is the internal name for `AT LEAST`/`>=`. The listed options are the available overloads — none of them accepts a `NUMBER` on the left and a `STRING` on the right, which is exactly the problem. Make both sides the same type:

```l4
-- ✅ Right
    person's `age` AT LEAST 18
```

You will see the same "multiple definitions ... `__PLUS__`" shape when an imported library adds overloads (for instance, `daydate` overloads `PLUS` for dates) and the operands do not pin down which one you mean. Adding a type annotation to one operand, or fixing a mistyped literal, resolves it.

---

## 6. Annotation Misuse: `@export` with a Function-Typed Input

`@export` publishes a rule as an API endpoint, so every input has to be representable as JSON. A parameter of `FUNCTION FROM ... TO ...` type cannot be, and the typechecker rejects it:

```l4
-- ❌ Wrong: exported rule takes a function as input
@export Check a predicate against a number
GIVEN p IS A FUNCTION FROM A NUMBER TO A BOOLEAN, x IS A NUMBER
GIVETH A BOOLEAN
DECIDE `check with` IS p x
```

```
File:     err-export.l4
  Range:    4:8-4:20
  Source:   check
  Severity: DiagnosticSeverity_Error
  Message:
    Function type inputs are not supported for @export.
    The parameter `p` has a function type.
```

Fix by removing the `@export` (keep the higher-order function internal) or by restructuring the exported rule to take plain data — for example, an enum value selecting among known predicates.

---

## A Debugging Routine

1. `l4 check file.l4` — cheap and fast; run it after every few edits.
2. Read the **first** diagnostic only. Note its `Source` (parser vs check) and go to its range.
3. Parser errors → look one line _up_ as well: layout problems are often caused by the previous construct.
4. Check errors → read the "expected X but got Y" pair and decide which side is wrong.
5. Can't see it? Isolate: comment out half the file (`--` or `{- ... -}` blocks) and re-check, then bisect.
6. Still stuck? Search the [error troubleshooting reference](../../reference/errors/README.md) for a phrase from the message.

---

## Next Steps

- [Error troubleshooting reference](../../reference/errors/README.md) — the systematic catalog this page samples from
- [Testing Your Rules](testing-your-rules.md) — catch semantic regressions once the types are clean
- [Common Patterns](../../reference/patterns/common-patterns.md) — idiomatic shapes that avoid these errors in the first place
