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

### Lists

A list literal is written with `LIST`, either inline or as an indented block:

```l4
LIST 1, 2, 3          -- inline, comma-separated

LIST                  -- vertical block (layout replaces the commas)
  1
  2
  3
```

**Bullet lists.** A `•` followed by a space and a same-line body opens a list
element; a block of `•` items aligned at a common column desugars to the same
list (conventionally written at the start of a line, though that's a style
convention, not an enforced rule). `•` was chosen because, unlike `-` (which
is subtraction), it has no arithmetic meaning, so it is unambiguous even in
**argument position**:

```l4
xs IS                 -- a plain list
  • 1
  • 2
  • 3                 -- == LIST 1, 2, 3

item "Parent"         -- bullet children nest under a constructor, no LIST/parens
  • item "a"
  • item "Sub"
    • item "b"        -- child '•' lines up under the parent's `item`; any
    • item "c"        --   deeper indent works too, to arbitrary depth
```

**Corner case.** Inside a vertical `LIST` block, a bare name is itself one of
the list's items, at the same column as its siblings. If a `•` block follows
immediately at that column, it binds to the name as an _argument_ rather than
becoming the next sibling item — this only matters for a name that is
arity-overloaded across a 0-arg and a list-taking definition. Wrap the name in
parens, e.g. `(reverse)`, to force it back into a standalone list item.

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

### @nonassertable

Marks a named step as closed to assertion: once node assertion ships, a request to a published rule will not be allowed to supply a value for this definition, so its truth will have to come from what it is defined as.
Today the mark is recorded and kept, and nothing reads it: a request that names the definition is treated as it is for an unmarked one.
Write it on a line of its own above a `MEANS` or `DECIDE` definition, at the top level of a file or inside a section: above the definition's `GIVEN`, or directly above the line that names it.

```l4
§ `The offence`
    GIVEN `did the act`    IS A BOOLEAN
          `had the intent` IS A BOOLEAN
          `has a defence`  IS A BOOLEAN

@nonassertable
`offence made out` MEANS `did the act` AND `had the intent` AND NOT `has a defence`
```

The mark changes nothing a rule works out, and it survives a re-print: `l4 batch` and the REPL, which re-print a module before running it, keep it.
On anything that is not a definition, above it or among its lines, it is an error that names what it sits on: a `DECLARE`, an `ASSUME`, a section heading or the `GIVEN` under it, a directive, an `IMPORT`.
On one of a definition's own `GIVEN` lines it is an error too, one per mark, naming the input on that line (or the next one, for a mark on a line of its own among them): an input is supplied, never asserted, so there is nothing there to close; a mark above the same definition still counts.
The mark takes no words: what follows it on the line is read as source and never swallowed, so prose after it is an error, often reported on the next line or inside the definition before; a definition written on the mark's line usually fails to parse, since it no longer starts at the margin, and where it does parse the mark is its.
A mark at the end of the line that names a definition, or inside its body, is a warning and carries nothing; one at the end of the `GIVETH` line is above the name line and counts; two marks above one definition are one mark and a warning.
A `@desc` whose text begins with the word `nonassertable` is a description, not the mark.
Not yet: the mark on a definition inside a `WHERE` or `LET` block, and the request-side assertion the mark closes; both are designed in `specs/todo/presumption-assertion/CONTRACT.md` and not built.

### @nlg

`@nlg` gives a definition its wording in natural language, with `%name%` slots for its inputs.

```l4
GIVEN x IS A NUMBER, y IS A NUMBER
GIVETH A NUMBER
@nlg the greater of %x% and %y%
`the greater of` x y MEANS IF x >= y THEN x ELSE y
```

