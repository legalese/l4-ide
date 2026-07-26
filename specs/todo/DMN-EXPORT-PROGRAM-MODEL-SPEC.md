# DMN Export — Program Model

_Status: **design, not yet implemented.** Supersedes the program model currently in
`jl4-core/src/L4/Dmn/{IR,Lower,Emit,Markdown}.hs`. Written 2026-07-26 on branch
`mengwong/dmn-export`._

**One-line summary.** The exporter today models an L4 module as _global scalars plus decisions
over them_ — the shape a module written with top-level `ASSUME` has. Idiomatic L4 is _functions
over threaded records_. This spec replaces the program model rather than patching the symptoms,
and does so from a single analysis: **un-lambda-lifting**.

Everything asserted here as "verified" was executed, validated or read out of a normative
document during the research pass; everything else is marked. §11 lists what is still open.

---

## 1. Why the current model is wrong

Verified empirically (harness positive-controlled against the committed `reg-cf` goldens,
byte-identical output):

| #   | Symptom                                                                                                                                                                                                        | Anchor                           |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| 1   | Free terms are keyed by `Unique`. Each decision's `GIVEN` is a separate `def`, so N decisions sharing a parameter name yield N `<inputData>` elements.                                                         | `Lower.hs:1201`                  |
| 2   | `assignIds` dedups the **id**; `idName = nm` does **not** dedup the **name**, and neither does the inner `<variable name=…>`. A probe emitted 9 `<inputData>`, three named `annual income`, two named `class`. | `Lower.hs:1359`, `Lower.hs:1219` |
| 3   | That output is **XSD-valid** — `DMN13.xsd` constrains `id` as `xsd:ID` but `name` as bare `xsd:string`, with zero `xsd:unique`/`key`/`keyref`. Validation catches nothing.                                     | `DMN13.xsd:29-40`                |
| 4   | A real engine **silently collapses** the duplicates. `@hbtgmbh/dmn-eval-js` 1.5.0 parses the model and evaluates every decision against the single context entry. Not a rejection — a wrong answer.            | executed                         |
| 5   | `D-SCOPE` fires once per colliding FEEL name. Zero notes under `ASSUME`; three in a GIVEN-style probe. A note written as a rare diagnostic is the normal case.                                                 | `Lower.hs:1245-1258`             |
| 6   | Record types erase to `Any` — `dmnTypeOf` sends a non-enum `TyApp` through `builtinType`, and `Emit.hs` has zero `itemDefinition` support.                                                                     | `Lower.hs:972`, `Emit.hs`        |
| 7   | Enum **domains** are discarded. `IS ONE OF` becomes bare `string`; no `<inputValues>` is ever emitted.                                                                                                         | `Lower.hs:973`, `Emit.hs:198`    |

The flagship exhibit `jl4/examples/dmn/reg-cf.l4` is itself `ASSUME`-style (5 top-level
`ASSUME`s, 0 `GIVEN`s), which is the only reason the goldens look clean. See the ASSUME→GIVEN
migration entry in `TIER1-WIP-INDEX.md` and PR #142.

---

## 2. The frame: DMN's DRG is a let-block

A DMN model is:

```
let inputData₁ = ⟨supplied⟩
    inputData₂ = ⟨supplied⟩
    decisionA  = expr over inputs
    decisionB  = expr over inputs and decisionA
in  ⟨whatever is asked for⟩
```

Single-assignment, non-recursive, all bindings at one scope level. `informationRequirement` is
not a call graph — it is "this binding's RHS mentions that binding".

An L4 module in house style is the **same let-block, lambda-lifted**: every binding has had the
ambient parameter pushed into its own signature.

```l4
GIVEN investor IS AN InvestorProfile
`greater of annual income or net worth` investor MEANS …

GIVEN investor IS AN InvestorProfile
`within the investment limit`           investor MEANS … `greater of …` investor …
```

So the translation is **un-lambda-lifting**, and DMN's answer to "where did the arity go?" is
_the model itself is the lambda_ — you invoke a DMN model by supplying its `inputData`. Arity
moves from each decision up to the model, where DMN puts it.

### 2.1 The analysis, stated once

For each top-level `DECIDE` `d` with parameters `p₁…pₙ`:

- **Un-lifts (tier 1)** if every reference to `d` within the scope unit applies it to the same
  argument expressions. Then `d` becomes a `<decision>`; each `pᵢ` becomes an `<inputData>`
  shared with every other decision that names it; and references to `d` are bare names carrying
  an `<informationRequirement><requiredDecision>` edge. Nothing is lost.
- **Does not un-lift (tier 2)** if `d` is applied to two or more distinct argument expressions.
  It is a real λ. DMN's word for a real λ is `businessKnowledgeModel` (§6).

This is one analysis producing the whole design. It also retires the "key by FEEL name instead
of `Unique`" idea as a standalone rule: **name-keying is the inverse of lambda lifting**, and
it is correct exactly when the un-lifting side-condition holds, not unconditionally.

### 2.2 The census says the frame is load-bearing

Measured across the three real corpora (Reg CF `regcf.l4`, `paper/case-studies/
charities-jersey-2014/`, `jl4/experiments/housing-act-*.l4`):

- **tier 2 is 2.7% / 4.0% / 4.3%** of parameterised decisions. It is a handful, not pervasive.
- **tier 2 correlates ≈100% with cross-module reuse** — 7/7 in Housing, 4/5 in Charities. The
  six `Ground N made out` roll-ups are tier 1 _inside their own file_ and become functions only
  when an aggregator imports them. **Downgraded 2026-07-27 from census to sample:** §2.4.3's
  independent re-derivation found a parameterised-decision population 2.0–2.6× this one, which
  makes 7 and 5 samples of ~19 and ~13 rather than complete tier-2 sets. The rate below is
  unaffected; the correlation is unverified at full population and owes a re-run.
- **Arity is essentially always 1.** Every arity ≥3 decision in all three corpora turned out to
  be a test-fixture builder.
- **No decision is ever applied to a constructed record or a conditional.** The complete
  argument grammar to lower is: bare variable | projection chain of depth ≤2 | application of
  another decision or arithmetic | numeric literal. The hard cases occur only in fixtures.

The second bullet is the frame paying rent: within a module parameters unify, across modules
they cannot, because **each module is its own λ**. Which makes §11-R1 (scope unit) and "where
do we draw the lambda" literally the same question.

### 2.3 The λ boundary is the `§`, and DMN's word for it is `decisionService`

**Ruled 2026-07-26.** One `<definitions>` per L4 module; one `<decisionService>` per `§` section.
`tInvocable` is a `drgElement` (`DMN13.xsd:143`), so many services live in one model — the
"several models" fan-out was never forced.

The corpus draws the seam already. `part-3-charity-test.l4` has thirteen sections, and **every one
is homogeneous in its parameter** — `§§ Article 6(1) and 6(2)` and `§§ Article 6(5)` are
`p IS A CharitablePurpose`; `§§ Article 7`, `§§ Article 5(1)`, `§§ Article 5(2) and 5(3)` and
`§§ Article 5` are `c IS A CandidateCharity`. The section boundary is exactly where the parameter
changes. The author drew those boundaries by following the Act's Article structure and landed on
the λ boundaries. (The last section is labelled _"(the regulative layer)"_ — so `§` also seams the
DMN side from the BPMN side.)

**Why a service and not N BKMs.** A plain `<decision>` is a value, not a function; it cannot be
applied per list element. Only `decisionService` and `businessKnowledgeModel` yield a FEEL
function, and a BKM holds exactly one `encapsulatedLogic` — a `§` with ten `GIVEN p` decisions
would need ten BKMs with duplicated internal wiring. One service covers the section.

**Verified by execution** (Drools/KIE 8.44.0.Final, XSD-valid under Xerces, KIE validator clean),
on the real corpus shape — a service `Article 6` with six output decisions over one
`CharitablePurpose` input, invoked from the Article 5(1) side:

```feel
every q in c.purposes satisfies Article 6(q).meets the Article 6 test
```

→ `true` on a conforming charity, `false` when one purpose is a casino. Also verified: invocation
from a `literalExpression`; from a decision table's `inputExpression`, `outputEntry` **and**
`inputEntry`; inside `some` and `for`; from five distinct callers with different arguments; and
one level of service nesting. `for q in c.purposes return Article 6(q)` returns a list of
contexts, one per purpose, each carrying all six named sub-conclusions — **a free per-element
audit trace**, which is worth having for the explainability story.

Spec basis, not vendor behaviour: §10.4 — _"A decision service is semantically equivalent to a
FEEL function whose parameters are the decision service inputs"_; §10.3.2.13.2 — _"Invocable
elements (Business Knowledge Models or Decision Services) are invoked using the same syntax as
other functions"_. Quantifier bodies therefore get invocation for free.

This also resolves the higher-order worry. `all f (c's purposes)` passes a decision as a _value_,
which DMN cannot do — but η-expanding to `every p in … satisfies f(p)` never passes the function,
only applies it. `all`/`any` over a decision lower to FEEL quantifiers.

#### 2.3.1 Emission requirements

- **`<knowledgeRequirement><requiredKnowledge>` on every caller is mandatory.** The spec never
  says `SHALL`, but §10.3.2.11.2 puts the service's name in scope _only_ via that edge. Verified:
  removing it leaves the model XSD-valid and fails with `Unknown variable 'purposeTest'`.
- **Parameter order is `inputData` first, then `inputDecision`** (§10.4) — the **reverse** of the
  XSD child order (`outputDecision, encapsulatedDecision, inputDecision, inputData`,
  `DMN13.xsd:516-519`). Verified: `orderProbe(1, 2)` → `102`. **Emit named parameters at every
  call site.** Named binding is verified working, costs nothing, and sidesteps a portability
  detail engines are likely to get wrong.
- **Prefer one output decision per service.** A multi-output service returns a _context_, so
  callers must project a field — and that is where FEEL naming bites (below). A single-output
  service returns a bare value needing no projection. Cost: more services.
- **XSD is insufficient here.** The spec says `outputDecisions: Decision [1..*]` but
  `DMN13.xsd:516` declares `minOccurs="0"`, so Xerces passes a service with no outputs. KIE's
  _model_ validator catches it; schema validation alone does not.

