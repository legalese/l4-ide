# Notes on this encoding

## Load check

Ran, as permitted:

```
swipl -q -g halt policy.pl queries.pl
```

First attempt produced 17 `discontiguous` warnings (no errors, exit code 0) because
`queries.pl` groups facts by claim/question rather than by predicate, so predicates like
`accidental_injury/1` and `confirmation_time/2` get clauses scattered through the file.
Added explicit `:- discontiguous ...` directives for the six per-claim predicates that
`queries.pl` defines facts for (`sickness/1`, `accidental_injury/1`,
`hospitalization_time/2`, `age_at_hospitalization/2`, `confirmation_time/2`,
`arises_out_of/2`). Re-ran and the load is now completely silent, exit code 0.

I did not run `q1` through `q9`, and did not otherwise query the encoding against the
nine questions, per the rules.

## Judgment calls

1. **The two Section 1.3 deadlines collapse to one check.** Section 1.3 actually names two
   dates: the wellness *visit* must occur no later than the 6-month anniversary, and
   *written confirmation* of it must be supplied no later than the 7-month anniversary.
   None of the nine questions ever gives two separate figures for this — each gives a
   single "proof/confirmation provided/submitted at N months" figure (Q4: 8, Q6: 6.5, Q7:
   2, Q9: 6). Since there is no separate "visit occurred at" fact available anywhere, I
   check that single figure against the 7-month confirmation deadline only
   (`wellness_condition_violated/1` in `policy.pl`). This also fits the task's instruction
   that no query ever needs a calculation between two dates — the design reads as
   comparing one given figure against one fixed threshold, not reconciling two.

2. **"Arising out of" an excluded activity means causation, not mere status.** Section
   2.1 excludes sickness/injury "arising directly or indirectly out of" skydiving,
   military service, firefighting, or police service. I read this as requiring the
   activity to be the actual cause of the injury, not just a fact about the claimant's
   job or on-duty status at the time. This distinguishes Q1 and Q8, where the activity
   itself produced the injury ("burns suffered while doing my duty as a firefighter",
   "injured in a military training exercise" — both asserted via `arises_out_of/2`), from
   Q9, where the claimant states he "was serving as a police officer at the time of
   hospitalization" but the injury was "due to my son biting me in the ankle" — a cause
   with no connection to police duty. For Q9 I deliberately do NOT assert
   `arises_out_of(claim_9, police_service)`, so the police-service exclusion does not
   fire. This is the most consequential interpretive call in the encoding, since the
   two readings (status vs. causation) produce opposite answers for Q9.

3. **"Punching my own face to show off for my friends" (Q5) is treated as an accidental
   injury the policy can cover**, i.e. not excluded. Section 2.1's general exclusions are
   a specific, enumerated list (skydiving, military service, firefighting, police
   service, age ≥ 80); there is no catch-all exclusion in the given text for
   intentional acts, horseplay, or self-inflicted injury. I read the enumerated list as
   exhaustive on its own terms (expressio unius est exclusio alterius) rather than
   importing an unstated "no intentional/self-inflicted injury" exclusion, especially
   since the question itself only raises fraud/misrepresentation as a possible
   objection and then rules that out. I did not encode any special "self-inflicted"
   predicate; `accidental_injury(claim_5)` is simply asserted true and nothing in
   `policy.pl` treats intentionality as disqualifying.

4. **Classifying each hospitalization as "sickness" vs. "accidental injury."** The
   contract distinguishes the two but never defines either. I classified pneumonia (Q3)
   and heart attack (Q7) as `sickness/1`, and falls, bites, skydiving injuries, burns,
   and military-exercise injuries (Q1, Q4, Q5, Q6, Q8, Q9) as `accidental_injury/1`.
   Nothing in the encoding actually depends on which of the two labels is used — both
   feed the same `hospitalization_event/1` disjunction — so this classification is for
   faithfulness/readability rather than because it changes any outcome.

5. **Q2 has no stated cause of hospitalization at all** ("will my policy apply if I am 78
   years old at the time of hospitalization?"). Since Section 1.1 only pays for
   hospitalization "for sickness or accidental injury", *some* such fact has to be true
   for coverage to be possible in principle. I asserted `sickness(claim_2)` as a neutral
   placeholder standing in for "some unspecified, non-excluded sickness", since the
   question is entirely about the age exclusion and gives no other detail to encode.

6. **Facts not mentioned by a question are omitted, not defaulted to an explicit value.**
   Every per-claim predicate in `policy.pl` is declared `:- dynamic`, and every rule that
   consumes one is written so that its absence means "does not block coverage" (no
   exclusion, no cancelation). So, per the task's instruction to set unrelated
   conditions/exclusions to whatever keeps the policy applying, `queries.pl` simply
   asserts nothing for facts a question does not raise, rather than asserting an
   explicit "safe" value for every possible predicate on every claim.

7. **Signing and premium payment are not modeled at all**, per the task's instruction
   that these should be assumed and need no rules or facts.

8. **Arbitration, governing law, and currency-of-payment terms (Sections 3.2-3.5) are not
   encoded as coverage conditions.** They are procedural/remedial provisions (how a
   dispute gets resolved, what law governs, what currency payment is made in) rather
   than conditions on whether the policy applies to a given hospitalization, and none of
   the nine questions references them.
