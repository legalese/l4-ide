# 1. Definitions and scope

One area of the phrasebook. The index, the preamble and the other ten areas are in
[source-patterns.md](../source-patterns.md).

<a id="e1-1"></a>

## 1.1 "In this Act, X means Y" — the term the text fixes

**If the source says**

> `PAA s 2 — "court" means the General Division of the High Court or a Family Court`
>
> — `jl4/examples/legal/sg-succession/cleanroom-2026-08/family-domain.l4:172`

**It is doing** The drafter has written the right-hand side down, so the meaning is settled for
every reader of the Act. It is not a fact about the case in front of you.

**Write** a definition: a `DECLARE` when the definition is a closed list of things, a `MEANS`
decision when it is a test.

```l4
§ `Interpretation`

-- "court" means the General Division of the High Court or a Family Court
DECLARE Court IS ONE OF
    `the General Division of the High Court`
    `a Family Court`

GIVEN c IS A Court
GIVETH A BOOLEAN
`the grant was made by a Family Court` MEANS
    CONSIDER c
    WHEN `a Family Court` THEN TRUE
    OTHERWISE FALSE
```

**Not** a section `GIVEN`, and not an `ASSUME`. Both say the caller supplies the value — which here
would mean letting the caller decide what "court" means in the Act. The section `GIVEN` is for the
**case**, never for the **term**.

