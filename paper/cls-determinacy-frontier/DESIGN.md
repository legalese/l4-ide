# Computational Skeletons and the Determinacy Frontier

> **A facet of the paper series**, distinct from Bounded Deontics. Empirical /
> computational-legal-studies paper; **target venue: the _Cambridge Forum on AI: Law
> and Governance_ themed issue "Computational Legal Studies"** (guest eds. Hartung,
> Soh, Katz; rolling, deadline ~end of June 2027 per the CFP page — confirm). Drafted
> 2026-06-25. Keystone case: **Poh Yuan Nie v PP [2022] SGCA 74** (see the existing
> Poh Yuan Nie work — `essay.tsx`, branch `mengwong/poh-yuan-nie`, and the ICAIL
> paper). This note lives in the bounded-deontics worktree for continuity; it may move
> to its own branch later.

## Hook (the CFP line that prompted this)

> "How might computational methods be meaningfully developed and deployed to
> empirically test legal theories?"

We answer it concretely: **develop a method to extract the _computational skeleton_ of
a judgment, deploy it over an appellate corpus, and use the result to empirically map
the _determinacy frontier_ of adjudication** — the boundary where rule-deduction stops
and judicial value-choice begins. That tests, with a sharp instrument, the
formalism↔realism debate and Hart's core/penumbra, instead of arguing it.

## Core construct: the computational skeleton, and four strata

The **computational skeleton** of a holding = the minimal formal structure (an AND/OR
tree of conditions + defeasible rules with priorities + burden allocations + the
resolution moves) that, when executed on the found facts, reproduces the disposition. A
judgment "has a skeleton" _to the degree_ its ratio is recoverable as an executable
inference whose output matches the court's order.

A bottom-up filter sorts judgments into four strata:

