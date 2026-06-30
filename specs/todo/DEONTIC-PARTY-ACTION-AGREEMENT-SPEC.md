# DEONTIC party / action-index agreement — design & roadmap

**Status:** ✅ **IMPLEMENTED** (rung 2). `checkPartyActionAgreement` in
`TypeCheck.hs` + `ExpectPartyActionAgreementContext`. Suite green
(jl4 899/0, core 46/0).
**Tests:** `not-ok/tc/deontic-party-action-agreement.l4` (rejection),
`ok/regulative-actor-indexed-action.l4` (acceptance).

> **Rung 3 — RESOLVED via _value-actors_, not the existential route.** Addendum
> II (below) planned event-driven actor-correct routing as a residual-seam +
> event-seam relaxation under a subtyping/existential wall (cost M–XL). The
> shipped solution is cheaper and supersedes that plan: model actors as
> **values**, give the contract a **monomorphic** `DEONTIC Actor Action` head
> (which drives mixed-actor events natively — no seam surgery, no subtyping, no
> existentials), and add a **value-level performer check**
> (`checkRegulativeActorAgreement` / `subjectOfActionExpr`, the SVO subject-first
> canon). This handles single-actor, duplex, parameterised (`EXACTLY`-applied),
> and higher-order _procurement_ actions. Suite 919/0. Fixtures:
> `ok/regulative-value-actor`, `ok/regulative-actor-duplex`,
> `not-ok/tc/value-actor-{agreement,duplex,procure}`. User-facing guide:
> [`doc/concepts/legal-modeling/actors-and-actions.md`](../../doc/concepts/legal-modeling/actors-and-actions.md).
> Theory & bibliography: [`ACTOR-ACTIONS-THEORY.md`](../../doc/concepts/legal-modeling/ACTOR-ACTIONS-THEORY.md).
**Origin:** synthesized from a multi-agent design workflow (5-subsystem map +
LiquidHaskell/Dependent-Haskell/GADT/Idris/F\* lessons + 4 scored proposals, two
of which were prototyped and verified against the golden suite).

## Implementation notes (what shipped vs the design)

Shipped exactly the recommended §2 design, scoped to **arity-1** action types
(judge B's hazard: arity-2+ like `Action Object Actor` is skipped, not
mis-projected). Two accepted deviations, both documented below:

- **Double-report is accepted, not suppressed.** On a clause that is *also* an
  action-type mismatch (rung 1), both the agreement error and the signature
  error fire (see `not-ok/tc/deontic-action-type-mismatch.l4`'s golden). Both are
  true; proper suppression needs the declared contract type at the
  `checkDeonton` seam (fresh metavars there), a larger refactor deliberately out
  of scope. Only ill-typed clauses are ever double-reported.
- **The check assumes the convention `party-type == actor-index-type`.** It
  compares the party's *type* to the action's index. So a model that types
  parties by a **separate union enum** (e.g. `DECLARE Party IS ONE OF …` with
  actions phantom-indexed by *different* role types) will see agreement fire on
  every indexed-action clause (`Party ≠ Role`). To use rung 2, type party values
  by the same types that index actions (`AnEater : Eater`, `Eat : Action Eater`).
  This is the nominal-equality / no-width boundary (§2.3.2) made concrete; it is
  the central trade-off and the natural place a future opt-out would attach.

---

## 0. The question

We have actor-indexed actions: `Action` carries a (phantom) actor index, so a
`DEONTIC P (Action Court)` contract rejects an `Action Landlord` value (rung 1,
done). The **next rung** is *party / action-index agreement*: "an actor may only
be obligated to perform its own actions." Today

```l4
DECLARE Eater   IS ONE OF AnEater
DECLARE Drinker IS ONE OF ADrinker
DECLARE Action who HAS `verb` IS A STRING
GIVETH AN Action Drinker
Drink MEANS Action WITH `verb` IS "drink"

GIVETH A DEONTIC Eater (Action Drinker)        -- party type Eater …
`bad` MEANS PARTY AnEater MUST Drink WITHIN 30  -- … action actor Drinker
```

wrongly type-checks: the two `DEONTIC` type parameters are never related. We want
it rejected — **without** losing multi-agent residuation (a `DEONTIC Party Action`
contract with *union* party/action types must still pass the ball Renter →
Landlord → Court; see `jl4/examples/ok/regulative-multiparty-residuation.l4`).

The owner's framing: dependent types are a slow burn (Dependent Haskell has been
"threatening to go Liquid" for years); *"just GADTs might be easier if they
achieve our goal."*

---

## 1. Direct answer: you need neither dependent types nor GADTs for this rung

The property "the obligated party's type equals the action's actor index" is a
relation between **two type arguments** of `DEONTIC a b` — *not* between a runtime
value and a type. It therefore sits **below the dependent-types line**, and even
below GADTs. The decisive facts:

