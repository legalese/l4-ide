# Notes on this encoding

## Load check

Ran (permitted by the task rules):

```
swipl -q -g halt policy.pl queries.pl
```

First attempt printed 61 `discontiguous` warnings (one family per `claim_*/2` predicate),
because `queries.pl` groups facts by claim/question (matching the block layout shown in
`inputs/TASK.md`'s own example) rather than by predicate name. No other warnings or errors
appeared alongside them — no singleton-variable warnings, no syntax errors, no undefined
procedures. I added `:- discontiguous` declarations for all 21 `claim_*/2` predicates at the
top of `queries.pl` rather than restructuring the file away from the example's per-claim
grouping. After that change, the command produces **no output at all** and exits 0. I did not
run `q1`..`q9` or call `covered/1` on anything; the load check only consults the files and
halts, it does not execute any query.

## Judgement calls

**"Still pending" under S1.3.** Section 1.1(3) says the policy stays in effect if the S1.3
condition "is still pending or has been satisfied in a timely fashion." I read "still pending"
as: the 7-month deadline for supplying written confirmation has not yet arrived, judged as of
the hospitalization month. So `section_1_3_ok/2` succeeds unconditionally when
`hospitalization_month =< 7`, and only checks the confirmation-by-month-7 /
visit-by-month-6 / qualified-provider facts when the hospitalization occurs after month 7. This
also means confirmation month, visit month and provider-qualified are _only_ load-bearing when
the hospitalization happens after the 7-month mark — I set them to compliant values in every
`queries.pl` claim regardless, so the encoding behaves the same whichever branch actually fires.

**Fraud/misrepresentation have no timing qualifier.** Section 1.2 says cancellation "will be
deemed to have occurred if there is fraud, or any misrepresentation..." with no "before the
hospitalization" or "before the claim" qualifier. I treated fraud/misrepresentation having
occurred at all (the month fact being a number rather than `none`) as disqualifying, regardless
of its relationship to `hospitalization_month`. I did not use `no_later_than` against the
hospitalization month here, since the text gives no such limit to compare against.

**Premium "paid" has no explicit deadline in the schema.** Section 4.5.1 says the premium is
due "at the signing of the policy," but the schema gives no `claim_signing_month` fact to
compare against, so there is no limit month available for `no_later_than`. I treated
`claim_premium_paid_month` as satisfied whenever it is a number (paid at all), not `none`.

**60-day post-proof-of-claim wait, approximated in months.** Section 4.2.1: "In no case shall
You seek to recover on this Policy before the expiration of sixty (60) days after written proof
of claim has been submitted." The schema's `claim_written_proof_of_claim_month` and
`claim_recovery_sought_month` are both in whole months, with no day-granularity fact available.
I approximated 60 days as 2 months (`recovery_sought_month >= written_proof_of_claim_month +
2`). None of the nine questions turn on this clause; in every `queries.pl` claim I set proof of
claim at the hospitalization month and recovery sought three months later, comfortably clearing
the 2-month gap either way.

**Arbitration as a condition precedent.** Read S4.2.1 as: if a dispute has arisen but the
parties are not yet "unable to settle" (`claim_unable_to_settle_month = none`), the arbitration
clock has not started and coverage is not yet blocked (same "still pending" shape as S1.3). Once
the parties are unable to settle, arbitration must have been _commenced_ within 3 months of that
date, **and** a valid arbitration award must have been issued, before the insurer is liable
("the issuance of a valid arbitration award shall also be a condition precedent to our
liability" — read as an additional requirement on top of, not a substitute for, timely
commencement). None of the nine questions mention a dispute, so every `queries.pl` claim sets
`claim_dispute_arisen` to `false`, which trivially satisfies this clause.

**S2.2's "hospital in the United States" is read as a real, literal requirement**, not
superseded by S4.1's "insures You twenty-four (24) hours a day anywhere in the world." I read
S4.1 as being about when/where the _insured risk_ (sickness or injury) is covered, and S2.2 as a
narrower, specific condition on the Daily Hospital Income Benefit itself: it is "only... payable
for each... day of continuous confinement in a hospital in the United States." Q4 (fall while
traveling abroad) is written to test exactly this: `claim_confined_in_us_hospital(c4, false)`,
which fails the benefit-triggering condition regardless of the S1.3 confirmation-timing issue
also present in that claim.

