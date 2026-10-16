# REFUSE

An expression, at any type, that stops evaluation because the model declines to answer, and says why.

## Syntax

```l4
REFUSE "message"
```

The message is a **string literal**.
It is not an arbitrary expression: a refusal's reason is meant to be readable without running the program.

**Example file:** [refuse-example.l4](refuse-example.l4)

## Why it exists

Some questions a model should not answer.
The law being encoded stops somewhere: a commencement date below which there is nothing to say, a relief whose eligibility turns on facts the encoding does not model, a schedule that has not been written yet.
The honest answer there is not a number.

Before `REFUSE`, authors reached for the nearest available device, and each one was wrong in a way that mattered:

- **A default value** ("return 0 below commencement") is a silently wrong answer, and the caller cannot tell it from a real one.
- **`NOTHING`** can be handled: a `CONSIDER` downstream turns "we decline" into "use the default", which is exactly the laundering the refusal was meant to prevent.
- **`ASSUME`** says "this is an unknown fact", so it becomes a required input.
  A caller of the decision is then asked to supply a value for _"no figure exists before commencement"_, and nobody can supply that, because it is not a fact.

`REFUSE` says the thing directly.
Nothing downstream can turn it into an answer, and it is not a parameter of the function.

## House style: one named definition per refusal

Write the refusal as its own definition, named for what is not covered, and let the arms that reach it read as the source text does:

```l4
GIVETH A NUMBER
`this schedule is not encoded for years before 2000` MEANS
    REFUSE "this schedule is not encoded for years before 2000"

GIVEN y IS A NUMBER
GIVETH A NUMBER
`the fee in year` y MEANS
    IF y AT LEAST 2000
    THEN 100
    ELSE `this schedule is not encoded for years before 2000`
```

A refusal used at more than one type is declared polymorphic:

```l4
GIVEN a IS A TYPE
GIVETH AN a
`this rule has not been written yet` MEANS REFUSE "this rule has not been written yet"
```

A 0-ary definition without `GIVEN a IS A TYPE` is monomorphic: it takes the first type it is used at.
Declare the type variable whenever the refusal serves two rules of different types.

## Uncatchable

Nothing in the language observes a refusal or converts it into an answer: not a `CONSIDER` over a refusing `MAYBE`, not a boolean connective, not a `LET`, not a `WHERE`.
There is no catch construct, and a refusal is caught only at the directive boundary, which reports it as its own outcome rather than as a value.

### Order matters, and it is left to right

`AND` and `OR` are lazy, so which operand is forced first decides whether a refusal is reached:

```l4
#ASSERT NOT (FALSE AND `not modelled`)   -- answers FALSE; the refusal is never forced
#EVAL `not modelled` AND FALSE           -- refuses
```

This is documented, not fixed.
It means L4's connectives are not commutative in the presence of a refusal.

## What each outcome prints

A refusal is neither a value nor an error, and every surface says which it is.

An `#EVAL` that refuses prints `The model refuses to answer:` and the reason.
An `#ASSERT` has four outcomes, not two:

| what happened                      | what is printed                                                 |
| ---------------------------------- | --------------------------------------------------------------- |
| the expression is `TRUE`           | `assertion satisfied`                                           |
| the expression is `FALSE`          | `assertion failed`                                              |
| the expression REFUSED             | `assertion refused:` followed by `The model refuses to answer:` |
| the expression raised, or is stuck | `assertion could not be evaluated:` and the reason              |

`#ASSERT NOT e` where `e` refuses reports **refused**, not failed: `NOT` forces its operand, so the refusal propagates through both polarities.
An assertion suite must be able to tell a wrong answer from a declined one.

| surface              | a refusal shows up as                                                                                                                                                                                                                                                                                                    |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `l4 run` (text)      | the lines above. **Exit code 0**: a refusal is an answer, not a crash. An error keeps exit code 1                                                                                                                                                                                                                        |
| `l4 run --json`      | a refusing `#EVAL` gets `"kind": "refused"` with a `"reason"`. A refused `#ASSERT` keeps `"kind": "assertion"` with a null `"value"` and its reason under `"refused"`, not `"error"`                                                                                                                                     |
| editor diagnostics   | a **Warning**, not an Error: a refusal is a designed outcome, and Error would mark every deliberate refusal as a defect                                                                                                                                                                                                  |
| the decision service | an error of its own kind, `EvaluatorRefused`, never an interpreter error (which would read as a server fault). `/evaluation` answers 422 with the bare reason as `contents`; the text `The model refuses to answer:` and the reason is what a batch case's `@error` and a Model Context Protocol (MCP) tool result carry |
| the Inspector        | `success` is **absent**, never `false`: a refusal is not a negative verdict. The browser API (`L4.API`) answers `"success": null`                                                                                                                                                                                        |
| the REPL             | `Refused: ` and the reason                                                                                                                                                                                                                                                                                               |
| an execution trace   | `↯ refused: <reason>`, a first-class event distinct from a crash, in the `l4 trace` text and in the `--format dot` node label                                                                                                                                                                                            |

## Limits

Stated plainly, because you find these out anyway.

- **The message must be a string literal.**
  `REFUSE 42` is a type error; `REFUSE (1 PLUS 1)` does not parse.
  Interpolated or computed reasons are not supported.
- **Order-dependence under lazy `AND` / `OR`**, as above.
- **`REFUSE` is now a reserved word.**
  A name spelled `REFUSE` must be written in backticks.
- **A questionnaire asks about a refusal.**
  The decision service's `/query-plan`, which orders the questions for a wizard, treats a named zero-input definition as a yes/no question.
  A rule that reaches a refusal through such a definition (the house style above) is planned as if the refusal were a fact to ask for, and an answer to it gives `"determined": true` or `false`, where `/evaluation` refuses.
  A refusal written directly in the rule's body is not asked, and the plan stays undetermined.
  Do not offer a questionnaire over a rule that can refuse until the plan learns about refusals.
- **The WASM backend does not run a refusal.**
  An exported function that contains one, or calls a definition that does, is marked unsupported, so the request is answered by the evaluator, which raises the refusal properly.
- **A batch reports a refusal as it reports an error.**
  In `l4 batch` the row's `status` stays `success` and its `result` is `{"refused": {"reason": …}}`; the batch carries on with the next row.
  In the service's batch endpoint the case comes back with `@error` set to `The model refuses to answer:` and the reason, and is counted in `casesIgnored`.
- **Other displays.**
  The ladder and query-plan diagrams draw a refusal written in a rule's body as a labelled leaf, and the document export prints it as prose and does not read it as part of a formula.
- **The refusal set is not computed.**
  A function does not yet carry the list of reasons it can refuse for, so nothing warns that a rule can decline before it is run.

## Related

- **[IF](IF.md)** and **[CONSIDER](CONSIDER.md)**: the arms that reach a refusal
- **[Testing your rules](../../tutorials/getting-started/testing-your-rules.md)**: what an assertion's outcomes look like
