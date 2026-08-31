# Notes

## Load check

Ran the permitted check:

```
swipl -q -g halt policy.pl queries.pl
```

Exit code 0. Captured stdout and stderr separately (not just visually inspected) — both were
0 bytes. No output, no warnings (in particular, no `discontiguous` or singleton-variable
warnings), no errors. I did not call any of `q1`..`q9`, `covered/1`, or otherwise query the
loaded database — only the load-and-halt check above.

## Schema note

`schema.md` lists 21 claim facts (not the 18 implied by the truncated example in `TASK.md`,
which is clearly just an illustrative snippet). I used all 21, per schema.md's own "Use ALL
OF, and ONLY, these" instruction, and `covered/1` in `policy.pl` references every one of them
either directly or via a helper predicate.

## Judgement calls in `policy.pl`

- **Fraud / misrepresentation timing (Sec. 1.2).** Section 1.3's deadlines are explicit
  (6-month / 7-month anniversaries), but the fraud/misrepresentation prong of 1.2 carries no
  stated deadline. I did not gate `fraud_occurred`/`misrepresentation_occurred` on having
  happened by the hospitalization month — occurrence at *any* time voids the policy. This
  also seems necessary on the merits: fraud committed in the course of making the claim
  itself (necessarily after the hospitalization) must still be able to void the claim, so
  gating on "before the hospitalization" would be wrong.
- **`claim_misrepresentation_month` covers two prongs.** The schema has no separate fact for
  "material withholding of information," so I read `claim_misrepresentation_month` as
  standing in for both "misrepresentation" and "material withholding" in 1.2 — they're
  disjoined together in the contract text with no distinguishing fact available.
- **Section 1.3 "still pending" (Sec. 1.1(3)).** Modeled as: the 7-month confirmation
  deadline has not yet passed as of the hospitalization month (`no_later_than(HospMonth, 7)`).
  I did not attempt to detect the finer case where the visit's own 6-month deadline has
  already passed without a visit, making eventual timely confirmation impossible even though
  the outer 7-month clock hasn't run out — none of the nine questions turn on that edge case,
  and the schema doesn't obviously ask for it.
- **1.1(3) and 1.2 folded into one check.** 1.1 requires the 1.3 condition to be "pending or
  satisfied," and 1.2 cancels the policy when that same condition "has not been satisfied in
  a timely fashion." These are logical mirror images of each other, so `policy_in_effect/1`
  checks `\+ canceled(C)` only, and `canceled/1` is where `\+ condition_1_3_ok(C)` actually
  lives, rather than repeating the same test as an independent top-level conjunct.
- **60-day recovery bar (Sec. 4.2.1) converted to 2 months.** The schema's clock is
  month-denominated throughout (including the 7-month and 6-month deadlines that plainly
  correspond to "months" in the contract), so I treated the contract's "sixty (60) days" as
  2 months for unit consistency with `claim_recovery_sought_month` / `claim_written_proof_of_claim_month`,
  rather than introducing a day-based check that nothing else in the schema uses.
- **`recovery_sought_month = none` is not a violation.** The 60-day bar only bites if the
  claimant has actually tried to seek recovery early; not yet having sought recovery at all
  is not itself non-compliant. But seeking recovery (a number) while
  `written_proof_of_claim_month = none` fails outright, via `no_later_than`'s built-in
  failure on `none` — read as: the 60-day clock never started, so recovery is always
  premature.
- **Section 2.2's "hospital in the United States" is a hard requirement**, encoded via
  `claim_confined_in_us_hospital`. I did not encode the 365-day cap as invalidating coverage
  entirely for longer confinements — the cap only limits how many days are compensated, not
  whether the claim is "covered" at all, and the questions ask "will my policy apply," not
  "will every day be paid."
- **Premium timing (Sec. 4.5 vs. 1.1(2)).** 4.5 says the premium is paid "in one lump sum at
  the signing of the policy," which could be read as requiring exact payment at time zero.
  I instead required only `premium_paid_month =< hospitalization_month` (i.e., paid by the
  time of the event), treating 4.5 as describing payment mechanics (lump sum, not
  installments) rather than adding a stricter eligibility deadline on top of 1.1(2)'s plain
  "has been paid." This is moot for all nine queries either way, since the standing preamble
  stipulates the premium was paid on time.
- **`claim_causes` uses `other` rather than `[]` for a non-excluded cause.** The schema
  enumerates `other` alongside the four exclusion-triggering atoms, which reads as intended
  for exactly this purpose, so I never used an empty list.

## Judgement calls in `queries.pl`

- **Q4 (fall while traveling abroad; "I had given confirmation... 8 months after").** The
  past-perfect "had given" (contrasted with the simple past "was hospitalized") reads as the
  confirmation preceding the hospitalization, so I set `claim_hospitalization_month(c4, 9)` —
  after the missed 7-month deadline — rather than an earlier month that would have left the
  condition merely "pending" at the time of hospitalization. Separately, "traveling abroad"
  describes where the fall happened, not stated to be where the hospitalization/confinement
  itself occurred, so I set `claim_confined_in_us_hospital(c4, true)` as an unreferenced,
  satisfying fact. That second call is not outcome-determinative: the late confirmation
  alone already fails `condition_1_3_ok`.
- **Q5 (punching own face to show off for friends).** Set
  `claim_hospitalization_ground(c5, neither)`: a deliberate, self-inflicted act is not
  "accidental" in the ordinary insurance sense (accidental injury excludes intentional
  self-harm), and it is plainly not "sickness" either. The schema's third ground value,
  `neither`, appears to exist specifically for a scenario like this one — none of the other
  eight questions has any natural use for it.
- **Q9 (son biting me in the ankle while serving as a police officer).** Set
  `claim_causes(c9, [other])`, not `[police_service]`: the exclusion requires the injury to
  arise "directly or indirectly out of" police service, and a family member's bite has no
  causal connection to the claimant's job — it is incidental that they happened to be on
  duty. I read the query's phrasing ("serving as a police officer *at the time of*
  hospitalization" — a status, contemporaneous but not causal) as deliberately distinct from
  Q1's and Q8's causal phrasing ("while doing my duty as a firefighter," "injured in a
  military training exercise").
- **Unstated hospitalization months (Q4, Q6, Q7, Q9)** and **unstated ages (Q1, Q4, Q5, Q8,
  Q9)** were filled with unreferenced, satisfying values (e.g. age 40; a hospitalization
  month consistent with the stated timeline) per the standing preamble's instruction to treat
  anything not referenced in the question as met.
- **`claim_policy_term_months` fixed at 12 for every claim**, matching Sec. 4.6's one-year
  term — this is a fact about the policy itself, not something that should vary claim to
  claim, since all nine questions concern the same policy.