**Q4's hospitalization month.** The question gives only "confirmation of my wellness visit 8
months after the effective date," phrased as something already true ("I had given confirmation")
at the time of hospitalization. I read this as the confirmation preceding the hospitalization,
so I set `claim_hospitalization_month(c4, 9)` — after both the confirmation month (8) and the
7-month S1.3 deadline — so the late-confirmation fact is actually exercised by the "satisfied"
branch of `section_1_3_ok/2` rather than mooted by the "still pending" branch.

**Q6's hospitalization month**, similarly, is set to 8 (after the 7-month mark) so that the
given "proof of wellness visit provided 6.5 months after the effective date" fact is actually
evaluated by `section_1_3_ok/2` rather than being moot under the "still pending" branch. This
does not change the outcome for Q6 either way, since the skydiving cause is independently
excluded under S3.1(1).

**Q5's hospitalization_ground: `neither`, not `accidental_injury`.** "Punching my own face to
show off for my friends" is a deliberate, voluntary act, not an unintended/unforeseen event —
I read "accidental injury" as requiring the _event_ causing the injury to be accidental, not
merely the resulting hospitalization to be unwanted. The policy's S3.1 exclusion list does not
mention self-inflicted or intentional acts at all, so this can't be handled as an exclusion;
instead I encoded it as not qualifying as a hospitalization "as a result of sickness or
accidental Injury" under S2.1 in the first place, via `hospitalization_ground = neither`. The
question's "I did not commit fraud or misrepresentation" is handled by the ordinary baseline
(`fraud_month`/`misrepresentation_month` = `none`) and does not otherwise affect the outcome.

**Q9's causes list excludes `police_service`.** The claimant is "serving as a police officer at
the time of hospitalization," but the injury (the claimant's son biting their ankle) has no
causal connection to police duties. I read S3.1's "arising directly or indirectly out of...
[s]ervice in the police" as requiring some causal nexus between the injury and police-service
activity, not merely the claimant's occupation or on-duty status at the moment of injury. So
`claim_causes(c9, [])` — the police-officer detail is treated as scene-setting, not as an
arising-out-of cause, consistent with the standing preamble's "other" meaning anything not
referenced by the query.

**`claim_claim_made_setting_out_basis` and `claim_written_proof_of_claim_month` are treated as
two independent, both-required facts**, even though S2.3 ("a claim must be made... setting out
the basis") and S4.2.1 ("written proof of claim") could plausibly refer to the same underlying
formality. The schema lists them as separate facts, so `covered/1` requires both.

**Baseline/"unrelated" fact values.** For every fact not mentioned by a given question, I set a
value that is unambiguously compliant and does not trip any clause: `agreement_signed = true`,
`premium_paid_month = 0`, `dispute_arisen = false` (with the three arbitration facts set to
`none`/`false`, which is inert once `dispute_arisen = false`), `continuous_confinement_days = 5`,
`confined_in_us_hospital = true` (except Q4), `policy_term_months = 12` (matching S4.6's
one-year term), `claim_made_setting_out_basis = true`, and `fraud_month`/`misrepresentation_month
= none`. Where a question gives no hospitalization month, I used an early, unambiguously
compliant month (2, 3 or 5) except where the question's own facts required a later month to be
meaningfully evaluated (Q4, Q6, as noted above). `hospitalization_ground` defaults to `sickness`
when a question specifies age or timing but no cause (Q2, Q3), since some qualifying ground must
be supplied and the question gives no reason to prefer one over the other.