- The actor index is **already recoverable by ordinary rank-1 HM**. `inferConDecl`
  (`TypeCheck.hs:843`) gives every constructor a System-F result type — a
  `MEANS`-defined `Drink` has type `∀who. STRING → Action who`, so a value
  `Drink :: Action Drinker` already carries `Drinker` in its plain HM type. No
  dependent types, no GADTs, no constraint store needed to *observe* the index.
- The unifier **already decides nominal type equality deeply**. `unifyBase`
  (`Unify.hs:96`) recurses pointwise into `TyApp` arguments via `ensureSameRef`
  (head-`Unique` identity) — this is exactly what the rung-1 fix relies on.
- `DEONTIC` is a plain arity-2 nominal constructor (`KnownType 2 [] Nothing`,
  `Environment.hs:863`); kinds are mere arities (`Kind = Int`, `Syntax.hs:105`),
  so there is no kind machinery to fight.

The only thing missing is **one equality constraint**: `partyType ~ index(actionType)`.
Lambda-cube-wise we add **no new axis** — we stay at HM and simply stop leaving two
metavariables independent. The Idris/Agda result that *generative datatypes ⇒
reflexive nominal index equality is decidable, total, and SMT-free* is the formal
license for this being enough.

> **Answer to "do we even need dependent types?": No — not for this rung.**
> Reflexive nominal equality between the two `DEONTIC` parameters suffices.
> GADTs are the right *ceiling* if we later want more (see §5), not the next step.

---

## 2. Recommended next step (minimal, verified): nominal agreement at the clause

A clause-level well-formedness rule in `checkDeonton`. Both prototyped proposals
(A "nominal agreement" and B "projection-unify") converged on the same ~6–8 lines;
both judges **built it and ran the suite: 895 examples, 1 failure — the pending
acceptance test, now correctly erroring** (its goldens just need regenerating).

### 2.1 The change

`jl4-core/src/L4/TypeCheck.hs`, `checkDeonton` (~`1121`): after the party and
action are checked (so their fresh metavars are solved), project the actor index
off the action type and unify it with the party type.

```haskell
-- after: partyR <- checkExpr ... party partyT
--        (actionR, boundByPattern) <- checkAction action actionT
partyT'  <- applySubst partyT
actionT' <- applySubst actionT
case actionT' of
  -- only when the action type actually carries an actor index
  TyApp _ _ (idx : _) -> expect ExpectPartyActionAgreementContext partyT' idx
  _                   -> pure ()          -- plain-enum / union / unsolved: no-op
```

`applySubst` is load-bearing — at this seam `partyT := Eater` and
`actionT := Action Drinker` are solved but still behind InfVars until substituted.
The `(idx : _)` guard is the **residuation guard rail**: arity-0 action types
(the entire current corpus, the multiparty file) have no index, so the check is a
structural no-op and nothing narrows.

Supporting edits (same pattern the rung-1 fix used):

- `TypeCheck/Types.hs` (`ExpectationContext`, ~`149`): add one constructor
  `ExpectPartyActionAgreementContext`. No new `CheckError` — `TypeMismatch ec
  expected given` already names both types.
- `TypeCheck.hs` (`prettyTypeMismatch`, ~`3486`): add an arm rendering a
  **domain phrase**, e.g. *"In this obligation the party is an Eater, but the
  action `Drink` belongs to a Drinker. An actor may only be obligated to perform
  its own actions."* This is the single biggest UX lever — pick the `expect`
  direction so the message blames the **action**, not the party.
- Tests: the pending fixture flips to satisfied (regenerate its
  `parses-and-checks` / `nlg` / `schema` goldens); add a positive lock-in
  (`DEONTIC Eater (Action Eater)` + `PARTY AnEater MUST Eat`, verified green
  today) so we pin *accept-on-match*, not only reject-on-mismatch.

### 2.2 Why it's sound and residuation-safe

It is a pure addition of one unification equality between two already-resolved
types. It can only **reject** programs the old checker accepted, never accept new
ones — so it cannot admit an ill-typed contract. The evaluator is untouched:
`EvaluateLazy` stores party/action as runtime **values** (`ValObligation`,
`EvaluateLazy.hs:257`), never types, so a type-level check changes no residual or
event-matching. Verified green across all the hard cases: plain-enum multiparty,
union-actor `DEONTIC Actor (Action Actor)`, the `GIVEN action … MUST action`
reference case, and the polymorphic `DEONTIC who (Action who)` self-action clause.

### 2.3 Honest boundaries (what this step does *not* do)

1. **Only fires when the action carries an index.** Plain-enum actions (the whole
   current corpus) are unprotected: "an Eater obligated to `payRent`" is
   uncatchable because `payRent` has no actor in its type. Catching that needs a
   different encoding (party and action drawn from a shared actor *kind*) — out of
   scope.
2. **Nominal equality, no subtyping/width.** `DEONTIC Actor (Action Renter)` with
   a broad-`Actor` party currently succeeds and would be **newly rejected**
   (L4 has no subtyping). Acceptable if "own action" is read literally; document
   it, and note the escape hatch is to index by the shared actor union.
