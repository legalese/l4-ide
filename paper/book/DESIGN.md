# An Introduction to Computational Law, Using L4

## Design note for the _Book of L4_ — the foundations, and where they sit

> **Status: DESIGN, 2026-08-11. Nothing is drafted.** The only prose that exists is
> [`specimen-ch1-opening.md`](specimen-ch1-opening.md), written to calibrate voice and pitch —
> it is a specimen, not a chapter, and its L4 fragment has not been through the type checker
> (see **D5**). This note records the decisions that would have to hold before drafting starts;
> it does not describe a book that exists.
>
> **Provenance.** Meng, 2026-08-11: software books follow a genre — "an introduction to
> ⟨subject⟩ using ⟨tool⟩" — and the good ones open on an abstract foundation (Haskellbook's
> first chapter is pure lambda calculus). The corpus in [`../`](../) is growing toward a book;
> what it lacks is the foundations half: computational law from first principles, the prior art,
> the notions of logic and logics, and the ad hoc applications that arose in the wild over the
> centuries — before we get to our formalisation, syntax, affordances, reasoners and limits.
> The target the phrasing sets: **a _credible_ introduction to computational law using L4.**
> "Credible" is the operative word, and §8 is where it is cashed.
>
> **What review changed (2026-08-11, same day).** The first draft of this note stacked the
> foundations: a nine-chapter Part I, then L4. Meng: _"Eight foundation chapters sounds like a
> lot. We should be getting into the meat of L4 by chapter 2."_ Correct, and it was §1's own
> failure mode — a theory half with the tool sprinkled on. **D13** (§3) is the repair: the
> foundations are interleaved, not stacked, and there is no Part I. Nine pre-tool chapters became
> a prologue plus a ten-chapter arc that is running L4 on page 3. §4, §5 and §6 are rewritten;
> D6 and D8 are amended in place and say so. Do not silently restore the stacked shape.
>
> **Second review, 2026-08-13.** Two additions, both from Meng, both recorded where they bite.
> **D14** (§4.1) inserts a chapter on compliance and `IMPLIES` at position 3, _before_
> quantification, sourced from
> [`logic-not-flowcharts.md`](../../doc/concepts/language-design/logic-not-flowcharts.md); its
> axis is Meng's — **"must be"** (all windows must be obscure-glazed) versus **"must do"** (all
> male persons above 18 must do national service) — which now names chs. 3 and 6 and is how the
> book earns L4's two-layer architecture instead of announcing it. **§4.2** reviews
> `doc/courses/foundation/` and `doc/tutorials/` against the arc, under the constraint that
> _those teach L4 and this teaches computational law by way of L4_: the review found one hazard,
> one gap (`MAYBE`), and one unpaid debt from ch. 1 (rule-version time), and changed chs. 1, 5
> and 7. The arc is now eleven chapters with a contingent twelfth.
>
> **Third review, 2026-08-13.** Meng, on the axis just adopted: the Searle dichotomy "runs aground
> on real-world scenarios" — to qualify for tax benefits you must _be_ married, but to be married
> you must have turned up somewhere and _said certain words_. Must-be and must-do **stack**; they
> do not partition. **D15** (§4.1.1) is the resolution, and it is Meng's: the rule is constitutive
> of a classification — window A counts as compliant, window B does not — while the deontic force
> is **ambient** ("thou shalt comply") and, importantly, _recoverable_ from the surrounding
> instrument. The thread is picked up in ch. 6, where A.3 returns as a **dominator** exhibit.
> **D16** (§4.3) adds a debt register, because the ch. 1 miss found in the second review was a
> promise nobody was tracking, and D15 opens two more.

---

## 0. Placement, and what this is not

[`../README.md`](../README.md) is the assembly index: seven paper facets that "facet together,"
to be consolidated into a Book once the papers go out. That index assumes the book is the papers
plus the concept notes, stapled. **It isn't, and this note is the argument for the missing half.**

Every facet presupposes a reader who already believes law can be formalised and wants to know how
we do it. None can be the opening, because none argues from first principles — they argue from
_our_ principles. The book needs an arc a reader can enter with no commitments, good enough that
the papers read as consequences rather than as claims.

**This note is not the whole book's outline.** It designs the foundations and the sequence they
sit in (§§3–5), and records where the existing facets land in it (§6).

---

## 1. The genre, and the way it fails

"An Introduction to Databases Using PostgreSQL." "…to Statistics Using R." The shape is
familiar enough to be invisible, and it fails in two directions, reliably:

- **The manual with a theory preface.** Chapter 1 is relational algebra; chapters 2–20 are
  `CREATE TABLE`. Nothing in the syntax half ever _uses_ chapter 1, so nothing in chapter 1 was
  load-bearing, and the reader who skipped it was right.
- **The theory book with syntax sprinkled on.** The tool is decoration — a way of typesetting
  the maths. The reader finishes able to discuss the subject and unable to do anything.

The books that survive the genre share one property: **the abstract foundation is cashed.**
Haskellbook's lambda calculus is not throat-clearing; you cannot understand currying, or why
`fmap`'s type is the shape it is, or what Haskell's evaluation actually does, without it. SICP's
evaluator is not an appendix; it is the thing the rest of the book keeps rebuilding. The tool
earns its place in the title by being the medium in which the foundation becomes checkable.

So the genre imposes a test, and it is the sharpest quality gate available to us:

> **The cash-out test.** For every concept the book introduces, name the L4 affordance,
> verification query, or defect class that would be unintelligible without it. If nothing is
> named, cut the concept — however respectable it is.

§4 carries the cash-out column. An uncashed row is a bug in the book, not a bonus chapter.

---

## 2. What our lambda calculus is (D2)

The Haskellbook question, asked properly: **what is the smallest formal object such that all of
computational law is visible in it, and which the reader can execute by hand on page 3?**

The obvious candidates all fail, and the way they fail is informative:

| Candidate                    | Why it looks right                                                       | Why it isn't                                                                                                                                                                                         |
| ---------------------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Propositional logic**      | Statutory elements _are_ Boolean formulas; every legal-tech book does it | Too weak to be a foundation and too familiar to be an opening. It is a chapter, not the ground (§4, ch. 2)                                                                                           |
| **First-order logic / Horn** | The actual historical foundation — Kowalski, the BNA, Prolog             | It is the foundation of **someone else's system**. L4 is not a logic program; opening here would teach the reader to expect resolution and negation-as-failure, then spend three chapters undoing it |
| **Untyped lambda calculus**  | Honest about L4's constitutive core, which _is_ a typed functional core  | Silent on everything that makes the subject _law_: parties, acts, deadlines, breach. It grounds half the language                                                                                    |
| **Deontic logic (SDL)**      | It is the logic _about_ obligation                                       | Starting here makes obligation primitive, which is exactly the commitment Bounded Deontics spends a paper refusing (**D11**)                                                                         |

