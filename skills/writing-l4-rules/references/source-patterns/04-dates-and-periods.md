# 4. Dates and periods

One area of the phrasebook. The index, the preamble and the other ten areas are in
[source-patterns.md](../source-patterns.md).

<a id="e4-1"></a>

## 4.1 "This Act comes into force on …", "applies to a death on or after …"

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

**Not** `NOTHING` either — see
[entry 11.3](11-when-the-encoding-cannot-answer.md#e11-3) for what `NOTHING` is for and what a later
rule does to it, and [entry 11.5](11-when-the-encoding-cannot-answer.md#e11-5) for the different
case of scope the encoding deliberately does not cover.

**One documented exception.** `jl4/examples/legal/regcf/regcf.l4:145-153` does spell its
pre-commencement arm as a refusal, and says out loud why: the taxonomy puts "not in force" in the gate row, no gate
construct exists, there is no figure to return, "so the
commencement arm is a REFUSE and stays one until one does". Cite it as an exception, never as the pattern.

**See** entry 4.2, and [drafting-patterns.md](../drafting-patterns.md), "Leap-safe date windows" for
building the comparison (and the `Date` month-subtraction footgun, which `YMD` does not share).

---

<a id="e4-2"></a>

## 4.2 "Nothing in this Act shall affect …", "continues to apply" — savings and transitional

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

**Not** a refusal on either side of the saving. See entry 4.1: nothing can reach past one.

**See** <https://legalese.com/l4/concepts/legal-modeling/default-reasoning.md>
for `UNLESS` and named defeaters, which is the same move at limb scale.

---

<a id="e4-3"></a>

## 4.3 "within 14 days after the change" — the deadline whose unit only you know

**If the source says**

> `s 28(1) — "Upon the grant of any probate or letters of administration, the grantee shall take an oath in the prescribed form …"`, encoded with `WITHIN 14`
>
> — the shape at [entry 2.1](02-conditions-and-logic.md#e2-1), from
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

**The deadline is inclusive at both edges, and this is the question the source text most often
leaves you to settle.** `WITHIN 30` means the act is timely if it happens at 30, and the clock
advanced to exactly 30 has not expired — the trace prints the obligation back with `WITHIN 0`
remaining. It is 31 that breaches. Measured on six traces of a two-rung payment duty (probe
`r6-trace-block.l4`, exit 0, no errors); `jl4/examples/ok/deontic-breach-semantics.l4:157-167`
makes the same three cases its own regression test. So a source that says "within 30 days after
receiving it" maps onto `WITHIN 30` **without an adjustment** on the reading that day 30 is in
time — but say in the comment that you took that reading, because "within 30 days" is exactly the
phrase parties litigate. See [entry 4.5](#e4-5) for the same question asked of a date comparison
rather than a deadline, and [entry 5.11](05-duties-powers-consequences.md#e5-11) for the event
block that measures it.

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
[regulative.md](../regulative.md) shows under "`WITHIN` — deadlines" —
`` WITHIN 5 days OF `order confirmation` `` — does not parse either: `unexpected OF`, exit 1,
measured on the same binary. **Write the bare number.** A `currency` library ships, but no unit
library does. The discipline is: one unit per file, stated once at the top, and every `WITHIN` and
every `AT` on it.

**See** [regulative.md](../regulative.md), "`WITHIN` — deadlines", and
[entry 3.2](03-quantities-and-calculation.md#e3-2) for the same problem in money.

---

<a id="e4-4"></a>

## 4.4 "not less than 14 days nor more than 60 days after publication" — the window

**If the source says** a period measured from a date, as a fact rather than as a duty. The corpus
encodes one from the New York environmental review rules as two comparisons on the same anchor:

```text
`Hearing Notice`'s `Scheduled date` AT LEAST `Hearing Notice`'s `Publish date` PLUS 14
AND `Hearing Notice`'s `Scheduled date` AT MOST  `Hearing Notice`'s `Publish date` PLUS 60
```

— `jl4/examples/legal/ny-environmental-7.3.l4:64-65`

**It is doing** fixing a window with an anchor, a length and two boundaries. This is the
_constitutive_ half of a period: whether a thing happened in time. The _regulative_ half — a duty
that must be discharged inside the period, with a breach if it is not — is `WITHIN` inside a
`DEONTIC`, and that is entry 4.3. Ask which you are writing before you pick a shape: a duty with a
deadline wants `WITHIN`; a question about whether a date fell inside a window wants comparisons.

**Write** `DATE PLUS <number of days>`, which yields a `DATE`, and compare dates against dates.

```l4
DECLARE `Hearing notice` HAS
    `Publish date`   IS A DATE
    `Scheduled date` IS A DATE

-- "not less than fourteen days nor more than sixty days after publication"
@ref 6 NYCRR 617.9(a)(4)
GIVEN notice IS A `Hearing notice`
GIVETH A BOOLEAN
`the hearing is scheduled in the permitted window` notice MEANS
        notice's `Scheduled date` AT LEAST notice's `Publish date` PLUS 14
    AND notice's `Scheduled date` AT MOST  notice's `Publish date` PLUS 60
```

_(Probe `q10-within-days.l4`, exit 0, no errors; `(YMD 2026 1 20) PLUS 14` evaluates to
`DATE OF 3, 2, 2026`. The printed form is day, month, year whichever constructor built it — `YMD`
is the safer one to \_write_, as entry 4.9 explains, but it is not how a date is _printed_.)\_

`Day d PLUS 14` is the same arithmetic on the day count rather than the date, and `Date (Day d PLUS
14)` converts it back; use whichever keeps the rule readable, but do not mix the two in one
comparison.

**Not** a day count compared against a date. The two are different types, and because the
comparison operators are overloaded across several types the message is about overload resolution,
not about dates:

```l4
GIVEN `the day of the grant` IS A DATE
      `the day of filing`    IS A DATE
GIVETH A BOOLEAN
`filed in time (wrong)` `the day of the grant` `and` `the day of filing` MEANS
    Day `the day of filing` AT MOST (Date (Day `the day of the grant` PLUS 14))
```

```text
There are multiple definitions for the identifier

  `__LEQ__`

and I do not have sufficient information to make a choice between them.
The options are:

  `__LEQ__` (predefined) of type FUNCTION FROM NUMBER AND NUMBER TO BOOLEAN
  `__LEQ__` (predefined) of type FUNCTION FROM STRING AND STRING TO BOOLEAN
  `__LEQ__` (predefined) of type FUNCTION FROM BOOLEAN AND BOOLEAN TO BOOLEAN
  `__LEQ__` (defined at prelude.l4:785:1-10) of type FUNCTION FROM MAYBE OF NUMBER AND MAYBE OF NUMBER TO BOOLEAN
  `__LEQ__` (defined at daydate.l4:704:1-10) of type FUNCTION FROM DATE AND DATE TO BOOLEAN
```

_(Probe `q10b-date-number.l4`, exit 1.)_

**See** entry 4.3 for the deadline inside a duty, entry 4.5 for whether the boundary days are in or
out, and entry 4.10 when the period is counted in business days.

---

<a id="e4-5"></a>

## 4.5 "on or before", "beginning with the day", "not later than" — the boundary days

**If the source says** a period whose endpoints are spelled out. The corpus's British nationality
encoding stops to reason about one word of it:

```text
-- AMBIGUITY: "after commencement" (ss (1), (2), (3), (4)). Commencement is
-- an instant — the Act commenced at the first moment of 1 January 1983 — so
-- a person born ON 1 January 1983 is born after commencement. Reading (i):
-- birth date >= 1983-01-01 (taken here, and the settled understanding).
```

— `jl4/examples/legal/bna/bna.l4:73-76`

**It is doing** two separate things that both look like arithmetic. First, saying whether the
boundary day is inside the period: "on or before" and "not later than" include it, "before" does
not. Second — and this is the one that gets missed — "**beginning with** the day" makes the anchor
day the **first** day of the period, so a period of N days beginning with day D ends on day
`D + N − 1`, not on `D + N`. "Beginning **from**" or "after" usually means the opposite. British and
Commonwealth drafting uses "beginning with" precisely to settle this, so when you see it, the
drafter is telling you the answer.

**Write** the inclusive comparison operators — `AT LEAST` is "on or after", `AT MOST` is "on or
before" — and write an inclusive span as the difference plus one.

```l4
-- Dates compare directly: AT LEAST / AT MOST are inclusive, so they are
-- "on or after" and "on or before".
@ref British Nationality Act 1981 s 1(1); s 50(1) "commencement"
GIVETH A DATE
`commencement` MEANS YMD 1983 1 1

GIVEN `the date of birth` IS A DATE
GIVETH A BOOLEAN
`born after commencement, born on` `the date of birth` MEANS
    `the date of birth` AT LEAST `commencement`

-- "a period of 12 months BEGINNING WITH the day of the grant" counts that day,
-- so the span is inclusive at both ends and the last day is start + 365 - 1.
GIVEN `the first day` IS A DATE
      `the last day`  IS A DATE
GIVETH A NUMBER
`the number of days in the period beginning with` `the first day` `and ending with` `the last day` MEANS
    (Day `the last day` MINUS Day `the first day`) PLUS 1

#ASSERT `born after commencement, born on` (YMD 1983 1 1)
#ASSERT NOT `born after commencement, born on` (YMD 1982 12 31)
#ASSERT `the number of days in the period beginning with` (YMD 2026 1 1) `and ending with` (YMD 2026 1 7) EQUALS 7
```

_(Probe `q11-boundaries.l4`, exit 0, no errors.)_

**And record the reading you took.** Where the words are genuinely open, the corpus writes the
ambiguity out, names both readings, says which it took and why, and only then encodes it. That note
is what lets a reviewer disagree with you cheaply.

**Not** the bare difference for a period "beginning with" a day. It is short by one, on every case,
in the direction that favours whoever is running the clock:

```l4
GIVEN `the first day` IS A DATE
      `the last day`  IS A DATE
GIVETH A NUMBER
`the number of days (wrong)` `the first day` `and` `the last day` MEANS
    Day `the last day` MINUS Day `the first day`

#ASSERT `the number of days (wrong)` (YMD 2026 1 1) `and` (YMD 2026 1 7) EQUALS 7
```

```text
assertion failed
```

_(Probe `q11b-offbyone.l4`, exit 0, one error.)_

**See** entry 3.3 for the same inclusive-or-exclusive question on numbers, and
[drafting-patterns.md](../drafting-patterns.md), "Leap-safe date windows", for building the far
endpoint of a window measured in years.

---

<a id="e4-6"></a>

## 4.6 "at the time of", "as at the date of" — a status frozen at an instant

**If the source says** a status asked as at a past moment:

```text
`father or mother a British citizen at the time of the birth`                                          IS A BOOLEAN
`father or mother settled in the United Kingdom or the territory of birth at the time of the birth`    IS A BOOLEAN
```

— `jl4/examples/legal/bna/bna.l4:132-133`

**It is doing** freezing a fact. Nationality, residence, marital status, solvency, share ownership,
capacity — all of these change, and the rule asks about the value one of them had at an instant that
has already passed. Note the corpus's spelling: the phrase "at the time of the birth" is **in the
field name**. That is deliberate. A field called `father or mother a British citizen` would be
answered by whoever fills the form with today's status, and nothing downstream could tell.

**Write** the frozen status as a recorded field whose name carries the instant, and let the rule
read it.

```l4
-- "his father or mother is a British citizen AT THE TIME OF THE BIRTH".
-- The status is asked as at a past instant, so it is a recorded fact about the
-- case, not a status recomputed now.
@ref British Nationality Act 1981 s 1(1)(a)
DECLARE PersonProfile HAS
    `date of birth`                                       IS A DATE
    `born in the United Kingdom`                          IS A BOOLEAN
    `father or mother a British citizen at the time of the birth` IS A BOOLEAN

@ref British Nationality Act 1981 s 1(1)
GIVEN person IS A PersonProfile
GIVETH A BOOLEAN
`section 1(1) is satisfied for` person MEANS
        person's `born in the United Kingdom`
    AND person's `date of birth` AT LEAST `commencement`
    AND person's `father or mother a British citizen at the time of the birth`
```

_(Probe `q12-at-the-time-of.l4`, exit 0, no errors.)_

**"At the time of" is a different axis from "in force at the time".** This entry is about a fact
about the world at a past instant. Which _version of the law_ applied at that instant is entry 4.7,
and the two are pinned separately.

**Not** `TODAY`. Besides being the wrong question, it fails loudly only if the file happens to
declare a timezone, and quietly gives a present-tense answer if the drafter reaches for a different
present-tense source:

```l4
GIVEN person IS A PersonProfile
GIVETH A BOOLEAN
`the parent was a citizen at the birth (wrong)` person MEANS
        person's `father or mother a British citizen`
    AND person's `date of birth` AT MOST TODAY
```

```text
assertion could not be evaluated:
TIMEZONE is not declared. TODAY requires 'TIMEZONE IS "<IANA timezone>"' in your document.
```

_(Probe `q12b-today.l4`, exit 1. `TODAY` needs a document-level `TIMEZONE IS` declaration naming a
zone from the Internet Assigned Numbers Authority database; see
[builtins.md](../builtins.md), "Temporal globals". For a reproducible run, pin the clock from the
command line with `l4 run --fixed-now=…` rather than letting a rule read the wall clock at all.)_

**See** entry 4.7 for the law-version axis, and entry 4.9 when the instant has to be computed rather
than recorded.

---

<a id="e4-7"></a>

## 4.7 "the law in force at the time", "as at 1 June 2023" — the rule-version axis

**If the source says** that the answer depends on which version of the instrument governs. The
corpus reads that off a built-in rather than off a parameter:

```text
GIVEN amendment IS A DATE
GIVETH A BOOLEAN
`the rules in force include` amendment MEANS
    `RULES EFFECTIVE DATE` AT LEAST amendment
```

— `jl4/examples/legal/regcf/regcf.l4:130-133`

**It is doing** naming the third clock. There are three, they move independently, and confusing them
produces answers that are confidently wrong rather than obviously wrong:

| the question                          | the reader             | how to pin it                   |
| ------------------------------------- | ---------------------- | ------------------------------- |
| when is this evaluation running?      | `TODAY` / `NOW`        | `EVAL AS OF SYSTEM TIME`        |
| when did the facts hold in the world? | the valid-time axis    | `EVAL UNDER VALID TIME`         |
| which version of the law applies?     | `RULES EFFECTIVE DATE` | `EVAL UNDER RULES EFFECTIVE AT` |

An auditor looking in 2026 at a 2019 transaction needs all three: running now, facts from 2019, law
from 2019.

**Write** the dated figure or the dated shape against `RULES EFFECTIVE DATE`, and test it by pinning
the axis at a directive.

```l4
-- "the rate in force at the time of the supply"
@ref Goods and Services Tax Act, rate change of 1 January 2024
GIVETH A NUMBER
`the rate of tax` MEANS
    IF   `RULES EFFECTIVE DATE` AT LEAST (YMD 2024 1 1)
    THEN 9%
    ELSE 7%

GIVEN value IS A NUMBER
GIVETH A NUMBER
`the tax payable on` value MEANS value TIMES `the rate of tax`

#ASSERT `EVAL UNDER RULES EFFECTIVE AT` (YMD 2023 6 1) (`the tax payable on` 1000) EQUALS 70
#ASSERT `EVAL UNDER RULES EFFECTIVE AT` (YMD 2024 7 1) (`the tax payable on` 1000) EQUALS 90
#ASSERT `EVAL UNDER VALID TIME` (YMD 2019 6 1) `the rate of tax` EQUALS 7%
```

_(Probe `q13-as-at.l4`, exit 0, no errors.)_ The third assertion is the default worth knowing: with
no rule-version pinned but the facts pinned to 2019, `RULES EFFECTIVE DATE` falls back to the
valid-time axis, so the old law applies. That is the presumption against retroactivity, built into
the fallback rather than written by you.

**Not** the current figure written as the figure. It answers every historical question with today's
law, and it does so without complaint:

```l4
GIVETH A NUMBER
`the rate of tax (wrong)` MEANS 9%

GIVEN value IS A NUMBER
GIVETH A NUMBER
`the tax payable on (wrong)` value MEANS value TIMES `the rate of tax (wrong)`

#EVAL `EVAL UNDER RULES EFFECTIVE AT` (YMD 2023 6 1) (`the tax payable on (wrong)` 1000)
```

```text
90
```

_(Probe `q13b-current-rate.l4`, exit 0, one error: 90 for a 2023 rule date, where the answer is 70.
Pinning the axis has no effect, because nothing reads it.)_

**See** [the multi-temporal modeling tutorial](../../../../doc/tutorials/multi-temporal-modeling/multi-temporal-rule-modeling.md),
which builds the three axes up one at a time, and entry 4.8 for what happens when only part of a
module is dated.

---

<a id="e4-8"></a>

## 4.8 "as amended by", "substituted by" — an amendment that changes the shape

**If the source says** an amendment. Some amendments move a number (entry 3.1); some change what the
rule does. The corpus records one of the second kind at length:

```text
-- SHAPE CHANGE, 2021-03-15 (Release 33-10884, 86 FR 3496). Before that date both
-- limbs read "the LESSER of the investor's annual income or net worth". The
-- amendment substituted "greater" for "lesser" in each limb, which raises the
-- limit for every investor whose income and net worth differ. This is a change
-- in the shape of the rule, not merely in a number, and it is the single most
-- consequential edit in Reg CF's history for an individual investor.
```

— `jl4/examples/legal/regcf/regcf.l4:397-402`

**It is doing** replacing one rule with another as of a date, while leaving both in force for their
own periods. The encoding does not choose between them; it holds both and selects on the rule-version
axis.

**Write** one arm per regime, newest first, selected by `the rules in force include`, with the
citation on each arm and the pre-commencement case last.

```l4
-- The 2021 amendment substituted "greater" for "lesser" in each limb: a change
-- in the SHAPE of the rule, not in a number. One arm per regime, newest first.
@ref 17 CFR 227.100(a)(2)(i)-(ii) — "greater of" since 2021-03-15; "lesser of" before
GIVEN investor IS AN InvestorProfile
GIVETH A NUMBER
`the applicable measure of annual income or net worth` investor MEANS
    BRANCH IF `the rules in force include` `the 2021 amendments` THEN max (investor's `annual income`) (investor's `net worth`)
           IF `the rules in force include` `Reg CF commenced`    THEN min (investor's `annual income`) (investor's `net worth`)
           OTHERWISE `no Regulation Crowdfunding figure exists before commencement on 2016-05-16`

#ASSERT `EVAL UNDER RULES EFFECTIVE AT` (YMD 2022 1 1) (`the applicable measure of annual income or net worth` `the investor`) EQUALS 120000
#ASSERT `EVAL UNDER RULES EFFECTIVE AT` (YMD 2018 1 1) (`the applicable measure of annual income or net worth` `the investor`) EQUALS 90000
#ASSERT REFUSED `EVAL UNDER RULES EFFECTIVE AT` (YMD 2015 1 1) (`the applicable measure of annual income or net worth` `the investor`)
```

_(Probe `q14-amendment-shape.l4`, exit 0, no errors; three assertions, one per regime, the last one
before commencement. The `OTHERWISE` arm is the documented exception discussed at entry 4.1: the
taxonomy puts "not in force" in the gate row, no gate construct exists, and this corpus spells it as
a refusal until one does.)_

**Date every constant in the read set, not just the interesting one.** This is the trap, and it has
a name in the corpus: temporal closure. If one figure a rule reads is dated and another is not, the
module answers inside the window with total confidence and the wrong figure.

**Not** a partly dated module:

```l4
-- ANTI-PATTERN: the dollar cut point is dated, the greater/lesser CHOICE is not.
-- The module answers for 2018 with full confidence, using the 2021 shape.
GIVETH A NUMBER
`the cut point` MEANS
    IF   `the rules in force include` (YMD 2021 3 15)
    THEN 124000
    ELSE 107000

GIVEN investor IS AN InvestorProfile
GIVETH A NUMBER
`the applicable measure (wrong)` investor MEANS
    max (investor's `annual income`) (investor's `net worth`)

#EVAL `EVAL UNDER RULES EFFECTIVE AT` (YMD 2018 1 1) (`the applicable measure (wrong)` `the investor`)
```

```text
120000
```

_(Probe `q14b-partial-dating.l4`, exit 0, one error: 120000 for a 2018 rule date, where the rule as
it then stood gives 90000. Nothing in the output suggests the answer is out of period.)_

**See** entry 3.1 for an amendment that moves a figure, entry 4.7 for the axis both select on, and
entry 4.1 for what to write at the far end of the earliest regime.

---

<a id="e4-9"></a>

## 4.9 "within 6 calendar months", "the first anniversary" — periods of months and years

**If the source says** a period in months or years rather than days. The corpus's award computes
several:

```text
`Third Anniversary` MEANS `years after` 3 `Grant Date`
```

— `jl4/examples/legal/ceo-performance-award.l4:15`

**It is doing** asking the calendar a question the calendar cannot always answer. There is no
31 February, so "six months after 31 August" and "the first anniversary of 29 February" have to be
resolved by a convention, and the two available conventions differ by one day on exactly the dates
somebody litigates.

**Write** `add months` and `add years` from `daydate`. They **clamp** to the last day of the target
month, which is what a spreadsheet's date-add does and what two independent decision-engine
implementations of the same operation were measured to do, so a module written this way exports and
comes back with the same answer.

```l4
-- "within 6 calendar months after the death"
GIVEN `the date of death` IS A DATE
GIVETH A DATE
`the last day of the six month period after` `the date of death` MEANS
    `add months` `the date of death` 6

-- "the first anniversary of the grant"
GIVEN `the date of the grant` IS A DATE
GIVETH A DATE
`the first anniversary of` `the date of the grant` MEANS
    `add years` `the date of the grant` 1

-- `add months` CLAMPS to the last day of the target month.
#ASSERT `the last day of the six month period after` (YMD 2025 8 31) EQUALS YMD 2026 2 28
#ASSERT `the first anniversary of` (YMD 2024 2 29) EQUALS YMD 2025 2 28
```

_(Probe `q15-months.l4`, exit 0, no errors.)_

**Not** the anniversary rebuilt from components with `Date`. `Date day month year` is the **lenient**
constructor and it **rolls forward**, so it turns the day that does not exist into the first day of
the next month:

```l4
GIVEN d IS A DATE
GIVETH A DATE
`the first anniversary of (wrong)` d MEANS
    Date (DATE_DAY d) (DATE_MONTH d) (DATE_YEAR d PLUS 1)

#EVAL `the first anniversary of (wrong)` (YMD 2024 2 29)
```

```text
DATE OF 1, 3, 2025
```

_(Probe `q15b-date-rolls.l4`, exit 0, one error: 1 March where the clamping answer is 28 February.
Rolling is right when you \_want_ rolling month arithmetic and wrong for an anniversary.)\_

**Not** "N months before X" computed by subtracting from the month component. `Date` does not roll a
month of zero or less back into the previous year — it clamps it to January of the **same** year —
and `YMD`, the bounds-checked constructor, refuses it outright:

```l4
#EVAL Date 1 (3 MINUS 6) 2025
#EVAL YMD 2025 (3 MINUS 6) 1
```

```text
DATE OF 1, 1, 2025
`YMD refused an out-of-range month or day`
```

_(Probe `q15c-months-back.l4`, exit 0. January 2025, not September 2024.)_ Go backwards by adding to
the **earlier** date and comparing, or by decrementing the year, which can never produce a month of
zero.

**See** [gotchas.md](../gotchas.md), "The `daydate` month-subtraction footgun", and
[drafting-patterns.md](../drafting-patterns.md), "Leap-safe date windows", both of which treat the
`Date` constructor at length. Prefer `YMD year month day` for literals: its big-endian order is much
harder to transpose than `Date day month year`, and it fails loudly on a date that does not exist.

---

<a id="e4-10"></a>

## 4.10 "within five business days", "a calendar month" — the unit with a calendar behind it

**If the source says** a period counted in business days:

```text
@ref § 227.203(b)(3) — "within five business days from the date on which the issuer becomes eligible"
```

— `jl4/examples/legal/regcf/denovo/regcf-denovo.l4:2034`; the corpus binds the number once, as
`` `business days to file Form C-TR` MEANS 5 `` (`jl4/examples/legal/regcf/regcf.l4:249`)

**It is doing** counting against a calendar that the instrument does not print. "Business day"
almost always means "not a Saturday, not a Sunday, and not a public holiday **in a named place**",
and the named place is somewhere else in the instrument — a definitions section, a governing-law
clause, or an assumption nobody wrote down.

**Write** it with the weekend test `daydate` gives you and a holiday list you supply and date
yourself. There is no holiday calendar in the library, and no import will produce one.

```l4
-- "within five business days". `daydate` knows Saturdays and Sundays; it knows
-- no public holidays, so the holiday calendar is data you supply and date.
@ref 17 CFR 227.203(b)(3) — "within five business days from the date on which the issuer becomes eligible"
`the public holidays for 2026` MEANS
    LIST (YMD 2026 1 1), (YMD 2026 4 3), (YMD 2026 12 25)

GIVEN d IS A DATE
GIVETH A BOOLEAN
`is a business day` d MEANS
        `is weekday` d
    AND NOT (elem d `the public holidays for 2026`)

GIVEN n IS A NUMBER
      d IS A DATE
GIVETH A DATE
`the day` n `business days after` d MEANS
    IF   n AT MOST 0
    THEN d
    ELSE IF   `is a business day` next
         THEN `the day` (n MINUS 1) `business days after` next
         ELSE `the day` n           `business days after` next
    WHERE
        next MEANS Date (Day d PLUS 1)

-- Thursday 2026-12-24; Friday the 25th is a holiday, the 26th and 27th a weekend.
#EVAL `the day` 3 `business days after` (YMD 2026 12 24)
#ASSERT NOT `is a business day` (YMD 2026 12 25)
#ASSERT     `is a business day` (YMD 2026 12 24)
```

```text
DATE OF 30, 12, 2026
```

_(Probe `q16-business-day.l4`, exit 0, no errors. `is weekday` and `is weekend` come from
`daydate`; the parameters of a mixfix definition must appear in the order of its `GIVEN`, which is
why `n` is declared before `d`.)_

**Say which jurisdiction's holidays the list is, and which years it covers.** A holiday list is a
dated fact like any other, and a list that runs out is a rule that starts answering as though every
day were a working day.

**"Calendar month" is the same problem** with a different answer: it means the month as the calendar
draws it, so a period of calendar months is `add months` (entry 4.9), not thirty-day blocks, and
certainly not `daydate`'s `Days in a month` — that constant is the average month length, 30.436875,
useful for projecting a schedule and wrong for a legal period.

**Not** business days counted as calendar days. The deadline lands early, and on the sort of day
nobody can file:

```l4
GIVEN d IS A DATE
GIVETH A DATE
`the day three business days after (wrong)` d MEANS Date (Day d PLUS 3)

#EVAL `the day three business days after (wrong)` (YMD 2026 12 24)
```

```text
DATE OF 27, 12, 2026
```

_(Probe `q16b-calendar-days.l4`, exit 0, one error: 27 December, a Sunday, where the answer is
30 December.)_

**See** entry 4.3 for why a `WITHIN` inside a duty cannot record its own unit at all, and entry 4.9
for months and years.

---

<a id="e4-11"></a>

## 4.11 "a grace period of ten days" — the second deadline

**If the source says** a period after a due date in which a consequence is held off:

```text
`Late Payment Penalty` MEANS Penalty WITH
                                `Interest Rate`     IS 5%
                                `Grace Period Days` IS 10
```

— `jl4/examples/legal/promissory-note.l4:23-25`

**It is doing** separating **breach** from **remedy**. A payment made inside the grace period is
still late — the obligation was to pay on the due date — but the penalty does not attach. Reading
the grace period as an extension of the due date collapses that distinction, and with it every
question that depends on it: whether the counterparty may serve a default notice, whether a
cross-default is triggered, whether interest runs.

**Write** two dates and two rules: lateness measured from the due date, and the consequence measured
from the end of the grace period.

```l4
-- A grace period is a SECOND, later date, not a softening of the first. The
-- instalment is still due on the due date; what the grace period postpones is
-- the consequence.
GIVEN `the due date` IS A DATE
GIVETH A DATE
`the last day before the penalty attaches, for a payment due on` `the due date` MEANS
    Date (Day `the due date` PLUS `Late Payment Penalty`'s `Grace Period Days`)

GIVEN `the due date` IS A DATE
      `the day of payment` IS A DATE
GIVETH A BOOLEAN
`the payment is late, due on` `the due date` `and paid on` `the day of payment` MEANS
    Day `the day of payment` GREATER THAN Day `the due date`

GIVEN `the due date` IS A DATE
      `the day of payment` IS A DATE
GIVETH A BOOLEAN
`the penalty is payable, due on` `the due date` `and paid on` `the day of payment` MEANS
    Day `the day of payment`
        GREATER THAN Day (`the last day before the penalty attaches, for a payment due on` `the due date`)

#ASSERT     `the payment is late, due on`   (YMD 2026 3 1) `and paid on` (YMD 2026 3 5)
#ASSERT NOT `the penalty is payable, due on` (YMD 2026 3 1) `and paid on` (YMD 2026 3 5)
#ASSERT     `the penalty is payable, due on` (YMD 2026 3 1) `and paid on` (YMD 2026 3 12)
```

_(Probe `q17-grace.l4`, exit 0, no errors. The middle assertion is the point of the entry: late, and
no penalty.)_

The corpus's own note beside this arithmetic is worth reading as a warning rather than as a model —
`-- It's curious that the ACTUAL due date is the due date + grace period.`
(`jl4/examples/legal/promissory-note.l4:136`). The curiosity is the collapse this entry is about.

**Not** the grace period folded into the due date:

```l4
GIVEN `the due date` IS A DATE
GIVETH A DATE
`the due date (wrong)` `the due date` MEANS
    Date (Day `the due date` PLUS `Grace Period Days`)

GIVEN `the due date` IS A DATE
      `the day of payment` IS A DATE
GIVETH A BOOLEAN
`the payment is late (wrong), due on` `the due date` `and paid on` `the day of payment` MEANS
    Day `the day of payment` GREATER THAN Day (`the due date (wrong)` `the due date`)

#ASSERT `the payment is late (wrong), due on` (YMD 2026 3 1) `and paid on` (YMD 2026 3 5)
```

```text
assertion failed
```

_(Probe `q17b-grace-folded.l4`, exit 0, one error: a payment four days after the due date is not
late at all.)_

**See** [regulative.md](../regulative.md), "`WITHIN` — deadlines", for the duty whose deadline this
is, and entry 4.3 for what `WITHIN` does and does not record.

---

<a id="e4-12"></a>

## 4.12 The `daydate` names this area uses, and how to find the rest

**If the source says** nothing — this entry, like [3.12](03-quantities-and-calculation.md#e3-12), is
not a drafting phrase. Every other entry in this area applies `Day`, `Date`, `YMD`, `add months`,
`is weekday` and the `DATE_*` accessors without ever stating their types, and no reference file in
this skill introduces them. This is that statement.

**It is doing** saving you from inferring a signature out of a call site. `daydate` overloads its
names heavily — `Date` has five definitions and `Day` three — so the arity you saw in one entry is
not the whole story, and applying the wrong one is a type error whose message is about overload
resolution rather than about dates.

**Write** `IMPORT daydate`, and use these:

| name                                  | signature                       | note                                                         |
| ------------------------------------- | ------------------------------- | ------------------------------------------------------------ |
| `YMD year month day`                  | `NUMBER NUMBER NUMBER → DATE`   | big-endian and bounds-checked; the one to write literals in  |
| `Date day month year`                 | `NUMBER NUMBER NUMBER → DATE`   | little-endian and **lenient** — it rolls, see [4.9](#e4-9)   |
| `Date days`                           | `NUMBER → DATE`                 | a day count back to a date                                   |
| `Day date`                            | `DATE → NUMBER`                 | a date to its day count                                      |
| `Day day month year`                  | `NUMBER NUMBER NUMBER → NUMBER` | straight to a day count                                      |
| `` `add months` date n ``             | `DATE NUMBER → DATE`            | date first, then the count; **clamps**, see [4.9](#e4-9)     |
| `` `add years` date n ``              | `DATE NUMBER → DATE`            | same shape, same clamping                                    |
| `` `is weekday` date ``               | `DATE → BOOLEAN`                | also defined on a `NUMBER` day count                         |
| `` `is weekend` date ``               | `DATE → BOOLEAN`                | knows Saturdays and Sundays and no holidays — [4.10](#e4-10) |
| `` `Days in month` m y ``             | `NUMBER NUMBER → NUMBER`        | also on a `DATE` and on a day count                          |
| `` `Days in a year` ``                | `NUMBER`, `365.2425`            | the **average** year; not the length of any actual year      |
| `` `Days in a month` ``               | `NUMBER`, `30.436875`           | the **average** month; wrong for a legal period              |
| `DATE_YEAR`, `DATE_MONTH`, `DATE_DAY` | `DATE → NUMBER`                 | built in, not from `daydate`                                 |

Three facts the table cannot show, all measured (probe `r4-daydate-signatures.l4`, exit 0, no
errors, ten assertions satisfied):

- `DATE PLUS NUMBER` yields a `DATE` — the number is a count of days.
- `DATE`s compare directly with `AT LEAST`, `AT MOST`, `EQUALS`; `daydate` supplies those overloads.
  Do **not** compare a `DATE` with a day count — [4.4](#e4-4) shows what that error looks like.
- A `DATE` prints as `DATE OF day, month, year` whichever constructor built it, so a `YMD`-built
  date comes back little-endian. That `OF` is the printer's and is not source.

**Write a `#CHECK` when you want the rest.** `#CHECK` on a name that has one definition prints its
type at Information severity and costs the run nothing. On an **overloaded** name it is an error —
and the error is the documentation, because it lists every definition with its file and line (probe
`r4b-check-overloaded.l4`, exit 1):

```
There are multiple definitions for the identifier

  `is weekday`

and I do not have sufficient information to make a choice between them.
The options are:

  `is weekday` (defined at daydate.l4:550:1-13) of type FUNCTION FROM DATE TO BOOLEAN
  `is weekday` (defined at daydate.l4:545:1-13) of type FUNCTION FROM NUMBER TO BOOLEAN
```

Provoke it deliberately, read the list, then delete the `#CHECK` — it is a one-line way to answer
"what can I apply this to" without leaving the file.

**Not** a guess from one call site. `add months` reads `date` then `count`, and `Date` reads
`day month year` while `YMD` reads `year month day`; both pairs are the wrong way round from each
other, and both type-check when transposed because every argument is a `NUMBER`. `Date 2027 4 1`
raises no diagnostic at all: it rolls 2027 days into month 4 of year 1 and answers
`DATE OF 18, 10, 6` — 18 October of the year 6, where `YMD 2027 4 1` answers `DATE OF 1, 4, 2027`
(probe `r4c-transposed-date.l4`, exit 0, no errors). Prefer `YMD` for every literal.

**See** [4.9](#e4-9) for the clamping and rolling difference the table only names,
[4.10](#e4-10) for the holiday calendar no library ships, and [gotchas.md](../gotchas.md),
"The `daydate` month-subtraction footgun".
