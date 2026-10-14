# L4 Syntax Reference

L4's syntax is designed to be readable by legal professionals while maintaining the precision needed for computation. This section documents syntax patterns, rules, and special features.

## Overview

Key syntax features:

- **Layout-sensitive** - Uses indentation like Python
- **Natural language style** - Reads like structured English
- **Annotations** - Metadata for documentation and generation
- **Directives** - Compiler commands for testing and evaluation
- **Special symbols** - Backticks, ditto marks, ellipsis, etc.

---

## Core Syntax Features

### Layout Rules

Indentation-based grouping instead of braces.

**Key Concepts:**

- Blocks defined by indentation level
- Consistent indentation required
- Replaces `{` `}` and `;` separators
- Pythonic style

**Example:** [layout-example.l4](layout-example.l4)

---

### Comments

Documentation and notes in code.

**Example:** [comment-example.l4](comment-example.l4)

**Note:** Both `{- -}` and `/* */` styles work for block comments.

---

### Identifiers

Names for variables, functions, and types.

**Example:** [identifier-example.l4](identifier-example.l4)

**Regular:** Start with letter, continue with letters/numbers/underscore  
**Quoted:** Use backticks for spaces/special characters

**Case Sensitivity:**

- Keywords: UPPERCASE only
- Identifiers: Case-sensitive (`age` ≠ `Age`)

---

## Annotations

Metadata attached to declarations.

### @desc

Human-readable descriptions.

**Example:** [annotation-example.l4](annotation-example.l4)

### @nlg

Natural language generation hints.

**Inline form:** `The applicant [is %age% years old].`

See [annotation-example.l4](annotation-example.l4)

### @ref

Cross-references to legal sources: the provision a rule, a type or an input comes from.

**Line form:** `@ref` and the citation, on a line of its own.

**Inline form:** the citation between `<<` and `>>`, which can sit in the middle of a line.

See [annotation-example.l4](annotation-example.l4)

#### What a `@ref` cites

A `@ref` cites what comes **after** it, so write it on the line above the thing it cites:

```l4
@ref Section 4(1)(a) of the Act
GIVEN age IS A NUMBER
      resident IS A BOOLEAN
GIVETH A BOOLEAN
`is eligible` MEANS
  age >= 18
  AND <<Section 4(1)(b)>> resident
```

The `@ref` cites the rule `is eligible`; the `<<…>>` cites `resident`, the expression that follows it.
A `@ref` is held by the first construct that starts after it: a rule, a type, a section heading, an input, or an expression inside a rule.
Blank lines and comments between a `@ref` and that construct make no difference.
A citation before the first operand of a chain of `AND`, `OR` or arithmetic is held by the whole chain, because the chain is the outermost expression that starts after it; to cite one operand, put the citation just before that operand inside the chain, as with `resident` above.

**Several citations.** Write them one above the other, each on a line of its own.
The construct below keeps all of them, in the order written.

```l4
@ref Dog Act 058 of 1976 (WA)
@ref url https://www.legislation.wa.gov.au/legislation/statutes.nsf/law_a230.html
§ `Dogs Act - 33D.1`
```

Where only one citation per construct is wanted, the nearest is used: the one written last, just above the construct.

#### Two warnings

Both are warnings, so `l4 check` still succeeds, and the VS Code extension marks the `@ref` itself.
The browser-based editor (the WebAssembly build) does not show them: its check drops every warning the parser raises, those for `@nlg` too.

**A `@ref` that follows code on its line.**
A `@ref` written at the end of a line, after the code it means to cite, cannot cite that code, because it cites what comes after it.
It does not cite the next construct either: it is attached to nothing, so the next construct's citation, in the IDE and in every export, is not this one.
The warning names the code it trails:

> This @ref (`1981/61 sec. 2`) follows code on its line, but a @ref refers to what follows it, so this one is attached to nothing. Put it on the line above `GIVETH A BOOLEAN`.

The fix is to move it to the line above that code.
An inline `<<…>>` is warned about only when it ends the line, because in the middle of a line it cites the word after it, which is what it is for.

**A `@ref` with nothing after it.**
A `@ref` after the last construct of the file has nothing to attach to:

> This @ref (`Section 4(1)(a) of the Act`) is at the end of the file, so there is nothing after it to attach to.

#### Where the citation goes

