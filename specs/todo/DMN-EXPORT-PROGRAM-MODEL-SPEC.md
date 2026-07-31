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

> **On what the DMN ecosystem does and does not analyse**, see
> [A Gap Analysis of Gap Analysis](../../doc/concepts/language-design/dmn-analysis-prior-art.md)
> — the canonical copy. One result is directly binding on this spec: **DMN 1.0's completeness
> indicator was removed by OMG in 1.1**, so a completeness claim cannot be emitted into conformant
> DMN 1.1+ XML at all. Whatever the exporter knows about a table's completeness has to travel in
> the fidelity report.

---

## 0. Ruling status, and whether smucclaw/l4-ide#923 is unblocked

**Updated 2026-07-27 by the integration pass that folded in R3–R6.**

| ruling                              | state                                     | detail                                                        |
| ----------------------------------- | ----------------------------------------- | ------------------------------------------------------------- |
| R1 — scope unit                     | **ANSWERED** 2026-07-26                   | §2.3                                                          |
| R2 — strictness                     | **ANSWERED** 2026-07-27, revised same day | §2.4                                                          |
| R3 — Unicode in `feelBase`          | **ANSWERED** 2026-07-27                   | §5.3                                                          |
| R4 — tagged unions                  | **ANSWERED** 2026-07-27                   | §4.2.1                                                        |
| R5 — acyclicity                     | **ANSWERED** 2026-07-27                   | §6.4                                                          |
| R6 — the uncalled population        | **ANSWERED** 2026-07-27                   | §2.5                                                          |
| R7 — target engine                  | **ANSWERED** 2026-07-27, elsewhere        | §13, arriving with PR #160 (branch `feat/dmn-engine-flavors`) |
| **R8 — builtin `MAYBE` / `EITHER`** | **ANSWERED 2026-07-29**, opened by R4     | §4.2.1-6, §11                                                 |

### Is #923 unblocked? **Yes.**

smucclaw/l4-ide#923 is R2's strictness side-condition. It was blocked because "R3, R4, R5 and R6 are
unsettled". All four are now ruled, and each ruling states explicitly what it does and does not do to
R2 (§14 is the register). Concretely:

- **R2's residual risk (3)** — _"L11 is not covered by §4.2's tagged-union `Blocking`, because R4 is
  still open"_ — is now **discharged for user-declared unions** and **narrowed to a named residue**.
  R4 (§4.2.1) rules `D-SUMTYPE` `Blocking` on the decision that _reads_ a payload-carrying
  user-declared `IS ONE OF`, and a payload-field projection is one of the three reading forms, which
  is exactly L11's subject at the decision level. What R4 deliberately does **not** cover is the
  builtin open sums, which is R8.
- **R8 does not block #923.** L11 stands inside `LOCALLY-TOTAL` on its own and does not consult
  §4.2, so R2's soundness does not wait on R8. And L11 has **no `MAYBE` exposure at all**: **[E]**
  ``GIVEN m IS A MAYBE NUMBER … `the payload` m MEANS m's val`` is a **type error** —
  `l4 check` reports _"I could not find a definition for the identifier `val`, which I have inferred
  to be of type FUNCTION FROM MAYBE OF NUMBER TO NUMBER"_ — so `MAYBE`'s payload is not reachable by
  a named projection, and a `MAYBE` is scrutinised with `CONSIDER`, i.e. through **L1**. R8 is a
  §4.2 _type-emission_ question in Phase 3, not a totality question. **[ANSWERED 2026-07-29, and the
  split this sentence predicted is the shape of the answer: §11-R8 accepts the leaning on the type
  channel and refuses it on the value channel.]**
- **R5 does not block #923** either way round. It ships in Phase 0, is independent of the un-lifting
  analysis, and §6.4.7 records that it is an artifact well-formedness check and **not** a recursion
  detector — recursion detection stays with §6.3-1 and §2.4.1.
- **R3, R4 and R6 all land in phases #923 depends on** (2, 3 and 4 respectively). That is
  _sequencing_, not blocking: none of them changes the `DMN-SAFE` predicate, so none of them can
  change what #923 has to implement. R6 changes the _population_ `DMN-SAFE` is evaluated over, which
  is why §10 Phase 4 now carries the obligation to re-run §2.4.3's census against the post-filter
  population rather than the old one.
- **What "unblocked" means here, said plainly.** Every design question §11 listed as open is now
  answered — **R8 included, as of 2026-07-29 (§11-R8)**, and R8 was in any case a
  type-emission question that cannot reach `DMN-SAFE`. #923 can be
  specified, reviewed and implemented against a settled model. It still has the two implementation
  prerequisites R2 always had — Phase 0.5's oracle, and the census re-run — and those are tracked in
  §10, not here.

R2's own two other residual risks are unchanged and are **not** rulings: (1) PR #45's exhaustiveness
oracle is still not on this line (§2.4.5, Phase 0.5), and (2) §2.4.3 measured a proxy whose recursion
detector is flatter than the ruled structural check. Both are implementation prerequisites tracked in
§10, not open questions about the design.

### Evidence legend, used throughout §2.5, §4.2.1, §5.3, §6.4 and §14

- **[E]** — executed by the integration pass, in this worktree, with the command shown.
- **[M]** — executed by the measurement or adversarial-review pass, artifact on disk in the session
  scratchpad, **not re-run here**. For this document's own evidence rule an `[M]` claim has the
  standing of **UNVERIFIED**: it must be re-executed before implementation relies on it. It is
  recorded rather than dropped because it says where to look.
- **[D]** — read in this tree's source, or in the OMG DMN 1.3 text, with the anchor given.
- **[U]** — unverified, and named as such.

---

## 1. Why the current model is wrong

Verified empirically (harness positive-controlled against the committed `reg-cf` goldens,
byte-identical output):

| #   | Symptom                                                                                                                                                                                                                                                                                           | Anchor                                                                 |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| 1   | Free terms are keyed by `Unique`. Each decision's `GIVEN` is a separate `def`, so N decisions sharing a parameter name yield N `<inputData>` elements.                                                                                                                                            | `Lower.hs:1201`                                                        |
| 2   | `assignIds` dedups the **id**; `idName = nm` does **not** dedup the **name**, and neither does the inner `<variable name=…>`. A probe emitted 9 `<inputData>`, three named `annual income`, two named `class`.                                                                                    | `Lower.hs:1359`, `Lower.hs:1219`                                       |
| 3   | That output is **XSD-valid** — `DMN13.xsd` constrains `id` as `xsd:ID` but `name` as bare `xsd:string`, with zero `xsd:unique`/`key`/`keyref`. Validation catches nothing.                                                                                                                        | `DMN13.xsd:29-40`                                                      |
| 4   | A real engine **silently collapses** the duplicates. `@hbtgmbh/dmn-eval-js` 1.5.0 parses the model and evaluates every decision against the single context entry. Not a rejection — a wrong answer.                                                                                               | executed                                                               |
| 5   | `D-SCOPE` fires once per colliding FEEL name. Zero notes under `ASSUME`; three in a GIVEN-style probe. A note written as a rare diagnostic is the normal case.                                                                                                                                    | `Lower.hs:1245-1258`                                                   |
| 6   | ~~Record types erase to `Any`~~ — **DOWNGRADED 2026-07-29 (Phase 3).** A record declared in **this** module now gets an `itemDefinition` and a named `typeRef`; a type declared in **another** module still erases to `Any`, because `topDecls` is module-local, and is now reported `D-ITEMDEF`. | `Lower.hs:1282-1286` → `classifyType`, `Emit.itemDefinitionXml`        |
| 7   | ~~Enum **domains** are discarded~~ — **RETIRED 2026-07-29 (Phase 3).** An `IS ONE OF` becomes a named `itemDefinition` over `string` carrying `allowedValues`, and every column that scrutinises one carries `inputValues`.                                                                       | ~~`Lower.hs:973`, `Emit.hs:198`~~ → `Lower.hs:1284`, `Emit.hs:225-234` |

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

> **The example is kept in its ORIGINAL spelling on purpose, and it is no longer the corpus's.**
> As of 2026-07-31 `greater of annual income or net worth` is a **computed field** on
> `InvestorProfile` rather than a standalone unary decide, and `regcf.l4` reads it as a
> projection — `` investor's `greater of …` `` (§4.4, and §4.4.7 for what that bought). The
> lambda-lifting point above is about the SHAPE of house-style L4 in general and is unaffected —
> plenty of the corpus is still written this way — but a reader who greps for this text in
> `regcf.l4` will not find it, and that is the drift this note exists to stop.

So the translation is **un-lambda-lifting**, and DMN's answer to "where did the arity go?" is
_the model itself is the lambda_ — you invoke a DMN model by supplying its `inputData`. Arity
moves from each decision up to the model, where DMN puts it.

### 2.1 The analysis, stated once

For each top-level `DECIDE` `d` with parameters `p₁…pₙ`:

- **Un-lifts (tier 1)** if every **non-directive** reference to `d` within the scope unit applies it
  to the same argument expressions. Then `d` becomes a `<decision>`; each `pᵢ` becomes an
  `<inputData>` shared with every other decision that names it; and references to `d` are bare names
  carrying an `<informationRequirement><requiredDecision>` edge. Nothing is lost.

  > **"Non-directive" added 2026-07-27 (R6).** §2.4.3 already found that counting
  > `#EVAL`/`#ASSERT`/`#TRACE` sites as call sites flips tier 2 from ~4% to 69–84%, i.e. inverts the
  > analysis, and said the sentence "must say so explicitly". It now does. **Directive references
  > are load-bearing in exactly one place, with the opposite polarity — §2.5.7's fixture
  > criterion.** Both statements live in the two places named here so that a later editor
  > "simplifying" one can see the other.

  > **Type-conflict side-condition, added 2026-07-27 (R6).** Two decisions may share a parameter
  > _name_ and not a parameter _type_. Un-lifting them onto one `<inputData>` is a silent wrong
  > answer, so it is prohibited: see §2.5.3 and §7's repurposed `D-SCOPE`, which R6 raises to
  > `Blocking` for exactly this case.

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

