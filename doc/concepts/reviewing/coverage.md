# Which combinations a rule has been tried on: `l4 coverage`

A rule that depends on several yes-or-no conditions can be in many situations.
A filing might be required unless the body is licensed, or dormant, or publicly funded.
That is three conditions, and a fourth if the rule also asks what kind of body it is, so there are sixteen combinations of yes and no.
A test checks the combination its author thought of.
`l4 coverage` lists **all** the combinations, and for each one shows an input that produces it and the answer L4 gives there.
It also shows the combinations that cannot happen, so that nobody wonders whether they were forgotten.

## What a coverage table is for

Three questions, in the order a reviewer usually asks them:

- **Has every combination of the rule's conditions been tried at all?**
  A combination nobody tried is a place where the rule might answer something nobody has looked at.
- **Which combinations can never happen?**
  Two conditions such as "income above 100 000" and "income above 50 000" are not independent: the first without the second is impossible.
  A table that lists impossible combinations as impossible, and says a solver proved it, lets you see that the rule's author and the rule agree about what can happen.
- **What does the rule answer in each?**
  Reading down the answers is a quick way to see whether the rule does what its words say, for example that every exception really does turn the answer around.

A coverage table does not say the rule is right.
It says which cases have an answer in front of you, which is the first step of checking.

## Running it

```
l4 coverage FILE.l4
```

Every rule in the file that branches on a condition gets a table.
(A rule with nothing to branch on, such as `x TIMES 2`, has nothing to cover; the closing line counts them.)

This is the report for `or-leaves.l4`, a file in L4's own examples: a filing is required of every kind of body except the residual one, unless the body is licensed, dormant or publicly funded.
The rule, as written in the file:

```l4
DECIDE `filing is required` IF
      NOT (category EQUALS Other)
  UNLESS `holds a licence`
      OR `is dormant`
      OR `is publicly funded`
```

and the start of what `l4 coverage` prints, with most of the rows left out:

```
l4 coverage: examples/catala/or-leaves.l4

Decision `filing is required`  (or-leaves.l4:14:1-23:30)
  Inputs: category, holds a licence, is dormant, is publicly funded
  Cover points (4):
    c0  category EQUALS Other  or-leaves.l4:20:7-21:9
    c1  `holds a licence`      or-leaves.l4:21:10-22:9
    c2  `is dormant`           or-leaves.l4:22:10-23:9
    c3  `is publicly funded`   or-leaves.l4:23:10-30

  Buckets (16 combinations: 16 witnessed, 0 proved impossible, none undecided):
    c0 c1 c2 c3   status
    F  F  F  F    witnessed by 8 inputs; L4 answers TRUE
          category = Individual, holds a licence = FALSE, is dormant = FALSE, is publicly funded = FALSE gives TRUE
    F  F  F  T    witnessed by 8 inputs; L4 answers FALSE
          category = Individual, holds a licence = FALSE, is dormant = FALSE, is publicly funded = TRUE gives FALSE
    ...
    T  T  T  T    witnessed by 1 input; L4 answers FALSE
          category = Other, holds a licence = TRUE, is dormant = TRUE, is publicly funded = TRUE gives FALSE

Coverage: 1 decision covered (4 cover points, 16 buckets); 16 witnessed by 72 inputs, at most 8 per bucket; 0 proved impossible; nothing undecided; every decision at leaf level; nothing skipped; a call to another rule is one cover point, and conditions inside an arm's result are not cover points.
```

### Reading it

- A **cover point** is one separate yes-or-no condition in the rule.
  `holds a licence OR is dormant OR is publicly funded` is three of them, not one, so each can be seen to matter on its own.
  A condition used in two places in the rule counts once.
  The line after each says where it is in the file.
- A **bucket** is one combination: a row of `T` (the condition holds) and `F` (it does not), one column per cover point.
  Four cover points give sixteen buckets.
- **witnessed** means L4 found a real input that makes exactly this combination true, ran the rule on it, and wrote down the answer.
  The row shows the first such input, and how many there were (at most eight per bucket).
- **proved impossible** means no input at all makes this combination true, and a solver, a program that decides such questions, proved it.
  See below.
