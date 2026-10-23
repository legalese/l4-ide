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

A Boolean decision that calls a helper which refuses on only some paths, such as `the fee in year` above, gets a 400 from the query plan and not a wrong verdict.
For a rule that a questionnaire is built over, keep the refusal in its own definition of no inputs that always refuses, and name it in the decision.

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
There is no catch construct.
A refusal stops at the `#EVAL` or `#ASSERT` that reached it, which reports it as its own outcome rather than as a value.

### Order matters, and it is left to right

`AND` and `OR` are lazy, so which operand is forced first decides whether a refusal is reached:

```l4
#ASSERT NOT (FALSE AND `not modelled`)   -- holds: the AND answers FALSE and the refusal is never forced
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
| `l4 run` (text)      | the lines above. **Exit code 0**: a refusal is an outcome, not a crash. An error keeps exit code 1                                                                                                                                                                                                                       |
| `l4 run --json`      | a refusing `#EVAL` gets `"kind": "refused"` with a `"reason"`. A refused `#ASSERT` keeps `"kind": "assertion"` with a null `"value"` and its reason under `"refused"`, not `"error"`                                                                                                                                     |
| editor diagnostics   | a **Warning**, not an Error: a refusal is a designed outcome, and Error would mark every deliberate refusal as a defect                                                                                                                                                                                                  |
| the decision service | an error of its own kind, `EvaluatorRefused`, never an interpreter error (which would read as a server fault). `/evaluation` answers 422 with the bare reason as `contents`; the text `The model refuses to answer:` and the reason is what a batch case's `@error` and a Model Context Protocol (MCP) tool result carry |
| the Inspector        | `success` is **absent**, never `false`: a refusal is not a negative verdict. The browser API (`L4.API`) answers `"success": null`                                                                                                                                                                                        |
| the REPL             | `Refused: ` and the reason                                                                                                                                                                                                                                                                                               |
| an execution trace   | `↯ refused: <reason>`, a first-class event distinct from a crash, in the `l4 trace` text and in the `--format dot` node label                                                                                                                                                                                            |
| the query plan       | `"determined": null`, no question asked, and the reason under `"refusal"`. A refusal the plan reads is never a question, so a wizard never asks it; the service and the web editor answer 400 for one they cannot read                                                                                                   |

## The query plan reaches a refusal where evaluation does

The decision service's query plan (`/query-plan`), which a wizard uses to choose its next question, reads a rule that refuses the way evaluation does: left to right, stopping as soon as the answer is known.
Where the plan is made decides whether a questionnaire over a rule that refuses can be trusted:

