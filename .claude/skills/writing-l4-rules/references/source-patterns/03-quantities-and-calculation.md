# 3. Quantities and calculation

One area of the phrasebook. The index, the preamble and the other ten areas are in
[source-patterns.md](../source-patterns.md).

<a id="e3-1"></a>

## 3.1 "such other amount as may be prescribed" — the power, exercised

**If the source says** an amount an instrument moves over time. Regulation Crowdfunding's dollar
limits are indexed for inflation by releases of the Securities and Exchange Commission, published in
the Federal Register:

```text
-- $1,000,000 as adopted (80 FR 71537); $1,070,000 from 2017-04-12
-- (82 FR 17545 instr. 5.a); $5,000,000 from 2021-03-15 (86 FR 3496 instr. 3).
```

— `jl4/examples/legal/regcf/regcf.l4:145-146`, with the rule at `:158-164`.

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

**See** [entry 11.1](11-when-the-encoding-cannot-answer.md#e11-1) for the arm this one falls
through to — the corpus writes it as a named refusal at `regcf.l4:151-153` — and
[drafting-patterns.md](../drafting-patterns.md), `Statutory tables as DATA`, when the instrument gives a
table rather than a number.

---

<a id="e3-2"></a>

## 3.2 "2% of the value", "a fee of $50" — a rate and an amount

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
as [entry 4.3](04-dates-and-periods.md#e4-3) applies: one currency per file, stated once.

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

**See** entry 3.1 for a rate that an instrument moves over time, and
[entry 11.1](11-when-the-encoding-cannot-answer.md#e11-1) for a rate the section supplies as its
own default.

---

<a id="e3-3"></a>

## 3.3 "not less than", "exceeds", "at least", "not more than" — the boundary

**If the source says**

```text
-- The (i)/(ii) selector. Limb (i) applies "if EITHER the investor's annual
-- income or net worth is less than $124,000"; limb (ii) applies "if BOTH ...
-- are equal to or more than $124,000". The two are exhaustive and mutually
-- exclusive, so one boolean selects between them.
```

— `jl4/examples/legal/regcf/regcf.l4:412-415`

(The citations in this area are to the Code of Federal Regulations (CFR) and the Federal Register
(FR), which are where the rules and the releases amending them are published.)

**It is doing** drawing a line and saying which side of it the line itself falls on. "Less than"
puts the boundary outside; "equal to or more than" puts it inside. Statutes and contracts spend
whole subsections on that difference because a case sitting exactly on the number is far commoner
than chance suggests — it is the number somebody was aiming at.

**Write** the operator whose inclusiveness matches the phrase, and keep it next to the source words.

| the source says                                                         | write            | is the boundary in? |
| ----------------------------------------------------------------------- | ---------------- | ------------------- |
| "not less than N", "at least N", "N or more", "equal to or more than N" | `AT LEAST N`     | yes                 |
| "not more than N", "at most N", "N or less", "does not exceed N"        | `AT MOST N`      | yes                 |
| "exceeds N", "more than N", "above N", "in excess of N"                 | `GREATER THAN N` | no                  |
| "less than N", "below N", "under N"                                     | `LESS THAN N`    | no                  |

```l4
-- "not less than 21" / "at least 21"  -> AT LEAST   (inclusive)
-- "exceeds 21" / "more than 21"       -> GREATER THAN (exclusive)
-- "not more than 21" / "at most 21"   -> AT MOST    (inclusive)
GIVEN n IS A NUMBER
GIVETH A BOOLEAN
DECIDE `the amount is not less than 21` n IF n AT LEAST 21

GIVEN n IS A NUMBER
GIVETH A BOOLEAN
DECIDE `the amount exceeds 21` n IF n GREATER THAN 21

#ASSERT     `the amount is not less than 21` 21
#ASSERT NOT `the amount exceeds 21` 21
```

_(Probe `q01-comparisons.l4`, exit 0, no errors.)_

**Then test the boundary itself, not a comfortable case either side of it.** The corpus does: one
case a dollar below the cut point and one exactly on it, asserted separately —

```text
#ASSERT     `either annual income or net worth is less than the cut point` (`an investor with` FALSE 123999 124000 0)
#ASSERT NOT `either annual income or net worth is less than the cut point` (`an investor with` FALSE 124000 124000 0)
```

— `jl4/examples/legal/regcf/regcf.l4:1039-1040`.

**Not** `GREATER THAN` for "not less than". It is off by exactly the case the drafter cared about,
and nothing type-checks it for you:

```l4
GIVEN n IS A NUMBER
GIVETH A BOOLEAN
DECIDE `the amount is not less than 21 (wrong)` n IF n GREATER THAN 21

#ASSERT `the amount is not less than 21 (wrong)` 21
```

```text
assertion failed
```

_(Probe `q02-boundary-wrong.l4`; the file still exits 0 — a failing assertion is reported at
`DiagnosticSeverity_Error` but does not change the exit code, so read the diagnostics.)_

**See** entry 4.5 for the same distinction on dates, where "on or before" and "beginning with the
day" hide an extra off-by-one, and [drafting-patterns.md](../drafting-patterns.md), "Constitutive
limbs", for building the limb the comparison sits in.

---

<a id="e3-4"></a>

## 3.4 "the lesser of", "the greater of", "whichever is the higher"

**If the source says** a quantity defined as a choice between two others. The corpus's oldest
encoding writes the pair out by hand, with a note that a library ought to have them:

```text
GIVEN a IS A NUMBER                         -- At some point in the future, there'll probably be a bunch of libraries
      b IS A NUMBER                         -- With all kinds of helper functions like this that can be seen as generally
`The lesser of` MEANS                       -- accepted definitions of phrases or terms
    IF a GREATER THAN b
        THEN b
        ELSE a
```

— `jl4/examples/legal/promissory-note.l4:281-286`

**It is doing** exactly what it says. The interest is that "greater of" and "lesser of" are the two
words most often swapped by an amendment: the 2021 amendment to the investor limit in Regulation
Crowdfunding substituted one for the other in both limbs, which raised the limit for every investor
whose two figures differed (`jl4/examples/legal/regcf/regcf.l4:384-406`). Name the concept after
the phrase so that an amendment is a one-word edit in one place.

**Write** the prelude's `max` and `min`. They are there now, so the hand-written pair above is
history rather than a model.

```l4
`the investor's annual income` MEANS 90000
`the investor's net worth`     MEANS 120000

GIVETH A NUMBER
`the greater of annual income or net worth` MEANS
    max `the investor's annual income` `the investor's net worth`

GIVETH A NUMBER
`the lesser of annual income or net worth` MEANS
    min `the investor's annual income` `the investor's net worth`

#ASSERT `the greater of annual income or net worth` EQUALS 120000
#ASSERT `the lesser of annual income or net worth`  EQUALS 90000
```

_(Probe `q03-minmax.l4`, exit 0, no errors.)_

For "the highest of the following" over a list rather than a pair, reach for `maximum` and
`minimum`. Each is **overloaded twice**, and the difference is what happens on an empty list. Over a
`LIST OF NUMBER` they answer a `NUMBER` — `maximum (LIST 90000, 120000, 75000)` is `120000`, with no
`JUST` anywhere — but an empty list has no greatest element, so that overload is partial: measured,
`maximum` applied to an `EMPTY` `LIST OF NUMBER` stops the evaluation, reporting that the value
`EMPTY` `reached a CONSIDER that has no branch for it.`, and `l4 run` exits 1. Over a
`LIST OF MAYBE NUMBER` they answer a `MAYBE NUMBER`, and the empty list is `NOTHING` rather than a
stopped evaluation. Use the plain list where the source guarantees at least one member ("the highest
of the three quotations"); use the `MAYBE` list where it does not ("the highest of the quotations
received, if any"):

```l4
-- "the highest of the three quotations": at least one member is guaranteed.
`the three quotations` MEANS LIST 90000, 120000, 75000

GIVETH A NUMBER
`the highest quotation` MEANS maximum `the three quotations`

-- "the highest of the quotations received, if any": there may be none.
`the quotations received` MEANS LIST JUST 90000, JUST 120000, JUST 75000

GIVETH A MAYBE NUMBER
`the highest quotation received, if any` MEANS maximum `the quotations received`

#ASSERT `the highest quotation` EQUALS 120000
#EVAL `the highest quotation received, if any`
```

```text
JUST OF 120000
```

_(Probe `v-q03c2-maximum.l4`, exit 0, no errors; the assertion is satisfied and the `#EVAL` prints
the line above. Note the printed `OF`: it is how an applied constructor renders, and it is not
source you can copy back.)_

**Not** `min` handed a list. `min` and `max` are two-argument functions, overloaded over `NUMBER`
and `MAYBE NUMBER`, and giving one a list makes the overload unresolvable rather than producing a
"wrong number of arguments" message:

```l4
`three quotations` MEANS LIST 90000, 120000, 75000

GIVETH A NUMBER
`the lowest quotation (wrong)` MEANS min `three quotations`
```

```text
There are multiple definitions for the identifier

  min

and I do not have sufficient information to make a choice between them.
The options are:

  min (defined at prelude.l4:373:1-4) of type FUNCTION FROM MAYBE OF NUMBER AND MAYBE OF NUMBER TO MAYBE OF NUMBER
  min (defined at prelude.l4:309:1-4) of type FUNCTION FROM NUMBER AND NUMBER TO NUMBER
```

_(Probe `q03b-min-on-list.l4`, exit 1, one check error. When you see "multiple definitions … and I
do not have sufficient information", the fix is almost always the argument types, not the name.)_

**See** [builtins.md](../builtins.md), "Prelude — most-used functions", and entry 3.7 for the
"whichever is greater, but not exceeding" shape, which is `max` and `min` composed.

---

<a id="e3-5"></a>

## 3.5 "the aggregate of", "the sum of", "taken together with"

**If the source says**

```text
@ref 17 CFR 227.100(a)(1); 17 CFR 227.201(t) Instruction 1
GIVEN offering IS AN Offering
GIVETH A NUMBER
`aggregate offering amount` offering MEANS
        offering's `aggregate amount sold in reliance on section 4(a)(6) during the preceding 12 months`
    PLUS offering's `maximum offering amount the issuer will accept`
```

— `jl4/examples/legal/regcf/regcf.l4:349-354`

**It is doing** two different jobs under one word. When the source **names** the things being added
— "the aggregate of the amount already sold and the amount to be sold" — the naming is operative:
a dispute about the aggregate is a dispute about which components go in, and the corpus's note
at `regcf.l4:366-368` is entirely about scope — `the aggregate counts ONLY securities sold in reliance on section 4(a)(6)`.
When the source **ranges** over an open class — "the sum of all payments made
under this agreement" — the members are not known at drafting time.

**Write** a named addition for the first, so each component reads back against the source, and
`sum` over a `LIST OF NUMBER` for the second.

```l4
DECLARE Offering HAS
    `the amount already sold in the preceding 12 months` IS A NUMBER
    `the maximum amount the issuer will accept`          IS A NUMBER

-- "the aggregate of X and Y": the source names the components, so name them.
@ref 17 CFR 227.100(a)(1)
GIVEN offering IS AN Offering
GIVETH A NUMBER
`aggregate offering amount` offering MEANS
         offering's `the amount already sold in the preceding 12 months`
    PLUS offering's `the maximum amount the issuer will accept`

-- "the sum of all payments made": the source ranges over an open class, so sum a LIST.
GIVEN payments IS A LIST OF NUMBER
GIVETH A NUMBER
`the sum of the payments made` payments MEANS sum payments
```

_(Probe `q04-aggregate.l4`, exit 0, no errors; two assertions satisfied.)_

**And write the scope note the aggregate needs.** "Aggregate" is where encodings quietly disagree
with each other: whether a concurrent transaction, a related party, or a different exemption is
inside the total is usually settled by a sentence elsewhere in the instrument, and a rule that just
adds two fields records no view about it. Put the view in a comment above the rule, with its
citation, as the corpus does.

**Not** `sum` over the records themselves. It is a list of the wrong thing, and the message names
the type rather than the mistake:

```l4
DECLARE Payment HAS amount IS A NUMBER

`the payments made` MEANS LIST (Payment WITH amount IS 100), (Payment WITH amount IS 250)

GIVETH A NUMBER
`the sum of the payments made (wrong)` MEANS sum `the payments made`
```

```text
The first argument of function

  sum (defined at prelude.l4:265:1-4)

is expected to be of type

  LIST OF NUMBER

but is here of type

  LIST OF Payment
```

_(Probe `q04b-sum-records.l4`, exit 1. The repair is `sum (map …)` — see entry 3.6, where the band
fold does exactly that.)_

**See** [drafting-patterns.md](../drafting-patterns.md), "Top-level aggregation (entry point)", for
aggregating conclusions rather than quantities.

---

<a id="e3-6"></a>

## 3.6 "where the amount exceeds X but does not exceed Y" — thresholds, bands and rate tables

**If the source says** a table of bands. The corpus's three-tier example selects a requirement, not
a number, but the shape is the same one a fee schedule uses:

```text
@ref 17 CFR 227.201(t)(1)-(3)
GIVEN offering IS AN Offering
GIVETH A FinancialStatementRequirement
`financial statements required` offering MEANS
    BRANCH IF `the COVID-19 temporary relief could change this answer` THEN `the COVID-19 temporary rules, Rule 201(z) and (bb), are not modelled here`
           IF `aggregate` AT MOST `tier 1 ceiling`                     THEN `financial statements certified by the principal executive officer, with tax return information`
           IF `aggregate` AT MOST `tier 2 ceiling`                     THEN `financial statements reviewed by an independent public accountant`
           IF `first-time issuer relief applies`                       THEN `financial statements reviewed by an independent public accountant`
           OTHERWISE `financial statements audited by an independent public accountant`
```

— `jl4/examples/legal/regcf/regcf.l4:497-505`

**It is doing** partitioning a quantity into intervals. Two readings are possible and the source
almost never says which in the table itself: a **slab** table applies one rate to the whole amount
according to the band it lands in; a **marginal** table applies each band's rate only to the slice
of the amount inside that band. Decide which before you write anything, and put the decision in a
comment with the words that settled it.

**Write the slab case as a first-match ladder, lowest ceiling first.** `BRANCH` takes the first arm
whose test holds, so the arms carry the band boundaries implicitly and each arm only needs its own
ceiling.

```l4
DECLARE `Financial statement requirement` IS ONE OF
    `certified by the principal executive officer`
    `reviewed by an independent public accountant`
    `audited by an independent public accountant`

`tier 1 ceiling` MEANS 124000
`tier 2 ceiling` MEANS 618000

-- A band ladder: one arm per ceiling, LOWEST CEILING FIRST, because BRANCH
-- takes the first arm whose test holds.
@ref 17 CFR 227.201(t)(1)-(3)
GIVEN `the aggregate offering amount` IS A NUMBER
GIVETH A `Financial statement requirement`
`the financial statements required for` `the aggregate offering amount` MEANS
    BRANCH IF `the aggregate offering amount` AT MOST `tier 1 ceiling` THEN `certified by the principal executive officer`
           IF `the aggregate offering amount` AT MOST `tier 2 ceiling` THEN `reviewed by an independent public accountant`
           OTHERWISE `audited by an independent public accountant`

#ASSERT `the financial statements required for` 100000 EQUALS `certified by the principal executive officer`
#ASSERT `the financial statements required for` 500000 EQUALS `reviewed by an independent public accountant`
#ASSERT `the financial statements required for` 900000 EQUALS `audited by an independent public accountant`
```

_(Probe `q05-bands.l4`, exit 0, no errors. Note the ceilings are named, not inlined: entry 3.1
explains why, since a ceiling is the thing an instrument moves.)_

**Write the marginal case as rows of data plus a fold**, so the table can grow a row without the
formula changing:

```l4
-- A rate table read MARGINALLY: each rate bites only on the slice of the amount
-- inside its own band. One row per band, as data, then a fold.
DECLARE Band HAS
    `the lower bound of the band` IS A NUMBER
    `the width of the band`       IS A NUMBER
    `the rate for the band`       IS A NUMBER

`the duty bands` MEANS
    LIST (Band WITH `the lower bound of the band` IS 0,      `the width of the band` IS 180000, `the rate for the band` IS 1%)
       , (Band WITH `the lower bound of the band` IS 180000, `the width of the band` IS 180000, `the rate for the band` IS 2%)
       , (Band WITH `the lower bound of the band` IS 360000, `the width of the band` IS 640000, `the rate for the band` IS 3%)

GIVEN amount IS A NUMBER
      band   IS A Band
GIVETH A NUMBER
`the duty on the slice of` amount `falling in` band MEANS
    `the part of the amount inside this band` TIMES band's `the rate for the band`
    WHERE
        `the amount above the lower bound` MEANS
            max 0 (amount MINUS band's `the lower bound of the band`)
        `the part of the amount inside this band` MEANS
            min `the amount above the lower bound` (band's `the width of the band`)

GIVEN amount IS A NUMBER
GIVETH A NUMBER
`the duty on` amount MEANS
    sum (map `the duty on this slice` `the duty bands`)
    WHERE
        `the duty on this slice` band MEANS `the duty on the slice of` amount `falling in` band

#ASSERT `the duty on` 100000 EQUALS 1000
#ASSERT `the duty on` 500000 EQUALS 9600
```

_(Probe `q19-marginal.l4`, exit 0, no errors. A record literal inside a `LIST` needs its
parentheses; without them the file does not parse.)_

**Not** the arms in the order the instrument prints them, when the instrument prints the widest band
first. Read as first-match, the wide arm swallows every narrower one below it, and nothing warns
you:

```l4
GIVEN `the aggregate offering amount` IS A NUMBER
GIVETH A `Financial statement requirement`
`the financial statements required for (wrong)` `the aggregate offering amount` MEANS
    BRANCH IF `the aggregate offering amount` AT MOST 618000 THEN `reviewed by an independent public accountant`
           IF `the aggregate offering amount` AT MOST 124000 THEN `certified by the principal executive officer`
           OTHERWISE `audited by an independent public accountant`

#ASSERT `the financial statements required for (wrong)` 100000 EQUALS `certified by the principal executive officer`
```

```text
assertion failed
```

_(Probe `q05b-bands-wrong-order.l4`, exit 0, one error. The second arm is unreachable and there is
no unreachable-arm warning: an assertion per band is the only thing that catches it.)_

**Not** a marginal table computed as a slab. Applying the top rate to the whole amount is the
single commonest arithmetic error in this area, and it overstates by a factor that grows with the
amount:

```l4
GIVEN amount IS A NUMBER
GIVETH A NUMBER
`the duty on (wrong)` amount MEANS
    BRANCH IF amount AT MOST 180000 THEN amount TIMES 1%
           IF amount AT MOST 360000 THEN amount TIMES 2%
           OTHERWISE                     amount TIMES 3%

#EVAL `the duty on (wrong)` 500000
```

```text
15000
```

_(Probe `q19b-slab.l4`: 15000 against the marginal answer of 9600 on the same table.)_

**See** [drafting-patterns.md](../drafting-patterns.md), `Statutory tables as DATA`, for a table
whose columns are enumerations rather than numbers, and entry 3.1 for a table whose figures move
over time.

---

<a id="e3-7"></a>

## 3.7 "whichever is greater, but not exceeding" — a floor and a cap

**If the source says** a computed amount hemmed in from both sides:

```text
@ref 17 CFR 227.100(a)(2)(i)-(ii) — the limit as a formula
`investment limit` investor MEANS
    IF   `either annual income or net worth is less than the cut point` investor
    THEN IF   `minimum permitted investment` AT LEAST `five percent of the measure`
         THEN `minimum permitted investment`
         ELSE `five percent of the measure`
    ELSE IF   `ten percent of the measure` AT MOST `maximum amount sold to any one investor in a 12-month period`
         THEN `ten percent of the measure`
         ELSE `maximum amount sold to any one investor in a 12-month period`
```

— `jl4/examples/legal/regcf/regcf.l4:423-433`

**It is doing** two different things that look alike. A **floor** ("or $2,500, whichever is
greater") protects the smallest case, and it is `max`. A **cap** ("not to exceed $124,000") protects
the largest, and it is `min`. Swap them and both protections invert.

**Write** them as `max` for a floor and `min` for a cap, with the percentage as a percent literal
(entry 3.2) and both limits named:

```l4
-- "5 percent ..., or $2,500, whichever is greater" -- a FLOOR, so max.
-- "10 percent ..., not to exceed $124,000"         -- a CAP,   so min.
GIVEN investor IS AN InvestorProfile
GIVETH A NUMBER
`the investment limit for` investor MEANS
    IF   `either measure is below the cut point`
    THEN max `the minimum permitted investment` `five percent of the measure`
    ELSE min `ten percent of the measure` `the maximum amount sold to any one investor in 12 months`
    WHERE
        `the measure` MEANS max (investor's `annual income`) (investor's `net worth`)
        `five percent of the measure` MEANS 5% TIMES `the measure`
        `ten percent of the measure`  MEANS 10% TIMES `the measure`
        `either measure is below the cut point` MEANS
               investor's `annual income` LESS THAN `the cut point`
            OR investor's `net worth`     LESS THAN `the cut point`
```

_(Probe `q18-floor-cap.l4`, exit 0, no errors; three assertions, one per case, including the very
small saver whose percentage is below the floor.)_

**Not** `min` for a floor. It type-checks, it evaluates, and it takes the protection away from
exactly the party it was written for:

```l4
GIVEN `the measure` IS A NUMBER
GIVETH A NUMBER
`the investment limit (wrong)` `the measure` MEANS
    min `the minimum permitted investment` (5% TIMES `the measure`)

#EVAL `the investment limit (wrong)` 30000
```

```text
1500
```

_(Probe `q18b-floor-as-cap.l4`: 1500 where the floor should have produced 2500. The test that
catches it is a case **below** the floor; a mid-range case agrees with both spellings.)_

**See** entry 3.4 for `max` and `min` themselves.

---

<a id="e3-8"></a>

## 3.8 "rounded down to the nearest dollar" — and the rounding L4 does not do

**If the source says** a rounding instruction. The corpus rounds a computed due date up and says
whose benefit it is choosing:

```text
`Next Payment Due Date` MEANS                      -- It's curious that the ACTUAL due date is the due date + grace period.
    CEILING (`Next Payment Due`'s `Days Beyond Commencement`) -- We round this up to not be too anal in the lenders favor
```

— `jl4/examples/legal/promissory-note.l4:136-137`

**It is doing** deciding who gets the fraction. Every rounding rule is a small allocation between
the parties, which is why instruments spell out the direction rather than leaving it to arithmetic.

**Write** the built-in that matches the direction. `FLOOR`, `CEILING` and `TRUNC` need no `IMPORT`.
`TRUNC value digits` truncates **toward zero**, so it is not `FLOOR` for a negative amount.

```l4
`the computed levy` MEANS 6199.95

-- "rounded down to the nearest dollar"
`the levy rounded down` MEANS FLOOR `the computed levy`
-- "rounded up to the nearest dollar"
`the levy rounded up`   MEANS CEILING `the computed levy`
-- "truncated to two decimal places" (toward zero, so it is NOT FLOOR for a
-- negative amount)
`the levy to two places` MEANS TRUNC `the computed levy` 2

-- There is no ROUND. "Rounded to the nearest dollar, half up" is written out.
GIVEN amount IS A NUMBER
GIVETH A NUMBER
`rounded to the nearest dollar, half up` amount MEANS FLOOR (amount PLUS 0.5)

#ASSERT `the levy rounded down`   EQUALS 6199
#ASSERT `the levy rounded up`     EQUALS 6200
#ASSERT `the levy to two places`  EQUALS 6199.95
#ASSERT `rounded to the nearest dollar, half up` 6199.5  EQUALS 6200
#ASSERT `rounded to the nearest dollar, half up` 6199.49 EQUALS 6199
#ASSERT FLOOR (0 MINUS 2.5) EQUALS (0 MINUS 3)
#ASSERT TRUNC (0 MINUS 2.5) 0 EQUALS (0 MINUS 2)
```

_(Probe `q06-rounding.l4`, exit 0, no errors; seven assertions. The comment in that snippet
overstates one thing, corrected immediately below: `ROUND` does exist.)_

**Correction, and the reason this entry is here.** `ROUND` **is** a built-in — measured
`FUNCTION FROM NUMBER TO NUMBER`, taking exactly one argument — and it rounds **half to even**, not
half up:

| written               | evaluates to |
| --------------------- | ------------ |
| `ROUND 6199.95`       | `6200`       |
| `ROUND 2.5`           | `2`          |
| `ROUND 3.5`           | `4`          |
| `ROUND (0 MINUS 2.5)` | `-2`         |

_(Probe `q06b-round.l4`, exit 0.)_ Half-to-even is the accountant's convention and it is a
defensible reading of "rounded to the nearest", but it is **not** what a drafter who writes "0.5 is
rounded up" means, and it is not what a spreadsheet elsewhere in the same transaction will have
done. So: use `ROUND` when the instrument says nothing and half-to-even is acceptable; write the
rule out when the instrument says which way a half goes.

**Not** `ROUND` for "rounded up where the amount is one half or more":

```l4
`the levy` MEANS 2.5
#ASSERT ROUND `the levy` EQUALS 3
```

```text
assertion failed
```

_(Probe `q06d-roundhalf.l4`, exit 0, one error.)_

**Not** `ROUND` with a number of decimal places. It takes one argument; the two-argument form is
`TRUNC`:

```l4
#EVAL ROUND 6199.955 2
```

```text
The function

  ROUND (predefined)

expects 1 argument,
but you are applying it to 2 arguments here.
```

_(Probe `q06c-round2.l4`, exit 1.)_

**See** [builtins.md](../builtins.md), "Type coercions", for `TRUNC`, and entry 3.10 for why the
unit being rounded to is a matter of naming rather than of type.

---

<a id="e3-9"></a>

## 3.9 "the number of" — counting, and who does the counting

**If the source says** a count. The corpus has both kinds. Where the count is a decision it makes,
it computes one:

```text
GIVETH A NUMBER
`the number of sureties a bond ordinarily requires` MEANS 2
```

— `jl4/examples/legal/sg-succession/sg-paa.l4:913-914`

Where the count is a fact about the world, it takes one, and records the convention it is relying
on:

```text
-- AMBIGUITY: counting "the number of days on which he was absent" — does a
-- day of departure or arrival, part-spent in the UK, count as a day of
-- absence? Reading (i): a day counts as absent only if the person was
-- outside the UK for the whole day (taken here as the input convention —
-- the NUMBER field carries whatever count the fact-supplier certifies).
```

— `jl4/examples/legal/bna/bna.l4:390-394`

**It is doing** one of two very different things, and the phrase is the same for both. Ask whether
the encoding holds the things being counted. If it does, count them. If it does not — days absent
from a country, employees on a payroll, shareholders on a register — the number is an input, and
the **counting convention** is the part that will be argued about. Write the convention down where
the field is declared; do not let a bare `IS A NUMBER` imply that everyone agrees what a day is.

**Write** `count` over the list when you hold the list, and `count (filter …)` when the source
qualifies the class being counted.

```l4
DECLARE Child HAS
    name        IS A STRING
    `survived the deceased` IS A BOOLEAN

`the children of the deceased` MEANS
    LIST (Child WITH name IS "Ada", `survived the deceased` IS TRUE)
       , (Child WITH name IS "Ben", `survived the deceased` IS FALSE)
       , (Child WITH name IS "Cai", `survived the deceased` IS TRUE)

-- "the number of children" -- count over the whole list
GIVETH A NUMBER
`the number of children` MEANS count `the children of the deceased`

-- "the number of children who survived the deceased" -- filter, then count
GIVETH A NUMBER
`the number of surviving children` MEANS
    count (filter `survived` `the children of the deceased`)
    WHERE
        `survived` c MEANS c's `survived the deceased`

#ASSERT `the number of children` EQUALS 3
#ASSERT `the number of surviving children` EQUALS 2
```

_(Probe `q07-counting.l4`, exit 0, no errors.)_

**Not** the unfiltered count under the qualified name. "The number of children who survived" is not
"the number of children", and the difference only shows up on a case where somebody predeceased:

```l4
GIVETH A NUMBER
`the number of surviving children (wrong)` MEANS count `the children of the deceased`

#ASSERT `the number of surviving children (wrong)` EQUALS 2
```

```text
assertion failed
```

_(Probe `q07b-count-wrong.l4`, exit 0, one error.)_

**See** [builtins.md](../builtins.md), "Lists", for `count`, `filter` and `elem`, and its
"Quantifiers" subsection for `any` and `all`; and
[sets.md](../sets.md) when the source counts distinct members rather than entries.

---

<a id="e3-10"></a>

## 3.10 "$25,000", "$2.5 billion" — money, and figures too large to type

**If the source says** a sum of money in an instrument that deals in more than one currency, or in
figures with nine or more zeros. The corpus does both. A note that trades in one currency carries
it in the value:

```text
`Principal Amount` MEANS USD 25000        -- Using the USD helper function to make it look super neat
```

— `jl4/examples/legal/promissory-note.l4:11`

and an award whose thresholds run to trillions writes them with scale helpers:

```text
`Acquisition Threshold` MEANS Billion 20
```

— `jl4/examples/legal/ceo-performance-award.l4:18`, with `Million`, `Billion` and `Trillion`
defined at `:470-483`

**It is doing** carrying a unit that the type system does not carry for you. Entry 3.2 gives the
default: amounts are `NUMBER`s, one currency per file, said once. This entry is the two cases where
that is not enough.

**Write a `Money` record when the instrument is genuinely multi-currency**, and define the addition
yourself — which is exactly where the currency check belongs:

```l4
-- A multi-currency instrument: carry the unit in the value, not only the name.
DECLARE Money HAS
    Currency IS A STRING
    Value    IS A NUMBER

GIVEN a IS A NUMBER
GIVETH A Money
USD MEANS Money WITH Currency IS "USD", Value IS a

GIVEN a IS A NUMBER
GIVETH A Money
SGD MEANS Money WITH Currency IS "SGD", Value IS a

-- Addition is defined by you, and it is where the currency check lives.
GIVEN a IS A Money
      b IS A Money
GIVETH A MAYBE Money
`the aggregate of` a `and` b MEANS
    IF   a's Currency EQUALS b's Currency
    THEN JUST (Money WITH Currency IS a's Currency, Value IS a's Value PLUS b's Value)
    ELSE NOTHING

#EVAL `the aggregate of` (USD 25000) `and` (USD 500)
#EVAL `the aggregate of` (USD 25000) `and` (SGD 500)
```

```text
JUST OF (Money OF "USD", 25500)
NOTHING
```

_(Probe `q08-money.l4`, exit 0, no errors. `IMPORT currency` does not supply this type — see entry
3.2 — but it does supply the decimal-places count you need if you convert to minor units.)_

**Write scale helpers for large figures.** Miscounting zeros is not a hypothetical failure; a helper
makes the figure read like the instrument and makes the mistake visible:

```l4
GIVEN a IS A NUMBER
GIVETH A NUMBER
Million MEANS a TIMES 1000000

GIVEN a IS A NUMBER
GIVETH A NUMBER
Billion MEANS Million a TIMES 1000

GIVEN a IS A NUMBER
GIVETH A NUMBER
Trillion MEANS Billion a TIMES 1000

@ref 2025 CEO Performance Award, tranche 1 market-capitalisation milestone
`Required Market Cap For Tranche 1` MEANS Trillion 2
`Acquisition Threshold`             MEANS Billion 20

#ASSERT `Required Market Cap For Tranche 1` EQUALS 2000000000000
#ASSERT `Acquisition Threshold` EQUALS 20000000000
```

_(Probe `q20-magnitude.l4`, exit 0, no errors. Underscores are also legal in a numeric literal —
`10_000` — and are worth using wherever you type the zeros out.)_

**Not** `PLUS` between two `Money` values. There is no arithmetic on your record until you write it,
and the message is about overload resolution rather than about money:

```l4
`the total (wrong)` MEANS USD 25000 PLUS USD 500
```

```text
There are multiple definitions for the identifier

  `__PLUS__`

and I do not have sufficient information to make a choice between them.
The options are:

  `__PLUS__` (predefined) of type FUNCTION FROM NUMBER AND NUMBER TO NUMBER
  `__PLUS__` (defined at prelude.l4:1283:1-11) of type FOR ALL a FUNCTION FROM SET OF a AND SET OF a TO SET OF a
```

_(Probe `q08b-money-plus.l4`, exit 1.)_

**See** entry 3.2 for the single-currency default, and entry 4.3 for the same unit problem in
deadlines, where there is no record to put the unit in at all.

---

<a id="e3-11"></a>

## 3.11 "15% per annum", pro rata — the rate whose period lives in its name

**If the source says** a rate over a period:

```text
`Interest Rate Per Annum` MEANS 15%                         -- Native support for % numbers!
```

— `jl4/examples/legal/promissory-note.l4:13`

**It is doing** stating a rate **and** a period, in one phrase. The percent literal captures the
rate exactly (entry 3.2). The period it captures not at all: `15%` is the number `0.15`, and
nothing stops a later rule from charging it monthly. This is the same failure as entry 4.3's bare
`WITHIN 14`, in a place where it costs money rather than days.

**Write** the annual rate under a name that says "per annum", derive every other period from it in
one named place, and put the day-count convention of a pro-rata calculation in the rule rather than
in a reader's head.

```l4
-- "interest at 15% per annum, accruing monthly"
-- THE PERIOD IS IN THE NAME AND NOWHERE ELSE. `Interest Rate Per Annum` is a
-- bare NUMBER; nothing stops a later rule from multiplying it by a month.
`Interest Rate Per Annum` MEANS 15%
`Monthly Installments`    MEANS 12

GIVETH A NUMBER
`the monthly rate` MEANS `Interest Rate Per Annum` DIVIDED BY `Monthly Installments`

-- pro rata for a part period: the fraction is days elapsed over days in the year
GIVEN principal IS A NUMBER
      `days elapsed` IS A NUMBER
GIVETH A NUMBER
`the interest accrued on` principal `over` `days elapsed` MEANS
    principal TIMES `Interest Rate Per Annum` TIMES (`days elapsed` DIVIDED BY 365)

#ASSERT `Interest Rate Per Annum` EQUALS 0.15
#EVAL `the monthly rate`
#EVAL `the interest accrued on` 25000 `over` 73
```

```text
0.0125
750
```

_(Probe `q09-perannum.l4`, exit 0, no errors.)_

**The 365 is a choice, and it is the one to argue about.** "Actual over 365", "actual over 360" and
"30/360" are all real day-count conventions and they give different answers on the same facts;
`daydate` gives you `Days in a year` (365.2425, the average including the leap-year cycle), which is
right for projecting an average month and wrong as a divisor for a contractual year. Name the
convention where you divide.

**Not** the annual rate applied once per period:

```l4
GIVEN principal IS A NUMBER
GIVETH A NUMBER
`the interest for one year (wrong)` principal MEANS
    principal TIMES `Interest Rate Per Annum` TIMES 12

#EVAL `the interest for one year (wrong)` 25000
```

```text
45000
```

_(Probe `q09b-perannum-wrong.l4`, exit 0, one error: 45000 against the 3750 a year's interest at
15% on 25000 actually is. It type-checks perfectly.)_

**See** entry 3.2 for the percent literal, and entry 4.9 for periods of months, where the calendar
adds its own trap on top of this one.

---

<a id="e3-12"></a>

## 3.12 The prelude names the arithmetic in this area needs

**If the source says** nothing — this entry is not a drafting phrase. It is the list of names the
other eleven entries reach for, gathered in one place because the file that claims to be the
built-ins reference does not have them.

**It is doing** closing a measured gap. [builtins.md](../builtins.md)'s "Prelude — most-used
functions" tables list `count` and `elem` and not `min`, `max`, `sum`, `product`, `maximum` or
`minimum` — which is to say, not the two functions a liability cap turns on
([3.4](#e3-4)) and not the one an aggregate turns on ([3.5](#e3-5)).

**Write** them with an `IMPORT prelude` at the top of the file:

```l4
IMPORT prelude

#CHECK sum      -- FUNCTION FROM LIST OF NUMBER TO NUMBER
#CHECK product  -- FUNCTION FROM LIST OF NUMBER TO NUMBER

#ASSERT min 120 150 EQUALS 120
#ASSERT max 120 150 EQUALS 150
#ASSERT sum (LIST 4800, 1500) EQUALS 6300
#ASSERT product (LIST 40, 120) EQUALS 4800
#ASSERT maximum (LIST 3, 9, 5) EQUALS 9
#ASSERT minimum (LIST 3, 9, 5) EQUALS 3
#ASSERT count (LIST 3, 9, 5) EQUALS 3
#ASSERT elem 9 (LIST 3, 9, 5)

-- "The Company's total liability shall not exceed the fees paid in the
--  preceding 6 months." The cap is the LESSER of the claim and the cap figure.
GIVEN `the claim` IS A NUMBER
      `the fees paid in the preceding 6 months` IS A NUMBER
GIVETH A NUMBER
`the amount recoverable on` `the claim` `, capped at` `the fees paid in the preceding 6 months` MEANS
    min `the claim` `the fees paid in the preceding 6 months`

#ASSERT `the amount recoverable on` 90000 `, capped at` 36000 EQUALS 36000
```

_(Probe `r5-prelude-arith.l4`, exit 0, no errors, nine assertions satisfied.)_

| name                       | shape                                  | note                                                             |
| -------------------------- | -------------------------------------- | ---------------------------------------------------------------- |
| `min a b`, `max a b`       | two `NUMBER`s to a `NUMBER`            | also defined over `MAYBE NUMBER`, so the bare name is overloaded |
| `sum xs`, `product xs`     | `LIST OF NUMBER` to a `NUMBER`         | not overloaded; `#CHECK` reports the type                        |
| `maximum xs`, `minimum xs` | `LIST OF NUMBER` to a `NUMBER`         | also defined over `LIST OF (MAYBE NUMBER)`                       |
| `count xs`                 | any `LIST` to a `NUMBER`               | the length; see [3.9](#e3-9) for who does the counting           |
| `elem x xs`                | an element and a `LIST` to a `BOOLEAN` | membership                                                       |

**Not** a bare file. **The prelude is not loaded automatically**, whatever
[builtins.md](../builtins.md) says at the head of its library index: in a file with no `IMPORT` at
all, `sum` is undefined (probe `r5b-no-prelude-import.l4`, exit 1):

```
I could not find a definition for the identifier

  sum

which I have inferred to be of type:

  FUNCTION FROM LIST OF NUMBER TO NUMBER
```

A library you import for another reason may pull it in — `hierarchy` opens with its own
`IMPORT prelude` — but do not rely on that; write the import.

**Not** a `#CHECK` on `min`, `max`, `maximum` or `minimum` expecting a type back. Each is overloaded
across `NUMBER` and `MAYBE NUMBER`, so `#CHECK` on the bare name is an error rather than an answer.
That error is worth provoking on purpose, though, because it prints the whole overload set with
`file:line` for each — it is the fastest way to find out what a prelude or `daydate` name can be
applied to. See [4.12](04-dates-and-periods.md#e4-12).

**See** [builtins.md](../builtins.md), "Prelude — most-used functions", for the list-and-`MAYBE`
functions this table does not repeat, [3.4](#e3-4) for "the lesser of" as a drafting phrase, and
[3.5](#e3-5) for "the aggregate of".
