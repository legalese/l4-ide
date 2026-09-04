# 7. Presumptions and defaults

One area of the phrasebook. The index, the preamble and the other ten areas are in
[source-patterns.md](../source-patterns.md).

<a id="e7-1"></a>

## 7.1 "shall be deemed to be", "shall be treated as"

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

**See** [drafting-patterns.md](../drafting-patterns.md), "Inert never shadows active", for when the
verbatim words stay whole — a deemed fact is one of the three cases it names.

<a id="e7-2"></a>

## 7.2 "unless the contrary is shown", "until the contrary is proved"

**If the source says**

> `-- AMBIGUITY: "unless the contrary is shown". What must be shown to the contrary — the deemed birth facts of limb (a), the deemed parentage of limb (b), or either?`
>
> — `jl4/examples/legal/bna/bna.l4:230-240`, on British Nationality Act 1981 s 1(2). The note ends:
> "Sergot et al. (1986) §'Some Difficulties with the Formalization of Negation' (pp. 378-381)
> wrestle with the same default; their encoding, like this one, makes rebuttal an explicit input."

**It is doing** setting up a **default that holds until somebody displaces it**. Two facts are in
play and they are not the same fact: whether the presumed thing is true, and whether anybody has
shown it is not. The presumption exists precisely because the first is unknowable — a foundling's
parentage is not on file — so the rule must run off the second.

**Write** the presumed conclusion as a decision, and the rebuttal as its own boolean input, negated.

```l4
-- "(2) A new-born infant who ... is found abandoned in the United Kingdom
--  shall, unless the contrary is shown, be deemed for the purposes of
--  subsection (1) ..."
GIVEN person IS A PersonProfile
GIVETH A BOOLEAN
DECIDE `deemed by subsection (2) to satisfy subsection (1)` person IF
        person's `found abandoned as a new-born infant in the United Kingdom`
    AND person's `date found abandoned` AT LEAST `commencement`
    AND NOT person's `the contrary shown, rebutting the subsection (2) presumption`
```

The field's name says what it records: not "the contrary is true", but "the contrary **shown**".
`FALSE` is the ordinary case — nobody has come forward — and it is exactly what makes the
presumption operate.

**Say what the rebuttal reaches.** The Act does not; the encoder must choose, and the corpus records
the choice as an ambiguity with the reading taken and the reading rejected, right above the rule.
Where one flag is extensionally adequate — as it is here, because subsection (1) needs both deemed
limbs, so rebutting either defeats the route — say so rather than leaving a reader to wonder.

**Not** a refusal because the rebuttal is unknown. Making the field a `MAYBE BOOLEAN` and refusing on
`NOTHING` runs, and it destroys the presumption:

```
The model refuses to answer:
  it is not known whether the contrary has been shown
```

That is the ordinary case — the case the presumption was enacted for — coming back unanswered. A
presumption is the law's own instruction about what to do when nothing is known; it never needs a
non-answer.

