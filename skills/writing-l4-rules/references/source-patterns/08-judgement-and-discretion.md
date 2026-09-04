# 8. Judgement and discretion

One area of the phrasebook. The index, the preamble and the other ten areas are in
[source-patterns.md](../source-patterns.md).

**The rule that governs the whole area: an evaluative standard is an input, never a computation.**
"Reasonable", "satisfied", "in the opinion of", "thinks fit" are places where the instrument hands
the question to a named decision-maker. An encoding that computes them has quietly replaced that
decision-maker with the encoder — and the substitution is invisible, because the result is a
confident boolean either way. What the module can do, and should, is **record who decided, what they
decided, and whether they went about it the way the instrument requires**.

Every snippet below was run on the current binary before it went in, the **Not** blocks included.
Most of the Nots here compile. That is the point: this is the area where the wrong shape produces a
clean answer rather than a diagnostic.

<a id="e8-1"></a>

## 8.1 "may reasonably be regarded as", "of a like nature" — the open standard

**If the source says**

> `-- AMBIGUITY A3 — 6(1)(p), "any other purpose that may reasonably be regarded as analogous to any of the purposes listed in sub-paragraphs (a) to (o)".` … `-- TAKEN: (i). "may reasonably be regarded" is the language of judgement, and 6(2)(f) is expressed as one instance ..., not as an exhaustive definition. Encoded as an input judgement rather than a computed one: this module records WHO decided the analogy, it does not decide it. That is a real limit on what this formalisation can verify and it is stated here rather than papered over.`
>
> — `jl4/examples/legal/charities-cleanroom/charity-test.l4:339-350`, on the Charities (Jersey)
> Law 2014.

**It is doing** leaving a category **open**. A closing limb like "any other purpose analogous to the
above" exists exactly because the drafter could not enumerate what belongs there. There is no fact
in the file from which the answer follows.

**Write** the standard as a boolean field whose name is the standard's own words, and read it.

```l4
DECLARE Purpose HAS
    `the advancement of animal welfare`                                                          IS A BOOLEAN  -- 6(1)(o)
    `reasonably regarded as analogous to any of the purposes listed in sub-paragraphs (a) to (o)` IS A BOOLEAN  -- 6(1)(p)

-- Encoded as an INPUT judgement, not a computed one: this module records who
-- decided the analogy; it does not decide it.
GIVEN purpose IS A Purpose
GIVETH A BOOLEAN
`(p) -- any other analogous purpose` purpose MEANS
    purpose's `reasonably regarded as analogous to any of the purposes listed in sub-paragraphs (a) to (o)`
```

Keeping the statute's whole phrase as the field name is deliberate. It is what a fact-supplier reads
on the form, and it is what stops the field drifting into a shorter, different question.

**Say the limit out loud.** The corpus note above does not merely take a reading; it records that
the reading is "a real limit on what this formalisation can verify". A user of the projections is
entitled to know which answers the module computed and which it was told.

**Not** a proxy assembled from facts the drafter never mentioned:

```l4
DECLARE Purpose HAS
    `the advancement of animal welfare`   IS A BOOLEAN
    `the advancement of education`        IS A BOOLEAN
    `the number of beneficiaries`         IS A NUMBER

GIVEN purpose IS A Purpose
GIVETH A BOOLEAN
`(p) -- any other analogous purpose` purpose MEANS
        purpose's `the number of beneficiaries` AT LEAST 100
    AND (purpose's `the advancement of animal welfare` OR purpose's `the advancement of education`)
```

The record has to be rewritten too, and that is the first tell: the statute's own field is gone and
two the drafter never mentioned have taken its place. Run as a module of its own it compiles and
answers with total confidence — against a purpose an assessor **did** find analogous but which
benefits nobody on the invented list, ``#ASSERT NOT `(p) -- any other analogous purpose` (Purpose OF
FALSE, FALSE, 5000)`` prints `assertion satisfied`. The module has overruled the assessor, and there
is no diagnostic anywhere to say so.

