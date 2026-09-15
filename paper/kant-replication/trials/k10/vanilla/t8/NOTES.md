# Notes on judgement calls (vanilla cell, t8)

These are the points where the contract text underdetermined the answer and I had to pick a
reading. Answers were produced by reading `inputs/chubb-policy.txt` and `inputs/queries-blind.md`
only.

1. **Q1 / Q8 vs Q9 — "arising directly or indirectly out of" service exclusions require a causal
   link, not just a status.** For Q1 (burns "while doing my duty as a firefighter") and Q8 (injury
   "in a military training exercise") I read the injury as caused by the excluded service itself,
   so General Exclusions 2.1(2)/(3) apply. For Q9 (son biting the claimant's ankle) I read the
   mention that the claimant "was serving as a police officer at the time" as occupational status
   only, with no causal link between police service and the injury, so exclusion 2.1(4) does not
   apply even though the person is a police officer. This is the main judgement call in the set:
   the exclusions are written as "arising ... out of" a cause, not "while employed as."

2. **Q4 — late wellness-visit confirmation.** Section 1.3 requires written confirmation of the
   wellness visit "no later than the 7th month anniversary." Q4 states confirmation was given at
   8 months, i.e. after that deadline. I read this as failing the disjunct in 1.1(3) ("still
   pending or ... satisfied in a timely fashion") — once the deadline passes unmet it is neither
   still pending nor timely — which triggers deemed cancelation under 1.2 and makes the policy not
   "in effect" per 1.1(4). The query does not state exactly when the hospitalization (the fall)
   occurred relative to the 7-month mark; I treated the late confirmation as dispositive rather
   than assuming an earlier, unstated hospitalization date that might have preceded the deadline.
   Worldwide/travel coverage (3.1.1) is not the issue here and does not block coverage on its own.

3. **Q5 — "accidental injury" and self-inflicted, non-fraudulent harm.** The contract has no
   exclusion for self-inflicted or intentional acts (only skydiving, military, firefighting,
   police service, and age ≥ 80 are listed), and the query affirmatively states no fraud or
   misrepresentation occurred. I read "accidental injury" as turning on whether the _result_
   (hospitalization) was unintended, not on whether the underlying voluntary act (punching one's
   own face) was intentional — i.e., an unintended, unexpectedly serious outcome of a voluntary
   act still counts as an accidental injury absent a specific exclusion. This is a judgement call;
   a stricter reading limiting "accidental" to unintended acts (not just unintended results) would
   point the other way.

4. **Timeliness of the 1.3 condition where the query gives a "still pending" scenario.** For Q3
   (hospitalization at 5 months, no confirmation event mentioned) I treated the Section 1.3
   condition as "still pending" under 1.1(3), since neither the 6-month (visit) nor 7-month
   (confirmation) deadline had yet passed at the time of hospitalization, so the policy is in
   effect. For Q6 and Q9, the stated confirmation timings (6.5 months and 6 months respectively)
   are both before the 7-month deadline, so I treated 1.3 as satisfied in a timely fashion in
   both cases; "no later than" was read as inclusive of the deadline date itself. In Q6 this is
   moot since the skydiving exclusion is independently dispositive.

5. **Section numbering gap.** The contract text as given references "Section 5" (policy term /
   premium amount) in 1.2 and 3.5, but the supplied text ends at clause 3.6 without an actual
   Section 4 or 5 ever appearing. None of the nine questions turned on the missing content
   (benefit amounts, exact premium figures), so this did not affect any answer, but it means the
   supplied contract excerpt is not complete relative to its own cross-references.