**When the rebuttal carries a value, it is not a separate flag — it is a `MAYBE` of that value.**
This is the case the entry above does not reach, and it is the commoner one in a contract: "a
notice sent by post is presumed received on the third Business Day after posting, unless the
contrary is shown" leaves you with two things to record, whether the presumption was displaced and
what the real date was. Those are one fact, not two. Record the value as a `MAYBE`, let its presence
_be_ the rebuttal, and join it to the presumed value with `fromMaybe`, exactly as [7.3](#e7-3)
does for a rate:

```l4
DECLARE Notice HAS
    `the day of posting`                  IS A DATE
    `the day of actual receipt, if shown` IS A MAYBE DATE

`the presumed number of days after posting` MEANS 3

GIVEN n IS A Notice
GIVETH A DATE
`the day of receipt of` n MEANS
    fromMaybe (n's `the day of posting` PLUS `the presumed number of days after posting`)
              (n's `the day of actual receipt, if shown`)
```

_(Probe `r9-rebuttal-with-a-value.l4`, exit 0, no errors. Posted 3 May with `NOTHING`, receipt is
6 May; with `JUST (YMD 2027 5 11)`, it is 11 May.)_ A bare `BOOLEAN` is right only where the
rebuttal has nothing attached to it — as in the subsection (2) foundling above, where what is shown
to the contrary is the deemed fact itself and there is no third thing to record.

**Not** a flag beside the value it governs. It is [7.3](#e7-3)'s forbidden shape and it fails
silently rather than loudly, which is why it is worth measuring: the record where the flag says the
presumption stands and the date field says the notice arrived eight days later runs clean and
answers `DATE OF 6, 5, 2027`, discarding the proved date without a diagnostic (probe
`r9b-rebuttal-two-fields.l4`, exit 0, no errors).

**See** entry [7.1](#e7-1) for the deeming the presumption feeds, entry [7.3](#e7-3) for the same
`MAYBE` + `fromMaybe` join where the displacing party is the contracting party rather than the party
rebutting, and [drafting-patterns.md](../drafting-patterns.md), "Negative limb — `NOT atom`", for the
shape of the negated input.

<a id="e7-3"></a>

## 7.3 "in the absence of agreement", "unless otherwise agreed" — a value the parties may displace

**If the source says**

> `-- ... administration expenses and debts still come off the top (s 5: "after payment thereout"). They are borne rateably by the part this Act governs, in the absence of any direction otherwise`
>
> — `jl4/examples/legal/sg-succession/sg-isa.l4:125-128`.

**It is doing** stating a **fallback value**. There is a value the parties (or the will, or the
contract) may set; where they have not, the instrument supplies one. The two are the same quantity,
reached two ways.

**Write** the party-supplied value as a `MAYBE`, the fallback as its own named definition, and
`fromMaybe` to join them. Naming the fallback separately matters: it is a rule of the instrument, it
will be cited, and it may itself be amended.

```l4
-- "Interest is payable on a late payment at the rate agreed between the
--  parties or, in the absence of agreement, at 5% per annum."
DECLARE Agreement HAS
    `the rate the parties agreed, per annum` IS A MAYBE NUMBER

`the statutory rate in the absence of agreement` MEANS 5%

GIVEN a IS AN Agreement
GIVETH A NUMBER
`the rate of interest on a late payment under` a MEANS
    fromMaybe `the statutory rate in the absence of agreement`
              (a's `the rate the parties agreed, per annum`)
```

`#EVAL` on `Agreement OF NOTHING` gives `0.05`; on `Agreement OF (JUST (8%))` it gives `0.08`.
Those inner parentheses are load-bearing — `%` is a **postfix operator**, so `JUST 8%` reads as
`(JUST 8)%` and is rejected with "The argument of '%' is expected to be of type NUMBER but is here
of type MAYBE OF NUMBER".

**Not** `TYPICALLY` for this job. It looks like the same idea and is not — see [7.4](#e7-4).
**Not**, either, a plain `BOOLEAN` "the parties agreed a rate" beside a separate `NUMBER` "the rate
agreed": that admits the record where the boolean is `FALSE` and the number is 8%, and every reader
has to remember which field governs.

**This is the same ruling as [7.2](#e7-2)'s, and the two entries are not in conflict.** 7.2 writes a
rebuttal as a bare `BOOLEAN`; the sentence above forbids a bare `BOOLEAN`. The dividing line is
whether the displacement brings a **value** with it. A rebuttal that brings nothing — "the contrary
has been shown", full stop — is one boolean and nothing more. A displacement that brings a rate, a
date, an amount or an order is one `MAYBE` of that thing, because the presence of the value is
already the flag. Where a source gives you both a rebuttal and a figure, this entry governs.

**See** [drafting-patterns.md](../drafting-patterns.md), "Where `MAYBE` is right — and it usually
is", and entry [3.1](03-quantities-and-calculation.md#e3-1) for the neighbouring case of an amount
"as may be prescribed".

<a id="e7-4"></a>

## 7.4 `TYPICALLY` — what it does today, and what it does not

**If the source says** nothing at all. `TYPICALLY` is not a translation of a drafting phrase; it is
an annotation you add to record the usual value of an input, for the benefit of whoever has to fill
the form.

**It is doing**, today, exactly one thing: **carrying metadata**. It stores a default on a `DECLARE`
field, a rule `GIVEN` parameter or an `ASSUME`, and an exported schema reports that value as the
field's default while still listing the field as required.

**Write** it beside the type, and keep supplying the value:

```l4
DECLARE `Employment terms` HAS
    `days of notice the contract requires` IS A NUMBER TYPICALLY 28
    `the employee is under duress`         IS A BOOLEAN TYPICALLY FALSE

-- TYPICALLY records the usual value; it does not supply it. Every field is
-- still written out at the construction site.
`the standard terms` MEANS `Employment terms` WITH
    `days of notice the contract requires` IS 28
    `the employee is under duress`         IS FALSE
```

**Not** a value you may omit. Leave the annotated field out of the construction and the file is
rejected:

```
In the application of

  `Employment terms` (defined at …)

you forgot to supply the following arguments:

  `days of notice the contract requires` of type NUMBER
```

_Proposed, not landed (2026-09-04): `TYPICALLY` becoming a real default — a value the caller may
omit, honoured once at the entry point, listed as optional in the schema. Until then it is metadata
and the input is required. Do not write a rule that relies on the default being applied._

For a default the rules actually **apply**, write it out as in [7.3](#e7-3): a named definition plus
`fromMaybe`. That works today and reads better in the source, because the fallback gets a name a
provision can cite.

**See** the corpus example `jl4/examples/ok/typically-basic.l4`, which exercises `TYPICALLY` on
record fields, rule `GIVEN` parameters and `ASSUME` declarations, and whose own header line says
"metadata-only default values".

<a id="e7-5"></a>

## 7.5 "no presumption shall arise" — a definition carrier, not a boolean

**If the source says**

> `... "No presumption shall arise that a funding portal has violated the prohibitions under section 3(a)(80) of the Exchange Act or this part by reason of ... engaging in activities ... that do not meet the conditions specified in paragraph (b) of this section."`
>
> — `jl4/examples/legal/regcf/denovo/regcf-denovo.l4:2889`, carried verbatim. The note above it, at
> `:2881-2883`: "Encoded as a definition carrier, because turning 'no presumption shall arise' into a
> boolean would assert something the paragraph is careful not to assert."

**It is doing** **blocking an inference**, not stating one. The paragraph refuses to let a
conclusion be drawn from a fact; it says nothing about whether the conclusion is true. There is no
proposition here for a rule to compute.

**Write** it as inert text hung on a definition that carries the framing, using the asyndetic `...`
operator so the words stay in the module and appear in the projections.

```l4
GIVETH A BOOLEAN
`the framing of the conditional safe harbor in paragraph (a)` MEANS
        "No presumption shall arise that a funding portal has violated the prohibitions under section 3(a)(80) of the Exchange Act or this part by reason of the funding portal or its associated persons engaging in activities in connection with the offer or sale of securities in reliance on section 4(a)(6) of the Securities Act that do not meet the conditions specified in paragraph (b) of this section."
    ... "The antifraud provisions and all other applicable provisions of the federal securities laws continue to apply to the activities described in paragraph (b) of this section."
    ... TRUE
```

**Not** the negation turned inside out into a test. This compiles and asserts the opposite of what
the paragraph permits:

```l4
GIVEN a IS A `portal activity`
GIVETH A BOOLEAN
`the portal has violated the prohibitions` a MEANS
    NOT a's `meets the conditions specified in paragraph (b)`
```

Run against an activity outside the safe-harbour list it prints `assertion satisfied` — a violation
found, on the very facts the paragraph says raise no presumption of one.

**See** [gotchas.md](../gotchas.md), "Asyndetic operators `...` and `..`", and
[drafting-patterns.md](../drafting-patterns.md), "Inert never shadows active", for when the verbatim
words are the whole content.

<a id="e7-6"></a>

## 7.6 "no will shall be revoked by any presumption" — abolishing a doctrine

**If the source says**

> `-- "No will shall be revoked by any presumption of an intention on the ground of an alteration in circumstances."`
>
> — `jl4/examples/legal/sg-succession/sg-wills.l4:489-490`, Wills Act 1838 s 14. The note beside it:
> "Constant FALSE, and it earns its place. s 14 abolishes a doctrine, and the only way to encode an
> abolition is to carry the abolished ground as a disjunct that can never fire."

**It is doing** **closing a route** that the general law would otherwise leave open. It is not a
condition on anything; it is a statement that one of the ways a thing could have happened no longer
works.

**Write** the abolished ground as a named constant `FALSE`, and keep it in the disjunction it would
have joined. The dead disjunct is what makes a closed list visibly closed.

```l4
-- "14. No will shall be revoked by any presumption of an intention on the
--  ground of an alteration in circumstances."
GIVETH A BOOLEAN
`revocation by presumption of an intention on the ground of an alteration in circumstances` MEANS FALSE

-- "15. No will or codicil ... shall be revoked otherwise than -- ..."
GIVEN w IS A Will
GIVETH A BOOLEAN
`the will has been revoked` w MEANS
        w's `revoked by a later will, writing or destruction`
    OR  `revocation by presumption of an intention on the ground of an alteration in circumstances`
```

**Not** silence. Dropping the section because "it does nothing" is the most tempting move here and it
loses the only thing the section says: that divorce, estrangement, the birth of a child and the sale
of the devised house revoke nothing. A reader of the encoding then cannot tell whether the ground was
abolished or merely forgotten.

**Not**, either, a suppliable input. There is nothing for a fact-supplier to answer; the answer is
fixed by the statute.

**See** [drafting-patterns.md](../drafting-patterns.md), "Repealed / omitted provision → a labelled
stub", for the neighbouring case where the whole provision is gone, and entry
[9.1](09-text-that-is-not-a-rule.md#e9-1).

<a id="e7-7"></a>

## 7.7 "may be varied by the will", "subject to any contrary direction" — the default a whole rule sits under

**If the source says**

> `-- "8. The following provisions shall also apply: (a) the order of application may be varied by the will of the deceased; and (b) this Schedule does not affect the liability of land ..."`
>
> — `jl4/examples/legal/sg-succession/sg-paa.l4:1566-1569`, Probate and Administration Act 1934
> Second Schedule item 8. The note: "Item 8 is not a class of assets. It is a rider on the seven that
> precede it ... 8(a) is the provision that lets a well-drafted will move everything above it."

**It is doing** what [7.3](#e7-3) does for one value, but for a **whole rule**: the instrument states
an order, a rate, a scheme — and then says the parties may replace it. Where 7.3's displacement is a
number you can slot in, this one is a different arrangement altogether, and no field holds it.

**Write** the displaceable rule as it stands, carry the rider verbatim at its own number, and say in
a comment that the variation is not modelled. Do not pretend the schedule is unconditional, and do
not try to compute what the will might have said.

```l4
DECLARE `Rule of application` HAS
    `paragraph` IS A NUMBER
    `text`      IS A STRING

GIVETH A `Rule of application`
`Second Schedule item 8` MEANS
    `Rule of application` WITH `paragraph` IS 8
                             , `text`      IS "The following provisions shall also apply: (a) the order of application may be varied by the will of the deceased; and (b) this Schedule does not affect the liability of land to answer the death duty imposed thereon in exoneration of other assets."

GIVETH A LIST OF `Rule of application`
`the Second Schedule` MEANS
    LIST `Second Schedule item 8`
```

The `LIST` above fits on one line. When one does not, its later items must be indented **past the
column where `LIST` starts**; an item at or left of that column is rejected with
`incorrect indentation (got n, should be greater than n)`, where `n` is that column. The comma
continuation of a record `WITH` needs the same room, though it fails differently — pull the comma
back to the left of the expression it continues and the parser reports `unexpected WITH` on the line
above, which points at the wrong line entirely.

**Not** the rider dropped because it is "not a rule". It is the provision that tells a user the
answer below it is a default, and it is the one they most need to see.

**Not** a refusal on the ground that a will might have varied the order. The schedule is the answer
where no variation was made, and that is the case the module is being asked about; a variation is a
fact somebody would have to supply, not a hole in the encoding.

**See** entry [2.2](02-conditions-and-logic.md#e2-2) for "subject to" and "notwithstanding" — neither
is a keyword — and [drafting-patterns.md](../drafting-patterns.md), "Provenance — pin every inert
string".
