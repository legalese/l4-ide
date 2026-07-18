# Seeing Like a Citizen

## The political economy of legal legibility, and the population-scale legal supply-chain attack

> **Status:** DESIGN — a new facet of the L4 papers series, hived off from the
> formal-methods-in-law paper (facet 5) on 2026-07-15. This is the **political-economy /
> security-policy** facet: the "why it matters at the level of the state" argument that the
> technical facets serve. Working title above; venue TBD (governance / law-&-tech-policy /
> national-security-law crossover).
>
> **Provenance:** grew out of verifying the AND-ambiguity case citations for
> `SET-OPERATORS-SPEC.md`, where a foundational precedent (_Re Best_ [1904] 2 Ch 354) turned out
> to be unreachable on any free database and others (_Royal Trust_, _Chichester_) had to be prised
> out of BAILII by driving a browser through an anti-scraper wall. The lived experience _is_ the
> paper's opening.

---

## 0. One-line thesis

**Legal legibility is critical civic infrastructure. When a sovereign under-provisions it, nature
abhors a vacuum — and the entity that fills the gap acquires quiet power over how a population
understands its own obligations. That filling ranges, on a single spectrum, from benign private
capture to a deliberate population-scale supply-chain attack. The defence is not "trust the
provider" but sovereign, machine-readable, cryptographically-provenanced law plus _auditable_
reasoning — which is what an L4-style stack is for.**

## 1. The setup: the Bad Man must be a Rich Man

Holmes's Bad Man is a **universal epistemic test** — you learn what the law _is_ by asking what it
does to the person who cares only about consequences. The test presupposes the law is _knowable_.
_Ignorantia juris non excusat_ has moral force only if the _juris_ is actually readable.

