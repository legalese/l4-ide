# BOUNDED-DEONTICS-SPEC.md vs. the 2026-06-24 discussion (delta)

> What the existing spec (`specs/todo/BOUNDED-DEONTICS-SPEC.md`, Jan 2026,
> "Planning") already has, where the discussion has surpassed it, and what to
> harvest. Companion to `related-work.md` and `static-vs-runtime.md`.

## Headline: the spec is an independent rediscovery of Anderson (1958) + Meyer (1988)

- Its `BREACH`/`FULFILLED` terminal states **are** Meyer's violation atom `V`.
- Its "deontic force is always bounded by consequences" **is** Anderson's sanction
  constant `S` (`Oφ ↔ □(¬φ → S)`).
- Spec line 328: "L4 makes the consequences explicit rather than relying on abstract
  modal semantics" — that is Anderson's reduction _program_, stated as if new.
- The spec cites only Searle / Kant / Hvitved / Gneezy — **none** of the deontic-
  reduction lineage. The discussion supplies the missing genealogy (`related-work.md`).

## Where the discussion surpasses the spec

1. **Scholarship / genealogy** — Anderson, Meyer, Kratzer, anankastic conditionals,
   Yan & He 2025.
2. **Sanction/goal duality** — spec binds the deontic to its _consequence_
   (Andersonian `S`, the `HENCE`/`LEST` outcome); discussion adds the _goal_ face
   (Kratzerian `G`, the ordering source). Two faces of the same boundedness.
3. **The static/runtime lattice** — when compile-time verification is possible vs
   when you fall to runtime. Absent from the spec.
4. **Stratification + detect≠resolve** — complete stratification masks the very
   double-binds verification wants to find ⇒ target = transparent _partial_
   stratification. Absent from the spec.
5. **The anankastic inversion + staging** — categorical = static-easy, instrumental
   = static-hard; anankastics as partial-evaluation seams.

## Where the spec is still AHEAD (harvest for the paper's tooling half)

- The concrete **`DO … HENCE … LEST`** primitive + **MUST/MAY/SHANT** sugar table.
- **Hvitved-CSL composition** (Unix exit-code analogy) and the correct reading that
  "breach isn't inherently bad; valence comes from context" = Meyer's `V` is a
  _neutral marker_. The spec got this right.
- The **two-level object/assertion architecture** — see "the sorter" below.
- The verification-backend **roadmap** (UPPAAL / SPIN / NuSMV / Maude).

## The load-bearing synthesis: the two-level architecture is the _sorter_

Searle's constitutive "must-be" ("all directors must vote yes _for it to pass_") is
**not deontic** — it's definitional necessity, outside the domain of goal-relative
obligation. The spec's two-level check is the **gate** that sorts constitutive
must-be from regulative deontic. So the real pipeline is:

    sort (constitutive must-be vs regulative deontic)        ← spec owns this
      → derive goal-necessity relation over the automaton    ← discussion (corrected)
      → stratify transparently (SUBJECT TO / NOTWITHSTANDING)
      → model-check (compile) or monitor (runtime)

## CORRECTION that supersedes part of `static-vs-runtime.md` (Meng, 2026-06-24)

The spec's anankastic anticipation was **derived path-necessity**, not a per-
obligation goal index: "in this state machine there is no way to achieve outcome J
without performing action K; therefore if you want J you must K."

**This relation is many-to-many**, so indexing each obligation by an intended goal
(my earlier "typed obligation carries its goal", ≈ Yan & He's `O_G(φ)`) is **too
tightly coupled**. The correct object is a derived relation, not a map:

    nec ⊆ State × Action × Goal     (K,J) ∈ nec  iff  J unreachable from here without K

- many-to-many: one action necessary for many goals; one goal needs many actions;
  necessity is contingent on absence of alternative paths (not local to the obligation).
- keeps the **object level goal-free** (letter); goals live at the **assertion
  level** as queries (spirit). The spec was right to keep goals out of the mechanics.

Three payoffs of the relational view:

1. **An algorithmic MUST (replaces the withdrawn FCA payoff).** `Nec_s(J)` = the
   actions that **dominate** J in the reachability graph (every path to J passes
   through them) = a CTL dominator / minimal-cut set, near-linear via Lengauer–Tarjan.
   _(WITHDRAWN: the earlier "concept-lattice answers what minimal acts I'm bound to
   for a basket of goals" claim is FALSE — the `bounded-deontics-fca` workflow showed
   FCA's basket-intent = the column-intersection `∩_J Nec(J)`, which under-reports
   joint-goal necessity. See `notes/fca-verdict.md`. Any surviving FCA reading is
   **co-necessity only** — "acts forced in common across several goals" — never
   "minimal acts for a basket". FCA is parked for a journal facet.)_
2. **MUST/MAY = path quantifiers over goals.** MUST K for J = K dominates J (`A`-side
   path-necessity); MAY K = `EF J`, a path exists (`E`-side). (The spec's `AG/E`
   gestures, with J as relativizer.)
3. **Time-varying; deadline = `may→must`.** `nec` is state-indexed; a `WITHIN`
   deadline (or, non-temporally, alternative-path elimination) is the transition where
   an avoidable act enters the dominator set. **Caveat:** monotone growth of the
   necessary set holds only for _cumulative whole-trace_ necessity, NOT the
   _from-here-onward_ `nec` defined above (a performed act drops out of future
   necessity) — do not conflate the two.

**Effect on the lattice (`static-vs-runtime.md`):** axis (a) is **not** "goal map
total" (no map exists) — it is "**goal _set_ closed**": is the family of goals J we
compute necessity against statically enumerable, or runtime-supplied? Anankastic = J
is a runtime input ⇒ `nec(·,J)` is an on-demand query (runtime / partial evaluation);
categorical-with-background-goal = J fixed constant ⇒ precomputable (compile time).
Same inversion, correct data model.

**Novelty differentiation:** Yan & He attach the goal _to the obligation_ (`O_G`,
coupled); we argue goal-relativity is a _derived many-to-many relation over the
transition system_, object level goal-free. Distinct from the nearest neighbour.
