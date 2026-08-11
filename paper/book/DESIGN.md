# An Introduction to Computational Law, Using L4

## Design note for Part I of the _Book of L4_ — the foundations half

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

---

## 0. Placement, and what this is not

[`../README.md`](../README.md) is the assembly index: seven paper facets that "facet together,"
to be consolidated into a Book once the papers go out. That index assumes the book is the papers
plus the concept notes, stapled. **It isn't, and this note is the argument for the missing half.**

The papers are all _Part II and later_. Every one of them presupposes a reader who already
believes law can be formalised and wants to know how we do it. None of them can be the first
chapter, because none of them argues from first principles — they argue from _our_ principles.
The book needs a Part I that a reader arrives at with no commitments, and it needs it to be
good enough that the papers read as consequences rather than as claims.

**This note is not the outline of the whole book.** It is the design of Part I, plus (§6) a
sketch of how Part I hands off to the material that already exists.

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

> **The cash-out test.** For every concept in Part I, name the L4 affordance, verification
> query, or defect class that would be unintelligible without it. If nothing is named, cut the
> concept — however respectable it is.

§4 carries the cash-out column. An uncashed row is a bug in the book, not a bonus chapter.

---

## 2. What our lambda calculus is (D2)

The Haskellbook question, asked properly: **what is the smallest formal object such that all of
computational law is visible in it, and which the reader can execute by hand on page 3?**

The obvious candidates all fail, and the way they fail is informative:

| Candidate                    | Why it looks right                                                       | Why it isn't                                                                                                                                                                                  |
| ---------------------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Propositional logic**      | Statutory elements _are_ Boolean formulas; every legal-tech book does it | Too weak to be a foundation and too familiar to be an opening. It is a chapter, not the ground (§4, ch. 2)                                                                                    |
| **First-order logic / Horn** | The actual historical foundation — Kowalski, the BNA, Prolog             | It is the foundation of **someone else's system**. L4 is not a logic program; opening here would teach the reader to expect resolution and negation-as-failure, then spend Part II undoing it |
| **Untyped lambda calculus**  | Honest about L4's constitutive core, which _is_ a typed functional core  | Silent on everything that makes the subject _law_: parties, acts, deadlines, breach. It grounds half the language                                                                             |
| **Deontic logic (SDL)**      | It is the logic _about_ obligation                                       | Starting here makes obligation primitive, which is exactly the commitment Bounded Deontics spends a paper refusing (**D11**)                                                                  |

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

Everything in Part I is a consequence of taking that seriously:

- an artifact can be **read wrongly** → the parse, the canons, ambiguity (ch. 2);
- an artifact can be **general** → quantification, and the ∀∃ shape of a well-formed rule (ch. 3);
- an artifact can be **run backwards** → abduction: what facts would make this conclusion hold
  (ch. 4), which is the wizard;
- an artifact can be **amended by another artifact** → defeasibility, provisos, priority (ch. 5);
- an artifact can tell someone to **do** something → deontics, derived rather than declared (ch. 6);
- an artifact runs **against a clock** → time, process, race conditions (ch. 7);
- an artifact can be **deliberately unfinished** → open texture, standards, detect ≠ resolve (ch. 8).

This also gives the book its politics for free, in chapter 1 rather than in a manifesto: a
syllogism is the form in which a decision becomes **checkable by someone other than the person
who made it**. That is not a nicety of formalism; it is what makes law reviewable at all, and
it is the through-line to [`../political-economy/`](../political-economy/).

---

## 3. The spine: each logic is the repair of a named failure (D3)

Part I must not be a tour of logics. A tour is what makes the theory half skippable, because a
tour has no plot: the reader is handed propositional, then predicate, then modal, then deontic,
with no reason for the order beyond the order of the textbooks.

**D3 — every logic enters the book as the repair of a specific, exhibited failure of the
previous one, and the exhibit is a real legal artifact, not a toy.**

The chapter therefore ends where it breaks, and the break _is_ the next chapter's motivation.
The reader is never asked to accept apparatus in advance of the trouble it answers. This has a
side benefit that matters for §8: a reader who stops early stops with a correct partial picture
rather than a wrong complete one.

The first break is deliberately not a logical one. Chapter 1 formalises the syllogism; the first
thing that fails is **not** the inference but the _sentence_ — Oakhurst's serial comma,
Lockhart's last antecedent. That jolt is the book's central claim delivered before any theory:
most of the trouble is not deep, it is **avoidable and clerical**, and it is being paid for at
litigation rates.

---

## 4. Part I, chapter by chapter

Eight chapters. Every row names its exhibit (all already in this tree or its bibliography) and
its cash-out (**D4**: an uncashed chapter is cut).