3. **Actor-indexed multiparty residuation is already in tension** — independently
   of this rung. The rung-1 fix pins the whole `DEONTIC` type across HENCE/LEST
   residuals, so `DEONTIC Actor (Action Renter)` → a Landlord follow-up already
   fails today. The **only** encoding that residuates freely with indexed actions
   is to index by the *union* actor (`DEONTIC Actor (Action Actor)`), where
   agreement is a happy no-op.
4. **No value-level identity.** It cannot say "*this* `AsRenter` token may only do
   *this* renter's action" — that is a value-dependency (§5 ceiling).

### 2.4 Two implementation hazards to get right (both found by adversarial judges)

- **"actor = first index" is an unstated, fragile convention.** A coherent
  `DEONTIC Eater (Action Food Eater)` (actor as the *second* index — natural for
  "Renter pays Landlord" object/counterparty indexing) is **falsely rejected**
  because the projection grabs `Food`. Fix: restrict the check to **arity-1**
  action heads, *or* add an explicit actor-index marker on the action declaration,
  and say which. Do not silently bake in "arg 0 = actor."
- **Diagnostic collision / double-report.** On the rung-1 fixture
  (`deontic-action-type-mismatch.l4`) the prototype emits **two** errors (the
  original action-type mismatch *plus* the new agreement error). Both are true,
  but double-reporting one incoherence is noisy. Suppress the agreement check when
  the action-type check already failed on the same clause, or order so the more
  specific message leads. (This also churns that fixture's golden — list it.)

**Cost:** S. No new keywords, no annotations, no SMT, no new type-system power.

---

## 3. Lessons from "going Liquid" and the dependent-types slow burn

Distilled from the literature (LiquidHaskell, Dependent Haskell/Singletons, GHC
GADTs, Idris/Agda, F\*/Dafny), filtered for a **lawyer-facing CNL** where error
legibility dominates:

- **LiquidHaskell** is the canonical bolt-on: refinements in comments, a *separate*
  checking phase that never touches GHC's core, SMT-discharged. Two recurring
  costs: a hard **external-SMT dependency** (Z3) and **research-grade error
  messages** (raw solver noise). *Transfer:* wrong altitude for L4's first move;
  right *architectural* lesson — keep any heavier checking a **separate, opt-in
  phase**. This rung needs no refinement predicates at all (it's a nominal fact,
  not an arithmetic one).
- **Dependent Haskell / Singletons / DataKinds** — the "slow burn." Using a
  promoted index at the term level needs singletons, which the maintainers
  themselves call out for "multiple definitions," "conversion evidence,"
  "inefficiency," "accidental complexity." *Transfer:* strong evidence **against**
  value-level dependency for this rung. The obligation is a type↔type relation,
  below the dependent line — don't import the singletons tax.
- **GADTs in GHC** buy exactly per-constructor index refinement + per-branch
  equality constraints, but **type inference for GADTs is undecidable** →
  "functions over GADTs lack principal types," missing signatures yield "obscure
  error messages." GHC's mitigation is to demand **rigid (annotated) types** at use
  sites. *Transfer:* L4 already **sidesteps the worst of this** — `inferContract`
  (`TypeCheck.hs:1488`) gives every clause a fully-known declared type via
  `GIVETH A DEONTIC …`, so a GADT-style indexed-action scheme would *always* be
  checked against a user-written signature, dodging the principal-types problem.
  So GADTs are the right **ceiling** if the nominal rule proves too weak — *not*
  singletons, *not* SMT.
- **Idris/Agda** indexed families decide index equality by **reflexivity** on
  generative datatypes — no open-term unification, no SMT. Plus **bidirectional
  checking** (check against a known expected type) keeps indexed types tractable
  and errors local. *Transfer:* this is precisely the cheap path §2 takes, and it
  maps onto machinery L4 already has.
- **F\*/Dafny** show the heavy end's usability cost: SMT **brittleness**
  (timeouts, quantifier blowup, "why did my proof fail?" opacity) — fatal for a
  CNL whose selling point is **traceable, citable, local** reasoning. *Transfer:*
  reserve SMT for L4's **existing property layer** (the race-condition /
  deontic-conflict finder), never for the basic well-formedness of one clause.
  Copy F\*'s pure-core / effectful-shell split: keep agreement in the cheap,
  decidable, nominal core.

---

## 4. Why not the other proposals (scored, adversarially judged)

| Approach | Score | Achieves goal | Cost | SMT | Verdict |
|---|---|---|---|---|---|
| **A — nominal agreement** (clause-level unify) | **8/10** | **fully** | **S** | no | **Recommended** |
| **B — projection-unify** (≈ A; "GADTs not needed") | **8/10** | **fully** | **S** | no | **Recommended (same change)** |
| C — refinement / Liquid | 3/10 | partially | XL | **yes** | Adds nothing over plain unification here; SMT opacity is wrong for lawyers |
| D — singletons / value→type promotion | 3/10 | partially | — | no | "Verified" claim was **false** (rigidity breaks the match case) and it **breaks residuation** |

