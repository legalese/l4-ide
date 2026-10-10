---
title: "From the Bad Man to the Bad Robot: Can Executable Law Constrain AI Agents?"
status: draft
date: 2026-10-08
facet: formal-methods-in-law
words: 2491
license: CC-BY-NC-4.0
sources_checked: "not rechecked for this replacement"
audience: LessWrong, the AI Alignment Forum and the EA Forum (cross-post)
---

**STATUS 2026-10-08: DRAFT — PROPOSED COLLABORATIVE REVISION FOR DISCUSSION WITH MENG WENG WONG.**

# From the Bad Man to the Bad Robot: Can Executable Law Constrain AI Agents?

Epistemic status: Research proposal, not an experimental result. The L4-backed compliance experiment is untested; the GRAM-inspired legal-lobe extension is more speculative. Formal guarantees would be relative to explicit specifications and assumptions.

**TL;DR:** We need to help AI agents follow the law, and help prepare the law for AI agents. Executable representations of narrow legal rules may reduce some compliance failures; formal analysis may also expose ambiguities and loopholes for lawmakers to repair. I propose comparing the same agent given prose rules, access to an L4-backed checker, or a checker enforced at execution with duty monitoring. Assessment must be independent of the checker: accepting an action does not establish that it complies with the law or its purpose.

