# Sidebar: Who is doing the subsuming?

## Principal, agent, and liability when the rule applies itself

> **Status:** COMPANION to [`SIDEBAR-unauthorised-practice.md`](SIDEBAR-unauthorised-practice.md),
> captured 2026-08-28/29 from a long working discussion. That sidebar asks **who is allowed** to
> apply a rule to a person's facts. This one asks **who is doing it** when the applier is a
> program — and what follows for liability, architecture, and the shape of an exemption worth
> asking for.
>
> **Read it second.** Everything here assumes its §1 (the statute), §1a (s 33(2) up close,
> including the s 33(10) will carve-out and the "papers" mismatch), and §2 (the two _Turner_
> tests). This document does **not** restate them.
>
> **Sources actually read in this pass**, from the lawplain corpora unless noted:
>
> - Legal Profession Act 1966 ss 32–36, 77 — full text, as amended by Act 37 of 2023 wef 17/07/2024
> - **Interpretation Act 1965 s 2(1)** — definitions of "person"; confirmed absence of "firm"
> - **Intestate Succession Act 1967** — complete (ss 1–10)
> - **Wills Act 1838** (Singapore) — ss 1–28
> - _Choo Cheng Tong Wilfred v Phua Swee Khiang_ **[2021] SGHC 154** at [78]–[79] (the _Turner_
>   tests, quoted verbatim from the judgment, not from a secondary source); **[2022] SGCA 8** at
>   [4]–[6] (Phang JCA, transfer application); **[2022] SGHC(A) 5** at [8]–[9] (AD, on the evidence)
> - _Public Prosecutor v Lim Tean_ **[2026] SGHC 44** at [2]–[3], [67] — **note:** the corpus copy
>   of this judgment appears truncated mid-sentence at [91], so the final disposition is **not**
>   established here. Do not state the sentence outcome from this document.
> - **Hansard:** `2025-04-08-151` (Shanmugam, PQ on the SAL Wills Registry) and `2026-02-27-178`
>   (Ms Hany Soh, Committee of Supply, Head R)
> - `https://claude.com/solutions/legal`, fetched 2026-08-28
>
> **Legal information, not legal advice.** This is a policy note. It is not an opinion on anyone's
> exposure, least of all this project's.
>
> **One provenance note, recorded because the repo's rules ask for it.** During the discussion that
> produced this document, the s 33(10) will carve-out was presented as a fresh discovery. It was
> not: it is already at §1(c) and §1a(vi) of the companion sidebar, written two days earlier by the
> same process that then re-found it. Nothing downstream depends on the error, but it is a clean
> instance of CLAUDE.md rule 4 — _verify before asserting the state of a tree, especially from your
> own notes_ — and the cost of not checking is a document that claims novelty it does not have.

---

## 0. The point in one line

**s 33 allocates criminal exposure by the supplier's legal form, engagement posture, and whether a
natural person can be named — and not by whether the answer given to the user was right.** Hold the
content of the advice constant and vary only the corporate metaphysics, and liability moves. That
is the whole finding; everything below is the demonstration.

---

## 1. The Hansard record — the guild asking, in its own words

The companion sidebar argues the protectionism case from structure. This is the same case from the
record, and it is better evidence, because nobody is being characterised: two speeches, six months
apart, say it themselves.

### 1a. The State as promoter of mass self-service will-making

**Mr K Shanmugam, 8 April 2025** (`2025-04-08-151`), answering a PQ on the SAL Wills Registry:

- **"over 153,000 Will records deposited"** as at 1 April 2025; registration **voluntary**, and
  "the validity of a testator's Will does not depend on whether one has registered".
- The Government "has embarked on a **national legacy planning campaign**", promoting
  **MyLegacy@LifeSG**, "a one-stop Government portal that provides citizens with information and
  services on legacy planning… useful tips and facts on Will-making and information to dispel
  common myths and misconceptions about Wills".
- The campaign is run by **AIC, MOH, MSF, CPFB and ServiceSG** — five agencies, not one of them a
  law practice.
- MinLaw "regularly conducts reviews of our laws, including legislation governing wills… This
  includes ensuring that the **Will-making process remains accessible** to Singaporeans."

