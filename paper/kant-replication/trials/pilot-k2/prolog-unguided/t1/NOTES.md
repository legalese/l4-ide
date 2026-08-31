# Notes -- prolog-unguided / t1

## Load check

Ran the permitted load check:

```
swipl -q -g halt policy.pl queries.pl
```

Output: none (silent), exit code 0. Did not run q1..q9 or any other query against the
encoding, per the task's rules.

## Judgement calls

- **Section 1.3 has two deadlines, but the questions only ever give one number.** The text
  sets a 6-month anniversary deadline for the wellness *visit* itself and a separate 7-month
  anniversary deadline for *supplying written confirmation* of that visit. Every question that
  mentions this condition phrases it as "proof/confirmation ... provided/submitted N months
  after the effective date," which reads as the confirmation-submission date, not the
  underlying visit date -- no question ever states when the visit itself took place. Since the
  benchmark's own standing preamble says to assume anything a question doesn't reference is
  satisfied, I encoded both deadlines as separate facts (`wellness_visit_time_months/2`,
  `confirmation_submitted_time_months/2`) and asserted the visit-timing fact compliant by
  default in every claim, driving only the confirmation-timing fact from the stated figure.
  This resolves what would otherwise be a real ambiguity (e.g. Q6's "6.5 months" sits between
  the 6-month and 7-month cutoffs) in what I believe is the most textually faithful way rather
  than an arbitrary pick, but it is a judgement call and I want it visible as one.

- **Exclusions are causal, not status-based.** Section 2.1 excludes an injury "arising directly
  or indirectly out of" skydiving/military/firefighter/police service -- the cause of the
  injury has to be the listed activity, not merely the claimant's occupation at the time. This
  matters for Q9: the claimant was "serving as a police officer at the time of hospitalization,"
  but the hospitalization was caused by their son biting them, which has nothing to do with
  police duty. I did not assert `injury_arose_from_police_service` for that claim. Q8's
  "military training exercise" I did treat as "service in the military," since the exclusion
  text isn't limited to combat or deployment.

- **Section 3.2 (arbitration + 60-day pre-suit wait), 3.3 (governing law) and 3.4 (currency)
  are out of scope for `covered/1`.** These condition how a dispute is litigated or a recovery
  is sought after the fact, not whether the hospitalization is a covered loss in principle. No
  question posits a dispute, so I left them out of the coverage predicate entirely rather than
  building machinery that no query would exercise. This is a scoping judgement call, recorded
  here and in `policy.pl`'s header comment.

- **Section 3.1 (worldwide, 24-hour coverage) is encoded by omission**: there is no location- or
  time-of-day-based exclusion in `policy.pl` at all, which is itself the faithful reading (Q4's
  "traveling abroad" is therefore never a coverage bar).

- **"Still pending or has been satisfied in a timely fashion" (Sec. 1.1(3)) is collapsed into
  one satisfied/not-satisfied check.** I did not separately model a "not yet due" pending state
  distinct from "satisfied," because every claim here is given, or defaulted to, a concrete
  month figure for both Section 1.3 deadlines, so the two branches never actually diverge for
  this question set.

- Boolean "trigger" facts (the four activity exclusions, and fraud/misrepresentation/
  withholding) are asserted only when true and simply left unasserted otherwise, relying on
  `policy.pl`'s negation-as-failure -- that omission is itself the "no exclusion" / "no fraud"
  default the task asks for. The numeric month facts, by contrast, are asserted explicitly for
  every claim (using `0` where the question doesn't address them), because an unasserted
  numeric fact would make the corresponding deadline check fail outright -- the wrong default
  direction for an "assume unrelated conditions are satisfied" instruction.
