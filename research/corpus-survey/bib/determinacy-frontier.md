## determinacy-frontier — related work

AI & Law has spent four decades circling the same fault line that L4's Cambridge CLS paper stakes out explicitly: the line between legal indeterminacy a formal system can *represent* and legal indeterminacy only a human — judge, drafter, or negotiating party — can *resolve*. Two adjacent traditions dominate the literature: a large one that treats open texture and statutory ambiguity as material for argumentation, to be adjudicated inside the formalism, and a much smaller one that treats formalization as a debugging instrument, flagging drafting defects without adjudicating them. L4's paper joins the second tradition, borrows vocabulary and case material from the first, and departs from both by making the detect/resolve boundary itself the object of study and by trying to price what gets lost when a formalization quietly resolves instead of flags (the "avoidable ambiguity tax").

### Open texture as the founding problem

The field's engagement with indeterminacy begins with Hart's "open texture," imported into AI & Law as the reason symbolic rule systems cannot mechanically decide hard cases without some interpretive supplement. Early ICAIL work asked whether that supplement should itself be formal — meta-rules, taxonomies of discretion — or left to unstated background knowledge, a question L4 answers operationally rather than philosophically: detect the case that falls outside a rule's clear extension, then stop and say so rather than guess.

- **Bench-Capon (1993, ICAIL)** tests whether neural nets can classify open-texture cases and whether rules can later be extracted from the trained net — a sub-symbolic route to resolution that L4 declines; L4 keeps classification symbolic and auditable rather than delegating it to a black box.
- **Sanders (1991, ICAIL)** built CHIRON to represent open-textured predicates in U.S. tax planning — an early system built to *carry* an open-textured term rather than close it, prior art for L4's insistence that some predicates should stay symbolically present, not silently resolved.
- **Schild & Herzog (1993, ICAIL)** add a meta-rule layer atop formalized legislation specifically to manage the "intrinsic vagueness" of legal rules — prior art for treating vagueness-handling as its own architectural layer above the base rules, close to how L4 separates rule logic from an ambiguity-detection pass.
- **Loui (1995, ICAIL)** revisits Hart's own account of defeasibility and ascription, grounding the field's working vocabulary of "defeasible" in the jurisprudence it came from — useful lineage for defining what "ambiguity" and "vagueness" mean before showing where formalization can and cannot dissolve them.

### Statutory interpretation as defeasible argumentation

A large, still-active JURIX/ICAIL programme — Sartor, Rotolo, Governatori, Walton, Macagno, and (in a long solo series) Araszkiewicz — treats indeterminate statutory language as material for argumentation schemes and defeasible logics: canons of interpretation become argument types that attack and defeat each other, and the "right" reading is whichever survives the dialectic. This is the tradition's dominant answer to what to do once ambiguity is found: argue it out inside the formalism. L4 draws its vocabulary of canons and defeat from this tradition but takes a different stance, treating the presence of live, un-defeated competing readings as the quantity to *report*, not resolve.

- **Sartor (1993, ICAIL)** is the tradition's founding move: a computational model of nonmonotonic, adversarial reasoning over norm sets that are themselves inconsistent or semantically indeterminate — licenses treating indeterminacy as an argumentation object rather than a defect to eliminate before modeling begins.
- **Rotolo, Governatori & Sartor (2015, ICAIL)** formalize interpretive canons as arguments within Defeasible Deontic Logic, giving concrete machinery for how "ought/may be interpreted as" claims get attacked and defended — the state of the art for *resolving* interpretation, against which L4's detect-only stance is a deliberate abstention.
- **Sartor, Walton, Macagno & Rotolo (2014, JURIX)** systematize the MacCormick-Summers and Tarello canon inventories into a single logical scheme — close to a taxonomy of "the ways law can be read," usable as a checklist for classifying the kinds of ambiguity L4's formalizations surface.
- **Zurek & Araszkiewicz (2013, ICAIL)** formalize teleological interpretation against a real decided case — prior art for one of the specific canons L4's worked examples will need to invoke when showing a formalization surfaces, rather than settles, a purposive reading.
- **Araszkiewicz (2013, JURIX)** is the field's own call for a systematic research program on statutory interpretation, anchoring a decade-long single-author series that has since tried to answer it.