**Why this matters doctrinally.** The first _Turner_ test turns on whether an act is "customarily
(whether by history or tradition) within his **exclusive** function". That is an _empirical_
criterion, and it is answerable with evidence rather than with argument. A function the State
performs at scale through five non-legal agencies, and describes as one it wants to keep
_accessible_, is not comfortably described as the exclusive function of an advocate and solicitor.

This is the strongest available attack on the exclusivity limb, and it is stronger than the
semantic attack (that intestacy rules are consequence-assigning rather than deontic, so explaining
them is not "advice on legal rights and obligations"). The semantic attack fails for three reasons
worth recording so it is not re-attempted: the ISA is saturated with entitlement language (s 5
"persons **entitled** to succeed"; s 7 Rules 1, 2, 4 "**shall be entitled**"; s 7 chapeau "the
following rules **shall be observed**"; s 10 proviso, the personal representative "shall… **be a
trustee** for the persons entitled"); the enquirer's own position is a Hohfeldian **power** (to make
a will) coupled with a **liability** (to have s 7 operate if she does not), and _Turner_ says
"rights **and** obligations", which in a 1988 lawyer's idiom covers the whole jural table; and the
three items after "**eg**" in _Turner_ are illustrations, not the criterion. Defeating an
illustration does not defeat the test.

### 1b. The ask, with the interest declared

**Ms Hany Soh (Marsiling-Yew Tee), Committee of Supply, Head R, 27 February 2026**
(`2026-02-27-178`). She opens: _"Chairman, I declare that I am a practising lawyer and my areas of
practice include estate matters."_ After proposing that the SAL Wills Registry's $50 fees be waived:

> Feedback from the lawyers and the public highlights concerning experiences with non-legal
> providers offering wills writing courses or services. I raised a Parliamentary Question in
> October on regulating such businesses. **The Ministry replied that wills and probate courses are
> not restricted to lawyers, but non lawyers cannot give legal advice or perform solicitor
> services. Doing so risk criminal liability under the Legal Profession Act.** Yet, can we fairly
> expect an average Singaporean to discern whether a course provider is rendering a legal advice or
> not. Without registrations or mandatory professional indemnity insurance, vulnerable individuals
> risk relying on flawed advice with little recourse. **Unscrupulous operators also risk tarnishing
> the reputation of our legal professions**, which has upheld high standards for decades.

Three things to take from it, in order of usefulness, and **fairly** — she declared the interest
openly, which is to her credit, and undue influence over elderly testators is a real harm, not a
pretext:

1. **MinLaw's position, as reported, matches the statute exactly.** Will-writing is not reserved;
   giving legal advice is. That is the s 33(10) carve-out plus the general limb, stated by the
   Ministry without needing to be argued to.
2. **The remedy sought is entry control**, not output verification: registration and mandatory
   professional indemnity insurance. Both are gates on _who may supply_. Neither is a check on
   whether any particular answer was right.
3. **The reputational interest is stated in the same breath as the consumer interest.** "Unscrupulous
   operators also risk tarnishing the reputation of our legal professions" is the guild interest,
   named by a member of the profession, in Parliament, next to the protective one. The companion
   sidebar's §4 puts the _judicial_ rationale on the record (_Lim Tean_ at [67]: s 33(1)(a) "serves
   to help preserve public confidence in the legal profession"). This puts the _legislative_ one
   there too.

### 1c. What the concession is worth

The load-bearing sentence is her own rhetorical question: **"can we fairly expect an average
Singaporean to discern whether a course provider is rendering a legal advice or not."**

That is a concession that the consumer _cannot audit the supply_. It is offered as an argument for
licensing. It is equally an argument for anything else that makes quality legible — and licensing
is only the incumbent answer to it, adopted when there was no other. That is the seam this project
argues into, and it is better to argue into a concession than into an assertion.

**Not found in the corpus**, and worth chasing before print: her October 2025 PQ itself, MinLaw's
verbatim reply (we have only her paraphrase), and MinLaw's COS response.

---

## 2. Three hypotheticals, one content, three answers

The method here is the paper's own: hold the thing that ought to matter constant, vary the thing
that ought not to, and see which one moves the outcome.

In all three, a Singapore user receives Singapore law applied to her own facts, for money, from a
non-lawyer.

