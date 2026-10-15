# Specimen — the opening of Chapter 1

> **This is a specimen, not a chapter.** It exists so that the plan in [`DESIGN.md`](DESIGN.md)
> can be judged on prose rather than on outline: the pitch, the two-audience sidebar, the density,
> and whether the chapter-1 move (**D2**) actually lands when written out. It is roughly the first
> quarter of what the chapter would be.
>
> **It deliberately violates D5**: the L4 below is written in the idiom of
> `doc/courses/foundation/eligibility-rule.l4` but has **not been through the type checker** —
> there was no built `l4` in the session that drafted it. Nothing here should be quoted as
> working code until it is a file in the corpus with goldens.

---

## 1. The smallest legal act

Here is a rule. It is not a real one, but it has the shape of a real one, and by the end of this
chapter you will have made a machine execute it.

> A person is eligible for the grant if the person is at least eighteen years of age and has
> shown valid identification.

Now here is what happens when somebody uses it. An officer, sitting across from an applicant, has
a form and a decision to make. The applicant is twenty-five. The applicant has produced a
passport. The officer writes: _eligible_.

Three things happened there, and law has had names for them for two thousand years. There was a
**major premise** — the rule, in the abstract, about anyone at all. There was a **minor
premise** — the facts, about this person, in this chair. And there was a **conclusion**, which
followed. Aristotle would have recognised the form. So would a Roman jurist, a Talmudic scholar,
a common-law judge, and the officer, who has probably never thought about it in these terms and
does not need to.

The move is called **subsumption**: bringing a particular fact under a general rule. It is the
atom of legal reasoning. Everything else in this book — every logic, every operator, every
verification technique — is scaffolding around this one operation, added because at some point
subsumption alone was not enough.

Which raises the obvious question: why isn't it enough? We will spend seven chapters answering
that. But first, notice something about the syllogism above that the classical version does not
have.

## 2. The major premise is an artifact

The textbook syllogism runs:

> All men are mortal. Socrates is a man. Therefore Socrates is mortal.

The major premise there — _all men are mortal_ — is a claim about the world. Nobody wrote it.
Nobody voted on it. It cannot be amended in committee, it has no commencement date, and it does
not apply differently in Jersey.

The major premise of a legal syllogism is none of those things. _A person is eligible for the
grant if…_ is a **decision that somebody made and wrote down**. It has an author. It has a date.
It came into force at some moment and may cease to. It exists in a particular jurisdiction, in a
particular language, at a particular version, and it was different last year. Someone drafted it
under time pressure, and someone else will amend it under different time pressure.

This is the whole of computational law in one observation. **The major premise is an artifact**,
and artifacts are the kind of thing engineering knows what to do with:

- an artifact can be **wrong** — not false, but defective: self-contradictory, or impossible to
  comply with, or ambiguous in a way that costs five million dollars in overtime;
- an artifact can be **versioned**, which means two of them can be **compared**;
- an artifact can be **tested**, if you can execute it;
- an artifact can be **checked** — exhaustively, mechanically, by something that does not get
  tired at four in the afternoon.

None of that is available for _all men are mortal_. All of it is available for a statute, and
almost none of it is currently done.

> **If you are a lawyer**, this is the syllogism from your first week of law school, and the
> observation is one you already act on: you look up the commencement date, you check whether the
> provision has been amended, you argue about what the sentence means. You have always treated
> the major premise as an artifact. This book is about what becomes possible once a machine can
> treat it as one too.
>
> **If you are a programmer**, the major premise is the source code and the minor premise is the
> input. That analogy is exact and it will carry you a long way — but hold it loosely, because
> the ways it breaks are the interesting part. Source code has one author, one version in
> production, and no doctrine of interpretation. Statutes have none of those luxuries.

## 3. Writing the major premise down so a machine can hold it

Here is that rule in L4. Read it before we discuss it; if the design has worked, you can.

```l4
GIVEN applicant IS AN Applicant
GIVETH A BOOLEAN
DECIDE `the applicant is eligible for the grant` IF
    `the applicant is at least 18 years old` applicant
    AND `the applicant has shown valid identification` applicant
```

Four observations, which between them are most of what distinguishes this from every other way
of writing the rule down.

