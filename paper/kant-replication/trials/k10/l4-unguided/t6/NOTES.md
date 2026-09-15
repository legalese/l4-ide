# Notes on this encoding

## Checks run

- `JL4_LIBRARY_PATH=<repo>/jl4-core/libraries l4 check policy.l4` -> `Check succeeded.`
- `JL4_LIBRARY_PATH=<repo>/jl4-core/libraries l4 check apply.l4` -> `Check succeeded.`

`l4 check` only typechecks (no evaluation of `#EVAL`), which is what the task rules
permit. I did not run `l4 run`, `l4 batch`, or any other command that would evaluate
the nine `#EVAL` directives or otherwise reveal what `covered q1`..`covered q9`
actually return. I did not open the answer key, the queries fixture, the schema doc,
FOUNDATION.md, source-defects.md, README.md, or the `jl4/examples/legal/chubb/`
reference encodings, and did not search the web.

## Design

`policy.l4` declares one record, `Claim` (the factual circumstances of a
hospitalization for which a benefit is claimed), and a cascade of BOOLEAN-returning
rules that mirror the contract's own section numbers (1.1/1.2/1.3, 2.1), ending in a
single top-level `` `covered` `` predicate. All dates/times other than the claimant's
age are NUMBER offsets in months relative to the effective date, per the task's
instruction that no elapsed-time-between-two-dates calculation is ever needed — so
the file never touches the `DATE` type or `daydate` library at all.

Sections 1.1(1)-(2) (agreement signed, premium paid) are omitted per the task's
explicit instruction not to encode them. Section 3 (worldwide/24-7 coverage,
arbitration, governing law, currency, premium timing, policy term) is treated as
either non-restrictive (3.1: nothing to gate) or claims-procedure/boilerplate with no
bearing on substantive coverage (3.2-3.5); only 3.6 (the one-year term) feeds into
`covered`, via the automatic-cancelation-at-term-end rule.

## Judgement calls

1. **Two deadlines in 1.3, one reported number.** Section 1.3 actually states two
   distinct temporal limbs: the wellness visit itself must occur by month 6, and
   written confirmation of it must be supplied by month 7. The benchmark questions
   that mention this (Q4, Q6, Q7, Q9) only ever report a single number — "confirmation
   ... given/provided/submitted N months after the effective date." I modelled both
   limbs as separate `Claim` fields but, when populating claim data from a question
   that reports only one figure, set both fields to that same figure (i.e. assumed
   the visit and the confirmation of it were contemporaneous). This does not change
   the answer to any of the four affected questions under the numbers actually given
   (Q4's 8 fails both limbs; Q6 is excluded on skydiving regardless; Q7's 2 clears
   both limbs comfortably; Q9's 6 sits exactly on both limbs' boundary and clears
   both under an inclusive "no later than"), but a different assumption about the
   gap between visit-date and confirmation-date could matter on other fact patterns.

2. **Harmonizing 1.2 with 1.1(3).** Read completely literally and in isolation,
   1.2's "cancelation ... if the condition set out in Section 1.3 has not been
   satisfied in a timely fashion" would cancel the policy from day one — at month 1,
   the confirmation obviously has "not ... been satisfied" yet, even though nothing
   has gone wrong. That would make 1.1(3)'s express "is still pending" carve-out
   meaningless, so I read the two together: cancelation on this ground requires the
   month-7 deadline to have actually passed without a timely satisfaction, not merely
   "not yet done." (`policy canceled for a late wellness-visit confirmation` in
   `policy.l4`.)

3. **The four activity exclusions (skydiving/military/fire fighter/police) are
   causal, not statuses.** Section 2.1 excludes injury "arising directly or
   indirectly out of" the listed activities. I modelled each as a `Claim` field
   asserting that causal link (e.g. `` `due to service in the police` ``), not as "the
   claimant held that job at the time." This is the crux of Q9: the claimant was
   "serving as a police officer at the time of hospitalization," but the stated cause
   of the hospitalization is their son biting their ankle, which has no connection to
   police duties — so I set the police-service field to FALSE for that claim. By
   contrast Q1 ("while doing my duty as a firefighter") and Q8 ("injured in a
   military training exercise") both state an explicit causal link, so those fields
   are TRUE. If the intended reading is closer to "any injury to a person who is, at
   that moment, employed in one of these roles," Q9 would flip.

4. **"Accidental injury" as a substantive gate, and Q5.** 1.1 conditions payment on
   "hospitalization for sickness or accidental injury." I treated this as a real
   requirement, not a formality: a `Claim` must be for sickness or for an accidental
   injury to be within the insuring clause at all, independent of the Section 2.1
   exclusion list. For Q5 ("hospitalized for punching my own face to show off for my
   friends"), I read the deliberate act of punching oneself as neither a sickness nor
   an accidental injury — the injury arose from a voluntary act, not an accident —
   and set both flags FALSE, so the claim is not covered regardless of the (already
   fraud-free, per the question) cancelation analysis. This is the most contestable
   call in the whole encoding: the given text contains no explicit exclusion for
   intentional self-inflicted injury or horseplay anywhere in Section 2.1 (which is
   the policy's only enumerated exclusions list), so a reader who takes "accidental"
   to describe the unintended _result_ (an unplanned trip to the hospital) rather
   than requiring an unintended _act_ would instead call this covered. I do not think
   the text as given resolves this cleanly either way; I went with the narrower,
   more literal sense of "accidental."

5. **Boundary convention.** "No later than" is read inclusively throughout (`AT
MOST`, not strictly `LESS THAN`) — e.g. a wellness-visit confirmation given
   exactly at the 6- or 7-month mark counts as timely (relevant to Q9).

6. **Hospitalization time for Q4 and Q6.** Neither question states the
   hospitalization's own month-offset directly. Q4 says "I _had given_ confirmation
   ... 8 months after the effective date," which I read as placing the confirmation
   (and so the hospitalization, which prompted the claim) at or after month 8. Q6
   similarly reports the wellness-visit proof at 6.5 months with no separate
   hospitalization date. In both cases I set the hospitalization month-offset equal
   to the reported figure; in neither case does the exact value matter to the
   outcome (Q4 fails Section 1.3 outright at 8 either way; Q6 is excluded on
   skydiving regardless of timing).