#### 2.3.2 The hazard that constrains granularity: services can manufacture cycles

**Section granularity can create a cycle where the decisions have none.** With decision-level
dependencies `xf → yh → xg` — acyclic — putting `xf` and `xg` in one service because they share a
`§` makes `sectX → sectY → sectX`.

Spec §6.3.9-analogue: _"a DecisionService element SHALL not require itself, directly or
indirectly"_, its requirement subgraph being the union of its members'. So this is **ill-formed**.
But measured:

| check         | result                                     |
| ------------- | ------------------------------------------ |
| Xerces XSD    | **valid** — structural only, cannot see it |
| KIE validator | **clean** — does not detect it             |
| KIE runtime   | `top = null`, reported as **`SUCCEEDED`**  |

**A silent null under a SUCCEEDED status is the worst available failure mode for a legal
reasoner**, and nothing downstream catches it. The prohibition is spec-mandated; the detection gap
is KIE's.

**Therefore `§` is the _proposed_ seam, not the emitted one.** The exporter must run its own SCC
check over the **service-level** graph and, where a section would close a cycle, split it into
finer services until the graph is acyclic. Verified: the same decisions with the offending section
split into two single-output services evaluate correctly. Emit a note recording any split, since
the artifact then departs from the source's own sectioning.

#### 2.3.3 Two further hazards

- **Multi-output projection collides with FEEL naming**, and it upgrades §5 from a portability
  concern to a correctness one. `Article 6(q).is charitable or purely ancillary or incidental to a
charitable purpose` fails — FEEL parses the embedded `or` as the infix operator
  (`Unknown variable name 'purely ancillary'`) — and an output named `satisfies the Article 6 test`
  fails differently, because `satisfies` terminates the quantifier header. Both are FEEL
  name-vs-keyword problems in _projection_ position, and both disappear under §5.2's mangling.
  Note this does not contradict §5.1-3: a keyword as a name _part_ is fine for a declared name; it
  is the projection position after a call that breaks.
- **Argument types are not enforced at the call site.** Passing a `tCharity` where a `tPurpose` is
  declared returned `false` — no XSD error, no validator message, no runtime message, unchanged
  under `-Dorg.kie.dmn.runtime.typecheck=true`. §10.3.2.13 says a non-conforming argument list
  yields **null**, so KIE diverges, and the divergence is a silent wrong answer. L4 is typed
  upstream so the exporter can guarantee conformance itself — but do not expect DMN to catch an
  exporter bug.

#### 2.3.4 Encapsulation is a view, not a partition

All verified: an encapsulated decision may still be referenced from outside its service; two
services may share an encapsulated decision; one service's output decision may be another's
encapsulated decision; and services may nest, with the inner service needing no declaration on the
outer. That last one is what makes `§` inside `§` work directly.

One operational note: because a service's parameters must be top-level `<inputData>` elements,
`evaluateAll` also tries to evaluate the encapsulated decisions standalone with that input unbound,
emitting `Required dependency not found` errors and `[SKIPPED]` results alongside the correct
answers. `evaluateByName` and `evaluateDecisionService` both report zero messages. Cosmetic, but it
will confuse anyone driving the export from a test harness.

---

### 2.4 Strictness: the totality side-condition on un-lifting — ruled 2026-07-27

**R2 was stated backwards, and the correction changes the severity.** DMN evaluates every decision
in the required closure; L4 forces lazily. Un-lifting moves a decision out of a lazily-evaluated
argument position and into the DRG's unconditionally-required set, so it widens the inputs that
decision is evaluated under — R2 had the mechanism right. What it got wrong is the consequence.
**FEEL has no undefined.** It has `null`, and `null` reads as `false` in every consuming position.

Verified in `feelin` 7.0.1: every operation L4 raises on returns `null`, and the `null` is then
_coerced_, not propagated.

| FEEL                                                                                   | result                                          |
| -------------------------------------------------------------------------------------- | ----------------------------------------------- |
| `1 / 0`, `modulo(5, 0)`, `sqrt(-1)`, `log(0)`, `number("abc")`, `[1,2][3]`, `{a: 1}.b` | `null`                                          |
| `if null then 1 else 2`                                                                | `2` — a null guard silently takes the `else`    |
| unary test `> 3` against `? = null`                                                    | `false` — the table row silently does not match |
| `every p in [2, null] satisfies p > 1`                                                 | `false` — silently "no"                         |
| `null or true` / `null and false`                                                      | `true` / `false` — full Kleene, symmetric       |

L4's answer on the same widened input is a **loud user exception**. Verified: with `d MEANS 0` and
`q MEANS 100 / d`, `#EVAL q` reports `Division by zero in the operation: DIVIDED BY`, while
`#EVAL (IF d EQUALS 0 THEN 0 ELSE q)` returns `0`.

So the exporter would not be converting a refusal-to-answer into a differently-spelled
refusal-to-answer. It would be converting it into a **wrong answer that nothing downstream
catches** — the mode §2.3.2 already called the worst available for a legal reasoner. It is also the
mode the exporter has already met once and already refuses on, in one special case. `rowsElided`
(`Lower.hs:1599`), on an elided `CONSIDER` arm with no `OTHERWISE` to plug the hole: _"For the
ladder that is exact: a missing disjunct contributes FALSE. For DMN it is not, because an unmatched
input yields **null**, not `false`. … the table would answer differently from the rule, so we refuse
to emit one."_

**R2 is the general case of a special case the exporter already handles.** The precedent for the
ruling is in-tree, and the ruling is: the side-condition stays.

One symmetry to record and then set aside. The widening runs both ways: FEEL's `and`/`or` are
symmetric Kleene, L4's are left-strict short-circuit, so `boom OR TRUE` raises in L4 and returns
`true` in FEEL. DMN can therefore also _succeed where L4 fails_. Both directions are fidelity
breaks; only null-as-false is a soundness break, and only soundness is ruled on here.

#### 2.4.1 The criterion

Let a _decision_ be a top-level `DECIDE`/`MEANS` (`Lower.hs:1310`) together with the `WHERE`-locals
`Lower` already peels and inlines.

```
DMN-SAFE(d)  ≡  TOTAL(d) ∧ PURE(d) ∧ DETERMINISTIC(d)

TOTAL(d)     ⇔  LOCALLY-TOTAL(body d)
              ∧  ∀ c ∈ calls(d). TOTAL(c)
              ∧  TERMINATES(d)
```

`TOTAL` is the **greatest** fixed point, computed SCC-ordered over the call graph, seeded `True`
within each SCC and pinned `False` on every SCC `TERMINATES` cannot certify. The three bits are
ANDed for the routing decision but kept separately reportable, because they have different
remedies.

> **Corrected 2026-07-27; this said "least fixed point" and that rejected the entire design.** The
> equation is conjunctive, so on any SCC containing a self-call both `True` and `False` are fixed
> points and the _least_ one is `False`. Instantiated at `sum` — self-recursive, structurally
> terminating, locally total — it reads `T(sum) = True ∧ T(sum) ∧ True`, whose least solution is
> `False`. Taken literally the lfp formulation therefore rejected `sum`, `count`, `and`, `or`,
> `map`, `filter` and every list-touching decision in all three corpora, i.e. it produced exactly
> the "design collapses" outcome the `TERMINATES` paragraph below exists to prevent, and made that
> paragraph dead text. The seeding language was the tell: seeding _some_ SCCs `False` only means
> anything if the rest are seeded `True`, which is a co-inductive computation. Totality here is
> co-inductive **modulo** termination — assume the SCC total, discharge the well-foundedness
> obligation separately with `TERMINATES`, and pin `False` when that obligation cannot be
> discharged. Recorded rather than silently patched because the same slip is easy to reintroduce.

**`LOCALLY-TOTAL(e)`** is a syntactic walk over the `Expr Resolved` with the substituted type at
each node. It is `False` if `e` contains, **in a strict position** (below), any of the following.
The clause list is derived from `UserEvalException` (`EvaluateLazy/Exceptions.hs:42-53`) — eight
constructors, which is the ground truth to re-derive against when the evaluator grows.
`InternalEvalException` is the compiler-bug channel and is deliberately not modelled.

| #   | reject                                                                                                                                                                                                                                                                                                                           | forecloses                                                                                               |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| L1  | a `Consider` the checker reported `PatternMatchesMissing` on, **or** whose analysis was suppressed (`branchHasOpaquePattern`; `isPrimitiveType`, `TypeCheck.hs:1954`) and which has no `OTHERWISE` arm. Multi-clause functions desugar to `CONSIDER`, so they are covered — but see L11: L1 does **not** exhaust this exception. | `NonExhaustivePatterns`                                                                                  |
| L2  | a `DECIDE`/`MEANS` carrying `@nonexhaustive` — the author's own machine-readable declaration that the match is incomplete                                                                                                                                                                                                        | same                                                                                                     |
| L3  | `DIVIDED BY` whose divisor is not a nonzero numeric literal after constant folding                                                                                                                                                                                                                                               | `DivisionByZero`                                                                                         |
| L4  | `MODULO`; `TO THE POWER OF`; `SPLIT` with a non-literal or empty delimiter                                                                                                                                                                                                                                                       | `NotAnInteger`; NaN/∞ via `Double`; an **uncaught** `Data.Text.splitOn: empty input` (`Machine.hs:2850`) |
| L5  | `SQRT`, `LN`, `LOG10`, `ASIN`, `ACOS`                                                                                                                                                                                                                                                                                            | NaN                                                                                                      |
| L6  | `DATE_FROM_DMY` / `TIME_FROM_HMS` / `DATETIME_FROM_DTZ` with any non-literal argument; the `DATE`/`TIME` projections off a `DATETIME` (timezone load)                                                                                                                                                                            | `UserError`                                                                                              |
| L7  | `EQUALS` at a type whose **transitive component structure** contains a function or `CONTRACT` type — not merely a function-headed or `CONTRACT`-headed one                                                                                                                                                                       | `EqualityOnUnsupportedType`                                                                              |
| L8  | `AS STRING` whose argument type does not resolve to `NUMBER`/`STRING`/`BOOLEAN`/`DATE`/`TIME`/`DATETIME`                                                                                                                                                                                                                         | `UserError`                                                                                              |
| L9  | `EVER BETWEEN`, `ALWAYS BETWEEN`, `WHEN LAST`, `WHEN NEXT`, `VALUE AT`                                                                                                                                                                                                                                                           | `UserError`; none has a DMN lowering anyway                                                              |
| L10 | `TODAY` / `TIMEZONE` / `CURRENTTIME` / `RULES EFFECTIVE DATE` with no `TIMEZONE IS` in module scope                                                                                                                                                                                                                              | `UserError`                                                                                              |
| L11 | a **projection `x's f` whose scrutinee type is an `IS ONE OF` with more than one constructor**, unless every constructor of that type declares a field `f`                                                                                                                                                                       | `NonExhaustivePatterns` — the source L1 cannot see                                                       |
| L12 | a `WHERE`/`LET` local whose right-hand sides form a **dependency cycle** among themselves                                                                                                                                                                                                                                        | `BlackholeForced`                                                                                        |