**It is the same sentence.** Not a paraphrase, not a flowchart of the sentence, not a table
derived from it — the same words, in the same order, with the same connective in the middle. You
can lay the statute and the encoding side by side and see that they say the same thing. That
property has a name in this field, **isomorphism**, and it is not an aesthetic preference: it is
what makes the encoding maintainable by the person who maintains the statute, and reviewable by
the person who is bound by it.

**The `AND` is doing real work.** It is not English punctuation; it is a commitment. The drafter
of the original sentence could leave it unsettled whether both limbs are required, and — this is
chapter 2 — very often does, by accident. Here you cannot. Writing the rule in this notation
forces the choice at the moment of drafting, which is roughly nine years and one lawsuit earlier
than the alternative.

**`the applicant is at least 18 years old` is a name, not a comment.** It is an identifier that
happens to be an English phrase, and it refers to a rule defined elsewhere, which you can go and
read:

```l4
GIVEN applicant IS AN Applicant
GIVETH A BOOLEAN
`the applicant is at least 18 years old` MEANS
    applicant's `the applicant's age` >= 18
```

So the structure of the encoding follows the structure of the reasoning: a conclusion, resting on
sub-conclusions, resting eventually on facts. This is the shape a legal argument already has. It
is also the shape of the explanation the machine will give you when you ask it _why_ — which is
the subject of §6, and, in a longer view, the reason any of this is worth doing.

**`GIVEN` and `GIVETH` are the premise structure, made explicit.** `GIVEN applicant IS AN
Applicant` says what the minor premise must supply. `GIVETH A BOOLEAN` says what conclusion comes
back. The rule is a function from facts to a legal consequence, and the two lines at the top are
its contract with whoever brings it a case.

## 4. The division of labour, which is not a technical detail

Look again at what the officer did, because there is a seam in it that this book will return to
until you are tired of it.

The officer did **two different jobs**. The first was finding the facts: is this person
twenty-five? Is that passport valid? That job requires eyes, a document scanner, judgement about
whether the photograph matches the face, and — in the hard cases — a hearing, evidence, and
someone empowered to disbelieve. The second job was applying the rule to those facts, and that
job requires nothing but care.

Machines are exceptionally good at the second job and have no business whatever doing the first.

Almost every disaster in the history of automated legal decision-making comes from confusing
them: a system that decides, on its own authority, that a person's circumstances _are_ such-and-such,
and then applies a rule to a fact it invented. The architecture in this book keeps the seam
visible, and does so by construction: the facts are inputs, they come from somewhere accountable,
and the rule is the only thing the machine gets to hold an opinion about.

That is also why the syllogism matters beyond pedagogy. **The reason law has always been argued
in this form is that the form makes a decision checkable by somebody other than the person who
made it.** Write out the major premise, the minor premise, and the step between them, and a
second person — an appellate judge, an auditor, the applicant — can find precisely which of the
three they disagree with. A decision delivered without that structure ("the department has
determined that you are not eligible") is not reviewable; it is only appealable to whoever
delivered it.

Executing rules by machine is either an enormous advance in that reviewability or a catastrophic
loss of it, and which one it turns out to be depends entirely on whether the machine can show its
syllogism. Hold that thought: it comes back in chapter 8 with teeth, and again at the end of the
book, where it stops being a point about software and becomes a point about states.

## 5. So what breaks?

We have a rule, a machine that runs it, and an explanation that a human can check. If this were
all law required, the book would end here, and the history in chapter 0 would not be a history of
repeated failure.

Here is the first crack, and it is not where you expect. It is not that the logic is too weak —
we have not even met a rule with an exception yet. It is that **the major premise is a sentence**,
and sentences are not as well-behaved as the last four pages have quietly assumed.

Consider a real one. Maine's overtime law exempted, from the requirement to pay time-and-a-half,
the

> canning, processing, preserving, freezing, drying, marketing, storing, packing for shipment or
> distribution of

certain perishable foods. A dairy company's drivers **distributed** perishable food. They did not
pack it. Were they exempt?

That depends on whether the list ends with two activities — _packing for shipment_ and
_distribution_ — or with one: _packing, for shipment or distribution_. There is no comma to tell
you. The First Circuit, in 2017, held the sentence ambiguous, construed it in the drivers'
favour, and roughly five million dollars changed hands.

Every word of the rule was clear. The logic was trivial. **The parse was not.**

That is chapter 2.
