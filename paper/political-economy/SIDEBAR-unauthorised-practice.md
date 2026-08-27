# Sidebar: Who is allowed to subsume?

## Unauthorised practice as the supply-side enclosure

> **Status:** SIDEBAR to [`DESIGN.md`](DESIGN.md) — captured 2026-08-27 from a discussion arising
> out of the SMU seminar deck's chapter 1 (subsumption, the legal syllogism). Not yet worked into
> the paper's body; the natural seam is between §4.8 (_the motive loop_) and §5 (_the constructive
> half_), because it is a **second** enclosure of the same kind, on the other side of the market.
>
> **Sources actually read** (this matters — see the "unchecked" list at the end): the Legal
> Profession Act 1966 (Singapore), ss 32–36 and s 77, full text from the lawplain `statutes`
> corpus, current as amended by Act 37 of 2023 wef 17/07/2024; _Choo Cheng Tong Wilfred v Phua
> Swee Khiang_ [2021] SGHC 154 at [6] and [77]–[80]; _Public Prosecutor v Lim Tean_ [2026] SGHC 44
> at [67]. **Legal information, not legal advice**, and this is a policy note, not an opinion on
> anybody's exposure.

---

## 0. The point in one line

**The paper's gap-fillers (§3) are, every one of them, unlicensed.** The corpus-side enclosure
(paywalls, §1) is only half the wound; the other half is a **supply-side** enclosure that makes it
an offence for anyone but a licensed professional to do the one thing a legal-reasoning system
exists to do — apply a rule to a person's facts. And the enclosure binds asymmetrically: it binds
the accountable filler and not the adversarial one.

## 1. What the statute actually says

Singapore has **no general "practice of law" offence.** There is no provision anywhere in the LPA
that prohibits "applying law to another person's facts" — the American formulation. What there is
instead is an enumerated list, in **s 33**, of acts an "unauthorised person" (defined in s 32(2):
not on the roll with a practising certificate) may not do:

| Provision  | Prohibited act                                                                                                                              | Paid?                           |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| s 33(1)(a) | acts as an advocate or solicitor **or an agent for any party to proceedings**; sues out process; conducts an action; drafts court documents | **irrelevant — no fee element** |
| s 33(1)(b) | holds out as qualified                                                                                                                      | irrelevant                      |
| s 33(2)(a) | draws or prepares any document or instrument relating to movable/immovable property, or to any legal proceeding                             | **reverse burden** — see below  |
| s 33(2)(b) | takes instructions for, or prepares, probate / letters of administration papers                                                             | reverse burden                  |
| s 33(2)(d) | sends a letter threatening legal proceedings on a claimant's behalf                                                                         | reverse burden                  |
| s 33(2)(e) | negotiates or settles a personal-injury or death claim                                                                                      | reverse burden                  |
| s 33(3)    | for reward, offers to place a solicitor's services at another's disposal                                                                    | **fee is an element**           |

Three things about that table are worth more than the table.

**(a) "Paid" is a defence, not an element — and only for s 33(2).** The s 33(2) offences are made
out **"unless he or she proves that the act was not done for or in expectation of any fee, gain or
reward"**. That is a persuasive burden on the defendant, not something the prosecution must
establish. And it does not appear in s 33(1) at all: **acting as an advocate and solicitor for
free is still the offence.** The common intuition that free legal help is safe and paid legal help
is not gets both the placement and the direction of the burden wrong.

**(b) The Act never says "legal advice".** The phrase occurs **zero** times in the whole statute
(grepped, not recalled). "Advice" appears only in the title of the Legal Aid and Advice Act 1995,
in the arbitration carve-out at s 35(1)(c), and in the foreign-lawyer/SICC permissions. Whatever
catches advice-giving, it is not an express prohibition on advice.

**(c) Wills are carved out.** s 33(10): "document" and "instrument" in s 33 **do not include** a
will or other testamentary document. So preparing a will is outside s 33(2)(a) — while preparing
the probate papers afterwards is squarely inside s 33(2)(b). This is not a small detail for
document-automation: the single most-automated consumer legal document in the world sits in an
express statutory hole.

## 1a. s 33(2) up close — the paragraph that actually reserves paperwork

