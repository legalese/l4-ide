# Bounded Deontics — paper outline + venue scoping (v0.1)

> First-crack outline, 2026-06-24, informed by `related-work.md`, `spec-delta.md`,
> and `notes/static-vs-runtime.md`. Everything here is provisional.

## Title candidates

- **"Deontics as Domination"** (front-runner, recorded 2026-07-18). The pun carries
  the paper's technical core exactly: a `MUST` precondition *is* the **graph
  dominator** of any LTS leading to a desired goal — every path to the goal passes
  through the obligated act (§5). Doubles as the jurisprudential hook — obligation as
  a relation of *domination* (Austin/Holmes command-and-sanction; the "or else what?"
  probe). Reads on both registers, which is the whole thesis in two words.
  - Possible subtitle: *"Goal-bounded obligation as necessity in a transition system"*
    (or *"…as dominator-necessity over a transition system"*).
- Fallbacks: "Bounded Deontics" (the working label; descriptive, less pointed);
  "Or Else What? Goal-Bounded Obligation and its Verification."

## Program strategy (faceting)

Bounded Deontics is **one facet of a planned series** of papers, each aimed at a
different venue, that compose to describe the whole L4 vision (cf. the ICAIL paper,
PROLEG/burden-of-proof, ladder diagrams, state-as-ledger, Poh Yuan Nie). Decisions
that follow from this:
- We need NOT cram everything into one paper; strands that overflow (e.g. the
  FCA/concept-lattice idea, the full tooling/compiler story) can become their own
  facets.
- **Single-paper vs split is deliberately deferred** ("get the thoughts out first").

## Thesis (one sentence)

The deontic "must" of law and contract is not primitive but **goal-bounded**, and on
the bounded reading the goal-relativized obligation is a **derived, many-to-many
necessity relation over a transition system** — which (a) reconstructs Anderson's
sanction reduction with the right data model, (b) keeps the object level goal-free
(letter/spirit), and (c) yields a verification story whose *domain of validity* —
the "bound" — is itself the contribution.

## Contribution claims (what is actually new)

> **Posture (from the `bounded-deontics-s6-priorart` deep-research pass — see
> `notes/s6-priorart-verdict.md`): a UNIFICATION, not new primitives.** Every
> ingredient is prior art and is conceded by name; the contribution is the
> *composition* + the *jurisprudential reading*. Claims below in descending strength.