**Derive it mechanically, not by eye.** The first pass of this list was written by reading the
eight constructors and it still missed two of them and under-stated a third — each found by
_probing the evaluator_, not by re-reading the list. The coverage map is therefore part of the
ruling, and the implementation owes a test that fails when a ninth constructor appears:

| constructor                 | foreclosed by                                                                        |
| --------------------------- | ------------------------------------------------------------------------------------ |
| `NonExhaustivePatterns`     | L1, L2, **L11** — L1+L2 alone do _not_ cover it, see L11                             |
| `EqualityOnUnsupportedType` | **L7**, which had to be restated transitively                                        |
| `DivisionByZero`            | L3                                                                                   |
| `NotAnInteger`              | L4                                                                                   |
| `UserError`                 | L4, L6, L8, L9, L10; the JSON sites via `PURE`                                       |
| `BlackholeForced`           | **L12** — was unmapped                                                               |
| `StackOverflow`             | `TERMINATES` — see below; not an independent clause                                  |
| `Stuck`                     | deliberately _not_ foreclosed: it is the `ASSUME` channel, i.e. an input (see below) |

`StackOverflow` is not a construct and has no syntactic image: `pushFrame`
(`EvaluateLazy/Machine.hs:457`) raises it when the frame stack passes `maximumFrameDepth`. It is a
resource bound, reachable as a _symptom_ of the divergence `TERMINATES` already refuses and,
independently, of data deeper than the cap. The second case is not statically decidable and is not
modelled; `DMN-SAFE` therefore claims definedness for well-founded evaluation, not evaluation under
a fixed frame budget. Say so rather than pretend the clause list covers it.

**L11, and why L1 alone was unsound.** L1 keys on a `CONSIDER` node. Record projection off a sum
type has no `CONSIDER` node in the source at all: `Proj` desugars to a _selector application_ at
eval time — `EvaluateLazy/Machine.hs:804`, `Proj _ann e l -> continueExpr env (App emptyAnno l [e])`
— so the selector is a partial function nothing in the source spells out. Verified on the installed
`l4`:

```l4
DECLARE Shape IS ONE OF
    Circle HAS radius IS A NUMBER
    Square HAS side   IS A NUMBER

GIVEN s IS A Shape
GIVETH A NUMBER
`the radius` s MEANS s's radius     -- l4 check: "Check succeeded." No diagnostic at all.
```

``#EVAL `the radius` (Circle WITH radius IS 3)`` → `3`;
``#EVAL `the radius` (Square WITH side IS 4)`` → _"Value &144@sum1.l4 has no corresponding
pattern"_, i.e. `NonExhaustivePatterns`. PR #45 (the §2.4.5 prerequisite) does **not** help: it
repairs `checkConsider`'s constructor oracle, and there is no `CONSIDER` here. The FEEL image is the
silent one — re-verified in `feelin` 7.0.1: `{a:1}.b` → `null`, `{a:1}.b > 3` → `null`,
`if {a:1}.b then 1 else 2` → `2`. Without L11 the criterion certified that decision `DMN-SAFE`.

The corpus has the shape live — `housing-act-ground-1A.l4:58`,
``DECLARE Disposal IS ONE OF `sell a freehold or leasehold interest` | `grant a long lease` HAS `term certain in years` IS A NUMBER`` — but scrutinises it with `CONSIDER` rather than projecting it,
so this is not yet a corpus break. **It is also not fully covered by §4.2's tagged-union
`Blocking`**, which is R4 and _still an open ruling_ ("leaning refusal for v1"). L11 must therefore
stand on its own inside `LOCALLY-TOTAL`, and not be justified by a sub-ruling that has not been
made.

**L7, and why the head type is the wrong granularity.** `EQUALS` in L4 is structurally recursive:
`runBinOpEquals` (`EvaluateLazy/Machine.hs:2874-2886`) pushes an `EqConstructor1` frame and recurses
componentwise over `ValConstructor` and `ValCons`, and the catch-all
(`:2893`, `userException (EqualityOnUnsupportedType v1 v2)`) is reached from _inside_ that recursion.
So the exception propagates out of a plain **record** with a function component, no sum type in
sight. Verified: a `DECLARE Policy HAS name IS A STRING, payout IS A FUNCTION FROM NUMBER TO NUMBER`
compared with `a EQUALS b` passes `l4 check` and raises _"Trying to check equality on types that do
not support it"_ at `#EVAL`. `LIST OF (FUNCTION …)` and `MAYBE (FUNCTION …)` are the same story.

**L12, and the hole `TERMINATES` did not close.** §2.4.1 defines a decision to _include_ its
`WHERE`-locals, which puts a cycle among those locals outside `calls(d)` — and `TERMINATES`'
structural rule is stated only for "a self-recursive `f`", so it never fires on a decision that is
not self-recursive. Verified:

```l4
GIVEN n IS A NUMBER
GIVETH A NUMBER
`f` n MEANS y
  WHERE
    y MEANS z PLUS n
    z MEANS y                       -- l4 check: "Check succeeded."
```

``#EVAL `f` 1`` → _"Infinite loop detected while trying to evaluate: z PLUS n"_
(`EvaluateLazy/Machine.hs:3093`, `userException (BlackholeForced e)`). Before L12 the criterion
returned `DMN-SAFE(f) = True` for a divergent decision. Because `Lower` **inlines** `WHERE`-locals,
this is a plausible exporter hang and not merely a wrong answer, so L12 is also a robustness fix for
the exporter itself. The check is a cycle test on the locals' dependency graph, which `Lower`
already needs in order to order the inlining.

**`PURE(d)`**: no `FETCH`, `POST`, `GETENV`, `JSON DECODE`, and no `RECALL`/`RECORD`/`ATTEST`. The
JSON decoder's dozen `UserError` sites are reachable only through these, so they are subsumed.
**`DETERMINISTIC(d)`**: no clock reader at all. `TODAY` is total once `TIMEZONE IS` is declared, but
DMN has no clock — kept separate from L10 because the remedy differs: partiality routes to a
fallback, a clock reader routes to "synthesise `today` as an `inputData`".

**Explicitly _not_ a partiality: a reference to an `ASSUME`d term.** Forcing one is `Stuck` in L4
precisely _because_ it is an input, and in DMN it is an `<inputData>` supplied at invocation.
`TYPICALLY` does not change this — `evalAssume` writes `ValAssumed` regardless. Reading `Stuck` as
partial would reject the whole `ASSUME`-style corpus, flagship exhibit included. Also accepted,
because they are genuinely total: `TO NUMBER`/`TO DATE`/`TO TIME` (they return `MAYBE`),
`DATE VALUE`/`TIME VALUE` (`EITHER`), `CHARAT` (clamps out of range to `""`), `INDEXOF` (returns
`-1`), `SUBSTRING`. `SPLIT` is the only string builtin that breaks the pattern, which is why it is
in L4 rather than here.

**`TERMINATES` is a structural check, not an allowlist.** L4 has no loops, so `calls(d)` acyclic ⇒
terminating — but that alone rejects `sum`, `count`, `and`, `or`, `map`, `filter`, i.e. essentially
every list-touching decision, and the design collapses. The cheap check that saves them, ~40 lines:

> A self-recursive `f` **structurally terminates** if there is a parameter position `k` such that
> every recursive call to `f` passes, in position `k`, a variable bound by a `FOLLOWED BY` pattern
> of a `CONSIDER` whose scrutinee is transitively parameter `k`.

That certifies `foldr`/`foldl`/`map`/`filter`/`sum`/`count`/`and`/`or`/`reverse`/`maximum1`/
`minimum1`/`at` in `prelude.l4` automatically. Mutual recursion and `NUMBER`-measure recursion
(`countdown (n - 1)`) reject in v1; the corpora contain neither — but see §2.4.3 on the fact that
this rule is the one part of the criterion the measurement did **not** score.

`calls(d)` acyclicity is not the whole well-foundedness obligation, because a decision's
`WHERE`-locals live inside its body rather than in `calls(d)`. `TERMINATES(d)` therefore also
requires **L12**'s cycle test over those locals.

The prelude is the proof that the two hard checks are orthogonal and compose exactly right: `at`
(`prelude.l4:132`) is structurally decreasing _and_ non-exhaustive, hence partial; `sum`/`map`/
`filter` are structurally decreasing _and_ exhaustive, hence total. A criterion combining them
classifies the whole prelude with no hand-maintained table — which matters, because the alternative
(a trusted totality basis, hand-audited) has to be re-audited on every prelude edit, and this
branch's prelude proves edits go wrong: **`maximum` over `LIST OF MAYBE NUMBER` (`prelude.l4:375`)
computes the _minimum_**, its body being `minimum1 x xs`, with `maximum1` (`:384`) recursing on
`min x y`. Fixed on `main` by PR #45; still wrong here. That and the `SPLIT` escape in L4 are live
evaluator bugs rather than R2 concerns, and each deserves its own issue.

**The refinement that saves the corpus: _strict position_.** Partiality is dangerous only where the
position is evaluated unconditionally.

