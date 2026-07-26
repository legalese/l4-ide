# The Gödel loophole — notes toward a spec

Status: **notes**, and explicitly a **victory lap**. Gated behind [[yc-safe-executable]] and
[[corporate-resolutions-lts]] succeeding first. Captured 2026-07-27.
Branch: `docs/godel-loophole-spec`. Worktree: `~/src/legalese/l4wt/godel-loophole`.

---

## 1. The story, and what is actually documented

Kurt Gödel's US naturalisation examination, **Trenton NJ, December 5 1947**, before **Judge Philip
Forman**, with **Albert Einstein** and **Oskar Morgenstern** as witnesses. Gödel took the oath on
**2 April 1948**.

The primary source is a **four-page memorandum Morgenstern wrote on 13 September 1971**, twenty-four
years after the fact. His widow Dorothy Morgenstern Thomas gave a copy to the Institute for Advanced
Study on 30 August 2005; it sits in the **Dorothy Morgenstern Thomas collection (`SMC.THOMAS`)** at
IAS, and a PDF is online.

The operative claim, as Morgenstern reports it: Gödel told him that on reading the Constitution he
had, to his distress, found

> some inner contradictions … and that he could show how in a perfectly legal manner it would be
> possible for somebody to become a dictator and set up a Fascist regime never intended by those who
> drew up the Constitution.

**Gödel never wrote down what the contradiction was.** That is the single most important fact for
scoping this work.