|                                                               | What the user gets                                                                 | Charged | Outcome under s 33 | Why                                                                           |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ------- | ------------------ | ----------------------------------------------------------------------------- |
| **The startup**                                               | intestacy position + a will, from an authored L4 model of the ISA                  | yes     | **exposed**        | engaged _for_ the legal outcome; authored legal content; identifiable authors |
| **Alice** — general assistant, consumer subscription          | the same, plus extra-usage billing at the moment of PDF delivery                   | yes     | not liable         | _Turner_ B fails; no authored view of the ISA                                 |
| **Betty** — same tool, asks only "would my startup be legal?" | advice on the lawfulness of proposed conduct — the _innermost_ example in _Turner_ | yes     | not liable         | as above, **plus** no natural person acted                                    |

### 2a. What is doing the work

Not the fee. **s 33(1) has no fee element at all** (companion sidebar §1a(a)); payment goes to
remedies — s 35A disgorgement, s 36(1) no costs recoverable, s 36(2) the payer may sue to recover —
and to the reverse onus in s 33(2), which is the only place absence of fee is a defence.

Not the artifact, except partially. s 33(10) protects the **will**; it does not protect an
explanatory memorandum about intestacy, which is not a testamentary document. So in a
document-assembly product the carve-out shelters the instrument and leaves the _explanation of why
you need it_ comparatively exposed — with the s 33(2) reverse onus attached if s 33(2)(a) reaches
explanatory documents at all. It probably does not: "document or instrument" reads as instruments of
disposition, and the companion carve-out for "a transfer of stock containing no limitation thereof"
points the same way. But the point of a reverse onus is that the argument happens from the dock.

**This corrects the companion sidebar's emphasis** rather than contradicting it. §1(c) there says
"preparing a will is outside s 33(2)(a)" — true — and the natural inference a reader draws is that a
wills product is therefore comparatively safe. The inference is wrong in an instructive direction:
in a product that _explains before it drafts_, the drafting is carved out and the explaining is not.

Not a disclaimer. "IANAL" answers **s 33(1)(b)** — holding out — completely, and nothing else. It
concedes the s 32(2) element it is offered to rebut, leaves the first _Turner_ test untouched, and
creates a record that the supplier knowingly applied law to a named user's facts. Where a disclaimer
defence exists it has been **legislated**: Texas amended its UPL statute after
_UPL Committee v Parsons Technology_, 179 F.3d 956 (5th Cir 1999) (vacated as moot), to exempt
software carrying a conspicuous "not a substitute for an attorney" statement. That the amendment was
necessary is evidence courts do not reach it by construction. _(Fifth Circuit disposition verified
in the earlier pass; the Texas wording is from recollection and is on the unchecked list.)_

What moves the outcome is **step 3** of the procedure below — the second _Turner_ test's
engagement basis, and the exclusivity limb — plus, for individuals, whether anyone can be named.

### 2b. The decision procedure, as it actually runs

Ordering matters, and it is not the intuitive one. In particular s 33(2) does not gate s 33(1): the
subsection opens "**Without limiting subsection (1)**", so limbs 2–5 are independent.

```
LIABLE( actor, act, artifact )

 0. UNAUTHORISED PERSON?                                       [s 32(2)]
      individual:      NOT (on roll AND has PC)
                   AND NOT (on roll(NP) AND provisional PC AND supervised)
      body corporate:  always TRUE                             [s 33(6)]
    → FALSE ⇒ NOT LIABLE

 1. EXEMPT?  s 34(1)(a)–(o)  · s 35 (arbitration, incl. the giving of advice)
             s 34(2) Ministerial rules  [none found; search inconclusive]
    → TRUE ⇒ NOT LIABLE

 2. ENUMERATED ACT?                                            [s 33(2)]
      (a) drew/prepared a DOCUMENT or INSTRUMENT re property or a proceeding
            — s 33(10): NOT a will or testamentary document
      (b) took instructions for / prepared PAPERS founding or opposing
            probate or letters of administration
            — no will carve-out: "papers" ≠ "document|instrument"
      (d) letter before action        (e) PI or death claim settlement
    → TRUE ⇒ GUILTY *unless the accused PROVES* no fee, gain or reward

 3. ACTING AS AN ADVOCATE OR SOLICITOR?      [s 33(1)(a); Turner — DISJUNCTIVE]
      A. act customarily (history or tradition) within the EXCLUSIVE function
      B. employed to act as such BY REASON OF BEING an advocate and solicitor
    → TRUE ⇒ GUILTY.  No fee element.

 4. HOLDING OUT?   name, title, addition or description implying qualification
                                                               [s 33(1)(b)]
 5. BROKERING?     placing a solicitor's services at another's disposal, for
                   reward; except under indemnity/insurance   [s 33(3), (4)]
```

