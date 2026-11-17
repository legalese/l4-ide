# Query Planning

The **query planner** turns a rule that decides `TRUE` or `FALSE` into a question-and-answer session.
Given the answers so far, it says whether the outcome is already settled and, if it is not, which inputs are still needed and which to ask next.

## An example

```l4
GIVEN
  adult IS A BOOLEAN
  citizen IS A BOOLEAN
  resident IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `may vote` IF adult AND (citizen OR resident)
```

If `adult` is answered `FALSE`, the outcome is settled, and neither `citizen` nor `resident` is asked.
If it is answered `TRUE`, both are still needed.

## What it asks first

An input that can no longer change the outcome is not asked.
Of the inputs still needed, the planner puts first the one whose answer is expected to tell the most about the outcome.
It treats each input as equally likely to be answered either way, except a `BOOLEAN` input on the rule's own `GIVEN`, or a `BOOLEAN` `ASSUME`, that has a [TYPICALLY](../types/TYPICALLY.md) value: that one is taken as likely to have its usual value, which can change the order.

## Where you meet it

- The ladder diagram, in the web app and in VS Code, uses the plan to show which inputs are still needed and which to ask next.
- `jl4-service` answers the same question for a deployed rule, at `POST /deployments/{id}/functions/{fn}/query-plan`; the service's README describes the request and the reply.

## Rules written as clauses

A rule that answers yes or no can be written as a list of clauses, one `DECIDE` line for each case, instead of as one `CONSIDER`.
These two rules are the same rule:

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN c IS A Colour
GIVETH A BOOLEAN
DECIDE warm Red   IS TRUE
DECIDE warm Green IS FALSE
DECIDE warm Blue  IS FALSE

GIVEN c IS A Colour
GIVETH A BOOLEAN
DECIDE `warm, by hand` c IS
  CONSIDER c
    WHEN Red   THEN TRUE
    WHEN Green THEN FALSE
    WHEN Blue  THEN FALSE
```

L4 reads the clauses as the `CONSIDER` they stand for.
Clauses may share an earlier input and differ in a later one, as the rows of a decision table do:

```l4
DECLARE Colour IS ONE OF Red, Green, Blue

GIVEN c IS A Colour
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `colour rule` Red   TRUE  IS TRUE
DECIDE `colour rule` Red   FALSE IS FALSE
DECIDE `colour rule` Green b     IS b
DECIDE `colour rule` Blue  b     IS NOT b
```

L4 reads each clause knowing what the clauses above it have already settled, so this is drawn as the nested `CONSIDER` a drafter would write: one question about the colour, and for `Red` one question about `b`.
A clause whose pattern is a new name, such as `DECIDE warm other IS FALSE`, matches anything that reaches it, and is read as `OTHERWISE`.

So the ladder diagram in the editor, the query plan (the `/query-plan` route of `jl4-service`, the service that publishes rules), and `l4 verify` treat the two forms alike: the same boxes, the same questions, asked in the same order.
That holds for tables like the ones above, whose patterns are enum values or literals (a number, a piece of text, `TRUE` or `FALSE`).

A name is read correctly wherever it is, but it can make the drawing larger.
A clause that names an input, instead of giving its value, and then tests a later input, has the clauses after it drawn again under each answer to that later test, because L4 cannot tell from that clause which value the named input has.
So the ladder can be larger than the `CONSIDER` you would write, and a long list can pass the limit below.
If that happens, write that part of the rule as a `CONSIDER`, or split the rule as described below.

### Patterns that are not broken down

A pattern with something inside it, such as `JUST TRUE`, `JUST x` or a list, is not broken down into questions.
The rule, or the part of it that tests that input, is drawn as one box, as it is for a `CONSIDER` written by hand.
`l4 verify` lists a rule written as clauses whose whole ladder is that one box as `NOT ANALYSED`, saying that it was not broken down into questions, rather than reporting that it found nothing.
A rule only part of which is such a box is analysed as far as its other boxes go: the box is one question, and nothing inside it is checked.

### At most 300 boxes

Read as a `CONSIDER`, a list of clauses can draw more boxes than it has clauses: in a rule with several inputs, a later clause is drawn again under each earlier case that leaves it open.
So L4 draws at most 300 boxes for a rule written as clauses.
A rule over that limit is not drawn or planned.
The ladder diagram and the query plan refuse it with this message (the service answers with a 400 error):

```
These clauses would draw a ladder of more than 300 boxes, too many to show. Split the rule into smaller groups of clauses, or into named sub-rules.
```

and `l4 verify` lists the rule as `NOT ANALYSED`, with the same reason.

Clauses with very long bodies can be refused before they are drawn, when written out as the `CONSIDER` they stand for they come to more than 20,000 parts:

```
These clauses are too long to draw: written out as the CONSIDER they stand for, they come to more than 20000 parts. Split the rule into smaller groups of clauses, or into named sub-rules.
```

In the editor, a rule refused for either reason keeps the lens above it, which then reads `No decision graph: these clauses would draw more than 300 boxes`, or `No decision graph: these clauses are too long to draw`.
Clicking it shows the whole message.

A rule that uses clauses too long to draw is still drawn, with the use as one box that does not open: the editor does not offer to expand it, and `l4 verify` checks the rule without looking inside that box, and says why under "call left as a leaf".

Only the picture and the plan are refused.
The rule still runs: `#EVAL`, `l4 run` and the service's evaluation answer it as usual.

**What you can do about it:**

- **Give part of the rule a name of its own.** Move a group of clauses into a separate rule, named for what it decides, and use that rule in the clauses that remain. The rule that uses it shows the call, not the clauses behind it, so they do not count towards its 300; the new rule is drawn, and counted, on its own.
- **Split one long list into smaller lists**, each deciding one part of the question, and combine their answers with `AND` or `OR`.

The limit applies only to a rule written as clauses, and it is the rule as you wrote it that counts.
A `CONSIDER` you write yourself is drawn as you wrote it, and so is a rule you wrote by hand after the editor unfolds a call to a clause group into it.
A rule that answers something other than yes or no, such as a number, is not drawn as a ladder at all, however it is written, and L4 says that first.

### The limit is on the drawing, not on planning

The 300 bounds how much is drawn, not how long planning takes.
A plan's cost depends on how its questions combine, not only on how many boxes there are.
A table of 20 rows over an enum of 20 values and a yes-or-no input draws 61 boxes and took between 11 and 21 seconds to plan when measured, depending on how busy the machine was; one of 24 rows draws 73 boxes and took about four minutes.
The same rule written as a `CONSIDER` by hand, with the same patterns, takes as long.
Written with the input `b` itself where the clauses have the pattern `TRUE`, it plans in a hundredth of a second: the plan treats the 20 copies of the question "is `b` true?" as one question there, and as 20 questions in the table.

## See also

- [TYPICALLY](../types/TYPICALLY.md): writing down the usual value of an input