The citation is stored on the syntax tree the checker works on (`l4 ast` shows it).
Nothing else in the checker or the exporters reads it yet, and it is not kept in a deployed bundle, so a service that restarts from its stored bundles has no citation on its syntax tree until the module is compiled again.
The link an editor shows when you hover over a citation comes from the citation itself, not from the syntax tree.

### @ref-src / @ref-map

Source references and mappings.

See [annotation-example.l4](annotation-example.l4)

### @export

Marks a function for export, e.g. as an endpoint when deploying to `jl4-service`. The rest of the annotation line is the exported function's description.

```l4
@export Check whether the applicant qualifies for a discount
GIVEN applicant IS A Applicant
GIVETH A BOOLEAN
DECIDE `qualifies for discount` IF ...
```

### @export default

Adding the `default` keyword marks the **default exported function** — the primary entry point among a file's exports:

```l4
@export default Calculate the insurance premium for an applicant
GIVEN applicant IS A Applicant
GIVETH A NUMBER
DECIDE `calculate premium` IS ...
```

Only functions carrying `@export` are exported; everything else stays internal.

---

## Directives

Compiler commands for testing and evaluation. Directives begin with `#` and appear at the top level of a file.

### #EVAL

Evaluate an expression and display the result. Used for testing functions and inspecting computed values.

**Syntax:**

```l4
#EVAL expression
```

**Examples:**

```l4
#EVAL `is adult` 21        -- evaluates to TRUE
#EVAL `tax owed` 75000     -- evaluates to the computed number
#EVAL 2 PLUS 2             -- evaluates to 4
```

**See also:** [directive-example.l4](directive-example.l4)

### #EVALTRACE

Evaluate an expression and display the full execution trace, showing each step of the evaluation.

**Syntax:**

```l4
#EVALTRACE expression
```

### #TRACE

Evaluate a deontic (regulative) expression and display the obligation trace. Shows the sequence of obligations, which parties must act, deadlines, and the resulting state (FULFILLED or BREACH).

**Syntax:**

```l4
#TRACE deonticExpression AT startTime WITH
  PARTY partyName DOES action AT eventTime
  ...
```

**Examples:**

```l4
#TRACE paymentObligation AT 0 WITH
  PARTY Alice DOES pay 100 AT 15

#TRACE saleContract AT 0 WITH
  PARTY Seller DOES delivery AT 2
  PARTY Buyer DOES payment 100 AT 5
```

**See also:** [Regulative Rules](../regulative/README.md) for the deontic keywords used with #TRACE

### #CHECK

Type check an expression without evaluating it.

**Syntax:**

```l4
#CHECK expression
```

### #ASSERT

Assert that an expression evaluates to TRUE. Used for automated testing.

**Syntax:**

```l4
#ASSERT expression
```

**Example:**

```l4
#ASSERT 2 PLUS 2 EQUALS 4
```

---

## Special Syntax

### Ditto

Copy from line above using `^`.

**Example:** [ditto-example.l4](ditto-example.l4)

**Rules:**

- One `^` per token to copy
- Copies tokens from line directly above
- Useful for repetitive declarations

---

### OF (Positional Argument Syntax)

Multi-purpose structural keyword that introduces comma-separated argument lists. Without OF, arguments must be space-separated on the same line or indented on subsequent lines.

**Contexts where OF appears:**

| Context              | Example                      |
| -------------------- | ---------------------------- |
| Function application | `add OF 3, 4`                |
| Sum type declaration | `IS ONE OF Red, Green, Blue` |
| Type constructor     | `LIST OF Person`             |
| Record construction  | `Pair OF 10, 20`             |
| Pattern matching     | `WHEN Pair OF x, y THEN ...` |

**Examples:**

```l4
-- With OF: comma-separated args on one line
result1 MEANS add OF 3, 4
result2 MEANS foldr OF add, 0, numbers

-- Without OF: space-separated on same line
result3 MEANS add 3 4
```

OF is optional in function application -- `add OF 3, 4` and `add 3 4` are equivalent. But for multi-argument calls, OF with commas is often clearer than relying on whitespace parsing.

**See also:** [Types reference](../types/keywords.md) for OF in type contexts

---

### TO (Function Type Syntax)

Used in function type annotations to separate input types from the return type.

**Syntax:**

```l4
FUNCTION FROM Type1 AND Type2 TO ReturnType
```

**Note:** `TO` is a reserved keyword used only in function type annotations. In deontic rules, `to` appearing in an action (e.g. `deliver goods to buyer`) is part of the mixfix expression, not the TO keyword.