A lexical note in keeping with this file's running theme: **s 33(1)(b) catches the noun.** "Counsel"
as a title is within "name, title, addition or description"; "counsel" as an ordinary English verb
meaning _advise_ is not. Same string, one form reserved.

---

## 3. The corporate-form finding: s 33(6)–(8)

**New, and not in the companion sidebar.** The Act allocates individual liability by entity type,
and the three regimes are not equivalent.

| Form                        | Provision    | Who is exposed                                                                                                                      |
| --------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| Sole practice / partnership | **s 33(8)**  | **every member, _deemed_ liable, reverse onus** — "unless he or she proves that he or she was unaware of the commission of the act" |
| LLP                         | **s 33(7A)** | the partner, officer or employee **who did the act**                                                                                |
| Company                     | **s 33(7)**  | the director, officer or employee **who did the act**                                                                               |

### 3a. "Firm" does not include "company"

An economist reads "firm" as any business organisation. The statute does not, and four things
foreclose it:

1. **Both words appear in the same sentence.** Interpretation Act 1965 s 2(1): _"'person' and
   'party' include any company or association or body of persons, corporate or unincorporate."_
   s 33(8) reads "Where any **firm** does an act which in the case of a **person** would be an
   offence". On the broad reading that is "where any person does an act which in the case of a
   person would be an offence" — vacuous. The contrast is deliberate.
2. **"Firm" is undefined in both Acts, but the LPA's own vocabulary settles it.** LPA s 2 defines
   "**law firm**" as "**a partnership**, or a practice of a solicitor who practises on his or her
   own account, which is licensed as a law firm under section 131", against "**law corporation**"
   meaning "**a company** licensed as a law corporation under section 153". The Act keeps firm ↔
   partnership and corporation ↔ company rigorously apart.
3. **The neighbouring subsections would collapse.** s 33(6)–(7) already cover bodies corporate. If
   "firm" swept them in, s 33(7) (identified actor) and s 33(8) (deemed, reverse onus) would be two
   incompatible regimes for one entity. And the later insertion of **s 33(7A)** for LLPs is
   affirmative evidence "firm" is not a catch-all: if it were, no LLP paragraph would have been
   needed.
4. **The broad reading reduces itself.** A company's "members" are its **shareholders**. s 33(8)
   would deem every shareholder guilty unless each proved ignorance. And s 33(8) is a deeming
   provision with a reverse onus in a penal statute — the least eligible provision in the Act for
   expansive construction against the accused.

### 3b. Why it matters: the incidence runs backwards from capital

Hold the conduct, the revenue, the clients and the risk constant, and vary only the wrapper. The
**two-person shop** bears deemed liability with the burden reversed. The **well-capitalised company**
requires a prosecutor to identify a human who performed the act — and the more automated the
operation, the harder that is. Automation is therefore a liability discount available only to the
entity form that can afford to automate.

That is regressive, and it is almost certainly an artifact rather than a policy. Read s 33(6)'s own
words: it catches an act "of such a nature or… done in such a manner as to be **calculated to imply
that the body corporate is qualified**… to act as a solicitor." The 1966 corporate mischief was _a
company posing as a law firm_. The limb that now shelters the largest and most automated actor was
drafted to catch impostors.

### 3c. Why it is a good formalisation example

Encode ss 33(6), (7), (7A) and (8) isomorphically and you get four near-identical rules keyed on an
entity-type discriminator that carries no consequence anywhere else in the analysis — the conduct
predicate, both _Turner_ tests and every s 34 exemption are form-blind. Then ask one property
question:

```
-- sketch, not compiled
PROPERTY form_irrelevance
  FOR ALL conduct c, entity_form f1, f2
    liable_individual(c, f1) EQUALS liable_individual(c, f2)
```