- **UNDECIDED** means neither: L4 did not find an input and could not prove there is none, and says why (there is no solver installed, the solver ran out of time, and so on).
  A bucket is also undecided when the rule raises an error at one of the inputs found for it, such as a division by zero or a day that is not a date; the reason then quotes the error and shows the input (from `examples/coverage-report/dates.l4`, which counts the days from 1 March to a date it builds from a day, a month and a year):

  ```
      T    UNDECIDED: L4 raises an error at d = 0, m = 3, y = 0: "DATE_FROM_DMY produced an invalid date from day=0, month=3, year=0"
  ```

  A rule that calls itself without end at such an input stops at one of L4's limits, and which one decides what the report says.
  One that adds to the answer of its own call, such as one that sums the numbers from its input down to zero, called with a number below zero, stops at L4's limit on depth, and that counts as an error too: `L4 raises an error at n = -1: "Stack overflow: …"`.
  One whose answer is the answer of its own call, such as one that counts down to zero, called the same way, stops at L4's limit on steps instead, and a stop at a limit says nothing about the rule's answer there, so the rule is not covered at all: `NOT COVERED: the evaluator stopped at a limit at an input it tried: …`, and the exit status is 3.
  A rule that answers with `REFUSE` there leaves the bucket undecided as well, and the reason quotes the refusal: `L4 gives no answer at n = 0: it refuses to answer: "…"`.
  An undecided bucket is never counted as covered.

### A combination that cannot happen

For `bands.l4`, a rate table in which one condition is "income above 100 000" and another is "income above 50 000":

```
  Buckets (4 combinations: 3 witnessed, 1 proved impossible, none undecided):
    c0 c1   status
    F  F    witnessed by 6 inputs; L4 answers 0.1
          f = Filer OF 0, TRUE gives 0.1
    F  T    witnessed by 6 inputs; L4 answers 0.25
          f = Filer OF 50001, TRUE gives 0.25
    T  F    proved impossible: no input makes these conditions hold together
    T  T    witnessed by 2 inputs; L4 answers 0.4
          f = Filer OF 100001, TRUE gives 0.4
```

Income above 100 000 without being above 50 000 cannot happen, so the row `T F` is not a gap in the testing.
It is the solver's word that it cannot happen, and **nothing else checks it**: if you doubt the claim, read the two conditions and ask yourself.
A table with 502 impossible rows out of 512, as `many-bands.l4` has, prints the first sixteen and says how many more there are; `--all` lists them all.

### When the answers inside one bucket differ

Sometimes one bucket has several inputs, and the rule gives different answers at them, because the answer depends on something the conditions do not decide.
The row then says so, instead of printing one answer as if it covered the bucket:

```
    F    witnessed by 3 inputs; L4's answer DIFFERS across them: 3 different values (0, 50, 49.95)
          income = 0 gives 0
          income = 1000 gives 50
          income = 999 gives 49.95
```

(From `examples/coverage-report/varies.l4`, whose allowance is a tenth of the income above 1000 and a twentieth of it otherwise: every income that is not above 1000 lands in one bucket.)

### Inputs that no condition reads

L4 tries every input at a few values, the same values for every input of the same kind:

- a number at zero, at each number the conditions mention (the rules they call count too), and at one either side of each, so at zero alone when they mention no number;
- a true-or-false input at both;
- a choice at every option, with the fields of an option or a record at the values of their own kinds, two levels deep.

It tries every combination of those values, up to 4,096 of them (past that, 4,096 spread across them), and keeps the first eight that land in each bucket, in an order in which the first input changes fastest.
A bucket that none of them lands in gets its input from the solver, if one is installed, and its row says so.

If any input is of a kind that has no value within those two levels, such as a record whose field is a record whose field is a record with fields of its own, there are no combinations at all: no input is tried, not even a true-or-false one, and every bucket gets its input from the solver, or is `UNDECIDED` when there is none.

An input that **no condition reads** is tried at those values too, but no bucket depends on it, so the values it has in a bucket are only those that came with the first eight inputs.
The report names such inputs under the heading of the decision:

```
  Inputs no condition reads (no bucket depends on them, so the answers below may vary with them): income
```

The answers shown for that decision are then answers at those values only, and the rule may answer differently at others.
(From `examples/coverage-report/unread.l4`, whose only condition is a true-or-false input: it mentions no number, so `income` is tried at zero alone.)