1. **(C3, strongest) The Holmes+Hart unification.** ONE divergence between `⪯_law`
   (normative) and `⪯_p` (the agent's, read **descriptively** as a behaviour-predictor)
   is *both* Holmes's bad man (where they diverge) and Hart's internal point of view
   (where they collapse), with sanctions as the realignment operation. *Concede the
   Hart-half formal precedent to **Silk 2019**; claim the Holmes+Hart unification +
   descriptive `⪯_p` + composition with the dominator-necessity.*
2. **(C2) Party-indexed ordering ∘ a graph-DOMINATOR necessity.** The composition's
   necessity is a **dominator** (on every path), not Bellman-optimal action / best
   world / causal intervention — the form no neighbour has. *Concede the party-indexed
   ordering and the composition idea (Condoravdi–Lauer; Shea-Blymyer & Abbas 2022);
   claim the dominator form.* Also the **derived-relation** stance vs. Yan & He's
   coupled `O_G`.
3. **(C5) Sign-toggled liveness/safety.** A single party-indexed `⪯_p` whose **sign**
   on an outcome routes the *same* dominator to its liveness pole (`EF J`, pursue) or
   safety pole (`AG¬S`, avoid). *Concede the sanction/goal duality (Anderson;
   Kowalski–Satoh 2018); claim the sign-selector + temporal split.*
4. **(C4) Ordinal, party-indexed force-gap.** `Force(MUST_p K)` = rank-difference over
   a Kratzer preorder, paired against `⪯_law` so sign + the C3 divergence fall out of
   one schema. *Concede the cardinal gap (Pearl 1993; Becker/Shavell); claim the
   ordinal deontic-native form; present fine-is-a-price as the legal sign-reading.*
5. **The engineering instantiation** in L4: goal-free CNL object syntax + compile to a
   violation-automaton/LTL semantics + loophole/race-condition verification. (No
   neighbour builds this.)
6. **Honest genealogy**: explicitly a reconstruction of Anderson (1958) / Meyer (1988);
   and the multi-party/ATL escalation (C6) is openly **recombination** of NATL\* +
   our C1/C2 deltas, framed as a future facet, not an independent claim.

*CONCEDED OUTRIGHT (state by name, do not claim): C1 dominator MUST = planning
**landmarks** (Hoffmann/Porteous/Sebastia 2004; LM-cut 2009) + Lengauer–Tarjan;
C6 obligation-as-strategic-ability = **NATL\*** (Wooldridge & van der Hoek 2005);
CTL-in-ATL = Alur et al. 2002. FCA strand stays parked (`notes/fca-verdict.md`).*

## Section outline

1. **Introduction — "or else what?"** The vernacular probe; letter vs spirit
   (program executes / specification judges); the Gneezy-Rustichini + Saki framings
   (the latter as the reverse-direction type error). State the thesis and the five
   claims. **Concede the genealogy up front.**
2. **Background & prior art** (= `related-work.md`). Anderson `S`; Meyer `V`;
   Kratzer modal base + ordering source; anankastic conditionals (von Fintel &
   Iatridou); Yan & He 2025 (`O_G`, the coupled view we differentiate from);
   Searle (constitutive/regulative); Kant (hypothetical/categorical); Austin →
   Holmes "bad man" → Hart "obliged vs obligation"; Gneezy-Rustichini / Frey /
   Cooter.
3. **The object level (the letter).** `DO … HENCE … LEST`; MUST/MAY/SHANT as sugar;
   `BREACH`/`FULFILLED` = Meyer's *neutral* violation marker; Hvitved-CSL
   composition. **Goal-free by design.** (Harvested from the spec.)
4. **The sorter: constitutive must-be vs regulative deontic.** Searle; the two-level
   architecture as the gate; only regulative deontics enter the bounded analysis.
   (Resolves the scope of every later quantifier.)
5. **The derived goal-necessity relation (the spirit).** Define `nec`; **MAY** K =
   `EF J` (a path to J exists); **MUST** K (for J) = K **dominates** J in the
   reachability graph (every path to J passes through K) = a CTL dominator /
   minimal-cut set, near-linear via Lengauer–Tarjan; many-to-many; `WITHIN` deadlines
   (and, non-temporally, alternative-path elimination) as the `may→must` event = the
   step where an avoidable action enters the dominator set. *Formal core; the
   differentiation from Yan & He.* **Concede the construct to planning landmarks**
   (Hoffmann et al. 2004 / LM-cut) + Lengauer–Tarjan; claim only the *deontic reading*.
   Disambiguate from **Horty's** decision-theoretic "dominance" (homonym) and LAMA
   "reasonable orderings". **Caveat to honour:** the monotone-growth of the necessary
   set holds for *cumulative whole-trace* necessity, NOT the *from-here-onward* `nec`
   (a performed act drops out of future necessity) — do not conflate. No concept
   lattice in v1.
6. **The boundary — two orderings (the paper's center of gravity).** Concede-then-
   claim. The party-indexed ordering source `⪯_p` over the party-neutral dominator
   `nec`; `⪯_law` vs `⪯_p` and the **Holmes+Hart unification** (C3); the sign-toggled
   liveness/safety duality (C5); the ordinal force-gap with fine-is-a-price /
   protestor as gap-sign cases (C4). Then the static/runtime lattice (goal-set closed;
   order acyclic & transparent; factbase closed); anankastic inversion + partial-
   evaluation staging; Hart's internal point of view + crowding-out as the *semantic*
   (not magnitude) limit — correcting the spec's penalty-size test. See
   `notes/per-party-ordering.md` + `notes/s6-priorart-verdict.md`.
7. **Verification & tooling.** Compile-time: model-check the closed form, double-bind
   = unsat core (loophole / deontic-temporal race condition; TLA+/UPPAAL/SPIN/NuSMV
   lineage). Runtime: monitoring the live event-sourced trace. Transparent partial
   stratification via `SUBJECT TO` / `NOTWITHSTANDING`. **Worked example (confirmed):
   UCC Art. 9 / PPSA perfection**, carrying the `nec` / may→must story — *decoupled
   from FCA* (its disjunctive file-OR-possess structure flattens any lattice). Sketch:
   deposit account → control is the only path to priority → MUST; ordinary goods →
   file OR possess → MAY; may→must when the claimant/collateral field changes
   (non-temporal). **Wills Act formalities** stays the constitutive foil for §4's
   sorter. Demote holder-in-due-course / contract-formation / standing (degenerate).
   *NOT the gov race-condition pilot* (temporal/concurrency, wrong fit).
8. **Discussion / limitations.** Anankastic compositionality is a known open problem
   (do NOT claim to solve). Categorical norms and the contestable "all oughts are
   hypothetical." Cooperative-parties assumption.
9. **Conclusion.**

## Venue scoping

| Venue | Fit | Cadence | Notes |
| --- | --- | --- | --- |
| **DEON** (Deontic Logic & Normative Systems) | **Best** for the theory core (§§5–6) | biennial — *verify next cycle* | The audience that knows Anderson/Meyer/Kratzer; where the boundary/derived-relation claims land hardest. |
| **ProLaLa** (Programming Languages & the Law, POPL workshop) | **Best** for the tooling half (§§3,7) | annual, w/ POPL (Jan) | On-brand for L4; PL+law crowd; lighter theory bar. |
| **JURIX** (Legal Knowledge & Information Systems) | Strong all-rounder | annual (Dec) | Applied AI&Law; good if we want annual + legal framing. |
| **ICAIL** | Possible but **avoid clash** | biennial (Jun) | Home of the main L4 paper; differentiate to avoid self-overlap. |
| **Journal** (AI & Law; J. Logic & Computation) | For the full-length version | rolling | If the FCA/concept-lattice strand matures. |

**DECIDED: JURIX** (Meng attends regularly, has colleagues there; it comfortably
carries both the theory and the applied/tooling framing, so no venue-driven split is
forced). Format to confirm against the current CFP: IOS Press *Frontiers in AI and
Applications*, long papers ~10pp / short ~6pp, typically **December** conference with
**~September** submission. DEON / ProLaLa remain candidates for *later facets* in the
series, not this paper.

**Co-authors:** Oliver Goodenough (the "squeezing out the deontics" framing is jointly
his) pencilled. Consider Ken Satoh only if a PROLEG/defeasibility angle grows.

## Open decisions

- ~~Venue~~ → **JURIX** (decided 2026-06-24).
- ~~FCA in scope for v1?~~ → **NO** — `bounded-deontics-fca` workflow refuted the
  basket claim; FCA parked for a journal facet (`notes/fca-verdict.md`). v1 carries
  the dominator/cut-set MUST instead.
- ~~Worked example?~~ → **UCC Art. 9 confirmed**, decoupled from FCA; race-condition
  dropped (temporal mismatch).
- **Single paper vs faceted split** — deliberately deferred until thoughts are out.

## Immediate next actions

- [x] **INTEGRITY — DONE:** "Superintelligence and Law" VERIFIED from the PDF = **Noam
      Kolt** (sole author), *Harv. J.L. & Tech.* forthcoming (25 Feb 2026) — NOT "Kolt
      et al."/Anthropic. Promoted to a cited **C3/§1 framing neighbour** (its Part III.A
      pairs Holmes-bad-man vs Hart-internal-POV and ties internal POV to letter-vs-
      spirit). See `notes/kolt-2026-superintelligence-and-law.md`.
- [ ] Confirm current JURIX CFP (deadline + IOS Press format/length) → fixes budget.
- [ ] Write the **§6 concession paragraph FIRST** (concede-then-claim): name planning
      landmarks (Hoffmann et al.) and NATL\* (Wooldridge & van der Hoek) explicitly;
      lead the deltas with C3 then C2. Insert the two disambiguations (graph dominator
      vs Horty dominance; betterness ordering vs LAMA "reasonable orderings").
- [ ] Obtain paywalled/abstract-only primaries before fine distinctions: vBGL full
      text, Bénabou–Tirole body, Broersen DEON 2006 reduction, von Fintel–Iatridou MS,
      Migotti 2015 (price/sanction/cost trichotomy).
- [ ] Add the §6 must-cite list (`notes/s6-priorart-verdict.md`) to `related-work.md`;
      already added Kowalski & Satoh 2018, Silk 2019, Shea-Blymyer & Abbas 2022.
- [ ] Sweep un-exhausted adjacent lines (Horty stit/default; Boella–van der Torre NMAS
      games; Casali–Godo–Sierra graded DL; van der Hoek NTL) for closer C3/C4/C5.
- [ ] Google Scholar pass (still blocked on extension perms); verify `[verify]` cites
      + metadata (Pearl UAI pages, Kowalski–Satoh JPL pages, DEON/ICAPS pagination).
- [ ] Draft §5 (`nec` + dominator MUST, conceded to landmarks, deontic reading claimed)
      then §6 (concede-then-claim, C3-led). No FCA lattice figure.