### Judicial discretion as bounded indeterminacy

A newer, narrower thread (Dik & Markovich) treats judicial discretion not as ambiguity to be argued away but as a normatively *legitimate* space of choice that a deontic logic should delimit rather than collapse — the judge is licensed to choose among several defensible outcomes, and the formal system's job is to characterize that license's boundary, not pick a winner inside it.

- **Dik & Markovich (2024, JURIX)** extend deontic logic with "nuanced permissions" to model a judge's initial freedom and the obligations whose violation makes a discretionary decision wrong, worked through child-custody cases — directly adjacent to L4's frontier concept but aimed at discretion-as-license rather than drafting-ambiguity-as-defect; a useful contrast for sharpening what L4 means by "cannot itself resolve."
- **Dik (2025, JURIX)** and **Dik & Markovich (2025, ICAIL)** operationalize the same idea in Answer Set Programming, testing the internal consistency of a judge's stated reasoning and surfacing the implicit weights that would make a decision consistent — a method to borrow if L4 wants to show mechanically that a given resolution is *one of several* consistent readings, not the only one.

### Rules-as-code in practice: measuring interpretive divergence

A more applied, less logic-heavy literature asks what actually happens when real people encode real legislation: do independent coders converge on the same formal rule, and what predicts when they don't? This is the empirical mirror of L4's theoretical claim, and the closest existing evidence for an "avoidable ambiguity tax" — divergence traceable to the coding process or language, as distinct from the law's genuine indeterminacy.

- **Witt, Huggins, Governatori & Buckley (2021, ICAIL)** ran a first-of-its-kind experiment: multiple legally-trained coders independently converting Australian copyright legislation into machine-executable code, finding that pre-agreeing on key legal "atoms" sharply raises convergence — the strongest available evidence for the distinction between fixable (avoidable) and genuine (unavoidable) divergence that L4's tax metric wants to operationalize.
- **Godfrey (2025, ICAIL)** applies translation-theory "fidelity" models to the same choice points, showing the fidelity regime a coder is trained on shapes their interpretive choices — prior art for treating the coder's methodology, not just the statute's language, as a source of variance L4 should control for or disclose.
- **van Engers & Boekenoogen (2003, ICAIL)** describe the Dutch tax authority's POWER method for translating legislation into processes and code, reporting real anomalies it caught in draft legislation — an early, non-formal-logic precedent for the "formalization finds bugs" claim L4's paper is built around.
- **Surden, Genesereth & Logu (2007, ICAIL)** propose a "representational complexity" measure to identify which individual legal rules are amenable to simplified computational representation in the first place — the closest existing attempt to draw the frontier line itself rather than argue across it, a natural formal companion to L4's more empirical tax metric.

### Detecting drafting defects: ambiguity, conflict, and error as bugs

A small cluster treats the output of formalization as a debugging report rather than a dialectical resource — ambiguity, contradiction, and error in a normative text are defects to be located and characterized, not resolved by the tool. This sub-theme sits closest in spirit to L4's own pilot findings: the double-bind race condition found in a piece of secondary legislation, the payout-formula ambiguity found in an insurance policy.

- **Araszkiewicz, Francesconi & Zurek (2023, ICAIL)** compare the structure and semantic content of legal provisions to detect drafting errors from unintended overlap, explicitly separating the detection framework from the interpretive choice needed to read the compared provisions in the first place — the bundle's closest analogue to L4's own bug-finding claim.
- **Governatori & Rotolo (2023, ICAIL)** extend Defeasible Deontic Logic to distinguish ambiguity that must *propagate* to other norms from ambiguity that should be *blocked* and confined — vocabulary L4 can borrow directly for describing why one detected ambiguity infects downstream obligations while another stays local.
- **Fungwacharakorn & Satoh (2020, JURIX)** generalize "Legal Debugging" — culprit detection, exception invention, fact- and rule-based induction — for locating the rule responsible for a counterintuitive consequence — prior art for a detect-then-localize workflow, though it still asks a judge-oracle to supply the intended interpretation, exactly the resolve step L4 argues should stay with a human.
- **Azzopardi, Gatt & Pace (2016, JURIX)** build an action-based deontic logic that formally tolerates unknown subcontracts, letting reasoning proceed under acknowledged incompleteness rather than forcing premature closure — a method to borrow: L4's evaluator could adopt the same syntactic/semantic treatment of "unknown" terms instead of silently defaulting them.

