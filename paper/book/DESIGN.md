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
- an artifact can be **general** → quantification, and the ∀∃ shape of a well-formed rule (ch. 3);
- an artifact can be **amended by another artifact** → defeasibility, provisos, priority (ch. 4);
- an artifact can tell someone to **do** something → deontics, derived rather than declared (ch. 5);
- an artifact runs **against a clock** → time, process, race conditions (ch. 6);
- an artifact can be **run backwards** → abduction: what facts would make this conclusion hold
  (ch. 7), which is the wizard;
- an artifact can be **defective** → checking, and the tests it never shipped with (ch. 8);
- an artifact can be **deliberately unfinished** → open texture, standards, detect ≠ resolve (ch. 9).

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

A prologue and ten chapters. Every row names its exhibit (all already in this tree or its
bibliography) and its cash-out (**D4**: an uncashed row is cut). The grouping in the left column
is a reading aid, not a set of Parts — the unit is the chapter.

| #        | Chapter                                | The concept it opens with                                                       | The L4 it runs                                                                                    | The break that generates the next         | Exhibit                                                    |
| -------- | -------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ----------------------------------------- | ---------------------------------------------------------- |
| **0**    | Calculemus, and five graves            | The history, by failure mode (§5)                                               | —                                                                                                 | Why it might be different now             | Leibniz; the spreadsheet                                   |
| _core_   |                                        |                                                                                 |                                                                                                   |                                           |                                                            |
| **1**    | The smallest legal act                 | Subsumption; the syllogism; the major premise as artifact                       | `DECIDE … IF`; the evaluation trace as explanation                                                | The major premise is a _sentence_         | any two-element provision                                  |
| **2**    | The sentence that means two things     | Propositional structure; parse multiplicity; the canons as disambiguation rules | **The CNL surface**: words not sigils, layout as bracketing, phrase identifiers, asyndeton, ditto | One sentence at a time doesn't scale      | Oakhurst; Lockhart; Rogers/Bell                            |
| **3**    | Every person who                       | Predicate logic; quantifier scope; ∀∃ as the shape of good law                  | `DECLARE`, records, enums, `GIVEN`/`GIVETH`, `CONSIDER` exhaustiveness, the empty-set trap        | Real rules have exceptions                | British Nationality Act (CACM 1986)                        |
| **4**    | Unless, notwithstanding, provided that | Defeasibility; non-monotonicity; burdens and presumptions                       | Layered defeat; override graphs; the burden-of-proof monad                                        | Nothing yet tells anyone to _do_ anything | Jersey charity test (defeater on a defeater); PROLEG lease |
| _acts_   |                                        |                                                                                 |                                                                                                   |                                           |                                                            |
| **5**    | Must, may, must not                    | Deontics — **derived** from action, goal and consequence, not primitive         | `PARTY`/`MUST`/`HENCE`/`LEST`; the dominator `MUST`                                               | Obligations have clocks; clocks collide   | the daycare fine; contrary-to-duty                         |
| **6**    | The clock and the other party          | Traces, transition systems, concurrency, race conditions                        | `WITHIN`; trace semantics; `#TRACE`; the LTS                                                      | Now you have a rule base worth asking     | the PDPA breach-notice race                                |
| _asking_ |                                        |                                                                                 |                                                                                                   |                                           |                                                            |
| **7**    | Asking the rules questions             | Deduction, **abduction**, induction — and which of the three we refuse          | The relational reading; abductive planning; the ROBDD interview                                   | An answer can't show you it is wrong      | the eligibility interview                                  |
| **8**    | Checking                               | Verification as the missing test suite; the white-hat Bad Man                   | Dead letters, semantic diff, exhaustiveness, model checking                                       | Some questions aren't of this kind        | the corporate constitution; s415                           |
| _limits_ |                                        |                                                                                 |                                                                                                   |                                           |                                                            |
| **9**    | Where this stops                       | Open texture; vagueness; standards vs rules; **detect ≠ resolve**               | Enumerate-mode encoding; the ambiguity fork and its witness                                       | Who gets to check any of this             | _Poh Yuan Nie_ ¶28; the determinacy strata                 |
| **10**   | Seeing like a citizen                  | Legibility as civic infrastructure                                              | —                                                                                                 | —                                         | the political-economy facet                                |

Notes that are decisions, not commentary:

- **Chapter 2 is the syntax chapter, and that is the point.** The CNL material is not deferred to
  a later part: it arrives as the answer to chapter 1's break, which is the strongest possible
  motivation for it. A reader meets layout-as-bracketing five pages after watching a missing comma
  cost five million dollars.
- **Four chapters were merged or moved, not cut.** Old ch. 3 (quantification) and the type
  material became one chapter, because in L4 they are one thing — you quantify over a declared
  type. Old ch. 4 (the three inferences) moved from fourth to **seventh**: abduction is the mode a
  citizen actually needs, but you cannot demonstrate running a rule backwards until the reader has
  a rule base worth interrogating. Old ch. 8 (the limits) became **ch. 9**, still in the arc.
- **Ch. 7 is the chapter nobody else writes.** Deduction gets taught everywhere; abduction is
  mentioned and dropped. But _what would have to be true for me to qualify?_ is the citizen's
  actual question, and it is what the interview compiles to. Induction gets a section for one
  purpose: to say plainly that learning rules from decided cases is a different subject with a
  different failure mode, that we do not do it, and what we give up by not doing it.
