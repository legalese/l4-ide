# §6 prior-art delineation — verdict (deep-research workflow `bounded-deontics-s6-priorart`)

> Result of the deep prior-art workflow (run wf_a68513fd-d0e; 13 agents, ~816k tokens,
> 202 tool calls; 6 literature surveys → 6 claim adjudications → synthesis). First run
> died on a transient API 529; the resume succeeded. Durable record for §6.

## Bottom line: synthesis, not new primitives

Every atomic ingredient of the §6 construction is established prior art and must be
**conceded by name**. The defensible novelty is the **composition** + the
**jurisprudential reading**. The recommended posture — _concede generously, claim
narrowly, unify_ — is itself the strongest defense against a hostile JURIX reviewer.
Calibration: **no claim is clean-novel**; every one is "partially-anticipated-at-risk."
C1 and C6-mechanism are near-EXACT anticipations.

## Claim-by-claim

- **C1 (MUST = graph dominator / minimal-cut).** CONCEDE the construct — it is the
  **planning landmark** (Hoffmann, Porteous & Sebastia 2004; landmark = fact/action on
  every solution plan; the PSPACE proof = "remove all achievers ⇒ goal unreachable" =
  minimal cut/dominator) and **LM-cut** (Helmert & Domshlak 2009), over **Lengauer–
  Tarjan 1979** dominators. _Closeness 5/5._ Keep only: reading this party-neutral
  necessity as deontic MUST (MAY=EF, MUST=AG-domination). DISAMBIGUATE from Horty's
  decision-theoretic "dominance" (homonym) and from LAMA "reasonable orderings."
- **C2 (party-indexed ordering ∘ dominator).** CONCEDE both halves: party-indexed
  ordering source (Condoravdi–Lauer 2016; von Fintel–Iatridou 2005) and composition of
  an agent ordering with a goal-necessity over a transition system (**Shea-Blymyer &
  Abbas 2022** "all optimal actions guarantee A"; Yan–He 2025 causal). Keep: the
  necessity is a **graph DOMINATOR** (on every path), not Bellman-optimal action / best
  world / causal intervention — the one element all neighbours lack, and the structural
  bridge that yields C3/C4/C5. (Risk: a reviewer may call dominator-vs-optimal cosmetic
  ⇒ weight shifts to C3.)