- **Safe** — reached only on the path that guards it: a `THEN`/`ELSE` arm of an `IF` that lowers to
  a FEEL `if` (branch-lazy, verified above); and the **output entry** of a single-hit table, of
  which exactly one is used. `IR.hs:288`'s no-`Collect` invariant is what makes the second one
  true, and R2 promotes that invariant from tidy to **load-bearing** — a `Collect` table evaluates
  every matching rule's output entry.
- **Strict** — always evaluated: a table's **input entries**, evaluated for every rule in order to
  match; the body of any `<decision>` in the required closure; anything reached through an
  un-lifted DRG edge.

The discrimination this buys is the right one, and it removes what would otherwise be the
criterion's largest false-rejection class. `IF d EQUALS 0 THEN 0 ELSE n / d` is **accepted** when
the guard and the division sit in the same decision, and rejected only when the guard lives in a
_different_ decision from the division — which is precisely the configuration un-lifting creates
and R2 exists to catch.

#### 2.4.2 On refusal: route by the _call site_, not by the node kind

**Corrected 2026-07-27. The first version of this ruling said "route to tier 2, do not reject" and
justified it with "tier 2 is sound for R2 _by construction_". That is false, and it left the
failure mode §2.4 exists to close fully open.** The correction is recorded rather than overwritten,
because the mistake is the natural one to make twice.

What the original said, and why it looked right: a BKM's parameters bind at the call site to the
caller's actuals — the same discipline L4 has, so the free-parameter widening does not happen; and a
BKM invocation sits inside a FEEL expression, where `if` evaluates only the taken branch, so the
required-closure widening does not happen either. Both sentences are **true**. Both are also
**irrelevant**, because neither mechanism is what turns a partial expression into `false`. The
coercion is done by FEEL's `null`, and `null` arrives identically whether the partiality sits in a
`<decision>` body, in a BKM's `encapsulatedLogic`, or inlined at the call site. Routing removes the
_widening_; it does nothing about the _coercion_.

The counterexample, run end to end. `share` below is tier 2 by §2.1 (two distinct argument tuples),
is `¬DMN-SAFE` by L3 (divisor not a nonzero literal), and its whole body is a strict position:

```l4
DECLARE Claim
  HAS `pot`       IS A NUMBER
      `claimants` IS A NUMBER

GIVEN pot IS A NUMBER
      n   IS A NUMBER
GIVETH A NUMBER
`share` pot n MEANS pot DIVIDED BY n

GIVEN c IS A Claim
GIVETH A BOOLEAN
`above threshold` c MEANS `share` (c's pot) (c's claimants) GREATER THAN 10

GIVEN c IS A Claim
GIVETH A NUMBER
`per head` c MEANS `share` 100 (c's claimants)
```

L4, with `claimants = 0`: `Division by zero in the operation: DIVIDED BY` — a loud refusal. FEEL
(`feelin` 7.0.1, the install §2.4 cites):

```
100/0                                 => null
100/0 > 10                            => null
(100/0 > 10) and true                 => null
if 100/0 > 10 then "yes" else "no"    => "no"      <-- silent wrong answer
every x in [1,2] satisfies 100/0 > x  => false
some  x in [1,2] satisfies 100/0 > x  => false
recip(0)  where recip(d) = 100/d      => null      <-- BKM invocation, identical
```

The last line is the point. Under the original ruling `share` was emitted as a
`businessKnowledgeModel` carrying a **`Lossy`** `D-PARTIAL` note, and the caller's guard-free
consumption of it produced precisely the silent wrong answer §2.4's opening calls "the worst
available for a legal reasoner" — under a `Lossy` note, i.e. an advisory one. The `inline into each
caller` row was worse: it puts the identical expression into the identical strict position with the
DRG node additionally gone.

**The ruled rule.** Severity keys off whether the **call site consumes the invocation strictly**, in
exactly the sense §2.4.1 already defines, and node kind is only the mechanical consequence:

```
DMN-SAFE(d) ∧ tier-1 side-condition          →  <decision>              nothing lost
¬DMN-SAFE(d), EVERY call site consumes d
  from a lazy position (a FEEL `if` arm, a
  single-hit output entry)                   →  BKM or inline           Lossy: D-PARTIAL
¬DMN-SAFE(d), ANY call site consumes d
  from a strict position                     →  D-PARTIAL, Blocking
¬DMN-SAFE(d), d is a DRG root / uncalled     →  D-PARTIAL, Blocking — never a node
```

Rows are first-match in the order written, which is what stops a root decision falling into the
"inline into each caller" arm with no caller to inline into.

**Partiality is contagious, and that is load-bearing rather than incidental.** `TOTAL(d)` already
requires `∀ c ∈ calls(d). TOTAL(c)`, so in the example `above threshold` is itself `¬DMN-SAFE` and
is routed by this table too, not emitted as a node. Under the corrected severity rule the chain
terminates in a `Blocking` at the first strict consumer — here immediately, since
`` `share` … GREATER THAN 10 `` is the whole body of `above threshold`. That is the behaviour §2.4
was arguing for all along; the original table simply never reached it, because every arm before the
last was `Lossy`.

**Consequence for the cost claim, stated plainly: R2's `Blocking` arm is no longer empty by
construction.** §2.4.3 measured a refusal set of five, all recursion, all already refused by §6.3-1
— and under the original table those five produced no _new_ `Blocking`s. Under the corrected table
a `¬DMN-SAFE` decision consumed strictly is a `Blocking`, so the arm is empty on the three corpora
only because the refusal set happens to be empty of non-recursive members there. That is a
contingent fact about these corpora, not a property of the rule, and §2.4.3's "R2 adds a routing
rule and no new refusals" must be read that way.

**The same predicate gates a second site R2 has not so far been connected to: multi-output
`decisionService` co-membership (§2.3).** A service computes _all_ of its output decisions, so
putting a not-certified-total decision in the same `§` as a total one forces it identically. §2.3.2
already splits services to break cycles; the split rule must fire on partiality too. §2.3.1's
"prefer one output decision per service" makes that nearly free.

Honour `¬DMN-SAFE` at both sites and `evaluateAll` over the whole model becomes safe as well, since
such a decision is never a node. That is not a small bonus: `evaluateAll` is the default entry point
in most tooling, and it forces every decision rather than a requested closure.

**`Blocking` remains the correct floor for the residual case**, given §2.4's opening — the
alternative is a silently wrong answer, which is what `rowsElided` already refuses on. The
measurement says the residual case is empty _on these three corpora_; under the corrected severity
rule above that is a fact about the corpora, not a guarantee.

#### 2.4.3 The measurement: what it actually scored, and what it did not

Measured over the same three corpora as §2.2 (62 files) by running `l4 ast` on each file and walking
the parsed abstract syntax — not grep. Tier 1 as §2.1 defines it, `#EVAL`/`#ASSERT`/`#TRACE` sites
excluded (see the flag below). Six detectors, applied to each tier-1 decision's body and
transitively to its corpus-local callees: non-exhaustive `CONSIDER`, division/`MODULO`, `MAYBE`
projection, `ASSUME` reference, recursion, partial prelude builtin.

> **Read the table below as a measurement of a _proxy_, not of the ruled criterion.** The detector
> list contains a flat "recursion" test. The criterion in §2.4.1 contains a structural-termination
> check that deliberately **accepts** structural recursion — the ~40 lines the same section says are
> all that stands between the design and collapse. The proxy therefore differs from the ruling on
> exactly the construct that produced 100% of the refusals.
>
> The corpus's one instance of the _accepting_ case was refused by the proxy.
> `jl4/experiments/housing-act-possession-decision.l4:251-257`:
>
> ```l4
> GIVEN branches IS A LIST OF DEONTIC Actor Action
> GIVETH A DEONTIC Actor Action
> `ror together` branches MEANS
>   CONSIDER branches
>   WHEN EMPTY                 THEN FULFILLED
>   WHEN d FOLLOWED BY EMPTY   THEN d
>   WHEN d FOLLOWED BY rest    THEN d ROR `ror together` rest
> ```
>
> Parameter position 1 is `branches`; the recursive call passes `rest`, bound by a `FOLLOWED BY`
> pattern of a `CONSIDER` whose scrutinee is parameter 1; the match is exhaustive. That is verbatim
> the §2.4.1 structural rule, so the **ruled** criterion certifies `ror together` terminating and
> total. `rent spine` (`housing-act-ground-1.l4:42`, ``HENCE `rent spine` (monthsLeft MINUS 1)``)
> is `NUMBER`-measure recursion, which §2.4.4 case 2 rejects in v1 — the _rejecting_ branch. The
> check that distinguishes them is untested against the corpora **on both sides**, and no measured
> decision exercises its accepting branch at all.
>
> The error direction is conservative, so **0.8% stands as an upper bound on the cost**. What does
> not stand is "the criterion is cheap" as a claim this measurement earned, or the headline below
> as a statement about the ruling rather than about the proxy. Re-running the census against the
> real structural check is an implementation-phase obligation, listed in §10 Phase 4.

| corpus    | tier 1  | refused | rate | tier 1 excl. regulative bodies | refused | rate     |
| --------- | ------- | ------- | ---- | ------------------------------ | ------- | -------- |
| Reg CF    | 40      | 1       | 2.5% | 37                             | 0       | **0.0%** |
| Charities | 309     | 0       | 0.0% | 249                            | 0       | **0.0%** |
| Housing   | 305     | 4       | 1.3% | 255                            | 1       | **0.4%** |
| **total** | **654** | **5**   | 0.8% | **541**                        | **1**   | **0.2%** |

Not a long tail — **one construct accounts for 100% of the refusals of the proxy, and it is
recursion.** Every instance is a deontic combinator: `ongoing reporting obligation` and `rent spine`
(`HENCE` self-call), `ror together` (an `ROr` fold over a list of contracts), and the decisions that
reach them. The one refusal whose own root node is not a `Regulative` — `election among available
grounds` — is `ror together (available ground duties cf)`, a contract fold. **For the population
that reaches the DRG at all, the proxy's refusal count is zero** — and at least two of the five
(`ror together` and the `election` that calls it) are refusals the ruled criterion would _not_ make,
per the box above.

Cross-checked under the opposite framing: counting tier-1 decisions that use _any_ construct outside
a known-total core refuses 3 / 61 / 50, and the outside-core constructs are exactly `MkDeonton`,
`Regulative`, `RAnd`, `ROr`, `Record`, `Breach` — the same population. The result does not depend on
blacklist-versus-whitelist framing.