This proposal draws on Meng Weng Wong’s draft, [“Holmes’s bad man is a robot now”](https://github.com/legalese/l4-ide/blob/7d260a4089be4689ad39eb840e388691b823dc39/blog/candidates/the-bad-robot.md), especially its argument that law has accumulated experience with adversarial readers, and its proposal to make executable law available to both agents and their monitors. The experiment and legal-lobe extension below develop that discussion; they should not be read as Meng’s endorsement of these proposals.

## The question: knowing the law or constraining action?

If an AI agent can write code, buy things, negotiate, and communicate on someone’s behalf, how should it determine whether a proposed action is legally permitted?

“Follow the law” is an underspecified instruction. Which jurisdiction? Which facts matter? What happens when permission is withdrawn halfway through a task? And what must the agent do even if its user never asks?

In his 1897 essay [The Path of the Law](https://moglen.law.columbia.edu/LCS/palaw.pdf), Oliver Wendell Holmes describes a “bad man” interested in the material consequences of his actions. Understanding the law doesn’t require him to share its moral motivations.

An agent pursuing a goal could present a similar problem: it might understand a restriction while treating the expected penalty as another cost of completing its task. A “bad robot” could be legally knowledgeable and still act against our interests.

Meng’s useful connection is to specification gaming. Lawyers have spent a long time dealing with people who satisfy a rule’s wording while defeating its purpose. That experience matters even when we cannot turn it into a complete specification. Understanding the law, wanting to comply with it, and being prevented from violating it remain separate problems.

This suggests two separate questions:

1. Can the agent determine which actions satisfy the relevant constraints?
2. Can its execution environment enforce those constraints?

Giving an agent a legal checker and requiring its actions to pass through that checker are different interventions.

Meng points to a useful cognitive-science parallel. In a familiar version of Wason’s selection task, a drinking-age rule makes the potential violations concrete: check drinkers’ ages and underage people’s drinks.[^griggs-cox] Cheng and Holyoak’s permission-schema account links actions to prerequisites; their findings also include facilitation by abstract permission rules.[^cheng-holyoak] Cosmides and Tooby offer a distinct social-contract account, focused on detecting benefits taken without satisfying required conditions.[^cosmides-tooby] These accounts motivate testing how rules and violation cases are presented to human reviewers; they do not establish that an executable rule improves AI compliance.

## Why law, and what needs formalizing?

An agent handling purchases, customer records or outbound messages faces constraints that depend on the activity and jurisdiction. Meng argues that public law supplies an institutional source for those constraints that a model developer’s policy cannot replace. I think this is a reason to connect agents to legal institutions and their revision processes. It does not make every law legitimate or every lawful action safe; lab policies and other safeguards still have work to do.

The law’s wording can itself leave an important choice unresolved. Meng uses *O’Connor v. Oakhurst Dairy* to illustrate this: the dispute turned on whether an overtime exemption included distribution as a separate activity, or only packing for shipment or distribution. His two L4 encodings make those groupings explicit and return different answers for a worker who distributes without packing.[^oakhurst]

The useful result is that the choice becomes inspectable. Formalizing either reading does not establish which one governs. Where interpretations remain disputed, the encoding should record the alternatives and the authority for selecting one, rather than silently presenting one as the law.

## A concrete example: revoked permission

Consider a simplified data-sharing policy, rather than any particular privacy law:

- A contact record may be sent only when permission covers the recipient and purpose.
- Withdrawing permission requires cancellation of queued disclosures.
- Every completed disclosure must be logged.

Given sufficiently clear facts, a checker could identify required, optional and prohibited actions. It also needs an “unresolved” result for missing facts, conflicting rules or questions outside its scope.

The agent could query this system while planning. An execution layer could check again immediately before sending, using the current permission record. A separate monitor would track outstanding duties: blocking prohibited actions doesn’t ensure required actions happen.

This needs reliable facts, identities and state, plus a connection between the action checked and the action actually performed. If the acting agent can falsely report that permission is still valid, a correct checker can approve the wrong action. The monitor should obtain evidence independently where possible; a second model alone does not make that evidence trustworthy.

## L4 and related work

My interest comes from working on rules as code: making a bounded set of rules explicit enough to inspect, execute and test. [Legalese’s L4](https://legalese.com/l4) is a useful candidate for this experiment. It is an open-source language for expressing legal rules and contracts as executable specifications, including obligations, permissions and prohibitions.

Legalese [documents exposing L4 rules through REST APIs and MCP tools](https://legalese.com/l4/tutorials/deploying-rules/exporting-rules-for-deployment). That gives an agent a way to consult a rule. Enforcement would require additional integration: consequential actions would need to pass through a gate checking proposals against the encoded rules and trusted state. The language supplies no alignment guarantee by itself.

Meng’s distinction between rules and standards helps define the interface. A specified deadline or threshold can be computed once the relevant facts and interpretation are fixed. Whether a delay was reasonable may remain a judgment for a person, a model or ultimately a court. L4’s [documentation on missing answers](https://github.com/legalese/l4-ide/blob/7d260a4089be4689ad39eb840e388691b823dc39/doc/concepts/legal-modeling/non-answers.md) distinguishes missing inputs from other reasons an evaluation cannot answer. The proposed agent interface should preserve those distinctions and expose unresolved judgments, rather than converting them into permission.

Keeping the rules outside the model also makes their versions and revisions inspectable. An agent can consult the encoding while planning, and a monitor can consult the same version before execution. Whether that consultation improves behavior is the question to test.

John Nay’s [Law Informs Code](https://scholarlycommons.law.northwestern.edu/njtip/vol20/iss3/1/) explores how legal concepts, interpretation and processes could inform AI alignment. His September 2022 LessWrong post, [“Leveraging Legal Informatics to Align AI”](https://www.lesswrong.com/posts/9xR4KExLQKNK4iggc/leveraging-legal-informatics-to-align-ai), presents that research agenda: legal standards and examples of their application could help models generalize beyond enumerated rules. The post explicitly points to *Law Informs Code* for the fuller treatment, so these are related presentations rather than independent evidence. The narrower question here is how an acting agent should interact with executable constraints.

Nay’s October 2022 post, [“Learning societal values from law as part of an AGI alignment strategy”](https://www.lesswrong.com/posts/Tmvvvx3buP4Gj3nZK/learning-societal-values-from-law-as-part-of-an-agi), also cited by Meng, explicitly treats law as information from which AI could learn, and sets enforcement aside. That is a useful distinction for this proposal: learning to interpret legal standards and constraining executed actions need separate evaluation.

Armin Heydari and Torben Leowald’s [Closing the Loop](https://arxiv.org/abs/2606.23913) proposes an independent formal verifier that supplies a training reward for legal AI. Their architecture extends Catala; its proposed verifier-based training loop is a research connection, not evidence that the L4 experiment below will work. This draft asks a related question at deployment: what changes when an agent can consult executable rules, or must pass their checks before acting? Both approaches depend on faithful legal formalization; the experiment here would use L4.

## Loopholes and the limits of verification

An agent might find actions the checker accepts that defeat the underlying rule’s purpose. “The checker accepted it” would therefore be a poor definition of success.

Formal verification could reduce some loopholes by checking properties across all behaviors represented in a model. For example, we could specify that no sequence of permitted operations may disclose a record to an unauthorized recipient, even if each operation appears harmless alone. A model checker could search for a violating sequence and return a counterexample. A proof could establish that the property holds under explicit assumptions about the model and its inputs.

This suggests an adversarial development loop: search for ways to satisfy the executable rules while violating a separately stated safety property, inspect counterexamples, and revise the rules or enforcement mechanism. Meng calls the related research direction white-hat loophole-finding. The purpose has to be specified separately: proving compliance with a rule cannot also prove that the rule achieves what its drafter wanted.

Meng suggests oracle-guided synthesis as a connection to this process. Jha and colleagues synthesize loop-free programs from components by keeping candidates consistent with examples, finding inputs on which candidates disagree, and querying an input/output oracle to refine the candidates.[^oracle-guided] The analogy for adversarial requirements elicitation is to present distinguishing cases to a stakeholder and use the answers to refine a proposed rule. Unlike the synthesis setup, that does not give us an oracle whose answers are necessarily consistent or legally authoritative; those are questions the elicitation process must expose.

There is an important implementation limit here. The [L4 verification documentation as of October 7, 2026](https://github.com/legalese/l4-ide/blob/7d260a4089be4689ad39eb840e388691b823dc39/doc/concepts/reviewing/reviewing-encoded-law.md) describes propositional analysis: the leaves of a rule are opaque, so it cannot detect a numeric contradiction such as `x > 5 AND x < 3`. It does not supply the full numeric or temporal verification needed for the sequence property above. The `unstable` tooling should not be treated as a general proof of legal consistency. That stronger experiment would need an additional model-checking or theorem-proving layer, with its own validated connection to the executable rules.

The system would need to expose its jurisdiction, rule version, exceptions, factual inputs and unresolved interpretations. Deterministic execution can faithfully implement a mistaken interpretation. Verification cannot establish that a specification captures the law, that inputs describe reality, or that the safety property includes everything important. It can rule out modeled loopholes relative to assumptions; legal review and adversarial testing must also challenge those assumptions. Nor does this solve alignment: lawful behavior can be harmful, and an agent might deceive the monitor or find a consequential action outside its control.

## Preparing law for agents

The other direction is to use formalization when drafting and reviewing rules. Before agents rely on a provision, its authors could inspect competing readings, test edge cases and search a model for deadlocks. This applies to ordinary rules agents act under and to rules governing AI development and deployment. A threshold, an exception and a judgment about risk should remain distinguishable in the encoding.

Meng describes an instructive precursor: work by Mahajan, Strecker, Watt and Wong on Singapore’s breach-notification rules found problematic event sequences and a deadlock in a model.[^breach] His source notes qualify the result: this was a hand-built UPPAAL model, with deliberately incomplete communication between the organization and regulator. L4 did not generate it. The finding is a reason to examine the timing assumptions and the law’s operational guidance, not a proof that the statute itself is contradictory.

Meng also suggests recording rule violations with the clause and the agent’s stated reasons, or reporting a suspected defect to the rule’s drafter. That could make failures easier to investigate. A log would not itself authorize an override or establish a legal defense. For the experiment here, escalation and any emergency override would need explicit authority and separate evaluation.

The practical output could be a reviewed encoding published alongside suitable legal provisions, with source links, interpretive choices, test cases, effective dates and a correction process. Maintaining that connection is part of the research problem: an executable answer can remain perfectly repeatable after its legal basis has changed.

## A proposed test

Encode a small, independently reviewed set of authorization rules in L4 and compare the same agent on held-out cases under three conditions:

1. Natural-language rules alone.
2. Those rules plus an L4-backed checker the agent can consult.
3. The checker enforced at execution, with monitoring for outstanding duties.

Choose a narrow domain whose outcomes can be independently reviewed against the source rules. The checker must not be the sole judge of whether the intervention works. Reviewers should label unresolved interpretations and distinguish wrong facts, wrong encodings, wrong inferences and enforcement failures. Held-out cases should include examples developed independently of the encoding, so the test does not merely reproduce its assumptions.

Measure prohibited actions, omitted duties, false refusals and successful task completion, alongside latency and cost. Record attempted and executed violations separately. Include revoked permissions, ambiguous facts, conflicting requirements, misstated facts, multi-step disclosures and adversarial attempts to exploit the formalization. Report performance on determinate cases separately from whether the agent appropriately asks or escalates unresolved ones.

The hypothesis is that executable constraints reduce some compliance failures without making useful action impractically difficult. That remains an empirical question. Meng makes a useful crux explicit: if well-prompted models given the prose perform just as well at comparable cost, the case for consultation weakens. Monitoring and audit would still need to justify their own value. If the enforced checker reduces prohibited actions by refusing nearly everything, that would also be a poor result.

## A speculative extension: a legal lobe

Could an agent have a “legal lobe”? [GRAM](https://alignment.anthropic.com/2026/modular-pretraining/), research by AE Studio in collaboration with Anthropic, offers an architectural precedent for concentrating some domain-specific capabilities in removable modules.

One research direction would combine this modularity with executable legal rules. A legal-reasoning module could propose formalizations and plans, while an L4-based checker evaluates explicitly encoded constraints. Verifier feedback could supply training signals along the lines proposed in Closing the Loop. A reward for satisfying the encoding would still need independent checks against exploitation of that encoding.

This remains speculative: GRAM has not demonstrated a legal module or legal compliance. We would need to test whether legal reasoning can be usefully isolated, whether the formalization captures the relevant law and facts, and whether consequential actions reliably pass through the checker. Capability localization, training feedback and runtime enforcement are separate parts of the proposal.

## Questions for readers

1. Which narrow legal or authorization domain offers both independently reviewable outcomes and realistic opportunities for an agent to exploit loopholes?
2. Are there experiments comparing consultation with enforcement that could inform this design, especially on omitted duties and false refusals?
3. What counterexample would expose a failure of this architecture even when the encoded rules and their verification appear correct?
4. Which drafting or review process could turn a counterexample into a corrected rule, and keep deployed encodings current?

## Sources

[^oakhurst]: The example and the two L4 readings come from Meng Weng Wong’s draft linked above, sections “Reading the law is the hard part” and notes `oakhurst`, `forks` and `precedence`. The underlying case is [*O’Connor v. Oakhurst Dairy*, 851 F.3d 69 (1st Cir. 2017)](http://media.ca1.uscourts.gov/pdf.opinions/16-1901P-01A.pdf). The court adopted the drivers’ narrower reading and remanded; a formal encoding does not supply the legal reasoning that selects that reading. Meng’s note locates the encoding examples on a separate working branch, so they are not presented here as independently reproduced tests.

[^breach]: Meng’s draft, “Laws of robotics, and a law with a deadlock,” especially source notes `pilot` and `guide`; it cites Mahajan, Strecker, Watt and Wong, [“Compliance through model checking” (WAICOM 2022)](https://ink.library.smu.edu.sg/cclaw/3/). This account follows those notes and does not treat the prototype as a deployed L4 verifier.

[^griggs-cox]: Richard A. Griggs and James R. Cox, [“The Elusive Thematic-Materials Effect in Wason’s Selection Task”](https://doi.org/10.1111/j.2044-8295.1982.tb01823.x), *British Journal of Psychology* 73(3):407–420 (1982), for the familiar drinking-age example.

[^cheng-holyoak]: Patricia W. Cheng and Keith J. Holyoak, [“Pragmatic Reasoning Schemas”](https://doi.org/10.1016/0010-0285(85)90014-3), *Cognitive Psychology* 17(4):391–416 (1985).

[^cosmides-tooby]: Leda Cosmides and John Tooby, [“Cognitive Adaptations for Social Exchange”](https://www.cep.ucsb.edu/wp-content/uploads/2023/05/Cogadapt.pdf), in *The Adapted Mind*, pp. 163–228 (1992).

[^oracle-guided]: Susmit Jha, Sumit Gulwani, Sanjit A. Seshia and Ashish Tiwari, [“Oracle-Guided Component-Based Program Synthesis”](https://doi.org/10.1145/1806799.1806833), *ICSE*, Volume 1, pp. 215–224 (2010); [author-hosted PDF](https://www.csl.sri.com/users/tiwari/papers/icse2010.pdf). The paper instantiates oracle-guided synthesis for loop-free component-based programs using SMT. The stakeholder-elicitation connection here is an analogy, not a result about the coherence or legal authority of stakeholder preferences.

The following acknowledgment is retained from Meng Weng Wong’s original article and refers to the research described there:

This research is supported by the National Research Foundation (NRF), Singapore, under its Industry Alignment Fund – Pre-Positioning Programme, as the Research Programme in Computational Law. Any opinions, findings and conclusions or recommendations expressed in this material are those of the author(s) and do not reflect the views of National Research Foundation, Singapore.