- **Ch. 5 precedes ch. 6 although it needs less machinery than it looks.** Obligation is
  introduced as _derived_ (**D11**) — a `MUST` is a landmark on the paths to a goal — which needs
  actions and goals but not yet clocks. Clocks are what break it into ch. 6.
- **D8, amended.** The limits stay inside the arc rather than becoming an afterword — the original
  reason holds, and _detect ≠ resolve_ is a first-principles fact about what a formal model of a
  normative system can be. What changed is only its number: with no Part I to be inside, "ch. 8 is
  Part I, not an appendix" now reads "ch. 9 is a chapter, not an appendix."

**D9 — no probability in the rule graph.** Legal consequences are largely constituted, not
caused; the deadline lapsing _is_ the breach, not evidence of it. Uncertainty lives at the
fact-finding layer, and the book says so once, in ch. 1, and holds the line. (The standard-of-proof
exception is ch. 4's, and is flagged as living on the other side of the boundary.)

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
  and Prolog to ch. 3, PROLEG and Governatori to ch. 4, Pace's CL and the contract calculi to
  ch. 5–6, decision tables and DMN to ch. 3 and 8, HYPO and case-based reasoning to ch. 7's
  induction section, Szabo and the DAO to ch. 9. Each arrives as a short **prior-art sidebar**
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

| Facet                                                                | Lands in                        | Note                                                                                                             |
| -------------------------------------------------------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| ICAIL §§3–5 (constitutive/regulative; the two-layer architecture)    | chs. 3, 5 — and ch. 1's framing | Why the two get different formalisms rather than one logic; `doc/concepts/legal-modeling/`                       |
| ICAIL §7 + [`../cnl-affordances/`](../cnl-affordances/)              | **ch. 2**, then reprised        | The facet most at risk of becoming the manual (§1): it must keep answering ch. 1's break, not enumerate keywords |
| [`../bounded-deontics/`](../bounded-deontics/)                       | ch. 5                           | Obligation derived, not declared (**D11**); concede Anderson 1958 in the chapter, not a footnote (**D7**)        |
| ICAIL PROLEG appendix; the burden monad                              | ch. 4                           | The burden layer is the reason ch. 4 is not just "exceptions"                                                    |
| [`../formal-methods-in-law/`](../formal-methods-in-law/)             | chs. 7–8                        | Its §8 honest map is **mandatory**: this material is in several states of existence and each must be marked      |
| [`../cls-determinacy-frontier/`](../cls-determinacy-frontier/)       | ch. 9                           | The determinacy strata and the avoidable-ambiguity tax, which ch. 2 promised and only here can be measured       |
| [`../political-economy/`](../political-economy/)                     | ch. 10                          | The coda; ch. 1's reviewability point, grown up                                                                  |
| [`../case-studies/`](../case-studies/); `the-letter-and-the-spirit/` | worked examples throughout      | Jersey charity test → ch. 4; s415 → chs. 2 and 8; GCO → ch. 6                                                    |
| `doc/concepts/language-design/` (tables, trees, order)               | chs. 3, 8                       | Cited, not re-derived (**D10**)                                                                                  |

**D12, unchanged and now sharper.** The verification material (chs. 7–8) is **written last**,
because its shipped/designed boundary moves and a book that gets it wrong is worse than no book.
Under the old stacked plan that meant "write Part IV last"; under D13 it means the two chapters
are drafted after the other eight, even though they sit in the middle of the arc.

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
4. **Pretending the limits are small.** Ch. 9 is not a hedge; it is content. The argument is
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
- **Length — mostly resolved by D13, and the residue named.** Nine foundation chapters plus four
  parts was two books; a prologue plus ten interleaved chapters is one, because the concept
  material stopped being chapters and became the first third of chapters that had to exist anyway.
  What survives: **ch. 2 and ch. 4 are now doing two jobs each** (parse ambiguity _and_ the whole
  CNL surface; defeasibility _and_ burdens) and are the two most likely to split back into two,
  which would put the book at twelve. Watch them in drafting; do not pre-emptively split.
- **The prologue is now the only place the history argument is made in full**, and it has to carry
  the five graves and the scorecard without the parade behind it (§5). If it cannot, D6's split
  is wrong and the parade comes back — but as an appendix, never as a stacked chapter 0.
- **Citation integrity.** §5 is triage from memory, in the manner of
  [`../bounded-deontics/related-work.md`](../bounded-deontics/related-work.md): **nothing in it
  has been verified against a primary source in this session**, and items already known to be
  shaky carry `[verify]`. Dates, venues and page numbers must be checked before any of it is
  drafted, not before it is published. The repo has been burned here before; see
  [`../bounded-deontics/notes/citation-verification.md`](../bounded-deontics/notes/citation-verification.md).
- **The papers move.** The book assembles facets that are still being written; chs. 7–8 especially
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
   third page, which is what the restructure now requires of every chapter.
3. **Draft chapter 2**, not chapter 1, as the second specimen. Ch. 1 is written; ch. 2 is where
   D13 is actually load-bearing, because it has to teach the CNL surface _as the answer to a
   break_ rather than as a syntax tour. If ch. 2 can be written that way, the structure holds.
4. **Verify §5's bibliography** against primary sources; promote or drop each `[verify]`.
5. **Write the prologue** — it carries the history argument alone now (§10), so it is the test of
   whether D6's split works.