## The exit status

A script can tell a complete run from an incomplete one by the exit status:

| status | meaning                                                                                                                      |
| ------ | ---------------------------------------------------------------------------------------------------------------------------- |
| 0      | every rule is covered, and every bucket is witnessed or proved impossible                                                    |
| 1      | the file did not check, or `--decision` names a rule the file does not have                                                  |
| 2      | at least one bucket is undecided                                                                                             |
| 3      | none is undecided, but some rule is covered only by its conditions as written (below), or not at all, or nothing was covered |

A run that covered nothing exits 3, not 0, so that a file with no conditions is not read as a clean bill.

## Options

| option              | effect                                                                                                    |
| ------------------- | --------------------------------------------------------------------------------------------------------- |
| `--decision NAME`   | cover only this rule; repeat for several. Without it, every rule of the file that branches on a condition |
| `--all`             | list every input of every bucket, and every bucket proved impossible                                      |
| `--json`            | write the report as JSON on standard output; the closing coverage line goes to standard error             |
| `--timeout SECONDS` | give the solver this long per bucket; past it the bucket is undecided (default 10)                        |

The solver is [z3](https://github.com/Z3Prover/z3), found through `Z3_EXE` if you set it, and otherwise on your `PATH`.
Without it, a bucket that none of the tried inputs produces is `UNDECIDED`, and the run exits 2; every other bucket is reported as usual.

## Limits

These are stated here, and printed in `l4 coverage --help`, because you would otherwise find them out from a wrong conclusion.

- **What a cover point is.**
  The separate conditions in the conditions a rule branches on: an `UNLESS` chain, a `BRANCH` or `IF`, each `WHEN` of a `CONSIDER`, or the body of a rule that returns true or false.
  `a OR b` is two; a condition used twice is one.
  A call to another rule is **one** cover point: the conditions in its body are not cover points, though its numbers are among the values each input is tried at (see [Inputs that no condition reads](#inputs-that-no-condition-reads)).
  A condition inside the _result_ of one arm is not a cover point.
- **A `CONSIDER`** in a rule that does not return true or false has one cover point for each `WHEN`: `CONSIDER p WHEN basic` is the condition `p EQUALS basic`, as the same rule written with `BRANCH` and `IF` has it.
  That holds when every `WHEN` names a number, an option that has no fields, or `EXACTLY` a value, and any `OTHERWISE` comes last.
  A `WHEN` that takes an option's fields apart (`WHEN many n`), puts a pattern inside a pattern (`WHEN JUST basic`), or gives a new name to whatever reaches it is not one yes-or-no condition, and neither is a `WHEN` after an `OTHERWISE`, which is never reached.
  A rule with one of those is not covered: the report names it, says which arm stopped it, and the exit status is 3.
  A `CONSIDER` with no `OTHERWISE` whose `WHEN`s miss an option leaves `UNDECIDED` the bucket in which none of them holds, since the rule raises an error at that option, and marking the rule `@nonexhaustive` does not change this.
  In a rule that returns true or false, a `CONSIDER` whose `WHEN`s all name numbers and which ends in an `OTHERWISE` has one cover point for each `WHEN`, each shown with the place of the whole `CONSIDER`; any other `CONSIDER` there is one condition, which the ladder diagram breaks into its parts.
- **Text, dates and other values the solver cannot read.**
  To find inputs and to prove combinations impossible, L4 first writes a rule's inputs and conditions in the language of the solver, and that language has no text, no dates, no lists, no `MAYBE` and no other type that takes a parameter.
  So a rule is not covered when one of its inputs is text, a date, a list, a `MAYBE` or of another type that takes a parameter, whether or not a condition reads it, or when a condition works on any of those, such as one that calls `DATE_SERIAL`: the report says `NOT COVERED`, with a reason that starts `out of fragment`, and the exit status is 3.
  That includes a `CONSIDER` over text, such as `CONSIDER colour WHEN "red" THEN …`, and one with a `WHEN NOTHING`, such as `CONSIDER m WHEN NOTHING THEN …`.
  A date built in the result of an arm, from numbers, does not stop it.
- **How many.**
  With _n_ cover points there are 2ⁿ buckets, and past twelve cover points the rule is covered by its conditions as written instead: the report says `AT RUNG LEVEL` and why, and the exit status is 3.
  It does the same where a condition raises an error at an input that an earlier condition of the same rung already decides, such as `(NOT x EQUALS 0) AND (10 DIVIDED BY x) GREATER THAN 2` at zero: that input would otherwise belong to no bucket.
- **A later arm that raises where an earlier arm answers.**
  An input at which a condition raises an error is left out of every bucket.
  Where L4 answers at it, by an earlier arm, that loses nothing when another input L4 tries, at which every condition is true or false, agrees with the left-out one on the conditions L4 reaches there: the separate conditions of each arm up to the one that answers (in an `UNLESS` chain, of the condition before the first `UNLESS`, and of the rest only where that condition holds).
  That input takes the same arm, and its bucket is witnessed.
  So in `BRANCH IF n AT MOST 0 THEN 0 IF 10 DIVIDED BY n GREATER THAN 2 THEN 1 OTHERWISE 2`, zero is left out, but minus one takes the first arm too, and the rule is covered (from `examples/coverage-report/later-arm-covered.l4`).
  A condition of a later arm is not compared, nor evaluated: add `IF n EQUALS 0 THEN 5` as a third arm, and zero is the only input that makes it true, but L4 never reaches it at zero, and the rule is still covered.
  When no input L4 tries agrees, the rule is covered by its conditions as written instead, and the same check is made of them.
  Where they lose the input too, as in `CONSIDER n WHEN 0 THEN 0 WHEN EXACTLY (1 DIVIDED BY n) THEN 1 OTHERWISE 2`, where zero is the only number the first arm takes and each arm is one condition as written, the rule is not covered: the report says at which input L4 answers and which condition raises there, and the exit status is 3 (from `examples/coverage-report/later-arm.l4`).
  Where they do not, the rule is covered `AT RUNG LEVEL`, and the exit status is 3: in `BRANCH IF n EQUALS 0 OR n EQUALS 100 THEN 0 IF 10 DIVIDED BY n GREATER THAN 2 THEN 1 OTHERWISE 2`, only zero makes `n EQUALS 0` hold, but a hundred makes the first arm hold as zero does.
  Only the inputs L4 tries are checked this way, the candidates listed under [Inputs that no condition reads](#inputs-that-no-condition-reads).
  An input outside them at which a condition raises is not seen, and the buckets in which the earlier arm holds can still be wrongly proved impossible, though L4 answers there.
  For example, a rule whose first arm is `n EQUALS cap`, where `cap` is `3 TIMES 5`, and whose second condition divides by `n MINUS cap`: no condition writes 15, so 15 is not tried, and the two buckets in which the first condition holds are proved impossible, though L4 answers 0 at 15.
  An input at which the rule itself raises an error, as well as a condition, has no answer to lose, and is left out of every bucket.
- **Witnessed** means the input realises the bucket and the evaluator agrees.
  The inputs come from a fixed set of candidates, the values listed above under "Inputs that no condition reads", at most eight per bucket.
  An input outside that set is a witness only for a bucket that no candidate lands in: then the solver supplies one, and its row says it was found by the solver.
  When one input's kind has no value two levels deep, there are no candidates, and every witness is the solver's; see above.
- **Proved impossible** is the solver's claim alone, and nothing else checks it.
- **Undecided** is neither, with its reason, and is never counted as covered.
- **An input that no condition reads** is tried at the same values as any other input of its kind, but no bucket depends on it, so the answers shown may vary with it; see above.
- **A rule that reads an `ASSUME`** is not covered, because an input cannot supply one.
  A rule whose body is wrapped in `WHERE` or `LET` is covered only if it returns true or false.
- **Only this file's rules.**
  Rules in imported files are called, but not covered.

## Related

- [`l4 prove`](proving-assertions.md) answers a different question: whether an assertion you wrote holds for every input.
  The two share a solver.
- [`l4 export catala`](../../exports/catala.md) uses the same buckets to decide which inputs to test its output at, and to check the Catala it writes against L4.
- The same exit-status and closing-line conventions as [`l4 explore`](../../reference/regulative/explore.md) apply: the last line says what was not done.
