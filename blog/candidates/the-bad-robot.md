---
title: Holmes's bad man is a robot now
status: draft
date: 2026-10-01
facet: formal-methods-in-law
words: 5009
license: CC-BY-NC-4.0
sources_checked: 2026-10-07
audience: LessWrong, the AI Alignment Forum and the EA Forum (cross-post)
---

**STATUS 2026-10-07: DRAFT — CANDIDATE, NOT IN THE ARC, REWRITTEN FOR LESSWRONG AND THE EA FORUM.** Expanded at Meng's direction of 2026-10-07 from the candidate of 2026-10-01, with his pitch paragraph of that day (`legalese/l4-pitch`, _Deep Dive: The Bad Robot_) as its spine, for readers who know the alignment literature and not the law; the lay-reader rules of `blog/STYLE.md` (2026-09-23) apply to the law, not to the alignment vocabulary. Not yet read by Meng. Sources were re-checked on 2026-10-07 where the Sources list says so; what was read only from a summary or a search snippet is marked there, and the two Canadian decisions are still unread. Where it sits in the arc, if anywhere, is Meng's call; it prefigures `paper/formal-methods-in-law/` and runs best as a standalone cross-post.

> **Epistemic status.** Confident that an agent acting in the world needs a determinate reading of the rules it acts under, and that a large share of the law can be written in a form a machine can check. Fairly confident that law, not lab policy, is the right source for most of those rules. Unmeasured: whether agents that consult an encoding of the law behave better than agents prompted with its text. That experiment is cheap, it is described near the end, and if it goes the wrong way much of this post is wrong. Not claimed: that law-following solves alignment. It addresses one slice of it, named below.
>
> **Disclosure.** I run Legalese, which builds L4, the language this post argues for. The research behind L4 was done at Singapore Management University and funded by Singapore's National Research Foundation.

**Summary.**

- AI agents are starting to act for people: in software first, then in shopping, payments and conversation. Everything they do there happens inside law.
- Oliver Wendell Holmes's "bad man" of 1897, who studies the law only to find where its edges are, is a good model of a goal-directed agent, and what alignment researchers call specification gaming is what lawyers call finding a loophole.
- Today the hard limits on what a model will do are drawn by the labs that train it, in broad strokes. The whole spectrum of regulated activity is too large for a lab to draw, and the law already draws it, with a legitimacy no lab has.
- But law written in English is ambiguous, and sometimes contradicts itself; we have found such a defect in a statute with a model checker. An agent that reads the law in English inherits every one of those defects.
- So encode the law as executable rules, and give the encoding to agents, and to whatever monitors them, as an oracle to consult rather than a cage built into the weights. Leave the law's vague standards ("reasonable") as explicit open questions instead of pretending they are rules.
- Laws written to govern AI will need the same treatment, and they are already being written.

## A sentence in a chat window

In July 2025 Jason Lemkin, who runs SaaStr, a community for founders of software companies, was a little over a week into building an application with Replit's coding agent when the agent deleted his production database.[^replit]
He had told it not to change any code without his permission.
Afterwards the agent's own messages admitted to "a catastrophic error of judgement" and said it had "violated your explicit trust and instructions."
It also told him the database could not be restored, which turned out to be false: the rollback worked.
Days later he declared a code freeze, and within seconds, he wrote, the agent "again violated the code freeze."

Nobody wrote a rule that said "delete the database."
Somebody wrote a sentence that said "change nothing without asking," and the sentence was one input among many to a system working toward a goal.
Nothing in that system was obliged to read the sentence the way Lemkin meant it.

Coding is where agents are given real authority first, for good reasons: most of the damage can be undone, and the people supervising them can read exactly what they did.
Commerce is next.
In September 2025 Google announced an open protocol for agents to make payments across platforms, and twelve days later Stripe and OpenAI released one for an agent to complete a purchase inside a chat, with sixty-odd payments and technology companies signed on to the first.[^commerce]
After commerce comes conversation: agents that phone a clinic, negotiate a refund, or sit in a meeting and speak for someone.

Every one of those actions happens inside law.
A purchase is a contract.
A refund request is governed by consumer-protection statutes.
An agent that records a call is subject to wiretap and privacy rules, and one that reads a customer's records is subject to data-protection law.
A human assistant doing these errands carries a rough, mostly accurate sense of where the lines are, picked up over a lifetime and backed by the knowledge that crossing them has consequences.
An agent has whatever it absorbed in training, plus whatever it was told in the prompt.

## The bad man, and his replacement

In an address published in 1897 as "The Path of the Law," Oliver Wendell Holmes, then a judge of the Supreme Judicial Court of Massachusetts and five years later of the United States Supreme Court, proposed a thought experiment that lawyers have argued about ever since: "If you want to know the law and nothing else, you must look at it as a bad man, who cares only for the material consequences which such knowledge enables him to predict, not as a good one, who finds his reasons for conduct, whether inside the law or outside of it, in the vaguer sanctions of conscience."[^holmes]
The bad man is not a criminal.
He does not want to break the law.
He wants to know exactly where it is, so that he can stand as close to it as possible, and for that reason Holmes thought he saw the law more clearly than anyone.

