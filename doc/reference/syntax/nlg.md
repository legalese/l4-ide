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
- A slot has no spaces inside. `% amount %` is not a slot, and nothing warns.
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
| On its own line above a rule under a section `GIVEN`             | The rule's sentence |
| After an input in the `GIVEN`, or indented under it              | That input's        |
| After a field, or under it                                       | That field's        |
| On its own line above a `GIVEN`                                  | Not the rule's      |

- **Trailing a line, it describes that line. On its own line, it describes what follows.** Fields and inputs are the exception: an annotation under one describes that one.
- **Under the last input, field or `ASSUME`, the column decides.** Indented past the `GIVEN`, `DECLARE` or `ASSUME` keyword, it describes that item. At the keyword's column or left of it, it describes what comes next. One extra space turns a rule's sentence into an input's wording, and nothing warns.
- **After an enum whose last value has no fields,** a line at the margin belongs to that value. Put the next rule's sentence after its name instead.
- **Empty or duplicated:** an empty `@nlg` is ignored with a warning. Two wordings in one language on one thing warn, and neither is used.
- **In the head and above it:** the one above is the rule's sentence, and the one on the input is that input's wording.
- **A head that repeats an input** takes the input from the head, so a wording in the `GIVEN` labels nothing.

## The placement, measured

Each row is one rule of [`jl4/examples/ok/nlg-head-placement.l4`](../../../jl4/examples/ok/nlg-head-placement.l4); the two `l4 nlg` columns are a positional call and a `WITH` call of that same rule.

| #   | head shape                        | annotation placement                              | `l4 nlg` positional | `l4 nlg` `WITH` | `l4 render`       |
| --- | --------------------------------- | ------------------------------------------------- | ------------------- | --------------- | ----------------- |
| 1   | `DECIDE` name                     | trailing the head                                 | sentence            | sentence        | sentence          |
| 2   | `DECIDE` name                     | own line above                                    | sentence            | sentence        | sentence          |
| 3   | name, then `MEANS`                | trailing the head                                 | sentence            | sentence        | sentence          |
| 4   | name, then `MEANS`                | own line above                                    | sentence            | sentence        | sentence          |
| 5   | name and input, then `MEANS`      | trailing the head                                 | sentence            | sentence        | sentence          |
| 6   | name and input, then `MEANS`      | own line above                                    | sentence            | sentence        | sentence          |
| 7   | name and input, then `MEANS`      | own line under input                              | sentence            | sentence        | sentence          |
| 8   | `DECIDE` name and input           | trailing the head                                 | sentence            | sentence        | sentence          |
| 9   | name, then input, then `MEANS`    | own line BEFORE input                             | sentence            | sentence        | sentence          |
| 10  | name and input with `AKA`         | own line after the AKA                            | sentence            | sentence        | sentence          |
| 11  | name and input with `AKA`         | own line above                                    | sentence            | sentence        | sentence          |
| 12  | name and two inputs, then `MEANS` | own line under the last input                     | sentence            | sentence        | sentence          |
| 13  | name and input, then `MEANS`      | own line above, and under the input               | outer sentence      | outer sentence  | outer sentence    |
| 14  | `DECIDE` name                     | trailing the `GIVEN` input                        | bare name           | input's gloss   | rule's body       |
| 15  | `DECIDE` name after `GIVETH`      | under the last `GIVEN` input, indented            | bare name           | input's gloss   | rule's body       |
| 16  | `DECIDE` name, no `GIVETH`        | under the last `GIVEN` input, indented            | bare name           | input's gloss   | rule's body       |
| 17  | `DECIDE` name, no `GIVETH`        | under the last `GIVEN` input, at `GIVEN`'s column | sentence            | sentence        | sentence          |
| 18  | inputs with `TYPICALLY`           | under each `GIVEN` input, indented                | bare name           | inputs' glosses | rule's body       |
| 19  | section `GIVEN`, then a rule      | under the section's input, indented               | no positional call  | input's gloss   | gloss in the body |