**D2 — Chapter 1 is subsumption: the legal syllogism, and the observation that its major
premise is an artifact.**

Bringing a fact under a rule is the one operation every legal system in history has performed,
prior to and independent of any logic anyone has written down for it. It is small enough to
execute by hand, formal enough to have a shape, and it has the property a good foundation needs:
**one step of noticing turns it into the whole subject.**

The noticing is this. In the classical syllogism, the major premise is a fact about the world —
_all men are mortal_ — discovered, not written. In the legal syllogism it is a fact about a
**decision someone made and wrote down**: _every person who does X commits an offence_. The
major premise of a legal argument is an **authored artifact**. It has a drafter, a date, a
version, an amendment history, a jurisdiction, and — this is the whole book — **defects**.

Everything that follows is a consequence of taking that seriously:

- an artifact can be **read wrongly** → the parse, the canons, ambiguity (ch. 2);
- an artifact can **demand a state of the world** → the material conditional, scope, compliance
  (ch. 3 — _must be_);
- an artifact can be **general** → quantification, and the ∀∃ shape of a well-formed rule (ch. 4);
- an artifact can be **amended by another artifact** → defeasibility, provisos, priority (ch. 5);
- an artifact can tell someone to **do** something → deontics, derived rather than declared
  (ch. 6 — _must do_);
- an artifact runs **against a clock — twice** → deadlines inside a rule, and versions over the
  rule itself (ch. 7);
- an artifact can be **run backwards** → abduction: what facts would make this conclusion hold
  (ch. 8), which is the wizard;
- an artifact can be **defective** → checking, and the tests it never shipped with (ch. 9);
- an artifact can be **deliberately unfinished** → open texture, standards, detect ≠ resolve
  (ch. 10).

This also gives the book its politics for free, in chapter 1 rather than in a manifesto: a
syllogism is the form in which a decision becomes **checkable by someone other than the person
who made it**. That is not a nicety of formalism; it is what makes law reviewable at all, and
it is the through-line to [`../political-economy/`](../political-economy/).

---

## 3. The spine: each logic is the repair of a named failure (D3), and none of them waits (D13)

The book must not be a tour of logics. A tour is what makes a theory half skippable, because a
tour has no plot: the reader is handed propositional, then predicate, then modal, then deontic,
with no reason for the order beyond the order of the textbooks.

**D3 — every logic enters the book as the repair of a specific, exhibited failure of the
previous one, and the exhibit is a real legal artifact, not a toy.**

The chapter therefore ends where it breaks, and the break _is_ the next chapter's motivation. The
reader is never asked to accept apparatus in advance of the trouble it answers. Side benefit: a
reader who stops early stops with a correct partial picture rather than a wrong complete one.

The first break is deliberately not a logical one. Chapter 1 formalises the syllogism; the first
thing that fails is **not** the inference but the _sentence_ — Oakhurst's serial comma,
Lockhart's last antecedent. That jolt is the book's central claim delivered before any theory:
most of the trouble is not deep, it is **avoidable and clerical**, and it is being paid for at
litigation rates.

**D13 — the foundations are interleaved, not stacked. There is no Part I.** Every chapter has one
shape: _a legal problem → the concept that names it → the L4 that runs it → the break that
generates the next chapter._ The concept is the first third of a chapter, never a chapter of its
own, and never a block of chapters.

This is not a compromise on rigour; it is the genre's own lesson taken seriously. A stacked
foundations part **is** §1's second failure mode — the theory book with syntax sprinkled on —
and it fails for a structural reason, not an attention-span one: **a concept that waits nine
chapters for its cash-out cannot be cashed out in front of the reader who is learning it.** D4
requires each concept to name the affordance that makes it necessary; D13 requires that
affordance to be on the same page. The two decisions are the same decision, seen from each end.

The consequence to hold to when drafting: **running L4 appears on page 3 of chapter 1, and
chapter 2 is a syntax chapter.** If a draft chapter's first L4 arrives after its tenth page, the
chapter is a lecture and needs restructuring, not trimming.

---

## 4. The table of contents

A prologue and eleven chapters. Every row names its exhibit (all already in this tree or its
bibliography) and its cash-out (**D4**: an uncashed row is cut). The grouping in the left column
is a reading aid, not a set of Parts — the unit is the chapter.

