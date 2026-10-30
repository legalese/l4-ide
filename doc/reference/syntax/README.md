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

**An annotation belongs to the name it sits with, not to a type nearby.**
In `GIVEN a IS A STRING @nlg the amount` the wording is `a`'s, not `STRING`'s, and it labels `a` wherever a call lists its inputs: ``#EVAL `is large` WITH a IS "x"`` reads `… where the amount is x`.
An annotation on its own line between a `GIVETH` and its `DECIDE` belongs to the rule, not to the type written after the `GIVETH`.
A record field works the same way: in `HAS dob IS A DATE @nlg date of birth` the wording is `dob`'s, as it would be under the field.

**An empty `@nlg` is ignored, and says so.**
A rendering replaces what it annotates, so `@nlg` with nothing after it would erase the name from the output rather than leave it alone.
L4 drops it and warns instead.

**Two wordings in one language on one field collide.**
`head [the first item] IS AN a [an element]` gives `head` two wordings, one before its type and one after it, so L4 warns and uses neither, as it does for two on an input.

**A field list is an exception to "own line describes what follows".**
Underneath a field, an annotation describes _that_ field, the one above it, not the next one:

```l4
DECLARE Employee
  HAS dob  IS A DATE
      -- describes `dob`
      @nlg date of birth
      `start date` IS A DATE
```

A field list is a column of things rather than a sequence of declarations, and writing the gloss under the field it belongs to is what authors do.

**A field's wording is read after the name of its owner.**
A rule that reads `e's dob`, for an input `e` that is an `Employee`, says "the employee's date of birth": the record type's name, then `'s`, then the field's wording.
So a field's wording is only the words that follow the owner.
`@nlg the employee's date of birth` under `dob` would read "the employee's the employee's date of birth" wherever the field is used.

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
After an enum whose last value has no fields, an annotation at the margin is read as that value's: nothing is reported unless the value already carries a note, and the rule written below it loses the annotation.
Write the rule's sentence trailing the rule's head instead, as in ``DECIDE `passes` @nlg the test is passed``.

#### Writing a literal `%` or `]`

Inside `@nlg`, `%` marks an input to fill in, and `%age%` is replaced by the value of `age`.
A `]` ends a bracketed annotation.
To write either character as itself, put a backslash in front of it.

| you write               | you get             | without the backslash          |
| ----------------------- | ------------------- | ------------------------------ |
| `10\%and\%20`           | `10%and%20`         | `and` is read as an input name |
| `[rate \] per unit]`    | `rate ] per unit`   | the annotation ends early      |
| `[see note \[3\] here]` | `see note [3] here` | —                              |
| `\\`                    | `\`                 | —                              |

**Most of the time you do not need this.**
A percent sign with a space after it is ordinary text, so `a 5% levy on %amount%` works as written and fills in `amount`.
The backslash is for the case with no space, such as `10%and%20`, where L4 cannot tell a written-out range from an input.

**The two mistakes fail very differently, and the quiet one is the one to watch.**
A stray `]` ends the annotation early and you get a parse error pointing at the leftover text, which is annoying but tells you.
A stray `%` pair with no spaces inside it tells you nothing.
If the word between the two percent signs happens to name one of your inputs, L4 quietly substitutes that value, and your sentence comes out with a number where you wrote a word.
Nothing is reported, and the rule runs.

**A pair with spaces inside it, such as `% amount %`, is plain text, and L4 warns.**
A slot is `%amount%` with no spaces, so `% amount %` prints as plain text and the slot is lost.
`l4 check` succeeds, and the warning names the pair and the slot to write instead.
In `5% with %amount%` the second percent sign opens the slot `%amount%`, so L4 does not warn.

**An opening `[` never needs escaping, and you may escape it anyway.**
A closing `]` ends the annotation unless it is written `\]`, so `[see note [3\] here]` is correct as written, and so is `[see note \[3\] here]`.
`\[` means a literal `[`, exactly as the bare character does, so the two spellings come out the same.

**To end an annotation with a backslash, write `\\`.**
A backslash immediately before the closing `]` is an escape, so `\]` is a literal `]` and the annotation goes on.
Any other character after a backslash is left completely alone: `\q` is a backslash followed by a `q`.

#### Labelling the language: `@nlg:he`

An `@nlg` annotation can say which language its prose is in, by putting a language subtag straight after `@nlg`:

```l4
GIVEN amount IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is large` @nlg:en the amount %amount% is large
  IF amount GREATER THAN 100
```