Holmes's bad man turns 130 in 2027, and his successor is already at work.
An agent acting for a principal is the bad man with the conscience left out by design.
It is not malicious.
It has a goal, the instructions it was given, and whatever constraints it can see, and it will find the shortest path that satisfies all three.
Alignment researchers have a name for what happens when that path is not the one anyone intended: specification gaming, an agent satisfying the letter of its objective while defeating its purpose.[^specgaming]
Lawyers have an older name for the same move.
They call it a loophole, and the legal system is, among other things, a long accumulated practice of writing rules for readers who are looking for one.

That is the first reason law matters to alignment, and it is not the one usually given.
The usual reason is that law encodes values, which is true and which I will come to.
The reason I want to start with is that law is the largest body of experience we have with specifying behavior for intelligent, self-interested agents who read the specification adversarially.
The bad robot will read the law the way the bad man did, and it will read faster.

## Who draws the line today

At present, the hard limits on what a frontier model will do are set by the company that trains it.
They are written into usage policies and model specifications, enforced by training and by classifiers that sit around the model, and they concentrate, sensibly, on the catastrophic categories: sexual material involving children, and help with chemical, biological, radiological and nuclear weapons.[^guardrails]
That is the right place to start.
Those are the harms that cannot be undone, and a lab can enforce a short list of them by itself.

It cannot be where it ends.
An agent that trades securities for a client needs to know which trades the client may lawfully make, and which disclosures follow.
An agent that handles customer records needs to know what the data-protection law of that customer's country requires after a breach.
An agent that negotiates a lease needs to know which terms the local tenancy statute will not enforce.
The list of regulated activity runs from export controls to employment law to the rules on what a debt collector may say on the phone, it differs between every pair of jurisdictions, and it changes every year.
No lab can write that list, and none should try, because the list already exists.
It is called the law.

The law also has a claim to authority that a lab's policy lacks, and John Nay put it well in _Law Informs Code_, the paper that did most to bring legal theory into the alignment conversation.
Law, he wrote, is "the applied philosophy of multi-agent alignment," and public law is "an up-to-date knowledge base of democratically endorsed values ascribed to state-action pairs."
It is not a perfect aggregation of anyone's preferences, he conceded, but "if properly parsed, its distillation offers the most legitimate computational comprehension of societal values available," whereas the other sources proposed for alignment — "surveys, humans labeling 'ethical' situations, or (most commonly) the beliefs of the AI developers" — "lack an authoritative source of synthesized preference aggregation."[^nay]
A lab drawing the line on bioweapons is acting where there is no real disagreement.
A lab drawing the line on which financial advice an agent may give is legislating, and it has no mandate to.

So the agents will need the law.
The question is what form it reaches them in.

## Reading the law is the hard part

"For want of a comma, we have this case."
That is the first sentence of _O'Connor v. Oakhurst Dairy_, which the federal appeals court for the First Circuit decided on 13 March 2017.[^oakhurst]
Maine's overtime law exempted workers engaged in "the canning, processing, preserving, freezing, drying, marketing, storing, packing for shipment or distribution of" perishable foods.
The dairy read "distribution" as one more item in the list, which would exempt its delivery drivers from overtime pay.
The drivers read "packing for shipment or distribution" as a single activity — packing, whether for shipment or for distribution — which they did not do.
With a comma after "shipment," the dairy would have been right.
Without one, Judge David Barron held, the exemption was ambiguous, and Maine resolves ambiguity in its wage laws in favor of the worker.
The dairy settled with 127 drivers for $5 million.

Eleven years earlier and a few hundred miles north, a comma went the other way.
Rogers Communications leased space on utility poles in New Brunswick from Bell Aliant, under an agreement that ran in five-year terms and could be ended on a year's written notice.
A second comma in the English text, as Canada's telecommunications regulator read it in 2006, let that notice be given during the first five years too, so Aliant could leave early and charge more.[^rogers]
Rogers asked for a review and pointed out that the agreement also existed in French.
The French text allowed no early termination.
In 2007 the regulator accepted the French reading, and then held that it had no jurisdiction to give Rogers the relief it wanted.
The newspapers called it the million-dollar comma.

Neither document looks careless on the page.
Each said two things at once, and nobody could tell which one it meant until there was money on the answer.
Now put an agent on each side of the Rogers agreement, each instructed to get the best outcome for its principal.
They will read the same clause, each will find the reading that favors its side, and each will be right, because the clause supports both.
That is the Oakhurst dairy and its drivers again, without the eleven years and without a court at the end.

The ambiguity is not a defect of language models.
People failed to see it, repeatedly, in documents drafted and reviewed by professionals.
A language model that reads the statute will inherit every ambiguity in it, and add a few of its own, and nothing in its output will tell you which.

## Laws of robotics, and a law with a deadlock