| #        | Chapter                                | The concept it opens with                                                                                              | The L4 it runs                                                                                    | The break that generates the next                            | Exhibit                                                    |
| -------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------- |
| **0**    | Calculemus, and five graves            | The history, by failure mode (§5)                                                                                      | —                                                                                                 | Why it might be different now                                | Leibniz; the spreadsheet                                   |
| _core_   |                                        |                                                                                                                        |                                                                                                   |                                                              |                                                            |
| **1**    | The smallest legal act                 | Subsumption; the syllogism; the major premise as artifact                                                              | `DECIDE … IF`; the evaluation trace as explanation                                                | The major premise is a _sentence_                            | any two-element provision                                  |
| **2**    | The sentence that means two things     | Propositional structure; parse multiplicity; the canons as disambiguation rules                                        | **The CNL surface**: words not sigils, layout as bracketing, phrase identifiers, asyndeton, ditto | The pinned sentence isn't a definition — it makes a _demand_ | Oakhurst; Lockhart; Rogers/Bell                            |
| **3**    | **Must be**                            | The material conditional; the rule as **constitutive of a classification**; three-valued compliance; logic is not flow | `IMPLIES`; vacuous truth; the **ladder** as derived view — two sinks, one changeover              | It applies to _a_ window; the statute says _any_             | GPDO Class A para A.3 (the window rule)                    |
| **4**    | Every person who                       | Predicate logic; quantifier scope; ∀∃ as the shape of good law                                                         | `DECLARE`, records, enums, `GIVEN`/`GIVETH`, `CONSIDER` exhaustiveness, the empty-set trap        | Real rules have exceptions                                   | British Nationality Act (CACM 1986)                        |
| **5**    | Unless, notwithstanding, provided that | Defeasibility; non-monotonicity; burdens; **absence of a fact ≠ falsity of a fact**                                    | Layered defeat; override graphs; `MAYBE`; the burden-of-proof monad                               | Nothing yet tells anyone to _do_ anything                    | Jersey charity test (defeater on a defeater); PROLEG lease |
| _acts_   |                                        |                                                                                                                        |                                                                                                   |                                                              |                                                            |
| **6**    | **Must do** (may do, must not do)      | Deontics — **derived** from action, goal and consequence; the must-be/must-do stack                                    | `PARTY`/`MUST`/`HENCE`/`LEST`; the dominator `MUST`                                               | Obligations have clocks; clocks collide                      | **A.3 again**, as a dominator; marriage ⇐ the ceremony     |
| **7**    | **Time, twice**                        | Two clocks: deadlines _inside_ a rule; versions _over_ it. Traces, concurrency, races                                  | `WITHIN`; `#TRACE`; the LTS; the three time axes and rule-version pinning                         | Now you have a rule base worth asking                        | the PDPA race; a statute amended mid-facts                 |
| _asking_ |                                        |                                                                                                                        |                                                                                                   |                                                              |                                                            |
| **8**    | Asking the rules questions             | Deduction, **abduction**, induction — and which of the three we refuse                                                 | The relational reading; abductive planning; the ROBDD interview                                   | An answer can't show you it is wrong                         | the eligibility interview                                  |
| **9**    | Checking                               | Verification as the missing test suite; the white-hat Bad Man                                                          | Dead letters, semantic diff, exhaustiveness, model checking                                       | Some questions aren't of this kind                           | the corporate constitution; s415; the Lexipedia drift      |
| _limits_ |                                        |                                                                                                                        |                                                                                                   |                                                              |                                                            |
| **10**   | Where this stops                       | Open texture; vagueness; standards vs rules; **detect ≠ resolve**                                                      | Enumerate-mode encoding; the ambiguity fork and its witness                                       | Who gets to check any of this                                | _Poh Yuan Nie_ ¶28; the determinacy strata                 |
| **11**   | Seeing like a citizen                  | Legibility as civic infrastructure                                                                                     | —                                                                                                 | —                                                            | the political-economy facet                                |

Notes that are decisions, not commentary:

- **Chapter 2 is the syntax chapter, and that is the point.** The CNL material is not deferred to
  a later part: it arrives as the answer to chapter 1's break, which is the strongest possible
  motivation for it. A reader meets layout-as-bracketing five pages after watching a missing comma
  cost five million dollars.
- **Four chapters were merged or moved, not cut.** Old ch. 3 (quantification) and the type
  material became one chapter, because in L4 they are one thing — you quantify over a declared
  type. Old ch. 4 (the three inferences) moved from fourth to **eighth**: abduction is the mode a
  citizen actually needs, but you cannot demonstrate running a rule backwards until the reader has
  a rule base worth interrogating. Old ch. 8 (the limits) became **ch. 10**, still in the arc.
- **Ch. 8 is the chapter nobody else writes.** Deduction gets taught everywhere; abduction is
  mentioned and dropped. But _what would have to be true for me to qualify?_ is the citizen's
  actual question, and it is what the interview compiles to. Induction gets a section for one
  purpose: to say plainly that learning rules from decided cases is a different subject with a
  different failure mode, that we do not do it, and what we give up by not doing it.
- **Ch. 6 precedes ch. 7 although it needs less machinery than it looks.** Obligation is
  introduced as _derived_ (**D11**) — a `MUST` is a landmark on the paths to a goal — which needs
  actions and goals but not yet clocks. Clocks are what break it into ch. 7.
- **D8, amended.** The limits stay inside the arc rather than becoming an afterword — the original
  reason holds, and _detect ≠ resolve_ is a first-principles fact about what a formal model of a
  normative system can be. What changed is only its number: with no Part I to be inside, "ch. 8 is
  Part I, not an appendix" now reads "ch. 10 is a chapter, not an appendix."