---

### Genitive

Record field access using `'s`.

**Example:** [genitive-example.l4](genitive-example.l4)

---

### Section Markers (§)

Organize code into named, nested scopes using `§`, similar to sections in legislation. Definitions in different sections do not shadow each other; the compiler creates fully qualified name bindings for disambiguation.

**Levels:**

- `§` -- Top-level section
- `§§` -- Subsection
- `§§§` -- Sub-subsection

**Example:** [section-example.l4](section-example.l4)

**Qualified access:** When the same name exists in multiple sections, consumers must qualify to disambiguate. This parallels how legislation scopes definitions ("for purposes of subsection 2, X means ...").

```l4
§ `Part VII`

§§ `Subsection 2`
`age of majority` MEANS 18

§§ `Subsection 3`
`age of majority` MEANS 21

-- Consumer must qualify:
DECIDE `is adult under sub 2` IF
    age >= `Part VII`'s `Subsection 2`'s `age of majority`
```

**Section aliases:** Use AKA to create shorter names for qualified references:

```l4
§ `Definitions for Part VII` AKA defs
  taxableIncome MEANS 50000

result MEANS defs.taxableIncome   -- via alias
```

---

## Literals

### Numbers

**Integers:** `42`, `-17`, `0`  
**Rationals:** `3.14`, `-0.5`, `2.718`

**Thousand separators:** Underscores may appear between digits as a visual grouping aid. They are stripped before the numeric value is computed, so `100_000` is exactly `100000` and `1_000_000.50_5` is exactly `1000000.505`. A literal must start with a digit and must not end with an underscore (so `_100` and `100_` are rejected).

### Strings

**Basic:** `"hello world"`, `"L4 language"`  
**Escape Sequences:** `\n` (newline), `\"` (quotes), `\\` (backslash)

### Booleans

`TRUE`, `FALSE`

### Lists

`LIST 1, 2, 3`, `EMPTY`, `1 FOLLOWED BY 2 FOLLOWED BY EMPTY`

---

## Symbols

### Parentheses

`( )` - Grouping and tuples.

Examples: `(age PLUS 5) TIMES 2`, `PAIR OF 1, 2`

### Brackets

`[ ]` - Inline NLG annotations.

Example: `The applicant [is %age% years old].`

### Angles

`<< >>` - Inline reference annotations.

Example: `The applicant <<must be 18 or over>>.`

### Braces

`{ }` - Block comments (alternative).

Example: `{- Block comment -}`

### Other Symbols

- `,` - Separator
- `;` - Statement separator (rarely needed with layout)
- `.` - Decimal point
- `:` - Type signature separator
- `%` - Percent numbers, NLG expression delimiter
- `^` - Ditto (copy above)
- `...` - Asyndetic AND
- `..` - Asyndetic OR

---

## Syntax Conventions

### Naming Conventions

**Variables and Functions:**

- camelCase: `taxRate`, `calculateTotal`
- snake_case: `tax_rate`, `calculate_total`
- Spaces with backticks: `` `tax rate` ``

**Types:**

- PascalCase: `Person`, `TaxBracket`
- Prefer nouns

**Constants:**

- UPPERCASE: `MAX_AGE`, `DEFAULT_RATE`

### Indentation

- **2 spaces** or **4 spaces** (choose one, be consistent)
- No tabs
- Align related items vertically

### Line Length

- Recommended: 80-100 characters
- Legal text may be longer for readability

---

## Style Guide

### Readability

- Use whitespace liberally
- Add comments for complex logic
- Prefer textual operators in legal contexts

### Consistency

- Follow project conventions
- Use linter/formatter when available
- Be consistent within a file

### Legal Isomorphism

- Structure code to mirror legal text
- Use legal terminology in identifiers
- Preserve section/subsection hierarchy

---

## Common Patterns

### Type Declarations

**Example:** [record-example.l4](../types/record-example.l4)

### Function Definitions

**Example:** [function-type-example.l4](../types/function-type-example.l4)

### Pattern Matching

**Example:** [enum-example.l4](../types/enum-example.l4)

---

## See Also

- **[GLOSSARY](../GLOSSARY.md)** - Complete feature index
- **[Functions](../functions/README.md)** - Function keywords
- **[Specifications](https://github.com/legalese/l4-ide/tree/main/specs)** - Technical specifications
