# Notes on judgment calls — vanilla cell, t7

For each question I read only `inputs/chubb-policy.txt` and `inputs/queries-blind.md`, plus the
standing preamble in TASK.md (agreement signed, premium paid on time, all unreferenced conditions
met, no unreferenced exclusions apply). Below are the points that required interpretation rather
than a mechanical lookup.

## Causal-nexus reading of the "service" exclusions (§3.1.2–3.1.4)

The exclusions read "any event causing sickness or accidental injury arising directly or
indirectly out of ... Service in the military / Service as a fire fighter / Service in the
police." I read "arising ... out of" as requiring a causal link between the professional service
and the injury, not merely that the claimant happens to hold that job.

- Q1 (burns "doing my duty as a firefighter") and Q8 (injury "in a military training exercise")
  both state the injury arose from performing the duty itself, so the exclusion applies. -> No.
- Q9 (bitten by claimant's own son, while the claimant happens to be "serving as a police
  officer") has no causal link between the bite and police duties — it reads as a domestic
  incident, with the job mentioned only as a status fact. I did not apply the police exclusion. ->
  answer depends only on the wellness-visit timing, which is satisfied.

## Q4: two independent readings, both pointing the same way

Two separate provisions bear on Q4 ("fall while traveling abroad," confirmation of wellness visit
given "8 months after the policy's effective date"):

1. §1.3 sets two deadlines: the wellness visit itself by month 6, confirmation of it by month 7.
   §1.2 deems the policy canceled if §1.3 "has not been satisfied in a timely fashion." The query
   says "I was hospitalized ... and **I had given** confirmation ... 8 months after" — the past
   perfect places the (late) confirmation before the hospitalization, so by the time of
   hospitalization the month-7 deadline had already passed without timely confirmation. Under
   §1.1, the policy is not "in effect" at the time of hospitalization.
2. Independently, §2.2 limits the Daily Hospital Income Benefit to confinement "in a hospital in
   the United States," whereas §4.1.1's 24-hour/worldwide language governs where the insured is
   *insured against risk*, not where the benefit-triggering confinement must occur. A fall while
   "traveling abroad" reads as hospitalization abroad, which §2.2 does not cover.

Both readings independently yield "No," so I treated this as a reasonably determinate answer
rather than "I do not know."

## Q5: "accidental Injury" and voluntary self-infliction

§2.1 conditions the benefit on confinement "as a result of sickness or accidental Injury." There
is no explicit exclusion anywhere in §3.1 for self-inflicted or intentional injury, so this
doesn't turn on the exclusions list — it turns on whether punching one's own face in the face to
show off is an "accidental" injury at all. I read "accidental" as requiring that the injury not
be the direct, foreseeable consequence of the claimant's own deliberate, targeted act. Throwing a
punch at one's own face is a deliberate application of force to one's own body, and resulting
injury is its direct, foreseeable consequence — not a fortuitous, unexpected event — even though
the claimant did not specifically intend to be hospitalized. On that reading it fails the basic
coverage grant in §2.1 (not "accidental"), independent of the fraud/misrepresentation question,
which the query separately forecloses. This was the closest call in the set; I concluded a
reasoned "No" rather than "I do not know" because the text does supply a workable standard
("accidental Injury") even though it doesn't spell out edge cases.

## Wellness-condition timing generally (§1.1.3, §1.2, §1.3)

Treated §1.1.3 ("the condition set out in Section 1.3 is still pending or has been satisfied in a
timely fashion") as evaluated as of the hospitalization date. If hospitalization occurs before
month 6–7 and no failure has yet occurred, the condition is "still pending" and the policy remains
in effect (Q3, at month 5). If a confirmation is supplied on or before the month-7 anniversary,
§1.3 is satisfied regardless of exactly when within that window (Q6 at 6.5 months, Q7 at 2 months,
Q9 at 6 months all treated as timely).

## Unreferenced facts

For questions that do not mention hospitalization location (Q1, Q2, Q3, Q5, Q6, Q7, Q8, Q9), I
assumed domestic/US hospitalization under the "assume all other conditions are met" preamble, so
§2.2's US-hospital limitation was only actually in play for Q4, where the query itself puts
location at issue ("traveling abroad").