**L4 has no idea what language you are writing in.**
The renderer prints whatever the annotation says, so an annotation written in Hebrew produces Hebrew output, with or without a tag.
The tag does not translate anything.
What it does is let you attach _more than one_ rendering to the same rule and say which is which.

**The bare inline form cannot be tagged.**
`[…]` has nowhere to put a subtag, so `@nlg:he` is available only on the `@nlg` form.

**A word glued to the colon is a tag, and a colon with a space after it is ordinary text.**
A subtag is letters, digits and hyphens, so `@nlg:he` and `@nlg:zh-Hant` are tags, while `@nlg: see below` has no tag and the colon is simply the first character of the prose.
So `@nlg:total of the first` has the tag `total` and the prose `of the first`, and `@nlg:Test` on its own is a tag with no prose, which is ignored with a warning.
L4 does not check that a tag names a real language: an English sentence that begins with a colon-joined word, as in `@nlg:the employee pays`, takes `the` for its tag, and the sentence reads `employee pays`.
So L4 warns when a rule, input or field has only one wording and nothing in the module backs its tag as a language.
A tag is backed when:

- a `@lang` line declares it;
- some rule, input or field has a wording in it beside a wording in another language; or
- it is `en`, `he` or a language a `@lang` line declares, with nothing after it but a script or a region: `en-GB`, `he-IL`, `zh-Hant`, and `pt-BR` in a module that declares `@lang pt`. `en` and `he` count in any case.

So `@nlg:en-route for %days% days` draws the warning, because `route` is neither a script nor a region, and so does a word used as the tag of several rules when none of them has another wording.
If the tag was the first word of the sentence, drop the colon, and if you want the colon as text, leave a space after it.

#### Writing the same rule in two languages

Put the second rendering on the continuation line, under the first:

```l4
GIVEN amount IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is large` @nlg:en the amount %amount% is large
                  @nlg:he %amount% עולה על הסף
  IF amount GREATER THAN 100
```

Then ask for one:

```console
$ l4 nlg --lang he mymodule.l4
$ l4 render --format html --lang he mymodule.l4 -o mymodule.he.html
```

`l4 nlg` gives the file's directives as plain prose; `l4 render` gives the formatted document, in any of its formats.
Both take `--lang`, and so does the Render tab of the VS Code extension, which shows a language menu beside its imports menu when the file has wordings in more than one language.

**A request reads a wording in its language, whatever region either names.**
`--lang he` reads a wording tagged `he-IL` when the rule has none tagged `he`, and `--lang he-IL` reads one tagged `he`.
A wording tagged exactly as asked comes first, then one whose tag the request extends (`he` for `he-IL`), then any other in the same language.
The language is compared as written, so `HE` is not `he`.
Two runs of the same command over the same source produce the two documents, and nothing about the rule is duplicated, only its wording.

In both, a call to a rule that has an `@nlg` wording reads as that wording with the call's arguments in its `%slots%`: ``#EVAL `is large` 150`` reads as `the amount 150 is large`.
An argument the wording does not mention is not dropped; it follows the sentence as `with …`, so a wording written without slots shows every value the call supplied.
A wording written on the `GIVEN` name is a gloss for that input, not a sentence for the rule, and is never used for the rule.

`l4 nlg` also writes a date given as literals as a date: `Date 16 7 2025` reads `16 July 2025`.
That covers only daydate's own `Date`, only when all three arguments are whole numbers, and only when they name a real day.
Anything else stays a call, so `Date 31 2 2025`, which rolls forward to March, reads as `` `Date` with 31, 2 and 2025 `` and not as a day that is not in the text.
A percentage reads `50%`.

**The words L4 itself puts around your sentences follow `--lang` in `l4 nlg`:** "is equal to", "not", "with", a month's name.
For ``#EVAL `is large` 150 EQUALS TRUE`` over the rule above, `l4 nlg --lang he` prints ``150 עולה על הסף שווה ל־`TRUE` `` where `l4 nlg` prints ``the amount 150 is large is equal to `TRUE` ``.
They come from a table of phrases, not a grammar, so the English word order stays: a Hebrew line is Hebrew words in the order English would put them.
A word the table has no entry for stays English, and `l4 nlg` names it on stderr, so you can see what was not translated.
The table is small and fixed, and it gives each connecting word one rendering whatever the sentence around it, so have a Hebrew speaker read the Hebrew output before you rely on it.
Hebrew is the one language with a table, and it serves every Hebrew tag, `he-IL` as well as `he`.
For every other language, `--lang` selects your own wordings and leaves L4's own connecting words in English.
`l4 render` does not use the table.
Without `--lang`, the connecting words are English.

In the `html` format the document says which language it is in: `<html lang="he" dir="rtl">`.
`lang` is the `--lang` you asked for, or the module's `@lang` if you asked for nothing, or `en`.
`dir="rtl"` is added for a right-to-left language, decided from the script subtag when the tag carries one, so `he-Latn` is left-to-right and `az-Arab` is not, and omitted for every other, left-to-right being HTML's own default.
Asking for a language **nothing** in the module renders does not relabel the document: it keeps the language it declares, and `render` says so on stderr.
The `akn` format reports the same choice as the language component of its FRBR URIs (`/akn/doc/main/heb@`).
The `--lang` value is checked, because it ends up in markup: a trailing space is trimmed, the first subtag is lowercased, and anything that is not a language tag is refused.

**A rule with no rendering in the language you ask for appears in its default one.**
`--lang he` falls back to a rule's default rendering when it has no Hebrew one, so a half-finished translation produces a whole document with some of it in the original language, rather than a document with holes in it.

**Which rendering is the default**, the one you get with no `--lang` at all, is the one in the module's own language (`en` unless the module says otherwise), and otherwise the first in the file.
A rule with exactly one annotation has only that rendering, tagged or not, and every `--lang` gets it.

**Two renderings in the same language are a warning, and neither is used.**
Two `@nlg:he` on one rule, or two untagged ones, are a genuine ambiguity.
`l4 check` succeeds, but L4 warns, names both wordings, and attaches neither, because picking one would silently throw away a sentence you wrote.
The rule is then read by its name, with its arguments after it.
A clash in one language does not affect the others: two `@nlg:he` and one `@nlg:en` leave the English rendering working.

#### Declaring the module's language: `@lang he`

Tagging every `@nlg` gets repetitive the moment a whole module is in one language.
Say it once instead, on a line of its own:

```l4
@lang he

