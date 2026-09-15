# Notes

## Load check

Ran `swipl -q -g halt policy.pl queries.pl` from the trial directory. Output was silent
(nothing on stdout or stderr) and the exit code was 0. Because every `claim_*/2` predicate's
clauses are grouped by claim (one block per question, matching the layout TASK.md's example
shows) rather than grouped by predicate, each of the 21 predicates has its clauses scattered
across the file; `queries.pl` declares all 21 as `:- discontiguous` up front so this does not
produce warnings. No other checks were run: q1..q9 were not called, and `covered/1` was not
called with any claim data.

## Judgement calls

- **§1.1(3) "still pending or has been satisfied in a timely fashion."** Read as: the policy
  stays in effect through the wellness-visit/confirmation compliance window even though §1.3
  can't yet be satisfied on day one (otherwise no policy could ever be "in effect" during its
  first six months, which would be absurd). I encoded "pending" as available only when (a) the
  7-month confirmation deadline has not yet passed as of the hospitalization month, and (b)
  nothing already on record shows a deadline was missed (a wellness-visit month over 6, a
  confirmation month over 7, or an unqualified provider). Condition (b) matters: without it, an
  encoder could dodge an admittedly-late confirmation (e.g. Q4's "8 months") just by picking an
  early, unstated hospitalization month, which would make the general rule gameable rather than
  faithful. With (b), a definite recorded violation defeats "pending" regardless of the
  hospitalization month chosen. In practice this branch is inert for all nine claims: five don't
  mention the wellness visit at all (so I gave them comfortably-compliant values) and the other
  four (Q4, Q6, Q7, Q9) each resolve directly under straightforward satisfaction or definite
  breach, without needing the pending escape hatch.

- **Premium paid (§1.1(2)).** No explicit deadline is stated for premium payment beyond "paid
  in one lump sum at the signing" (§4.5.1), so I read "has been paid" (as of the hospitalization,
  per §1.1's framing) as `claim_premium_paid_month =< claim_hospitalization_month`, via
  `no_later_than/2`. All nine claims set this to month 0, which trivially satisfies it.

- **365-day confinement cap (§2.2).** Read as a cap on how many days are _paid_, not a gate on
  whether _any_ benefit is payable, so `covered/1` only requires continuous confinement to be a
  positive number of days, not that it be under 365.

- **60-day recovery-timing bar (§4.2.1, final sentence).** Read as a general condition on all
  claims ("in no case shall You seek to recover"), independent of whether a dispute arose,
  because it's phrased as an unconditional bar and the schema tracks it with its own pair of
  facts (`claim_written_proof_of_claim_month`, `claim_recovery_sought_month`) separate from the
  dispute/arbitration facts. Since the schema tracks both fields in whole months rather than
  days, 60 days was approximated as 2 months (`recovery_sought_month >= written_proof_of_claim_month + 2`).
  All nine claims use month 1 and month 4 respectively, well clear of that bar.

- **Arbitration conditions (commencement within 3 months; valid award required), §4.2.1.** Read
  as conditional on `claim_dispute_arisen = true`, since the whole clause opens with "If any
  dispute or disagreement arises." All nine claims set `claim_dispute_arisen = false`, so this
  machinery is inert throughout.

- **Hospitalization ground per question.** Pneumonia (Q3) and a heart attack (Q7) were encoded
  as `sickness` (internal medical events, not external trauma). Burns from firefighting (Q1), a
  fall (Q4), a skydiving injury (Q6), a military-training injury (Q8), and a bite (Q9) were
  encoded as `accidental_injury` (external physical trauma). Punching one's own face "to show
  off" (Q5) was encoded as `neither`: it's a deliberate, non-medical act, not a sickness and not
  an accident, and the schema's inclusion of a third `neither` value alongside `sickness` /
  `accidental_injury` reads as existing precisely to capture this kind of case. Q2 states only an
  age, with no medical detail, so I gave it a neutral qualifying ground (`sickness`) so that age
  is the only variable actually in play, per the "set unrelated facts non-restrictively"
  instruction.

- **Q9's "serving as a police officer at the time of hospitalization."** Read as a status, not a
  cause. §3.1 excludes events "arising directly or indirectly out of ... service in the police,"
  which requires the injury to be causally connected to police duties. A son biting his parent's
  ankle isn't caused by the parent's occupation, so I did not include `police_service` in Q9's
  `claim_causes`. This is in deliberate contrast to Q1 (burns "while doing my duty as a
  firefighter" — causally arising from firefighting), Q6 ("injury sustained while skydiving"),
  and Q8 ("injured in a military training exercise"), all of which state a causal link to the
  excluded activity and so do carry the corresponding entry in `claim_causes`.

- **Distinguishing the wellness visit itself from the written confirmation of it.** §1.3 sets two
  separate deadlines: the visit (with a qualified provider) by month 6, and written confirmation
  of it by month 7. Q4 ("I had given confirmation of my wellness visit 8 months after..."), Q6
  ("proof of my wellness visit was provided 6.5 months after..."), Q7 ("proof of the wellness
  visit was submitted 2 months after..."), and Q9 ("proof of my wellness visit was provided 6
  months after...") were all read as stating the _confirmation_ month (the act of giving/
  providing/submitting proof), not the underlying visit's own month, by analogy to Q7's
  unambiguous "submitted." None of the four questions state the visit's own month, so I set it to
  a value comfortably inside the 6-month deadline and at or before the stated confirmation month.

- **Q4's unstated hospitalization month.** Q4 gives a confirmation month (8, already past the
  7-month deadline) but no hospitalization month. "I had given confirmation ... 8 months after"
  is past-perfect relative to "I was hospitalized," so I placed the hospitalization after month
  8 (chose month 9). This also ensures the claim is decided on its evident merits (a genuinely
  late confirmation) rather than on an arbitrarily early hospitalization date that would let the
  "still pending" branch paper over an already-recorded deadline miss.

## Structure

`policy.pl` contains only `covered/1` and its helper rules, plus `no_later_than/2` and
`arose_out_of/2` reproduced verbatim from `inputs/schema.md`; it defines no claim facts.
`queries.pl` defines `q1/0`..`q9/0` and, for each, all 21 `claim_*/2` facts from the schema —
no more, no fewer.
