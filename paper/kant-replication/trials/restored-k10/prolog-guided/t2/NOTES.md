# Notes

## Load check

Ran `swipl -q -g halt policy.pl queries.pl`. First attempt printed ~840 `discontiguous`
warnings (exit code 0, no errors) because `queries.pl` groups facts per claim (matching the
task's own example layout) rather than per predicate, so each `claim_*/2` predicate's clauses
are scattered across the file. Added one `:- discontiguous claim_X/2.` declaration per fact
predicate at the top of `queries.pl` (21 declarations, matching the 21 facts in
`inputs/schema.md`) to silence these; this changes no semantics, only suppresses a style
warning. Re-ran and confirmed the load is now completely silent, exit code 0.

Did not run q1..q9 or otherwise test the encoding against the nine questions, per the rules.

## Judgement calls

- **Schema has 21 claim facts, not 18.** `inputs/TASK.md`'s own worked example says
  "% ... all 18 facts", but `inputs/schema.md` (the authoritative fact vocabulary for this
  cell) lists 21 `claim_*/2` predicates. Treated `schema.md` as controlling and used all 21;
  verified every one is both referenced in `policy.pl` and defined for every claim in
  `queries.pl` (see the counting check implicit in this trial's construction — 21 facts times
  9 claims).

- **Section 2.2's "hospital in the United States" versus Section 4.1.1's "anywhere in the
  world."** Read these as compatible, not conflicting: 4.1.1 fixes where the insured peril
  (the sickness or accidental injury) may arise — anywhere — while 2.2 imposes an additional,
  benefit-specific situs requirement that the Daily Hospital Income Benefit is payable only
  for confinement in a US hospital. Encoded `confinement_ok/1` to require
  `claim_confined_in_us_hospital(C, true)` unconditionally. This is what makes the schema's
  `claim_confined_in_us_hospital` fact meaningful at all, which supports the reading.

- **The 365-day cap (Section 2.2) is not encoded as a coverage gate.** It bounds how many
  days are paid, not whether any benefit is payable, so `covered/1` (a binary "is a benefit
  payable" predicate) only requires `claim_continuous_confinement_days` to be a number >= 1,
  never comparing it to 365.

- **Section 1.3 ("condition ... is still pending or has been satisfied in a timely
  fashion").** Encoded as: satisfied-on-time (written confirmation <= month 7 AND the
  underlying wellness visit <= month 6 AND a qualified provider), OR still pending, meaning
  no confirmation is yet on record (`claim_written_confirmation_month(C, none)`) and the
  hospitalization itself falls at or before month 7. A confirmation that _is_ on record but
  late (a number that fails the month-7 check) is a completed breach and cannot fall back to
  "pending" regardless of when the hospitalization occurred — otherwise the fact that a
  question states a specific late confirmation month (as Q4's "8 months" does) could never
  matter, which would make that detail pointless to state. This also resolves what would
  otherwise be a real ambiguity in Q4 (hospitalization timing isn't given): under this
  reading it doesn't matter what hospitalization month is chosen for that claim, since a
  late, on-the-record confirmation fails Section 1.3 regardless.

- **Fraud/misrepresentation timing.** Section 1.2 cancels the policy "if there is fraud, or
  any misrepresentation..." with no stated timing qualifier, so `policy.pl` treats fraud or
  misrepresentation at _any_ recorded month as cancelling the policy outright, rather than
  only counting occurrences before the hospitalization.

- **The 60-day recovery bar (Section 4.2.1) is read in months.** The schema only offers
  `claim_written_proof_of_claim_month` and `claim_recovery_sought_month` at month
  granularity, so "sixty (60) days" is treated as two months (`RM >= PM + 2`) rather than
  invented as a new day-granularity fact outside the given vocabulary.

- **Arbitration (Section 4.2) only bites when a dispute has actually arisen.** Read
  Section 4.2.1 as entirely conditional on `claim_dispute_arisen(C, true)`: the three-month
  arbitration-commencement deadline and the valid-arbitration-award condition precedent only
  apply once there is a live dispute; absent one, `arbitration_ok/1` holds unconditionally.

- **Q4 ("hospitalized due to a fall while traveling abroad")** was read as the claimant being
  hospitalized abroad too (not just injured abroad), i.e. `claim_confined_in_us_hospital(c4,
false)`, since one would ordinarily be hospitalized wherever a disabling fall occurs while
  traveling. This is the fact pattern that exercises the Section 2.2 US-hospital requirement
  above.

- **Q5 (punching own face to "show off")** was read as `accidental_injury` (the act was
  voluntary, but the resulting hospitalization was not the intended outcome), and no listed
  exclusion in Section 3.1 covers self-inflicted or foolish conduct, so nothing in the policy
  text disqualifies it once fraud/misrepresentation are absent (as the question states).

- **Q8 ("military training exercise")** was read as squarely within the "Service in the
  military" exclusion (Section 3.1.2) — the exclusion carries no combat/live-duty
  qualifier, so a training exercise counts as service in the military arising directly or
  indirectly out of that service.

- **Q9 (bitten by claimant's own son while serving as a police officer)** was read as the
  police-service exclusion (Section 3.1.4) _not_ being triggered: being a police officer at
  the time of hospitalization is background status, not itself a cause the injury "arose
  directly or indirectly out of" — the cause is the bite. `claim_causes(c9, [other])`, not
  `[police_service]`.

- **Facts unrelated to each question** were set to values that satisfy every condition and
  trigger no exclusion, per the standing preamble in `inputs/queries-blind.md` and the task's
  own instruction to do the same (agreement signed, premium paid at month 0, no fraud or
  misrepresentation, no dispute, claim properly made, confinement in a US hospital for 5
  days, a 12-month policy term, and — where a question doesn't mention the wellness-visit
  condition at all — a wellness visit and confirmation both well inside their respective
  month-6/month-7 deadlines).