It fails, and it fails with a counterexample pair rather than an argument. A human reader skims four
consecutive subsections about corporate liability because they _look_ like boilerplate; that is
exactly the shape of text where the eye stops working. It is the same failure mode as a definition
clause that redefines two nouns and thereby reaches two paragraphs but not a third.

**Both belong on the same slide: the bugs live in the plumbing.** Definition clauses and
entity-liability subsections are the two places lawyers skim and model checkers do not.

---

## 4. The closure: a prohibition that cannot be lawfully inquired about

Any system that **determines** whether conduct is unauthorised practice must be capable of
**performing** unauthorised practice, because the determination _is_ an application of law to facts.

### 4a. It is Tarski, not Gödel

There is no diagonalisation here and nothing refers to itself; the resemblance is to **Tarski's
undefinability of truth**. A language rich enough to describe conduct cannot host a
freely-exercisable predicate over its own application, because evaluating the predicate is an
instance of the operation it ranges over. Three disanalogies keep it honest:

1. **No contradiction.** The class is self-applicative, which is consistent — merely awkward.
2. **It is exactly as strong as the information/advice line, no stronger.** _Stating_ the limbs of
   s 33 is not the regulated operation; _applying_ them to given facts is. A system returning the
   **criteria** escapes; a system returning a **verdict** does not — at the cost of not answering
   the question.
3. **It is repealable by the Minister.** s 34(2) empowers exemption rules for a class of persons
   doing prescribed acts in prescribed circumstances. A rule exempting _determining the application
   of section 33_ dissolves the closure. Gödel has no commencement date. **This is a contingent
   closure of a drafted system, not a necessary property of formal systems** — which is why it
   belongs in a policy paper and not a logic one.

### 4b. The monopoly is on the metalanguage

The profession holds a reserved position not only over the object language (advice) but over the
**metalanguage** (advice about whether advice is reserved). The boundary of the monopoly is
lawfully knowable only from inside it.

Which suggests reading **s 34 as, among other things, a list of who is permitted to know where the
line is**: the AG's officers (a), public officers acting in the course of duty (d), law academics
instructed by a solicitor (h), the person acting for himself alone (e). When MinLaw answered that
"non lawyers cannot give legal advice", that answer was itself an application of the LPA to a
described class of facts — lawful because s 34(1)(a) and (d) cut the State a path through the
closure that is cut for nobody else.

### 4c. The design lesson

Well-formed systems **stratify**: Russell's ramified types, Tarski's hierarchy of metalanguages, and
every proof assistant that keeps a universe out of itself. The LPA never stratifies — it defines a
prohibition over an _operation_ and omits to exempt that operation when applied to the prohibition
itself, so the predicate lands in its own domain.

Stated in the vocabulary this project already uses: the object level (rules as written) and the
property-assertion level (claims about the rules) are separated in our tooling and are **not**
separated in the LPA. s 34(2) is the missing universe annotation, and the fix is one line of
subsidiary legislation. That framing matters strategically: it makes the defect a **drafting**
defect rather than a policy choice, which a regulator can repair without anyone losing an argument
about guilds.

---

## 5. The information/advice line: a failed taxonomy, and its repair

### 5a. What was proposed

A three-tier test, offered as the machine-checkable version of a line UPL law has never drawn
crisply:

1. evaluate a consequence-assigning rule on user facts → **information** (the calculator class)
2. emit a deontic conclusion attaching to the user → **advice**
3. search a configuration space and return a recommendation → **advice, emphatically**

### 5b. Why it fails as stated

**It is not one scale.** The tiers are keyed on three different features — what is _evaluated_, what
is _emitted_, what is _searched_ — and presented as increasing severity. A prudential recommendation
("do not become the test case") contains **no deontic operator at all**, so it passes tier 2's
criterion untouched and is caught by tier 3 on unrelated grounds. Tier 3 is orthogonal to tier 2,
not above it.

**The tiers are not exclusive.** One answer can occupy all three: evaluate ISA s 7 on the user's
facts (1), conclude she is exposed (2), rank her options (3). So "which tier is this system in" is
not well-formed as a per-system question; it is per-utterance, arguably per-clause.

**And it is impredicative.** To prove a system never gives advice you need a classifier for advice,
and classifying free text as advice-or-information is itself a legal characterisation. The proposal
bootstraps on the thing it was meant to settle — which is precisely the closure of §4 reappearing
inside the proposed cure.

