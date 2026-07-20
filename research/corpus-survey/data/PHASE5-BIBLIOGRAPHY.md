# L4 corpus survey — annotated bibliography (Phase 5)

Facet-mapped, annotated related-work synthesized from the vetted **tight-core (327 papers)** of
the ICAIL/JURIX/DEON corpus. Pipeline: 1,817 indexed → 1,758 papers enriched → citation-graph
pre-rank → independent Sonnet abstract-filter → 717 kept → **327 tight-core** (core + confidence
≥ med + abstract) → per-facet synthesis. Annotations are original synthesis over abstracts, not
reproductions. Section sources live under `bib/<facet>.md`; working data in `shortlist-core.csv`.

## Facet → target paper

| Facet | Target paper | Tight-core papers |
|-------|--------------|------------------:|
| intro | ICAIL — introducing L4 | 132 |
| bounded-deontics | JURIX/DEON — Bounded Deontics | 180 |
| determinacy-frontier | Cambridge CLS — detect ≠ resolve | 54 |
| cnl | CNL workshop — syntactic affordances (w/ Wyner) | 19 |
| fm-in-law | ProLaLa — white-hat Bad Man | 54 |

(Papers can carry >1 facet, so the column sums exceed 327.)

## Contents
- [intro](#intro--related-work)
- [bounded-deontics](#bounded-deontics--related-work)
- [determinacy-frontier](#determinacy-frontier--related-work)
- [cnl](#cnl--related-work)
- [fm-in-law](#fm-in-law--related-work)

---

## intro — related work

L4's introductory paper joins a lineage that runs from the earliest ICAIL proceedings to today: the project of making legislation and contracts directly *executable* rather than merely searchable, classified, or drafted in prose. It departs from that lineage's usual shape — a bespoke logic-programming, ASP, or description-logic engine wedded to one statute or one contract form — by proposing a general-purpose, statically-typed functional language with an accompanying IDE, NL round-tripping, and automatic app generation, aimed at the whole pipeline from formalization to end-user deployment. The related work below spans the founding logic-programming wave, the isomorphism debate it provoked, the rules-as-code movement in government practice, the deontic/temporal contract-semantics tradition L4's own prior papers sit inside, and the current wave of LLM-assisted extraction and layperson-facing wizards.

### Executable law: the logic-programming founding wave

Starting in the mid-1980s, the dominant strategy for making statutes computable was direct translation into a Horn-clause program whose SLD resolution mirrored the deductive "if satisfied then entitled" structure of the rule. This work proved that large, real bodies of law — welfare benefit rules, tax codes, pension schemes — could be rendered as runnable programs, and it settled negation-as-failure as the default (if contested) reading of statutory "unless" clauses. L4 inherits the ambition of direct executable translation but replaces the untyped clause substrate with a typed functional core, trading some of Prolog's search flexibility for compile-time guarantees.

- **Bench-Capon, Robinson, Routen & Sergot (1987), ICAIL** — the field's most-cited demonstration that a whole statute (UK Supplementary Benefit) could be rendered in logic programming and executed; L4 treats this as proof that legislation-as-program scales, and aims to add static types where this project had none.
- **Sherman (1987), ICAIL** — an early Prolog model of Canada's Income Tax Act built explicitly to surface unintended tax consequences of transactions; direct prior art for L4's "run the model, find the loophole" pitch.
- **Kowalski (1989), ICAIL** — argues for negation-as-failure as the standard reading of statutory exceptions in logic-programmed law, a semantic commitment L4 must state its own position on when it moves to a typed setting.
- **Sergot, Kamble & Bajaj (1991), ICAIL** — Indian Civil Service pension rules encoded and run as a stand-alone program, an early government-scale rules-as-code case study anticipating L4's own public-sector pilots.

### Deep models and the shape of legal knowledge

A parallel strand asked not "can law be encoded" but "what structure should the encoding have," arguing that flat rule sets miss the layered, defeasible, meta-level character of legal reasoning — rules about rules, exceptions to exceptions, world knowledge separated from regulation knowledge. This debate matters to L4 because its type system and module structure amount to a fresh answer to this older question.

- **McCarty (1989), ICAIL** — argues for "deep conceptual models" of legal domains rather than shallow surface rules, launching the Language for Legal Discourse project; L4's insistence on structured types over bag-of-rules formalisms continues this line.
- **Bench-Capon (1989), ICAIL** — notes the gap between the theoretical case for deep models and deontic logic and the shallow rule-based systems that actually got built and used commercially; L4 bets that a properly designed language can close this gap without losing usability.
- **Breuker & den Haan (1991), ICAIL** — the classic argument for separating "world knowledge" from "regulation knowledge" in legal KR; L4's module boundaries implicitly take a position on this separation.
- **Gordon (1987), ICAIL** — Oblog-2, a hybrid terminological plus Horn-clause system built specifically for defeasible legal reasoning with exceptions; a design precursor to L4's typed defeasible constructs.

### Isomorphism and fidelity to the source text

If a formal model is to be trusted and maintained by lawyers, its structure should track the paragraph-and-clause structure of the text it formalizes — a demand usually called isomorphism. This literature shows both why isomorphism matters (traceability, explanation, maintainability) and why it is harder than it looks: the same statute admits multiple, non-equivalent isomorphic renderings. L4's round-tripping and citation-to-source features are a direct response to this body of work.

- **Bench-Capon & Gordon (2009), ICAIL** — using a fragment of German Family Law, shows that "isomorphic" formalizations of the same text are not unique and that the choice shifts burdens of proof and explanation; the clearest statement of the problem L4's isomorphic-formalization claim has to answer.
- **Allen & Saxon (1995, 1997), ICAIL** — the A-HOHFELD / LEGAL RELATIONS language, a Hohfeld-grounded representation designed for structural fidelity to legal text, with puzzles built to teach fluency in it; prior art for treating Hohfeldian relations as a formal substrate.
- **Witt, Huggins, Governatori & Buckley (2021), ICAIL** — an empirical study showing independent coders diverge when converting the same legislation into executable code, proposing a distinction between technical validation and "legal alignment"; a cautionary data point for any isomorphism claim, including L4's.
- **Godfrey (2025), ICAIL** — imports the translation-studies notion of "fidelity" to give legal coders an explicit framework for the interpretive choices that isomorphism otherwise glosses over.

### Rules-as-code in government practice

Since the 1990s several national administrations have run their own "translate legislation into executable form" programs, motivated by wanting faster, more consistent, anomaly-free implementation of new law rather than by KR theory as such. This is the direct institutional precedent for L4's public-sector pilot (the secondary-legislation wizard whose formal verification found a genuine race condition) and for its pitch to legislative drafting offices.

- **van Engers (2001) and van Engers & Boekenoogen (2003), ICAIL** — the Dutch Tax and Customs Administration's POWER programme, translating legislation into UML/OCL models with automatic code generation and anomaly detection; the closest institutional precedent for a legal-drafting-office deployment of a formal language.
- **Dayal, Harmer, Johnson & Mead (1993), ICAIL** — SoftLaw's commercial framing of legislation-as-knowledge-base for administrative applications, early evidence that rules-as-code could be sold, not only researched.
- **Greenleaf, Mowbray, King, Cant & Chung (1997), ICAIL** — AustLII's wysh/DataLex engine, a quasi-natural-language rule representation deployed live on the web alongside a free-access-to-law repository; precedent for coupling a rule engine to a public-facing legal information service.
- **Morris (2021), ICAIL, and Ali, Sileno & van Engers (2025), JURIX** — recent rules-as-code experiments (constraint answer-set programming; a criteria-based framework for assessing RaC languages, applied to the Dutch RegelSpraak) that give L4 contemporary comparators for its own design choices.
- **Mador-Haim & Hershowitz (2023), JURIX** — a production grammar (CIMPL/AMPL) actually running inside the US House of Representatives to execute bill amendments, evidence that rules-as-code tooling can reach real legislative production use.

### Deontic and temporal logic for contracts and norms

A separate but overlapping strand, concentrated in JURIX, works out formal semantics for obligation, permission, and prohibition in contracts specifically — as automata, as action/dynamic logics, with reparations and conditional permissions — largely independent of the legislation-focused tradition above. L4's own prior publications sit inside this strand, giving the intro paper a direct lineage to point to.

- **Governatori, Dumas, ter Hofstede & Oaks (2001), ICAIL** — an executable, defeasible-logic framework for automated legal negotiation between software-agent parties; precedent for treating negotiation itself as executable.
- **Prisacariu & Schneider (2009), ICAIL** — CL, an action-based deontic language combining obligation/permission/prohibition with dynamic logic for contracts; a direct stylistic ancestor of L4's regulative constructs.
- **Pace & Schapachnik's contract-automata programme (2011-2020), JURIX/ICAIL** — permissions, Hohfeld/Kanger rights, reparations, and conflict analysis all formalized as automata over a multi-party contract; the most sustained single research programme on formal contract semantics that L4 must position itself against.
- **Watt, Goodenough & Wong (2023), JURIX** — "Deontics and Time in Contracts," the L4 team's own prior paper giving an operational, Maude-executed semantics for norms and timing in L4 itself; the intro paper's direct predecessor, establishing that L4's deontic core already has a formal semantics.

### From text to formal model: NL pipelines, LLMs, and end-user wizards

The last decade brings two converging developments the intro paper needs to place L4 against: NLP/LLM pipelines that partially automate the natural-language-to-formal-rule step, and decision-support "wizards" that turn a formal model into a question-and-answer interface for laypeople. Both are exactly the two ends of L4's own pipeline — isomorphic ingestion and automatic web-app generation — so this is where L4 has to show it does more than combine two already-known ideas.

- **Wyner & Peters (2011), JURIX, and Wyner, Bos, Basile & Quaresma (2012), JURIX** — linguistically-oriented rule extraction and a state-of-the-art survey of automatic law-to-formal-representation translation, predating the LLM wave but defining the extraction problem L4 later tackles with LLM assistance.
- **Ranta, Listenmaa, Soh & Wong (2022), JURIX** — an end-to-end grammar-based pipeline from law text to logical formulas via an "assembly logic" intermediate representation, co-authored by L4's own PI; the most direct predecessor of L4's ingestion pipeline.
- **Janatian, Westermann, Tan, Savelka & Benyekhlef (2023), JURIX** — shows GPT-4 can auto-generate legal-expert-system decision pathways rated as good as manually built ones in blind comparison; clear evidence that LLM-assisted formalization is viable at the scale L4 needs.
- **Westermann & Benyekhlef (2023), ICAIL** — JusticeBot, a deployed hybrid rule/case-based wizard that has helped thousands of landlord-tenant litigants; the closest existing analogue to L4's citizen-facing web-wizard output, minus a formally-verified reasoner underneath.
- **Atkinson, Collenette, Bench-Capon & Dzehtsiarou (2021), ICAIL** — an executable ANGELIC model of ECHR case law driving a fact-collecting, explanation-giving interface for lawyers; a direct parallel to L4's auto-generated wizards with source citations.

### Must-cite anchors

- Bench-Capon, Robinson, Routen & Sergot (1987), ICAIL — flagship proof that a whole statute can be executable logic.
- McCarty (1989), ICAIL — founds the "deep conceptual model" tradition L4 explicitly continues.
- Sherman (1987), ICAIL — earliest "run the tax code to find the loophole" precedent, mirrors L4's own pilot anecdote.
- Kowalski (1989), ICAIL — settles negation-as-failure semantics for statutory exceptions, a position L4 must restate for a typed language.
- Bench-Capon & Gordon (2009), ICAIL — states the isomorphism problem itself; unavoidable for any paper claiming isomorphic formalization.
- Love & Genesereth (2005), ICAIL — names "Computational Law" as a research programme; L4's most direct conceptual ancestor and label.
- van Engers (2001), ICAIL — POWER, the closest institutional precedent for a legislative-drafting-office deployment.
- Greenleaf, Mowbray, King, Cant & Chung (1997), ICAIL — AustLII, earliest precedent for a rule engine coupled to a live public legal-information service.
- Pace & Schapachnik (2011-2015 series), JURIX/ICAIL — the most sustained formal contract-semantics research programme L4 must be positioned against.
- Prisacariu & Schneider (2009), ICAIL — CL, the closest prior deontic-action language design to L4's own constructs.
- Watt, Goodenough & Wong (2023), JURIX — L4's own prior paper; establishes L4 already has a formal semantics the intro paper builds on.
- Westermann & Benyekhlef (2023), ICAIL — JusticeBot, the nearest deployed analogue to L4's citizen-wizard output.

### Supporting cites

*Founding logic programming / deep models / KR debates:* Biagioli, Mariani & Tiscornia (1987, Esplex); Routen (1989, hierarchical structure of statutes); Schild & Herzog (1993, meta-rules); Yoshino (1995, legal meta-inference); Nitta et al. (1995, HELIC-II); Rissland & Skalak (1989, CABARET hybrid CBR/RBR); Poulin, Bratley, Frémont & Mackaay (1993, statutory interpretation recast as rules); Johnson & Mead (1991, legislative KBS for public administration); Simon & Gaes (1989, ASSYST sentencing guidelines); Van Nevel, Balfroid & Venken (1991, import/export expert system); Fisher (1997, tax-residence expert system); Lauritsen (1991, government benefits analysis); Tiscornia & Turchi (1997, functional model of legislative documents); Winkels & den Haan (1995, NL paraphrase generation from deep structure); Martinek & Cybulka (2005, event-calculus model of legal-provision dynamics); Satoh, Kubota, Nishigai & Takano (2009, Japanese presupposed-fact theory as logic programming); Leff (2001, Jess over legal XML); Kerrigan & Law (2003, XML compliance-assistance).

*Isomorphism / traceability:* Daskalopulu & Sergot (1995, constraint-driven contract assembly); St-Vincent, Poulin & Bratley (1995, dialectical reasoning preserving isomorphic representation); Agnoloni & Francesconi (2011, RDF/OWL of Hohfeldian relations between provisions).

*Rules-as-code / government practice:* Meessen (2023, Catala vs Regelspraak comparison); van Engers & van Doesburg (2015, Dutch immigration NL-to-executable translation); Batsakis, Baryannis, Governatori, Tachmazidis & Antoniou (2018, ASP/Argumentation/Defeasible-Logic comparison); Calegari, Contissa, Lagioia, Omicini & Sartor (2019, comparative survey of defeasible formalisms); Burgemeestre, Hulstijn & Tan (2009, rule- vs principle-based compliance); Palmirani & Governatori (2018, GDPR compliance via BPMN + Regorous); Palmirani, Governatori & Contissa (2010, 2011, temporal LKIF-rules); Li, Balke, De Vos, Padget & Satoh (2013), Araszkiewicz, Francesconi & Zurek (2023), and Gorín, Mera & Schapachnik (2010) (automated detection of conflicts/errors in drafts via ASP/ILP, semantic comparison, and LTL model checking); Doesburg & van Engers (2016, 2019, FLINT frame language for norm interpretation and potestative powers); Vanthienen & Robben (1993, decision-table legal KBS); Biagioli & Grossi (2008, description-logic legislative meta-drafting); van de Ven, Breuker, Hoekstra & Wortel (2008, HARNESS OWL-DL legal assessment); Förhécz, Korösi, Millinghoffer & Strausz (2009, Emerald OWL+rules); Islam & Governatori (2015, RuleOMS over relational DBs).

*Deontic / temporal contract logic:* Pace & Schapachnik (2012, 2013); Pace, Schapachnik & Schneider (2015); Azzopardi, Gatt & Pace (2016); Azzopardi, Pace & Schapachnik (2014, 2018); Pace (2020); Cambronero, Llana & Pace (2017) — fuller contract-automata / reparations / conditional-permission / timed-compliance cluster; Sileno, Boer & van Engers (2014, 2015, Petri-net models of Hohfeldian relations and law-implementation-behaviour bridging); Herzig, de Lima, Lorini & Troquard (2012, dynamic stit logic of legal agency); Dinesh, Joshi, Lee & Sokolsky (2008, trace-checking regulatory conformance); Rotolo & Smith (2021, PDL model of legal procedures); Minsky & Rozenshtein (1987, "System = Program + Users + Law"); Governatori, Lam, Rotolo, Villata & Gandon (2013, deontic license-composition heuristics); Liu, Sileno & van Engers (2020, Digital Enforceable Contracts); Henderson & Bench-Capon (2017, ontology-based contract interpretation per Lord Hoffmann); Carlson & Genesereth (2023, insurance-portfolio gap analysis via logic-program containment — directly parallel to L4's own insurance pilot); Baldoni, Giordano & Satoh (2019, 2020, renvoi in private international law); Buchanan et al. (2010, 2012, data-protection-by-design firewall systems).

*NL pipelines / LLMs / wizards:* Nazarenko, Lévy & Wyner (2016, LegalRuleML formalization methodology); Zin, Nguyen, Satoh, Sugawara & Nishino (2023), Nguyen, Nishino, Fujita & Satoh (2022), Zin, Borges, Satoh & Fungwacharakorn (2025), and Pont, Sartor, Wyner & Sartor (2025) (NER/LLM pipelines into PROLEG/PROLOG/Logical English); Billi, Pisano & Sanchi (2024), Billi, Parenti, Pisano & Sanchi (2025, ALEXChat), Nguyen, Goebel, Toni, Stathis & Satoh (2023, LawGiBa), and Kaczmarczyk, Libal & Smywinski-Pohl (2024) (GPT+Prolog/argumentation hybrids against hallucination); Steenhuis & Westermann (2024, LLM+rule intake for legal aid eligibility); Westermann (2025, DALLMA hybrid expert-system+LLM framework); Satoh, Takahashi & Kawasaki (2021) and Nishioka, Mori & Satoh (2022) (PROLEG-based issue-arranging and consumer-dispute systems); Branting (2001), Woodin (2001), Libal (2022), Zuurmond, Borg, van Kempen & Wieten (2023), Hanif et al. (2023), Ghosh & Abdulrab (2020), Adrian et al. (2024, DIREGA), Bouche-Pillon, Aussenac-Gilles, Chevalier & Zaraté (2024), and Matkovic, Markovic & Gostojic (2025) (further advisory/decision-support/explanation deployments across pro se litigation, AI Act classification, maritime liability, German register law, GDPR/LED, criminal offences); Grabmair & Ashley (2009, critical-questions disambiguation before formalization); Sasdelli & Steffes (2025, validity diagrams for conditional norms); Thompson, Padget & Satoh (2016, TropICAL DSL to ASP institutions); Laneve, Parenti & Sartor (2024, incompatible-clause detection in Stipula); Dong, van der Torre & Yu (2025, rights-first CTD model with agentic-AI act selection); Ecobichon, Carpentier, Doutre & Mailly (2025, prioritized default logic for exceptions); Prakken (2017, autonomous-vehicle traffic-law compliance case study).

### Gap / L4's opening

No system in this literature combines a general-purpose, statically-typed programming language — with its own IDE, NL transpiler, and automatic app generator — with isomorphic formalization and an audit-grade, LLM-callable reasoner, as one integrated pipeline. Each prior effort supplies one or two pieces: the founding wave built bespoke Prolog/ASP encodings for a single statute with no reusable language or type discipline; the deontic-logic programme (Pace & Schapachnik, Prisacariu & Schneider) built rigorous contract calculi with no legislative-drafting workflow or end-user surface; the LLM-hybrid systems (Janatian et al., JusticeBot, LawGiBa, ALEXChat) bolt extraction or explanation onto a system with no independent, type-checked formal semantics underneath. The isomorphism debate (Bench-Capon & Gordon 2009; Witt et al. 2021) shows the representation-choice problem is real and unresolved by fiat — L4's opening is to make that choice an explicit, type-checked, round-trippable language design rather than an artifact of a one-off encoding, and to pair it with a reasoner whose execution trace an LLM can cite directly, closing the audit-grade-explainability gap the hybrid systems above gesture at but do not fully deliver.


---

## bounded-deontics — related work

L4's Bounded Deontics paper joins a fifty-year tradition, centered on the DEON workshop and its ICAIL/JURIX satellites, that tries to make obligation, permission and prohibition behave as well-defined logical operators rather than as folk intuitions borrowed from natural language. That tradition is largely proof-theoretic and model-theoretic: its object is a logic, evaluated by which paradoxes it avoids. L4 departs from it by treating the "bounded" phenomena this literature keeps rediscovering — defeasible obligation, weak vs. strong permission, deadline discharge, contrary-to-duty structure — not as competing logics to choose among, but as a compile-time/runtime boundary inside a single typed, executable language. The 180 papers in this bundle are the raw material L4's paper must position itself against: mostly DEON and JURIX proceedings, with a dense sub-cluster from the Governatori–Rotolo–Sartor "defeasible deontic logic" program that is, in effect, the closest existing relative to what L4 is trying to build.

### Classical deontic logic and its paradoxes

The DEON community's central preoccupation for decades has been a family of paradoxes — Chisholm's contrary-to-duty (CTD) scenario, Ross's paradox, the good-Samaritan and gentle-murderer puzzles, deontic dilemmas — each exposing some way that standard deontic logic's clean axioms (obligation distributes over conjunction, permission is dual to obligation, etc.) break under realistic normative structure. This is the literature that motivates why a "bounded" treatment is needed at all: a naively unified deontic operator collapses the moment two obligations conflict or a primary duty is breached.

- **McNamara (1996, DEON)** argues that "must" and "ought" are not interchangeable and that treating them as one presupposes a false uniformity in deontic logic — a foundational reminder that L4's obligation/permission boundary needs more than one modal primitive.
- **Goble (2004, DEON)** modifies standard deontic logic so that deontic dilemmas (conflicting obligations) don't explode into triviality, prior art for any system, like L4, that must tolerate conflicting rules without collapsing.
- **Governatori (2015, ICAIL)**, "Thou shalt is not you will," constructs a new CTD/derived-permission paradox specifically to argue that temporal logic is *not* well suited to modeling real norms — this is a direct challenge to any deontic-as-LTL framing and L4's paper has to answer it, not just cite it.
- **Gabbay (2008, DEON)** offers reactive Kripke models for CTD obligations, reworking Carmo/Jones- and Prakken/Sergot-style examples — a representative technique for handling primary/secondary obligation pairs without ad hoc violation markers.
- **Meheus, Beirlaen & Van De Putte (2010, DEON)** use adaptive logic to block deontic explosion by contextually restricting aggregation — an alternative, non-defeasible route to the same conflict-tolerance problem defeasible logic solves differently.

### Defeasible deontic logic: the Governatori–Rotolo–Sartor program

This is the largest and most load-bearing cluster in the bundle, and functionally L4's nearest neighbor: a two-decade research program building a non-monotonic, rule-priority-based logic in which obligations, permissions and their exceptions are derived defeasibly, with explicit machinery for temporal validity, norm change, and ambiguity propagation. Where L4 compiles a typed functional language to an execution trace, this program builds a bespoke proof theory (and, in Regorous, an engine) for the same underlying intuitions about bounded, defeasible obligation.

- **Governatori, Rotolo & Sartor (2005, ICAIL)** is the foundational paper: a computationally-oriented non-monotonic multi-modal logic combining temporalised agency with temporalised normative positions in Defeasible Logic. This is the single closest prior-art paper to L4's temporal-deontic ambitions and should be cited as the lineage L4's execution semantics reinterprets operationally.
- **Governatori & Rotolo (2004, DEON)** derive obligation from the combination of agency, intention and commitment in the same defeasible framework — an early instance of "derived obligation" as a first-class concept, which is exactly what L4's bounded-deontics paper is trying to formalize computationally.
- **Governatori, Rotolo, Riveret, Palmirani & Sartor (2007, ICAIL)** extend the logic with variants of Temporal Defeasible Logic distinguishing norm modifications whose conclusions persist from those that get blocked — directly relevant to how L4 must decide what survives a rule update.
- **Governatori, Rotolo & Calardo (2012, DEON)** supply possible-world semantics for Defeasible Deontic Logic, addressing the standard complaint that defeasible logics are "merely" proof-theoretic — a methodological question L4's own semantics (Maude-executed, trace-generating) answers by different means.
- **Governatori, Olivieri, Rotolo & Scannapieco (2013, ICAIL)**, "Legal contractions," model rule removal, exception-addition and priority change as AGM-style theory contraction — the clearest existing treatment of *legal change as a first-class operation* on a rule base, a problem L4 must eventually confront for statute amendment.
- **Governatori & Rotolo (2023, ICAIL)** on deontic ambiguities, and **Governatori, Olivieri, Rotolo & Scannapieco (2011, JURIX)** on three concepts of defeasible permission, extend the same program to ambiguity propagation/blocking and to permission as exception-to-obligation — both squarely inside the "permission/obligation boundary" that gives Bounded Deontics its title.

### Permission theory: weak, strong, free-choice and derived

A second thread, overlapping the first but conceptually distinct, asks what permission *means* rather than how to compute it defeasibly: is permission the mere absence of prohibition (weak/negative), an explicit grant (strong/positive), or actually more fundamental than obligation (obligation as "weakest permission")? This bears directly on where L4 draws its compile-time/runtime line, since "permitted because not (yet) forbidden" is a very different design commitment from "permitted because affirmatively licensed."

- **Boella & van der Torre (2003, ICAIL)** formalize the weak/strong permission distinction in input/output logic and show that strong permissions can dynamically add exceptions to obligations — foundational vocabulary for any system, including L4, that needs both senses of "permitted."
- **Roy, Anglberger & Gratzl (2012, DEON)** invert the usual dependency, defining obligation as the weakest permission consistent with everything else an agent may do — a genuinely contrasting foundational stance that L4's paper should note as an alternative it does not adopt, and explain why.
- **Stolpe (2010, DEON)** repairs a triviality result in derogation-based theories of positive permission, refining the technical machinery behind "permission as removal of prohibition."
- **Anglberger, Dong & Roy (2014, DEON)** prove that the "open reading" of permission (every execution of a permitted action must be normatively OK) entails Free Choice Permission — a technical result L4 will need to either respect or explicitly decline in its own permission semantics.

### Institutional facts, Hohfeld and counts-as

A separate lineage, running from Hohfeld through Lindahl/Odelstad to the "counts-as" modal-logic tradition, treats legal concepts (ownership, authority, rights) as intermediate structures joining brute facts to normative consequences, rather than as deontic operators directly on actions. This matters to L4 because contracts and legislation are full of constitutive, not just regulative, provisions ("X counts as Y"), and a bounded-deontics account that only handles obligation/permission/prohibition will miss half the corpus.

- **Herrestad & Krogh (1995, ICAIL)** give a Hohfeldian logical analysis of directed obligation, prohibition and permission as relations between a bearer and a counterpart — the classic formal starting point for any bearer/counterparty-indexed obligation, which is exactly how L4 represents deontic actions.
- **Grossi, Meyer & Dignum (2006, DEON)**, and their companion 2005 ICAIL paper, disentangle the classificatory and constitutive readings of "counts-as" using modal logic — the standard reference for treating institutional facts as a phenomenon distinct from, but composable with, deontic obligation.
- **Lindahl & Odelstad (2006/2008, DEON)** formalize "joining systems" that chain legal grounds to legal consequences (contract → purchase → ownership → power) algebraically — a structural account of derived normative concepts that complements defeasible-logic derivation with an explicit compositional algebra.

### Temporal and action-based deontic logic: deadlines, STIT, discharge

A fourth thread pushes deontic logic toward branching-time and action semantics specifically to handle deadlines, discharge of obligation over time, and the interaction between "ought-to-do" and "ought-to-be." This is the DEON-workshop literature closest in subject matter to L4's actual runtime — obligations that must be discharged by a deadline, in a system with concurrent agents and branching futures — even though none of it compiles to an executable language.

- **Broersen, Dignum, Dignum & Meyer (2004, DEON)** define a dyadic deadline-obligation operator with branching-time (CTL) semantics — the direct prior art for L4's REPARATION/deadline constructs, and a paper any bounded-deontics treatment of deadlines must cite.
- **Sergot & Craven (2006, DEON)** add a deontic component to the action language *nC+*, specifying permitted states and transitions directly rather than layering deontic operators onto a separate ontic logic — a "operational semantics first" methodology close in spirit to L4's own approach.
- **Horty (1996, DEON)** proposes a new ought-to-do operator on top of Belnap/Perloff STIT theory, the foundational move that lets later work (Broersen's ATL reduction, Herzig et al.'s dynamic logic) talk about what an *agent* ought to do rather than what ought to *be the case*.
- **Brunel, Bodeveix & Filali (2006, DEON)** combine state and event temporal formalisms with an explicit deadline operator, a technically close cousin of L4's own event/time model.

### Applied computational deontics: standards, compliance checking and contract automata

A more applied strand — much of it "method-to-borrow" or "example" in this bundle rather than pure logic — builds working tools: markup standards for deontic legal content, compliance-checking engines, model checkers for deontic/epistemic properties, and automata-based contract formalisms with reparation clauses. This is the closest thing in the literature to "legal tech that runs," and is the most direct competitive set for L4's own tooling claims.

- **Athan, Boley, Governatori, Palmirani, Paschke & Wyner (2013, ICAIL)**, OASIS LegalRuleML, defines a shared markup core for legal sources, defeasibility, time and deontic operators — the standards-track alternative to a full programming language, and a natural point of comparison/interoperability for L4.
- **Palmirani & Governatori (2018, JURIX)** and **Palmirani, Martoni, Rossi, Bartolini & Robaldo (2018, JURIX)**, the PrOnto/Regorous GDPR compliance work, show defeasible-logic-based compliance checking applied to a live, high-stakes regulation — a proof of applied relevance L4 can match with its own pilot deployments.
- **Governatori & Shek (2013, ICAIL)**, Regorous, packages compliance-by-design defeasible-logic checking as an actual business-process compliance tool — the closest thing to a shipped product in this whole bundle, and worth citing as evidence that the underlying logic *can* be operationalized, just not (yet) as a general-purpose language.
- **Raimondi & Lomuscio (2004, DEON)** verify deontic and epistemic properties of multi-agent systems via OBDD-based model checking — prior art for treating deontic compliance as a model-checking problem, methodologically adjacent to L4's own verification ambitions.
- **Pace & Schapachnik's** contract-automata line (2011, 2012, JURIX), together with **Azzopardi, Pace & Schapachnik (2014/2018, JURIX)**, formalize multi-party permissions, Hohfeldian rights, and reparations as automata rather than as pure logic formulas, and extend to real-time monitoring of smart contracts — the nearest thing here to L4's own "contract as executable specification" framing, just built on automata rather than a typed language.
- **Watt, Goodenough & Wong (2023, JURIX)**, "Deontics and Time in Contracts: An Executable Semantics for the L4 DSL," is L4's own immediate predecessor: an operational, state-and-transition semantics for deontics and time in L4, implemented in Maude. The Bounded Deontics paper is a direct continuation of this line and should cite it as the paper it extends, not merely as related work.

### Must-cite anchors

- **Governatori, Rotolo & Sartor (2005, ICAIL)** — the foundational temporalised-defeasible-deontic-logic paper; the closest prior-art lineage to L4's own temporal-deontic semantics.
- **Broersen, Dignum, Dignum & Meyer (2004, DEON)** — the standard formal treatment of deadline obligations, directly relevant to L4's REPARATION/deadline constructs.
- **Boella & van der Torre (2003, ICAIL)** — the canonical weak/strong permission distinction that any obligation/permission boundary account must engage.
- **Governatori (2015, ICAIL)**, "Thou shalt is not you will" — the strongest existing objection to modeling norms in temporal logic; L4's paper must answer it directly.
- **McNamara (1996, DEON)** — foundational must/ought distinction underlying the whole idea of "bounded" deontic notions.
- **Athan, Boley, Governatori, Palmirani, Paschke & Wyner (2013, ICAIL)**, OASIS LegalRuleML — the standards-based rival representation for deontic legal content.
- **Watt, Goodenough & Wong (2023, JURIX)** — L4's own direct predecessor paper; the Bounded Deontics paper extends this work.
- **Herrestad & Krogh (1995, ICAIL)** — foundational Hohfeldian bearer/counterparty account of directed obligation.
- **Governatori, Olivieri, Rotolo & Scannapieco (2013, ICAIL)**, "Legal contractions" — the clearest existing account of legal/rule change as a formal operation.
- **Palmirani & Governatori (2018, JURIX)** — the leading applied benchmark (GDPR) for defeasible-logic compliance checking.
- **Sergot & Craven (2006, DEON)** — action-logic-first deontic semantics, methodologically close to L4's operational approach.
- **Roy, Anglberger & Gratzl (2012, DEON)** — the "obligation as weakest permission" alternative foundational stance L4 should position itself against.

### Supporting cites

*Classical paradoxes / CTD:* Croix & Thomason (2014) on Chisholm's paradox and conditional oughts; Smith (1993) on violability vs. defeasibility; Kuijer (2012) showing sanction semantics cannot faithfully represent CTD obligations; Gabbay (2012) on temporal deontic logic for the generalised Chisholm set; Parent & van der Torre (2017) on the pragmatic oddity; Governatori & Rotolo (2019a) computational model of pragmatic oddity; Hansen (2004) on conflicting imperatives in dyadic deontic logic; Tan & van der Torre (1996) on preference-ordering semantics underlying CTD; Calardo, Governatori & Rotolo (2014) preference-based CTD semantics; Gabbay, Robaldo, Sun, van der Torre & Baniasadi (2014) on the miners scenario.

*Defeasible/derived obligation (Governatori school and adjacent):* Artosi, Governatori & Sartor (1996) on computational deontic defeasibility; Rotolo (2010) on retroactive legal change; Rotolo, Governatori & Sartor (2015) on defeasible reasoning in legal interpretation; Governatori & Rotolo (2008) on abrogation/annulment as theory revision; Cristani, Olivieri & Rotolo (2017) on operators for temporary-norm change; Broersen, Gabbay & van der Torre (2012) discussion paper on norm change; Governatori & Mullins (2019) on deontic closure and conflict; Governatori, Olivieri, Rotolo & Cristani (2022) on stable normative explanations; Governatori & Palmirani (2025) on legal explanation via LegalRuleML; Royakkers & Dignum (1996) on priority-based defeasible legal reasoning; Nitta et al. (1995), HELIC-II, an early logic-programming legal reasoner with defeasible priority; Sartor (1991) on the structure of norm conditions; Loui (1995) on Hart's theory of defeasibility; Calegari, Contissa, Lagioia, Omicini & Sartor (2019) comparative survey of DL/ASP/ASPIC+ for legal reasoning; Ecobichon, Carpentier, Doutre & Mailly (2025) on a prioritized-default-logic tool for unexpected exceptions.

*Permission theory:* Boella & van der Torre (2005) on permission vs. authorization; Governatori & Rotolo (2020) on Free Choice Permission in DDL; Governatori, Olivieri, Rotolo & Scannapieco (2011) on three concepts of defeasible permission; Kaci & van der Torre (2006) on non-monotonic DSDL3 permissions; Ciabattoni, Parent & Sartor (2021, 2023) on a Kelsenian deontic logic and Kelsenian strong permission; Dik & Markovich (2024, 2025) on nuanced permissions and ASP models of judicial discretion; Governatori & Rotolo (2024, 2025) and Governatori & Rotolo (2025), "Judicial Permission," on weak permission requiring judicial/dialogue-game determination.

*Institutional facts / Hohfeld / counts-as / power:* Boella, Favali & Lesmo (2001) action-based ontology of legal relations; Boella & van der Torre (2006) logical architecture of a normative system; Boella & van der Torre (2006a) delegation of power; Pacheco & Santos (2004) delegation in role-based organizations; Pace & Schapachnik (2011, 2012) permissions/rights in contracts; Doesburg & van Engers (2019) deontic vs. potestative norms (FLINT); Xu & Ju (2023) multi-agent logic of duties and powers; Markovich (2015) correlativity and the state in legal relations; Agnoloni & Francesconi (2011) RDF/OWL Hohfeldian relations; Peters & Wyner (2015) extracting Hohfeldian relations from text; Pascucci & Sileno (2021) computability of diagrammatic (Aristotelian/Hohfeldian) theories; Sileno, Boer & van Engers (2015, 2019) bridging law/implementation/behaviour and action-causation-power theory; Allen (1996) refining Hohfeld via stit-like agency; Markovich & Roy (2021) formal analysis of a cause-of-action bill; Sasdelli & Steffes (2025) validity diagrams; Hanauer, Novotná & Pascucci (2023) Aristotelian-diagram reasoning (GDPR case).

*Temporal / action / STIT deontic logic:* Broersen (2008) obligation-to-do vs. knowingly-doing (STIT); Broersen (2006a) "Acting with an End in Sight"; Brown (1996, 2006, 2008) diachronic/branching-time deontic logic of dischargeable obligations and actions-as-events; Castro & Maibaum (2008) tableaux for deontic action logic; Kulicki & Trypuz (2012) sequential composition of actions; Trypuz & Kulicki (2010, 2014) Boolean-algebra deontic action logics; Jamroga, van der Hoek & Wooldridge (2004) obligations and abilities via ATL; French, McCabe-Dansted & Reynolds (2010) RoCTL* axiomatization; Lomuscio & Wozna (2006) axiomatization of deontic interpreted systems; Herzig, de Lima, Lorini & Troquard (2012) dynamic logic of agency for legal actions; Belnap (2008) norms in branching space-times; Åqvist (2004) combinations of tense and deontic modality; Torre & Tan (1997) diagnostic vs. decision-theoretic normative reasoning; Torre, Hulstijn, Dastani & Broersen (2004) specifying multiagent organizations; Smith, Rotolo & Sartor (2010) representations of time in normative MAS; Marra (2014) dynamic semantics of necessity modals; Wyner (2004, 2006) stative obligations and CTD via sequences; Demolombe & Herzig (2004) obligation change and the frame problem; Kooi & Tamminga (2006) conflicting obligations with utilities; Grossi, Dignum, Royakkers & Meyer (2004) collective obligations and blame; Cholvy, Cuppens & Saurel (1997) and Cholvy & Cuppens (1995) formalizing responsibility and role-based conflict resolution; Lorini & Sartor (2015) influence-based responsibility; Halpern & Friedenberg (2025) causal-model definition of intent; Bench-Capon (1989, 2014) deep models and transition-system analysis of norms; Bench-Capon & Modgil (2016) value-based norm violation; Castelfranchi & Tummolini (2003) deontic nature of social conventions; Jones (1987, 2004) permission/obligation relationship and normative-informational positions; Turrini (2012) agreements as norms; Torre (2010) deontic redundancy; Dellunde & Godo (2008) graded/fuzzy deontic modalities; Straßer & Arieli (2014) sequent-based argumentation for normative reasoning; Straßer & Beirlaen (2012) Andersonian logic with contextualized sanctions; Grossi (2008) Anderson's reduction unified with counts-as; Parent (2010) input/output logic, CTD and moral particularism; Parent & van der Torre (2014) I/O logics without weakening; Sun & van der Torre (2014) combining constitutive and regulative norms in I/O logic; Gonçalves & Alferes (2012) embedding I/O logic in ASP; Robaldo (2021) reified I/O logic compliance via SHACL; Alchourrón & Martino (1989) Jørgensen's dilemma.

*Applied / compliance / smart contracts / conflict detection:* Gandon, Governatori & Villata (2017) normative requirements as linked data; Governatori, Lam, Rotolo, Villata & Gandon (2013) and Rotolo, Villata & Gandon (2013) license-composition heuristics and semantics; Francesconi & Governatori (2019) OWL2-based compliance; Palmirani, Governatori & Contissa (2010, 2011) temporal dimensions in LKIF-rules; Tamargo, Martínez, Rotolo & Governatori (2017) temporalised belief revision in law; Giordano, Martelli & Dupré (2013) deontic temporal ASP + bounded model checking; Colombo Tosatto, Governatori & Kelsen (2014) detecting deontic conflicts dynamically; Li, Balke, De Vos, Padget & Satoh (2013) conflict detection across interacting legal systems (privacy law); Pace (2020) contract conflicts with environmental constraints; Prisacariu & Schneider (2009) the *CL* contract-specification language; Pace, Schapachnik & Schneider (2015) conditional permissions in contracts; Azzopardi, Gatt & Pace (2016) reasoning about partial contracts; Cambronero, Llana & Pace (2017) timed-contract compliance under timing uncertainty; Chircop, Pace & Schneider (2022) automata for real-time normative documents; Kharraz, Leucker & Schneider (2021) timed dyadic deontic logic; Kharraz, Schneider & Leucker (2024) SMT-based conflicts in metric timed normative logic; Azzopardi & Pace (2024) conflict analysis for timed contract automata; Liu, Sileno & van Engers (2020) Digital Enforceable Contracts; Bhuiyan, Governatori, Bond, Demmel, Islam & Rakotonirainy (2020) defeasible deontic encoding of AV traffic rules; Zurek, Mohajeriparizi, Kwik & van Engers (2022) IHL compliance for autonomous devices; Sartor, Governatori, Pisano, Rotolo & Wyner (2025) defeasible deontic ASP integrated with planning; Neufeld, Ciabattoni & Tulcan (2024) restraining bolts for norm-compliant RL agents; Servantez et al. (2023) extracting Obligation Logic Graphs from NL contracts; Dal Pont, Galli, Sartor & Contissa (2025) LLM extraction of GDPR/DSA/AI-Act obligations; Lawniczak & Benzmüller (2025) HOL/Isabelle formalization of AI-Act modalities; Ferrigno, Billi, Yousefi & Rotolo (2025) DLRisk for AI-Act rights balancing; van Berkel, Markovich, Straßer & van der Torre (2023) conflict-of-laws argumentation; van der Hoek (2010) CTL-based normative-system games; Kimbrough (2001) disquotation theory for propositional attitudes; Brown (2004) obligation arising from contracts/negotiation; Carmo (2006) organizational obligation via roles and counts-as; Santos & Pacheco (2003) tableaux-automated institutional-agent reasoning; Abraham, Gabbay & Schild (2010) deontic logic of Talmudic law; Rotolo, Di Florio & Governatori (2025) rule-based deontic case-based reasoning for validating AI judicial predictions.

### Gap / L4's opening

Almost none of this literature produces a *language*: it produces logics — proof systems, model-theoretic semantics, or at best a bespoke reasoner (Regorous, SPINdle, a Maude encoding) built to answer one paper's example. The defeasible-deontic-logic program gets closest to L4's substantive claims about derived obligation and the permission boundary, but stops at the logic; it does not offer a type system that statically distinguishes what is decidable at compile time from what depends on runtime facts, nor does it generate human-readable, round-tripped natural-language explanation and an LLM-facing audit trace from the same artifact that is executed. The applied strand (LegalRuleML, Regorous, GDPR checkers, contract automata) shows these ideas can be operationalized, but as narrow compliance tools rather than general-purpose executable specifications that a non-lawyer could run, test, and extend. L4's opening is to reframe "bounded deontics" itself: not as a choice between competing deontic logics, each with its own paradox-avoidance profile, but as a structural boundary a programming language's type system can enforce and expose — turning fifty years of paradox-hunting into a design constraint on a compiler.


---

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


---

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


---

## fm-in-law — related work

L4's ProLaLa contribution — treating formal verification as a search for loopholes, exactly as a security team searches for exploits — joins a three-decade AI & Law tradition of applying model checking, deontic/temporal logics, and logic-programming reasoners to statutes, regulations, and contracts. That tradition has repeatedly demonstrated the *technique* (model-check a normative text, find a conflict) on hand-built formal models constructed by logicians; L4's departure is to make the formal model *be* the drafting artifact itself, so that verification is a by-product of authoring rather than a separate translation exercise performed after the fact.

### Model checking and temporal/modal logics for verifying normative systems

The most direct technical ancestors of "verification finds the loophole" are systems that borrowed off-the-shelf model checkers and modal logics wholesale from computer science and pointed them at legal or normative texts. This sub-theme establishes that the *machinery* for finding contradictions and race conditions in norms has existed for two decades; L4's contribution is closing the gap between the checker's input language and the lawyer's drafting language.

- **Gorín, Mera & Schapachnik (JURIX 2010)** built FormaLex, which feeds legislative drafts to off-the-shelf LTL model checkers on the strength of the analogy between regulations and software specifications — the most direct precedent for L4's own "formalize legislation, then model-check it" pipeline.
- **Faciano et al. (ICAIL 2017)** report the engineering needed to scale FormaLex to a real statute (the Argentine consumer-protection act), evidence that state-space blowup is the practical bottleneck any such tool must solve.
- **Raimondi & Lomuscio (DEON 2004)** verify deontic and epistemic properties of multi-agent systems via OBDD-based model checking — an early instance of the BDD-based approach L4's own reasoner lineage echoes.
- **Wooldridge (DEON 2004)** reframes social-law effectiveness and synthesis as ATL model-checking problems, the clearest statement of the "normative question = model-checking problem" equivalence L4's ProLaLa framing generalizes to law at large.
- **Giordano, Martelli & Dupré (ICAIL 2013)** extend Answer Set Programming with deontic temporal modalities (Deontic DLTL) specifically to bounded-model-check business-process compliance against achievement, maintenance, deadline, and contrary-to-duty obligations together — a rare prior system that, like L4, treats multiple obligation types uniformly.
- **Liepina, de Lima, Lorini, Pisano & Sartor (ICAIL 2025)** build a model checker over TQBF for causal notions (NESS test, actual cause) in legal cases — a 2025 demonstration that the model-checking-for-law program is still actively expanding to reasoning tasks (causation) well beyond compliance.

### Deontic paradoxes and the limits of temporal logic for norms

A parallel and partly adversarial literature asks whether standard temporal logics are even the right tool for norms, given long-standing deontic paradoxes (contrary-to-duty, Chisholm's scenario). L4's paper must engage this literature honestly, since it is the strongest prior argument against L4's own strategy of casting normative conflicts as temporal-logic model-checking problems.

- **Governatori (ICAIL 2015)**, "Thou shalt is not you will," is a direct challenge: it constructs a new CTD/permission paradox showing that ordinary temporal logic mishandles the interaction of obligation, permission, and contrary-to-duty obligation in realistic norms. This is the key contrasting voice L4's paper needs to answer — L4's bug-finding pilots (the double-bind race condition) are exactly the phenomenon Governatori says naive temporal encodings get wrong, so L4 must show its semantics avoids this trap.
- **Broersen (DEON 2006)** answers a version of the same worry constructively, reducing strategic deontic temporal logic to Alternating-time Temporal Logic (ATL) and using the reduction to resolve Chisholm's paradox — a template for how a temporal encoding *can* be made CTD-safe.
- **Torre, Hulstijn, Dastani & Broersen (DEON 2004)**, **Castro & Maibaum (DEON 2008)**, and **Libal & Pascucci (ICAIL 2019)** each propose bespoke logics (KBDIOCTL; a tableaux-complete deontic action logic; bimodal "normative detachment structures") purpose-built to keep CTD reasoning and deontic paradoxes decidable and mechanizable, underscoring how much logical apparatus this literature has judged necessary just to get contrary-to-duty right.

### Compliance-checking systems: encoding regulations and business processes

A large applied strand treats compliance-checking as the deliverable: encode a body of regulation or a business-process specification formally, then check conformance automatically. This is the oldest and most industrially-oriented part of the corpus, and it establishes both the demand for L4-like tooling and the ceiling that document-first, translate-after approaches have hit.

- **Kerrigan & Law (ICAIL 2003)**, the highest-cited paper in this facet, builds a first-order predicate-calculus compliance-assistance system for environmental regulation atop an XML document framework — an early demonstration that formal infrastructure for regulatory compliance is buildable, but one built as a downstream layer over documents rather than as the drafting language itself.
- **Dinesh, Joshi, Lee & Sokolsky (DEON 2008)** cast regulatory conformance as trace-checking: a logic evaluated against an abstract run, explicitly handling the conditions-and-exceptions structure that pervades real regulation.
- **Governatori & Shek (ICAIL 2013)** ship Regorous, a business-process compliance checker built on the compliance-by-design methodology, and **Governatori & Rotolo (JURIX 2008)** supply the underlying algorithm — together the clearest evidence that "compliance is a relation between two formal specifications" is a mature, tool-supported idea that L4 extends from processes to natural-language-facing contracts and legislation.
- **van de Ven, Breuker, Hoekstra & Wortel (JURIX 2008)** encode legal assessment in OWL 2 (the HARNESS system), trading expressiveness for the soundness and completeness guarantees of description-logic reasoners — the same trade-off L4 must justify choosing against, in the other direction, favoring a richer functional language.
- **Vanthienen & Robben (ICAIL 1993)**, the oldest paper in the bundle, shows decision tables were already valued in 1993 not just for representing legal knowledge but for *testing its consistency* — the germ of the "verification as a byproduct of formalization" idea L4 pursues three decades later with a strictly more expressive language.

### Conflict, contradiction, and loophole detection — the "white-hat Bad Man" lineage

This is the sub-theme closest in spirit to ProLaLa: work whose explicit goal is finding conflicts, gaps, and contradictions in normative or contractual text — the direct precedent for L4's pilot findings (the double-bind race condition in secondary legislation, the payout-formula ambiguity in an insurance policy).

- **Li, Balke, De Vos, Padget & Satoh** publish essentially one research program across two papers (**ICAIL 2013**; **JURIX 2013**) combining a formal model of legal specifications with answer-set/inductive-logic programming to *detect* conflicts between interacting legal systems and *propose revisions* — the fullest prior realization of "verification finds the bug, then a repair is suggested," which L4's legislative pilot (bug found, no automated repair yet offered) has not yet matched.
- **Bhuiyan, Governatori, Bond, Demmel, Islam & Rakotonirainy (JURIX 2020)** encode autonomous-vehicle traffic rules in Defeasible Deontic Logic specifically to surface exceptions and conflicts — a domain (safety-critical rule-following by an artificial agent) structurally close to L4's regulatory-compliance wizard use case.
- **Tosatto, Governatori & Kelsen (DEON 2014)** give necessary-and-sufficient conditions for conflicting obligations/permissions in dynamic (time-varying) regulatory settings — conflict-detection-as-verification stated in its most general form.
- **Carlson & Genesereth (JURIX 2023)** encode insurance policies as logic programs and use logic-program containment testing to find coverage gaps and redundancies across *multiple* policies — the closest direct precedent to L4's own insurance-policy pilot (an ambiguous payout formula leaking value), differing mainly in scope (portfolio containment vs. single-policy ambiguity) and in L4's added NL-traceability layer.
- **Laneve, Parenti & Sartor (JURIX 2024)** detect incompatible clauses in Stipula, a domain-specific language for computable legal contracts, using patterns mined from real case law — Stipula is the closest sibling language to L4 in this entire bundle (an executable DSL for contracts built explicitly to expose incompatibilities), making the comparison a must for L4's related work.
- **Pace (JURIX 2020)**, **Araszkiewicz, Francesconi & Zurek (JURIX 2021)**, **Kharraz, Schneider & Leucker (JURIX 2024)**, and **Azzopardi & Pace (JURIX 2024)** extend conflict analysis to environmental action constraints, Semantic-Web contradiction models, SMT-based satisfiability for timed norms, and timed contract automata respectively — collectively showing the conflict-detection problem keeps being re-solved in a new logic or new formalism for each new feature (time, environment, ontology) rather than accreting into one general-purpose language.

### Logic-programming, argumentation, and tableaux-based reasoning tools

A distinct methodological cluster reaches for logic programming (Prolog/ASP), argumentation frameworks, or proof-theoretic tableaux as the reasoning engine behind legal verification — the same broad family of "left-brain" symbolic reasoning L4 commits to, but typically wrapped around a bespoke logic rather than a general-purpose typed functional language.

- **Artikis, Sergot & Pitt (ICAIL 2003)** give an early, influential executable specification of a normative multi-agent protocol in the action language C+, run via the CCALC causal calculator — an early proof that "formal, declarative, verifiable, executable" was already the explicit ambition for normative systems in 2003.
- **Satoh, Takahashi & Kawasaki (ICAIL 2021)** build an interactive PROLEG-based tool for arranging disputed issues in Japanese civil litigation, and **Fungwacharakorn & Satoh (JURIX 2020)** generalize Satoh's "Legal Debugging" method — interactively finding the *culprit rule* behind a counterintuitive legal consequence and then generalizing its fix — both directly relevant given L4's own PROLEG transpiler work and its interest in explaining *why* a verifier's answer is what it is.
- **Santos & Pacheco (ICAIL 2003)**, **Strasser & Arieli (DEON 2014)**, **Brasil & Garcia (ICAIL 2003)**, and **Zheng, Xiong & Verheij (JURIX 2018)** each mechanize a different proof method — tableaux, sequent-based argumentation, weighted MAXSAT, and Prolog respectively — over a bespoke deontic or defeasible logic, illustrating how fragmented the choice of reasoning engine has been across this literature.
- **Araszkiewicz & Savelka (JURIX 2012)**, **Bench-Capon (JURIX 2014)**, **Rotolo & Smith (ICAIL 2021)**, and **Dik (JURIX 2025)** extend verification-style formal methods (constraint satisfaction, transition systems, PDL, ASP) from norm-checking into judicial and procedural reasoning, showing the "bad-man" verification stance generalizes past rule-conflict-finding to reasoning about case outcomes and discretion.

### Frontier applications: AI Act, autonomous systems, and quantitative extensions

The newest work in the bundle applies this whole toolkit to contemporary regulatory flashpoints, evidence that demand for formal verification of norms is intensifying rather than fading.

- **Lawniczak & Benzmüller (ICAIL 2025)** formalize modalities in the EU AI Act using LogiKEy's shallow semantic embeddings in Isabelle/HOL — a higher-order-logic, proof-assistant-based approach to the same "formalize a live, high-stakes regulation and check it" problem L4 targets, but via interactive theorem proving rather than an executable domain-specific language.
- **Ferrigno, Billi, Yousefi & Rotolo (JURIX 2025)** and **Zurek, Mohajeriparizi, Kwik & van Engers (JURIX 2022)** apply defeasible deontic logic and formal verification respectively to AI Act rights-balancing and to autonomous weapons' compliance with international humanitarian law — both illustrate the "verification for safety-critical, high-stakes norms" motivation L4 also invokes (its government-agency pilot), in domains adjacent to but distinct from L4's own.
- **Wyner, Bos, Basile & Quaresma (JURIX 2012)** and **Takano, Nakamura, Oyama & Shimazu (JURIX 2010)** tackle the upstream problem of automatically translating natural-language legal text into a machine-readable formal representation — the isomorphism/round-tripping problem L4 treats as first-class, here approached as an NLP task rather than a language-design one.

### Must-cite anchors

- **Governatori (ICAIL 2015)** — the sharpest existing argument that temporal logic mishandles CTD/permission paradoxes; L4 must position its semantics against this critique directly.
- **Gorín, Mera & Schapachnik (JURIX 2010)** and **Faciano et al. (ICAIL 2017)** — FormaLex is the closest existing "model-check a real statute" pipeline and its scaling story.
- **Kerrigan & Law (ICAIL 2003)** — highest-cited anchor for formal regulatory-compliance infrastructure as a research goal.
- **Governatori & Shek (ICAIL 2013)** and **Governatori & Rotolo (JURIX 2008)** — Regorous and its algorithm, the maturest tool-supported instance of compliance-as-formal-relation.
- **Li, Balke, De Vos, Padget & Satoh (ICAIL/JURIX 2013)** — the fullest prior example of detect-and-propose-repair for legal conflicts.
- **Carlson & Genesereth (JURIX 2023)** — the direct precedent for L4's insurance-policy-ambiguity pilot finding.
- **Laneve, Parenti & Sartor (JURIX 2024)** — Stipula, the nearest sibling executable contract DSL, with its own conflict-detection story.
- **Wooldridge (DEON 2004)** — the cleanest statement that normative questions reduce to model-checking problems.
- **Satoh, Takahashi & Kawasaki (ICAIL 2021)** and **Fungwacharakorn & Satoh (JURIX 2020)** — Satoh's PROLEG and Legal Debugging line, directly relevant given L4's own PROLEG transpiler work.
- **Vanthienen & Robben (ICAIL 1993)** — the earliest statement that formalizing legal knowledge (decision tables) doubles as testing its consistency.

### Supporting cites

*Model checking / temporal-modal logics:* Raimondi & Lomuscio (DEON 2004) — OBDD deontic/epistemic MAS verification; Jamroga, van der Hoek & Wooldridge (DEON 2004) — deontic logic + ATL for obligations/abilities; Lomuscio & Wozna (DEON 2006) — complete axiomatization of deontic interpreted systems; French, McCabe-Dansted & Reynolds (DEON 2010) — RoCTL* axiomatization for CTD; van der Hoek (JURIX 2010) — CTL-style transition-system model of normative systems; Giordano, Martelli & Dupré (ICAIL 2013) — Deontic DLTL + ASP bounded model checking; Liepina et al. (ICAIL 2025) — TQBF model checker for causation.

*CTD / deontic paradoxes:* Broersen (DEON 2006) — strategic deontic temporal logic resolving Chisholm's paradox; Torre, Hulstijn, Dastani & Broersen (DEON 2004) — KBDIOCTL for normative multiagent organizations; Castro & Maibaum (DEON 2008) — tableaux for deontic action logic; Libal & Pascucci (ICAIL 2019) — bimodal normative detachment structures.

*Compliance checking:* Dinesh, Joshi, Lee & Sokolsky (DEON 2008) — trace-checking for conditions/exceptions in regulation; van de Ven, Breuker, Hoekstra & Wortel (JURIX 2008) — HARNESS, OWL-DL legal assessment; Francesconi & Governatori (JURIX 2019) — OWL2 defeasible norms in Linked Open Data; Robaldo (ICAIL 2021) — reified I/O logic compliance via SHACL; Morris (ICAIL 2021) — constraint-ASP rules-as-code drafting experiment.

*Conflict/contradiction detection:* Bhuiyan et al. (JURIX 2020) — Defeasible Deontic Logic for AV traffic-rule conflicts; Tosatto, Governatori & Kelsen (DEON 2014) — conflicting obligations in dynamic settings; Araszkiewicz, Francesconi & Zurek (JURIX 2021) — Semantic-Web contradiction detection; Pace (JURIX 2020) — contract conflicts with environmental constraints; Kharraz, Schneider & Leucker (JURIX 2024) — SMT satisfiability for timed normative conflicts; Azzopardi & Pace (JURIX 2024) — conflict analysis for timed contract automata; Chircop, Pace & Schneider (JURIX 2022) — automata-based real-time deontic formalism; Cambronero, Llana & Pace (JURIX 2017) — timed-contract compliance under timing uncertainty; Pace & Schapachnik (ICAIL 2013) — synthesizing implicit contracts as automata.

*Logic programming / argumentation / tableaux:* Artikis, Sergot & Pitt (ICAIL 2003) — executable C+/CCALC normative protocol; Santos & Pacheco (ICAIL 2003) — tableaux for institutional-agent deontic/action logic; Strasser & Arieli (DEON 2014) — sequent-based argumentation for CTD/specificity; Brasil & Garcia (ICAIL 2003) — MAXSAT for defeasible legal entailment; Zheng, Xiong & Verheij (JURIX 2018) — Prolog validity-of-rule-based-arguments; Satoh, Baldoni & Giordano (JURIX 2020) — logic-program renvoi in private international law; Araszkiewicz & Savelka (JURIX 2012) — constraint-satisfaction coherence for judicial reasoning; Bench-Capon (JURIX 2014) — transition systems for norm design; Rotolo & Smith (ICAIL 2021) — PDL for legal procedures; Dik (JURIX 2025) — ASP for discretionary judicial decisions.

*Frontier domains / NL translation:* Zurek, Mohajeriparizi, Kwik & van Engers (JURIX 2022) — IHL compliance verification for autonomous devices; Ferrigno, Billi, Yousefi & Rotolo (JURIX 2025) — DLRisk for AI Act rights-balancing; Wyner, Bos, Basile & Quaresma (JURIX 2012) — state-of-the-art NL-to-formal translation survey; Takano, Nakamura, Oyama & Shimazu (JURIX 2010) — multi-sentence paragraph logical-formulation system.

### Gap / L4's opening

Every system surveyed here builds its formal model as a *second artifact*, produced by a logician after the regulation, contract, or process specification already exists in natural language — none treats the executable formalization as the drafting medium itself, so isomorphic traceability back to the source text is bolted on (if attempted at all) rather than structural. None of these systems pairs its verifier with an LLM front-end capable of both ingesting arbitrary legacy text at scale and explaining a verification trace in natural language to a non-specialist end-user; each targets a logician-analyst as the operator of the tool, not a citizen or SME founder facing a wizard. And while several papers (Governatori 2015 chief among them) argue persuasively that naive temporal-logic encodings mishandle contrary-to-duty structure, none of them then demonstrates a language expressive and disciplined enough to formalize an entire real-world statute or insurance policy and surface a genuine, previously-undetected conflict in production use — which is precisely what L4's pilots (the legislative race condition, the insurance payout ambiguity) already show.


---

