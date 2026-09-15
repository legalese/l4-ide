---
title: What the machine can decide
status: outline
date: 2026-09-15
facet: formal-methods-in-law/
words: 0
license: CC-BY-NC-4.0
sources_checked: never
---

**STATUS 2026-09-15: OUTLINE, NOT A DRAFT.** No prose has been written. This file records a
conversation and the shape a post could take, so the material is not lost. It sits in
`blog/candidates/` rather than `blog/posts/` on purpose: it carries no arc number, and
`check-post.sh` would fail it on length and on `status:`. Whoever adopts it assigns the number,
flips `status:` to `draft`, and moves the file. **Nothing here has been fact-checked** —
`sources_checked: never` is accurate, and every citation below is marked with who is confident
about it and on what basis.

---

## The occasion

A computer science undergraduate, after an L4 talk, asked: _"Random question I had, totally
unrelated, but is the FSM stuff to say that law is a regular grammar?"_

The question is aimed wrong and is better than it looks, which makes it a good cold open under
STYLE.md §3. The reader we want is the one who would have asked it.

## The claim, in one sentence

**The verification you can get is fixed by the fragment you project into and the question you ask
of it — not by the language you wrote in.**

If that does not fit a title, the post is two posts. Candidate titles, all sentences per §6:
"What the machine can decide"; "Every verifier is an argument about what to throw away".

## Beat 1 — the question is aimed at the wrong alphabet

The student's inference is valid given its premise: finite automaton ⟺ regular language ⟺ regular
grammar is Kleene's theorem, and it is not in dispute. The premise is where it slips.

- **Ask what the alphabet is.** When a contract is drawn as an automaton, the strings it accepts
  are not legal documents. They are traces of events — `buyer_pays`, `seller_delivers`,
  `30_days_elapse`. The language is a set of behaviors, not a set of texts.
- **So two questions hide under one.** (1) Is legal _text_ regular? That is a question about
  English, not about law, and the answer is no — Shieber's Swiss German result is the standard
  citation for natural language sitting above context-free. We do not parse statutes with a finite
  automaton. (2) Is the set of compliant _behaviors_ regular? That is the question worth the
  reader's time.
- **A model is not a theorem.** Flood and Goodenough's contract-as-automaton is a modeling claim
  about particular contracts. Same register as "I modeled this protocol as a state machine";
  nobody concludes that networking is regular. Their completeness check is explicitly relative to
  a chosen alphabet, and choosing the alphabet does a great deal of the work.

## Beat 2 — where contracts leave the regular languages, and the reframe

Four exits. Each one is visible in our own tooling, which is what keeps this beat concrete rather
than a lecture on the Chomsky hierarchy.

| Exit           | What breaks                                                                 | Where we already hit it                                                                           |
| -------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Counting       | A running balance or cumulative threshold is unbounded state; pumping lemma | `Threshold` joins — `SOME 2 OF …`, `sum OF amount AT LEAST rent`                                  |
| Recursion      | A renewal cycle needs a counter to terminate                                | `P-CYCLE`: the state graph says a duty renews, not that it renews with one fewer cycle left       |
| Quantification | The cast is unbounded and known only at run time                            | `EVERY Tenant t`; ruling R-T6                                                                     |
| Concurrency    | _n_ obligations outstanding at once is a marking, not a state               | The barrier-versus-fork distinction; why a marked net beats a deterministic finite automaton here |

Then the reframe, which is the part the conversation actually turned on:

- **Turing-completeness is a property of a formalism. Decidability is a property of a question
  about a formalism.** One implication holds, one does not.
- **Forward, it holds.** Rice's theorem: in a Turing-complete formalism every non-trivial semantic
  property of programs is undecidable.
- **Backward, it fails, and this is the part that gets skipped.** "Not Turing-complete" buys
  nothing on its own. The cleanest witness is the one the post should lead with: **Petri nets are
  not Turing-complete; reachability is decidable; language equivalence is undecidable.** Same
  formalism, three questions (add coverability), three different answers.
- **So the object is the pair — (fragment, question).** "Is it Turing-complete?" interrogates half
  of it.
- **Our own case makes it vivid.** L4 is Turing-complete: `jl4/examples/ok/desc.l4:4` defines
  `factorial` by unrestricted self-recursion over the integers, there is no termination checker in
  `TypeCheck.hs`, and divergence is caught by a run-time frame-depth guard
  (`Machine.hs:474-481`) — a seatbelt, not a decision procedure. By Rice, nothing non-trivial about
  an arbitrary L4 program is decidable. And we ship verification anyway.
- **The resolution is the architecture.** We never model-check the L4. We model-check a
  _projection_: the ladder is propositional, so a reduced ordered binary decision diagram; the
  state graph is finite-state, so linear temporal logic model checking, decidable; the decision
  table is a decision table, so completeness and overlap. Each projection is a deliberate lossy
  descent into a fragment where the question we want has an answer. **The fidelity report is the
  receipt for what the descent cost.**

