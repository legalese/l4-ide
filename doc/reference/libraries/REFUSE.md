# REFUSE

A way to say that a rule deliberately does not answer a case, and to say why.

## Syntax

```l4
IMPORT prelude

REFUSE "reason"
```

`REFUSE` is a function in the [prelude](prelude.md).
It takes the reason as a `STRING` and gives back a value of whatever type the surrounding rule needs, so the same `REFUSE` works as a `NUMBER`, a `BOOLEAN`, or any other type.

**Example file:** [refuse-example.l4](refuse-example.l4)

## Why it exists

Some questions a model should not answer.
The law being encoded stops somewhere: a commencement date below which there is nothing to say, a relief whose eligibility turns on facts the encoding does not model, a schedule that has not been written yet.
The honest answer there is not a number.

The nearest alternatives go wrong in a way that matters:

- **A default value** ("return 0 below commencement") is a silently wrong answer, and the caller cannot tell it from a real one.
- **`NOTHING`** can be handled: a `CONSIDER` further down can turn "we decline" into "use the default".

`REFUSE` says the thing directly, in the place where the encoding stops.

## Writing a refusal

Write `REFUSE` where the rule stops, with the reason in words a reader of the source will understand:

```l4
GIVEN year IS A NUMBER
GIVETH A NUMBER
`the fee in year` year MEANS
    IF year AT LEAST 2000
    THEN 100
    ELSE REFUSE "this schedule is not encoded for years before 2000"

GIVEN year IS A NUMBER
GIVETH A BOOLEAN
`the fee is waived in year` year MEANS
    IF year AT LEAST 2000
    THEN FALSE
    ELSE REFUSE "this rule has not been written yet"
```

The first `REFUSE` is a `NUMBER` and the second is a `BOOLEAN`.
Nothing declares either type: `REFUSE` takes the type the rule around it needs.

## What happens when evaluation reaches a refusal

Evaluation that does not reach a `REFUSE` is unaffected: `` `the fee in year` 2024 `` above answers `100`.

Evaluation that does reach one stops.
An `#EVAL` prints

```
I could not continue evaluating, because I needed to know the value of
  REFUSE
but it is an assumed term.
```

and `l4 run` exits with status 1.
The reason you wrote is not part of that message.

## Limits

These are the limits of how `REFUSE` is provided in this version of L4.

- **An `#ASSERT` cannot tell a refusal from a wrong answer.**
  An `#ASSERT` over an expression that reaches a refusal prints `assertion failed`, and prints it again with `NOT` in front, so neither polarity of the assertion holds.
  To find out whether the failure was a refusal, `#EVAL` the same expression.
- **There is no `#ASSERT REFUSED`.**
  Nothing in this version of L4 asserts that an expression refuses, or refuses for a given reason.
- **A refusal written as its own definition with no inputs reports a loop the second time it is reached.**
  Given `` `not covered` MEANS REFUSE "reason" ``, the first `#EVAL` that reaches `` `not covered` `` prints the message above.
  Every later one in the same run prints `Infinite loop detected while trying to evaluate:` followed by `REFUSE OF "reason"`.
  A `REFUSE` written inside a rule that takes inputs, as in the example above, prints the message above on every `#EVAL` that reaches it.
- **`l4 batch` reports a refusing row as `success`.**
  The row's `status` is `success`, and the message above is in the row's `result` under `error`.

## Related

- [prelude](prelude.md): where `REFUSE` is defined, beside the `TBD` placeholder.
  `TBD` stands for a value you have not written yet; evaluating it prints `TBD` rather than stopping.
- [IF](../control-flow/IF.md) and [CONSIDER](../control-flow/CONSIDER.md): the arms that reach a refusal.
