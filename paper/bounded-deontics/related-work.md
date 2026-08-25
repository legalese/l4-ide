# Bounded Deontics — prior art / related work

> Scholarship triage for the prospective "Bounded Deontics" paper. Drafted
> 2026-06-24 from web + arXiv search (a Google Scholar pass is still TODO — the
> browser extension lacked site permission for scholar.google.com during this
> session). **Citations below are from search snippets and need verification
> against primary sources before they go in a submission.** Items flagged
> `[verify]` are uncertain (author, year, venue, or page).

## Bottom line

The core idea of **bounded deontics** — an obligation is a (possibly implicit)
**goal-/sanction-indexed** conditional, reducible to ordinary modal / dynamic /
temporal logic — is **not novel**. It is a named, central move in three largely
separate literatures (philosophical deontic logic, linguistic modal semantics,
and analytic jurisprudence), the earliest being **Anderson (1958)**. The term
"bounded deontics" itself appears unused (no exact hits), but the paper must
foreground that it is _reconstructing_ a well-known reduction, not inventing it.

The defensible contribution is therefore **not** the reduction but (a) its
**engineering instantiation** in a typed, executable legal DSL (L4) with a real
compiler and verification payoff; (b) the **"or else what?" goal-index as a
drafting/type discipline**; and (c) a principled account of the **boundary** —
where the reduction is faithful vs. where it breaks (the "bounded" in the name).

---

## Strand 1 — Philosophical deontic logic: reduce O to modality + a violation constant

This is the closest prior art and the spine of the citation story.

- **Anderson, A. R. (1958), "A Reduction of Deontic Logic to Alethic Modal
  Logic," _Mind_ 67(265): 100–103.** `Oφ ↔ □(¬φ → S)`, where `S` is a propositional
  **sanction/penalty constant** ("the sanction is invoked"), with the axiom `¬□S`.
  This is "or else what?" formalized: an obligation _is_ the necessity that breach
  entails the sanction. **The direct ancestor of bounded deontics.** (DOI
  10.1093/mind/lxvii.265.100.)
