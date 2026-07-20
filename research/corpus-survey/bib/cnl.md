## cnl — related work

*Note: this facet paper is co-authored with Adam Wyner. Five papers in this bundle are his own
prior work — Wyner & Peters (2011), Athan et al. (2013), Nazarenko, Lévy & Wyner (2016), Wyner et
al. (2017), and Dal Pont, Sartor, Wyner & Sartor (2025) — flagged inline below as **[Wyner]**.*

L4's CNL-workshop paper joins a tradition that has, since the 1990s, tried to keep formal legal
rules visibly tethered to their natural-language source: controlled-natural-language (CNL)
front ends, the LegalRuleML markup standard for deontic/defeasible norms, and — most recently —
LLM-assisted natural-language-to-logic pipelines. L4 shares this tradition's core aspiration
(isomorphism, traceability, lay-accessible explanation) but departs from it by delivering a
single statically-typed, executable language with native round-tripping and a reasoner API,
rather than an annotation format, a translation layer, or a Prolog back end sitting behind an NL
front door.

### LegalRuleML: the deontic/defeasible markup standard

Since its 2013 OASIS introduction, LegalRuleML has anchored a decade of JURIX/ICAIL work
extending, applying, and explaining a shared markup for deontic operators, defeasibility, and
source provenance. This is the "interchange format" pole L4 should be read against: LegalRuleML
captures norms as annotations layered on top of source text, useful for interoperability, but
generally paired with a separate external reasoner and no type discipline of its own.

- **[Wyner]** Athan, Boley, Governatori, Palmirani, Paschke & Wyner (ICAIL 2013) — introduces the
  LegalRuleML core: abstract syntax for deontic operators, defeasibility, and legal-source
  provenance. The field's markup standard and direct prior art for L4's own representation
  choices; L4 borrows the ambition (deontic + defeasible + source-linked) but compiles and
  type-checks rather than annotates.
- **[Wyner]** Nazarenko, Lévy & Wyner (JURIX 2016) — proposes a coarse/medium/fine-grained
  methodology for hand-moving legal text into LegalRuleML markup. Prior art on the "how do you
  actually get from text to rules" question that L4 answers differently: a checked compiler step
  rather than tiered manual annotation.
- **[Wyner]** Wyner, Gough, Lévy, Lynch & Nazarenko (JURIX 2017) — a pilot annotating Scottish
  legal instruments with LegalRuleML elements, evaluated against how well the result answers user
  queries. Useful evidence of how labor-intensive and corpus-specific manual LegalRuleML
  annotation remains — a data point for L4's gap.
- Palmirani, Martoni, Rossi, Bartolini & Robaldo (JURIX 2018) — PrOnto, a GDPR privacy ontology
  built on LegalRuleML and defeasible logic for compliance checking. The standard's most mature
  real-domain deployment, and a useful contrast to L4's compliance-wizard pilots, which generate
  end-user-facing reasoning rather than an ontology for internal audit.
- Gandon, Governatori & Villata (JURIX 2017) — recasts LegalRuleML normative requirements as
  Linked Data with an operational deontic-reasoning layer over Semantic Web infrastructure. Prior
  art for giving LegalRuleML executable teeth; L4's reasoner API pursues a similar
  operationalization goal without committing to RDF/OWL machinery.

### Isomorphism as a design principle for legal knowledge representation

A separate, older strand treats isomorphism to source text as a first-order constraint on legal
KR — not an implementation nicety but something that shapes burden of proof, explanations, and
procedure. This is the conceptual ancestor of L4's "isomorphic formalization" claim, and the CNL
paper should credit it explicitly rather than present isomorphism as an L4 invention.

- Bench-Capon & Gordon (ICAIL 2009) — reflecting on the Estrella project, shows that even a small
  fragment of German family law admits several different isomorphic representations, and that the
  choice matters for burden of proof and explanation. The foundational articulation of the
  isomorphism desideratum L4 inherits; L4's contribution is to make isomorphism checkable and
  round-trippable rather than a one-off manual design judgment.
- **[Wyner]** Wyner & Peters (JURIX 2011) — a linguistically-oriented, rule-based (as opposed to
  machine-learning) method for extracting conditional and deontic rules from regulatory text.
  Method-to-borrow for L4's front end: its rule-based, non-black-box extraction philosophy
  anticipates L4's insistence on traceable text-to-rule mapping.
- Winkels & den Haan (ICAIL 1995) — generates natural-language paraphrases back out of
  deep-structure legislative representations. Prior art for the *other* direction of L4's
  round-trip (formal-to-NL), decades before "isomorphic formalization" had a name.

### NL-to-logic pipelines: the PROLEG/NII lineage

A distinct, ongoing line out of Ken Satoh's group builds natural-language front ends onto PROLEG,
a Prolog-based legal reasoner, tackling the same "lawyers won't write Prolog" problem L4's surface
syntax addresses. Useful as method-to-borrow on NL-to-logic translation technique, but PROLEG
remains a reasoning backend behind a translation layer, not a language drafters read, write, and
maintain directly.

- Nguyen, Nishino, Fujita & Satoh (JURIX 2022) — an interactive NL interface translating input
  facts directly into PROLEG's native Prolog syntax. Prior art showing both the demand for
  exactly the kind of NL-legible surface L4 provides natively, and the residual translation error
  such interface layers still carry.
