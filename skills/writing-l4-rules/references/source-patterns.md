# From the words on the page to L4: a phrasebook

Keyed on **what the source text says**. [drafting-patterns.md](drafting-patterns.md) is keyed on the
L4 shape — reach for that one when you know which shape you want; reach for this one when you are
looking at a sentence of statute or contract and do not.

Each entry has five parts:

- **If the source says** — the drafting phrase, with a real quotation from the encoded corpus in
  this repository and its file and line.
- **It is doing** — the legal job the phrase performs, in a sentence or two. Most encoding mistakes
  are here, not in the syntax: the same word (`means`, `refuses`, `prescribed`) does two different
  jobs in two different places.
- **Write** — the L4 pattern. Every snippet on this page was run before it went in.
- **Not** — the shape a model reaches for first, and why it is wrong.
- **See** — where the shape is treated at length.

## What is new, and what is not here yet

**New in this release.**

- The **section `GIVEN`** — a `GIVEN` indented under a `§` heading, declaring an input that every
  rule in that section reads without re-declaring it. A `GIVEN` at column 1 is unchanged: it is the
  signature of the one declaration below it, a **rule `GIVEN`**. Indentation is the whole
  difference.
- **`REFUSE "message"`** — an expression at any type that stops the evaluation and says why. Nothing
  downstream can catch it; only the boundary (the directive, the command line, the application
  programming interface, the web form) sees it. That guarantee is about a refusal something
  **forces**: evaluation is lazy, so a refusal you store inside a value instead of returning may
  never run at all, and the caller gets an ordinary answer. Entry 24 measures both halves. `TBD`,
  from the prelude, is the refusal that means "not written yet".
- **`ASSUME` is deprecated for declaring inputs, and still works.** It parses, type-checks and
  exports exactly as before, and emits no warning. Write new inputs as a record parameter or a
  section `GIVEN`; see entry 19 for migrating an old one.

**Proposed, not landed (2026-09-04). Do not write these.**

- Supplying a **section `GIVEN`** or an `ASSUME`d name from inside the file, at a directive or at
  a call in a body: `` #EVAL f WITH `the reading` IS `the strict reading` ``.
  What `WITH` can name today is a rule's **own** inputs, so `#EVAL f WITH x IS 25` works where
  `f` is `GIVEN x …`; naming anything that is not one of the rule's own inputs is a check error,
  not a parse error (the rule's real inputs are reported unsupplied, and the name you wrote is
  reported undefined). A parse error, `unexpected WITH`, is what you get only when a positional
  value precedes the `WITH`, as in ``#EVAL `tax on` 100 WITH rate IS 0.2``. Section-`GIVEN`
  values are supplied from outside: a web form, `l4 batch FILE --inputs cases.json`, or the
  service request.
- Discharge — the compiler working out which inputs an entry point actually reads and asking for
  exactly those.
- `TYPICALLY` as a default the caller may omit. Today it is metadata: the input is still required.
- A dedicated `SUBJECT TO` / `NOTWITHSTANDING` construct. **Neither is a keyword** — there is no
  token for either in the lexer. Entry 9 says what to write instead.
- Per-backend handling of a refusal in the export targets.

## The distinction that decides half of these entries

> **"The law does not apply, or is not in force" is the law's own answer, and stays an ordinary
> value or gate. "The model does not cover this" is the encoder's answer, and is a refusal.**

The first is determinate, and the law provides for it: savings and transitional provisions reach
back into exactly that period, so something must be there for them to reach. The second is a
recusal — the encoder declines, no party may read the decline as a decision in their favour, and the
matter goes to another bench. A refusal is unreachable by construction, so **if you find yourself
wanting a savings provision to reach past a `REFUSE`, the `REFUSE` was wrong.**

---

## 1. "In this Act, X means Y" — the term the text fixes

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

**The tell**, and it is the whole of entry 2: if you can write the right-hand side from the statute,
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
exercisable on any case; the Part's rule is exercised as entry 25 describes.

**See** [drafting-patterns.md](drafting-patterns.md), "Checkbox relation-on-an-entity" and
`Statutory tables as DATA`, for the two shapes a long definition usually wants.

---

## 2. "the grantee", "the personal representative" — the role the case fills

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

## 3. "a person ('P')", "(the 'Purchaser')" — the parenthetical label

**If the source says** — this device does **not** occur in the encoded corpus. Checked across all 26
files under `jl4/examples/legal/`: no `("P")`, no `(the "Purchaser")`, no `(hereinafter …)`, in
quoted text or in comments. Modern United Kingdom drafting uses it constantly, and the encoded slice
of the British Nationality Act 1981 does not reach one. The nearest corpus analogue is the role
parameter `GIVEN person IS A PersonProfile` (`jl4/examples/legal/bna/bna.l4:257`, and 28 more
sites).

**It is doing** exactly what entry 2 does, with a shorter name. The parenthetical letter is a role
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

**See** entry 2, and the skill's own page, "Writing for legal audiences".

---

## 4. "For the purposes of this section, X means …" — the same word, defined twice

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

**See** entry 1 for the definition half, entry 2 for the case half.

---

## 5. "unless the context otherwise requires", and a provision two readings are open on

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
the house style still run green; entry 25 is the whole recipe.

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

**See** entry 4 (the confinement), and [drafting-patterns.md](drafting-patterns.md), "Provenance —
pin every inert string".

---

## 6. "This Act comes into force on …", "applies to a death on or after …"

**If the source says**

> `"ISA s 5: the Act distributes the estates of those dying intestate after 2 June 1967."`
>
> — `jl4/examples/legal/sg-succession/sg-isa.l4:420`

**It is doing** fixing a boundary in time. Before it, this Act has nothing to say — but **something
else does**, and the law provides for the handover: savings and transitional provisions reach back
into that period and decide it.

**Write** a value, with the pre-commencement case named, so a later rule can match on it.

```l4
DECLARE `Distribution under this Act` IS ONE OF
    `the Act was not yet in force at the death`
    `the estate is distributed under section 7`

@ref Intestate Succession Act 1967 s 5
GIVEN `the date of death` IS A DATE
GIVETH A `Distribution under this Act`
`the distribution for a death on` `the date of death` MEANS
    IF   Day `the date of death` AT MOST Day (YMD 1967 6 2)
    THEN `the Act was not yet in force at the death`
    ELSE `the estate is distributed under section 7`
```

The named arm is where the note goes: the corpus's own version carries
`` `governed by this Act` IS FALSE `` and a sentence saying which regime governs instead, because
"the Act gives your spouse half" is a wrong answer, not a rough one, for an estate this Act does not
touch.

**Not** `REFUSE`. A refusal cannot be reached by anything downstream, so the savings provision
becomes unwritable. Measured:

```l4
GIVETH A NUMBER
`the rate before commencement (wrong)` MEANS
    REFUSE "the Act was not in force before 1 January 2016"

GIVETH A NUMBER
`the rate the savings provision would apply (wrong)` MEANS
    IF   `the rate before commencement (wrong)` EQUALS 0
    THEN 7
    ELSE `the rate before commencement (wrong)`
```

`#EVAL` of the second prints, under `Result:`,

```text
The model refuses to answer:
  the Act was not in force before 1 January 2016
```

The `THEN 7` arm is unreachable. That is the correct behaviour of `REFUSE` and the wrong construct
for commencement.

**Not** `NOTHING` either — see entry 14 for what `NOTHING` is for, and entry 17 for what a later
rule does to it.

**One documented exception.** `jl4/examples/legal/regcf/regcf.l4` does spell its pre-commencement
arm as a refusal, and says out loud why: the taxonomy puts "not in force" in the gate row, no gate
construct exists, there is no figure to return, "so the
commencement arm is a REFUSE and stays one until one does". Cite it as an exception, never as the pattern.