A and B are the same minimal change described in §2. C and D were rejected: C's
refinement framing "delivers nothing over plain unification for this rung" while
importing an SMT backend; D's singleton encoding both fails the matching case
(skolem rigidity) and breaks union-typed residuation.

---

## 5. The staircase (where this sits, and the ceiling)

1. **Rung 1 — action-type enforced** *(done).* `MUST`/`MAY` action checked deeply
   against the contract's declared action type. Elaboration fix, no new theory.
2. **Rung 2 — party/action-index agreement** *(this spec, recommended now).*
   One nominal-equality constraint. Stays at HM. Cost S.
3. **Rung 3 — GADT-style indexed actions** *(only if needed).* Per-constructor
   result-type refinement (two constructors of one `DECLARE Action` fixing
   *different* closed indices) + refinement-by-matching in `CONSIDER`. Needs:
   per-`ConDecl` result-type annotations (`Syntax.hs:188`), `inferConDecl` to
   elaborate them, and equality-witness refinement at pattern matches. L4's rigid
   `GIVETH` signatures keep this out of the GADT inference swamp. Reach for it only
   when an action type must host distinct closed indices per constructor, or when
   matching must *learn* the index.
4. **Ceiling — value-level dependency** *(probably never in the core).* "This
   specific party value may only do this specific party's action." Singletons/Π or
   refinement+SMT. The literature says: expensive, brittle, and unreadable for
   lawyers. If ever needed, build it as a **separate opt-in verification phase**
   (the LiquidHaskell/F\* architecture), reusing L4's existing property/conflict
   finder — never bolted into the deontic core's well-formedness.

---

## 6. Concrete next actions

1. Implement §2.1 (guard scoped to **arity-1** action heads; pick the `expect`
   direction; suppress on prior action-type failure to avoid double-report).
2. Add the domain-phrase `prettyTypeMismatch` arm.
3. Flip the pending fixture to a real not-ok case; regenerate its goldens; add the
   `DEONTIC Eater (Action Eater)` positive lock-in.
4. Document the boundaries in §2.3 (esp. no-width and union-actor-for-residuation)
   in the regulative reference docs.
5. Leave rungs 3–4 unbuilt; revisit only against a concrete use case that the
   nominal rule provably cannot express.

---

# Addendum — Rung 3: actor-correct *free* residuation ("the ball in either court")

> **Status: this addendum is the original hand-sketch (2026-06-24), now
> superseded by a design-workflow run that pressure-tested it against the rung-3
> acceptance test on the live binary. The sketch's *diagnosis* (the residual
> pin, the union/specific fork, the GIVETH-rigidity dodge) held; its *cost
> framing* ("XL — first-class `Exists`") and its *load-bearing piece*
> (actor-agnostic `DEONTIC SOME who` head) did not. Read "Addendum II —
> validated findings" at the bottom before building anything.**

## Why this wasn't solved by rungs 1–2 (acceptance-test scoping)

The design that produced rung 2 was driven by an acceptance test that was the
**monomorphic** incoherent contract (`DEONTIC Eater (Action Drinker)`), with free
residuation present only as a *preserve* constraint. The **union encoding
satisfies that constraint vacuously** (`DEONTIC Actor (Action Actor)` residuates
*and* passes agreement `Actor ~ Actor`), so nothing forced the two goals to be
reconciled in one contract. Rung 3 is exactly that reconciliation, and it needs
its own acceptance test (below) — with which rung 2 visibly fails.

## The tension, demonstrated (rung-2 binary)

