# Regulation Crowdfunding (17 CFR Part 227) — the mirror corpus

`regcf.l4` formalises US SEC **Regulation Crowdfunding**, scoped to mirror exactly one
external artifact: the Lexipedia wiki page
[`reg_cf_exemptions`](https://www.lexipedia.xyz/doku.php?id=reg_cf_exemptions), which
presents Reg CF as eight numbered requirement groups. This is Track **C0** ("Mirror") of
[`specs/todo/lexipedia-superset/SPEC.md`](../../../../specs/todo/lexipedia-superset/SPEC.md).

**The law is stated as in force on 2026-07-23**, taken from the eCFR and cross-checked
against the amending releases in the Federal Register. **No figure in this corpus came
from the mirrored page.** Where the two disagree, the CFR governs; every divergence is
itemised in [§3](#3-where-the-mirrored-page-is-wrong-or-stale) below.

## Why this lives in `jl4/examples/legal/`

The team brief suggested `jl4/examples/regcf/`. It is here instead, one level down,
because `jl4/tests/Main.hs` discovers corpora by glob:

```haskell
okFiles    <- globDir1 (compile "ok/**/*.l4")    examplesRoot
legalFiles <- globDir1 (compile "legal/**/*.l4") examplesRoot
```

`legal/**` is recursive, so `legal/regcf/` is typechecked, exactprint-identity-checked,
NLG-checked and schema-checked on every CI run; a bare `examples/regcf/` matches no glob
and would get no coverage at all. `jl4/experiments/` (where the Housing Act corpus lives)
is likewise uncovered — that is a known gap, not a convention worth copying. A corpus that
nothing validates is precisely the "maintained vs abandoned vs injected" problem SPEC §1.3(4)
levels at the wiki, so putting this one outside CI would have conceded the argument.

Goldens land in `jl4/examples/legal/regcf/tests/`.

## 1. Scope boundary

Encoded — the eight groups, in the page's own order:

| # | Their heading | Encoded as | Rules |
|---|---|---|---|
| 1 | Issuer eligibility | 6 exclusion limbs, disjoined, negated once | 227.100(b)(1)–(6) |
| 2 | Offering limit | `DECIDE` over an aggregate | 227.100(a)(1) |
| 3 | Investor limits | a **formula**, not a table | 227.100(a)(2)(i)–(ii) |
| 4 | Disclosure | 3 financial-statement tiers + assurance ordering + Form C | 227.201(t), 227.203(a) |
| 5 | Intermediary obligations | single-intermediary + 21-day + investor-facing duties | 227.100(a)(3), 227.301–303 |
| 6 | Advertising restrictions | closed-list predicate + `SHANT` prohibition | 227.204 |
| 7 | Ongoing reporting | 5 termination limbs + recursive `MUST` spine (C-AR / C-TR) | 227.202, 227.203(b) |
| 8 | Resale restrictions | 1-year window + 4 exceptions + `SHANT` prohibition | 227.501 |

Plus one thing their page has no slot for: a top-level `DECIDE` composing Rule 100(a)(1)–(4)
into a single "does this transaction qualify?" question.

**Deliberately out of scope** (not on their page, so not mirrored): funding-portal
registration (Rules 400–404), bad-actor disqualification detail (Rule 503), the Rule 201
disclosure itemisation beyond the financial-statement tiers, Rule 206 (offering
communications), and the Rule 205 (compensation disclosure) regime.

## 2. Every threshold: figure, citation, effective date

| Figure | What it governs | Citation | In force since | Previous value |
|---|---|---|---|---|
| **$5,000,000** | offering maximum per 12 months | 17 CFR 227.100(a)(1) | **2021-03-15** | $1,070,000 |
| **$124,000** | income / net-worth cut point between limbs (i) and (ii) | 17 CFR 227.100(a)(2)(i)–(ii) | **2022-09-20** | $107,000 |
| **$2,500** | investment floor under limb (i) | 17 CFR 227.100(a)(2)(i) | **2022-09-20** | $2,200 |
| **$124,000** | cap on total sold to any one investor per 12 months | 17 CFR 227.100(a)(2)(ii) | **2022-09-20** | $107,000 |
| **5 %** | of the greater of income or net worth, limb (i) | 17 CFR 227.100(a)(2)(i) | 2016-05-16 | (percentage unchanged) |
| **10 %** | of the greater of income or net worth, limb (ii) | 17 CFR 227.100(a)(2)(ii) | 2016-05-16 | (percentage unchanged) |
| **$124,000** | tier 1 ceiling — CEO-certified financials + tax return info | 17 CFR 227.201(t)(1) | **2022-09-20** | $107,000 |
| **$618,000** | tier 2 ceiling — reviewed financials | 17 CFR 227.201(t)(2) | **2022-09-20** | $535,000 |
| **$1,235,000** | first-time-issuer review ceiling inside tier 3 | 17 CFR 227.201(t)(3) | **2022-09-20** | $1,070,000 |
| **300** | holders-of-record threshold to terminate reporting | 17 CFR 227.202(b)(2) | 2016-05-16 | — |
| **$10,000,000** | total-assets threshold to terminate reporting | 17 CFR 227.202(b)(3) | 2016-05-16 | — |
| **21 days** | minimum public availability before any sale | 17 CFR 227.303(a)(2) | 2016-05-16 | — |
| **120 days** | after fiscal year end, to file Form C-AR | 17 CFR 227.202(a), 227.203(b)(1) | 2016-05-16 | — |
| **5 business days** | to file Form C-TR after becoming eligible to terminate | 17 CFR 227.203(b)(3) | 2016-05-16 | — |
| **5 business days** | to file a Form C-U progress update | 17 CFR 227.203(a)(3)(i) | 2016-05-16 | — |
| **1 year** | resale restricted period | 17 CFR 227.501(a) | 2016-05-16 | — |

### The four dates, and the rule-version axis

**As of 2026-07-29 the corpus encodes the full amendment history, not just the current
values.** Every figure above that has ever moved carries one arm per regime in `regcf.l4`,
selected on `RULES EFFECTIVE DATE`, so any question in this corpus can be asked under the
rules in force on any date back to commencement via `EVAL UNDER RULES EFFECTIVE AT`. The
regime table (verified instruction-by-instruction against the Federal Register full text —
see CORPUS-TRACK §2.4.1):

| In force                    | Offering limit | Limb test      | Cut point | Floor  | Cap      | Tier 1   | Tier 2   | First-time ceiling | Accredited carve-out |
| --------------------------- | -------------- | -------------- | --------- | ------ | -------- | -------- | -------- | ------------------ | -------------------- |
| **2016-05-16 – 2017-04-11** | $1,000,000     | **lesser** of  | $100,000  | $2,000 | $100,000 | $100,000 | $500,000 | $1,000,000         | none                 |
| **2017-04-12 – 2021-03-14** | $1,070,000     | **lesser** of  | $107,000  | $2,200 | $107,000 | $107,000 | $535,000 | $1,070,000         | none                 |
| **2021-03-15 – 2022-09-19** | $5,000,000     | **greater** of | $107,000  | $2,200 | $107,000 | $107,000 | $535,000 | $1,070,000         | **added**            |
| **2022-09-20 – present**    | $5,000,000     | **greater** of | $124,000  | $2,500 | $124,000 | $124,000 | $618,000 | $1,235,000         | yes                  |

The four boundary dates:

1. **2016-05-16 — commencement.** Release 33-9974, 80 FR 71388 (Nov. 16, 2015), Part 227
   text at 71537. A rule date below this is a **curated refusal** in the corpus, not an
   answer (CORPUS-TRACK ruling R2).

2. **2017-04-12** — Release 33-10332,
   [82 FR 17545](https://www.federalregister.gov/d/2017-06797) (Apr. 12, 2017), instrs. 5–6.
   Moved every Reg CF dollar figure then in existence.

3. **2021-03-15** — **Release 33-10884**, *Facilitating Capital Formation and Expanding
   Investment Opportunities by Improving Access to Capital in Private Markets*,
   [86 FR 3496](https://www.federalregister.gov/d/2020-24749) (Jan. 14, 2021). Raised the
   offering limit to $5,000,000 **and changed the shape of the investor limit** — "lesser
   of" → "greater of", plus the accredited-investor carve-out (see §3.1).

4. **2022-09-20** — **Release 33-11098**, *Inflation Adjustments Under Titles I and III of
   the JOBS Act*, [87 FR 57394](https://www.federalregister.gov/d/2022-19867) (Sept. 20,
   2022). Moved every remaining Reg CF dollar figure. The **$5,000,000 offering limit was
   deliberately left alone**: the Commission said the March 2021 increase already "more
   than account[s] for inflation", and noted it "expect[s] that the Commission will use $5
   million as the baseline" next time (87 FR at 57397 & n.18).

The statutory adjustment cycle is roughly five-yearly, so **the next release is due around
2027** — at which point the corpus gains one arm per moved figure, and the assertions in
the rule-version group keep the old answers pinned to their old dates.

Primary text used: eCFR Title 17 Part 227 at the 2026-07-23 issue date, retrieved via
`https://www.ecfr.gov/api/versioner/v1/full/2026-07-23/title-17.xml?part=227`. The pre-2021
comparison text is the same API at `2021-01-04`.

**Currency check.** A Federal Register query for documents affecting 17 CFR 227 published
on or after 2023-01-01 returns **zero results**, so Release 33-11098 (2022-09-20) is the most
recent amendment and the figures above are current as at 2026-07-25. The deadlines in Rules
202/203 were confirmed unchanged: the only 2021 amendment to Rule 203 revised paragraph
(a)(1) (co-issuer language) and left (a)(3)(i), (b)(1) and (b)(3) alone; Rule 202 has never
been touched by an inflation release (its 2017 amendment, 82 FR 45725, is hurricane relief,
not 82 FR 17545).

## 3. Where the mirrored page is wrong or stale

Nine findings. The first is a substantive misstatement of law, not a stale number.

### 3.1 The investor limit uses the **greater** of income or net worth, not the lesser

Their page says, twice:

> "Greater of $2,200 or 5% of **the lesser** of annual income or net worth"
> "10% of **the lesser** of annual income or net worth"

The rule has read **"the greater of the investor's annual income or net worth"** in both
limbs since **2021-03-15**. Release 33-10884 substituted "greater" for "lesser" in each limb.
This is a **change in the shape of the rule, not in a number**, and it is the single most
consequential edit in Reg CF's history for an individual investor:

> An investor with $60,000 annual income and $200,000 net worth is limited to **$10,000**
> under the rule in force. Under the page's stated rule they would be limited to **$3,000**.
> The page understates this investor's lawful capacity by a factor of 3.3.

Encoded at `greater of annual income or net worth`; the $10,000 figure is asserted at
`#ASSERT \`investment limit\` (\`an investor with\` FALSE 60000 200000 0) EQUALS 10000`.

What makes this more than a typo on their part is that **neither reading was ever compelled
by the statute**. Section 4(a)(6)(B) of the Securities Act says only "a given percentage of
the annual income or net worth of such investor, as applicable". The Commission says so
itself, twice, in the release that flipped it:

> "The statutory language does not expressly provide that the investor use the lesser of
> annual income or net worth." — 86 FR 3496, n.460
>
> "When adopting Regulation Crowdfunding, the Commission considered whether to use a
> 'greater of' or 'lesser of' standard for the exemption's investment limits and determined
> to use the 'lesser of' standard at that time due to concerns about investors incurring
> unaffordable losses." — 86 FR 3496

So "lesser of" was a discretionary gloss on an ambiguous statute, held for five years and
then reversed to align Reg CF with Tier 2 of Regulation A. A page that still says "lesser
of" is not carrying a stale *number*; it is carrying a **policy position the regulator
abandoned**, and nothing in the page's format can tell a reader which of the two it is.

### 3.2 `$107,000` and `$2,200` are the pre-2022 figures

Both were superseded on **2022-09-20**. Current: **$124,000** and **$2,500**.

### 3.3 The page is internally inconsistent about the *same* threshold

$107,000 appears in their group 3 (investor limits) while **$124,000** appears in their
group 4 (financial-statement tier 1). These are **three distinct legal parameters** — the
cut point (§ 227.100(a)(2)), the per-investor cap (§ 227.100(a)(2)(ii)), and the tier-1
ceiling (§ 227.201(t)(1)) — which have moved in lockstep through every release so far, by
the *same release* on the *same day* but by **separate amendatory instructions** (2.a for
§ 227.100(a)(2), 3.a for § 227.201):

> a. In paragraph (a)(2)(i), removing reference to "$2,200" and adding in its place "$2,500";
> and removing "$107,000" and adding in its place "$124,000" […]
> 3. Amend Sec. 227.201 by: a. In paragraph (t)(1), removing reference to "$107,000" and
> adding in its place "$124,000" — 87 FR 57394, 57398

Half the page was updated and half was not. This is the failure mode SPEC §1.3(3) predicts
when a figure is transcribed with nothing linking it to its rule, its instruction, or its
date. In `regcf.l4` the three parameters are three bindings, each carrying its own `@ref`
to its own paragraph and its own dated arms — their agreement at $124,000 today is a
coincidence of the rounding table, not a structural identity, and a future release could
move one without the others exactly as the 2021 release moved § 227.100(a)(1) alone.

### 3.4 The first-time-issuer audit relief is **bounded**, and the page drops the bound

Their group 4 says: "Offerings over $618,000: Audited (reviewed for first-time; audited for
repeat issuers)."

Rule 201(t)(3) caps that relief at **$1,235,000**. A first-time issuer raising more than
$1,235,000 **must** provide audited financials. The page's formulation implies a first-time
issuer may always substitute a review, at any size. Asserted at both sides of the boundary
(`1235000` → reviewed; `1235001` → audited).

### 3.5 The offering limit does **not** aggregate Rule 504 or "other exemptions"

Their group 2 says the issuer "must aggregate amounts sold in reliance on Reg CF with
amounts sold in reliance on Rule 504 of Regulation D and in reliance on other exemptions."

Rule 100(a)(1) aggregates **only** "the aggregate amount of securities sold to all investors
by the issuer **in reliance on section 4(a)(6)**". Whether a concurrent offering is
integrated with the Reg CF offering is a different question, referred out by Rule 100(e) to
17 CFR 230.152. The aggregation the page describes runs in the *opposite* direction: it is
**Rule 504's own** $10,000,000 cap that is reduced by other securities sold in the preceding
12 months (17 CFR 230.504(b)(2)) — not Reg CF's cap that is reduced by Rule 504 sales.

### 3.6 The page omits Rule 100(b)(5) — the delinquent-filer disqualifier

Their group 1 lists four eligibility conditions. Rule 100(b) has **six** exclusions. The
missing one that bites in practice: an issuer that has sold under Reg CF and **has not filed
its ongoing annual reports** during the two years preceding the offering statement is
disqualified from the *next* offering (17 CFR 227.100(b)(5)). Encoded as
`(b)(5) — delinquent in ongoing annual reports`, with a dedicated `a delinquent issuer`
fixture and a top-level scenario showing an otherwise-clean transaction failing on it.

To be fair to the page: it does cover (b)(1), (b)(2), (b)(3), (b)(4) and (b)(6), splitting
(b)(6) across a "blank check company" mention and a "specific business plan" bullet. That
split is a presentational choice, not an error. **(b)(5) is the one genuinely missing limb.**

### 3.7 The page omits two of the five ongoing-reporting termination conditions

Their group 7 gives three ways out: becoming a reporting company, repurchase, liquidation.
Rule 202(b) has **five**, and the two omitted are the numerically interesting ones:

- **(b)(2)** one annual report filed **and fewer than 300 holders of record**;
- **(b)(3)** three annual reports filed **and total assets not exceeding $10,000,000**.

These are the conditions a real issuer actually exits on. Both encoded, both with boundary
tests (299 vs 300 holders; $10,000,000 vs $10,000,001).

### 3.8 The advertising notice permits a third content item the page drops

Their group 6 limits a conforming notice to "statement of offering, terms, intermediary
name, and platform link". Rule 204(b)(3) also permits **factual information about the legal
identity and business location of the issuer** — name, address, phone, website, a
representative's email, and a brief description of the business. Carried inline as inert
prose at `notice complies with Rule 204(b)`.

### 3.9 "Accredited investors have no limits" is right, but is a 2021 addition

Their group 3 states it without a date. Before **2021-03-15** the investor limit applied to
**every** investor; Release 33-10884 added the "[w]here the purchaser is not an accredited
investor" gate. Worth pinning because it is the kind of statement that silently becomes
false when read against a pre-2021 transaction.

## 4. What typechecks, and what the tests return

```
$ JL4_LIBRARY_PATH=jl4-core/libraries cabal run jl4:exe:l4 -- check jl4/examples/legal/regcf/regcf.l4
Check succeeded.
```

`l4 run` on the same file: **70 assertions, all satisfied; 0 errors, 0 warnings.**
`l4 format` is the identity on the source (the exactprint-identity invariant CI enforces).

Boundary coverage — at least one case on each side of every numeric threshold:

| Threshold | On the permissive side | On the restrictive side |
|---|---|---|
| $5,000,000 offering limit | `5000000` ✓ | `5000001` ✗ |
| …with $4,000,000 already sold | `+1000000` ✓ | `+1000001` ✗ |
| $124,000 (i)/(ii) selector | `123999 / 124000` → limb (i) | `124000 / 124000` → limb (ii) |
| $2,500 floor | `40000/40000` → 2500 | `60000/200000` → 10000 |
| $2,500 exactly | `50000/50000` → 2500 (5 % = 2500) | — |
| $124,000 per-investor cap | `1240000` → 124000 | `3000000` → 124000 (capped) |
| investor aggregation | `9000 + 1000` ✓ | `9000 + 1001` ✗ |
| accredited carve-out | `5000000` ✓ (no limit) | — |
| $124,000 tier 1 | `124000` → certified | `124001` → reviewed |
| $618,000 tier 2 | `618000` → reviewed | `618001` → audited (repeat issuer) |
| $1,235,000 first-time relief | `1235000` → reviewed | `1235001` → audited |
| 21 days availability | `21` ✓ | `20` ✗ |
| 1 intermediary | `1` ✓ | `2` ✗ |
| 300 holders | `299` ✓ | `300` ✗ |
| $10,000,000 assets | `10000000` ✓ | `10000001` ✗ |
| 3 annual reports | `3` ✓ | `2` ✗ |
| 1-year resale window | `365` permitted | `364` restricted |

The seven `#TRACE` directives residuate the obligation tail. Verbatim results:

```
`advertising restriction` `a conforming notice`, Issuer advertises at 10
  -> FULFILLED

`advertising restriction` `an overreaching notice`, Issuer advertises at 10
  -> DEONTIC BREACHED: party Issuer who did action `advertise the terms of the offering`
     at 10 surpassed the deadline of party Issuer who had to do obligatory action
     MUST NOT `advertise the terms of the offering` before their deadline, which was at 10

`ongoing reporting obligation` (still reporting, 2 cycles), C-AR filed at 100
  -> PARTY Issuer
     MUST `file a Form C-AR annual report`
     WITHIN `days to file the annual report after fiscal year end`
     HENCE `ongoing reporting obligation` OF status, (`annual cycles` MINUS 1)
     [the duty renewed: next year's report is what remains standing]

`ongoing reporting obligation` (may terminate), C-TR filed at 3
  -> FULFILLED

`ongoing reporting obligation` (may terminate), C-TR filed at 30
  -> DEONTIC BREACHED: ... MUST `file a Form C-TR termination of reporting`
     before their deadline, which was at 5

`resale restriction` (day 364, to an accredited investor), transfer at 100
  -> FULFILLED

`resale restriction` (day 100, ordinary buyer), transfer at 200
  -> DEONTIC BREACHED: ... MUST NOT `transfer the securities` ...
```

## 5. What could **not** be expressed, and why

Honest list. Nothing below is hidden behind a `TRUE`.

1. **"Business days" are counted as plain days.** `WITHIN` counts in whatever unit the trace
   uses. Rules 203(a)(3)(i) and 203(b)(3) say *business* days; Rule 202(a) says plain days.
   The corpus binds `business days to file Form C-TR` = `5`, which is right only when no
   weekend or holiday intervenes. Expressing it properly needs a business-day calendar over
   `daydate`, which the deadline arithmetic does not currently consult.

2. **The 1-year resale period: the unit is now right; its endpoint is still a guess, and its
   leap-day anniversary is a disclosed fork.**
   Rule 501(a) restricts transfer "during the one-year period beginning when the securities
   were issued". This entry used to record three infidelities. One is **fixed**, two remain,
   and the two that remain are of a different kind — they are places the rule does not decide,
   not places the encoding gave up.

   - **FIXED 2026-08-05 — the unit.** The period was encoded as the constant `365`, which is
     wrong by one day for any holding spanning a 29 February, i.e. roughly one in four. It is
     now a calendar anniversary (`add years`, in `daydate`'s Calendar Arithmetic), and the
     `Transfer` record carries two dates instead of an elapsed count — exactly the trade this
     entry predicted.

     **Say the provenance accurately, because an earlier draft of this bullet did not.** The
     defect was never hidden: it was disclosed in this list from the corpus's first commit
     (`4c6a385d`, 2026-07-25), which named the cause, the remedy and its price. What it was
     not, for eleven days, was *fixed*. Being written down and being repaired are different
     states, and this entry is the evidence that a disclosed defect can outlive several
     readings of the disclosure.

     What moved it was the §8 differential comparison, and the reason neither side could get
     there alone is **not** the same on both sides:

     - **This corpus could not state the case.** While `Transfer` held only "days since
       issue", a leap-spanning holding was inexpressible in its own vocabulary.
     - **The de novo encoding could state it, and still would not have found this.** Its
       `Transfer` carries two dates and it computes its own anniversary
       (`regcf-denovo.l4:1245`) — by reconstructing the components, so it *rolls forward*
       where this corpus now clamps. Its assertions exercise the de novo. A test cannot fail
       on a defect in a file it does not import.

     So the comparison did not supply the knowledge; it supplied the **witness** — a concrete
     pair of answers that differ, on a case both sides evaluate. The battery it runs over has
     perturbation **off by construction**: twenty hand-built rows that are already one fact
     apart, not generated inputs. The case is now pinned in `regcf.l4` and, per R0, executed
     on both DMN engines from `regcf-corpus.cases.json`.

     And the two encodings still disagree: this one clamps, the de novo rolls forward. That
     divergence is not a bug in either — it is the fork below, live in the tree, with one
     reading committed on each side.
   - **OPEN — the endpoint.** The rule does not say whether the first anniversary is inside
     or outside the period. Modelled as the half-open interval `[issuance, first anniversary)`:
     the day before the anniversary is restricted, the anniversary itself is free. **No
     encoding can fix this, because the rule does not decide it.** Flagged inline.
   - **OPEN — the leap-day anniversary.** What is "one year after 29 February 2024"? There is
     no single right answer, and we have three measured candidates:

     | reading | answer | where it comes from |
     | --- | --- | --- |
     | clamp to the month end | 2025-02-28 | Excel `EDATE`; FEEL `date + duration("P1Y")` on both DMN engines |
     | roll forward | 2025-03-01 | L4's lenient `Date d m y` constructor |
     | no such date | *null* | FEEL `date(2025, 2, 29)` on both engines |

     The corpus takes **the clamp** as its primary reading, because it is what both engines do
     natively and what the anniversary convention generally implies — so the L4 answer and the
     exported-DMN answer cannot drift apart. **1 March is the disclosed alternative**, and a
     drafter who cared could remove the question in four words.

3. **Reasonable-belief standards are inputs, not derivations.** Rules 301(a)–(c) and
   303(b)(1) turn on whether an intermediary "has a reasonable basis for believing" something.
   These are carried as `BOOLEAN` fields supplied by the user. L4 can represent the
   *consequence* of the standard being met; it cannot decide the standard.

4. **"Total assets", "annual income", "net worth" are unmodelled primitives.** Instruction 1
   to Rule 100(a)(2) defers to Rule 501's accredited-investor calculation, and Instruction 2
   permits spousal joint calculation with a per-individual cap. The joint-calculation rule is
   expressible and is simply **out of the mirrored scope** — their page does not mention it.
   The underlying valuation rules are not in Part 227 at all.

5. **The bad-actor disqualification is one boolean.** Rule 503(a) is a substantial
   sub-regime (covering categories of person, look-back periods, and a reasonable-care
   exception). It collapses to
   `subject to a disqualification as specified in section 227.503(a)`. Deliberate: their
   page also collapses it to one bullet. Expanding it is Track C1 work, not C0.

6. **Rule 100(a)(4)'s proviso is documented but not enforced structurally.** The statute
   says failure to comply with Rules 202, 203(a)(3) and 203(b) does *not* cost the issuer the
   exemption for an offering already made — while the *same* default reappears as a Rule
   100(b)(5) disqualifier for the *next* offering. Both halves are encoded, but the temporal
   link between them ("this offering's default is next offering's disqualifier") is carried
   as a comment, because it needs the rule-version / bitemporal axis to state properly.

7. **Integration under Rule 230.152 is a reference, not a computation.** Rule 100(e) refers
   integration out to a rule in Part 230. Encoding it would require Regulation D, which is
   outside both this scope and the mirrored page's.

8. **The financial-statement "assurance ordering" is our invention, not the rule's.** Rules
   201(t)(1) and (t)(2) each say that if higher-assurance statements are *available* the
   issuer must supply those instead. We encode this as a total order
   (certified < reviewed < audited) and test `AT LEAST`. That is a faithful reading of the
   effect, but the rule never states an ordering, and the "if available" trigger — which
   turns on what the issuer happens to possess — is not modelled at all.

9. **The rule-version axis is encoded (2026-07-29), with four named residuals.** The
   corpus now answers "what was the investor limit on 2020-06-01?" — every amended figure
   and both shape changes carry dated arms back to commencement, closed per CORPUS-TRACK
   §2.4 trap 5, with a floor refusal below 2016-05-16 (ruling R2). What remains, named
   rather than hidden:

   - **The COVID-19 temporary rules (Rule 201(z)/(bb)) are refused, not modelled.** For a
     rule date in 2020-05-04 – 2022-08-28 AND an aggregate in the affected band (above the
     then-tier-1 ceiling, at most $250,000), `financial statements required` stops with a
     deliberate `ASSUME` bottom rather than guessing: relief eligibility turns on facts
     (organization age, prior delinquency) the corpus does not model. Outside that band,
     in-window questions answer normally, and two assertions pin that.
   - **Per-arm citation has no in-language home** (CORPUS-TRACK §2.4 trap 4): each dated
     arm's authority is a `--` comment, because number-returning bodies cannot carry inert
     prose. Phase 2's `@label` is the designed fix.
   - **Nothing lints the dated arms** for exhaustiveness, overlap, or citation (ruling R6).
     The arms are hand-checked against the Federal Register instructions and pinned by the
     rule-version assertion group; that is discipline, not enforcement.
   - **The 55 pre-existing assertions are deliberately unpinned** (ruling R3, resolved: pin
     none). They state the *current* law; in CI they evaluate under the harness's fixed
     clock (2025-01-31), which sits in the current regime. After the next inflation release
     (~2027), they must either be pinned to the pre-release regime or re-verified against
     the new figures — the rule-version group's own assertions are all pinned and immune.

   The demonstration SPEC §8/M5 is built around this axis; the encoding-time clock
   (`l4 diff-eval`, Phase 3) remains absent.

## 6. Projections: what comes out of this corpus, and what does not

The mirrored page is prose plus **one** hand-drawn BPMN diagram pasted from Camunda
Modeler, with nothing connecting the prose to the XML — which is why the investor
threshold appears twice on it and is stale in both. Everything in this section is cut
from `regcf.l4` by a program. None of it was drawn.

**[`PROJECTIONS.md`](PROJECTIONS.md) is the full account**: every artifact, the exact
command that regenerates it, its fidelity notes, and — the part that matters — what each
projection *cannot* say. What follows is the summary.

| Target     | Artifact                                                                      | Status                                                       |
| ---------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------ |
| **Ladder** | `figures/*.{svg,txt,mmd,sentences}`, 7 decisions × 4 carriers                  | works; 1 of 7 too wide for a page untrimmed — see `figures/README.md` |
| **DMN**    | `../../dmn/expected/regcf-corpus.{dmn,dmn.md,fidelity.txt,md.fidelity.txt}`    | emits, validates, **executes 1540/1540 over 22 cases on both engines** — see below |
| **BPMN**   | `../../bpmn/expected/regcf-{reporting,advertising,resale}.{bpmn,fidelity.txt}` | cut from this file, three rules, three processes              |

Every BPMN golden, and the DMN **markdown** golden, reproduces byte for byte from a bare
CLI invocation — no `--model-name`, no flag but `--rule`. The DMN **XML** golden differs
from the CLI's bytes in exactly its 23 source-range annotation labels (`main.l4:` vs
`regcf.l4:` — the golden harness loads the module under a virtual URI; measured
2026-08-02, see `../../dmn/README.md` "From the CLI"). The `<definitions>` name comes
from this file's own outermost `§` heading.

### 6.1 DMN: 70 decisions, 12 tables, and a model both engines evaluate

**Measured 2026-08-09 on the shipped goldens (R12 + R13,
`specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §15.12/§16).** `l4 export --to=dmn` on
this file succeeds, the XML parses under `dmn-moddle` with **zero warnings**, and —
since R12 dropped the law-time-rebinding scenarios and R13 lowered the deontic
reporting spine to a verdict decision table — **both engines evaluate it end to end**,
over the 22 cases in `../../dmn/regcf-corpus.cases.json` (the base world, 15 dated
relocation cases carrying the dropped rule-date fixtures' truths — ruling R-C, spec
§15.12.1 — 4 seed cases added 2026-08-03, the leap case added 2026-08-05, and the
escheat case added 2026-08-09):
KIE 8.44.0.Final answers 1540/1540 decisions with 1540/1540 values as expected (plus
330/330 decision-service output values), and Camunda 8.7.6 (zeebe-dmn) parses it and
answers 1540/1540. An earlier revision of this section — "102 decisions, 11 tables, and a model no
engine can bind" — described the pre-BKM, pre-R12/R13 artifact; that model no longer
ships.

- **70 `<decision>`** elements — 9 decision tables, 60 boxed literal expressions, 1
  boxed context — plus **10 `businessKnowledgeModel`s** (Phase 5's tier-2 λ-lifts,
  3 of which carry the other 3 of the artifact's 12 `<decisionTable>`s) and **7
  `decisionService`s**. Of the 12 tables, 10 are `hitPolicy="UNIQUE"` rule-date
  interval tables and 2 are `FIRST` — one of them the R13 verdict table over the
  reporting spine. The boxed literals are FEEL an engine evaluates:
  `D-LITERALEXPR` is now **advisory**, ×67 (60 decisions + 7 BKM bodies). The three
  bullet figures above read 67/57/×64 until 2026-08-09 and were stale by two
  before this edit: the calendar-anniversary change of 2026-08-05 added two decisions
  and nothing regenerated this list. Re-derived here by counting the shipped XML and
  the shipped fidelity report, not by adding to the old numbers.
- **15 `<inputData>`** elements, one of which is the rule-date input
  `RULES_EFFECTIVE_DATE` (`typeRef="date"`). The flat-namespace collision story shrank
  with them: hydration and the BKM lowering absorbed most of the old scalar inputs, so
  `D-RENAME` and `D-SCOPE` fire once each (the two `status` terms) and `D-FEELNAME` is
  zero.
- **0 blocking, 21 lossy, 133 advisory** notes in total (re-counted from the shipped
  `regcf-corpus.fidelity.txt` on 2026-08-09; this line read 125 and drifted the same
  way the bullet above it did). The lossy set is the honest
  remainder: 15 `D-RULEDATE-UNBOUND` (the `EVAL UNDER RULES EFFECTIVE AT` scenarios
  are **not emitted** — a DRG has one global rule-date input and no scoped rebinding),
  2 `D-REGULATIVE`, 1 `D-VERDICT` (the obligation lifecycle is the BPMN projection's
  content), plus naming/partiality notes. The per-code table is in `PROJECTIONS.md`
  §1; the engine verdicts and their history are in `../../dmn/README.md`.

The old one-sentence diagnosis — **a DMN decision is a 0-ary variable**, so every
cross-decision call `f x` was emitted verbatim and unevaluable — is retired: tier-1
calls read shared `inputData` after un-lifting, tier-2 calls render as FEEL
invocations of emitted BKMs, and what could not be made faithful was dropped with a
note rather than shipped broken.

The `dmnmd` markdown leg still makes the loss-report point in one glance: 1,236 lines
of law become **one table** — the R13 verdict table, as it happens — plus 301 lines of
loss report; 57 decisions have no dmnmd form at all (`D-MD-NOLITERAL`) and 31 tables
fall to date cells dmnmd's grammar cannot hold.

An earlier revision of this section reported two further defects that the fidelity
report did not catch — a section heading spliced into FEEL as a path step (22
decisions), and the same heading prefixing every enum value in the one clean table.
Both are **fixed**: `.` separates scopes in L4 and traverses a value in FEEL, so
section qualification is now dropped on the way out
(`L4.Syntax.unqualifiedNameToText`). See `PROJECTIONS.md` §1.

`jl4/examples/dmn/reg-cf.l4` is kept as a **separate, deliberately different**
exhibit: 101 lines of `ASSUME`-style scalars chosen so the goldens show every
outcome the exporter has. Its figures are illustrative and it says so. It is not
this corpus and must not be read as it.

### 6.2 BPMN: three rules, three processes, cut from this file

```
$ l4 export jl4/examples/legal/regcf/regcf.l4 --to bpmn --rule "ongoing reporting obligation"
```

All three regulative rules here are `IF`-headed — `advertising restriction` (:494),
`ongoing reporting obligation` (:567), `resale restriction` (:622) — because the CFR
writes the guard outside the duty ("**unless** such securities are transferred: …").
`L4.StateGraph` reads that shape directly: an `IF`/`ELSE` chain over regulative arms
becomes a `OneOf` junction whose branch edges carry the condition that selects them.

Until 2026-07-27 it did not, and this section recorded a workaround —
`jl4/examples/bpmn/regcf.l4`, a hand-written second source — together with the
sentence "there is at present no BPMN of this corpus that is single-sourced from it."
**That file is deleted and that sentence no longer holds.** It had re-declared three
deadline constants, renamed four predicates, dropped the statutory chapeau, invented
two `LEST` breach clauses the CFR does not contain, and silently dropped the annual
cycle's base case — so the shipped diagram asserted a duty this corpus discharges.
None of those five is expressible now.

Three things worth looking at in the goldens:

1. **The base case is drawn.** `Split_0 → End_2` carries
   `NOT (…may terminate…) AND ``annual cycles`` AT MOST 0` — the arm that imposes no
   duty at all.
2. **The renewal loop is drawn**, and `P-CYCLE` fires on it. `HENCE` back into the
   rule itself is an `App` *with arguments*; it used to fall through to "unknown
   target" and produce a state literally named `next` with no successor.
3. **Single-sourcing costs the timer.** Every deadline here is a *name*
   (`business days to file Form C-TR`), because this file binds each period once and
   every consumer reads the binding. `P-DEADLINE` fires on every boundary event: no
   ISO 8601 duration could be read, so it is a conditional event carrying the text.
   Inlining `5` and `120` would draw real timers by reintroducing exactly the
   duplication this corpus exists to remove.

`F1` remains the most important note in the set, and it applies to the mirrored page's
own hand-drawn diagram just as much: *"A prohibition is not an activity at all and BPMN
has no negative shape for one, so read literally this diagram instructs the reader to
perform the very act the rule forbids."*

## 7. Deployment: `regcf-wizard.l4`, the façade

`regcf.l4` carries **no `@export` annotations**, so nothing in it is deployable. `regcf-wizard.l4`
is the deployable surface: it `IMPORT`s the corpus, routes flat plain-English inputs into the
corpus's own record types, calls the corpus's own predicates, and presents the result as flat
records a form can render. It re-implements no law. The corpus is untouched.

Five `@export`s, each a question a reader of the mirrored page actually has:

| Export                   | Route                            | Answers                                             |
| ------------------------ | -------------------------------- | --------------------------------------------------- |
| `raise check` (default)  | `/regcf/raise-check`             | groups 1, 2, 4 — eligibility, limit, financials      |
| `investment limit check` | `/regcf/investment-limit-check`  | group 3 — the investor's own limit (§3.1)            |
| `resale check`           | `/regcf/resale-check`            | group 8 — may these securities be transferred yet    |
| `reporting exit check`   | `/regcf/reporting-exit-check`    | group 7 — when the annual reporting duty may end     |
| `can this company raise` | `/regcf/can-this-company-raise`  | the same question as a `BOOLEAN`, for `/ladder`      |

### 7.1 Why a façade, and not `@export` on the corpus

Three reasons, each measured rather than assumed.

1. **Field names.** `jl4-service` sanitises schema property names — every non-alphanumeric
   becomes `-`, runs collapse — and then **truncates to 60 characters**
   (`jl4-service/src/Shared.hs`). **24 of the corpus's 48 record fields exceed that**, because
   they are the CFR's own sentences. Counted 2026-08-09 by reading every `` `field` IS … `` line
   of every `DECLARE` in `regcf.l4`; the same count over the file at the previous commit gives
   23 of 43, so the "23 of 41" this line used to carry was measured by some other method and is
   not reproduced here. The longest field was Rule 501(a)(4)'s limb, at 288 characters — this
   line said 291, which was its length before the clitic rename dropped a leading `is `. That
   field was decomposed into six on 2026-08-09, so the longest is now Rule 100(b)(5)'s
   184-character limb: three times the cut, and still severed at the same place. Deployed and
   read back off the live MCP endpoint:

   ```
   60  is-subject-to-a-disqualification-as-specified-in-section-227
   59  the-Form-C-includes-the-information-required-by-section-227
   ```

   Both citations lose their paragraph number at the same cut: `227.503(a)` and `227.201` both
   arrive as `section-227`. A form built off the corpus records would be labelled in amputated
   CFR-ese. Every one of the façade's 49 fields sanitises to **43 characters or fewer**, so
   nothing is truncated and nothing collides.

2. **Six declared corpus fields are inputs no rule reads** — `target offering amount`, `name` on
   `IssuerProfile` and `InvestorProfile`, and the three "states …" booleans on
   `AdvertisingNotice` (Rule 204(b) makes them permissions, not requirements). A schema-driven
   form off the corpus records would ask six questions that cannot change any answer.

3. **The corpus's top-level `DECIDE` takes six records** and the regulative rules return
   `DEONTIC`, which `jl4-service` will only evaluate against a hand-built event trace. Neither
   shape is a citizen form.

### 7.2 No figure is typed twice — including in the prose

Every threshold, deadline and percentage that appears in a façade description or answer string is
**spliced from the corpus constant**, so an amendment to `regcf.l4` rewrites the façade's
sentences without anyone editing them. Live output, with the figures the corpus supplied:

```
"Rule 100(a)(2)(i) governs, because at least one of your annual income ($60,000) and your net
 worth ($200,000) is below $124,000. Your limit is 5% of the greater of the two ($200,000), or
 $2,500, whichever is the larger — which comes to $10,000."
```

That is §3.1's investor, answered by machine. Typing "5%" or "$124,000" into that sentence would
have reproduced, inside our own artifact, exactly the duplication §3.3 convicts the mirrored page
of.

**The same investor, accredited, gets no number at all** — and that is a fix, not an omission.
`your 12 month limit` and `you can still invest` are `MAYBE NUMBER`, serialising to JSON `null`
when Rule 100(a)(2)'s carve-out applies:

```json
{ "you have no limit": true, "your 12 month limit": null, "you can still invest": null }
```

They were plain `NUMBER`s until 2026-07-27, computed with the carve-out ignored, so an accredited
investor was told `"your 12 month limit": 10000` — a cap that does not exist in law, and which
`regcf.l4:934` contradicts outright by asserting that the very same investor is within the limit
at $5,000,000. The prose field said the right thing and the numbers did not. A citizen asking "may
I invest $50,000?" would have compared against 10000 and concluded no; an LLM reading the
structured fields would have reported the same. A wrong number in a field a form renders as its
headline is worse than no number, and `null` is how JSON says "no number".

**The corpus has one single-sourcing gap, and it is the two percentages.** `regcf.l4` binds every
dollar figure once, as a named constant with an `@ref`. It does **not** do that for `0.05` and
`0.10`: both are inlined in a `WHERE` local inside `investment limit`. Rather than re-type them,
the façade recovers them from the corpus by probing `investment limit` at a point where neither
the floor nor the cap binds, and dividing out (`limb (i) percentage`). Two `#ASSERT`s, stated in
corpus constants only, pin the conditions that make the derivation valid. The proper fix is to
bind the two rates in `regcf.l4` the way every other figure is bound; that is a corpus edit, and
this file does not make it.

### 7.3 What the local deploy proved, and what it did not

Verified against a live `jl4-service` (5 functions, deploy job `applied`): the function list, the
parameter schema, evaluation on all five exports, `?trace=full` (a reasoning tree of `exampleCode`/`explanation` pairs bottoming out in corpus predicates; 30–76 KB depending on the export), batch
evaluation, `query-plan`, `ladder`, MCP discovery + `tools/list` + `tools/call` on both the
scoped and org-wide endpoints, WebMCP discovery and `embed.js`, OpenAPI, and file browsing.
Field names round-trip in **both** forms — `"organized in the United States"` and
`"organized-in-the-United-States"` are both accepted, on REST, batch and MCP alike.

Three things the deploy showed that reading the types would not have:

1. **`/state-graphs` returns `{"graphs":[]}`** on every export — but no longer for the reason
   §6.2 used to give. `findRegulativeExpr` reads `IfThenElse` now, and
   `l4 state-graph regcf.l4` yields **3** graphs. `l4 state-graph regcf-wizard.l4` still yields
   **0**, because `extractStateGraphs` walks the deployed module's own section tree and does not
   follow `IMPORT`. A façade still cannot work around it — a wrapper that calls the imported rule
   is an `App`, not a `Regulative` — but the remaining defect is import traversal, not shape
   blindness.

2. **A properly single-sourced façade has a two-leaf ladder, and an empty query plan.** The
   `/ladder` route returns exactly what `can this company raise` says:

   ```
   funDecl.body  $type = And
     args[0]     $type = UBoolVar   name.label = `issuer is eligible` OF (`issuer profile from` OF plan)
     args[1]     $type = UBoolVar   name.label = `offering is within the offering limit` OF (`offering from` OF plan)
   ```

   The six Rule 100(b) limbs are inside `issuer is eligible`, which is an `App` over a record, so
   the ladder cannot see through it. Correspondingly `query-plan` returns `"asks": []` and
   `"inputs": []`: it can name no citizen question, only the two derived predicates. **This is a
   structural tension, not an oversight.** Any decision body that delegates to the corpus is one
   opaque leaf; getting an interesting ladder means restating the statutory connectives in the
   façade, which is the duplication the whole exercise exists to avoid. The six-limb picture
   already exists, cut from the corpus itself, at `figures/regcf-rule-100b.svg`.

3. **The `atomId`s did not line up, and the disagreement was internal to one response — FIXED
   2026-08-03.** As first measured here, a single `/query-plan` payload's ids under
   `impact[…].support[].atomId` and the ids in its own embedded `ladder` field had an **empty
   intersection** (two ids each, none shared); the embedded ladder agreed with the standalone
   `/ladder`, so the split was between the query planner's atoms and the ladder's nodes. That
   became upstream `smucclaw/l4-ide#935`, because it is worse than an inconvenience: posting a
   binding keyed by a ladder `atomId` returned `200` and silently changed nothing.

   Re-measured on this bundle against a loopback service built from
   `legalese/l4-ide@mengwong/ladder-atomid-embed`, `can this company raise`, 6 exports:

   | surface                        | ids | value                                        |
   | ------------------------------ | --- | -------------------------------------------- |
   | `GET /ladder`                  | 2   | `a87d9b26-…`, `6cfcd833-…`                   |
   | embedded `ladder` in the POST  | 2   | same two                                     |
   | `impact[…].support[].atomId`   | 2   | same two                                     |
   | `impactByAtomId` keys          | 2   | same two                                     |

   Intersection of `GET /ladder` with the planner's atoms: **2 of 2**, where it was 0 of 2. Both
   ids in the issue body reproduce exactly, on `unique=4`
   (`` `issuer is eligible` OF (`issuer profile from` OF plan) ``):

   | surface       | before                                  | after                                   |
   | ------------- | --------------------------------------- | --------------------------------------- |
   | `GET /ladder` | `64e895d0-1863-5f26-bb2b-63ef440b85d3`  | `a87d9b26-bfef-5b0b-9c22-d77d103f93a9`  |
   | `query-plan`  | `a87d9b26-bfef-5b0b-9c22-d77d103f93a9`  | unchanged                               |

   So the ladder converged onto the planner's namespace and not the reverse, which is the right
   direction: an `atomId` must survive a redeploy, and the planner's is the only one of the two
   that does not embed a compilation-order `unique`. Nothing on the planner's side moved — across
   `/query-plan`, only the **values** of `impactByAtomId` change, and only for atomIds that name
   more than one occurrence; `impact`, `ranked`, `stillNeeded`, `asks` and `inputs` are
   byte-identical before and after. Binding the ladder's id end-to-end now moves the decision:
   `determined` `null → false`, `verdict` `Undetermined → Fails`, `stillNeeded` `2 → 0`.

   A ladder-embedded wizard can therefore join the two surfaces on `atomId`, which is the join
   the shapes invite.

   **Not fixed, and still worth having.** The issue asks for two things — one namespace, *or*
   a loud refusal of unknown binding keys, "ideally both". Only the first landed. A binding keyed
   by a string that names no atom is still accepted with a `200` and silently ignored (measured:
   `{"deadbeef-0000-5000-8000-000000000000": false}` → `200`, `stillNeeded` unchanged at 2). The
   class of bug that produced #935 can therefore still be introduced silently by a client typo.

### 7.4 Defects found in `jl4-service` while deploying

**Fixed** (each reproduced live before and after):

- **An enum return value did not validate against its own declared schema.** `returnSchema`
  declares `"enum": ["financial statements reviewed by an independent public accountant", …]`,
  and evaluation returned `` "`financial statements reviewed by an independent public accountant`" ``
  — the L4 backticks inside the JSON string. `Backend.Jl4` rendered a constructor with
  `prettyLayout`, which emits L4 *source* and so backtick-quotes an identifier containing spaces,
  while `L4.FunctionSchema` built the declared enum from the plain name. They now use the same
  spelling by construction.
- **`NOTHING` serialised as the string `"NOTHING"` and `JUST x` was not unwrapped**, which made
  `MAYBE` unusable for the one job it is for. `NOTHING` is now JSON `null`, matching
  `L4.Evaluate.ValueLazyJSON`.
- **`@desc` was emitted with a leading space** into every JSON Schema `description`, deployed
  function schema and hover. The lexer keeps the annotation line verbatim for exact printing;
  `L4.Syntax.getDesc` now trims for readers.
- **`POST /deployments` with a new `id` but identical bundle bytes silently ignored the id.**
  Content-hash deduplication returned the *existing* deployment (200, `"id":"regcf"`) and never
  created the requested one (`GET` → 404) — documented as "skips recompilation", it actually
  skipped deployment creation. The shortcut is now keyed on the id as well as the hash.

**Reported, not fixed** — outside this corpus:

- **Org-wide MCP tool names are not namespaced.** `jl4-service/README.md` documents
  `{"name":"my-rules/compute_qualifies"}`; the server actually emits the bare sanitised function
  name and puts the deployment in the description. Calling `regcf/raise-check` on `/.mcp` returns
  `-32602 Unknown tool`. (The naming is deliberate — `buildToolNames` disambiguates with a
  `-<depPrefix>` suffix only on collision — so this is a documentation defect, not a hazard.)
- **`GET /webmcp.js` 404s.** The README says it is a 301 to `/.webmcp/embed.js`; the string does
  not appear anywhere in `jl4-service/src`. `/.well-known/{mcp,mcp/manifest,webmcp}` and
  `/.webmcp/embed.js` all return 200.
- **`evaluation/batch` with `outcomes` returned no result at all**:
  `{"cases":[],"summary":{"casesRead":1,"casesIgnored":1,"casesProcessed":0}}`. Reproduced; not
  diagnosed.

## Attribution

The mirrored page is © its authors under **CC BY-SA 4.0** (Center for Civic Innovation,
Lexipedia). It is referenced here for criticism and comparison. Everything quoted inline in
`regcf.l4` is US federal regulatory text, which is not subject to copyright.