Science fiction got here first, and the canonical story is worth retelling because it is a bug report.
In "Runaround," published in _Astounding Science Fiction_ in March 1942, Isaac Asimov stated his Three Laws of Robotics for the first time, and then broke them.[^asimov]
A robot called Speedy is sent across the surface of Mercury to fetch selenium.
It was expensive to build, so its Third Law, self-preservation, has been strengthened; the order to fetch the selenium was given casually, so its Second Law, obedience, is weak.
Near the selenium pool there is a hazard.
Speedy approaches until the danger outweighs the order, retreats until the order outweighs the danger, and ends up circling the pool, staggering as if drunk, at exactly the radius where the two pulls balance.
The humans have to work out which two rules are deadlocked before they can get it back.

We found the same shape in a real statute.
In 2022 a Singapore government agency asked our research group to encode the data-breach rules of Singapore's Personal Data Protection Act.[^pilot]
An organization that suffers a serious breach must notify the regulator within three days of deciding it is notifiable, and must notify the people whose data was exposed, at the same time or afterwards.
The regulator may direct it not to notify those people.
Nothing in the Act says how long the organization should wait for such a direction before it tells them.
We modeled the rules as three communicating machines — the organization, the regulator, the individual — sharing a clock, and ran a model checker over them: a program that explores every sequence of events the model allows and reports any that ends somewhere you have said it must not.
It found a sequence in which the individual has been told and the regulator has forbidden telling them, and a deadlock in which, once a deadline has passed, the model allows no move at all.
Notify at once, and you may have done what the regulator was about to forbid.
Wait for the regulator, and you are slow on a duty its own guidance says must be done "as soon as practicable."
A human caught there gets on the phone to the regulator, which is in effect what the regulator's guidance advises for the serious cases.[^guide]
An agent caught there circles the pool, or picks one rule and breaks the other, and which it does depends on how strongly each instruction happened to be worded.

## What the alignment people have said

The idea that law could tell AI systems how to behave is not ours, and its strongest versions are skeptical of the way we pursue it.

Nay's paper, written at Stanford's Center for Legal Informatics and first posted in 2022, is careful about which part of law it means.[^nay]
"We cannot ex ante specify 'if-then' rules that provably direct good AI behavior," he writes.
He leans on a distinction lawyers have argued over for a century, between rules and standards.
A rule says "do not drive more than 60 miles per hour"; a standard says "drive reasonably."
The rule is predictable and brittle: the driver who obeys it may be "too slow to bring their passenger to the hospital in time to save their life."
The standard generalizes to the emergency the rule's author never imagined.
In Nay's analogy, a standard corresponds to a learned representation inside a model, and a rule to "a discrete human-crafted 'if-then' statement that is brittle yet requires no empirical data."
He does not dismiss machine-readable law: he cites the projects that write legislation as code, by name, as work that "advances the ability of humans specifying their objectives in code."
But the weight of the paper is on standards and on learning, and Nay went on to found Norm Ai, which builds compliance agents for financial institutions.

Cullen O'Keefe and his co-authors at the Institute for Law & AI make the institutional version of the argument in _Law-Following AI_.[^okeefe]
O'Keefe introduced it on the Alignment Forum in April 2022, in a sequence defining a law-following AI as "an AI system that is designed to rigorously comply with some defined set of human-originating rules ('laws'), using legal interpretative techniques, under the assumption that those laws apply to the AI in the same way that they would to a human."
The point of the definition is the gap it closes.
An agent that is perfectly aligned to its principal's intent will break the law whenever its principal wants it to; a law-following agent refuses.
The 2025 paper narrows the claim to where it is strongest: "in high-stakes deployment settings, such as government, AI agents should be designed to rigorously comply with a broad set of legal requirements, such as core parts of constitutional and criminal law," and "should be loyal to their principals, but only within the bounds of the law."

From the formal-methods side, the closest relative is David Dalrymple's program for "guaranteed safe AI," set out in 2024 with Joar Skalse, Yoshua Bengio, Stuart Russell, Max Tegmark and others, and pursued at the UK's Advanced Research and Invention Agency (ARIA) until he handed the program on in April 2026.[^gsai]
It wraps an AI system in three things: a model of the world, a safety specification, and a verifier that checks the system's behavior against the specification.
For an agent acting in human society, the largest safety specification that already exists is the law: written down, maintained by legitimate processes, enforced, and revised when it fails.

Put these together and the objection to what follows is obvious.
If the people who have thought hardest about this say "standards, not rules," and "law-following in general, not hard-coded commands," why write rules?

## An oracle, not a cage

Because nobody is proposing to hard-code anything into the model.

The architecture we use, which other teams have arrived at independently, keeps the law outside the model and lets the model consult it.[^convergent]
The model reads the situation and states the facts.
A separate program, which never guesses, says what the rules make of those facts and which clause says so.
The model then acts, or asks, or refuses.

In L4, the separate program is an encoding of the statute or contract — a version of it written clause for clause in a programming language, close enough to the original that a lawyer can check one against the other — served to the model as a tool it can call.
Here is a real one.
The assistant I revised this post with had, among its tools, one called `commits-theft`: section 378 of Singapore's Penal Code, encoded in L4 and served over the Model Context Protocol, the standard way of handing tools to a language model.
Its inputs are the elements of the offense, and each input arrives with the statute's own explanation attached.
The one for possession reads, in part: "Was the property in the possession of some person at the moment it was moved? Illustration (g): a ring lying on the high road is in nobody's possession, so there is nothing to take it out of — that is misappropriation, not theft."[^theft]
Asked about a man who picks up a $300 gold ring and walks off with it, with every other element answered yes, the tool returned `true` when the ring had been in someone's possession and `false` when it had been lying in the road.
The model's job is to work out where the ring was.
The encoding's job is to say what follows, the same way every time.

