# Notes -- prolog-guided / t3

## Load check

Ran the permitted check:

```
swipl -q -g halt policy.pl queries.pl
```

Output was empty on both stdout and stderr, exit code 0 -- silent, as required. I did **not**
call q1..q9 or otherwise evaluate the encoding against the nine questions.

`queries.pl` declares all 21 `claim_*/2` predicates `discontiguous` up front, since the
per-question block layout (mirroring the `q1 :- covered(c1). claim_...(c1, ...). ...` shape shown
in `inputs/TASK.md`) necessarily scatters each predicate's nine clauses across the file; without
the declaration SWI's default consultation would print "not together in the source-file"
warnings and the load would not be silent.

## Judgement calls in `policy.pl`

- **Section 1.3 "pending" vs. "failed" is evaluated as of the hospitalization month.** 1.1 ties
  being "in effect" to the policy's state "at the time of the hospitalization," and 1.1(3)
  explicitly allows the Section 1.3 condition to be merely "still pending." I read this as: a
  deadline (month 6 for the wellness visit, month 7 for the written confirmation) only causes
  cancellation once it has passed as of the hospitalization month without being met; before that,
  the condition is pending, not failed, regardless of what a fact says will eventually happen.
  This is what `section_1_3_failed/1` implements via `claim_hospitalization_month`.
- **Fraud, misrepresentation and premium payment are treated as plain occurred/not-occurred
  (or paid/not-paid) facts**, not compared against the hospitalization month the way Section 1.3
  and the arbitration clause are. The policy gives no deadline or relative-timing language for
  these (premium is paid "at the signing," fraud/misrepresentation have no stated cutoff), unlike
  Section 1.3's explicit month anniversaries and the arbitration clause's explicit 3-month window.
- **Territorial scope (4.1, "insures You ... anywhere in the world") is distinct from the
  benefit-payment condition (2.2, "confinement in a hospital in the United States").** I read 4.1
  as saying the triggering sickness/injury can happen anywhere, while 2.2 imposes an independent
  requirement that the confinement for which the benefit is paid be in a US hospital. Both are
  encoded; `covered/1` requires `claim_confined_in_us_hospital(C, true)`.
- **The age-80 exclusion (3.1 item 5) is independent of the four cause-based exclusions**
  (skydiving / military service / firefighting / police service), not a fifth item in the
  "arising out of" list. Encoded as a second `excluded/1` clause keyed only on
  `claim_age_at_hospitalization`.
- **The 365-day cap in 2.2 limits the payable period, not coverage itself**, so it is not
  enforced as an upper bound in `covered/1`; only "some positive number of continuous confinement
  days" is required (`continuous_confinement_ok/1`).
- **The 60-day recovery bar (4.2.1's last sentence) is expressed in the schema's month
  granularity as 60/30 = 2 months** (`RS < WP + 2` in `premature_recovery/1`), since the schema
  otherwise uses fractional months (e.g. 6.5) and gives no separate day-level fact.
- The contract's own cross-reference is a little off: 1.2 says the policy term is "described in
  Section 5 below," but the one-year term is actually stated in 4.6, and Section 5 (5.1/5.2) only
  gives the benefit and premium amounts. I did not try to resolve this; I simply used
  `claim_policy_term_months` as the operative fact for "the policy term" wherever the text refers
  to it, however mislabelled the internal cross-reference is.

## Judgement calls in `queries.pl` (per question)

- **Q4** ("fall while traveling abroad," confirmation given at month 8): read "traveling abroad"
  as meaning the confining hospital was not a US hospital (`claim_confined_in_us_hospital(c4,
  false)`), since that is the one fact the scenario most directly speaks to. Also placed the
  hospitalization at month 9 (after the stated month-8 confirmation and after both Section 1.3
  deadlines), on the reading that a claimant reporting an already-late confirmation is describing
  a claim being assessed after that lateness occurred, not one being assessed from some earlier,
  unstated vantage point where the confirmation might still have come in on time. Set
  `claim_wellness_visit_month(c4, 5)` (on-time) so the scenario isolates late *confirmation*
  specifically, rather than compounding it with a late visit.
- **Q5** ("punching my own face to show off," no fraud/misrepresentation): classified the ground
  as `accidental_injury` rather than `neither`. The general exclusions (Section 3) list specific
  activities but nothing for self-inflicted or foolish conduct, and ordinary insurance usage
  treats "accidental" as turning on whether the *result* (injury requiring hospitalization) was
  unintended, not on whether the underlying act was voluntary. Causes recorded as `[other]`.
- **Q6 / Q9** ("proof of my wellness visit was provided N months after..."): read this as
  describing the written-confirmation event specifically (`claim_written_confirmation_month`),
  since "proof ... was provided" parallels the policy's own language of confirmation being
  "supplied," and assumed the underlying visit occurred at essentially the same time
  (`claim_wellness_visit_month` set to the same figure). For Q6 (6.5 months) this means the visit
  itself is late against the 6-month deadline even though 6.5 is inside the 7-month confirmation
  window; for Q9 (6 months) both deadlines are met at the boundary (6 =< 6). In Q6 this judgement
  call is not outcome-determinative on its own, since the claim's causes independently include
  `skydiving`.
- **Q8** ("injured in a military training exercise"): classified as arising out of
  `military_service`, reading a training exercise as part of "service in the military" rather
  than requiring active combat or deployment.
- **Q9** ("serving as a police officer at the time of hospitalization," injury from a son's bite):
  did *not* include `police_service` in `claim_causes`. The exclusion requires the sickness or
  injury to arise "directly or indirectly out of" the listed service, not merely that the
  claimant held that occupation or was on duty when it happened; a domestic bite injury has no
  causal connection to police duties. Recorded as `claim_causes(c9, [other])`.
- **All other facts not addressed by a given question** (e.g. dispute/arbitration facts, written
  proof of claim / recovery-sought timing, provider qualification, US-hospital confinement except
  in Q4, continuous confinement days, claim-made-setting-out-basis) were set to neutral values
  that satisfy coverage and trigger no exclusion, per the standing preamble. `claim_causes` was
  set to `[]` wherever the question describes no specific precipitating activity at all (Q2, Q3,
  Q7), and to a single-element list matching the question's own scenario otherwise.