**D9 — no probability in the rule graph.** Legal consequences are largely constituted, not
caused; the deadline lapsing _is_ the breach, not evidence of it. Uncertainty lives at the
fact-finding layer, and the book says so once, in ch. 1, and holds the line. (The standard-of-proof
exception is ch. 5's, and is flagged as living on the other side of the boundary.)

### 4.1 Why the conditional is chapter 3, before quantification (D14)

**D14 — the compliance/`IMPLIES` chapter goes _before_ "Every person who", not after.** It is
new material, not a reshuffle: the arc had a real hole where it now sits, and the source is
[`logic-not-flowcharts.md`](../../doc/concepts/language-design/logic-not-flowcharts.md), which is
already the strongest single piece of writing in `doc/`.

**The hole it fills — and the axis that names it (Meng, 2026-08-11).** Chapters 1–2 teach
_classification_ — is this applicant eligible, what does this sentence say — and ch. 6 teaches
_obligation_, with a party, a clock and a reparation. Between them sits the shape most regulation
actually has, and the distinction is exactly **"must be" versus "must do"**:

|                 | **Ch. 3 — must be**                                | **Ch. 6 — must do**                                   |
| --------------- | -------------------------------------------------- | ----------------------------------------------------- |
| The form        | "all windows must be obscure-glazed"               | "all male persons above 18 must do national service"  |
| What it demands | a **state** of an object                           | an **act** by an agent                                |
| Who is bound    | nobody in particular — the thing must simply be so | a named party                                         |
| Time            | none; it is true or false now                      | deadlines, sequence, reparation on breach             |
| Breach is       | a state that fails the predicate                   | an act not done                                       |
| L4 layer        | the constitutive core — `IMPLIES` over Booleans    | the regulative layer — `PARTY/MUST/WITHIN/HENCE/LEST` |

GPDO A.3 is the pure **must-be** case: it defines nothing and names no addressee; it says that _if_
a window is covered, _then_ it must be obscure-glazed and either non-opening or high enough.
`P → Q`, two Boolean trees and a seam. Without this chapter the reader goes from "rules classify
you" straight to "rules order you about", and the step where a rule demands that something simply
**be so** is skipped.

**This pairing is how the book earns L4's two-layer architecture instead of announcing it.** The
reader meets a must-be rule in ch. 3 and runs it as a Boolean function; meets a must-do rule in
ch. 6 and finds that the same treatment will not hold it. That is D2's "one step of noticing"
again, and it is a far better introduction to the constitutive/regulative split than the ICAIL
paper's — which, correctly for its audience, simply cites Searle and moves on.

**The prior art.** "Must be" / "must do" is the **ought-to-be vs ought-to-do** distinction in
deontic logic (German legal theory's _Seinsollen_/_Tunsollen_); von Wright and Castañeda are the
usual anchors, and Meyer's dynamic deontic logic is an ought-to-do treatment. `[verify all four
before drafting — attributions are from memory, and this is precisely the kind of claim the field
will check.]`

#### 4.1.1 The Searle problem, and the reading that dissolves it (D15)

The obvious next move is to line the new axis up against Searle's and call it a third cut. **That
does not survive contact with real instruments** (Meng, 2026-08-13), and the book has to say so
rather than inherit a tidy dichotomy that does not hold.

**The counterexample.** To qualify for a tax benefit you must **be** married. To be married, you
must have turned up at a particular place at a particular time and **said certain words**. The
must-be bottoms out in a must-do. Push on any status — married, resident, registered, licensed,
incorporated, of age — and the same thing happens: it is the residue of acts, or of the passage of
time, or of someone else's determination. **Must-be and must-do do not partition law; they
_stack_.** A working legal analysis walks up and down that stack constantly, and a book that
presents ch. 3 and ch. 6 as two disjoint kinds of rule will have taught something false.

**D15 — the resolution the book adopts: the rule constitutes a classification; the deontic force
is ambient, and recoverable.** For A.3: window A **counts as** a compliant window, window B counts
as a non-compliant one — that is a constitutive judgement in Searle's own "X counts as Y in context
C" form. What makes the sentence feel obligatory is not in the sentence. It is the ambient
expectation that **thou shalt comply**, which sits outside the provision.

Three things follow, and they are the reason this is a repair rather than a redescription:

1. **It explains the encoding.** A statute that says "must be" is encoded as a Boolean function, and
   that looks like a loss of force until you see that the force was never in that sentence. The
   provision does the classifying; the obligation lives elsewhere. Nothing was dropped — it was
   **factored**.
2. **The ambient expectation is usually findable, and finding it is a discipline.** "Ambient" must
   not become a licence to wave. In the GPDO case the force is recoverable from the surrounding
   instrument: Class A grants permitted development _subject to_ these conditions, so the "or else
   what?" is that you lose the permission and fall back to needing express consent, with
   enforcement behind that. So the chapter teaches a practice, not a shrug: **when you encode a
   must-be rule as a Boolean, you have factored out a goal index — go find it and write it down.**
   That is the Bounded Deontics "or else what?" discipline arriving three chapters before the
   theory that names it.
3. **It hands ch. 6 its best exhibit, which is a rule the reader already knows.** "Thou shalt
   comply" gets analysed in ch. 6, and the window comes back: the goal is _development is permitted
   under Class A_, obscure glazing lies on every path to it, and therefore it is a **dominator** —
   a `MUST` derived, not declared (**D11**). Demonstrating the dominator thesis on a statute the
   reader encoded themselves in ch. 3 is worth more than any fresh exhibit, and it makes chs. 3 and
   6 a matched pair rather than two chapters that happen to rhyme.

**So the honest statement about Searle is stronger than "three cuts."** The constitutive/regulative
distinction does not sort _rules_; a single provision routinely plays both roles, and which role you
read it in is a modelling decision with consequences. `[The non-exhaustiveness of the dichotomy is
contested ground in the literature — find the critics rather than asserting it ourselves.]` What
L4's two layers sort is not Searle's kinds but **what the formalism must carry**: a classification
needs a Boolean function, a demand on an agent over time needs a transition system. A reader who
thinks "constitutive core" means "constitutive rule" has been misled by our own naming, and the
chapter should say so in as many words.

**A debt this opens, deliberately.** Ch. 3 leaves two threads hanging for ch. 6 — _where did the
force go?_ and _this state is the residue of acts_ — and it should hang them explicitly rather than
leave the reader to notice the gap. See §4.3.

**Four arguments for before rather than after:**

1. **It needs nothing from ch. 4.** The conditional is propositional. A.3's atoms are Booleans about
   one window; the encoding needs a parameter (`GIVEN w IS A Window`), which the reader has had
   since ch. 1's specimen, but no declared record, no sum type, no quantification over a collection.
   Putting it after quantification would pay for machinery it does not use.
2. **It repairs a confusion the reader already has.** `DECIDE x IF …` has been on the page since
   ch. 1, and `IF` there is the **definitional** connective introducing a boolean function's body —
   confirmed at `doc/reference/functions/DECIDE.md`. `P IMPLIES Q` is the **material conditional**.
   Both read "if" in English, and a reader who meets the second three chapters after the first will
   have spent three chapters quietly conflating them. Teach the distinction at the first
   opportunity, which is here.
3. **Compliance is three-valued, and that is a first-principles fact, not an advanced one.** Out of
   scope, in scope and satisfied, in scope and breached. The material conditional distinguishes all
   three with no extra machinery — the vacuous case is a _feature_, and "the rule never reached you"
   is not the same verdict as "the rule reached you and you complied." A reader who does not have
   this early will read every later chapter's `TRUE` as though it meant one thing.
4. **It sets up defeasibility (now ch. 5) far better than quantification does.** An exception
   operates on the **antecedent** — "unless" carves the scope — and "notwithstanding" arbitrates
   between two conditionals. Give the reader `P → Q` first and ch. 5 is an obvious set of operations
   on a shape they hold; without it, defeasibility has to be taught against nothing.

**What else this chapter carries.** It is also where the reader learns to **read a ladder**, which
every later chapter then uses, and where "logic is not flow" is argued — the category error, and
the three senses of order (the denotation has none; the text has one, which the ladder mirrors on
purpose, per Bench-Capon & Coenen isomorphism; asking has one, which ch. 8's wizard optimises, per
Bryant). The flowchart's specific inability to say the vacuous case — the dangling arrow to an
unlabelled exit — is the sharpest possible motivation for `IMPLIES`, so the negative argument and
the positive one are the same argument.

**Prior art it distributes (D6):** Lexipedia's BPMN and Rulemapping both land here, because both
get half of this chapter right. Rulemapping is the important one and must be conceded generously
(**D7**): it independently refuses the flowchart for a Boolean tree, from two decades of commercial
deployment, and has the measurement we lack. Its structural gap is exactly this chapter's subject —
**no `IMPLIES`, therefore no N/A**, in criminal law, where "out of scope" and "assessed and cleared"
must not be the same `⊥`.

**The cost, stated.** The arc is now eleven chapters, not ten, and this is an _addition_ where the
last revision was a compression. It does not reintroduce the stacked-foundations problem — ch. 3
runs `IMPLIES`, the ladder and a real statute, so it is a tool chapter with a concept opening,
which is the D13 shape — but the honest count went up and §10 records it.

### 4.2 What the existing curriculum tells us — and what it must not be allowed to tell us

`doc/courses/foundation/` (modules 0–7) and `doc/tutorials/` are the closest thing to a prior draft
of this book, and they were reviewed against the arc above. **They teach L4; this teaches
computational law by way of L4** (Meng, 2026-08-13), and that difference decides what transfers.
A language course may lead with its most distinctive feature, because the reader has already
bought in and only wants to know what the thing can do. A subject book has to build the subject,
and its order is owed to the argument, not to the feature list.

So the curriculum is read here as **evidence about dependency and coverage** — what genuinely needs
what, and what has no home — and explicitly _not_ as a template.

**What does not transfer, and why it is worth saying so:**

- **Module 1 opens with `PARTY … MUST` — an obligation, on page one.** That is the right call for
  the course, and their own Developers path says why: it is "the part with no programming-language
  equivalent." The book cannot copy it. Leading with _must do_ presents obligation as a **primitive**,
  which is exactly the commitment **D11** and the Bounded Deontics facet spend a paper refusing.
  The course can afford a theoretical concession that buys engagement; the book is partly _about_
  why that concession is wrong.
- **Modules 3 → 4 run machinery before meaning** (`BRANCH`, `CONSIDER`, lists, then the legal
  framing of `DECIDE`). Correct for a language course, backwards under **D13**.
- **Module 5 makes functions a topic** (recursion, `map`/`filter`/`foldl`). In the book these are
  never a topic; they are the mechanism by which "all of its purposes are charitable" gets said,
  and they appear inside ch. 4 without a section of their own.

**What transfers — three findings, two of which change the arc above:**

1. **A hazard, not a gap.** The course leads with obligation for a reason, and deferring _must do_
   to ch. 6 means five chapters in which a reader may conclude they are looking at decision tables
   with better syntax — precisely the rival
   [`logic-not-flowcharts.md`](../../doc/concepts/language-design/logic-not-flowcharts.md) spends
   a thousand lines distinguishing. **Mitigation, adopted: ch. 1 shows both forms on its first
   pages** — a rule that classifies and a rule that commands — names the _must be_ / _must do_ axis,
   and defers the second explicitly. Cheap, and it plants the book's spine where the reader can see
   it. This does not make obligation primitive: it is displayed, not analysed, and ch. 6 still
   derives it.
2. **A real gap: `MAYBE` and the absence of a fact.** Module 4 teaches optional values as a type
   feature; the book had nowhere to put them. They belong in **ch. 5**, and not as a type feature:
   the absence of a fact is not the falsity of a fact, which is _non liquet_, the burden of proof,
   and the difference between "not proven" and "proven not." Added to ch. 5's row — it is a
   first-principles point that happens to have a type as its cash-out, which is the D4 shape exactly.
3. **The gap that matters most: the book owed a debt from ch. 1 and never paid it.** Ch. 1's whole
   noticing is that the major premise is an artifact with _a version and an amendment history_.
   Nothing in the arc cashed that — a **D4 violation at the book's most load-bearing claim**, and it
   went unnoticed until the tutorial index was read. `doc/tutorials/multi-temporal-modeling/` is a
   seven-step treatment of exactly this: system time, valid time and rule-effective time, with
   amendments and commencement dates falling out of the three axes. **Adopted: ch. 7 becomes
   "Time, twice"** and carries both clocks — deadlines _inside_ a rule, versions _over_ it — because
   the chapter's best lesson is that these are different kinds of time, which is the tutorial's own
   opening question ("why more than one 'now'?").
   **Flagged as the most likely thing to be wrong in this note.** The alternative is a twelfth
   chapter placed right after ch. 3, on the argument that "which version governs these facts?" is
   asked of the simplest _must-be_ rule, long before obligations exist, and is the prologue's grave
   #2 (drift) answered. Ch. 7 is already the heaviest machinery chapter and may not survive the
   addition. **Decide when ch. 7 is drafted, not now** — but do not let the debt go unpaid again.

**A confirmation worth recording.** `doc/tutorials/getting-started/grouping-and-precedence.md` —
"what binds to what, why L4 groups by indentation, and three cases where a comma was the whole
dispute" — is **chapter 2, already written as a tutorial**, down to the exhibits (Chew, Oakhurst,
Rogers). Ch. 2 is therefore the best-sourced chapter in the arc and its shape can be considered
settled. Note the one adaptation the genre demands: the tutorial's job is to stop you writing an
ambiguous line, while the chapter's job is to establish that the ambiguity was **avoidable** — same
material, different burden of proof.

### 4.3 Breaks and debts — and a register for the second kind (D16)

D3 gave every chapter a **break**: the failure that generates the _next_ chapter. That worked, and
it is why the arc has a plot. But it turns out to model only half of what chapters actually owe
each other, and the missing half has already cost us once.

A **break** is discharged immediately, by the chapter that follows. A **debt** is a promise made in
one chapter and cashed several chapters later — and because nothing was tracking them, ch. 1's
version-and-amendment-history debt went unpaid through two full revisions of this note and was
caught only by reading a tutorial index (§4.2, finding 3). That is a **D4 failure with no detector**:
the cash-out test asks whether a concept names an affordance, and says nothing about whether a
promise was kept.

**D16 — debts are tracked in a register, and a chapter may not be considered drafted while it owes
an unlisted one.**

| Debt                                                           | Incurred | Paid   | Note                                                                                        |
| -------------------------------------------------------------- | -------- | ------ | ------------------------------------------------------------------------------------------- |
| The major premise has a **version and an amendment history**   | ch. 1    | ch. 7  | The miss that motivated this register; rule-effective time (§4.2)                           |
| A decision is **checkable by someone other than its maker**    | ch. 1    | ch. 11 | The politics, planted in ch. 1 and grown up in the coda                                     |
| The rule that **commands** rather than classifies              | ch. 1    | ch. 6  | Displayed on ch. 1's opening pages, not analysed (§4.2, finding 1)                          |
| The ambiguity was **avoidable**, and the waste is measurable   | ch. 2    | ch. 10 | The avoidable-ambiguity tax; ch. 2 asserts it, only the determinacy material can measure it |
| **Where did the force go?** — the ambient "thou shalt comply"  | ch. 3    | ch. 6  | D15; the window returns as the dominator exhibit                                            |
| A **status is the residue of acts** (married ⇐ said the words) | ch. 3    | ch. 6  | D15; the must-be/must-do stack, and why the two are not a partition                         |
| **Absence of a fact is not falsity of a fact**                 | ch. 5    | ch. 8  | `MAYBE` and the burden in ch. 5; what an abductive query does with an unknown, in ch. 8     |
| The reader can **read a ladder**                               | ch. 3    | —      | Not a debt but a capability: every later chapter spends it, so ch. 3 must actually teach it |

Two disciplines fall out, and both are cheap:

- **A chapter's draft is not done until its outgoing debts are in this table**, and a chapter that
  pays one should say so in the text — the reader who remembers the promise is the reader who
  trusts the book.
- **An unpaid debt at the end of the arc is a missing chapter**, and should be argued for on that
  footing rather than smuggled in. That is precisely the shape of the open question about
  version-time in §4.2's finding 3.

---

## 5. The history: a short prologue, and the rest distributed

"The ad hoc applications that have arisen in the wild over the centuries" is the other half of
the ask, and it is the half most likely to turn into a list. A list is worthless here: the reader
cannot tell, from a chronology, which of these attempts we are repeating.

**D6 — the history is organised by _recurring failure mode_, not by date.** Its thesis:
computational law has been attempted, in the wild, roughly continuously, and it fails in the same
five ways each time. Naming the five is what earns the right to say what has changed.

**D6, amended by D13 — the history splits.** The original plan gave it a full chapter 0, which
put a long block of scholarship in front of a reader who had not yet seen a single rule run. That
is the same stacking mistake at smaller scale. So:

- **The prologue keeps the argument and stays short** — Leibniz's _calculemus_ as the epigraph,
  the observation that it has been tried more or less continuously since, the **five graves**
  (§5.2), and the honest scorecard on what LLMs do and do not change. That is the analytical
  payload, it is what earns the book's right to exist, and it does not need the parade to make it.
- **The parade distributes.** Each system goes to the chapter whose problem it attacked: the BNA
  and Prolog to ch. 4, PROLEG and Governatori to ch. 5, Pace's CL and the contract calculi to
  chs. 6–7, decision tables, DMN, Lexipedia and Rulemapping to ch. 3, HYPO and case-based reasoning
  to ch. 8's induction section, Szabo and the DAO to ch. 10. Each arrives as a short **prior-art sidebar**
  next to the thing it is prior to.

This is better scholarship, not just better pacing: prior art read beside the problem it addressed
is checkable by the reader, and prior art in a chronology is a list of names. It also enforces
**D7** structurally — a sidebar that would have to say _"and we do this too, first"_ is caught
when the chapter is drafted, not in review.

**Risk of the split, stated so it is watched for:** distributed prior art can become invisible
prior art, and a reviewer's fair complaint that "the book doesn't engage X" is harder to answer
when the engagement is scattered across nine sidebars. Mitigation: a single consolidated
**"the field you have just joined"** appendix that collects every sidebar in one place, ordered
by date, purely as a finding aid. The prologue points at it.

### 5.1 The strands, with their exhibits (the parade, before it is distributed)

- **Law as an inference system, before there was a word for it.** The rabbinic _middot_ — Hillel's
  seven, Ishmael's thirteen — are explicitly _meta-rules of inference_ over an authoritative text:
  a written-down proof system, centuries before proof systems. Justinian's Digest closes with
  **50.17, _De diversis regulis iuris antiqui_** — a title that is nothing but extracted rules.
  Gratian's **_Concordia discordantium canonum_** (c. 1140) is a conflict-resolution engine over
  norms: defeasibility as an editorial method. The medieval brocards are a clause library.
- **The dream, and its author's day job.** Leibniz took his doctorate in law and wrote the
  _Nova Methodus Discendae Docendaeque Jurisprudentiae_ (1667) before the _calculemus_ — the
  founding fantasy of the field was a **legal** project first, which is both the best epigraph
  available and the oldest warning that the fantasy long predates any means of realising it.
- **Codification as a formalisation project.** Bentham's pannomion; the civilian codes; the
  ambition of a complete, consistent, gap-free statement of law — and what actually happened to
  completeness.
- **The first type system.** Hohfeld (1913/1917): jural correlatives and opposites as an algebra
  of rights. A dangling entitlement is a type error, and he knew it before there were types.
- **Jurimetrics and the machine age.** Loevinger (1949); Mehl (1958) `[verify]`; and, decisively,
  **Layman Allen (1957 onward)** on symbolic logic for drafting and interpreting legal documents,
  and normalised drafting. Allen is the direct ancestor of this book's ch. 2 claim that the
  ambiguity is avoidable, and he is chronically under-cited in the rules-as-code revival.
- **Decision tables.** Montalbano (1962); Vanthienen & Robben (ICAIL 1993) — completeness and
  consistency checking of legal rule bases, decades before DMN. Already triaged in
  [`../../doc/concepts/language-design/related-work.md`](../../doc/concepts/language-design/related-work.md),
  which the chapter cites rather than re-derives (**D10**).
- **AI & Law proper.** McCarty's TAXMAN (1977); Sergot, Kowalski et al., _The British Nationality
  Act as a Logic Program_ (CACM 1986); Ashley's HYPO and case-based reasoning; Prakken & Sartor on
  argumentation; Governatori on defeasible deontic logic and Regorous; Satoh's PROLEG.
- **The wild — where the deployed systems actually are.** This is the section that does not
  usually get written, and it is the one practitioners will recognise. Tax preparation software is
  the largest legal expert system ever deployed. Payroll encodes employment law; underwriting
  encodes policy wordings; benefits calculators encode entitlement (OpenFisca; NZ's Better Rules);
  points systems encode immigration law. Oracle Policy Automation `[verify lineage: Haley →
RuleBurst → Oracle]` has been running government determinations at scale for years with almost
  no academic citation. And beneath all of it: **the spreadsheet**, which is how most of the
  world's law is already executed — unversioned, untested, unreviewed, and load-bearing.
- **The blockchain detour.** Szabo (1994/1997); Ricardian contracts; the DAO. Worth a short,
  unsneering section: it is the one attempt in this list whose failure taught a lesson _this_
  book depends on — that letter and spirit come apart, and that "the code is the contract" is a
  claim about which of the two you have agreed to be bound by.
- **Rules as code, now.** OECD/GovTech; Catala; Blawx; Accord/Cicero; Symboleo; Stipula; Bailey's
  Lean component library; and L4.

### 5.2 The five graves (the chapter's actual payload)

1. **The knowledge-acquisition bottleneck.** Encoding is expensive, expert time is scarce, and
   the encoder is neither the lawyer nor the programmer. This killed the 1980s wave.
2. **Drift.** The statute is amended; the encoding is not. Two artifacts, one authoritative, and
   nothing that checks them against each other. (Whence isomorphism — Bench-Capon & Coenen 1992.)
3. **The open-texture wall.** Every system eventually meets "reasonable", and either lies about
   it or stops.
4. **The two-audience problem.** The formalism is legible to the logician or to the lawyer, never
   to both, so review is impossible and the artifact becomes an oracle.
5. **Enclosure.** You cannot formalise what you cannot read. The primary sources are paywalled,
   scanned, or behind a proof-of-work wall.

**The honest scorecard, and the prologue's closing move.** LLMs materially attack (1) and
partially (4). They do nothing whatever for (3). And they make (2) **worse** — encoding gets
cheap, so encodings proliferate, and nothing checks them — unless the artifact is isomorphic to
its source and carries tests. Which is the thesis of the rest of the book, arrived at by
subtraction rather than assertion, and the reason the reader should keep going.

---

## 6. Where the existing facets land

The foundations are the new writing. Most of the rest is assembly (**D10**), and this section
records what lands where, so drafting can aim at it. Note what the interleaving does to this map:
no facet is a Part any more; each is **distributed across the chapters whose problem it answers**,
which is a real editorial cost and is the price of D13.

| Facet                                                                                   | Lands in                        | Note                                                                                                                                                                                          |
| --------------------------------------------------------------------------------------- | ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ICAIL §§3–5 (constitutive/regulative; the two-layer architecture)                       | chs. 3, 6 — and ch. 1's framing | The book **earns** the split via _must be_/_must do_ (§4.1) rather than citing Searle; `doc/concepts/legal-modeling/`                                                                         |
| ICAIL §7 + [`../cnl-affordances/`](../cnl-affordances/)                                 | **ch. 2**, then reprised        | The facet most at risk of becoming the manual (§1): it must keep answering ch. 1's break, not enumerate keywords                                                                              |
| [`logic-not-flowcharts.md`](../../doc/concepts/language-design/logic-not-flowcharts.md) | **ch. 3**, ladder reused after  | The source for the whole chapter: `IMPLIES`, three-valued compliance, logic-is-not-flow, the ladder as _view_                                                                                 |
| [`../bounded-deontics/`](../bounded-deontics/)                                          | ch. 6, seeded in ch. 3          | Obligation derived, not declared (**D11**); the "or else what?" goal-index arrives in ch. 3 as a drafting discipline (**D15**); concede Anderson 1958 in the chapter, not a footnote (**D7**) |
| ICAIL PROLEG appendix; the burden monad                                                 | ch. 5                           | The burden layer is the reason ch. 5 is not just "exceptions"                                                                                                                                 |
| `doc/tutorials/multi-temporal-modeling/`                                                | ch. 7                           | The three time axes — ch. 1's unpaid debt (§4.2, finding 3)                                                                                                                                   |
| [`../formal-methods-in-law/`](../formal-methods-in-law/)                                | chs. 8–9                        | Its §8 honest map is **mandatory**: this material is in several states of existence and each must be marked                                                                                   |
| [`../cls-determinacy-frontier/`](../cls-determinacy-frontier/)                          | ch. 10                          | The determinacy strata and the avoidable-ambiguity tax, which ch. 2 promised and only here can be measured                                                                                    |
| [`../political-economy/`](../political-economy/)                                        | ch. 11                          | The coda; ch. 1's reviewability point, grown up                                                                                                                                               |
| [`../case-studies/`](../case-studies/); `the-letter-and-the-spirit/`                    | worked examples throughout      | Jersey charity test → ch. 5; s415 → chs. 2 and 9; GCO → ch. 7                                                                                                                                 |
| `doc/concepts/language-design/` (tables, trees, order)                                  | chs. 3, 4, 9                    | Cited, not re-derived (**D10**)                                                                                                                                                               |
| `doc/tutorials/getting-started/grouping-and-precedence.md`                              | **ch. 2**                       | Effectively a draft of the chapter already (§4.2)                                                                                                                                             |

**D12, unchanged and now sharper.** The verification material (chs. 8–9) is **written last**,
because its shipped/designed boundary moves and a book that gets it wrong is worse than no book.
Under the old stacked plan that meant "write Part IV last"; under D13 it means the two chapters
are drafted after the other nine, even though they sit in the middle of the arc.

---

## 7. The corpus discipline (D5)

**D5 — every code fragment printed in the book is a real file in the checked corpus, cited by
path, and the book's build fails if it does not type-check.**

This is what makes the "using L4" half honest rather than decorative: the reader can run every
line, and we cannot print a fragment that has quietly rotted past a language change. It is also
the mechanism that keeps §1's failure modes away — a foundation chapter whose fragment does not
run is a foundation chapter that was not cashed.

Two consequences to plan for before the first chapter is drafted, not after:

- **The goldens trap.** Book examples living under the corpus globs pull in the four-goldens-per-file
  rule (repo `CLAUDE.md` §3.3): a `.l4` with no `tests/` directory turns `jl4-test` red for the
  _next_ person, not for us, because no paths filter matches. Book `.l4` files ship their goldens
  in the same commit, read before blessing, or they do not ship.
- **Fragments vs files.** Most chapters want three lines, not a module. Either the book quotes a
  named region of a real file, or it prints whole small files. The first needs a region-extraction
  mechanism the repo does not have; the second constrains how examples are written. **Open —
  decide before drafting**, because it shapes every chapter.

The specimen in this directory deliberately violates D5 (its fragment is untested prose-code) and
says so at the top. That is the only exemption, and it expires when the specimen becomes a chapter.

---

## 8. What "credible" costs — the anti-goals

The ask was for a _credible_ introduction. Five things forfeit that, and each has a rule:

1. **Selling the tool in the foundations.** The concepts must be usable by someone who then goes
   and uses Catala, or Prolog, or nothing. If a chapter's concept only makes sense in L4, the
   concept is wrong or the chapter is marketing. The cash-out column (§4) points _from_ concept
   _to_ affordance; it must never be run backwards to justify a feature. **D13 raises this risk
   rather than lowering it** — interleaving puts the tool on every page, so the discipline that
   used to be structural (a foundations part with no product in it) now has to be exercised
   paragraph by paragraph. The test when drafting: could this section be rewritten against
   another language with only the code blocks changing? If not, check it is teaching a concept and
   not a feature.
2. **Rediscovering prior art (D7).** This project's own papers are strict about this — Bounded
   Deontics leads by conceding Anderson 1958 outright, and claims the boundary rather than the
   idea. A book that presents defeasibility or goal-relative obligation as ours is not credible to
   the fifty people whose opinion determines whether it is taken seriously. **Concede loudly,
   early, by name.**
3. **Overclaiming what runs.** See D12 and the FORMAL-PAPER §8 map. Present tense for what ships;
   named future tense for what does not.
4. **Pretending the limits are small.** Ch. 10 is not a hedge; it is content. The argument is
   stronger, not weaker, for saying exactly where a formal model of a normative system stops —
   because that is the claim the reader is most suspicious of and most able to test.
5. **Writing two books in one binding.** The lawyer and the programmer both have to finish it.
   **D1 — one spine, and paired short sidebars at each foundation**: _"you already do this, and
   you call it X"_ addressed once to each. Not two editions, not a split, not an appendix of
   preliminaries — a sidebar, because the point is that they are the same move under two names,
   and that is itself one of the book's claims.

---

## 9. Why another one

There are books. Ashley, _Artificial Intelligence and Legal Analytics_ (2017); Sartor's and
Prakken's work on legal reasoning and argument; the Stanford CodeX literature; the OECD
rules-as-code reports. They are surveys of **reasoning about law by machine**, written for the
AI-and-Law field.

The gap this book takes: **it is a language book.** Its claim is not that law can be reasoned
about computationally — that literature is settled and forty years deep — but that the
foundations are best _taught_ by writing them down in something that runs, and that a reader who
has written a hundred lines of a legal language understands subsumption, defeasibility and
contrary-to-duty in a way no survey delivers. That is the SICP move, and the "using L4" in the
title is the argument, not the branding.

The second gap, from §5.1: **nobody writes the wild.** A book that takes tax software, payroll,
and the spreadsheet seriously as deployed computational law — rather than starting the story at
TAXMAN — is telling practitioners something true about the world they already work in.

---

## 10. Risks, and the ones without answers yet

- **It is a logic textbook written by non-logicians, for two audiences, neither of which wants a
  logic textbook.** The mitigation is D3 (no apparatus before its trouble), D13 (no apparatus
  without its tool) and the cash-out test, but this remains the single most likely way the book is
  bad. **Test it early:** the specimen exists so this can be judged on prose rather than on plan.
- **Length — the count went back up, and honestly.** Nine foundation chapters plus four parts was
  two books; D13's interleaving brought that to a prologue plus ten. **D14 then added one (ch. 3)
  and §4.2's review added no chapters but flagged a possible twelfth** (the version-time split out
  of ch. 7). So the working count is **eleven, with one contingent**. The chapters most likely to
  split back, in order: **ch. 7** (two clocks — see §4.2 finding 3), **ch. 2** (parse ambiguity
  _and_ the whole CNL surface) and **ch. 5** (defeasibility _and_ burdens _and_ `MAYBE`). Watch all
  three in drafting; do not pre-emptively split any of them.
- **The prologue is now the only place the history argument is made in full**, and it has to carry
  the five graves and the scorecard without the parade behind it (§5). If it cannot, D6's split
  is wrong and the parade comes back — but as an appendix, never as a stacked chapter 0.
- **Citation integrity.** §5 is triage from memory, in the manner of
  [`../bounded-deontics/related-work.md`](../bounded-deontics/related-work.md): **nothing in it
  has been verified against a primary source in this session**, and items already known to be
  shaky carry `[verify]`. Dates, venues and page numbers must be checked before any of it is
  drafted, not before it is published. The repo has been burned here before; see
  [`../bounded-deontics/notes/citation-verification.md`](../bounded-deontics/notes/citation-verification.md).
- **The papers move.** The book assembles facets that are still being written; chs. 8–9 especially
  describe a moving boundary. D12 is the mitigation, and it is a scheduling constraint, not a fix.
- **D5's mechanism does not exist.** §7's fragment-vs-file question has no answer, and every
  chapter's shape depends on it.

---

## 11. Candidate titles

- _An Introduction to Computational Law, Using L4_ — the genre, stated plainly; strongest
- _The Major Premise_ — chapter 1's noticing as the book's name
- _Computational Law from First Principles_
- _Law You Can Run_
- _Subsumption_ — too clever, recorded so it stops being suggested

---

## 12. Next steps, in order

1. **Decide fragment-vs-file** (§7) — it determines the shape of every chapter, and D13 makes it
   urgent rather than merely pending: interleaved chapters print code constantly, so a mechanism
   that only handles whole small files will distort every chapter, not just the code-heavy ones.
2. **Judge the specimen.** If the voice is wrong, everything above is a plan for the wrong book.
   It was written against the old plan and survives D13 unchanged — it already runs L4 on its
   third page, which is what the restructure now requires of every chapter. **One edit it now
   needs:** §4.2's finding 1 puts a _must-do_ rule on ch. 1's opening pages beside the _must-be_
   one, so the specimen is a chapter-1 draft that is missing a page.
3. **Draft chapter 3**, not chapter 2, as the second specimen. Ch. 2 turned out to be the
   best-sourced chapter in the arc (§4.2) and is the least likely to surprise us. Ch. 3 is the new
   one, it carries the book's hardest single load — the _must be_/_must do_ axis, three-valued
   compliance, and teaching the reader to read a ladder — and if it does not work, D14 is wrong.
4. **Verify the citations.** §5's bibliography and §4.1's ought-to-be/ought-to-do attributions
   (von Wright, Castañeda, Meyer, _Seinsollen_/_Tunsollen_) are from memory and carry `[verify]`.
   §4.1.1 additionally owes a literature check on the **non-exhaustiveness of Searle's dichotomy**:
   D15 is a modelling decision we can defend on our own terms, but the claim that a single provision
   routinely plays both roles should be attributed to the critics who made it, not asserted fresh.
5. **Write the prologue** — it carries the history argument alone now (§10), so it is the test of
   whether D6's split works.
