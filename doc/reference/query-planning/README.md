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
   questions are needed. This is *partial evaluation*: fixing the known atoms
   with [`restrict`](robdd.md#core-operations) may collapse the ROBDD to a
   terminal.
2. **If not, what should we ask next?** Of the atoms still unknown *and still
   relevant*, which one should the wizard put to the user next.

Atoms that no longer affect the outcome — because earlier answers pruned the part
of the decision that depended on them — drop out of the diagram's *support* and
are never asked. This is the first and biggest usability win: the wizard asks
only questions that can still change the answer.

## Question ordering

Among the atoms that remain relevant, the planner ranks them. The **current**
policy is *determinability-first*: prefer the atom that, once answered, settles
the most of the decision, using the atom's position in the ROBDD as a tiebreak.
Concretely the ranking key is `[-determinableCount, level]` — ask the most
decisive question first, and break ties by diagram level.

This is a purely structural policy: it treats every unknown atom as equally
likely to be `TRUE` or `FALSE`. It is a good default, but it leaves two things on
the table:

- It has no notion that some facts are *usually* one way. A contract party is
  typically not under duress; a transaction is typically at arm's length. A
  structural policy will still ask about the unusual case as eagerly as the
  decisive one.
- It measures "how much does this settle" combinatorially, not by *expected*
  progress once likelihoods are taken into account.

### Information gain and priors (roadmap)

The designed evolution is an **information-gain** policy. Using
[model counting](robdd.md#model-counting) over the ROBDD, estimate the
probability the outcome is `TRUE`, and score each candidate atom by how much
answering it is *expected* to reduce uncertainty:

```
gain(X) = H(before) − [ w_X · H(after X = TRUE) + (1 − w_X) · H(after X = FALSE) ]
```

where `H` is Boolean entropy and `w_X` is a per-atom prior — the probability the
atom is `TRUE`. The weights come from [TYPICALLY](../types/TYPICALLY.md): a
binder declared `IS A BOOLEAN TYPICALLY TRUE` supplies `w_X` close to `1`.

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
