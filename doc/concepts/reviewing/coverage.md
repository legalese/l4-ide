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

L4 tries each input at values taken from the conditions: the numbers they mention, one either side of each, zero, both truth values, every option of a choice.
An input that **no condition reads** has nothing to take values from, so it is tried at one value only (zero, for a number).
The report names such inputs under the heading of the decision:

```
  Inputs no condition reads (tried at one value only, so the answers below may vary with them): income
```

The answers shown for that decision are then answers at that one value, and the rule may answer differently at others.

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
  The separate conditions in the conditions a rule branches on: an `UNLESS` chain, a `BRANCH` or `IF`, or the body of a rule that returns true or false.
  `a OR b` is two; a condition used twice is one.
  A call to another rule is **one** cover point, and its body is not read.
  A condition inside the _result_ of one arm is not a cover point.
- **How many.**
  With _n_ cover points there are 2ⁿ buckets, and past twelve cover points the rule is covered by its conditions as written instead: the report says `AT RUNG LEVEL` and why, and the exit status is 3.
  It does the same where a condition raises an error at an input that an earlier condition of the same rule already decides, such as `x EQUALS 0` guarding `10 DIVIDED BY x GREATER THAN 2`: that input would otherwise belong to no bucket.
- **Witnessed** means the input realises the bucket and the evaluator agrees.
  The inputs come from a fixed set of candidates (each number the rule mentions, one either side of it, zero, both truth values, every option of a choice), at most eight per bucket, so the report does not depend on which solver is installed.
  An input outside that set is not tried.
- **Proved impossible** is the solver's claim alone, and nothing else checks it.
- **Undecided** is neither, with its reason, and is never counted as covered.
- **An input that no condition reads** is tried at one value only; see above.
- **A rule that reads an `ASSUME`** is not covered, because an input cannot supply one.
  A rule whose body is wrapped in `WHERE` or `LET` is covered only if it returns true or false.
- **Only this file's rules.**
  Rules in imported files are called, but not covered.

## Related

- [`l4 prove`](proving-assertions.md) answers a different question: whether an assertion you wrote holds for every input.
  The two share a solver.
- [`l4 export catala`](../../exports/catala.md) uses the same buckets to decide which inputs to test its output at, and to check the Catala it writes against L4.
- The same exit-status and closing-line conventions as [`l4 explore`](../../reference/regulative/explore.md) apply: the last line says what was not done.