**This is what justifies routing over rejection, and it justifies it twice over.** The entire
measured refusal set is recursion, and §6.3-1 already routes recursion to a `Blocking` `D-RECURSIVE`
— so R2's own `Blocking` arm is **empty on all three corpora**, in the contingent sense §2.4.2 now
spells out. R2 adds a routing rule and, on these corpora, no new
refusals. Choosing rejection instead would therefore cost nothing measurable _today_, which is
exactly why it should not be chosen: the one decision the corpora say would eventually be caught by
a rejection rule is a `meets the charity test`-shaped tier-2 function, and §6.2 has already ruled
that refusing those exports a model missing the statute's constitutive test.

**The measurement is syntactic, and its zeroes deserve their caveats.** It walks the parsed but
_unresolved_ AST, so name resolution is textual and corpus-wide rather than per-module. That
produced two false positives, both instructive: `DECLARE Disposal` has 2 constructors in
`housing-act-ground-1A.l4` and 3 in `-1B.l4`, and a corpus-wide type table conflates them — both
`CONSIDER`s are exhaustive in their own module, and a real per-module checker gets this right; and
`BRANCH` carries a _mandatory_ otherwise arm in the AST, so it is always total. Exhaustiveness was
checked against declared constructor sets rather than by the real checker, and prelude bodies were
not scanned beyond the six enumerated partials.

**And the zeroes are partly zeroes because the corpora barely contain the constructs being tested.**
There are **19 `CONSIDER`s in all 62 files** (1 / 1 / 17) and all 19 are exhaustive; **zero**
occurrences of `DIVIDED BY` or `MODULO` anywhere; **zero `ASSUME` declarations** in any of the three
(all use the GIVEN+record house style); `at`/`maximum`/`minimum` are never applied as prelude
functions. A positive control was therefore run — 7 probes and 4 negative controls, including a
parameter shadowing the name `maximum` — and **all seven detectors fire while all four negatives
stay clean**. The honest reading of the table above is _the criterion is cheap_, not _the criterion
is well exercised_. The single real division in all 62 files is `reg-cf.l4:101`'s
`OTHERWISE annual limit basis * 10 / 100`, whose divisor is the literal `100`, which L3 accepts.

**Bad news, flagged rather than buried — and it is not R2's.** The measurement re-derived §2.2's
census and got **4.8% / 4.0% / 5.9%** tier 2 against §2.2's **2.7% / 4.0% / 4.3%**. The first
version of this paragraph read those as corroboration — "Charities lands exactly, the other two are
1–2 points high, most likely a scope-unit difference". **That reading is wrong: the rates agree and
the populations do not.**

Back out the denominators. §2.4.3's Charities tier-1 count of 309 at a 4.0% tier-2 rate implies
~322 parameterised decisions and ~13 tier-2; Housing's 305 at 5.9% implies ~324 and ~19; Reg CF's 40
at 4.8% implies ~42 and ~2. §2.2 names its tier-2 sets outright — "7/7 in Housing, 4/5 in Charities"
— so **5** and **7**, which at 4.0% and 4.3% imply ~125 and ~163 parameterised decisions. An
independent count of top-level `GIVEN` blocks, the natural proxy for a parameterised decision,
settles which measurement the corpora support:

| corpus                            | top-level `^GIVEN` | §2.4.3 implies | §2.2 implies |
| --------------------------------- | ------------------ | -------------- | ------------ |
| `regcf.l4` (981 lines)            | 42                 | ~42            | ~74          |
| `charities-jersey-2014/*.l4` (12) | 332                | ~322           | ~125         |
| `housing-act-*.l4` (49)           | 349                | ~324           | ~163         |

So the re-derivation did **not** reproduce §2.2. It measured a population 2.0–2.6× larger and
landed on a similar ratio, and the larger population is the one the files support.

**The consequence lands on §2.2, not on R2, and it is the consequence §2.2 can least afford.** If
Housing really has ~19 tier-2 decisions, then "7/7 in Housing" is 7 of ~19 and "tier 2 correlates
≈100% with cross-module reuse" is a claim about a sample of roughly a third — and that bullet is the
one §2.2 calls "the frame paying rent", the one that makes R1 and "where do we draw the lambda"
literally the same question. **§2.2's second bullet is hereby downgraded from census to sample**
until the correlation is re-run over the full tier-2 set. Nothing in §2.4 depends on it; §2.3's
service-granularity ruling does.

The same pass also found that **the tiering is fragile with respect to test fixtures, which is where
the redesign's census claim is separately at risk.** Counting `#EVAL`/`#ASSERT`/`#TRACE` sites as
call sites flips tier 2 to
**69.0% / 83.5% / 71.3%**. §2.1 says "every reference to `d` within the scope unit" and does not
exclude directives; that sentence must say so explicitly, or the analysis inverts. Two smaller
findings from the same pass: **185 of 688 parameterised decisions (27%) have zero non-directive call
sites**, so they un-lift vacuously rather than by observed unification — R6's population, and larger
than R6 states; and the un-lifting analysis is **currently untested**, since `DmnExport.hs:986`
goldens exactly one file whose five decisions are all nullary, so no golden exists in which anything
un-lifts at all.

#### 2.4.4 Where the criterion cannot decide: a note, not a refusal

**Yes — a fidelity note is the fallback, and it is `D-PARTIAL` (§7).** The criterion has three
"don't know" cases. Each must read as `¬TOTAL` for routing purposes, while the note says _not
certified total_ rather than _is partial_:

1. **Analysis-suppressed `CONSIDER`s.** `branchHasOpaquePattern` bails on literal and expression
   patterns because the guard model cannot reason about them, and `isPrimitiveType`
   (`TypeCheck.hs:1954`) deliberately skips `NUMBER`/`STRING`/`DATE` scrutinees. An `OTHERWISE` arm
   makes both accepted, so the residual is narrow.
2. **Non-structural recursion** — accumulator patterns whose decreasing argument is not recognised,
   mutual recursion, `NUMBER`-measure recursion.
3. **Statically-safe uses of L3–L6** — `SQRT 4`, `x MODULO 12` on a whole-number field. Constant
   folding recovers the all-literal cases; the rest stay conservative, at zero measured cost.

`D-PARTIAL` therefore carries two severities and always names the failing clause and its source
range. At `Lossy`: _"`d` could not be certified total (⟨clause⟩ at ⟨range⟩), so it was emitted as a
`businessKnowledgeModel` / inlined at N call sites rather than as a `<decision>`. A DMN decision node
is evaluated on every input any requiring decision is evaluated on, and an undefined FEEL result is
`null`, which reads as `false`."_ At `Blocking`, the same text with "and no fallback was available".

Two things the note must **not** say. It must not claim the decision _is_ partial — cases 1–3 are
ignorance, not evidence. And it must not offer `@nonexhaustive` as a remedy: `@nonexhaustive` is a
_reject_ signal, being the author's own declaration that the match is incomplete. The remedy for a
genuinely non-exhaustive `CONSIDER` is in the source, and that pressure is correct.

One cross-reference, to keep the claim honest: **DMN-SAFE is about definedness, not equality.** L4's
`NUMBER` is an exact `Rational`; FEEL's `number` is a 34-digit decimal (§10.3.2.3.1). A DMN-SAFE
decision can still produce a _different_ answer. That is a fidelity question and not R2's, but
nobody should read DMN-SAFE as value-equal.

#### 2.4.5 The prerequisite: as it stands, this cannot ship on this branch

**Say it plainly: L1 is nearly vacuous here.** `checkConsider` sources its constructor oracle from
`buildConstructorLookup` (`TypeCheck.hs:1457`), which is fed only from **top-level** `DECLARE`s and
is **reset to `Map.empty` at the import boundary** (`Import/Resolution.hs:401`). Measured against
the installed `l4`:

| probe                                                                                                    | warns?  |
| -------------------------------------------------------------------------------------------------------- | ------- |
| enum declared and `CONSIDER`ed in the same file, top level                                               | **yes** |
| the same enum declared in an `IMPORT`ed module                                                           | no      |
| the same `CONSIDER` placed inside a `WHERE`                                                              | no      |
| `CONSIDER` over `MAYBE` missing `NOTHING`; over `BOOLEAN` missing `FALSE`; over a `LIST` missing `EMPTY` | no      |

A criterion that trusts `PatternMatchesMissing` on this branch will certify imported-enum,
`WHERE`-local, `MAYBE`, `BOOLEAN` and `LIST` partial matches as **total** — unsound in the silent
direction, which is the direction this whole ruling exists to close.

`main` already fixed exactly this, and **it is not an ancestor of this branch**
(`git merge-base --is-ancestor 8a8b46bc HEAD` → false). PR #45 replaces the lookup with
`constructorsInScopeFromEntityInfo`, sourced from the cumulative, cross-module-unioned,
builtin-inclusive `entityInfo`; it injects `LIST`'s `[EMPTY, cons]` pair, and excludes only
`CONTRACT` — permanently, the deontic values being an open sum. It also introduces `@nonexhaustive`,
which L2 depends on outright.

**So R2 lands in §10's Phase 4, where the routing decision is made, but with a hard prerequisite
that was not in that table: PR #45's exhaustiveness oracle must be on the `mengwong/dmn-export` line
first.** Until it is, any totality claim outside same-file top-level enums is vacuous. Added as
Phase 0.5.

Implementation surface, briefly. `lowerModule` (`Lower.hs:1296`) sees only the `Module Resolved` and
needs the checker's output; `CheckResult` (`TypeCheck/Types.hs:481-493`) already carries both
`entityInfo` and `errors`, so the signature grows one parameter. The cheap route scans
`CheckResult.errors` for `PatternMatchesMissing`, and attribution to the enclosing decision is
already free — every `CONSIDER` inside a `DECIDE` is checked under
`errorContext (WhileCheckingDecide …)` (`TypeCheck.hs:564`), so walk the context chain, taking the
outermost for a `WHERE`-local, or key by `SrcRange` containment. The cleaner route re-runs the
analysis from `entityInfo` inside the exporter, and is the only one that can distinguish "missing
arms" from "analysis suppressed" — a distinction route one structurally cannot see, because a
suppressed analysis emits no warning and is indistinguishable from a clean one. That distinction is
what §2.4.4 case 1 rests on, so the cleaner route is the one to build.