### 5c. The repair: make advice untypeable

Do not classify the output. **Restrict the output type so that a verdict is not expressible.**

```
Answer = { criteria    : [Rule]        -- the rules, stated generally
         , derivation  : Trace         -- which fired, in what order
         , citations   : [Provision]   -- back to the source text
         , unresolved  : [Question] }  -- what the user must decide
```

A system whose response type is `String` can always say "you should incorporate offshore", and you
are reduced to classifying strings. A system with the type above **cannot express a recommendation**
— not "is checked not to", _cannot_. The property becomes structural and holds by construction,
which is the only sense in which it was ever going to be machine-checkable. The witness is the
compiler.

This is the predicative repair: the classifier quantified over a totality including itself; the type
discipline stratifies instead, and the obligation moves from the output to the interface.

It is also a far better thing to put to MinLaw under s 34(2), because the Minister is not being
asked to trust a classifier. The exemption condition becomes a statement about the interface, which
an auditor verifies once rather than per transaction.

### 5d. What it costs

Free-text chat and a restricted output type are incompatible: the moment the system can talk, it can
advise. What survives is a **structured interview returning a derivation with the open questions
named and left to the user** — which is also what makes s 34(1)(e) architecture real rather than
nominal. This should be stated plainly in any proposal, because a regulator will hold the proposer
to the version proposed.

---

## 6. Principal/agent boundaries

Four tests, ordered by how checkable they are. Each is stateable as a s 34(2) condition, and none
requires a legal characterisation to apply — which is what keeps them predicative.

**1. Non-interference at the service boundary.** Two designs look alike and are not:

- the agent sends the user's facts to the rules service, which evaluates and returns a trace **about
  her** → the service **individuated**;
- the service returns the rule set and decision procedure, and the agent evaluates locally → the
  service **published**.

The distinguishing property is a data-flow property: **the service's output must be a function of
the query type alone, independent of the user's facts.** That is non-interference in the
Denning / Volpano–Smith sense, decidable in a security-typed language, and it needs no legal
judgment to verify. It is the formal content of "publication": a publisher's output does not depend
on who is reading.

**2. Configuration for the legal use case.** Did the supplier author anything domain-specific —
system prompts, tool routing, fine-tuning, UI affordances naming the legal outcome? Checkable from
artifacts, not from intent.

**3. Fee capture for the legal outcome.** Not a liability element under s 33(1), but the statute
already uses it in s 33(2) and (3), and it is the best available proxy for who is _in the business_
of this.

**4. Dominance of the individuation step.** Is any party other than the user on every path from
facts to verdict?

### 6a. Dominators form a tree, and diffusion is usually multiplicity

In a control-flow graph, `d` dominates `n` if **every** path from entry to `n` passes through `d`.
The dominators of a node are a chain, not a unique node. So _many contributors_ does not entail
_no principal_; it entails a longer chain, and joint dominance is the ordinary case.

Taking the user's facts as entry and the individuated verdict as the node of interest:

| Architecture                                                | Dominators of the verdict |
| ----------------------------------------------------------- | ------------------------- |
| Vendor supplies model + rules + prompt + UI                 | user, **vendor**          |
| Browser ships a general agent; user points it at law        | user, **browser vendor**  |
| User runs open weights locally against a published rule set | **user alone**            |

Only the third row is genuinely without a supplier — and that row is the library: a person with the
statute, a tool, her own facts, her own hardware. Nobody thinks a library practises law, and the
result is right. The second row is not diffuse at all; it is one very large node, and what reads as
evaporation is the difficulty of naming a natural person inside it — the s 33(7) problem of §3, not
an absence of a principal.

---

## 7. Harm does not diffuse

The liability may evaporate under diffusion. **The harm does not.** The user bears the whole
consequence of a wrong answer in every architecture; the diffusion is entirely on the supply side.
A rule that dissolves under diffusion has not eliminated a loss — it has moved it onto the only
party who was never diffuse and cannot detect the error.

Run Calabresi over it. Liability should sit with the **least-cost avoider**. In every one of these
architectures that is **whoever authored the rule model**: a defect in an encoding of ISA s 7 is
fixed once and prevented for every future user, whereas the user cannot detect it at all and an
orchestrating agent has no independent way to check. Interposing a browser, a protocol hop and a
local model changes **identifiability**. It does not move the least-cost avoider.