| where the plan is made                  | what it does with a refusal                                                                                                                                                       |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| the decision service and the web editor | reads a refusal as `/evaluation` does, or answers 400 and says which part of the rule it cannot read, except a refusal in another file and a call with inputs ([Limits](#limits)) |
| VS Code and the REPL                    | can answer where evaluation refuses, and report a refusal where evaluation answers ([below](#in-vs-code-and-the-repl))                                                            |

For this rule, where `adult` is a Boolean input (the `GIVEN` and `GIVETH` lines are left out):

```l4
`the other conditions are not modelled` MEANS
    REFUSE "the other conditions are not modelled"

eligible adult MEANS adult AND `the other conditions are not modelled`
```

the plan asks one question, `adult`.
Answered `FALSE`, it says `"determined": false`, as evaluation does without ever reaching the refusal; answered `TRUE`, it says `"determined": null`, asks nothing more (the refusing rule is never asked, since evaluation takes no answer for it), and gives the reason evaluation gives under `"refusal"`.

### What the service and the web editor read

They read a refusal in the whole rule, in an operand of `AND`, `OR`, `NOT` or `IMPLIES`, or in the condition or an arm of an `IF` that itself sits in one of these places.
What they read there is a `REFUSE`, or a rule of no inputs that always refuses: one whose body is a `REFUSE`, or names such a rule.

### When the plan answers 400

A rule that holds a refusal the plan cannot read is not planned: `/query-plan` answers 400 with an `"error"` that says where the first one may be reached from, for either of these:

- **A refusal inside a part that is not an `AND`, `OR`, `NOT`, `IMPLIES` or Boolean `IF`**: an arm of a `CONSIDER`, an operand of a comparison or of `EQUALS`, a `LET` binding.
- **A call to a rule that refuses, other than a rule of no inputs that always refuses**: a rule with inputs that always refuses, and any rule that refuses on only some paths, such as one ending `ELSE REFUSE "…"`, whether or not it takes inputs and whether or not evaluation reaches the refusal.
  The plan declines such a rule even when the refusal is on a path the inputs never take, as in `a AND check a` where `check a` refuses only when `a` is `FALSE`.

For this rule, where `` `the scheme is open` `` is a rule of no inputs that is `FALSE` (the `GIVEN` and `GIVETH` lines are left out):

```l4
`the residence test is met` MEANS
    IF `the scheme is open` THEN TRUE
    ELSE REFUSE "the residence test is not modelled once the scheme is closed"

eligible adult MEANS adult AND `the residence test is met`
```

`/evaluation` refuses wherever the residence test is read, but the plan does not look inside it, so it cannot tell, and it answers 400 instead of asking the test as a question:

```json
{
  "error": "The query plan cannot order the questions for this rule, because a refusal (\"the residence test is not modelled once the scheme is closed\") may be reached from this part of it: `the residence test is met`"
}
```

### In VS Code and the REPL

- VS Code plans from the ladder its panel shows, drawn as written unless Simplified is switched on, and the REPL's `:queryplan` from the simplified ladder; neither spells out an `IF` or an `IMPLIES`, and neither answers 400, so a part the service cannot read is listed in `stillNeeded` as a question.
- So the plan can answer where evaluation refuses, and report a refusal where evaluation answers: plan with the service or the web editor, or check against `/evaluation`; the shapes are in `specs/as-built/refuse.md`.

## Limits

- **The message must be a string literal.**
  `REFUSE 42` is a type error; `REFUSE (1 PLUS 1)` does not parse.
  Interpolated or computed reasons are not supported.
- **Order-dependence under lazy `AND` / `OR`**, as above.
- **`REFUSE` is a reserved word.**
  A name spelled `REFUSE` must be written in backticks.
- **Names are not followed into other files.**
  A refusal reached only through an `IMPORT` is not seen, and the name is asked as a question.
- **A call with inputs is planned as the input it names.**
  When a call that is an operand of `AND`, `OR` or `NOT` depends on one input, the plan takes the answer to that input as the call's own, whatever the called rule does with it.
  So the plan can answer where evaluation answers otherwise, and this does not depend on a refusal.
  As the condition of an `IF` in a rule that holds a refusal, a call is read the same way, because the `IF` is spelled out as `AND`, `OR` and `NOT`.
  With `` `never no` person MEANS NOT person `` and ``adult AND `never no` applicant``, the plan says `"determined": true` when `adult` and `applicant` are `TRUE`, where `/evaluation` says `FALSE`.
- **The WASM backend does not run a refusal.**
  An exported function that contains one, or calls a definition that does, is marked unsupported, so the request is answered by the evaluator, which raises the refusal properly.
- **A batch carries on after a refusal.**
  In `l4 batch` the row's `status` is `refused`, its `result` is `{"refused": {"reason": …}}` and its `diagnostics` give the reason; the batch carries on with the next row, and the command still exits 0.
  In the service's batch endpoint the case comes back with `@error` set to `The model refuses to answer:` and the reason, and is counted in `casesIgnored`.
- **Other displays.**
  The ladder and query-plan diagrams draw a refusal written in a rule's body as a labelled leaf, and the document export prints it as prose and does not read it as part of a formula.
- **Nothing lists the reasons a function can refuse for.**
  A rule that can decline gives no warning before it is run.

## Related

- **[IF](IF.md)** and **[CONSIDER](CONSIDER.md)**: the arms that reach a refusal
- **[Testing your rules](../../tutorials/getting-started/testing-your-rules.md)**: what an assertion's outcomes look like