Cross-module callees are a genuine gap in both routes. `freeRefs` (`Lower.hs:1565-1570`) drops names
from other modules by design — _"which is what keeps every prelude function and builtin out of the
DRG"_ — so `TOTAL`'s fixpoint over `calls(d)` needs traversal the exporter does not have today.
Prelude callees are covered by the structural check above; user imports are not.

---

## 3. Decision-table columns are the typed bindings

This is the part the current design most underweights, and it reorders the work.

```
tInputClause  = inputExpression : tLiteralExpression   -- carries typeRef
              + inputValues?    : tUnaryTests          -- carries the domain
tOutputClause = outputValues?   : tUnaryTests
              + defaultOutputEntry? : tLiteralExpression
              @ name, @typeRef
```

(`DMN13.xsd:316-337`.) That is `let x : τ ∈ D = e`. Because `inputExpression` is a full literal
expression rather than a name, a projection `investor.annual_income` **is** a binding, typed at
its point of use. The columns materialise from what the decision reads; nothing declares them
globally.

**Consequence: columns come first, `itemDefinition` second.** A table is well-typed and
analysable from its columns alone. `itemDefinition` is needed only to type the `<inputData>`
element — the λ's parameter — which is a smaller, separable job (§4.3).

### 3.1 `inputValues` is what makes DMN's analysis mean anything

DMN 1.3 §8.2.4, normative:

> "It is important to model these expected input values, because a decision table will be
> considered complete if its rules cover all combinations of expected input values for all
> input expressions."

Completeness is assessed **against `inputValues`**, not against the type. §8.2.7 adds that they
validate the cells: _"The input entries in a unary test SHOULD be '-' or a subset of the input
values specified."_

Today the enum table in our own golden emits:

```xml
<inputExpression id="…_i1_expr" typeRef="string"><text>class</text></inputExpression>
```

— no `<inputValues>`, two rules, and a `<defaultOutputEntry>`. The domain
`{accredited, retail, institutional}` is nowhere, though `Lower.hs` computes `constructorNames`
and the `enums` set already. An analyser therefore sees an unbounded string column and cannot
assess completeness **at all**.

This means `reg-cf.l4`'s claim about that table — _"this table is INSIDE the fragment DMN's own
analysis is defined over"_ — is currently unearned. Not wrong about the fragment; the artifact
just hands the analyser nothing.

**Required:** emit `<inputValues>` for every column whose L4 type has a known finite domain.

```xml
<input id="…_i1" label="class">
  <inputExpression id="…_i1_expr" typeRef="string"><text>class</text></inputExpression>
  <inputValues><text>"accredited","institutional","retail"</text></inputValues>
</input>
```

### 3.2 `outputValues` unlocks two hit policies

`Emit.hs:198-199` declines outputValues because "we only know the values a table happens to
mention". True for a computed output; **false** for a boolean or enum-typed one. DMN 1.3 §8.2.5:

> "If provided, it is a list restricting output entries to the given list of values. … the
> ordering of the list of output values is used to specify the (decreasing) priority. The
> ordering … is also used when the hit policy is output order."

So `outputValues` is the precondition for hit policies **`P` (Priority)** and **`O` (Output
Order)**, neither of which the exporter can currently express. An L4 `CONSIDER` over an
enum-typed output supplies exactly the ordered list.

**Required:** emit `<outputValues>` when the output type has a known finite domain. Whether to
_use_ `P`/`O` is a later question; emitting the values is unconditional.

### 3.3 `OTHERWISE` stays a default — ruled 2026-07-26

With a finite domain in hand, `OTHERWISE` _could_ be expanded into explicit rules, making the
table literally complete rather than defaulted. **We do not do this.** Export stays isomorphic
to the L4; a consumer wanting completeness-by-enumeration performs the expansion itself, which
is a semantics-preserving normalisation derivable from `inputValues` + the default.

This is the rule the exporter already follows for negated prefixes (`DmnExport.hs` module
header): hit policy `FIRST` _is_ the "no earlier guard fired" quantifier, so restating it in
cells would produce a different, worse artifact.

Note the composition: **preserving `OTHERWISE` makes §3.1 load-bearing rather than optional.**
The default form says only "everything else", and "everything else" is computable only against
a declared domain. Isomorphic export is analysable precisely because the domain ships with it.

No change to the two spellings, both already correct: `<defaultOutputEntry>` under `UNIQUE` (a
catch-all row would overlap everything and make a `UNIQUE` table illegal), a final all-`-` rule
under `FIRST`.

#### 3.3.1 A defaulted table _is_ an incomplete table — and that is the point

Two normative statements settle what a default means, and they are stronger than "the default
covers the rest":

- Table 34, `defaultOutputEntry`: _"**In an Incomplete table**, this attribute lists an instance
  of Expression that is selected when no rules match."_
- Execution semantics: _"A decision table may have no rule hit for a set of input values. In this
  case, the result is given by the default output value, or null if no default output value is
  specified. **A complete decision table SHALL NOT specify a default output value.**"_

So a default does not close a gap — it **declares** one, and supplies the value taken in it.
Verified downstream: KIE/Drools 8.44 `ANALYZE_DECISION_TABLE` reports `DECISION_TABLE_GAP` on a
table with `inputValues` red/green/blue, rules for red and green, **and** a
`<defaultOutputEntry>` — `Gap detected: [ "blue" ]`. Mechanism confirmed at bytecode level:
`DMNDTAnalyser` never calls `getDefaultOutputEntry`. **That is not a KIE defect; it is the spec.**

This _strengthens_ the ruling above rather than threatening it. `OTHERWISE` in the L4 says
exactly "the enumerated rules do not cover everything, and here is what happens otherwise". The
defaulted DMN table says the same thing, and a gap report is that statement being read back
correctly. Expanding would _erase_ an assertion the source makes.

Two consequences to hold onto:

1. **The two spellings differ in completeness semantics, not just syntax.** `UNIQUE` + default is
   a declaredly incomplete table; `FIRST` + a final all-`-` rule is a **complete** one, since that
   row covers the remaining space. The exporter already emits both, so its `FIRST` tables are
   already analysably complete while its `UNIQUE` tables are declaredly not.
2. **Invariant, and it is a `SHALL`:** never emit a `defaultOutputEntry` on a table whose rules
   already cover the declared input space. Worth an assertion in the emitter.

Expect gap reports from any third-party analyser on `UNIQUE`-plus-default tables, and do not
treat them as noise to be suppressed — they are the artifact working.

---

## 4. Data model

### 4.1 Records ↔ itemDefinitions

`DECLARE T HAS f IS A τ` ↔ `<itemDefinition name="T"><itemComponent name="f" typeRef="τ">`.
Fields ↔ components, nesting ↔ nesting, projection ↔ FEEL path. **FEEL contexts are records**;
this is the tightest correspondence in the exercise.

### 4.2 Enums

`IS ONE OF` over nullary constructors ↔ `<typeRef>string</typeRef>` +
`<allowedValues><text>"A","B","C"</text></allowedValues>` on the itemDefinition, **and**
`<inputValues>` on every column that scrutinises it (§3.1).

**Both channels, because they are different scopes with different normative meanings.**
§7.3.3 (ItemDefinition metamodel): _"If an ItemDefinition element contains one or more allowedValues, the
allowedValues specifies the complete range of values that this ItemDefinition represents"_ —
that is the **type's** domain. `inputValues` is the **column's** expected values, and §8.2.4
ties completeness specifically to those. §8.2.4 also says _"Regardless of how the expected input
values are modeled"_, acknowledging that an analyser may derive a column's domain from the type
— so this is belt-and-braces rather than strictly redundant, and `inputValues` is the only
statement that is column-local. A column may legitimately be narrower than its type; L4 cannot
express that yet, but the emission shape should not foreclose it.

An enum with **non-nullary** constructors is a tagged union. FEEL has no sum type. Emit `Any`
plus a `Blocking` note; do not invent an encoding (see §11-R4).

### 4.3 Placement, and the validator trap

`itemDefinition` elements are **the first children of `<definitions>`** — before every
`<inputData>` and `<decision>`. `Emit.hs:118-131` currently builds
`map nodeXml drg.drgNodes <> [dmndiXml drg]`; item definitions must be **prepended**.

> **Do not trust `xmllint` as the gate.** libxml2 silently accepts `itemDefinition` placed
> _after_ `inputData`; Xerces rejects it with `cvc-complex-type.2.4.a`. A misordered emitter
> passes CI and then fails in Drools/Kogito and every other JAXP-based engine. See §9.

**Scalars get no itemDefinition.** Keep `typeRef="number"` for `GIVEN income IS A NUMBER`; an
alias adds no information and degrades for any consumer that does not resolve typeRefs. Mint one
for a scalar only when L4 supplies a domain.

---

## 5. Naming

### 5.1 What is actually broken

The research overturned the motivating worry. **Spaces work.** DMN 1.3 §10.3.1.4 "Tokens, Names
and White space" is normative (OMG issue DMN12-58 was resolved in 1.2 and the resolution
shipped); space-bearing names were verified evaluating in feelin 7.0.1, `@hbtgmbh/dmn-eval-js`
1.5.0 **and** Drools/KIE 8.44. **Hyphens work** too: `a-b` resolves to the joint name whenever
the joint name is declared, which an exporter always does.

So mangling is a **portability decision about Camunda** (whose engine does forbid whitespace in
names), not a correctness fix. What _is_ broken today is narrower and worse:

1. **`feelIdentText` passes dots through** — `keep c | c elem " _."` (`IR.hs:260-270`). An L4
   name containing `.` injects a FEEL path expression and silently shadows a genuine projection,
   with no warning. This is the E7 silent-misreading class, in our own code. **Fix this first;
   it is a defect independent of the whole redesign.**
2. **The same function is used for type names**, where a dot is DMN's import-prefix separator.
   Needs a separate `feelTypeNameText`.
