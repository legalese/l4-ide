# sg-child-support — this subject's idiosyncrasies

Read this before running the pipeline over it. Nothing here is repeated in the skill.

## 1. The primary source is an announcement, not an enactment

Every other subject in this repo encodes law that is in force. This one does not, and almost
everything odd about it follows from that.

The **SG Child Support Package** was announced by the Prime Minister at the National Day Rally on
**23 August 2026**, to be implemented from **1 April 2027**. As at the encoding date
(2026-08-25) no Bill has been introduced and the **Child Development Co-Savings Act 2001** — the
statute under which the Baby Bonus Scheme, the Child Development Account and childcare leave all
operate — is unamended. The P2 register records that as a checked negative, not an assumption:
searches `S1` and `S2` looked for a Bill and found only `B42-2024`, which implements a different
policy and predates the Rally.

So the rule-version axis here does **not** carry two versions of one statute. Its arms are:

| rule date           | what the arm states                                                                    |
| ------------------- | -------------------------------------------------------------------------------------- |
| before `2027-04-01` | the schemes **as administered today** — Baby Bonus, Large Families Scheme, CDCSA s 12B |
| on or after         | the scheme **as announced** — policy, not law                                          |

`sg-csp.l4`'s header says this, and each dated figure repeats it. A reader who does not pin a rule
date must not be handed an announced figure without being told it is one.

## 2. `checks.min_dated_arms` is 0, and it is NOT sg-succession's zero

sg-succession declares 0 because it has no rule-version axis at all. This subject has a thorough
one — and still declares 0, because `p3-check` matches a dated arm syntactically: \*a line comparing
`RULES EFFECTIVE DATE` against a `Date` **literal\***. This encoding reaches the axis through a named
predicate instead:

```l4
`the rules in force include` `the Package commences`
```

which is more readable, keeps every commencement date bound once with its own `@ref`, and matches
the check's shape **nowhere**. The number the check would report is an artefact of the indirection.
Raising the floor would mean inlining date literals at call sites purely to be counted — a worse
encoding bought with a greener receipt. The 0 makes the sub-check report NOT CHECKED rather than
vacuously green, which is the honest state.

## 3. Two scopes, two different floors, on purpose

The encoding answers two questions that look like one, and they have different valid ranges:

- **"What does the Package give this child?"** — total from a **2009** birth onward, which is as far
  back as life.gov.sg's cohort table reaches.
- **"Is this child better off than under the schemes being replaced?"** — needs the Baby Bonus rate
  table, which this encoding holds only from **2015-01-01**. Below that it **refuses**: an `ASSUME`
  bottom named `` `no Baby Bonus Cash Gift rate is encoded for a birth before 2015-01-01` `` stops
  evaluation instead of quoting a rate nobody measured.

They are computed by different functions for exactly this reason. If you point a batch runner at
the comparison functions over a pre-2015 cohort, the run **stalls with an "assumed term" error, and
that is the encoding working.** `app/build-scenarios.mjs` handles it by emitting comparison
`#EVAL`s only for cohorts that have a rate table; the app renders a dash for the rest.

## 4. The `rules` pin is empty because the probe cannot see a single-rule module

`etc/go/lib/discover.mjs rules` recovers regulative-rule names from the error `l4 export --to bpmn`
emits when it cannot choose between several. `sg-childcare-leave.l4` has exactly **one** rule — the
CDCSA s 12B(8) obligation to grant and to take the leave before the relevant period ends — so the
export **succeeds** and emits BPMN, and the probe reports `BROKEN` on a module that is fine.

`pins.json` therefore pins `regulative_rules: []`, which is what the probe can establish. If you
add a second regulative rule the probe will start working and the pin should be re-measured.

## 5. Two materialised forks, and what turns on them

Both are fields of one `Interpretation` record, with the live reading carried on `TYPICALLY`:

- **F1 — `the harmonised co-matching cap counts a lifetime total`.** life.gov.sg says "from
  1 October 2027, all caps adjust to $5,000" without saying whether that counts what was already
  matched. **$5,000 per child** turns on it, concentrated on the largest families. The fork _opens_
  on 1 October 2027: before that the outgoing cap governs and both readings agree, which the case
  suite asserts.
- **F2 — `the service-duration graduation survives the merger`.** The Act gives 2–6 days graduated
  by months served; the announcement states one number per family size and is silent on part-year
  service. A half-year employee gets **4 days or 8** depending on the reading.

The **rounding under F2's live reading is the encoding's own** and is not a reading of anything: the
source gives no rule for a fractional day and `8 × 2/6` is not whole. The encoding floors, visibly.

## 6. Seven more forks are resolved at encode time, and F5 is a real gap

`F5` records that the Act's **per-child lifetime caps** (42 days of childcare leave, 12 of extended)
are **not carried into the announced arm**. They cannot survive unchanged — 8–12 days a year for
twelve years is up to 96 days against a 54-day ceiling — and the announcement does not say what
replaces them. So the announced arm answers **per relevant period only**. A parent asking "how many
days do I have left for this child, ever" gets no answer here.

## 7. Where the third finding actually comes from

The conversion report's employer-cost finding rides on **fork F7**: that the employee keeps their
gross rate and the _employer_ bears the excess above the $500 reimbursement limit. Under the rival
reading — the structure CDCSA s 12B(10) already uses — the _employee_ is capped instead, the
employer's residual is nil, and the finding becomes "high earners take a pay cut on leave days".
Either way somebody bears the excess. The fork decides who, and it is not settled.

## 8. Scope

**In:** the five money lines of the Package; the Baby Bonus Cash Gift and Large Families Scheme it
replaces; CDCSA ss 12B, 12C, 12CA (childcare and extended childcare leave, and their reimbursement).

**Out, on the record:** maternity, paternity, adoption and shared parental leave (P2 entry `M3` —
so the employer-cost finding is a **lower bound**); preschool fee reductions and the BTO ballot and
income-ceiling changes, both announced at the same Rally but stated as targets rather than rules;
and the Edusave contributions that make up the difference between the Package's "$62,000" and the
speech's "almost $70,000".