**See** entry 7, and [drafting-patterns.md](drafting-patterns.md), "Leap-safe date windows" for
building the comparison (and the `Date` month-subtraction footgun, which `YMD` does not share).

---

## 7. "Nothing in this Act shall affect …", "continues to apply" — savings and transitional

**If the source says**

> `s 18(5) — "Nothing in this section shall affect any law by which special provision is made regarding the estates of persons of a particular religion or race."`
>
> — `jl4/examples/legal/sg-succession/cleanroom-2026-08/probate-administration-act.l4:1600`

**It is doing** leaving some other law, or some accrued right, untouched. It is the mechanism by
which the law itself reaches a period or a class that the rule in front of you does not cover.

**Write** a boolean named for the saving, carrying the verbatim words inert beside the one fact the
ontology actually puts in evidence, and consult it in the rule it saves.

```l4
@ref Probate and Administration Act 1934 s 18(5)
GIVEN d IS A `Deceased person`
GIVETH A BOOLEAN
`s 18(5) — a law making special provision regarding the estates of persons of a particular religion or race is in evidence` d MEANS
        "Nothing in this section shall affect any law by which special provision is made regarding the estates of persons of a particular religion or race."
    AND d's `a Muslim`

GIVEN d IS A `Deceased person`
GIVETH A BOOLEAN
`s 18 governs the distribution of the estate of` d MEANS
    NOT `s 18(5) — a law making special provision regarding the estates of persons of a particular religion or race is in evidence` d
```

