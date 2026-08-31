# Notes

## Load check

Ran, from the trial directory root:

```
swipl -q -g halt policy.pl queries.pl
```

First attempt printed a long series of `discontiguous` warnings (each of the 18
`claim_*/2` predicates has its clauses spread across the nine per-question blocks in
`queries.pl` rather than grouped together) — no errors, exit code 0. I added
`:- discontiguous claim_*/2.` declarations for all 18 predicates at the top of
`queries.pl` to suppress these. Re-ran the same command afterward: no output at all,
exit code 0. Did not run `q1`–`q9` or any other query at any point.

## Judgement calls

- **"Still pending or ... satisfied in a timely fashion" (§1.1 item 3, §1.3).** I read
  this as a disjunction evaluated as of the hospitalization: either (a) the 7-month
  deadline for supplying written confirmation has not yet arrived as of the
  hospitalization month (`no_later_than(HospitalizationMonth, 7)` — "still pending", so
  nothing has yet failed and a hospitalization that already occurred while the policy
  was validly in force cannot be retroactively un-covered by a later lapse), or (b) the
  condition was actually met: confirmation given no later than month 7, the wellness
  visit itself occurring no later than month 6, with a qualified provider. This lets the
  same `no_later_than/2` predicate serve all three deadline checks in the policy
  (months 6, 7, and the term length). The alternative reading — that any confirmation
  later than month 7 cancels the policy regardless of when the hospitalization occurred
  — would make §1.1 item 3's "still pending" carve-out meaningless, since a claim's
  eventual (or eventual lack of) confirmation would always be knowable in the fact
  pattern; I judged the "still pending" branch is only usable by tying it to the
  hospitalization month.

- **Fraud / misrepresentation (§1.2).** Modeled as an unconditional bar: any recorded
  month value (as opposed to `none`) for `claim_fraud_month` or
  `claim_misrepresentation_month` voids coverage outright, regardless of its value
  relative to the hospitalization month. The text ("Cancelation will be deemed to have
  occurred if there is fraud, or any misrepresentation...") gives no temporal
  qualification, unlike the wellness-visit condition, so I did not add one.

- **60-day proof-of-claim waiting period (§3.2.1).** The fact schema only supplies
  month-granularity facts (`claim_written_proof_of_claim_month`,
  `claim_recovery_sought_month`), with no day-level fact available. I converted "sixty
  (60) days" to 2 months for the `no_premature_recovery/1` check, as the nearest
  workable unit given what the schema provides. None of the nine questions exercise
  this clause.

- **Arbitration (§3.2.1).** Modeled `arbitration_ok/1` as: no bar at all if no dispute
  has arisen; otherwise a valid arbitration award must have been issued, and — once the
  parties are unable to settle — arbitration must have commenced within 3 months of
  that point. None of the nine questions mention a dispute, arbitration, or proof of
  claim, so in `queries.pl` I set `claim_dispute_arisen` to `false` and the related
  facts to `none`/`false` for all nine claims, per the standing preamble's instruction
  to assume anything not referenced by the question is satisfied.

- **`claim_hospitalization_ground`.** Set to `sickness` for illness-type facts
  (pneumonia in Q3, heart attack in Q7) and `accidental_injury` for trauma-type facts
  (burns, a fall, a punch, a skydiving injury, a training-exercise injury, a bite — Q1,
  Q4, Q5, Q6, Q8, Q9). Q2 states only an age, with no stated cause of hospitalization;
  since the ground itself is not at issue in that question, I defaulted it to
  `sickness` as an arbitrary non-`neither` placeholder.

- **Q4 — hospitalization month not stated.** The question gives only
  `claim_written_confirmation_month(c4, 8)` (one month past the §1.3 deadline) and says
  nothing about when the hospitalization occurred. I deliberately set
  `claim_hospitalization_month(c4, 8)` — i.e., *after* the 7-month deadline — rather
  than defaulting to an early month that would trigger the "still pending" branch above
  and make the stated late confirmation irrelevant to the outcome. I judged that
  letting an unstated fact silently moot the one fact the question does state would be
  the less faithful encoding of the two; a different, earlier choice of hospitalization
  month would flip `covered(c4)` via the "still pending" carve-out. This is the most
  consequential judgement call in this trial.

- **Q9 — occupational status vs. causation.** The question states the claimant "was
  serving as a police officer at the time of hospitalization," but the stated cause of
  the injury is "my son biting me in the ankle." The general exclusion in §2.1(4) is
  for sickness or injury "arising directly or indirectly out of ... service in the
  police," i.e., it excludes by causation, not by the claimant's occupation or status at
  the time. Since the bite did not arise out of police service, I set
  `claim_causes(c9, [other])`, deliberately omitting `police_service` from the list.

- **`claim_causes` default.** Wherever a question does not implicate any of the four
  excluded activities, I used `[other]` (the schema's explicit catch-all enum value)
  rather than the empty list `[]`. Both behave identically against
  `arose_out_of/2`/`memberchk/2`; `[other]` seemed the more complete representation of
  "the event arose out of some ordinary, non-excluded cause."

- **Premium payment.** No explicit deadline is stated in the contract text for when the
  premium must be paid other than "at the signing of the policy" (§3.5.1), and the
  standing preamble instructs assuming it was paid on time for every question, so
  `premium_paid/1` in `policy.pl` only checks that a month value is on record (not
  `none`), and every claim in `queries.pl` sets `claim_premium_paid_month` to `0`
  (paid at signing, i.e., the effective date).