**See** [drafting-patterns.md](../drafting-patterns.md), "Checkbox relation-on-an-entity", for the
field shape, and entry [1.5](01-definitions-and-scope.md#e1-5) for recording a provision on which two
readings are open.

<a id="e8-2"></a>

## 8.2 "if satisfied on reasonable grounds that" — record who was satisfied

**If the source says**

> `-- An authorised person may issue a community protection notice to an individual aged 16 or over, or a body, if satisfied on reasonable grounds that— a. the conduct ... is having a detrimental effect ... and b. the conduct is unreasonable.`
>
> — `jl4/examples/legal/anti-social.l4:3-9`.

**It is doing** conditioning a power on **somebody's state of mind**, tested against a standard.
Two things are true at once, and both belong in the record: the officer was satisfied, and the
grounds were reasonable ones. Neither is derivable from the conduct itself — if it were, the section
would have said so.

**Write** one record for what the decision-maker recorded, with the office-holder named and the
statutory words kept whole.

```l4
DECLARE `Grounds recorded by the authorised person` HAS
    `who was satisfied`                                                     IS A STRING
    `satisfied on reasonable grounds that the conduct is having a detrimental effect, of a persistent or continuing nature, on the quality of life of those in the locality` IS A BOOLEAN
    `satisfied on reasonable grounds that the conduct is unreasonable`      IS A BOOLEAN

GIVEN g IS A `Grounds recorded by the authorised person`
GIVETH A BOOLEAN
DECIDE `the section 43(1) grounds are made out on` g IF
        "(a)" ... g's `satisfied on reasonable grounds that the conduct is having a detrimental effect, of a persistent or continuing nature, on the quality of life of those in the locality`
    AND "(b)" ... g's `satisfied on reasonable grounds that the conduct is unreasonable`
```

**Not** an uninterpreted function standing in for the judgement. `anti-social.l4` itself does this —
``ASSUME `is unreasonable` IS A FUNCTION FROM Conduct TO BOOLEAN`` at `:28` — and carries its own
warning at `:30-33`: "this function is NOT @export. Its body calls function-typed `ASSUME`s … which
stay uninterpreted at runtime — exporting it would produce a tool that fails with 'assumed term'
errors on every invocation." Measured, that is exactly what happens, and `l4 run` exits 1:

```
I could not continue evaluating, because I needed to know the value of
  `is unreasonable`
but it is an assumed term.
```

A boolean field on a record answers the same question, evaluates, exports, and appears on the form
with the statute's words on it.

**See** [regulative.md](../regulative.md) for the `MAY` that follows once the grounds are made out,
and entry [5.1](05-duties-powers-consequences.md#e5-1) for reading who actually holds that
permission.

<a id="e8-3"></a>

## 8.3 "has a reasonable basis for believing", "reasonably designed", "in the exercise of reasonable care" — whose belief?

**If the source says**

> `` `the intermediary has a reasonable basis for believing that the investor satisfies the investment limitations` IS A BOOLEAN ``
>
> — `jl4/examples/legal/regcf/regcf.l4:580`, a field of `IntermediaryArrangement`, read at `:603` as
> the second limb of `` `the intermediary has discharged its investor-facing duties` ``.

**It is doing** imposing a duty **on one party to have formed a view about another**. The subject of
the belief and the subject of the facts are different people, and the duty attaches to the believer.
The same shape covers "written policies and procedures reasonably designed to achieve compliance"
and "did not know and, in the exercise of reasonable care, could not have known".

**Write** the field on the record of the party who must hold the belief, and let its name say whose
belief it is.

```l4
DECLARE Intermediary HAS
    `the intermediary has a reasonable basis for believing that the investor satisfies the investment limitations` IS A BOOLEAN

GIVEN i IS AN Intermediary
GIVETH A BOOLEAN
DECIDE `Rule 303(b)(1) is satisfied by` i IF
    i's `the intermediary has a reasonable basis for believing that the investor satisfies the investment limitations`
```

**Not** the belief replaced by the arithmetic it was a belief about:

```l4
DECLARE Investor HAS
    `annual income` IS A NUMBER
    `net worth`     IS A NUMBER

GIVEN inv IS AN Investor
GIVETH A BOOLEAN
DECIDE `Rule 303(b)(1) is satisfied for` inv IF
    inv's `annual income` AT LEAST 124000 OR inv's `net worth` AT LEAST 124000
```

This compiles and prints `assertion satisfied` for a wealthy investor whose intermediary never formed
a view at all — which is the precise breach the rule exists to catch. It also fails the other way:
an intermediary with a well-founded belief on the information available to it is not in breach
because the investor's true figures turned out lower.

**The tell.** Read the sentence for its grammatical subject. "The intermediary must have a
reasonable basis for believing that the investor …" — the duty-holder is the intermediary, so the
field goes on the intermediary. If you find yourself putting it on the investor, you have swapped the
parties.

**See** entry [6.1](06-parties-and-things.md#e6-1) on performers and participants, which is the same
distinction one level up.

<a id="e8-4"></a>

## 8.4 "in the opinion of the Registrar", "if the court is satisfied" — a determination is a record, not a flag

**If the source says**

> `-- The Article 7 determination, as a record of what the determiner found and what the determiner did. Two of these fields are TRUTH-conditional (they can change whether the entity provides public benefit); four are PROCEDURAL (they record compliance with Article 7(2) and 7(3)(a), which bind the determiner's reasoning, not the entity's status).`
>
> — `jl4/examples/legal/charities-cleanroom/charity-test.l4:156-160`, above `DECLARE
PublicBenefitFinding`.

**It is doing** two jobs the same sentence usually hides. A determination has a **content** (what was
found) and a **manner** (how it was reached). Provisions that bind the determiner's reasoning —
"shall have regard to", "shall not presume" — attack the manner. They can invalidate a determination
whose content is perfectly correct.

**Write** the determination as a record with both kinds of field, marked as such, and a separate
decision for whether it was properly made.

```l4
DECLARE PublicBenefitFinding HAS
    `description`                                                                                                IS A STRING
    `public benefit in Jersey or elsewhere, to a reasonable degree, provided in giving effect to those purposes`  IS A BOOLEAN  -- truth-conditional
    `regard had to the comparison required by Article 7(2)(a)`                                                    IS A BOOLEAN  -- procedural
    `a particular charitable purpose presumed to be for the public benefit`                                       IS A BOOLEAN  -- 7(3)(a), procedural

GIVEN f IS A PublicBenefitFinding
GIVETH A BOOLEAN
`the public benefit determination was properly made` f MEANS
        f's `regard had to the comparison required by Article 7(2)(a)`
    AND NOT f's `a particular charitable purpose presumed to be for the public benefit`
```

The `description` field is not decoration: it is where the determiner's own words go, so that a
projection can show a human what was decided rather than a row of `TRUE`s.

**Not** one boolean, "the Registrar is satisfied". It compiles, and a determination reached by a
forbidden presumption becomes indistinguishable from a proper one:

```l4
DECLARE Entity HAS
    `the Registrar is satisfied that the entity provides public benefit` IS A BOOLEAN

GIVEN e IS AN Entity
GIVETH A BOOLEAN
`the public benefit determination was properly made` e MEANS
    e's `the Registrar is satisfied that the entity provides public benefit`
```

`assertion satisfied`, on facts where the statute says the determination is bad. The procedural
provisions have nothing to bite on, so they simply vanish from the encoding.

**See** [drafting-patterns.md](../drafting-patterns.md), "Checkbox relation-on-an-entity", and entry
[7.5](07-presumptions-and-defaults.md#e7-5), which is the provision that forbids the presumption this
record catches.

<a id="e8-5"></a>

## 8.5 "in its sole discretion", "as the court thinks fit" — say who is eligible, do not pick

**If the source says**

> `-- "(4) Without prejudice to the generality of subsection (2) -- (a) letters of administration may be granted to the husband or widow or next of kin or any of them; (b) when such persons apply for letters of administration, it shall be in the discretion of the court to grant them to any one or more of such persons; ..."`
>
> — `jl4/examples/legal/sg-succession/sg-paa.l4:596-601`. The note at `:613-615`: "within rank 1,
> s 18(4)(b) puts the choice squarely in the court's discretion, and this module does not pretend
> otherwise."

**It is doing** naming a **class** and then handing the choice within it to a decision-maker. The
eligibility question is a rule and is computable. The choice is not a rule at all, and there is
nothing in the instrument from which an answer could be derived.

**Write** a function that returns the eligible **set**, and stop there.

```l4
-- The module says WHO is in the class. It does not say who gets the grant:
-- s 18(4)(b) puts that squarely in the court's discretion.
GIVEN candidates IS A LIST OF Applicant
GIVETH A LIST OF Applicant
`those the court may grant to under section 18(4)(a)-(b) among` candidates MEANS
    filter (GIVEN p YIELD (p's `the husband or widow or next of kin`)
                      AND (p's `an applicant for the grant`)) candidates
```

Where the discretion has actually been exercised, that is a **fact**, and a fact is an input: record
the order the court made as a field, and let later rules read it. What you must not do is derive it.

**Not** a winner picked by the encoding:

```l4
GIVEN candidates IS A LIST OF Applicant
GIVETH AN Applicant
`the person to whom the court grants letters of administration among` candidates MEANS
    at (filter (GIVEN p YIELD (p's `the husband or widow or next of kin`)
                          AND (p's `an applicant for the grant`)) candidates) 0
```

Given a widow and a son who both applied, that runs and returns
`Applicant OF "Fatimah", TRUE, TRUE` — the whole record of whoever is first in the list, and for no
other reason. The tie-break is an artefact of the order somebody happened to type the applicants in,
presented as the court's decision.

**Note the neighbouring case that _is_ rankable.** Where the instrument states an order of priority
("a prior right ... in the following order"), that order is a rule and you should encode it — see
entry [6.7](06-parties-and-things.md#e6-7). The difference is whether the text ranks the classes or
merely lists them.

**See** [drafting-patterns.md](../drafting-patterns.md), "Mandatory vs discretionary — `MUST` vs
`MAY`", for the deontic side of the same distinction: a discretionary power left unexercised
residuates to `FULFILLED` rather than a breach, which is what makes it discretionary.

<a id="e8-6"></a>

## 8.6 "for any sufficient reason", "may in a particular case direct otherwise" — compute the default, not the discretion

**If the source says**

> `-- "(3) The court or the registrar may for any sufficient reason increase or decrease the number of the sureties, or dispense with them, or reduce the amount of the bond."`
>
> — `jl4/examples/legal/sg-succession/sg-paa.l4:917-919`. The note at `:925-929`: "'ordinarily' is
> doing the same work in s 29(2) and s 29(5): both state a default that s 29(3) lets the registrar
> move. The encoding computes the default. It does not model s 29(3), because 'for any sufficient
> reason' is a discretion and not a rule; a registrar's actual order overrides the number below."

**It is doing** giving an office-holder an **unstructured power to depart** from a stated default.
The default is a rule with a computable answer. The power to depart names no criteria — "any
sufficient reason" is the drafter saying so explicitly — and so has no content to encode.

**Write** the default, and say in a comment what you did not model and why. The word to watch for is
"ordinarily": it marks the value the discretion moves.

```l4
-- "(2) The security shall ORDINARILY be by bond ... by the grantee and 2 sureties ..."
-- "(5) When the administrator is entitled to the whole of the estate after payment
--  of the debts, sureties in the bond may ORDINARILY be dispensed with."
`the number of sureties a bond ordinarily requires` MEANS 2

-- s 29(3) is NOT MODELLED: "for any sufficient reason" is a discretion, not a
-- rule. The encoding computes the default the discretion moves; a registrar's
-- actual order overrides the number below.
GIVEN a IS AN Administration
GIVETH A NUMBER
`the number of sureties required in` a MEANS
  BRANCH
    IF NOT a's `security for the due administration of the estate is required` THEN 0
    IF a's `the administrator is entitled to the whole of the estate after payment of the debts` THEN 0
    OTHERWISE `the number of sureties a bond ordinarily requires`
```

**Not** a refusal because the discretion is unmodelled. It runs, and it withholds the answer the
section does give:

```
The model refuses to answer:
  section 29(3) lets the registrar vary the number of sureties for any sufficient reason, and this encoding does not model that discretion
```

The instrument states a number that stands until an order moves it; the everyday case has an answer,
and a user asking "how many sureties?" is entitled to "two, unless the registrar orders otherwise".
An unexercised power to depart from a default is not a gap in the model — it is the default doing its
job.

**Not**, either, criteria invented for "sufficient reason". That is 8.1's mistake wearing different
clothes: a threshold nobody enacted, presented as the registrar's judgement.

**See** entry [7.7](07-presumptions-and-defaults.md#e7-7) for the same structure where a whole rule
rather than a number is displaceable, and entry
[11.1](11-when-the-encoding-cannot-answer.md#e11-1) for the genuinely different case of a power that
must be exercised before the provision has any content at all.

<a id="e8-7"></a>

## 8.7 "the Company may, in its reasonable opinion, reject" — the discretion that is also a power

**If the source says** one sentence that is doing three jobs at once:

> "Where the Contractor works more than 160 hours in a month, the Company may, in its reasonable
> opinion, reject any hours above 160."
>
> — drafted, not quoted; no instrument under `jl4/examples/legal/` combines the three in one
> sentence. The nearest corpus witness is the registrar's power at
> `jl4/examples/legal/sg-succession/sg-paa.l4:917-919`, treated at [8.6](#e8-6), which lacks the
> deontic half because nobody is permitted to do anything by it.

**It is doing** three separable things, and the whole difficulty of the entry is that a model reads
the sentence once and writes one of them:

1. an **eligibility test** — "more than 160 hours" — which is a rule with a number in it, and is
   computable;
2. an **exercise of judgement** — "in its reasonable opinion" — which is not computable, and is
   [8.4](#e8-4)'s recorded determination;
3. a **power** — "may reject" — held by a **named actor**, which is
   [5.4](05-duties-powers-consequences.md#e5-4)'s active permission and belongs in a `DEONTIC`.

**Write all three.** They answer different questions and no one of them substitutes for another: the
first tells a user whether the clause bites at all, the second tells an auditor whether the Company
actually acted, and the third is what a projection draws as a decision point in the process.

```l4
-- (a) ELIGIBILITY is a rule, and it is computable: 160 is a number in the text.
GIVEN m IS A `Month of the engagement`
GIVETH A BOOLEAN
DECIDE `clause 4(3) is engaged for` m IF
    m's `hours worked` ABOVE 160

-- (b) THE EXERCISE is a fact, and it is an input. The encoding does not decide
--     what the Company's reasonable opinion was; it records whether the
--     Company acted.
GIVEN m IS A `Month of the engagement`
GIVETH A BOOLEAN
DECIDE `the hours above 160 are rejected in` m IF
        `clause 4(3) is engaged for` m
    AND m's `the Company rejected the hours above 160`

-- (c) THE POWER is a DEONTIC, and it is a MAY: a permission of a named actor.
GIVEN m IS A `Month of the engagement`
GIVETH A DEONTIC Party Act
`clause 4(3) -- the Company may reject the hours above 160, for` m MEANS
    IF   `clause 4(3) is engaged for` m
    THEN PARTY `the Company` MAY `reject the hours above 160` WITHIN 30 HENCE FULFILLED
    ELSE FULFILLED
```

_(Probe `r10-discretion-and-power.l4`, exit 0, no errors, four assertions satisfied.)_ Both traces
answer `FULFILLED` — the one where the Company rejects within the window, and the one where the
window runs out untouched. **That is what makes it a `MAY`**: an unexercised permission residuates
to `FULFILLED`, never to a breach, which is the deontic half of the same distinction
[8.5](#e8-5) draws on the constitutive side.

**Write only the first two** when the sentence names no actor — "hours above 160 are not
reimbursable" states a consequence, not a permission, and a `DEONTIC` there invents a party. The
three questions of entry [5.2](05-duties-powers-consequences.md#e5-2) settle it: who is permitted,
to do what, by when.

**Not** the judgement computed. Writing ``DECIDE `the rejection is reasonable` m IF m's `hours
worked` ABOVE 200`` substitutes the encoder for the Company on the one question the clause
reserved, and it does it in a rule that runs clean.

**Not** the eligibility test folded into the deontic's guard and nowhere else. A user who wants to
know whether clause 4(3) bites on a 170-hour month should get an answer without running a trace, and
an export schema built from the deontic alone cannot ask the question.

**Not** an all-or-nothing reading of "any hours above 160" assumed silently. "Any" may mean all of
them or some of them; the boolean above takes the all-or-nothing reading, which is a simplification
the clause does not compel. Say so in a comment, as [8.4](#e8-4) requires of every determination you
record.

**See** entry [5.4](05-duties-powers-consequences.md#e5-4) for the active permission,
[5.11](05-duties-powers-consequences.md#e5-11) for the trace that exercises it, and [8.6](#e8-6) for
the neighbouring case where the discretion moves a computed default and there is no power to model.
