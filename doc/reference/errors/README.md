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

**Types**

- [Pipes in sum types](#pipes-in-sum-types)
- [Bare positional payload in sum types](#bare-positional-payload-in-sum-types)
- [Branch type mismatch](#branch-type-mismatch)
- [Wrong number of arguments](#wrong-number-of-arguments)
- [Argument of the wrong type](#argument-of-the-wrong-type)
- [Two types with the same name](#two-types-with-the-same-name)
- [Several definitions with the same name](#several-definitions-with-the-same-name)

**Names and imports**

- [I could not find a definition for the identifier](#i-could-not-find-a-definition-for-the-identifier)
- [Module not found](#module-not-found)
- [Import cycle](#import-cycle)

**Definitions and clauses**

- [A clause written like a rule with a word between its inputs](#a-clause-written-like-a-rule-with-a-word-between-its-inputs)
- [Clauses with more or fewer patterns than the GIVEN names](#clauses-with-more-or-fewer-patterns-than-the-given-names)
- [Multi-clause DECIDE does not cover all cases](#multi-clause-decide-does-not-cover-all-cases)
- [Clause that is never used](#clause-that-is-never-used)
- [Annotation above a later clause](#annotation-above-a-later-clause)
- [A definition after clauses that is not another clause](#a-definition-after-clauses-that-is-not-another-clause)
- [Infinite loop detected](#infinite-loop-detected)

**Pattern matching**

- [Non-exhaustive pattern match](#non-exhaustive-pattern-match)
- [Redundant pattern match branch](#redundant-pattern-match-branch)
- [Non-exhaustive patterns at runtime](#non-exhaustive-patterns-at-runtime)

**Regulative rules**

- [#EVAL shows the rule instead of an outcome](#eval-shows-the-rule-instead-of-an-outcome)

**Export**

- [An @export of clauses with no GIVEN](#an-export-of-clauses-with-no-given)
- [An @export with an input or result that cannot be sent yet](#an-export-with-an-input-or-result-that-cannot-be-sent-yet)

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

### Wrong number of arguments

**Error:** `The function add (defined at ...) expects 2 arguments, but you are applying it to 3 arguments here.`

A call gives a function more or fewer arguments than its `GIVEN` names.

**How to fix it:** Check the function's `GIVEN` and give one argument for each input, in the same order:

```l4
GIVEN a IS A NUMBER
      b IS A NUMBER
GIVETH A NUMBER
add a b MEANS a + b

#EVAL add 1 2
```

---

### Argument of the wrong type

**Error:** `The first argument of function append (defined at ...) is expected to be of type LIST OF a but is here of type STRING`

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

### Two types with the same name

**Error:** a type mismatch whose two types are spelled the same, each followed by where it was declared, such as `Verdict (Verdict defined at verdicts.l4:1:9-16)` against `Verdict (Verdict defined at verdicts.l4:3:9-16)`

```l4
DECLARE Verdict IS ONE OF yes, no

DECLARE Verdict IS ONE OF maybe, perhaps

GIVEN x IS A BOOLEAN
`pick` MEANS IF x THEN yes ELSE maybe
```

The file declares two different types called `Verdict`, and `yes` belongs to the first and `maybe` to the second.
So the two branches of the `IF` have different types, though both are called `Verdict`.
When the two types of a mismatch are spelled the same, L4 adds where each was declared, so that you can tell them apart.
The numbers after the file name are the line, then the columns.

Writing the name of such a type, in a `GIVETH` for example, gives a different message: [several definitions with the same name](#several-definitions-with-the-same-name), because L4 cannot tell which of the two you mean.

**How to fix it:** Declare each name once.
Rename one of the two types, or delete the `DECLARE` that repeats the other.

---

### Several definitions with the same name

**Error:** `There are multiple definitions for the identifier Date and I do not have sufficient information to make a choice between them.`, followed by the candidates and their types

Some names have several definitions told apart by their types, such as `Date` and `Time` in the date and time libraries. When L4 cannot tell from the context which one is meant, it asks. This often happens when such a call is followed by a word written between two inputs, as in ``Date 10 1 2024 `is before` Date 11 1 2024``.

**How to fix it:** Put each call in parentheses, or say the expected type with `GIVETH`:

```l4
IMPORT daydate

#EVAL (Date 10 1 2024) `is before` (Date 11 1 2024)
```

A type you declare yourself is ambiguous in the same way when it has the same name and the same number of parameters as a built-in type.
`DECLARE EVENT party action HAS ...` clashes with the built-in `EVENT`, and `DECLARE MAYBE a HAS ...` with the built-in `MAYBE`.
L4 then reports this error at each place that names the type, with your type and the built-in one as the two options, and nothing else about the use.
Give your type another name.
A type called `EVENT` with no parameters is not affected, because the built-in `EVENT` takes two.

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
- **A type that was never declared**, such as `Money` in `GIVEN amount IS A Money`. L4 reports the type at every place it is written, each at its own position, and nothing else about it: a `Money` in two `GIVEN`s and a `GIVETH` is three errors, and the rule that uses a `Money` is not also reported as having the wrong type.

**How to fix it:** Correct the spelling, or add the `IMPORT`:

```l4
IMPORT prelude

DECIDE total IS sum (LIST 1, 2, 3)
DECIDE `is ready` IS TRUE
```

---

### Module not found

**Error:** `I could not find a module with this name: helpers`, then `I have tried the following locations:` and the places that were tried. The list ends with the standard library built into `l4`, for example `the stdlib embedded in this binary (20 modules, not among them)`, or `the stdlib embedded in this binary (skipped: JL4_LIBRARY_PATH is set)` when that variable is set. On the command line, `l4` also prints `Warning | [Import Resolution] Module not found: helpers`.

An `IMPORT` names a module that is neither a standard library nor a file `helpers.l4` in your project's root folder or beside the importing file.
This stops `l4 check`, `l4 run` and deploying, even if nothing from the module is used.

**How to fix it:**

- Check the name. A name with a hyphen needs backticks: ``IMPORT `legal-persons` ``. `IMPORT` takes a module name, not a path: a folder in front of the name is ignored.
- Put your own module in the project's root folder or beside the file that imports it.
- If `JL4_LIBRARY_PATH` is set, the built-in standard library is not used at all, so that folder must hold every library you import, `prelude.l4` included.

[IMPORT](../libraries/README.md#import) describes module names and where they are found; [How IMPORT finds libraries](../libraries/resolution.md) gives the full search order for operators and library developers.

---

### Import cycle

**Error:** `This IMPORT makes a ring of imports: a.l4 -> b.l4 -> a.l4.` or `A file cannot import itself.`

Files import each other in a ring, directly or through other files. L4 checks the files a file imports before the file itself, so a ring can never be checked. The error is on the `IMPORT` that closes the ring. Files that import a file in the ring get an error on that `IMPORT` too.

**How to fix it:** move what both files need into a new file that both import, or remove an `IMPORT` the file doesn't use.

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
A use of the word inside another rule is still read as a use of the mixfix rule: with ``a `plus` b`` in the file, the body `total plus y` of a rule whose inputs are `plus` and `y` is read as ``total `plus` y``, and fails to check ("The first argument of function `plus` is expected to be of type NUMBER but is here of type FUNCTION FROM NUMBER AND NUMBER TO NUMBER").
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

**Note:** Rules whose clauses match enumeration values or `TRUE`/`FALSE` are checked, and so are rules whose clauses match particular numbers or texts.
A number or a piece of text is one value of its input, and there is no end of the others, so such a rule is complete only with a clause written with the input's name, and the warning suggests that clause: ``DECIDE `describe` n IS`` for `DECIDE describe 0 IS "zero"` and `DECIDE describe 1 IS "one"`.
The other inputs of the same rule are still analysed, the gaps under each number first and then the clause for every other number.
Rules that match lists or `MAYBE` values, or an enumeration declared in another file, get no warning where the check would have to tell such values apart, not even for a number nested inside one; where the other inputs settle the question first it still warns, and when every clause of such a rule has a number or a piece of text in it, the warning suggests the one clause with every input's name and nothing finer.
`EXACTLY` of a number, a piece of text or a value of an enumeration is read as that value, and `EXACTLY` of the input's own name matches every input; any other `EXACTLY` counts for nothing on a number, text or date input, and in such a field of a record, stops the check on an enumeration input, and stops it on any input when its expression mentions the input itself.
An input or a field declared under another name for a number (`DECLARE Age IS A NUMBER`) is a number to the check.
When a clause counts for nothing that way, the warning lists only what the clauses without a number or a piece of text leave open, since a keyed gap could be one that clause covers.
A suggested number prints as the clauses spelled it, and a suggested piece of text as L4 writes it, with `"` and `\` escaped.
A rule whose clauses match enumeration values only gets no warning when it would need more than 64 clauses listed, or more than 10000 steps to find them; when its clauses match numbers or texts, the warning lists instead only the clauses that the clauses without a number or a piece of text leave open, which, when every clause names a number or a text, is the clause with every input's name alone.
[Several clauses](../functions/DECIDE.md#several-clauses), under DECIDE, gives an example of each.
A rule of one clause that is not checked keeps whatever warning a CONSIDER would give (see [Non-exhaustive pattern match](#non-exhaustive-pattern-match)), listing WHEN branches, now at the clause; a CONSIDER reads numbers, texts and `EXACTLY` the same way, so a missing case over them is reported in either spelling; the two can differ for a repeated value, and where a branch or clause names a constructor of a `MAYBE`, an `EITHER`, a list or a type from another file (see [CONSIDER](../control-flow/CONSIDER.md)).
See [Several clauses](../functions/DECIDE.md#several-clauses).

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

A clause that is never used is still checked against the rule's `GIVEN` and `GIVETH`, so a mistake inside it, such as a misspelt name or an answer of the wrong type, is still reported.

Only the clauses after one that matches every input are warned about: a clause whose every pattern is its input's own name, `_`, or a new name.
A pattern that is not a value of its input's type is a new name, such as `other`, or `Gren` where `Green` was meant, and a new name matches anything.
The warning then names it:

```
This clause of `colour` is never used, because the clause above it with the new name `Gren` matches every input.
`Gren` is not a value of its input's type, so it is a new name, and a new name matches anything.
If you meant a value, correct the spelling; if you meant to match anything, move that clause below the others.
```

This holds in rules that match numbers or text too.
It is not given when a pattern of the rule does not fit its input's type, since the rule is then an error.
A new name inside a larger pattern draws no warning: after `(JUST Gren)`, a clause for `(JUST Blue)` is never used, and nothing says so.
There is no warning for a clause that repeats one above it.

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
- A NUMBER, a STRING or a DATE has no end of values, so a CONSIDER over one is complete only with an OTHERWISE, and the warning suggests it. A WHEN with a number or a piece of text, and an `EXACTLY` of one or of a value of an enumeration, matches that value, as in a [rule written as clauses](#multi-clause-decide-does-not-cover-all-cases).
- The contents of MAYBE, EITHER and LIST values are checked: `WHEN JUST Red` over a `MAYBE Colour` asks for `WHEN JUST Green` and `WHEN JUST Blue`. A missing `NOTHING` or `EMPTY` branch is not reported, so a CONSIDER with only `WHEN JUST x` gets no warning.
- A CONSIDER over an enumeration declared in an imported file gives no missing-case warning at all.

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

**What went wrong:** Evaluation reached a CONSIDER whose branches do not cover the actual value of the scrutinee (shown in the message). Either the [warning](#non-exhaustive-pattern-match) was ignored, or the check could not see the gap: a missing `NOTHING` or `EMPTY` branch, or a missing value of an enumeration declared in another file, gets no warning. A directive that stops this way makes `l4 run` exit with an error.

**How to fix it:** Add branches for the missing cases, or an OTHERWISE branch for everything else. A CONSIDER over a NUMBER, a STRING or a DATE always needs an OTHERWISE.

When the rule was written as a list of clauses rather than with a CONSIDER, the message talks about its clauses instead:

```
No clause of `label` matches these inputs.
The value that the last clause could not match is
  Suspended
Add a clause for this case, or end the clauses with one that matches every input.
```

Here `label` has a clause for `Active` and one for `Closed`, and was asked about `Suspended`. Add a clause for the missing case (the warning [Multi-clause DECIDE does not cover all cases](#multi-clause-decide-does-not-cover-all-cases) lists the clauses still needed), or end the list with a clause whose pattern matches anything. A rule with only one clause says "The only clause of `label` does not match these inputs." instead.

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
The error stops the whole file from checking: `l4 run`, the REPL and `l4 batch` refuse the file, the `#EVAL`s of its other rules included, and jl4-service will not deploy it, until you add the `GIVEN` or remove the `@export`.
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

### An @export with an input or result that cannot be sent yet

**Error:**

```
`who acted` is published with @export, but its input `e` is an EVENT, and @export does not support that yet.
Take the party, the action and the time as separate inputs, and build the event inside the rule.
```

The first line names the input, or says "its result", and says what the type is.
The second line says what to do about it, and is different for each kind of type.

**What you wrote:**

```l4
DECLARE Party IS ONE OF alice, bob
DECLARE Act IS ONE OF ping, pong

@export Who acted
GIVEN e IS AN EVENT Party Act
GIVETH A Party
`who acted` MEANS
  CONSIDER e
  WHEN EVENT p a n THEN p
```

**What went wrong:** `@export` publishes a rule as a web endpoint, and a request to it supplies each input as a value written in JSON, and the answer comes back as a value written in JSON.
That works for a `NUMBER`, a `BOOLEAN`, a `STRING`, a `DATE`, a `TIME`, a `DATETIME`, a `LIST OF` or a `MAYBE` of those, and a type that you declare as a record or as an enumeration of those.
It does not work yet for these, so an `@export` of a rule that takes or returns one is an error, reported at the `@export` line:

| the input or result is...                                  | the error says                                |
| ---------------------------------------------------------- | --------------------------------------------- |
| an [EVENT](../regulative/EVENT.md)                         | `an EVENT`                                    |
| a `DEONTIC`, which is what a contract rule gives back      | `a DEONTIC, a contract rule`                  |
| a `FUNCTION FROM ... TO ...`                               | `a function`                                  |
| a type variable, in a rule that works for any type         | `of the type variable ...`                    |
| any other type that has no JSON form yet, such as `EITHER` | `of the type ...`                             |
| a record with a field of one of those types                | `of a record type ... whose field ... is ...` |

The same goes for an `EVENT` or a function inside a `LIST OF` or a `MAYBE OF`, or named through a type that you declared as another name for it.
A rule that builds or reads an `EVENT` inside its body, and does not name one in its inputs or its result, is published as usual.

A rule that gives back a `DEONTIC` is a contract: it says who must do what by when.
It cannot be published yet, and a contract rule is still evaluated where you write it, so its `#EVAL` and `#EVALTRACE` results still show.

The error is reported by its own check, and not by the type check, so the file still checks: `l4 run` still runs it, the `#EVAL`s of its other rules included.
`l4 check` reports the error, the editor shows it as an error from `export`, and deploying is refused until you remove the `@export` or change the type.
`@export default` is refused the same way.

**How to fix it:** Take the parts of the event as separate inputs, and build the event inside the rule if it needs one.
A helper that is not published can still take an `EVENT`:

```l4
DECLARE Party IS ONE OF alice, bob
DECLARE Act IS ONE OF ping, pong

GIVEN e IS AN EVENT Party Act
GIVETH A NUMBER
`event time` MEANS
  CONSIDER e
  WHEN EVENT p a n THEN n

@export When it happened
GIVEN who IS A Party
      what IS AN Act
      time IS A NUMBER
GIVETH A NUMBER
`when it happened` MEANS `event time` (EVENT who what time)
```

For a function, pass the values it would work on, and apply the function inside the rule.
For a contract rule, remove the `@export`.