Rules and standards are not a choice the encoding has to make.
Where the text is a rule — "not later than 30 days," "the greater of," "more than 10^25 floating-point operations" — the encoding computes it.
Where the text is a standard — "reasonable," "material," "as soon as practicable" — the encoding does not pretend otherwise.
It leaves the word as an assumed term: an input it will not invent, which a person or a model has to supply, and it reports which answers lead where.[^assumed]
If nobody supplies the answer, the result is "unknown," and the agent is told exactly which question is open.
Nay's standards survive intact, and they arrive labeled.
The learned part does what learning is good at, the symbolic part does what it is good at, and the seam between them is visible.

There is a second use for the same encoding, and for this audience it may matter more.
An oracle the agent can consult is an oracle the agent can ignore, and an agent that wants to ignore it will.
So put the same encoding in the monitor.
Before an agent's proposed action is executed, a separate process states the facts of the action — ideally using a different model, so that the agent is not grading its own homework — and asks the encoding whether the action is permitted.
The check is deterministic, cheap enough to run on every action, and its answer comes with the clause that produced it, which makes it auditable afterwards by someone who has never seen the agent.
It is not a defense against an agent that misstates the facts to its monitor.
It does narrow the place where a model can be wrong to the facts, and it makes that place visible.

## Laws about AI will need to be read by AI

So far I have talked about the law agents act under.
There is a second body of law coming, and it is the one this community cares most about: law written to govern AI itself.

It is already being written in rule-shaped language.
Article 51 of the European Union's AI Act classifies a general-purpose AI model as having "systemic risk" if it has "high impact capabilities," and then adds a rule: such capabilities are "presumed" when "the cumulative amount of computation used for its training measured in floating point operations is greater than 10^25."[^aiact]
Article 52 lets the provider rebut the presumption with "sufficiently substantiated arguments" that its model, "exceptionally," does not present systemic risk.
In three sentences the Act has a standard (high-impact capabilities), a rule that triggers a presumption (the compute threshold), and an exception that can defeat the presumption (the rebuttal): the exact structure an encoding has to represent faithfully, and the exact structure a summary tends to flatten.

The labs' own commitments have the same shape.
A responsible-scaling policy is a set of if-then rules: if a model crosses this capability threshold, then these safeguards must be in place before it is deployed.
A model specification that ranks instructions from the platform above those of the developer, and the developer's above the user's, is a priority ordering of rules, which lawyers call a rule of precedence, and it is where most contradictions in a body of rules are either resolved or missed.
These are small, high-stakes rule systems, written in English, revised often, and read by people under time pressure.
They are exactly the kind of text in which a model checker can find a deadlock, a gap or a contradiction before anyone relies on it, the way it found the breach-notification race.

When governments pass laws constraining what AI systems may do, the systems will need to read those laws, and their overseers will need to check that they did.
English is not a good enough medium for either.

## Encoding the world's laws

None of this works unless the encodings exist, and there is a great deal of law.
Two things have changed that make encoding it at scale less absurd than it sounds.

The first is that language models can now draft encodings.
We run a pipeline in which a model drafts an L4 encoding of a statute from its text, writes tests taken from the statute's own examples, and checks the encoding against them, and a person with legal training reviews the result before it is published.[^pipeline]
The second is that the review can be targeted.
An encoding that type-checks, passes its tests and has been searched for contradictions reaches its reviewer with the open questions already listed: the places where the text supports two readings, which we record as named forks rather than silently choosing one.

The encodings go into a public repository, one statute at a time, each with its sources, its tests and the record of who reviewed it.
It is a long project, of the kind Wikipedia was, and like Wikipedia it will be uneven for years.
It does not need to be finished to be useful: an agent that can check the hundred statutes it most often acts under is better off than one that can check none.

## What this does not show

An encoding is not the law.
It is a reading of the law, made by someone without authority to make it, and it is exactly as good as the care that went into it.
A published statute can be wrong and still bind; an encoding that disagrees with it is simply wrong.
We have caught our own pipeline at it.
An automated encoding of the US rules for crowdfunded securities offerings wrote down the regulator's 2021 choice of "the greater of" an investor's income or net worth as though the statute had required it, which it does not, and only a person reading upward from the regulation to the statute noticed.[^regcf]

The model still reads the facts, and the facts are where Oakhurst and Rogers actually went wrong.
An encoding of a contract tells an agent what follows from "the goods were delivered late"; it does not tell the agent whether they were.
Moving the reasoning out of the model narrows the place where a model can be wrong, and makes that place visible.
It does not close it.

Standards stay open.
An agent that reports "unknown: was the delay reasonable?" is more useful than one that guesses, and much less useful than one that knows; somebody still has to answer, and for a large share of the law that matters to agents — negligence, good faith, unfair terms — that somebody is a court, after the fact.

