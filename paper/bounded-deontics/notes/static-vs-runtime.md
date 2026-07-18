# Bounded deontics: the static/runtime frontier (design note)

> Spitballing note, 2026-06-24, Meng + Claude. Captures the line of thought about
> *quantifying* the goal-index discipline and what makes the strong (compile-time)
> vs weak (runtime) form. Companion to `related-work.md` and the source transcript.
> Status: working theory, nothing here is validated against the evaluator yet.

## The seed (Meng)

> "Every deontic carries its goal index as a typed obligation… suppose we quantify:
> every deontic? or some? If ∀ then a strong form, amenable to compile-time
> verification. If ∃ then a weak form requiring runtime evaluation. The strong form
> probably requires stratification, where rules are ordered defeasibly."

The intuition is right in spirit. The refinements below are about *what* is being
quantified and *why* it gates static vs dynamic.

## 1. What is actually quantified: totality of the goal-resolution map

> **SUPERSEDED (2026-06-24, Meng):** the "map `goal : Deontic → GoalTerm`" framing
> below is **too tightly coupled** — the goal-relativized "must" is a *derived
> many-to-many relation* over the transition system, not a per-obligation index.
> See `spec-delta.md` § "CORRECTION". Axis (a) below should read "**goal *set*
> closed**", not "goal map total". The rest of the lattice (axes b, c; the
> inversion; detect≠resolve) survives unchanged.

The relevant object is the map

    goal : Deontic → GoalTerm        ("or else what?", made explicit)

- **Strong form** = this map is **total and statically resolvable**: every
  obligation's goal index is either written, or fillable from the background theory
  at compile time (the implicit→explicit step the ChatGPT thread describes:
  "for the purposes of L4 it is sufficient to interpret implicit goals to explicit").
- **Weak form** = the map is **partial**: some goal terms are holes filled only later.

So the quantifier sits on the *totality of `goal`*, not on a raw "∀ deontics."
This is the same discipline as L4's constitutive layer (total typed functions):
goal-indexing pushes a slice of each obligation **down** into the constitutive
layer, and the strong form is exactly "that slice is total." ∀ buys compile-time
**because a total goal map closes the formula**, not because of the quantifier itself.

A partial `goal` is naturally modelled by Meng's `Default GoalTerm` (the same
`Default a` type from the PROLEG/burden-of-proof work): a primary slot filled from
context, with a fallback. Totalizing = providing the fallback for every obligation.

## 2. Two axes the seed folds together

Compile-time vs runtime is driven by (at least) two independent axes:

1. **Goal-totality** — are all deontics indexed (a **closed** LTL/automaton
   formula) or only some (a formula with **free goal-variables**)?
2. **Factbase-closedness** — are all facts known statically, or do they stream in
   (the event-sourced / bitemporal factbase)?

These dissociate. Even a fully ∀-indexed (closed) formula still needs **runtime
evaluation of the actual trace** as facts arrive. But the **verification** question
— "does any reachable trace hit a violation / double-bind?" — is the **compile-time
model-check**.

### Sharper statement of strong vs weak

- **∀ (closed formula) → compile-time *verification* is possible** (model-check all
  traces; a deontic double-bind MUST-p ∧ SHANT-p shows up as an **unsat core**).
  Runtime *monitoring* of the live trace is still available too — strong form gives
  **both**.
- **∃ (open formula) → runtime only**, because the property isn't even *determined*
  until the missing goal is injected at runtime (the anankastic "if you want X").
  Weak form gives **monitoring only**.

The point is formula-**closedness**, not "static vs also-runtime."

## 3. The inversion (a paper-worthy tension)

