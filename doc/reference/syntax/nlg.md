# @nlg

`@nlg` gives a definition its wording in natural language.
`l4 render`, `l4 nlg` and the editor read that wording in place of the name.

```l4
GIVEN x IS A NUMBER, y IS A NUMBER
GIVETH A NUMBER
@nlg the greater of %x% and %y%
`the greater of` x y MEANS IF x >= y THEN x ELSE y
```

``#EVAL `the greater of` 3 7`` reads "the greater of 3 and 7".

- **To fix wording in a document:** [Fix wording with @nlg](../../tutorials/natural-language-functions/fix-wording-with-nlg.md)
- **To write rules that read well:** [Make rules read like law](../../tutorials/natural-language-functions/optimising-natural-language-generation.md)
- **Example:** [nlg-mixfix-example.l4](nlg-mixfix-example.l4)

Text in square brackets after a name is a short form: ``DECIDE `the limit` [the statutory limit] IS 5``.

## Slots

`%name%` is filled with the call's argument.

- An input with spaces in its name keeps its backticks: ``%`the amount`%``.
- A slot has no spaces inside. `% amount %` is plain text, and L4 warns.
- An input with no slot is not dropped. It follows the sentence: "the threshold is passed with 5".

To write `%` or `]` as itself, put a backslash before it:

| You write               | You get             |
| ----------------------- | ------------------- |
| `10\%and\%20`           | `10%and%20`         |
| `[rate \] per unit]`    | `rate ] per unit`   |
| `[see note \[3\] here]` | `see note [3] here` |
| `\\`                    | `\`                 |

You need this only where a `%` touches a word: `a 5% levy on %amount%` works as written.
Take care with `%word%`: if `word` names an input, L4 fills it in and nothing warns.

## Where to put it

| Where                                                            | Whose wording it is |
| ---------------------------------------------------------------- | ------------------- |
| On its own line, between the `GIVEN` or `GIVETH` and the rule    | The rule's sentence |
| After the rule's name: ``DECIDE `is large` @nlg …``              | The rule's sentence |
| After an input named in the head: `` `is large` amount @nlg … `` | The rule's sentence |
| On an `AKA` name                                                 | The rule's sentence |
| After an input in the `GIVEN`, or indented under it              | That input's        |
| After a field, or under it                                       | That field's        |
| On its own line above a `GIVEN`                                  | Not the rule's      |

- **Trailing a line, it describes that line. On its own line, it describes what follows.** Fields and inputs are the exception: an annotation under one describes that one.
- **Under the last input, field or `ASSUME`, the column decides.** Indented past the `GIVEN`, `DECLARE` or `ASSUME` keyword, it describes that item. At the keyword's column or left of it, it describes what comes next. One extra space turns a rule's sentence into an input's wording, and nothing warns.
- **After an enum whose last value has no fields,** a line at the margin belongs to that value. Put the next rule's sentence after its name instead.
- **Empty or duplicated:** an empty `@nlg` is ignored with a warning. Two wordings in one language on one thing warn, and neither is used.
- **In the head and above it:** the one above is the rule's sentence, and the one on the input is that input's wording.
- **A head that repeats an input** takes the input from the head, so a wording in the `GIVEN` labels nothing.

## How it reads

| You annotate                                 | It reads                                                                            |
| -------------------------------------------- | ----------------------------------------------------------------------------------- |
| A rule                                       | The sentence heads the rule and the body follows. Every call reads as the sentence. |
| A rule that calls itself, or an imported one | The sentence stands in for the body.                                                |
| An input                                     | Its label in a `WITH` call: `… where the amount is x`.                              |
| A field                                      | After its owner: `@nlg date of birth` reads "the employee's date of birth".         |
| A `BOOLEAN` field                            | On its own, with no owner, so write a whole statement.                              |

- **In a rule's own sentence,** an input of a built-in type reads as a blank, `[x]`. An input of your own type reads as the rule's body calls it, such as "the application kind".
- **A `WITH` call** reads the sentence, then each argument by name: "the smaller of a and b where a is price and b is 100".
- **A call reads the sentence of the definition it resolved to,** not of another definition with the same name.
- **A unit of time after a slot agrees with the number:** "%n% months" reads "1 month" for 1.
- **`l4 nlg` writes literal dates as dates:** `Date 16 7 2025` reads `16 July 2025`. A date that does not exist, such as `Date 31 2 2025`, stays a call.

## Limits

- **An `ASSUME`d function has no named inputs,** so it has no slots, and a call reads as its name and arguments. Use a `BOOLEAN` field or a rule instead.
- **A function passed on, or named without being called,** reads as its name. In `filter even xs`, `even` reads `even`.
- **A sentence inside another call is spliced in without brackets,** so nested calls can read alike: with `@nlg %a% doubled` on `dbl`, `` `f2` 2 (`dbl` 3) `` and `` `dbl` (`f2` 2 3) `` both read "`f2` with 2 and 3 doubled". Set slots off with words that cannot be part of an argument, and read the output of nested calls. A sentence that ends with a condition is the exception, in the next point. Arithmetic is bracketed, and so is anything beside it that does not say where it ends: "10 minus (5 minus 2)", "(5 doubled) minus 2", "twice (5 minus 2)", "(f2 for 2 and x) − 3".
- **A condition or an IF that fills a slot is bracketed when the sentence goes on after the slot,** so the rest of the sentence cannot read as part of it: with `@nlg %p% is shown` on `shown`, ``NOT (`shown` (`fb` TRUE))`` reads "not `fb` with `TRUE` is shown" and `` `shown` (NOT (`fb` TRUE)) `` reads "(not `fb` with `TRUE`) is shown"; `` `shown` (TRUE OR FALSE) AND FALSE `` reads "(`TRUE` or `FALSE`) is shown and `FALSE`"; and with `dbl` as above, `` `dbl` (IF FALSE THEN 1 ELSE 10 MINUS 3) `` reads "(if `FALSE` then 1 else 10 minus 3) doubled". So is a call that ends with such a condition: `` `shown` (`fb` (TRUE AND FALSE)) `` reads "(`fb` with `TRUE` and `FALSE`) is shown", and `l4 render` reads `` `shown` (`fb` (p AND q)) `` as "(fb for p and q) is shown". So is a call with a sentence of its own whose slot at the end holds such a condition: with `@nlg %a% is told %b%` on `told`, `` `shown` (`told` TRUE (NOT FALSE)) `` reads "(`TRUE` is told not `FALSE`) is shown", and `` `told` TRUE (NOT (`shown` FALSE)) `` reads "`TRUE` is told not `FALSE` is shown"; `l4 render` reads `` `shown` (`told` p (NOT (`fb` q))) `` as "([p] is told it is not the case that fb for q) is shown". Which slots is decided by where the slot is, not by the words: the sentence goes on after a slot when its words or another of its slots come after it, so with `@nlg %a%, %b%` on `comma`, `` `comma` (NOT (`fb` TRUE)) FALSE `` reads "(not `fb` with `TRUE`), `FALSE`". A condition in the slot at the end of the sentence is not bracketed, because nothing of the sentence follows it.
  What is left: in `l4 render` a denial of a single condition reads "p is false", which says where it ends, and is not bracketed: `` `shown` (NOT p) `` renders "p is false is shown".
  The slot at the end of a sentence can still run on past it, whatever fills it: ``((`told` p (NOT (`fb` q))) OR r) IMPLIES r`` renders "[p] is told it is not the case that fb for q or r implies r".
  In `l4 nlg`, with `@nlg it is shown that %x%` on `shown that`, ``(`shown that` TRUE) AND FALSE`` and `` `shown that` (TRUE AND FALSE) `` both read "it is shown that `TRUE` and `FALSE`", and so they read alike again in another sentence's slot.
  And a condition given to a call with no sentence is not bracketed: ``NOT (p OR (`fb` (q AND r)))`` renders "neither p nor fb for q and r".
  Give the condition a rule of its own, with a sentence, and call that.
- **A function with no sentence** reads as its pattern: `` `_ LESS _` with 100 and 20 ``.

## Several languages

Tag each wording with its language, and ask for one with `--lang`:

```l4
GIVEN amount IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is large` @nlg:en the amount %amount% is large
                  @nlg:he %amount% עולה על הסף
  IF amount GREATER THAN 100
```

