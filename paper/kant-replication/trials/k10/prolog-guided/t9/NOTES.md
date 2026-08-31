# Notes

## Load check

Ran the permitted load check from the trial directory:

```
swipl -q -g halt policy.pl queries.pl
```

Exit code 0, and both stdout and stderr were completely empty (checked separately by
redirecting each to its own file). No singleton-variable warnings, no discontiguous
warnings, no errors. I did **not** call q1..q9 or `covered/1` anywhere, and did not otherwise
test the encoding against the nine questions, per the rules.

## Judgment calls in `policy.pl`

- **Section 1.1(3) "still pending or has been satisfied in a timely fashion."** Modeled as:
  the condition cannot yet be a reason for cancelation while the hospitalization occurs at or
  before the 7-month anniversary of the effective date (`claim_hospitalization_month =< 7`,
  see `canceled_by_condition_1_3/1`); only once that deadline has passed does an unsatisfied
  condition 1.3 cancel the policy. I treated this as necessary to give "still pending" any
  content distinct from "satisfied" — without it, a claimant hospitalized before they've had
  the chance to take their 6-month wellness visit (`claim_wellness_visit_month = none`) would
  always be disqualified, which the "pending" language is clearly there to prevent. `none` at
  month 7 exactly is treated as still pending (`=<`, not `<`), reading "no later than the 7th
  month anniversary" as inclusive of that anniversary.
- **Fraud / misrepresentation timing (1.2).** Cancelation for fraud or misrepresentation is
  triggered only when it occurred at or before the hospitalization month
  (`canceled_by_fraud/1`, `canceled_by_misrepresentation/1`, both via `no_later_than/2` against
  `claim_hospitalization_month`). This follows 1.1's framing of everything relative to "the
  policy being in effect **at the time of** the hospitalization." I did not adopt the
  alternative reading that fraud/misrepresentation at any time (even after the hospitalization
  in question) retroactively voids an earlier, otherwise-valid claim.
- **"Material withholding of any information" (1.2).** No claim fact corresponds to this
  separately from `claim_misrepresentation_month`, so it is treated as subsumed by
  misrepresentation rather than modeled as its own trigger.
- **Section 2.1 item 5 (age >= 80).** The clause is drafted as if it continues the "arising
  directly or indirectly out of ..." list opened by items 1-4, but an age threshold cannot
  "arise out of" anything — that is a drafting seam in the source text, not a deliberate
  legal test. Modeled item 5 as its own cause-independent exclusion (`excluded_by_age/1`):
  any hospitalization at age >= 80 is excluded regardless of what it arose out of.
- **Arbitration condition precedent (3.2.1).** Modeled as binding only once
  `claim_unable_to_settle_month` is an actual month (i.e., the parties have reached an
  impasse); while it is `none`, the 3-month arbitration-commencement clock and the
  valid-award requirement are treated as not yet triggered, by analogy to how 1.1(3) treats
  condition 1.3 as pending before its own deadline. The policy text doesn't use the word
  "pending" here, so this is an extension by analogy, not a textual instruction.
- **60-day proof-of-claim delay (3.2.1, last sentence).** Modeled as a general precondition on
  `covered/1` (`recovery_timing_ok/1`), not limited to dispute/arbitration cases, since the
  sentence reads "in no case shall you seek to recover," unqualified by whether there was a
  dispute. It only bites once `claim_recovery_sought_month` is an actual month; 60 days is
  approximated as 2 months to match the schema's month-denominated (and sometimes fractional)
  facts. None of the nine questions turn on this, so the approximation has no effect on the
  answers, but I flag it since it is a real modeling choice.
- **`claim_hospitalization_ground = neither`.** Treated as an automatic disqualifier
  (`qualifying_hospitalization/1`), since 1.1 conditions payment on hospitalization "for
  sickness or accidental injury on which the claim ... is premised."

## Judgment calls in `queries.pl`

- **"Proof of my wellness visit was provided/submitted N months after the effective date"**
  (Q4, Q6, Q7, Q9): read as describing `claim_written_confirmation_month`, i.e. the written
  confirmation to the insurer, not `claim_wellness_visit_month` (the visit itself). The
  question never states when the underlying visit occurred, so — per the standing
  instruction to satisfy every condition not referenced in the question — I set the visit
  month to a compliant, unstated value (on or before month 6, qualified provider).
  - This matters most in **Q6**: confirmation at 6.5 months is inside the 7-month confirmation
    deadline, but if I had instead read "provided 6.5 months after" as the *visit's own* month,
    that visit would itself be too late (> 6 months) and would independently break condition
    1.3, on top of the skydiving exclusion. I did not adopt that reading.
- **Q4** ("I had given confirmation... 8 months after..."): the past perfect ("had given")
  relative to "was hospitalized" reads as the confirmation having already been submitted
  before the hospitalization, so I set `claim_hospitalization_month(c4, 9)` — after month 8 —
  which makes the late (> 7 month) confirmation the determinative fact under
  `canceled_by_condition_1_3/1`, rather than leaving it ambiguous by placing the
  hospitalization before month 7 (still "pending").
- **Q5** ("punching my own face to show off... hospitalized"): classified
  `claim_hospitalization_ground = accidental_injury`, treating the resulting hospitalization
  as an unintended-harm outcome even though the underlying act (throwing the punch) was
  voluntary. The policy text has no separate exclusion for intentional acts or self-inflicted
  injury, so I did not invent one or route this to `neither`. This is a genuine judgment call;
  a stricter reading ("the act was deliberate, so this isn't an *accident*") would classify it
  as `neither` and remove it from the policy's scope entirely via
  `qualifying_hospitalization/1`, with the same practical result of no benefit only if that
  reading is right — the two readings actually diverge in outcome here, which is why I'm
  flagging it explicitly rather than treating it as immaterial.
- **Q9** ("I was serving as a police officer at the time of hospitalization"): this is a
  status fact, not a causal one. The stated cause of the injury is the claimant's son biting
  their ankle, which has no connection to police service, so I set
  `claim_causes(c9, [other])` and did **not** include `police_service`. Exclusion 2.1 requires
  the injury to "arise ... out of" the excluded activity (and `arose_out_of/2` is a membership
  test over `claim_causes`), not merely to coincide with the claimant's on-duty status. I read
  this as the deliberate point of the question — distinguishing status from causation.
- **Unstated facts with no bearing on the question** (age where not given, hospitalization
  month where not given or not load-bearing, dispute/arbitration/recovery facts in all nine
  claims, `claim_fraud_month`/`claim_misrepresentation_month` where not explicitly addressed
  by the question): set to neutral values that satisfy every relevant condition and trigger no
  exclusion — e.g. age well under 80, causes not matching any of the four excluded activities,
  `none` for events that haven't happened when the hospitalization is early enough that 1.3 is
  still pending, `false`/`none` throughout the dispute/arbitration/recovery facts (no question
  mentions a dispute). This follows the task's instruction to set every fact unrelated to the
  question so that all other conditions for coverage are satisfied and no other exclusion is
  triggered.
- I did not compute or check what any `q1`..`q9` actually evaluates to — the above records my
  reasoning for *why* I chose each fact value, not a claim about the resulting truth value.