3. **Keyword-_initial_ names** are the genuine hazard. §10.3.1.4: a name start SHALL NOT be a
   literal terminal symbol; a name _part_ MAY be. Keyword-inner is fine, which retires the worry
   about legal English being full of `in`, `for`, `between`.

### 5.2 The policy

`@name` carries a FEEL-safe identifier; `@label` carries the verbatim L4 name. `label` is an
attribute of `tDMNElement` (`DMN13.xsd:30`), xmllint-verified as available on every element type
this exporter emits. Round-trippability becomes a property of the sidecar, so mangling costs
nothing in readability.

**Stage 1 — `feelBase : Text -> Text`**, pure, deterministic, total:

1. Normalise to NFC.
2. Collapse every maximal run of Unicode whitespace to a single `' '` — engines normalise
   whitespace runs, so without this two distinct L4 names silently become one.
3. Map each character: keep FEEL name-start / name-part characters; otherwise `'_'`. **Space and
   `.` must now become `'_'`.** Map `?` to `_` as well: it is a legal name-start char but is
   S-FEEL's input-value placeholder in unary tests.
4. Collapse runs of `_`; strip leading and trailing `_`.
5. Empty → `"_"`. Leading digit → prefix `"_"`.
6. Reserved word → append `"_"` (list: `true false null and or not if then else for in return
some every satisfies instance of between function external date time duration list context`).

**Stage 2 — `uniquifyIn : Scope -> [Text] -> [Text]`** over a stable source-order traversal:
first claimant keeps the base, the nth gets `base_<n>` for the least free `n ≥ 2`. Two
independent scopes: (i) the DRG's FEEL variable namespace — all `inputData` variables and all
decision variables together, since they share one evaluation scope; (ii) each itemDefinition's
`itemComponent` list.

Stage 1 is deliberately non-injective; stage 2 makes the composite injective **within each
scope** by construction. Every rename — benign mangle and collision suffix alike — is a fidelity
entry, at **different severities**: a benign mangle preserves information in `@label`, a
collision suffix means the FEEL text no longer resembles the L4 name.

Net effect: `investor's \`annual income\``exports as`investor.annual_income`, with
`label="annual income"`on the variable, the component and the column. A mangled dotted path is
exactly S-FEEL's`qualified name`, so `Proj` (`Lower.hs:651`) stays classified `SFeel` — which
is what keeps record-reading columns inside the analysable fragment.

---

## 6. Call sites and BKMs

### 6.1 What is already right

`Lower.hs:678` — `App _ r args -> call e (feelIdent r) args`, rendering `f(x)` — **is correct**.
A FEEL invocation resolves against a BKM and evaluates, verified on Drools/KIE 8.44 in a
`<literalExpression>` and inside a decision table's `inputExpression` **and** `outputEntry`
cells. The bug is entirely on the **callee** side: the callee is emitted as a `<decision>` when
it should be a `<businessKnowledgeModel>`, and the `<knowledgeRequirement>` edge is missing.

The un-lifting analysis therefore decides **what kind of node the callee is**, not how the call
site is spelled.

### 6.2 BKM emission

Build it in v1. `encapsulatedLogic`'s body is `<xsd:element ref="expression"/>` and
`decisionTable` is in that substitution group, so **a parameterised guarded chain stays a
table** — no degradation to a literal expression. KIE's gap analyser fires on a table inside a
BKM identically to one in a plain decision, so this costs nothing in analysability.

Requirements:

- Child order (`xsd:sequence`, inherited first): `description?`, `extensionElements?`,
  `variable?`, `encapsulatedLogic?`, `knowledgeRequirement*`, `authorityRequirement*`.
  `formalParameter` is **not** a BKM child — it belongs to `encapsulatedLogic`
  (`tFunctionDefinition`).
- Emit `<knowledgeRequirement><requiredKnowledge href="#bkm_id"/></knowledgeRequirement>` on
  every calling decision. **Load-bearing and unenforced by the XSD** — omit it and KIE errors at
  both compile and eval time.
- Invariant: BKM `@name` == `variable/@name`. KIE's validator raises ERROR otherwise, and the
  two are resolved in different phases (compile-time name resolution vs runtime context
  binding).
- Formal parameters take the (mangled) L4 `GIVEN` names. DMN binds by **name**, L4 by
  **position**; emit bindings position→name at the seam.

Boxed `<invocation>` is an optional second form for a decision whose whole logic is exactly one
saturated call. It buys better modeller rendering plus a validator check ("Unknown parameter
'X'"), at the cost of not composing with a table body. Not v1.

**Why v1 and not deferred**, against the census's own recommendation: `meets the charity test`
is tier 2 with six call sites across four modules, and registration, deregistration,
required-steps notices and appeals all route through it. A v1 that refuses it exports a Charities
model **missing the statute's constitutive test**. Given BKM turns out to be cheap, refusing buys
nothing.

### 6.3 Refuse loudly — three cases, not BKMs in general

1. **Recursion.** DMN §6.3.9 (Business Knowledge Model metamodel): "a BusinessKnowledgeModel
   element SHALL not require itself, directly or indirectly". KIE
   evaluates recursive BKMs anyway (`fact(5)=120`) but emits a spurious eval-time ERROR and the
   behaviour is explicitly vendor-dependent. L4 permits recursion (`rent spine`, `ror together`
   in Housing). Needs a cycle check with its own `Blocking` note — see §11-R5 for where it lives.
2. **Partial application / higher-order.** A BKM is a first-order named function only.
3. **Non-KIE target engines.** `@hbtgmbh/dmn-eval-js` has no BKM support and fails **silently**:
   an unresolvable callee in a cell logs `resolved to undefined` and the table falls through to
   the next rule, returning a plausible wrong answer. If the exporter claims a target engine,
   gate BKM emission on it.

---

## 7. Fidelity notes

| Code               | Change                                                                                                                                                                                                                                                                                                                                                                                                                                  | Rationale                                                                                                                                                                                                                                                                                                                                                                     |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `D-SCOPE`          | **Repurpose.** Today it fires on "two Uniques, one FEEL name" (`Lower.hs:1245-1258`) — universal under GIVEN style, so pure noise. Replace the predicate with a **type conflict** test: two same-named terms with _different_ declared types.                                                                                                                                                                                           | `freeTermTypes` is a plain `Map.fromList` (`Lower.hs:1228`), i.e. **last-wins** — that is the genuine defect currently hidden behind the false positives. Also fix: the message hardcodes "two different terms" for 3+, anchors only to the first element's id, and its `lost:` text ("L4's lexical scoping of GIVEN parameters") is false when two global `ASSUME`s collide. |
| `D-PARAM-AS-INPUT` | **New**, `Advisory`. A tier-1 decision's parameters became model inputs; the decision can no longer be applied twice to different subjects within this model.                                                                                                                                                                                                                                                                           | Names what un-lifting costs, without pretending it is free.                                                                                                                                                                                                                                                                                                                   |
| `D-BKM`            | **New**, `Advisory`. A tier-2 decision became a BKM, with the differing call sites listed.                                                                                                                                                                                                                                                                                                                                              | The reader should know which decisions are functions.                                                                                                                                                                                                                                                                                                                         |
| `D-RECURSIVE`      | **New**, `Blocking`. §6.3 case 1.                                                                                                                                                                                                                                                                                                                                                                                                       |                                                                                                                                                                                                                                                                                                                                                                               |
| `D-PARTIAL`        | **New**, two severities, **keyed off the call site and not off the node kind** (§2.4.2). `Lossy` only when every call site consumes the decision from a _lazy_ position and it was inlined or emitted as a BKM; `Blocking` when any call site consumes it strictly, and when it is a DRG root. Names the failing clause and its range, says _not certified total_ rather than _partial_, and never offers `@nonexhaustive` as a remedy. | §2.4. Not decision-node-ness: an undefined FEEL result is `null` wherever it arises — `<decision>` body, BKM `encapsulatedLogic`, or inlined cell alike — and `null` reads as `false` at the first boolean consumer. Routing to a BKM removes the input _widening_; only a lazy consuming position removes the _coercion_.                                                    |
| `D-SUMTYPE`        | **New**, `Blocking`. §4.2, tagged union.                                                                                                                                                                                                                                                                                                                                                                                                |                                                                                                                                                                                                                                                                                                                                                                               |
| `D-RENAME`         | **New**, two severities. Benign mangle = `Advisory` (recoverable from `@label`); collision suffix = `Lossy`.                                                                                                                                                                                                                                                                                                                            | §5.2.                                                                                                                                                                                                                                                                                                                                                                         |
| `D-MD-FLATRECORD`  | **New**, `Lossy`, markdown carrier only. §8.                                                                                                                                                                                                                                                                                                                                                                                            |                                                                                                                                                                                                                                                                                                                                                                               |

---

## 8. The markdown carrier

**Under record threading the markdown emitter currently produces _nothing_** — not a degraded
table, zero tables. Verified by running it: every table dies on `D-MD-NONIDENTCOLUMN` because
`Lower` renders a projection as a FEEL qualified name and dmnmd's `parseVarname` admits no `.`;
`dmnmd -f md` over the result then prints `** parser failure in grepMarkdown`, because a
table-free file is not a case its fallback handles.

So this is not a nice-to-have. **Day-one behaviour: flatten, keeping the thread variable as a
prefix.** `i.annual_income` → column `i annual income : Number`, one column per projected _path
actually used_, one `D-MD-FLATRECORD` note per table. Verified end to end: the flattened
markdown parses and `dmnmd -t l4` returns well-formed L4.

It is the least-lying option because the lie is confined to the **type** level — cells, rules,
hit policy and outputs are bit-identical to the scalar form, so the table decides exactly what
the record version decides. What is lost is that `i annual income` and `i net worth` came from
one object. Keeping the prefix is not cosmetic: it is what makes the flattening injective when
two records share a field name.

State the round-trip property in the contract as **L4 → md → L4′ equal modulo record
flattening**, rather than letting a golden discover it.

Three consequences for `~/src/smucclaw/dmnmd/BUILD-SPEC-dmnmd-extensions.md`, to be handed over
as an addendum (l4-ide still never depends on that repo):

1. **E1 is specified against the program shape being replaced.** Under threading, a reference to
   another decision is `annual limit basis(i)`, not `annual limit basis`, so E1's
   output-column-name matching resolves **zero** edges in the new corpus. Rewrite before anyone
   builds it.
2. **Enum domains want a home in the markdown grammar** — E8's existing subject. Note for the
   dmnmd session, not a constraint on this spec: at time of writing dmnmd parses
   `itemDefinition` and ignores it, so an XML→md→L4 differential would not today observe a
   domain carried only on the type. That is a snapshot of a component under active redesign and
   should not drive our emission; §3.1/§4.2 justify both channels from the DMN spec alone.
3. A new item — record types have no home in a pipe table — for the flattening above.

**dmnmd's current behaviour is not a design input.** It is under substantial redesign; this
spec's obligations to it are limited to the standing contract (emit strictly within the grammar
of the day, record every gap as a `D-MD-*` note, never depend on the repo). Where dmnmd's
present state is mentioned above it is reportage for the dmnmd session's benefit, and any of it
may be obsolete by the time either side ships.

