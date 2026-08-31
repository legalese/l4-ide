# Notes on this encoding

## Load check

Ran the permitted check:

```
swipl -q -g halt policy.pl queries.pl
```

First attempt was **not** silent: SWI printed ~90 `discontiguous` style-warnings (exit
code 0, no errors) because `queries.pl` groups facts by claim/question (one block per
`qN`) rather than by predicate name, so clauses of the same leaf predicate (e.g.
`confined_in_hospital/1`) are scattered through the file. Fixed by adding explicit
`:- discontiguous` directives for the nine affected predicates at the top of
`queries.pl`. Re-ran the identical command afterward: **exit code 0, zero output** —
silent, as required.

I did **not** run `q1`, ..., `q9`, or any other query against the encoding, and did not
otherwise test it against the nine questions. The only executions were the two load
checks above (`-g halt`, which consults and immediately exits before any query could
run).

## Judgement calls

- **"Accidental Injury" vs. self-inflicted/reckless acts (Q5-shaped facts).** The
  contract never defines "accidental" restrictively and Section 3 (General Exclusions)
  does not list self-inflicted, intentional, or reckless conduct as an exclusion. I
  encoded `accidental_injury/1` as a plain leaf fact with no built-in intentionality
  test, so a claim like "I injured myself doing something silly" is treated as a
  qualifying injury unless it falls under one of the five enumerated exclusions. I
  considered reading in an implicit "no intentional self-harm" carve-out (common in
  real-world hospital-indemnity policies) but rejected it as inventing a condition the
  text does not contain, which the task brief warns against.

- **Section 3.1 exclusions require a causal nexus, not mere status.** "arising directly
  or indirectly out of: Skydiving / Service in the military / Service as a fire fighter
  / Service in the police" is encoded as requiring the sickness/injury to be causally
  connected to the listed activity (`arose_from_skydiving/1`,
  `arose_from_military_service/1`, etc.), not merely that the claimant happens to hold
  that occupation, or is even nominally on duty, at the time of hospitalization. This
  matters for distinguishing "hospitalized while performing firefighting duties" (causal
  -> excluded) from "a police officer hospitalized for a cause with nothing to do with
  police work" (no nexus -> not excluded merely because of occupation).

- **Section 1.3's two deadlines, and what "still pending" is measured against.** 1.3
  actually sets two dates: the wellness visit itself must occur by the 6-month
  anniversary, and written confirmation of it must be supplied by the 7-month
  anniversary. I modeled both (`wellness_visit_month/2`, `confirmation_month/2`), but
  when a claim gives a confirmation date without separately giving the underlying
  visit's date, I treat a timely confirmation as adequate evidence the visit itself was
  timely too — the text gives no basis to assume a claimant would report confirmation of
  a visit that never happened or happened late. Separately, "condition 1.3 ... still
  pending" (1.1(3)) is judged against `hospitalization_month/2` (time of hospitalization
  relative to the effective date), since 1.1 itself frames the whole "is the policy in
  effect" question as being asked "at the time of the hospitalization."

- **2.2's "hospital in the United States" vs. 4.1.1's "anywhere in the world."** These
  two clauses sit in tension: 2.2 says the Daily Hospital Income Benefit is only payable
  for confinement "in a hospital in the United States," while 4.1.1 ("Where does Your
  Policy apply?") says the policy "insures You twenty-four (24) hours a day anywhere in
  the world." I resolved this by reading them as governing different things rather than
  as a straight contradiction: the insured *peril* (the sickness- or injury-causing
  event) is covered worldwide per 4.1.1, but the *daily indemnity* specifically requires
  the qualifying hospital confinement itself to be in a U.S. hospital, per the literal,
  more specific language of 2.2. I encoded `hospital_in_us/1` as a real, separate gating
  fact rather than collapsing it into a no-op. This did not end up being outcome-
  determinative for any of the nine questions in this benchmark (the one question
  involving travel abroad also independently fails on a late wellness-visit
  confirmation), so I flag it here rather than being confident it is the "right" reading.

- **Section 2.2's 365-day cap is a payment cap, not a coverage gate.** "payable ... for a
  period not exceeding three hundred and sixty-five (365) days" reads naturally as
  capping how many days are *compensated*, not as voiding the entire claim if
  confinement happens to run past a year. `hospitalized/1` only requires
  `confinement_days > 0`; a non-gating `payable_days/2` helper (`min(Days, 365)`) is
  provided for completeness but does not affect the `covered/1` boolean.

- **Signature, premium, and claim-notice.** Per the task brief, "the agreement has been
  signed and the premium has been paid" is assumed throughout and is not encoded at all
  (no predicate references either condition). Section 2.3's separate requirement that "a
  claim must be made to the Company" *is* encoded (`claim_made/1`), since the task brief
  does not exempt it the way it exempts signature/premium, but every query in
  `queries.pl` asserts it true, since none of the nine questions turn on a failure to
  give notice.

- **Arbitration (4.2), governing law (4.3), and currency (4.4) are not coverage-gating.**
  These are procedural/remedial provisions (how a dispute is resolved, which law
  governs, what currency payment is made in) rather than substantive conditions on
  whether a given hospitalization is covered. They are not modeled as predicates that
  `covered/1` depends on.

- **Fraud/misrepresentation and the three specific-exclusion facts
  (`arose_from_police_service/1`, `wellness_visit_month/2`) are never asserted true
  anywhere in `queries.pl`.** Combined with `fraud_or_misrepresentation/1`, these would
  have zero clauses across both files if not declared `dynamic` in `policy.pl`, which
  would raise a "procedure does not exist" error the first time `policy_canceled/1` or
  `excluded/1` tried to call them for a claim lacking the fact. All fifteen "leaf" claim-
  level predicates are declared `dynamic` in `policy.pl` for exactly this reason.
