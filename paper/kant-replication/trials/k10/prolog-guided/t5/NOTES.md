# NOTES

## Load check

Ran the permitted check from the trial directory root:

```
swipl -q -g halt policy.pl queries.pl
```

Exit code 0, no output (silent), as required. Also re-ran without `-q` as a diagnostic
(still only consulting the two files, never calling `q1`..`q9`) — also silent, no
warnings (e.g. no "discontiguous" or singleton-variable warnings), exit code 0. Did not
call any of `q1`..`q9`, and did not otherwise evaluate `covered/1` against the nine
questions.

## Judgement calls

- **Q5 (`claim_hospitalization_ground(c5, neither)`).** "Punching my own face to show
  off for my friends" is a deliberate, self-directed act, not a fortuitous/unforeseen
  external event, so I read it as outside "accidental injury" under Sec. 1.1 (which
  requires the claim be premised on hospitalization "for sickness or accidental
  injury"). I used `neither` rather than `accidental_injury`. This is a genuine
  interpretive fork — a fortuity-focused reading (harm to the *face* was unintended even
  though the punch was voluntary) could instead call it `accidental_injury` — and the
  policy has no explicit self-inflicted-injury exclusion to fall back on, so the outcome
  turns entirely on this one classification. I made the call independently, from the
  contract text alone (see the contamination note below).

- **Q9 (`claim_causes(c9, [other])`, not `[police_service]`).** "My son biting me in the
  ankle" while I "was serving as a police officer at the time of hospitalization" reads
  as two independent facts: the cause of the injury (an incident with the claimant's
  son), and the claimant's occupation/status at that moment. Sec. 2.1's exclusion is
  causal ("any event ... arising directly or indirectly out of ... service in the
  police"), not status-based, and nothing ties the ankle bite to police duties, so I did
  not add `police_service` to the causes list.

- **Q4's hospitalization month is not stated** ("hospitalized due to a fall ... and I
  had given confirmation of my wellness visit 8 months after the effective date"). The
  question names `claim_written_confirmation_month(c4, 8)`, which is late under Sec.
  1.3's 7-month deadline, but does not say when the hospitalization itself occurred.
  Per the task's instruction to set facts unrelated to the question so that coverage
  conditions are satisfied, I set `claim_hospitalization_month(c4, 3)` — before the
  7-month deadline — so Sec. 1.3's condition is "still pending" (Sec. 1.1(3)) as of the
  hospitalization, rather than already failed. This isolates the question to the one
  fact it actually states (the late confirmation) rather than letting my own choice of
  an unstated fact manufacture a failure. `claim_wellness_visit_month` is likewise not
  stated in Q4 (only when confirmation was *given* is); I set it to `1`, well inside its
  own 6-month deadline, so that only the confirmation-timing fact drives the outcome.
  The same "confirmation-month stated, visit-month not" pattern, and the same
  `wellness_visit_month = 1` default, is used for Q6, Q7 and Q9.

- **"Material withholding of any information" (Sec. 1.2)** has no corresponding claim
  fact in the schema (only `claim_fraud_month` and `claim_misrepresentation_month` are
  given). I treated it as not separately encodable and folded its effect into the
  misrepresentation check — i.e. `claim_misrepresentation_month` stands in for both
  "misrepresentation" and "material withholding" from Sec. 1.2.

- **Sec. 1.3 "still pending" boundary.** I encoded "still pending" as
  `claim_hospitalization_month(C, H), H < 7` (strict), so a hospitalization at exactly
  month 7 with no confirmation yet given is treated as already failed rather than
  pending. None of the nine questions land on that exact boundary, so this only matters
  if the harness probes it separately.

- **60-day arbitration recovery bar (Sec. 3.2, `recovery_timing_ok/1`).** The claim
  facts are in months; the contract's waiting period is in days. I converted 60 days to
  2 months (30-day month) rather than a fractional value. None of the nine questions
  exercise this predicate (all set `dispute_arisen = false`; the recovery-timing facts
  are set uniformly to `written_proof_of_claim_month = 1`, `recovery_sought_month = 4`,
  satisfying the bar regardless of the exact day/month conversion chosen).

- **Fraud/misrepresentation timing.** I read Sec. 1.2's cancelation trigger as biting
  only when the fraud or misrepresentation occurred *at or before* the hospitalization
  being claimed on (`no_later_than(FraudMonth, HospMonth)`), consistent with Sec. 1.1's
  "in effect at the time of the hospitalization" framing — a later fraud (e.g. during
  claims handling) would not retroactively un-cover an earlier, already-covered
  hospitalization under this reading. Not exercised by the nine questions: Q5 and Q8
  explicitly state no fraud/misrepresentation, and all other claims default
  `claim_fraud_month`/`claim_misrepresentation_month` to `none`.

- **Default/neutral values used wherever a question does not speak to a fact:**
  `claim_agreement_signed = true`, `claim_premium_paid_month = 0` (per the standing
  preamble), `claim_hospitalization_month = 3` unless the question states otherwise
  (Q3 = 5, per the question), `claim_age_at_hospitalization = 40` unless stated (Q2=78,
  Q3=65, Q6=79, Q7=75), `claim_causes = [other]` unless an excluded cause is named
  (Q1=`[firefighting]`, Q6=`[skydiving]`, Q8=`[military_service]`),
  `claim_wellness_visit_month = 1` and `claim_wellness_visit_provider_qualified = true`
  unless a reason exists to vary them (none did), `claim_written_confirmation_month = 1`
  unless stated (Q4=8, Q6=6.5, Q7=2, Q9=6), `claim_fraud_month` /
  `claim_misrepresentation_month = none` throughout, `claim_dispute_arisen = false`,
  `claim_unable_to_settle_month = none`, `claim_arbitration_commenced_month = none`,
  `claim_valid_arbitration_award_issued = true` (vacuous given no dispute),
  `claim_written_proof_of_claim_month = 1`, `claim_recovery_sought_month = 4`,
  `claim_policy_term_months = 12` (the one-year term of Sec. 3.6).

## Contamination disclosure

My session context (auto-loaded project memory, not something I searched for or opened
during this task) contains a one-line reference to a prior "Kant/Chubb replication"
project and a remark that a benchmark fixture makes one question's "gold" answer
underivable. I did not open, search for, or otherwise consult that material, and I did
not let it influence any encoding choice above (in particular the Q5 judgement call was
made from the plain text of `inputs/chubb-policy.txt` and `inputs/queries-blind.md`
alone, reasoned independently rather than recalled). Flagging this so the experiment
owner can judge whether it affects this trial's validity as a blind trial; I did not
read `bench/keys.json`, `fixtures/queries.json`, `FOUNDATION.md`, `source-defects.md`,
`README.md`, or `jl4/examples/legal/chubb/`, and did not search the web, per the trial
rules.