Jeffrey Kegler, who did the archival legwork
(<https://jeffreykegler.github.io/personal/morgenstern.html>), is deliberately deflationary: the
memorandum is "brief and cryptic", Morgenstern himself notes he did not check dates, and Kegler
reports that other second- and third-hand Gödel anecdotes he chased proved "almost certainly false".
His conclusion is flat: **"Nobody seems to know what Gödel's proof was."**

Treat the story as **folklore with a documented core**, and be scrupulous about which is which. A
project that overclaims here would deserve everything it got.

---

## 2. Why this is not a stunt — the connection to the other two arcs

All three arcs are the same problem wearing different clothes: **self-reference in a normative
system**.

| Arc                           | The circularity                                                                           |
| ----------------------------- | ----------------------------------------------------------------------------------------- |
| [[yc-safe-executable]]        | the SAFE's value depends on the company's valuation, which depends on the SAFE            |
| [[corporate-resolutions-lts]] | who may change the rule that says who may change the rules (amendment thresholds, layers) |
| **Gödel**                     | the amendment rule applied **to itself**                                                  |

So this is the capstone of a coherent programme, not a change of subject. And the middle arc is
genuinely preparatory — see §3, which is the good bit.

---

## 3. The corporate arc is a scale model, and it has the answer

`CoA1967` **s26A — "Power to entrench provisions of constitution of company"** turns out to be a
worked, statutory solution to precisely the regress Gödel is said to have found:

- **26A(1)** — an entrenching provision may be included at formation, or inserted later **only if
  all the members agree**.
- **26A(2)** — it may be **removed or altered only if all the members agree**.
- **26A(3)** — "The provisions of this Act relating to the alteration of the constitution of a
  company are **subject to** any entrenching provision in the constitution of a company."

Set that beside the constitutional case:

|                                         | Company (Singapore)                       | US Constitution                      |
| --------------------------------------- | ----------------------------------------- | ------------------------------------ |
| Amendment rule                          | s26(1) — special resolution               | Article V                            |
| **Where does the amendment rule live?** | **In the Act — outside the constitution** | **Inside the Constitution**          |
| Can the actor amend the amendment rule? | **No.** s26 is statute.                   | **Yes.** Article V is amendable.     |
| Entrenchment                            | s26A — statutory, unanimity to remove     | Article V's own entrenchment clauses |
| Is the entrenchment itself reachable?   | **No** — s26A is statute                  | **Yes** — by amending Article V      |
| The regress                             | **closed by a higher layer**              | **open**                             |

**That is the whole thesis in one table.** Company law closes the self-amendment regress by putting
the meta-rule in a layer the actor cannot reach. The US Constitution cannot, because Article V is
inside the document it governs. **The alleged Gödel loophole is the observation that the regress is
open** — which is exactly Guerra-Pujol's reading (§4).

This also generalises the finding already recorded at
`corporate-resolutions/SPEC-NOTES.md` §2.5: **precedence is not a hierarchy, it is a question of
which layer each rule lives in and who can reach it.** The Gödel case is the limit point — what
happens when the layers collapse into one.

It is likewise the limit point of the **temporal rule-version axis** (`TEMPORAL-RULE-VERSION-DESIGN`
/ [[temporal-rule-version]]): that axis answers "which version of the rules governed at time T";
self-amendment is "the rules at T+1 are what you get by applying the rules at T to themselves."
Same axis, pushed until it becomes reflective. Also squarely relevant to `HOMOICONICITY-SPEC.md`.

---

## 4. The scholarship — and the honest state of play

**The candidate answer.** F. E. Guerra-Pujol, _Gödel's Loophole_, **41 Capital University Law Review
637 (2013)** (SSRN `2010183`). Thesis: Article V's amendment procedure **self-applies** — it can be
used to amend Article V itself, including its own entrenchment clauses, and can be amended
**downward** ("anti-entrenchment"), making future amendment progressively easier. If the amending
clause can amend itself, every express and implied limit on the amending power can be dissolved by
self-amendment. He argues the problem is unsolvable.

**The prior literature, which long predates the Gödel framing** — verify citations before relying on
them, but the lineage is:

- **Alf Ross**, _On Self-Reference and a Puzzle in Constitutional Law_, Mind 78 (1969) — argues that
  an amendment clause cannot coherently be used to amend itself.
- **H. L. A. Hart**, _Self-referring laws_ (1964) — the opposing side of that exchange.
- **Peter Suber**, _The Paradox of Self-Amendment: A Study of Logic, Law, Omnipotence, and Change_
  (Peter Lang, 1990) — the book-length treatment, and the one to read first. Argues against Ross.

**So "Gödel's loophole" is, on the leading reconstruction, an instance of the Ross–Hart–Suber
self-amendment paradox.** That is worth saying plainly: the interesting object is a well-studied
problem in legal philosophy, and the Gödel story is the hook, not the contribution.

---

## 5. What we can and cannot claim — scope discipline

**There is no ground truth here.** This is the sharpest contrast with the SAFE arc, where van der
Meyden supplies findings to reproduce and we can check ourselves against him. Gödel wrote nothing
down. "Reproduce Gödel's finding" is **not a well-defined target** and must never be stated as the
deliverable.

**Not achievable:**

- Establishing what Gödel actually had in mind. Unknowable from the record.
- Any claim that a path we exhibit **is** his.

**Achievable, and worth doing:**

1. **Formalise Article V** and the constitutional provisions it reaches.
2. **Reachability**: from the current text, is there a legal sequence of amendments reaching a target
   state — entrenchment removed, threshold lowered, an arbitrary provision installed? This is a model
   checking query and it is the same shape as the P2f/dominator work in the corporate arc, run
   forwards instead of backwards.
3. **Exhibit the space of paths**, not "the" loophole. A general capability beats a historical
   curiosity, and it is honest.
4. **State precisely what would count as a candidate** — a formal predicate for "is a Gödel-style
   loophole". That is arguably the real contribution: the literature argues about the paradox in
   prose, and nobody has written down the acceptance condition.

**The genuine technical hazard, and the reason this is last.** This is **not ordinary reachability
over a fixed transition system.** The amendment rule mutates the rule set, including itself, so the
transition relation is _mutable by the transitions_. That is a reflective system, and it is harder
than anything in the other two arcs. Do not start here. The corporate arc's layered model — where
the meta-rule is fixed because it lives in statute — is the tractable special case, and building it
first is what earns the right to attempt the general one.

---

## 5a. The testbed: Fluxx and Nomic

**Nomic closes the loop with §4.** Peter Suber invented Nomic in 1982 and published it as
**Appendix 3 of _The Paradox of Self-Amendment_** — "Nomic: A Game of Self-Amendment"
(<https://legacy.earlham.edu/~peters/writing/nomic.htm>). So the book §4 recommends reading first
_contains the game_. Suber did not merely write about self-amendment; he shipped an **executable
model** of it. Nomic is the operational semantics for the paradox, and it is small enough to encode
in full — which the US Constitution is not.

**Nomic's structure is entrenchment made explicit.** Its initial ruleset is divided into **mutable
and immutable** rules, and an **immutable rule must first be _transmuted_ into a mutable one before
it can be amended or repealed.** Line that up with §3:

| System          | Entrenchment                          | The regress                       |
| --------------- | ------------------------------------- | --------------------------------- |
| US Constitution | Article V's own clauses, amendable    | **open**                          |
| Company (s26A)  | statutory, unanimity to remove        | **closed by a higher layer**      |
| **Nomic**       | immutable rules, transmutable by rule | **open, but explicitly modelled** |

Nomic sits **between** the two cases and is the more useful of the three to build on, because it
makes the transmutation step legal, visible and finite — which is exactly what neither the
Constitution nor company law does openly. It is the controlled experiment.

**Fluxx and Nomic are a ladder, and it is the same ladder as the whole programme.** The distinction
that matters is the _size of the rule-change space_:

| Game      | How rules change                           | Rule-change space                                                                       | Analogue                                 |
| --------- | ------------------------------------------ | --------------------------------------------------------------------------------------- | ---------------------------------------- |
| **Fluxx** | playing cards from a **fixed deck**        | **finite and known in advance** — essentially the powerset of the New Rule / Goal cards | the bounded-configuration corporate case |
| **Nomic** | proposal and vote, **players author text** | **open and unbounded**                                                                  | the Article V / Gödel case               |

So **Fluxx is bounded self-modification and Nomic is unbounded** — precisely the distinction between
[[corporate-resolutions-lts]] (bounded by statute the actor cannot reach) and this arc (open). That
makes them a scale model of the entire programme that fits on a table, with **no jurisdiction, no
client and no ground-truth problem**.

**Both break Game Description Language, for our reason.** GDL and GDL-II, and the Card Game
Description Language (Springer 2013, demonstrated on poker variants, Blackjack and UNO), all assume
a **fixed ruleset over changing state**. Fluxx and Nomic invert that: **the rules _are_ the state.**
That is the same defect that makes self-amendment resist ordinary reachability (§5), in a domain
where we can iterate cheaply. If the encoding cannot do Fluxx, it will not do Article V.

**Prior modelling work** — found by search, **authors and venues not yet verified**, treat as leads:

- **"Minimum Nomic: A tool for studying rule dynamics"** — a reduced Nomic that keeps the essence
  while promoting evolvability of the self-amendment game.
- **"Reasoning and Reflection in the Game of Nomic: Self-Organising Self-Aware Agents with Mutable
  Rule-Sets"** — normative multi-agent systems. The title alone names our open question 1: _self-aware
  agents with mutable rule-sets_ is the reflective-evaluator fork.
- **Fluxx appears to be essentially unmodelled formally.** Searching turns up only its use as a
  _pedagogical_ device for teaching use-case modelling. If that holds up, the gap is an opportunity
  rather than a problem — but check properly before claiming it.

**The concrete first target, and it should probably come before anything in this file.** Fluxx's rule
space is finite, so real properties are decidable by enumeration:

- **Can Fluxx deadlock?** Reach a state where no legal move exists, or where the Goal is unreachable
  — e.g. rule cards that make the draw/play counts jointly unsatisfiable, or a state with no Goal in
  play. This is a **liveness** question with a yes/no answer over a finite space.
- **Is a given state winnable, and by whom?** Reachability, again finite.

That is a genuine model-checking result, on a system whose entire ruleset fits on a few cards, and
it exercises exactly the machinery this arc needs. **Do Fluxx first.** It is cheap, it is finite, it
is publishable-adjacent, and failing at it is a much better way to discover the encoding is wrong
than failing at the US Constitution.

---

## 6. Open questions

1. **Does the evaluator have to go reflective, or can self-amendment be staged?** If each amendment
   produces a new rule-set version and evaluation is always against a fixed version, the reflection
   is pushed into the version-generation step. That may be enough — and it is exactly what
   [[temporal-rule-version]] already does. Resolve this before any implementation.
2. **Where does the fixpoint bottom out?** Is a legal system with an open self-amendment regress
   genuinely inconsistent, or merely unbounded? Ross says one thing, Suber another. An encoding
   ought to make the disagreement precise rather than pick a side.
3. **Is the "dictatorship" target formalisable at all?** Guerra-Pujol's path reaches
   _anti-entrenchment_, which is well-defined. "Fascist regime" is not. Target the former; the latter
   is rhetoric and should be flagged as such.
4. **Jurisdictional honesty.** The US Constitution is the story, but the machinery gets built on
   Singapore company law. Say so up front rather than implying US-law expertise we do not have.
5. **Should this be a paper?** It fits the `determinacy-frontier` / detect≠resolve facet of
   [[l4-papers-series]], and the s26A comparison of §3 is a genuinely new observation as far as these
   notes can tell. Worth a literature check against Suber before claiming novelty.

---

## 7. Next actions — all gated

- [ ] **Gate: do not start the _constitutional_ work until the SAFE and corporate arcs have shipped
      something real.** §5a's Fluxx work is **not** gated — it is cheap, finite, and the right way to
      find out early whether the encoding can do self-modification at all.
- [ ] **Encode Fluxx and check for deadlock** (§5a). Finite rule space, decidable, no jurisdiction,
      no client, no ground-truth problem. Probably the first thing to do in this whole file.
- [ ] Encode Suber's Nomic initial ruleset — small, complete, and entrenchment is explicit in it.
- [ ] Read Suber, _The Paradox of Self-Amendment_. Cheapest high-value step, and it may moot §5(4).
      Note that the game is **Appendix 3 of that same book**, so this action and the previous one are
      one purchase.
- [ ] Verify authors/venues for the two Nomic modelling leads in §5a, and confirm whether Fluxx
      really is formally unmodelled before saying so anywhere public.
- [ ] Read Guerra-Pujol properly, not via abstract.
- [ ] Pull the Morgenstern PDF from the IAS `SMC.THOMAS` collection and read the actual four pages
      rather than the legend.
- [ ] Verify the Ross / Hart citations in §4.
- [ ] Settle open question 1 (reflective vs staged) — it is the fork the whole design hangs on.
- [ ] Write up the §3 s26A comparison regardless; it stands on its own, needs none of the above, and
      is the part most likely to be genuinely new.
