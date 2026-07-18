# FCA / deontic-concept-lattice strand — verdict (workflow `bounded-deontics-fca`)

> Result of the background workflow (run wf_021cef1b-30e, 9 agents: 4 investigate →
> 4 adversarial stress → 1 synthesis). **Recommendation: PARK FOR JOURNAL.** The
> headline FCA payoff is false; the sound core survives and belongs in JURIX v1 §5
> independently of FCA. This note is the durable record.

## The kill: the FCA basket query is provably wrong

The pitched payoff — "the concept lattice answers *what minimal set of acts am I
bound to perform for this basket of goals*" — does not hold.

- FCA intent-derivation of a basket `Y` computes the **column-intersection**
  `Y' = ∩_{J∈Y} Nec(J)`, which is neither the union of per-goal necessities nor the
  legally-correct **joint-goal** necessity `NecBoth(Y)`.
- **Counterexample (realizable in a genuine labelled transition system):**
  `a;c → J₁`, `b;c → J₂`, only `a;b;c → both`. Then `Nec(J₁)={a,c}`,
  `Nec(J₂)={b,c}`, so FCA gives `{a,c} ∩ {b,c} = {c}`, while the correct joint bound
  is `{a,b,c}`. FCA **under-reports** the obligations — the dangerous direction for
  compliance.
- **Root cause (structural):** necessity is *non-local* — it depends on which paths
  achieve the goals *jointly* — and per-cell incidence projects that away. Necessity
  **does not compose across goal-conjunction**; the lattice cannot answer the exact
  question it was introduced to answer.

## What survives (and carries JURIX v1 §5 — NOT the FCA strand)

The single-goal necessity core is sound and algorithmic:

- `Nec_s(J)` = the actions that **dominate** J in the reachability graph from state
  `s` (every path to J passes through them) = a **CTL dominator / minimal-cut** set.
- **MAY** K = `s ⊨ EF J` (a path to J exists).
- **MUST** K (for J) = K dominates J.
- **may→must** = the step where the last alternative path lapses and a previously
  avoidable action *enters* the dominator set. Computable near-linearly via
  **Lengauer–Tarjan** dominators.

This is a *better* §5 than the FCA framing: MUST gets a precise, citable, computable
definition, and it stands with no FCA apparatus. It is the differentiation from Yan &
He (derived relation over a transition system, not a goal index on the obligation).

## What is salvageable for a journal paper (the parked strand)

Two candidate contributions, lead with the counterexample either way:
1. **A non-compositionality theorem** — the concept lattice over `(Action×Goal,
   nec_s)` is sound but *provably lossy* w.r.t. joint-goal necessity (the intent
   derivation = intersection, invariant to whether goals interact). A clean negative/
   structural result.
2. **The correct construction** — basket-indexed / **triadic FCA** context (the
   ternary `State×Action×Goal` is literally a TCA context). Honest baseline to beat:
   minimal hitting-set / set-cover (Reiter 1987), with its NP-hardness stated.

## Open risks / things to fix before any revival

- **DEFINITIONAL (live):** the bug-vs-feature status hinges on the unstated meaning
  of "I want this basket." If *independent per-goal discharge* → the intersection is
  correct but the lattice is decorative (just intersecting precomputed dominator
  sets). If *joint-goal reachability* → the bug is fatal. Verdict robust because the
  lattice over-promises under **either** reading. A journal paper must FIX basket
  semantics up front.
- **Thin salvage:** the co-necessity reading ("acts forced in common across many
  goals") is of limited legal interest vs. the marketed query; risk that FCA does no
  work the CTL/reachability reasoner doesn't already do (reviewers will say so).
- **Tractability:** hitting-set/transversal is output-exponential — don't silently
  swap a lossy-but-cheap lattice for an exact-but-intractable hypergraph.
- **Temporal apparatus:** `nec` is irreducibly state-indexed → a *family* `{L(s)}`,
  not one lattice. TCA prior art (Lehmann–Wille 1995; Wolff 2001) does NOT directly
  license the deadline-crossing picture (Wolff moves an object through a *fixed*
  lattice; here the incidence relation itself changes per state) — needs a Conceptual
  Time System construction.
- **may→must monotonicity is mis-stated:** the ascending-chain ("increment IS the
  deadline") holds only for **cumulative whole-trace** necessity, NOT the
  **from-here-onward** `nec` we defined (a forced act, once performed, drops out of
  future necessity). Fix this conflation before any monotone-trajectory claim.
  *(Action item: also correct in `static-vs-runtime.md` and `illustrations.md`.)*
- **Prior-art gaps:** add **Kowalski & Satoh, "Obligation as Optimal Goal
  Satisfaction" (J. Phil. Logic 2018)** — closest goal-relativized-obligation
  neighbour (and it's Satoh). Pre-empt **Triadic Concept Analysis** and
  **RBAC-via-FCA** (apparatus collisions) — claim novelty strictly at the
  semantic/domain level.
- **Doctrinal audit:** the Art. 9 cells (9-312(b)(1) deposit-account control-only;
  9-328 control-beats-filing; 9-317(a)(2)+544(a) strong-arm) are black-letter but
  audited from doctrine — a secured-transactions reviewer should check vs. 2022
  amendments / PPSA (AU/NZ/CA) divergences before print.

## Chosen illustration (confirmed, but DECOUPLED from FCA)

**UCC Art. 9 / PPSA perfection** carries §5's `nec` / may→must story — *not* a concept
lattice (its disjunctive file-OR-possess structure flattens the lattice; goal axis
collapses to perfected/unperfected + a priority rank). Sketch: deposit account, goal =
priority over a control-creditor → control is the only path → `(control, J) ∈ nec` =
MUST; filing doesn't reach J → not nec. Ordinary goods, goal = bind a lien creditor →
file OR possess both reach it → neither individually necessary = MAY. may→must when
the claimant/collateral field changes so all surviving paths pass through one act.
Demote HDC / contract-formation / standing (degenerate); Wills Act stays the
constitutive-vs-regulative sorter foil.

## Actions taken from this verdict

- OUTLINE: FCA removed from v1 contribution claims (→ deferred journal facet); §5
  restated as dominator/cut-set; §7 illustration decoupled from FCA.
- spec-delta.md: the inconsistent FCA payoff sentence corrected to co-necessity only.
- related-work.md: Kowalski & Satoh 2018 + TCA/RBAC collision note added.
- may→must cumulative-vs-from-here caveat flagged in the relevant notes.