- Zin, Borges, Satoh & Fungwacharakorn (ICAIL 2025) — an LLM pipeline translating traffic rules
  into Logical English and then PROLOG, via in-context learning and fine-tuning. Corroborates the
  "Logical English as intermediate representation" pattern from outside Wyner's circle, suggesting
  convergent practice rather than one team's idiosyncrasy.

### LLM-era Logical English pipelines for autonomous compliance

The most recent cluster uses LLMs to bootstrap Logical English (Kowalski's CNL) or Prolog rule
sets for autonomous-vehicle traffic-law compliance, treating the LLM purely as a translation aid
ahead of a symbolic executable core — the same LLM-for-ingestion/logic-for-execution division of
labor L4 argues for.

- **[Wyner]** Dal Pont, Sartor, Wyner & Sartor (ICAIL 2025) — an LLM + Logical English pipeline
  turning Highway Code text into an executable, simulation-validated rule set for AV
  decision-making, with an explicit error-correction phase. The closest adjacent work in the
  bundle (Wyner is a co-author on both this and the CNL paper): it shows Logical English's
  viability as an LLM ingestion target, but stops at simulation validation rather than formal
  verification of the rule set itself — a gap L4's reasoner API is built to close.

### Must-cite anchors

- Athan, Boley, Governatori, Palmirani, Paschke & Wyner (ICAIL 2013) — the LegalRuleML standard
  itself; the field's reference point for deontic/defeasible legal markup.
- **[Wyner]** Wyner & Peters (JURIX 2011) — the rule-based rule-extraction lineage L4's front end
  continues.
- Bench-Capon & Gordon (ICAIL 2009) — origin of "isomorphism" as an explicit design constraint on
  legal KR.
- Palmirani, Martoni, Rossi, Bartolini & Robaldo (JURIX 2018) — LegalRuleML's most mature
  real-world (GDPR) deployment, for contrast with L4's own pilots.
- **[Wyner]** Nazarenko, Lévy & Wyner (JURIX 2016) — the tiered text-to-LegalRuleML methodology L4
  replaces with a compiler.
- **[Wyner]** Wyner, Gough, Lévy, Lynch & Nazarenko (JURIX 2017) — empirical evidence of manual
  LegalRuleML annotation's cost, motivating L4's automation claim.
- Winkels & den Haan (ICAIL 1995) — earliest formal-to-NL paraphrase generation in the bundle.
- Gandon, Governatori & Villata (JURIX 2017) — prior attempt to make LegalRuleML operationally
  executable.
- Nguyen, Nishino, Fujita & Satoh (JURIX 2022) — PROLEG's NL interface, the clearest non-L4
  comparator for "NL surface over a legal reasoner."
- Zin, Borges, Satoh & Fungwacharakorn (ICAIL 2025) — independent corroboration of the LLM +
  Logical English pattern.
- **[Wyner]** Dal Pont, Sartor, Wyner & Sartor (ICAIL 2025) — nearest-neighbor contemporary work,
  co-authored by this paper's own co-author.
- Ranta, Listenmaa, Soh & Wong (JURIX 2022) — L4's own direct predecessor pipeline; must be framed
  as lineage, not arm's-length citation.

### Supporting cites

- *Isomorphism / dialectics:* St-Vincent, Poulin & Bratley (ICAIL 1995) — meta-level dialectical
  framework preserving isomorphic representation under multiple interpretive viewpoints.
  Allen, Chung, Mowbray & Greenleaf (ICAIL 2001) — AustLII's Aide, an early quasi-NL KR close to
  statutory wording, usable by a predicate-calculus engine.
- *PROLEG/NII lineage:* Nguyen, Fungwacharakorn, Nishino & Satoh (JURIX 2022) — multi-step deep
  learning NL-to-logic translation. Zin, Nguyen, Satoh, Sugawara & Nishino (ICAIL 2023) —
  LegalCaseNER, an NER pipeline from case prose to PROLEG fact formulas.
- *LegalRuleML applications/tooling:* Governatori & Palmirani (ICAIL 2025) — judicial explanation
  via LegalRuleML-encoded Defeasible Deontic Logic. Libal (JURIX 2022) — LegAi, a wizard-guided
  annotation tool validating formal output against original text.
- *Explanation UX:* Zuurmond, Borg, van Kempen & Wieten (JURIX 2023) — human-centred,
  question-driven explanation for a real Dutch Tax/Customs rule-based system.

### Gap / L4's opening

None of this literature delivers isomorphism, execution, and explanation as one checked property
of a single artifact. LegalRuleML gives rich markup but no native execution or type discipline —
Palmirani et al. and Gandon et al. each need a separate reasoning engine bolted on. The PROLEG/NII
and 2025 LLM+Logical-English lines get closer to "executable," but the LLM sits purely in front of
the reasoning core as an ingestion aid, producing Prolog/Logical-English artifacts rather than a
typed language drafters maintain directly — and even the most adjacent work (Dal Pont et al.)
validates by simulation, not formal verification. The isomorphism literature itself (Bench-Capon &
Gordon; Winkels & den Haan) treats isomorphism as a manual drafting discipline to aspire to, not
something a compiler enforces or a round-trip test can check. L4's opening is to collapse these
into one pipeline: an isomorphic surface syntax that type-checks, executes, round-trips back to
readable prose with citations, and exposes a verifiable reasoning trace to an LLM tool-caller —
where prior work offers at most two of those four at once.