1. **Skeletal / deductive** — disposition follows from extracted rules + found facts.
   (Formalism's home turf.)
2. **Defeasible-but-resolved** — needs exceptions/priorities, but they are stated or
   derivable; one admissible model. (Sartor/Prakken; still computational.)
3. **Overloaded / detect-but-don't-resolve** — the formal structure admits **>1
   admissible model with divergent dispositions**; the court closes the fork by a value
   choice, an interpretive canon, or a patch. _(Poh Yuan Nie: the overload-resolution /
   defeasible-coercion frame, s6A as the patch, the seam at ¶28.)_
4. **Open-textured / discretionary** — no skeleton entails the outcome; proportionality,
   standards, value-balancing. (Realism's home turf.)

## The spine: detect ≠ resolve

The novel, jurisprudentially-loaded contribution is **locating, at scale, the points
where adjudication transitions from deduction to decision** — where a formal model can
_detect_ a problem (an overload, a gap, a deontic double-bind) it cannot _resolve_
without a value choice. Most CLS/legal-NLP work predicts _outcomes_ or extracts
_citations_; this finds the **deduction→decision seam**, which requires actually
formalising the rule, not merely embedding the text. Stratum 3 is the target, and Poh
Yuan Nie is its hand-coded gold exemplar.

## Legal theory under test

- **Determinacy / formalism vs realism**: what fraction of appellate reasoning is
  rule-deductive (strata 1–2) vs choice-laden (strata 3–4)? We _measure_ the frontier.
- **Hart's open texture / core vs penumbra**: operationalise "easy" = skeleton entails;
  "hard" = unresolved fork or no skeleton. Test the core/penumbra distribution.
- **Defeasibility's prevalence** (Hart, Sartor, Prakken): how deep do exception layers go?
- We are **not** claiming law is computable; we are measuring _where it stops being so_.

## Sub-analysis: the avoidable-ambiguity tax

The determinacy frontier has a _second line inside it_: not all "hard" cases are hard for
the same reason. Distinguish three sources of interpretive dispute:

- **(A) Syntactic / lexical / constructional — AVOIDABLE.** Two sub-kinds.
  **(A1) _Structural / parse_** — the parse tree itself is contested: comma scope,
  "and/or", attachment, last-antecedent, which list-items a proviso governs, the
  structure of a long sentence (_Poh Yuan Nie_; _Oakhurst Dairy_).
  **(A2) _Functional / constructional_** — the parse is fixed but the _function_ of a
  construction is underspecified, e.g. an infinitive read as **purpose vs result**
  (_Chew v The Queen_). Both are curable by drafting — or by an isomorphic formalisation
  that _forces the choice at enactment_.
- **(B) Semantic / definitional — sometimes avoidable.** Meaning of a term fixable by a
  definition.
- **(C) Normative / open texture — IRREDUCIBLE.** Applying a value-laden standard
  ("reasonable", "dishonest", proportionate) to facts; Hart's penumbra; the vagueness
  Endicott (_Vagueness in Law_) argues is sometimes _valuable_. No formalism removes it
  (and none should).

**The question (Meng):** how much judicial and litigant effort goes on (A) — avoidable
drafting defects — rather than (C), the genuinely hard value questions courts are _for_?
A large (A)-share is a measurable **waste**: scarce adjudicative attention spent
re-parsing sentences a formal artefact would have disambiguated once, at drafting time.

**The Poh Yuan Nie signal.** The s415 judgment cites two prior cases that exist
essentially to have done the _parsing_ of the s415 sentence — prior litigation whose
ratio is a **construction of the sentence's structure**, not a normative principle. The
corpus marker is therefore detectable: a **construction-borrowing citation** ("following
[X], we read s N as [structural reading]") is a fingerprint of type-(A) litigation. So is
invocation of the **syntactic canons of construction** (last-antecedent rule, series-
qualifier canon, "and/or", scope), which exist _precisely because_ of avoidable ambiguity
(Solan, _The Language of Judges_; Scalia & Garner, _Reading Law_).

**Metric.** Per judgment, code each interpretive crux A/B/C and proxy the effort
(paragraphs spent, cases cited, whether a _whole prior case_ was needed just to fix the
parse). Corpus metric = the **(A)-share of interpretive labour** + the count of
construction-borrowing citations. External-validity check: type-(A) cruxes should
correlate with _subsequent amendments_ (the legislature quietly cleaning up the sentence).

**The L4 counterfactual + cross-facet link.** For a sampled type-(A) provision, show that
an isomorphic L4 formalisation _could not have left the ambiguity open_ — the parse must
be committed when the formal version is written (the asyndeton/inert + indentation
affordances of the CNL facet are exactly the tools that pin the structure). So **facet 3
measures the disease; facet 4 is the cure.** This reframes the rules-as-code case from
the fraught "replace judges" to "stop spending courts' scarce attention on parse-bugs so
they can spend it on the value questions only they can answer."

**Illustrations.**

- **(A1) structural-parse anchors:** (1) **Poh Yuan Nie** — the "prior cases existed only
  to parse the s415 sentence" signal (construction-borrowing citations); (2) _O'Connor v
  Oakhurst Dairy_ (1st Cir. 2017) — ~US\$5M overtime dispute on a missing serial comma;
  (3) **Rogers Communications v Aliant Telecom** (Canada, CRTC, July 2006) — the
  "million-dollar comma": the comma in "...successive five (5) year terms, unless and
  until terminated by one year prior notice..." made the termination right attach to the
  _whole_ clause (terminable anytime on 1yr notice) vs only at each term's end; ~CAD\$1M.
  **Killer detail for the tax:** the English ambiguity was re-fought via the contract's
  **French-language version** (different punctuation) + a 69-page linguist affidavit — the
  "fix" was another NL text, not a formalisation that would have pinned the attachment at
  drafting. (Source: Pinsent Masons Out-Law, "The case of the million-dollar comma.")
  (4) **Lockhart v United States, 577 U.S. 347 (2016)** (No. 14-8358; 6-2, Sotomayor J.)
  — **last-antecedent vs series-qualifier**: does "involving a minor or ward" in 18 U.S.C.
  §2252(b)(2) modify all three predicate offences or only the last ("abusive sexual
  conduct")? Sotomayor (majority) applied the **rule of the last antecedent** (only the
  last); Kagan (dissent, w/ Breyer) the **series-qualifier canon** (all three). A 10-year
  mandatory minimum turned on the parse — the canonical modern SCOTUS exhibit of a
  _which-items-does-the-qualifier-govern_ dispute, and a clean case of duelling syntactic
  canons (itself evidence the ambiguity was avoidable at drafting).
  _(Still TODO: a clean "and/or" case.)_
- **(A2) functional / bridge anchor:** **Chew v The Queen (1992) 173 CLR 626** (HCA, on
  s229(4) Companies (WA) Code), confirmed via **Australian OPC _Drafting Direction No.
  2.1_** ("Lessons from Chew v The Queen — distinguishing purpose from result"). _Not_ a
  parse ambiguity — the infinitive "to gain ... or to cause detriment ..." is read as
  **purpose** (5 JJ), **result** (1), or **both** (1). Its value = the **cross-facet
  bridge**: purpose-vs-result IS the bounded-deontics **goal-vs-outcome** distinction, and
  the OPC's own cures corroborate our machinery — ¶8 "indicate expressly whether a purpose
  or result is meant" = **goal-indexing**; ¶12 "the 'must not' form is inappropriate ...
  because the contravention is not complete until one of the specified results happens"
  (with the ¶11 resultative rewrite "contravenes ... if ... results in") = **the §4
  constitutive/regulative sorter**. A drafting authority independently stating our
  distinctions. **Also cite Chew in the Bounded Deontics paper §4 and §6.** (Source: OPC
  Drafting Direction 2.1, opc.gov.au; couldn't auto-fetch — egress-blocked; passage on
  file.)

## Method pipeline (generate → check → classify → measure)

The reason this is not "ask an LLM to summarise": the **left-brain check** (run the
skeleton) is the guardrail, and the _multiple-model_ test is what makes stratum 3
detectable. This is the ICAIL ingestion loop pointed at a corpus.

- **Corpus.** Singapore appellate judgments (SGCA, then SGHC) via eLitigation (openly
  available). Add a contrast corpus (trial-level / a tribunal) to control selection bias.
- **Stage 1 — Extract (right brain).** LLM emits a _paragraph-anchored_ structured
  object per judgment: issues, the candidate rule(s) with conditions (AND/OR),
  exceptions + priorities, the found facts, the burden allocations, and the disposition.
  Anchors (¶ citations) are mandatory.
- **Stage 2 — Check (left brain).** Compile the skeleton to **L4 / a defeasible reasoner
  / ASP** and test: does it entail the disposition from the found facts?
  - _entails, unique model_ → strata 1–2 (verified skeleton).
  - **>1 admissible model with divergent dispositions** → stratum 3 (overload /
    detect-not-resolve); the court's choice between models is the value move. (This is
    the ASP-stable-model / unsat-core / overload machinery from the bounded-deontics +
    PROLEG work, reused here as a _detector_.)
  - _no model entails it_ → stratum 4 (discretionary).
- **Stage 3 — Classify + featurise.** Stratum label + features: defeasibility depth,
  overload degree (# divergent admissible models), presence of a patch / call for
  legislative fix, dissent, reversal of the court below.
- **Stage 4 — Measure.** Skeletal-coverage %; the determinacy-frontier distribution
  across strata; **detect-≠-resolve frequency**; correlations (does stratum 3/4
  predict dissent, reversal, or a _later legislative amendment_ — a nice external
  validity check, since stratum-3 "patches" should correlate with subsequent
  statutory fixes).
- **Validation.** Human-coded gold set with inter-annotator agreement (NOT just the L4
  check); Poh Yuan Nie is the stratum-3 anchor; sample-audit the classifier.

## Risks to design around

1. **Selection bias** — reported/appellate cases are pre-filtered _for difficulty_, so
   the corpus over-represents strata 3–4. State it; it makes the corpus an adversarial
   test of formalism, but contrast with a lower-court/tribunal corpus.
2. **Ground truth** — "has a skeleton" is partly interpretive; need human labels +
   agreement, not one gold case.
3. **Absence of evidence** — "no skeleton found" ≠ "none exists." The entailment check
   makes a _positive_ finding strong and a _negative_ weak; report asymmetrically.
4. **Hallucinated skeletons** — guarded by the Stage-2 entailment check (a skeleton that
   doesn't run is rejected); but the LLM may also miss a real skeleton — sample-audit.

## Assets it composes

- The **L4 reasoner** (Stage-2 entailment / model enumeration).
- **Ladder diagrams** (AND/OR visualisation of each extracted skeleton — figures).
- The **burden-of-proof monad** (the defeasibility / burden layer of the skeleton).
- The **overload / unsat-core** machinery (the stratum-3 detector).
- The **Poh Yuan Nie essay** (`essay.tsx`) — the worked stratum-3 exemplar + write-up.

## Place in the series

- **Bounded Deontics → JURIX** — the _theory_ facet (the formal machinery).
- **This (determinacy frontier / detect≠resolve) → Cambridge CLS** — the _empirical_
  facet (the machinery deployed over a corpus to test a legal theory).
- **Poh Yuan Nie** is the keystone case that bridges both: the worked single-case
  formalisation (theory) _and_ the gold exemplar of the stratum-3 seam (empirical).

## Open questions / next steps

- Scope the corpus (how many SGCA judgments; which subject areas; time span).
- Pin the extraction schema and pilot Stage 1→2 on ~5 hand-picked cases (incl. Poh Yuan
  Nie) before scaling.
- Decide the headline legal-theory framing (determinacy frontier vs Hart core/penumbra
  vs detect≠resolve-as-its-own-claim) — likely lead with detect≠resolve, support with
  the determinacy distribution.
- Confirm the Cambridge CLS deadline (page says ~June 2027) and article type/length.
- Consider co-authors with empirical-CLS standing (Soh is an editor — conflict; but the
  Katz/Hartung/Soh crowd is the audience).