---

## 9. Verification plan

- **Schema: Xerces, not libxml2.** Add a JAXP-based check to the export suite (~20 lines, system
  JDK only). Without it a misordered emitter passes CI and fails in every real engine (§4.3).
- **A negative golden** `M1-itemdef-after-inputdata.dmn`, precisely because it is the case the
  obvious validator misses.
- **Execution, not just validation.** Drive emitted models through Drools/KIE 8.44 (TCK
  reference implementation). Schema validity is not engine acceptance — the duplicate-name bug
  validated cleanly and produced wrong answers.
- **Fix the test harness's own hole first.** `drgNamed` (`jl4/tests/DmnExport.hs:808`) matches
  only `Left` from `checkWithImports`; **type errors come back inside `Right` as `tcdErrors` /
  `tcdSuccess=False`** (`Resolution.hs:265-279`) and are ignored, so the whole DMN suite
  currently accepts ill-typed L4. Same defect class as `jl4-service/src/Compiler.hs:68` — two
  occurrences make it worth a lint rather than two fixes.
- **Re-cut the exhibit** from the real 981-line GIVEN-style Reg CF corpus
  (`../l4wt/regcf-corpus/jl4/examples/legal/regcf/regcf.l4`) rather than the 5-`ASSUME` toy.
- **Open empirical question, answerable not arguable:** does KIE's gap analyser perform the
  `OTHERWISE`-expansion given `inputValues` + a `defaultOutputEntry`? A KIE 8.44 classpath
  exists in the session scratchpad; run it, with a genuinely-gapped table as positive control.

  **Phrase the resulting claim carefully.** Two different things get called "DMN's analysis":

  1. the **analysable fragment** — a mathematical property (Calvanese et al.), vendor-independent
     and true of the artifact whether or not anyone runs a checker;
  2. an **implementation** of completeness/overlap checking, which appears to vary by vendor and
     is believed _not_ to be part of DMN conformance testing (the TCK looks to be runtime
     evaluation only — being verified).

  The defensible claim is therefore about (1) plus artifact adequacy: _this table lies inside the
  fragment for which completeness and overlap are decidable, and the emitted artifact carries the
  domain information such a checker requires._ That is true regardless of vendor uptake. "DMN
  validates this" is the claim to avoid, and it is the one §3.1 says we have not even earned in
  the weaker form, because we ship no domain at all.

---

## 10. Sequencing

Each phase is independently shippable and independently useful.

| Phase   | Content                                                                                                                                                                                                                                                                                                                                                                                             | Depends on |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| **0**   | Kill the dot passthrough in `feelIdentText` (§5.1-1). Fix `drgNamed`'s type-error hole (§9). Add the Xerces check.                                                                                                                                                                                                                                                                                  | —          |
| **0.5** | Land PR #45's exhaustiveness oracle (`constructorsInScopeFromEntityInfo`, `@nonexhaustive`) on this line — `8a8b46bc` is not an ancestor. Hard prerequisite for §2.4's L1 and L2; without it the totality criterion is vacuous outside same-file top-level enums.                                                                                                                                   | —          |
| **1**   | Columns: `typeRef` + `<inputValues>` / `<outputValues>` from L4's known domains (§3).                                                                                                                                                                                                                                                                                                               | 0          |
| **2**   | Naming policy: `feelBase` + `uniquifyIn`, `@label` everywhere, `feelTypeNameText` (§5.2).                                                                                                                                                                                                                                                                                                           | 0          |
| **3**   | `itemDefinition` emission and placement; records and enums at the data level (§4).                                                                                                                                                                                                                                                                                                                  | 2          |
| **4**   | The un-lifting analysis and its totality side-condition; `D-SCOPE` repurposed; `D-PARAM-AS-INPUT`, `D-PARTIAL` (§2.1, §2.4, §7). **Two obligations §2.4 incurs on this phase:** a test that fails when `UserEvalException` grows a ninth constructor (§2.4.1's coverage map), and a re-run of §2.4.3's census against the _real_ structural-termination check rather than the flat recursion proxy. | 3, 0.5     |
| **5**   | BKM emission, `knowledgeRequirement`, the three refusals (§6).                                                                                                                                                                                                                                                                                                                                      | 4          |
| **6**   | Markdown carrier: flattening + `D-MD-FLATRECORD`; dmnmd addendum (§8).                                                                                                                                                                                                                                                                                                                              | 3          |

Phase 1 alone makes the existing exhibit's analysability claim true, which is worth shipping on
its own.

---

## 11. Open rulings

- **R1 — Scope unit. ANSWERED 2026-07-26, see §2.3.** Not module-vs-closure: one `<definitions>`
  per module, one `<decisionService>` per `§`. The "several models" fan-out was never forced —
  `tInvocable` is a `drgElement`, so many services live in one model. The residual sub-ruling is
  §2.3's **service granularity**, which is a constraint to satisfy rather than a preference to
  choose.
- **R2 — Strictness. ANSWERED 2026-07-27, revised the same day under review, see §2.4.** DMN
  computes every _required_ decision; L4 forces lazily, and un-lifting widens the input set a shared
  node is evaluated under. The consequence is worse than "undefined": **FEEL has no undefined** — it
  has `null`, and `null` reads as `false` in a guard, a table row and an `every … satisfies` alike,
  so L4's loud exception becomes a silent wrong answer. The side-condition stays, as a **routing**
  rule rather than a rejection: `TOTAL ∧ PURE ∧ DETERMINISTIC`, evaluated only in strict positions,
  gates tier-1 `<decision>` emission and multi-output `decisionService` co-membership.
  **Severity is keyed off the call site, not the node kind** — routing to a BKM removes the input
  widening but not the `null` coercion, so a strictly-consumed `¬DMN-SAFE` decision is `Blocking`
  even though a fallback node kind exists (§2.4.2). Measured cost: **5 of 654 tier-1 decisions
  (0.8%), 1 of 541 (0.2%) once regulative bodies are excluded, all five recursion — a set §6.3-1
  already refuses**, so R2's own `Blocking` arm is empty on these three corpora, contingently.

  **What review changed, recorded so it is not un-changed by accident.** Five defects, all repaired
  in place, none of which unseated the ruling: `TOTAL` was specified as the _least_ fixed point,
  which rejects every list-touching decision (now the greatest, §2.4.1); L1 did not exhaust
  `NonExhaustivePatterns` — sum-type field projection is a second, `CONSIDER`-free source, now L11;
  L7 was stated at the head type when `EQUALS` recurses structurally, so a record with a function
  field escaped it; `BlackholeForced` was unmapped and a `WHERE`-local cycle escaped both
  `LOCALLY-TOTAL` and `TERMINATES`, now L12; and §2.4.2's "tier 2 is sound by construction" was
  false. Two of the five were **silent-unsoundness** holes found by probing the evaluator rather
  than by re-reading the constructor list, which is why §2.4.1 now carries an explicit coverage map
  and an obligation to test it mechanically.

  Residual risk, in order. (1) The **oracle**: L1 depends on PR #45's exhaustiveness fix, which is
  not on this branch (§2.4.5, Phase 0.5 in §10). (2) The **measurement scored a proxy** whose
  recursion detector is flatter than the ruled structural check, so the accepting branch of that
  check has zero corpus exercise and 0.8% is an upper bound rather than an estimate (§2.4.3). (3)
  L11 is not covered by §4.2's tagged-union `Blocking`, because **R4 is still open**.

- **R3 — Unicode in `feelBase`.** Keep FEEL-legal non-ASCII name characters (spec-legal;
  `feelin` evaluates `revenu année` natively) or ASCII-fold? Today's `feelIdentText` destroys
  them (`année` → `ann_e`). Leaning keep, with a fold behind a flag.
- **R4 — Tagged unions.** `Blocking` refusal, or a context with a discriminant plus optional
  payload fields and a `Lossy` note? Leaning refusal for v1; the corpora do not need it.
- **R5 — Where the acyclicity check lives.** In `Lower`, or as a pre-emission well-formedness
  pass? L4's one-pass scope checker does not currently admit forward references among top-level
  `DECIDE`s, so no module can produce a cycle **today** — but §6.3-1 recursion is reachable
  through local recursion. `Lower.hs:1339-1349` already documents this as a deliberate gap.
- **R6 — The uncalled population.** 44% of Charities decisions and 18% of Housing are never
  called. They are DRG roots; a parameterised uncalled decision has no supplied input. Becomes a
  decision with `inputData` synthesised from its `GIVEN`, or dropped?
- **R7 — Target engine.** Is Camunda a target? If nobody will open these files in Camunda
  Modeler, §5's mangling collapses to "just stop emitting dots", since spaces work everywhere
  else. If it is, the full policy applies — and BKM emission needs gating (§6.3-3).

---

## 12. Non-goals

- **`legalese/l4-ide` never depends on `smucclaw/dmnmd`.** dmnmd is local differential
  validation. Gaps go into its extension spec as an addendum; the exporter degrades honestly
  with `D-MD-*` notes until they land. Neither side waits on the other.
- Not a general DMN implementation. No decision services, no DMNDI layout beyond what is already
  emitted, no FEEL evaluation.
- Not the process side. `Regulative`/`Deonton` targets BPMN 2.0 (PR #141) and has no markdown
  carrier.
