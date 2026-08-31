# Notes on this encoding

## Load check

Ran the permitted load check:

```
swipl -q -g halt policy.pl queries.pl
```

Output: none (stdout and stderr both empty), exit code 0. Silent, as required. I did not run
`q1` through `q9`, and did not otherwise query the encoding against the nine questions.

## Judgement calls

1. **Section 1.3 timing collapsed to a single deadline.** Section 1.3 actually imposes two
   dates: the wellness visit itself must occur by the 6-month anniversary, and written
   confirmation of it must reach the Company by the 7-month anniversary. None of the nine
   questions ever states when the underlying visit occurred, only when confirmation/proof was
   "provided" or "submitted." I treated confirmation timing as dispositive of Section 1.3 as a
   whole and checked it only against the 7-month mark. `policy.pl`'s `section_1_3_ok/1`.

2. **"Still pending" default.** Section 1.1(3) allows the Section 1.3 condition to be either
   "still pending" or "satisfied in a timely fashion." I read "still pending" as: the 7-month
   deadline has not yet passed as of the hospitalization. When a question gives neither a
   confirmation month nor a hospitalization month, this defaults to "pending, fine," per the
   instruction to treat conditions unrelated to the query as satisfied. See
   `overdue_without_confirmation/1`.

3. **"Accidental injury" requires the injury itself to be unintended (Q5).** This is the
   highest-stakes call in the encoding. The policy never defines "accidental," and Section 3.1's
   five enumerated exclusions do not include self-inflicted or intentional injury. I nonetheless
   read "accidental Injury" in Section 2.1 as requiring that the injury be unintended, so that an
   injury which is the direct, intended physical consequence of the claimant's own deliberate act
   against themselves (Q5: punching one's own face on purpose) fails the basic peril definition
   before any exclusion is even reached. I distinguished this from an injury sustained *while*
   engaged in a voluntary but legal activity such as skydiving (Q6): there the activity is
   intentional but the injury is not, so it remains "accidental" and is instead handled by the
   named Section 3.1(1) exclusion. An opposing, more literal reading is available: since Section 3
   is captioned "GENERAL EXCLUSIONS" and enumerates a closed list that does not mention
   self-inflicted or intentional injury, a stricter textualist might argue Q5's injury is
   "accidental" in the loose sense of "not a listed exclusion" and so is covered. I did not adopt
   that reading, for the reason given above, but flag it as genuinely contestable.

4. **Section 3.1 exclusions require causation, not status (Q9).** "[A]rising directly or
   indirectly out of ... [s]ervice in the military / ... fire fighter / ... police" is read as
   requiring an actual causal link between the sickness/injury and the named activity, not merely
   that the claimant holds that job. Q9's claimant is a police officer, but the injury (the
   claimant's son biting their ankle) has no connection to police duties, so I did not assert the
   police-service exclusion fact for that claim. By contrast Q1 ("burns ... while doing my duty as
   a firefighter") and Q8 ("injured in a military training exercise") state the causal link
   explicitly, so those exclusions are asserted.

5. **Section 2.2's "hospital in the United States" read as an independent gate on the benefit,
   separate from Section 4.1's worldwide scope (Q4).** Section 4.1 says the policy "insures You
   twenty-four (24) hours a day anywhere in the world," while Section 2.2 says the Daily Hospital
   Income Benefit "will only be payable for ... confinement in a hospital in the United States." I
   read these as consistent rather than contradictory: the insured event (sickness or injury) can
   happen anywhere in the world, but the confinement for which the benefit is actually paid must
   be in a US hospital. Q4's phrase "hospitalized due to a fall while traveling abroad" is
   ambiguous about whether the hospital stay itself was abroad or only the fall that caused it; I
   read it as the former (confinement abroad), since that is the reading under which Section 2.2's
   US-hospital clause has any work to do. Q4 also independently fails on the Section 1.3 deadline
   (confirmation at month 8, one month late), so the encoding's answer for Q4 does not turn on this
   call alone.

6. **Not modelled as coverage gates at all:** Section 1.1(1)-(2) (signature and premium payment)
   and Section 4.5 (premium mechanics) per the task's explicit instruction; Section 2.3 (a claim
   must be made to the Company), since every one of the nine questions is itself framed as a
   hypothetical claim; Section 4.2 (arbitration as a condition precedent), since it only bites once
   a dispute exists and none of the nine questions posits one; Sections 4.3-4.4 (governing law,
   currency) as non-substantive; and Section 2.2's 365-day confinement cap, since it bounds how
   many days are paid rather than gating whether the policy applies at all, and no question turns
   on confinement duration.

## Design notes (not judgement calls about the contract, but about the encoding)

- `policy.pl` defines only rules and `:- dynamic` declarations, no facts, per Step 1's
  instructions. All per-claim facts live in `queries.pl`.
- Every fact predicate a claim might supply is declared `dynamic` in `policy.pl` so that a
  question silent on some circumstance fails cleanly (via negation-as-failure) rather than
  raising an existence error.
- `queries.pl` declares the same predicates `discontiguous` because facts for, e.g., `injury/1`
  are naturally scattered across separate per-question blocks; this silences SWI-Prolog's
  (harmless) discontiguous-clause warnings so the load check is silent.
- Per Step 2 instructions 6-7, facts are only asserted when a question's narrative actually
  raises that circumstance; everything else is left unasserted so policy.pl's defaults treat it
  as satisfied (for conditions) or not-applicable (for exclusions).
