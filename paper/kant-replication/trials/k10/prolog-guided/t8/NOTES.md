# Notes

## Load check

Ran (as permitted, nothing else):

```
swipl -q -g halt policy.pl queries.pl
```

Exit code 0. Both stdout and stderr were empty (verified by redirecting each to a file and
checking size: 0 bytes). No singleton-variable or discontiguous-clause warnings. `queries.pl`
declares the 18 `claim_*/2` predicates `discontiguous` up front, since each is asserted once
per claim block (grouped by claim, per the TASK.md example) rather than grouped by predicate.

I did not run `q1`..`q9`, `covered/1`, or any other goal against the encoding.

## Judgement calls on what the policy means

- **S1.3 "still pending" vs "satisfied in a timely fashion" (S1.1(3)).** Section 1.3 states
  one operative deadline for action (supply written confirmation no later than month 7) of a
  fact that itself has an earlier sub-deadline (the visit itself, no later than month 6). I
  treated the two as a single compound condition whose "is it due yet" cutoff, as evaluated at
  the moment of hospitalization, is the outer month-7 deadline: if hospitalization occurs
  before month 7, the condition is "still pending" and the policy remains in effect regardless
  of the wellness-visit/confirmation facts; at or after month 7, both the visit (<=6) and the
  confirmation (<=7), with a qualified provider, must actually hold. An alternative reading
  would split "pending" at month 6 for the visit sub-part; I did not adopt it because S1.1(3)
  refers to "the condition set out in Section 1.3" as one item, governed by the deadline
  stated at the top of that section.

- **Premium timing (S1.1(2)).** The clause just says the premium "has been paid," with no
  explicit deadline of its own. I required it to be paid no later than the hospitalization
  month (`no_later_than(PremiumMonth, HospMonth)`), consistent with the "in effect at the time
  of the hospitalization" framing in S1.1 and with the schema's month-based-fact pattern used
  elsewhere. All nine queries set this to month 0 per the standing preamble ("premium paid on
  time"), so this choice does not affect any of the nine answers.

- **Fraud / misrepresentation (S1.2).** Unlike S1.3, this clause carries no "no later than"
  qualifier — cancellation is "deemed to have occurred if there is fraud, or any
  misrepresentation ... in connection with any communication or information relating to this
  policy," with no stated timing relative to the hospitalization. I therefore treated any
  non-`none` value of `claim_fraud_month` or `claim_misrepresentation_month` as an unconditional
  cancellation trigger, regardless of whether it falls before or after the hospitalization
  month.

- **60-day wait before seeking recovery (S3.2.1, last sentence).** The schema's
  `claim_written_proof_of_claim_month` / `claim_recovery_sought_month` facts are
  month-denominated, but the contract states the wait in days. I converted 60 days to 2
  months. I also read this sentence as applying to every claim, not only ones where a dispute
  has arisen — it is not textually scoped to "where there is a dispute or disagreement" the way
  the sentence immediately before it is.

- **Q5 (hospitalized for punching own face to show off).** A deliberate act done for show is
  not an "accident," so I encoded `claim_hospitalization_ground = neither` rather than
  `accidental_injury`. That is what disqualifies the claim in my encoding — none of the five
  S2.1 exclusions mention self-inflicted or intentional injury, so the schema's `neither` value
  for `claim_hospitalization_ground` is the only mechanism available for excluding an event
  that is not a sickness and not an accident in the first place. The question's assurance that
  "I did not commit fraud or misrepresentation" heads off the S1.2 cancellation route,
  consistent with the standing preamble that other conditions are met.

- **Q9 (son biting claimant's ankle while claimant was serving as a police officer).** S2.1(4)
  excludes injury "arising directly or indirectly out of ... service in the police" — a
  causation requirement, not mere contemporaneous employment status. Since the stated cause is
  a family member's bite, unconnected to police duties, I did not add `police_service` to
  `claim_causes` for this claim (used `[other]` instead). This is a deliberate contrast with Q1
  (burns suffered "while doing my duty as a firefighter," i.e. explicitly caused by the duty),
  where I did add `firefighting` to `claim_causes`.

- **Filling in facts a question does not mention.** Per the standing preamble ("assuming all
  other conditions are met and no other exclusions apply"), unmentioned facts were set to
  whichever value most favors coverage. One specific choice worth flagging: where a question
  named a specific wellness-visit-related month (a confirmation/proof month) but not a
  hospitalization month (Q4, Q6, Q7, Q9), I set `claim_hospitalization_month` to a value after
  that named month, so the S1.3 "satisfied" branch is actually exercised by the stated fact
  rather than being mooted by an early "still pending" hospitalization. Q3 gives its
  hospitalization month directly (month 5), so no such choice was needed there.

- **Mapping "proof of my wellness visit was provided/submitted" and "I had given confirmation
  of my wellness visit" (Q4, Q6, Q7, Q9).** Read all of these as the act of supplying written
  confirmation to the insurer, i.e. `claim_written_confirmation_month`, not
  `claim_wellness_visit_month` (the date of the underlying visit itself, which none of those
  four questions separately states — left at a favorable default).

## Scope compliance

Read only the four files under `inputs/` in this trial directory (`TASK.md`,
`chubb-policy.txt`, `queries-blind.md`, `schema.md`). Did not open any file under
`paper/kant-replication/` outside this trial directory, did not open `jl4/examples/legal/chubb/`,
and did not search the web.