| #     | Chapter                                | The logic                                                                       | The break that generates the next chapter         | Exhibit                                              | Cashed by                                                       |
| ----- | -------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------- | ---------------------------------------------------- | --------------------------------------------------------------- |
| **1** | The smallest legal act                 | Subsumption; the syllogism; the major premise as artifact                       | The major premise is a _sentence_                 | any two-element provision                            | `DECIDE … IF`; the evaluation trace as explanation              |
| **2** | The sentence that means two things     | Propositional structure; parse multiplicity; the canons as disambiguation rules | Propositions don't scale to "every person who…"   | Oakhurst; Lockhart; Rogers/Bell; _Poh Yuan Nie_ s415 | CNL surface, layout-as-bracketing, `CONSIDER` exhaustiveness    |
| **3** | Every person who                       | Predicate logic; quantifier scope; ∀∃ as the shape of good law                  | You can only run it forwards                      | British Nationality Act (CACM 1986)                  | `GIVEN`/`GIVETH`, types, `all`/`any`, the empty-set trap        |
| **4** | Three directions of inference          | Deduction, **abduction**, induction — and which of the three we refuse          | Real rules have exceptions, and they arrive later | eligibility interviews; the query-plan wizard        | the relational reading; abductive planning; the ROBDD interview |
| **5** | Unless, notwithstanding, provided that | Defeasibility; non-monotonicity; burdens and presumptions                       | Nothing so far says anyone must _do_ anything     | PROLEG lease case; Jersey charity-test knock-outs    | the burden-of-proof monad; override graphs; `default-reasoning` |
| **6** | Must, may, must not                    | Deontics — **derived** from action, goal and consequence, not primitive         | Obligations have clocks, and clocks collide       | the daycare fine; contrary-to-duty                   | `PARTY/MUST/WITHIN/HENCE/LEST`; the dominator `MUST`            |
| **7** | The clock and the other party          | Traces, transition systems, concurrency, race conditions                        | Some questions have no answer of this kind at all | the PDPA breach-notice race                          | trace semantics; the LTS; model checking                        |
| **8** | Where this stops                       | Open texture; vagueness; standards vs rules; **detect ≠ resolve**               | —                                                 | _Poh Yuan Nie_ ¶28; the four determinacy strata      | enumerate-mode encoding; the ambiguity fork + witness           |

Notes that are decisions, not commentary:

- **Ch. 4 is the chapter nobody else writes, and it is why the wizard makes sense.** Deduction
  gets taught everywhere; abduction is mentioned and dropped. But abduction is the mode a
  citizen actually needs — _what would have to be true for me to qualify?_ — and it is what the
  interview compiles to. Induction gets a section too, for one purpose: to say plainly that
  learning rules from decided cases is a different subject with a different failure mode, that we
  do not do it, and what we give up by not doing it.
- **Ch. 6 comes after ch. 7's ingredients conceptually but before it in the text.** Obligation is
  introduced as _derived_ (**D11**) — a `MUST` is a landmark on the paths to a goal — which needs
  actions and goals but not yet clocks. Clocks are what break it into ch. 7.
- **Ch. 8 is Part I, not an appendix (D8).** A book that teaches the machinery for seven chapters
  and confesses its limits in an afterword has already sold the reader something. The limits are
  a foundation: _detect ≠ resolve_ is a first-principles fact about what a formal model of a
  normative system can be, and the reader should meet it before Part II, not after.