Which obligations are inherently **∃**? The genuinely **instrumental / anankastic**
ones — "you must take the A train *if you want to go to Harlem*" — because the goal
is a **runtime input the agent supplies** (Yan & He's `O_G`).

Which are **∀**? The **categorical** ones — *once we accept the bounded-deontics
fiction* of assigning them a constant background goal ("…to maintain civic order").

So the norms that were the philosophical **problem** cases (torture; categorical
imperatives; the breakdown zone of the reduction in `related-work.md` Strand 3)
become the computationally **easy** cases (static constant goal), while the cleanly
instrumental obligations are the **hard** cases for static verification.

**Faithfulness and staticness pull in opposite directions**, and the frontier
between them is — recursively — the "bound" in *bounded* deontics. Publishable on
its own.

## 4. Stratification: yes, but detect ≠ resolve

The strong form needs the defeasible order to be statically resolvable: an
**acyclic superiority relation** (Governatori / Nute), which in Kratzer's idiom is a
**ranked ordering source** — the same object in three vocabularies (defeasible
logic / Kratzerian semantics / priority rules). Acyclicity is exactly the soundness
gate the PROLEG transpiler already requires (`exception` ↔ `AND NOT` is sound only
if the signed dependency graph **stratifies**).

**Caveat that bites:** a *complete* stratification defeats the verification payoff.
If every conflict has a tie-breaker, the model checker never **reports** the
double-bind — the priority silently resolves the collision we wanted to surface as
a loophole / unsat core. This is the **detect ≠ resolve seam** (Poh Yuan Nie ¶28;
the PROLEG burden ledger).

So the target is **transparent partial stratification**:
- resolve exactly where the law genuinely prioritizes (lex specialis / lex posterior
  — L4's `SUBJECT TO` / `NOTWITHSTANDING` machinery), and
- deliberately **leave true gaps unresolved**, so verification can find them.

The stratification's job is to **separate "resolved by law" from "genuinely
conflicted"** — not to make everything go green.

## 5. The frontier as a small lattice

Strong / compile-time corner = **all three** of:

    (a) goal map total           — formula is closed
    (b) order acyclic & transparent — conflicts resolvable, but gaps preserved
    (c) factbase closed          — facts known statically

Every *other* corner peels off to runtime for a **different reason**:
- ¬(a): a free goal variable awaits runtime injection (anankastic / instrumental).
- ¬(b): unresolved or cyclic priority → either a detected conflict (good, the
  verification output) or a needed runtime tie-breaker.
- ¬(c): streaming facts can non-monotonically defeat prior conclusions → runtime
  re-evaluation (the two non-monotonicities: AND-NOT within a knowledge state;
  epistemic revision across knowledge states).

This **trichotomy of reasons** is more honest than a flat ∀/∃ split, and each ¬
corresponds to an existing L4 spec surface (goal/`Default`; `SUBJECT TO`/
`NOTWITHSTANDING`; runtime-input-state + temporal / event-sourced factbase).

## 6. L4 implementation hooks (to verify against current code)

- Constitutive = total typed functions ⇒ goal map totality lives here.
- `Default a` type ⇒ partial goal map (primary + fallback); totalize by supplying
  fallbacks. (From PROLEG/burden work.)
- `SUBJECT TO` / `NOTWITHSTANDING` ⇒ the transparent priority / superiority relation.
- `TYPICALLY` / defaults spec ⇒ defeasible defaults.
- Event-sourced / bitemporal factbase + temporal specs ⇒ axis (c).
- PROLEG stratification check ⇒ axis (b) acyclicity gate, already implemented.
- Verification: deontic double-bind ⇒ unsat core (ties to Meng's TLA+/UPPAAL origin).

## 7. Open question (back to Meng)

Where do **anankastic** obligations sit on the lattice? They look like they
straddle: ∃ in the goal axis (goal is supplied), yet once the agent commits to the
goal the residual obligation may be ∀-closed and statically checkable. Candidate
reading: anankastics are **partial-evaluation seams** — runtime goal-injection
*specializes* an open formula into a closed one, after which static verification
resumes. If so, the strong/weak split isn't a property of an obligation but of a
*phase* (pre- vs post-goal-commitment), and bounded deontics is really about
**staging** the verification.