Row 13 heralds the rule twice, above the head and under its input, and the outer sentence wins; row 14 is an input gloss written in the `GIVEN`, which stays one.
Rows 15 to 19 are the `GIVEN`-list rule in [Where to put it](#where-to-put-it).
In rows 15, 16, 18 and 19 the annotation is indented past `GIVEN`, so it is the input's gloss, and a `WITH` call labels the input with it.
A positional call shows the rule's bare name in rows 15, 16 and 18; row 19 has none, because a section's input can only be supplied by name.
These rows use heads that do not repeat their inputs: when the head does repeat them, the gloss in rows 15 and 16 is rendered nowhere, as [Where to put it](#where-to-put-it) says of a head that repeats an input.
Row 17 is the control, at `GIVEN`'s column, where it is still the rule's sentence.
The row numbers are the rule names in [`jl4/examples/ok/nlg-head-placement.l4`](../../../jl4/examples/ok/nlg-head-placement.l4), whose committed golden pins both `l4 nlg` columns, and a CLI test pins the `l4 render` one — so a change to any cell is a test failure rather than stale prose here.

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
- **`l4 nlg` writes literal dates as dates:** `YMD 2025 7 16` and `Date 16 7 2025` read `16 July 2025`. A date that does not exist, such as `Date 31 2 2025`, stays a call.

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
- **In `l4 render`, a mixfix call's hole is bracketed, first, middle or last,** unless it holds a literal, a name, a field of one, a date written as numbers, or a call with one argument.
  So ``(a `reduced by` b) `reduced by` c`` and ``a `reduced by` (b `reduced by` c)`` read apart, and so do a `NOT`, an `IF`, a list or a `FOLLOWED BY` in a hole: ``yes `as well as` (NOT no)`` reads "yes as well as (no is false)".
  This is a different rule from a sentence's slot, above, where only a slot that the sentence goes on after is bracketed.
  A mixfix call that ends with a hole ends as the argument there does, so in such a slot it is bracketed whole when that argument would run on: in a rule whose inputs are `p`, `q` and `r`, `` `shown` (p `beats` (q AND r)) `` renders "([p] beats (q and r)) is shown", and ``p `beats` (`shown` (q AND r))`` renders "[p] beats (q and r) is shown".
  A mixfix call that is an operand of built-in arithmetic is bracketed as a whole: ``price PLUS (discount `reduced by` rebate)`` reads "price + ([discount] reduced by [rebate])".
- **A call with one argument is not bracketed in a hole, even one that ends with a condition, and it does not bracket its own argument,** so ``(double p) `reduced by` d`` and ``double (p `reduced by` d)`` read "double of p reduced by [d]" and "double of [p] reduced by [d]": with `p` an input they differ only in a blank, and with a constant in its place they read the same. With `fb` a rule with no sentence, `` `shown` (x `beats` (`fb` (q AND r))) `` and `` `shown` ((x `beats` (`fb` q)) AND r) `` both render "([x] beats fb for q and r) is shown". Give one of them a name of its own.
- **A ledger write, a ledger read and a refusal end in a clause of their own,** so `l4 render` brackets each in a slot the sentence goes on after, as it does a condition, and a write or a refusal beside arithmetic as well.
  With `dbl` as above, ``(RECORD `balance` IS 100) MINUS 3`` renders "(100, recorded as balance) − 3", `` `dbl` (REFUSE "not yet") `` renders "(the model refuses to answer: not yet) doubled", and with `@nlg %m% is kept` on `kept`, `` `kept` (RECALL `balance`) `` renders "(the value last recorded as balance, if any) is kept".
  A write in `l4 render` also starts with its value, with no word of its own before it, so it is bracketed wherever it is part of something larger: given to a call, in any slot or hole, compared, beside `AND` or `OR`, in a branch of an `IF` or in a list.
  With `@nlg pay %x%` on `pay`, `` `pay` (RECORD `balance` IS 100) `` renders "pay (100, recorded as balance)", and ``RECORD `balance` IS (`pay` 100)`` renders "pay 100, recorded as balance".
  A write that is the whole of a rule's body is not bracketed, but one laid out as an item of a list, or as a branch of an `IF`, keeps its brackets: "(b) (true, recorded as flag)."
  `l4 nlg` brackets a write and a refusal the same way: "(record balance is 100) minus 3".
  There a ledger read, "recall balance", ends with the cell's name, and is not bracketed.
  And there a write that is an operand of `OR` or `AND` is not bracketed, as an `IF` is not: ``(RECORD `flag` IS FALSE) OR TRUE`` and ``RECORD `flag` IS (FALSE OR TRUE)`` both read "record flag is `FALSE` or `TRUE`".

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

- **L4 does not translate.** It picks among the wordings you wrote.
- **A tag is matched as written.** `--lang he` does not read a `he-IL` wording, and `--lang he-IL` does not read a `he` one.
- **A missing wording falls back** to the rule's default: the one in the module's language, otherwise the first in the file.
- **The square-bracket form cannot be tagged.**
- **A word glued to the colon is a tag.** `@nlg:the employee pays` has the tag `the` and reads "employee pays", and nothing warns. Leave a space after the colon to keep it as text.

**`@lang he`** on a line of its own means every untagged `@nlg` in the module is Hebrew. It applies to the whole file.

- A module that declares nothing is `en`, so `@lang en` is not needed, and L4 hints that it can go.
- Declare the language of a module that is not English: it sets `<html lang=…>`, right-to-left `dir` and the Akoma Ntoso language.
- If two `@lang` lines disagree, the last one is used, and nothing warns.

**L4's own words,** such as "is equal to", "if" and "with", follow `--lang` where L4 has a table for the language. Hebrew is the only one. It is small and keeps English word order, so have a Hebrew speaker read the output. A word with no entry stays English, and `l4 nlg` names it on stderr.
