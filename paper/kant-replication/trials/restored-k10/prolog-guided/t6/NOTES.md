# Notes on this trial

## Load check

Ran exactly the permitted check:

```
swipl -q -g halt policy.pl queries.pl
```

Exit code 0, and both stdout and stderr were completely empty (checked by redirecting
each to a file and inspecting it) - no syntax errors, no "singleton variable" warnings,
no "discontiguous" warnings. I did not run q1..q9 or any other goal against the
encoding.

To keep `queries.pl` silent despite grouping each claim's 21 facts together (rather than
grouping by predicate across all nine claims), I added explicit `:- discontiguous
claim_*/2.` directives for all 21 predicates at the top of the file. Without them, SWI
prints a warning for every claim\_\* predicate the first time its clauses turn out to be
non-adjacent.

## Judgement calls in `policy.pl`

- **Section 1.3, "still pending or has been satisfied" (1.1(3)).** The written-confirmation
  deadline (month 7) and the wellness-visit deadline (month 6) are both measured from the
  policy's effective date, not from the hospitalization. But 1.1 ties "the condition is
  still pending" to a point in time, and the only clock available in the schema is the
  hospitalization month. I read "still pending" as "the month-7 deadline has not yet
  elapsed as of the hospitalization" - i.e. `claim_hospitalization_month(C,HM), HM =< 7` -
  and only require actual satisfaction (confirmation <= 7, visit <= 6, qualified provider)
  once `HM > 7`. This means an early hospitalization can be covered even if the claimant's
  wellness-visit paperwork is, as of that early date, still outstanding or even eventually
  late - which seems to be exactly the protection 1.1(3)'s disjunction ("pending OR
  satisfied") is for.
- **Fraud / misrepresentation (1.2).** I treat any fraud or misrepresentation as voiding
  the policy regardless of its month relative to the hospitalization month - the clause
  conditions cancellation on fraud/misrepresentation "in connection with any communication
  or information ... relating to this policy" generally, with no "before the loss" proviso,
  and there is no fact tying fraud to a particular claim event to test relative ordering
  against.
- **Premium paid (1.1(2), 4.5.1).** 4.5.1 says the premium is paid "at the signing," but
  the schema has no "signing month" fact to compare `claim_premium_paid_month` against, so
  `premium_paid/1` only checks that the value is a number (paid at all), not any specific
  timing.
- **Policy term boundary (1.2, 4.6).** Cancellation "at midnight ... on the last day of the
  policy term" reads as the term running through the end of its last day, so I treat
  `claim_hospitalization_month(C,HM) =< claim_policy_term_months(C,Term)` as still in force
  and only `HM > Term` as expired (strict, not `>=`).
- **Continuous confinement (2.1/2.2).** `claim_continuous_confinement_days` must be a
  number greater than 0 (there was at least one day of qualifying confinement). The 365-day
  cap in 2.2 bounds the benefit amount, not eligibility, so it is not used as a coverage
  gate.
- **Arbitration (4.2.1).** I read the arbitration machinery as engaging only once the
  parties are actually unable to settle (`claim_unable_to_settle_month` is a number, not
  `none`) - a dispute that arose but was resolved between the parties never needs an
  arbitration award. Once they are unable to settle, arbitration must be commenced within
  three months of that date (via `no_later_than/2` against `UnableToSettleMonth + 3`), and
  a valid award becomes a condition precedent to liability, per 4.2.1's last sentence.
- **The 60-day wait (4.2.1, final sentence).** "In no case shall You seek to recover on
  this Policy before the expiration of sixty (60) days after written proof of claim" is the
  closing sentence of the arbitration clause, but its wording ("in no case", "this Policy")
  reads as a general precondition to recovery rather than one scoped to disputes -
  consistent with the schema giving `claim_written_proof_of_claim_month` and
  `claim_recovery_sought_month` as ordinary, always-present claim facts rather than
  dispute-only ones. I applied it universally: `RecoverySoughtMonth >= WrittenProofMonth +
2`, translating 60 days as two 30-day months to stay on the same monthly axis as every
  other date in the schema.

## Judgement calls in `queries.pl`

Per the task, every fact not put in issue by a question is set to a value that satisfies
all conditions and triggers no exclusion (agreement signed, premium paid at month 0, no
fraud/misrepresentation, wellness-visit and confirmation both timely, no dispute, proof of
claim and recovery timed two months apart, one year policy term, confined in a US hospital
for 3 continuous days, claim made setting out its basis). Notable choices for the facts a
question _does_ put in issue:

- **Mapping "proof/confirmation of my wellness visit was provided/submitted at month X"**
  (Q4, Q6, Q7, Q9) to `claim_written_confirmation_month`, not `claim_wellness_visit_month`
  - Section 1.3 distinguishes the visit itself from the written confirmation of it that
    you supply to the insurer, and it is the latter ("provided"/"submitted" to whom the
    policy speaks of "supplying") that these questions describe. `claim_wellness_visit_month`
    is left at a baseline value on or before the given confirmation month, since no question
    separately puts the underlying visit's own date in issue.
- **Hospitalization month when not stated (Q4, Q6, Q9).** These questions describe the
  confirmation as already having happened ("I had given confirmation ...", "was provided
  ...", "was submitted ...") in the past relative to the hospitalization/claim, so I placed
  `claim_hospitalization_month` at or after the stated confirmation month rather than at an
  early baseline. This matters substantively for Q4: an early hospitalization month would
  let the late (month-8) confirmation fall under the "still pending" branch of section 1.3
  and never actually get tested, which would make the one fact the question supplies
  irrelevant to the outcome. I used month 9 for c4 (after the month-8 confirmation), month
  8 for c6 (after the month-6.5 confirmation, though here it does not change the outcome
  either way since 6.5 <= 7), and month 7 for c9 (after the month-6 confirmation, same
  non-determinative reasoning). Q7's confirmation (month 2) is comfortably timely regardless,
  so c7's hospitalization month (3) is just kept consistent with the same convention.
- **Q7's wellness-visit month.** Set to 1 (rather than the usual baseline of 3) so that the
  visit precedes its own confirmation at month 2, keeping the claim's timeline internally
  consistent.
- **Q9 - "serving as a police officer at the time of hospitalization."** I read this as
  describing the claimant's occupation/status at the time, not the cause of the injury. The
  general exclusion in 3.1 requires the sickness or injury to arise "directly or indirectly
  out of ... service in the police" - a causal nexus to the service itself - and a son
  biting his father's ankle has no such nexus merely because the father happens to be on
  the police force. So `claim_causes(c9, [other])`, not `[police_service]`. This is the one
  fact assignment in this file that is doing more than mechanically transcribing the
  question, so it is called out here explicitly as a judgement call rather than a given.
- **Q1's causal link, by contrast, is explicit** ("while doing my duty as a firefighter"),
  so `claim_causes(c1, [firefighting])` follows directly from the text with no inference
  needed.