- **C3 (⪯_law vs ⪯_p divergence = Holmes/Hart). STRONGEST SURVIVOR.** CONCEDE the
  Hart-half formal precedent: **Silk 2019** already renders Hart's internal/external
  (and Raz's committed/detached) as _which ordering-source variable the modal reads
  against_, with divergence carrying the load and internal-POV = adopting the law's
  variable. Keep (claim this): (1) ⪯_p as a **descriptive behaviour-PREDICTOR**
  (Holmes's bad man), not an endorsement set; (2) **ONE divergence being BOTH** Holmes
  (diverge) and Hart (collapse); (3) composition with the dominator-necessity;
  (4) sanction as a formal **realignment** operation moving ⪯_p toward ⪯_law (vs the
  scalar-utility prose of Bénabou–Tirole / McAdams).
- **C4 (Force = rank-gap).** CONCEDE the cardinal gap: **Pearl 1993** (utility gap with
  firing threshold), **Becker 1968 / Shavell 2003** ("commit iff benefit > expected
  sanction"); both sign-readings pre-empted (fine-is-a-price gap≤0 = Gneezy-Rustichini/
  Cooter; protestor gap<0 = negative deterrence). Keep: ORDINAL rank-difference over a
  Kratzer preorder (not cardinal EU), PARTY-INDEXED against a paired ⪯_law so sign and
  the C3 divergence fall out of one schema, attached to the C1 dominator. Present
  fine-is-a-price as the **legal sign-reading** of a known economic phenomenon.
- **C5 (sanction/goal duality = sign under ⪯_p).** CONCEDE the duality: Anderson 1958
  (constant S); **Kowalski–Satoh 2018** (sanction = worse disjunct of a goal under one
  model-order); Governatori 2015 (O=maintenance, P=achievement temporal map);
  Cooter/Gneezy-Rustichini inversion. Keep: a SINGLE party-indexed ⪯_p whose SIGN routes
  the SAME dominator to its liveness pole (EF J, pursue) or safety pole (AG¬S, avoid) —
  distinct from Governatori's O/P modal duality and Kowalski–Satoh's atemporal rank.
- **C6 (multi-party strategic MUST = ATL ⟨⟨p⟩⟩F J).** CONCEDE both ingredients:
  obligation-as-strategic-ability is **NATL\*** (Wooldridge & van der Hoek 2005) — a
  near-exact anticipation a reviewer WILL flag; CTL-as-one-player-ATL is textbook
  (Alur–Henzinger–Kupferman 2002). Keep only the inherited deltas: index the strategic
  MUST by a PARTY carrying ⪯_p (NATL\* indexes by a norm-system η), cooperative special
  case = the graph dominator/landmark. **C6 standalone is recombination — say so.**

## Recommended §6 framing (concede-then-claim)

1. Open: the thesis is a **UNIFICATION, not a new primitive** — "each ingredient has a
   precedent; our contribution is their composition and its jurisprudential reading."
2. Concede the graph construct to landmarks/LM-cut/Lengauer–Tarjan; the ordering layer
   to Kratzer/von Fintel–Iatridou/Condoravdi–Lauer/vBGL/Hansson; the duality to
   Anderson/Kowalski–Satoh; strategic-ability to NATL\*; CTL-in-ATL to Alur et al.; the
   force-gap to Pearl/Becker/Shavell with sign-readings to Cooter/Gneezy-Rustichini.
3. THEN claim the delta in descending strength: **C3 > C2 > C5 > C4.**
4. Two defensive disambiguations: graph goal-dominator vs Horty dominance; betterness
   ordering source vs LAMA "reasonable orderings."
5. Be candid C6 is recombination (multi-party escalation of C1/C2).

## Residual risks

- **No clean-novel claim exists** — the defense rests entirely on the composite being
  unanticipated. Foreground the integration or the paper is exposed.
- **Concede landmarks + NATL\* by name** or it reads as undisclosed prior art = highest
  rejection risk.
- The graph-dominator vs **Horty "dominance"** homonym is a live trap — one-line
  disambiguation required.
- **Shea-Blymyer & Abbas 2022** anticipates the C2 composition single-agent; only delta
  = dominator vs Bellman-optimality. If judged cosmetic, C2 collapses onto C3.
- MEDIUM confidence on C2/C3/C5: several primaries read via abstracts/paywall (vBGL
  full text, Bénabou–Tirole body, Broersen DEON 2006 reduction, von Fintel–Iatridou via
  Condoravdi–Lauer). Verify before relying on fine distinctions.
- **INTEGRITY — RESOLVED (2026-06-25):** "Superintelligence and Law" is REAL and now a
  CITED neighbour. Correct attribution: **Noam Kolt** (sole author), _Harvard J. of Law
  & Technology_ (forthcoming), draft 25 Feb 2026 — NOT "Kolt et al.", NOT Anthropic.
  Its Part III.A pairs Austin/Holmes(bad-man, instrumental) vs Hart(internal point of
  view, normative) and ties the internal POV to letter-vs-**spirit** — a C3/§1 framing
  neighbour (not a formal anticipation). See `notes/kolt-2026-superintelligence-and-law.md`.
- Citation metadata to double-check (Pearl UAI pages, Kowalski–Satoh JPL pages, DEON/
  ICAPS pagination). Un-exhausted adjacent lines to sweep: Horty stit/default branch;
  Boella–van der Torre NMAS games; Casali–Godo–Sierra graded DL; van der Hoek NTL.

## Must-cite list (verbatim from the workflow)

C1: Hoffmann/Porteous/Sebastia 2004 (JAIR 22:215-278); Porteous/Sebastia/Hoffmann 2001
(ECP-01); Helmert & Domshlak 2009 (ICAPS, LM-cut); Lengauer & Tarjan 1979 (TOPLAS
1(1):121-141). C2: Condoravdi & Lauer 2016 (S&P 9.8); von Fintel & Iatridou 2005 (MS);
Reisinger 2016 (PLSA 1.36); Katz/Portner/Rubinstein 2012 (SALT 22); van Benthem/Grossi/
Liu 2010/2014; Hansson 1969 (Noûs 3:373-398); Yan & He 2025 (arXiv:2505.06824);
Shea-Blymyer & Abbas 2022 (AIES); Horty 2001 (disambiguate); Richter & Westphal 2010
(LAMA, JAIR 39, distinguish). C3: Silk 2019 (OUP); **Kolt 2026 (Superintelligence and
Law, Harv. J.L. & Tech. forthcoming — framing neighbour)**; Holmes 1897 (10 Harv L Rev
457); Hart 1961/2012; Shapiro 2006 (75 Fordham L Rev 1157); McAdams 2015; Bénabou &
Tirole 2011 (NBER 17579); Casey 2017 (Amoral Machines); O'Keefe et al. 2025 (Law-
Following AI); Nerantzi & Sartor 2024 (Hard AI Crime). C4: Pearl 1993 (UAI); Becker 1968 (JPE 76(2)); Shavell 2003 (NBER
9698); Gneezy & Rustichini 2000 (JLS 29(1)); Cooter 1984 (Colum L Rev 84(6):1523);
Calegari et al. 2020 (CP-nets, arXiv:2003.10480); Dellunde/Godo et al. 2008 (graded DL,
DEON). C5: Anderson 1958; Kowalski & Satoh 2018 (JPL 47(4):579-609); Governatori 2015
(arXiv:1404.1685); Castro & Maibaum (dCTL). C6: Wooldridge & van der Hoek 2005 (NATL\*,
JAL 3(3-4):396-420); Alur/Henzinger/Kupferman 2002 (JACM 49(5)); Broersen 2006 (DEON,
LNAI 4048); Jamroga/van der Hoek/Wooldridge 2004 (DATL, the FOIL); Pauly 2002 (JLC
12(1)). Plus Broersen & Dignum (nC+, CTL-deontic neighbour to distinguish).