**Cited exactly, 2026-07-27 (R5).** The clause is not a "§6.3.9-analogue" — it has its own number.
**DMN 1.3 §6.3.10 "Decision service metamodel", pp. 42–43:** _"An instance of DecisionService is said
to be well-formed if and only if its requirement subgraph is acyclic, that is, that a DecisionService
element SHALL not require itself, directly or indirectly."_ Its requirement subgraph is the union of
its members'. So this is **ill-formed**. §6.4.1 quotes all three of DMN's acyclicity clauses side by
side. **A second §6.3.10 constraint, newly read and not previously recorded here** (R6, §2.5.5):
_"The encapsulatedDecisions, inputDecisions and inputData attributes are optional. At least one of
the encapsulatedDecisions and inputDecisions attributes SHALL be specified."_ That bites on the
single-member sections §2.5.5 measures. Measured:

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
`Blocking`.** (**Updated 2026-07-27 when R4 was ruled**, §4.2.1: R4-a makes a payload-field
projection `Blocking` at the reading decision, which _is_ L11's subject for **user-declared** unions
and drives its single-decision traffic to zero by construction — but the builtin open sums are
deliberately left to **R8**, and §4.2's note is type-scoped where L11 is decision-scoped.) L11 must
therefore still stand on its own inside `LOCALLY-TOTAL`, and not be justified by a sub-ruling made
about a different scope.

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

**RULED 2026-07-31 (OPEN-1, Phase 4's build): in Phase 4 this table assigns _severities_, not
_node kinds_ — Phase 4 classifies and reports; it does not change what is emitted.** A `¬DMN-SAFE`
decision simply **does not un-lift**: it keeps today's `<decision>` node and its saturated call
sites keep rendering as verbatim L4 (already `Blocking`-noted by `D-LITERALEXPR`), and it carries
`D-PARTIAL` at the severity this table rules. Rows 2–4's node kinds — BKM, inline, "never a node" —
are **Phase 5's to honour**, because BKM emission and a decision-inliner do not exist in Phase 4
(`peelLocals` inlines `WHERE`-locals only). This is sound: it introduces no new silent `null`,
since a verbatim call site is an engine-visible compile failure, not a wrong answer. Row 4's
"never a node" also stands in tension with `Lower.hs`'s standing never-drop principle and R6 rule
1's keep-uncalled-roots; the measured residual set is empty on all three corpora, so nothing
decides it by measurement — Phase 5 must re-open row 4 explicitly when it changes node kinds.

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

> **DISCHARGED 2026-07-31 on the Phase 4 line.** PR #45's oracle
> (`constructorsInScopeFromEntityInfo` + `@nonexhaustive`) was **vendored onto
> `mengwong/bkm-phase4-unlift`** as merge commit `904192ea` before any Phase 4 totality code was
> written — the Phase 0.5 route (A), not the gate-on-`Unknown` route (B). Note the oracle was
> REVERTED on `origin/main` on 2026-07-13, so ancestry-of-`8a8b46bc` is no longer the right probe;
> the vendor commit is. W3 took the **cleaner route** below: `L4.Dmn.Analysis.analyzeSafety`
> re-examines each `CONSIDER`'s own branches for opaque/literal patterns (the suppressed-analysis
> case) and takes the checker's `PatternMatchesMissing` ranges (`dloMissingMatchRanges`, extracted
> identically at both call sites) for the reported-missing case, exactly the two-disjunct L1 this
> section demands. The cross-module-callee gap below **remains open and is stated in the code**
> (`Analysis.hs`, `analyzeSafety`'s haddock).

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

### 2.5 The emitted population: which decisions reach the DRG at all — R6, ruled 2026-07-27

**R6 asked a binary about one population. There are four populations, the binary is false for three
of them, and the numbers R6 states do not reproduce.** Its premise — _"a parameterised uncalled
decision has no supplied input"_ — is also false: the exporter already synthesises `inputData` from
`GIVEN`, and both R7 target engines evaluate the result. What is actually broken is the opposite of
what R6 worried about: the uncalled set contains **test scaffolding**, and that scaffolding is what
stops a real corpus module compiling in an engine.

Evidence tags are §0's.

#### 2.5.1 R6's headline numbers do not reproduce

**[M]** Measured by `l4 ast` over 66 files (the spec's 62 plus the four GCO Jersey Covid files),
`Anno` blocks elided, then a structural walk of the parsed tree — not grep. A call site is the head
name of an `App`/`AppNamed`; binder shadowing (`GIVEN`, `WHERE`-locals, `PatApp` binders) is
subtracted; `Directive` sub-trees are scored separately. The parameterised-decision count reproduced
§2.4.3's 42 / 322 / 324 = 688 exactly, so the denominators agree and only the numerator is disputed.

| variant (scope; do directives count as calls?) | Reg CF        | Charities       | Housing         | GCO            |
| ---------------------------------------------- | ------------- | --------------- | --------------- | -------------- |
| all decisions, module, dir=N                   | 20/73 = 27.4% | 420/682 = 61.6% | 369/791 = 46.6% | 62/129 = 48.1% |
| all decisions, module, dir=Y                   | 2/73 = 2.7%   | 20/682 = 2.9%   | 43/791 = 5.4%   | 0/129 = 0.0%   |
| **parameterised only**, module, dir=N          | 6/42 = 14.3%  | 116/322 = 36.0% | 52/324 = 16.0%  | 0/45 = 0.0%    |
| nullary only, module, dir=N                    | 14/31 = 45.2% | 304/360 = 84.4% | 317/467 = 67.9% | 62/84 = 73.8%  |

**[M]** Sensitivity: the two headline cells were re-run with binder-shadow correction on/off and with
non-`Decide` top-level references included/excluded — all four combinations byte-identical. The
adversarial review re-derived the whole grid by an independent walker written from `Syntax.hs`
constructor definitions and reproduced **every cell**.

**No variant yields R6's 44% / 18%.** Housing's parameterised rate is close (16.0%); Charities is
nowhere near 44% on any denominator. **[U]** The likely provenance is §2.2's superseded census
population, which §2.4.3 already downgraded. **Replace R6's figures with this table.**

#### 2.5.2 The uncalled set is four populations, and only one is what R6 meant

**[M]**, and every row independently reproduced by the adversarial review:

| corpus       | called (internal) | uncalled: **fixture** | uncalled: **regulative** | uncalled: **inert stub** | uncalled: **DMN root** | total    |
| ------------ | ----------------- | --------------------- | ------------------------ | ------------------------ | ---------------------- | -------- |
| Reg CF       | 53                | 5                     | 3                        | 5                        | **7**                  | 73       |
| Charities    | 262               | 232                   | 88                       | 10                       | **90**                 | 682      |
| Housing      | 422               | 294                   | 46                       | 4                        | **25**                 | 791      |
| GCO          | 67                | 43                    | 0                        | 0                        | **19**                 | 129      |
| **all four** | 804 (48.0%)       | **574 (34.3%)**       | 137 (8.2%)               | 19 (1.1%)                | **141 (8.4%)**         | **1675** |

Of the 141 DMN roots, **[M]** 129 (91%) are referenced by at least one `#EVAL`/`#ASSERT`/`#TRACE` —
the author wrote a test asking that question, which is the strongest available evidence of
entry-point status — and 12 are referenced by nothing at all, every one an inert prose carrier by its
own name.

> **Two claims from the measurement pass are struck, on the review's counter-measurement.** (i) _"59
> have `reach > 0` … including Housing's 30 `ground N possession order` roots (reach 2–18)"_ —
> **[M]** the true figure is **68**, Housing has **25** roots in total, of which **2** have reach > 0,
> and **no root is named `… possession order`**: all 38 `possession order` decisions classify
> _regulative_, which rule 3 below routes to BPMN. That sentence cited, as rule 1's headline
> keep-evidence, decisions that rule 3 removes from the artifact three paragraphs later. (ii)
> _"Housing's 69 `CONTRACT`/`DEONTIC` decisions are all already refused by `isRegulative`"_ —
> **[M]** the refusal count is **45**, because `isRegulative` (`Lower.hs:1816`) is `cosmosOf` over a
> decision's **own** body, so a decision that merely _calls_ a regulative one is not refused.

#### 2.5.3 R6's premise is false — and the way it is false is a hazard of its own

**[D]** `Lower.hs:1554-1577` collects `freeTerms` across all decisions and emits one `MkInputData`
each; `Lower.hs:1767-1769` says so outright — _"`GIVEN` parameters are bound in the signature, not
the body, so they correctly come out free and become `inputData`."_ Types come from `dmnTypeOf`
(`Lower.hs:1244-1248`), which sends every non-builtin, non-nullary-enum type to `DmnAny`. **[E]**
`grep -rn itemDefinition jl4-core/src/L4/Dmn/` returns nothing.

**[M]** Exported from `housing-act-ground-8.l4`: `GIVEN claim IS A Ground8Claim` on six decisions
emits six `<inputData name="claim" typeRef="Any">` plus a `D-SCOPE` note, and the uncalled root
`ground 8 possession order` is emitted with its `requiredInput` intact. **[M]** Driven through KIE
8.44.0.Final and Camunda 8.7.6 on a four-decision model shaped like `part-3-charity-test.l4`:
supply the record and the uncalled root evaluates **correctly** in both. So DMN's answer to R6 is
§2's own frame — _the model is the lambda_ — and `itemDefinition` is a documentation feature, not a
soundness one (**[M]** no effect in Camunda 8; in KIE it converts a missing-field silent `null` into
an error only under the **non-default** `-Dorg.kie.dmn.runtime.typecheck=true`).

**But un-lifting those six is only sound because they are six of the same type. They are not always.**

**[E]** `paper/case-studies/gco-jersey-covid/GCO-first-version.l4:157,164` binds `s` at two distinct
declared types, on two `@export`ed statutory conclusions that are both uncalled roots:

```
GIVEN s IS A Article3Situation  … DECIDE `the person commits an Article 3 offence`
GIVEN s IS A Article7Situation  … DECIDE `the person commits an Article 7 offence`
```

**[E]** `l4 export … GCO-first-version.l4 --to dmn --fidelity-report` on this branch emits
`<inputData id="input_s" name="s">` and `<inputData id="input_s_2" name="s">`, with a `D-SCOPE`
_lossy_ note naming both users. Under §2.1's un-lifting they collapse to **one** `s`, and **[M]**
KIE 8.44 then answers `commits an Article 3 offence = true` and `commits an Article 7 offence =
null`, `SUCCEEDED`, zero runtime messages; Camunda 8.7.6 the same with no failure and no message.
That is §2.4's Kleene coercion arriving through the front door. **[M]** 11 modules bind one `GIVEN`
name at two or more declared types; 17 kept roots sit in them.

> **This is the one place R6 and R7 compose, and the composition is not obvious.** **[E]** Run the
> same file through the R7 branch's binary (`feat/dmn-engine-flavors`, `7e766d71`) and the hazard is
> already **loud**: `D-FEELNAME`, **`blocking`**, _"`s` is the FEEL name of 2 elements this module
> keeps apart"_ — four such notes on that file (`g` ×10, `p` ×3, `s` ×2, `_self` ×5). **But
> `D-FEELNAME` counts elements that share a FEEL name, and after un-lifting there is exactly one
> element, so it goes quiet at precisely the moment the hazard becomes real.** The note that has to
> take over is §7's repurposed `D-SCOPE` — whose ruled predicate is already _"two same-named terms
> with different declared types"_ — and R6 therefore raises it to **`Blocking`**. Detection must not
> be handed from a `Blocking` note to a `Lossy` one by an improvement.

#### 2.5.4 What the scaffolding costs, measured

**[M]** KIE build of the real exported `housing-act-ground-8.dmn`: **18 errors, does not compile.**
Deleting only the 5 test fixtures and 2 inert-prose decisions: **18 → 6**. Also deleting the
regulative root: **6 → 5**. **[M]**, and corrected by the review: deleting the fixtures **alone** —
which is all rule 2 prescribes — gives **18 → 8**, so **rule 2 buys 10 errors, not 12**. The other 2
come from em-dashes in two decisions rule 1 **keeps**, and are fixed by §5.2/§5.3's mangling in Phase
2, not by R6.

#### 2.5.5 The R1 interaction, and where the measurement pass overstated it

**[D]** DMN 1.3 §6.3.10, p. 43, Table 17: _"A DecisionService element has one or more associated
outputDecisions"_; `outputDecisions: Decision [1..*]`. (The measurement pass cited this as §7.3.5;
§7.3.5 is _Literal expression metamodel_. Corrected.)

The natural R1 rule — a `§`-service's `outputDecision`s are the members nothing outside the service
requires — makes **the uncalled set exactly the supply of `outputDecision`s.** **[M]** Executed both
directions on KIE: a service whose sole `outputDecision` is the uncalled root validates clean and
`evaluateDecisionService(model, ctx, "Article 5")` returns `{meets the charity test=true}`; the same
section with the uncalled root dropped fails the KIE **model** validator — _"Decision service
'Article 5' does not define any output decisions in top segment"_ — and throws at invocation.

> **Halved under review, and the archetype was self-refuting.** The measurement said 113 of 443
> substantive innermost sections (25.5%) consist entirely of module-uncalled decisions. **[M]** The
> review gets **117 of 462 (25.3%)** — Housing's 59 and GCO's 4/25 match exactly, the denominators do
> not, and "substantive" was never defined, so the figure is not reconstructible from the text. More
> importantly: **66 of the 117 (56%) contain no member this ruling keeps** — 60 entirely regulative
> (rule 3 routes them away), 6 entirely fixtures (rule 2 drops them). The named archetype,
> `§§ The mandatory outcome — Court MUST order possession` with sole member `ground 8 possession
order`, is **one of the 60**: it vanishes from the DMN model _under this ruling_, not under the
> alternative. The live hazard is at most **51** sections. And **[M]** 48 of the 117 have neither
> encapsulated nor input decisions, so §6.3.10's _"at least one of encapsulatedDecisions and
> inputDecisions SHALL be specified"_ makes them unemittable as services whatever we decide. The
> R1↔R6 link survives; its magnitude does not.

#### 2.5.6 The ruling

**Do not drop the uncalled population. Split it four ways and rule per part.**

1. **Uncalled DMN roots (141; 8.4%) — KEEP, and make them `outputDecision`s.** Each becomes a
   `<decision>` whose `GIVEN` parameters are `inputData`, unified across the module by §2.1's
   un-lifting **subject to the type-conflict side-condition in §2.1 and §2.5.3**: parameters that
   share a name and not a type are **not** merged, and the attempt is `D-SCOPE` at `Blocking`. Emit
   `D-PARAM-AS-INPUT` as §7 already provides. The justification is the **83 operative roots**, not
   the 141 (§2.5.7's inert correction), together with §6.2's already-ruled principle that refusing a
   `meets the charity test`-shaped decision ships a model missing the statute's constitutive test.
2. **Test fixtures and their transitive helper closure — DO NOT EMIT**, behind `--include-tests`
   defaulting to off, with **every dropped decision recorded** as a new `D-FIXTURE` (`Advisory`),
   named. The closure is **fixture-side** (a decision referenced only from fixtures is a fixture
   helper) and is computed **before** rule 3 — **[M]** stated that way it is 768 of 1675 (46%);
   re-seeded live-side _after_ rule 3 it would be 1249 of 1675 (74.6%), 675 of them non-fixtures,
   which is not what is ruled. Criterion in §2.5.7.
3. **Regulative bodies — out of scope for the DMN DRG**, per §12; they go to BPMN. Today
   `ground 8 possession order` is emitted as raw L4 inside a `<literalExpression>` and fails KIE with
   `Unknown variable 'IF'`. Emit `D-REGULATIVE` (`Lossy`; drops to `Advisory` once BPMN co-emission,
   PR #141, gives it an artifact to point at). **Scope correction:** 167 decisions have regulative
   bodies and rule 3 addresses the **137 uncalled** ones; **[M]** the other **30 are module-called**
   (`possession route`, `court duty for ground`, `rent spine`, `ror together`, …) and stay in the
   DRG, still emitting raw L4. Those are §2.4.2's and §6.3-1's, not R6's, and rule 3 must not be read
   as closing them.
4. **Inert prose / constant stubs — KEEP, with a new `D-INERT` (`Advisory`).** **The detector the
   measurement pass specified is scoped to the wrong shape and is hereby widened.** It tested for a
   body that is a `Lit` or a constant application, which finds 19. The corpus's dominant inert idiom
   is `"statutory text" ... TRUE`, which parses as **`And`**, so those decisions land in the _root_
   bucket instead: **[M]** 58 of the 141 kept roots (41%) have bodies containing no reference at all,
   50 of them directive-referenced. **[E]** In the exported corpus this is directly visible — 12
   decisions in 5 of the 51 exported modules carry the literal body `true and true`, among them
   `definition — rent means rent lawfully due from the tenant`,
   `rule — universal credit housing amount not yet received is ignored`, and four
   `former para N — … (REPEALED)` carriers:

   ```sh
   # over the 51 exported corpus models, counting decisions whose whole literal body is a tautology
   # 12 decisions in 5 modules: regcf, housing-act-ground-7, -ground-8, -part-4-repealed,
   #                            -part-5-interpretation
   ```

   `D-INERT`'s predicate is therefore **"the body forces no reference and no input"**, not "the body
   is a literal", and its population is ≥58, not 19. Consequently §2.5.2's decisive sentence —
   _"dropping deletes 129 tested entry points to delete 12 prose carriers"_ — is wrong on both terms;
   the true split of the 141 is about **83 operative / 58 prose**, and the two sets overlap.

5. **`itemDefinition` support: schedule, do not gate.** §4.1 / Phase 3, and a fidelity/UX feature.
   Selling it as R6's answer would launder a documentation improvement as a soundness fix.

#### 2.5.7 The fixture criterion, stated implementably

**`FIXTURE(d)` iff** (a) no reference to `d` from any decision body or non-`Decide` top-level
declaration in the scope unit; **and** (b) `d` has at least one directive reference; **and** (c)
every directive reference to `d` is in _argument_ position, never the applied head; **and** (d)
**no caller in any module that imports `d`'s module**. Closed transitively, fixture-side: a decision
referenced only from fixtures is a fixture helper.

Four corrections to the measured predicate `(not called) and (not d['params']) and da[d] and not
dh[d]`, all of which the corpora exercise:

- **Delete the `not params` conjunct.** **[M]** `arity` there is the _head_ arity, not the `GIVEN`
  count, and **54 decisions (3.2%)** have at least one `GIVEN` and an argument-free head (Charities
  10 / Housing 25 / GCO 19) — including GCO's five `@export`ed statutory conclusions. The conjunct
  simultaneously **keeps** real fixture builders: Reg CF's `a reporting status with` (arity 3) and
  `a transfer at` (arity 2), which is §2.2's "every arity ≥3 decision turned out to be a test-fixture
  builder" showing up as a false negative.
- **Add (b) explicitly.** Without it, (c) is vacuously true of a decision nobody references, and the
  rule drops the 12 unreferenced inert-prose carriers and any unreferenced genuine root.
- **Add (d) — and this is the correction that stops the rule deleting a statute.** **[E]**
  `jl4/experiments/housing-act-part-5-interpretation.l4:247` `` `relevant date` `` encodes Sch. 2
  para. 12(1)(a)/(b) and the para. 12(2) s.8(1)(b) dispensing override as a real `IfThenElse` over a
  `RelevantDateInputs` record. It is module-uncalled; it has five directive references; **every one
  is in argument position**, because the tests wrap the call —
  ``#ASSERT (Day (`relevant date` `inputs — 5F, served`)) EQUALS (Day `service date`)`` — so `Day`
  is the applied head. It satisfies (a)+(b)+(c) exactly. Its callers are statutory and cross-module:

  ```sh
  grep -rn '`relevant date` (' jl4/experiments/*.l4
  # ground-2ZA.l4:102  ground-2ZB.l4:86  ground-5F.l4:169
  #   `the relevant date` claim MEANS `relevant date` (claim's `relevant date inputs`)
  ```

  **[E]** And the "the other module's export is a separate artifact" defence fails on execution: in
  2ZA's own export the reference **dangles** —
  `<literalExpression>` ``<text>`relevant date` OF (claim's `relevant date inputs`)</text>`` with an
  `informationRequirement` list containing only `#input_claim`, because cross-module refs are filtered
  at `Lower.hs:1558`. Drop it from its home module and para. 12 exists in **no** artifact.
  `relevant date` is one of the **11** decisions the measurement pass counted as fixtures while they
  are called from another module.

- **Say which scope unit "called" means.** Module-local, for v1, consistent with R1's
  one-`<definitions>`-per-module — but conjunct (d) is what keeps that from being a licence to delete
  a callee. A cross-module export mode (DMN `import`) reopens it.

**Conjunct (d) as implemented (OPEN-5, landed 2026-07-31): a sibling-directory scan, failing
safe.** The CLI (`jl4/app/L4/Cli/Export.hs`, `siblingExternalRefs`) globs `*.l4` beside the
exported file, textually detects `IMPORT <this basename>`, and collects which of the module's
decide names occur anywhere in an importing sibling's text. Deliberately textual and conservative
in the KEEP direction — a name in a comment still counts, because a false keep costs one element
while a false drop deletes a statute. **What it can see:** importers in the same directory, which
is exactly where `relevant date`'s three callers sit. **What it cannot see:** importers anywhere
else. When the scan cannot run at all, the view is `Nothing` and the filter **fails safe**: a
decision satisfying (a)+(b)+(c) is then KEPT with a report-only `D-FIXTURE` advisory saying
conjunct (d) was not checked. The golden harness supplies `Just Set.empty` (a VFS fixture's
universe is closed, so "no importers" is a fact there, not a guess). The note names which view
ran.

**[M]** Two further facts constrain any cheaper implementation. A section-name heuristic is neither
sound nor complete: a strict `^Test` top-level-section rule covers 687 of 1675 decisions but misses
72 of the fixtures (all 43 GCO fixtures live outside a Tests section) and wrongly drops 7 genuine
roots. A body-shape test is not a substitute either: of the 565 directive-argument-only decisions,
**475 have body `AppNamed` and 90 have body `App`**, so "all fixtures are record constructions" is
false. The call-graph criterion is the only one exact on these corpora.

#### 2.5.8 The case against this ruling, honestly

**Rule 2 makes the exported model depend on a heuristic about authorial intent, and it is the kind of
clever filter this spec has twice been burned by.** Its precision is 100% _on these four corpora_,
where every fixture happens to be reachable only from directive arguments and every entry point
happens to be tested — **nothing in L4 enforces either**, and §2.5.7 had to patch it four times
against shapes the corpora do contain, one of which (`relevant date`) was a statute. It makes
emission depend on `#ASSERT` placement, so **adding a test can change the exported model**. And it
inverts §2.1's polarity on directives in the same document.

**What would overturn it.** A parameterised fixture builder that is also called from a decision body;
or a genuine statutory entry point with no directive reference and no callers that is not inert
prose. The second is one commit away in any corpus whose author has not yet written the tests.
Either forces `--include-tests` to default **on** and demotes the filter to a lint.

**And the principled replacement already exists in the language.** **[E]** `@export` is a real
decorator (`ResolveAnnotation.hs:766`, `L4/Export.hs:111`) and GCO uses it on exactly the shape this
ruling calls a DMN root — but `grep -c '@export'` gives **Reg CF 0, Charities 0, Housing 2, GCO 19**,
so an `@export`-gated rule would emit an **empty** model for three of the four corpora and cannot be
the v1 criterion. **[U]** Whether GCO's 19 `@export`s coincide with its 19 measured DMN roots was not
checked and is the cheapest decisive experiment available; if they do, the migration is: annotate,
then retire the heuristic for annotated modules and keep it as the fallback for the rest.

#### 2.5.9 What R6 does **not** decide

- **It does not discharge R2's residual risk (3).** That is R4's, and §4.2.1-6 states what R4 leaves
  open (R8).
- **`itemDefinition`.** Ruled out of R6 deliberately (rule 5); §4.1 / Phase 3.
- **The emitted shape for Camunda.** Every service-level result in §2.5.5 is **KIE-only**. **R7 has
  since ruled that a `decisionService` is emitted in both flavors but is _invocable_ only in the
  `kie` flavor** (§13). Rule 1's `outputDecision` link is therefore **flavor-independent as
  structure** — a bare service is inert-but-safe on Camunda 8 — but the §2.3 payoff that motivates
  it is `kie`-only, so on the default flavor rule 1 rests solely on the tested-entry-point evidence.
  That is sufficient, and it is a different argument; §14 records it.
- **Whether a decision called only from another module is "uncalled".** §2.5.7(d) rules it is not.
- **Where the population filter runs.** Same question as R5's, and **§6.4.4 answers it the other
  way for a reason**: R6's filter is an _emission_ decision and belongs in `Lower`; R5's acyclicity
  check is an _artifact_ property and belongs on the finished `Drg`. They compose by construction —
  `checkDrg` runs over whatever `Lower` emits (§6.4.7).

#### 2.5.10 What review changed

Thirteen defects. Four changed the ruling and are repaired in place: **rule 1 was type-blind**, and
un-lifting two same-named parameters of different types is a silent `null` in both target engines —
now prohibited, with `D-SCOPE` raised to `Blocking` (§2.5.3); **the fixture criterion dropped a
statute**, `relevant date`, so conjunct (d) is added (§2.5.7); **the R1 argument overcounted by ~2×**
and its named archetype is removed by the ruling's own rule 3 (§2.5.5); and **the inert detector
missed the corpus's dominant idiom**, so `D-INERT` is re-scoped from 19 decisions to ≥58 (§2.5.6-4).
Nine did not change it and are corrected in place: `reach > 0` is 68 not 59 and no root is a
possession order; Housing's regulative refusals are 45 not 69; rule 2's benefit is 10 errors not 12;
the closure is fixture-side and pre-rule-3; three arithmetic slips (54 not 46, 475 not 473, 71 not
70); rule 3's scope excludes 30 module-called regulatives; and the amended criterion's own partition
is 576 fixtures / 17 inert rather than 574 / 19.

**One review claim is recorded as scoped rather than accepted.** The review's `[U]` on the identity of
the 11 cross-module "fixtures" is now closed for the one that matters — **[E]** `relevant date` is one
of them, and it is the counterexample — but the other ten are still unnamed, and §2.5.7(d) is written
to be safe without knowing them.

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

> **NARROWED 2026-07-29, when this landed: enum in, boolean out.** The sentence above names "a
> boolean or enum-typed" output as the case where the domain is knowable, and for a boolean that is
> true and useless. For `boolean` the domain **is** the `typeRef`, and §8.2.4 assesses completeness
> "regardless of how the expected input values are modeled", so restating `true,false` adds no
> information — while adding a validation surface, because §8.2.7's "input entries in a unary test
> SHOULD be … a subset of the input values" has an output-side twin that every **computed** boolean
> output entry would then violate (`D-COMPUTEDOUTPUT` fires twice on `reg-cf` alone). An enum is the
> case where the domain is genuinely unrecoverable from `typeRef="string"`, which is §3.1's whole
> complaint. So `ocValues` is set for an enum-typed output only, and only when the type that won was
> the **declared** one from `GIVETH`: a type recovered from the cells says what this table happens
> to mention, which is exactly the domain we must not assert.

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

> **LANDED 2026-07-29 (Phase 3), both channels, on `legalese/l4-ide` branch
> `mengwong/dmn-itemdefs`.** `Drg` carries `drgItemDefs`; one `itemDefinition` is minted per
> module-local record and `IS ONE OF`, in source order, referenced or not — reachability-gating
> would make the type-level output depend on which decisions happened to survive lowering, and an
> unreferenced definition is inert. **Measured:** `reg-cf.dmn` gains one `itemDefinition`
> (`Investor_Class`), `input_class`'s `typeRef` goes `string` → `Investor_Class`, and the
> `is accredited investor` column gains `<inputValues>`; `regcf-corpus.dmn` gains 11, and 62
> `typeRef="Any"` plus 11 `typeRef="string"` become named. **The named-`typeRef` risk §4.2 could not
> pre-decide is measured clean on both engines**: `etc/kie-dmn-check` and `etc/camunda-dmn-check`
> both stay at **25/25 values as expected, 0 errors**, so the primary arm ships and the
> `keep typeRef="string"` fallback is not needed. `etc/kie-dmn-check`'s Xerces leg reports
> `XSD valid` on all three goldens, which is §4.3's gate rather than `etc/validate-dmn.mjs`.

An enum with **non-nullary** constructors is a tagged union. FEEL has no sum type. **Ruled
2026-07-27 — see §4.2.1:** the refusal is narrower than "emit `Any` plus a `Blocking` note", it lives
on the _reading decision_ rather than on the itemDefinition, and it deliberately does **not** fire on
the shape the corpus actually contains and both engines actually get right.

#### 4.2.1 Tagged unions — R4, ruled 2026-07-27

Evidence tags are §0's.

**1. The measurement, and the leaning's premise is false.**

**[E]** Type census over the same 62 files:

```sh
xargs grep -h '^DECLARE.*IS ONE OF' < corpus62.txt | wc -l          # 43
# of which, blocks containing a HAS:
#   housing-act-ground-1A.l4:58   Disposal      (2 cons, 1 payload)
#   housing-act-ground-1B.l4:59   Disposal      (3 cons, 1 payload)
#   housing-act-ground-2ZD.l4:42  EndingManner  (3 cons, 1 payload)
```

| corpus    | record  | enum, nullary ≥2 cons | enum, 1 nullary con | **union, payload-carrying** |
| --------- | ------- | --------------------- | ------------------- | --------------------------- |
| Reg CF    | 8       | 3                     | 0                   | **0**                       |
| Charities | 56      | 14                    | 0                   | **0**                       |
| Housing   | 55      | 21                    | 2                   | **3**                       |
| **total** | **119** | **38**                | **2**               | **3**                       |

Really **two** modelling ideas: `Disposal` in 1A and 1B is the same type differing by one nullary arm.
**[M]**, reproduced exactly by the adversarial review: **41 of 1546 decisions (2.7%)** touch a payload
union, all in Housing (5.2% of Housing), concentrated in three files. **6** have the union directly
in a `GIVEN`/`GIVETH`; **23** reach it only through a record field; **12** only through a body
reference. By what they do: **6** `CONSIDER` it (4 with a payload-binding arm), **7** construct a
payload constructor with `AppNamed`, **15** pass it on, **13** merely thread the record.

> **The leaning's stated reason was wrong; recorded rather than quietly dropped.** §11-R4 read
> "leaning refusal for v1; the corpora do not need it." True for Reg CF and Charities. **False for
> Housing**, where three grounds model a statutory alternation as typed data deliberately — **[E]** > `housing-act-ground-1A.l4:51-57` says so: _"as TYPED DATA (not reflection) … Whether a granted
> lease counts as a 'long lease' … is a STRUCTURAL PROPERTY of the intended instrument's data."_ The
> conclusion survives in narrowed form; its premise does not.

Two ratios to keep. **Enum-like and payload-carrying are different problems in a 9:1 ratio** — §4.2's
`allowedValues`/`inputValues` work is load-bearing for **[M]** 368 decisions and R4 concerns 41 — so
**R4 must not be allowed to hold up §4.2**. And **[M]** 163 `CONTRACT`/`DEONTIC` decisions are refused
by `isRegulative` for reasons that predate R4.

**2. The baseline: what today's exporter actually does, executed rather than read.**

The measurement pass derived, from a chain of eight code reads, that a `CONSIDER` over a tagged union
matching its nullary arms with an `OTHERWISE` emits a note-free `string` column that silently routes
the payload constructor to the default — and called that _"the finding that makes this ruling
urgent"_, tagging the corpus claim `[U]`. **Both halves are wrong, and in opposite directions.**

**[E]** The shape _is_ in the corpus, twice, in one file:

```sh
l4 export jl4/experiments/housing-act-ground-1B.l4 --to dmn --fidelity-report -o 1B.dmn
#   → 29 blocking, 3 lossy;  3 decision tables
#   TABLE: minimum stated period in years
#   TABLE: is a sale of a freehold or leasehold interest              <- over Disposal
#   TABLE: is a grant of an assured tenancy to another person         <- over Disposal
#   codes: 29 [D-LITERALEXPR], 3 [D-SCOPE]  — neither table carries any note
```

**[E]** And the emitted tables are **correct**. Extracted standalone with their three `disposal`
`inputData` and driven through KIE 8.44.0.Final:

```
BUILD messages: 0 ; MODEL hasErrors=false ; RUNTIME messages: 0
disposal = "….sell a freehold or leasehold interest"        → sale=true   assured=false
disposal = "….grant an assured tenancy to another person"   → sale=false  assured=true
disposal = "….grant a long lease"                           → sale=false  assured=false
```

which is exactly what the L4 says (`WHEN sell THEN TRUE OTHERWISE FALSE`). The `defaultOutputEntry`
reproduces `OTHERWISE` faithfully; there is no silent misreading here, and **these are 2 of the 12
decision tables the whole 51-file export yields.**

**The genuinely unsound shape is a different one, and it is not about tagged unions at all.** **[E]**
A fresh probe, two decisions, one over a payload union and one over a plain nullary enum, each
non-exhaustive and each **without** `OTHERWISE`:

```l4
DECLARE Disposal IS ONE OF  sell / lease HAS years IS A NUMBER / assign
`is sell no otherwise` d MEANS CONSIDER d WHEN sell THEN TRUE WHEN assign THEN FALSE
DECLARE Colour IS ONE OF  red / green / blue
`is red no otherwise`  c MEANS CONSIDER c WHEN red  THEN TRUE WHEN green  THEN FALSE
```

```
l4 check  →  WARNING ×2: "The following branches still need to be considered: WHEN lease" / "WHEN blue"
l4 export --fidelity-report  →  "fidelity report — DMN 1.3 (XML) / (nothing lost)"
             both emit a 2-rule UNIQUE table with NO defaultOutputEntry
KIE 8.44   →  is sell no otherwise = null [SUCCEEDED]   is red no otherwise = null [SUCCEEDED]
              (WARN "No rule matched … Setting result to null", status still SUCCEEDED)
```

Three things follow, and they are the whole of R4's shape. (i) The hazard is **exhaustiveness**, and
it is **byte-identical for a plain nullary enum** — so it is **R2's L1**, not R4's. (ii) The
checker already knows: it warns on both, and the exporter reports `(nothing lost)` anyway, which is
§2.4.5's oracle-plumbing gap showing up in the artifact rather than in the analysis. (iii) The
measurement pass's own corollary — _"when the binding arm is `FALSE` it is dropped and `rowsElided`
fires"_ — is false; **[D]** `rowsElided` returns `False` whenever an `OTHERWISE` exists
(`Lower.hs:1802-1806`).

**3. The ruling.**

**R4-a — `D-SUMTYPE`, on the reading decision, at two severities.** A decision is **`Blocking`** if
it does any of:

1. **project a payload field** of a user-declared multi-constructor payload-carrying `IS ONE OF`;
2. **construct a payload-carrying constructor** of one;
3. `CONSIDER` one with a **payload-binding arm**;

or transitively calls a decision that is. A decision that `CONSIDER`s such a union over its **nullary
arms only** is **`Lossy`**, naming the constructors that have no cell — it is not refused, because
**[E]** the emitted table is exact when an `OTHERWISE` covers them and, when it does not, the defect
is L1's and identical for a plain enum. A decision that merely **threads** a record containing such a
field without reading it is also `Lossy`.

> ~~with the component typed `Any`.~~ **CORRECTED 2026-07-30.** That was written before Phase 3
> minted `itemDefinition`s, and Phase 3 falsified it without moving the sentence.
> **[E]** `jl4/examples/dmn/expected/sumtype.dmn` emits
> `<itemComponent id="itemdef_claim_c4" name="the_disposal"><typeRef>Disposal</typeRef>`, and
> `itemdef_disposal` is `<typeRef>string</typeRef>` + `<allowedValues>"sell","lease","assign"</allowedValues>`.
> The component carries the **minted name**, not `Any`, and the `Lossy` note now reads that name off
> the same `classifyType` call the emitter uses rather than asserting a constant. What is lost is
> therefore **not the component's declared type** — that survives — but the **tag/payload
> distinction**: every constructor is spelled as a bare string, so a constructor carrying a payload
> and the same constructor without one are one FEEL value, and the payload has no image in the
> component at all.

Three reasons the refusal cannot live on the itemDefinition, all measured:

- **A type-level note routes nothing.** §2.4.2 already ruled severity keys off the call site, not the
  node kind; the same logic applies.
- **Visibility.** **[M]** Only **6 of the 41** union-touching decisions have the type at a
  `GIVEN`/`GIVETH` boundary; 23 reach it through a record field and 12 only through a body reference,
  and a `WHERE`-local or a callee's return type would be invisible too. A type-boundary rule misses
  85% of the population.
- **Propagation is forced by emission.** A refused callee is not a node, so a caller's reference to
  it dangles — `Blocking` propagates along `calls`, exactly as partiality does under §2.4.2.

**Cost, at the precision it was measured.** **[M]** Directly in scope: 13 decisions — the 6
`CONSIDER`s and the 7 `AppNamed` payload constructions. **[E]** Exporting all three union files and
asking which of their union-reading decisions emit a `<decisionTable>` versus a `Blocking`
`D-LITERALEXPR`:

```
housing-act-ground-1A.dmn   tables: []       — is a qualifying long lease, is a sale …, and all
                                               four `disposal — …` constructions carry a note
housing-act-ground-1B.dmn   tables: [minimum stated period in years,
                                     is a sale of a freehold or leasehold interest,
                                     is a grant of an assured tenancy to another person]
                                             — is a qualifying long lease carries a note
housing-act-ground-2ZD.dmn  tables: []
```

So **11 of the 13 are already `Blocking` today**, and the **2 that are not are precisely 1B's two
working tables**. Under R4-a as narrowed those 2 are `Lossy`, not refused, so
**R4-a's incremental refusal count on these corpora is 0.** The earlier draft ruled them `Blocking`
and reported an incremental cost of 6; the true figure under that draft was 2, and the 2 were the
only union decisions that worked. **[M]** The transitive closure of a refusal over the 41 is **47
decisions confined to `housing-act-ground-{1A,1B,2ZD}.l4`**, including all three roll-ups, and **[M]**
no file imports the three grounds — so the closure does not escape, which is what makes the narrowing
affordable rather than merely nicer.

**R4-b — the encoding is specified, and gated.** When Phase 4 lands **L11** and the tag-guard
invariant, the `Blocking` cases above may emit as `Lossy` under: an itemDefinition that is a
**context** with one `tag` component (`typeRef="string"`, `<allowedValues>` listing every constructor
name), plus the **canonical union** of every constructor's payload components, nulled where absent,
key-qualified per constructor on name collision; every scrutinising table carries the `tag` column
with `<inputValues>`; and **every payload read is tag-guarded within the same decision**.

Four constraints on that encoding, all executed, three of which §4.2's sketch does not state:

- **[M]** `{tag: "A"} = {tag: "A", payload: null}` → **false** on KIE and feelin. "Optional payload
  fields" is unsound for equality; the emitter must be canonical. With that, equality is exact —
  `{tag:"Paid",amount:40} = {tag:"Owed",amount:40}` → **false**, matching L4.
- **[D]** Two constructors of one L4 union may declare the **same** field name; L4 then makes two
  distinct selectors and the typechecker refuses the projection outright. A flattened context has one
  key, so the encoding needs per-constructor key qualification.
- **[E]** **A missing payload _component_ is silent even when the tag is guarded.** On the
  measurement pass's own `tagged.dmn`, KIE 8.44, tag inside `inputValues`, read fully tag-guarded:

  ```
  disposal={tag:"grant a long lease"; term_certain_in_years:25}   # boolean component absent
    → is a qualifying long lease = null  [SUCCEEDED]   (WARN "No rule matched … no default values")
  ```

  R4-b's invariant is _satisfied_ and the answer is still `null`. The encoding therefore owes a
  further obligation the earlier draft did not state: **`allowedValues` on every payload component,
  or a total row cover / `defaultOutputEntry`.**

- **[M]** The four `AppNamed` defects `Lower.hs:770-796` records all hold, and defect 3 is worse than
  documented: KIE rejects `{for: 1}` at compile time yet reports the decision **SUCCEEDED with `{}`**,
  and quoting the key does not rescue it. `feelin` accepts the same expression, so the reserved-word
  key check is a **portability** requirement that must hold for the strictest engine.

**R4-c — fix the constant-ref defect in Phase 3, independently.** **[D]** `constructors`
(`Lower.hs:1515`) has no nullary filter and `isConstructorKind` (`Lower.hs:506-510`) accepts any name
the checker stamped `Constructor`, so a nullary arm of a _payload-carrying_ union lowers to a bare
`VStr` cell against a variable typed `Any`. Under R4-a's `Lossy` arm that is the right cell and needs
only the domain (`allowedValues`/`inputValues`); under R4-b it must become `disposal.tag = "…"`.
~~**[E]** Note what the cell actually contains today, which the ruling's R3 dependency
mis-routed:~~ **CORRECTED 2026-07-29 — the exhibit was stale.** The draft showed the emitted cell as
**section-qualified**:

```xml
<text>"Housing Act 1988 — Schedule 2 — Part I — Ground 1B (Renters' Rights Act 2025).Domain model.sell a freehold or leasehold interest"</text>
```

On this tree it is **not**. **[D]** `nameOf = unqualifiedNameToText . getOriginal`
(`Lower.hs:590-591`), a repair that landed with the naming work, so **[E]** `1B.dmn` emits
`<text>"sell a freehold or leasehold interest"</text>` and `reg-cf.dmn` emits
`<text>"accredited"</text>`. The residue of the observation still holds and is what Phase 3
implements: the constructor name is a **string literal** — the tag _value_ — so `feelIdentText` must
**not** touch it, and `allowedValues`/`inputValues` reproduce `nameOf` verbatim. With the
qualification gone there is no §5.2 pipeline coupling left to worry about.

**4. Interaction with R2 / L11.**

R2 records: _"L11 is not covered by §4.2's tagged-union `Blocking`, because R4 is still open."_
Replace that sentence with:

> **Discharged in part, 2026-07-27.** For **user-declared** unions R4-a's first reading form _is_
> L11's subject: a payload-field projection is `Blocking` at the decision, which drives L11's
> single-decision traffic to zero by construction. What survives is (i) the **builtin** open sums,
> `MAYBE` and `EITHER`, which R4 deliberately does not rule — see **R8**; and (ii) R4-b's
> cross-decision guard/use split, where the guard lives in the caller and the read in the callee.
> L11 must still stand on its own inside `LOCALLY-TOTAL`, because §4.2's note is type-scoped where
> L11 is decision-scoped, only 6 of the 41 union-touching decisions have the type at a boundary at
> all, and inexpressibility and unsoundness are different severities.

**[M]** L11 still ships with **zero corpus exercise on its accepting branch**: a scan for `Proj` sites
whose field is declared by a constructor of a multi-constructor enum finds **0 hits across all 62
files**, with the detector positive-controlled on §2.4.1's synthetic. The two
`` claim's `term certain in years` `` hits are record projections, which are safe. §2.4.1 already
flags this class of gap; R4 does not close it, and Phase 4 owes a synthetic test.

**5. The case against this ruling.**

_Refusal is the more dangerous choice, because the encoding is measurably sound and refusal is
measurably expensive._ **[M]** The tag column with `inputValues` turns DMN's unmatched-constructor
case into a loud engine-reported `FAILED`, better than the nullary-enum path, and the encoding stays
inside S-FEEL so `UNIQUE`, gap and overlap analysis keep working — which is §3.1's whole thesis.
Refusal forfeits it on exactly the decisions where a statute's alternation lives, and "v1 refusal" is
how Housing's typed-alternation house style becomes non-exportable by accident.

Two things answer it. **[E]** The encoding has a silent-`null` hole its own proposer did not find
(the missing-component probe above), so it is not ready. And the narrowing already concedes the rest:
under R4-a as ruled the corpus loses **nothing it currently gets right** — the two working tables stay,
at `Lossy` — and what is refused is exactly the set that is already refused for other reasons.

**What would overturn it, checkably.** (i) Discharge the missing-component obligation (§4.2.1-3) and
verify the encoding on Camunda 8; then R4-b ships as `Lossy` and `Blocking` survives only for
cross-constructor field collision and the BKM-boundary split. (ii) Land PR #45 and L11 at or before
Phase 3, which removes the gate independently. **Note what does _not_ overturn it:** the earlier draft
rested this ruling on §10's phase order and was defeated by its own §4.2.1-7 ("R4 fixes the
precondition, not the slot"). The ruling now rests on the **narrowing** — R4-a refuses only what is
already refused, so there is nothing to trade away — and re-sequencing therefore changes when R4-b
ships, not whether R4-a was right.

**6. R8, opened here.**

**Builtin `MAYBE` and `EITHER` are payload-carrying unions and are out of R4's scope.** **[M]**
`MAYBE` reaches 11 decisions, `EITHER` none. ~~Their tempting encoding — `JUST x ↦ x`, `NOTHING ↦
null` — is exactly the coercion §2.4 refuses~~ — **that characterisation is wrong, and R8 is now
ANSWERED (2026-07-29); see §11-R8 for the ruling and §11's R8 entry for the census.** The correction,
because it is the load-bearing half: §2.4's refused arrow has the **L4 error channel** as its domain
— it is about turning a "loud user exception" into "a wrong answer that nothing downstream catches",
and its whole clause list is derived from `UserEvalException`'s constructors. `NOTHING` is not a
raise; it is a value of a total function. §2.4.1 makes exactly that distinction load-bearing in the
opposite direction, in one sentence: `TO NUMBER`/`TO DATE`/`TO TIME` are "Also accepted, because they
are genuinely total: … (**they return `MAYBE`**)" — i.e. §2.4.1 treats _"the failure has been moved
out of the error channel and into the value channel"_ as the property that makes an operation safe to
un-lift. R8's encoding does not undo that move; it preserves it and asks only how the resulting value
is spelled in the target, which is a §4.2 question. What is left is a real **fidelity** residue, and
`Lossy` is its name: FEEL has one `null` and it spells both "the rule says there is none" and "the
engine could not compute it", where L4 keeps them apart. Refusing them silently would still have
refused 11 decisions on no analysis, which is why R8 waited for the census. **[E]** R8 is
narrower than it looks on the totality side: `MAYBE`'s payload is **not projectable** — `m's val` on
`m IS A MAYBE NUMBER` is a type error — so L11 has no `MAYBE` exposure and `MAYBE` reaches
`LOCALLY-TOTAL` only through `CONSIDER`, i.e. through **L1**. R8 is a §4.2 type-emission question for
Phase 3, and **does not block #923** (§0).

**7. What R4 does not decide.**

- **Which phase R4-b ships in.** R4 fixes the precondition, not the slot.
- **Single-constructor payload types.** Zero in these corpora; §4.1 arguably covers them as records.
  Not ruled.
- **Value equality.** As §2.4.4 says of `DMN-SAFE`, this is about expressibility and definedness.
- **Engine flavor.** **Flavor-independent as ruled**: R4-a emits nothing engine-specific, and the
  `Lossy` arm's tables are ordinary S-FEEL. R4-b **is** flavor-sensitive and all its engine evidence
  is KIE 8.44 plus `feelin`; **[U]** Camunda 8 untested. §14 records it.

**8. Obligations on later phases.**

- **Phase 3:** R4-c. A golden pinning the `Lossy` nullary-only arm — a `CONSIDER` over a
  payload-carrying union with an `OTHERWISE` — proving it still emits its (correct) table and now
  carries `D-SUMTYPE` at `Lossy` plus the domain.
  **DISCHARGED 2026-07-29** by `jl4/examples/dmn/sumtype.l4` and its four goldens under
  `jl4/examples/dmn/expected/`. R4-c itself needed **no change to `isConstantRef`**: under the
  enriched classifier the variable becomes `typeRef="Disposal"` against an itemDefinition carrying
  `allowedValues` over **all** constructors, and the column gains matching `inputValues` — the cell
  was already the right string, and what was missing was the domain and the type.
- **Propagation along `calls` is NOT built, and the narrowing is recorded here rather than left
  silent (2026-07-29).** §4.2.1-3's rationale is that "a refused callee is not a node, so a caller's
  reference to it dangles". **[D]** In this exporter a `Blocking` note does **not** remove the node:
  `literalFallback` still emits a `<decision>` carrying a boxed literal expression, so there is
  nothing to dangle. §10 already assigns the closure **measurement** to Phase 4, which is also where
  refusal-to-emit arrives; propagation belongs with it.
- **One cost the corpus-derived claim does not cover, found by building it.** §4.2.1-2 argues R4-a
  "refuses only what is already refused". That is true of the three corpus files and **false of a
  synthetic shape the test suite contained**: `elidedArmWithOtherwise` (`jl4/tests/DmnExport.hs`) is
  a `CONSIDER` whose `WHEN other description THEN FALSE` arm binds a payload, and whose emitted
  table — one rule for `education`, everything else to the `defaultOutputEntry` — was **correct**.
  R4-a's third reading form refuses it. Two consequences: the ruling shipped as written, and
  `RowsElided` is now **unreachable** for a multi-constructor payload union, because `considerRows`
  elides an arm only when it binds _and_ still supplies a disjointness key, which only a constructor
  pattern does (**[E]** a `PatVar` catch-all gives "is not a guarded chain" instead).
- **Phase 4:** measure the transitive closure of R4-a's `Blocking` arm over the 41, alongside
  §2.4.3's structural re-census; report the closure, not the direct count. And a synthetic test for
  L11's accepting branch, which no corpus exercises.
  **MEASURED 2026-07-31 (Phase 4's build), over the emitted post-filter DRGs** — closure computed
  on `requiredDecision` edges, which is exactly "whose answer flows through the poisoned node":
  **5 `D-SUMTYPE`-`Blocking` decisions survive the population filter** (all Housing:
  `ground-1A` ×2, `ground-1B` ×2, `ground-2ZD` ×1 — the other ~36 of the 41 were fixtures or are
  in dropped scaffolding), **4 of the 5 have at least one caller, and the transitive caller
  closure is 5 further decisions**. The closure is small but **non-empty**, so the §4.2.1-3
  narrowing ("nothing to dangle") remains true — the node still exists and emits a fallback — but
  five downstream decisions consume a value KIE cannot compute, and propagation of the `Blocking`
  along `calls` has a real population the day node kinds change (Phase 5). L11's synthetic
  accepting **and** rejecting fixtures shipped in `jl4/tests/DmnExport.hs` the same day.
- **Diagnosis order:** `D-SUMTYPE` must be reported **before** `D-LITERALEXPR`. **[D]** Today the
  payload-binding `CONSIDER`s fail earlier in `GuardedRows` and are reported _"is not a guarded
  chain"_, which misdiagnoses a FEEL type-system limit as a table-shape problem.

**9. What review changed.**

Nine defects; four changed the ruling and are repaired in place. **The baseline section was wrong in
both directions** — the shape it called unreachable is in the corpus twice, and the emitted tables it
called silently wrong are **correct in KIE**, so §4.2.1-2 is rewritten from execution (D1, D3). **The
cost figure was wrong by 3×, in the direction that mattered**: incremental refusals were 2, not 6, and
the 2 were the only working union decisions — which is what forced the narrowing from "refuse all
reading decisions" to the two-severity rule (D2). **R4-b's own encoding had an unfound silent-`null`
hole** — a missing payload component under a satisfied tag guard (D4). **And §4.2.1-5's only stated
load was defeated by §4.2.1-7 in the same draft** ("R4 fixes the precondition, not the slot"), so the
sequencing argument is no longer load-bearing and the ruling now rests on the narrowing (D9). Five
did not change it and are corrected: Housing's regulative refusals are 45 not 69 (D5); R4-a and R4-c
disagreed about nullary-arm construction, now reconciled by the `Lossy` arm (D6); the emitted
constructor cell is section-qualified and its coupling is to §5.2 not R3 (D7); the closure is 47 and
confined to three files (D8); and `Lower.hs:1816` not `:1811` for `isRegulative`.

**One reviewer framing is recorded rather than adopted.** The review proposed leaving nullary-only
`CONSIDER`s entirely to L1 with no note. R4 emits `D-SUMTYPE` at `Lossy` on them instead, because the
_domain_ is genuinely lost — **[E]** the payload constructor has no cell and no `allowedValues`, so a
gap analyser cannot see that it is missing — and §3.3.1's whole argument is that a declared
incompleteness is information the artifact should carry.

### 4.3 Placement, and the validator trap

`itemDefinition` elements are **the first children of `<definitions>`** — before every
`<inputData>` and `<decision>`. `Emit.hs:118-131` currently builds
`map nodeXml drg.drgNodes <> [dmndiXml drg]`; item definitions must be **prepended**.

> **Do not trust `xmllint` as the gate.** libxml2 silently accepts `itemDefinition` placed
> _after_ `inputData`; Xerces rejects it with `cvc-complex-type.2.4.a`. A misordered emitter
> therefore passes CI. See §9.

> **LANDED 2026-07-29.** `definitionsXml` is now
> `map itemDefinitionXml drg.drgItemDefs <> map nodeXml drg.drgNodes <> [dmndiXml drg]`, and a unit
> test pins that the first `<itemDefinition` offset precedes the first `<inputData` one.
> **The gate that was actually run is `etc/kie-dmn-check/run.sh`**, whose `SchemaFactory` leg
> validates against the DMN 1.3 schema shipped inside the KIE jar: **[E]** `XSD valid` on
> `reg-cf.dmn`, `regcf-corpus.dmn` and `sumtype.dmn`. `etc/validate-dmn.mjs` is **not** the gate for
> this — its own header says it "does NOT check XSD sequence order" — though it was run too and
> reports `OK` on all three.

> **NEGATIVE CONTROL LANDED 2026-07-29, and it corrects the paragraph above it.** §9's
> `M1-itemdef-after-inputdata.dmn` is committed, together with the positive control it is a
> controlled experiment against, at `jl4/tests-cli/fixtures/dmn-xsd-order/`:
> `M1-itemdef-before-inputdata.dmn`, `M1-itemdef-after-inputdata.dmn` and their shared
> `M1-itemdef.cases.json`. The two files hold **the same lines**, differing only in where the
> `<itemDefinition>` block sits, and `jl4/tests-cli/Main.hs` asserts that (`sort . lines` equality)
> so a red negative always isolates placement as the cause. They are hand-written and are **not**
> regenerated: the emitter cannot produce the negative case, which is the property under test.
>
> Driven from the "XSD sequence-order gate" describe in `jl4/tests-cli/Main.hs` (opt-in behind
> `L4_DMN_ENGINE_CHECK=1`, same skip contract as the other engine legs) and from a dedicated
> `dmn-engines` CI step, which asserts the harness exits **non-zero** on the negative and greps
> for both the VERDICT banner and `cvc-complex-type.2.4.a` — the banner because a harness that died
> before running also exits non-zero.
>
> **[E] Measured, and it falsifies "fails in Drools/Kogito and every other JAXP-based engine",
> which is why that clause has been struck from the paragraph above.** On the misordered file:
>
> | checker                                | verdict                                                                                        |
> | -------------------------------------- | ---------------------------------------------------------------------------------------------- |
> | Xerces via `etc/kie-dmn-check`         | `XSD INVALID`, `cvc-complex-type.2.4.a`; KIE validator `FAILED_XML_VALIDATION`; harness exit 1 |
> | Drools/KIE 8.44 `KieBuilder` + runtime | **clean** — builds, loads, and answers both cases correctly                                    |
> | Camunda 8.7.6 (zeebe-dmn)              | `PARSE INVALID`, `0 parsed, 1 error(s)` — rejected outright                                    |
> | `etc/validate-dmn.mjs` (dmn-moddle)    | `OK` — misses it, exactly as its own header warns                                              |
>
> Both engines accept the positive control (`0 error(s), 0 warning(s), 2/2 value(s) as expected`;
> `1 parsed, 0 error(s), 2/2 value(s) as expected`). So the correct statement of the risk is that
> **the schema check is the only thing between a misordered emitter and a shipped artifact on
> Drools** — its runtime tolerance is what makes an XSD gate load-bearing rather than redundant —
> while on Camunda the file does not load at all.

**Scalars get no itemDefinition.** Keep `typeRef="number"` for `GIVEN income IS A NUMBER`; an
alias adds no information and degrades for any consumer that does not resolve typeRefs. Mint one
for a scalar only when L4 supplies a domain.

The objection here is to an alias that **adds nothing**, and it does not reach the domain-free
`<τ>_optional` aliases §11-R8-a mints at `MAYBE` sites: those exist to _subtract_ a range that
would otherwise be re-asserted through the `typeRef` hop, which is a difference in the artifact and
not only in the reader's convenience. A `MAYBE NUMBER` still gets no alias, and this paragraph is
why — a builtin asserts no range, so there is nothing to subtract.

### 4.4 Hydration: a record with computed fields is a boxed context

**LANDED 2026-07-31.** Everything in this section is true of the tree.

An L4 record may carry a **computed field** — `` `doubled amount` IS A NUMBER MEANS `amount` TIMES 2 ``
inside a `DECLARE`. DMN has no such thing: `tItemDefinition` has no derived flag, and an L4 call is
not a FEEL invocation (§4.2.1-8's reason — a `DECIDE` becomes a 0-ary decision variable, so `f(x)`
names nothing an engine can resolve). The lowering is therefore a **hydrator**: the record instance
is re-emitted as a boxed `<context>` whose stored components are copied from the source and whose
derived components are computed **from the entries declared before them**, and every downstream read
becomes plain path access on the hydrated value.

**[E] The idiom is measured, not assumed.** `jl4/tests-cli/fixtures/dmn-hydration-probe/` is a
hand-written model in exactly this shape — later context entries referencing earlier siblings by
bare name, no final result entry, read downstream by path access — and it answers **6/6 on KIE
8.44.0.Final with zero warnings, and 6/6 on zeebe-dmn 8.7.6**, measured 2026-07-31. The boundary
from PR #176 still holds and is why this works at all: a decision **table** inside a context entry is
zeebe-unparseable; **literal-expression** entries are fine, and that is all hydration needs.
`jl4/examples/dmn/hydration.l4` then carries the same measurement on **emitter-produced** XML —
33/33 on both engines — so a red run in one isolates the engine and a red run in the other isolates
the lowering.

#### 4.4.1 Which instances are hydrated

An instance is hydrated iff **all** of: it is a free term or a surviving decide whose type head is a
record; that record owns at least one computed field; and **some surviving decide contains a foldable
computed read of that instance**.

The third condition is a **use gate**, and it follows the `_optional` alias precedent verbatim: a
base `itemDefinition` is inert and is therefore minted ungated, but a hydrator is a `<decision>`, and
one with no dependents is noise in an artifact whose whole claim is that every line in it means
something. It costs the Reg CF corpus eight hydrators it would otherwise mint and never read; it
mints exactly one. There is no knot — the gate is a purely syntactic scan of decide bodies, computed
before the decisions are lowered.

**Only computed reads rewire.** A raw-field read stays on the source instance. Hydrated stored
entries are literal copies, so rewiring them would buy nothing and would churn every existing table.

#### 4.4.2 ★ Entry order is TOPOLOGICAL, and getting it wrong is silent

A boxed context's entries evaluate in order, and only **earlier** siblings are in scope.
`detectComputedFieldCycles` (`jl4-core/src/L4/Desugar.hs`) guarantees **acyclicity only** —
declaration order is not guaranteed topological. An entry that reads a later sibling resolves to
nothing and **FEEL answers `null`**: no error, no warning, a wrong number.

The fields are therefore emitted by a **depth-first walk in declaration order**: take the fields as
declared, and before emitting one, emit any sibling it reads that is not out yet. Dependencies come
first where there is a dependency; declaration order holds everywhere else.

> **CORRECTED 2026-07-31 in review.** The first implementation used
> `Data.Graph.stronglyConnComp`, and this paragraph asserted that "independent fields keep
> declaration order because the input list is in declaration order". `stronglyConnComp` gives no
> such guarantee for edge-free vertices, and the shipped artifact refuted the claim: Reg CF's
> `greater of annual income or net worth` and `lesser of …` are mutually independent and were
> declared in that order, and `regcf-corpus.dmn` emitted them **reversed** (`ce6` = lesser, `ce7` =
> greater). Harmless to evaluate — independent entries evaluate in any order — but false as a
> claim, and it is the claim `D-COMPUTEDFIELD` itself makes when it says the derived components are
> computed "from the components declared before them". Pinned by "keeps INDEPENDENT computed fields
> in declaration order" in `jl4/tests/DmnExport.hs`.

Termination does not depend on acyclicity: a field is marked emitted **before** its dependencies
are walked, so a cycle stops rather than loops. Acyclicity itself still comes from
`detectComputedFieldCycles`, which runs long before this.

`jl4/examples/ok/computed-fields.l4` **cannot catch the omission**, because its declaration order
already happens to be topological. `jl4/examples/dmn/hydration.l4` declares `band` **before** the
`total income` it reads, precisely so that it can, and its engine cases assert the hydrated records
in full rather than only the decisions downstream.

#### 4.4.3 Recognising a computed field after the desugaring

`L4.Desugar.desugarComputedFields` runs **before** typechecking and splits the `DECLARE`: stored
fields stay, and each computed field becomes a synthetic top-level
`GIVEN … _self IS A R / GIVETH τ / f _self MEANS …`. So the exporter never sees a computed field on a
`DECLARE` at all.

Recognition is by **provenance**, not reconstruction: `TypeCheck` stamps those decides
`ComputedSelector` rather than `Computable`, and `resolveTermFiltered` writes the kind onto every
**reference** occurrence as well as the definition — so no environment has to be threaded. The owning
record is the head **type** of the last `GIVEN` parameter (the parameter being spelled `_self`
corroborates but is not the key).

This is deliberately **not** the test in `jl4-core/src/L4/Export/Document.hs`, which recognises the
same thing by comparing a receiver's name to the string `"_self"`. A name test is what R8-f was.

Both spellings of a read fold, because both occur in real corpora: `x's f` (L4 house style) and
`f x` (what `jl4/examples/legal/regcf/regcf-wizard.l4` writes).

**A computed read whose receiver is not a nullary reference refuses gracefully, with no new code.**
`` `greater of …` (`investor profile from` facts) `` applies a computed selector to a record-valued
_expression_, which no hydrator names; it renders verbatim exactly as any unrenderable `App` does and
the existing `D-LITERALEXPR`/`D-NONFEEL*` machinery reports it. `regcf-wizard.l4` is left carrying
that untouched **on purpose**, so the path stays exercised by a real file.

#### 4.4.4 The DRG rewiring, and R11

Requirements are computed from `survivingRefs`, a **fold-aware** traversal that on a foldable
computed read records the instance and does **not** descend into the receiver or the selector,
because after the fold neither appears in the emitted FEEL. It is the same function §15.3's law-time
rewrite uses, and it subsumes the `exprFreeRefs` it replaced.

> **The fold is a PRUNE, not a whitelist — corrected 2026-07-31 in review, and the shape is
> load-bearing.** The first implementation walked the tree collecting names per node from a
> whitelist (`App` contributes its head, `Proj` contributes nothing, **everything else contributes
> nothing**). That silently dropped every name that is not an `App` head — an `AppNamed` head above
> all, but also `Regulative`, `Event` and `Record` — while `exprFreeRefs` had collected every `Ref`
> in the tree. Because `dcnRequirements` can only ever REMOVE edges relative to the source, the loss
> was invisible in every golden, and showed up only as a decision whose `<text>` named a decision
> its `informationRequirement`s did not: `` `sum of` WITH x IS `the base` y IS 7 `` renders verbatim
> and lost its edge to `decision_sum_of` — the exact inverse of the R11 property this function
> exists to establish. `survivingRefs` now replaces each folded read with a name-free placeholder
> and then collects exactly as `exprFreeRefs` did, so what is **not** folded is collected as before
> and the failure mode cannot recur. Pinned by "a NAMED-ARGUMENT call keeps its edge" in
> `jl4/tests/DmnExport.hs`.

**Consequence, and it is intended:** where every read of `x` in a decide is folded, the direct
`RequiredInput` edge **disappears** and the graph becomes `x → hydration_x → decide`. That is what
R11 demands — the emitted FEEL no longer names `x`, so the DRG must not claim it does. A decide that
reads **both** raw and computed fields keeps both edges, which is also correct. Free-term collection
is **not** filtered this way: `x` must still become an `inputData`, because the hydrator requires it.

Two further couplings are load-bearing and are silent if omitted:

- **`ComputedSelector` uniques join the `selectors` set.** Removing the synthetic decides from the
  decision list removes them from `decideByUnique`, and free-term collection excludes a reference only
  if it is a known decide, a constructor or a selector — so without this, a read of `doubled amount`
  would mint a **bogus `inputData` named after the field**: a supplied value where the model computes
  one.
- **`fieldScopes` learns the computed selectors**, inside the record's own `uniquifyIn` call. Without
  it a hydrated computed component would miss the field namespace and could collide with a stored
  field's path step in silence — §5.3.4's executed collision, reintroduced. Because one map then
  serves both the context entry names and the downstream path steps, the two agree **by
  construction**.

**A hydrator's own edges are computed the same way, and are NOT just its source instance.** ADDED
2026-07-31 in review, closing a defect that shipped:

`Desugar.rewriteFieldRefs` rewrites only the names that are the record's **own** fields; every other
name in a `MEANS` body resolves in module scope and is emitted into the context entry unchanged. So

```l4
DECLARE R HAS
    `a` IS A NUMBER
    `b` IS A NUMBER MEANS `a` TIMES `vat rate`
```

renders `a * vat_rate` inside `hydration_r`'s context. With the source instance as the hydrator's
only `informationRequirement`, `vat_rate` is not in the hydrator's evaluation scope — and this
change's own fixture measured both outcomes for exactly that shape: KIE 8.44 reports
`Required dependency 'r' not found` and **SKIP**s, zeebe-dmn 8.7.6 reads `null` and multiplies by it
(`jl4/tests-cli/fixtures/dmn-null-probe/null-absent.dmn`). Either a hard engine failure or a silently
wrong number, with a clean fidelity report.

The hydrator therefore runs `survivingRefs` over its **rendered** computed bodies and takes
`classifyRef` over the result, minus the synthetic `_self` binders, unioned with the source-instance
edge — the same pair every other decision uses. Two couplings come with it:

- **A free term reachable only from a computed body still becomes an `inputData`.** `freeTerms`
  scans the computed-selector decides as well, minus `_self` (which is a `GIVEN` parameter and
  therefore a `Ref` rather than a `Def`, so letting it through would put `input_self` — the
  desugaring's own scaffolding — back in the model's input contract). Before hydration the field
  **was** its own decision and did mint that input; after it, the context entry names it just the
  same.
- The rule is pinned by "requires every DECISION a computed field's body names" in
  `jl4/tests/DmnExport.hs`.

#### 4.4.4a A hydrator's entries pass the SAME verbatim gate as every other expression

ADDED 2026-07-31 in review, closing a defect that shipped.

Every other rendering path in `L4.Dmn.Lower` asks `feFragment == L4Verbatim` before emitting — that
gate **is** `D-NONFEELOUTPUT`. Hydrators are built outside the per-decide note machinery, so for a
time nothing looked at a context entry at all, and a computed field whose body `renderFeelIn` cannot
render shipped **raw L4 source** inside a `<literalExpression>` with a **clean fidelity report and
exit 0**. Reproduced with the built binary on a computed field that is a `CONSIDER` over a
payload-carrying sum:

```xml
<literalExpression id="hydration_r_ce3_lit">
  <text>CONSIDER `_self`'s d WHEN lease t THEN t, WHEN sale THEN `_self`'s a</text>
```

reported `1 lossy, 1 advisory`, no Blocking note, so `--fail-on blocking` passed it. That is exactly
the "green in the validator, wrong in the engine" failure this exporter exists to close, and it also
falsified two claims in this document at once: §4.4.3's "`_self` disappears from the model" (it is
right there, unbound) and `D-COMPUTEDFIELD`'s `lost:` clause "nothing an engine needs".

The gate is now applied: any context entry whose fragment is `L4Verbatim` raises `D-NONFEELOUTPUT`
**Blocking** against the hydrator, with a message written for a context entry rather than an output
entry. The corpora did not catch it because every committed hydrator's body happens to render
cleanly — `hydration.l4`'s header even says "everything here must stay engine-clean" — which is
precisely why the test is synthetic. Pinned by "reports a computed field body it cannot render as
FEEL, Blocking".

#### 4.4.4b A stated boundary: the select idiom does not fold inside a hydrator

`IF a AT LEAST b THEN a ELSE b` folds to `max(a, b)` everywhere else, **including through a
source-written projection** (`max(p.x, p.y)`, measured) — but not inside a hydrator, where Reg CF's
`greater of annual income or net worth` emits `(if annual_income >= net_worth then annual_income else
net_worth)`.

**Cause, narrowed by measurement rather than left as a hypothesis:** `Desugar.rewriteFieldRefs`
builds a sibling read as `Proj emptyAnno (Var emptyAnno _self) n`, a node with **no source range**;
the typechecker's annotation machinery skips rangeless nodes, so `annTypeSource` answers `Nothing`,
`builtinOperandType` answers `DmnAny`, `feelOrderable` is `False` and `selectIdiomIn` declines. The
same body written as a top-level decide over the same fields folds normally, which is the control.

**Not repaired, deliberately.** Both forms are `FullFeel`, both evaluate (33/33 on KIE 8.44 and
zeebe-dmn 8.7.6), so the cost is legibility and not fidelity — and the repair would be in
`L4.Desugar`, whose output every computed-field module and the exactprint goldens depend on. It is
**pinned** instead, by "does not fold the SELECT idiom inside a hydrator — a stated boundary" in
`jl4/tests/DmnExport.hs`, so the golden cannot move without someone reading this section. The
committed probe `jl4/tests-cli/fixtures/dmn-hydration-probe/hydration-context.dmn` uses
`max(annual_income, net_worth)` by hand and is therefore **not** byte-for-byte the emitter's output;
what it pins is the boxed-context **idiom**, not the expression text.

#### 4.4.5 A latent silent-null defect, found and FIXED

This is reported as a **defect the work uncovered**, not as new behaviour.

`alice's adult` (`jl4/examples/ok/computed-fields.l4`) type-checks through `inferRecordProjection`,
which resolves with an unfiltered `resolveTerm` and builds a `Proj` node whose selector is the
`ComputedSelector` decide — structurally identical to a stored-field projection. On the tree before
this change, `renderFeelIn`'s `Proj` case emitted `alice.adult` tagged **`SFeel`**: a path step into a
FEEL context whose `itemDefinition` **has no such component**, so FEEL answers `null` — while
`classifyRef` found the selector in `decideByUnique` and emitted a `RequiredDecision` beside it. The
artifact's edges and its expression contradicted each other, which is R11's exact complaint, and the
answer was silently wrong.

It was **latent rather than shipped**: `sumtype.l4` never called `doubled amount` and the Reg CF
corpus had no computed fields. Hydration closes it by construction, because it handles both the
`Proj` and the `App` spellings.

#### 4.4.6 `D-COMPUTEDFIELD`

**Advisory**, one per hydrated **type**, raised on the hydrated `itemDefinition`. It says that the
derived components are not marked derived in DMN, because `tItemDefinition` has no such flag and a
`contextEntry` is indistinguishable from a supplied value.

Advisory is the right severity and is not a fudge: **nothing an engine needs is missing**, because
hydration means no caller ever supplies a derived component. What is lost is a reader's ability to
tell, _from the type alone_, which components are the model's input contract and which the model
computes for itself. `FIDELITY-SEVERITY-AXIS-SPEC.md` §3.2 binds Advisory to the `Faithful` effect,
which is exactly the claim being made.

Component-level notes (`D-MAYBE-NULL`, `D-ITEMDEF`) fire on the **base** definition only and never on
the hydrated one, or every component note would double. The base is where a reader looks up the input
contract.

**[E] The one input shape that could have refuted "nothing an engine needs is missing" — MEASURED
2026-07-31, and it does not, but the answer is not the obvious one.** A hydrator's stored entries are
path accesses on the source instance, so if the SOURCE RECORD ITSELF is `null` every stored entry
answers `null`. Case D of `jl4/examples/dmn/hydration.cases.json` supplies exactly that, and **KIE
8.44.0.Final and zeebe-dmn 8.7.6 return byte-identical values**:

| entry / decision                     | value  |
| ------------------------------------ | ------ |
| `salary`, `other_income`             | `null` |
| `total_income` (`salary + other_…`)  | `null` |
| `band` (`if total_income >= …`)      | **1**  |
| `band_width` (`band * 25000`)        | 25000  |
| `applicant_score` (`total_… / 1000`) | `null` |

`band` is **not** `null`, and that is the finding. Its body is
`if total_income >= 100000 then 3 else if total_income >= 50000 then 2 else 1`; a non-boolean FEEL
condition yields `null`, `null` is not `true`, so each `if` takes its ELSE arm and the chain bottoms
out at `1`. The hydrated record therefore carries a **plausible, non-null derived component computed
from an absent record** — and its reader `applicant band width` answers `25000` rather than `null`.

The `D-COMPUTEDFIELD` claim survives, because it is about a caller never SUPPLYING a derived
component and that is still true. What this measures is a different boundary, stated here rather than
assumed away: **L4 has no null record**, so no L4 program can ask this question; the emitted DMN model
_can_ be asked it, and answers without complaint. Any caller that can produce a null record is outside
the model's contract, and the artifact does not say so anywhere an engine would enforce.

#### 4.4.7 The measurable win

`regcf-corpus.fidelity.txt` carried **four** `D-NONFEELOUTPUT` **Blocking** notes; two of them named
output entries that were literally `` `greater of annual income or net worth` OF investor `` and its
`lesser of` twin. After converting those two functions to computed fields, the entries read
`investor_hydrated.greater_of_annual_income_or_net_worth` — real S-FEEL — and **both Blocking notes
are gone** (4 → 2). The two that remain name `the applicable measure … OF investor`, a decision call
rather than a computed field, and are unaffected.

Six of the eight record functions over `InvestorProfile` were **left alone**, and the split is
**four and two**, not five and one:

- **Four are unary and read other module decisions** — `the applicable measure of annual income or
net worth` (`regcf.l4:388`), `either annual income or net worth is less than the cut point`
  (`:401`), `investment limit` (`:408`) and `the accredited-investor carve-out applies to` (`:436`).
  The first, third and fourth reach the dated rule-date predicate and the dated cut point, which
  would put law time inside a context entry where the DRG's single global rule-date input cannot
  reach, destroying #178's interval table.
- **Two are binary, not unary** — `aggregate amount sold to this investor including this
transaction` (`:423`) and `investor is within the investment limit` (`:443`). Each takes the
  amount to be sold alongside the investor, so neither is a candidate at all: a computed field's
  only parameter is the record.

(Corrected 2026-07-31 in review; this paragraph read "five … and one is binary" and also called all
eight "unary record functions" while counting two binary ones among them.)

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

> **Superseded in part, 2026-07-27 — see §13.2.** "Spaces work" is true of KIE, feelin and
> dmn-eval-js and **false of Camunda, in the silent-wrong-answer direction**: `annual income` is
> tokenised as `annual` `in` `come` — the membership operator — and answers a **boolean** rather
> than the number. EXECUTED on Camunda 8.7.6 against a model declaring `annual income` = 100000,
> `annual` = 5, `come` = [1,2,5]: it answers `true`, identically to `annual in come`, where KIE
> 8.44 answers `100000` (§13.2). The shipped golden throws on 4 of 5 decisions in Camunda 7
> (QUOTED) and is rejected outright at `parse()` by Camunda 8 (EXECUTED). Mangling is therefore
> **not** an optional portability preference — under R7 it is a correctness fix, and §5.2 is the
> policy. The three defects below stand unchanged; item 4 is added.
>
> Also measured: the two engines **bind the FEEL name off different attributes** — KIE off the
> node's `@name`, Camunda off the `<variable>`'s `@name`. Today's exporter mangles only the
> latter, which is why the same file fails both, for opposite reasons.

1. **`feelIdentText` passes dots through** — `keep c | c elem " _."` (`IR.hs:260-270`). An L4
   name containing `.` injects a FEEL path expression and silently shadows a genuine projection,
   with no warning. This is the E7 silent-misreading class, in our own code. **Fix this first;
   it is a defect independent of the whole redesign.**
2. **The same function is used for type names**, where a dot is DMN's import-prefix separator.
   Needs a separate `feelTypeNameText`.
3. **Keyword-_initial_ names** are the genuine hazard. §10.3.1.4: a name start SHALL NOT be a
   literal terminal symbol; a name _part_ MAY be. Keyword-inner is fine, which retires the worry
   about legal English being full of `in`, `for`, `between`.
4. **The declaration side is mangled and the node side is not** — `Emit.hs:135` emits
   `<inputData name="first-time issuer">` verbatim while `Emit.hs:141` emits
   `<variable name="first_time issuer">` through `feelIdentText`. `feelIdentText`'s own
   doc-comment claims the declaring and referencing sides "always agree"; the node `@name` is the
   place that does not go through it. KIE fires `VARIABLE_NAME_MISMATCH` **and then fails to
   build**. Added 2026-07-27; measured, see §13.2.

> **Status, 2026-07-29.** All four items are now fixed, and stage 2 has landed with them. Item **2**
> is `feelTypeNameText` (`IR.hs`), with the dot policy §5.3.6 left open ruled in §5.2 — a `.` folds
> to `_`, because a dot in a `typeRef` QName is DMN's import-prefix separator and this exporter
> emits no imports. **And item 2's separate function is now load-bearing for a second reason,
> found under review 2026-07-30 and fixed in the same change:** a type name is checked against
> `reservedFeelTypeNames`, which is `reservedFeelWords` **plus FEEL's built-in type spellings**
> (`number`, `string`, `boolean`, `Any`, `dateTime`, `daysAndTimeDuration`,
> `yearsAndMonthsDuration`; `date`/`time`/`duration`/`list`/`context` are already reserved words).
> The two namespaces genuinely differ here — a _variable_ called `number` is fine, because nothing
> resolves a variable name against the type names — but a `typeRef` **is** resolved against them,
> so an `itemDefinition name="number"` does not shadow FEEL's numeric type, it **aliases** onto it.
> An L4 `DECLARE` of a type named `number`, and every genuine `NUMBER`-typed element, would then
> emit the same `typeRef="number"`, and a reader resolving the numeric element's type would land on
> a `string` enum. **No fidelity note could report that**, because nothing in the artifact
> distinguishes the two types — which is why the repair is a rename, `number` to `number_`, keeping
> the L4 spelling verbatim on `@label`, rather than a diagnosis.
>
> Golden: the `number` / `is alpha` pair in `jl4/examples/dmn/sumtype.l4`, where `input_k` carries
> `typeRef="number_"` and `input_n` carries `typeRef="number"`.
>
> Item **3** is the reserved-word suffix (§5.2 stage 1 step 6), applied to the whole folded name and
> **case-sensitively**: FEEL's literal terminal symbols are lower case, so `IF` is not one and is
> not renamed. Stage 1's step 1 (NFC) is deliberately **not** implemented; the deferral and its
> measurement are in §5.3.3. `uniquifyIn` (stage 2) covers the DRG variable namespace and the
> record-field / projection-path namespace; `decisionService` and BKM `formalParameter` names have
> no emitter yet (Phase 5) and are each their own scope. On the Reg CF corpus the effect is
> measured: 169 DRG elements, **169 distinct FEEL names**, 37 `D-RENAME` at `Lossy`, and
> `D-FEELNAME` **0** where it was 9. The paragraph below is the state before that, retained because
> it is what the rest of §5.3 argues against.
>
> **Status, 2026-07-27 (revised the same day under review).** Items **1 and 4 are FIXED** and both
> engines are green on the re-blessed golden, at 25 expected values over 5 contexts (§13.7). Items
> **2 and 3 are still open**: type names still go through the same function, and no reserved-word
> suffix is applied. §5.2's stage 1 is implemented as far as step 5; step 6 and the whole of stage
> 2 (`uniquifyIn`) remain Phase 2 work, so distinct L4 names can still collapse onto one FEEL name
> — and mapping space and `.` to `_` **widens** that collision domain rather than leaving it
> unchanged. Every such collision is now reported by **`D-FEELNAME` at `Blocking`**, across the
> whole DRG namespace rather than the `inputData` half of it; measured engine behaviour is in
> §13.7-1. `@label` additionally keeps the L4 name visible in the file. Detection is not
> resolution: `uniquifyIn` is still the fix and is still Phase 2.

### 5.2 The policy

`@name` carries a FEEL-safe identifier; `@label` carries the verbatim L4 name. `label` is an
attribute of `tDMNElement` (`DMN13.xsd:30`), xmllint-verified as available on every element type
this exporter emits. Round-trippability becomes a property of the sidecar, so mangling costs
nothing in readability.

**Stage 1 — `feelBase : Text -> Text`**, pure, deterministic, total:

1. Normalise to NFC.
2. Collapse every maximal run of Unicode whitespace to a single `' '` — engines normalise
   whitespace runs, so without this two distinct L4 names silently become one.
3. Map each character: **keep `[A-Za-z0-9]`; map every other character — ASCII or not, letter or
   not, including space, `.`, `?` and every rule-30 symbol — to `'_'`.** (**Ruled by R3, 2026-07-27,
   §5.3.** This step used to read "keep FEEL name-start / name-part characters", which would have
   kept `é`, `収`, `·` and `’`. It does not, and §5.3.2 says why: "spec-legal" is not a usable
   predicate, because KIE **rejects** `’` — which grammar rule 30 explicitly permits — and
   **accepts** ASCII `'`, which no rule permits.)
4. Collapse runs of `_`; strip leading and trailing `_`.
5. Empty → `"_"`. Leading digit → prefix `"_"`.
6. Reserved word → append `"_"` (list: `true false null and or not if then else for in return
some every satisfies instance of between function external date time duration list context`).

**Stage 2 — `uniquifyIn : Scope -> [Text] -> [Text]`** over a stable source-order traversal:
first claimant keeps the base, the nth gets `base_<n>` for the least free `n ≥ 2`. **Scopes, widened
2026-07-27 by R3 (§5.3.4) and by what R1/§2.3 and §6.2 have since added to the namespace:**

1. the DRG's FEEL variable namespace — all `inputData` variables and all decision variables
   **together**, since they share one evaluation scope;
2. each itemDefinition's `itemComponent` list — **and, until itemDefinitions exist, the record-field
   projection paths `Lower` emits, which is where the one executed corpus collision actually lands
   (§5.3.4)**;
3. **`decisionService` names** (§2.3), which are FEEL names under R1 and which the original scope
   list predates;
4. **BKM `formalParameter` names** (§6.2), likewise.

**Stage 2 is a port, not a design.** **[D]** `assignIds` (`Lower.hs:1721-1730`) is already exactly
`uniquifyIn` — first claimant keeps the base, the nth gets `base_<n>` — applied to XML **ids**, and
`DmnExport.hs` pins `["input_n", "input_n_2"]`. Its character map is already byte-identical to the one
§5.2 step 3 now rules (`sanitiseId`'s `keep`, `Lower.hs:1740-1742`).

Stage 1 is deliberately non-injective; stage 2 makes the composite injective **within each
scope** by construction. Every rename — benign mangle and collision suffix alike — is a fidelity
entry, at **different severities**: a benign mangle preserves information in `@label`, a
collision suffix means the FEEL text no longer resembles the L4 name.

Net effect: `investor's \`annual income\``exports as`investor.annual_income`, with
`label="annual income"`on the variable, the component and the column. A mangled dotted path is
exactly S-FEEL's`qualified name`, so `Proj` (`Lower.hs:651`) stays classified `SFeel` — which
is what keeps record-reading columns inside the analysable fragment.

### 5.3 Unicode in names: fold, not keep — R3, ruled 2026-07-27

Evidence tags are §0's.

#### 5.3.1 The measurement that overturned the leaning

§11's R3 leaned **keep**. The leaning is wrong, and the number that kills it is not close.

**[M]** A full tokenised exposure scan over every `.l4` in the tree (639 files, 153 091 identifier
tokens; the L4 tokeniser transcribed from `Lexer.hs:474-495,652-656`, legality decided against DMN
1.3 rules 28/29/30), independently corroborated by a codepoint census that found **16 occurrences of
a non-ASCII letter in the entire tree** and not one of them in a declaration head:

| class                                              | occurrences | distinct |
| -------------------------------------------------- | ----------: | -------: |
| reaches a FEEL name, non-ASCII is **FEEL-ILLEGAL** |       2 930 |      704 |
| reaches a FEEL name, non-ASCII is **FEEL-LEGAL**   |       **0** |    **0** |
| `§`-header only, illegal                           |         930 |      865 |

Every one of the 2 930 is **U+2014 EM DASH**, which no engine accepts and which today's function
already maps to `_`. A stricter pass over unambiguous declaration heads agrees: 759 occurrences / 699
distinct non-ASCII heads, **100% FEEL-illegal, 0 FEEL-legal**.

> **One cell of the measurement's table is struck.** It reported `§`-header-only / FEEL-**legal** as
> `3 | 3`. **[M]** The command shown emits no such row; the 3 is a per-**character** count (`α`×2,
> `ç`×1) in a table whose other rows are name-token occurrences, and at token level the correct value
> is **0**, because every `§` name carrying `α` or `ç` also carries `§` or `—`. Harmless, and flagged
> anyway: this project has shipped fabricated citations before, and a number tagged as executed that
> its own command does not print is the same failure in miniature.

> **And the scope of "reaches a FEEL name" is now wider than that scan.** §2.3 (R1, already ANSWERED)
> rules **one `<decisionService>` per `§`**, and §2.3.1 records that the service's _name_ is what FEEL
> invocation resolves against. So `§` names **do** become FEEL names under the program model this
> document specifies, and the scan's `reaches = not a section header` rule cannot see them — parking
> 1 411 distinct `§` names, 865 of them non-ASCII-bearing, in an out-of-scope bucket. **[M]** KIE
> validates a `decisionService`'s element name as a FEEL identifier
> (`Invalid name 'Article 2(10) — "misconduct"': Name cannot contain the character '('`). The answer
> does not flip — every reclassified name is FEEL-**illegal**, so folding is still required — but the
> exposure claim is now stated over the right population, and **R1 joins R3's dependency list.**

**R3 asks which of two treatments to apply to FEEL-legal non-ASCII names. The corpus contains none.**

#### 5.3.2 "Spec-legal" is not a usable predicate

**[D]** DMN 1.3 §10.3.1.2 "Grammar rules", quoted from `pdftotext -layout` over
`https://www.omg.org/spec/DMN/1.3/PDF`. The identical production appears a second time as §9.2's
S-FEEL rules 25-27, which is how the transcription was checked — `pdftotext` inserts stray spaces
inside a few escapes and the two copies disagree about which, so each corrects the other:

```
 28. name start char = "?" | [A-Z] | "_" | [a-z] | [\uC0-\uD6] | [\uD8-\uF6] | [\uF8-\u2FF] |
      [\u370-\u37D] | [\u37F-\u1FFF] | [\u200C-\u200D] | [\u2070-\u218F] | [\u2C00-\u2FEF] |
      [\u3001-\uD7FF] | [\uF900-\uFDCF] | [\uFDF0-\uFFFD] | [\u10000-\uEFFFF] ;
 29. name part char = name start char | digit | \uB7 | [\u0300-\u036F] | [\u203F-\u2040] ;
 30. additional name symbols = "." | "/" | "-" | "’" | "+" | "*" ;
```

By that grammar `é ç ü ñ å ø α β 収 € ·`, combining U+0301 and `’` are all legal; `— – §` and ASCII
`'` are not.

**[M]** The same names put through four engines (KIE `kie-dmn-core` 8.44.0.Final and Camunda 7 on JDK
17, Camunda 8 `zeebe-dmn` 8.7.6, `feelin` 7.0.1):

| name                           | grammar       | KIE 8.44        | Camunda 7.23                | Camunda 8.7.6 | feelin |
| ------------------------------ | ------------- | --------------- | --------------------------- | ------------- | ------ |
| `année`, `収入`, `α`, `€`, `ç` | legal r28     | ✅              | ✅                          | ✅            | ✅     |
| `revenu année`                 | legal         | ✅              | ❌ parse error, col 8       | ❌            | ✅     |
| `revenu_année`                 | legal         | ✅              | ✅                          | —             | ✅     |
| `·` U+00B7                     | legal r29     | ✅              | ❌                          | —             | —      |
| **`’` U+2019**                 | **legal r30** | **❌ rejected** | ❌                          | —             | —      |
| **`'` ASCII apostrophe**       | **illegal**   | **✅ accepted** | ❌                          | —             | —      |
| **soft hyphen U+00AD**         | **illegal**   | ❌              | **✅ accepted** (invisible) | —             | —      |
| `—` U+2014, `–` U+2013         | illegal       | ❌              | ❌                          | ❌            | ❌     |
| `a-b`, `a.b`, `a*b`            | legal r30     | ✅              | ⚠️ parses, returns `null`   | —             | ✅     |

KIE's error on `’` is verbatim _"Invalid name 'x’': Name cannot contain the character '’'"_. So on the
first grammar-legal character tested, the engine is **exactly backwards from the specification**. The
two engines do not agree with the spec and do not agree with each other. A keep-arm's allow-list would
have to be established by execution against each engine and re-established at each engine upgrade,
and §5's whole point is that the output must run.

**[M]** Three riders. The spec's own `feelin` claim is correct — `evaluate('revenu année', …)` → 42 —
but `feelin` is not an engine anyone deploys against. **Camunda's objection is the space, not the
accent**, so folding non-ASCII buys Camunda nothing by itself; **[M]** after the ruled fold the space
is gone too, so §5.3.3 _is_ the Camunda fix (see §5.3.6's correction). And **NFC/NFD is a live
silent-wrong-answer hole** — model in NFC, caller in NFD: KIE `[SKIPPED]` loudly, **Camunda 7 returns
`Untyped 'null'` with no error and no warning**, feelin `null` + a warning — but that hazard is
**load-bearing under the keep arm only**, since folding collapses both forms into ASCII.

#### 5.3.3 The ruling

**`feelBase` folds. Emit ASCII-only FEEL names.** §5.2 Stage 1 step 3 as amended above is the whole
of it: keep `[A-Za-z0-9]`, map everything else to `_`. **No transliteration** (`é` → `_`, not `e`),
**no keep-flag** in v1 — a flag whose enabled path has zero corpus coverage is an untested second
exporter.

Three notes.

- The character map is byte-identical to `sanitiseId`'s existing `keep` (`Lower.hs:1740-1742`), which
  makes Stage 2 a port rather than a design (§5.2).
- **NFC (step 1) stays, but its cost is stated.** Under fold it is defence-in-depth, not load-bearing,
  and it is not free: **[D]** `jl4-core.cabal` has no normalisation dependency, so step 1 adds one and
  the library must survive the `arch(wasm32)` branch. `unicode-transforms` is the obvious candidate;
  **[U]** untested under wasm32. If it does not build, drop step 1 rather than blocking §5 — step 2
  carries the part that matters and the NFC hazard is the keep arm's.

  > **DEFERRED, 2026-07-29, when the rest of stage 1 and the whole of stage 2 landed.** Step 1 is
  > **not implemented**, and the reason is recorded here rather than left implied by absence.
  > `feelIdentText` and `feelTypeNameText` (`jl4-core/src/L4/Dmn/IR.hs`) implement steps 2–6 and
  > nothing else. Three facts make the deferral the default rather than the lazy option: the
  > dependency question above is unanswered and the wasm32 branch is real; §5.3.3 itself calls NFC
  > "defence-in-depth, not load-bearing" **under fold**, which is the arm that shipped; and the
  > exposure is nil — §11-R3 records that every one of 2 930 non-ASCII characters reaching a FEEL
  > name in 639 files is U+2014 EM DASH, which the fold already maps to `_`, and §5.3.1's codepoint
  > census found 16 non-ASCII letters in the entire tree, **none in a declaration head**. The
  > trigger for revisiting is §5.3.7's: the first corpus with non-Latin-script or diacritic
  > declaration heads, which reopens the keep arm and promotes step 1 to load-bearing in the same
  > motion.

- **`@label` emission is promoted from convenience to `SHALL`.** Under fold it is the only carrier of
  the source name's non-ASCII content.

**And the ruling is not hypothetical: it has already shipped, on R7's branch.** **[D]**
`feat/dmn-engine-flavors` (`7e766d71`, PR #160) implements exactly this as `feelIdentText` —
`isAscii c && isAlphaNum c` kept, everything else `_`, runs collapsed, leading digit prefixed — minus
step 1 (NFC), step 6 (reserved-word suffix) and Stage 2, all of which its own docstring defers to
Phase 2. R7 reached the same answer from the opposite direction (Camunda tokenises `annual income` as
`annual in come` and answers a **boolean**), which is independent corroboration rather than agreement.
**R3 and R7 are not in tension, and R3 does not owe R7 a flavor bit** (§14).

#### 5.3.4 The prerequisite: folding is the collision-generating step

**R3 SHALL NOT be treated as closed without §5.2 Stage 2** — and the review's central correction here
is right in substance and had to be re-measured, because it scored the wrong function.

**[D]** The measurement pass's collision census ran today's `feelIdentText`, not the `feelBase` R3
rules; the review re-ran it against a faithful reimplementation of the ruled function and reported 11
collisions in 5 files. Neither is the decisive measurement, because **the ruled function now exists**
and can be executed. Doing so gives a sharper answer than either:

**[E]** Exporting the corpus with the PR #160 binary — the ruled fold, plus its `D-FEELNAME` detector
— and classifying every collision group by whether the colliding L4 names are the _same_ name (the N
`inputData`-per-`GIVEN` case §2.1 fixes) or _different_ names (a genuine fold collision):

```sh
for f in $(cat corpus62.txt); do <PR#160-l4> export "$f" --to dmn --fidelity-report -o new/…; done
# 51 of 62 modules exported (Charities is slow; see coverage below)
# D-FEELNAME groups, all-names-identical : 67
# D-FEELNAME groups, names DIFFER        : 0
```

So **in the DRG's variable namespace, across the exported corpus, the ruled fold creates zero new
collisions.** The review's 11 are real but live outside that namespace: **[M]** they are `§` section
names (not emitted today), a `not-ok` fixture, and `jl4/experiments/dogs.l4` — which **[E]** does not
typecheck on this tree (`l4 check` errors on an AND/OR precedence rule), so it can never reach the
exporter at all.

**But the hazard is live, and it is somewhere neither pass looked.** **[E]** The one executed corpus
collision is in the **record-field projection namespace**, and it is a wrong number:

```
jl4/examples/openfisca/not-ok/name-collision.l4
  DECLARE Person HAS `foo bar` IS A NUMBER, foo_bar IS A NUMBER
  `sum two` p period MEANS (p's `foo bar`) PLUS (p's foo_bar)      -- two DIFFERENT fields
```

| exporter                     | emitted FEEL                | fidelity report      |
| ---------------------------- | --------------------------- | -------------------- |
| this branch (`3b9bfc6e`)     | `p.foo bar + p.foo_bar`     | `D-LITERALEXPR` only |
| **PR #160 (the ruled fold)** | **`p.foo_bar + p.foo_bar`** | `D-LITERALEXPR` only |

The old form is broken loudly (a space in a projection path); **the new form is valid FEEL that
computes the wrong number, and nothing reports it.** `D-FEELNAME` does not fire because it walks the
DRG namespace and this is a projection path. The file's own comment says _"The bridge must REJECT
this (silently conflating them gives wrong numbers)"_ — the OpenFisca backend does; the DMN exporter
does not.

**Consequently:**

1. §5.2's Stage 2 scope list is widened (done, above) to cover projection paths / `itemComponent`
   lists, `decisionService` names and BKM `formalParameter` names.
2. **Until Stage 2 lands, a record whose fields collide under `feelBase` is `Blocking`.** Reuse
   `D-FEELNAME`, whose severity R7 already set to `Blocking` for the DRG namespace; R3 extends its
   domain rather than minting a code.
3. **The severity argument is now settled rather than assumed.** With detection, `D-RENAME`'s
   collision arm can stay `Lossy` — the names are made distinct and `@label` preserves the source.
   Without detection, `Lossy` understates a silent wrong answer.

> **Two witnesses from the review are withdrawn, and the reason matters.** Its `collide.dmn` and
> `collide2.dmn` probes were built with the two colliding elements carrying **distinct element
> `name`s** and identical `<variable name>`s, and **[M]** KIE binds compile-time FEEL scope from the
> element `name`, not from `<variable name>` — so those files demonstrate something else. The
> `p.foo_bar` witness above needs no such construction: it is the shipped exporter, on a committed
> file, producing an arithmetic error.

#### 5.3.5 The element-`name`/`variable`-`name` invariant, and a golden that did not load

R3 makes folding normative and `@label` mandatory, so it is the right place to state the invariant
that makes them work — and to record that this branch violated it.

**[E]** The committed golden on this branch, straight through KIE 8.44.0.Final:

```
jl4/examples/dmn/expected/reg-cf.dmn   (branch 3b9bfc6e)
  BUILD messages: 1
  ERROR: DMN: Error compiling FEEL expression 'first_time issuer' on decision table
         'financial statements required', input clause #2: syntax error near 'issuer'
  BUILD FAILED
```

Root cause: `Emit.hs:136-146` emitted the **verbatim** L4 name as the element `name` and the folded
name as the `<variable>` name, on the belief that "the variable's is the FEEL name a decision's
expressions actually use". **[M]** That belief is false in both directions — referencing the variable
name fails at compile with `Unknown variable`, referencing the element name compiles and fails at
runtime — and §6.2 already stated the rule for one node kind (_"Invariant: BKM `@name` ==
`variable/@name`"_) without anyone generalising it.

**Ruled: element `@name` == `<variable>/@name` == the folded name; the verbatim L4 name lives only in
`@label`.** **[E]** This is **already fixed on PR #160** — `<inputData id="input_first_time_issuer"
name="first_time_issuer" label="first-time issuer">` — and the same golden now builds with **0
messages, `hasErrors=false`, 5 decisions**. R3 records the invariant so that the fix is a rule rather
than a repair.

#### 5.3.6 What R3 does **not** decide, and one correction to its own draft

- **Spaces and dots are R3's after all.** An earlier draft said 95.2% of folded declaration heads still
  contain a space, that Camunda's problem is therefore §5.2 step 3's and "not R3". **[M]** That figure
  characterises the function R3 _replaces_; under the ruled `feelBase` the space and dot counts are
  **0** and the corpus is 100% Camunda-clean, and R3's own §5.3.3 says step 3 "is replaced by". The
  two statements contradicted each other; the second wins. **R3 is the Camunda naming fix**, which is
  why R7 shipped it. Flavor-independence still holds — see §14.
- **Enum constructor spellings.** A constructor name becomes a FEEL **string literal** (the tag
  _value_), not an identifier, so `feelBase` must **not** touch it. **[E]** §4.2.1-3's exhibit shows
  what those literals actually are — section-qualified, with dots and em dashes, inside quotes, which
  is legal. Payload **component** names are identifiers and do go through `feelBase`.
- **XML ids.** `sanitiseId`/`assignIds` untouched; R3 rules the FEEL name namespace only.
- **Type names.** §5.1-2's separate `feelTypeNameText` still owes its own dot policy; R3 fixes only
  that it uses the same character map underneath. **RESOLVED — see §5.2's item-2 status paragraph**
  for the dot policy (2026-07-29) and for the built-in-type-name collision the separate function
  also has to prevent (2026-07-30). The character map is still shared; the reserved set is not.
- **`@label` content.** Verbatim, unfolded, un-normalised.
- **R2's residual risk (3).** R3 does not touch it — that is R4's (§4.2.1-4).

**Two incidental defects, recorded so they are fixed when §5 lands.** **[D]** `IR.hs:255`'s docstring
cites _"grammar rule 30"_ for FEEL names containing spaces; rule 30 is the `. / - ’ + *` production
and the correct authority is §10.3.1.4. And `D-SCOPE`'s message renders the **folded** name ("two
different terms are both named `a_b`") when the L4 terms are `a-b` and `a_b`; it should name both L4
spellings, since under R3 the folded form is precisely what the reader cannot invert.

#### 5.3.7 The case against this ruling, and what overturns it

The measurement is of an English-and-French-legislation corpus written by this team, and **0** is a
fact about _today's_ corpus, not about L4. The moment anyone encodes Singapore, Japanese or Québec
rules — the stated ambition of this pipeline — accented and CJK declaration heads arrive in bulk, and
**[M]** KIE, Camunda 7, Camunda 8 and feelin **all** evaluate `année` and `収入` natively and
unanimously, in literal expressions and decision tables alike. Under this ruling a Japanese statute
exports as a DRG in which **every name is the single character `_`** — steps 4 and 5 strip the
underscore runs, so it is not `__`/`___` as an earlier draft said, it is one `_` for every name — and
Stage 2 then suffixes an entire model into `_`, `_2`, `_3`, with `@label` the sole carrier of meaning.

The honest framing is not "the keep arm's justification failed" — true, and incidental. It is that
**the corpus supplies zero discriminating evidence between the two arms, and fold is the cheaper of
two empirically tied options.** **[M]** Over all 10 558 distinct L4 names in the tree, a faithful keep
arm and the ruled fold differ on **three**, all `§` headers, and both engines accept both forms. No
measurement available to this ruling could have separated them.

**The concrete trigger for revisiting R3: the first corpus with non-Latin-script or diacritic
declaration heads.** Re-run the exposure scan; when the "FEEL-legal, reaches a FEEL name" cell is
non-zero, R3 reopens. The keep arm is then: relax step 3 to a per-engine allow-list _established by
execution_ (never from rules 28-30), promote step 1 (NFC) to load-bearing with the wasm32 dependency
question settled, and keep Stage 2 unchanged. The fold path and the keep path differ in exactly one
function.

#### 5.3.8 What review changed

Eight defects; the ruling's direction survived all of them and three changed its content. **The
collision census scored the wrong function** — and rather than adopt the review's re-score, this pass
executed the ruled function as shipped on PR #160 and found **0** fold-created collisions in the DRG
namespace and **one, in the projection namespace, that computes a wrong number** (§5.3.4); the
prerequisite stands, with a wider Stage 2 scope than either pass proposed. **The exposure denominator
predated §2.3** — `§` names are FEEL names under R1, so R1 joins the dependency list (§5.3.1). **And
R3 owed a normative sentence it had not written** — element `name` == variable `name` == folded name —
whose absence is why the committed golden did not load in KIE (§5.3.5). Five did not change it and are
corrected in place: the `3 | 3` exposure cell is struck (§5.3.1); the two engine witnesses are
withdrawn and replaced (§5.3.4); Stage 2's scope now covers `decisionService` and BKM parameter names
(§5.2); the Camunda figure and the self-contradicting "not R3" sentence are corrected (§5.3.6); and
the worst case is "every name becomes `_`" (§5.3.7).

**One reviewer finding is recorded as narrowed rather than accepted.** Its "the hole is live, not
latent" rests on 11 collisions counted over all 639 `.l4` files. **[E]** Two of its three named
witnesses cannot reach the exporter — `dogs.l4` does not typecheck, and `§` names are not emitted
today — and in the three ruled corpora the DRG-namespace count is 0. The finding is upheld on its
third witness, which this pass strengthened into an executed wrong answer.

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

**Measured 2026-07-30 — the engine-intersection triple.** BKM emission is not only the faithful
spelling of a parameterised callee; it is the **only two-engine-portable** spelling of a
per-element predicate with a tabular body. Three hand-written fixtures in
`jl4/tests-cli/fixtures/dmn-engine-intersection/` express one statute-shaped predicate ("either
spouse earns under $100,000 or is a Qualifying Candidate") over one shared cases file, and both
committed engine harnesses were run over all three:

| predicate spelled as                    | KIE 8.44         | zeebe-dmn 8.7.6   |
| --------------------------------------- | ---------------- | ----------------- |
| inline in the quantifier's `satisfies`  | pass, 0 warnings | pass              |
| decision table in a boxed-context entry | pass, 1 warning  | **parse failure** |
| decision table in a BKM                 | pass, 0 warnings | pass              |

The boxed-context placement is schema-valid DMN 1.3 — a context entry holds any expression, and
`tFunctionDefinition` is an expression — yet zeebe-dmn rejects it at parse (`expected literal
expression but found '...DecisionTableImpl...'`). So "schema-valid" and "portable" are distinct
properties, and the middle row is the measured gap between them. The KIE warning on that row is
itself a finding: `MISSING_TYPE_REF` on the context-bound function asks for the type
`Spouse → boolean`, which the `itemDefinition` language cannot spell (§4's type table has no
function type). Consequence for this section: without BKMs, the exportable per-element predicate
is an opaque FEEL string that no gap/overlap analysis can reach; with them, it is a table both
engines accept and KIE's analyser checks. The Camunda failure is **pinned** as a negative
control in `jl4/tests-cli/Main.hs` and in the `dmn-engines` CI job; if a zeebe-dmn upgrade
learns to parse the boxed-context file, those legs go red with instructions to flip the pin and
narrow this note.

### 6.3 Refuse loudly — three cases, not BKMs in general

> **Case 3 narrowed 2026-07-27 by R7 (§13.3).** It read as an instruction to _suppress_ BKM
> emission under a target engine. Measurement retired that: KIE and Camunda 8 — the two flavors
> this exporter emits — both execute BKMs in every probed form, so **BKM is built once, for both
> flavors, ungated**. What survives is a **fidelity note**, not a suppression, and it is keyed to
> consumers we do not emit for (`@hbtgmbh/dmn-eval-js`, Camunda 7). Read case 3 below with that
> substitution.

1. **Recursion.** DMN §6.3.9 (Business Knowledge Model metamodel): "a BusinessKnowledgeModel
   element SHALL not require itself, directly or indirectly". KIE
   evaluates recursive BKMs anyway (`fact(5)=120`) but emits a spurious eval-time ERROR and the
   behaviour is explicitly vendor-dependent. L4 permits recursion (`rent spine`, `ror together`
   in Housing). **Ruled 2026-07-27: the cycle check is §6.4's, and `D-RECURSIVE` is its §6.3.9 arm,
   riding with Phase 5's BKM emission.** This bullet used to forward to §11-R5 for where the check
   lives, which meant §6.3-1 was **not** an independent backstop for R5 — it was a forward reference
   to it. It is now discharged by §6.4, and §6.4.2 records why a detector written as "does this
   decide mention its own name" would miss four of the nine reachable cycle shapes.
2. **Partial application / higher-order.** A BKM is a first-order named function only.
3. **Non-KIE target engines.** `@hbtgmbh/dmn-eval-js` has no BKM support and fails **silently**:
   an unresolvable callee in a cell logs `resolved to undefined` and the table falls through to
   the next rule, returning a plausible wrong answer. ~~If the exporter claims a target engine,
   gate BKM emission on it.~~ **Superseded — name it in the fidelity report; do not gate emission
   on it.** See the note at the head of this section.
   the next rule, returning a plausible wrong answer. If the exporter claims a target engine,
   gate BKM emission on it. (**Narrowed 2026-07-27 by R7/§13:** KIE and Camunda 8 both execute BKMs
   in every probed form, so this is not a flavor axis. It survives as a refusal keyed to
   `dmn-eval-js` and Camunda 7, neither of which is a flavor we emit for.)

### 6.4 Acyclicity: three graphs, one check — R5, ruled 2026-07-27

Evidence tags are §0's.

**R5's premise was false, and correcting it moves the ruling from bookkeeping to soundness.** R5 asked
only _where_ a check should live, on the stated ground that "L4's one-pass scope checker does not
currently admit forward references among top-level `DECIDE`s, so no module can produce a cycle
**today**". Six one-line probes produce one.

#### 6.4.1 The clause, cited correctly

`Lower.hs` cites **"DMN 7.3.1"**. **[M]** §7.3.1 is _Expression metamodel_. The acyclicity requirement
is **§6.3.7**, and there are three sibling clauses, one per element kind — **[D]**, verbatim from the
extracted OMG DMN 1.3 text (`grep -n "SHALL not require itself"` → three hits):

- **§6.3.7 Decision metamodel, pp. 38-39:** _"…the requirement subgraph of a Decision element SHALL be
  acyclic, that is, that a Decision element SHALL not require itself, directly or indirectly."_
- **§6.3.9 Business Knowledge Model metamodel, p. 41:** the same sentence for
  `BusinessKnowledgeModel`. (§6.3-1 already cites this correctly.)
- **§6.3.10 Decision service metamodel, pp. 42-43:** the same sentence for `DecisionService`. This is
  the clause §2.3.2 called "the §6.3.9-analogue"; it has its own number, now corrected there.

**Three elements, three requirement subgraphs, and this spec already owns all three.** §6.3.7 is the
`informationRequirement` graph, which _is_ `dcnRequirements`. §6.3.9 is the `knowledgeRequirement`
graph, arriving with BKMs in Phase 5. §6.3.10 is §2.3.2's service graph. R5 is not one ruling about
one check; it is the placement question for a routine three parts of this spec need.

#### 6.4.2 What is reachable today

**[M]** Nine probes. Cycle detection by DFS back-edge over `<requiredDecision>` in the exported DMN.

| #   | construct                                              | typechecks | DRG cyclic?                              | fidelity report                          |
| --- | ------------------------------------------------------ | ---------- | ---------------------------------------- | ---------------------------------------- |
| p1  | forward reference, top-level `DECIDE` → later `DECIDE` | yes        | no (genuinely acyclic)                   | D-SCOPE, 2× D-LITERALEXPR                |
| p2  | **mutual recursion, two top-level `DECIDE`s**          | yes        | **yes**                                  | no mention of the cycle                  |
| p3  | self-recursion, top-level `DECIDE`                     | yes        | no — **self-edge erased** by `freeRefs`  | D-NONFEELOUTPUT (on `OF`, not recursion) |
| p4  | cycle through a `WHERE`-local                          | yes        | **yes**                                  | no mention of the cycle                  |
| p5  | cycle through a record computed field                  | yes        | no — one direction only, `Proj` filtered | —                                        |
| p6  | section-qualified mutual recursion across two `§`s     | yes        | **yes**                                  | **advisory only**                        |
| p7  | nullary `MEANS` cycle                                  | yes        | **yes**                                  | **advisory only**                        |
| p8  | cycle through a guard / input position                 | yes        | **yes**                                  | **`(nothing lost)`**                     |
| p9  | 3-cycle among nullary decisions                        | yes        | **yes**                                  | advisory only                            |

The only route L4 closes is a cross-**module** `IMPORT` cycle. The premise's second half is false for a
reason the repo already knows: **[D]** `TypeCheck.hs:30-34` still says _"forward references are not
possible"_ while `specs/done/SECTION-LEXICAL-SCOPING-SPEC.md:435` says _"L4 currently allows forward
references within a module (the three-phase pipeline scans all declarations before inferring
bodies)."_ R5 was reasoned from a stale header comment instead of from a run.

**[M]** Corpus census: 55 exported models, 1068 decisions, 961 `requiredDecision` edges, **0 cyclic**
— Housing and Reg CF complete, half of Charities not covered (export timeouts; **[E]** this pass hit
the same wall, 51 of 62 modules in a 900 s-per-file run, `charities-common.l4` and
`housing-act-common.l4` timing out). So **R5 is a reachability break, not a corpus break.**

**And §6.3-1 is not a backstop.** **[E]** `grep -rn 'D-RECURSIVE\|D-SUMTYPE\|D-PARTIAL' --include=*.hs .`
returns nothing; §7 marks `D-RECURSIVE` "New"; and §6.3-1's own last sentence used to forward to R5.
Nor would §6.3-1 as _worded_ catch p6-p9: it is framed around recursion of _functions_, whereas those
four are **nullary, parameterless, tier-1** decisions where nothing is recursive by inspection and the
recursion exists only as a cycle in the requirement graph. **It has to be an SCC.**

#### 6.4.3 The failure mode is a clean bill of health, plus one silent `null`

**[D]** The emitter terminates — `decisionLevels`' fold is bounded by `length ds` and its comment says
so. Output is well-formed XML, `l4 export` exits 0, and p8's report reads `(nothing lost)`.

**[M]** Engines, on the emitted cyclic file: KIE 8.44 `ERROR DMN: Cyclic dependency detected for node
'p'` then `[SKIPPED]`; Camunda 7.23 refuses to parse (`DMN-02015 … has a loop`); Camunda 8.7.6 rejects
at parse (`Invalid DMN model: Cyclic dependencies between decisions detected`). **[E]** Both of the
last two reproduced in this pass on real corpus files (§6.4.4-2).

Two conclusions pointing in opposite directions.

**(a) An emitted cycle is loud.** Three engines, three rejections. So the _indirect_ case is not silent
unsoundness; it is a dead-on-arrival artifact over which our report says `(nothing lost)`. That caps
its severity — and it is still the exporter asserting a property it did not check.

**(b) The suppressed self-edge is silent unsoundness, and it is ours.** **[D]** `freeRefs` binds the
decide's own name (`Lower.hs:1779`) and `classifyRef` filters `target /= did` (`Lower.hs:1713-1715`),
so a decision that requires _itself_ — the case §6.3.7 names **first** — cannot appear in a `Drg` by
construction. **[M]** On the real exporter, `GIVETH A NUMBER / a MEANS IF x THEN 1 ELSE a` exports
with **advisory-only** fidelity and **no** `informationRequirement`, and KIE then compiles it with
`hasErrors=false` and answers `x=true → 1 [SUCCEEDED]`, **`x=false` → `null` [SUCCEEDED]**; Camunda 7
parses it happily. Both engines catch the two-node version of the identical defect. **Our filter is
what converts a loudly-caught violation into a silent one.**

#### 6.4.4 The ruling

**Both of R5's options are half right, and the question as posed was not the load-bearing one.** The
load-bearing question is _which graph_, and there are three.

1. **Where: a well-formedness check on the finished IR — `checkDrg :: Drg -> [FidelityNote]` in
   `L4.Dmn.IR`, folded into `drgNotesAll`.** Not in `Lower`, and not a free-standing CLI pass. §6.3.7
   constrains the `informationRequirement` graph and that graph _is_ `dcnRequirements`, so the check
   should read the artifact and nothing else; **[D]** `IR.hs` already owns this backend's loss
   vocabulary (`FidelityLoss` / `renderFidelityLoss`) and its report (`dmnReport`), so this is not a
   fresh mechanism; and `checkDrg` is unit-testable without constructing a `Module Resolved`. A CLI
   pass is excluded separately: **[D]** the only pre-emission guard there is
   `when (null (drgDecisions drg)) … exitFailure` (`Export.hs:286-291`), and `Export.hs:37-46`
   explicitly forbids fidelity findings from setting the exit code. Order inside `drgNotesAll`, so
   goldens do not churn: module-level `drgNotes`, then `checkDrg`, then per-table notes in decision
   order.

2. **`Lower` must stop lying about self-edges — and, on the ruled target pair, that costs nothing.**
   Delete the own-name binding from `freeRefs`' `bound` and the `target /= did` arm of `classifyRef`,
   so a self-requirement appears in `dcnRequirements` as a one-element SCC and the emitted file is
   ill-formed in the way it actually is. **[D]** Blast radius: `freeRefs` has exactly two call sites
   (`Lower.hs:1559`, `1699`) and no use outside `Dmn/Lower.hs`; the first already filters
   `not (Map.member u decideByUnique)`, so the own name cannot leak into `inputData` synthesis.

   > **The review's cost objection, measured on the right engines.** Review found **4 corpus models
   > containing a self-recursive emitted decision** — **[E]** confirmed: `rent spine` in
   > `housing-act-ground-1`, `-1-full` and `-schedule2-aspect`, and `ror together` in
   > `housing-act-possession-decision` — and measured that patching the self-edge in takes all four
   > from `PARSE OK` to a whole-file `DMN-02015 … has a loop` in **Camunda 7**, i.e. 72 decisions.
   > **[E]** Reproduced exactly. **But Camunda 7 is not a target: R7/§13.1 rules the flavors `kie` and
   > `camunda` (= Camunda 8), and §13 records that Camunda 7 lacks BKM support and is out of scope.**
   > On the two engines that _are_ targets the cost is **zero, because these four models already do
   > not load**:
   >
   > ```
   > KIE 8.44   housing-act-ground-1.dmn          today: BUILD FAILED (4 errors)   +self: 5 errors
   >            housing-act-possession-decision   today: BUILD FAILED (58 errors)  +self: 59 errors
   > Camunda 8  housing-act-ground-1.dmn          today: PARSE FAILED (raw-L4 literal expressions)
   >                                              +self: PARSE FAILED ("Cyclic dependencies … detected")
   > ```
   >
   > **[E]** And all four decisions are **already `Blocking` today**: `rent spine` carries
   > `D-LITERALEXPR` _"is a deontic (regulative) body"_, `ror together` carries `D-LITERALEXPR` _"is
   > not a guarded chain"_. So the un-suppression adds a second `Blocking` note to decisions that are
   > already refused, in files that are already unloadable in both target engines. **The review's
   > finding is upheld as a fact and rejected as a cost.** What survives it is the honesty
   > requirement, which is the point: **[E]** Camunda 8's message goes from a four-line FEEL parse
   > dump to `Invalid DMN model: Cyclic dependencies between decisions detected`, which is a strictly
   > better diagnosis of the same file.

3. **The note: `D-CYCLE`, `Blocking`, one per SCC, `range = Nothing`.** **The side condition is
   `|SCC| ≥ 2, or |SCC| = 1 with a self-edge`** — stated because both defaults are wrong: literal
   "one per SCC" emits a note for every acyclic node (1068 on the measured corpus), and the obvious
   repair "SCCs of size ≥ 2" silently undoes the whole of (2). It must list **both the name and the
   id** of every member: **[M]** a probe emits two decisions both named `shared` with ids
   `decision_shared` and `decision_shared_2`, so names alone are ambiguous under §5.2's uniquifier.

4. **Emission: unchanged, no repair — with one un-suppression, whose cost is (2).** Emit the cycle as
   it is and report it. Every available repair — dropping an edge, dropping a node, inlining a member
   — changes what the model says and would convert a rejection three engines make loudly into a
   plausible wrong answer. **This is the exact inverse of §2.3.2, and the contrast justifies both:** a
   service-level cycle is an artifact of _our_ granularity choice, so splitting is semantics-preserving
   and repair is honest; a decision-level cycle is in the source, so there is nothing to preserve by
   rewriting it.

5. **§6.3.9, same routine, second graph, `D-RECURSIVE`, Phase 5.** When BKM emission adds
   `knowledgeRequirement` edges, `checkDrg` runs the same SCC over them and emits `D-RECURSIVE`
   (`Blocking`) — different code because the clause cited and the reader's remedy differ, one detector
   because two detectors is how one of them gets skipped. **This discharges §6.3-1's forward reference
   to R5**, and §6.3-1 now says so.

6. **§6.3.10, same routine, third graph, §2.3.2's splitter.** The service partition is chosen in
   `Lower`; `checkDrg` verifies it. §2.3.2 says "split it into finer services **until** the graph is
   acyclic", i.e. a fixpoint, so the routine must be an exported plain function over `Drg` callable
   from `Lower` mid-lowering — **not** inlined into a report. That is a real amendment to (1), forced
   by the review, and it is why (1) says `checkDrg :: Drg -> [FidelityNote]` rather than "a step in
   `dmnReport`".

7. **Sequencing: Phase 0.** The §6.3.7 half depends on nothing in this spec — no un-lifting, no naming
   policy, no BKMs — and is perhaps 40 lines including the note. **R5 does not block #923.**

8. **`--fail-on` unchanged.** **[D]** `Blocking` is the ordinary case (`Export.hs:37-46`), and a gate
   on it would fail nearly every export. p8's defect was never the exit code; it was the report saying
   `(nothing lost)`.

9. **Fix two stale artifacts in the same change.** `Lower.hs:1702-1712` — delete the false premise and
   correct "DMN 7.3.1" to §6.3.7. `TypeCheck.hs:30-34` — the stale _"forward references are not
   possible"_ is what produced this ruling's error and will produce the next one.

#### 6.4.5 What this check cannot see

`dcnRequirements` is an **under-approximation** of the source's reference graph in three named ways,
two of which survive (2):

- **`Proj`-mediated edges.** **[D]** `freeRefs` filters projection field names, so p5's `f → Node.c →
f` emits only one of its two edges. Whether that survives is a Phase 3 question — §4.1 changes what
  a record field becomes — so the instruction is **re-measure p5 after Phase 3**, not patch it blind.
- **Intra-decision recursion.** A `WHERE`-local that recurses on itself or a sibling is a cycle
  entirely _inside_ one node; no graph over decisions can see it. **Not R5's**: it is §2.4.1's **L12**
  and §2.4's `TERMINATES`, and **[M]** both are caught incidentally by `D-LITERALEXPR` at `Blocking`
  today.
- **Cross-module callees.** `freeRefs` drops names from other modules by design (§2.4.5), so a cycle
  closing through an import is invisible to this check and to §2.4.1's `TOTAL` alike. L4 rejects an
  `IMPORT` cycle, which closes the mutual case but not a diamond.

`D-CYCLE` over `dcnRequirements` is therefore **exactly sound for the question §6.3.7 asks — is the
emitted artifact well-formed — and is not a recursion detector.** Recursion detection is §6.3-1's and
§2.4.1's, over the source call graph, in `Lower`, where R2 already has to build one.

#### 6.4.6 The argument against this ruling

**The strongest case for `Lower` is that `Lower` is where the source is, and the source is where the
truth is.** §6.4.5 concedes three classes of reference the lowering has already erased, and §6.4.3(b)
shows one erasure _is_ the bug. A `Drg`-only check can confirm "the picture we drew is internally
consistent", never "the thing you wrote is circular". `Lower` also has `bestRange` in scope. And
**[E]** every one of the 26 fidelity codes in this tree lives in a backend's `Lower` — 12 `D-*` in
`Dmn/Lower.hs`, 6 `D-MD-*` in `Dmn/Markdown.hs`, 8 `P-*` in `Bpmn/Lower.hs` — with **[D]**
`Bpmn/Lower.hs:697-712` having already decided this precise question the other way, for a cycle:
_"the /types/ permit all three, and this module is written against the types, not against one
afternoon's extractor … **Detected, not rendered.**"_

Three things answer it, one of which is a measurement.

- The locatedness argument is **refuted by the same precedent**: **[D]** `P-CYCLE` sets
  `range = Nothing` (`Bpmn/Lower.hs:786`) and identifies the cycle by naming its members, because a
  cycle is not at a point. **[M]** With a 93-decision maximum in the corpus, "these four decisions form
  a cycle, with ids" is more actionable than a range pointing at one arbitrary edge.
- The "source is the truth" argument is **conceded and routed elsewhere**: §6.4.4(2) moves the erasure
  fix into `Lower`, and §6.4.5 hands recursion detection to §2.4.1's call graph.
- The consistency argument cuts both ways: a whole-graph SCC computed in a `where`-clause of a function
  whose body is `zipWith lowerOne decides decideIds` is a global check wearing a per-decision costume.

**And the review's strongest counter-proposal — detect in `Lower` over the pre-filter reference graph,
so that p3/p5 and the four corpus self-recursions are caught with emission untouched — is adopted in
part rather than rejected.** It is right that detection and emission are separable, and §6.4.4 keeps
them separable: `Lower` decides what to emit, `checkDrg` verifies it. Where it is not followed is p5,
because a pre-filter graph would report a cycle the emitted artifact does not contain, which is a
different note with a different remedy; §6.4.5 defers it to Phase 3 instead. The un-suppression is
kept because it is what makes the emitted artifact _true_, and §6.4.4(2) measures its cost on the
ruled engines as zero.

**What would overturn it.** (i) If R6 or Phase 4 gives `Decision` a `SrcRange` for other reasons —
**[E]** `L4.Dmn.IR` contains **zero** occurrences of `SrcRange` today — a located `D-CYCLE` is free and
the calculus shifts, though not the conclusion. (ii) If a probe shows KIE _accepting_ a cyclic model
that `checkDrg` flags, the check is crying wolf; measured the opposite way on two engines.

#### 6.4.7 What R5 does not decide

- **The node population is R6's**, and it resolves by construction: `checkDrg` runs over whatever
  `Lower` emits, and §2.5.9 records that R6's filter is deliberately an emission decision in `Lower`.
  No blocking dependency in either direction.
- **R4 is untouched, and R2's residual risk (3) is not discharged here** — that is R4's.
- **R2 conflict, recorded rather than left implicit.** §2.4.3 spends a paragraph establishing that the
  **ruled** criterion certifies `ror together` **terminating and total**. R5 nevertheless flags it, in
  Phase 0, under §6.3.7. These are consistent — `DMN-SAFE` is about definedness, §6.3.7 is about DMN's
  own well-formedness `SHALL`, and a decision can be total and still ineligible to be a DMN node — but
  a reader meeting both without this sentence would reasonably think one of them wrong. **[E]** The
  practical reconciliation is that `ror together` is already `Blocking` today for an unrelated reason,
  so no decision changes hands.
- **Flavor.** **Not R7-flavor-sensitive at the decision level**: §6.3.7 is a spec requirement and
  **[E]** KIE 8.44 and Camunda 8.7.6 both reject an emitted cycle. **Possibly flavor-sensitive at the
  service level**, since whether the `camunda` flavor emits an _invocable_ `decisionService` is exactly
  R7's one bit — but §6.3.10 constrains the service's requirement subgraph whether or not it is
  invocable, so the check is the same. §14 records it.
- **The gate gap is named, not filled.** Nothing in `--fail-on` distinguishes "lossy but loadable" from
  "no engine will load this". A fifth severity, or `--fail-on=invalid` keyed to well-formedness notes,
  is the obvious shape; it is a CLI ruling.
- **`markdownReport` will not see this note**, because **[D]** it shadows the name `drgNotes` with its
  own list and never reads `drg.drgNotes`. Harmless _for this note_ — it emits `D-MD-NODRG` at
  `Blocking` whenever there are requirements, and a cycle implies at least two — but worth fixing as
  hygiene.
- **Half of Charities is unmeasured**, for the separate and possibly more interesting reason that one
  module takes >400 s to export. **[E]** Reconfirmed this pass.

#### 6.4.8 What review changed

Eight defects; the placement conclusion survived and two changed the ruling's content. **The SCC side
condition was missing and both defaults were wrong** — literal "one per SCC" emits 1068 notes,
"size ≥ 2" undoes the self-edge fix — so §6.4.4(3) now states it (D4); this is the same defect class as
R2's fixed point specified as `LEAST` when it had to be `GREATEST`. **And §6.4.6(i)'s own overturning
condition was already true on the record**: §2.3.2 says "split … **until** the graph is acyclic",
which is the fixpoint the ruling said would degenerate it — so §6.4.4(6) now requires the routine to be
callable from `Lower` mid-lowering (D6). Corrected without changing the ruling: (2) and (4)
contradicted each other about whether emission changes (D5); `Export.hs`'s guard is at 286-291 (D7);
the ruling's one `[U]` claim — the nullary self-recursive export — was executed by the review and is
now `[M]` rather than `[U]`.

**One reviewer finding is rejected on measurement, and it is the review's own headline.** D1 —
_"'a reachability break, not a corpus break' is false the moment the ruling is implemented; 72
decisions go from parseable to a whole-file parse failure"_ — is **arithmetically correct and measured
against an engine R7 has ruled out of scope.** **[E]** The 72 reproduce exactly in Camunda 7.23; on
KIE 8.44 and Camunda 8.7.6, the ruled targets, all four models already fail to build or parse **today**,
and all four self-recursive decisions are already `Blocking`. D2's corollary — "the expected golden delta
is zero, for a reason the ruling does not give" — is accepted in full: the delta is zero because
**[E]** the tree contains exactly one committed `.dmn` golden and it has no self-recursion, not because
the census showed 0 cyclic files. The census is blind to suppressed self-edges by construction, and
§6.4.4(2) no longer relies on it.

---

## 7. Fidelity notes

> **Re-rule this section against
> [`FIDELITY-SEVERITY-AXIS-SPEC.md`](./FIDELITY-SEVERITY-AXIS-SPEC.md) §5 before building any of
> it** (that spec's W9). Two consequences to read first. (1) The `D-PARTIAL` and `D-RENAME` rows
> below each assign **two severities to one code**; that is the effect axis smuggled into severity
> before it had a name, and it becomes one severity plus one `FidelityEffect`. (2) The `D-SCOPE`
> repurpose below would replace the predicate that is currently the tree's only detector of
> duplicate `inputData/@name` — measured TP=185 / FP=0 / FN=0 over 507 artifacts, 36.5% of DMN
> exports, not "universal". The type-conflict test may be **added** as a new, narrower code; the
> existing predicate must not be deleted until something else reports the duplicate, because DMN 1.3
> §7.3.4 makes that duplicate a violation of a normative `SHALL`.

| Code                 | Change                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Rationale                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `D-SCOPE`            | **Predicate and severity KEPT — the 2026-07-27 "repurpose" was overruled by FIDELITY W9 and the type-conflict test landed as the NEW code `D-PARAMTYPE` below (2026-07-31).** This predicate is the tree's only detector of DMN 1.3 §7.3.4's duplicate-`inputData/@name` `SHALL` violation (TP=185/FP=0/FN=0 over 507 artifacts) and stays exactly as shipped. What Phase 4 changed here, and only this: the `lost:` text now **branches on what collided** — "L4's lexical scoping of GIVEN parameters" was false when two global `ASSUME`s collide, and that arm now says what is actually lost (the distinct identity of two module-scoped globals). **Message rewritten 2026-07-29 (predicate and severity untouched):** it names both L4 spellings and the resolved FEEL names and handles 3+.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | **The merge makes this code fall quiet exactly where the hazard becomes real** — after merging there is one element per name, so nothing shares a FEEL name — which is why `D-PARAMTYPE` exists and is `Blocking`. Measured on `regcf-corpus`: D-SCOPE 9 → 7, the residue being groups containing a tier-2 or not-certified-total member whose parameter did not merge. The old last-wins `freeTermTypes` defect is fixed **structurally**: the Phase 4 group map is built with `Map.fromListWith` and consumed whole (`paramGroups`, `Lower.hs`), never `Map.fromList`.                                                                                                                       |
| `D-PARAMTYPE`        | **NEW, LANDED 2026-07-31 (Phase 4, W4; name ruled at build — OPEN-4).** `Blocking`. Two or more same-**L4**-named `GIVEN` parameters of un-lifted decisions whose **declared types differ**: the Phase 4 merge is **REFUSED** for that group — the parameters stay distinct elements exactly as before Phase 4 — and this note says so, naming every L4 spelling, every declared type spelling, every resolved FEEL name and every claimant decision, anchored to **every** claimant's element id (not only the first). **Merge key (OPEN-2, ruled at build): the verbatim L4 name, not the folded FEEL name** — two spellings that merely fold together are different parameters, kept apart by `uniquifyIn` and reported by `D-RENAME`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | §2.5.3's measured hazard: merging `s IS AN Article3Situation` with `s IS AN Article7Situation` (GCO) makes both engines answer `null` with status `SUCCEEDED` and zero runtime messages. `D-SCOPE` cannot carry this: it goes quiet at the moment of the merge. The A,B,A anti-regression (three claimants, two types, all named) is pinned by a test; the group map is `Map.fromListWith`, never last-wins `Map.fromList`.                                                                                                                                                                                                                                                                    |
| `D-PARAM-AS-INPUT`   | **LANDED 2026-07-31 (Phase 4)**, `Advisory`. A tier-1 decision's parameters became model inputs; the decision can no longer be applied twice to different subjects within this model, and the argument expressions at its call sites are discarded. **Granularity (OPEN-3, ruled at build): one note per merged `inputData` group of size ≥ 2**, naming the sharing decisions — that is where the loss is realised; a singleton parameter was already a global `inputData` before Phase 4, so a note there would be pure noise. 6 notes on `regcf-corpus` (not the predicted 9: three groups contain tier-2/not-certified members and did not fully merge).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Names what un-lifting costs, without pretending it is free.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `D-BKM`              | **LANDED 2026-07-31 (Phase 4, W9's report-only option)**, `Advisory`. A tier-2 decision is **classified as** a BKM candidate — not _became_: in Phase 4 it keeps its `<decision>` node and its call sites stay verbatim (`Blocking`-noted), and Phase 5's BKM emission is what changes behaviour. The note lists the callers applying distinct argument expressions. A golden test pins the unchanged behaviour and is the tripwire that goes red the day Phase 5 lands.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | The reader should know which decisions are functions, one phase before the emission changes.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `D-RECURSIVE`        | **New**, `Blocking`. §6.3 case 1.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `D-PARTIAL`          | **LANDED 2026-07-31 (Phase 4)**, two severities, **keyed off the call site and not off the node kind** (§2.4.2). `Lossy` when every call site consumes the decision from a _lazy_ position; `Blocking` when any call site consumes it strictly, and when it is a DRG root. Names the failing clause (L1–L12 / `PURE` / `DETERMINISTIC` / `TERMINATES`) and its range, says _not certified total_ rather than _partial_, and never offers `@nonexhaustive` as a remedy. Per §2.4.2's OPEN-1 ruling the node kind does NOT change in Phase 4 — the decision keeps its `<decision>` and verbatim call sites; the "inlined or emitted as a BKM" wording is Phase 5's. **Migration obligation:** when `FIDELITY-SEVERITY-AXIS-SPEC` W1/W2 lands, the two severities collapse to one severity + one `FidelityEffect`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | §2.4. Not decision-node-ness: an undefined FEEL result is `null` wherever it arises — `<decision>` body, BKM `encapsulatedLogic`, or inlined cell alike — and `null` reads as `false` at the first boolean consumer. Routing to a BKM removes the input _widening_; only a lazy consuming position removes the _coercion_.                                                                                                                                                                                                                                                                                                                                                                     |
| `D-SUMTYPE`          | **LANDED 2026-07-29 (Phase 3)**, **two severities** (§4.2.1). `Blocking` on a decision that _reads_ a user-declared payload-carrying `IS ONE OF` — payload-field projection, payload-constructor construction, or a `CONSIDER` with a payload-binding arm — propagated to its callers. `Lossy` on a decision that `CONSIDER`s one over its _nullary arms only_, naming the constructors with no cell, and on a decision that merely threads a record containing one. Names the type, the constructor and the reading site.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | §4.2.1. Reported **before** `D-LITERALEXPR`, which otherwise misdiagnoses the same decision as "not a guarded chain". ~~Does **not** fire on builtin `MAYBE`/`EITHER` (R8).~~ **SUPERSEDED 2026-07-29:** R8-d and R8-e put both inside it — a decision that constructs `JUST`/`NOTHING`/`LEFT`/`RIGHT`, or whose `CONSIDER` scrutinee is a `MAYBE`/`EITHER`, is `Blocking`, and so is a nested `MAYBE` at a boundary (R8-c). Propagation along `calls` is **not** built; see §4.2.1-8 for why and where it goes. The `Lossy` arm exists because the emitted table is _correct_ — measured in KIE 8.44 — while its _domain_ is not: the payload constructor has no cell and no `allowedValues`. |
| `D-MAYBE-NULL`       | **New 2026-07-29 (Phase 3)**, `Lossy`. R8-a/R8-b. One per element whose `MAYBE τ` was lowered to τ's own `typeRef` — a decision's `<variable>`, an `inputData`'s, a column's, an `itemComponent`'s. Names the L4 type, says FEEL has one `null` for both "there is none" and "it could not be computed", and — when τ is a **named** type with a finite domain — that no `allowedValues`/`inputValues` is emitted **at this element** and that the element therefore points at a minted **domain-free alias** `<τ>_optional` rather than at τ itself. ~~that the domain was **dropped**~~ **CORRECTED 2026-07-30 (twice): the range is read through the `typeRef`, so suppressing it at the element alone was defeated one hop away — an answer change, repaired in the artifact by §11-R8-a's carve-out rather than in the note.** The note names the alias and τ, and reports what the alias costs: at that element an engine no longer validates the values that **are** present. See §11-R8-a and §11-R8-b. **AMENDED 2026-07-31 (R8-d′): the null lowering is now ADOPTED rather than hypothetical** — `NOTHING` lowers to FEEL `null` on the value channel, so the absence-vs-undefined conflation this note reports is a price paid deliberately, and the note's message says so. The `lost:` clause is unchanged: that distinction is exactly what is still lost. | §11-R8. The output clause has no site of its own because this emitter emits no `typeRef` on an `<output>` (measured: KIE says `ILLEGAL_USE_OF_TYPEREF`), so a `MAYBE`-typed output is reported at the decision's `<variable>`. **Explicit and mandatory rather than silent**, because once `NOTHING` is spelled `null` no reader and no analyser can recover which channel was meant.                                                                                                                                                                                                                                                                                                          |
| `D-COMPUTEDFIELD`    | **New 2026-07-31 (§4.4)**, `Advisory`. One per hydrated **type**, on the hydrated `itemDefinition`. Names the derived components and says DMN cannot mark them derived: `tItemDefinition` has no such flag and a `contextEntry` is indistinguishable from a supplied value, so a reader of the hydrated type alone cannot tell a derived component from a stored one.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | §4.4.6. Advisory, not Lossy, and the severity is the claim: nothing an **engine** needs is missing, because hydration means no caller ever supplies a derived component. What is lost is legibility of the type, not correctness of the model. `FIDELITY-SEVERITY-AXIS-SPEC.md` §3.2 binds Advisory to `Faithful`. Component-level notes (`D-MAYBE-NULL`, `D-ITEMDEF`) fire on the **base** definition only, or every one of them would double.                                                                                                                                                                                                                                                |
| `D-MD-NOCONTEXT`     | **New 2026-07-31 (§4.4)**, `Blocking`, dmnmd only. A hydrator is a boxed **context**, and dmnmd can say a decision over cases and nothing else, so the decision is omitted from the markdown. Names the component count.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | §8. Its **own** code rather than a widening of `D-MD-NOLITERAL`: that note's message says "is a formula", which is false of a context, and it is a separately counted code in `FIDELITY-SEVERITY-AXIS-SPEC.md` §5.2 — widening it would make one line of that table describe two different losses. What it costs is larger than a literal's: the tables downstream read derived components _through_ the omitted decision, so in the markdown those reads name a decision that is not there.                                                                                                                                                                                                   |
| `D-ITEMDEF`          | **New 2026-07-29 (Phase 3)**, `Lossy`. One code, three reasons: a **computed** record field was skipped; a field or element type is declared in **another module**, so no `itemDefinition` could be minted and it is typed `Any`; a `LIST OF τ` has no `itemDefinition`, because `isCollection` is an attribute of `tItemDefinition` and needs one of its own.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | §4.1, §4.2. **[E]** The computed-field reason has **zero exercise** and the reason is worth knowing: `L4.Desugar` rewrites a computed field into a synthetic top-level `DECIDE` **before type checking**, so the `Declare` the exporter sees never carries one — the field is relocated to a `<decision>` reading a `_self` `inputData`, not dropped. The arm is kept for the reason `D-FEELNAME`'s is (below). The other two fire 10 times on `regcf-wizard.l4`.                                                                                                                                                                                                                              |
| `D-RENAME`           | **LANDED 2026-07-29, collision arm only**, `Lossy` — the condition is discharged, because `uniquifyIn` now makes the names distinct (§5.2 stage 2). One note per element whose FEEL name was suffixed, naming the L4 name, the resolved name and the other claimants on the base. 37 instances on the Reg CF corpus. **The benign-mangle `Advisory` arm is NOT built**, and stays deferred to this section's own re-ruling against `FIDELITY-SEVERITY-AXIS-SPEC.md` §5: it would emit ~169 `Advisory` notes on one module while `@label` already carries the source name.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | §5.2, §5.3.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `D-FEELNAME`         | **Landed on PR #160** (R7), `Blocking`. Two or more DRG elements share one FEEL name. R3's proposed extension to the record-field / projection-path namespace was **superseded 2026-07-29 rather than built**: `uniquifyIn` covers that namespace too, so the projection collision is now renamed apart and reported by `D-RENAME`. **Code, severity and predicate are unchanged, and it now fires zero times by construction** — kept, per this section's header, because nothing else reports a duplicate `inputData/@name`, which DMN 1.3 §7.3.4 makes a violation of a normative SHALL. A test pins the count at 0 on `regcf.l4`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | §5.3.4. `(p's \`foo bar\`) PLUS (p's foo_bar)`emits`p.foo_bar + p.foo_bar` under the ruled fold — a wrong number, unreported.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `D-CYCLE`            | **New**, `Blocking`. §6.4. One per SCC of the `informationRequirement` graph, side condition `\|SCC\| ≥ 2` **or** `\|SCC\| = 1` with a self-edge. Names every member by **name and id**; `range = Nothing`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | DMN 1.3 §6.3.7. KIE reports `Cyclic dependency detected` and skips; Camunda 7 and Camunda 8 refuse to parse.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `D-FIXTURE`          | **LANDED 2026-07-31 (Phase 4)**, `Advisory`. §2.5.6-2. Names every decision not emitted because it is test scaffolding (or its fixture-side helper closure), so the omission is visible in the artifact rather than inferred from absence; `--include-tests` restores them with no note. A third form fires when conjunct (d)'s importer view is unavailable: the decision is KEPT and the note says (d) was **not checked** — report-only, per §2.5.7's fail-safe.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | §2.5. The filter is a measurement about four corpora, not a soundness property; it must never be silent.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `D-INERT`            | **LANDED 2026-07-31 (Phase 4)**, `Advisory`. §2.5.6-4. A decision that carries statutory text and no operative logic, kept. Predicate: **the body forces no reference and no input** — implemented as "no reference in the body survives to a decide edge or a free term", not "the body is a literal", which misses the corpus's dominant `\"text\" ... TRUE` idiom.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | §2.5. Stops a reader mistaking a tautology for a rule. 12 decisions in 5 of the 51 exported modules emit the body `true and true`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `D-REGULATIVE`       | **LANDED 2026-07-31 (Phase 4)**, `Lossy`. §2.5.6-3. An **uncalled** regulative body belongs to the BPMN artifact (§12), not to a fake decision emitting raw L4, and is not emitted; a module-called regulative body stays in the DRG, still emitting raw L4 (§2.4.2's and §6.3-1's problem, not this rule's). Drops to `Advisory` once PR #141 gives it a target to point at.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | §2.5. Today `ground 8 possession order` emits raw L4 and fails KIE with `Unknown variable 'IF'`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `D-MD-FLATRECORD`    | **New**, `Lossy`, markdown carrier only. §8.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `D-RULEDATE`         | **New 2026-07-30 (Phase 3.5)**, `Advisory`, **one severity**. §15.5. Exactly one per DRG: the rule-date `inputData` was emitted, and these named decisions depend on it. An unbound `RULES_EFFECTIVE_DATE` is a well-formed DMN model that answers null in every dated decision, and before this the report was silent about it.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `D-RULEDATE-UNBOUND` | **New 2026-07-30 (Phase 3.5)**, `Blocking`, **one severity**. §15.5. One per decision that rebinds law time with `EVAL UNDER RULES EFFECTIVE AT`. A DRG has one global rule-date input and no scoped rebinding, so supplying that input does not make the decision answer. Fires 15× on the Reg CF corpus.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `D-DATEDCHAIN`       | **New 2026-07-30 (Phase 3.5)**, `Blocking`, **one severity**. §15.3, R10. One per chain of rule-date guards that could not be lowered to a date-interval table (mis-ordered or duplicate dates, an unfoldable date, or a mixed chain). The sound fallback still ships, and it is columns of raw L4 no engine can evaluate — which is what `Blocking` means here.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

---

## 8. The markdown carrier

### 8.0 `D-MD-NOCONTEXT`, and what R8-d′ did to `D-MD-NOLITERAL`

**Added 2026-07-31.** A hydrator is a boxed **context**, and dmnmd has no boxed-context form — it
can say a decision over cases and nothing else — so `renderDecision` returns `Nothing` for it and
`D-MD-NOCONTEXT` (`Blocking`) discloses it. Its **own** code rather than a widening of
`D-MD-NOLITERAL`, for the reason in §7's table: that note's message says "is a formula", which is
false of a context, and it is a separately counted code in `FIDELITY-SEVERITY-AXIS-SPEC.md` §5.2.

The cost it reports is larger than a literal's, and it says so: downstream tables read derived
components **through** the omitted decision, so in the markdown those reads name a decision that is
not there.

**What R8-d′ did to `D-MD-NOLITERAL`, VERIFIED against the code rather than presumed.**
`renderDecision` returns `Nothing` for **any** `LogicLiteral` and `decisionNotes` raises
`D-MD-NOLITERAL` for **any** `LogicLiteral`; neither consults the `FeelFragment`
(`jl4-core/src/L4/Dmn/Markdown.hs`). So the hypothesis worth checking — "a formula decision is still
not a table, so it is still omitted and still disclosed" — **is confirmed**, and it is the right
answer for the decisions that stayed formulas: both spellings of `grade is settled` remain
`LogicLiteral` and remain `D-MD-NOLITERAL`, with the interpolated text changing from L4 source to
real FEEL (`if p != null then true else false`).

But the premise does not hold for `capped at ten`, and the golden is what settles it: under R8-d′
that decision **becomes a table**, so it leaves `D-MD-NOLITERAL` altogether.

**What it lands on took two attempts, and the first one was wrong — recorded rather than
overwritten, because the wrong answer is the one a reader would reach on their own.**

- _First attempt._ The table rendered, picking up `D-MD-NODEFAULT` (`Lossy`) — dmnmd has no
  `<defaultOutputEntry>`, so the absent case becomes a final catch-all row and the hit policy
  degrades U → F. That was recorded here as "a strict improvement in the markdown carrier". **It
  was not one.** `expressible` checked the rules and not the default entry, and `defaultRows` fell
  back to `fromMaybe "-"`; FEEL `null` is `FullFeel` by design and `mdOutput` refuses it, so the
  catch-all printed `| 2 | - | - |`. In dmnmd `-` is the **input** column's "any" token, so the
  markdown said "output unspecified" where the DMN said `null` — and the only disclosure beside it
  was `D-MD-NODEFAULT`, whose message is about the hit-policy demotion and whose row in
  `FIDELITY-SEVERITY-AXIS-SPEC.md` asserts "the answers are preserved". A **loud omission**
  (`D-MD-NOLITERAL`, Blocking, decision absent) had been traded for a **quiet misstatement**.
- _Landed._ `expressible` now also asks `mdOutput` of `ocDefault`, so such a table is **omitted**
  and routed to `D-MD-CELLSYNTAX` (`Blocking`) — the same standard `mdConstant`'s own haddock
  already sets for a date ("Returning `Nothing` routes the whole table to `D-MD-CELLSYNTAX`
  Blocking and omits it honestly"). The note names the OTHERWISE text, `defaultRows` no longer
  carries a `fromMaybe "-"` at all, and `D-MD-NODEFAULT` correctly does **not** fire, because the
  table is not there to have had its hit policy demoted. Pinned by "omits a table whose OTHERWISE
  dmnmd cannot say" in `jl4/tests/DmnExport.hs`.

So R8-d′'s effect on the markdown carrier is: **no change** for the decisions that stayed formulas,
and for a `MAYBE`-valued decision that now tabulates, a Blocking omission with a **different and
more accurate** reason than before. Not an improvement — an equally loud loss, honestly named.

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
  JDK only). Without it a misordered emitter passes CI (§4.3).
  **DONE** — `etc/kie-dmn-check`'s leg 1 is that check.
- **A negative golden** `M1-itemdef-after-inputdata.dmn`, precisely because it is the case the
  obvious validator misses. **DONE 2026-07-29**, as a matched pair with a positive control at
  `jl4/tests-cli/fixtures/dmn-xsd-order/`; see §4.3 for the measurements, including the one that
  corrected this plan's own "fails in every real engine" wording — Drools/KIE 8.44 builds and
  evaluates the misordered file correctly, and only its schema legs object.
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

| Phase   | Content                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Depends on |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| **0**   | Kill the dot passthrough in `feelIdentText` (§5.1-1). Fix `drgNamed`'s type-error hole (§9). Add the Xerces check. **+R5 (§6.4):** `checkDrg` + `D-CYCLE`; delete `freeRefs`' own-name binding and `classifyRef`'s self-edge filter. Independent of every other phase, ~40 lines, and the expected golden delta is zero — the tree has exactly one committed `.dmn` golden and it has no self-recursion (§6.4.8).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | —          |
| **0.5** | **LANDED 2026-07-31 (vendored).** PR #45's exhaustiveness oracle (`constructorsInScopeFromEntityInfo`, `@nonexhaustive`) merged onto the Phase 4 line as commit `904192ea` — by vendor merge, not ancestry, because the oracle was REVERTED on `origin/main` 2026-07-13 (`8a8b46bc` ancestry is no longer the right probe). Hard prerequisite for §2.4's L1 and L2; without it the totality criterion is vacuous outside same-file top-level enums.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | —          |
| **1**   | Columns: `typeRef` + `<inputValues>` / `<outputValues>` from L4's known domains (§3).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | 0          |
| **2**   | Naming policy: `feelBase` + `uniquifyIn`, `@label` everywhere, `feelTypeNameText` (§5.2). **+R3 (§5.3):** step 3 folds to ASCII; the element-`name`/`variable`-`name` invariant; `uniquifyIn`'s scope widened to projection paths, `decisionService` names and BKM `formalParameter` names. **`feelBase` and the invariant landed on PR #160** (R7); **the residue landed 2026-07-29 except NFC** — the reserved-word suffix, `feelTypeNameText`, `uniquifyIn` over the DRG variable namespace **and** the projection-path namespace, the resolved name carried on the IR rather than recomputed in `Emit`, and `D-RENAME`'s collision arm. The hard sequencing constraint (**`uniquifyIn` may not lag the fold**, §5.3.4) is therefore discharged. **Still open in this phase:** step 1 (NFC), deferred with its measurement in §5.3.3, and `uniquifyIn`'s two unemitted scopes — `decisionService` names and BKM `formalParameter` names — which arrive with their emitters in Phase 5.                                                                                                                                                                                                                                                                                                                                               | 0          |
| **3**   | **LANDED 2026-07-29.** `itemDefinition` emission and placement; records and enums at the data level (§4). **+R4 (§4.2.1):** R4-c, the constant-ref defect; `D-SUMTYPE`'s two arms; a golden pinning the `Lossy` nullary-only arm. **+R8: ANSWERED**, see §11-R8 — the leaning survives on the _type_ channel (R8-a/b) and dies on the _value_ channel (R8-c/d/e), and R8-f's `NOTHING`-as-`"NOTHING"` defect ships regardless. New goldens `sumtype.{dmn,dmn.md,fidelity.txt,md.fidelity.txt}`. Column-level `inputValues`/`outputValues` (§3.1, §3.2, nominally Phase 1) rode along, because the enriched classifier answers both questions in one walk.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | 2          |
| **3.5** | **LANDED 2026-07-30.** Law time: the rule-date `inputData` (D1), date-interval tables and the FEEL date literal (D2), and the `D-RULEDATE` / `D-RULEDATE-UNBOUND` / `D-DATEDCHAIN` codes (D3). **+R9** (§3.3's third spelling), **+R10**, **+R11** (§15). Independent of Phase 4 and Phase 5.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | 3          |
| **3.6** | **LANDED 2026-07-31.** Hydration (§4.4) and `MAYBE`→`null` (§11-R8-d′), in one change. Computed record fields lower as boxed-context entries computed from earlier siblings, downstream reads become path access, and the DRG rewires so the graph says what the expression says (R11 again). `NOTHING` → FEEL `null`, `JUST x` → `x`, `CONSIDER`-on-`MAYBE` → `if … != null then … else …`, `isJust`/`isNothing` recognised by prelude `Unique`. New codes `D-COMPUTEDFIELD` (Advisory) and `D-MD-NOCONTEXT` (Blocking). New golden subject `hydration`. **Prerequisite of its own engine legs, and it was built first:** both harnesses needed a null carve-out, because a decision answering `null` was scored a failure by construction on both — so before it, the only green cases would have been ones that avoided the absent branch. Independent of Phase 4 and Phase 5.                                                                                                                                                                                                                                                                                                                                                                                                                                                       | 3, 3.5     |
| **4**   | **LANDED 2026-07-31.** The un-lifting analysis (`L4.Dmn.Analysis`: one call graph, `cgCalls`/`cgDirective` polarity split) and its totality side-condition (`DMN-SAFE`: L1–L12, `PURE`, `DETERMINISTIC`, structural `TERMINATES`; greatest fixed point). The name-keyed parameter merge with type-conflict refusal — `D-SCOPE` **kept, not repurposed** (W9); the conflict is the NEW `Blocking` code **`D-PARAMTYPE`**. `D-PARAM-AS-INPUT` (per merged group ≥ 2), `D-PARTIAL` (call-site-keyed severities; node kind unchanged per §2.4.2's OPEN-1 ruling), `D-BKM` (W9's report-only tier-2 classification) (§2.1, §2.4, §7). **+R6 (§2.5):** the population filter and `D-FIXTURE` / `D-INERT` / `D-REGULATIVE` off the same graph; `--include-tests` (default off); conjunct (d) = sibling scan, failing safe (§2.5.7). Obligations: the ninth-constructor tripwire test SHIPPED (`DmnExport.hs`); L11's synthetic accepting/rejecting pair SHIPPED; the post-filter census re-run and the `D-SUMTYPE` closure measurement are recorded in §14.4 with what was and was not run. New golden subject `unlift`; `regcf-corpus` moved 66→37 `inputData`, D-SCOPE 9→7, D-LITERALEXPR 89→80, and KIE went from `Compiled model is null!` (nothing loads) to a node-by-node build with 37 residual verbatim FEEL errors — Phase 5's work. | 3, 0.5     |
| **5**   | BKM emission, `knowledgeRequirement`, the three refusals (§6). **+R5:** `checkDrg` extends to the `knowledgeRequirement` graph; `D-RECURSIVE` (§6.4.4-5), which discharges §6.3-1. **+R4-b (earliest slot):** the tagged-union encoding may ship as `Lossy` once L11 and the tag-guard invariant exist **and** the missing-payload-component obligation (§4.2.1-3) is discharged.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | 4          |
| **6**   | Markdown carrier: flattening + `D-MD-FLATRECORD`; dmnmd addendum (§8).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | 3          |

Phase 1 alone makes the existing exhibit's analysability claim true, which is worth shipping on
its own.

**Amended 2026-07-27 by R7 — see §13.7 for the added rows.** In summary: Phase 0 grows the uniform
`feelBase` fix (which is now a correctness fix, not a portability preference), the two committed
engine harnesses, and the `DmnFlavor` seam; Phase 2 loses its flavor branch, because naming was
measured not to diverge; Phase 5 gains the one bit that does diverge and is where the goldens
split. **Phase 0's naming item was a red gate — the shipped golden failed both engines — and it
landed 2026-07-27; both harnesses are green on both flavors (§11-R7, §13.7).**

**Amended 2026-07-30 by R9, R10 and R11 — see §15.** Phase 3.5 is independently shippable: it
touches columns and cells (Phase 1's territory) but ships after Phase 3 because it emits
`annotation` elements, whose XSD position is a sequence question of the same kind §4.3 settled for
`itemDefinition` — and, as there, only Xerces is watching it, which is why
`jl4/tests-cli/fixtures/dmn-date-probe/` is a permanent hand-written fixture rather than a golden.

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
  **L11 and §4.2 — updated 2026-07-27 when R4 was ruled.** For **user-declared** unions R4-a's
  first reading form _is_ L11's subject: a payload-field projection is `Blocking` at the decision,
  which drives L11's single-decision traffic to zero by construction. What survives is (i) the
  **builtin** open sums, `MAYBE` and `EITHER`, which R4 deliberately does not rule — see **R8**;
  and (ii) R4-b's cross-decision guard/use split, where the guard lives in the caller and the read
  in the callee. L11 must still stand on its own inside `LOCALLY-TOTAL`, because §4.2's note is
  type-scoped where L11 is decision-scoped, only 6 of the 41 union-touching decisions have the type
  at a boundary at all, and inexpressibility and unsoundness are different severities (§4.2.1-4).
  **Neither residue blocks #923** (§0): L11 does not consult §4.2, and `MAYBE`'s payload is not
  projectable at all, so `MAYBE` reaches `LOCALLY-TOTAL` only through L1.

- **R3 — Unicode in `feelBase`. ANSWERED 2026-07-27, see §5.3.** **Fold — and the leaning was
  wrong.** The corpus exposure to the question R3 asks is **zero**: of 2 930 non-ASCII characters
  reaching a FEEL name across 639 files, **every one is U+2014 EM DASH**, which is FEEL-illegal, which
  every engine rejects, and which the existing fold already maps to `_`; the FEEL-**legal** cell is
  `0 | 0`. And the "keep" arm's justification — _spec-legal_ — failed as a predicate on the first
  character tested: KIE 8.44 **rejects** `’`, which grammar rule 30 explicitly permits, and **accepts**
  ASCII `'`, which no rule permits. So §5.2 step 3 keeps `[A-Za-z0-9]` and maps everything else to
  `_`; no transliteration, no keep-flag, no per-engine allow-list to maintain. **R3 has already
  shipped**, independently, as R7's naming fix on PR #160 — which is corroboration, not agreement, since
  R7 got there from Camunda tokenising `annual income` as `annual in come` and answering a boolean.
  **R3 also owed a normative sentence it had not written, and its absence had teeth:** element `@name`
  == `<variable>/@name` == the folded name, verbatim only in `@label` — without it the committed golden
  `reg-cf.dmn` **does not build in KIE on this branch** (`syntax error near 'issuer'`), and does build,
  clean, on PR #160. **Prerequisite, not preference:** folding _is_ the collision-generating step, so
  `uniquifyIn` may not lag it — the one executed corpus collision is
  `(p's \`foo bar\`) PLUS (p's foo*bar)` emitting **`p.foo_bar + p.foo_bar`**, a wrong number, with no
note, in the projection namespace `D-FEELNAME` does not yet cover. \*\*Flavor-independent, and R3 \_is*
  the Camunda naming fix** (§14). **Depends on R1\*\* — `§` names become FEEL names under §2.3, which the
  exposure scan could not see. Does not touch R2's residual risk (3), R4, R5 or R6.

- **R4 — Tagged unions. ANSWERED 2026-07-27, see §4.2.1.** Refusal — but **narrower than the leaning,
  on the decision rather than the type, at two severities, and not for the reason the leaning gave.**
  _"The corpora do not need it" is false and is struck_: 3 payload-carrying `IS ONE OF` types, 41
  decisions (2.7%), 5.2% of Housing, in Grounds 1A/1B/2ZD — the corpus's only worked examples of a
  statutory alternation carrying operative data. `D-SUMTYPE` is **`Blocking`** on a decision that
  _reads_ such a union (payload-field projection, payload-constructor construction, or a `CONSIDER`
  with a payload-binding arm), propagated along `calls`; **`Lossy`** on a nullary-only `CONSIDER` and
  on a decision that merely threads the record. **The number that forced the narrowing:** the earlier
  draft refused all 13 reading decisions and priced it at 6 incremental refusals; the true figure is
  **2**, and the 2 are `is a sale of a freehold or leasehold interest` and `is a grant of an assured
tenancy to another person` — **2 of the 12 decision tables the entire 51-file export yields**, which
  build with **0 messages** in KIE 8.44 and answer correctly on all three constructors. The genuinely
  unsound shape is non-exhaustive-**without**-`OTHERWISE`, and a fresh probe shows it is **byte-identical
  for a plain nullary enum** — both emit a note-free table, both report `(nothing lost)`, both return
  `null [SUCCEEDED]` in KIE, while `l4 check` warns on both. That is **R2's L1**, not R4's.
  **Discharges R2's residual risk (3) for user-declared unions** and names the residue. **Opens R8.**
  v1 is flavor-independent; R4-b's encoding is not (§14).

- **R5 — Acyclicity. ANSWERED 2026-07-27, see §6.4.** **The premise was false, not merely the
  leaning:** L4 **does** admit forward references among top-level `DECIDE`s
  (`specs/done/SECTION-LEXICAL-SCOPING-SPEC.md:435` against a stale `TypeCheck.hs:30-34`), and **6 of 9
  one-line probes emit a cyclic DRG today** — mutual recursion, a `WHERE`-local cycle, one across two
  `§`s, one through a guard, a 3-cycle. The guard-position probe exports with **`(nothing lost)`** and
  is rejected by KIE 8.44, Camunda 7.23 and Camunda 8.7.6 alike. **Ruling: a well-formedness check on
  the finished IR — `checkDrg :: Drg -> [FidelityNote]` in `L4.Dmn.IR`, folded into `drgNotesAll`;
  `D-CYCLE`, `Blocking`, one per SCC (`|SCC| ≥ 2`, or `= 1` with a self-edge), naming every member by
  name _and_ id; emitted unchanged, never repaired.** One SCC routine serves all three of DMN's
  acyclicity clauses — §6.3.7 (decisions, now), §6.3.9 (BKMs, Phase 5, discharging §6.3-1's forward
  reference to R5), §6.3.10 (services, §2.3.2, where repair _is_ honest because that cycle is our
  granularity choice and not the source's) — and because §2.3.2's splitter is a fixpoint, the routine
  must be callable from `Lower` mid-lowering. **The soundness half:** `freeRefs` binds a decide's own
  name and `classifyRef` filters `target /= did`, so a decision requiring _itself_ — the case §6.3.7
  names first — cannot appear in a `Drg` at all, and KIE then answers **`null` reported `SUCCEEDED`**
  while catching the two-node version of the same defect. Both filters go. **Cost of that, on the
  ruled target pair: zero** — the 4 corpus models containing a self-recursive decision already fail to
  build in KIE and fail to parse in Camunda 8 **today**, and all 4 decisions are already `Blocking`;
  the review's 72-decision figure is real and is measured in **Camunda 7, which R7 rules out of scope**
  (§6.4.8). Ships in **Phase 0**; **does not block #923**. Not a recursion detector: `Proj`-mediated
  edges, intra-decision `WHERE`-local recursion (§2.4.1's L12) and cross-module callees are invisible
  to it by construction.

- **R6 — The uncalled population. ANSWERED 2026-07-27, see §2.5.** **R6's own numbers do not reproduce
  and its premise is false.** Re-measured, the uncalled rate is **61.6% / 46.6%** of all decisions and
  **36.0% / 16.0%** of parameterised ones (Charities / Housing), not 44% / 18% — no scope, denominator
  or directive-counting variant yields R6's figures. And a parameterised uncalled decision **does**
  have a supplied input: `Lower.hs:1554-1577` already synthesises one `inputData` per `GIVEN`, and the
  result evaluates correctly in KIE 8.44 **and** Camunda 8.7.6. So the question is not emit-or-drop but
  **which of four populations**. Ruled: **keep** the 141 uncalled DMN roots and make them their
  `§`-service's `outputDecision`s; **do not emit** the 574 test fixtures and their 194-decision helper
  closure, behind `--include-tests` defaulting off with a `D-FIXTURE` per dropped decision (measured:
  it removes **10** of the 18 errors that stop a real corpus module compiling in KIE); **route** the 137
  uncalled regulative bodies to BPMN with `D-REGULATIVE`; **keep** the inert stubs with `D-INERT`,
  whose predicate is widened from "the body is a literal" (19 decisions) to "the body forces no
  reference and no input" (≥58), because the corpus's dominant idiom `"text" ... TRUE` parses as `And`.
  **The repair that changes emission:** un-lifting must **not** merge two same-named parameters of
  **different declared types** — GCO binds `s` at `Article3Situation` and `Article7Situation`, and the
  merge answers `null [SUCCEEDED]` in both engines — so §7's repurposed `D-SCOPE` is raised to
  **`Blocking`**, and it has to be, because R7's `D-FEELNAME` catches this today only by counting the
  N elements un-lifting is about to collapse. **The repair that saves a statute:** the fixture criterion
  needs a fourth conjunct, _no caller in any importing module_, or it drops
  `` `relevant date` `` — Sch. 2 para. 12 — which is module-uncalled, directive-referenced only in
  argument position, and called from Grounds 2ZA, 2ZB and 5F whose own artifacts carry a **dangling**
  reference to it. `itemDefinition` is **scheduled, not gating**. Flavor: the `outputDecision` link is
  structurally flavor-independent but its §2.3 payoff is `kie`-only (§14).

- **R7 — Target engine. ANSWERED 2026-07-27, revised the same day under review, see §13.** Camunda is a target, and so is KIE: the
  exporter emits **two flavors**, `camunda` (default) and `kie`, and both are driven through a
  real engine in the test suite. But the flavor axis is **one bit wide, not three** — of the three
  axes the issue proposed, measurement retired two.

  **Axis 1, naming — NOT a divergence.** Exactly one policy is clean-and-correct on all three
  engines measured (KIE 8.44.0.Final, Camunda 7.23/7.24, Camunda 8.7.6): §5.2's `feelBase` applied
  **uniformly** to the node `@name`, the `<variable>` `@name` and every FEEL reference, with
  `@label` carrying the verbatim L4 name. The appearance of a divergence was two of our own bugs
  wearing one coat (§5.1-4, §13.2). The alternative that looked engine-specific — backtick-escaping
  the reference — is a **Camunda-only extension** and is a hard KIE compile error (`syntax error near` the backtick), so
  it is not a flavor either; it is simply wrong. §5.2 becomes a shared fix, not a knob.

  **Axis 2, BKM — NOT a divergence on the ruled target pair.** KIE and Camunda 8 both execute
  BKMs in every probed form (literal-invoked, `<invocation>`-boxed, table-bodied, hyphen-named,
  invoked from a table's `inputExpression` and `outputEntry`). Only **Camunda 7** lacks BKM, and
  silently — a BKM call evaluates to `null`, and an `<invocation>`-bodied decision is dropped from
  the model entirely. Camunda 7 is not the target (§13.1). §6.3-3's gating survives as a refusal
  keyed to `@hbtgmbh/dmn-eval-js` and C7, neither of which is a flavor we emit for.

  **Axis 3, `§`-as-`decisionService` — THE divergence, and narrower and sharper than supposed.**
  A bare `<decisionService>` is inert-but-safe everywhere. The bit that actually splits is
  `<knowledgeRequirement><requiredKnowledge href="#a-decisionService"/></knowledgeRequirement>` —
  the edge §2.3.1 marks **mandatory**, without which the service's name is not in FEEL scope and
  §2.3's whole `every q in c.purposes satisfies Article 6(q)…` payoff is unspellable. KIE compiles,
  validates and executes it. **Camunda 8 throws `ClassCastException: DecisionServiceImpl cannot be
cast to BusinessKnowledgeModel` inside `parse()` and rejects the entire DRG**, including
  decisions that have nothing to do with the service. Deleting that one element makes the same file
  parse and evaluate. So the knob is: **may a `decisionService` be invocable?**

  **Default is `camunda`,** from where artifacts are consumed and from the failure asymmetry.
  `specs/todo/lexipedia-superset/SPEC.md` K4 commits the BPMN side to Camunda Modeler import and
  says outright that "Camunda remains _the_ audience, because their authoring flow is Camunda
  Modeler → paste XML; KIE is a correctness instrument". A DMN file that user cannot open breaks
  the pairing. And the two flavors fail unequally on the other engine: the camunda flavor on KIE is
  **degraded but sound** (the service survives as grouping, every decision still validates and
  evaluates — measured), whereas the kie flavor on Camunda is **catastrophic** (nothing in the file
  loads). Default to the flavor whose wrong-engine failure mode is "less structure", not "nothing".

  **Honest scope note.** Neither `decisionService` nor BKM is emitted today, so **on today's
  emitter the two flavors are byte-identical** and `--flavor` changes nothing. It lands now because
  the seam, the goldens and the two harnesses are what make Phase 5 checkable; §13.6 pins the
  byte-identity as a test so the day it stops being true is visible rather than silent.

  **Prerequisite — was red, fixed 2026-07-27, now green.** The shipped golden
  `jl4/examples/dmn/expected/reg-cf.dmn` used to fail in **both** engines — KIE: 2 validator errors
  and a `KieBuilder` build failure, undeployable; Camunda 8: rejected at `parse()`. §13.2's naming
  fix was therefore a hard prerequisite for wiring either checker green, and it moved the golden.
  Both failures were reproduced from the committed harnesses before the fix and again from
  `git show origin/unstable:…/reg-cf.dmn` afterwards, so the red gate is itself regression-tested
  rather than merely remembered. Current state, both flavors, from the committed harnesses:

  ```
  KIE 8.44.0.Final VERDICT: 1 file(s), 5 case(s), 0 error(s), 0 warning(s), 25/25 decision(s) SUCCEEDED, 25/25 value(s) as expected
  Camunda 8.7.6 (zeebe-dmn) VERDICT: 1 file(s), 5 case(s), 1 parsed, 0 error(s), 25/25 decision(s) evaluated, 25/25 value(s) as expected
  ```

  This is also the direct answer to why the harness must be committed. `spec:124`'s "KIE validator
  clean" is **not reproducible**, and that — rather than "it was true and rotted" — is the
  supportable claim: the run behind it was never committed, so there is no state of the tree in
  which anyone can re-derive it. An uncommitted measurement is indistinguishable from one that was
  never taken, which is the entire argument for `etc/kie-dmn-check/` and `etc/camunda-dmn-check/`
  existing at all.

  **What review changed, recorded so it is not un-changed by accident.** The ruling stands; seven
  defects around it did not, and all are repaired in place. (1) Both harnesses checked **liveness,
  not answers** — `5/5 SUCCEEDED` passes a file that answers `true` where a number was meant, which
  is precisely the Camunda misparse. They now take `--cases` and compare **expected values**, both
  engines, 25 values over 5 contexts, symmetric in both directions (an unexpected decision and an
  unmatched expectation are each a failure). (2) The Camunda banner **echoed** its version from a
  shell variable; it is now read off the jar's implementation version and cross-checked against the
  pom pin, on both harnesses, and asserted in CI and in `l4-cli-test`. (3) `--flavor` was admitted
  on `--to=dmn-md`, where **nothing reads it** — the markdown emitter never touches `drgFlavor` and
  `markdownReport` hard-codes its target — so it is now rejected there, per this file's own rule
  against silently ignoring a flag the caller typed. (4) The flavor test helper was a second copy of
  `drgNamed` **without its `tcdErrors` guard**, reopening the hole that guard's docstring exists to
  describe, directly under the byte-identity tripwire; there is now one helper taking the flavor as
  a parameter. (5) `feelIdentText`'s widening of the collision domain had **no detector for two of
  its three classes**; `D-FEELNAME` now covers the whole DRG namespace at `Blocking`. (6) The C7
  column of §13.2 and (7) the `dmn-js` row of §13.4 were corrected as recorded in those sections.

  Two of the seven were found only by **execution**, and both had been reported green: the harness
  did not compile (an unbalanced brace, which `run.sh` reported as `SKIP … javac failed` and exit 0
  — the skip contract hiding a repo defect, now a hard `BROKEN` exit), and `jl4-core` did not build
  (`-Werror=x-partial` on a `head`). A suite number quoted from a pipeline whose exit code was
  masked by `tail` is how both survived review.

  **Residual risk, in order.** (1) **The two flavors are still byte-identical**, so the axis is
  ceremony until Phase 5; the tripwire at `DmnExport.hs` is what makes the day it stops being true
  visible, and it now sits behind a typecheck guard. (2) **`uniquifyIn` is still not implemented**
  (§5.2 stage 2), so a FEEL-name collision is _detected_ and not _resolved_ — and the asymmetry
  runs against the default: KIE's validator says `DUPLICATE_NAME` (while still building and
  answering), Camunda 8 says nothing at all, and the two engines do not agree on which element
  wins. On `camunda`, a `Blocking` note is the only line of defence. (3) **The `dmn-engines` job is
  not a required status check** on the `unstable` ruleset — verified against
  `gh api repos/legalese/l4-ide/rulesets/18543507`, which lists only TypeScript, Haskell, WASM and
  Nix — so today its failure does not block a merge; adding the context is a repo-settings change,
  not a code one. (4) Zeebe **deploy-time** validation, Camunda **Modeler** import, and Camunda 8's
  behaviour on a **malformed BKM** remain unmeasured (§13.8).

- **R8 — Builtin `MAYBE` / `EITHER`. ANSWERED 2026-07-29, see §4.2.1-6 and §7. Opened 2026-07-27 by
  R4 (§4.2.1-6).** They are payload-carrying unions and were deliberately out of R4's scope.

  **The verdict: the leaning survives on the _type_ channel and dies on the _value_ channel, and the
  measurement is what splits it.** That split is also what R8's own text asked for — R8 is "a §4.2
  _type-emission_ question in Phase 3, not a totality question".

  **The census R8 demanded**, over the same three corpora §2.2 names (Reg CF, Charities, Housing;
  63 `.l4` files on this tree, where the spec said 62): **16 decisions, not 11, classified
  6 / 3 / 6 / 1.** The figure differs because a decision can touch a `MAYBE` without `MAYBE`
  appearing in its own type — six do, through a parameterised `mapMaybe` `WHERE`-local. **[E]**
  `EITHER` reaches **0** decisions in these corpora, confirming R8's own figure; it reaches 8 in
  `jl4/examples/**`, all `JSON DECODE` results, every one of which §2.4.1's `PURE` already refuses.
  **[E]** `MAYBE` reaches **zero** decisions in the committed DMN golden set, so no R8 ruling moves an
  existing golden by itself — which is why Phase 3 adds `jl4/examples/dmn/sumtype.l4`.

  - **R8-a — type emission (the leaning is accepted).** `MAYBE τ` lowers to **τ's own `typeRef`**. No
    wrapper `itemDefinition`: DMN 1.3's `tItemDefinition` has no nullability flag, so the `MAYBE` is
    _recorded_, not spelled. Every such site raises **`D-MAYBE-NULL`, `Lossy`**.

    > **Carve-out, AMENDED 2026-07-30 under review — when τ carries `allowedValues`, the element
    > points at a minted domain-free alias `<τ>_optional` instead.** Same base `typeRef`
    > (`<typeRef>string</typeRef>`), **no** `allowedValues`, minted at most once per module, emitted
    > after the base definitions, and **only where an element actually points at it**. τ with no
    > domain-carrying `itemDefinition` — a record, a builtin, a `LIST OF` — keeps the lowering above
    > unchanged, because it asserts no range for the hop to re-assert.
    >
    > **This is not a way to spell nullability**, which `tItemDefinition` still cannot do, and it is
    > not the "wrapper `itemDefinition`" R8-a refuses on information grounds (§4.3's objection is to
    > an alias that adds nothing; this one subtracts something load-bearing). It exists for exactly
    > one reason: **R8-b's suppression was being defeated one `typeRef` hop away**, and that is an
    > answer change rather than a reporting gap. See R8-b for the measurement and the reversal.

    **The alias is not merely retained under R8-d′ (2026-07-31) — it is STRENGTHENED, and the
    reason is worth stating because it inverts.** Before R8-d′, **nothing this exporter emitted was
    ever `null`**, so an enforcing engine's rejection of the absent case was hypothetical: the
    argument for the alias rested entirely on §7.3.3's reading. After R8-d′ the exporter genuinely
    emits `null` into positions typed `<τ>_optional`, so the rejection is **real**. Making `NOTHING`
    lower to `null` gives `tItemDefinition` no nullability flag and makes `null` no more listable in
    an `allowedValues` — rule 34 keeps it out of the endpoint grammar either way — so every word of
    R8-a and R8-b stands, with live evidence behind it instead of a hypothetical.

    > **[D] DEFECT, FOUND 2026-07-31 and NOT FIXED — the alias is emitted after the definitions
    > that reference it, and KIE 8.44 resolves `itemDefinition` typeRefs in DOCUMENT ORDER.**
    > Measured the first time any engine was pointed at `sumtype.dmn`, which is also the first time
    > any engine was pointed at an artifact using this alias:
    >
    > ```
    > ERROR [TYPE_DEF_NOT_FOUND] DMN: Unable to resolve type reference '…}Grade_optional'
    >   on node 'Claim' (DMN id: itemdef_claim_c2, The listed type definition was not found)
    > ```
    >
    > `itemdef_claim` is emitted at document position 3 and `itemdef_grade_optional` at 5. The DMN
    > XSD sequences `itemDefinition*` with no ordering constraint among them, so this is an engine
    > behaviour rather than a schema violation — but "valid and unloadable" is exactly the class of
    > outcome the engine harnesses exist to catch, and the fix is one line of emission order:
    > **aliases before the base definitions**, not after.
    >
    > Not repaired in this change, and the reason is scope rather than difficulty: `sumtype.dmn` is
    > the ONLY DMN golden that uses an `_optional` alias (`grep -c _optional` over the other four
    > returns 0), and it is a `HarnessMustFail` exhibit for an unrelated reason, so no MustPass leg
    > moves either way. Reordering would churn the golden and require re-measuring every artifact
    > on both engines for a defect nothing currently exercises. It is **pinned** instead: the
    > `sumtype` MustFail leg asserts `TYPE_DEF_NOT_FOUND` and `Grade_optional` by name, so the day
    > it is fixed the leg goes red and this paragraph gets read. The carve-out's own text above
    > ("emitted after the base definitions") is the sentence to change.

    > The residue is recorded on the note: at an aliased site an engine no longer validates the
    > values that _are_ present, so a string outside τ's constructors passes where at a non-`MAYBE`
    > site it would be rejected. That is the price of keeping the absent case admissible, and it is
    > the narrower loss — it is confined to `MAYBE` sites, whereas the defect it replaces rejected
    > the `NOTHING` that is the whole content of the type.

  - **R8-b — `MAYBE` suppresses the domain _at the element_.** A `MAYBE`-typed element **may not
    carry** `allowedValues` / `inputValues` / `outputValues`, even when τ has a finite domain.
    §7.3.3 makes `allowedValues` "the **complete** range of values that this ItemDefinition
    represents", and `null` is not a legal S-FEEL endpoint (grammar rule 34 makes it a _literal_;
    rule 33's `simple literal` is numeric | string | boolean | date-time only), so any list we
    wrote would exclude a value the type admits.

    > **The defect, and the repair — recorded 2026-07-30 under review. R8-b was being defeated one
    > `typeRef` hop away, and the shipped lowering was an ANSWER CHANGE.** §7.3.3 makes
    > `allowedValues` the complete range of **the itemDefinition the `typeRef` resolves to**, not of
    > the element that carries the `typeRef`. So suppressing the range _at the element_ while
    > pointing that element at τ's own definition re-asserts the identical range one hop on.
    >
    > **[E]** As shipped, `jl4/examples/dmn/expected/sumtype.dmn` gave the inputData `q` the
    > attribute `typeRef="Grade"` and no `allowedValues` of its own, while `itemdef_grade` carried
    > `<typeRef>string</typeRef>` and the range `"high","low"`. So that range was `q`'s complete
    > range, and it has **no absent case in it**. Nothing this exporter emits lowers to `null`,
    > so under an enforcing engine a `MAYBE Grade` input could never _be_ `NOTHING`. That is not a
    > fidelity gap to report; it is the export answering differently from the L4, which is §2.4's
    > own severity line.
    >
    > **The repair is R8-a's carve-out** (see above): the element points at `Grade_optional`, whose
    > definition is `<typeRef>string</typeRef>` with no range, and R8-b's suppression then holds
    > through the hop — the only place it can hold.
    >
    > **[E]** `sumtype.dmn` now carries one `itemdef_grade_optional`, and both `input_q` and
    > `Claim`'s `assessed grade` component point at it. `Disposal` has a domain too and is never
    > reached through a `MAYBE`, so no alias is minted for it. `capped at ten` is `MAYBE NUMBER` and
    > keeps `typeRef="number"`. The Reg CF and Reg CF corpus goldens are **unchanged** — neither
    > reaches a domain-carrying type through a `MAYBE`.
    >
    > **What this replaces, in two steps.** (1) The note originally asserted that the payload type's
    > declared domain was **DROPPED**, and `jl4/tests/DmnExport.hs` pinned that sentence; the
    > artifact contradicted it, because `classifyType` returns a domain **only** from the branch
    > that mints a name. (2) The first correction went the other way and said the suppression "does
    > not reach through the `typeRef`", calling the residue "the artifact **under-declares
    > nullability**" — true of the artifact as it then stood, and it is what this ruling reopened
    > R8-a to fix rather than to describe. That second sentence is the live hazard, because it
    > describes an export we no longer emit, so it is the one the test suite pins against. The flag
    > carrying this is `tfOptionalAlias` in `L4.Dmn.Lower`, and it holds both names so the note can
    > name the alias _and_ the type whose range it drops. "The domain was dropped" is artifact-true
    > again — at the alias, and nowhere else.
    >
    > _(An earlier draft of this paragraph also recited a chain of prior names for that flag. Those
    > names are in no commit and in no file on this tree, so a reader had no way to check them; a
    > rename history that cannot be verified is not worth the citation it looks like.)_

  - **R8-c — nested `MAYBE` is refused.** `MAYBE (MAYBE τ)` ⟹ **`D-SUMTYPE`, `Blocking`**. `null`
    does not nest, so `JUST NOTHING` and `NOTHING` become one FEEL value and FEEL `=` answers `true`
    where L4 answers `false` — an **answer change**, which is §2.4's own severity line. Corpus cost:
    **1 decision**, `jl4/examples/ok/pattern-matching.l4:69-71`, not a golden subject.

    **STILL REFUSED after R8-d′ (2026-07-31), and now pinned in two places.** Test anchors:
    `jl4/tests/DmnExport.hs`, "refuses a NESTED MAYBE, because null does not nest (R8-c)" (the
    boundary clause, via `sumtype.l4`'s `deep`) and "refuses a NESTED MAYBE used as a CONSIDER
    SCRUTINEE (R8-c)" (the scrutinee clause). The second is new and is not redundant: `deep`'s body
    is `TRUE`, so it only ever reached the boundary clause, and the scrutinee clause's guard is
    `tfEither || tfNestedMaybe` — `classifyType` sets `tfMaybe` **as well as** `tfNestedMaybe` on a
    nested `MAYBE`, so a narrowing to `tfEither` alone would have let a nested scrutinee through
    silently.

    **★ THE NOTE IS NOT THE REFUSAL — corrected 2026-07-31 in review, and this is the repair that
    matters most in this change.** A `D-SUMTYPE` Blocking note does **not** stop the body being
    rendered: `literalFallback` renders it with `renderFeelIn` and reports Blocking _beside_ it,
    which is why `decision_deep` ships `<text>true</text>` under a Blocking note. R8-d′'s three new
    render arms (`NOTHING → null`, `JUST x → x`, `CONSIDER`-over-`MAYBE`) had **no type guard**, so
    a nested-`MAYBE` scrutinee rendered `if m != null then true else false` — engine-loadable FEEL
    that answers `false` for `JUST NOTHING` where L4 answers `true`. Before R8-d′ the same decide
    rendered `CONSIDER q WHEN JUST g THEN TRUE, WHEN NOTHING THEN FALSE`, L4 source no engine can
    compile. **The refusal had been weakened from "cannot run" to "runs and answers wrongly"** —
    the answer change this very paragraph forbids.

    Every render arm that gives a `MAYBE` a FEEL image is now guarded on the expression's own
    `TypeFlags` (`not (tfNestedMaybe || tfEither)`), including the `isJust`/`isNothing` combinator
    table; a refused arm falls through to `verbatim` and the refusal stays loud. The guard is
    separate from the note deliberately — the note describes the **decision** while the guard
    describes one **sub-expression**, and `renderFeelIn` composes. The test now asserts the
    RENDERING, not only the note; before that assertion existed it was green with the defect
    present.

  - **R8-d — value emission is refused _in this change_.** **OVERTURNED FOR THE VALUE CHANNEL
    2026-07-31, on its own stated terms; see R8-d′.** The paragraph is retained unedited below
    because R8-d′ discharges it reason by reason, and a deleted premise cannot be checked against
    the conclusion drawn from it. A decision that constructs
    `JUST`/`NOTHING`/`LEFT`/`RIGHT`, or whose `CONSIDER` scrutinee is a `MAYBE`/`EITHER`, ⟹
    **`D-SUMTYPE`, `Blocking`**, reported before `D-LITERALEXPR`. Two independent reasons. (i) **Zero
    corpus exercise on the accepting branch**: all three `CONSIDER`-on-`MAYBE` decisions in the
    corpora are already `Blocking` for reasons that have nothing to do with `MAYBE` (two
    `RegulativeBody`, one `NotAGuardedChain`), so building the lowering would ship a code path no file
    reaches — the precise thing §5.3.3 refused. (ii) **It cannot be built inside this exporter's
    stated conservatism**: a `CONSIDER`-on-`MAYBE` table needs `null` as an **input cell**, and by
    §2.2's grammar reading `null` is not a legal S-FEEL endpoint at all, so the cells would leave the
    fragment §3.1's whole thesis depends on. **Re-open condition:** the earliest phase that has an
    independent reason to leave S-FEEL on the cell side (Phase 5).
  - **R8-e — `EITHER` stays inside the `D-SUMTYPE` refusal**, at `Blocking`. Measured exposure: 0 in
    the DMN corpora; 8 in `jl4/examples/**`, all already refused by `PURE`.

    **UNCHANGED in substance by R8-d′, and now COVERED.** Until 2026-07-31 this refusal had **zero
    tests and zero corpus exposure** — `grep -n 'EITHER\|LEFT\|RIGHT' jl4/tests/DmnExport.hs`
    returned nothing — which is exactly how a narrowing takes a refusal with it and nobody notices.
    Three tests were written and watched go green on the **unmodified** tree before the narrowing
    landed: "refuses a decision that CONSTRUCTS an EITHER", "refuses a CONSIDER over an EITHER" and
    "refuses an EITHER at a decision BOUNDARY, even unread" (the last is the one the other two
    cannot substitute for: it is the only clause a threaded-but-unread `EITHER` reaches).

  - **R8-f — the defect the census found ships regardless of the above.** **[D]** `isConstantRef`
    accepted anything the typechecker stamped `Constructor`, and it stamps the **builtin** `NOTHING`
    exactly that way, so `NOTHING` lowered to the S-FEEL **string constant** `"NOTHING"`. **[E]** Six
    decisions of the shape `IF p THEN JUST c ELSE NOTHING` shipped with a `Blocking`
    `D-NONFEELOUTPUT` on the `JUST` arm and **no note at all** on the other — strictly worse than a
    loud failure, because a reader who checks the report concludes the unreported arm is fine.
    Excluding them from `isConstantRef` alone is **not** sufficient: the reference would then fall
    through to `feelIdentIn` and render as a bare FEEL _identifier_ tagged `SFeel`, which is worse
    still. So a reference to one of the four renders **verbatim** and R8-d routes the decision to a
    boxed literal expression. **[E]** After the fix, `regcf-wizard.dmn` and `part-6-use-of-terms.dmn`
    contain **zero** occurrences of `"NOTHING"`.

    **The defect stays fixed; its MECHANISM now covers two of the four (2026-07-31).** `LEFT` and
    `RIGHT` keep the verbatim rendering and the refusal. `JUST` and `NOTHING` have real FEEL
    renderings under R8-d′ — `x` and `null` — so they no longer need to be kept out of the FEEL
    text, only out of the _string_ channel, which is what the defect was about. The assertion that
    pins it is **unchanged and still runs**: `jl4/tests/DmnExport.hs`, "never spells NOTHING as a
    FEEL value", asserts `xml` contains neither `"NOTHING"` (the string constant) nor `>NOTHING<`
    (a bare identifier or element text). `null` is a _literal_, and is neither.

  - **R8-d′ — `null` IS the lowering of `MAYBE` on the value channel. RULED 2026-07-31.**

    `null` is admitted **wherever DMN admits an arbitrary FEEL expression** — a `literalExpression`,
    an output entry, a `defaultOutputEntry`, a context entry, an input _expression_ — and is
    **refused as an input _entry_**, i.e. as a unary test or an endpoint. §2.2's grammar reading
    stands unchanged: DMN 1.3 rule 34 makes `null` a _literal_ and rule 33's _simple literal_ is
    numeric | string | boolean | date-time only.

    **The guarantee is mechanical, not a convention an emitter must remember.** There is no `VNull`
    constructor in `FeelValue` (`jl4-core/src/L4/Dmn/IR.hs`), which is the only type a `UnaryTest`
    endpoint can hold; and `constantRefIn`'s `isBuiltinSumCon r -> Nothing` short-circuit stays
    exactly as it is. So `null` cannot reach an `<inputEntry>` by any route, including a wrong
    `FeelFragment` tag.

    Four lowering rules:

    | L4                                                    | FEEL                                 | fragment                              |
    | ----------------------------------------------------- | ------------------------------------ | ------------------------------------- |
    | `NOTHING`                                             | `null`                               | `FullFeel` — never `SFeel`, see above |
    | `JUST x`                                              | `x`                                  | whatever `x` is                       |
    | `CONSIDER m WHEN JUST g THEN a / WHEN NOTHING THEN b` | `if m != null then a[g := m] else b` | `FullFeel`                            |
    | `isJust e` / `isNothing e`                            | `e != null` / `e = null`             | `FullFeel`                            |

    **All four rows are GUARDED on the MAYBE being one level deep and carrying no `EITHER`**, and
    the guard was added in review after the unguarded version shipped — see R8-c above for what it
    cost. A refused arm falls through to `verbatim`, which is the refusal, not the note.

    **`null` as an OUTPUT entry is a LITERAL, and `D-COMPUTEDOUTPUT` now says so.** Its generic
    message ("is an expression, not a constant") contradicted `D-MAYBE-NULL` in the same report,
    which cites rule 34 to call `null` a literal. Both cannot be right. The message branches on the
    entry text: for `null` it says the entry is FEEL's null literal but denotes **no object in any
    domain**, which is the real reason a decision-table analysis — which maps an output entry to an
    object — still cannot place it. The severity and the `lost:` clause are unchanged, and
    `constantRefIn`'s input-entry short-circuit is untouched, because that is the half R8-d′
    actually needs.

    The `CONSIDER` rule is a `renderFeelIn` **case**, not a source rewrite to `IfThenElse`. A case
    composes — a `CONSIDER` nested inside a larger expression still renders — where a source rewrite
    would only fire when the `CONSIDER` is the whole body. The scrutinee's text is emitted more than
    once, so the rule is guarded on `not (hasEffectfulNode scrut)`.

    The combinator row is checked **before** general compilation and matches on the **resolved
    `Unique`** of the prelude definition, never on a name string — matching on a name is precisely
    the class of defect R8-f was. Because `isJust`/`isNothing` are ordinary prelude L4 source rather
    than builtins, their `Unique`s cannot be TH constants, so `DmnLowerOptions` gains one field and
    `resolveMaybePredicates` resolves it once at the boundary under a **type** check (a
    `KnownTerm … Computable` whose argument head is `maybeUnique` and whose result head is
    `booleanUnique`, with exactly one survivor per name). Both call sites — the CLI exporter and the
    golden harness — go through that one function, so they cannot drift.

    **The type check alone was not enough, and "exactly one survivor" did not cover the case it
    claimed to — corrected 2026-07-31 in review.** The `Unique` is _found by a name lookup_, so the
    name is still what selects the entity; "exactly one survivor" only rejects a shadow that sits
    **alongside** the prelude's. A module that defines its own `isJust :: MAYBE a -> BOOLEAN` and
    does **not** import the prelude has exactly one shaped candidate, and the shape check cannot see
    the body — so `` `isJust` x MEANS FALSE `` rendered `x != null`: a wrong answer with **no
    fidelity note at all**, because a recognised combinator is clean FEEL. Two provenance conditions
    now sit on top of the shape, and neither is a path test (`Unique` carries the URI of the module
    that minted it, and comparing URIs for _equality_ is immune to the CLI-vs-VFS difference a path
    test would trip on):

    - both survivors must come from the **same** module — one prelude defines the pair;
    - that module must **not** be the module being exported.

    **What is still not established, stated rather than glossed:** that the defining module is the
    L4 prelude and not some other imported library that defines both names at both types. Closing
    that would need the **bodies**, and `EntityInfo` carries only types. A library imported
    _instead_ of the prelude is recognised; one imported _alongside_ it is not. Pinned by "does not
    recognise a LOCALLY defined isJust as the prelude's" in `jl4/tests/DmnExport.hs`.

    **Discharging R8-d's two reasons, separately, because only one of them is answered:**

    - Reason (i), _zero corpus exercise on the accepting branch_: **DISCHARGED.** `capped at ten`
      (`jl4/examples/dmn/sumtype.l4`) now emits a real decision table, and the rephrased corpus plus
      the new `jl4/examples/dmn/hydration.l4` exercise all four rules.
    - Reason (ii), _`null` as an input cell_: **NOT overturned — RETIRED AS AN ASK.** The lowering
      never requests a cell. §2.2's grammar reading and §3.1's thesis are untouched.

    **[E] The evidence R8-d itself asked for, and it was gathered BEFORE the lowering was written.**
    `jl4/tests-cli/fixtures/dmn-null-probe/` measures, on KIE 8.44.0.Final and zeebe-dmn 8.7.6:
    comparison against `null` is a proper **boolean** (`n = null` is `false`, not `null`); the
    composed `if q != null then … else …` takes the branch it looks like it takes; a decision may be
    `null` outright; and **a table's `defaultOutputEntry` may be `null`** — which is the
    `defaultOutputEntry` half of R8-d's own overturn condition, verbatim. 15/15 on both engines.

    A fallback was **pre-declared before the probe ran**: had `=` against `null` answered non-boolean
    on either engine, only the value channel would have shipped and the scrutinee refusal would have
    stayed. It did not arise.

    **One question the engines answer DIFFERENTLY**, split into `null-absent.dmn` and asserted in
    both directions: an unbound name is `null` on zeebe-dmn and a **model error** on KIE (the
    decision is `SKIPPED`). It is out of scope **by construction** rather than by luck — this
    exporter never emits a reference to a name it has not declared, because every free term becomes
    an `inputData` and a hydrator emits every entry of its record — and the fixture is what makes
    that a measured statement instead of an assumption.

  - **R8-d″ — tabulating a `CONSIDER`-on-`MAYBE`. DEFERRED, with its condition.** Rewriting the
    `CONSIDER` to an `IfThenElse` at the AST level, so that a whole-body instance tabulates with a
    boolean column instead of becoming a boxed literal, is **not built**. Re-open when a corpus
    decision of that shape would otherwise be the _whole_ body of a decide **and** the resulting
    table would carry more than one row — below that, the boxed literal says the same thing and the
    rewrite only fires where the case already suffices.

  **Incremental refusal cost of R8-c/d/e on the corpora: 6 decision tables** — and **none of the 6
  works today**: each already carries a `Blocking` `D-NONFEELOUTPUT` on its `JUST` arm and the
  silently wrong `"NOTHING"` string on the other. R4-a's narrowing argument ("do not refuse what the
  corpus already gets right") therefore does not apply, because nothing here is got right. On the
  **golden** set the cost is **0**.

  **What would overturn R8-d, checkably.** (i) A `MAYBE`-scrutinising decision that would otherwise
  emit a table appears in a corpus, giving the accepting branch exercise; **and** (ii) KIE 8.44 and
  Camunda 8.7.6 are both measured, from `etc/kie-dmn-check/` and `etc/camunda-dmn-check/`, to
  evaluate a `null` input cell and a `null` `defaultOutputEntry` the way L4 evaluates `NOTHING`.
  Both are cheap and **[U]** neither is done.

  **It does not block #923** — `MAYBE`'s payload is not projectable (`m's val` is a type error), so
  L11 has no `MAYBE` exposure and `MAYBE` reaches `LOCALLY-TOTAL` only through L1, which is already
  gated on Phase 0.5.

---

- **R9 — `OTHERWISE` on a rule-date interval table: a floor ROW, not a `defaultOutputEntry`.
  ANSWERED 2026-07-30, see §15.3. Amends §3.3.**
  §3.3 rules that `OTHERWISE` stays a default and forbids expanding it into explicit rules; §3.3.1
  adds a `SHALL` — never emit a `defaultOutputEntry` on a table whose rules already cover the input
  space. A rule-date interval table emits the `OTHERWISE` as one final rule `< date("<earliest>")`
  and **no** `defaultOutputEntry`.
  _Why this is not the expansion §3.3 rejects._ §3.3 forbids **enumerating a declared finite
  domain** to turn "everything else" into _k_ rules, which consults `inputValues` and erases the
  source's own statement of incompleteness. The floor row consults no domain, enumerates nothing,
  and is **one** unary test that is the _exact_ complement of the arms — derived by the same
  arithmetic that derives the intervals, from the same first-match reading. It is the `UNIQUE`
  analogue of the final all-`-` row §3.3 already blesses under `FIRST`: under `FIRST` "everything
  else" is spelled all-`-`; under `UNIQUE` an all-`-` row would overlap every other rule, so the
  same statement must be spelled as its complement. **Same statement, different spelling, forced by
  the hit policy** — §3.3's closing sentence ("No change to the two spellings, both already
  correct") therefore gains a third.
  _Why it is also the better artifact._ §3.3.1 consequence 1 observes that `FIRST` + all-`-` is a
  **complete** table while `UNIQUE` + default is a declaredly **incomplete** one. These eight tables
  are complete today. Emitting `UNIQUE` + default would trade order-dependence for declared
  incompleteness — a sideways move. The floor row buys the order-free reading and keeps
  completeness, and §3.3.1's `SHALL` then _requires_ omitting the default. The two are locked
  together: one without the other is a spec violation.
  _What review changed:_ the first draft used `UNIQUE` + `defaultOutputEntry` on the strength of
  §3.3's headline, arguing that a gap report over the pre-commencement half-line honestly names the
  corpus's curated refusal (`regcf.l4:126-133`). That reading was dropped once §3.3.1 consequence 1
  was read: it would have made eight complete tables incomplete in order to state something the
  `<description>` and the annotation column already state.

- **R10 — the interval-table recogniser is a peephole over two idioms, and refuses loudly.
  ANSWERED 2026-07-30, see §15.3.**
  The recognised shapes are (a) an application of a one-parameter `DATE`-typed predicate whose body
  is `RULES EFFECTIVE DATE AT LEAST <that parameter>`, applied to a nullary decide whose body folds
  to a date; and (b) the same comparison written inline against a `Date d m y` literal. Everything
  else — strict (`>`) guards, `DATE_SERIAL`-wrapped comparisons, `YMD`, nested chains, multi-conjunct
  guards — is `NotDated` (existing path, unchanged findings); a chain that MIXES a rule-date arm with
  an ordinary one, or whose date will not fold, or whose arms are not strictly descending, is a
  **Blocking** `D-DATEDCHAIN`. **[E]** The severity follows the vocabulary in `Lower.hs`'s roster:
  the fallback ships columns of raw L4 that no engine can evaluate, which is `Blocking`, and it is
  what the sibling backend already does (`L4/OpenFisca/Lower.hs` returns `Left`). Duplicate dates are
  refused by the same strictly-descending predicate rather than emitting an empty `[d..d)` interval:
  the second arm is dead in L4 too, but a rule that can never fire is not an artifact worth shipping.
  **[E]** `DATE_SERIAL`-wrapped comparisons are a real v1 gap and the tree's own temporal exemplar
  hits it: `jl4/examples/ok/temporal-rule-version-spike.l4:23` writes
  `(DATE_SERIAL RULES EFFECTIVE DATE) AT LEAST (DATE_SERIAL (Date 1 1 2024))`, which is a **NUMBER**
  comparison and will not become an interval table. Unwrapping `DATE_SERIAL` on both sides is the
  first v2 extension; it is out of v1 because nothing in the shipped exhibits would have tested it.

  **Amended 2026-07-31 after adversarial review.** Four repairs, each with a witness:

  - **The inline idiom takes a NAMED regime constant, not only a literal.** The inline form _is_ the
    predicate form with the one-line helper elided, so
    `` `RULES EFFECTIVE DATE` AT LEAST `the 2024 rate change` `` carries exactly the information the
    predicate form does and folds the same way — through `constantDay`'s one hop, not the bare
    literal fold. Before this, every such chain was refused while the refusal MESSAGE told the reader
    that "a nullary decision whose body is one" **is** folded; a reader following that message would
    have written the very thing that was refused. Witness: `gst-rate.l4`'s
    `tourist refund minimum spend` now writes one arm each way, and the constant the arm names
    reaches the annotation column instead of degrading to `from <day>`.
  - **A REGULATIVE body, or an effectful guard, is `NotDated`.** `rowsToDmnWith'` refuses those two
    shapes _before_ it builds anything, and the dated path does not go through `rowsToDmnWith'`, so
    those refusals had silently stopped applying to any chain that happened to look dated. A
    law-time-guarded obligation — "under the 2024 rules the issuer must file within 30 days, before
    that within 45", the shape temporal rule-versioning most invites — would have become a `UNIQUE`
    table of verbatim L4 obligations, and the reader would have been told "the output entry is L4
    source, not FEEL" instead of "DMN has no notion of time or obligation". Witness:
    `not-ok/dated-chain-regulative.l4`.
  - **The `OTHERWISE` counts as an arm body for the nested-chain test.** On the ordinary path
    `expandOtherwise` splices a nested catch-all chain's rows into the table and reports what it
    declines to splice as `D-FLATTENCAP`; the dated path would have collapsed the whole nested chain
    into one floor-row output entry with **no note at all**.
  - **Every ordinal a refusal quotes is an index into the chain's own rows.** The ordering refusal
    used to number only the _matched_ arms while the mixed refusal numbered all of them, so "arm 3"
    meant two different source arms on one file.

  The mixed-chain arm now has its own witness, `not-ok/dated-chain-mixed.l4`, and it needed one: the
  corpus's `financial statements required` matches **zero** rule-date arms and is therefore
  `NotDated`, which is a different code path with a different outcome, so the test named for the
  mixed arm was exercising the opposite one.

- **R11 — a dated table's `informationRequirement`s are computed from what survives into the
  artifact. ANSWERED 2026-07-30, see §15.3.**
  D2 inlines the guard predicate and the regime constants into interval endpoints, so a dated
  decision's emitted expression no longer references them while its cells now reference the
  rule-date input. Computing `dcnRequirements` from the source `freeRefs` would describe a graph the
  expression contradicts, which is a DMN 6.2.2 problem and not a cosmetic one. Requirements are
  therefore `RequiredInput <law time>` plus the requirements of the surviving **bodies** (arms +
  `OTHERWISE`), guards excluded. Consequence, and it is intended: the four regime constants and the
  guard predicate become DRG leaves with no dependents. They are **not** dropped (§2.5, and
  `literalFallback`'s own comment), they became evaluable for the first time in the same change
  (§15.4), and the annotation column carries their provenance back into the artifact.

## 12. Non-goals

- **`legalese/l4-ide` never depends on `smucclaw/dmnmd`.** dmnmd is local differential
  validation. Gaps go into its extension spec as an addendum; the exporter degrades honestly
  with `D-MD-*` notes until they land. Neither side waits on the other.
- Not a general DMN implementation. No DMNDI layout beyond what is already emitted, no FEEL
  evaluation. (**Corrected 2026-07-27:** this line used to read "No decision services", which
  contradicted §2.3's R1 ruling from the day it was written. Decision services **are** in scope; what
  R7/§13 rules is whether they are _invocable_, and that is the flavor bit. The same correction is on
  PR #160.)
- Not the process side. `Regulative`/`Deonton` targets BPMN 2.0 (PR #141) and has no markdown
  carrier.

---

## 13. Engine flavors — R7's detail

_Written 2026-07-27, from execution against three engines. Everything marked **EXECUTED** in
§13.2, §13.3 and §13.4 was run against a real engine, from the sources listed in §13.9;
everything marked **QUOTED** was run by another agent in the same session and is reproduced
without independent re-run; everything marked **UNKNOWN** was not measured and must not be
designed against._

_Revised 2026-07-27 under review, and the revisions are corrections rather than additions: the
Camunda 7 column of §13.2 said "all 5 correct" and did not survive re-measurement (§13.2); the
`annual in come` probe was promoted from QUOTED to EXECUTED and its claimed value corrected;
`dmn-js` was removed from the engine table in §13.4; and §13.10 records what review changed. The
labels in this section are load-bearing — the reason §5.1 shipped a wrong headline for months is
that a reading of the DMN grammar was recorded as though it were a measurement._

### 13.1 Which Camunda

They are not two versions of one engine, they are unrelated implementations, and the artifact
that matters differs:

|                | Camunda 7                                    | Camunda 8                                                    |
| -------------- | -------------------------------------------- | ------------------------------------------------------------ |
| Maven artifact | `org.camunda.bpm.dmn:camunda-engine-dmn`     | `io.camunda:zeebe-dmn`                                       |
| DMN engine     | Camunda's own Java engine                    | `org.camunda.bpm.extension.dmn.scala:dmn-engine` (dmn-scala) |
| FEEL           | `camunda-engine-feel-scala` + `camunda-juel` | `org.camunda.feel:feel-engine`                               |
| Impl class     | `DefaultDmnEngine`                           | `io.camunda.zeebe.dmn.impl.DmnScalaDecisionEngine`           |
| BKM            | **absent, and silent**                       | full                                                         |
| JDK            | 17                                           | 21+ (class file 65)                                          |

**The Camunda target is Camunda 8.** Camunda 7 executes only decision tables and literal
expressions — it cannot run a BKM at all, which is exactly axis 2 — and it is end-of-life: 7.24.0
is the final minor and Community received nothing after 2025-10-14. Camunda 8 ran every construct
this exporter might emit, correctly.

Camunda 7 is still worth **measuring** — it is the reason axis 2 looked like a divergence — but it
is not a flavor we emit for. Where C7 and C8 differ, C8 wins and C7's behaviour is recorded as
context.

The two engines' classpaths **must be kept separate**: `feel-engine` 1.19.x-scala-shaded (C7) and
1.18.3 (C8) collide. QUOTED, and consistent with the two separate `cp.txt`s used here.

### 13.2 Axis 1 — naming. Measured NOT to diverge.

The four candidate policies, each carried through all three engines on the same `reg-cf` model:

| Variant                          | node `@name`                   | `<variable>` `@name`               | FEEL reference        | KIE 8.44                                                    | Camunda 7.23                       | Camunda 8.7.6                 |
| -------------------------------- | ------------------------------ | ---------------------------------- | --------------------- | ----------------------------------------------------------- | ---------------------------------- | ----------------------------- |
| **shipped golden**               | verbatim (`first-time issuer`) | half-mangled (`first_time issuer`) | half-mangled          | **2 ERR, BUILD FAILS**                                      | parses, **4 of 5 decisions throw** | **`parse()` rejects the DRG** |
| **backticked**                   | verbatim                       | verbatim                           | `` `annual income` `` | **6 ERR, BUILD FAILS** (`syntax error near` the backtick)   | all 5 evaluate (QUOTED)            | all 5 evaluate                |
| **variable-only mangle**         | verbatim                       | `annual_income`                    | `annual_income`       | **6 ERR, BUILD FAILS** (`Unknown variable 'annual_income'`) | all 5 evaluate (QUOTED)            | all 5 evaluate                |
| **`vE` = `feelBase` everywhere** | `annual_income`                | `annual_income` (+`label`)         | `annual_income`       | **0 ERR, BUILD clean, 5/5 SUCCEEDED**                       | **4 of 5; see below**              | all 5 correct                 |

The KIE and Camunda 8 cells are **EXECUTED**. The Camunda 7 cells are **not what an earlier draft
of this table said**, and the correction is the substance of the next paragraph.

> **Corrected 2026-07-27 under review.** Three of the C7 cells previously read "all 5 correct".
> That was wrong, it contradicted §13.2's own last bullet (which says C7 ignores
> `<defaultOutputEntry>`), and the contradiction was in the document from the day it was written.
> Re-measured on the shipped `vE` golden, **EXECUTED** on `camunda-engine-dmn` 7.23.0 (probe
> `C7Gen`, scratchpad):
>
> - `is accredited investor` returns `[]` — an **empty result**, not `false` — under a context
>   where no rule fires and the answer is the `<defaultOutputEntry>`. Reviewer B was right.
> - Under an `accredited` context, `investor limit` answers **25000** where KIE and Camunda 8 both
>   answer **100000000**. A wrong _value_, not merely a missing one.
> - Four `DMN-01006 Unsupported type 'number' for clause` warnings: C7 does not support the
>   `number` typeRef on a clause at all.
> - Two decisions come back keyed `null` rather than by name, which is the documented cost of
>   dropping `output/@name` (below) and is C7-only.
>
> Both of the first two are **naming-independent**, so "all 5 correct" cannot have been right on
> any row of this table, including the two still marked QUOTED. C7 is not a target (§13.1); this
> is recorded so nobody re-measures on C7 and mistakes any of it for a live constraint. The word
> in the remaining C7 cells is deliberately "evaluate", not "correct": nothing in this repo pins
> C7's values, and the harnesses do not run it.

Three things fall out, and together they retire the axis:

1. **`vE` is a universal policy.** There is no naming decision left to flavor. §5.2's `feelBase`,
   applied uniformly and paired with `@label`, is simply the right answer everywhere.
2. **The engines bind the FEEL name off different attributes.** KIE resolves an `inputData` by the
   **node's** `@name`; Camunda resolves it by the **`<variable>`'s** `@name`. That is why
   variable-only mangling is green on Camunda and fatal on KIE, and why the shipped golden is
   fatal on both — it does half of each. Making the two attributes equal is what makes the
   question disappear; it is not a compromise, it is the invariant `feelIdentText`'s doc-comment
   already claims to hold and does not.
3. **Backticking is not an alternative.** It is a `feel-scala` extension. Camunda accepts it, KIE
   rejects it at compile time. Any design that reaches for backticks to preserve verbatim names
   has silently become Camunda-only.

**The failure mode on Camunda is the bad kind.** `annual income` does not fail to resolve; it is
_tokenised_ as `annual` `in` `come` — the membership operator — and answers a **boolean** rather
than the number.

**EXECUTED 2026-07-27** (this claim was marked QUOTED until then, and it is the single claim the
whole naming ruling rests on, so it was run). A two-decision model declaring `annual income` =
100000, `annual` = 5 and `come` = [1,2,5], with one decision bodied `annual income` and the other
`annual in come`:

| Engine                                 | `annual income` | `annual in come` |
| -------------------------------------- | --------------- | ---------------- |
| KIE 8.44.0.Final                       | `100000`        | `true`           |
| Camunda 8.7.6 (`io.camunda:zeebe-dmn`) | **`true`**      | `true`           |

The two expressions are indistinguishable to Camunda. Note the value: **`true`**, not `null` — the
boolean is whatever the membership test happens to yield, so the earlier "evaluates to `false`" was
right about the _kind_ and wrong to fix the _value_. This matters operationally, and is why §13.6's
harness contract compares **expected values** and not merely statuses and nulls: a checker that
failed on `FAILED`, `SKIPPED` and `null` passes this file. Verified both ways — the committed
harnesses were run over this exact probe, and Camunda's leg fails on it **only** because of the
value comparison (`= true <<< EXPECTED 100000`), while reporting `0 error(s), 2/2 decision(s)
evaluated`.

This is the E7 silent-misreading class again, in the artifact rather than in the encoding —
precisely what §5.1 was written to prevent, arriving through the one clause §5.1 got wrong.

**Two adjacent findings, both shared fixes rather than flavor bits:**

- **`output/@name` + `output/@typeRef` on single-output tables.** KIE fires `ILLEGAL_USE_OF_NAME`
  and `ILLEGAL_USE_OF_TYPEREF`, six warnings on the golden; stripping both makes `vE` **0 errors,
  0 warnings** on KIE, leaves Camunda 8 byte-for-byte correct, and costs Camunda 7 only the
  result-map _key_ (values unchanged). EXECUTED on all three. Do it once, for both flavors.
- **`<defaultOutputEntry>`.** Camunda 7 **ignores** it — `is accredited investor` returns an empty
  result instead of `false` — while KIE and Camunda 8 both honour it. EXECUTED, and **re-executed
  under review on the shipped `vE` golden**, which is what exposed the contradiction corrected in
  the table above. A C7-only divergence, and C7 is not a target, so it does not become a knob; it
  is recorded so that nobody re-measures on C7 and mistakes it for a live constraint. Both target
  engines are pinned on this path by `reg-cf.cases.json` case A, whose `is_accredited_investor`
  expectation is exactly the `false` that the default entry produces.

### 13.3 Axis 2 — BKM. Measured NOT to diverge on the target pair.

| Probe                                                                 | KIE 8.44                                        | Camunda 7.23                                     | Camunda 8.7.6 |
| --------------------------------------------------------------------- | ----------------------------------------------- | ------------------------------------------------ | ------------- |
| BKM + `formalParameter` + caller `knowledgeRequirement`, literal call | `answer = 120` ✅                               | **`answer = null`, silently**                    | `120` ✅      |
| BKM invoked from a decision table cell                                | correct ✅                                      | **`null`, silently, and the output key is lost** | `120` ✅      |
| `<invocation>`-boxed decision                                         | QUOTED ✅                                       | **silently dropped: `PARSE OK: 0 decision(s)`**  | QUOTED ✅     |
| BKM whose encapsulated logic is a decision table                      | QUOTED ✅                                       | —                                                | QUOTED ✅     |
| caller `knowledgeRequirement` **removed**                             | validator ERROR **and** BUILD ERROR — loud      | —                                                | UNKNOWN       |
| BKM `@name` ≠ `variable/@name`                                        | validator ERROR, build clean, **runtime FAILS** | —                                                | UNKNOWN       |

The first two rows and the Camunda columns of them are **EXECUTED**; the rest as marked.

So on `{KIE, Camunda 8}` BKM is uniformly supported and uniformly loud when malformed. **BKM
emission does not need a flavor gate.** What §6.3-3 actually established is a refusal keyed to
_consumers we do not emit for_ — `@hbtgmbh/dmn-eval-js`, which has no BKM support and falls through
to the next rule with a plausible wrong answer, and Camunda 7, which returns `null`. Those stay in
§6.3-3 as reasons the **fidelity report** must name BKM usage; they are not reasons for a
`--flavor` bit.

**Consequence for §6.2:** build BKM once, for both flavors, unconditionally. The "gating" clause in
§6.3-3 is hereby narrowed to a fidelity note, not a suppression.

### 13.4 Axis 3 — `§`-as-`decisionService`. The one real bit.

| Shape                                                                                   | KIE 8.44                                                                                                              | Camunda 7.23                                                                                               | Camunda 8.7.6                                                                                                                       |
| --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `<decisionService>` present, **no** caller edge (grouping only)                         | validator clean, build clean, service **addressable** via `evaluateDecisionService`; enclosed decisions also evaluate | parses; service not addressable (`DMN-01001 Unable to find decision with id`); enclosed decisions evaluate | parses; service not addressable; enclosed decisions evaluate                                                                        |
| `<knowledgeRequirement><requiredKnowledge href="#svc"/>` on a caller + FEEL `svc(x: x)` | **clean, build clean, `caller SUCCEEDED = 610`**                                                                      | parses; caller silently evaluates to **`null`**                                                            | **`parse()` throws `ClassCastException: DecisionServiceImpl cannot be cast to BusinessKnowledgeModel` — the whole DRG is rejected** |
| identical file, that one `<knowledgeRequirement>` element deleted                       | —                                                                                                                     | —                                                                                                          | **parses, 3/3 decisions evaluate**                                                                                                  |

All three rows **EXECUTED**, on both a space-bearing and a FEEL-safe-named variant so the crash
cannot be blamed on naming. Row 3 is the isolation: one element, nothing else changed, parse
failure → parse success. **Re-executed independently under review 2026-07-27** on a fresh probe
(`KIE: caller SUCCEEDED = 610`, `SVC double_svc -> {n=300, doubled=600}`, 0 errors; `Camunda:
PARSE INVALID: DecisionServiceImpl cannot be cast to BusinessKnowledgeModel`; same file minus the
one element: `PARSE ok … 2/2 evaluated`). This is the sole justification for the flavor axis, so
it is the one measurement that is not allowed to be inherited.

> **A renderer is not an engine.** An earlier version of this table carried a fourth row —
> "Camunda Modeler / dmn-js renders the service box" — with ✅ in the two Camunda **engine**
> columns. `dmn-js` is a moddle-based renderer; a ✅ from it in an engine column is exactly the
> "valid per the validator, wrong in the engine" conflation this whole section exists to stop, and
> it was doubly misleading here because the C8 **engine** rejects at `parse()` the very file the
> renderer draws happily. The row is removed; the renderer/Modeler evidence lives in §13.8 with
> the rest of what was not executed against an engine.

Read carefully, this says the divergence is **not** "does the engine support decision services". It
is narrower: **may a `decisionService` be the target of a `knowledgeRequirement`.** Camunda 8's
model layer casts every `requiredKnowledge` target to `BusinessKnowledgeModel` unconditionally,
which is a Camunda defect against DMN 1.3 §10.3.2.11 (`tKnowledgeRequirement/requiredKnowledge`
points at `tInvocable`, and `tDecisionService` is a `tInvocable`) — but it is the defect we have to
export against.

And it is the worst possible shape of divergence: **whole-file, at parse, before any decision runs**.
There is no partial credit and no diagnostic pointing at the cause.

### 13.5 The ruling, and the option

**Two flavors. One bit. `camunda` is the default.**

|                                                           | `camunda` (default)                                                               | `kie`                   |
| --------------------------------------------------------- | --------------------------------------------------------------------------------- | ----------------------- |
| §5.2 naming (`feelBase` everywhere + `@label`)            | yes                                                                               | yes — **identical**     |
| `itemDefinition`, `inputValues`/`outputValues` (§3, §4)   | yes                                                                               | yes — **identical**     |
| BKM + `knowledgeRequirement` → BKM (§6)                   | yes                                                                               | yes — **identical**     |
| `<decisionService>` per `§` (§2.3)                        | emitted, **structural only**                                                      | emitted                 |
| `knowledgeRequirement` → `decisionService`                | **never emitted**                                                                 | emitted                 |
| FEEL invocation of a `§` (`Article 6(q)`)                 | **not available** — route to a BKM, else refuse with the existing `Blocking` note | available (§2.3)        |
| `output/@name`, `output/@typeRef` on single-output tables | omitted                                                                           | omitted — **identical** |

The camunda flavor pays a real price and the spec should say so rather than imply parity: a `§`
with N `GIVEN p` decisions that must be applied per list element needs N BKMs with duplicated
internal wiring, which is exactly the cost §2.3 cites for choosing a service over BKMs in the
first place. Where that is not affordable the call is refused with a `Blocking` note, not silently
degraded. **A new fidelity code, `D-FLAVOR-NOSERVICE`,** carries it: `Blocking` when a call site
needed an invocable `§` and the flavor forbids it, `Advisory` when a `§` was emitted as grouping
only and nothing tried to invoke it.

**Why a lowering option and not a post-hoc XML rewrite.** Three reasons, in order of force:

1. **The FEEL text differs, not just the element set.** A rewriter can delete
   `<knowledgeRequirement>`; it cannot re-render `Article 6(q).meets the test` into whatever the
   camunda flavor routes it to, because that text was already committed to a `<text>` node with no
   record of what it meant. The difference is a lowering decision that happens to _also_ show up
   as a missing element.
2. **The fidelity report is generated from the IR** (`dmnReport :: Drg -> FidelityReport`,
   `IR.hs:493`). A post-hoc pass would produce an artifact whose accompanying report describes a
   _different_ artifact — the report would still claim the service is invocable. That is the
   "valid per the validator, wrong in the engine" failure class this whole issue exists to close,
   reintroduced one layer up.
3. **Camunda 8 fails at `parse()`, whole-file.** "Emit the rich form, then strip for Camunda"
   has no safe intermediate: the intermediate is a file that loads nowhere.

**Type and placement.**

```haskell
-- L4.Dmn.IR, beside the other emission-shaping types.  (Mirrors DeadlineUnitPolicy,
-- which lives in L4.Bpmn.IR rather than L4.Bpmn.Lower for the same reason: the
-- emitter and the fidelity report both need to see it.)
data DmnFlavor = FlavorCamunda | FlavorKie
  deriving stock (Eq, Show, Generic)

defaultDmnFlavor :: DmnFlavor
defaultDmnFlavor = FlavorCamunda
```

- **Enters at** `DmnLowerOptions` (`Lower.hs:206`) as `dloFlavor :: !DmnFlavor`, with
  `defaultDmnLowerOptions` setting `FlavorCamunda`. Adding the field is a compile break at exactly
  two external construction sites, `Cli/Export.hs:281` and `tests/DmnExport.hs:1247`, both of which
  want to be updated anyway.
- **Is stored in the `Drg`** as `drgFlavor :: !DmnFlavor` (`IR.hs:410`). This keeps
  `emitDrg :: Drg -> Text`, `emitMarkdown :: Drg -> Text`, `dmnReport :: Drg -> FidelityReport` and
  `markdownReport :: Drg -> FidelityReport` at one argument each, preserves the "one IR, two
  emitters" story `Markdown.hs:4-11` is built on, and lets `dmnReport` tag `FidelityReport.target`
  as `"DMN 1.3 (XML), camunda flavour"` so the report names the artifact it describes.
- **Does not reach `renderFeelIn`** under this ruling, because naming turned out not to diverge.
  Had it diverged, the carrier would have been `TypeOracle` (`Lower.hs:171`), which is already
  threaded to every `renderFeelIn` call site by `oracleOf`; recorded here so the next person does
  not re-derive it.

**CLI** (`jl4/app/L4/Cli/Export.hs`), matching the file's three existing conventions — a closed
enum behind an `eitherReader` that names the accepted spellings, a `Maybe` so
`checkTargetFlags` can tell "typed" from "defaulted", and a hard error rather than a silent
ignore when the flag lands on the wrong target:

```haskell
dmnFlavorReader :: ReadM DmnFlavor           -- beside deadlineUnitReader, Export.hs:130
dmnFlavorReader = eitherReader \input ->
  case Text.toLower (Text.pack input) of
    "camunda" -> Right FlavorCamunda
    "kie"     -> Right FlavorKie
    "drools"  -> Right FlavorKie
    other     -> Left $
      "Invalid --flavor: " <> Text.unpack other <> " (expected camunda|kie)"
```

`--flavor` is legal on `--to=dmn` **only**, and `checkTargetFlags` rejects it on both other
targets.

> **Corrected 2026-07-27 under review.** This paragraph used to admit `--flavor` on `--to=dmn-md`
> as well, reasoning that "the flavor lives in the `Drg`, which both emitters read". Review checked
> the markdown side and it reads it **nowhere**: `emitMarkdown` mentions no field of `drgFlavor`,
> and `markdownReport` hard-codes its target string as `"dmnmd"` instead of naming the flavor the
> way `dmnReport` does. So `--flavor=kie --to=dmn-md` produced a byte-identical document **and** a
> byte-identical fidelity report — the exact silent ignore that `checkTargetFlags`' own docstring
> refuses. Nor would it self-heal at Phase 5: the one divergence is whether a `<decisionService>`
> may be invocable, and dmnmd is a table format with no DRG at all (it says so already, via
> `D-MD-NODRG`). Admitting a flag on the strength of a dependency that does not exist is the same
> error class as a banner reporting a version nothing loaded.

### 13.6 Goldens and test wiring

**Goldens: one pair per flavor, not a base plus a diff** — but not yet, and the "not yet" is the
interesting part.

Today the two flavors are byte-identical, because neither `decisionService` nor BKM is emitted. So:

- **Now:** the existing four goldens stay at their existing names, and a new test asserts
  `emitDrg (lower FlavorCamunda m) == emitDrg (lower FlavorKie m)` on the exhibit, with a comment
  saying this is expected to **fail** at Phase 5 and that the fix is to split the goldens, not to
  delete the test. A flavor knob with no observable effect is a trap; a test that will announce the
  day it acquires one is the cheapest defence.
- **At Phase 5:** the default flavor keeps the unsuffixed names (`reg-cf.dmn`,
  `reg-cf.fidelity.txt`) and the kie flavor gets `reg-cf.kie.dmn`, `reg-cf.kie.fidelity.txt`. The
  asymmetry is deliberate: it keeps `jl4/tests-cli/Main.hs:340`, `jl4/examples/dmn/README.md:130`
  and `git blame` intact, and it makes the default visible in the filesystem.
- **Never a diff-golden.** `jl4/examples/dmn/README.md:127-137` and `tests-cli/Main.hs:888-894`
  both assert every golden is reproducible byte-for-byte by one `l4 export` invocation; a diff is
  not the output of any command. And a diff cannot be fed to an engine, which is the whole point.

**Two harnesses, two directories, two independent skip gates.**

|           | `etc/kie-dmn-check/`                                                                  | `etc/camunda-dmn-check/`                         |
| --------- | ------------------------------------------------------------------------------------- | ------------------------------------------------ |
| Artifacts | `org.kie:kie-dmn-core`, `org.kie:kie-dmn-validation`                                  | `io.camunda:zeebe-dmn`                           |
| Pinned at | `8.44.0.Final`                                                                        | `8.7.6`                                          |
| JDK       | 17                                                                                    | 21+                                              |
| Legs      | Xerces XSD · KIE validator · `KieBuilder` · `evaluateAll` + `evaluateDecisionService` | `parse()` + `isValid()` · `evaluateDecisionById` |
| Env gate  | `KIE_CHECK_REQUIRED`                                                                  | `CAMUNDA_CHECK_REQUIRED`                         |

Both resolve their classpath into `$TMPDIR` via `mvn dependency:build-classpath` and **never** into
the repo; nothing downloaded is committed and neither touches `package.json` or the lockfile. Both
pin their version in a comment that says bumping it invalidates every EXECUTED claim in this file.
The XSD needs no download: `kie-dmn-validation-8.44.0.Final.jar` ships
`org/kie/dmn/validation/org/omg/spec/DMN/20191111/DMN13.xsd`.

**What a harness must assert**, because no single leg is sufficient — each row is a measured case
where the other legs are silent:

| Condition                                    | XSD   | validator | build     | runtime                                                                             |
| -------------------------------------------- | ----- | --------- | --------- | ----------------------------------------------------------------------------------- |
| cyclic decision service                      | valid | **clean** | **clean** | every decision `SUCCEEDED` with **`null`**; ERROR only in `DMNResult.getMessages()` |
| service with no `outputDecision`             | valid | ERROR     | **clean** | throws                                                                              |
| `variable/@name` mismatch on `inputData`     | valid | ERROR     | clean     | **succeeds, right answer** — the validator over-reports                             |
| required input absent or under the wrong key | valid | clean     | clean     | `SKIPPED` + `null`                                                                  |

QUOTED from the KIE strand, whose author reports reproducing the first row's trap in their own
first draft — a harness counting only `FAILED` statuses exits 0 on it. So the assertion set is:
**fail on any validator ERROR, any build ERROR, any `DMNResult` message at ERROR, any decision
`SUCCEEDED` whose value is `null`, and any decision `SKIPPED`.**

> **Necessary, and measured to be insufficient — amended 2026-07-27 under review.** Every row above
> is a case where a decision fails to _run_. None is a case where it runs and answers **wrongly**,
> and that is the failure this exporter actually ships: §13.2's identity probe has Camunda 8
> answering `true` — non-null, `SUCCEEDED`, no message at any severity — where the number `100000`
> was meant. The assertion set above passes that file.
>
> So both harnesses now take **`--cases`**: a list of `{name, context, expect}`, where `expect`
> pins the value of **every** decision. The check is symmetric — a decision with no expectation and
> an expectation naming no decision are each a failure — so adding a decision cannot silently
> widen the unchecked surface. `jl4/examples/dmn/reg-cf.cases.json` carries five contexts, 25
> expected values, and between them they fire all nine `<rule>` elements and both
> `<defaultOutputEntry>` paths; the single context this used to run left six of the nine
> unevaluated. The banner gained a term that is not a liveness claim:
> `25/25 value(s) as expected`.
>
> Discriminating power was checked in both directions rather than assumed: perturbing one expected
> value fails both harnesses (`= 80000 <<< EXPECTED 99999`) while still reporting `25/25 …
SUCCEEDED`, and removing one expectation fails both with `NO EXPECTATION for this decision`.
>
> **What no context on this exhibit can catch**, stated so its absence is not read as evidence:
> `annual income` and `net worth` are consumed only by `+` and `min`, both commutative, so
> exchanging those two bindings is invisible here. That is faithful to a statute symmetric in the
> two (17 CFR 227.100(a)(2)) rather than a gap a further case could close.

**Where it is wired: `l4-cli-test` (`jl4/tests-cli/Main.hs`), not `jl4-test`.** `jl4-test` has
neither `process` nor `directory` in `build-depends` and is the hermetic leg of `cabal test all`;
`l4-cli-test` already has both, already spawns `l4`, and already owns the `l4 export` golden
byte-comparisons at `:884-1075`.

**Skip-loudly contract — the part that must not be got wrong.**

1. **Locally**, an absent toolchain prints `SKIP  <checker>: <reason>` on stderr and exits 0; the
   hspec leg calls `pendingWith` with the same reason, which hspec renders as `# PENDING: …` and
   counts separately in the summary. A pending is visibly not a pass.
2. **In CI it cannot skip.** The `dmn-engines` job sets `KIE_CHECK_REQUIRED=1` and
   `CAMUNDA_CHECK_REQUIRED=1`, caches `~/.m2` in its own step, and runs **the two scripts
   directly**, greping their banners. It does not invoke `l4-cli-test`, and the Haskell job does
   not set `L4_DMN_ENGINE_CHECK` — so the gate is the job, and the hspec leg is the developer
   entry point (one command, the same harnesses, the same assertions). Neither pretends to be the
   other. (As written, this item claimed the job set `L4_DMN_ENGINE_CHECK=1` and reached the hspec
   path; it does not, and the deviation is recorded at §13.7-3.) The default `cabal test all` stays
   hermetic and network-free; the engine block is gated on `L4_DMN_ENGINE_CHECK=1` so it is a
   deliberate opt-in, not an accident of what happens to be installed. **This is the answer to
   "what if a checker is unavailable in CI": in CI, unavailable is a failure. Only a developer
   laptop is allowed to skip, and only loudly.**

   **An absent toolchain skips; a broken harness does not.** If `javac` fails, both scripts exit 1
   regardless of `*_CHECK_REQUIRED`, because absent tooling is a fact about the machine while a
   harness that will not compile is a fact about the repo. Added under review, from a live
   instance: a `KieDmnCheck.java` with an unbalanced brace reported `SKIP … javac failed` and
   exited 0, so the skip contract was concealing a repo defect on the very branch that introduced
   it.

3. **A skip can never be mistaken for a pass by a reader either.** Each harness prints a verdict
   banner on success (`KIE 8.44.0.Final VERDICT: 1 file(s), 5 case(s), 0 error(s), 0 warning(s),
25/25 decision(s) SUCCEEDED, 25/25 value(s) as expected`), and the hspec leg asserts the banner
   is present rather than asserting exit 0. A skip has no banner, so "exit 0 and nothing ran" fails
   the assertion. **The version substring is part of what is asserted**, in both the hspec leg and
   the CI grep, because the banner reports the version the harness observed off its classpath —
   which is the only token in it that is evidence about which engine looked at the file.
4. **Per-flavor reporting.** The suite runs the camunda golden through the Camunda harness and the
   kie golden through the KIE harness. If one harness is absent, the test output names that flavor
   **`UNEXERCISED`** rather than omitting it, so a green run always states which of the two engines
   actually looked at the artifact.

**If one strand were blocked.** They are separately gated by construction, so the camunda strand
lands whole while the kie hook is present-but-`UNEXERCISED`, or vice versa. Neither ever reads as
passing on the other's behalf. (As of this writing **neither is blocked**: both harnesses were run
against the goldens and probes while writing this section, from a clean Maven repo in the KIE case.)

### 13.7 Sequencing consequences

| Phase    | Added or changed by R7                                                                                                                                                                                                          |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **0** ✅ | `feelBase` uniformly on node `@name`, `variable/@name` and references (§5.2, §13.2). Was a red gate: the shipped golden failed both engines. Drop `output/@name` + `output/@typeRef` on single-output tables. Re-bless goldens. |
| **0** ✅ | Commit `etc/kie-dmn-check/` and `etc/camunda-dmn-check/`, wire both into `l4-cli-test`, add the CI job. Ordered **with** the naming fix, not after it — the harness is what proves the fix.                                     |
| **0** ✅ | `DmnFlavor`, `dloFlavor`, `drgFlavor`, `--flavor`, and the byte-identity test of §13.6. No output change.                                                                                                                       |
| **2**    | Unchanged: §5.2 is now known to be a shared fix, so no flavor branch here.                                                                                                                                                      |
| **5**    | BKM emission for **both** flavors (§13.3 retires the gate). `decisionService` per `§` for both flavors as grouping; `knowledgeRequirement` → service for `kie` only; `D-FLAVOR-NOSERVICE`. **This is where the goldens split.** |

**Phase 0 landed 2026-07-27, and was revised the same day under review.** Verbatim, from the
committed harnesses over the re-blessed `jl4/examples/dmn/expected/reg-cf.dmn`, at **both**
flavors (they are byte-identical today, so the four runs are two distinct artifacts):

```
KIE 8.44.0.Final VERDICT: 1 file(s), 5 case(s), 0 error(s), 0 warning(s), 25/25 decision(s) SUCCEEDED, 25/25 value(s) as expected
Camunda 8.7.6 (zeebe-dmn) VERDICT: 1 file(s), 5 case(s), 1 parsed, 0 error(s), 25/25 decision(s) evaluated, 25/25 value(s) as expected
```

Four deviations from the letter of §13.5/§13.6, all deliberate:

1. **`feelIdentText` implements steps 2–5 of §5.2's stage 1, not all six, and no stage 2.**
   NFC normalisation, the reserved-word suffix and `uniquifyIn` stay in Phase 2: the first
   two are independent of R7, and `uniquifyIn` needs a whole-DRG traversal rather than a
   per-name function. Two L4 names can therefore still collapse onto one FEEL name.

   **Amended under review.** Calling that "pre-existing" was too comfortable. Mapping space _and_
   `.` to `_` **widens** the collision domain: `first-time issuer` / `first time issuer` and
   `a.b` / `a_b` were distinct FEEL names before this change and are not now. And the only detector
   in the lowering, `D-SCOPE`, is computed from `freeTerms` and therefore covered exactly one of
   the three classes (inputData × inputData), leaving inputData × decision and decision × decision
   silent. All three are now reported by **`D-FEELNAME` at `Blocking`**, over the whole DRG
   namespace. Measured on both target engines (base = 100, `net worth` = 7):

   | Collision             | L4 says  | KIE 8.44                                             | Camunda 8.7.6     |
   | --------------------- | -------- | ---------------------------------------------------- | ----------------- |
   | inputData × inputData | 10 + 200 | validator 2× `DUPLICATE_NAME`, **build clean**, `20` | silent, `20`      |
   | inputData × decision  | 108      | validator 2× ERROR, decision `NOT_EVALUATED`, `14`   | silent, **`202`** |
   | decision × decision   | 203      | validator 2× ERROR, one `NOT_EVALUATED`, `202`       | silent, **`204`** |

   Note what that does **not** say: KIE does not _reject_ any of these. The `DUPLICATE_NAME`
   errors come from the validator leg, `KieBuilder` is clean, and the model deploys and answers.
   So neither engine refuses the file, neither returns what L4 said, and the two do not even agree
   on which element wins — while the **default** flavor is the one that says nothing at all.
   `Blocking` rather than `Lossy` for that reason: nothing was approximated, an answer was changed.
   Detecting is not resolving; `uniquifyIn` is still the fix, and it is still Phase 2.

2. **Spelling: `flavor`, not `flavour`** — §13.5 wrote the report target as
   `"DMN 1.3 (XML), camunda flavour"` once, against the American spelling used by `--flavor`
   and by every heading in this section. The code says `flavor` throughout.
3. **The CI job runs the two scripts directly, not `cabal test l4-cli-test` with
   `L4_DMN_ENGINE_CHECK=1`.** Same check, same file, but the script route needs no GHC, so
   the gate is a small Java job rather than a second full Haskell build. The hspec leg is
   still wired and is the developer-facing entry point; `KIE_CHECK_REQUIRED` /
   `CAMUNDA_CHECK_REQUIRED` do the not-allowed-to-skip work either way. **Consequence, stated
   because a code comment got it wrong and had to be corrected:** in CI, `dmnEngineCheck` in
   `jl4/tests-cli/Main.hs` always takes its outer `pendingWith`, because nothing in CI sets
   `L4_DMN_ENGINE_CHECK`.

4. **`--flavor` is rejected on `--to=dmn-md`, where §13.5 originally admitted it.** Recorded at
   §13.5; the flag is accepted only where something reads it.

**Not done, and not a deviation but a gap:** the `dmn-engines` job is **not** in the `unstable`
ruleset's required status checks (`gh api repos/legalese/l4-ide/rulesets/18543507` lists
TypeScript, Haskell, WASM, Nix). Until its context is added there — a repo-settings change, not a
code one — a failure of this job, including the deliberate `exit 1` the whole skip contract is
built around, does not block a merge.

### 13.8 What was not measured

Stated so nobody reads absence as evidence:

- **Zeebe deployment-time validation.** `zeebe-dmn` is the code Camunda 8 uses to _evaluate_; a
  real deployment additionally runs `DmnResourceTransformer` id/DRG constraints. Everything here
  covers evaluation semantics, not deploy-time rejection. Would need `zeebe-workflow-engine` or a
  broker in Docker.
- **Camunda Modeler desktop import**, which is K4's human check and deliberately not scriptable.
  dmn-js in headless Chrome is the closest scriptable proxy and passes (QUOTED); treat the desktop
  app as confirmation only. **A renderer is not an engine**, and this one especially so: dmn-js
  draws the decision-service file that the Camunda 8 _engine_ rejects at `parse()` (§13.4). A
  green render says the XML is well-formed against the metamodel and says nothing whatever about
  whether the model loads or answers. This bullet is where that evidence belongs; it was briefly a
  ✅ row in §13.4's engine table, which is the conflation this section exists to prevent.
- **`@camunda/linting`** is BPMN-only — there are no Camunda DMN lint rules on the npm side. So
  there is no JS-side Camunda check to add alongside `etc/validate-dmn.mjs`; the engine harness is
  the only Camunda opinion available.
- **Camunda 8 behaviour on a malformed BKM** (missing `knowledgeRequirement`, `@name` ≠
  `variable/@name`). KIE is loud on both; C8 is UNKNOWN. Worth a probe before Phase 5 ships BKM,
  since a silent C8 would change §6.2's invariants from "checked by the engine" to "checked by us".

### 13.9 Review triage — what was rejected, and on what measurement

Two reviews raised 20 findings against the R7 landing. Thirteen were defects and are fixed in
place (§11-R7's "What review changed"). The rest were **rejected on evidence**, and the evidence is
recorded here rather than in a commit message, because a rejection nobody can re-derive is worth as
little as a measurement nobody committed.

| Finding                                                                                                   | Verdict                    | Measurement                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| --------------------------------------------------------------------------------------------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "The flavor enters at the _report_, not at lowering; the commit is observationally a post-hoc rewrite."   | **Accurate, not a defect** | True and disclosed. `dloFlavor` has one consumer (`Lower.hs`) and `drgFlavor` one (`dmnReport`'s target), because the emitter has nothing flavor-dependent to emit yet. The seam is still the right shape: a rewriter can delete a `<knowledgeRequirement>` but cannot re-render the FEEL call text that referenced the service, and C8 fails whole-file at `parse()`, so "emit rich, strip later" has no safe intermediate. Kept, with the byte-identity tripwire as the forcing function. |
| "`Drg` derives `Eq` and now carries `drgFlavor`, so two `Drg`s emitting identical bytes compare unequal." | **Not a defect**           | No test compares `Drg` values; the byte-identity tests compare `emitDrg` output, which is the property that matters. Left as is deliberately.                                                                                                                                                                                                                                                                                                                                               |
| "`spaced = Text.unwords (Text.words t)` is a no-op."                                                      | **Correct — removed**      | It was: `Text.map keep` maps every whitespace character to `_`, and `squashed` already collapses `_` runs and trims. Verified across NBSP, tabs, leading/trailing and interior runs. Removed rather than left to read as a load-bearing invariant.                                                                                                                                                                                                                                          |
| "`l4 export --fidelity-report -o /dev/null` dies with a raw GHC backtrace."                               | **Real, out of scope**     | Reproduced. It is the fidelity-report writer refusing `/dev/null.fidelity.txt`, not a flavor concern, and it predates this branch. Left for the export-surfaces strand rather than fixed under an R7 commit.                                                                                                                                                                                                                                                                                |
| "R7 claims `spec:124`'s KIE-clean run 'was true when written and rotted silently'."                       | **Correct — reworded**     | Unverifiable by construction: the run was never committed, which is the strand's own argument. Now states the supportable claim — it is **not reproducible** — and draws the actual conclusion from it (§11-R7).                                                                                                                                                                                                                                                                            |

Two findings were rejected as **premises rather than defects**, and both are worth keeping visible:
the brief's "wire both engines the way KIE already is" assumed a committed KIE harness that did not
exist (there was none; the §13 measurements were ad-hoc), and reviewer B's "the harnesses have real
discriminating power" was accepted only after being re-checked in the failing direction, not the
passing one.

### 13.10 Sources

Probe sources and full engine output are in the session scratchpad, not the repo:
`c7/`, `c724/`, `c8/` (poms, `cp.txt`, Java probes), `kieflavors/` (harness, 13 axis probes, golden
variants, consolidated runs), `flavorcheck/` (the generic `C7Gen`/`C8Gen` drivers and the
`vE`/`vF` variants built for §13.2), `probes/`, and `triage/` (the review-round re-runs: the `annual income` identity probe, the three FEEL-name collision modules, the decision-service isolation, and the Camunda 7 re-measurement of the shipped golden). Doc corroboration: Camunda FEEL variable-names page
("It may not contain whitespaces … the name can be wrapped into single backquotes"), Camunda 7 DMN
reference (BKM, invocation and decision services absent from the supported list), Camunda 7
end-of-life notice.

---

## 14. Cross-ruling register

_Written 2026-07-27 by the pass that folded R3, R4, R5 and R6 into this document. Its purpose is the
interactions no single-ruling pass could see. Everything here is stated in the ruling it belongs to as
well; this section exists so that a later editor changing one ruling can find what else moves._

### 14.1 R2's residual risk (3) — the one obligation an already-answered ruling left open

R2 recorded: _"L11 is not covered by §4.2's tagged-union `Blocking`, because **R4 is still open**."_

**Status: discharged in part, residue named, and the residue does not block #923.**

| L11's population                                                    | after R4                                                                                                   |
| ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| projection off a **user-declared** payload union                    | **covered** — R4-a's reading form (1) is `Blocking` at the decision, so L11's single-decision traffic is 0 |
| projection off builtin **`MAYBE` / `EITHER`**                       | **not covered** — R8, opened by R4. **[E]** but empty: `m's val` on a `MAYBE NUMBER` is a type error       |
| R4-b's cross-decision guard/use split (caller guards, callee reads) | **not covered**, and R4-b is gated on L11 existing, so the dependency runs the other way                   |

**L11 must still stand on its own inside `LOCALLY-TOTAL`**, for the three reasons §4.2.1-4 gives:
§4.2's note is type-scoped where L11 is decision-scoped; only **6 of the 41** union-touching decisions
have the type at a `GIVEN`/`GIVETH` boundary at all; and inexpressibility and unsoundness are different
severities, which §2.4.2 already ruled cannot be merged into one note.

**The integrator check R2 asked for:** do **not** read "R4 answered" as narrowing L11's clause. R4
changes L11's _traffic_, never its _necessity_ — and **[M]** L11 still ships with **zero corpus
exercise on its accepting branch** (0 `Proj` sites over a multi-constructor enum across all 62 files),
which is why §10 Phase 4 now owes it a synthetic test.

### 14.2 R7's two flavors, against R3, R4, R5 and R6

R7's axis is **one bit**: may a `decisionService` carry
`<knowledgeRequirement><requiredKnowledge href="#a-decisionService"/>`, i.e. be _invocable_. KIE yes;
Camunda 8 throws `ClassCastException` in `parse()` and rejects the whole DRG. Default `camunda`.

| ruling | flavor-sensitive?                                           | statement                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ------ | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **R3** | **No** — and it is R7's own fix                             | The fold is one policy that is clean on KIE 8.44, Camunda 7.23, Camunda 8.7.6 and feelin alike. **[D]** R7 landed exactly it as `feelIdentText` on PR #160, from an independent argument (Camunda tokenises `annual income` as `annual in come` and returns a **boolean**). An earlier R3 draft said Camunda's problem is spaces and "that is §5.2 step 3, not R3"; step 3 **is** R3, so R3 _is_ the Camunda naming fix. Corrected in §5.3.6.                                         |
| **R4** | **v1 no, R4-b yes**                                         | R4-a emits nothing engine-specific and its `Lossy` tables are ordinary S-FEEL. **[E]** The two working union tables build with 0 messages in KIE 8.44. R4-b's context-with-discriminant encoding has **all** its engine evidence from KIE plus feelin; **[U]** Camunda 8 untested, and §4.2.1-3's missing-payload-component hole must be re-probed on both before it ships.                                                                                                           |
| **R5** | **No at the decision level; the service level is R7's bit** | §6.3.7 is a spec requirement and **[E]** KIE 8.44 and Camunda 8.7.6 both reject an emitted cycle. §6.3.10 constrains a service's requirement subgraph **whether or not it is invocable**, so `checkDrg` is the same routine on both flavors. **The one place R7 changed an R5 conclusion:** the review's cost objection is measured in Camunda 7, which §13.1 rules out of scope (§6.4.8).                                                                                            |
| **R6** | **Structure no, payoff yes**                                | A bare `decisionService` is inert-but-safe on both flavors, so rule 1's "uncalled members are the `outputDecision`s" is structurally flavor-independent. But the §2.3 payoff that motivates it — `every q in c.purposes satisfies Article 6(q)…` — needs the service to be **invocable**, i.e. `kie`. On the default `camunda` flavor **rule 1 rests solely on the tested-entry-point evidence** (129 of 141 roots), which is sufficient and is a different argument. §2.5.9 says so. |

**One flavor fact this pass adds.** **[E]** R7's `D-FEELNAME` is `Blocking` on both flavors and fires
on 47 of the 51 exported corpus modules — but **all 67 of its groups are the "N `inputData` for one
`GIVEN` name" case**, which §2.1's un-lifting removes. That makes it a **pre-un-lifting** detector, and
§14.3 is the consequence.

### 14.3 Contradictions found and reconciled

Four places where two rulings, or a ruling and the existing text, could not both stand.

1. **R6 rule 1 vs R7's `D-FEELNAME` — a detector that switches off when the hazard arrives.**
   `D-FEELNAME` counts DRG elements sharing a FEEL name. **[E]** On `GCO-first-version.l4` it reports
   _"`s` is the FEEL name of 2 elements"_ at `Blocking`, which is exactly R6's type-conflict hazard.
   **After un-lifting there is one element, and the note goes quiet.** Reconciled by raising §7's
   repurposed `D-SCOPE` — whose ruled predicate is already "two same-named terms with different
   declared types" — to **`Blocking`**, so detection is handed from one `Blocking` note to another
   rather than from a `Blocking` note to nothing.

2. **R3's fold vs R3's own "the Camunda problem is not R3".** §5.3.3 says step 3 "is replaced by",
   and step 3 is where the space goes. The two sentences contradicted each other in the same draft.
   **Resolved in favour of the first**: R3 is the naming fix, flavor-independence is about the
   _answer_ (one policy for both engines), not about the _effect_ (which is largely on Camunda).

3. **R5's `D-CYCLE` vs R2's rehabilitation of `ror together`.** §2.4.3 establishes that the ruled
   criterion certifies `ror together` **terminating and total**; R5 flags it `Blocking` in Phase 0
   under §6.3.7. Both are correct — `DMN-SAFE` is definedness, §6.3.7 is DMN's own well-formedness
   `SHALL`, and a total decision can still be ineligible to be a DMN node — but a reader meeting both
   cold would think one wrong. Recorded in §6.4.7, with the practical note that **[E]** `ror together`
   is already `D-LITERALEXPR` `Blocking` today, so nothing changes hands.

4. **R6's filter in `Lower` vs R5's check on the `Drg`.** Two rulings placing a new pass, in opposite
   places, in the same document. Reconciled on a principle rather than a coin flip: **an emission
   decision belongs in `Lower`; an artifact property belongs on the finished `Drg`.** R6 decides
   _what to emit_ (rule 2 drops nodes) and is `Lower`'s; R5 checks _whether what was emitted is
   well-formed_ and is `checkDrg`'s. They compose by construction — `checkDrg` runs over whatever
   `Lower` produced — so there is no ordering dependency (§2.5.9, §6.4.7).

### 14.4 Sequencing constraints created by these four rulings

- **`uniquifyIn` may not lag `feelBase`** (R3, §5.3.4). Both are Phase 2; **[D]** PR #160 has already
  shipped `feelBase` without `uniquifyIn`, which is why `D-FEELNAME` is `Blocking` there — that is the
  correct interim, and R3 requires it to be extended to the projection namespace where **[E]** the one
  executed corpus collision produces a wrong number.
- **R4-b may not ship before L11 and the tag-guard invariant**, and now also not before the
  missing-payload-component obligation is discharged (§4.2.1-3). R4-a ships at Phase 3 regardless.
- **R8 must be ruled before Phase 3 emits a type for `MAYBE`/`EITHER`.** It is the only ruling this
  pass leaves open, and §11-R8 says what would close it.
- **R5 ships at Phase 0** and depends on nothing here.
- **§2.4.3's census re-run (Phase 4) must use R6's post-filter population.** Dropping ~46% of
  decisions changes every denominator in that table, and running it against the old population would
  silently reproduce the error §2.4.3 was written to correct.

  **RE-RUN 2026-07-31 (Phase 4's build), against the real structural `TERMINATES` and the
  post-filter population, via `l4 export --to=dmn --fidelity-report` over all four corpora**
  (Housing 48 modules exported + 1 declaration-only refusal; Reg CF `regcf.l4` + `regcf-wizard.l4`;
  Charities 11 + 1 declaration-only; GCO 4 — **no timeouts**: the §14.6 900 s wall is gone since
  the AND/OR overload fix, the full sweep runs in seconds). Kept (post-filter) decisions: Housing
  326, Reg CF 134, Charities 314, GCO 71 — **845 total**. `D-PARTIAL` notes 35, of which
  **13 are root refusals** (L3 ×2 Reg CF; `PURE` ×6 Housing; `TERMINATES` ×5 — `rent spine` ×3,
  `ongoing reporting obligation`, one further) and **22 are `TOTAL` contagion** through callers.
  Root-refusal rate **13/845 = 1.5%** of kept decisions (4.1% with contagion); Charities and GCO
  refuse **zero**, now firmly (their exports completed). The ruled criterion behaves as designed on
  the discriminating pair: **`ror together` is ACCEPTED** by the structural check (no note) while
  `rent spine`'s `NUMBER`-measure recursion refuses. Tier-2 (`D-BKM`): Housing 9, Reg CF 14,
  Charities 9, GCO 6. Drops: `D-FIXTURE` 784 (Housing 423 / Charities 282 / GCO 62 / Reg CF 17),
  `D-REGULATIVE` 130. `D-PARAMTYPE` fires live on Charities ×5 and GCO ×3 (§2.5.3's measured GCO
  conflict, confirmed in production), zero on Housing and Reg CF. **What this re-run did not
  score:** a per-decision tier-1 denominator (the old table's 654/541 columns) — the fidelity
  report names merges, refusals and drops but not each un-lifted singleton, so the old proxy's
  0.8%/0.2% cells have no successor figure; deriving one needs a driver over `L4.Dmn.Analysis`
  and is owed by whoever next needs the rate, not by the report format.

### 14.5 What review changed across all four rulings

Per-ruling records are in §2.5.10 (R6), §4.2.1-9 (R4), §5.3.8 (R3) and §6.4.8 (R5), following the
convention §11-R2 established. The summary, so a later editor does not silently un-change them:

**Ten defects changed a ruling.** R3 owed an unwritten normative sentence whose absence stops the
committed golden loading in KIE, and its collision census scored a function nobody rules. R4's baseline
section was wrong in both directions and its cost figure was wrong by 3× in the direction that mattered,
which forced the refusal from one severity to two; R4-b turned out to have an unfound silent-`null`
hole of its own. R5's SCC side condition was missing with both defaults wrong — the same defect class as
R2's `LEAST`-for-`GREATEST` — and its own overturning condition was already true on the record. R6's
rule 1 was type-blind, its fixture criterion dropped a statute, its R1 argument overcounted by ~2×, and
its inert detector missed the corpus's dominant idiom.

**Three reviewer findings are rejected or narrowed on measurement, and the measurement is shown:**

| finding                                                                       | verdict                                                                                                                                                                                                                                                                                                                                            |
| ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **R5 D1** — _"72 decisions go from parseable to a whole-file parse failure"_  | **Rejected as a cost, upheld as a fact.** **[E]** The 72 reproduce exactly in **Camunda 7.23**, which R7/§13.1 rules out of scope. On KIE 8.44 and Camunda 8.7.6 all four models already fail today, and all four decisions are already `Blocking`.                                                                                                |
| **R3 D1** — _"the hole is live, not latent; 11 collisions in 5 files"_        | **Narrowed.** **[E]** In the DRG namespace, across 51 exported corpus modules under the ruled fold as shipped, fold-created collisions are **0**. Two of its three witnesses cannot reach the exporter (`dogs.l4` does not typecheck; `§` names are not emitted). Upheld on the third, which this pass strengthened into an executed wrong answer. |
| **R4 review §5** — _leave nullary-only `CONSIDER`s to L1 with no note at all_ | **Adopted for the refusal, declined for the note.** R4 emits `D-SUMTYPE` at `Lossy`, because **[E]** the payload constructor has no cell and no `allowedValues`, so the _domain_ is lost even where the answer is right — and §3.3.1's whole argument is that a declared incompleteness is information the artifact should carry.                  |

### 14.6 Measurement coverage of this pass, stated rather than implied

**[E]** The corpus export used for §5.3.4 and §2.5.6-4 covers **51 of 62 modules**: all 49 Housing
files bar `housing-act-common.l4`, `regcf.l4`, and 2 of 12 Charities modules. `charities-common.l4`,
`part-3-charity-test.l4` and `housing-act-common.l4` exceeded a **900 s** per-file timeout, which is
the same wall §6.4.2 hit at 120 s and is a finding in its own right: **a flagship corpus module takes
more than fifteen minutes to export.** Every zero reported from that run is therefore firm for Housing
and Reg CF and **not established for most of Charities**. Nothing in these four rulings turns on a
Charities zero; §2.5's Charities figures come from `l4 ast`, not from export.

> **OBSOLETE 2026-07-31: the 900 s wall is gone.** The Phase 4 census re-run (§14.4) exported the
> full four-corpus sweep — `part-3-charity-test.l4` included — in seconds per file, the AND/OR
> overload blow-up having been fixed in the interim (smucclaw#929, PRs #168/#169). The only two
> modules that do not export are `housing-act-common.l4` and `charities-common.l4`, both
> declaration-only (zero `MEANS`), refused by the pre-existing empty-model check. Charities zeros
> are now as firm as Housing's.

---

## 15. Law time: binding, interval tables, and the `D-RULEDATE` family

**Status: IMPLEMENTED 2026-07-30. Every number below was measured on this tree after the change;
the before-column numbers are from the goldens as they stood at `8235b2e0`.**

§2.4's clause **L10** is the only earlier mention of `RULES EFFECTIVE DATE` in this document, and it
is a _totality_ clause for Phase 4's un-lifting analysis. **Lowering law time was greenfield: there
was no prior ruling to reconcile or contradict.**

### 15.1 The defect, measured

**[E]** On the corpus golden as shipped at `8235b2e0`, `RULES_EFFECTIVE_DATE` occurred exactly once
(`jl4/examples/dmn/expected/regcf-corpus.dmn:391`, inside `decision_the_rules_in_force_include`) and
was bound by **nothing** — no `inputData`, no `variable`, no `itemDefinition`. A free FEEL name no
engine can resolve. **[E]** `grep -c RULES regcf-corpus.fidelity.txt` was **0**: the fidelity report
never mentioned it. A model whose every dated answer depended on an unsupplied input, and an
artifact that said so nowhere.

**[D]** The cause was one predicate. `decideFreeTerms` (`jl4-core/src/L4/Dmn/Lower.hs`) filtered
free references on `u.moduleUri == uri`; builtin uniques carry
`builtinUri = toNormalizedUri (Uri "jl4:builtin")`, so law time never became an `inputData`, never
entered `inputByUnique`, and therefore never got an `informationRequirement` from `classifyRef`. It
rendered through `feelIdentIn`'s _fallback_ and came out tagged `SFeel`, which is why no note fired.

### 15.2 Binding (D1)

Law time is an **ordinary free term**, not a special case in the emitter: `decideFreeTerms` admits
`TC.rulesEffectiveDateUnique` alongside module-local uniques, `freeTermSrc` gives it
`TC.rulesEffectiveDateBuiltin` (which **is** `date`), and the `inputData`, its `typeRef="date"`, its
resolved FEEL name and every requirement edge fall out of existing machinery with no new emitter
code.

The FEEL name stays `RULES_EFFECTIVE_DATE` and the term is **appended** to `freeTerms` rather than
interleaved in source order. A `GIVEN` is written at a source position and source order is the right
key for it; a builtin is written at no source position, so its "first mention" is an accident of
which decision happens to read law time first. Appending also keeps the existing `inputData` block
byte-identical, which is what made the binding diff reviewable.

Requirement edges are computed at IR level over `freeRefs`, never by scanning emitted FEEL. **[E]**
That is not a style preference: `regcf.l4:479-481`'s COVID-window decision reads law time twice and,
before §15.4's date-literal fold, its emitted text contained no `RULES_EFFECTIVE_DATE` token at all,
so a text scan would have missed it.

### 15.3 Interval tables (D2)

A newest-first chain of rule-date guards becomes a single-column table over the rule-date input with
half-open interval cells and `hitPolicy="UNIQUE"`. For arms dated `d₁ > d₂ > … > dₙ` the cells are
`>= date(d₁)`, then `[date(dᵢ)..date(dᵢ₋₁))`, then a floor row `< date(dₙ)` carrying the `OTHERWISE`
— which is exact, total over the date axis, and pairwise disjoint.

**[D]** This is not merely an executability fix. DMN 1.3 grammar rule 18 makes a unary-test
`endpoint` a `simple value`; rule 19 admits a `simple literal`; rule 33's `simple literal` includes a
date-time literal, i.e. `date("YYYY-MM-DD")`. So the emitted cells are inside **S-FEEL**, which is
the fragment DMN's own completeness/consistency analysis is defined over. The table moves _into_ the
analysable fragment; it does not merely become runnable.

**[D] The generic table path cannot produce this and was not asked to.** `policy` in
`rowsToDmnWith'` requires `rows.grDisjoint`, which comes from `guardsDisjoint`
(`L4/Viz/GuardedRows.hs`); its `exclusive` relation has no `(Geq, Geq)` case, so two `>=` guards are
never exclusive there and every dated chain would stay `FIRST` no matter what the cells said. `D2`
therefore constructs its own `DecisionTable` and _reuses_ `tableNotes` for the note families that
still apply — so the output-side families (`D-NONFEELOUTPUT`, `D-COMPUTEDOUTPUT`) still see exactly
the bodies they saw before.

The recogniser is conservative and all-or-nothing, in the manner of `L4/OpenFisca/Lower.hs`'s
`splitDated`: every arm must be a single-conjunct rule-date guard against a foldable date, no arm
body may itself be a chain — **and the `OTHERWISE` counts as an arm body for that test**, because on
the ordinary path `expandOtherwise` splices a nested catch-all's rows into the table — and the dates
must be strictly descending. A chain that references law time and does **not** match takes the
existing path unchanged and keeps its existing findings; §15.8 names the corpus witnesses. See
**R9**, **R10** and **R11**.

**[D] The three pre-tabulation refusals are restated on this path, because it does not go through
`rowsToDmnWith'`.** `rowsToDmnWith'` rejects an effectful guard, a regulative body and an empty
chain before it builds anything; `datedTable` is called directly, so `datedChain` answers `NotDated`
for the first two and routes the decision back to the ordinary path and its existing
`RegulativeBody` / `EffectfulGuard` fallback. (`NoRules` is unreachable: `Dated` means a non-empty
`arms`.) This is not defensive: the corpus already writes `IF cond THEN <regulative> ELSE
<regulative>` in three places, and one law-time guard away, a `UNIQUE` decision table of verbatim L4
obligations would have shipped with `D-NONFEELOUTPUT` — a statement about _rendering_ standing in
for the categorical fact that DMN cannot hold an obligation at all. Witness:
`jl4/examples/dmn/not-ok/dated-chain-regulative.l4`.

Every ordinal a `D-DATEDCHAIN` message quotes ("arm 3 of the chain") is an index into the chain's
own rows, so the same number names the same source arm in all three refusal messages.

### 15.4 FEEL dates

`FeelValue` gains `VDate !Day`, rendered `date("YYYY-MM-DD")`. Two separate concerns, deliberately
not conflated:

- **in an expression**, only the _literal_ form folds: `Date d m y` over three integer literals
  becomes `date("…")`, tagged `SFeel`. A **nullary reference to a named date constant keeps
  rendering as its FEEL name** — it is a DMN decision variable, and inlining its value into an
  expression would erase a reference the DRG records.
- **in a table cell**, a nullary reference to a date constant _does_ fold to a `VDate` endpoint,
  because inlining is what an endpoint means.

`Date` is **lenient** (`daydate.l4:52-56` rolls `Date 32 1 2024` forward to 2024-02-01), so the fold
**refuses** an out-of-range component rather than replicating the roll: putting a date in the
artifact that the source does not obviously say would be worse than falling through. `YMD` is not
folded at all — its body is an `IF … THEN candidate ELSE <ASSUME bottom>`, so a structural match
would silently drop the refusal arm.

Disjointness became **kind-aware** in the same change. `numberOf` was replaced by `ordKey`, which
returns an _axis tag_ alongside the position, and `satisfies`/`cmpDisjoint` degrade to "assume they
might overlap" across axes. Without that, a `VNum` cell and a `VDate` cell could have been declared
disjoint on Modified-Julian-Day arithmetic that means nothing.

**dmnmd refuses dates outright rather than rendering them.** `mdValue` became
`mdConstant :: FeelValue -> Maybe Text`, returning `Nothing` for `VDate`, so every table carrying a
date cell raises `D-MD-CELLSYNTAX` Blocking and is honestly omitted. dmnmd's cell grammar has no
date datatype: `>= 1994-04-01` would have been emitted and then misread by dmnmd's numeric parser.
That is not a workaround for the gap; it **is** the gap being reported.

### 15.5 The three codes (D3)

`D-RULEDATE` Advisory (one per DRG, when the input was bound), `D-RULEDATE-UNBOUND` Blocking (one
per decision that _rebinds_ law time with `EVAL UNDER RULES EFFECTIVE AT`), `D-DATEDCHAIN` Blocking
(one per chain that looked dated and could not be tabled). **Three codes and not one code with three
severities**, because §7's own header defers the two-severities-on-one-code shape to a re-ruling
against `FIDELITY-SEVERITY-AXIS-SPEC.md` §5, and because these are three different predicates rather
than three intensities of one.

**The invariant:** for every emitted `Drg`, if any decision reaches `RULES EFFECTIVE DATE` then
either a bound `inputData` plus exactly one `D-RULEDATE` Advisory is present, or at least one
`D-RULEDATE-UNBOUND` Blocking is. Asserted over every golden subject in `jl4/tests/DmnExport.hs`
("never references law time without a binding or a Blocking note"), not left to the goldens.

**[E] The Blocking arm is not defensive.** `regcf.l4:1143-1238` holds 15 `EVAL UNDER RULES EFFECTIVE
AT` call sites, each inside its own top-level `DECIDE`, and the note fires **15 times** on the
corpus. A DMN DRG has one global rule-date input and no scoped rebinding, so a module that both
reads and rebinds law time cannot be modelled by that input, and the artifact must say so.

**`D-RULEDATE-UNBOUND`'s claim is scoped to what was emitted.** `EVAL UNDER RULES EFFECTIVE AT` can
sit inside an _arm body_ of a chain that still tabulates, and "no DMN engine can evaluate this
decision" would then be false about the rest of a table an engine will happily run. The code
therefore carries **two message forms**, chosen from the emitted `dcnLogic`: a boxed literal gets the
whole-decision claim, and a decision that still ships a table gets "a sub-expression of `X` … even
though the surrounding decision table is". On today's corpus all 15 take the first form — and that
is now an assertion (`jl4/tests/DmnExport.hs`, "scopes `D-RULEDATE-UNBOUND`'s claim to what was
emitted", an invariant over every subject) rather than a fact the note quietly depended on.

**[U]** Six further builtins (`valueAt`, `evalUnderValidTime`, `everBetween`, `alwaysBetween`,
`whenLast`, `whenNext`) were nominated as also stamping a temporal context. They belong to the
valid-time / transaction-time axis, not the rule-version axis, and their behaviour was **not**
verified. v1 matches `evalUnderRulesEffectiveAtUnique` only. Adding the others must be preceded by a
measurement, because it would change counts with nothing behind it.

### 15.6 Engine measurements

**[E] Measured 2026-07-30** on `jl4/tests-cli/fixtures/dmn-date-probe/date-axis.dmn`, a hand-written
fixture kept permanently for the same reason `dmn-xsd-order` is: the emitter cannot produce the
questions, only the answers.

| question                                                           | KIE 8.44.0.Final                                        | Camunda 8.7.6 (zeebe-dmn)                               |
| ------------------------------------------------------------------ | ------------------------------------------------------- | ------------------------------------------------------- |
| `<annotation>` after `<output>`, `<annotationEntry>` with no `@id` | `XSD    valid` (Xerces), `VALID  clean`, `BUILD  clean` | parses (`1 parsed`)                                     |
| `>= date("…")` / `[date("…")..date("…"))` / `< date("…")` cells    | evaluate; `6/6 value(s) as expected`                    | evaluate; `6/6 value(s) as expected`                    |
| Java type for a `typeRef="date"` input                             | `java.time.LocalDate`                                   | `java.time.LocalDate`                                   |
| what a **date-valued decision** returns                            | `java.time.LocalDate`                                   | an ISO-8601 **`String`** — MessagePack has no date type |

The last row is the one asymmetry, and it is a measurement rather than a claim: before
`CamundaDmnCheck.sameValue` gained a `LocalDate`-vs-`String` branch, the probe reported
`3/6 value(s) as expected` on three **correct** answers. The fixture convention is the explicit tag
`{"$date": "YYYY-MM-DD"}` rather than an ISO-shape sniff, because these harnesses convert by
declared type and never by appearance (`etc/kie-dmn-check/src/main/java/KieDmnCheck.java`, the
`BigDecimal` note on `jsonToFeel`).

**A malformed `$date` is a FIXTURE error on both engines** — measured 2026-07-31 by feeding
`{"$date": 20240101}`, which now prints
`` `{"$date": ...}` wants an ISO-8601 YYYY-MM-DD string, got: 20240101 `` and exits 2 on each.
The two predicates used to disagree: KIE accepted any non-null node and died with an uncaught
`DateTimeParseException`, while Camunda tested `instanceof String` and silently degraded the same
fixture to an ordinary map, reporting it as a value mismatch. One malformed fixture, two different
wrong answers.

**[E] The positive fixture is only half the measurement, and 2026-07-31 added the other half.**
A valid file validating shows that a valid file validates; it is equally consistent with Xerces
ignoring `<annotation>`/`<annotationEntry>` entirely, which is the failure the Q4 row claims to
exclude. `date-axis-badannotation.dmn` is `date-axis.dmn` with an `@id` on each `<annotationEntry>`
and **nothing else changed** — asserted line-by-line in `l4-cli-test`, so the pair cannot drift and
leave a red negative failing for some other reason. Measured, verbatim:

| engine                    | on the negative                                                                                                                                          |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| KIE 8.44.0.Final          | `XSD    INVALID`, ×3 `cvc-complex-type.3.2.2: Attribute 'id' is not allowed to appear in element 'annotationEntry'`; **`BUILD  clean`**, 6/6 as expected |
| Camunda 8.7.6 (zeebe-dmn) | `PARSE  INVALID: DmnModelException: Unable to parse model`; `0 parsed, 1 error(s)`                                                                       |

Note what Drools does **not** do: it builds the malformed file anyway and answers every case
correctly. So "a malformed emitter would fail in the engine" is false of Drools, exactly as it is
for the `dmn-xsd-order` pair, and the schema leg is the only thing between a malformed emitter and a
shipped artifact.

### 15.7 Measured before/after

**[E]** `cd jl4/examples/dmn/expected && grep -o "\[D-[A-Z-]*\]" regcf-corpus.fidelity.txt | sort | uniq -c | sort -rn`

| code                 | before  | after   | mechanism                                                                                      |
| -------------------- | ------- | ------- | ---------------------------------------------------------------------------------------------- |
| `D-LITERALEXPR`      | 89      | **89**  | unchanged — the date constants and the predicate are still boxed literals, but now _evaluable_ |
| `D-RENAME`           | 37      | **37**  | `RULES_EFFECTIVE_DATE` collides with nothing                                                   |
| `D-NONFEELINPUT`     | 29      | **6**   | the 23 `` `the rules in force include` OF … `` columns became one FEEL `date` column each      |
| `D-UNDECOMPOSABLE`   | 28      | **5**   | the same 23 guards no longer fall back to boolean columns                                      |
| `D-SCOPE`            | 9       | **9**   | —                                                                                              |
| `D-ORDERDEPENDENT`   | 9       | **1**   | 8 dated tables went `FIRST` → `UNIQUE`; only `financial statements required` remains           |
| `D-COMPUTEDOUTPUT`   | 9       | **9**   | —                                                                                              |
| `D-NONFEELOUTPUT`    | 4       | **4**   | `the applicable measure …`'s outputs are still verbatim L4 calls                               |
| `D-INLINEDLOCAL`     | 2       | **2**   | —                                                                                              |
| `D-RULEDATE-UNBOUND` | —       | **15**  | new, Blocking                                                                                  |
| `D-RULEDATE`         | —       | **1**   | new, Advisory                                                                                  |
| `D-DATEDCHAIN`       | —       | **0**   | the corpus is well-ordered                                                                     |
| **blocking**         | **122** | **114** | 122 − 23 + 15                                                                                  |
| **lossy**            | **46**  | **46**  |                                                                                                |
| **advisory**         | **48**  | **18**  | 48 − 23 − 8 + 1                                                                                |

> **The blocking total falls by only 8 net, because 15 new Blocking notes appear — and that is the
> point.** The complaint this section answers is that the report was _silent_ about law time; making
> it speak necessarily adds notes. A reader who scores this change by the blocking total will
> misread it.

**Structure.** `<inputData>` 67 → **68**; `<decision>` stays **102**; `<decisionTable>` stays **11**,
of which `hitPolicy` is now **10 `UNIQUE` / 1 `FIRST`**. Each of the 8 dated decisions lost its
`requiredDecision` edges to the guard predicate and the regime constants and gained
`<requiredInput href="#input_rules_effective_date"/>` (R11), with `_ir<n>` renumbering inside them.
Eight `<annotation name="regime"/>` elements are new.

**Markdown carrier.** `D-MD-NONIDENTCOLUMN` 30 → **7** (−23, the backticked columns are gone);
`D-MD-CELLSYNTAX` 4 → **33** (+29 — the note is **per rule**, and the 8 dated tables contribute 31
rules, 2 of which already carried it for a parenthesised output). Markdown blocking 126 → **132**.
`D-MD-NOLITERAL` (91) and `D-MD-NODRG` (1) are unchanged, and `D-MD-TYPE` does **not** appear for the
date columns, because `expressible t` is false once the cells are refused.

**`D-MD-CELLSYNTAX` names the cause it actually found (amended 2026-07-31).** It used to recite the
whole enumeration — "a negation, a half-open or non-integer range, or an output with parentheses or
a comma" — which became a **misdiagnosis** the moment dates existed: `>= date("2024-01-01")` is none
of those, and on this corpus that wrong cause would have been the majority reading (31 of the 33
instances name a date; only 4 name an output). `cellSyntaxReason` now reports the reasons it can
demonstrate for the rule in hand, joined with `;` when a cell trips more than one — a half-open date
range trips both, and both are true and independent obstacles.

**[E] `sumtype.*` (4 files) is byte-identical, and so are `reg-cf.dmn`, `reg-cf.dmn.md` and
`reg-cf.fidelity.txt`.** Neither module contains `RULES EFFECTIVE DATE`, so the date-literal fold
and `constantOf`'s date arm reached nothing in them, which is what those unchanged goldens assert.
`reg-cf.md.fidelity.txt` **did** move, by exactly one line, and only because of the message repair
above: its one `D-MD-CELLSYNTAX` now says "an output dmnmd cannot read: parentheses, a comma, or an
expression outside S-FEEL" instead of reciting all four causes. That is the repair working on a
module with no dates in it at all.

### 15.8 Chains that reference law time and are NOT dated chains

They take the existing path and keep their existing findings. Named, so the claim is checkable:

| decision                                             | why it is not a dated chain                      | what stayed                                         |
| ---------------------------------------------------- | ------------------------------------------------ | --------------------------------------------------- |
| `financial statements required` (`regcf.l4:498-503`) | **zero** rows are law-time guards, so `NotDated` | `FIRST`, 5 `D-NONFEELINPUT`, its `D-ORDERDEPENDENT` |
| `investment limit` (`regcf.l4:416`)                  | not a guarded chain at all                       | its 1 `D-NONFEELINPUT`                              |
| the COVID-19 window (`regcf.l4:479-481`)             | a conjunction, not a chain                       | `D-LITERALEXPR`; its body is now evaluable FEEL     |
| the 15 `EVAL UNDER RULES EFFECTIVE AT` decisions     | not chains                                       | `D-LITERALEXPR`, **plus** `D-RULEDATE-UNBOUND`      |

**`NotDated` is not the same outcome as a refusal, and the difference matters for testing.**
A chain that matches **zero** rule-date arms is an ordinary chain and gets no note; a chain that
matches **some** rows and not others is a Blocking `D-DATEDCHAIN`, because mixing a law-time arm with
an ordinary one is exactly how a temporal bug hides. `financial statements required` is the first
kind. The second kind has **no witness in the corpus at all** — `D-DATEDCHAIN` is 0 here — which is
why it has its own negative fixture, `jl4/examples/dmn/not-ok/dated-chain-mixed.l4`. Before
2026-07-31 it had neither a fixture nor a test, and the test _named_ for it asserted the first kind.

### 15.9 What the annotation column can carry

`@ref` **is** machine-readable — `L4/Lexer.hs`, `Extension.ref` in `L4/Syntax.hs`, read with
`annRef`/`getRef` — and every Reg CF regime constant carries one (`regcf.l4:102,106,110,114`). It
attaches to the **`TopDecl`** (`L4/Parser/ResolveAnnotation.hs`), which `Lower.hs` used to discard at
`decides = [d | Decide _ d <- decls]`.

**[E] Measured, not assumed.** The exporter now binds that annotation and reads it joined with the
inner `MkDecide`'s, and the emitted corpus golden shows the citation arriving:

```xml
<annotationEntry>
  <text>the 2021 amendments — 86 FR 3496 (Rel. 33-10884), instr. 3 — the 2020 amendments, eff. 2021-03-15 (main.l4:111:1-112:43)</text>
</annotationEntry>
```

So the `TopDecl` annotation is where the ref lives, and the `<|>`-style join is what made the
question not block the build. The `@ref` keyword itself is stripped: it is L4 syntax, not part of
the citation.

Ordinary `--` comments are **not** available: they live in `CsnCluster` trailing tokens for
exact-print (`L4/Annotation.hs`) and are not indexed by node, so a citation written as a comment
cannot reach the column. That distinction matters, because "citations are/are not machine-readable"
is exactly the kind of claim that gets copied and sharpened.

The column carries, per row: the L4 regime-constant name; the `@ref` text when one is attached; and
the constant's own `file:line`. An **inline**-idiom arm names no constant, so it carries only
`from <day>` — and the exhibit's `tourist refund minimum spend` is there so that limit is visible in
a golden rather than asserted here.

**dmnmd ignores `dtAnnotations` and emits no new code.** That is defensible only because every dated
table is already omitted from the markdown by `D-MD-CELLSYNTAX` (§15.4), so no table's annotation is
actually being dropped. The day a dated table becomes dmnmd-expressible, the dropped annotation
needs a `D-MD-NOANNOTATION`.

### 15.10 The exhibit

`jl4/examples/dmn/gst-rate.l4` (golden stem `gst-rate`, a fourth `goldenSubjects` row) is the
smallest module that exercises law time end to end: two chains — one PREDICATE idiom, one INLINE —
both lowering to single-column `UNIQUE` date-interval tables, plus one downstream arithmetic
decision so a date is shown driving a number driving a number.

The INLINE chain writes **one arm against a named regime constant and one against a bare
`Date d m y`**, because those are the two things an inline right-hand side may be and they reach
different code (`constantDay`'s one hop, then the literal fold). It is also where the annotation
column's limit is visible in a golden: the named arm carries the constant and its `@ref`, the
literal arm carries only `from 1994-04-01`.

**[E] Amended 2026-07-31.** `jl4/examples/dmn/gst-rate.cases.json` drives it through **both** engines
with **ten** rule dates: `70/70 value(s) as expected` on KIE 8.44.0.Final (0 errors, 0 warnings) and
on Camunda 8.7.6 (1 parsed, 0 errors). `GST rate percent` lowers to four rules and therefore **three
seams** — 2024-01-01, 2023-01-01, 1994-04-01 — and every one is straddled by a day-of/day-before
pair, plus a case well before commencement for the floor row. The first version straddled only the
newest seam, so an off-by-one on the middle interval's low end, or on the floor row's
`< date("1994-04-01")`, would have passed `42/42` green while the cases file claimed to pin the
convention. This is the OpenFisca parameter file re-expressed as engine-evaluable DMN.

Six negative fixtures under `jl4/examples/dmn/not-ok/` are **not** golden subjects, so no `.dmn` is
emitted for them and `etc/validate-dmn.mjs` is unaffected. All six are asserted from
`jl4/tests/DmnExport.hs`, in the shape of `l4-cli-test`'s existing "rejects a mis-ordered dated
BRANCH (ascending arms)". The first four are Blocking **refusals**; the last two are **declines**,
which carry no note because nothing was lost:

| fixture                           | the arm of R10 it witnesses                                                  | outcome    |
| --------------------------------- | ---------------------------------------------------------------------------- | ---------- |
| `dated-chain-misordered.l4`       | arms ascending, so the derived intervals would be empty                      | refusal    |
| `dated-chain-duplicate-date.l4`   | two arms on one day, refused by the same strictly-descending predicate       | refusal    |
| `dated-chain-rolling-date.l4`     | `Date 32 1 2024`, which L4 rolls to 2024-02-01 and the fold refuses (§15.4)  | refusal    |
| `dated-chain-mixed.l4`            | some arms are rule-date guards and some are not: no single date axis         | refusal    |
| `dated-chain-regulative.l4`       | a law-time-guarded OBLIGATION: `rowsToDmnWith'`'s `RegulativeBody` must win  | `NotDated` |
| `dated-chain-nested-otherwise.l4` | the `OTHERWISE` is itself a chain, so `expandOtherwise` must still splice it | `NotDated` |

### 15.11 What review changed

- The mission asked for **one `D-RULEDATE` code with two severities**. It ships as **three codes,
  one severity each** (§15.5), because §7's own header defers that shape to a re-ruling against
  `FIDELITY-SEVERITY-AXIS-SPEC.md` §5, and because the two arms have different _predicates_, not
  two intensities of one.
- The mission asked for a **floor row**, which collides with §3.3's headline ruling. §3.3 was
  **amended** rather than overridden — see **R9**, which admits the floor row as a third spelling on
  §3.3's own logic, and explains why the first draft's `UNIQUE` + `defaultOutputEntry` was dropped
  once §3.3.1 consequence 1 was read.
- The annotation column's citation claim was **checked against `@ref`** rather than inferred from
  comments (§15.9), and §15.9 records what the tree actually produced rather than what it should
  have.
- `numberOf` → `ordKey` was **not** in the mission. It is required: adding `VDate` to a bare
  `Rational` key would have let a number cell and a date cell be declared disjoint (§15.4).
- The **requirement rewrite (R11)** was not in the mission either, and without it the DRG would have
  described a dependency graph the emitted expression contradicts — a DMN 6.2.2 problem, not a
  cosmetic one.

**Second review pass, 2026-07-31.** Seven further repairs, each recorded where it belongs so a later
editor cannot silently un-change one:

- The **inline idiom** folded only bare literals while its own refusal message said named constants
  are folded (R10, §15.10). Fixed in `datedChain`; the exhibit now writes one arm each way.
- A **regulative body** stopped being refused the moment a chain looked dated, because the dated path
  bypasses `rowsToDmnWith'`'s three pre-tabulation refusals (§15.3, R10). Restated, with a fixture.
- The **nested-chain test** skipped the `OTHERWISE`, so a nested catch-all collapsed into one output
  entry with no `D-FLATTENCAP` (§15.3, R10).
- **`D-DATEDCHAIN`'s ordinals** meant two different things in two messages (§15.3, R10).
- **`D-RULEDATE-UNBOUND`** asserted "no DMN engine can evaluate this decision" unconditionally, which
  is false of a decision that still ships a table. Two message forms, and an invariant test (§15.5).
- **`D-MD-CELLSYNTAX`** recited an enumeration that misdiagnosed every date cell — the majority of
  its instances on this corpus (§15.7).
- The **date-axis probe had no negative control** while three places claimed it showed Xerces was
  watching the annotation position. It has one now, measured on both engines (§15.6).

Two harness repairs went with them: the `{"$date": …}` predicate disagreed between the two Java
checkers (§15.6), and the exhibit's boundary coverage straddled one seam out of three (§15.10).