Which yields the inversion this whole line of argument has been walking toward:

> **Authorship-based liability is correct.** The author of a verified rule model is the least-cost
> avoider, holds the auditable artifact, and is the only party who can be held to a standard that
> means anything. What is wrong with the present regime is not that it attaches responsibility to
> an author. It is that it attaches it through a **status** test — _are you a solicitor_ — instead
> of a **capability** test: _is the reasoning inspectable, is the rule model versioned, can a
> regulator replay the derivation that produced this answer._

Under a rule formulated that way, being the identifiable author is what **qualifies** a supplier for
exemption rather than what exposes it. `git blame` stops being an evidence bundle and becomes a
licence application.

This is also the honest answer to the diffusion strategy: it is legally weak in two of the three
architectures, and strategically backwards in all three, because it spends the one durable advantage
— auditability nobody else can offer — to buy anonymity that only helps in the case where the
supplier is not in the transaction at all.

---

## 8. Publisher, client-side execution, and the commons

### 8a. What compiling to WASM buys

Client-side execution satisfies **non-interference by construction rather than by proof**, which is
strictly stronger: there is no service boundary for facts to cross, so there is nothing to verify.
That is the position of a book of tables.

It does **not** touch the output type. Where the computation runs is a deployment fact; what the
artifact is designed to emit is a design fact. A module that returns _"your daughter takes one
quarter"_ is an advising machine that happens to execute on her CPU. **Both halves are needed:**
client-side execution for the data flow, restricted return type for the individuation.

### 8b. The second regime, which grows as the first shrinks

Optimising against s 33 walks into ordinary negligence. A published calculator with a defect in its
ISA s 7 encoding is a defective product; Singapore runs the _Spandeck_ two-stage framework for duty
of care in negligent misstatement. The publisher route carries **no professional indemnity, no
privilege, and no professional standard to shelter under** — the ordinary law of negligence with
none of the profession's protections. Being a publisher is not a way of having no liability; it is a
way of having a different one. _(The *Spandeck* framing is named from recollection and is on the
unchecked list.)_

### 8c. The marketplace: one real gain, three problems

The gain is genuine and it is the strongest structural move available: **rules published as a
commons cannot be sold as advice.** A public, versioned, openly verifiable canon of law-as-code is
closer to a legal publisher — and to MyLegacy@LifeSG — than to a consumer funnel. It is the best
s 34(2) exhibit there is, because it is evidence rather than argument.

Against it:

1. **Curation is authorship, and verification is curation.** A repository that reviews, ranks,
   badges or certifies is an editor, not a conduit — and _verification is the differentiator_.
   A repository asserting "this ISA encoding has been checked against these properties" is making a
   representation. **You cannot hold verification as the value proposition and conduit as the
   defence.**
2. **It relocates risk onto contributors who cannot carry it.** The module author becomes the
   individuating author: a solo academic, a legal-aid NGO, a student. Least-cost avoider in theory;
   least able to absorb a prosecution or a negligence claim in practice, and carrying no indemnity.
   Worth deciding deliberately rather than discovering.
3. **Fragmented authorship degrades the property being sold.** Three contributors with different
   assumptions about ISA s 4 domicile yield a traceable derivation with nobody answerable for the
   version. "Inspectable and versioned" needs a maintainer of record.

### 8d. The split, which is the shape already named

Separate the layers, because their economics already differ:

- **Commons** — the rule canon: open, versioned, publicly verified, free, non-individuating,
  client-side distributable. Its value is universality and network effects, which is exactly the
  value that cannot be captured by selling it.
- **Product** — tooling for people who are already authorised. _Turner_ B fails cleanly when the
  customer is a law practice; authorship stops being fatal because a solicitor makes the call and
  signs; the fee attaches to workflow rather than to rules.

**This is the PostScript shape.** Adobe published the language specification and sold the
interpreter. The UPL analysis arrives independently at the split this project named for itself at
the outset, which is some evidence it is the right one.

### 8e. One route not yet costed