A `DEONTIC P A` value's **type is the invariant residuation must preserve**
(subject reduction: every HENCE/LEST residual must have the contract's type).
That forces a fork:

- **Union index** `DEONTIC Actor (Action Actor)` — residuates Eater→Drinker
  freely, but `eat`/`drink` are both `Action Actor`, so agreement is **vacuous**
  and `PARTY ADrinker MUST eat` is *accepted*.
- **Specific index** `DEONTIC Eater (Action Eater)` — keeps agreement's teeth,
  but the contract type is pinned to one actor; a Drinker `LEST` fails with
  *"HENCE … expected DEONTIC OF Eater, Action OF Eater but is here DEONTIC OF
  Drinker, Action OF Drinker."*

So under *nominal* typing, **"routes the ball between actors" and "each actor only
does its own actions" are mutually exclusive for a single contract.** A function
can return a union contract (multi-party, agreement off) or a polymorphic
per-actor contract (`GIVEN who … GIVETH A DEONTIC who (Action who)` — agreement
on, but one actor per instantiation). It cannot today return one contract that
does both.

## Rung-3 acceptance test

```l4
-- MUST type-check (ball routes Eater -> Drinker) …
-- … AND `PARTY ADrinker MUST eat` inside such a contract MUST be rejected.
```
Rung 2 fails this: union-index accepts the bad clause; specific-index rejects the
routing.

## The mechanism: existential ("∃") obligations — "just GADTs"

Index *both* party and action by the actor, and have each obligation
**existentially pack a shared actor index**:

```
Obligation = ∃who. MkOb (Party who) (Action who) Deadline …
Contract    = Tree Obligation        -- names no specific actor
```

- Each obligation is **actor-correct** (party and action share `who`).
- The **contract type mentions no actor**, so residuals may use a *different*
  `who` each → the ball routes freely; subject reduction holds on the existential.
- This is "just GADTs" in the colloquial sense: a constructor that quantifies
  `who` in its argument types and hides it in the result. **No value→type
  promotion, no singletons, no SMT.** A clause `PARTY p MUST a` becomes sugar for
  `MkOb p a …`, opening a fresh `who` skolem per clause.

In lambda-cube terms this is the genuine step past rung 2: rung 2 added a
constraint at HM; rung 3 adds **existential quantification** (the negative-position
∀ that GADT/existential constructors introduce).

## L4 surface sketch (TBD)

```l4
DECLARE Party  who IS ONE OF AsEater Eater | AsDrinker Drinker   -- party indexed
DECLARE Action who HAS `verb` IS A STRING

-- contract whose obligations may fall on ANY actor, each self-consistent:
GIVETH A DEONTIC SOME who
`pingpong` MEANS
  PARTY (AsEater AnEater)  MUST eat   WITHIN 30   -- opens who = Eater
  HENCE FULFILLED
  LEST PARTY (AsDrinker ADrinker) MUST drink WITHIN 10 …   -- opens who = Drinker
```
The load-bearing new piece is `DEONTIC SOME who` (an existential contract type)
plus a **fresh per-clause `who`** rather than a single contract-level parameter.

## Toolchain changes (honest cost: XL — the real rung)

1. **`Type'` / kinds (Syntax.hs):** add existential quantification — either a
   general `Exists` to sit beside `Forall`, or (more contained) a built-in
   "obligation existential" that `DEONTIC` special-cases. This is the genuine
   type-system extension; everything else follows.
2. **`checkDeonton` / `inferContract` (TypeCheck.hs ~1117):** allocate a fresh
   skolem `who` per clause; check `party : Party who` and `action : Action who`
   against it (rung-2's agreement, but on a per-clause skolem); the clause's
   contribution to the contract type is existential in `who`.
3. **Residual unification (`ExpectRegulativeFollowupContext`):** HENCE/LEST must
   unify against the existential contract type, instantiating `who` *per residual*
   — this is precisely what makes the cross-actor `LEST` (today's TEST 3 error)
   type-check.
4. **`inferConDecl` (TypeCheck.hs ~843):** if users declare their own indexed
   party/obligation constructors, per-`ConDecl` result-type handling (the genuine
   GADT feature: a constructor fixing its index).
5. **Evaluator (EvaluateLazy.hs):** largely unaffected — `ValObligation` stores
   party/action as runtime *values*, never types, so the existential is erased at
   runtime (the same reason rung 2 needed no evaluator change).
6. **Inference:** GADTs lack principal types in general, but L4 sidesteps the pain
   because `GIVETH A DEONTIC …` makes the contract type **rigid** — every clause is
   checked against a written signature, the condition GHC needs for GADT
   refinement without inference blowup (see the GADT lesson in §3).

## Lighter alternatives (and why they're not the static answer)

- **Subtyping** (`Action Eater <: Action Actor`, covariant index) would also
  reconcile — a union contract accepting specific actions — but L4 has **no
  subtyping**, a large orthogonal addition.
- **Singletons / value→type** (the party *value* determines the action type) —
  heavier, the dependent route the LiquidHaskell/DH lessons warn against.
- **Runtime `PROVIDED` guard on a union contract** (`DEONTIC Actor (Action
  Actor)` + a guard that the party and action denote the same actor) — **zero
  type-system change, available today** — gives free residuation + *dynamic*
  actor-correctness, but it's a runtime check, not a static guarantee, and is
  only expressible if the action value carries its actor as a field (needs
  verification). This is the pragmatic interim while rung 3 is unbuilt.

## Recommendation

- **Interim (now):** runtime `PROVIDED` guard for actor-correctness on union
  contracts; accept that routing-correctness is dynamic.
- **Rung 3 (when a concrete case needs *static* actor-correct routing):**
  existential obligations per the mechanism above. Scope it against the rung-3
  acceptance test; reuse rung-2's per-clause agreement check on the fresh skolem;
  lean on L4's rigid `GIVETH` signatures to dodge GADT inference pain. Consider
  re-running the design workflow with the rung-3 acceptance test to pressure-test
  this sketch before building.

---

# Addendum II — Rung 3 validated findings (design-workflow run #2, 2026-06-24)

A 4-subsystem-map → 4-proposal → adversarial-verdict workflow was run against the
exact rung-3 acceptance test, with every claim checked on a freshly built `l4`
binary (patches applied, contracts driven with `#TRACE` events). The sketch above
was confirmed where it described *today's* behaviour and corrected where it
guessed at *cost* and *mechanism*. Net: **the static refinement is cheaper than
the sketch claimed (S–M, not XL), but "the ball in either court" at *runtime*
needs a second change the sketch never mentioned.**

## What held (sketch was right)

- **The pin is `checkDeonton`'s `let rTy = contract partyT actionT`
  (TypeCheck.hs:1125).** All four maps reproduced it independently: HENCE (1127)
  and LEST (1128) are both checked against this one `rTy`, whose `partyT`/`actionT`
  are the head clause's already-solved metavars — so every residual is forced to
  the head actor. Confirmed even with *no* `GIVETH` signature (the first
  `PARTY AnEater` solves `partyT := Eater` and pins the rest), and confirmed to
  re-surface inside a polymorphic helper (`expected DEONTIC OF who … but who2`),
  proving **no pure-L4 encoding closes both halves** — the seam itself must move.
- **The union/specific fork is real and mutually exclusive under nominal typing**
  (re-verified on the binary): union `DEONTIC Actor (Action Actor)` routes but
  vacuously accepts `PARTY ADrinker MUST eat` (*"Check succeeded"*); specific
  `DEONTIC Eater (Action Eater)` rejects the cross-actor `LEST`. A
  coproduct/tagged single `Action` enum also fails half (2) (arity-0 action ⇒
  agreement no-op). A polymorphic `GIVEN who GIVETH A DEONTIC who (Action who)`
  doesn't even bind `who` as a type parameter today.
- **GADT inference pain is dodged by L4's mandatory `GIVETH`.** Every contract is
  checked bidirectionally against a written, rigid signature — exactly the
  condition GHC's OutsideIn(X) and OCaml's locally-abstract types need to keep
  indexed checking out of the no-principal-types swamp. This is the single
  biggest reason rung 3 is tractable at all.
- **Full dependent types / SMT (the "going Liquid" route) is overkill** — the
  per-clause obligation is one *nominal equality* (party type ~ action's actor
  index), not a refinement predicate. The LiquidHaskell decade-long slow burn is
  the cost of the *SMT/refinement substrate*, which this problem never invokes.

## What changed (sketch was wrong, in order of importance)

### 1. There are TWO actor pins, not one — and the second is the real wall.

The sketch (and the cheapest proposal) relaxes only the **static residual seam**
(`checkDeonton:1125`). A verdict applied that ~8-line patch verbatim, rebuilt, and
showed both halves of the acceptance test pass *as a static type-check*. Then it
**drove the contract with events** and found the fatal flaw:

> The `#TRACE`/`#CONTRACT` directive types the event stream as
> `eventT = event partyT actionT` (**TypeCheck.hs:437**) with a *single* actor
> pinned to the declared contract type. Feeding the cross-actor event the routing
> exists to consume — `#TRACE pingpong … WITH PARTY ADrinker DOES drink` — fails:
> *"EVENT OF Eater, Action OF Eater but is here EVENT OF Drinker, Action OF
> Drinker."*

So the cheap patch **relocates** the single-actor pin from the residual clause to
the event seam rather than removing it. A contract that type-checks but cannot
ingest its own routing event is not "routing the ball" in any runtime sense — and
event-driven residuation is the entire point of an L4 contract. **To deliver
executable rung-3 routing you must relax *both* seams coherently** (residual *and*
event typing), and the event-seam relaxation re-opens soundness: you must add
**event-time party/action agreement** (reject `ADrinker DOES eat` events) or the
event stream becomes a hole. This is the honest "real rung," and it raises the
cost from S to **M**.

### 2. Cost is S–M, not XL — no first-class `Exists`, no skolem/escape machinery.

The sketch's §"Toolchain changes (honest cost: XL)" overstated the type-system
delta. The contained refinement needs **none of**: a new `Type'` constructor, a
`unifyBase` `Forall`/`Exists` arm, skolemisation, TcLevels, an escape check, kind
machinery, singletons, or SMT. The reason (confirmed by all four maps and the
lessons agent): the per-clause actor index is **consumed entirely within the
clause** — party and action are leaves, and obligations are *never destructured
downstream* the way a GADT scrutinee is. **No elimination site ⇒ no escape hazard
to police.** The "existential" is therefore *operational*, not a type: a fresh
`InfVar` opened per residual (reusing the existing `fresh` + reflexive-nominal
unifier), solved by the residual's own party, and discarded. The XL number in the
sketch applies only to the *first-class-`Exists`* route (general `∃` constructor +
skolem-escape infrastructure), which the workflow judged the **wrong altitude**:
~10 new arms across `Type'`-matching code plus genuinely-new unifier machinery
L4 has zero of today (grep confirms no `skolem`/`rigid`/`level`/`escape` anywhere
in TypeCheck/Types/Unify/Environment), bought for nothing this problem needs.

### 3. Do NOT make the contract head actor-agnostic (`DEONTIC SOME who` / 0-arg).

The sketch's load-bearing piece was an actor-erased head. The workflow rejected it
twice over: (a) `GIVETH A DEONTIC` with no actor arg is an **arity error today**
(*"expected 2, found 0"*, plus a confusing double-report); (b) more fundamentally
an actor-agnostic head has **no concrete party/action to feed the event type**
`event partyT actionT` — the same wall as finding #1, hit from the other side. The
viable shape keeps a **concrete head** (`DEONTIC Eater (Action Eater)`) and
relaxes the *seams*.

### 4. The soundness pin: freshen the index, never the action head.

The obvious one-line version — fresh *both* party and action per residual — is
**unsound** (a verdict confirmed it accepts `Dog MUST Cat` / a `Robot` LEST). The
correct shape pins the action **head** and freshens only its **index**, with party
and action sharing **one** fresh actor: `rTy_resid = contract (fresh w)
(Action (fresh w))`. Within-clause, rung-2's already-shipped
`checkPartyActionAgreement` forces `w` to the party's actor type, preserving the
reject-half; across residuals, distinct `w`s let the ball route.

### 5. The reject-half needs per-actor party *types* (rung-2's known limitation).

Half (2) of the acceptance test (`PARTY ADrinker MUST eat` rejected) survives only
because each actor is its own `DECLARE … IS ONE OF` type, so `ADrinker : Drinker`
and agreement `Drinker ~ Eater` bites. A **single union `Party` enum** makes the
party type identical for everyone and agreement goes vacuous again — so rung 3, to
keep its teeth, presumes per-actor party types (or an actor-indexed `Party who`).

## Cost-corrected recommendation

| Goal | Change | Cost | Soundness |
|---|---|---|---|
| **Static actor-correct well-formedness** (routing contract *type-checks*; bad clause rejected statically) | Relax residual seam at `checkDeonton:1125`: fresh actor index per residual, action-head pinned + index freshened (share one `w`), re-run rung-2 agreement per clause. No new `Type'`, no skolem machinery. | **S** (~8 lines, suite stays green) | Sound (only accepts programs today wrongly rejected); but the routed contract is **undriveable by cross-actor events** |
| **Executable actor-correct routing** ("the ball in either court" *at runtime*) | The above **plus** relax the event-typing seam (`eventT = event partyT actionT`, ~TypeCheck.hs:437) with **event-time agreement** so cross-actor events type-check yet stay actor-checked. | **M** | Sound iff event-time agreement is added; re-opens soundness at the event seam |
| **First-class existential obligations** (general `∃`, honest actor-erased head) | New `Type'` constructor + skolemise + TcLevels + escape check + ~10 match arms + Event-type rework. | **XL** | Sound but **wrong altitude** — buys generality this problem never uses; breaks event typing unless also reworked |

- **Reject** the actor-agnostic `DEONTIC SOME who` head (arity + event-typing
  collision) and **reject** the first-class-`Exists`/full-dependent/SMT routes.
- **The legibility tradeoff is the one real design decision left:** a concrete head
  with relaxed seams means a `DEONTIC Eater` contract silently admits a `Robot`
  residual — the declared type stops documenting "who this contract is about." Two
  exits: live with it, or **bound the fresh actor to a declared union** (which
  partially re-introduces the union encoding rung 3 set out to retire). Pick when a
  concrete case forces it.
- **Interim, available today:** runtime `PROVIDED` guard on the union encoding
  (`DEONTIC Actor (Action Actor)` + a guard that party and action denote the same
  actor). It is the **only multi-actor encoding that drives events end-to-end
  today** — but actor-correctness is *dynamic*, and the union footgun (vacuous
  static agreement) persists until rung 3 ships.

## The validated minimal mechanism (~8 lines) and build sequence

The winning proposal ("Per-residual actor-open contract head") was the **only one
of the four with zero fatal flaws** (score 6). The synthesis distilled it to a
concrete, regression-safe patch at the residual seam.

### The patch (checkDeonton, TypeCheck.hs:1125–1128)

Replace the single `let rTy = contract partyT actionT` (reused for both HENCE and
LEST) with a **per-residual** followup type:

```haskell
-- after party/action are checked and their metavars solved:
actionT' <- applySubst actionT
rTy <- case actionT' of
  TyApp ann actionHead [_idx] -> do            -- arity-1, actor-indexed (rung-2's case)
    w <- fresh                                 -- a METAVAR, not a skolem (see caveat)
    pure (contract w (TyApp ann actionHead [w]))   -- party & action share ONE w
  _ -> pure (contract partyT actionT)          -- arity-0 enums/unions & multi-agent
                                               -- DEONTIC Party Action: UNCHANGED → no regression
-- check HENCE and LEST against rTy as today; each residual is a fresh Regulative
-- whose own checkDeonton re-runs checkPartyActionAgreement, binding its w to its
-- party's actor type.
```

Why this passes both halves: routing type-checks because each residual gets a
*distinct* `w`; `PARTY ADrinker MUST eat` is rejected because *within one clause*
`w ~ Drinker` (from the party) and `w ~ Eater` (from `eat : Action Eater`) both
fire on the same `w`, and `ensureSameRef Drinker Eater = False`.

> **Caveat that sank a rival proposal — it must be a `fresh` *metavar*, not a
> rigid skolem.** A competing design minted the per-clause actor via
> `def + extendKnown KnownTypeVariable` (the `GIVEN who IS A TYPE` path), which
> yields a `TyApp who []` that `ensureSameRef` unifies only with *itself*. Under
> that, `expect (party = Eater) who` would **fail even in the good case**
> (`Eater MUST eat`). The actor index here must be *solvable* (a metavar the
> residual's own party fills in), not rigid. The arity-1 guard means the whole
> legacy corpus and the multi-agent `DEONTIC Party Action` union take the
> untouched `else` branch.

### Sequenced build plan

1. **Land the ~8-line seam change** above (arity-1 only; arity-0 untouched). Add an
   OK fixture — one specific-index routing contract (`Eater MUST Eat; LEST Drinker
   MUST Drink`) that now type-checks — and a NOT-OK fixture — that same style with a
   residual `PARTY ADrinker MUST Eat` rejected statically. *That is the acceptance
   test, encoded as fixtures.*
2. **Run the golden suite;** confirm only the pre-existing unrelated excel-date
   failures remain and all deontic/residuation/multiparty fixtures stay green (the
   change is monomorphic metavar freshening — benign for inference, no
   principal-types hazard).
3. **Add the domain-phrased `prettyTypeMismatch` arm** for the residual-actor case
   (see hazard below); treat the closed `GIVETH` annotation as the leak boundary.
4. **Separately scoped (M, do *not* block step 1):** decide whether routed
   contracts must be *driveable by cross-actor events*. If yes, relax the event
   seam `eventT = event partyT actionT` (TypeCheck.hs:437) **with an event-time
   agreement check** so `PARTY ADrinker DOES Drink` type-checks against a
   concrete-Eater-headed routing contract yet stays actor-checked. Without it, the
   contract routes internally but `#TRACE`/EVALTRACE on a cross-actor event is a
   static type error.
5. **Defer arity-2+** (`Action Object Actor`): keep rung-2's arity-1 "actor = index
   0" restriction; a robust fix needs an explicit actor-index marker on the
   `Action` declaration — out of rung-3 scope.

### Explicitly *not* doing

First-class `Exists` on `Type'` (wrong altitude: ~10 new match arms across
Unify/Print/Export/JsonSchema/FunctionSchema/EvaluateLazy/Parser + `substituteType`/
`applySubst`, a sound `unifyBase` existential arm with skolemise/open/escape-check
L4 has none of, **and** it forces confronting the unfixed capture-avoiding-
substitution-under-`Forall` TODO at `Types.hs:719`); actor-agnostic `DEONTIC SOME
who`/0-arg head (arity error today + starves the event type); freshening *both*
party and action (unsound); a single contract-level `GIVEN who … DEONTIC who
(Action who)` (verified: pins the whole contract to the first clause's actor, fails
routing); GADTs, singletons, dependent types, SMT.

### Open question that needs a human call

The legibility/documentation tradeoff is the one genuine design decision left: a
concrete `DEONTIC Eater` head with relaxed seams **silently admits a `Robot`/`Drinker`
residual** — the declared head stops documenting "who this contract is about."
Either live with it, or bound the fresh `w` to a declared actor union (which
partially re-introduces the union encoding rung 3 set out to retire). Decide when a
concrete case forces it.

## Error-message hazard (carry into whichever rung is built)

The CNL/proof-tool usability literature (Naproche, Lean autoformalization) is
unanimous: index/type errors are the dominant comprehension barrier for
non-experts, and the fix is a **domain-phrased message with a concrete repair
hint**, never raw solver/type output. Rung 2 already does this ("An actor may only
be obligated to perform its own actions"). Rung 3 must not regress it: a leaked
unsolved actor index would otherwise surface as `who.0` / `$App_'b` /
*"rigid type variable would escape its scope"* — pure PL jargon at the
`ExpectRegulativeFollowupContext` seam a lawyer actually reads. The contained
approach mostly avoids this (the fresh index is solved by the residual's own
party), so it is **lower priority than the original sketch implied** — but a
domain-phrased `prettyTypeMismatch` arm for an unconstrained residual actor is
still worth adding, and the closed `GIVETH` annotation should be treated as the
boundary past which no actor index may leak.