s 33(2)(a) is the provision that corresponds to the intuitive formulation ("the paid generation of
executable paperwork"), and it repays a slow read. Verbatim:

> **(2)** Without limiting subsection (1), any unauthorised person who, **directly or indirectly** —
> **(a)** draws or prepares any **document or instrument relating to any movable or immovable
> property or to any legal proceeding**;
> **(b)** takes instructions for or draws or prepares any **papers** on which to found or oppose a
> grant of probate or letters of administration;
> **(c)** _[Deleted by Act 8 of 2011]_ > **(d)** on behalf of a claimant … writes, publishes or sends a **letter or notice** threatening
> legal proceedings other than a letter or notice that the matter will be handed to a solicitor …;
> or
> **(e)** solicits the right to negotiate, or negotiates in any way for the settlement of, or
> settles, any claim arising out of personal injury or death …,
>
> shall, **unless he or she proves that the act was not done for or in expectation of any fee, gain
> or reward**, be guilty of an offence.

Five observations, in rough order of how much they matter to a software system.

**(i) "directly or indirectly" appears here and nowhere else in s 33.** s 33(1) has no such words.
The phrase is the classic reach-through, aimed at the unlicensed operator who has someone else hold
the pen. Whether it reaches a _tool_ — as opposed to a person acting through another person — is
the central undecided question for document automation, and nothing in the Act answers it.

**(ii) The scope of (a) is enormous on its face.** "Any document or instrument relating to any
movable or immovable property or to any legal proceeding" — read literally, almost every commercial
agreement relates to movable property: a sale of goods, an equipment lease, a charge, an assignment,
a licence. On its face (a) reserves **general contract drafting**. Compare the English "reserved
instrument activities", which are tied narrowly to dispositions and registration of _land_. Singapore
did not draft a narrow reservation and then widen it; it drafted a wide one and has been carving
exemptions out of it one profession at a time (see (v)).

**(iii) And it is essentially unlitigated.** A search of the lawplain `judgments` corpus for the
operative words of (a) returns **exactly one** hit — _Choo Cheng Tong_, quoting it in passing while
deciding a case that turned on other limbs. Nobody has litigated what "relating to" means at the
edge. The broadest paragraph in the section has no case law defining its outer boundary, which cuts
both ways: no authority has confirmed the wide reading, and none has cut it down either.

**(iv) The reverse burden is where "free" actually matters.** "Unless he or she proves" is a
persuasive burden on the defendant. So under s 33(2) the shape is: the prosecution establishes that
you indirectly prepared a document relating to property; **you** must then prove, on the balance of
probabilities, that you did it without expectation of fee, gain or reward. A commercial vendor
cannot discharge that. A genuinely free tool can. This is the one place in the section where the
free/paid distinction does real work — and it is the exact opposite of s 33(1), where free is no
defence at all. Note the perverse alignment with §3 of the paper: **the statute is most permissive
towards precisely the free, unaccountable filler, and least permissive towards the one with a
business model, a company, and an address.**

**(v) Three exemptions in s 34(1) bite specifically on (a), and one of them is the interesting one.**

- **s 34(1)(k): "any person merely employed to engross any instrument or proceeding."** To _engross_
  is to produce the final fair copy. This is the closest thing in the Act to a document-assembly
  carve-out, and it is drawn along exactly the line computational law cares about: it protects the
  party that **renders** without **choosing**. A template filler is an engrosser; a system that
  selects which clause the facts require is not obviously one. If any existing words in the LPA are
  going to be argued over by a document-automation vendor, these are they.
- **s 34(1)(i): accountants** drawing or preparing documents in the exercise of their profession.
- **s 34(1)(m): trade mark agents** drawing or preparing documents in trade mark matters.

**(vi) A drafting detail worth having: the will carve-out lands on two paragraphs only.** s 33(10)
says "document" and "instrument" do not include a will or other testamentary document (or a transfer
of stock containing no limitation). Those two nouns are the operative words in **s 33(1)(a)(iii)**
and **s 33(2)(a)** — and nowhere else in s 33. Paragraph (b) says "**papers**", (d) says "**letter
or notice**". So the exclusion trims the two general document paragraphs and leaves probate work
fully caught. Whether that is design or accident, the effect is precise: **you may draft the will;
you may not prepare the papers to prove it.**

**Unresolved: what paragraph (c) used to say.** It was deleted by Act 8 of 2011 — the same Act that
added the s 34(2) exemption power and the s 34(1)(ec) in-house-counsel carve-out, which suggests a
single liberalising pass. I could not establish its former text: Singapore Statutes Online refuses
automated requests, and two public mirrors were dead (certificate mismatch and 404). Resolve it from
SSO's version history for LPA1966, or from the amendment Act itself at
`sso.agc.gov.sg/Acts-Supp/8-2011`. **Do not guess at it** — a repealed paragraph in a penal
provision is exactly the kind of claim that gets copied and sharpened.

## 2. The general limb, and the two Turner tests

s 33(1)(a) does open with an unenumerated limb — "acts as an advocate or a solicitor" — and that is
where the American intuition gets its purchase. It is read through **_Turner (East Asia) Pte Ltd v
Builders Federal (Hong Kong) Ltd_ [1988] 1 SLR(R) 281** (Chan Sek Keong JC), as set out in _Choo
Cheng Tong_ at [79]:

> **(a)** Other than those specific acts listed [in what is now s 33], an act is an act of an
> advocate and solicitor when it is customarily (whether by history or tradition) **within his
> exclusive function** to provide, eg **giving advice on legal rights and obligations**, drafting
> contracts and pleadings and pleading in a court of law. _(the first Turner test)_
>
> **(b)** A person acts as an advocate and/or solicitor if, **by reason of his being an advocate
> and solicitor**, he is employed to act as such in any matter connected with his profession.
> _(the second Turner test)_

So: advice on legal rights and obligations **is** named, as an example, inside the first test. The
intuitive statement is not wrong; it is imprecise in two places that happen to be the two places a
software system lives.

- The first test turns on **"exclusive"**. It is not "an act lawyers do", it is an act _customarily
  within their exclusive function_. That word is the whole question for computational law, and it
  is a moving one: whatever a $9 app does at population scale for a decade stops being exclusive to
  anybody, and the test is expressly historical/traditional — it reads the past, so it cannot help
  but ratify the present once the present has lasted.
- The second test turns on **"by reason of his being an advocate and solicitor"**. A software
  vendor is not engaged _qua_ lawyer. On its face the second test does not reach a product at all;
  it reaches a person trading on professional standing. _Turner_ itself was two New York attorneys
  in a Singapore arbitration — the paradigm of being hired _because_ you are a lawyer.

**Neither test was written with a machine in the room**, and the seam between them is exactly where
an L4-style system sits: doing an act that was once exclusive, for a principal who is not engaging
a professional.

## 3. Why this is _this paper's_ problem

§3's spectrum of gap-fillers has five rows. **Every row below the sovereign is unlicensed.** The
open-civic corpus, the free high-accuracy advice service, the state-sponsored adversary running the
identical service — none of them holds a practising certificate anywhere, and the middle rows are
the ones the paper hopes will win.

Now apply the prohibition down the column, and note that **it does not bind uniformly:**

| Filler                            | Bound by UPL in practice?                                                                                                                         |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sovereign rules-as-code           | no — s 34(1)(a), (d) exempt the AG and public officers drawing instruments in the course of duty                                                  |
| Domestic startup / civic project  | **yes, maximally** — incorporated, named, bank-accounted, reachable, and s 33(6)–(8) reach the company, its directors and every partner of a firm |
| Big tech                          | partly — deep pockets, lobbying, and the option to geofence a feature                                                                             |
| Anonymous offshore "free" service | **no** — no forum, no assets, no directors to charge                                                                                              |
| State-sponsored adversary         | **no, by construction**                                                                                                                           |

This is the sting, and it is a claim the paper can make that nobody in the access-to-justice
literature is making: **an unauthorised-practice regime is a filter that selects out precisely the
gap-fillers who can be held to account, and leaves untouched the ones who cannot.** It does not
reduce the number of people getting machine-mediated legal answers. It reduces the number of
_jurisdictionally reachable_ people supplying them. Under-provision (§1) creates the vacuum; UPL
then disqualifies the accountable candidates for filling it. §4.8 says enclosure manufactures its
own liberators; this says the second enclosure **disarms the defenders**.

## 4. Protectionism or consumer protection? — put the judicial rationale on the record first

The honest version of this argument has to quote what the courts actually say the provisions are
_for_, because they say it plainly and it is a mix.

_Turner_ at [34], as quoted in _Choo Cheng Tong_ at [6]: the primary object is to **"protect the
public from claims to legal services by unauthorised persons"**, ensuring that members of the
public "are not charged fees for legal services rendered by persons who are not authorised". _Then_,
"more broadly, these provisions also help to preserve **public confidence in the legal
profession**." _Lim Tean_ at [67] adopts that second formulation, holds s 33(1)(a) to be a **conduct
crime**, and draws the consequence that **the absence of harm is not mitigating** — the offence is
complete on the conduct, so nobody has to have been hurt.

Read that ordering carefully, because it is doing the work:

- The **first** rationale is consumer protection with a specific mechanism: recourse. It is not
  hand-waving. _Lim Tean_ turns partly on professional-indemnity cover, and ss 35A and 36 give it
  teeth on the money side — a client can claw back what they paid, and the unauthorised person
  cannot sue for fees. That is a real remedy that a disclaimer in an app's terms of service does not
  replicate.
- The **second** rationale is confidence **in the profession**. That is not a consumer interest. It
  is the interest of an industry in the reputation of its brand — which is exactly the thing the
  protectionism reading predicts you would find, stated openly, in the reasoning.
- The **conduct-crime holding** is the tell that matters most. An offence that is complete without
  harm, and where absence of harm is not even mitigating, is not calibrated to consumer detriment.
  It is calibrated to the boundary of the profession.

So the fair answer to "protectionism or consumer protection?" is **both, and the case law does not
hide it.** The paper's contribution is not to pick a side but to observe the _incidence_: a rule
justified by recourse is being applied to a class of supplier for whom the recourse rationale is
strongest (the reachable domestic vendor) and is unenforceable against the class for whom it is
weakest (the anonymous offshore one).

## 5. The medallion analogy — and where it breaks

The instinct to reach for taxi medallions is right about the flavour and wrong about the mechanism,
and the difference changes what reform even looks like.

New York capped yellow-cab medallions at **13,587**, made them **transferable**, and thereby created
a tradeable asset that peaked around **$1.05M in June 2013** (with auction prints reported to ~$1.3M)
before collapsing below $250k after ride-hailing arrived. That is **quantity rent**: an artificial
scarcity, capitalised into a security, held by incumbents who then have a balance-sheet reason to
fight entry.

Practising certificates have **none of those three properties**. They are not capped in number, not
transferable, and have no resale value. Singapore admits everyone who qualifies; there is no
_numerus clausus_ to abolish. So there is no capitalised rent and no incumbent whose net worth
collapses when the rule changes — which, incidentally, is why this reform is _politically easier_
than the medallion fight, not harder. Nobody is holding a million-dollar asset that goes to zero.

The rent here, to the extent there is one, is **scope rent** — it accrues to the profession as a
whole through the _size of the reserved zone_, not to individuals through a tradeable licence. Which
means the reform lever is not "raise the cap". It is **"shrink or map the zone"**, and there are two
existing instruments for that:

1. **The English model.** The Legal Services Act 2007 reserves exactly six activities — rights of
   audience, conduct of litigation, reserved instrument activities, probate activities, notarial
   activities, administration of oaths — and **legal advice is not among them.** Anyone in England
   and Wales may give legal advice. The sky has not fallen. Singapore's LPA is structurally much
   closer to this enumerated model than to the American blob; it is the general limb in s 33(1)(a)
   plus _Turner_ that supplies the elasticity the English list deliberately refuses.
2. **The lever Singapore already holds.** **s 34(2): "The Minister may make rules for the exemption
   from section 33 of any person who, or any class of persons each of whom, satisfies such
   requirements, and does such act in such circumstances, as may be prescribed."** A regulatory
   sandbox for computational legal services needs **no amendment to the Act.** The power is already
   there, added by Act 8 of 2011. _(I searched the subsidiary-legislation corpus and did not find
   rules made under it; the search is keyword-based, so treat that as "not found", not "none
   exist" — check before asserting.)_

That second point is the single most useful sentence in this sidebar for a Singapore audience, and
it reframes the whole question. The argument is not "the law should be changed." It is: **the
instrument for permitting this already exists and has apparently never been used.**

## 5a. The US record: LegalZoom did not win the argument, it won around it

The received story is "LegalZoom beat UPL." The record is mixed, and **the mechanisms by which it
prevailed are the whole point** — because only one of the four is a court holding about what
computational document assembly _is_.

| Year | Forum                                                                | Outcome                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ---- | -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1999 | Texas — _UPL Committee v Parsons Technology_ (Quicken Family Lawyer) | **Lost.** District court enjoined sale of the software statewide as the practice of law under Tex. Gov't Code § 81.101.                                                                                                                                                                                                                                                                                                                                                                      |
| 1999 | Texas legislature                                                    | **Reversed by statute within months.** H.B. 1507, 76th Leg., effective immediately: the practice of law "does not include the design, creation, publication, distribution, display, or sale … [of] computer software, or similar products if the products clearly and conspicuously state that the products are not a substitute for the advice of an attorney." Fifth Circuit then **vacated the injunction and remanded** "in light of the amended statute": 179 F.3d 956 (5th Cir. 1999). |
| 2011 | Missouri — _Janson v LegalZoom_, 802 F. Supp. 2d 1053 (W.D. Mo.)     | **Lost**, and settled. Summary judgment for LegalZoom only on patent and trademark applications; denied in all other respects.                                                                                                                                                                                                                                                                                                                                                               |
| 2014 | South Carolina — _Medlock v LegalZoom_                               | **Won cleanly**, on the merits.                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| 2015 | North Carolina — consent judgment, 22 Oct 2015                       | **Won by antitrust leverage.**                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| 2016 | North Carolina legislature — H.B. 436 / S.L. 2016-60                 | **Codified.**                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |

Four things in that table are worth more than the table.

**(i) In Missouri the human in the loop is what sank them.** The service failed because non-lawyer
employees reviewed customers' answers for completeness and inconsistency and rang the customer to
clarify — that made it "a document preparation service that involved human intervention", not
"merely a product". **The quality-control step was the offence.** Any regime with that shape
penalises exactly the intervention that reduces consumer harm, which is a strong argument that the
line is drawn around the profession rather than around the risk.

**(ii) South Carolina's ratio is the engrossing distinction, in an American accent.** Judge Clifton
Newman's report, adopted by the SC Supreme Court in a two-paragraph order of 11 March 2014:
**"LegalZoom's software acts at the specific instruction of the customer and records the customer's
original information verbatim, exactly as it is provided by the customer."** That is s 34(1)(k) of
the Singapore LPA — the person "merely employed to engross" — arrived at independently, by a court
reasoning from first principles about what the machine does. **Renders, does not choose.** Two
jurisdictions, two centuries apart in drafting, converging on the same seam is the strongest
available evidence that the seam is real and not merely convenient.

**(iii) South Carolina's _second_ reason is §1 of this paper.** The report relied on an affidavit
that of the 20 practice areas LegalZoom covered, **19 had the same basic services available free via
self-help portals run by South Carolina government agencies.** The defence to UPL was that _the
sovereign was already provisioning it._ Which is the paper's thesis stated as a rule of decision:
**where the state fills the gap, the gap-filler is lawful; the enclosure bites hardest precisely
where the state has under-provisioned.**

**(iv) North Carolina was won with antitrust, not doctrine — and that is the protectionism thesis
being vindicated by a different branch.** The State Bar had pursued LegalZoom since 2008. In June
2015 LegalZoom sued the Bar in federal court for $10.5M, arguing on the authority of _North Carolina
State Board of Dental Examiners v FTC_, 574 U.S. 494 (2015) that a regulator **controlled by active
market participants and not actively supervised by the state** has no state-action immunity from the
antitrust laws. The consent judgment followed four months later. The legislature then codified it in
2016 — and **the FTC staff and the DOJ Antitrust Division filed a joint comment on H.B. 436**
urging competition between lawyers and non-lawyers in the provision of legal services.

So the honest summary is: LegalZoom won **once** on the merits (SC), **once** by making the
regulator personally exposed in antitrust (NC), and **twice** by legislation (TX 1999, NC 2016).
Nobody ever held that applying a rule to a customer's facts by machine is not the practice of law.
The question was routed around three times out of four. For this paper that is the finding, not a
disappointment: **the "is it protectionism?" question has already been answered by the US antitrust
authorities and by the Supreme Court's active-supervision doctrine — just never by the professional
regulators themselves, which is exactly what the doctrine predicts.**

**One condition in the NC statute is worth stealing.** The exclusion applies only if, among other
things, **"an attorney licensed to practice law in the State of North Carolina has reviewed each
blank template offered to North Carolina consumers, including each and every potential part thereof
that may appear in the completed document."** Read that as an engineer: it is a **coverage
requirement over a template's branching space**, written in lawyerly prose. For a combinatorial
template a human cannot actually complete it — the reachable-document set is exponential in the
number of branch points. Enumerating the reachable outputs of a rule set is precisely what a formal
encoding _can_ do. **The statute has already imposed an obligation that is only tractable with
formal methods, and does not know it.** That is the single best available bridge from this paper's
regulatory argument to the constructive half in §5.

## 5b. The indirection argument — why it fails, and what its failure reveals

The engineer's instinct on being shown s 33(2) is Wheeler's theorem: _all problems in computer
science can be solved by another level of indirection._ Interpose layers. The startup sells a
package; the package fills a template with the customer's own name and address; an agent inside the
package reads the template and selects a configuration reflecting the facts; the customer signs. No
human at the vendor ever touched this customer's facts.

**It does not work, and s 33(2) is the one subsection drafted against it.** "Directly or
**indirectly**" appears there and nowhere else in s 33. The 1966 drafter was solving for the layman
who hires a clerk, but the words are act-based, and indirection defeats a _person_-based test, not
an _act_-based one. Walk the stack:

| Layer                                                  | Status                                                                                                                                                                                                                            |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The company sells software                             | s 33(6) makes a body corporate's act an offence; **s 33(7) makes the director, officer or employee who did the act personally liable** to the s 33(5) punishments. The corporate layer doubles exposure rather than absorbing it. |
| The package fills in name and address                  | **Safe on all three authorities.** s 34(1)(k) "merely employed to engross"; _Medlock_'s "records the customer's original information **verbatim**". Rendering.                                                                    |
| The agent selects a configuration reflecting the facts | **This is the _Janson_ employee, automated.** LegalZoom lost Missouri because staff reviewed answers for completeness and inconsistency; that turned a product into a service. Choosing.                                          |
| The customer signs                                     | Irrelevant to the offence, which is complete on the preparing.                                                                                                                                                                    |

**But the reductio holds, and it is the more valuable half.** Nothing in the statutory text
distinguishes an L4-based product from Word running vanilla Copilot. Both are a corporate person,
indirectly, preparing a document relating to movable property, for reward. So exactly one of two
things is true:

1. **It catches Microsoft too, and no one will ever charge Microsoft.** Then the provision is
   enforced by prosecutorial discretion against whoever is small enough to charge — the paper's
   asymmetry thesis (§3) demonstrated rather than argued.
2. **It does not catch Microsoft, and the reason is a principle.** The only candidate is
   **general-purpose versus purpose-built** — the dual-use tool question, which copyright resolved
   with substantial-non-infringing-use and inducement and which accessory liability resolves
   everywhere else. **It has never been applied to UPL in any jurisdiction we surveyed.**

Route 2 does not rescue the consumer-protection story either, because applied honestly **it inverts
with respect to the stated rationale.** Vanilla Copilot will confabulate a clause and cannot say
why; a purpose-built formal system emits a checkable trace. A rule that exempts the unverifiable
tool because it was not _trying_ to do law, and catches the verifiable one because it was, sorts by
intent when the rationale on the record is recourse. That is the sharpest single argument in this
sidebar and it belongs in the paper's body.

**Wheeler's corollary is why the argument should not be run even though it is correct.** _Except the
problem of too many levels of indirection._ Every layer interposed between the vendor and the choice
is also a layer between the customer and anyone answerable. Win by indirection and you have proved
the regulator's premise: nobody to sue, nobody to strike off, no indemnity policy. **The move that
beats the offence concedes the rationale.** The constructive route below does not have that defect.

## 5c. QuickCheck considered legally required to run

Recall the condition North Carolina actually legislated: the exclusion applies only if an attorney
has reviewed each blank template **"including each and every potential part thereof that may appear
in the completed document."** Taken literally over a combinatorial template this is not merely
onerous, it is **impossible** — the reachable-document set is exponential in the branch points, so
the statute imposes a duty no human reviewer has ever discharged or could.

That is the wrong response to it, though, and the objection has a known answer: **you do not
enumerate the documents, you enumerate the equivalence classes.** This is exactly Imandra's **region
decomposition**, which its own documentation describes as lifting **cylindrical algebraic
decomposition** (Collins, 1975) from real-closed fields up to algorithms, via symbolic execution,
automated induction and nonlinear decision procedures. A decomposition partitions a function's input
space into **finitely many symbolic regions**, each carrying three things:

- **constraints over the inputs** characterising when execution enters that region — _when does this
  clause fire_;
- an **invariant result** describing the output for every input satisfying those constraints —
  _what document you get_;
- **sample points** witnessing satisfiability — _a concrete specimen the reviewer can read_.

Which is precisely a **reviewable artefact of human size**. A lawyer cannot review 2⁴⁰ documents.
A lawyer can review forty regions, each stated as "_if these facts, then this text, and here is an
example_" — and can sign off that the enumeration is exhaustive, because the decomposition is a
proof that it is, not a sampling of it.

So the constructive position, which is the one to argue:

> **The obligation the statute already imposes is discharged by a decomposition, and by nothing
> else.** Not by a human reading templates, who cannot complete the task; not by testing, which
> samples; not by a general-purpose model, which cannot say what it will do next time. The
> regulatory requirement and the formal-methods capability are the same shape, and the statute got
> there first without knowing it.

Two things follow for the paper.

**(a) It reframes the ask.** Do not argue "we are not preparing the document" — that is §5b, correct
and self-defeating. Argue instead: _we are the class of person who should be exempted under LPA
s 34(2), and the decomposition is the evidence that exempting us is safe._ That is an argument
addressed to a **supervising sovereign**, which is the only regulatory shape _NC Dental_ leaves
standing, and it uses a power Singapore already holds.

**(b) It gives the constructive half (§5) its sharpest formulation.** The defence against the
population-scale supply-chain attack is not "trust the provider" — it is that **the provider can be
made to publish a finite, checkable map of everything it will ever emit**, and the adversarial
filler in §3 cannot. A neural gap-filler has no decomposition to publish. That is the first
requirement in this paper that a poisoned 99.5%-accurate service **structurally cannot meet**, which
makes it a real discriminator rather than a wish. _Cf._ QuickCheck (Claessen & Hughes, 2000): the
move from "we tested some cases" to "we stated a property and it is checked" is the same move,
one rung lower.

## 5d. The general move, and the tension inside it

**Borrowed material — this belongs in [`../formal-methods-in-law/`](../formal-methods-in-law/), not
here.** Recorded in this sidebar because it arrived with §5c and would otherwise be lost. Region
decomposition is one instance of a general move: **quotient an intractable space by an equivalence
relation and work with the finitely many classes.** The umbrella is **abstract interpretation**
(Cousot & Cousot, 1977) — a sound quotient of a concrete domain into a finite abstract one. Nearly
the whole toolbox is an instance:

| Instance                               | The equivalence relation                                                           |
| -------------------------------------- | ---------------------------------------------------------------------------------- |
| **Myhill–Nerode**                      | right-congruence on strings; **number of classes = states in the minimal DFA**     |
| Predicate abstraction / CEGAR          | agreement on a finite predicate set; refinement **splits** a class when too coarse |
| Symbolic execution                     | the path condition — Imandra's route in                                            |
| Cylindrical algebraic decomposition    | cells on which every polynomial has constant sign (Collins, 1975)                  |
| Bisimulation quotient                  | no observation distinguishes the states                                            |
| Symmetry reduction                     | orbits under a group action                                                        |
| Equivalence partitioning (Myers, 1979) | the testing textbook's name for the same move                                      |

**Myhill–Nerode is the one to put on a slide**, because it says the quotient _is_ the minimal
automaton. So "decompose the contract into regions" and "minimise the contract's automaton" are the
same act — and the contract-as-automaton framing (Flood & Goodenough, _Contract as Automaton_, OFR
WP 15-04, 2015) is already in the deck to hang it on.

### The tension: the two axes want different quotients

- **For machine tractability you want the _coarsest_ sound partition** — fewest classes, each as
  large as possible. Minimality is the entire goal.
- **For human reviewability, coarsest is wrong.** A minimised automaton is finite and unreadable,
  because minimisation discards the names. Two regions with identical outputs — "under 18" and
  "lacking capacity" — get merged by the machine and must stay apart for the lawyer, because they
  are different legal cases that happen to agree on this output.

So the reviewer does not want the coarsest sound partition. The reviewer wants **the coarsest
partition that still respects the source text's own case structure.**

**And that is an argument for isomorphism that nobody currently makes.** Isomorphic formalisation is
usually justified as an audit convenience — a lawyer can diff the encoding against the provision line
by line. The stronger claim is that **isomorphism is what makes a decomposition legible rather than
merely finite**: an encoding that preserves the statute's own limbs decomposes along lines a lawyer
has already named, so every region comes with a name the source text supplied. A non-isomorphic
encoding can produce exactly the same finite region count and be unreviewable.

### Two corollaries

**(i) The class count is the review budget.** Forty regions is a morning's work; forty thousand has
moved the problem rather than solved it. So _how the rule is drafted_ determines whether it is
reviewable at all — which is a much stronger argument for rules-as-code than the usual one. Not
"code is precise", but **"a rule drafted this way decomposes small enough that a human can check all
of it."**

**(ii) Surplusage is already an equivalence-class statement, and it is already in the deck.**
"Flip one bit and see whether the answer moves": if deleting a condition leaves the partition
unchanged, the condition is surplusage. The s 415 cheating analysis in _Poh Yuan Nie v Public
Prosecutor_ [2022] SGCA 74 — where a proposed reading was rejected at [32] because it "rendered
Explanation 1 to s 415 otiose" — is mechanically **"your reading induces a coarser partition than
mine, and the difference is exactly the clause you say is doing work."** The canon and the quotient
are the same test.

### One caveat to keep straight in print

Quotienting does **not** beat NP-completeness in the complexity-theoretic sense. It shrinks real
instances, often enormously, but the worst case stands — CAD is doubly exponential in the number of
variables. The thing that changes the complexity _class_ is the **language restriction**: no
unbounded loops moves you from undecidable to decidable. Keep the two claims apart, or a reviewer
will separate them for you. It is also the tidiest defence of L4's design: the restriction that
looks like a limitation is precisely what makes the region map available.

## 6. The steelman against all of the above

Do not ship the argument without this, or it reads as a lobbying document.

- **Recourse is real and software does not have it.** ss 35A/36 give a wronged client a statutory
  claw-back. Professional indemnity insurance pays out. A struck-off solicitor stops practising.
  There is no analogue for a product that returns a wrong answer to a hundred thousand people, and
  "we're just information, see our terms" is precisely the disclaimer the paper's adversarial filler
  would also write.
- **The conduct-crime shape is defensible on exactly the paper's own logic.** §4.1's argument is
  that a service right 99.5% of the time becomes load-bearing and the danger lives in the 0.5% that
  nobody can check. An offence that does **not** wait for demonstrable harm is the natural
  regulatory response to a harm that is undetectable in the individual case. The paper cannot argue
  that undetectable population-scale error is the threat _and_ that harm-independent regulation is
  illegitimate. Pick one, or distinguish carefully.
- **"Exclusive" may be doing honest work.** The first Turner test asks what is customarily within
  the exclusive function of the profession. If a task genuinely requires professional judgment under
  uncertainty, that is a finding about the task, not a guild's assertion. The interesting claim is
  narrower and more defensible: **subsumption over a formally-encoded rule with a machine-checkable
  trace is a different act** from advising under uncertainty, and it is that difference — not a
  general attack on licensure — that deserves the exemption. This is the strongest available bridge
  to the constructive half in §5: auditability is what makes the carve-out principled rather than
  merely convenient.

## 7. Not checked — do this before any of it is published

- **_Turner_ [1988] 1 SLR(R) 281 has not been read in the original.** Both tests, the "primary
  object" line at [34], and the facts are taken from how _Choo Cheng Tong_ quotes them at [6] and
  [79]–[80]. Get the report. A 1988 first-instance decision is a thin foundation for a load-bearing
  claim, and there may be later appellate treatment.
- **_Choo Cheng Tong_ and _Lim Tean_ were read in targeted extracts, not end to end.**
- **Whether any s 34(2) exemption rules exist** — see §5.
- **How s 33(1)(a) has actually been charged.** Every case surfaced here (_Lim Tean_, _Mahadevan_,
  _Bhaskaran_, _Selena Chiong_) is a **lawyer without a current practising certificate** or someone
  **holding out** as a lawyer, not a technology provider. The absence of a technology prosecution is
  itself a finding worth stating carefully — and worth not over-reading, since the deterrent effect
  of an unprosecuted offence on a funded startup is the whole point.
- **The US survey is now done for the four LegalZoom-adjacent matters (§5a), but read the
  primary sources before publication.** Of that section, only the Fifth Circuit opinion in
  _Parsons_ (179 F.3d 956, read via law.resource.org) was read in the original. _Janson_,
  _Medlock_, the NC consent judgment, H.B. 436 and the FTC/DOJ joint comment are all from
  secondary reporting, as is the holding of _NC State Board of Dental Examiners v FTC_ 574 U.S. 494
  (2015) — which is load-bearing for §5a(iv) and has not been read.
- **Imandra's region decomposition (§5c) is cited from its own documentation and press material,
  not from the system-description paper.** Get Passmore & Ignatovich, "The Imandra Automated
  Reasoning System (System Description)" (IJCAR 2020) before relying on the CAD lineage in print,
  and do not overstate it: the claim to make is that decomposition yields a finite reviewable
  partition, not that legal templates are semialgebraic.
- **Still unsurveyed: the Utah regulatory sandbox and Arizona's abolition of ER 5.4, both 2020.**
  They are the strongest evidence that the scope question is being reopened by regulators rather
  than by courts, and they are the closest structural analogue to the s 34(2) power.

## 8. Where it sits in the series

- **This paper (§3, §4.8, §5)** — the primary home; second enclosure, asymmetric incidence.
- [**`../formal-methods-in-law/`**](../formal-methods-in-law/) — the auditability argument in §6's
  third bullet is that paper's ladder pointed at a regulatory question: what makes a machine's
  subsumption checkable is what could make it exemptible. **§5d is on loan from that paper and
  should be moved there**: the equivalence-class framing, the two-quotient tension, and the claim
  that isomorphism is what buys legibility rather than mere finiteness are general results, not
  UPL ones.
- [**`../bounded-deontics/`**](../bounded-deontics/) — the dominator reading has something to say
  about a profession that holds a power over who may speak about obligations.