Name the decision for the **saving**, not for the outcome. A validating provision ("a grant is not
invalid where …") encoded under a name about validity invites exactly the opposite reading of its
own `FALSE`; the corpus renamed one for that reason
(`probate-administration-act.l4:2251-2270`).

**And state the width you did not encode.** s 18(5) does not say which law makes the special
provision, and the class is not enumerable — so what is encoded is the narrow case in evidence and
the wider saving rides inert beside it. Say that in a comment; do not let the narrow case pretend to
the full width.

**Not** a refusal on either side of the saving. See entry 6: nothing can reach past one.

**See** <https://legalese.com/l4/concepts/legal-modeling/default-reasoning.md>
for `UNLESS` and named defeaters, which is the same move at limb scale.

---

## 8. "This section does not apply where …" — the gate and the exemption

**If the source says**

> `s 28(2) — "Subsection (1) shall not apply where the grantee is the Public Trustee or a trust company."`
>
> — `jl4/examples/legal/sg-succession/cleanroom-2026-08/probate-administration-act.l4:2715`

**It is doing** switching something off — and the scale matters. A whole Act (a gate consulted
first), one section (an outcome the caller must handle), one duty (an exemption), or one limb of a
calculation.

**Write**, for a duty, the duty **not arising at all**. "s 28(2) is an exemption from the duty, not a
permission to omit it, so it is encoded by the duty not arising at all rather than by a `MAY`"
(`:2716-2717`).

```l4
@ref Probate and Administration Act 1934 s 28(1), s 28(2)
GIVEN gr IS A Grantee
GIVETH A DEONTIC Grantee `An act under the Probate and Administration Act`
`s 28 — the grantee shall take an oath` gr MEANS
    IF   `s 28(2) — the grantee is the Public Trustee or a trust company` gr
    THEN FULFILLED
    ELSE PARTY gr
         MUST  `take an oath in the prescribed form`
         WITHIN 14
```

For a **section** whose result a caller reads, make "this section is silent" a named member of the
section's own result type, as in entry 6 — so a caller matching on the result has to handle it. For
a **limb**, append `UNLESS` and name the defeater; for a whole Act, a boolean gate consulted before
anything else.

**Not** `REFUSE`, twice over: the statute has decided this case, and it has decided it in a way a
later provision may need to read. **Not** `MAY` for an exemption — a permission not to do it is a
different legal animal from a duty that never arose, and it exports differently.

**See** [regulative.md](regulative.md) for `MUST`/`MAY` polarity and residuals;
[drafting-patterns.md](drafting-patterns.md), "Total enum over `MAYBE`", for the named-outcome shape;
<https://legalese.com/l4/concepts/legal-modeling/default-reasoning.md>
for `UNLESS`.

---

## 9. "Subject to section N", "Notwithstanding anything in this Act"

**If the source says**

> `s 27(1) opens "Notwithstanding anything in this Act", so it is asked FIRST: a soldier in actual military service or a mariner at sea may make a will with no writing, no signature, no witnesses and no majority`
>
> — the encoding's note at `jl4/examples/legal/sg-succession/sg-wills.l4:712-715`, on Wills Act
> 1838 s 27(1)

**It is doing** declaring an express priority between two provisions.

**There is no construct for it.** `SUBJECT TO` and `NOTWITHSTANDING` are **not keywords today** —
the lexer has no token for either. A dedicated construct is proposed, not landed (2026-09-04).

**Write** the priority in one of the three ways the corpus uses. The first — arm order — looks like
this:

```l4
@ref Wills Act 1838 s 27(1), s 4, s 6
GIVEN w IS A Will
GIVETH A BOOLEAN
`the will is formally valid` w MEANS
  BRANCH
    IF   w's `made by a soldier in actual military service or a mariner at sea`
    THEN TRUE
    IF   NOT w's `the testator had attained the age of 21 years`
    THEN FALSE
    OTHERWISE w's `signed by the testator and attested by two witnesses`
```

1. **Arm order.** `BRANCH` is first-match, so the overriding provision goes first, and the order
   is the Act's own — record that in a comment, because the order is now load-bearing.

   **Where the Act states no priority, the order is yours, and the comment must say so.** A `BRANCH`
   over several sections has to put them in _some_ order even when no section says "notwithstanding"
   or "subject to" — most Acts do not. Writing "the Act's own order of priority" over an order you
   invented is a false claim in the one place a later reader will trust it. Write instead what you
   actually did and why, in the reader's terms: reach first, force second, exemption third,
   computation last.

   ```l4
   -- ARM ORDER. The Act states no priority between ss 3, 5 and 6. This order is
   -- the ENCODING's, chosen so each arm only runs where the ones above it did not
   -- decide the case: does the Act reach this transaction at all (s 6), is it in
   -- force for it (ss 1, 5), does s 2 apply to it (s 3), and only then the sum.
   ```

   Two consequences worth stating on the same comment: an arm that is genuinely disjoint from the
   others could sit anywhere, and reordering the arms is a change to the law the file states, not a
   tidy-up.

2. **`UNLESS` naming the overriding rule**, where the override subtracts from a conclusion rather
   than replacing it — the snippet below.
3. **The override in the name of the decision** —
   `` DECIDE `a British citizen notwithstanding cesser of the order — subsection (6)` ``
   (`jl4/examples/legal/bna/bna.l4:572`), with assertions on both sides.

```l4
GIVEN w IS A Will
GIVETH A BOOLEAN
`a grant of probate may issue on the will` w MEANS
    `the will is formally valid` w
    UNLESS `a caveat is in force against the estate`
    WHERE `a caveat is in force against the estate` MEANS FALSE
```

**Not** a grep for "subject to". In this corpus the phrase is almost always part of a **field name**
describing a status — `` `subject to the requirement to file reports pursuant to section 13 or
section 15(d) of the Exchange Act` `` (`jl4/examples/legal/regcf/regcf.l4:273`, and five more
sites in that file) — not a priority operator. Read which one you have before encoding it.

**Not** an override of a refusal. `SUBJECT TO` overrides a **conclusion**; a refusal is not a
conclusion and nothing can override it.

**See** <https://legalese.com/l4/concepts/legal-modeling/default-reasoning.md>
(its table maps "Subject to section N" to `UNLESS` naming that section's rule) and
[drafting-patterns.md](drafting-patterns.md), "Conditional / proviso limb" and "Only in a case where
X applies".

---

## 10. "shall be deemed to be", "shall be treated as"

**If the source says**

> `The deeming reaches ONLY subsection (1): "deemed for the purposes of subsection (1)". A foundling gets no help toward subsection (1A)`
>
> — `jl4/examples/legal/bna/bna.l4:263-266`, on British Nationality Act 1981 s 1(2)

**It is doing** rewriting the facts **before** the rule runs, rather than handling a gap afterwards.
This is how a statute avoids a non-answer, and it is why nothing in L4 catches a refusal: the legal
mechanism for "make this case answerable" operates upstream, not downstream.

**Write** a decision named for the deeming, and call it where the deemed facts are needed. State the
reach.

```l4
@ref British Nationality Act 1981 s 1(2)
GIVEN person IS A PersonProfile
GIVETH A BOOLEAN
DECIDE `deemed by subsection (2) to satisfy subsection (1)` person IF
        person's `found abandoned in the United Kingdom after commencement`
    AND NOT person's `the contrary shown, rebutting the subsection (2) presumption`
    AND "(a) to have been born in the United Kingdom after commencement ...; and"
    AND "(b) to have been born to a parent who ... was a British citizen or settled ..."

@ref British Nationality Act 1981 s 1(1), (2)
GIVEN person IS A PersonProfile
GIVETH A BOOLEAN
DECIDE `a British citizen under section 1(1)` person IF
        person's `born in the United Kingdom after commencement to a settled parent`
    OR  `deemed by subsection (2) to satisfy subsection (1)` person
```

The deemed limbs (a) and (b) are inert strings on purpose: they are **deemed rather than tested**, so
there is no fact to check and the words are the only content.

**Not** a new field on the record meaning "is deemed a citizen". That loses the reach — the deeming
here is for subsection (1) only, and a field would leak it into subsection (1A). **Not** a rewrite of
the tested limb into the deemed one: keep the deeming a named decision so a reader can see which
provision it serves.

**See** [drafting-patterns.md](drafting-patterns.md), "Inert never shadows active", for when the
verbatim words stay whole — a deemed fact is one of the three cases it names.

---

## 11. "such other amount as may be prescribed" — the power, exercised

**If the source says** an amount an instrument moves over time. Regulation Crowdfunding's dollar
limits are indexed for inflation by releases of the Securities and Exchange Commission, published in
the Federal Register:

```text
-- $1,000,000 as adopted (80 FR 71537); $1,070,000 from 2017-04-12
-- (82 FR 17545 instr. 5.a); $5,000,000 from 2021-03-15 (86 FR 3496 instr. 3).
```

— `jl4/examples/legal/regcf/regcf.l4:145-146`, with the rule at `:150-154`.

**It is doing** delegating the number to an instrument. The power has been exercised, so **the
instrument is law and you encode it**, with the citation on each arm.

**Write** a first-match branch over the rule date, newest first, one arm per release, and the
pre-commencement case in the `OTHERWISE`.

```l4
@ref 17 CFR 227.100(a)(1); 82 FR 17545 instr. 5.a; 86 FR 3496 instr. 3
GIVEN `the rule date` IS A DATE
GIVETH A NUMBER
`offering maximum in a 12-month period as at` `the rule date` MEANS
    BRANCH IF Day `the rule date` AT LEAST Day (YMD 2021 3 15) THEN 5000000
           IF Day `the rule date` AT LEAST Day (YMD 2017 4 12) THEN 1070000
           IF Day `the rule date` AT LEAST Day (YMD 2016 5 16) THEN 1000000
           OTHERWISE `no Regulation Crowdfunding figure exists before commencement on 2016-05-16`
```

**Not** the current figure alone. A rule that answers only for today cannot answer about a
transaction from 2018, which is most of what anyone asks a rules engine.

**Not** an `ASSUME` for the amount. It is not an unknown fact — it is written down in the release,
and an `ASSUME` puts it in the export schema as something the caller is invited to supply.

**See** entry 12 for the arm this one falls through to, and
[drafting-patterns.md](drafting-patterns.md), `Statutory tables as DATA`, when the instrument gives a
table rather than a number.

---

## 12. "The Minister may by regulations prescribe …" — the power, not exercised

**If the source says**

> `6(3)-(4) (the States' power to add heads by Regulations)` — listed among the parts that "are out of scope"
>
> — `jl4/examples/legal/charities-cleanroom/charity-test.l4:22-25`

**It is doing** one of two things, and you must decide which before writing anything:

- **The power has not been exercised, and the statute supplies its own default.** Then the default
  is the law, and you encode the default. Nothing is missing.
- **The power has not been exercised and there is no default** — or it has been exercised and this
  encoding did not reach the instrument. Then the model has no answer, and should say so.

**The test is one question: does the section supply its own fallback?** Read the sentence to the
end. "The levy is 2% of the value, **or such other rate as the Minister may prescribe**" supplies
one — 2% is the law until an instrument displaces it, and there is nothing missing to declare.
"The Minister **may by order extend** this Act to trusts" supplies none — with no order, the
sentence leaves you with no rule to encode at all. Both limbs routinely appear in **one Act**, so
decide it per section, never per statute:

```l4
-- 2. The levy is 2% of the value, OR SUCH OTHER RATE as the Minister may
--    prescribe by regulations.  The power is unexercised and the section
--    supplies its own rate, so the 2% is the law: encode it.
@ref Transactions Levy Act s 2; no regulations prescribing another rate have been made
GIVETH A NUMBER
`s 2 — the rate of the levy` MEANS 2%

-- 6. The Minister MAY BY ORDER extend this Act to trusts.  No order, and the
--    section supplies no fallback, so there is nothing to encode: a refusal.
@ref Transactions Levy Act s 6 — no order extending this Act to trusts has been made
GIVETH A `The levy on the transaction`
`no order under section 6 extending this Act to trusts is encoded in this model` MEANS
    REFUSE "no order under section 6 extending this Act to trusts is encoded in this model"

#ASSERT `s 2 — the rate of the levy` EQUALS 0.02
#ASSERT REFUSED `no order under section 6 extending this Act to trusts is encoded in this model`
```

_(`REFUSE`; checked on the `REFUSE` binary, exit 0, both assertions satisfied.)_ On `2%`, which is
a real percent literal and not a comment, see entry 22.

**Write**, for the second case, one named definition per refusal: the definition's name **is** its
message, an `@ref` above it says why, and every rule that needs it calls the name.

```l4
@ref Charities (Jersey) Law 2014 Article 6(3)-(4) — the States' power to add heads by Regulations
GIVETH A BOOLEAN
`no Regulations adding a head of charity are encoded in this model` MEANS
    REFUSE "no Regulations adding a head of charity are encoded in this model"
```

**Not** a `-- NOT MODELLED` comment on a provision a rule can actually reach. A comment stops
nothing: the evaluation runs on, the export schema does not mention it, and the wizard asks nothing
about it. A comment is right only where **no rule reaches** the gap.

**Not** `FALSE`, and not `0`. "No Regulations have been made" and "the Regulations say no" are
different answers, and a caller cannot tell them apart once you have written the second.

**Careful which side of the line you are on.** A power the legislature has never exercised is closer
to "the law provides no figure" — the entry-6 shape — than to "the model does not cover this". The
instances in **this** corpus happen all to fall on the refusal side, because in each of them the
encoding chose not to reach the instrument. Read that as a fact about what has been encoded here,
**not as a prior**: it is not evidence about the section in front of you, and taking it as one is
how a section that supplies its own default gets written as a refusal. Apply the fallback test
above to the sentence you actually have.

**See** entry 17, which is the same construct for the general case.

---

## 13. "[amount to be inserted]", a clause not yet drafted

**If the source says** a blank. This does **not** occur in the encoded corpus — no bracketed
"to be inserted", no `TBD`, no row of capital Xs, in any of the 26 files under
`jl4/examples/legal/`, because these are encodings of enacted law and enacted law has no blanks. The phrase belongs to a bill in progress or
a contract in negotiation, which this phrasebook also serves.

**It is doing** marking a hole that a human will fill later.

**Write** `TBD`, the prelude's refusal meaning exactly "not written yet" (needs `IMPORT prelude`).

```l4
IMPORT prelude

GIVETH A NUMBER
`the surcharge, [rate to be inserted]` MEANS TBD
```

`#EVAL` of it prints, under `Result:`,

```text
The model refuses to answer:
  TBD: this rule has not been written yet
```

**State the limit.** `TBD` is **not yet** reported differently from a hand-written `REFUSE`; warning
it separately as a placeholder is proposed, not landed (2026-09-04). So the drafting note in your
identifier does not reach the output at all — every `TBD` in the file prints the same one line.

**Which to write, by default: a named refusal, and `TBD` only for the one-blank scratch draft.**
The moment a file has two blanks, `TBD` stops telling the reader anything, and the reader who most
needs to know which blank they hit is the drafter who has to fill it. Measured, both on the `REFUSE`
binary, exit 0 — four `#EVAL`s over four blanks:

```l4
IMPORT prelude

-- Two blanks under TBD. The output tells the reader neither of them apart.
GIVETH A NUMBER
`the surcharge, [rate to be inserted]` MEANS TBD

GIVETH A NUMBER
`the late fee, [amount to be inserted]` MEANS TBD

-- The same two blanks, each named. The name IS the message.
GIVETH A NUMBER
`clause 4.2 — the surcharge rate is not yet drafted` MEANS
    REFUSE "clause 4.2 — the surcharge rate is not yet drafted"

GIVETH A NUMBER
`clause 9.1 — the late fee is not yet drafted` MEANS
    REFUSE "clause 9.1 — the late fee is not yet drafted"
```

The four `#EVAL` results, in order. The first two are the same line twice; the second two name
their own blank:

```text
The model refuses to answer:
  TBD: this rule has not been written yet
The model refuses to answer:
  TBD: this rule has not been written yet
The model refuses to answer:
  clause 4.2 — the surcharge rate is not yet drafted
The model refuses to answer:
  clause 9.1 — the late fee is not yet drafted
```

Keep `TBD` where it earns its brevity: a draft with a single hole, or a sketch you will finish in
the same sitting. Everything a negotiating counterparty or a second drafter will read gets a name.

**Not** `0`, `""` or `NOTHING` as a placeholder. Each is a value the rest of the file will happily
compute with, and a draft that silently prices a blank at zero is worse than one that stops.

**See** entry 17 and entry 18.

---

## 14. "…, if any", "where there is no …"

**If the source says**

> `s 7 rule 3 — "Subject to the rights of the surviving spouse, if any, the estate (both as to the undistributed portion and the reversionary interest) of an intestate who leaves issue shall be distributed by equal portions per stirpes"`
>
> — `jl4/examples/legal/sg-succession/cleanroom-2026-08/intestate-succession-act.l4:1126`

**It is doing** the drafter's own hedge that a thing may not exist, together with an instruction on
what follows when it does not. The absence is a fact about the case, as solid as any number.

**Write** `MAYBE`, matched with `CONSIDER`, and give the absent arm a name or a value that says what
follows from the absence.

```l4
DECLARE Estate HAS
    `the net value of the estate`       IS A NUMBER
    `the share of the surviving spouse` IS A MAYBE NUMBER

@ref Intestate Succession Act 1967 s 7 rule 3
GIVEN e IS AN Estate
GIVETH A NUMBER
`the portion distributable among the issue of` e MEANS
    e's `the net value of the estate`
    MINUS
    CONSIDER e's `the share of the surviving spouse`
    WHEN NOTHING THEN 0
    WHEN JUST s  THEN s
```

`MAYBE` is by far the most common non-answer in real encodings: **106** `IS A[N] MAYBE` slots in the
legal corpus alone, against 54 `ASSUME` declarations. Do not migrate them anywhere.

**Not** a refusal. An absent value is one the rule can and should handle — the statute told you how.

**Not** an unnamed `NOTHING` arm in a result the caller reads. Where the source **names** the absent
outcome ("no issuance", "the application is refused"), the outcome belongs in the result type as a
named member; see the two-question test in [drafting-patterns.md](drafting-patterns.md), "Where
`MAYBE` is right — and it usually is", which also lists the four cases where folding it would be a
mistake.

**See** `concepts/legal-modeling/non-answers.md` (new in this release), section 1.

---

## 15. "must be a positive number", a date that does not exist — invalid input

**If the source says** a requirement that rules an **input** out, rather than deciding a case: a
negative quantity, a month of 13, a form field that contradicts itself.

**It is doing** rejecting the question, not answering it. The caller can act on this: fix the form
and ask again.

**Write** `EITHER`, with a named problem on the left, so the caller must handle both shapes.

```l4
DECLARE `A problem with the filing` IS ONE OF
    `the number of securities offered is negative`
    `the offering date is not a date in the calendar`

GIVEN `the number offered` IS A NUMBER
GIVETH AN EITHER `A problem with the filing` NUMBER
`the number of securities in the filing` MEANS
    IF   `the number offered` LESS THAN 0
    THEN LEFT `the number of securities offered is negative`
    ELSE RIGHT `the number offered`
```

A caller matches with `CONSIDER … WHEN LEFT p … WHEN RIGHT n …` and turns the left into a message.

**Three facts about `EITHER` that save you a workaround.** All measured on the section-`GIVEN`
binary, exit 0.

- **`EQUALS` works on an `EITHER` value, and on an enum constructor carrying fields.** You do not
  need a boolean helper to assert which side you got. (`DEONTIC` is the type that cannot be
  `EQUALS`-compared — see [drafting-patterns.md](drafting-patterns.md), "Exercising a DEONTIC".)

  ```l4
  #ASSERT `the number of securities in the filing` (0 MINUS 5) EQUALS LEFT `the number of securities offered is negative`
  #ASSERT `the number of securities in the filing` 200 EQUALS RIGHT 200
  ```

  **Keep each `#ASSERT` on one line.** Continuing one onto the next line with `EQUALS` is a parse
  error: `unexpected EQUALS`, `expecting %, ;, end of input, or space token`. The one split form
  that does parse is `#ASSERT REFUSED` with its `BECAUSE` on the second line — entry 18.

- **A one-constructor `IS ONE OF` is legal**, and is the right shape for a problem type with exactly
  one problem in it. Do not invent a second member to make it look like the examples.

- **Read the printed forms as printed forms, not as source.** `#EVAL` renders an applied
  constructor with an `OF` that you never write:

  ```text
  `the levy is` OF 200
  LEFT OF `the stated value is not a positive amount`
  RIGHT OF (`the levy is` OF 200)
  ```

  In source these are ordinary application — `` `the levy is` 200 ``, `LEFT p`, `RIGHT x`. The word
  `OF` belongs to the printer. Copying output back into a file is the one way to get this wrong.

**Not** `REFUSE`. The standard library agrees, deliberately: `YMD 2023 2 29` — no such leap day —
evaluates to the distinguished term `` `YMD refused an out-of-range month or day` ``, and **despite
the word in its name that is not a `REFUSE`**. Out-of-range date components were left as invalid
input on purpose. Do not tidy them into refusals.

**Not** a silent clamp. `Date 1 (3 MINUS 6) 2025` clamps to January 2025 rather than rolling back to
September 2024; `YMD` is the bounds-checked constructor and is what new code should use for literals.

**See** [gotchas.md](gotchas.md), "The `daydate` month-subtraction footgun", and
`concepts/legal-modeling/non-answers.md` (new in this release), section 2.

---

## 16. "[Repealed]" — a section number with nothing under it

**If the source says** a gap in the numbering in the version in force.

**It is doing** nothing at all — which is the difficulty. "A reader who finds s 33 and then s 35
cannot otherwise tell whether s 34 was overlooked or is not there to be encoded"
(`jl4/examples/legal/sg-succession/cleanroom-2026-08/probate-administration-act.l4:2242-2246`).

**Write** a labelled stub carrying the repeal note as inert prose, with **no operative outcome** —
nothing calls it.

```l4
`ss 34 and 36 — repealed, and therefore not encoded` MEANS
        "34. [Repealed by Act 27 of 2014]"
    ... "36. [Repealed by Act 27 of 2014]"
```

**Not** a refusal. There is no question it declines to answer, because no rule reaches it — this is
documentation with a section number.

**See** [drafting-patterns.md](drafting-patterns.md), "Repealed / omitted provision → a labelled
stub".

---

## 17. Scope this encoding deliberately does not cover

**If you are about to write** `-- NOT MODELLED`, `-- OUT OF SCOPE`, or a comment beginning "we do
not handle". This is the encoder speaking, not the statute, and it is the largest single category of
prose in the corpus — 25-plus sites. One of them:

> `-- ... the honest answer is a refusal, not a guess. Outside the band the ordinary tiers were unaffected and the answer stands.`
>
> — `jl4/examples/legal/regcf/regcf.l4:482-484`, on the temporary rules made during the coronavirus
> disease 2019 pandemic

**It is doing** marking the boundary of the model. The question is only whether a rule can **reach**
that boundary at run time.

**Write**, where a rule can reach it, a named refusal — one definition per refusal, the name is the
message, an `@ref` above it says why:

```l4
DECLARE FinancialStatementRequirement IS ONE OF
    `financial statements certified by the principal executive officer`
    `financial statements reviewed by a public accountant`
    `financial statements audited by a public accountant`

@ref 85 FR 27116 (Rule 201(z)); 86 FR 3496 instr. 5 (Rule 201(bb))
GIVETH A FinancialStatementRequirement
`the COVID-19 temporary rules, Rule 201(z) and (bb), are not modelled here` MEANS
    REFUSE "the COVID-19 temporary rules, Rule 201(z) and (bb), are not modelled here"
```

A refusal is an expression at **any** type, so it needs no sentinel constructor in
`FinancialStatementRequirement` and cannot be mistaken for one of the three real answers.

**Where no rule reaches the boundary, a comment is still the right thing** — it documents a gap that
cannot be hit. State which way the omission errs, as the corpus does
(`jl4/examples/legal/sg-succession/sg-wills.l4:278-280`):

```text
-- WHICH WAY THE OMISSION ERRS. s 5 only ever ADDS ways of being properly
-- executed -- "shall be treated as properly executed if" -- so leaving it out
-- can only make `the will is formally valid` too STRICT.
```

**Not** an `ASSUME`. That says "this is an unknown fact", so it is promoted to a parameter of every
exported function that reads it — and a caller of the Regulation Crowdfunding money decisions was
being asked to supply a value for _"no Regulation Crowdfunding figure exists before commencement on
2016-05-16"_. Nobody can supply that. A refusal appears in no export schema, because it is not an
input.

**Not** `NOTHING`, because a later rule can quietly default it:

```l4
GIVETH A MAYBE NUMBER
`the figure before commencement (wrong)` MEANS NOTHING

GIVETH A NUMBER
`the figure a caller sees (wrong)` MEANS
    fromMaybe 0 `the figure before commencement (wrong)`
```

That answers `0`. The decline became an answer, one line away, and nothing in the output says so.

**And a refusal is only safe from that once something forces it.** A `REFUSE` you build into a
value — ``RIGHT (`the levy on` t)`` where the levy is the blank — is a decline that never runs,
and the caller gets an ordinary answer just as the `fromMaybe 0` above does. Entry 24 measures it
and gives the repair, which is one line: **return the refusal; do not store it.**

**Not** a computed message. `REFUSE` takes a string literal: a refusal's reason should be readable
without running the program.

**See** the `REFUSE` reference page (new in this release) and
`concepts/legal-modeling/non-answers.md` (new in this release), section 5.

---

## 18. Testing a refusal

**If you have just written** a `REFUSE`, it needs a test like anything else — and a plain `#ASSERT`
will not do it.

**Write** `#ASSERT REFUSED e`, adding `BECAUSE "…"` to pin the wording:

```l4
#ASSERT `offering maximum in a 12-month period as at` (YMD 2021 3 15) EQUALS 5000000
#ASSERT REFUSED `offering maximum in a 12-month period as at` (YMD 2016 5 15)
        BECAUSE "no Regulation Crowdfunding figure exists before commencement on 2016-05-16"
#ASSERT REFUSED `no Regulations adding a head of charity are encoded in this model`
```

All three print `assertion satisfied`. A failing one prints `assertion failed: expected a refusal,
but the expression produced a value`, or `assertion failed: expected the refusal "x", got "y"` when
the `BECAUSE` message differs. The directive may be split over two lines, as above.

Two facts worth knowing when you read the output:

- A **plain** `#ASSERT e` whose `e` refuses reports `assertion refused:` — not _failed_, and not
  _could not be evaluated_. It is telling you the assertion never got to run.
- `l4 run` **exits 0** for a file containing a refusing `#EVAL` (reported at Warning severity) or a
  refused assertion. It exits **1** for a file whose `#EVAL` reads an input nobody supplied. So a
  refusal may appear in a runnable documentation example where an unsupplied section `GIVEN` may
  not.
- **A `#ASSERT` that fails does not make `l4 run` exit non-zero.** Measured on both binaries: a
  bare `#ASSERT 1 EQUALS 2` prints `assertion failed` at **Error** severity and the process still
  exits **0**. So "the file ran green" is not evidence that the assertions passed — check the
  diagnostics for `DiagnosticSeverity_Error`, which is what `doc/test-docs.sh` does and what a
  hand-rolled `l4 run; echo $?` does not.

**Not** `#ASSERT NOT e` to show that a rule declines. That reports a refusal too, and says nothing
about the message.

**And `#ASSERT REFUSED e` is a claim about `e`, not about the refusal inside it.** If `e` can reach
the refusal without forcing it, the assertion **fails** with `expected a refusal, but the expression
produced a value` — which is the test doing its job, telling you the decline is not on the path the
caller takes. Do not repair that by asserting on the inner refusal instead; that only tests the
definition. Read entry 24 first and decide whether the wrapping was right.

**See** the `REFUSE` reference page (new in this release), and entry 24.

---

## 19. Migrating an existing `ASSUME`

**If the file already has** a block of module-level `ASSUME`s standing in for facts about the case:

```l4
ASSUME `the person is a body corporate` IS BOOLEAN
ASSUME `the person engages in business for profit` IS BOOLEAN
```

— the first two of seven such lines at `jl4/examples/legal/imaginary-alcohol-act.l4:33-39`, read
by the rule at `:41`.

**It is doing** three different jobs across a corpus, and each has its own destination:

| the `ASSUME` is                                     | it becomes                                                                                  |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| a fact about the case, to be supplied by the caller | a section `GIVEN` under the heading of the section whose rules read it                      |
| an uninterpreted type (`ASSUME T IS A TYPE`)        | `DECLARE T` — **which does not parse today**; leave these as `ASSUME`                       |
| a stand-in for something the model does not cover   | a named `REFUSE` (entry 17) — it was never a fact, and it should never have been suppliable |

**Write** the first case as one section `GIVEN`, names comma-separated, under the provision's
heading:

```l4
§§ `Section 1 — Prohibition on sale`
    GIVEN `is a body corporate`             IS A BOOLEAN,
          `engages in business for profit`  IS A BOOLEAN

GIVETH A BOOLEAN
`the person must not sell alcohol` MEANS
        `is a body corporate`
    AND `engages in business for profit`
```

**Behaviour in this release is identical.** A module-level `ASSUME` and a section `GIVEN` both
evaluate as assumed terms and both export as parameters. The migration buys scoping and the reader's
eye, not new behaviour — so do it when you are editing the section anyway, and do not sweep a corpus
for it.

**Not** a migration that expects `@export` to start working. A **function-typed** input is rejected
for `@export` whichever way it is declared: `Function type inputs are not supported for @export`.
Moving it to a section `GIVEN` does not change that.

**Not** a claim that `ASSUME` has stopped working. It parses, checks and exports as before, and no
deprecation warning is emitted.

**See** entry 2 (where to put it), entry 17 (when it was a refusal all along), and
the skill's own page, "Declaring inputs: one record, or a section `GIVEN`".

---

## 20. "may be granted", "may be made", "may be revoked" — the passive `may`

**If the source says**

> `-- "8.--(1) Probate may be granted to any executor appointed by a will."`
>
> — `jl4/examples/legal/sg-succession/sg-paa.l4:432`, encoded at `:450` as
> `` `probate may be granted to` p MEANS … ``, a `GIVETH A BOOLEAN`.

**It is doing** stating an **eligibility test**, not conferring a permission. Read who holds the
permission: in "the applicant may be granted a licence", the applicant is the grammatical subject
but the _object_ of the granting. Whatever discretion there is belongs to the Registrar, and the
sentence in front of you is about whether this applicant is inside the class the Registrar may
grant to. The same is true of "an order may be made", "a caveat may be entered", "registration may
be revoked".

**Write** a `GIVETH A BOOLEAN` decision, in the source's own words, with no deontic in it. The
corpus does this twice over: `` `probate may be granted to` `` above, and
`` `registration may be granted` person … `` (`jl4/examples/legal/bna/bna.l4:461`).

```l4
-- 6.—(1) The applicant may be granted a licence if the applicant is 18 years
--        of age or older and has not been disqualified under section 9.
@ref Licensing Act s 6(1)
GIVEN `the person` IS AN Applicant
GIVETH A BOOLEAN
`s 6(1) — a licence may be granted to` `the person` MEANS
        `the person`'s `age in years` AT LEAST 18
    AND NOT `the person`'s `has been disqualified under section 9`
```

_(Neither feature; checked on the section-`GIVEN` binary, exit 0.)_

**Reach for `MAY` only where the section goes on to say what the office-holder may do**, and then
the `PARTY` is that office-holder — never the person the passive put in front:

```l4
@ref Licensing Act s 6(1)
GIVEN `the person` IS AN Applicant
GIVETH A DEONTIC `A party under this Part` `An act under this Part`
`s 6(1) — the Registrar may grant a licence to` `the person` MEANS
    IF   `s 6(1) — a licence may be granted to` `the person`
    THEN PARTY  `the Registrar of Licences`
         MAY    `grant a licence to the applicant`
         WITHIN 30
    ELSE FULFILLED
```

`GIVETH A DEONTIC` takes two **type** names, and both may be backticked multi-word names, as here.

**Not** `PARTY the-applicant MAY be-granted-a-licence`, which is what the mechanical rule
"statutory _may_ → `MAY`" produces on this sentence. It puts the permission in the wrong party's
hands, and it turns a constitutive test — the thing every later section will want to consult as a
boolean — into a deontic that cannot be `EQUALS`-compared and has to be exercised with `#TRACE`.

**The tell.** Ask _who is permitted to do what_. If the answer is "nobody in this sentence — it says
when a thing is permissible", it is a boolean. Active voice with a named actor ("the Registrar may
refuse an application", "the tenant may terminate") is the real permission.

**See** [regulative.md](regulative.md) for `MUST`/`MAY` polarity, and
[drafting-patterns.md](drafting-patterns.md), "Mandatory vs discretionary", whose Part I / Part II
examples are both _active_ — "the court shall make an order" / "the court may make an order" — which
is why they do not raise this trap and this entry does.

---

## 21. "within 14 days after the change" — the deadline whose unit only you know

**If the source says**

> `s 28(1) — "Upon the grant of any probate or letters of administration, the grantee shall take an oath in the prescribed form …"`, encoded with `WITHIN 14`
>
> — the shape at entry 8, from
> `jl4/examples/legal/sg-succession/cleanroom-2026-08/probate-administration-act.l4:2715`

**It is doing** fixing a period, in a unit — days, months, business days — that the statute states
and L4 does not record. `WITHIN` takes a bare `NUMBER` on the same nameless timeline as the `AT`
timestamps in a `#TRACE`. Nothing in the language, the type-checker or the output says that your
`14` means days; if a later section says "within 3 months" and you write `WITHIN 3`, the two rules
are silently on different scales and nothing will tell you.

**Write** the number, and put the unit where a reader will meet it: in the comment carrying the
verbatim words, and in the `BECAUSE` string, which is the one part of the deontic that reaches an
auditor.

```l4
-- 8. A person ("P") who holds a licence must notify the Registrar of any
--    change of P's address WITHIN 14 DAYS after the change.
--
-- THE UNIT IS DAYS, AND ONLY THIS COMMENT SAYS SO. `WITHIN` takes a bare
-- NUMBER on the same timeline as the #TRACE timestamps below; nothing in the
-- language or the checker records that 14 means days.
@ref Licensing Act s 8
GIVETH A DEONTIC `A party under this Part` `An act under section 8`
`s 8 — P must notify the Registrar of any change of address` MEANS
    PARTY  `the licence holder P`
    MUST   `notify the Registrar of the change of address`
    WITHIN 14
    HENCE  FULFILLED
    LEST   BREACH BY `the licence holder P`
           BECAUSE "P did not notify the Registrar within 14 days after the change of address"

-- Day 10, in time.
#TRACE `s 8 — P must notify the Registrar of any change of address` AT 0 WITH
    PARTY `the licence holder P` DOES `notify the Registrar of the change of address` AT 10

-- Day 20, too late.
#TRACE `s 8 — P must notify the Registrar of any change of address` AT 0 WITH
    PARTY `the licence holder P` DOES `notify the Registrar of the change of address` AT 20

-- No event at all: the duty is still standing, and the trace prints it back.
#TRACE `s 8 — P must notify the Registrar of any change of address` AT 0 WITH
    -- no events
```

_(Neither feature; checked on the section-`GIVEN` binary, exit 0.)_ The three results, in order:

```text
FULFILLED

DEONTIC BREACHED:
  BREACH
  BY `the licence holder P`
  BECAUSE "P did not notify the Registrar within 14 days after the change of address"

PARTY `the licence holder P` MUST `notify the Registrar of the change of address` WITHIN 14 HENCE FULFILLED LEST (BREACH BY …)
```

**A `#TRACE` whose `WITH` block holds only a comment is legal**, and it is how you show the duty
standing un-discharged: with no event and no clock movement the deadline has not passed either, so
the result is the **residual obligation**, not a breach. **Not** a `#TRACE` with the `WITH` dropped
altogether — that is a parse error, `unexpected end of input / expecting %, WITH, or space token`.

**Not** a unit written into the deadline. There is no unit keyword to append: `WITHIN 14 days` does
**not** parse as "fourteen days" — `days` is an ordinary identifier, so the line is read as applying
a function to `14`, and the file fails to check with

```
I could not find a definition for the identifier

  days

which I have inferred to be of type:

  FUNCTION FROM NUMBER TO NUMBER
```

Measured on the section-`GIVEN` binary, exit 1. The anchored form
[regulative.md](regulative.md) shows under "`WITHIN` — deadlines" —
`` WITHIN 5 days OF `order confirmation` `` — does not parse either: `unexpected OF`, exit 1,
measured on the same binary. **Write the bare number.** A `currency` library ships, but no unit
library does. The discipline is: one unit per file, stated once at the top, and every `WITHIN` and
every `AT` on it.

**See** [regulative.md](regulative.md), "`WITHIN` — deadlines", and entry 22 for the same problem in
money.

---

## 22. "2% of the value", "a fee of $50" — a rate and an amount

**If the source says** a percentage or a sum of money.

**It is doing** what it looks like — but the two land differently in L4.

**Write** the percentage as a **percent literal**: `%` is a real postfix operator, not a comment.
`2%` evaluates to `0.02`, `0.4%` to `0.004`, `100%` to `1`, and it applies to a name or a
parenthesised expression as readily as to a numeral. Measured, all on the section-`GIVEN` binary,
exit 0:

```l4
`the rate` MEANS 2%
`a fractional rate` MEANS 0.4%
`n` MEANS 2

#EVAL `the rate`                          -- 0.02
#EVAL `a fractional rate`                 -- 0.004
#EVAL 100%                                -- 1
#EVAL n%                                  -- 0.02
#EVAL (1 PLUS 1)%                         -- 0.02
#ASSERT 10_000 TIMES `the rate` EQUALS 200
```

So `` `s 2 — the rate of the levy` MEANS 2% ``, with
`` value TIMES `s 2 — the rate of the levy` `` reading it back, is the whole of "the levy is 2% of
the value" — and the statute's own figure is on the page.

**Write the money as a bare `NUMBER`, and say what the currency is in the name or a comment.** There
is no money type in the language and `$50` is not a literal. `IMPORT currency` resolves and is
cheap, but what it supplies is a table of ISO (International Organization for Standardization) 4217
facts — a three-letter code and a decimal-places count per currency — not a money type
and not an arithmetic that carries a unit. Amounts stay `NUMBER`s either way, so the same discipline
as entry 21 applies: one currency per file, stated once.

```l4
-- 6.—(2) For the purposes of this section, "the fee" means $50.
--        Amounts in this file are Singapore dollars.
@ref Licensing Act s 6(2)
GIVETH A NUMBER
`the fee` MEANS 50
```

**Not** `0.02` where the source says `2%`. Both evaluate the same and only one of them reads back
against the statute — and a reader who has to check whether you dropped a factor of 100 is doing
work the literal would have saved.

**Not** a name that hides the unit: `` `the fee` `` under a file whose amounts are dollars is fine,
`` `the fee in cents` `` beside `` `the fee` `` in dollars is a bug waiting for its first
subtraction.

**See** entry 11 for a rate that an instrument moves over time, and entry 12 for a rate the section
supplies as its own default.

---

## 23. "… under section 9", where section 9 is not in the slice you are encoding

**If the source says** a condition that turns on a provision your encoding does not contain — a
section outside the extract, an Act you did not reach, a schedule left for later.

**It is doing** exactly what it does for a full encoding; the gap is yours, not the statute's. There
are two honest readings and the choice is a modelling decision, not a detail:

- **The cross-reference names a recorded status.** "Has not been disqualified under section 9" is
  something a registrar can look up and answer without running s 9. Then it is a fact about the
  case: a field on the record, supplied at the boundary like any other.
- **The cross-reference names a rule you would have to run.** If answering it means applying s 9's
  own conditions to facts the caller does not have, nobody can supply it, and inviting them to is
  worse than declining. Then it is a named refusal (entry 17) — or a reason to go and encode s 9.

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
#ASSERT `s 6(1) — a licence may be granted to` `an applicant aged 25 who is not disqualified`
#ASSERT REFUSED `s 6(1) — a licence may be granted to, deciding s 9 here` `an applicant aged 25 who is not disqualified`
#ASSERT NOT `s 6(1) — a licence may be granted to, deciding s 9 here` `an applicant aged 17`
```

**Not** a field named for a rule. `` `has been disqualified under section 9` `` is defensible
because disqualification is a status a register holds; `` `satisfies section 9` `` on a section that
computes something would be a promise the caller cannot keep.

**Not** a silent choice. Whichever reading you take, an unmarked one is indistinguishable from not
having noticed, and the next reader has to re-derive it from the statute you did not include.

**See** entry 17 (the refusal shape and its `@ref`), entry 24 (why the refusal in reading 2 is
sometimes skipped, and why that is right here), and the row-7 test in the closing table.

---

## 24. A refusal only refuses when something forces it

**If you have written** a `REFUSE` and want to rely on "nothing downstream can catch it".

**It is doing** less than the sentence suggests. The guarantee is real: no `CONSIDER`, `IF`, `AND`,
`WHERE` or `MAYBE` match can observe a refusal and convert it to a value. But L4 evaluates lazily,
so a refusal that nothing **forces** never runs at all, and an unrun refusal is indistinguishable
from no refusal. Both halves are measured below.

**Write** the refusal in **return** position — as the answer the rule gives — not stored inside a
value the rule hands back.

The failure first, because it is the one that ships. A rule that wraps the refusal in a constructor
and a second rule that only looks at the constructor:

```l4
IMPORT prelude

DECLARE `A problem with the return` IS ONE OF
    `the stated value is not a positive amount`

@ref Transactions Levy Act s 4 — the amount is a blank in the draft
GIVETH A NUMBER
`s 4 — the levy where there is no stated value, [amount to be inserted]` MEANS TBD

GIVEN `the stated value` IS A MAYBE NUMBER
GIVETH AN EITHER `A problem with the return` NUMBER
`the return for a stated value of` `the stated value` MEANS
    CONSIDER `the stated value`
    WHEN NOTHING THEN RIGHT `s 4 — the levy where there is no stated value, [amount to be inserted]`
    WHEN JUST v  THEN IF   v AT MOST 0
                      THEN LEFT `the stated value is not a positive amount`
                      ELSE RIGHT (v TIMES 2%)

GIVEN `the stated value` IS A MAYBE NUMBER
GIVETH A BOOLEAN
`the return is rejected for a stated value of` `the stated value` MEANS
    CONSIDER `the return for a stated value of` `the stated value`
    WHEN LEFT p  THEN TRUE
    WHEN RIGHT r THEN FALSE

#EVAL `the return is rejected for a stated value of` NOTHING
```

_(`REFUSE`; checked on the `REFUSE` binary, exit 0.)_ That `#EVAL` answers **`FALSE`**. The blank
from s 4 is sitting inside the `RIGHT`, and asking whether the return is rejected never opens it, so
a return built on an amount nobody has drafted is reported as _not rejected_ — a decision, made on a
value that does not exist. The file is green, no warning fires, and nothing in the output mentions a
refusal. This is the same failure the entry-17 `fromMaybe 0` example warns about, arriving through
the construct that was supposed to prevent it.

**The repair is to return the refusal rather than store it.** Declare it once at any type
(`GIVEN a IS A TYPE` / `GIVETH AN a`) and give it back as the answer:

```l4
@ref Transactions Levy Act s 4 — the amount is a blank in the draft
GIVEN a IS A TYPE
GIVETH AN a
`s 4 — the levy where there is no stated value, [amount to be inserted]` MEANS
    REFUSE "s 4 — the levy where there is no stated value, [amount to be inserted]"

GIVEN `the stated value` IS A MAYBE NUMBER
GIVETH AN EITHER `A problem with the return` NUMBER
`the return for a stated value of` `the stated value` MEANS
    CONSIDER `the stated value`
    WHEN NOTHING THEN `s 4 — the levy where there is no stated value, [amount to be inserted]`
    WHEN JUST v  THEN IF   v AT MOST 0
                      THEN LEFT `the stated value is not a positive amount`
                      ELSE RIGHT (v TIMES 2%)

#ASSERT REFUSED `the return is rejected for a stated value of` NOTHING BECAUSE "s 4 — the levy where there is no stated value, [amount to be inserted]"
#ASSERT `the return is rejected for a stated value of` (JUST (0 MINUS 5))
#ASSERT NOT `the return is rejected for a stated value of` (JUST 100)
```

_(`REFUSE`; checked on the `REFUSE` binary, exit 0, all three satisfied.)_ Now the decline reaches
the boundary **through** a downstream `CONSIDER`, which is the guarantee working as advertised: the
`CONSIDER` cannot see it, cannot match on it, and cannot answer instead of it.

**The same laziness at limb scale, and there it is a feature.** `FALSE AND r` answers `FALSE`
without forcing `r`; `r AND FALSE` refuses. So a limb chain whose earlier limbs already decide the
case skips a refusal further down, which is the right legal answer — entry 23's 17-year-old fails on
age whether or not s 9 is encoded. Order your limbs so the ones the model can answer come first.

**Not** a `#ASSERT REFUSED` on the inner definition as proof that the caller will see it. That tests
the definition, not the path. Assert on the thing a caller actually calls.

**Not** the reading that laziness makes `REFUSE` unsafe. It makes the _placement_ load-bearing:
a refusal in return position is uncatchable exactly as advertised.

**See** entry 17 (the shape and its `@ref`), entry 18 (`#ASSERT REFUSED`), and the closing table,
row 7.

---

## 25. Exercising a rule that reads a section `GIVEN`

**If you have written** the house-style input — a `GIVEN` indented under a `§` heading — and now
want directives that show the rule working.

**It is doing** something no directive can supply from inside the file. Supplying a section `GIVEN`
with `WITH` is proposed, not landed (2026-09-04); values come from a web form, from
`l4 batch --inputs cases.json`, or from the service request. So a `#EVAL` or `#ASSERT` that reaches an unsupplied
section `GIVEN` stops and makes `l4 run` **exit 1** — see entry 5 for the two messages it prints and
why neither of them is about the construct it names.

**Write** two rules where you were going to write one: the operative test as an ordinary **rule
`GIVEN`**, which any case can be passed to, and the section's own rule as a one-line delegation that
reads the section `GIVEN`. Exercise the first with `#ASSERT`, and the second with `#CHECK`.

```l4
DECLARE Applicant HAS
    `age in years`                          IS A NUMBER
    `has been disqualified under section 9` IS A BOOLEAN

§ `Part 2 — Licences`
    GIVEN `the applicant` IS AN Applicant

-- The operative test, as an ordinary rule GIVEN: exercisable with any case.
@ref Licensing Act s 6(1)
GIVEN `the person` IS AN Applicant
GIVETH A BOOLEAN
`s 6(1) — a licence may be granted to` `the person` MEANS
        `the person`'s `age in years` AT LEAST 18
    AND NOT `the person`'s `has been disqualified under section 9`

-- The Part's own rule, in the Part's own words, reading the section GIVEN.
@ref Licensing Act s 6(1)
GIVETH A BOOLEAN
`s 6(1) — the applicant may be granted a licence` MEANS
    `s 6(1) — a licence may be granted to` `the applicant`

`an applicant aged 25 who is not disqualified` MEANS Applicant WITH
    `age in years`                          IS 25
    `has been disqualified under section 9` IS FALSE

#ASSERT `s 6(1) — a licence may be granted to` `an applicant aged 25 who is not disqualified`
#CHECK  `s 6(1) — the applicant may be granted a licence`
```

_(Section `GIVEN`; checked on the section-`GIVEN` binary, exit 0.)_ The `#ASSERT` prints
`assertion satisfied`; the `#CHECK` prints `BOOLEAN ` at Information severity and costs the run
nothing, because it type-checks without evaluating. **`#CHECK` is the only directive that is safe on
a rule with an unsupplied section `GIVEN`**, and it is what keeps a file in the house style runnable.

The delegation is not scaffolding you delete later. It is the same split the statute makes: a test
stated in general terms, and a Part that applies it to the person the Part is about. Both names are
worth having, and when supply lands the second becomes callable as it stands.

**Not** a `#EVAL` or `#ASSERT` on the section-`GIVEN` rule. Exit 1, and on a page under `doc/` it
fails the docs harness.

**Not** a section `GIVEN` abandoned for a rule `GIVEN` because you could not test it. The repetition
the section `GIVEN` removes is real — 62 identical lines in one corpus file (entry 2) — and one
extra delegating rule per section is a much smaller price.

**Not** `#CHECK … WITH x IS v`. `WITH` at a directive names a **rule's own** inputs, so it works on
the delegating rule's `GIVEN`-parameterised twin and not on the section `GIVEN`; naming a section
`GIVEN` there is a check error, not a parse error. Entry 5 has the detail.

**See** entry 2 (why the section `GIVEN` is the house style), entry 5 (the two failure messages),
and the `section GIVEN` reference page (new in this release).

---

## The questions to ask, in order

When a rule cannot produce an ordinary value, work down this list and stop at the first `yes`. The
order matters: the expensive mistakes are all a case answered by a later row being written as an
earlier one.

| #   | Ask                                                                                        | If yes, write                                                                           | Who handles it                      | Can a later rule catch it? |
| --- | ------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------- | ----------------------------------- | -------------------------- |
| 1   | Does the source itself contemplate the thing being absent — "if any", "where there is no"? | `MAYBE`, matched with `CONSIDER`                                                        | the rule, by matching               | yes, as a value            |
| 2   | Is the **input** invalid — a negative count, a month of 13, a self-contradicting form?     | `EITHER`, with a named problem on the left                                              | the rule or its caller              | yes, as a value            |
| 3   | Is it simply a fact **nobody has told us yet**?                                            | an input: a record parameter or section `GIVEN`                                         | the boundary, by asking             | not applicable             |
| 4   | Does the **law** say it does not apply, or was not yet in force?                           | an ordinary value, or a gate consulted first                                            | savings and transitional provisions | yes                        |
| 5   | Is it a **duty that was not performed**?                                                   | `LEST` on the obligation                                                                | the obligation's own branch         | structured                 |
| 6   | Is the conclusion **overridden** by another provision?                                     | arm order, or `UNLESS` naming the overriding rule (`SUBJECT TO` is not a keyword today) | the overriding rule                 | structured                 |
| 7   | Does **the model** not cover this — the encoder declining, not the law?                    | `REFUSE "…"` (`TBD` if the reason is "not written yet")                                 | the boundary only                   | **no**                     |

Row 7 is the only one nothing downstream can catch, and that is what it is for: an absent value can
be quietly defaulted by a later rule, a refusal cannot — **provided something forces it**, which is
a question about where you put the `REFUSE` and is settled in entry 24. Rows 4 and 7 are the pair
that gets confused, and the test between them is whose sentence it is — the law's, or yours.

Three tests worth having to hand while you work down the table, each the answer to a question the
rows above do not settle on their own:

| when you are unsure                           | ask                                                                   | it is in |
| --------------------------------------------- | --------------------------------------------------------------------- | -------- |
| a delegated power, unexercised (rows 4 vs 7)  | does the section supply its own fallback?                             | entry 12 |
| a cross-reference outside your slice          | can a caller answer it without running the missing rule?              | entry 23 |
| a statutory `may` — deontic, or a plain test? | who is permitted to do what? if nobody is named, it is a boolean test | entry 20 |
