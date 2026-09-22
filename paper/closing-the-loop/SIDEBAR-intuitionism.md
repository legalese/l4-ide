# Sidebar: Intuitionism is not about intuition

## Why the trace is the answer, and not a report about the answer

> **Status:** CAPTURED 2026-09-22 from a working conversation, in support of the main paper's
> argument about traces. It is a conceptual note, not a research pass: nothing here was read out
> of a source in the session that produced it.
>
> **Everything below is written from the model's own knowledge**, and the history in §1 and §3 is
> the part most likely to need correction. Before any of this is published, check: Brouwer's
> formulation of the *Urintuition* and its derivation from the perception of time; the date and
> character of *Life, Art and Mysticism*; the precise scope of his rejection of excluded middle
> (it is a rejection for infinite domains, not a blanket one); and the exact behaviour of
> `Classical.em` in current Lean, which is stated here loosely.
>
> The argument in §4 to §6 does not depend on the history being exactly right. The history is
> there because it is a good joke, and because the joke is *true about the structure* even if a
> date is wrong.

---

## 1. The false friend

Brouwer's *intuition* is a term of art, and it is not the everyday word.

He took it from Kant: the *Urintuition*, the primordial intuition of two-oneness, which he held
arose from the mind's apprehension of the passage of time.
It names a thesis about what mathematics **is** — mental construction, an activity performed by a
mathematician, rather than the discovery of objects that were sitting there beforehand.

So "intuitionism" does not mean "the school that trusts hunches".
It means "the school that holds mathematics to be constructed rather than found".

## 2. What follows, and why it is the opposite of a hunch

The thesis has a severe consequence, and the severity is the whole point.

If a mathematical object exists only insofar as it has been constructed, then you may not assert
that something exists until you have exhibited it.
Excluded middle goes, at least over infinite domains.
Proof by contradiction of an existence claim goes with it: showing that the non-existence of a
thing leads to absurdity does not hand you the thing.

"There must be such a number" stops being an answer.
Only "here it is" counts.

Which makes the naming a perfect false friend.
Colloquial intuition is **seeing without showing**.
Brouwerian intuition is the faculty of **showing**, and nothing that fails to show is admitted.

## 3. The joke is biographical

Brouwer was a mystic.

*Life, Art and Mysticism* is his, and so is a long hostility to formalism — a conviction that
language was a degraded and unreliable vehicle for the mathematician's inner constructions, and
that Hilbert's programme was a betrayal of the subject rather than a rescue of it.
The most Dionysian figure in the foundations crisis produced the most Apollonian artifact in the
discipline.

And then the machines arrived and took **his** logic, out of all the logics on offer, precisely
because it was the one that refuses leaps.
The proof assistants run on constructive foundations.
In Lean, classical reasoning is something you reach for deliberately, and reaching for it marks
what you have built as a thing that cannot be executed.

A man who thought formalisation was a desecration of mathematics is now the foundation of every
machine that checks it.

## 4. Curry–Howard: the witness and the derivation are one object

This is where the naming stops being a curiosity and becomes the argument.

Under the Curry–Howard correspondence, a constructive proof **is** a program.
Not "corresponds to", not "can be compiled into" — is.
The witness and the derivation are the same object, which is why a proof you can check is also a
proof you can run.

Classical logic hands you truths with no witnesses attached.
They are perfectly good truths.
They are not artifacts you can execute, and they do not carry with them the thing they assert the
existence of.

## 5. A model's leap is a non-constructive existence claim

Now put a language model in the position of the classical prover.

The answer arrives. It is frequently correct. It carries nothing.

Dziri et al.'s measurement is the sharpest available statement of this: on multi-digit
multiplication of a shape unseen in training, **82.3% of the final answers that were correct had
at least one error in the computation graph that produced them** (*Faith and Fate*, NeurIPS 2023 —
see the main paper's citation notes).
Four right answers in five, arrived at by a route that does not support them.

That is non-constructive correctness, and it is exactly what intuitionism was built to refuse.
The hit rate is not the objection.
The objection is that a correct answer with no exhibited construction is, in the constructive
sense, **not knowledge** — and no amount of it accumulating changes that, because the defect is
categorical rather than statistical.

It also explains why the obvious remedy does not work.
If you audit **outputs** — benchmark scores, spot checks, a partner skimming the memo — you cannot
detect this failure at all, because in every instance of it the output is *right*.
The only things that catch it are executing the composition somewhere auditable, or checking the
chain step by step.

## 6. What this buys the paper's argument

The main paper shows that four sentences of prose admit three implementations that disagree by up
to four days.
This sidebar says why that finding generalises past deadline arithmetic.

An encoding that evaluates produces its answer **by** producing its derivation.
The trace is not instrumentation bolted onto a result, not a log, not an explanation generated
after the fact and hoping to be faithful to a computation it did not perform.
It is the same object as the answer, in the same sense that a constructive proof is the same
object as its program.

Which is the reply to anyone who treats auditability as a compliance feature to be priced
separately.
Strip the trace off and you have not removed a report about the answer.
You have removed the only thing that made it an answer rather than a guess that landed.