GIVEN amount IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is large` @nlg %amount% עולה על הסף
                  @nlg:en the claim of %amount% exceeds the threshold
  IF amount GREATER THAN 100
```

**`@lang he` means "every untagged `@nlg` in this module is Hebrew".**
It is not a separate mechanism with its own precedence: it is exactly equivalent to writing `:he` on each of those `@nlg` annotations, and you can mix the two freely.
An `@nlg` that names its own language keeps it, which is how the English rendering above survives in a Hebrew module.

**`@lang` does not translate anything.**
It labels what you wrote.

**A module that declares nothing is `en`.**
That is a default, not a detection: L4 cannot tell what language you are writing in, so a Hebrew module with no `@lang` is _labelled_ English while it _renders_ Hebrew.
The label has a visible cost: `l4 render --format html` puts it in `<html lang="en">` and emits no `dir`, so the Hebrew renders left-to-right with its punctuation at the wrong end of the line, and `--format akn` identifies the document as an English expression.
So declare it if your module is not English.

**Do not write `@lang en`: it says what every module without a declaration is.**
`l4 check` and your editor put a hint on the line: "A module that declares nothing is English; this line can go."
It is only a hint: `l4 check` succeeds with the line or without it.
A module that also declares another language gets no hint, and neither does a tag other than `en`.

**A module declares one language.**
If two `@lang` lines name different languages, L4 uses the last one in the file and warns on each of the others.
The warning names both languages and the line that is used, and the earlier line has no effect.
Two `@lang` lines that name the same language are not reported.

**It applies to the whole file, wherever you write it**, including annotations above the declaration.
Convention is the top; nothing breaks if it is not.

**Two renderings in the module's own language collide.**
`@lang he` together with an explicit `@nlg:he` on the same rule is two Hebrew renderings, and is reported as such.

#### A rule that names its inputs in the head

A rule may name its inputs twice, once in the `GIVEN` and again in the head, and an annotation written after an input's name in the head lands on that INPUT rather than on the rule.
It is read as the rule's sentence anyway:

```l4
GIVEN amount IS A NUMBER
GIVETH A BOOLEAN
`is large` amount @nlg the claim of %amount% is large
  MEANS amount GREATER THAN 100
```

