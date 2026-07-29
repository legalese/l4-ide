# Citation verification — read from the full PDFs (2026-06-25)

> Six parallel readers verified the §2/§6 citations against the actual PDFs in the
> Dropbox `to-print/` dir. This is the source of truth for the `.bib` and for the
> §2/§6 differentiations. Supersedes looser claims in `related-work.md` /
> `s6-priorart-verdict.md` where flagged.

## ⚠️ Material corrections (fix before drafting hardens)

1. **Yan & He 2025 — our reason was BACKWARDS.** We wrote they "keep two priority
   structures separate by design." Truth: they _raise_ the agent-goal vs ideal/law
   distinction (§2.2) and **deliberately unify it into ONE ideal ordering** — the goal
   _restricts a subset_ of the single ideal ordering and "does not change the ideal
   ordering." Exactly one priority structure in the model. The operator is a **dyadic
   `O(goal : action)`** defined via **Pearl-style causal intervention + best-world**,
   NOT a goal-indexed `O_G` subscript, NOT a Kratzer ordering source in the formalism,
   single-agent, satisfiability NP-complete. ⇒ This _strengthens_ our C3 (they had two
   orderings and collapsed them; we keep them apart and study the gap), but fix the
   stated reason in `related-work.md`, `spec-delta.md`, `kolt-2026-*.md`.
2. **Silk 2019 — soften.** Silk collapses Kratzer's modal-base + ordering-source into a
   single **premise set P** "for simplicity" (fn. 8). So call it a "premise-set /
   simplified Kratzer parameter," not an ordering source. It is **NOT party-indexed**:
   the contrast is _endorsing vs non-endorsing_ uses of modals over the **same** norms
   (discourse-level `P_l` vs object-level `P_NH`/`P_v`), Hart **and Raz** (detached =
   external). Do NOT say Silk already has two parties' orderings. Concession scoped to
   the _internal/external as premise-set choice_ idea only.
3. **Landmarks (Hoffmann et al.) — concede more, claim less on C1.** "Landmark = fact
   on every solution plan" IS our dominator (at the fact level) — concede the whole
   insight. But there is **no explicit "graph dominator / minimal-cut over a transition
   system" theorem**; the cut intuition lives in the PSPACE/PLANSAT-reduction proof and
   in the reasonable-order _deletion_ clause. No MAY=EF dual, no deontic. Our C1
   residue = the deontic dual (MAY=`EF J`), the transition-system/dominator _phrasing_,
   and the legal reading — NOT the "necessary on every plan" idea itself.
4. **Two "dominance" HOMONYMS to disambiguate** (not one): (a) Horty's decision-theoretic
   action _dominance_; (b) Shea-Blymyer & Abbas's logic EAU descends from Horty's
   **Dominance Act Utilitarianism (DAU)** — their "dominance" = utility-dominance over
   actions. Neither is our graph goal-_dominator_. One footnote must clear both.

## Verified bibliography + per-claim notes

- **Silk 2019** — Alex Silk, _Normativity in Language and Law_, in D. Plunkett, S.
  Shapiro & K. Toh (eds.), _Legal Norms, Ethical Norms: New Essays on Metaethics and
  Jurisprudence_, OUP 2019. (PDF = author preprint; verify OUP page span.) C3 Hart-half;
  quotes: "Hart's distinction between 'internal' and 'external' legal claims can be
  viewed as an instance of the … endorsing and non-endorsing uses of modals" (p.19);
  "The difference lies in what premise set variable is supplied" (p.19).