But the primary sources are enclosed. Case reports sit behind Westlaw / ICLR / HeinOnline;
standards incorporated by reference into regulation are copyrighted; even the _findability_ layer
(West Key Numbers, Shepard's) is proprietary. So the Bad Man must be a **Rich Man** before he can
run the test at all. (Carl Malamud / public.resource.org has fought exactly this: _Georgia v.
Public.Resource.Org_, 590 U.S. 255 (2020), extended the **government-edicts doctrine** to
legislator-authored annotations; the ASTM incorporation-by-reference litigation is the starkest
case, where a copyrighted private standard _is_ the binding law.)

**The lived vignette (the paper's cold open):** verifying three charity-law precedents for a
formal-methods spec, we found _Re Best_ [1904] 2 Ch 354 — cited by the House of Lords, taught in
every trusts course — on **no** free database; _Royal Trust_ [1986] UKPC 34 survived only as an
image-scanned PDF with no text layer at an unguessable filename; and BAILII, itself a
_free-access-to-law charity_, now sits behind an **Anubis proof-of-work wall** to fend off
scrapers and AI harvesters. Douglas Adams's "Beware of the Leopard": the notice was on display —
just not _accessible_. **Free law is under-funded law**, and under-funding degrades into
inaccessibility even where nobody intends it.

## 2. The move: from access-to-law grievance to political economy

### 2.0 The epigraph (the whole argument in eight lines)

> Western economies circa 2000: "we don't care about manufacturing."
> China: "ok."
>
> Western polities circa 2030: "citizens will get their legal advice from whatever AI hands it out
> for free."
> Russia: "ok."

This is the paper in miniature, and it is **not** merely rhetorical — it is a claim that legal
legibility is a **strategic capability** subject to the same offshoring dynamics that hollowed out
Western industrial capacity, and that we already have the historical template for how the abdication
plays out and how ruinously expensive the correction is.

### 2.1 The manufacturing template: strategic dependency as political economy

The offshoring logic circa 2000 was Ricardian and seemed unanswerable: manufacturing is
low-margin, commoditized "dirty assembly"; keep the high-value design/IP, let others do the rest.
What that logic missed is that capability is an **ecosystem, not a line item**. When the factories
go, so do the supplier networks, the skilled workforce, and — decisively — the _tacit process
knowledge_ that cannot be written down and cannot be repurchased on demand (Pisano & Shih,
_Producing Prosperity_ / "the industrial commons"). The bill arrived late and all at once: PPE in
2020, semiconductors, rare earths, pharmaceutical precursors — and the corrective (CHIPS Act,
reshoring, friend-shoring) costs orders of magnitude more than the capability would have cost to
keep.

The relevant literature is **International Political Economy**, and it is directly portable:

- **Hirschman, _National Power and the Structure of Foreign Trade_ (1945):** asymmetric dependence
  _is_ power — the less-dependent party holds coercive leverage over the more-dependent one, whether
  or not it ever "uses" it.
- **Farrell & Newman, "Weaponized Interdependence" (2019):** in networked systems, whoever controls
  the **chokepoints** gains two capabilities — the **panopticon** (see everything that flows
  through) and the **chokepoint** (shape or deny it). A dominant free legal-AI layer is _exactly_
  such a node: it **sees** every citizen's legal question and **shapes** every answer.

**Legibility is a strategic capability, and it can be offshored by neglect.** "We don't care about
manufacturing" and "citizens can get legal advice from free AI" are the same sentence twenty years
apart — the abdication of a capability that looks like a cost centre until the day it is revealed to
have been infrastructure.

### 2.2 Why the legal case is _worse_ than the manufacturing case

The analogy is precise, but the disanalogies all cut the wrong way:

1. **No empty shelf.** Manufacturing dependence produces a _visible, meterable_ signal — when the
   ships stop, the shelves are bare (2020 PPE was legible overnight). A poisoned legal-advice layer
   produces **no such signal**: nobody samples enough to notice the 0.5%, and each wrong answer is
   deniable as ordinary error. The feedback loop that _eventually_ forced the manufacturing
   reckoning is **absent**.
2. **"Free" is stronger gravity than "cheap."** Offshoring was driven by cost, so there was at least
   a price signal to weigh. The legal-AI vacuum is filled by _free_ — there isn't even a number on
   the tradeoff, so nobody is ever prompted to make it.
3. **No TSMC to point at.** Semiconductors got a policy correction because the risk became
   **legible and attributable** (concentration in one firm, one island). The legal-epistemic risk is
   **diffuse and unattributable** — no single chokepoint to galvanize a CHIPS-Act moment — so the
   correction, if it comes, comes even later.

Together: the legal case has manufacturing's strategic-dependency structure, minus every feedback
mechanism that made the manufacturing mistake eventually self-correcting. That is the argument for
acting _before_ the empty shelf, because here there will never be one.

### 2.3 The move

The access-to-law literature usually stops at grievance ("this is unjust / inefficient"). The
contribution here is to treat legibility as **infrastructure with a supply chain**, and to ask the
political-economy question: _if the sovereign won't provision it, who will, and on what
incentives?_

**Nature abhors a vacuum.** A population's demand to understand its own obligations does not
disappear when the state fails to meet it; it gets met by whoever has the incentive and capability.
The identity and incentives of that filler are the whole story.

### Inversion of Scott

James C. Scott's _Seeing Like a State_: states impose **legibility on populations** — cadastral
maps, surnames, standardized weights — for taxation and control. This paper is the **dual**: the
citizen's need to make the **state** legible to _them_. Call it **Seeing Like a Citizen**. The
failure mode Scott studies is over-legibility imposed downward; the failure mode here is
**under-legibility** withheld upward, and its consequence is not oppression but **dependence on an
intermediary** — and dependence is an attack surface.

## 3. The spectrum of gap-fillers (the core figure)

One axis, from most-aligned to most-adversarial. The point is that these are **the same
structural position** — the legal-understanding intermediary — differing only in the operator's
incentives.

| Filler                                                            | Incentive                                          | Failure mode                                                                    | Accountability           |
| ----------------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------- | ------------------------ |
| **The sovereign itself** (rules-as-code, official reasoner)       | legitimacy, compliance, efficiency                 | under-provision → the vacuum                                                    | democratic, in principle |
| **Big tech "organizing the world's information"**                 | ads/attention, platform lock-in, obeying a mission | private capture of a public function; opacity; the findability moat re-enclosed | market + regulator, weak |
| **Open / civic (public.resource.org, BAILII, an open L4 corpus)** | mission, public good                               | under-funding → inaccessibility (§1)                                            | community, fragile       |
| **A free-beer high-accuracy advice service**                      | build trust, achieve scale, then… ?                | _depends entirely on the operator_                                              | none, if anonymous       |
| **A state-sponsored adversary** operating the same free service   | steer outcomes at population scale                 | the poisoned 0.5% (§4)                                                          | none, by design          |

The unsettling claim: **the benign and the malicious fillers occupy the identical socket.** A
free, anonymous, 99.5%-accurate legal/tax advisor is indistinguishable, from the user's chair,
from the same service run as a weapon. Adoption is driven by the 99.5%; the danger lives in the
0.5%.

### 3.1 The barrier to entry has already collapsed (existence proof)

This spectrum is not a forecast; its lower rows are **buildable today by one person**. **Legal Data
Hunter** — 230+ jurisdictions, 38M+ documents, a working legal-research back-end — was, per its
provenance, stood up by **a single non-programmer in about a month**, on the back of
AI-assisted development. That is the whole argument for why the vacuum _will_ be filled: the cost
of standing up a plausible, wide-coverage legal-advice layer has fallen to roughly one motivated
individual and a weekend's worth of API spend. When the marginal cost of a filler approaches zero,
the only question left is _whose_ filler wins adoption — and adoption is won by _free_ and
_fluent_, not by _accountable_ or _auditable_.

## 4. The population-scale legal supply-chain attack (the novel core)

### 4.1 Why 99.5% is the dangerous number, not 70%

A service wrong 30% of the time is abandoned — it never becomes load-bearing. A service **right
99.5% of the time becomes civic infrastructure**, relied on by millions who cannot check it. _Then_
the 0.5% is not error but **a precision-guided munition**: the high baseline manufactures the trust
that makes the rare poisoned answer land. This is the exact structure of a **software supply-chain
attack** — a dependency trusted precisely because it is _almost always_ correct.

### 4.2 The canonical analogy: xz-utils / SolarWinds

The threat model is not hypothetical; it is **ported**, not invented. The **xz-utils backdoor**
(CVE-2024-3094, 2024) is the perfect template: a patient actor social-engineers a trusted position
in a near-universal dependency over _years_, then ships a backdoor that would have been invisible
to almost every downstream consumer. **SolarWinds** (2020) is the enterprise version. The paper's
move is to observe that **legal understanding is now acquiring a dependency graph too** — a small
number of advice services, models, and cited "authoritative sources" that a population imports
without inspection — and that this graph has **no equivalent of code review, provenance, or
reproducible builds.**

### 4.3 Where subtle wrongness pays

Targets where a rare, plausible, wrong answer converts to strategic effect:

- **Tax**: steer structuring to erode a rival state's revenue base, or to create latent liabilities.
- **Benefits / immigration**: manipulate eligibility beliefs at scale (chilling or over-claiming).
- **Electoral / campaign-finance law**: subtly wrong deadlines, thresholds, disclosure rules.
- **Limitation periods**: the cruelest — advice that quietly runs a claimant past a statutory
  deadline is unrecoverable and looks like the user's own fault.
- **Corporate / regulatory compliance**: seed latent breaches that mature on the attacker's clock.

The signature is **plausible, individually-deniable, rare, and aimed at civic chokepoints.** No
single wrong answer proves malice; the _distribution_ does.

### 4.4 Why it is hard to detect — and what that implies

The attack is hard to detect _because_ it is rare and plausible: no user samples enough to notice,
and each poisoned answer is defensible as ordinary model error. Detection therefore needs a
**differential oracle** — an independent, authoritative source to cross-check against. That is
precisely what a **sovereign formal model of the law + property assertions** provides: run the
neural answer against the re-executable formal source and flag divergence. **The defence against a
poisoned neural advisor is an auditable symbolic one.**

### 4.5 You do not have to build it, or even hack it — you can _buy_ it

The cheapest compromise is not the years-long social-engineering of xz-utils (§4.2). It is an
**acquisition**. Let the vacuum be filled organically by an independent, genuinely useful,
widely-adopted service — the lone builder's Legal Data Hunter, ten years on and load-bearing — and
then simply **buy the company**. No intrusion, no zero-day, no maintainer to burn out and
replace: a lawful M&A transaction transfers the chokepoint, its user base, and its trust intact.

**Precedent:** _LiveJournal._ Built in the US (Brad Fitzpatrick, 1999), sold to Six Apart, then in
2007 to **SUP Media (Russia)**; by 2016 its servers had physically moved to Russia and its users
fell under Russian jurisdiction, data law, and content rules — with real consequences for the
dissident and LGBT communities that had relied on it. A Western-built social platform passed into a
rival jurisdiction's control **by purchase**, quietly, years after the trust was established.
_"Whoever bought LiveJournal could buy LDH."_

This is the **xkcd 2347 ("Dependency")** failure class made geopolitical: a population's
understanding of its own law comes to rest on "a project some random person has been thanklessly
maintaining," which is exactly the fragile, acquirable, single-maintainer node that xz-utils
proved can be captured. The convergence is the point — **xkcd 2347 named the vulnerability class;
xz-utils realized it in code; the legal-AI layer reproduces it for civic knowledge.**

The acquisition vector also **splits the payoff**, and the quieter half is the more valuable:

- **Chokepoint (shape answers):** adjust the poisoned 0.5% (§4.1–4.3). High impact, some detection
  risk.
- **Panopticon (harvest questions):** the intelligence value of seeing _every_ citizen's, firm's,
  and official's legal and tax questions — who is exposed, who is about to litigate, which
  ministry is quietly researching which liability — is a strategic asset on its own, extracted with
  **near-zero detection risk and no need to alter a single answer.** This is the panopticon half of
  weaponized interdependence (§2.1), and an acquisition delivers it for the price of a startup.

**Why this is the strongest argument _for_ the §5 defence, not just a scarier threat.** You cannot
stop the lone builder's tool from one day being bought by a hostile power; ownership is lawful and
mobile. What you _can_ do is make it **not matter** — by relocating trust from the _operator_ to
the **sovereign-signed source and the auditable trace**. If every "the law says X" is checkable
against a state-signed artifact and ships a re-executable derivation, then it is immaterial who owns
the front-end: a captured service either keeps telling the truth (checkable) or diverges
(detectable). The acquisition vector is precisely the threat that operator-level trust cannot
answer and source-level provenance can — which is the whole case for building the defence at the
_source_, not the _service_.

### 4.6 The root of the supply chain: the training corpus (the shadow-library problem)

There is a layer below the service and below the acquisition: the **corpus the models learned law
from.** Modern legal AI is trained, in part, on **shadow libraries** — and the largest aggregator,
**Anna's Archive** (pseudonymous "Anna," launched 2022 after the Z-Library seizures, mirroring
Library Genesis / Sci-Hub / Z-Library and scraped metadata), has explicitly positioned itself as
**AI training-data infrastructure**, offering bulk access to its collection to model builders. Its
mission is the noblest version of §1's grievance: free the paywalled knowledge, preserve the human
record.

Now pose the paper's most uncomfortable question: **what if the curator of the corpus is a hostile
intelligence asset?** Not "what if the advice service is captured" (§4.5) but "what if the _books
the models read to learn the law_ were curated by an adversary." That is **training-data
poisoning at the root** — it needs no service, no acquisition, no live 0.5%; it biases the
_prior_ of every downstream model that trained on the corpus, deniably, years upstream of any
answer, under the halo of preserving human knowledge.

**Frame this carefully.** This is a **structural** claim about _unverifiability_, not an
allegation about any actual person: the point is precisely that the provenance of a **pseudonymous,
unaccountable corpus curator cannot be verified**, so the threat holds _whoever_ Anna actually is.
"What if Anna works for the FSB?" is unanswerable by design — and a dependency whose trustworthiness
is _unfalsifiable_ is, for a security argument, already compromised.

### 4.7 The uncomfortable symmetry: the paper's heroes are the threat archetype

This is where the argument turns on itself, and it must, to be honest. §1 lionizes the
free-knowledge liberator — Malamud, BAILII, the open corpus, and yes, the shadow-library archivist.
But that liberator and the §4.5–4.6 attacker are **the same archetype**: the unaccountable,
unattributable, free-at-the-point-of-use provider of a civic knowledge good. The very virtues that
make the hero lovable — pseudonymity, independence, mission-over-profit, giving it away — are
_exactly_ the properties that make provenance unverifiable. **The socket does not care who is
plugged into it** (§3), and neither Malamud's good faith nor Anna's mission statement is a
_check_ — it is a _reputation_, and reputations are acquirable, coercible, and pseudonymous.

The resolution is the paper's spine, stated at its sharpest: **the answer is not to find a provider
you can trust; it is to build a system in which you do not have to.** Relocate trust from the
_provider's identity_ to the **sovereign-signed source and the re-executable trace**, and the
question "is Anna FSB?" — like "is the lone Frenchman's startup about to be bought?" — becomes
**moot**, because the claim is checkable against a signature the provider does not control. A
security argument that depends on the loyalty of a pseudonym has already lost; one that depends on
a verifiable signature has not. That is why the defence lives at the source, not the service, and
not the saint.

### 4.8 The motive loop: enclosure manufactures its own liberators

Why should the vacuum be filled by an actor _hostile_ to the West rather than a neutral one? Because
**the motive and the position share a root.** The free-knowledge liberator archetype has a natural
home in the **post-Soviet intelligentsia** — the samizdat tradition of circumventing information
control is a century deep, the largest shadow libraries (Library Genesis' Russian-language origins;
Sci-Hub, founded 2011 by Alexandra Elbakyan) grew there, and the people locked _out_ by Western
paywalls had every reason to tear them down. Crucially, **their grievance is legitimate.** The
Western academic-industrial complex — Elsevier and the journal oligopoly, Westlaw and the
legal-reports cartel — extracts rents on knowledge that authors and reviewers produce unpaid and
that prices non-Western scholars out entirely. The liberator is not a false-flag; they are a
**true-flag** — genuinely motivated, genuinely admirable — who _also_ happens to serve a rival's
interest. That is far more dangerous than a fake, because the halo is _earned_.

And here is the sting: **the heirs of the Cold War owe no allegiance to the Western
academic-industrial complex, and the West gave them the reason.** Sharing the anti-enclosure
_value_ is not sharing Western _loyalties_, and the paywall cartel conflates the two at its peril.
Decades of rent-seeking enclosure **manufactured the West's own liberators and handed them a halo**:
the scholarly-paywall cartel created Sci-Hub; the legal-paywall cartel (Westlaw / ICLR / the
enclosed findability layer) will create the legal Sci-Hub — and it will be built, quite reasonably,
by actors who feel no obligation to protect the institutions that enclosed the knowledge in the
first place.

So the enclosure is a **self-inflicted strategic wound**, and it rhymes exactly with the
manufacturing epigraph (§2): just as offshoring was short-term cost logic that ignored strategic
capability, knowledge-enclosure is short-term rent extraction that ignores strategic capability. The
academic-industrial complex is the CFO who offshored the factory — except the "factory" here is a
population's ability to understand its own law, and the low-cost overseas supplier it got outsourced
to owes the West nothing.

## 5. The constructive half: what closes the attack surface

The paper must not be only a warning; it must name the defence, and the defence is the L4 thesis
restated as security policy:

1. **Sovereign machine-readable law.** The state publishes its statutes/regulations as
   authoritative, openly-licensed, machine-readable source (rules-as-code; the OECD prophecy). This
   removes the _economic_ vacuum — free-beer fillers no longer own the only convenient copy.
2. **Cryptographic provenance.** The authoritative source is **signed by the sovereign**. An advice
   service's claim "the law says X" becomes _verifiable_ against a state-signed artifact, not taken
   on the operator's word. This is the supply-chain fix (provenance / SBOM) applied to law.
3. **Auditable reasoning, not opaque verbalization.** Advice must ship an **explanation trace** —
   a citation-linked, re-executable derivation — not just a fluent paragraph. A poisoned LLM gives
   a plausible answer with no verifiable trace; an L4-backed reasoner gives a derivation you (or a
   watchdog) can check against the signed source. **Auditability is therefore a _democratic
   defence_, not a UX nicety** — arguably the paper's sharpest single claim.
4. **The neural/symbolic division of labour** (ties to the origin conversation): the LLM is the
   accessible right-brain front-end; the sovereign formal model is the left-brain guardrail that
   constrains it. The 99.5% comes from the neural fluency; the missing 0.5%-of-safety comes from
   binding every answer to the signed, auditable source.

**Epistemic sovereignty.** "Sovereignty" over law usually means the state's _authority to make_ it.
This paper argues for a neglected second sense: the state's **duty to make its law legible to its
own citizens** as a component of legitimacy _and_ of national security — because the alternative is
to leave a population-level dependency wide open to whoever fills the gap.

### 5.1 The convergence (the political payoff)

The motive loop (§4.8) has a constructive mirror. You cannot _fight_ the liberators — their
grievance is just, and litigating shadow libraries only confirms the enclosure that created them
(the scholarly-paywall cartel has been suing Sci-Hub for a decade; it still exists). You **dissolve
the vacuum** instead: a sovereign that publishes its own law _free, authoritative, signed, and
machine-readable_ removes the grievance and the dependency **in the same act** — there is no rent to
resent and no unaccountable layer to weaponize, because the authoritative copy is already the free
one.

That yields the paper's political money shot: **the access-to-justice reformer and the
national-security hawk want the identical policy for opposite reasons.** The left wants sovereign
open law to end the Rich-Man injustice (§1); the right wants it to close the supply-chain
vulnerability (§4). Open, signed, authoritative provision is where those two arrive together — a
genuinely trans-ideological mandate, which is exactly the kind that gets funded. The enemy of the
access-to-justice problem and the enemy of the security problem turn out to be **the same enemy:
enclosure.**

The convergence is even instantiated in the funding landscape: the security pole has its investor
(**In-Q-Tel**, the US intelligence community's strategic venture arm) and the open-society pole its
philanthropy (the **Open Society Foundations**, descended from Popper's _The Open Society and Its
Enemies_). That both would plausibly back open-law infrastructure, for opposite reasons, is the
thesis made literal — **but for _this kind of project_ that symmetry is a trap, not an opportunity;
see §7 (self-referential integrity).**

## 6. Relationship to the rest of the series

- This is the **"why it matters" facet**: the political economy the technical facets serve.
- The **detect≠resolve / auditability** theme (Poh Yuan Nie keystone; formal-methods facet §6 "The
  Missing Test Suite") reappears here as a _security property_: the auditable trace is the
  differential oracle of §4.4.
- The **ambiguity-detector** work (`SET-OPERATORS-SPEC.md`; empty-intersection lint = _Royal
  Trust_'s otiosity canon automated) is a concrete instance of "the sovereign source can catch what
  the fluent advisor smooths over."
- Hives **off** facet 5 (formal-methods-in-law): that paper keeps the _technique_ (white-hat Bad
  Man, model-checking-as-exploit-finding); this paper takes the _political economy_.

## 7. Open questions / risks for the argument

- **Overclaim check — now substantially answered (§3.1, §4.5, §4.6).** The "why is this real /
  why this vector" objection is met on three fronts: the **barrier to entry has already
  collapsed** (Legal Data Hunter as existence proof — one person, one month), so the fillers are
  cheap and plentiful; the cheapest compromise is a **lawful acquisition** (LiveJournal precedent),
  not a costly intrusion; and the deepest is **training-corpus capture** (Anna's Archive as
  upstream infrastructure), which needs no service at all. Why _this_ vector over ordinary
  disinformation: legal advice is uniquely **trusted, actionable, individually-deniable, and
  unattributable** — it is _acted on_, not merely believed. Residual work: still owe one concrete,
  costed end-to-end attack path written up as a worked example.
- **Base-rate honesty.** Human legal advice is not 100% either; the paper must not pretend the
  status quo is safe. The argument is about _who controls the error distribution_ and _whether it
  is auditable_, not about achieving zero error.
- **Does provenance actually help lay users?** A signed source only defends those who (or whose
  tools) check the signature. Needs the auditable-reasoner UX to make verification automatic, or the
  defence stays theoretical (the same critique L4's explainability faces).
- **Self-referential integrity — the project's own funding provenance is subject to this paper's
  thesis.** The convergence (§5.1) tempts the obvious patrons — In-Q-Tel for the security pole,
  Open Society for the access pole. But §4.7 applies to the _tool-builder_ too: a claim to be a
  sovereign-grade _neutral_ trust layer cannot survive being funded by a spy agency or a
  globally-polarizing financier, because the tool inherits the funder's enemies and refutes its own
  neutrality. In-Q-Tel money makes an open-law reasoner read as a Western-intelligence instrument —
  poisoning adoption in exactly the non-aligned jurisdictions and man-on-the-street personas it
  needs; Open Society money makes it "Soros-funded," a lightning rod for the populist right and for
  the very governments that have expelled OSF. The consistent answer is the _same_ as the technical
  one: **don't seek a trustworthy patron; make trust structural** — transparent, multilateral /
  sovereign, open-licensed, reproducible funding whose identity nobody has to trust (national
  legislative-drafting offices and GovTech, the OECD rules-as-code programme, EU digital-public-
  infrastructure funds, research councils, open-source foundations). **Dogfood the thesis: fund the
  trust infrastructure the way you would tell a state to publish its law — openly, verifiably, owned
  by no single interested party.**
- **Venue and register.** Governance/policy journal vs. law review vs. security-policy crossover.
  The supply-chain framing may travel best in a law-&-national-security forum; the Malamud/Scott
  framing in a governance/access-to-justice one. Possibly two sibling pieces.

## 8. Candidate titles

- _Seeing Like a Citizen: Legal Legibility and the Population-Scale Supply-Chain Attack_
- _The Bad Man Must Be a Rich Man: Access to Law as Critical Infrastructure_
- _Epistemic Sovereignty and the Legal Supply Chain_
- _Nature Abhors a Vacuum: Who Explains the Law When the State Won't_
