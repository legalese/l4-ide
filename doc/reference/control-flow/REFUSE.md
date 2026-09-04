# REFUSE

An expression, at any type, that stops evaluation because the model declines to answer — and says
why.

## Syntax

```l4
REFUSE "message"
```

The message is a **string literal**. It is not an arbitrary expression: a refusal's reason is meant
to be readable without running the program.

**Example file:** [refuse-example.l4](refuse-example.l4)

## Why it exists

Some questions a model should not answer. The law being encoded stops somewhere — a commencement
date below which there is nothing to say, a relief whose eligibility turns on facts the encoding
does not model, a schedule that has not been written yet. The honest answer there is not a number.

Before `REFUSE`, authors reached for the nearest available device, and each one was wrong in a way
that mattered:

- **A default value** ("return 0 below commencement") is a silently wrong answer, and the caller
  cannot tell it from a real one.
- **`NOTHING`** can be handled: a `CONSIDER` downstream turns "we decline" into "use the default",
  which is exactly the laundering the refusal was meant to prevent.
- **`ASSUME`** says "this is an unknown FACT". So it becomes a required input: it appears in the
  export schema, and a caller of the Reg CF money decisions was asked to supply a value for
  _"no Regulation Crowdfunding figure exists before commencement on 2016-05-16"_. Nobody can supply
  that. It is not a fact.

`REFUSE` says the thing directly. Nothing downstream can turn it into an answer, and it appears in
no export schema, because it is not an input.

## The taxonomy of non-answers

A refusal is one of several ways a rule can decline to produce an ordinary value, and choosing the
right one is a modelling decision. (From `specs/todo/PROPS-REDTEAM-2026-09-03.md` §2.8.)

| the non-answer                           | the construct        | who handles it                                   | catchable?      |
| ---------------------------------------- | -------------------- | ------------------------------------------------ | --------------- |
| a value that may be absent               | `MAYBE`              | the rule, by matching                            | yes, as a value |
| an expected failure with a reason        | `EITHER`             | the rule or its caller                           | yes, as a value |
| a fact not yet known                     | an unsupplied binder | the boundary asks for it                         | n/a             |
| the law does not apply / is not in force | a value or a gate    | savings and transitional provisions can reach it | yes             |
| the model does not cover this            | `REFUSE`             | the boundary only                                | **no**          |
| a breach                                 | `LEST`               | the obligation's own branch                      | structured      |
| an overridden conclusion                 | `SUBJECT TO`         | the overriding rule                              | structured      |

The fourth and fifth rows are close, and the difference is legal, not technical. "Not in force" is
_determinate_ and a savings or transitional provision can operate on it, so it wants a value or a
gate. "The model does not cover this" is a statement about the ENCODING, not about the law, and
nothing in the law can reach it.

## House style: one named definition per refusal

Write the refusal as its own definition, named for what is not covered, and let the arms that reach
it read as the source text does:

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

Keep the definition's `@ref` on it, so the refusal carries its provenance the way every other
provision does.

A refusal used at more than one type is declared polymorphic:

```l4
GIVEN a IS A TYPE
GIVETH AN a
`this rule has not been written yet` MEANS REFUSE "this rule has not been written yet"
```

A 0-ary definition without `GIVEN a IS A TYPE` is monomorphic — it takes the first type it is used
at — so declare the type variable whenever the refusal serves two rules of different types.

The prelude's `TBD` is exactly this, and is the placeholder to reach for while drafting:

```l4
GIVEN a IS A TYPE
GIVETH AN a
TBD MEANS REFUSE "TBD: this rule has not been written yet"
```

## Uncatchable

Nothing in the language observes a refusal or converts it into an answer: not a `CONSIDER` over a
refusing `MAYBE`, not a boolean connective, not a `LET`, not a `WHERE`. There is no catch
construct, and a refusal is caught only at the directive boundary — which reports it as its own
outcome rather than as a value.

That is what makes a refusal analysable: with no handler stack, "can this rule decline?" is
reachability over the call graph rather than a question about control flow.

### Order matters, and it is left to right

`AND` and `OR` are lazy, so which operand is forced first decides whether a refusal is reached:

```l4
#ASSERT NOT (FALSE AND `not modelled`)       -- answers FALSE; the refusal is never forced
#ASSERT REFUSED (`not modelled` AND FALSE)   -- refuses
```

This is documented, not fixed. It means L4's connectives are not commutative in the presence of a
refusal, and it diverges from FEEL's commutative three-valued logic. The regulative connectives
`RAND` / `ROR` force NEITHER side eagerly, so they commit to no demand order at all.

## Testing a refusal

```l4
#ASSERT REFUSED e                        -- e must refuse
#ASSERT REFUSED e BECAUSE "message"      -- ...and the reason must be exactly this
```

A plain `#ASSERT` has four outcomes, not two:

| what happened                      | what is printed                                                 |
| ---------------------------------- | --------------------------------------------------------------- |
| the expression is `TRUE`           | `assertion satisfied`                                           |
| the expression is `FALSE`          | `assertion failed`                                              |
| the expression REFUSED             | `assertion refused:` followed by `The model refuses to answer:` |
| the expression raised, or is stuck | `assertion could not be evaluated:` and the reason              |

