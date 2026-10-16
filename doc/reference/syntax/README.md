# Syntax and directives

This page covers how an L4 file is written: layout, comments, names, literals, annotations, directives and the special forms that make rules read like legal text.
For how to write rules that read well, see [Writing in the L4 style](../../concepts/language-design/principles.md#writing-in-the-l4-style).

## Layout

L4 is layout-sensitive: indentation, not braces or semicolons, shows what belongs to what.
The lines of a block are indented further than the line that opens it, and the items of a block (fields, inputs, branches) start in the same column.
Spaces only; a tab is not a substitute.

**Example:** [layout-example.l4](layout-example.l4)

In a long expression, indentation also groups the operators; see [AND, OR, NOT, IMPLIES: Several lines](../operators/logical.md#several-lines).

## Comments

- `--` or `//` starts a comment that runs to the end of the line.
- `{- … -}` and `/* … */` enclose a comment that can span several lines.

**Example:** [comment-example.l4](comment-example.l4)

## Identifiers

- A plain identifier starts with a letter and continues with letters, digits and underscores: `age`, `income_band`.
- A quoted identifier is written in backquotes and can contain spaces and punctuation: `` `the applicant` ``, `` `Section 2(a)` ``. Prefer these: they let a rule read like the legal text.
- Keywords (`DECIDE`, `GIVEN`, `IF`, …) are written in capitals. Identifiers are case-sensitive: `` `the rate` `` and `` `The rate` `` are different names.

**Example:** [identifier-example.l4](identifier-example.l4)

## Literals

| Kind    | Examples                                                     |
| ------- | ------------------------------------------------------------ |
| Number  | `42`, `-17`, `3.14`, `5%` (= `0.05`), `100_000`              |
| Text    | `"hello"`, with `\"`, `\\` and `\n` as escapes               |
| Boolean | `TRUE`, `FALSE`                                              |
| List    | `LIST 1, 2, 3`, `EMPTY`, `1 FOLLOWED BY 2 FOLLOWED BY EMPTY` |

Underscores between the digits of a number are ignored. A number must start with a digit and must not end with an underscore.
There is no date literal; see [Types and data](../types/README.md#built-in-types).

## IMPORT

`IMPORT name` at the top of a file, before the first `§` section, makes the definitions of a library or another L4 file available. An `IMPORT` below a section heading is ignored. See [Standard libraries: IMPORT](../libraries/README.md#import).

## Annotations

Annotations attach information to the definition that follows them, or to the line they end.

### @desc

`@desc text` describes a rule, a type or an input. It goes on the line above a definition, or at the end of an input's line. Deployed functions show it to their callers.

```l4
@desc The applicant's age in years
ASSUME `the applicant's age` IS A NUMBER
```

### @nlg

`@nlg` gives the natural-language wording of a definition, with `%name%` slots for its inputs. Write it at the end of the definition's line. `l4 render` and the editor use it when they put the rule into words.

```l4
GIVEN x IS A NUMBER, y IS A NUMBER
GIVETH A NUMBER
`the greater of` x y @nlg the greater of %x% and %y%
  MEANS IF x >= y THEN x ELSE y
```

Text in square brackets after a name, as in ``DECIDE `the limit` [the statutory limit] IS 5``, is a short inline wording for that name.
How to use `@nlg` well: [Make rules read like law](../../tutorials/natural-language-functions/optimising-natural-language-generation.md).

### @ref

`@ref` cites a legal source: the provision a rule, a type or an input comes from.

- **Line form:** `@ref` and the citation, on a line of its own.
- **Inline form:** the citation between `<<` and `>>`, which can sit in the middle of a line.

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
In the editor, hovering over a citation shows it as a link.

**`@ref-map name url`** maps a citation to a link: a `@ref` whose text is `name` links to `url`.

#### Two warnings

Both are warnings, so `l4 check` still succeeds, and the VS Code extension marks the `@ref` itself.
The browser-based editor does not show them.

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

### @export

`@export` marks a function to be published as an endpoint when the file is deployed. The rest of the line is the function's description. Functions without `@export` stay internal.

```l4
@export Check whether a person is old enough to apply
GIVEN age IS A NUMBER @desc The person's age in years
GIVETH A BOOLEAN
DECIDE `is old enough` IF age >= 18
```

`@export default` marks the file's main entry point among its exports.
A function written as [several clauses](../functions/DECIDE.md#several-clauses) needs a `GIVEN` to be exported, and a function-typed input cannot be exported ([ASSUME](../types/ASSUME.md#function-typed-inputs-are-not-supported-for-export)).
How to deploy: [Deploy your rules](../../tutorials/deploying-rules/exporting-rules-for-deployment.md).

**Example:** [annotation-example.l4](annotation-example.l4)

## Directives

Directives are instructions to the tools, written at the top level of a file. `l4 run` and the editor carry them out; `l4 check` only type-checks them.

| Directive    | What it does                                                                                      |
| ------------ | ------------------------------------------------------------------------------------------------- |
| `#EVAL`      | evaluates an expression and shows the result                                                      |
| `#EVALTRACE` | evaluates an expression and also shows the steps that led to the result (`l4 trace` draws them)   |
| `#CHECK`     | type-checks an expression and shows its type, without evaluating it                               |
| `#ASSERT`    | evaluates an expression and reports "assertion failed" when it is not TRUE                        |
| `#TRACE`     | runs a regulative rule against a list of events (see [Regulative rules](../regulative/README.md)) |

```text
#EVAL expression
#EVALTRACE expression
#CHECK expression
#ASSERT expression
#TRACE rule AT start-time WITH
  PARTY party DOES action AT time
```

A directive's expression ends with its line. To continue it, start the next line with `#` and a space, followed by an operator:

```l4
GIVEN age IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is an adult` IF age >= 18

#EVAL `is an adult` 21
#   AND `is an adult` 30
#CHECK `is an adult`
#ASSERT NOT `is an adult` 12
```

**Example:** [directive-example.l4](directive-example.l4)

## Sections

`§` starts a section, like a part or section of a statute; `§§` starts a subsection, `§§§` a sub-subsection, and so on. The heading is the name after the marks.

```l4
§ `Part VII`

§§ `Subsection 2`
`age of majority` MEANS 18

§§ `Subsection 3`
`age of majority` MEANS 21

GIVEN age IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is an adult under subsection 2` IF
    age >= `Part VII`'s `Subsection 2`'s `age of majority`
```

Definitions in different sections can share a name. Where the name alone would be ambiguous, qualify it with the section's name and `'s`, as above.
A section can have a shorter alias: ``§ `Definitions for Part VII` AKA defs``, then `` defs's `taxable income` `` (or `` defs.`taxable income` ``).

**Example:** [section-example.l4](section-example.l4)

## Genitive

`'s` reads a field of a record, as in English: `` `the applicant`'s age ``. It can be chained: `` `the applicant`'s address's city ``.
``age OF `the applicant` `` means the same.

**Example:** [genitive-example.l4](genitive-example.l4)

## OF

`OF` introduces arguments separated by commas: `add OF 3, 4` means the same as `add 3 4`.
It also appears in types (`LIST OF NUMBER`, `Box OF NUMBER`), in enumerations (`IS ONE OF`), when making a record (`Person OF "Kim", 30`) and in patterns (`WHEN JUST OF x`).

## Ditto

`^` repeats the word in the same position on the line above, one `^` per word. It keeps repetitive lines short.

**Example:** [ditto-example.l4](ditto-example.l4)

## Asyndetic AND and OR

`...` means `AND` and `..` means `OR`, as in lists of conditions in legal text. See [Operators: Asyndetic AND and OR](../operators/README.md#asyndetic-and-and-or).

## Related pages

- [Glossary](../GLOSSARY.md): every keyword, with links
- [Definitions](../functions/README.md)
- [Operators](../operators/README.md)