**D9 — no probability in the rule graph.** Legal consequences are largely constituted, not
caused; the deadline lapsing _is_ the breach, not evidence of it. Uncertainty lives at the
fact-finding layer, and the book says so once, in ch. 1, and holds the line. (The standard-of-proof
exception is ch. 5's, and is flagged as living on the other side of the boundary.)

---

## 5. The history chapter — and why it is chapter 0, not chapter 1

"The ad hoc applications that have arisen in the wild over the centuries" is the other half of
the ask, and it is the half most likely to turn into a list. A list is worthless here: the reader
cannot tell, from a chronology, which of these attempts we are repeating.

**D6 — the history is organised by _recurring failure mode_, not by date.** Its thesis:
computational law has been attempted, in the wild, roughly continuously, and it fails in the same
five ways each time. Naming the five is what earns the right to say what has changed.

**It runs as chapter 0** — before subsumption — because the reader who does not know that this
has been tried since Leibniz will read Part I as novelty, and the reader who _does_ know will not
trust a book that omits it.

### 5.1 The strands, with their exhibits

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

**The honest scorecard, which is the bridge into Part II.** LLMs materially attack (1) and
partially (4). They do nothing whatever for (3). And they make (2) **worse** — encoding gets
cheap, so encodings proliferate, and nothing checks them — unless the artifact is isomorphic to
its source and carries tests. Which is the thesis of the rest of the book, arrived at by
subtraction rather than assertion.

---

## 6. Handing off: Parts II–V, in one paragraph each

Part I is the new writing. The rest is mostly assembly (**D10**), and this section exists to
record what lands where so the drafting of Part I can aim at it.

- **Part II — the formalisation.** Constitutive vs regulative, and why they get two different
  formalisms rather than one logic. Source: ICAIL §§3–5; `doc/concepts/legal-modeling/`.
- **Part III — the syntax and its affordances.** Controlled natural language; words not sigils;
  indentation not parentheses; inert scaffolding, asyndeton, ditto marks, phrase-shaped
  identifiers. Source: ICAIL §7; [`../cnl-affordances/`](../cnl-affordances/). This part is where
  the book is most obviously "using L4", and it is the part most at risk of becoming the manual
  (§1) — it must keep answering ch. 2's break, not enumerate keywords.
- **Part IV — the reasoners.** Evaluation, the relational reading, the interview, checking,
  model checking, the game-theoretic frontier. Source: [`../formal-methods-in-law/`](../formal-methods-in-law/),
  whose §8 honest map is **mandatory** here: this part describes machinery in several states of
  existence, and the book must mark each one. **D12 — Part IV is written last**, because the
  shipped/designed boundary moves and a book that gets it wrong is worse than no book.
- **Part V — the limits, revisited with the machinery in hand.** Ch. 8's claims, now provable
  rather than promised: the determinacy strata, the avoidable-ambiguity tax, and what remains
  irreducibly a judgement. Source: [`../cls-determinacy-frontier/`](../cls-determinacy-frontier/).
- **Coda — why it matters at the level of a state.** [`../political-economy/`](../political-economy/).

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

1. **Selling the tool in the foundations.** Part I must be usable by someone who then goes and
   uses Catala, or Prolog, or nothing. If a chapter's concept only makes sense in L4, the concept
   is wrong or the chapter is marketing. The cash-out column (§4) points _from_ concept _to_
   affordance; it must never be run backwards to justify a feature.
2. **Rediscovering prior art (D7).** This project's own papers are strict about this — Bounded
   Deontics leads by conceding Anderson 1958 outright, and claims the boundary rather than the
   idea. A book that presents defeasibility or goal-relative obligation as ours is not credible to
   the fifty people whose opinion determines whether it is taken seriously. **Concede loudly,
   early, by name.**
3. **Overclaiming what runs.** See D12 and the FORMAL-PAPER §8 map. Present tense for what ships;
   named future tense for what does not.
4. **Pretending the limits are small.** Ch. 8 and Part V are not hedges; they are content. The
   argument is stronger, not weaker, for saying exactly where a formal model of a normative
   system stops — because that is the claim the reader is most suspicious of and most able to test.
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

- **Part I is a logic textbook written by non-logicians, for two audiences, neither of which
  wants a logic textbook.** The mitigation is D3 (no apparatus before its trouble) and the
  cash-out test, but this remains the single most likely way the book is bad. **Test it early:**
  the specimen exists so this can be judged on prose rather than on plan.
- **Length.** Eight foundation chapters plus a history chapter plus four parts is two books. The
  honest options are (a) Part I ships alone first as _An Introduction to Computational Law_, with
  the L4 material as its worked medium, or (b) the parts are ruthlessly thin. **Unresolved —
  and it changes the drafting order, so it is the next thing to decide.**
- **Citation integrity.** §5 is triage from memory, in the manner of
  [`../bounded-deontics/related-work.md`](../bounded-deontics/related-work.md): **nothing in it
  has been verified against a primary source in this session**, and items already known to be
  shaky carry `[verify]`. Dates, venues and page numbers must be checked before any of it is
  drafted, not before it is published. The repo has been burned here before; see
  [`../bounded-deontics/notes/citation-verification.md`](../bounded-deontics/notes/citation-verification.md).
- **The papers move.** The book assembles facets that are still being written; Part IV especially
  describes a moving boundary. D12 is the mitigation, and it is a scheduling constraint, not a fix.
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

1. **Decide the length question** (§10) — it determines whether Part I is a book or a part.
2. **Decide fragment-vs-file** (§7) — it determines the shape of every chapter.
3. **Judge the specimen.** If the voice is wrong, everything above is a plan for the wrong book.
4. **Verify §5's bibliography** against primary sources; promote or drop each `[verify]`.
5. **Draft chapter 0** (the history) before chapter 1 — it is the chapter whose research load is
   real, and the one whose absence would be noticed first.
