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
There is no date literal; see [Types](../types/README.md#built-in-types).

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

#### Where to put it

An annotation describes the thing it sits with, and there are two places to sit:

```l4
-- trailing: describes `amount`
GIVEN amount IS A NUMBER @nlg the claim amount

GIVETH A BOOLEAN
-- own line: describes the rule
@nlg the claim of %amount% is large
DECIDE `is large` IF amount GREATER THAN 100
```

**Trailing a line, it describes what is on that line.**
**Starting a line of its own, it describes what follows.**
That holds whether the thing is a rule, an input, a field or a type declaration, with two exceptions, for a list of fields and a list of inputs, below.

**Put a rule's sentence trailing its head, or on its own line between its `GIVEN` block and the `DECIDE`, never above the `GIVEN`.**
An annotation on its own line above a `GIVEN` is not the rule's, because the `GIVEN` comes between them.
When something written just before it can take it, such as an `IMPORT` or a section heading, it is read as that one's and nothing is reported; when nothing can, L4 warns "Not attached to any valid syntax node".

**Before this rule, an annotation attached to the nearest name before it.**
`GIVEN a IS A STRING @nlg the amount` then annotated `STRING`, and an annotation on its own line above a `DECIDE` annotated the `GIVETH` type.
Both attached to a node nothing reads, so the annotation rendered nowhere and nothing said so.

**An empty `@nlg` is ignored, and says so.**
A rendering replaces what it annotates, so `@nlg` with nothing after it would erase the name from the output rather than leave it alone.
L4 drops it and warns instead.

**A record field can carry two.**
`head [the first item] IS AN a [an element]` glosses the field and its type separately, because each annotation sits with the token it follows.

**A field list is an exception to "own line describes what follows".**
Underneath a field, an annotation describes _that_ field, the one above it, not the next one:

```l4
DECLARE Employee
  HAS `full name`  IS A STRING
      -- describes `full name`
      @nlg the employee's full name
      `start date` IS A DATE
```

A field list is a column of things rather than a sequence of declarations, and writing the gloss under the field it belongs to is what authors do.

**A `GIVEN` list is the other exception, last input included.**
Underneath an input, an annotation describes that input.
Under the LAST input, with no `GIVETH` before the rule, the same line is also the line above the rule, so the column decides: indented further than the `GIVEN` keyword, the annotation describes the input; at the keyword's column or left of it, it describes the rule.

```l4
GIVEN floor  IS A NUMBER
      amount IS A NUMBER
      @nlg the sum of money
@nlg the claim of %amount% is over %floor%
DECIDE `is large` IF amount GREATER THAN floor
```

Here `the sum of money` is `amount`'s gloss and the second annotation is the rule's sentence.
It is the `GIVEN` keyword's column that counts, not the left margin, so a `GIVEN` indented under a section heading or inside a `WHERE` reads the same way.
The column is all it reads: a rule's sentence indented under the last input, by even one space, becomes that input's gloss, and nothing warns.
The exceptions are confined to those two lists: between `GIVETH` and `DECIDE`, an annotation on its own line describes the rule below it at any indentation.

**The last field of a record, and an `ASSUME`, are read by the same column.**
The last field of a record, and the last field of the last constructor of an enum, have no field after them, so the line under them is also the line above whatever is written next.
An annotation indented further than the `DECLARE` keyword describes that field; at the keyword's column or left of it, it describes what follows.
An `ASSUME` is read the same way: an annotation trailing it, or indented under it, is its own, and one at the margin is the next declaration's.
After an enum whose last value has no fields, an annotation at the margin is still read as that value's: nothing is reported unless the value already carries a note, and the rule written below it loses the annotation.
Write the rule's sentence trailing the rule's head instead, as in ``DECIDE `passes` @nlg the test is passed``.

#### Writing a literal `%` or `]`

Inside `@nlg`, `%` marks an input to fill in, and `%age%` is replaced by the value of `age`.
A `]` ends a bracketed annotation.
To write either character as itself, put a backslash in front of it.

| you write            | you get           | without the backslash             |
| -------------------- | ----------------- | --------------------------------- |
| `10\%and\%20`        | `10%and%20`       | `and` is read as an input name    |
| `[rate \] per unit]` | `rate ] per unit` | the annotation ends early         |
| `\\`                 | `\`               | —                                 |

**Most of the time you do not need this.**
A percent sign with a space after it is already ordinary text, so `a 5% levy on %amount%` works as written and fills in `amount`.
The backslash is for the case with no space, such as `10%and%20`, where L4 cannot tell a written-out range from an input.

**The two mistakes fail very differently, and the quiet one is the one to watch.**
A stray `]` ends the annotation early and you get a parse error pointing at the leftover text, which is annoying but tells you.
A stray `%` pair tells you nothing.
If the word between the two percent signs happens to name one of your inputs, L4 quietly substitutes that value, and your sentence comes out with a number where you wrote a word.
Nothing is reported, and the rule still runs.

**What this costs.**
A backslash immediately before the closing `]` no longer ends the annotation, because `\]` now means a literal `]`.
Write `\\` if you want the annotation to end with a backslash.
Any other character after a backslash is left completely alone: `\q` is still a backslash followed by a `q`.

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

#### Writing a literal `>>`

The inline form ends at `>>`, so a citation that contains those two characters would otherwise stop halfway.
Put a backslash before the angle bracket:

| you write                | you get             |
| ------------------------ | ------------------- |
| `<<see s.5 \>> onward>>` | `see s.5 >> onward` |
| `<<\\>>`                 | `\`                 |

**A single `>` needs nothing.**
`<<s.5 > s.3>>` has always worked and still does: only the doubled `>>` closes a citation, so a lone one is ordinary text.

**What this costs.**
A citation can no longer end with a backslash, because `\>` now means a literal `>`; write `\\` instead.
Any other character after a backslash is left alone, so `\q` is still a backslash followed by a `q`.

This is the same idea as the `\%` and `\]` escapes in `@nlg`, but the set of characters is deliberately different.
`%` and `]` are ordinary text in a citation, and `>` is ordinary text in an `@nlg` annotation.
Each annotation escapes only what would otherwise be read as punctuation in that annotation.

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
- [Functions](../functions/README.md)
- [Operators](../operators/README.md)
