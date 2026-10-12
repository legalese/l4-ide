# Query Planning

The **query planner** turns a Boolean-valued L4 decision into an interactive
question-and-answer session: given the facts known so far, it decides whether the
outcome is already settled, and if not, which question to ask next. This is what
lets the [web-app generator](../../courses/advanced/module-a4-production.md#web-form-generation)
produce a wizard from a rule instead of a static form.

The planner is built on a [Reduced Ordered Binary Decision Diagram](robdd.md)
(ROBDD). Read that page for the underlying data structure; this page covers what
L4 does with it.

## The two jobs

Given a decision such as

```l4
GIVEN
  age IS A NUMBER
  citizen IS A BOOLEAN
  resident IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `may vote` IF age >= 18 AND (citizen OR resident)
```

and a partial set of answers (say, `age >= 18` is known to be `TRUE`, the rest
unknown), the planner answers two questions:

1. **Is the outcome already determined?** If every remaining assignment of the
   unknown atoms produces the same result, the answer is fixed and no further
   questions are needed. This is _partial evaluation_: fixing the known atoms
   with [`restrict`](robdd.md#core-operations) may collapse the ROBDD to a
   terminal.
2. **If not, what should we ask next?** Of the atoms still unknown _and still
   relevant_, which one should the wizard put to the user next.

Atoms that no longer affect the outcome — because earlier answers pruned the part
of the decision that depended on them — drop out of the diagram's _support_ and
are never asked. This is the first and biggest usability win: the wizard asks
only questions that can still change the answer.

## Question ordering

Among the atoms that remain relevant, the planner ranks them. The **current**
policy is _determinability-first_: prefer the atom that, once answered, settles
the most of the decision, using the atom's position in the ROBDD as a tiebreak.
Concretely the ranking key is `[-determinableCount, level]` — ask the most
decisive question first, and break ties by diagram level.

This is a purely structural policy: it treats every unknown atom as equally
likely to be `TRUE` or `FALSE`. It is a good default, but it leaves two things on
the table:

- It has no notion that some facts are _usually_ one way. A contract party is
  typically not under duress; a transaction is typically at arm's length. A
  structural policy will still ask about the unusual case as eagerly as the
  decisive one.
- It measures "how much does this settle" combinatorially, not by _expected_
  progress once likelihoods are taken into account.

### Information gain and priors (roadmap)

The designed evolution is an **information-gain** policy. Using
[model counting](robdd.md#model-counting) over the ROBDD, estimate the
probability the outcome is `TRUE`, and score each candidate atom by how much
answering it is _expected_ to reduce uncertainty:

```
gain(X) = H(before) − [ w_X · H(after X = TRUE) + (1 − w_X) · H(after X = FALSE) ]
```

where `H` is Boolean entropy and `w_X` is a per-atom prior — the probability the
atom is `TRUE`. The weights come from [TYPICALLY](../types/TYPICALLY.md): a
fact declared `IS A BOOLEAN TYPICALLY TRUE` supplies `w_X` close to `1`.

This subsumes the current policy and adds a prior-aware ordering for free: a
strongly presumed atom carries almost no expected information, so a greedy
information-gain policy sinks it to the bottom of the ask-order — reproducing the
"don't ask; allow the user to override the presumption" behaviour without
special-casing it — and orders the genuinely uncertain questions by how much they
are expected to resolve.

> **Status.** The shipped planner uses the determinability-first policy described
> above. The information-gain policy and TYPICALLY-driven priors are the planned
> direction; [TYPICALLY](../types/TYPICALLY.md) already parses and stores the
> per-atom defaults that the policy will read, but no consumer reads them for
> ordering yet.

### Interactive explanation surface (backlog)

The planner's internals already carry the structural ingredients for the kind of live,
per-question explanation AustLII's DataLex platform has shipped for two decades over its
`yscript` rule language: `Why?` (why is this question being asked), `How?` (which facts and
rules produced a conclusion), `What if?` (try a hypothetical without committing), and `Forget`
(retract an answer and re-ask whatever depended on it). See
[DATALEX-YSCRIPT-RESEARCH.md](../../../specs/research/DATALEX-YSCRIPT-RESEARCH.md) §C-D for the
worked examples and the stratum-by-stratum mapping.

Concretely, against this repo's own types (`jl4-query-plan/src/L4/Decision/QueryPlan.hs`):

- **`Why?`** is `inputRefsClosureByUnique`'s dependency closure (`QueryPlan.hs:38-84`) read the
  other way — which higher-level atom needs this one — already computed to drive ranking, not
  yet exposed as an answer to a user's question.
- **`How?`** is the sequence of `restrict` calls that collapses the ROBDD to a terminal (the
  generator loop's step 3 below, "show the result with the trace of why") — the trace exists
  implicitly as the steps the wizard already took; nothing currently retains or replays it as an
  explanation.
- **`What if?`** is `restrict` applied to a hypothetical value without committing it to the
  session's answer set — the operation already exists; only the "don't commit" wrapper is
  missing.
- **`Forget`** is un-restricting one atom and re-running the planner over the remaining
  answers — again an operation the substrate supports, not one the wizard surface exposes.

None of this needs a new subsystem: the gap is that the planner is consumed today as a one-shot
"what's the next question" oracle, and the intermediate structure (which atoms were fixed, in
what order, and why each one mattered) is discarded rather than retained and surfaced. Turning it
into a real explanation surface means threading per-step provenance from the query-plan response
through to the wizard UI. Backlogged 2026-09-08; see
[Future Features](../../../specs/roadmap/future-features.md) ("Interactive explanation surface for
the query planner") for the tracked entry. Not scheduled.

## How the web-app generator uses it

The [web form generator](../../courses/advanced/module-a4-production.md#web-form-generation)
walks the planner as the user answers:

1. render the top-ranked unanswered question as a form field;
2. record the answer and `restrict` the decision by it;
3. if the outcome is now determined, show the result (with the trace of why);
   otherwise return to step 1.

Because determined outcomes short-circuit, a user often reaches an answer after a
few questions rather than filling in every field — the difference between a
static form and a guided interview.

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

So the ladder diagram in the editor, the query plan behind the wizard (the `/query-plan` route of `jl4-service`, the service that publishes rules), and `l4 verify` treat the two forms alike: the same boxes, the same questions, asked in the same order.
That holds when every pattern in the clauses is an enum value, a literal (a number, a piece of text, `TRUE` or `FALSE`), or a name.

### Patterns that are not broken down

A pattern with something inside it, such as `JUST TRUE`, `JUST x` or a list, is not broken down into questions.
The rule, or the part of it that tests that input, is drawn as one box, as it is for a `CONSIDER` written by hand.
`l4 verify` lists a rule written as clauses whose whole ladder is that one box as `NOT ANALYSED`, saying that it was not broken down into questions, rather than reporting that it found nothing.

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

Only the picture and the plan are refused.
The rule still runs: `#EVAL`, `l4 run` and the service's evaluation answer it as usual.

**What you can do about it:**

- **Give part of the rule a name of its own.** Move a group of clauses into a separate rule, named for what it decides, and use that rule in the clauses that remain. The rule that uses it shows the call, not the clauses behind it, so they do not count towards its 300; the new rule is drawn, and counted, on its own.
- **Split one long list into smaller lists**, each deciding one part of the question, and combine their answers with `AND` or `OR`.

The limit applies only to a rule written as clauses, and it is the rule as you wrote it that counts.
A `CONSIDER` you write yourself is drawn as you wrote it, and so is a rule you wrote by hand after the editor unfolds a call to a clause group into it.
A rule that answers something other than yes or no, such as a number, is not drawn as a ladder at all, however it is written, and L4 says that first.

### The limit is on the drawing, not on planning

The 300 bounds how much is drawn, not how long the wizard's plan takes.
A plan's cost depends on how its questions combine, not only on how many boxes there are.
A table of 20 rows over an enum of 20 values and a yes-or-no input draws 61 boxes and took between 11 and 18 seconds to plan when measured; one of 24 rows draws 73 boxes and took about four minutes.
The same rule written as a `CONSIDER` by hand takes as long.

## Implementation

- TypeScript: `ts-shared/boolean-analysis/src/decision-query.ts`
  (`compileDecisionQuery`, the `rank` policy) over
  `ts-shared/boolean-analysis/src/robdd.ts`. This is the path the browser-side
  wizard uses.
- Haskell: `jl4-query-plan/src/L4/Decision/QueryPlan.hs` over
  `BooleanDecisionQuery.hs`, for server-side query planning.

## See also

- [Binary Decision Diagrams (ROBDD)](robdd.md) — the substrate
- [TYPICALLY](../types/TYPICALLY.md) — per-atom priors for the ordering policy
- [Web Form Generation](../../courses/advanced/module-a4-production.md#web-form-generation)
  — the generator that consumes the planner