- **Shea-Blymyer & Abbas 2022** — _Generating Deontic Obligations From Utility-Maximizing
  Systems_, AIES '22, pp. **653–663**, DOI **10.1145/3514094.3534163** (Oregon State).
  C2 closest composition. Obligation (Def 3.3): `⊗[α cstit:A]` iff A is guaranteed by
  **every optimal action**, optimality = **Bellman** (§4.2: "the EAU optimal action and
  the Bellman optimal action are the same"). Cardinal/probabilistic (PCTL), single
  ordering fused into the modality. **C2 survives**; delta = dominator (reachability)
  vs Bellman-optimality (value), and composed-over-ordering-agnostic vs ordering-fused.
- **Yan & He 2025** — Jialiang Yan & Qingyu He (Tsinghua), _A Logic for Instrumental
  Obligation_, **arXiv:2505.06824v1**, 11 May 2025 (preprint; no venue). See correction
  #1. Quotes: "the goal … constrains a subset of the ordering" (§2.2 p.3); "an agent's
  goal … does not change the ideal ordering" (p.4).
- **Hoffmann, Porteous & Sebastia 2004** — _Ordered Landmarks in Planning_, **JAIR 22
  (2004) 215–278**. (Primary origin: Porteous, Sebastia & Hoffmann, ECP-2001.) See
  correction #3. Def 1 (p.218): landmark = fact true at some point on every solution
  plan; LANDMARK is **PSPACE-complete** via PLANSAT-complement reduction (p.219).
- **Wooldridge & van der Hoek 2005 (NATL\*)** — _On Obligations and Normative Ability:
  Towards a Logical Analysis of the Social Contract_, **J. Applied Logic 3 (2005)
  396–420**, doi:10.1016/j.jal.2005.04.006. Obligation AS ATL modality: `P_η φ ≜
⟨⟨η:Ag⟩⟩φ`, `O_η φ ≜ ¬P_η¬φ` (p.408). Indexed by **norm-system η** (action-constraint
  set), doubly (η, C); **O_η fixed to grand coalition Ag** (sub-coalition `P_{C,η}` =
  future work). Over AATSs. ⇒ our party-PREFERENCE indexing, single-party `⟨⟨p⟩⟩F J`,
  dominator-as-degenerate-case, and C3 reading are all genuinely ours. (Year **2005**.)
- **Pearl 1993** — _From Conditional Oughts to Qualitative Decision Theory_, **UAI-93
  proceedings, pp. 12–20** (Morgan Kaufmann; tech report R-201). Force = utility gap
  with 1/ε threshold, but **cardinal** (integer μ) and **single-agent**. Our delta =
  ordinal + party-indexed. (Cite as proceedings, NOT a journal/Festschrift.)
- **Gneezy & Rustichini 2000** — _A Fine Is a Price_, **J. Legal Studies 29(1) (Jan 2000) 1–17**, DOI 10.1086/468061. Field experiment, 10 Haifa daycares, NIS 10/child
  fine; lateness ~doubled and **did not revert** after removal. Corroborating data, not
  a rival formalism. Quote: title "A Fine Is a Price."
- **Governatori 2015** — _Thou Shalt is not You Will_, NICTA TR-8026 / **arXiv:1404.1685v3**
  (25 Jan 2015); short version ICAIL 2015, pp. 63–68. Caution is **qualified** (a
  _particular_ naive LTL formalisation fails, not LTL per se). O = **maintenance (G)**,
  achievement = **F** (p.7); the G/F-duality conflation with permission is his objection.
- **Condoravdi & Lauer 2016** — _Anankastic conditionals are just conditionals_,
  **Semantics & Pragmatics 9:8, pp. 1–69**, DOI 10.3765/sp.9.8 (open access, CC-BY).
  Agent-indexed **bouletic ordering source** `g_bulA` (p.8:6) AND explicit legal-vs-agent
  juxtaposition: "For [the tax] sentence, the norms … US tax law. For the Harlem
  sentence … the preferences of the agent" (p.8:10). Strong C2 support.
- **von Fintel & Iatridou 2005** — _What to Do If You Want to Go to Harlem: Anankastic
  Conditionals and Related Matters_, **unpublished ms** (Rutgers Semantics Workshop,
  Sept 2005). The "A train" locus classicus; explicit "hypothetical goal must override
  conflicting actual goals" (p.5). Proposes a **nested/doubly-modalized** account (they
  _reject_ Sæbø's ordering-source-augmentation). Cite as "ms.", not a journal.

## Net effect on novelty

All four headline deltas hold and several sharpen: C2 (dominator≠Bellman) survives;
C3 strengthens (Yan & He collapse the two orderings; Silk lacks the Holmes/predictive
half and party-indexing); C4 delta (ordinal+party-indexed vs Pearl's cardinal single-
agent) confirmed; C1 must concede the landmark insight outright and claim only the
deontic re-reading. Build the `.bib` from the verified entries above.

## van der Meyden — permission dual + the SAFE-author identity (2026-07-29)

Pulled to answer "do the prior-art papers frame MAY as the dual to the dominator,
and how do they tackle state-space explosion?" Feeds `draft/section-permission-and-explosion.tex`.

- **van der Meyden, "The Dynamic Logic of Permission," J. Logic and Computation
  6(3):465–479, 1996** (DOI 10.1093/logcom/6.3.465). Verified via dblp + OUP.
  - Classifies **executions (state-sequences), not states**, as permitted →
    trajectory-indexed, constrains intermediate course, not just the result.
  - Separates **free-choice permission** from **permission-as-lack-of-prohibition**;
    the former is what standard modal logics can't capture — his stated motivation.
  - **NOT goal-indexed.** ⚠️ Correction to an earlier chat claim: do NOT describe it
    as "the edge that keeps the goal reachable" — that goal-reachability dual is the
    Anderson/Meyer `◇(A∧¬V)` reading (our reconstruction), not van der Meyden's result.
    His is the transition-system home of _free-choice_ permission, a different refinement.
  - **DLP is EXPTIME-complete**; contribution is a complete axiomatisation, not a
    scalable checker. This IS the strand-1 answer to "how do they handle explosion":
    they don't enumerate a model — the cost lives in the decision procedure.
  - Follow-up: **"Reduction from DLP to PDL," JLC 15(5):767–782, 2005**
    (DOI 10.1093/logcom/exi044) — page range to reconfirm against OUP before camera-ready.
- **Identity confirmed:** same Ron van der Meyden (UNSW) authored the DLP papers and,
  with **Michael J. Maher**, the **SAFE** book — _Simple Agreement for Future Equity
  (SAFE): Smart Contracts for Venture Finance_, Springer Nature Singapore, Blockchain
  Technologies series, 2025 (ISBN 9789819639199, DOI 10.1007/978-981-96-3920-5,
  hardcover 2 Oct 2025). One author spans the classical semantics of permission and its
  contemporary executable use — a one-citation spine linking the deontics paper's
  permission dual to the SAFE facet. (Cross-ref memory [[yc-safe-executable]].)
- Three-strata explosion story recorded in the draft: (1) classical deontic logic
  (Anderson→Meyer→van der Meyden) doesn't enumerate; (2) normative-MAS model checkers
  (MCMAS/deontic interpreted systems) use generic OBDD/POR/BMC; (3) planning landmarks
  = dominators dodge the product via delete-relaxation (Hoffmann–Porteous–Sebastia 2004;
  Helmert–Domshlak 2009; Richter–Westphal 2010). Lomuscio & Sergot 2003 srctag still
  needs a bib entry + primary-source check before camera-ready.
