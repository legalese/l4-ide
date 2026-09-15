# Notes

## Load check

Ran, as permitted by the task rules:

```
swipl -q -g halt policy.pl queries.pl
```

Output was silent and the exit code was 0. I re-ran it a second way (explicit `consult/1`
of each file wrapped in `catch/3`, printing any caught error) to make sure a swallowed
warning wasn't hiding behind `-q`; that run was also silent with exit code 0. I did **not**
run `q1`..`q9` or call `covered/1` on any of the nine claims, and did not otherwise test the
encoding against the questions, per rule 4.

I also did static cross-checks that don't involve running the questions: grepped that every
`claim_*` predicate name/arity used in `policy.pl` and defined in `queries.pl` matches
`inputs/schema.md`'s list exactly (21 facts, arity 2, no extras, no omissions); confirmed the
two supporting predicates appear in `policy.pl` byte-for-byte as given in the schema and are
not redefined anywhere; confirmed `policy.pl` defines no `claim_*` facts; confirmed each of
`c1`..`c9` sets all 21 facts (counted, not just spot-checked).

## Judgement calls

- **Section 1.3 "still pending or has been satisfied in a timely fashion" (S1.1(3)).** I read
  this as a snapshot test taken at the hospitalization that grounds the claim: if the
  hospitalization occurs no later than the 7-month written-confirmation deadline, the
  condition cannot yet have been breached, so it counts as "still pending" regardless of what
  the wellness-visit/confirmation facts eventually turn out to be. Once the hospitalization
  falls after month 7, the condition must actually be satisfied (visit by month 6 with a
  qualified provider, confirmation by month 7) or the policy is treated as canceled under
  S1.2. This reads S1.1's "at the time of the hospitalization" framing literally, and matches
  the ordinary insurance principle that a benefit properly triggered while a policy is in
  effect is not retroactively undone by a later, unrelated lapse.

- **`claim_hospitalization_month` for c4 (Q4).** The question ("hospitalized due to a fall
  while traveling abroad and I had given confirmation of my wellness visit 8 months after the
  effective date") never states the hospitalization month. Because my reading of S1.3 above
  makes the late confirmation (month 8, past the month-7 deadline) irrelevant whenever
  hospitalization is chosen early enough to fall in the "still pending" branch, I deliberately
  set `claim_hospitalization_month(c4, 8)` — at/after the deadline — so that the fact the
  question is plainly about (a confirmation given late) is actually exercised by `covered/1`,
  rather than being neutralized by an arbitrary, unstated choice for an unrelated-looking fact.
  I flag this because it is exactly the kind of choice that determines the answer to a
  question that is otherwise silent on the point.

- **`claim_confined_in_us_hospital` for c4.** Section 2.2 restricts the Daily Hospital Income
  Benefit to confinement "in a hospital in the United States", distinct from Section 4.1's
  "insures You ... anywhere in the world" (which I read as being about where the insured
  event may occur, not about where the resulting hospital confinement must be). Since Q4's
  narrative is "traveling abroad" with no mention of repatriation for treatment, I set this
  fact to `false` for c4 (confinement is abroad) rather than defaulting it to `true` as I did
  for every other claim. This is a reading of the narrative, not a free "favor coverage"
  choice, since the question itself supplies the location.

- **`claim_hospitalization_ground` = `neither` for c5 (Q5).** "Punching my own face to show
  off for my friends" is a deliberate, voluntary act, not an unexpected/unintended one, and
  not an illness. Section 2.1 only pays for confinement "as a result of sickness or accidental
  Injury." Since the schema's `claim_hospitalization_ground` explicitly offers `neither` as a
  value (distinct from `sickness` and `accidental_injury`), I took this to be the value the
  schema was designed for exactly this kind of fact pattern, and used it, with `covered/1`
  requiring the ground to be `sickness` or `accidental_injury`.

- **`claim_causes` for c9 (Q9), excluding `police_service`.** The claimant reports "serving as
  a police officer at the time of hospitalization," but the injury itself ("my son biting me
  in the ankle") plainly does not arise out of that service — it is a domestic incident.
  Section 3.1 excludes an event "arising directly or indirectly out of ... service in the
  police," which I read as requiring a causal link between the service and the injury, not
  merely that the claimant holds that occupation. This reading is reinforced by the
  `arose_out_of/2` supporting predicate, which tests membership in the _causes_ of the event,
  not the claimant's general status. I therefore set `claim_causes(c9, [other])`, omitting
  `police_service`.

- **Fraud / misrepresentation cancelation (S1.2) treated as timing-independent.** The policy
  text ties cancelation to the fact of fraud or misrepresentation without an explicit deadline
  or "before/after the claim" qualifier, so `fraud_or_misrepresentation/1` fires whenever
  either month fact is a number, regardless of its relationship to the hospitalization month.

- **"Material withholding of any information" (S1.2)** has no corresponding claim fact in
  `schema.md` (only `claim_fraud_month` and `claim_misrepresentation_month` exist for this
  clause). I did not invent a fact for it; it is simply not separately modeled.

- **Section 2.2's 365-day cap** ("for a period not exceeding three hundred and sixty-five
  (365) days") is modeled as a cap on how many days are compensated, not as an all-or-nothing
  coverage switch, since `covered/1` answers a yes/no "does the policy apply" question rather
  than computing an amount. `confinement_ok/1` therefore only requires a positive number of
  continuous confinement days, and does not gate on `=< 365`.

- **The 60-day pre-recovery bar (S4.2.1, last sentence)** is approximated as 2 months, to
  stay consistent with the month-granularity `claim_written_proof_of_claim_month` and
  `claim_recovery_sought_month` are given in.

- **Term-expiry cancelation (S1.2 last sentence / S4.6)** uses a strict `HospitalizationMonth

  > PolicyTermMonths` test: cancelation takes effect "at midnight ... on the last day of the
  > policy term," so hospitalization occurring on that last day itself is still within the term.

- **Heart attack (Q7) and pneumonia (Q3) encoded as `sickness`, not `accidental_injury`**;
  falls, bites, burns and skydiving/military-exercise injuries (Q1, Q4, Q6, Q8, Q9) encoded as
  `accidental_injury`. Ordinary usage: illness/medical events vs. externally-caused bodily
  harm.

For every claim, facts not drawn from the question text were set to values chosen to satisfy
all coverage conditions and avoid triggering any exclusion (agreement signed, premium paid,
no fraud/misrepresentation, no dispute, wellness visit and confirmation timely, confined in a
US hospital with a positive number of confinement days, claim made setting out its basis,
12-month policy term per Section 4.6, age well under 80 and causes not among the excluded
list where the question does not otherwise specify), except where noted above.
