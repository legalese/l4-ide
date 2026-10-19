# Fix errors

Read an L4 error message, find the cause, and fix it. The [error message reference](../../reference/errors/README.md) lists the errors one by one; this page shows how to work through them.

---

## Read a diagnostic

Run `l4 check myfile.l4`, or open the file in VS Code, which shows the same messages as red underlines. Each problem is printed as a block:

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

Read three things, in this order:

1. **Range**: `line:column-line:column` of the code at fault. Go there first.
2. **Source**: `parser` means the file could not be read as L4 at all, usually because of layout or a misplaced keyword. `check` means it was read but the types do not fit together.
3. **Message**: the explanation, in plain words. Read all of it before guessing.

When there are several errors, fix the first one and check again: later errors are often caused by the first. `l4 check` exits with `0` when the file is valid and `1` otherwise.

---

## A debugging routine

1. Run `l4 check file.l4` after every few edits. It is fast because it evaluates nothing.
2. Read the **first** diagnostic only. Note its source (`parser` or `check`) and go to its range.
3. For a `parser` error, look at the line above as well: a layout problem is often caused by the construct before it.
4. For a `check` error, find the pair "expected X … but is here of type Y" and decide which side is wrong.
5. Still can't see it? Comment out half of the file (`--` per line, or `{- ... -}` around a block), check again, and narrow it down.
6. Search the [error message reference](../../reference/errors/README.md) for a phrase from the message.

---

## Common errors

### Indentation

L4 is layout-sensitive: the body of a definition must be indented further than the line that introduces it. The diagnostic above comes from this file:

```l4
GIVEN x IS A NUMBER
GIVETH A NUMBER
DECIDE `twice` IS
x TIMES 2
```

Indent the body (`    x TIMES 2`) or keep it on the same line. Any `parser` error that says "incorrect indentation" or "unexpected …" is usually a layout problem. See [Incorrect indentation](../../reference/errors/README.md#incorrect-indentation).

### Type mismatch

The `GIVETH` type is a promise that the body has to keep:

```l4
GIVEN x IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is large` IS x PLUS 1
```

```
The type of this definition must match its type signature at err-mismatch.l4:2:8-17, namely

  BOOLEAN

but is here of type

  NUMBER
```

Decide which side is wrong. Here it is the body: ``DECIDE `is large` IF x GREATER THAN 1000``. L4 never converts types for you; when you need a conversion, write it (see [Coercions](../../reference/types/coercions.md)). See [Types](../../reference/errors/README.md#types).

### Unknown name

A file defines `` `is an adult` `` for a `Person`, and a test misspells it as `` #EVAL `is an adutl` `Alice` ``:

```
I could not find a definition for the identifier

  `is an adutl`

which I have inferred to be of type:

  FUNCTION FROM Person TO res11
```

The second half shows how the unknown name is used: here, as a function from `Person` to something not yet known (`res11`). Use that to find the definition you meant. In order of likelihood:

- **Spelling**, including spaces inside backticks: `` `is an adult` `` and `` `is an adult ` `` are different names.
- **Missing backticks**: `is an adult` without backticks is three separate words.
- **The definition does not exist**: order does not matter for top-level definitions, but the name must be defined in the file or in an imported module.

### Missing IMPORT

A library name such as `Date` only exists after you import the library that defines it. Without `IMPORT daydate`, the line `` `the closing date` MEANS Date 15 1 2025 `` gives "I could not find a definition for the identifier `Date`", the same message as a typo. Add the import:

```l4
IMPORT daydate

`the closing date` MEANS Date 15 1 2025

#EVAL `the closing date`
```

If an unknown name is one you did not define yourself, check the [library reference](../../reference/libraries/README.md) for the library that provides it. See [I could not find a definition for the identifier](../../reference/errors/README.md#i-could-not-find-a-definition-for-the-identifier) and [Module not found](../../reference/errors/README.md#module-not-found).

### Ambiguous operator: mixed types in a comparison

Comparison operators such as `AT LEAST` work on numbers, strings and booleans, as long as both sides have the same type. Compare a number with a string and L4 cannot choose:

```l4
DECLARE Person
    HAS `name` IS A STRING
        `age`  IS A NUMBER

GIVEN person IS A Person
GIVETH A BOOLEAN
DECIDE `is an adult` IF
    person's `age` AT LEAST "18"
```

```
There are multiple definitions for the identifier

  `__GEQ__`

and I do not have sufficient information to make a choice between them.
The options are:

  `__GEQ__` (predefined) of type FUNCTION FROM NUMBER AND NUMBER TO BOOLEAN
  `__GEQ__` (predefined) of type FUNCTION FROM STRING AND STRING TO BOOLEAN
  `__GEQ__` (predefined) of type FUNCTION FROM BOOLEAN AND BOOLEAN TO BOOLEAN
```

`__GEQ__` is the internal name of `AT LEAST` (`>=`). None of the listed versions takes a `NUMBER` and a `STRING`, which is the problem. Make both sides the same type: ``person's `age` AT LEAST 18``.

The same "multiple definitions" message appears with `__PLUS__` and other operators when an imported library adds versions of them (`daydate` adds `PLUS` for dates) and the operands do not show which one you mean. Fix a mistyped literal, or give one operand a known type.

### `@export` with a function-typed input

A rule marked `@export` cannot take a function as an input, because a function cannot be sent as JSON. The error is "Function type inputs are not supported for @export". See [ASSUME and `@export`](../../reference/types/ASSUME.md#function-typed-inputs-are-not-supported-for-export).

---

## Next steps

- [Error message reference](../../reference/errors/README.md): every error message, with fixes.
- [Test your rules](testing-your-rules.md): once the file type-checks, check that it gives the right answers.