reads as ``the claim of `amount` is large`` at every call site, in `l4 nlg` and in `l4 render` alike.
A call written with `WITH` keeps its `where` clause and takes the sentence as its heading.
A rule whose own name carries an annotation keeps that one, and the one on the input stays the input's gloss.

**An annotation on an `AKA` name is the rule's sentence too**, and a call through the alias reads it.

**An annotation in the `GIVEN` is an input gloss, never the rule's sentence.**
It labels the input in a `WITH` call's `where` clause.
When the rule's head names the input too, as in `` `is large` amount MEANS … ``, L4 takes the input from the head, so a gloss written in the `GIVEN` of that rule labels nothing.
Put a sentence for the rule on the rule, and a gloss for an input in the `GIVEN` of a head that does not repeat it.

**Two annotations in the same language on one input collide**: L4 warns, naming the input, and uses neither.
`l4 nlg` and `l4 render` then read the input under its own name, and the rule as they would read it with no annotations.

Where a wording sits decides whose it is:

| where you write it                                                                                                     | whose wording it is                                                  |
| ---------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| trailing the rule's name: ``DECIDE `is large` @nlg …`` or `` `is large` @nlg … MEANS ``                                | the rule's sentence                                                  |
| on its own line above the head                                                                                         | the rule's sentence                                                  |
| after an input named in the head: `` `is large` amount @nlg … MEANS ``                                                 | the rule's sentence                                                  |
| on its own line below an input, or below an `AKA`, in the head                                                         | the rule's sentence                                                  |
| in the `GIVEN`, trailing an input's name or on its own line indented under it, when the head does not repeat the input | that input's gloss                                                   |
| above the head and also after an input in the head                                                                     | the one above is the rule's sentence; the other is the input's gloss |

Each of the rule's-sentence placements reads the same in `l4 nlg` and in `l4 render`.

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
`<<s.5 > s.3>>` is one citation: only the doubled `>>` closes it, so a lone `>` is ordinary text.

**To end a citation with a backslash, write `\\`.**
A backslash immediately before `>>` is an escape, so `\>` is a literal `>` and the citation goes on.
Any other character after a backslash is left alone, so `\q` is a backslash followed by a `q`.

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
A function written as [several clauses](../functions/DECIDE.md#several-clauses) needs a `GIVEN` to be exported, and a function-typed input cannot be exported ([ASSUME](../types/ASSUME.md#function-typed-inputs-are-not-supported-yet-for-export)).
How to deploy: [Deploy your rules](../../tutorials/deploying-rules/exporting-rules-for-deployment.md).

**Example:** [annotation-example.l4](annotation-example.l4)

## Directives

Directives are instructions to the tools, written at the top level of a file. `l4 run` and the editor carry them out; `l4 check` only type-checks them.

| Directive    | What it does                                                                                      |
| ------------ | ------------------------------------------------------------------------------------------------- |
| `#EVAL`      | evaluates an expression and shows the result                                                      |
| `#EVALTRACE` | evaluates an expression and also shows the steps that led to the result (`l4 trace` draws them)   |
| `#CHECK`     | type-checks an expression and shows its type, without evaluating it                               |
| `#ASSERT`    | evaluates an expression and reports whether it is TRUE ([what it reports](#what-assert-reports))  |
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

### What `#ASSERT` reports

An `#ASSERT` has one of three outcomes:

| When the expression…                                                                                         | It prints                                          | The editor shows          | `l4 run` exit code | In `l4 run --json`                               |
| ------------------------------------------------------------------------------------------------------------ | -------------------------------------------------- | ------------------------- | ------------------ | ------------------------------------------------ |
| is TRUE                                                                                                      | `assertion satisfied`                              | information               | not affected       | `"value": true`                                  |
| is FALSE                                                                                                     | `assertion failed`                                 | an error                  | not affected       | `"value": false`                                 |
| cannot be evaluated: a division by zero, a `CONSIDER` with no matching branch, a term that is only `ASSUME`d | `assertion could not be evaluated:` and the reason | an error, with the reason | non-zero           | `"value": null`, with the reason under `"error"` |

In `--json` the result's `"kind"` is `"assertion"` in all three.

An assertion that cannot be evaluated is not a verdict, so `#ASSERT P` and `#ASSERT NOT P` then report the same thing. Asserting an `ASSUME`d `BOOLEAN` directly, as in `#ASSERT b`, is one such case: `b` has no value to check.
[Testing your rules](../../tutorials/getting-started/testing-your-rules.md#what-an-error-looks-like) shows an example.

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
