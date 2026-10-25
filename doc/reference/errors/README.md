# Error messages

This page lists the messages L4 gives when a file does not parse, does not type-check or stops while it runs, and the warnings it gives about code that probably does not do what you meant. Each entry quotes the message, says what causes it and how to fix it. Search the page for a phrase from your message.

- An **error** stops the file: it is not checked further, and its `#EVAL` lines do not run.
- A **warning** does not stop anything. The file still runs, but the code it points at is likely to be wrong.
- A parse error shows the line and the column where L4 stopped reading, then `unexpected ...` and a list of what it expected. The mistake is often just before that point.

Coming from another language? The [Cheat sheet](../cheat-sheet.md) shows the L4 spelling of familiar constructs. The tutorial [Fix errors](../../tutorials/getting-started/debugging-type-errors.md) walks through the errors beginners meet most.

## Entries

**Layout and syntax**

- [Incorrect indentation](#incorrect-indentation)
- [IF without ELSE](#if-without-else)
- [Arguments on the lines below a function](#arguments-on-the-lines-below-a-function)
- [Field access as an argument](#field-access-as-an-argument)
- [Double equals sign](#double-equals-sign)
- [Curly quotes and dashes from a word processor](#curly-quotes-and-dashes-from-a-word-processor)
- [GIVEN at column 1 meant for the section](#given-at-column-1-meant-for-the-section)
- [NOT followed by AND, OR or IMPLIES on one line](#not-followed-by-and-or-or-implies-on-one-line)

**Types**

- [Pipes in sum types](#pipes-in-sum-types)
- [Bare positional payload in sum types](#bare-positional-payload-in-sum-types)
- [Branch type mismatch](#branch-type-mismatch)
- [Wrong number of inputs](#wrong-number-of-inputs)
- [Input of the wrong type](#input-of-the-wrong-type)
- [Several definitions with the same name](#several-definitions-with-the-same-name)

**Names and imports**

- [I could not find a definition for the identifier](#i-could-not-find-a-definition-for-the-identifier)
- [Module not found](#module-not-found)
- [I could not find a module at this path](#i-could-not-find-a-module-at-this-path)
- [This import leaves the root of this deployment](#this-import-leaves-the-root-of-this-deployment)
- [This import is relative, but has no directory to be relative to](#this-import-is-relative-but-has-no-directory-to-be-relative-to)
- [IMPORT resolved to a module with a shorter name](#import-resolved-to-a-module-with-a-shorter-name)

**Definitions and clauses**

- [A clause written like a rule with a word between its inputs](#a-clause-written-like-a-rule-with-a-word-between-its-inputs)
- [Clauses with more or fewer patterns than the GIVEN names](#clauses-with-more-or-fewer-patterns-than-the-given-names)
- [Multi-clause DECIDE does not cover all cases](#multi-clause-decide-does-not-cover-all-cases)
- [Clause that is never used](#clause-that-is-never-used)
- [Annotation above a later clause](#annotation-above-a-later-clause)
- [A definition after clauses that is not another clause](#a-definition-after-clauses-that-is-not-another-clause)
- [Unknown annotation](#unknown-annotation)
- [Malformed annotation](#malformed-annotation)
- [Infinite loop detected](#infinite-loop-detected)

**Assumed terms and refusals**

- [ASSUME is being retired](#assume-is-being-retired)
- [Needed the value of an assumed term](#needed-the-value-of-an-assumed-term)
- [Refusal reported instead of a result](#refusal-reported-instead-of-a-result)

**Pattern matching**

- [Non-exhaustive pattern match](#non-exhaustive-pattern-match)
- [Redundant pattern match branch](#redundant-pattern-match-branch)
- [Non-exhaustive patterns at runtime](#non-exhaustive-patterns-at-runtime)

**Regulative rules**

- [#EVAL shows the rule instead of an outcome](#eval-shows-the-rule-instead-of-an-outcome)

**Export**

- [An @export input that is a rule, not a value](#an-export-input-that-is-a-rule-not-a-value)
- [An @export of clauses with no GIVEN](#an-export-of-clauses-with-no-given)

---

## Layout and syntax

L4 is layout-sensitive, like Python: indentation decides what belongs to what. Use spaces, not tabs, and indent a continuation line further than the line it continues.

### Incorrect indentation

**Error:** `incorrect indentation (got 5, should be greater than 9)`

The line named is not indented far enough for the place it is in. Two common causes:

**The body of a definition starts left of the definition.**

```l4
GIVEN x IS A NUMBER
      y IS A NUMBER
GIVETH A NUMBER
        result x y MEANS
    x + y
```

Indent the body further than the line that defines the name:

```l4
GIVEN x IS A NUMBER
      y IS A NUMBER
GIVETH A NUMBER
result x y MEANS
    x + y
```

**A chain of `ELSE IF` lined up under the first `IF`.**

```l4
GIVEN a IS A BOOLEAN
      b IS A BOOLEAN
      c IS A BOOLEAN
GIVETH A NUMBER
result a b c MEANS
    IF a THEN 1
    ELSE IF b THEN 2
    ELSE IF c THEN 3
    ELSE 4
```

Each `IF` after an `ELSE` starts a new expression that must be indented further than the one before. Use `BRANCH` for a list of conditions instead:

```l4
GIVEN a IS A BOOLEAN
      b IS A BOOLEAN
      c IS A BOOLEAN
GIVETH A NUMBER
result a b c MEANS
    BRANCH
        IF a THEN 1
        IF b THEN 2
        IF c THEN 3
        OTHERWISE 4
```

BRANCH takes the first condition that is TRUE, and OTHERWISE covers the rest. See [BRANCH](../control-flow/BRANCH.md).

---

### IF without ELSE

**Error:** `unexpected ...` followed by `expecting %, ELSE, or space token` (at the end of a file, `unexpected end of input`)

```l4
GIVEN condition IS A BOOLEAN
GIVETH A NUMBER
result condition MEANS IF condition THEN 1
```

IF is an expression: it has to give a value whether the condition is TRUE or FALSE, so the ELSE is required.

**How to fix it:** Add the ELSE:

```l4
GIVEN condition IS A BOOLEAN
GIVETH A NUMBER
result condition MEANS IF condition THEN 1 ELSE 0
```

---

### Arguments on the lines below a function

**Error:** `unexpected 100` (the first argument), followed by a list of what was expected

```l4
GIVEN a IS A NUMBER
      b IS A NUMBER
      c IS A NUMBER
GIVETH A NUMBER
triple a b c MEANS a + b + c

r MEANS triple
    100
    200
    300
```

Arguments written on their own lines below a function name are not read as its arguments.

**How to fix it:** Write the arguments on the same line, or use `OF` with commas:

```l4
GIVEN a IS A NUMBER
      b IS A NUMBER
      c IS A NUMBER
GIVETH A NUMBER
triple a b c MEANS a + b + c

r MEANS triple OF 100, 200, 300
s MEANS triple 100 200 300
```

---

### Field access as an argument

**Error:** `unexpected 's`

```l4
IMPORT prelude

DECLARE Person HAS age IS A NUMBER
DECLARE Charity HAS governors IS A LIST OF Person

GIVEN charity IS A Charity
GIVETH A BOOLEAN
`all governors are adults` charity MEANS
  all (GIVEN g YIELD g's age >= 18) charity's governors
```

When a field access such as `charity's governors` is an argument to a function, L4 cannot tell where the argument ends.

**How to fix it:** Put the field access in parentheses:

```l4
IMPORT prelude

DECLARE Person HAS age IS A NUMBER
DECLARE Charity HAS governors IS A LIST OF Person

GIVEN charity IS A Charity
GIVETH A BOOLEAN
`all governors are adults` charity MEANS
  all (GIVEN g YIELD g's age >= 18) (charity's governors)
```

---

### Double equals sign

**Error:** `unexpected ==`

```l4
GIVEN x IS A NUMBER
GIVETH A BOOLEAN
result x MEANS x == 5
```

L4 writes equality with a single `=`, or `EQUALS`. There is no assignment in L4, so `=` is never ambiguous.

**How to fix it:**

```l4
GIVEN x IS A NUMBER
GIVETH A BOOLEAN
result x MEANS x = 5
```

---

### Curly quotes and dashes from a word processor

**Error:** ``This is ’ (Right Single Quotation Mark, U+2019). It looks like `'`, but L4 only understands the plain one.`` (or the same for another curly quote, dash or ellipsis)

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

### GIVEN at column 1 meant for the section

**Error:**

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

**Error:**

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

Or move the `AND` to its own line. Over several lines nothing is refused, and the columns decide: an `AND` that starts in the same column as the `NOT`, or further left, stops the `NOT`; one that starts further right is reached over. `x AND NOT y` on one line is always fine, because the `NOT` is last and there is nothing after it to reach over. Comparisons are not refused either: `NOT n EQUALS 0` has only one sensible reading. See [How Far Does NOT Reach?](../operators/logical.md#how-far-does-not-reach).

---

## Types

### Pipes in sum types

**Error:** `expecting operator char`, pointing at the first `|`

```l4
DECLARE Colour IS ONE OF
    Red | Green | Blue
```

L4 does not separate the alternatives of a type with `|`.

**How to fix it:** Use commas, or one alternative per line:

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

DECLARE Shape IS ONE OF
    Circle HAS radius IS A NUMBER
    Square HAS side IS A NUMBER
```

See [DECLARE](../types/DECLARE.md).

---

### Bare positional payload in sum types

**Error:** `unexpected NUMBER` followed by `expecting ,, ;, HAS, end of input, or space token`

```l4
DECLARE Shape IS ONE OF
    Circle NUMBER
```

An alternative that carries data names each field with `HAS`. L4 has no unnamed fields.

**How to fix it:** Name the field:

```l4
DECLARE Shape IS ONE OF
    Circle HAS radius IS A NUMBER
```

---

### Branch type mismatch

**Error:** `Both the THEN and the ELSE branch of an IF-THEN-ELSE and BRANCH-IF-THEN-OTHERWISE constructs must have the same type.`, followed by the type expected and the type found

```l4
GIVEN x IS A NUMBER
GIVETH A STRING
result x MEANS
    BRANCH
        IF x < 0 THEN "negative"
        IF x = 0 THEN 0
        OTHERWISE "positive"
```

Every branch of an IF, a BRANCH or a CONSIDER must give a value of the same type. Here two give a STRING and one a NUMBER.

**How to fix it:**

```l4
GIVEN x IS A NUMBER
GIVETH A STRING
result x MEANS
    BRANCH
        IF x < 0 THEN "negative"
        IF x = 0 THEN "zero"
        OTHERWISE "positive"
```

---

### Wrong number of inputs

**Error:** `The function add (defined at ...) expects 2 inputs, but here it is given 3 inputs.`

A call gives a function more or fewer inputs than its `GIVEN` names.

**How to fix it:** Check the function's `GIVEN` and give one input for each name, in the same order. If you meant to give fewer (partial application), make sure the context supports it:

```l4
GIVEN a IS A NUMBER
      b IS A NUMBER
GIVETH A NUMBER
add a b MEANS a + b

#EVAL add 1 2
```

---

### Input of the wrong type

**Error:** `The first input of function append (defined at ...) is expected to be of type LIST OF a but is here of type STRING`

A function was given a value of a type it does not take. A common case is mixing up two prelude functions with similar names:

| Function | Written            | Works on | Example                          |
| -------- | ------------------ | -------- | -------------------------------- |
| `APPEND` | between its inputs | STRING   | `"hello" APPEND " world"`        |
| `append` | before its inputs  | LIST     | `append (LIST 1, 2) (LIST 3, 4)` |

**How to fix it:** Use the function for the type you have. `CONCAT` also joins strings, and needs no import:

```l4
IMPORT prelude

DECIDE greeting IS "hello" APPEND " world"
DECIDE numbers IS append (LIST 1, 2) (LIST 3, 4)
DECIDE `the same greeting` IS CONCAT "hello", " world"
```

---

### Several definitions with the same name

**Error:** `There are multiple definitions for the identifier Date and I do not have sufficient information to make a choice between them.`, followed by the candidates and their types

Some names have several definitions told apart by their types, such as `Date` and `Time` in the date and time libraries. When L4 cannot tell from the context which one is meant, it asks. This often happens when such a call is followed by a word written between two inputs, as in ``Date 10 1 2024 `is before` Date 11 1 2024``.

**How to fix it:** Put each call in parentheses, or say the expected type with `GIVETH`:

```l4
IMPORT daydate

#EVAL (Date 10 1 2024) `is before` (Date 11 1 2024)
```

---

## Names and imports

### I could not find a definition for the identifier

**Error:** `I could not find a definition for the identifier`, then the name, then `which I have inferred to be of type:` and the type L4 expected it to have

L4 met a name that nothing in scope defines. The usual causes:

- **A library is not imported.** `map`, `filter`, `all`, `any`, `sum`, `fromMaybe` and `APPEND` come from the prelude, which is never loaded automatically. Add `IMPORT prelude`. The same goes for `Date` (`IMPORT daydate`) and the other [standard libraries](../libraries/README.md).
- **A typo or a different spelling**, in a function name or a field name: `person's fullname` where the record declares `full name`. The type L4 shows helps: for a field it is `FUNCTION FROM Person TO ...`.
- **The wrong case.** Keywords and built-in values are upper case: `TRUE` and `FALSE`, not `True` or `true`; `NOTHING`, `JUST`, `LEFT`, `RIGHT`.
- **An `IMPORT` below a section heading.** `IMPORT` lines count only before the first `§`; one placed after it is ignored, so the names it should bring in are not defined. Move it to the top of the file.
- **A name defined somewhere it cannot be seen.** A name defined in the `WHERE` or `LET` of one definition exists only inside that definition.

**How to fix it:** Correct the spelling, or add the `IMPORT`:

```l4
IMPORT prelude

DECIDE total IS sum (LIST 1, 2, 3)
DECIDE `is ready` IS TRUE
```

---

### Module not found

**Error:** `I could not find a module with this name: helpers`, then `Nothing it defines is in scope here; names you expected from it are reported as undefined.`, then `I have tried the following locations:` and the places that were tried, once each, in the order L4 looks. The standard library built into `l4` is listed at its own place, for example `the stdlib embedded in this binary (22 modules, not among them)`, or `the stdlib embedded in this binary (skipped: JL4_LIBRARY_PATH is set)` when that variable is set. On the command line, `l4` also prints `Warning | [Import Resolution] Module not found: helpers`.

This is an error, not a warning: it fails `l4 check` and `l4 run` even when nothing in your file reads anything from the missing module. Other commands, `l4 render`, `l4 nlg` and the transpilers among them, print the same error and still exit 0; [When nothing resolves](../libraries/resolution.md#which-commands-fail-on-it) has the measured list.

An `IMPORT` names a module that is neither a standard library nor a file `helpers.l4` in your project's root folder or beside the importing file.

**How to fix it:**

- Check the name. This is usually not the first error on screen: a failed import also produces one "I could not find a definition for the identifier" per name it was meant to supply, so read the top of the output. A name with a hyphen needs backticks: ``IMPORT `legal-persons` ``. To import a file from another folder, write its path in backticks, with a slash: ``IMPORT `../shared/helpers` ``; that is a different error, [I could not find a module at this path](#i-could-not-find-a-module-at-this-path).
- Put your own module in the project's root folder or beside the file that imports it.
- If `JL4_LIBRARY_PATH` is set, the built-in standard library is not used at all, so that folder must hold every library you import, `prelude.l4` included.

[IMPORT](../libraries/README.md#import) describes module names and where they are found; [How IMPORT finds libraries](../libraries/resolution.md) gives the full search order for operators and library developers.

---

### I could not find a module at this path

**Error:** `I could not find a module at this path: ../shared/helpers`, then `Nothing it defines is in scope here; names you expected from it are reported as undefined.`, then `Relative to <the importing file> that is <the path that was looked for>, which does not exist.`

Like [Module not found](#module-not-found), this is an error, not a warning, and it fails `l4 check` and `l4 run` even when nothing in your file reads anything from the missing module.

An `IMPORT` with a slash in its name names one file, relative to the file that writes the `IMPORT`. The third line shows where that came out once `.` and `..` were worked through, which is the place to look.

**How to fix it:**

- Compare the third line with where the file really is. The path starts from the folder of the file that writes the `IMPORT`, not from the folder you ran `l4` in.
- Leave off `.l4`, or keep it; both name the same file. Use `/` and not `\`.
- In a deployment, the file must be among the files uploaded: a path import cannot reach a file that was not deployed with the rest.

[Importing a file from another folder](../libraries/README.md#importing-a-file-from-another-folder) describes path imports; [Path imports](../libraries/resolution.md#path-imports) says exactly how one is resolved.

---

### This import leaves the root of this deployment

**Error:** `This import leaves the root of this deployment: ../../x`. Two forms of it:

- A path that climbs out of the files that were uploaded, in `jl4-service` or Legalese Cloud. The second line shows where the path would have landed.
- A path that starts with `/`, on any machine. A leading slash is reserved for a form L4 does not have yet, and is refused rather than guessed at.

A service that runs files somebody else uploaded does not read its own disk for them, so a path import there can reach other uploaded files and nothing else. On your own machine, `l4` lets a path leave the folder you started in.

**How to fix it:**

- Deploy the file the path points at together with the rest, and write the path so that it stays inside the deployed files.
- If the path starts with `/`, write it relative to the importing file instead: ``IMPORT `../shared/helpers` ``.

---

### This import is relative, but has no directory to be relative to

**Error:** `This import is relative, but <the document> has no directory to be relative to.`, then `Write a bare module name, or supply the file through the editor's project files.`

A path import starts from the folder of the file that writes it. A document that does not live in a folder, such as one typed into the browser editor, has none to start from.

**How to fix it:** write a bare module name, which is looked up by the [usual order](../libraries/resolution.md#the-resolution-order), or open the file from disk so that it has a folder.

---

### IMPORT resolved to a module with a shorter name

**Warning:** ``IMPORT `a.b` resolved to module `a`; write `IMPORT a` `` (and the same for ``IMPORT `foo.l4` ``, which resolves to `foo`).

A module is named by its file name without `.l4`, and a name with a dot or an extension is cut at its last dot. So ``IMPORT `a.b` `` has always loaded `a.l4`, not a file called `a.b`, and ``IMPORT `v1.2-rates` `` has always loaded `v1.l4`. This was silent; now it is a warning, and nothing about which module is loaded has changed. It does not fail `l4 check`.

The same cut explains a [Module not found](#module-not-found) for a name shorter than the one you wrote: ``IMPORT `v1.2-rates` `` that fails with `I could not find a module with this name: v1` was looking for `v1.l4`.

**How to fix it:** write the name the warning suggests. If the file's real name has a dot in it, import it by path, which keeps the dot: ``IMPORT `./v1.2-rates` `` loads `v1.2-rates.l4` from the importing file's own folder. If you meant a file in another folder, write its path: ``IMPORT `sub/a` ``.

---

## Definitions and clauses

### A clause written like a rule with a word between its inputs

**Error:**

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
DECLARE Colour IS ONE OF Red, Green, Blue

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
DECLARE Colour IS ONE OF Red, Green, Blue

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
A use of the word inside another rule is still read as a use of the mixfix rule: with ``a `plus` b`` in the file, the body `total plus y` of a rule whose inputs are `plus` and `y` is read as ``total `plus` y``, and fails to check ("The first input of function `plus` is expected to be of type NUMBER but is here of type FUNCTION FROM NUMBER AND NUMBER TO NUMBER").
Give that input another name, and the body means what it says.

---

### Clauses with more or fewer patterns than the GIVEN names

**Error:**

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

### Multi-clause DECIDE does not cover all cases

**Warning:**

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

**What the check reads.** Rules whose clauses match enumeration values or `TRUE`/`FALSE` are checked, and so are rules whose clauses match particular numbers or texts.

A number or a piece of text in a clause matches one value of its input, and there is no end of the other values.
So a rule whose clauses match particular numbers or texts is complete only with a clause written with the input's name, and the warning suggests that clause:

```l4
GIVEN n IS A NUMBER
GIVETH A STRING
DECIDE describe 0 IS "zero"
DECIDE describe 1 IS "one"
```

```
This multi-clause definition does not cover all cases. The following clauses are still needed:

  DECIDE `describe` n IS
```

The other inputs of the same rule are still analysed: a table keyed by a number and a `Tier` that has no clause for `Gold` is told so, for the keyed rows first, in the order the clauses first name the keys, and then for every other number.
The same goes for a number or a piece of text nested inside a pattern, as in `(JUST 1)` or `(Box 0)`: the clause for the other values is suggested with `` `_` `` in that place.
A suggested number is written as the first clause that names it spells it (`1.50`, `1_000`, every digit of `0.1234567890123456789`), and a suggested piece of text as L4 writes it, every printable character as it is (`"São Paulo"`) and a character that does not print escaped (`"tab\there"`).
An input declared under another name for a number, a piece of text or a date (`DECLARE Money IS A NUMBER`) is one to the check.
`EXACTLY` of a number, a piece of text, or a value of an enumeration is read as that value, and `EXACTLY` of the input's own name matches every input, as the bare name does.
Any other `EXACTLY`, such as `EXACTLY someConstant`, or `EXACTLY (m PLUS 1)` with `m` another input, compares the input with a value the check cannot name.
Where that input is a number, a piece of text or a date, at the top of the clause or inside a pattern as in `(Box (EXACTLY zero))`, the clause counts for nothing: it matches one value of the input for each value of the other inputs, and only the clause with the input's name covers the rest, which covers that one too.
Such a clause may still match some of the inputs the other clauses miss, so the warning then lists only what the clauses without a number or a piece of text leave open, with each input's name in its number and text positions; for a rule keyed only on numbers and texts, that is the one clause with every input's name.
With `two MEANS 2`, the clauses `DECIDE f 2 "b" IS 1`, `DECIDE f (EXACTLY two) s IS 2` and `DECIDE f 1 s IS 3` list ``DECIDE `f` n s IS`` alone, not `f 2 s`, which the second clause covers.
Where it is anything else, such as an enumeration or a record, it stops the check for the rule.
So does an `EXACTLY` whose expression mentions the input it is matched against, as `EXACTLY (n PLUS 0)` does for `n`, since such a clause may match any number of that input's values.
When there would be more than 64 clauses to list, a rule whose clauses name numbers or texts is told instead what the clauses without a number or a piece of text leave open; when every clause names one, that is the clause with every input's name alone, and a gap inside the table is not listed.
A rule whose clauses name no number or text gets no missing-clause warning past that cap, and neither does one whose shorter list is also longer than 64 clauses; a clause that is never used is reported either way.
A rule declared partial on purpose, with `@nonexhaustive` before its `GIVEN`, gets no missing-clause warning.
A rule of one clause whose check gives up gets the warning for a CONSIDER instead, listing the WHEN branches its clause does not cover; that warning stands down where the clause's does, for an `EXACTLY` it cannot read, so `DECIDE f (EXACTLY someColour) IS 1` on its own, with `c IS A Colour`, gets no warning at all.
A rule whose clauses match enumeration values only also gets no missing-clause warning when finding the clauses would take more than 10000 steps.

[Several clauses](../functions/DECIDE.md#several-clauses), under DECIDE, gives an example of each.

---

### Clause that is never used

**Warning:**

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

A third form, "Every input it matches is already matched by a clause above it", is for a clause that repeats an earlier one, or that is covered by a larger pattern above it.
It is given for numbers and text too: `1` and `1.0` are the same number, so `DECIDE h 1 IS "one"` followed by `DECIDE h 1.0 IS "one point zero"` draws it, and so does a repeated code in a table keyed by text, or a clause after `EXACTLY n` where `n` is the input's own name.
It is not given when the check stands down for an `EXACTLY` it cannot read (see [Non-exhaustive pattern match](#non-exhaustive-pattern-match)).

A clause that is never used is still checked against the rule's `GIVEN` and `GIVETH`, so a mistake inside it, such as a misspelt name or an answer of the wrong type, is still reported.

**How to fix it:** Put the clauses for particular cases first and the clause that matches anything last, or remove the clause that can never be reached.

---

### Annotation above a later clause

**Warning:**

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

**Warning:**

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
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN c IS A Colour
      d IS A Colour
GIVETH A NUMBER
f c d MEANS 3
```

---

### Unknown annotation

**Warning:**

```
Unknown annotation `@exprot`: this version of L4 does not know it, so it is ignored, along with the rest of its line. Did you mean `@export`?
```

When the name is not close to a known one, the last sentence lists the annotations this version knows instead.

**What you wrote:**

```l4
@exprot what the rule works out
GIVEN n IS A NUMBER
GIVETH A NUMBER
DECIDE `add one` n IS n + 1
```

**What went wrong:** An `@` and a name that L4 has no annotation for is read as a comment: it and the rest of its line are ignored, and the rest of the file is checked as usual.
It is a warning, not an error, for two reasons.
A file written for a newer version of L4 can use an annotation this version lacks and still be opened, checked and highlighted.
And a misspelt annotation is better flagged than silently dropped, since here the rule is not published and nothing else says so.

A newer annotation that changes what a rule means is not applied by a version that does not know it, so the warning is the only sign that it was left out.
A known annotation that lacks the form it needs is not this warning; it has [its own](#malformed-annotation).
An `@` that is not followed by a letter is still an error.

**Where you see it.** `l4 check` and `l4 run` print it, and so does the editor, as a warning on the line. The browser editor shows such a line like a comment and does not show the message, so `l4 check` is where to see it. `l4 batch` prints it on its standard error, as `file:line:column: message`, for the file you name (not for the modules it imports). `jl4-service` is the exception, on purpose: a deployment is what the service publishes, and a misspelt `@export` is a rule that is silently not published, so **a deployment that holds such a line is refused**, with the same message and its line and column in the file, and a service that is older than the file it is given refuses it for the same reason: it cannot honour the annotation, and the message names it. This is what the service always did with such a line, as a lexer error, so nothing already stored can hold one, and a restart refuses nothing it accepted before.

**A name that begins with a known annotation's is not this warning.** `@exports` is `@export` followed by the text `s`, and `@descr` is `@desc` followed by `r`, as they always were, so neither is unknown and neither is warned about. An `@exports` does not publish a function.

**How to fix it:** Correct the spelling, as the message suggests, or update L4 if the annotation is a newer one, or remove the line.

---

### Malformed annotation

**Warning:**

```
Malformed annotation `@lang`: it needs a language code after a space, such as `@lang en` (letters, digits and hyphens), so this line is ignored.
```

**What you wrote:**

```l4
@lang
```

or `@lang` followed by a tab, or by a language code with a non-ASCII letter.

**What went wrong:** `@lang` names the module's language, and it needs a language code after a space.
Without one, L4 cannot use the line, so it ignores it, as it ignores an [unknown annotation](#unknown-annotation), and the module's language is what it would be with no `@lang` at all.
It is a warning, not an error, so the rest of the file is still checked and highlighted.
`@lang` is the only annotation that can be malformed; every other accepts a bare herald, a trailing space, a tab and a non-ASCII letter after it.

**How to fix it:** Write the language code after one or more spaces, in letters, digits and hyphens: `@lang en`, `@lang he`.

---

### Infinite loop detected

**Error:** `Infinite loop detected while trying to evaluate: x PLUS 1`

```l4
x MEANS x + 1
#EVAL x
```

To find `x`, L4 needs `x + 1`, which needs `x` again. L4 notices this for a value defined in terms of itself and stops with this error.

A function that calls itself with new inputs, and never reaches a case that stops, is not caught: its `#EVAL` keeps running and never answers.

**How to fix it:** If you meant recursion, give it a case that stops:

```l4
GIVEN n IS A NUMBER
GIVETH A NUMBER
factorial n MEANS
    IF n <= 1 THEN 1
    ELSE n * factorial (n - 1)

#EVAL factorial 5
```

If you did not, you probably meant another name on the right-hand side.

---

## Assumed terms and refusals

Some names stand for facts that are supplied for each case, and some cases a rule declines to answer.

### ASSUME is being retired

**Warning:**

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

### Needed the value of an assumed term

**Error:**

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

## Pattern matching

### Non-exhaustive pattern match

**Warning:**

```
The following branches still need to be considered:

  WHEN Suspended THEN
```

```l4
DECLARE Status IS ONE OF Active, Suspended, Closed

GIVEN status IS A Status
GIVETH A STRING
describe status MEANS
    CONSIDER status
    WHEN Active THEN "running"
    WHEN Closed THEN "stopped"
```

The branches of the CONSIDER do not cover every value of its type. The file still runs, but evaluating the CONSIDER on a value with no branch stops with an error (see [Non-exhaustive patterns at runtime](#non-exhaustive-patterns-at-runtime)).

**How to fix it:** Add the branches the warning lists, or an OTHERWISE for everything else:

```l4
DECLARE Status IS ONE OF Active, Suspended, Closed

GIVEN status IS A Status
GIVETH A STRING
describe status MEANS
    CONSIDER status
    WHEN Active THEN "running"
    WHEN Closed THEN "stopped"
    OTHERWISE "unknown"
```

What the check covers:

- Enumerations declared in the same file, records and BOOLEAN are checked, including inside `WHERE` and `LET` definitions.
- A NUMBER, a STRING or a DATE has no end of values, so a CONSIDER over one is complete only with an OTHERWISE, and the warning suggests it. A WHEN with a number or a piece of text, and an `EXACTLY` of one or of a value of an enumeration, matches that value, as in a [rule written as clauses](#multi-clause-decide-does-not-cover-all-cases). A CONSIDER written by hand reads numbers, pieces of text and `EXACTLY` exactly as the clauses do, so the two spellings of one rule warn alike. A keyed gap inside a pattern is suggested as a WHEN, with the key as the branches spell it, and a number repeated in another spelling is a redundant branch.
- The builtin container types MAYBE, EITHER and LIST are checked, constructors and contents alike: a CONSIDER over a `MAYBE` with no `WHEN NOTHING` branch is warned about, and so is one over a `LIST` with no `WHEN EMPTY`. `WHEN JUST Red` over a `MAYBE Colour` asks for `WHEN JUST Green` and `WHEN JUST Blue`. A number or a piece of text nested in a pattern (`WHEN JUST 1`, `WHEN "a" FOLLOWED BY rest`) is read the same way.
- A CONSIDER over an enumeration declared in an imported file gives no missing-case warning at all.
- Past 64 missing branches to list, a CONSIDER with a number or a piece of text in a branch, written out or as the value of an `EXACTLY`, is told only what the branches without one leave open, as clauses are, and gets no warning when that list is too long as well.
  A CONSIDER with no such branch lists its first 128 missing branches instead, each a case that really is missing, where the check can read all its branches.
  The warning says when it lists only the first of more, and that adding them may not be enough: the check follows at most 128 cases still uncovered and gives up without a warning past that, which many added branches, or a CONSIDER of branches that each test several fields, can reach.
  It also says nothing where it cannot read a branch: an `EXACTLY` of anything but a number, a piece of text or a value of an enumeration stops the check for that match.
  A rule written as clauses is not given the longer list.
- Warnings never block evaluation: a file with warnings still runs its `#EVAL` directives.

A rule written as a list of clauses is checked the same way; its warning is [Multi-clause DECIDE does not cover all cases](#multi-clause-decide-does-not-cover-all-cases).

[CONSIDER](../control-flow/CONSIDER.md#missing-and-redundant-branches) gives the full rules, and [Exhaustiveness](../../concepts/type-system/exhaustiveness.md) explains why the check works this way.

---

### Redundant pattern match branch

**Warning:** `The following CONSIDER branch is redundant:`, followed by the branch

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN c IS A Colour
GIVETH A STRING
label c MEANS
    CONSIDER c
    WHEN Red THEN "r"
    OTHERWISE "x"
    WHEN Blue THEN "b"
```

A branch can never be reached, because the branches above it, here the OTHERWISE, already cover every value it could match. A number repeated in another spelling (`WHEN 1.0` after `WHEN 1`) is also redundant.

**How to fix it:** Delete the branch, or move it above the more general one.

---

### Non-exhaustive patterns at runtime

**Error:**

```
The value
  Withdrawn
reached a CONSIDER that has no branch for it.
Add a WHEN branch for this case, or a catch-all OTHERWISE branch.
The typechecker's exhaustiveness warning lists all missing branches.
```

**What went wrong:** Evaluation reached a CONSIDER whose branches do not cover the actual value of the scrutinee (shown in the message). Either the [warning](#non-exhaustive-pattern-match) was ignored, or the check could not see the gap: a missing value of an enumeration declared in another file gets no warning. A directive that stops this way makes `l4 run` exit with an error.
The last line of the message is quoted as the program prints it; for a CONSIDER with more than 128 missing branches the warning lists only the first 128, and says so.

**How to fix it:** Add branches for the missing cases, or an OTHERWISE branch for everything else. A CONSIDER over a NUMBER, a STRING or a DATE always needs an OTHERWISE.

When the rule was written as a list of clauses rather than with a CONSIDER, the message talks about its clauses instead:

```
No clause of `label` matches these inputs.
The value that the last clause could not match is
  Suspended
Add a clause for this case, or end the clauses with one that matches every input.
```

Here `label` has a clause for `Active` and one for `Closed`, and was asked about `Suspended`. Add a clause for the missing case (the warning [Multi-clause DECIDE does not cover all cases](#multi-clause-decide-does-not-cover-all-cases) lists the clauses still needed), or end the list with a clause whose pattern matches anything. A rule with only one clause says "The only clause of `label` does not match these inputs." instead.

A value that nobody supplied never produces this message: a `CONSIDER` on it stops with [Needed the value of an assumed term](#needed-the-value-of-an-assumed-term) instead, `OTHERWISE` or not.

---

## Regulative rules

### #EVAL shows the rule instead of an outcome

**Symptom:** `#EVAL` of a regulative rule prints the rule back (`PARTY Seller MUST ...`) instead of saying whether it was complied with.

A regulative rule is a `DEONTIC` value: it says what is owed, not what happened. To see an outcome, run it against events with `#TRACE`, giving a start time and what each party did and when:

```l4
DECLARE Party IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF `deliver the goods`, `pay`

GIVETH A DEONTIC Party Action
`the delivery duty` MEANS
    PARTY Seller
    MUST `deliver the goods`
    WITHIN 14
    HENCE FULFILLED
    LEST BREACH

#TRACE `the delivery duty` AT 0 WITH
    PARTY Seller DOES `deliver the goods` AT 3
```

This gives `FULFILLED`. See [Regulative rules](../regulative/README.md) and [EVENT](../regulative/EVENT.md).

---

## Export

### An @export input that is a rule, not a value

**Error:** `Function type inputs are not supported for @export.` — or, for the other
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

**Error:**

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
The error stops the whole file from checking: `l4 run`, the REPL, `l4 batch` and every exporter refuse the file, the `#EVAL`s of its other rules included, and jl4-service will not deploy it, until you add the `GIVEN` or remove the `@export`.
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
