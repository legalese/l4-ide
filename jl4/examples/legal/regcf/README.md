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

### The two amending events

1. **Release 33-10884**, *Facilitating Capital Formation and Expanding Investment
   Opportunities by Improving Access to Capital in Private Markets*,
   [86 FR 3496](https://www.federalregister.gov/d/2020-24749) (Jan. 14, 2021), **effective
   2021-03-15**. Raised the offering limit to $5,000,000 **and changed the shape of the
   investor limit** (see §3.1).

2. **Release 33-11098**, *Inflation Adjustments Under Titles I and III of the JOBS Act*,
   [87 FR 57394](https://www.federalregister.gov/d/2022-19867) (Sept. 20, 2022), **effective
   2022-09-20**. Moved every remaining Reg CF dollar figure. The **$5,000,000 offering limit
   was deliberately left alone**: the Commission said the March 2021 increase already "more
   than account[s] for inflation", and noted it "expect[s] that the Commission will use $5
   million as the baseline" next time (87 FR at 57397 & n.18).

The prior adjustment was Release 33-10332, [82 FR 17545](https://www.federalregister.gov/d/2017-06797)
(Apr. 12, 2017). The statutory adjustment cycle is roughly five-yearly, so **the next one is
due around 2027** — and will move six of the eleven dollar figures above.

Primary text used: eCFR Title 17 Part 227 at the 2026-07-23 issue date, retrieved via
`https://www.ecfr.gov/api/versioner/v1/full/2026-07-23/title-17.xml?part=227`. The pre-2021
comparison text is the same API at `2021-01-04`.

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

### 3.2 `$107,000` and `$2,200` are the pre-2022 figures

Both were superseded on **2022-09-20**. Current: **$124,000** and **$2,500**.

### 3.3 The page is internally inconsistent about the *same* threshold

$107,000 appears in their group 3 (investor limits) while **$124,000** appears in their
group 4 (financial-statement tier 1). These are the *same underlying figure*, moved by the
*same amendatory instruction*, on the *same day*:

> a. In paragraph (a)(2)(i), removing reference to "$2,200" and adding in its place "$2,500";
> and removing "$107,000" and adding in its place "$124,000" […]
> 3. Amend Sec. 227.201 by: a. In paragraph (t)(1), removing reference to "$107,000" and
> adding in its place "$124,000" — 87 FR 57394, 57398

Half the page was updated and half was not. This is the failure mode SPEC §1.3(3) predicts
when one number is typed in more than one place. In `regcf.l4` the figure is bound once, as
`income or net worth cut point`, and read by both consumers.

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

The page also omits Rule 100(b)(2)'s companion framing and folds the blank-check test into
the "specific business plan" bullet; that is a presentational choice, not an error.

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

`l4 run` on the same file: **55 assertions, all satisfied; 0 errors, 0 warnings.**
`l4 format` is the identity on the source (the exactprint-identity invariant CI enforces).

Boundary coverage — at least one case on each side of every numeric threshold:

| Threshold | Inside | Outside |
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

The four `#TRACE` directives residuate the obligation tail. Verbatim results:

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

2. **The 1-year resale period is rendered as 365 days, and its endpoint is a guess.**
   Rule 501(a) restricts transfer "during the one-year period beginning when the securities
   were issued" and does not say whether the first anniversary is inside or outside. Modelled
   as the half-open interval `[issuance, issuance + 365)`. Two separate infidelities: the
   leap-year one (a real anniversary is 365 or 366 days out — `daydate` could fix this, at
   the cost of carrying an issuance *date* rather than an elapsed count), and the endpoint
   one, which **no encoding can fix because the rule does not decide it**. Flagged inline.

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
   `is subject to a disqualification as specified in section 227.503(a)`. Deliberate: their
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

9. **No temporal axis yet.** Every figure here is the 2026-07-23 value. The corpus records
   each figure's effective date in an `@ref` and in §2 above, but cannot yet answer "what was
   the investor limit on 2020-06-01?". That is Track C1 (`temporal-rule-version`), and it is
   the demonstration SPEC §8/M5 is built around.

## Attribution

The mirrored page is © its authors under **CC BY-SA 4.0** (Center for Civic Innovation,
Lexipedia). It is referenced here for criticism and comparison. Everything quoted inline in
`regcf.l4` is US federal regulatory text, which is not subject to copyright.