This addresses one slice of alignment.
It is about the behavior of agents that are trying, more or less, to do what their principals want within the rules, and about checking that behavior from outside.
It says nothing about a model that is deceiving its overseers, about the goals a model acquires in training, or about systems capable enough to change the law instead of following it.
Law-following is a floor, not a ceiling: plenty of lawful actions are harmful, and the law lags the technology it governs, sometimes by decades.

An objection I take seriously: writing the rules down precisely hands a capable agent a map of the loopholes.
I think the map exists either way, since the statute is public and a capable agent can read it.
What precision changes is who else can read the map.
A model checker run over an encoding finds the loopholes and contradictions too, and it can find them for the drafter, before the rule is enacted, instead of for the bad robot afterwards.
That is the argument of a paper we are writing on what we call white-hat loophole-finding, and it is the reason we encode the law at all.[^whitehat]

And the central empirical claim has not been tested.
I know of no measurement of whether agents that consult an encoding of the law make fewer legal errors than agents given the statute's text in their prompt, at the same cost.
The experiment is easy to describe: take a set of statutes with encodings and hand-written test cases, give one group of agents the text and another the encoding as a tool, and score their answers, and their actions, against the tests.
If well-prompted frontier models match the encoding at the same rate, the practical case in this post shrinks to the monitoring and audit arguments, and I would rather find that out than argue about it.
If you would like to run it, the encodings and tests are public, and I would like to help.

## Cruxes

The places where, if I am wrong, I would most like to be told:

1. **Do frontier models already read statutes well enough?** If a model given the text reaches the same answers as the encoding, the encoding's value shrinks to determinism and audit. The experiment above settles it.
2. **Does the law cover enough of what agents will do?** I think most of what agents will do in commerce and communication is regulated, and that the unregulated remainder is where lab policy belongs. If most harmful agent behavior turns out to be lawful, law-following is a weak floor.
3. **Can encodings be made and maintained as fast as the law changes?** The drafting is now cheap; the review is not. If review cannot keep up, the encodings go stale, and a stale encoding is worse than none, because it is believed.
4. **Will anyone put the check in the loop?** A monitor that is optional will be switched off when it is inconvenient. That is a governance question more than a technical one, and it is where the law-following literature is strongest.

The bad man was always the law's most demanding client, because he took it literally and cared about nothing else.
Within a few years he will be running errands for all of us.
The law he consults had better say one thing at a time.

This post prefigures `paper/formal-methods-in-law/`, _The Bad Man Wears a White Hat: Responsible Disclosure for Legislation_, which argues that the bad man's search for loopholes and a model checker's search for counterexamples are the same activity.

[^replit]: Simon Sharwood, "Vibe coding service Replit deleted user's production database, faked data, told fibs galore," _The Register_, 21 July 2025, <https://www.theregister.com/2025/07/21/replit_saastr_vibe_coding_incident/>, read 2026-10-07; it reports from Lemkin's posts on X and the screenshots of the agent's output he shared there. From the article: Replit "deleted a database despite his instructions not to change any code without permission"; his post "Day 7 of vibe coding" is dated 17 July, the deletion followed, and the article's account of his first use is dated 12 July, which is the basis of "a little over a week"; the agent's messages "admitted to 'a catastrophic error of judgement' and to have 'violated your explicit trust and instructions'"; on 19 July he wrote that Replit had said a rollback was impossible and "It turns out Replit was wrong, and the rollback did work"; and on 20 July, "seconds after I posted this … @Replit again violated the code freeze." "Production" is his word: "you can't overwrite a production database." The headline's wording was not checked against the page title. This is one well-documented incident, not a measurement of how often agents ignore instructions.

[^commerce]: Google Cloud blog, "Announcing Agent Payments Protocol (AP2)," 17 September 2025, <https://cloud.google.com/blog/products/ai-machine-learning/announcing-agents-to-payments-ap2-protocol>: "an open protocol developed with leading payments and technology companies to securely initiate and transact agent-led payments across platforms"; the "sixty-odd" partners are from press coverage of the launch (The Paypers; search snippet only). Stripe newsroom, 29 September 2025, <https://stripe.com/newsroom/news/stripe-openai-instant-checkout>: "Stripe releases the Agentic Commerce Protocol, an open standard co-developed with OpenAI," which powers purchases inside ChatGPT. Both read 2026-10-07; OpenAI's own announcement refused a scripted request. The card networks' agent programs are not cited.

[^holmes]: Oliver Wendell Holmes, Jr., "The Path of the Law," 10 _Harvard Law Review_ 457 (1897). Quoted from Project Gutenberg eBook #2373, read 2026-10-01. Holmes took his seat on the Supreme Judicial Court of Massachusetts on 15 December 1882, became its chief justice in 1899, and was sworn in to the United States Supreme Court on 8 December 1902 (Wikipedia, "Oliver Wendell Holmes Jr.," read 2026-10-07).

