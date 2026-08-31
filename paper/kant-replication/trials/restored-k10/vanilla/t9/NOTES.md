# Notes on judgement calls (vanilla trial, t9)

Reasoning was done directly against `inputs/chubb-policy.txt` and `inputs/queries-blind.md`,
applying the standing preamble (all other conditions met, no unreferenced exclusions apply,
policy signed, premium paid on time). Points where the contract required interpretation rather
than a mechanical read:

1. **§3.1 exclusion list treated as closed/exhaustive.** The five enumerated exclusions
   (skydiving; military service; fire-fighter service; police service; age ≥ 80) are the only
   ones recognized. No exclusion outside this list (e.g. for self-inflicted or reckless conduct)
   was assumed to exist, per the instruction to answer from the contract text as given.

2. **Q1 (firefighter burns) and Q8 (military training injury):** treated "doing my duty as a
   firefighter" and "military training exercise" as squarely "arising directly or indirectly out
   of" fire-fighter service / military service respectively — i.e. an activity-based causal nexus
   to the excluded service, not merely incidental. Both excluded -> No.

3. **Q9 (son bit my ankle, currently serving as a police officer):** distinguished *status* from
   *causal nexus*. §3.1.4 excludes events "arising directly or indirectly out of ... Service in
   the police." Being employed as a police officer at the time of an unrelated domestic injury
   (a dog/child-bite-style incident from one's own son) does not, on this text, mean the injury
   arose out of police service. Treated as not excluded -> Yes. This is the same nexus-vs-status
   reading applied consistently with Q1/Q8, just with the opposite result because the facts given
   supply no occupational nexus.

4. **§1.3 read as a compound, two-part condition:** (a) the wellness visit itself must occur no
   later than the 6-month anniversary, and (b) written confirmation of that visit must be
   supplied no later than the 7-month anniversary. §1.2 cancels the policy if "the condition set
   out in Section 1.3 has not been satisfied in a timely fashion." Both sub-deadlines were
   treated as necessary for "timely" satisfaction.

5. **Q4 (fall while traveling abroad; confirmation given at 8 months):** two independent readings
   both point the same direction, so the ambiguity did not change the answer:
   - 8 months is past the 7-month confirmation deadline in §1.3, so the condition was not
     satisfied in a timely fashion, triggering deemed cancellation under §1.2.
   - Separately, §2.2 limits the payable Daily Hospital Income Benefit to confinement "in a
     hospital in the United States." "Hospitalized ... while traveling abroad" was read as the
     hospitalization itself occurring outside the US (not merely the fall), which — independent
     of §4.1.1's broad 24/7/worldwide *insuring* language — would make the benefit non-payable
     under §2.2's narrower payment condition for location.
   Both point to No; the exact temporal ordering of the fall vs. the 8-month confirmation was not
   spelled out in the query, but it did not matter given the second, independent ground.

6. **Q5 (punched own face to show off; no fraud/misrepresentation) — the least certain call.**
   The contract has no exclusion for intentional self-infliction or recklessness. Read "accidental
   Injury" (§2.1) under the "accidental result" approach (an act can be voluntary while its
   resulting injury/severity is still "accidental" if unintended and unexpected) rather than the
   older "accidental means" approach (any voluntary act taints the whole result as non-accidental).
   The policy is expressly "governed by the laws of New York" (§4.3.1), and this result-based
   reading is the one associated with NY case law in this area. Combined with the closed
   exclusion list (point 1) and the query's explicit stipulation that there was no fraud or
   misrepresentation (foreclosing §1.2's cancellation route), this was read as covered -> Yes.
   A reader applying the older "accidental means" doctrine, or importing an unstated
   self-inflicted-injury exclusion by analogy to typical real-world hospital-indemnity policies,
   would reach No instead. Flagged here as the one answer most sensitive to interpretive choice.

7. **Q2, Q3, Q6, Q7 timing/age details:** age thresholds (78, 79, 75 — all below the ≥80
   exclusion) and wellness-visit-proof timings (5, 6.5, 2 months — all either before the 6/7-month
   deadlines, or, for Q3, still within the window where §1.1(3)'s "still pending" prong keeps the
   policy in effect) were read as satisfying §1.1/§1.3 without incident. For Q6 the skydiving
   exclusion is independently dispositive, so its timing detail does not affect the answer either
   way.
