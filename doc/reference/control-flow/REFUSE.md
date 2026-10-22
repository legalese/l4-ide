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
| `l4 run` (text)      | the lines above. **Exit code 0**: a refusal is an answer, not a crash. An error keeps exit code 1                                                                                                                                                                                                                        |
| `l4 run --json`      | a refusing `#EVAL` gets `"kind": "refused"` with a `"reason"`. A refused `#ASSERT` keeps `"kind": "assertion"` with a null `"value"` and its reason under `"refused"`, not `"error"`                                                                                                                                     |
| editor diagnostics   | a **Warning**, not an Error: a refusal is a designed outcome, and Error would mark every deliberate refusal as a defect                                                                                                                                                                                                  |
| the decision service | an error of its own kind, `EvaluatorRefused`, never an interpreter error (which would read as a server fault). `/evaluation` answers 422 with the bare reason as `contents`; the text `The model refuses to answer:` and the reason is what a batch case's `@error` and a Model Context Protocol (MCP) tool result carry |
| the Inspector        | `success` is **absent**, never `false`: a refusal is not a negative verdict. The browser API (`L4.API`) answers `"success": null`                                                                                                                                                                                        |
| the REPL             | `Refused: ` and the reason                                                                                                                                                                                                                                                                                               |
| an execution trace   | `↯ refused: <reason>`, a first-class event distinct from a crash, in the `l4 trace` text and in the `--format dot` node label                                                                                                                                                                                            |
| the query plan       | `"determined": null`, no question asked, and the reason under `"refusal"`. A refusal the plan reads is never a question, so a wizard never asks it; one it cannot read is a 400                                                                                                                                          |

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

The plan reads a refusal that sits in any of these places:

- the whole rule;
- an operand of `AND`, `OR`, `NOT` or `IMPLIES`;
- the condition, or an arm, of an `IF` that itself sits in one of these places, including an `IF` inside an arm of an `IF`.

What it reads there is a `REFUSE`, or a rule of no inputs that always refuses.
A rule always refuses when its body is a `REFUSE`, or names a rule of no inputs that always refuses, however many steps away; a `WHERE` or `LET` around it makes no difference.
A rule that refuses on only some paths, such as one ending `ELSE REFUSE "…"`, is a question (see the limits below).

`"refusal"` is `null` in every other answer.
When it is not, it holds `"reasons"`, the reasons evaluation would give, and `"atoms"`, the refusing leaves the plan reached.
Where more than one refusal can be the first one reached, `"reasons"` lists each of them.
An answer that would lead to a refusal shows under `"impact"` as `"determined": null` with `"support": []`, the same as an answer that settles nothing, so send the plan that answer and read its `"refusal"`.

In the service, a rule with a refusal in it is drawn as written, not simplified, so its ladder diagram shows it as written too.
Simplifying distributes `OR` over `AND`, and that can change which refusal evaluation reaches first.

An `IMPLIES` in such a rule is read as the `OR` it stands for: ``adult IMPLIES `the other conditions are not modelled` `` is ``NOT adult OR `the other conditions are not modelled` ``.
The plan asks `adult`, says `"determined": true` where it is answered `FALSE`, and gives the refusal where it is answered `TRUE`, as evaluation does.

An `IF` is read as the choice it is: the condition first, and then only the arm the condition picks.
For this rule:

```l4
GIVETH A BOOLEAN
`not encoded for non-residents` MEANS
    REFUSE "the rules for non-residents are not encoded"

GIVEN resident IS A BOOLEAN
GIVETH A BOOLEAN
eligible resident MEANS
    IF resident
    THEN TRUE
    ELSE `not encoded for non-residents`
```

the plan asks one question, `resident`.
Answered `TRUE`, it says `"determined": true`; answered `FALSE`, it says `"determined": null` and gives the refusal.
Beside other operands, as in `(IF b THEN c ELSE r) AND a`, the `IF` is read before the `a` that follows it, so an answer to `a` alone does not settle the plan.
A condition that is a call to a rule with inputs is read once for each arm, so `stillNeeded` lists it twice; `asks` names its input once.

### A refusal the plan cannot read

Anywhere else a rule can hold a refusal, the service does not plan it: `/query-plan` answers 400 with an `"error"` that says where the first one sits.
Those places are an arm of a `CONSIDER`, an operand of a comparison or of `EQUALS`, and a call, with or without inputs, to a rule that always refuses.
Evaluation reaches a refusal there only when the part around it is evaluated, and the plan has no way to read that part: it could treat it only as one yes-or-no question, which evaluation never asks.
For ``adult AND (`the fee` GREATER THAN 3)``, where `` `the fee` `` is a rule of no inputs that always refuses, the answer is:

```json
{
  "error": "The query plan cannot order the questions for this rule, because a refusal (\"no fee is modelled\") sits inside this part of it: `the fee` GREATER THAN 3"
}
```

A long part is cut short with `...`.
Only the rule being planned is read, so another rule in the same file is planned as any rule is.
The same call to a rule that answers is planned as a question.

## Limits

- **The message must be a string literal.**
  `REFUSE 42` is a type error; `REFUSE (1 PLUS 1)` does not parse.
  Interpolated or computed reasons are not supported.
- **Order-dependence under lazy `AND` / `OR`**, as above.
- **`REFUSE` is a reserved word.**
  A name spelled `REFUSE` must be written in backticks.
- **Some refusals are asked as questions.**
  A rule of no inputs that refuses on only some paths is a question, because whether it refuses can turn on what the plan does not see, such as the date the rules are read at.
  The plan uses the answer it is given, where evaluation would evaluate the rule instead, and the rule may refuse.
  A call with inputs to a rule that refuses on only some paths is a question too: once the input the call names is answered, the plan takes that answer as the call's.
  With `` `some paths` person MEANS IF person THEN TRUE ELSE REFUSE "…" `` and ``adult AND `some paths` applicant``, the plan says `"determined": false` when `applicant` is answered `FALSE`, where `/evaluation` refuses.
  And names are not followed into other files, so a refusal reached only through an `IMPORT` is not seen.
- **In the editor and the REPL, the plan follows the ladder as drawn, and does not read a refusal as the service does.**
  The editor's wizard plans from the ladder the panel shows, which is drawn as written unless you switch Simplified on.
  The REPL's `:queryplan` always plans from the simplified ladder.
  Simplifying distributes `OR` over `AND`, so with Simplified on, and in the REPL, the plan can report a refusal where evaluation answers.
  For `(a AND r1) OR (b AND c)`, where `r1` is a rule that always refuses, and `a` `FALSE`, `b` `TRUE` and `c` `TRUE`, evaluation answers `TRUE` and the plan reports the refusal.
  With Simplified off, the editor draws an `IMPLIES` as one question and answers it with the value of the one input it names directly, so `b IMPLIES (NOT c)` can be answered wrongly, with a refusal in the rule or without.
  An `IF` whose arms are not single names is drawn as one question in the editor with Simplified on or off and in the REPL, with the same result: `IF b THEN (c AND d) ELSE (NOT d)` can be answered wrongly, with a refusal in the rule or without.
  Neither the editor nor the REPL spells out an `IF` or an `IMPLIES`, and neither answers 400.
  A refusal inside an `IF` can be answered where evaluation refuses, and a refusal in a comparison is listed in `stillNeeded` as a question.
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