**The tell**, and it is the whole of [entry 1.2](#e1-2): if you can write the right-hand side from the statute,
it is a definition. If the right-hand side is "whatever this case happens to be", it is an input.

**When one sentence is both — and this is common.** _"In this Part, 'the applicant' means a person
who has applied for a licence under section 6"_ is an entry-1 sentence that names an entry-2 role.
The tell answers **yes** — the right-hand side is written down — and the answer is still incomplete,
because "the applicant" is also the role every later section is about. The "Not" above forbids
making the **meaning** an input; it does not forbid the Part from also having a case. So write both
halves, and do not let the prohibition talk you out of the role:

```l4
-- 5. In this Part, "the applicant" means a person who has applied for a
--    licence under section 6.

DECLARE Applicant HAS
    `has applied for a licence under section 6` IS A BOOLEAN
    `age in years`                              IS A NUMBER

-- The DEFINITIONAL half: the test the drafter wrote down, asked of any person.
@ref Licensing Act s 5
GIVEN `the person` IS AN Applicant
GIVETH A BOOLEAN
`s 5 — the person is the applicant` `the person` MEANS
        "a person who has applied for a licence under section 6"
    ... `the person`'s `has applied for a licence under section 6`

§ `Part 2 — Licences`
    -- The ROLE half: which person this run is about. "In this Part" is the scope.
    GIVEN `the applicant` IS AN Applicant

@ref Licensing Act s 6(1)
GIVETH A BOOLEAN
`s 6(1) — the applicant may be granted a licence` MEANS
    `the applicant`'s `age in years` AT LEAST 18
```

_(Section `GIVEN`; checked on the section-`GIVEN` binary, exit 0.)_ The definitional rule is
exercisable on any case; the Part's rule is exercised as [entry 11.9](11-when-the-encoding-cannot-answer.md#e11-9) describes.

**See** [drafting-patterns.md](../drafting-patterns.md), "Checkbox relation-on-an-entity" and
`Statutory tables as DATA`, for the two shapes a long definition usually wants.

---

<a id="e1-2"></a>

## 1.2 "the grantee", "the personal representative" — the role the case fills

**If the source says**

> `s 28(1) — "Upon the grant of any probate or letters of administration, the grantee shall take an oath in the prescribed form, faithfully to administer the estate and to account for the same."`
>
> — `jl4/examples/legal/sg-succession/cleanroom-2026-08/probate-administration-act.l4:2715`

**It is doing** naming a role that each case fills differently. The Part opens by naming "the
grantee" and then talks about him for twenty sections without introducing him again — the role is
scoped to the Part, and every rule in it is about the same one.

**Write** the role once, under the heading of the part whose rules read it, indented past the `§`.
Name it as the source names it.

```l4
DECLARE `Deceased person` HAS
    `domiciled in Singapore`        IS A BOOLEAN
    `the gross value of the estate` IS A NUMBER

§ `Part 3 — Grants of representation`
    GIVEN `the deceased person` IS A `Deceased person`

GIVETH A BOOLEAN
`the deceased died domiciled in Singapore` MEANS
    `the deceased person`'s `domiciled in Singapore`

GIVETH A BOOLEAN
`the estate is a small estate` MEANS
    `the deceased person`'s `the gross value of the estate` AT MOST 50000
```

Both rules read the role; neither declares it. In the corpus the same line
`` GIVEN `the deceased person` IS A `Deceased person` `` is written out **62 times**, and eight more
role parameters repeat between 26 and 59 times each — that repetition is what this replaces.

**Not** a `GIVEN` at column 1 when you meant the section. That is a rule `GIVEN`, and it silently
becomes the signature of the declaration below it. Where that declaration never uses the name, L4
catches it:

```
This GIVEN starts at column 1, so it is the signature of the declaration
below it -- and that declaration never uses

  `is a body corporate`
```

Where the declaration below is a `DECIDE`, nothing catches it — a rule that ignores one of its own
inputs is an ordinary thing to write.

**And not** a hoist that is not true. A part where three rules are about a will and two are about
the deceased has **two** roles, not one; hoisting the wrong one gives a rule an input its provision
never mentions.

**See** the `section GIVEN` reference page (new in this release) for the visibility rules: two
sections declaring the same name declare two different things, a child shadows only inside its own
subtree, and a rule that reaches two at once is an error naming both.

---

<a id="e1-3"></a>

## 1.3 "a person ('P')", "(the 'Purchaser')" — the parenthetical label

**If the source says** — this device does **not** occur in the encoded corpus. Checked across all 26
files under `jl4/examples/legal/`: no `("P")`, no `(the "Purchaser")`, no `(hereinafter …)`, in
quoted text or in comments. Modern United Kingdom drafting uses it constantly, and the encoded slice
of the British Nationality Act 1981 does not reach one. The nearest corpus analogue is the role
parameter `GIVEN person IS A PersonProfile` (`jl4/examples/legal/bna/bna.l4:257`, and 28 more
sites).

**It is doing** exactly what [entry 1.2](#e1-2) does, with a shorter name. The parenthetical letter is a role
label, and the label's scope is stated by where it appears: one introduced at the head of a Part
governs the Part; one introduced inside a single subsection governs that subsection.

**Write** the letter as the parameter's name, at the scope the source gives it — a section `GIVEN`
for a Part, a rule `GIVEN` for one provision.

```l4
DECLARE PersonProfile HAS
    `born in the United Kingdom after commencement` IS A BOOLEAN
    `a parent who was settled in the United Kingdom at the time of the birth` IS A BOOLEAN

§ `Section 1 — Acquisition by birth`
    GIVEN P IS A PersonProfile

GIVETH A BOOLEAN
`P is a British citizen under subsection (1)` MEANS
        P's `born in the United Kingdom after commencement`
    AND P's `a parent who was settled in the United Kingdom at the time of the birth`
```

**Not** a fresh name of your own invention (`applicant`, `subject`) where the source says `P`. The
whole value of an isomorphic encoding is that a reader can hold the two texts side by side; a
renamed role breaks that for no gain.

**See** [entry 1.2](#e1-2), and the skill's own page, "Writing for legal audiences".

---

<a id="e1-4"></a>

## 1.4 "For the purposes of this section, X means …" — the same word, defined twice

**If the source says**

> `s 6(6) — "For the purposes of this section, "trust corporation" means the Public Trustee or a corporation licensed as a trust company under the Trust Companies Act 2005."`
>
> — `jl4/examples/legal/sg-succession/cleanroom-2026-08/probate-administration-act.l4:222`

and then, twenty-two sections later, uses "a trust company" unqualified for a class that is **not**
the same (`:2715`).

**It is doing** confining a definition to one section by its own opening words. The corpus records
having got this wrong and undone it: "An earlier draft called s 6(6) here and said only that the
class was s 6(6)'s under another name" (`:2728-2729`).

**Write** one definition per section, under that section's own `§` heading — **and keep the source's
own word**. A `§` heading scopes an ordinary definition exactly as it scopes a section `GIVEN`; the
confinement is in the language, and you do not have to rename anything to get it.

```l4
§ `Probate and Administration Act 1934`

DECLARE `Person or corporation` IS ONE OF
    `the Public Trustee`
    `a corporation licensed as a trust company under the Trust Companies Act 2005`
    `a trust company not so licensed`

§§ `Section 6 — number of grantees`
    GIVEN pc IS A `Person or corporation`

GIVETH A BOOLEAN
`s 6(6) — a trust corporation` MEANS
    CONSIDER pc
    WHEN `the Public Trustee` THEN TRUE
    WHEN `a corporation licensed as a trust company under the Trust Companies Act 2005` THEN TRUE
    OTHERWISE FALSE

§§ `Section 28 — oath by the grantee`
    GIVEN pc IS A `Person or corporation`

GIVETH A BOOLEAN
`s 28(2) — the grantee is the Public Trustee or a trust company` MEANS
    CONSIDER pc
    WHEN `the Public Trustee` THEN TRUE
    WHEN `a corporation licensed as a trust company under the Trust Companies Act 2005` THEN TRUE
    WHEN `a trust company not so licensed` THEN TRUE
    OTHERWISE FALSE
```

The two `pc` names are two different names, and so are two same-named **definitions**. Measured on
the section-`GIVEN` binary, exit 0:

```l4
§ `Licensing Act`

§§ `Section 6 — Grant of a licence`

-- 6.—(2) For the purposes of this section, "the fee" means $50.
@ref Licensing Act s 6(2)
GIVETH A NUMBER
`the fee` MEANS 50

-- An in-section alias, so a rule outside both sections can name this one.
GIVETH A NUMBER
`s 6(2) — the fee` MEANS `the fee`

§§ `Section 7 — Renewal of a licence`

-- 7.—(2) For the purposes of this section, "the fee" means $30.
@ref Licensing Act s 7(2)
GIVETH A NUMBER
`the fee` MEANS 30

GIVETH A NUMBER
`s 7(2) — the fee` MEANS `the fee`

§§ `Illustrations`

#ASSERT `s 6(2) — the fee` EQUALS 50
#ASSERT `s 7(2) — the fee` EQUALS 30
#ASSERT NOT (`s 6(2) — the fee` EQUALS `s 7(2) — the fee`)
```

A rule inside s 6 that says `` `the fee` `` gets 50; a rule inside s 7 gets 30; all three assertions
pass. **The section-numbered names are aliases for reaching in from outside, not replacements for
the source's word.** There is no syntax for writing the qualified name
(`` `Licensing Act`.`Section 6 — Grant of a licence`.`the fee` `` appears in the error message and
nowhere else), so an outside reference needs an alias declared inside the section — which is what
the two `s 6(2)` / `s 7(2)` lines above are for, and the only reason to write a section number into
a name at all.

**A rule under neither section that reaches for the bare name gets an error naming both by section**,
which is the point:

```
There are multiple definitions for the identifier

  pc

and I do not have sufficient information to make a choice between them.
The options are:

  `Probate and Administration Act 1934`.`Section 28 — oath by the grantee`.pc (defined at …) of type `Person or corporation`
  `Probate and Administration Act 1934`.`Section 6 — number of grantees`.pc (defined at …) of type `Person or corporation`
```

An outside reference to a same-named **definition** produces the identical error, with
`` `the fee` `` in place of `pc` and `of type NUMBER` in place of the record type — measured on the
`the fee` file above.

The three ways out say different things about the drafting: **hoist** to a common ancestor heading
if the sections really are about one thing; **alias** inside each section if they are two and
something outside both has to name each one; **rename** only where the source itself uses two words.

**Not** a rename you did not need. The reflex — call them `` `s 6(2) — the fee` `` and
`` `s 7(2) — the fee` `` and delete the source's word — throws away the isomorphism for a collision
that the `§` heading has already resolved. Rename the alias, never the definition.

**Not** the definition itself as a section `GIVEN`. That would say the caller supplies the meaning
of "trust corporation" for this run, which is exactly backwards: the two classes coincide on this
ontology by coincidence, and a trust company that is not licensed is exempt from the oath while not
being a trust corporation for s 6.

**Not** a shared definition called from both sections because the members happen to match today.
That is the mistake the corpus made and reverted.

**See** [entry 1.1](#e1-1) for the definition half, [entry 1.2](#e1-2) for the case half.

---

<a id="e1-5"></a>

## 1.5 "unless the context otherwise requires", and a provision two readings are open on

**If the source says**

> `"(4) In this Law, unless the context otherwise requires, \"constitution\" in relation to an entity means –"`
>
> — `jl4/examples/legal/charities-cleanroom/charity-test.l4:81`

**It is doing** two very different jobs under one phrase. As boilerplate on a definitions section it
usually has no operative effect and rides as inert prose beside the definition. But where a
provision genuinely bears two readings — and the encoder cannot settle which — the choice is real
and belongs to whoever runs the rules.

**Write** the reading as a parameter, and declare it once for the whole encoding as a section
`GIVEN`. "Rather than pick one and present it as the text, the encoding takes the reading as a
parameter" (`jl4/examples/legal/regcf/denovo/regcf-denovo.l4:92-93`).

```l4
§ `Regulation Crowdfunding`
    GIVEN `the reading` IS AN Interpretation

DECLARE `twelve month window reading` IS ONE OF
    `rolling from each closing`
    `from the date of such offer or sale`

DECLARE Interpretation HAS
    `the twelve month window` IS A `twelve month window reading`

`the staff reading` MEANS
    Interpretation WITH `the twelve month window` IS `rolling from each closing`

GIVEN `the closing date` IS A NUMBER, `the offer date` IS A NUMBER
GIVETH A NUMBER
`the day the twelve month window opens on` MEANS
    CONSIDER `the reading`'s `the twelve month window`
    WHEN `rolling from each closing`          THEN `the closing date`
    WHEN `from the date of such offer or sale` THEN `the offer date`
```

This is the largest measured win in the corpus: `GIVEN interp IS AN Interpretation` is written out
**26 times** in `regcf-denovo.l4`, on rules that already take the case record. One section `GIVEN`
replaces all 26.

**Keep writing the named readings** (`` `the staff reading` ``, `` `the text alone` ``) as values.
Until supply lands they are how a file demonstrates both poles: a `#EVAL` that reads an unsupplied
section `GIVEN` stops, and makes `l4 run` exit non-zero. What it prints depends on where the missing
value is first needed. Reached by the `CONSIDER` above, as here:

```
The value
  `the reading`
reached a CONSIDER that has no branch for it.
Add a WHEN branch for this case, or a catch-all OTHERWISE branch.
The typechecker's exhaustiveness warning lists all missing branches.
```

**That message is not about `CONSIDER`, and hunting for one will waste your time.** A plain genitive
field access on an unsupplied record produces it word for word, with no `CONSIDER` anywhere in the
file — field access is itself a match. Measured on the section-`GIVEN` binary, whole file, exit 1:

```l4
DECLARE Applicant HAS
    `age in years` IS A NUMBER

§ `Part 2 — Licences`
    GIVEN `the applicant` IS AN Applicant

GIVETH A BOOLEAN
`the applicant is of age` MEANS
    `the applicant`'s `age in years` AT LEAST 18

#EVAL `the applicant is of age`
```

```
The value
  `the applicant`
reached a CONSIDER that has no branch for it.
Add a WHEN branch for this case, or a catch-all OTHERWISE branch.
The typechecker's exhaustiveness warning lists all missing branches.
```

Read it as **"you did not supply this input"**, whatever construct it names.

Reached by arithmetic instead — a section `GIVEN` `` `the rate` `` read by
`` `tax on` amount MEANS amount TIMES `the rate` `` — it is the assumed-term message:

```
I could not continue evaluating, because I needed to know the value of
  `the rate`
but it is an assumed term.
```

**`#CHECK` is the directive that is safe here.** `` #CHECK `the applicant is of age` `` on the same
file prints `BOOLEAN ` at Information severity and `l4 run` exits **0** — it type-checks without
evaluating, so an unsupplied section `GIVEN` costs it nothing. That is what lets a file that uses
the house style still run green; [entry 11.9](11-when-the-encoding-cannot-answer.md#e11-9) is the whole recipe.

**Not** ``#EVAL `the day the twelve month window opens on` WITH `the reading` IS `the staff
reading` `` — `WITH` names a rule's own inputs, and `` `the reading` `` is not one of them, so
that line is a check error: the rule's two real inputs are reported unsupplied and
`` `the reading` `` is reported undefined. **Not** a `TYPICALLY` default to make one reading win: a
`TYPICALLY` value must be a literal, and `` `the staff reading` `` is a defined name of record type,
so the typechecker rejects it — _"The TYPICALLY value for `the reading` must be a literal: a number,
a string, or a nullary constructor such as TRUE, FALSE or NOTHING."_ A constructor of your own
`ONE OF` type is a literal and is accepted, so a reading modelled as a bare enum could carry one —
and it would still not decide anything, because `TYPICALLY` is metadata in this release and the
input stays required either way. **Not**, above all, silently picking a reading and presenting it as the text.

**See** [entry 1.4](#e1-4) (the confinement), and [drafting-patterns.md](../drafting-patterns.md), "Provenance —
pin every inert string".

---

<a id="e1-6"></a>

## 1.6 "… under section 9", where section 9 is not in the slice you are encoding

**If the source says** a condition that turns on a provision your encoding does not contain — a
section outside the extract, an Act you did not reach, a schedule left for later.

**It is doing** exactly what it does for a full encoding; the gap is yours, not the statute's. There
are two honest readings and the choice is a modelling decision, not a detail:

- **The cross-reference names a recorded status.** "Has not been disqualified under section 9" is
  something a registrar can look up and answer without running s 9. Then it is a fact about the
  case: a field on the record, supplied at the boundary like any other.
- **The cross-reference names a rule you would have to run.** If answering it means applying s 9's
  own conditions to facts the caller does not have, nobody can supply it, and inviting them to is
  worse than declining. Then it is a named refusal ([entry 11.5](11-when-the-encoding-cannot-answer.md#e11-5)) — or a reason to go and encode s 9.

**Write** whichever you chose, and **say in a comment which reading you took and why**, because the
file cannot show it:

```l4
-- READING 1 — s 9 disqualification is a RECORDED STATUS. A registrar can look
-- it up and answer it, so it is a fact about the case: a field.
DECLARE Applicant HAS
    `age in years`                          IS A NUMBER
    `has been disqualified under section 9` IS A BOOLEAN

@ref Licensing Act s 6(1)
GIVEN `the person` IS AN Applicant
GIVETH A BOOLEAN
`s 6(1) — a licence may be granted to` `the person` MEANS
        `the person`'s `age in years` AT LEAST 18
    AND NOT `the person`'s `has been disqualified under section 9`

-- READING 2 — s 9 is a RULE, with its own conditions, that this encoding does
-- not contain. Nobody can supply its answer, so the honest shape is a refusal.
@ref Licensing Act s 9 — not encoded in this model
GIVETH A BOOLEAN
`section 9 (disqualification) is not encoded in this model` MEANS
    REFUSE "section 9 (disqualification) is not encoded in this model"

@ref Licensing Act s 6(1)
GIVEN `the person` IS AN Applicant
GIVETH A BOOLEAN
`s 6(1) — a licence may be granted to, deciding s 9 here` `the person` MEANS
        `the person`'s `age in years` AT LEAST 18
    AND NOT `section 9 (disqualification) is not encoded in this model`
```

_(`REFUSE`; checked on the `REFUSE` binary, exit 0.)_ Reading 2 is worth running before you commit
to it, because it behaves better than it looks: for an applicant aged 17 it answers a flat
**`FALSE`**, not a refusal, because the age limb decides the case and left-to-right evaluation never
reaches the s 9 term. Only where s 9 would actually settle the outcome does the model decline. All
three assertions below are satisfied:

```l4
`an applicant aged 25 who is not disqualified` MEANS Applicant WITH
    `age in years`                          IS 25
    `has been disqualified under section 9` IS FALSE

`an applicant aged 17` MEANS Applicant WITH
    `age in years`                          IS 17
    `has been disqualified under section 9` IS FALSE

#ASSERT `s 6(1) — a licence may be granted to` `an applicant aged 25 who is not disqualified`
#ASSERT REFUSED `s 6(1) — a licence may be granted to, deciding s 9 here` `an applicant aged 25 who is not disqualified`
#ASSERT NOT `s 6(1) — a licence may be granted to, deciding s 9 here` `an applicant aged 17`
```

**Not** a field named for a rule. `` `has been disqualified under section 9` `` is defensible
because disqualification is a status a register holds; `` `satisfies section 9` `` on a section that
computes something would be a promise the caller cannot keep.

**Not** a silent choice. Whichever reading you take, an unmarked one is indistinguishable from not
having noticed, and the next reader has to re-derive it from the statute you did not include.

**See** [entry 11.5](11-when-the-encoding-cannot-answer.md#e11-5) (the refusal shape and its `@ref`), [entry 11.8](11-when-the-encoding-cannot-answer.md#e11-8) (why the refusal in reading 2 is
sometimes skipped, and why that is right here), and the row-7 test in the closing table.

---

<a id="e1-7"></a>

## 1.7 "In this Agreement, 'Effective Date' means 1 January 2026" — the contract's own definitions clause

**If the source says** a clause 1 that fixes the terms the rest of the instrument is written in. Both
contracts in the corpus open exactly this way:

> `` `Note Date` MEANS February 4 2024 ``; `` `Interest Rate Per Annum` MEANS 15% ``;
> `` `Monthly Installments` MEANS 12 ``
>
> — `jl4/examples/legal/promissory-note.l4:9-19`, under the heading `` §§ `Basic Definitions` ``.
> `jl4/examples/legal/ceo-performance-award.l4:8-19` does the same under `` §§ `Core Constants` ``.

**It is doing** for a contract what entry 1.1 does for an Act. The drafter has written the
right-hand side down, so the term is settled for everyone who reads the Agreement, and a capitalised
word is a promise that it is defined somewhere in the document and means nothing else there.

**Write** the definitions clause as a run of `MEANS` constants, one per defined term, in the clause's
own order, keeping the source's own capitalisation — and **backtick every defined term**.

```l4
IMPORT daydate

§ `Services Agreement`

§§ `1. Definitions`

-- 1.1 "Effective Date" means 1 January 2026.
`Effective Date` MEANS January 1 2026

-- 1.2 "Fee Rate" means 12% per annum.
`Fee Rate` MEANS 12%

-- 1.3 "Payment Period" means 30 days.
`Payment Period` MEANS 30

-- 1.4 "Governing Law" means the laws of Singapore.
`Governing Law` MEANS "the laws of the Republic of Singapore"

§§ `Illustrations`

#ASSERT `Fee Rate` EQUALS 0.12
#ASSERT `Payment Period` EQUALS 30
#EVAL `Effective Date`
```

_(Checked on the release binary, exit 0, no errors.)_ Both assertions are satisfied; the `#EVAL`
prints `DATE OF 1, 1, 2026`, and `March 15 2026` prints `DATE OF 15, 3, 2026` — day, then month,
then year, and the `OF` is the printer's, not something you write (entry
[11.4](11-when-the-encoding-cannot-answer.md#e11-4)).

**Not** the term without its backticks. Written bare, `Effective Date` is two tokens and not one
name, so the line defines a **function** called `Effective` of a parameter called `Date`. Nothing
complains where it is written: a definitions clause that says `Effective Date MEANS January 1 2026`
and is not read yet **checks clean and exits 0**. The failure lands at the reader, some distance
away, and names `Date` or the term — never the line that is actually wrong.

The reader that spells the term as you meant it is told the term does not exist:

```
I could not find a definition for the identifier

  `Effective Date`

which I have inferred to be of type:

  DATE
```

The reader that repeats the same mistake gets, in a file that has `IMPORT daydate` — as a contract
fixing dates will — the library's own `Date` instead:

```
There are multiple definitions for the identifier

  Date

and I do not have sufficient information to make a choice between them.
The options are:

  Date (defined at daydate.l4:81:12-26) of type FUNCTION FROM DATETIME TO DATE
  Date (defined at daydate.l4:70:12-26) of type FUNCTION FROM STRING TO MAYBE OF DATE
  …
```

Without the import the same reader gets `I could not find a definition for the identifier / Date`.
All three measured on the release binary; the middle one is the file the entry's own `Write` block
would become.

Backticks are only load-bearing where the name is more than one token: `` `Fee` `` and `Fee` are the
same name, and both assertions pass in a file that mixes them. Since almost every defined term in a
contract is two or three words, backtick all of them and stop thinking about it.

**Not** an input. A defined term whose right-hand side the contract states is a constant; making it
a section `GIVEN` would let the caller decide what the Agreement says. Entry
[1.1](#e1-1) has the tell, and it is the same tell here: if you can write the right-hand side from
the document, it is a definition.

**See** entry [1.1](#e1-1) for the statutory form of the same clause, and
[drafting-patterns.md](../drafting-patterns.md), `Statutory tables as DATA`, when the definitions
clause runs to a table rather than a list.

---

<a id="e1-8"></a>

## 1.8 "'Funding portal' means a broker … that does not …" — the definition with a condition inside it

**If the source says**

> `(2) _Funding portal_ means a broker acting as an intermediary in a transaction involving the offer or sale of securities in reliance on section 4(a)(6) of the Securities Act …, that does not: (i) Offer investment advice or recommendations; (ii) Solicit purchases, sales or offers to buy the securities displayed on its platform; …`
>
> — 17 CFR (Code of Federal Regulations) 227.300(c)(2), in the repository at
> `jl4/examples/legal/regcf/denovo/source/part227.txt:458`

The same instrument's sibling definition carries the other common form, an exception rather than a
condition: "except that any person … whose functions are solely clerical or ministerial shall not be
included in the meaning of such term" (`:456`). "means a day other than a Saturday, a Sunday or a
public holiday" is the contract drafter's version of the identical device.

**It is doing** defining a class by a positive core plus one or more things that take you out of it.
The exclusions are part of the definition, not a separate rule, so they must be inside the
definition's own name and not stranded in whatever calls it.

**Write** the excluded conduct as **positive** fields on the record — the words the source uses to
describe the thing being excluded — and put the negation in the rule, one limb per numbered
sub-paragraph, tagged with its own number:

```l4
§ `Regulation Crowdfunding`

DECLARE IntermediaryProfile HAS
    `is a broker acting as an intermediary in a section 4(a)(6) transaction` IS A BOOLEAN
    `offers investment advice or recommendations`                            IS A BOOLEAN
    `solicits purchases, sales or offers to buy the securities displayed on its platform` IS A BOOLEAN
    `holds, manages, possesses, or otherwise handles investor funds or securities`        IS A BOOLEAN

@ref 17 CFR 227.300(c)(2)
GIVEN intermediary IS AN IntermediaryProfile
GIVETH A BOOLEAN
DECIDE `the intermediary is a funding portal` intermediary IF
        intermediary's `is a broker acting as an intermediary in a section 4(a)(6) transaction`
    AND NOT "(i)"   ... intermediary's `offers investment advice or recommendations`
    AND NOT "(ii)"  ... intermediary's `solicits purchases, sales or offers to buy the securities displayed on its platform`
    AND NOT "(iv)"  ... intermediary's `holds, manages, possesses, or otherwise handles investor funds or securities`
```

_(Checked on the release binary, exit 0, no errors; limb (iii) is elided above for length, which is
why the tags run (i), (ii), (iv).)_ This is the corpus's own shape, at
`jl4/examples/legal/regcf/denovo/regcf-denovo.l4:2218-2226`, where all four limbs are written
against fields declared in the positive at `:869-873`, under a comment calling them the four
negative limbs of "funding portal".

**Not** `EXCEPT`. There is no such keyword, and the failure is at the identifier, not the parse, so
it reads as a missing definition rather than as a word L4 does not have:

```
I could not find a definition for the identifier

  EXCEPT

which I have inferred to be of type:

  FUNCTION FROM BOOLEAN AND BOOLEAN TO BOOLEAN
```

**Not** the exclusion in the field name. Naming the field
`` `does not offer investment advice or recommendations` `` copies the source's "does not" onto the
fact, and then the "that does not" of the definition is written as a `NOT` a second time. The file
compiles, the run exits **0**, and a portal that gives no advice is held not to be a funding portal:

```
Result:
  assertion failed
```

A double negative is the one bug in this family that no diagnostic will find for you, so keep every
field in the affirmative and let the rule do all the negating. `NOT` is also
where the drafting is: see [drafting-patterns.md](../drafting-patterns.md), "Negative limb — `NOT
atom`, and the negated disjunction", for the two ways a negated list can be read.

**See** [drafting-patterns.md](../drafting-patterns.md), "Checkbox relation-on-an-entity", for why
these are independent booleans rather than an enumeration, and entry
[2.1](02-conditions-and-logic.md#e2-1) for the neighbouring shape — an exclusion that is a **gate**
on a section rather than part of a definition.

---

<a id="e1-9"></a>

## 1.9 "has the meaning given by Article 6", "within the meaning of section 3" — the definition that points elsewhere

**If the source says**

> `"charitable purpose" has the meaning given by Article 6;` … `"constitution" has the meaning given by Article 2(4);`
>
> — `jl4/examples/legal/charities-cleanroom/charity-test.l4:66-71`, carrying Article 1 of the
> Charities (Jersey) Law 2014

**It is doing** deferring. The interpretation section is not defining anything; it is telling you
where the definition lives. Where it points decides what you write, and there are three
destinations:

- **At a provision you have encoded.** Then it is not a definition at all — call the rule. The
  pointer costs you nothing.
- **At a provision you are carrying inert.** The Jersey file's four Article 1 terms all point into
  Article 2, and the encoder's note at `:73-79` says the dispatch there settles only which document
  or which person the words pick out, and does not vary the charity test's logic. So Article 2 rides
  as quoted text and the records take the resolved referents as given.
- **At another Act, or another module.** Then you have two texts of one definition, and they can
  drift.

**Write**, for the third case, the definition again in the borrowing module — named for the section
it borrows from, so the borrowing is visible in every call site — and then an assertion that the two
still agree:

```l4
§ `Intestate Succession Act 1967`

DECLARE Child HAS
    `a legitimate child of the person whose child he is` IS A BOOLEAN
    `adopted by that person by virtue of an order of court` IS A BOOLEAN

@ref Intestate Succession Act 1967 s 3 — "“child”"
GIVEN `the relationship of child to parent` IS A Child
GIVETH A BOOLEAN
DECIDE `section 3 — a “child” within the meaning of this Act` IF
        `the relationship of child to parent`'s `a legitimate child of the person whose child he is`
    OR  `the relationship of child to parent`'s `adopted by that person by virtue of an order of court`

§ `Probate and Administration Act 1934`

-- This Act says "next of kin" and does not define it. s 18(4)(a) is read as
-- borrowing the other Act's classes, so it borrows that Act's definition of
-- "child" with them — and says so in the name.
@ref Probate and Administration Act 1934 s 18(4)(a); Intestate Succession Act 1967 s 3
GIVEN c IS A Child
GIVETH A BOOLEAN
`a “child” within the meaning of section 3 of the Intestate Succession Act 1967` c MEANS
        c's `a legitimate child of the person whose child he is`
    OR  c's `adopted by that person by virtue of an order of court`

§ `Cross-check`

-- Not a rule of either Act: an assertion that two texts of one definition still
-- say the same thing. It fails if either is edited alone.
GIVEN `the relation` IS A Child
GIVETH A BOOLEAN
`the two modules agree whether this child is a “child” within the meaning of section 3` MEANS
        (`section 3 — a “child” within the meaning of this Act` `the relation`)
    EQUALS
        (`a “child” within the meaning of section 3 of the Intestate Succession Act 1967` `the relation`)
```

_(Checked on the release binary, exit 0, no errors, with an `#ASSERT` over the cross-check
satisfied. The adoption field's name is shortened here; the corpus carries the whole phrase,
including the three jurisdictions, for the reason its own note gives.)_ The three rule names are the
corpus's own:
`jl4/examples/legal/sg-succession/cleanroom-2026-08/intestate-succession-act.l4:194`,
`probate-administration-act.l4:417`, and the cross-check at `family-cases.l4:1016-1019`, whose
comment says why it exists — "there are two texts of one definition. What a composition can do is
assert that they still say the same thing, in one expression that fails if either is edited alone".

Drop one limb from the borrowing module and that is exactly what happens:

```
Result:
  assertion failed
```

with `l4 run` still exiting **0**, which is the reason the cross-check is an `#ASSERT` you look at
and not a comment you believe.

**Not** a fresh name. `` `is a qualifying child` `` in the borrowing module hides the borrowing, and
the next reader cannot tell whether the module took the other Act's definition or invented one. The
pointer belongs in the name because the pointer is what the source wrote.

**Not** a boolean field asking the caller whether the person is "a child within the meaning of
section 3". That hands the definition to whoever fills in the form. The distinction is entry
[1.6](#e1-6)'s: a **recorded status** may be a field; a **rule you would have to run** may not.

**See** entry [1.4](#e1-4) (the same word defined twice in one instrument, which is the in-file
version of this problem) and [drafting-patterns.md](../drafting-patterns.md), "Inert never shadows
active — quote the label, not the sentence", for the second destination.

---

<a id="e1-10"></a>

## 1.10 "specified in the Schedule" — the definition that lives in a Schedule

**If the source says**

> `36.—(1) Notwithstanding any other written law, a minor who has attained the age of 18 years and who is not otherwise under any legal disability — (a) may, in his own name and without a litigation representative, bring, defend, conduct or intervene in any legal proceeding or action specified in the Schedule as if he were of full age`
>
> — Civil Law Act 1909 (Singapore) s 36(1)(a), in the repository at
> `jl4/examples/legal/sg-succession/cleanroom-2026-08/source/CLA1909.txt:1766-1772`

**It is doing** putting the extension of a term somewhere the operative section is not, usually
because the list is long, or ordered, or meant to be amended without touching the section. The
section's own words are then a membership test over that list. (Very often the Schedule is
amendable by order — s 36(2) here — which is entry
[11.1](11-when-the-encoding-cannot-answer.md#e11-1)'s question, asked about a list rather than a
number.)

**Write** the Schedule as **data**: one named item per paragraph, carrying the paragraph number and
the words as they stand, gathered into a `LIST` in the Schedule's own order; then the operative
section as a membership test over that list.

```l4
IMPORT prelude

§ `Civil Law Act 1909`

DECLARE `Proceeding` IS ONE OF
    `a claim in contract`
    `a claim in tort`
    `an application for a grant of representation`
    `a matrimonial proceeding`

§§ `The Schedule`

DECLARE `Scheduled item` HAS
    `paragraph`      IS A NUMBER
    `text`           IS A STRING
    `the proceeding` IS A Proceeding

GIVETH A `Scheduled item`
`Schedule item 1` MEANS
    `Scheduled item` WITH `paragraph`      IS 1
                        , `text`           IS "A claim in contract."
                        , `the proceeding` IS `a claim in contract`

GIVETH A LIST OF `Scheduled item`
`the Schedule` MEANS
    LIST `Schedule item 1`
       , `Schedule item 2`

§§ `Section 36`

@ref Civil Law Act 1909 s 36(1)(a)
GIVEN p IS A Proceeding
GIVETH A BOOLEAN
`s 36(1)(a) — a legal proceeding or action specified in the Schedule` p MEANS
    any `the item is this proceeding` `the Schedule`
    WHERE
        `the item is this proceeding` i MEANS i's `the proceeding` EQUALS p
```

_(Checked on the release binary, exit 0, no errors;
`` #ASSERT `s 36(1)(a) — …` `a claim in tort` `` and the `#ASSERT NOT` for an unscheduled proceeding
are both satisfied. `Schedule item 2` is elided above for length.)_ The corpus does this at
`jl4/examples/legal/sg-succession/sg-paa.l4:1582-1591`, where the Probate and Administration Act's
Second Schedule is eight named items gathered into one `LIST`, each carrying its `paragraph` and its
`text` — kept at its own number, in the file's words, "because the app shows the Schedule as the
Schedule reads" (`:1572-1573`).

**Not** the record literals written straight into the `LIST`. It looks like it should work and it is
a parse error:

```
    7 |     LIST `Scheduled item` WITH `paragraph` IS 1
      |                           ^^^^
    unexpected WITH
```

Parenthesising each one does parse — ``LIST (`Scheduled item` WITH `paragraph` IS 1, `text` IS "…")``
— but naming each item, as above and as the corpus does, is better anyway: the name is where the
paragraph's own commentary goes, and a section that cites one paragraph can cite it.

**Not** an enumeration alone. `DECLARE Proceeding IS ONE OF …` is the right type for the **cell**,
and it is not the Schedule: it drops the numbering and the words, so nothing can show the Schedule
back to a reader, and an amendment to one paragraph cannot be pinned to that paragraph.

**See** [drafting-patterns.md](../drafting-patterns.md), `Statutory tables as DATA — a record per row + enums + membership via any`,
which is the multi-column version of this shape.

---

<a id="e1-11"></a>

## 1.11 A defined term used in clause 2 and defined in clause 12

**If the source says** — as nearly every contract does — an operative clause that uses "the Fee" ten
pages before the definitions clause that fixes it. The statutory version is the reverse: an
interpretation section at the front whose terms are used throughout.

**It is doing** nothing you have to work around. Order of definition is a drafting convention, not a
dependency.

**Write** the clauses in the source's order, wherever the definitions happen to be. A name defined in
a later section — even a later sibling `§§` — is visible to an earlier one:

```l4
§ `Services Agreement`

§§ `2. Payment`

-- 2.1 The Client shall pay the Fee within the Payment Period after the
--     Effective Date. (All three are defined in clause 12, below.)
GIVETH A NUMBER
`the day the fee falls due` MEANS `Effective Date` PLUS `Payment Period`

GIVETH A NUMBER
`the fee payable on the first invoice` MEANS `Fee`

§§ `12. Definitions`

`Effective Date` MEANS 0
`Payment Period` MEANS 30
`Fee`            MEANS `Rate` TIMES `Hours Worked`
`Rate`           MEANS 200
`Hours Worked`   MEANS 10

§§ `Illustrations`

#ASSERT `the day the fee falls due`          EQUALS 30
#ASSERT `the fee payable on the first invoice` EQUALS 2000
```

_(Checked on the release binary, exit 0, no errors; both assertions satisfied.)_ `Fee` reaches
forward to `Rate` and `Hours Worked` in the same way. What matters is not order but **scope**: a
name is visible sideways like this when it is the only candidate, and two sections defining it makes
a reader outside both an error naming both — entry [1.4](#e1-4).

**Not** a file reordered to put definitions first. It buys nothing, and it costs the isomorphism
between the file and the instrument, which is the thing a reviewer holding both documents is
checking.

**Not** a definition that closes a circle. Ordering is free; circularity is not, and the typechecker
does not see it. `` `Net Fee` MEANS `Gross Fee` MINUS `Discount` `` beside
`` `Gross Fee` MEANS `Net Fee` PLUS `Discount` `` passes `l4 check` — literally `Check succeeded.`,
exit 0 — and fails only when something evaluates it:

```
Infinite loop detected while trying to evaluate:
`Gross Fee` MINUS Discount
```

Two contract definitions that each define the other is a real drafting defect, and this is how you
find it: a `#EVAL` or `#ASSERT` on every defined term you actually use, not a clean `l4 check`.

**See** entry [1.4](#e1-4) for the scope rules this depends on, and entry
[11.9](11-when-the-encoding-cannot-answer.md#e11-9) for exercising a rule you cannot `#EVAL`.

---

<a id="e1-12"></a>

## 1.12 "In this Act" against "In this Part" — the same word at two scopes

**If the source says** an interpretation section for the whole instrument and, later, a Part that
redefines one of its words for itself. Section 2 of the Probate and Administration Act 1934 carries
"the three definitions" for the Act (`jl4/examples/legal/sg-succession/cleanroom-2026-08/family-domain.l4:1497`),
while s 6(6) confines a definition of "trust corporation" to s 6 alone
(`probate-administration-act.l4:222`; entry [1.4](#e1-4)).

**It is doing** exactly what its opening words say, and those words are the whole instruction:
"In this Act" is the instrument, "In this Part" is the Part, "For the purposes of this section" is
the section. A definition placed at the wrong level is either invisible where it is needed or
visible where it was excluded.

**Write** the definition under the heading whose scope its opening words name — the Act's at the top
`§`, the Part's under that Part's `§§`. A definition under a nested heading **shadows** the one above
it, and only inside its own subtree:

```l4
§ `Licensing Act`

-- 2. In this Act, "the prescribed fee" means $50.
@ref Licensing Act s 2
GIVETH A NUMBER
`the prescribed fee` MEANS 50

§§ `Part 2 — Grant of a licence`

@ref Licensing Act s 6(3)
GIVETH A NUMBER
`s 6(3) — the fee payable on a grant` MEANS `the prescribed fee`

§§ `Part 3 — Renewal of a licence`

-- 11. In this Part, "the prescribed fee" means $30.
@ref Licensing Act s 11
GIVETH A NUMBER
`the prescribed fee` MEANS 30

@ref Licensing Act s 12(2)
GIVETH A NUMBER
`s 12(2) — the fee payable on a renewal` MEANS `the prescribed fee`

§§ `Illustrations`

#ASSERT `s 6(3) — the fee payable on a grant`    EQUALS 50
#ASSERT `s 12(2) — the fee payable on a renewal` EQUALS 30
```

_(Checked on the release binary, exit 0, no errors; both assertions satisfied.)_ Part 3's rule reads
Part 3's meaning; Part 2, which is not under Part 3, keeps the Act's. Neither rule says which one it
means, and neither should: the source did not, and the heading is what carries it.

**Not** both definitions at the level of the Act. Losing the `§§` loses the confinement, and the
error names the two sites — which is the good case, because the alternative would be one of them
silently winning:

```
There are multiple definitions for the identifier

  `the prescribed fee`

and I do not have sufficient information to make a choice between them.
The options are:

  `Licensing Act`.`the prescribed fee` (defined at …:9:1-21) of type NUMBER
  `Licensing Act`.`the prescribed fee` (defined at …:5:1-21) of type NUMBER
```

**Not** a rename to dodge it. `` `the prescribed fee (Part 3)` `` throws away the source's word for a
collision the heading already resolves; see entry [1.4](#e1-4), which is the sibling-section case and
gives the three ways out — hoist, alias, rename — and when each is honest.

**Not** a section `GIVEN` for either of them. This is entry [1.1](#e1-1)'s prohibition at the level
of a Part: the Part's meaning of "the prescribed fee" is written down, so it is a definition. What a
Part's `GIVEN` is for is the **case** the Part is about — entry [1.2](#e1-2).

**See** entry [1.4](#e1-4), entry [1.2](#e1-2), and the `section GIVEN` reference page (new in this
release) for how the same heading tree scopes an input.

---

<a id="e1-13"></a>

## 1.13 Where the illustrations live

**If the source says** nothing — this is a question about the file, not about the statute, and it is
one the phrasebook answers only by example. Four entries above open a `` §§ `Illustrations` ``
heading and put their named cases under it; other entries scatter them beside the rule they exercise.
That is a house style worth stating, and with a section `GIVEN` in the file it stops being cosmetic.

**It is doing** two things at once. It keeps the operative rules readable — a reader meets the rule
before its fact patterns — and it keeps the fixtures out of a scope where they would change what a
rule can see. A `§` heading scopes everything beneath it, definitions and section `GIVEN`s alike;
put a fixture under the wrong heading and it inherits a scope you did not intend.

**Write** the rules first, then a sub-heading of the section they belong to, then the named cases,
then the directives that use them:

```l4
§ `4. Fees`
    GIVEN `the month` IS A `Month of the engagement`

-- The operative test carries its own rule GIVEN, so a directive can exercise it.
GIVEN m IS A `Month of the engagement`
GIVETH A NUMBER
`the fee for the month` m MEANS
    IF   m's `hours worked` AT MOST 40
    THEN m's `hours worked` TIMES 120
    ELSE (40 TIMES 120) PLUS ((m's `hours worked` MINUS 40) TIMES 150)

-- The one-line reader the section GIVEN exists for.
GIVETH A NUMBER
`the fee for this month` MEANS `the fee for the month` `the month`

#CHECK `the fee for this month`

§§ `4 -- illustrations`

`a 50 hour month` MEANS `Month of the engagement` WITH `hours worked` IS 50
`a 40 hour month` MEANS `Month of the engagement` WITH `hours worked` IS 40

#ASSERT `the fee for the month` `a 50 hour month` EQUALS 6300
#ASSERT `the fee for the month` `a 40 hour month` EQUALS 4800
```

_(Probe `r11-illustrations-scope.l4`, exit 0, no errors, both assertions satisfied and the `#CHECK`
printing `NUMBER ` at Information severity.)_ The illustrations heading is a **child** of the
section, not a sibling: nesting it under `§ 4. Fees` keeps the fixtures with the rules they belong
to, and a reader scanning `§` headings still sees one entry per clause.

**Not** an `#ASSERT` on the rule that reads the section `GIVEN`. The fixture exists and there is
still no way to hand it over — nothing inside the file supplies a section `GIVEN` in this release —
so the assertion stops, and `l4 run` exits 1 (probe `r11b-assert-on-the-reader.l4`):

```
assertion could not be evaluated:
The value
  `the month`
reached a CONSIDER that has no branch for it.
Add a WHEN branch for this case, or a catch-all OTHERWISE branch.
```

Read that as "you did not supply this input", whatever construct it names — entry [1.5](#e1-5) has
the other wording it comes in. The recipe that keeps the file green is
[11.9](11-when-the-encoding-cannot-answer.md#e11-9): assert on the rule `GIVEN`, `#CHECK` the reader.

**Not** the fixtures at the end of the file, in one block, away from the rules. It reads well until
the second section, at which point every case value in the file is in one namespace and named for a
clause a reader has to scroll to find.

**See** entry [1.4](#e1-4) for what else a `§` heading scopes, entry
[6.10](06-parties-and-things.md#e6-10) for the mixfix helper that builds a case value worth naming,
and entry [11.9](11-when-the-encoding-cannot-answer.md#e11-9) for the delegation recipe.