- **Kanger, S.** — a parallel reduction using a constant `Q` ("what morality
  prescribes"). `[verify exact ref]` Usually paired with Anderson as the
  "Anderson–Kanger" reduction.
- **Meyer, J.-J. Ch. (1988), "A Different Approach to Deontic Logic: Deontic Logic
  Viewed as a Variant of Dynamic Logic," _Notre Dame J. Formal Logic_ 29(1).**
  Dynamic Deontic Logic (DDL). Enriches PDL with a **violation atom `V`**:
  `Fα ↔ [α]V` (an action is forbidden iff every execution leads to a violation
  state); `Pα ↔ ⟨α⟩¬V`. **This is exactly "squeeze the deontic into a state
  machine where bad transitions land in a violation state" — i.e. our compile
  target.** Our LTL/automaton move is Meyer's program, not naive LTL.
- **"An Andersonian Deontic Logic with Contextualized Sanctions"** (Springer,
  ~2012, DEON-adjacent) `[verify authors/venue]`. Replaces Anderson's single `S`
  with a **sanction operator indexed to the specific norm violated**. This is the
  nearest thing to our per-obligation "bounded" index — must cite and differentiate.
- **Anglberger, A. J. J.**, "Alternative Reductions for Dynamic Deontic Logics" /
  "Dynamic Deontic Logic and its Paradoxes" — surveys/refines the Meyer-style
  reductions and their paradoxes. `[verify]`
- Background: **Stanford Encyclopedia of Philosophy, "Deontic Logic"** (McNamara)
  — for the standard paradoxes our reduction is implicitly trying to dodge
  (Chisholm, contrary-to-duty, Ross, Good Samaritan).

## Strand 2 — Linguistic semantics: modality is already goal-relative

- **Kratzer, A.** ("What 'must' and 'can' must and can mean," 1977; "The Notional
  Category of Modality," 1981; _Modals and Conditionals_, 2012). The dominant
  theory: a modal is interpreted relative to a **modal base** + an **ordering
  source** (a set of goals/norms). A deontic "must" is necessity _relative to a
  goal-providing ordering source_ — i.e. **never an unindexed primitive.** Bounded
  deontics is, semantically, Kratzerian relativization. Foreground this: in
  mainstream semantics our central claim is the default, not a discovery.
- **Anankastic conditionals** — "If you want to go to Harlem, you must take the A
  train." Term from **von Wright**. Key analyses: **von Fintel & Iatridou (2005),
  "What to Do If You Want to Go to Harlem"**; **Sæbø (2001)**; **Huitink (2008
  diss.; "Anankastic Conditionals and Salient Goals")**; **Condoravdi & Lauer
  (2016)** (object to all prior semantics); **Phillips-Brown, "Anankastic
  Conditionals Are Still a Mystery."** Meng's "I must return the book _if I want to
  avoid a fine_" is a textbook anankastic conditional. Open problem there: a
  **compositional** semantics (what does "want" contribute?) — a known hard nut we
  should _not_ claim to have cracked.
- **Yan, J. & He, Q. (2025), "A Logic for Instrumental Obligation"
  (arXiv:2505.06824).** _Most direct contemporary overlap (≈1 yr old)._
  Goal-indexed obligations `O_G(φ)`; the goal **restricts the ordering** used to
  interpret the obligation (ideal worlds _consistent with the agent's goal_);
  Kratzer-style ordering sources; explicitly positioned **between hypothetical and
  categorical** obligation. We must engage this head-on and differentiate (they
  formalize the instrumental case; our angle is executable tooling + the boundary).
- **Kowalski, R. & Satoh, K. (2018), "Obligation as Optimal Goal Satisfaction,"
  _J. Philosophical Logic_ 47.** _(Added 2026-06-24 — flagged by the FCA workflow as
  a missing close neighbour; and it's **Satoh**.)_ The nearest goal-relativized-
  obligation account: obligation defined via optimal satisfaction of goals. Differentiate:
  ours is a **derived many-to-many necessity relation over a transition system**
  (`MUST` = dominator/cut), theirs a **preference order over FOL models**.
- **Apparatus-collision note (for any FCA revival):** the ternary `State×Action×Goal`
  is literally a **Triadic Concept Analysis** context (Lehmann–Wille 1995; Wolff
  2001), and **RBAC-via-FCA** already builds permission lattices + minimal-set
  extraction. ⇒ claim novelty strictly at the **semantic/domain** level, never the
  apparatus level. (FCA strand is parked — see `notes/fca-verdict.md`.)

## Strand 3 — Jurisprudence: the sanction/prediction lineage and its standard refutation

- **Bentham; Austin, _The Province of Jurisprudence Determined_ (1832).** Command
  theory: law = command backed by **sanction**. "Or else what?" = Austin's sanction.
- **Holmes, O. W. (1897), "The Path of the Law," 10 Harv. L. Rev. 457.** The **"bad
  man"**, to whom a duty is "a prophecy that if he does certain things he will be
  subjected to disagreeable consequences by way of imprisonment or compulsory
  payment of money." The bad man treats law as an **amoral state machine of
  sanctions** — i.e. he _is_ the Gneezy–Rustichini daycare parent. Prediction
  theory of law.
- **Hart, H. L. A. (1961), _The Concept of Law_.** The canonical critique:
  **"being obliged" (gunman/sanction) vs "having an obligation" (the internal
  point of view).** Squeezing out the deontics = collapsing Hart's distinction.
  So the behavioral economics below is a 20th-/21st-c. empirical confirmation of
  Hart's conceptual objection.
- **Kant, _Groundwork_ (1785).** Hypothetical ("Don't steal if you want to stay
  out of jail") vs **categorical** ("Don't steal") imperative. Bounded deontics =
  the contested thesis that _all_ legal oughts are hypothetical imperatives
  (carry a goal index); the **torture** edge case is a categorical imperative
  resisting the index. This is the philosophical fault line of the whole paper.

## Strand 4 — Behavioral / expressive-law counterweight (when squeezing out backfires)

Empirical/economic confirmation that `Obligation(A,X) ≠ Price(A,X,$10)`:

- **Gneezy, U. & Rustichini, A. (2000), "A Fine is a Price," _J. Legal Studies_
  29(1).**
- **Frey, B. & Jegen, R. (2001), "Motivation Crowding Theory," _J. Economic
  Surveys_ 15(5)**; Frey, "How Intrinsic Motivation Is Crowded Out and In."
- **Cooter, R., "Expressive Law and Economics"** (1998, _J. Legal Studies_);
  **Bohnet & Cooter (2003), "Expressive Law: Framing or Equilibrium Selection?"**;
  **Bohnet, Frey & Huck (2001), "More Order with Less Law."**

## Strand 5 — Cautionary counterpoint to the LTL plank

- **"Thou Shalt is not You Will"** (arXiv:1404.1685) `[verify author — poss. J.
Broersen]`. Argues norms are **not** just "what will always be true"; the naive
  O="always"/P="eventually" translation into LTL fails. Reinforces that our
  compile target needs Anderson/Meyer **violation markers**, not naive LTL.
- **"Expressibility of Norms in Temporal Logic"** (arXiv:1608.06787).
- **Ågotnes, van der Hoek & Wooldridge — Normative Temporal Logic** (a CTL
  generalization for temporal norms). `[verify]`
- Compliance/runtime-verification-of-norms literature (Giordano et al., _Temporal
  Deontic Action Logic ... in ASP_, ICAIL 2013) — bounded model checking of
  deontic constraints, close to our verification story.

---

## Strand 6 — §6 composition neighbours (deep prior-art pass)

From the `bounded-deontics-s6-priorart` workflow; full adjudication in
`notes/s6-priorart-verdict.md`. **Concede each by name; claim only the composition.**

- **C1 dominator MUST = planning landmarks.** Hoffmann, Porteous & Sebastia (2004,
  JAIR 22); Helmert & Domshlak (2009, LM-cut); Lengauer & Tarjan (1979, dominators).
  _Closeness 5/5 — concede the construct outright._ DISAMBIGUATE from **Horty (2001)**
  decision-theoretic "dominance" (homonym) and LAMA "reasonable orderings" (Richter &
  Westphal 2010).
- **C2 composition neighbours.** Shea-Blymyer & Abbas (2022, AIES — agent ordering +
  "all optimal actions guarantee A", single-agent, Bellman not dominator); Condoravdi
  & Lauer (2016); von Fintel & Iatridou (2005); Reisinger (2016); Katz/Portner/
  Rubinstein (2012); van Benthem/Grossi/Liu (2010/2014); Hansson (1969).
- **C3 Holmes/Hart.** **Silk (2019), "Normativity in Language and Law"** — nearest
  formal precursor (Hart internal/external as ordering-source variable); concede the
  Hart half. **Kolt (2026), "Superintelligence and Law," Harv. J.L. & Tech.
  (forthcoming)** — VERIFIED (sole author Noam Kolt; not "Kolt et al."/Anthropic);
  Part III.A pairs Austin/Holmes(bad-man) vs Hart(internal point of view) and ties the
  internal POV to letter-vs-spirit — a framing neighbour for C3 + §1, not a formal
  anticipation. Primaries: Holmes (1897); Hart (1961); Shapiro (2006). AI-agent
  adjacents (via Kolt): Casey (2017, Amoral Machines); O'Keefe et al. (2025, Law-
  Following AI); Nerantzi & Sartor (2024, Hard AI Crime). Sanction-as-realignment
  antecedents: McAdams (2015); Bénabou & Tirole (2011).
- **C4 force-gap.** Pearl (1993, UAI); Becker (1968); Shavell (2003); Cooter (1984,
  "Prices and Sanctions"); Calegari et al. (2020, CP-nets); Dellunde/Godo et al.
  (2008, graded DL).
- **C5 duality.** Anderson (1958); Kowalski & Satoh (2018); Governatori (2015);
  Castro & Maibaum (dCTL).
- **C6 strategic.** **Wooldridge & van der Hoek (2005), NATL\*** — near-exact, concede;
  Alur/Henzinger/Kupferman (2002); Broersen (2006); Jamroga/van der Hoek/Wooldridge
  (2004, DATL — the foil); Pauly (2002).

**INTEGRITY — CLEARED:** "Superintelligence and Law" VERIFIED = Noam Kolt (sole author),
Harv. J.L. & Tech. forthcoming, 25 Feb 2026 — promoted to a cited C3/§1 neighbour above.

## Positioning checklist for the paper

1. **Concede the reduction up front.** Lead with Anderson 1958 → Meyer 1988 →
   contextualized sanctions; say plainly we reconstruct, not invent.
2. **Claim the boundary, not the idea.** The "bounded" = the _domain of validity_
   of the reduction. Characterize the faithful zone (cooperative/instrumental
   norms) vs. the breakdown zone (Hart's internal POV, categorical imperatives,
   crowding-out). Yan & He formalize the inside; we map the edge.
3. **Claim the tooling.** CNL surface + typed goal-indexed obligations + compiler
   to a violation-automaton/LTL semantics + executable verification (loophole /
   deontic-temporal race conditions). No one in strands 1–3 built this.
4. **Bridge three literatures.** Part of the value is that deontic-logic,
   linguistic-modality, and jurisprudence camps rarely cite each other; L4 is a
   concrete artifact that forces the synthesis.
5. **Don't overclaim on anankastic compositionality** — it's a known open problem.

## Still TODO (scholarship)

- The promised **Google Scholar** pass (citation counts, who cites Anderson/Meyer
  for _legal/contract_ execution specifically, recent DEON/JURIX/ICAIL work).
- Verify all `[verify]` items against primary sources; confirm Anderson/Meyer
  page numbers; confirm the "Thou Shalt is not You Will" author.
- Check **DEON** (Deontic Logic and Normative Systems) proceedings 2020–2024 for
  near-neighbors beyond Yan & He.
- Governatori's defeasible deontic logic line (already on Meng's radar) — locate
  the closest "obligation-as-goal/sanction" statements there.
