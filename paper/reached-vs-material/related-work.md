# Related work — Reached versus Material

All 22 references verified against primary or authoritative secondary sources on 2026-08-27
(session `call-graph`). Verification cautions that would otherwise bite at camera-ready time are
flagged inline. Organized by the literature each strand argues with.

## Causation in legal theory (what "material" has always meant)

- **R.W. Wright, "Causation in Tort Law", _California Law Review_ 73:1735 (1985).** The NESS test
  — necessary element of a sufficient set — is our M3, and is (nearly verbatim) membership in a
  prime implicant consistent with the instance. The paper's overdetermination cases are our F6.
- **H.L.A. Hart & T. Honoré, _Causation in the Law_, 2nd ed., Clarendon Press (1985).** The
  doctrinal backdrop; causally-relevant-condition analysis NESS sharpens.
- **_Wayne Tank and Pump Co Ltd v Employers' Liability Assurance Corporation Ltd_ [1974] QB 57
  (CA).** Concurrent proximate causes in insurance — causal selection in event traces is live
  doctrine, not philosophy. (Sometimes reported without the apostrophe in "Employers'"; decided
  1973, reported 1974.)

## Structural causality (the formal home of "minimal significant counterfactual")

- **J.Y. Halpern & J. Pearl, "Causes and Explanations: A Structural-Model Approach. Part I:
  Causes", _BJPS_ 56(4):843–887 (2005).** Actual cause with witnesses/contingencies — handles the
  preemption cases trace edit-distance alone cannot.
- **J.Y. Halpern, _Actual Causality_, MIT Press (2016).** The modified HP definition (his
  preferred form); our intervention-set parameter is HP's contingency machinery with doctrine
  choosing the allowed interventions.
- **H. Chockler & J.Y. Halpern, "Responsibility and Blame: A Structural-Model Approach", _JAIR_
  22:93–115 (2004).** Degree of responsibility 1/(k+1) — our M4, the continuous node shading.
- **D. Lewis, _Counterfactuals_ (1973).** Closest-possible-world semantics; our distance metric on
  traces operationalizes it, with admissibility as the legal twist. (Dual 1973 imprints: Harvard
  UP and Blackwell; cite one consistently.)

## Formal explainability (the algorithms)

- **R. Reiter, "A Theory of Diagnosis from First Principles", _AIJ_ 32:57–95 (1987).** The
  minimal-hitting-set duality everything below stands on.
- **A. Ignatiev, N. Narodytska & J. Marques-Silva, "Abduction-Based Explanations for Machine
  Learning Models", AAAI 2019.** AXps as minimal sufficient reasons.
- **A. Ignatiev, N. Narodytska, N. Asher & J. Marques-Silva, "From Contrastive to Abductive
  Explanations and Back Again", AIxIA 2020.** The AXp↔CXp hitting-set duality — one engine, both
  explanation directions. (CAUTION: Asher is the commonly-dropped co-author; the Springer LNCS
  volume appeared **2021** though the conference was Nov 2020 — cite accordingly.)
- **A. Darwiche & A. Hirth, "On the Reasons Behind Decisions", ECAI 2020, 712–720.** Sufficient
  and necessary reasons via prime implicants on tractable circuits; closest algorithmic cousin of
  our BDD route.
- **T. Miller, "Explanation in Artificial Intelligence: Insights from the Social Sciences",
  _AIJ_ 267:1–38 (2019).** People ask contrastive why-questions; the argument that the CXp side is
  the one end-users want.

## Argumentation theory (defeasibility, stability, dialectic)

- **P.M. Dung, "On the acceptability of arguments…", _AIJ_ 77:321–357 (1995).** Attack/acceptance
  semantics; our SUBJECT-TO defeat edges are an attack graph over rules.
- **A.J. García & G.R. Simari, "Defeasible Logic Programming: An Argumentative Approach", _TPLP_
  4(1–2):95–138 (2004).** Dialectical trees — the "reached, would have fired, was defeated" trace
  annotation shape.
- **X. Fan & F. Toni, "On Computing Explanations in Argumentation", AAAI 2015, 1496–1502.**
  Explanation as a first-class object over argument acceptance.
- **D. Odekerken, A. Borg & F. Bex, "Estimating Stability for Efficient Argument-Based Inquiry",
  COMMA 2020**, and **D. Odekerken, F. Bex, A. Borg & B. Testerink, "Approximating stability for
  applied argument-based inquiry", _Intelligent Systems with Applications_ 16 (2022).** Stability
  — can future information change the status? — is our prospective wizard mode extended to event
  sequences. (CAUTION: author orders differ between the two papers as shown; the Netherlands
  Police trade-fraud intake deployment claim belongs to the **2022 journal** paper. Antecedent
  method paper: B. Testerink, D. Odekerken & F. Bex, FQAS 2019.)
- **D. Walton, C. Reed & F. Macagno, _Argumentation Schemes_, CUP (2008).** Critical questions as
  hand-curated counterfactual probe templates — the discipline for predicates the formalism
  leaves open.
- **T. Bench-Capon, "Persuasion in Practical Argument Using Value-based Argumentation
  Frameworks", _J. Logic and Computation_ 13(3):429–448 (2003).** Where preference between
  defeating rules comes from; background for defeat-edge semantics.

## Verification and runtime monitoring (the event-trace side)

- **H. Chockler, J.Y. Halpern & O. Kupferman, "What Causes a System to Satisfy a Specification?",
  _ACM TOCL_ 9(3) (2008).** Causality lifted to model checking. (CAUTION: a 2010 TOCL erratum
  exists — cite it if leaning on the technical results rather than the framing.)
- **I. Beer, S. Ben-David, H. Chockler, A. Orni & R. Trefler, "Explaining Counterexamples Using
  Causality", CAV 2009; _FMSD_ 40(1):20–40 (2012).** The red-dot idiom: mark the causal points in
  a failing trace. Our frontier-crossing rendering is this, applied to breach.
- **A. Bauer, M. Leucker & C. Schallhart, "Runtime Verification for LTL and TLTL", _ACM TOSEM_
  20(4) (2011).** LTL₃'s three-valued verdict; the pivot is the step where the verdict leaves
  _inconclusive_ — our open/committed regions.
- **O. Kupferman & M.Y. Vardi, "Model Checking of Safety Properties", _FMSD_ 19(3):291–314
  (2001).** Bad prefixes: the prefix after which no extension satisfies — the committed region's
  formal name.

## What we claim is missing at the intersection

No work found that (a) types counterfactual explanations by **time axis** (valid / transaction /
rule-version) with a mapping to legal remediability, (b) treats counterfactual admissibility (the
intervention set) as an explicit **doctrinal parameter** of the explanation query, or (c) reports
implementation-experience evidence that production evaluation traces **actively mislead** about
materiality (our F5/F6). These are the paper's claimed gaps; a submission-time literature re-sweep
should re-verify all three, dated.