See [@nlg](nlg.md).

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
Everything before the last space is the name and the last word is the URL; the name is matched ignoring case.
See [jl4/README.md](../../../jl4/README.md#how-to-use-annotations-for-citations) for an example.

**`@ref-src`** is accepted and ignored.
It used to load name-to-URL mappings from a CSV file; that was removed so that the language core needs no file access, and `@ref-map` replaces it.
A `@ref-src` that names a file which does not exist passes `l4 check`.

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

The inline form ends at `>>`, so a citation that contains those two characters
would otherwise stop halfway. Put a backslash before the angle bracket:

| you write                | you get             |
| ------------------------ | ------------------- |
| `<<see s.5 \>> onward>>` | `see s.5 >> onward` |
| `<<\\>>`                 | `\`                 |

**A single `>` needs nothing.** `<<s.5 > s.3>>` has always worked and still
does — only the doubled `>>` closes a citation, so a lone one is ordinary
text.

**What this costs.** A citation can no longer end with a backslash, because
`\>` now means a literal `>`; write `\\` instead. Any other character after a
backslash is left alone, so `\q` is still a backslash followed by a `q`.

This is the same idea as the `\%`, `\]` and `\[` escapes in `@nlg` above, but
the character set is deliberately different: `%`, `]` and `[` are ordinary
text in a citation, and `>` is ordinary text in an `@nlg` annotation. Each
annotation escapes only what would otherwise be read as punctuation in that
annotation.

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

### @infixl / @infixr / @infix

Declare the precedence and associativity of a binary infix operator, so that
unparenthesized chains of such operators group the way you declare — the same
kind of fixity declaration Haskell offers, applied to L4's identifier
operators.

```l4
@infixl 6
GIVEN p IS A SET OF a
      q IS A SET OF a
GIVETH A SET OF a
p UNION q MEANS ...

@infixl 7
p INTERSECT q MEANS ...

#EVAL a UNION b INTERSECT c    -- groups as a UNION (b INTERSECT c)
#EVAL a UNION b UNION c        -- groups as (a UNION b) UNION c
```

- `@infixl N` — left-associative, `@infixr N` — right-associative,
  `@infix N` — non-associative (chains of it always need parentheses).
- `N` is a priority from 1 (loosest) to 9 (tightest).
- The annotation goes on the line(s) above the operator's definition and only
  applies to a plain binary infix definition (`a OP b MEANS ...`); anywhere
  else it is ignored with a warning.
- **No default fixity.** An operator without a declaration cannot be chained
  without parentheses (you get the usual arity error). This is a deliberate
  divergence from Haskell's `infixl 9` default: existing programs keep their
  meaning exactly.
- Fixity travels with the operator across `IMPORT`, so a library can declare
  it once and every client gets bare chains. Conflicting imported
  declarations for the same operator are an error at the use site.
- Chaining operators of equal priority requires them to associate in the
  same direction; mixed `@infixl`/`@infixr` at one priority is an error.
- Keyword operators (`PLUS`, `AND`, ...) have their own built-in precedence
  table, and identifier operators may appear unparenthesized on either side
  of them. An identifier-operator chain **binds tighter than every keyword
  operator** — ``10 PLUS 2 `scaledby` 3`` is ``10 PLUS (2 `scaledby` 3)``,
  and ``p `resides in` "NY" OR p `resides in` "NJ"`` is a disjunction of the
  two calls. Declared priority numbers govern grouping **among**
  identifier operators only; they do not interleave with the keyword table
  (even an `@infixl 1` operator binds tighter than `TIMES`). In operand
  position (after a keyword operator) chain keywords must be on the same
  line as the operand; at the head of an expression an aligned continuation
  line is also accepted.

### An annotation L4 does not know

An `@` followed by a name this version of L4 has no annotation for is not an error.
It is ignored, together with the rest of its line, as a comment is, and L4 warns about it:

```
Unknown annotation `@exprot`: this version of L4 does not know it, so it is ignored, along with the rest of its line. Did you mean `@export`?
```

There are two ways to meet it.
One is a misspelling of a known name, and the warning says which: a rule whose `@export` is misspelt is not published, and nothing else would have told you.
The other is a file written for a newer version of L4 that has an annotation this one lacks.
That file still opens, checks and is highlighted in the older version, which reads past what it does not know.
An annotation that changes what a rule means is not applied by a version that does not know it, so the warning is the only sign that it was left out.

The annotations this version knows are `@desc`, `@export`, `@infix`, `@infixl`, `@infixr`, `@lang`, `@nlg`, `@nonassertable`, `@nonexhaustive`, `@ref`, `@ref-map` and `@ref-src`.

- **What counts as a name.** A letter, then letters, digits and underscores, with hyphens between them, as in `@ref-src`. An `@` followed by anything else, a space or a digit or a symbol, is still an error.
- **A name that begins with a known annotation's is that annotation.** `@exports default x` is `@export` followed by the text `s default x`, and `@descr` is `@desc` followed by `r`, as they always have been. They are not unknown, so they are not warned about, and the stray text is the annotation's own: `@exports` publishes nothing, because the first word of an export's text must be `export`. The lexer ignores only a name it used to refuse.
- **What it takes with it.** The rest of its line and nothing from the next line, as every line annotation does: there are no continuation lines. That holds in the middle of a line too, so `DECIDE f n IS n @oops + 1` ignores the `+ 1` along with `@oops`, and the warning says so.
- **Where it can go.** Anywhere a comment can. It is not attached to the rule below it, it does not come between a known annotation and the rule that annotation describes, and it does not interrupt a table of ditto marks `^`: the rows on either side of it still copy from each other, as they do across a comment. A known annotation between ditto rows is an error (`unexpected ^`), so a table with an unknown annotation inside it stops parsing on the first version of L4 that knows that annotation: keep annotations out of ditto tables.
- **A known annotation that lacks the form it needs is ignored too, with its own warning.** `@lang` is the only one that can: it needs a language code after a space, so a bare `@lang`, `@lang` followed by a tab, and `@lang` followed by a code with a non-ASCII letter are each ignored and warned about, instead of ending the file. Every other annotation accepts all of those forms. The module's language then stays what it would be with no `@lang` at all.
- **An `@` that is not followed by a letter is still an error.** That is not the shape of an annotation, so no annotation of any version can take it, and L4 cannot tell what the line was meant to be.
- **`l4 format` keeps the line** exactly as written, as it keeps comments.

## Directives

Directives are instructions to the tools, written at the top level of a file. `l4 run` and the editor carry them out; `l4 check` only type-checks them.

| Directive    | What it does                                                                                                     |
| ------------ | ---------------------------------------------------------------------------------------------------------------- |
| `#EVAL`      | evaluates an expression and shows the result                                                                     |
| `#EVALTRACE` | evaluates an expression and also shows the steps that led to the result (`l4 trace` draws them)                  |
| `#CHECK`     | type-checks an expression and shows its type, without evaluating it                                              |
| `#ASSERT`    | evaluates an expression and reports "assertion failed" when it is not TRUE (`#ASSERT REFUSED` expects a refusal) |
| `#TRACE`     | runs a regulative rule against a list of events (see [Regulative rules](../regulative/README.md))                |

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

### #EVALTRACE

Evaluate an expression and display the full execution trace, showing each step of the evaluation.
`AND`, `OR`, `IMPLIES` and `NOT` each appear under their own text, with the first operand and its value beneath them.
The second operand, when it was needed, is the next step, at the connective's own level, and one that was not needed does not appear.
For `both p q MEANS p AND q`, `#EVALTRACE both TRUE FALSE` shows:

```
┌ both OF TRUE, FALSE
│┌ both
│└ <function>
├ p AND q
│┌ p
│└ TRUE
├ q
└ FALSE
```

A first operand written as plain `TRUE` or `FALSE` is not shown, since its value is already in the source: `#EVALTRACE TRUE AND FALSE` is `┌ TRUE AND FALSE`, `├ FALSE`, `└ FALSE`.
`UNLESS` appears as what it means, so `p UNLESS q` shows as `p AND (NOT q)`.

**Syntax:**

```l4
#EVALTRACE expression
```

**Example:**

```l4
-- #EVALTRACE shows the steps behind an answer, not only the answer.

GIVEN age IS A NUMBER
      `is a resident` IS A BOOLEAN
GIVETH A BOOLEAN
`may apply` MEANS age >= 18 AND `is a resident`

#EVAL      `may apply` 25 TRUE
#EVALTRACE `may apply` 25 TRUE
```

Both directives give `TRUE`.
Only the `#EVALTRACE` also keeps its working, which `l4 run` prints under `Trace:` beneath the result:

```
Evaluation[2] @ evaltrace-example.l4:9:1-31

Result:
  TRUE


Trace:
  ┌ `may apply` OF 25, TRUE
  │┌ `may apply`
  │└ <function>
  ├ age AT LEAST 18 AND `is a resident`
  │┌ age AT LEAST 18
  │└ TRUE
  ├ `is a resident`
  └ TRUE
```

Read it from the top: the first line is what was asked, each line starting `├` is one step in working it out, and the last line, `└ TRUE`, is the answer.
The indented lines beside a step are the smaller questions that step had to answer first.

The `AND` line is the rule's own text, then comes its left side with the answer it gave, `age AT LEAST 18`, and then its right side, `` `is a resident` ``, which was needed because the left side was `TRUE`.
One line in it is one you did not write.
`<function>` is a rule being looked up by its name; what is found is the rule itself, which has no answer of its own until it is given its inputs.

**Seeing the trace from the command line.**

- `l4 run FILE` prints the trace of every `#EVALTRACE` in the file, under `Trace:` below its result.
  This is the default.
  To leave the traces out and see only the results, add `--trace none`.
- `l4 trace FILE` draws the same traces as diagrams instead of text.
  It prints a description of the diagram in GraphViz DOT: GraphViz is a free diagram-drawing program, and DOT is its text format.
  With `--format png` or `--format svg` and `-o DIR` it writes one picture per `#EVALTRACE` into the directory `DIR`; that needs GraphViz installed.
  See [Using the l4 CLI](../../tutorials/getting-started/l4-cli.md).

**What it does not do.**

- A plain `#EVAL` keeps no trace.
  Its `Trace:` line says so: `(no trace captured; add #EVALTRACE to the directive)`.
  That is not a fault in your file; change the `#EVAL` to `#EVALTRACE` to see the working.
- `l4 run --json` carries no trace, whatever `--trace` says.
  `--trace` changes only the text output.
- An `#EVALTRACE` inside a module that other files `IMPORT` is worked out but not shown.
  `l4 run` prints only the results of the file you gave it, yet it still collects the trace, which costs time and memory for nothing.
  Leave `#EVALTRACE` out of modules that other files import.
- A trace grows with the work done: a rule that calls itself a hundred times prints a trace of about a thousand lines.
- A trace past a fixed size is cut off, and the cut is marked with this line:
  `• "… trace truncated (exceeded maximum display size)"`
  In a test with a rule that adds 1 each time it calls itself, 600 calls printed in full and 1,000 were cut.
  The exact point depends on how big each call is.
- Lines can be very wide.
  Each level of nesting adds a character of indentation, so a rule that calls itself 1,000 times prints lines more than 2,000 characters wide.
- Keeping a trace takes memory, and nothing limits it.
  The cut-off above limits what is shown, not what is kept: a rule that called itself 100,000 times used about 1.3 GB, against 0.19 GB without the trace.
  For a large computation, run with `--trace none`.

**See also:** [evaltrace-example.l4](evaltrace-example.l4)

### #ASSERT

`#ASSERT expression` and `#ASSERT NOT expression` check that an expression is TRUE, or not.

**Outcomes.** An assertion reports one of four things: `assertion satisfied`; `assertion failed`;
`assertion could not be evaluated`, when working the expression out stopped part-way — most often because it
needed the value of a name nobody supplied; and _refused_, when the expression is one the model declines to answer (see
[REFUSE](../control-flow/REFUSE.md)). A refusal is neither satisfied nor failed, and a plain
`#ASSERT` is not the way to test for one:

```
Result:
  assertion refused:
  The model refuses to answer:
    no Regulation Crowdfunding figure exists before commencement in 2016
```

### #ASSERT REFUSED

Assert that an expression _refuses_ — that the case is one the model declines to answer, and that
declining is the expected outcome.

**Syntax:**

```l4
#ASSERT REFUSED expression
#ASSERT REFUSED expression BECAUSE "message"
```

`#ASSERT REFUSED e` passes when `e` refuses, whatever the message it carries. Adding
`BECAUSE "message"` also requires the refusal to carry exactly that message, which pins down _which_
refusal was reached when a rule has more than one.

**Example:**

```l4
#ASSERT REFUSED `funding limit for` 2015
#ASSERT REFUSED `funding limit for` 2015 BECAUSE "no Regulation Crowdfunding figure exists before commencement in 2016"
```

**Outcomes:**

```
assertion satisfied
assertion failed: expected a refusal, but the expression produced a value
assertion failed: expected the refusal "x", got "y"
```

The first is what a `#ASSERT REFUSED` reports when the expression refused and any `BECAUSE` message
matched; the second when the expression produced an ordinary value instead; the third when it
refused, but carrying a different message.

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

Definitions in different sections can share a name.
A name is looked for first along the using rule's own ancestry: its own section, then each enclosing section, then the root. The nearest declaration of it wins.
If nothing on that ancestry declares the name, every declaration of it anywhere in the file is a candidate, and one candidate resolves while two of the same kind is an error.
L4 also gives every declaration a fully qualified name, so any of them can be named explicitly. [Sections](sections.md) states the whole rule, with the table of cases and the diagnostics.

A bare name resolves whenever exactly one declaration of it is in reach, whatever section that is in.
Qualification is _required_ only where two declarations of the same kind are equally far from the rule using them, and is worth writing anyway across Parts, so a reader can see where the name comes from.
In the example above, `is an adult under subsection 2` sits inside `Subsection 3`, which declares its own `age of majority`, so reaching `Subsection 2`'s must be spelled out with `'s`.

**The section `GIVEN`.** A rule is told some facts about the case in front of it (its **"inputs"**, the names listed after `GIVEN`). A `GIVEN` indented under a section heading declares one of those names once for the whole section, instead of every rule in the section repeating it in its own `GIVEN`. See [The section `GIVEN`](section-given.md) and [section-given-example.l4](section-given-example.l4).

**Field opening.** Inside a rule whose input is a record, the record's fields can be read by their bare names: `bankrupt` for ``person's `bankrupt` ``. See [Field opening](field-opening.md) and [field-opening-example.l4](field-opening-example.l4).

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

- [@nlg](nlg.md): a definition's wording, in one language or several
- [Glossary](../GLOSSARY.md): every keyword, with links
- [Functions](../functions/README.md)
- [Operators](../operators/README.md)