`#ASSERT NOT e` where `e` refuses reports **refused**, not failed: `NOT` forces its operand, so the
refusal propagates through both polarities. That is the point — an assertion suite must be able to
tell a wrong answer from a declined one.

`#ASSERT REFUSED` fails, rather than holding, when the expression produces a value
(`assertion failed: expected a refusal, but the expression produced a value`) or refuses with a
different reason than `BECAUSE` named. An expression that RAISES is reported as an error, not as a
refusal — an error is not a refusal, and conflating them would destroy the distinction the
directive exists to test.

## What each surface prints

| surface               | a refusal shows up as                                                                                                                                                                        |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `l4 run` (text)       | `The model refuses to answer:` and the reason. **Exit code 0** — a refusal is an answer, not a crash                                                                                         |
| `l4 run --json`       | a refusing `#EVAL` gets `"kind": "refused"` with `"reason"`; a refused `#ASSERT` keeps `"kind": "assertion"` with a null `"value"` and its reason under `"refused"`, **not** under `"error"` |
| `l4 batch`            | the row's `"status"` is `"refused"` — a third terminal status beside `"success"` and `"error"` — and the batch does **not** stop on it                                                       |
| editor diagnostics    | a **Warning**, not an Error: a refusal is a designed outcome, and Error would squiggle every deliberate refusal in the corpus                                                                |
| the decision service  | its own error kind, never an interpreter error (which would read as a server fault)                                                                                                          |
| `l4/getDirectiveInfo` | `success` is **absent**, not `false`: a refusal is not a negative verdict                                                                                                                    |
| the REPL              | `Refused: ` and the reason                                                                                                                                                                   |
| an execution trace    | `↯ refused: <reason>` — a first-class event, distinct from a crash                                                                                                                           |
| the export schema     | nothing. A refusal is not an input, so it is not a parameter                                                                                                                                 |

That last row is the change worth seeing. In `jl4/examples/legal/regcf/denovo/`, the encoding floor
used to appear in the exported JSON schema as

```json
"no encoding of Part 227 exists for rule dates before 2022-09-20": { "type": "number" }
```

and in that function's `required` list. A caller of the money decisions was being asked to supply
the encoding floor. As a `REFUSE` it is gone from the schema, and the ten-line paragraph in the
source that apologised for it is gone too.

## Limits, as they stand today

Stated plainly, because you find these out anyway; the only question is whether you find out from
us or from a wrong answer.

- **The message must be a string literal.** `REFUSE 42` is a type error; `REFUSE (1 PLUS 1)` does
  not parse. Interpolated or computed reasons are not supported.
- **Order-dependence under lazy `AND` / `OR`**, as above, and no demand order at all under
  `RAND` / `ROR`.
- **`#ASSERT REFUSED e BECAUSE "…"` where `e` ends in a `BREACH`**: `BREACH` itself takes an
  optional `BECAUSE`, and it wins. Bracket the expression if you need the outer reading.
- **The backends do not yet have their designed image for a refusal.** Today every backend refuses
  it loudly and by name — none crashes, and none emits a refusal as something a caller could be
  asked to supply:

  - **DMN** renders the refusing decision verbatim, which marks it Blocking. In
    `jl4/examples/dmn/expected/regcf-corpus.dmn` this means two Blocking notes where there were
    none. The designed image — omit the refusing row, report a **non-Blocking** `D-REFUSE`, and add
    a `MayRefuse` safety kind that does not withdraw `DMN-SAFE` — is not built.
  - **Catala** and **docassemble** refuse the module, naming `REFUSE` (`DA-REFUSE`). The designed
    images (Catala emits no definition; docassemble shows a terminal screen carrying the reason)
    are not built.
  - **OpenFisca** and the **relational / Blawx** path refuse by name. On the relational path this
    matters more than elsewhere: its whole surface is propositional, so a refusal admitted as an
    atom would be something Prolog could assert or negate.
  - **MLIR / WASM** marks the export unsupported, which routes the request to the fallback
    evaluator — and that one raises the refusal properly.

  The full per-backend image is `specs/todo/PROPS-REDTEAM-2026-09-03.md` §6 item 6.

- **The refusal set `Ref(f)` is not built.** The design calls for every function to carry its
  reachable refusal reasons on hover and in the export schema, the way it already carries its
  read-set. It is not here yet.
- **`TBD` is not distinguished from a hand-written refusal.** It reports as an ordinary refusal
  whose reason begins `TBD:`. Warning separately on placeholders needs `Ref(f)` first.
- **Not every curated refusal in the corpus has been migrated**, and each exception says why at its
  own site: `jl4-core/libraries/daydate.l4`'s out-of-range `YMD` is invalid INPUT rather than a
  refusal (a change to that constructor's return type, not a change of bottom), and
  `jl4/examples/dmn/gst-rate.l4` and `ymd-dates.l4` wait for the DMN image above, because their
  engine harnesses deliberately query a rule date below commencement.

## Related

- **[ASSUME](../types/ASSUME.md)** — for a fact the boundary supplies, which a refusal is not
- **[IF](IF.md)** / **[CONSIDER](CONSIDER.md)** — the arms that reach a refusal
- **[Errors and Troubleshooting](../errors/README.md)**