```console
$ l4 nlg --lang he mymodule.l4
$ l4 render --format html --lang he mymodule.l4 -o mymodule.he.html
```

The Render tab in VS Code has a language menu when a file has wordings in more than one language.

- **L4 does not translate.** It picks among the wordings you wrote.
- **Regions match.** `--lang he` reads a `he-IL` wording, and `--lang he-IL` reads a `he` one. An exact match comes first.
- **A missing wording falls back** to the rule's default: the one in the module's language, otherwise the first in the file.
- **The square-bracket form cannot be tagged.**
- **A word glued to the colon is a tag.** `@nlg:the employee pays` has the tag `the`. L4 warns when nothing backs a tag as a language. Leave a space after the colon to keep it as text.

**`@lang he`** on a line of its own means every untagged `@nlg` in the module is Hebrew. It applies to the whole file.

- A module that declares nothing is `en`, so `@lang en` is not needed, and L4 hints that it can go.
- Declare the language of a module that is not English: it sets `<html lang=…>`, right-to-left `dir` and the Akoma Ntoso language.
- If two `@lang` lines disagree, the last one is used, and L4 warns.

**L4's own words,** such as "is equal to", "if" and "with", follow `--lang` where L4 has a table for the language. Hebrew is the only one. It is small and keeps English word order, so have a Hebrew speaker read the output. A word with no entry stays English, and `l4 nlg` names it on stderr.