### Neuro-symbolic and hybrid attempts to resolve, not just detect

A final, mostly recent cluster tries to have it both ways — pairing a symbolic, structured layer with a sub-symbolic or numeric one (fuzzy membership, LLM judgment, visual exploration) specifically to *close* the gap open texture leaves open, rather than report it. These are the papers L4 should engage most directly as contrast, since they represent the road not taken.

- **Pereira, Tettamanzi, Liao, Malerba, Rotolo & van der Torre (2017, ICAIL)** combine fuzzy logic with formal argumentation, letting graded categories stand in for vagueness that crisp open-texture predicates can't express — a genuine attempt at resolution-by-degree, contrasting with L4's binary detect/escalate stance.
- **Westermann (2025, ICAIL)** demonstrates DALLMA, pairing expert-system-style structured legal criteria with an LLM for the open-textured terms the expert system can't decide — the bundle's most direct engagement with the determinacy frontier as such, and the paper L4's introduction should position itself against most explicitly, since it proposes LLM judgment as exactly the resolution mechanism L4 withholds.
- **Xia, Zheng, Bowers & Ludäscher (2025, ICAIL)** built AF-XRAY to visualize and help resolve ambiguity in abstract argumentation frameworks, overlaying alternative two-valued solutions on an ambiguous three-valued grounded semantics — a visualization method L4's IDE tooling could borrow for surfacing *which* competing readings survive, even while declining to pick one.

### Must-cite anchors

- Sartor (1993, ICAIL) — founding computational model of reasoning over inconsistent/indeterminate norms.
- Bench-Capon (1993, ICAIL) — neural-net vs. symbolic classification of open texture; sharpest sub-symbolic contrast.
- Sanders (1991, ICAIL) — CHIRON, earliest "represent, don't resolve" open-texture system.
- Schild & Herzog (1993, ICAIL) — meta-rules as an architectural answer to vagueness.
- Rotolo, Governatori & Sartor (2015, ICAIL) — canons-as-arguments; the resolution road L4 declines to take.
- Sartor, Walton, Macagno & Rotolo (2014, JURIX) — taxonomy of interpretive argument types, useful as a classification checklist.
- Witt, Huggins, Governatori & Buckley (2021, ICAIL) — empirical coder-divergence study; closest evidence for the ambiguity tax.
- Surden, Genesereth & Logu (2007, ICAIL) — representational-complexity measure; formal companion to the frontier concept.
- Araszkiewicz, Francesconi & Zurek (2023, ICAIL) — legislative error detection; nearest analogue to L4's bug-finding claim.
- Governatori & Rotolo (2023, ICAIL) — ambiguity propagation vs. blocking; vocabulary to borrow.
- Azzopardi, Gatt & Pace (2016, JURIX) — formal tolerance of incompleteness; method to borrow for L4's evaluator.
- Westermann (2025, ICAIL) — DALLMA; the paper L4 should position itself against most directly.

### Supporting cites

**Open texture classics**
- Liebwald (2013, ICAIL) — surveys vagueness in legal drafting as both problem and opportunity for AI & Law.
- Schild & Zeleznikow (2005, ICAIL) — taxonomy of discretionary decision-making crossed with open texture.
- Gordon (1989, ICAIL) — issue-spotting by searching a space of candidate interpretations, ATMS-based.
- Allen & Saxon (1991, ICAIL) / Allen & Tury (2007, ICAIL) — MULTINT/NewMINT, enumerating all formal interpretations of an ambiguous provision (1,344, for the First Amendment) rather than choosing one.

