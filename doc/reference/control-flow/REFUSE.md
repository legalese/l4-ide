# REFUSE

`REFUSE "reason"` declines to answer, and gives the reason.
Rules encode some cases and leave others out: a fee schedule may start in the year 2000, or a scheme may leave the case of a minor to an officer.
Where a rule reaches a case it does not encode, `REFUSE` gives no answer rather than a wrong one, and says why, and the tools that evaluate L4 report it as a refusal, with that reason ([What each tool shows](#what-each-tool-shows)).

## Syntax

```text
REFUSE "reason"
```

The reason is a string literal, written as a reader should see it.
A `REFUSE` stands wherever a value can, whatever the type of that value: a rule that gives a number, a `BOOLEAN` or a record can refuse.

**Example file:** [refuse-example.l4](refuse-example.l4)

## Examples

Give each reason a definition of its own, named for what is not encoded, and use the name where the rule needs it:

```l4
GIVETH A NUMBER
`fees before 2000 are not encoded` MEANS
    REFUSE "this schedule is not encoded for years before 2000"

GIVEN year IS A NUMBER
GIVETH A NUMBER
`the fee in` year MEANS
    IF year >= 2000
    THEN 100
    ELSE `fees before 2000 are not encoded`

#EVAL `the fee in` 2024
#EVAL `the fee in` 1999
```

The first `#EVAL` gives `100`, and the second prints:

```text
The model refuses to answer:
  this schedule is not encoded for years before 2000
```

A rule that answers yes or no refuses the same way:

```l4
GIVETH A BOOLEAN
`the insurance of a minor is not modelled` MEANS
    REFUSE "the insurance of a minor is not modelled"

GIVEN adult   IS A BOOLEAN
      insured IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE covered IS
    IF adult
    THEN insured
    ELSE `the insurance of a minor is not modelled`
```

`covered TRUE TRUE` is `TRUE`, and `covered FALSE TRUE` refuses, with the reason "the insurance of a minor is not modelled".

To use one refusal in rules of different types, declare it for any type, with `GIVEN a IS A TYPE` and `GIVETH AN a`:

```l4
GIVEN a IS A TYPE
GIVETH AN a
`not written yet` MEANS
    REFUSE "this rule has not been written yet"

GIVETH A NUMBER
`the deposit` MEANS 1 PLUS `not written yet`

GIVETH A BOOLEAN
`the deposit is refundable` MEANS `not written yet`
```

Both rules refuse, with the reason "this rule has not been written yet".

## Which refusals are reached

`AND`, `OR` and `IF` read from left to right, and stop as soon as the answer is known, so a `REFUSE` they do not reach does not refuse:

```l4
#EVAL FALSE AND `the insurance of a minor is not modelled`
#EVAL `the insurance of a minor is not modelled` AND FALSE
#EVAL TRUE OR `the insurance of a minor is not modelled`
```

The first gives `FALSE` and the third `TRUE`.
The second refuses, because it reaches the refusal before the `FALSE`.
So write first what settles the cases a rule encodes, and the refusal where only the other cases reach it, as `covered` does with its `IF`.

## A refusal cannot be caught

Once a rule reaches a `REFUSE`, everything that needs its value refuses too, with the same reason.
No construct turns a refusal back into a value: `NOT` of a refusal refuses, and so does a `CONSIDER` or an `IF` on one.

```l4
#EVAL NOT `the insurance of a minor is not modelled`
#EVAL CONSIDER covered FALSE TRUE
        WHEN TRUE  THEN "covered"
        WHEN FALSE THEN "not covered"
```

Both refuse, with the reason "the insurance of a minor is not modelled".
A rule that uses a rule that refuses gives the same refusal to whatever uses it in turn.

## Testing a refusal: `#ASSERT REFUSED`

`#ASSERT REFUSED expression` holds when the expression refuses.
`#ASSERT REFUSED expression BECAUSE "reason"` holds when it refuses with exactly that reason.

```l4
#ASSERT REFUSED `the fee in` 1999
#ASSERT REFUSED `the fee in` 1999 BECAUSE "this schedule is not encoded for years before 2000"
#ASSERT REFUSED covered FALSE TRUE
    BECAUSE "the insurance of a minor is not modelled"
```

The reason after `BECAUSE` is a string literal.
`BECAUSE` goes on the line of the `#ASSERT`, or at the start of a line of its own indented further than the `#ASSERT`.

An `#ASSERT REFUSED` reports one of these:

- `assertion satisfied`, when the expression refuses, with the reason after `BECAUSE` if there is one;
- `assertion failed: expected a refusal, but the expression produced a value`, when it gives a value;
- `assertion failed: expected the refusal "…", got "…"`, naming both reasons, when it refuses with another reason;
- `assertion could not be evaluated:` and the cause, when its evaluation stops with an error, such as a division by zero or a term that is only `ASSUME`d;
- `assertion could not be evaluated:` and `The value goes deeper than a directive reads, so whether it refuses below that depth is not known.`, when it gives a value deeper than a directive reads, such as a list of more than 200 items.

In `l4 run --json`, an `#ASSERT REFUSED` is a result whose `"kind"` is `"assertion"`, with `"value": true` when it holds, and `"value": false` and the message under `"error"` when it fails.

A plain `#ASSERT` of an expression that refuses reports `assertion refused:` and the reason, which is neither satisfied nor failed; see [What `#ASSERT` reports](../syntax/README.md#what-assert-reports).

## What each tool shows

Each of these reports a refusal as a refusal, with the reason as the rule wrote it, in a form of its own:

| Where                               | What a refusal shows                                                                                                                                                   |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `l4 run`                            | `The model refuses to answer:`, then the reason on the next line, indented; `l4 run` exits `0` for it                                                                  |
| `l4 run --json`                     | a result whose `"kind"` is `"refused"`, with the `"reason"`                                                                                                            |
| `l4 batch`                          | for that row, `"status": "refused"` and the result `{"refused": {"reason": …}}`; the rows after it are evaluated as usual                                              |
| `l4 trace`, and the REPL's `:trace` | `↯ refused:` and the reason, at the step that refuses                                                                                                                  |
| The REPL, and its `:traceascii`     | `Refused:` and the reason                                                                                                                                              |
| The editor                          | a warning at the directive: `The model refuses to answer:` and the reason                                                                                              |
| The editor's Inspector              | `The model refuses to answer:` and the reason, shown neither as a success nor as a failure                                                                             |
| The service's `/evaluation`         | a body whose `contents` is `{"kind": "refused", "reason": …}`                                                                                                          |
| The service's `/evaluation/batch`   | for that case, `"@refused": {"kind": "refused", "reason": …}` in place of a `value`; the case is counted in `casesProcessed`                                           |
| The service's MCP tools             | a result whose text is the body `/evaluation` gives, with `"kind": "refused"` and the reason                                                                           |
| A query plan                        | no plan for a rule that may refuse, and the sentence `No query plan for covered: it may refuse to answer, with the reason "the insurance of a minor is not modelled".` |

The service marks a refusal by `"kind": "refused"`, and answers it with `422`, the HTTP status of an evaluation that stops with an error:

```json
{
  "contents": {
    "kind": "refused",
    "reason": "this schedule is not encoded for years before 2000"
  },
  "tag": "Error"
}
```

An MCP tool call answers a refusal with `isError: true`, and that body as its text.
So tell a refusal by its `kind`: the `contents` of an error has a `tag` of its own, and an MCP error's text is the error's message.

## The query plan

A query plan names the inputs still needed to settle a rule's answer.
A rule that may refuse has no query plan, whatever it answers and whatever inputs are already known: the planner declines it, and names each reason the rule may refuse with.
A rule may refuse when a `REFUSE` is written in it, or in a rule it uses, directly or through others, in its own file or in one it imports, whether or not the inputs given reach that `REFUSE`.
The service answers such a rule with `400`, `"kind": "declined"`, the `rule`, its `reasons` and the sentence in the table above; [The decision graph and the query plan](../functions/DECIDE.md#the-decision-graph-and-the-query-plan) says what else a plan can be declined for.

## In a rendered document

`l4 render` writes a `REFUSE` as "the model refuses to answer:" and the reason in quotes, wherever it sits.
Under `AND`, it is listed among the conditions that must all be true:

```l4
GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `may travel` IF
    adult AND REFUSE "travel is not modelled"
```

is rendered as

```text
• May travel holds if:
    all of the following are true:
    - adult
    - the model refuses to answer: “travel is not modelled”
```

Read such a line as the point at which the rule stops without an answer: the rule reaches it only when what comes before it has not settled the answer, here for an adult.
A refusal with a name of its own is written by its name, as `covered` reads "otherwise: the insurance of a minor is not modelled".

## Limits

- The reason is the string literal beside `REFUSE`: `REFUSE 42` is a type error, and `REFUSE ("a" APPEND "b")` is a parse error.
  In `REFUSE "a" APPEND "b"`, `REFUSE` takes `"a"` alone, so the rule refuses with the reason "a".
- A directive prints the reason exactly as written, spaces included, and `REFUSE ""` refuses with an empty reason.
- `REFUSE` is a keyword, so a definition named `REFUSE` is written in backticks, `` `REFUSE` ``.
- An operator with more than one meaning must be able to tell the type of a refusal it is given.
  Under `IMPORT daydate`, `PLUS` adds numbers and dates, so L4 must be able to tell whether a refusal added to a number stands for a number or for a date.
  A `GIVETH A NUMBER` on a rule whose answer is the sum, or on the named refusal, tells it, so `` `the deposit` `` above checks under `IMPORT daydate`.
  So does using the sum where only a number fits, as in `(1 PLUS REFUSE "…") TIMES 2`, or passing it to a function whose input is a number.
  Brackets around the `REFUSE` do not tell it, and neither does declaring the refusal for any type.
  Where nothing tells it, as in a rule `x MEANS 1 PLUS REFUSE "…"` with no `GIVETH`, or in `(1 PLUS REFUSE "…") EQUALS (1 PLUS REFUSE "…")` even in a rule with `GIVETH A NUMBER`, L4 reports "There are multiple definitions for the identifier".
- The WASM backend (`jl4-mlir`) marks a function that may refuse, through its own `REFUSE` or one in a definition it calls, `"supported": false`, with the reason "REFUSE is not supported by the WASM backend".
  Evaluate such a function with jl4-service, which reports its refusal as the table above says.

## Related pages

- [IF](IF.md) and [CONSIDER](CONSIDER.md): choosing between values
- [What `#ASSERT` reports](../syntax/README.md#what-assert-reports): the outcomes of a plain `#ASSERT`, a refusal among them
- [DECIDE](../functions/DECIDE.md): rules, and their decision graph and query plan
- [Control flow](README.md)
