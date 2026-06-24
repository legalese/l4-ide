# DEONTIC party / action-index agreement — design & roadmap

**Status:** ✅ **IMPLEMENTED** (rung 2). `checkPartyActionAgreement` in
`TypeCheck.hs` + `ExpectPartyActionAgreementContext`. Suite green
(jl4 899/0, core 46/0).
**Tests:** `not-ok/tc/deontic-party-action-agreement.l4` (rejection),
`ok/regulative-actor-indexed-action.l4` (acceptance).
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