**Statutory interpretation as argumentation**
- Araszkiewicz & Zurek (2015, JURIX) — comprehensive framework for the full complexity of statutory interpretation.
- Walton, Macagno & Sartor (2014, JURIX) — argumentation schemes tailored to contested statutory readings.
- Maranhão (2017, ICAIL) / Maranhão & Sartor (2019, ICAIL) — input/output-logic architectures modeling interpretation as theory revision toward a stable reading.
- Malerba, Rotolo & Governatori (2016, JURIX) — canons-as-meta-rules extended across legal systems (private international law).
- Governatori, Olivieri, Rotolo & Scannapieco (2012, JURIX) — restrictive interpretation via revision of counts-as rules.
- Araszkiewicz's solo series (2015 causation; 2022 canon-preference scheme; 2023 conceptual structures; 2024, 2025 case-frame models) — decade-long single-author programme formalizing successive pieces of interpretation doctrine.
- Araszkiewicz & Zurek (2017, JURIX) — value-balancing extension of the teleological-interpretation model.
- Grabmair & Ashley (2009, ICAIL) — critical-questioning process model for disambiguating a provision before formalization.
- Henderson & Bench-Capon (2017, ICAIL) — ontology-based contract interpretation per Lord Hoffmann's common-law rules.
- Mai, Le, Vuong, Nguyen, Stathis & Satoh (2025, ICAIL) — DeCoRA, context-aware resolution of conflicting legal definitions.
- Canavotto & Horty (2023, ICAIL) — precedential constraint over hierarchies of open-textured predicates.
- Rissland & Skalak (1989, ICAIL) — CABARET, hybrid case-based/rule-based statutory interpretation.
- Prakken (2012, JURIX) — ASPIC+ reconstruction of a contested scholarly opinion on a legislative proposal.

**Rules-as-code in practice**
- Burgemeestre, Hulstijn & Tan (2009, JURIX) — rule-based vs. principle-based regulatory reasoning styles (EU vs. US customs).
- Muthuri, Boella, Hulstijn, Capecchi & Humphreys (2017, ICAIL) — compliance patterns bridging value modeling and legal interpretation.
- Branting (2001, ICAIL) — pro se advisory systems, scoped to domains that don't require open-textured reasoning.
- Pethe, Rippey & Kalé (1989, ICAIL) — early expert system that explicitly hands discretion/ambiguity to the human judge.
- Prakken (2017, ICAIL) — evaluates autonomous-vehicle designs against exceptions and vagueness in Dutch traffic law.
- Poulin, Bratley, Frémont & Mackaay (1993, ICAIL) — legal expert system recasting interpreted statutory/case text into formal rules.
- van Doesburg & van Engers (2016, JURIX) — FLINT, a frame-based language for formal norm interpretation traceable to source text.

**Hybrid/neuro-symbolic**
- McCarty (2015, ICAIL) — grounds a Language for Legal Discourse in perceptual/manifold-learning semantics, aimed at legal "coherence."

### Gap / L4's opening

None of this literature separates, as a first-class deliverable, the act of *detecting* an indeterminate reading from the act of *adjudicating* it: the argumentation-scheme tradition builds machinery that resolves interpretive conflict inside the formalism, while the discretion and rules-as-code-fidelity threads either delimit a space of legitimate choice or measure divergence after the fact — none offers a language whose type-checker or evaluator can surface ambiguity at formalization time, mid-draft, before any dispute exists. Nor does anyone quantify what a formalization loses by silently picking a reading instead of flagging it; even the strongest empirical study here (Witt et al. 2021) reports divergence, not cost. L4's opening is to make detect≠resolve a language-level guarantee: a type-checked artifact that can prove a term is genuinely indeterminate under the source text, refuse to auto-resolve it, and report the live alternatives and their provenance — turning what this literature treats as either a dialectical opportunity or a post-hoc coding-methodology finding into a checkable property of the formalization itself.