For modules encoding **legislation** rather than private documents, **s 34(1)(d)** exempts "any
other public officer drawing or preparing instruments in the course of his or her duty." If a
drafting office publishes the L4, the authorship sits with an exempt person from the start. That
turns the rules-as-code pilot from a use case into a compliance architecture, and it is the one path
on which the canon's most important modules have an author nobody can prosecute.

A composition detail in keeping with this file's theme: **s 33(10) opens "In this section"**, so its
carve-out governs s 33 only and does not reach s 34's use of "instruments". The joints keep turning
out to be lexical.

---

## 9. Corrections to the companion sidebar

Recorded here rather than silently applied, so the two documents can be reconciled deliberately.

1. **§1(c) emphasis.** "Preparing a will is outside s 33(2)(a)" is right, and the inference a reader
   draws — that a wills product is comparatively safe — is wrong in the direction described at §2a
   above. In an explain-then-draft product the instrument is carved out and the explanation is not.
2. **§5b, the indirection argument.** That section concludes indirection fails. It is right at the
   level of the **entity** and materially weaker at the level of the **individual**, which the
   companion does not separate: s 33(7) requires a named actor and s 33(8)'s deeming provision does
   not reach companies. Whether _authoring_ a rule system amounts to _applying_ it at each later
   execution is, as far as this pass could establish, **unresolved in Singapore** — _Turner_ is
   1988, _Choo_ concerned a human consultant's emails, _Lim Tean_ a lapsed practising certificate.
   None speaks to an authored artifact executing without its author. The companion should not be
   read as settling it.
3. **The "advice" grep** at §1a(b) is confirmed and load-bearing in a way not drawn out there:
   because **s 35(1)(c)** expressly exempts "the giving of advice" for arbitration, advice must
   otherwise be within ss 32–33. That is a textual route to the same conclusion the _Turner_ tests
   reach, and it does not depend on 1988 case law.

---

## 10. Not checked — do this before any of it is published

- **Ms Hany Soh's October 2025 PQ and MinLaw's verbatim reply.** Only her COS paraphrase is in hand.
  Also MinLaw's COS response, not located in the corpus.
- **The final disposition in _Lim Tean_.** The corpus copy truncates mid-sentence at [91]. [67] is
  quoted and reliable; the sentence outcome is not established here.
- **The Texas post-_Parsons_ statutory wording.** The Fifth Circuit disposition was verified in the
  earlier pass; the amendment's text is from recollection.
- **_Spandeck_** as the operative negligent-misstatement framework — named from recollection, not
  read in this pass.
- **Whether any rules have been made under s 34(2).** A subsidiary-legislation search returned
  nothing relevant, but the search was noisy and is **not** conclusive.
- **Extraterritorial reach of s 33.** Whether it reaches an offshore supplier serving a Singapore
  user was raised and not researched. The sub-limbs of s 33(1)(a) are tied to "the courts in
  Singapore"; the chapeau and _Turner_ test A are not territorially qualified on their face.
- **England & Wales.** Will-writing is not a reserved activity under the Legal Services Act 2007;
  the recollection that the Legal Services Board recommended reserving it around 2013 and the Lord
  Chancellor declined is **unverified**.
- **Corporate attribution doctrine.** §3 argues from the statute's own text. The general law on
  attributing an act to a company (directing mind, or a statutory attribution rule) was not
  researched, and s 33(6) may be doing more work than the text alone suggests.

---

## 11. Where it sits

- **[`SIDEBAR-unauthorised-practice.md`](SIDEBAR-unauthorised-practice.md)** — the canonical
  statement of the enclosure argument. Read first. This file is the agency half and defers to it on
  ss 32–36, the _Turner_ tests, and the medallion and LegalZoom material.
- **[`DESIGN.md`](DESIGN.md)** — §4.9 already points at the companion; the seam for both remains
  between §4.8 and §5.
- **[`../formal-methods-in-law/`](../formal-methods-in-law/)** — §3c (the form-irrelevance property)
  and §5c (advice as a type rather than a classification) are that paper's arguments applied to a
  regulatory question, and may belong there.
- **[`../bounded-deontics/`](../bounded-deontics/)** — §6a uses "dominator" in the control-flow
  sense. That paper uses it in the deontic sense. **The collision is real and the two should not be
  merged without disambiguating the word**, which is, appropriately enough, the third lexical trap
  in this file.
