# REFUSE

An expression, at any type, that stops evaluation because the model declines to answer, and says why.

## Syntax

```l4
REFUSE "message"
```

The message is a **string literal**.
It is not an arbitrary expression: a refusal's reason is meant to be readable without running the program.

**Example file:** [refuse-example.l4](refuse-example.l4)

## When to use it

Some questions a model should not answer.
The law being encoded stops somewhere: a commencement date below which there is nothing to say, a relief whose eligibility turns on facts the encoding does not model, a schedule that has not been written yet.
The honest answer there is not a number.

`REFUSE` says so directly.
Nothing downstream can turn it into an answer, and it is not a parameter of the function.

The other devices each give a wrong kind of answer:

- **A default value** ("return 0 below commencement") is a silently wrong answer, and the caller cannot tell it from a real one.
- **`NOTHING`** can be handled: a `CONSIDER` downstream turns "we decline" into "use the default".
- **`ASSUME`** says "this is an unknown fact", so it becomes a required input.
  A caller of the decision is then asked to supply a value for _"no figure exists before commencement"_, and nobody can supply that, because it is not a fact.

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
There is no catch construct. A refusal stops at the `#EVAL` or `#ASSERT` that reached it, which reports it as its own outcome rather than as a value.

### Order matters, and it is left to right

`AND` and `OR` are lazy, so which operand is forced first decides whether a refusal is reached:

```l4
#ASSERT NOT (FALSE AND `not modelled`)   -- answers FALSE; the refusal is never forced
#EVAL `not modelled` AND FALSE           -- refuses
```

So L4's connectives are not commutative in the presence of a refusal.

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
| the query plan       | `"determined": null`, no question asked, and the reason under `"refusal"`. A refusal that always happens is never a question, so a wizard never asks it                                                                                                                                                                  |

## The query plan reaches a refusal where evaluation does

The decision service's query plan (`/query-plan`), which a wizard uses to choose its next question, reads a rule that refuses the way evaluation does: left to right, stopping as soon as the answer is known.
For this rule:

```l4
GIVETH A BOOLEAN
`the other conditions are not modelled` MEANS
    REFUSE "the other conditions are not modelled"

GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
eligible adult MEANS adult AND `the other conditions are not modelled`
```

the plan asks one question, `adult`.
Answered `FALSE`, the plan says `"determined": false`, as evaluation does without ever reaching the refusal.
Answered `TRUE`, it says `"determined": null`, asks nothing more, and gives the reason evaluation gives under `"refusal"`.
`` `the other conditions are not modelled` `` is never asked, because no answer to it would ever be used: evaluation does not take one, it reaches the `REFUSE`.
Written the other way round, as `` `the other conditions are not modelled` AND adult ``, the plan shows the refusal before anything is asked, because evaluation reads the refusal first.

The plan treats two things as a refusal that always happens: a `REFUSE` written as an operand of `AND`, `OR` or `NOT`, and a rule of no inputs that always refuses.
A rule always refuses when its body is a `REFUSE`, or names a rule of no inputs that always refuses, however many steps away; a `WHERE` or `LET` around it makes no difference.
A rule that refuses on only some paths, such as one ending `ELSE REFUSE "…"`, is a question (see the limits below).

`"refusal"` is `null` in every other answer.
When it is not, it holds `"reasons"`, the reasons evaluation would give, and `"atoms"`, the refusing leaves the plan reached.
Where more than one refusal can be the first one reached, `"reasons"` lists each of them.

In the service, a rule with a refusal in it is drawn as written, not simplified, so its ladder diagram shows it as written too.
Simplifying distributes `OR` over `AND`, and that can change which refusal evaluation reaches first.

## Limits

- **The message must be a string literal.**
  `REFUSE 42` is a type error; `REFUSE (1 PLUS 1)` does not parse.
  Interpolated or computed reasons are not supported.
- **Order-dependence under lazy `AND` / `OR`**, as above.
- **`REFUSE` is a reserved word.**
  A name spelled `REFUSE` must be written in backticks.
- **The query plan sees a refusal only where it can name one**: a `REFUSE` written as an operand of `AND`, `OR` or `NOT`, or a rule of no inputs that always refuses.
  Everything else is asked, and an answer to it is used by the plan where evaluation would refuse instead.
  That covers a rule of no inputs that refuses on only some paths, because whether it refuses can turn on what the plan does not see, such as the date the rules are read at.
  It covers a `REFUSE` on an arm of an `IF`, and a refusal inside an `IMPLIES`, each of which the plan asks as part of one question, and a call with inputs to a rule that refuses.
  And names are not followed into other files, so a refusal reached only through an `IMPORT` is not seen.
- **In the editor, the plan follows the ladder as drawn.**
  The editor's wizard plans from the ladder the panel shows, and that ladder is drawn as written unless you switch simplification on.
  With it on, a refusal inside an `OR` of `AND`s can be planned in the simplified order rather than the written one.
  The REPL's `:queryplan` always plans from the simplified ladder.
- **The WASM backend does not run a refusal.**
  An exported function that contains one, or calls a definition that does, is marked unsupported, so the request is answered by the evaluator, which raises the refusal properly.
- **A batch carries on after a refusal.**
  In `l4 batch` the row's `status` is `refused` and its `result` is `{"refused": {"reason": …}}`; the batch carries on with the next row, and the command still exits 0.
  In the service's batch endpoint the case comes back with `@error` set to `The model refuses to answer:` and the reason, and is counted in `casesIgnored`.
- **Other displays.**
  The ladder and query-plan diagrams draw a refusal written in a rule's body as a labelled leaf, and the document export prints it as prose and does not read it as part of a formula.
- **Nothing lists the reasons a function can refuse for.**
  A rule that can decline gives no warning before it is run.

## Related

- **[IF](IF.md)** and **[CONSIDER](CONSIDER.md)**: the arms that reach a refusal
- **[Testing your rules](../../tutorials/getting-started/testing-your-rules.md)**: what an assertion's outcomes look like
