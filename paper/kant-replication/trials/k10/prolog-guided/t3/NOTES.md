# Notes

## Load check

Ran, from the trial directory root:

```
swipl -q -g halt policy.pl queries.pl
```

Output: silent (nothing printed to stdout or stderr), exit code 0. I did not run q1..q9 or
otherwise query `covered/1` against the nine claims.

## Judgement calls

- **"Still pending" (Section 1.1(3)).** The policy is "in effect" if Section 1.3 "is still
  pending or has been satisfied in a timely fashion." I formalize "still pending" as: the
  hospitalization occurs no later than Section 1.3's own 7-month deadline
  (`section_1_3_pending/1`, using `claim_hospitalization_month` as the point in time at which
  "is the policy in effect" is being asked, per Section 1.1's opening sentence). If the
  hospitalization is at or before month 7, the condition hasn't yet failed even if
  confirmation/visit facts are absent or still outstanding; only hospitalization strictly
  after month 7 forces the stricter "was it actually satisfied in time" test.

- **Q4's hospitalization month (not stated in the question).** Q4 only gives the confirmation
  month (8, i.e. already late). To test the late-confirmation failure mode itself, rather than
  have it mooted by the "still pending" arm above, I set `claim_hospitalization_month(c4, 9)`
  — reading "I _had given_ confirmation... 8 months after" as describing something already
  completed by the time of hospitalization. This is a real judgement call: had I instead put
  the hospitalization at, say, month 3, `section_1_3_pending/1` would hold regardless of the
  (future, as of month 3) late confirmation, and the claim would come out covered.

- **Q5's hospitalization ground = `neither`.** "Punching my own face to show off" is a
  deliberate act, not an unintended one, so I did not encode it as `accidental_injury`; nor is
  it a `sickness`. I read the explicit "I did not commit fraud or misrepresentation" in the
  question as a deliberate distractor pointing away from the real issue (whether this is an
  insured event at all under Section 1.1) rather than as the dispositive fact.

- **Q9's causes = `[other]`, not `[police_service]`.** "I was serving as a police officer at
  the time of hospitalization" states an occupation/status, not a cause of the injury — the
  bite came from the claimant's own son. Section 2.1 excludes events "arising directly or
  indirectly out of ... service in the police," which requires a causal link the question does
  not supply, so I did not include `police_service` in the causes list.

- **`claim_written_confirmation_month` is what "proof of my wellness visit was
  provided/submitted" and "I had given confirmation of my wellness visit" refer to (Q4, Q6,
  Q7, Q9).** Section 1.3 only names one submitted document — the written confirmation — so all
  four are mapped to that fact, distinct from `claim_wellness_visit_month` (the visit itself).

- **Premium timing.** `claim_premium_paid_month` is treated as satisfying Section 1.1(2)
  whenever it is a number (not `none`), with no further deadline check — the contract gives no
  numeric deadline for premium payment analogous to Section 1.3's month-6/month-7 figures, and
  the standing preamble tells us to assume it was paid on time regardless.

- **Fraud / misrepresentation** are treated as an absolute bar: any month value at all (as
  opposed to `none`) cancels the policy per Section 1.2. The clause does not condition this on
  timing relative to the hospitalization, so no `no_later_than` comparison is applied to these
  two facts.

- **Arbitration award as condition precedent applies whenever a dispute has arisen**, even
  before the parties reach the "unable to settle" impasse that starts the 3-month arbitration
  clock (`arbitration_ok/1` in `policy.pl`). This is the more literal reading of "where there
  is a dispute or disagreement, the issuance of a valid arbitration award shall also be a
  condition precedent to our liability." None of the nine questions raise a dispute, so this
  does not affect any answer; all nine claims set `claim_dispute_arisen` to `false`.

- **60-day wait before recovery (Section 3.2.1) treated as 2 months**, consistent with this
  schema's month-level granularity elsewhere (`recovery_ok/1`). Not exercised by any of the
  nine questions; all nine set `claim_recovery_sought_month` to `none` (recovery not yet
  sought), which the encoding treats as not yet triggering this bar.

All 18 claim facts from `inputs/schema.md` are used somewhere in `policy.pl`, and all 18 are
set for every one of the nine claims in `queries.pl`. The two supporting predicates
(`no_later_than/2`, `arose_out_of/2`) are reproduced verbatim in `policy.pl` and are not
redefined in `queries.pl`.