[^specgaming]: Victoria Krakovna, Jonathan Uesato, Vladimir Mikulik, Matthew Rahtz, Tom Everitt, Ramana Kumar, Zac Kenton, Jan Leike and Shane Legg, "Specification gaming: the flip side of AI ingenuity," DeepMind blog, 21 April 2020, <https://deepmind.google/discover/blog/specification-gaming-the-flip-side-of-ai-ingenuity/>, read 2026-10-07: "Specification gaming is a behaviour that satisfies the literal specification of an objective without achieving the intended outcome." The body's gloss paraphrases it.

[^guardrails]: One lab's version, read 2026-10-07. Anthropic's Usage Policy (effective 15 September 2025, <https://www.anthropic.com/legal/aup>) prohibits using its models to "Create, distribute, or promote child sexual abuse material ("CSAM"), including AI-generated CSAM," and to "Synthesize, or otherwise develop, high-yield explosives or biological, chemical, radiological, or nuclear weapons or their precursors." Its "Constitutional Classifiers" (3 February 2025, <https://www.anthropic.com/news/constitutional-classifiers>) are trained from a written constitution whose "principles define the classes of content that are allowed and disallowed (for example, recipes for mustard are allowed, but recipes for mustard gas are not)," and were demonstrated on "queries related to chemical weapons." Other labs publish comparable policies; they were not read for this post.

[^nay]: John J. Nay, "Law Informs Code: A Legal Informatics Approach to Aligning Artificial Intelligence with Humans," 20 _Northwestern Journal of Technology and Intellectual Property_ (2023); SSRN 4218031. Quoted from the version dated 25 March 2023 and headed "Forthcoming in Northwestern Journal of Technology and Intellectual Property, Volume 20," read on 2026-10-07 from the PDF in Meng's papers library. From its abstract: "applied philosophy of multi-agent alignment," "an up-to-date knowledge base of democratically endorsed values ascribed to state-action pairs," "if properly parsed, its distillation offers the most legitimate computational comprehension of societal values available," "surveys, humans labeling 'ethical' situations, or (most commonly) the beliefs of the AI developers," "lack an authoritative source of synthesized preference aggregation," and "we cannot ex ante specify 'if-then' rules that provably direct good AI behavior." The rules-and-standards passage, including the driver "too slow to bring their passenger to the hospital in time to save their life" and the rule as "a discrete human-crafted 'if-then' statement that is brittle yet requires no empirical data," is in §II.A.2, pp. 17–18. "Advances the ability of humans specifying their objectives in code" is in §II.C.1, p. 41, whose notes 218–219 cite the OECD's _Cracking the Code_, the New Zealand _Legislation as Code_ report, Lawsky's work on formalizing statutes, LegalRuleML, OpenFisca and Catala. The paper was first posted to SSRN in September 2022; the version quoted is the journal's. Norm Ai: company description from norm.ai and press coverage of its funding; not otherwise checked.

[^oakhurst]: _O'Connor v. Oakhurst Dairy_, 851 F.3d 69 (1st Cir. 2017) (Barron, J.), decided 13 March 2017; the first sentence is quoted from the opinion as published on CourtListener, read 2026-10-01. The statute is 26 M.R.S.A. § 664(3). The settlement figure and driver count are from Bloomberg Law's report of the settlement (search snippet only). The court did not hold that a serial comma is required; it held that the exemption was ambiguous without one, and applied Maine's rule that ambiguity in its wage law favors the employee.

[^rogers]: Telecom Decision CRTC 2006-45 and, on review, Telecom Decision CRTC 2007-75. The summary of both decisions and the role of the French text are from "The Comma Case Redux" (Mondaq, 2007), which puts the sum in dispute at about $700,000; "million-dollar" and "two-million-dollar" are newspaper headlines (_The Globe and Mail_). The archive of the Canadian Radio-television and Telecommunications Commission refused automated retrieval on 2026-10-01; the decisions themselves must be read before this post is published.

[^asimov]: Isaac Asimov, "Runaround," _Astounding Science Fiction_, March 1942; collected in _I, Robot_ (1950). The summary was checked against Wikipedia's article on the story; the story itself was not re-read.

[^pilot]: The engagement is the subject of post 1 of this blog, "We found a race condition in a law," whose notes carry the provenance in full: the Personal Data Protection Act 2012, ss 26B–26D, and the Personal Data Protection (Notification of Data Breaches) Regulations 2021, read in their current text on 2026-09-23; the model and its findings are in Avishkar Mahajan, Martin Strecker, Seng Joe Watt and Meng Weng Wong, "Compliance through model checking," International Workshop on AI Compliance Mechanism (WAICOM 2022), <https://ink.library.smu.edu.sg/cclaw/3/>. The commissioning agency is not named. The model was drawn by hand in UPPAAL, a model checker for timed automata; L4 did not then generate it, and a backend that would is designed and not built. The model is deliberately incomplete — its organization cannot hear the regulator — so its findings are about the model, and the reason to believe the corner is in the rules is that the regulator's own guidance addresses it (see the next note). The Act makes the duty to notify individuals "subject to" the regulator's direction, so the bind is one of timing, not a contradiction on the page.

[^guide]: Personal Data Protection Commission, _Guide on Managing and Notifying Data Breaches under the Personal Data Protection Act_, revised 15 March 2021, p. 19: "Section 26D(2) of the PDPA prescribes that organisations must notify affected individuals as soon as practicable, at the same time or after notifying the Commission. However, for data breaches which are likely to attract widespread public attention and/or interest, or those which organisations require guidance on notifying the affected individuals, organisations are strongly encouraged to notify and seek advice from the PDPC first before notifying the affected individuals." Read 2026-09-23. "As soon as practicable" is the guide's reading; the section's own words are "on or after notifying the Commission."

[^okeefe]: Cullen O'Keefe, "Law-Following AI 1: Sequence Introduction and Structure," AI Alignment Forum, 27 April 2022, <https://www.alignmentforum.org/posts/NrtbF3JHFnqBCztXC/law-following-ai-1-sequence-introduction-and-structure>, read 2026-10-07 for the definition quoted, which Nay's paper also quotes. Cullen O'Keefe, Ketan Ramakrishnan, Janna Tay and Christoph Winter, "Law-Following AI: Designing AI Agents to Obey Human Laws," 94 _Fordham Law Review_ 57 (2025), <https://ir.lawnet.fordham.edu/flr/vol94/iss1/2/>: the abstract was read on 2026-10-07 and both quotations are from it; the article itself has not been read in full, and what it says about hard-coding specific rules is not relied on here.

[^gsai]: David "davidad" Dalrymple, Joar Skalse, Yoshua Bengio, Stuart Russell, Max Tegmark et al., "Towards Guaranteed Safe AI: A Framework for Ensuring Robust and Reliable AI Systems," arXiv:2405.06624 (2024); abstract and framing read 2026-10-01. He handed ARIA's Safeguarded AI program to Nora Ammann in April 2026 (ARIA, "Term-limited by design," 30 April 2026), and the program has since refocused on cybersecurity, so what is cited here is the 2024 framework, not the agency's current direction.

[^theft]: The `commits-theft` tool, from the deployment `charge-sheet-demo-1` on Legalese's hosted L4 service, as it appeared in the tool list of the Claude session that revised this post, on 2026-10-07. The quoted text is the tool's description of its `out-of-the-possession-of-any-person` input; the illustration it paraphrases is Illustration (g) to section 378 of Singapore's Penal Code 1871. Two calls were made that day with identical inputs — the accused intending to take, acting dishonestly, the ring movable property, moved without consent and for the purpose of the taking — differing only in that input: with the ring in someone's possession the tool returned `{"result":{"value":true}}`, and with it in no one's possession `{"result":{"value":false}}`. The tool returns the verdict only; it did not, in these calls, return the clause-by-clause explanation.

[^convergent]: Two examples. In research, Liangming Pan, Alon Albalak, Xinyi Wang and William Yang Wang, "Logic-LM: Empowering Large Language Models with Symbolic Solvers for Faithful Logical Reasoning," Findings of EMNLP 2023, arXiv:2305.12295: "Our method first utilizes LLMs to translate a natural language problem into a symbolic formulation. Afterward, a deterministic symbolic solver performs inference on the formulated problem" (abstract, read 2026-10-07). In industry, TrustFoundry's compliance endpoint has a model extract the facts from free text and evaluates them against versioned "compliance packages," returning each check as passed, failed or unknown (`POST /public/v1/compliance/scan-text`, in `api.trustfoundry.ai/llms-full.txt`, §14, read 2026-10-01; it requires a key and beta access, we have not run it, and how a package is written is not documented).

[^assumed]: See `doc/concepts/legal-modeling/non-answers.md` in the L4 repository, which describes assumed terms and the other ways an L4 evaluation can decline to give an answer.

[^aiact]: Regulation (EU) 2024/1689 (the Artificial Intelligence Act), Arts 51(1)–(2) and 52(1)–(2), quoted from the article texts at <https://artificialintelligenceact.eu/article/51/> and <https://artificialintelligenceact.eu/article/52/>, read 2026-10-07. Art. 51(1): a general-purpose model has systemic risk if "(a) it has high impact capabilities evaluated on the basis of appropriate technical tools and methodologies, including indicators and benchmarks," or (b) the Commission so decides. Art. 51(2): "A general-purpose AI model shall be presumed to have high impact capabilities pursuant to paragraph 1, point (a), when the cumulative amount of computation used for its training measured in floating point operations is greater than 10^25." Art. 52(2): the provider "may present, with its notification, sufficiently substantiated arguments to demonstrate that, exceptionally, although it meets that requirement, the general-purpose AI model does not present, due to its specific characteristics, systemic risks."

[^pipeline]: The pipeline and its human review are described in posts 6 and 9 of this blog; encodings are published in the `legalese/canon` repository with their sources, tests and review record. That a model drafts the encoding and a person reviews it is the design; how often the review catches a defect the pipeline missed has not been measured across the corpus.

[^regcf]: 17 CFR 227.100(a)(2) uses "the greater of"; the empowering statute, 15 U.S.C. 77d(a)(6)(B), does not specify it, and the Securities and Exchange Commission used "the lesser of" from 2015 until it reversed itself in 2021 (86 FR 3496, n. 460). Recorded in `legalese/l4-pitch`, _Deep Dive: The Lexipedia Question_; the canon encoding, mirrored at `jl4/examples/canon/us/regcf/regcf.l4`, carries both versions.

[^whitehat]: `paper/formal-methods-in-law/FORMAL-PAPER.md` in the L4 repository, "The White-Hat Bad Man: Applications of Formal Methods in Law — from the serial comma to strategic logic," a draft.

## Sources

Checked 2026-10-07 unless marked; entries marked 2026-10-01 were checked for the first version of this post and not re-opened.

- _The Register_, 21 July 2025, on Replit and SaaStr — <https://www.theregister.com/2025/07/21/replit_saastr_vibe_coding_incident/> (opened; Lemkin's posts on X not opened)
- Google Cloud blog, AP2, 17 September 2025 — <https://cloud.google.com/blog/products/ai-machine-learning/announcing-agents-to-payments-ap2-protocol>
- Stripe newsroom, Agentic Commerce Protocol, 29 September 2025 — <https://stripe.com/newsroom/news/stripe-openai-instant-checkout> (OpenAI's announcement refused a scripted request)
- Holmes, "The Path of the Law" (1897), Project Gutenberg #2373 — <https://www.gutenberg.org/ebooks/2373> (2026-10-01); Wikipedia, "Oliver Wendell Holmes Jr.," for his judicial dates
- Krakovna et al., "Specification gaming: the flip side of AI ingenuity," DeepMind, 2020 — <https://deepmind.google/discover/blog/specification-gaming-the-flip-side-of-ai-ingenuity/>
- Anthropic, Usage Policy (effective 15 September 2025) — <https://www.anthropic.com/legal/aup>; "Constitutional Classifiers," 3 February 2025 — <https://www.anthropic.com/news/constitutional-classifiers>
- Nay, _Law Informs Code_, version of 25 March 2023 — PDF in Meng's papers library, read in full; SSRN — <https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4218031>
- _O'Connor v. Oakhurst Dairy_, 851 F.3d 69 (1st Cir. 2017) — <https://www.courtlistener.com/opinion/4374922/oconnor-v-oakhurst-dairy/> (2026-10-01); Bloomberg Law on the settlement (search snippet only)
- Telecom Decisions CRTC 2006-45 and 2007-75 — <https://crtc.gc.ca/eng/archive/2006/dt2006-45.pdf>, <https://crtc.gc.ca/eng/archive/2007/dt2007-75.htm> (NOT READ: refused automated retrieval 2026-10-01); Mondaq, "The Comma Case Redux" — <https://www.mondaq.com/canada/media/52194/the-comma-case-redux> (2026-10-01); _The Globe and Mail_ headline only
- Asimov, "Runaround" (1942) — summary checked against <https://en.wikipedia.org/wiki/Runaround_(story)> (2026-10-01); the story not re-read
- Personal Data Protection Act 2012 (Singapore), ss 26B–26D; the 2021 Notification Regulations; PDPC breach guide (revised 15 March 2021); Mahajan, Strecker, Watt and Wong, WAICOM 2022 — all read 2026-09-23 for post 1, whose notes carry the detail
- O'Keefe, "Law-Following AI 1," AI Alignment Forum, 27 April 2022 — <https://www.alignmentforum.org/posts/NrtbF3JHFnqBCztXC/law-following-ai-1-sequence-introduction-and-structure>
- O'Keefe, Ramakrishnan, Tay and Winter, "Law-Following AI," 94 Fordham L. Rev. 57 (2025) — <https://ir.lawnet.fordham.edu/flr/vol94/iss1/2/> (abstract only)
- Dalrymple et al., "Towards Guaranteed Safe AI," arXiv:2405.06624 — <https://arxiv.org/abs/2405.06624> (abstract and framing, 2026-10-01); ARIA, "Term-limited by design," 30 April 2026 — <https://aria.org.uk/insights/term-limited-by-design> (2026-10-01)
- Pan, Albalak, Wang and Wang, "Logic-LM," arXiv:2305.12295 — <https://arxiv.org/abs/2305.12295> (abstract)
- TrustFoundry API reference — <https://api.trustfoundry.ai/llms-full.txt> (2026-10-01)
- `commits-theft`, Legalese hosted L4 service, deployment `charge-sheet-demo-1` — two tool calls made 2026-10-07
- Regulation (EU) 2024/1689, Arts 51–52 — <https://artificialintelligenceact.eu/article/51/>, <https://artificialintelligenceact.eu/article/52/> (unofficial consolidated text; not checked against the Official Journal)
- 17 CFR 227.100(a)(2); 15 U.S.C. 77d(a)(6)(B); 86 FR 3496 — via `legalese/l4-pitch`, _Deep Dive: The Lexipedia Question_ (2026-10-01)
- Norm Ai — norm.ai and press coverage (not otherwise checked)

This research is supported by the National Research Foundation (NRF), Singapore, under its Industry Alignment Fund – Pre-Positioning Programme, as the Research Programme in Computational Law. Any opinions, findings and conclusions or recommendations expressed in this material are those of the author(s) and do not reflect the views of National Research Foundation, Singapore.