## Beat 3 — what this does not show

Per §3, the post is a pitch without this beat. Four concessions, in descending order of how much
they cost us:

1. **This is Cousot and Cousot, 1977.** Sound over-approximation to buy decidability is abstract
   interpretation, and it is old. We are applying a known idea to a domain that had not had it, not
   inventing the idea. The computational-law veteran persona in §7 exists to catch exactly this
   kind of unearned novelty, and the post should concede it before that reader does.
2. **Decidable is not tractable.** Petri net reachability is decidable and Ackermann-complete.
   Coverability is EXPSPACE-complete. "There exists an algorithm" and "you will get an answer this
   week" are different sentences.
3. **A decidable question can have a useless answer.** Our own structural reachability is an
   over-approximation — recorded as G9 in the LTS visualizer spec — which means it can report a
   state as reachable that no run reaches. A green result from an over-approximating analysis
   carries less than it looks like it carries, and saying so is the whole point of beat three.
4. **The fidelity report is a claim we make about ourselves.** It is only as good as our own
   accounting, and we have shipped at least one gap it did not name: a barrier and a fork exported
   to byte-identical process models, and the report that exists to list the losses was silent about
   it. Located 2026-09-14, fixed forward. A post that cites fidelity reports as the answer should
   admit that one of them had a hole.

## Material we already hold

Everything in the table above is in the tree and was read on 2026-09-14/15. That matters for §4:
these are things we can show, not things we assert.

- `jl4/examples/ok/desc.l4` — the recursive `factorial`, in the corpus, checked in.
- `jl4-core/src/L4/EvaluateLazy/Machine.hs:474-481` — `maximumFrameDepth`, `StackOverflow`.
- `jl4-core/src/L4/StateGraph.hs` — the Flood-and-Goodenough lineage is stated in the module
  header; `P-CYCLE` and its comment about the lost termination argument.
- `specs/todo/lexipedia-superset/LTS-VISUALISER.md` — G9, and §4.9 on the join that never reached
  the projections.
- `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md` — the barrier/fork pair, R-T6 on the run-time cast.

## Sources to check before this becomes a draft

None of these has been opened. Confidence is the drafter's prior, not a check.

- Kleene 1956 (automata ⟺ regular sets) — standard, low risk.
- Rice 1953 — standard, low risk.
- Shieber 1985, Swiss German is not context-free — standard; **state it as a claim about natural
  language, not about English specifically**, since the English case is contested.
- Flood and Goodenough, "Contract as automaton", _Artificial Intelligence and Law_ 30:391-416,
  2021 — already cited in the LTS visualizer spec's reference list.
- Hack 1976, equivalence of Petri net languages is undecidable — **high confidence, unverified.**
  This is the witness beat 2 rests on; if it does not check out, the beat needs rebuilding.
- Mayr 1981 and Kosaraju 1982 for decidability of reachability; Leroux, and Czerwiński with
  Orlikowski, 2021, for Ackermann-completeness — **high confidence, unverified**, and the 2021
  attribution in particular should be got right, since two groups arrived independently.
- Lipton 1976 and Rackoff 1978, coverability is EXPSPACE-complete — high confidence, unverified.
- Dufourd, Finkel and Schnoebelen 1998, reset nets: reachability undecidable while coverability
  stays decidable — high confidence, unverified. A second witness for beat 2 if Hack fails.
- Apt and Kozen 1986, parameterized verification undecidable in general — high confidence,
  unverified. Pair it with the cutoff results so the paragraph is not purely negative.
- Cousot and Cousot 1977 — standard, and it carries concession 1.

## What a drafter has to decide

- **Does this stand alone, or fold in?** It overlaps post 4 ("What the compiler checks") and post 6
  ("The missing test suite"). One post makes one claim — so either this is post 10 and 4 and 6 hand
  it the decidability material, or it is three sections inside post 4 and this file is retired. A
  drafter should not split the difference.
- **Which facet?** `formal-methods-in-law/` is the closest fit, and post 6 already claims that
  facet plus the backend portfolio. If both land, they need different facet sections.
- **How much Chomsky hierarchy does the target reader want?** STYLE.md §1's reader is a working
  programmer, not a theory student. The four-exit table may carry the whole argument with the
  hierarchy left implicit.
- **Meng's framing, 2026-09-15:** this material becomes necessary once the series reaches symbolic
  execution and static analysis, where expressiveness and decidability have to be discussed
  together with how different model checkers treat them. That suggests the post lands late in the
  arc, or that the arc grows a technical sub-thread. Not decided.

## Provenance

Conversation between Meng and Claude Opus 5, 2026-09-14/15, session `lts-diagrams`
(`00af28a4-99c8-4bf0-b330-3f4b4191569b`). The student's question is quoted as Meng relayed it.
