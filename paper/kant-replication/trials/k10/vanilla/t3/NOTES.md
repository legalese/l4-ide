# Notes — judgement calls (vanilla, t3)

Method: read only `inputs/chubb-policy.txt` and `inputs/queries-blind.md`; answered directly
against the contract text with no encoding. Key clauses used: §1.1 (payment conditioned on
policy being "in effect" at time of hospitalization "for sickness or accidental injury"),
§1.2/§1.3 (deemed cancelation, incl. failure to satisfy the wellness-visit condition "in a
timely fashion"), §2.1 (five enumerated exclusions: skydiving, military service, firefighting
service, police service, age ≥ 80), §3.1.1 (worldwide 24/7 coverage).

Judgement calls, roughly in order of difficulty:

1. **Status vs. causation in the exclusions (Q9).** §2.1 excludes injury "arising directly or
   indirectly out of" military/fire/police service, etc. — i.e. it requires a causal link to the
   listed activity, not merely that the claimant happens to hold that job. Q9's claimant "was
   serving as a police officer at the time of hospitalization," but the injury (son biting his
   ankle) has no connection to police duties, so I did not apply the police exclusion. I treated
   Q1 (firefighter burns from "doing my duty as a firefighter") and Q8 (injury "in a military
   training exercise") as the mirror-image cases where the causal link *is* present, so those
   exclusions do apply.

2. **Q4 — late wellness-visit confirmation and retroactivity.** §1.3 requires written
   confirmation, no later than the 7-month anniversary, of a wellness visit that itself occurred
   no later than the 6-month anniversary. Q4 gives confirmation at 8 months, which misses both
   sub-deadlines. §1.2 says cancelation "will be deemed to have occurred" when §1.3 is not
   satisfied timely, but the contract never pins down the effective date of that deemed
   cancelation, and the query doesn't state exactly when the fall/hospitalization happened
   relative to the late filing. I read the deeming clause as a categorical, hindsight fact
   ("was §1.3 ultimately satisfied on time? No.") rather than something that only bites
   prospectively from the moment of lateness, and answered No. A reading that only cancels
   coverage going forward from month 7 (leaving an earlier hospitalization covered) is
   textually available but I found it less supported, since §1.1(3) itself is phrased as a
   condition ("still pending or has been satisfied in a timely fashion") that a claimant given
   full hindsight cannot satisfy once the confirmation is known to have been late.

3. **Q6 — 6.5-month confirmation is moot.** 6.5 months is past the 6-month visit deadline but
   before the 7-month confirmation deadline, and the query doesn't say when the underlying visit
   itself occurred, so §1.3's timeliness is genuinely ambiguous on these facts alone. I did not
   have to resolve it because Q6's injury arose from skydiving, an independent, unambiguous
   §2.1 exclusion.

4. **Q5 — hardest call: is a deliberate self-punch an "accidental injury"?** §2.1's five
   exclusions do not mention self-inflicted or intentional acts at all, so if that list were the
   *only* gate, punching one's own face would be covered (it's excluded from neither list, and
   the query stipulates no fraud/misrepresentation, closing off the other cancelation route in
   §1.2). But §1.1 only ever promises payment for hospitalization "for sickness or accidental
   injury" — a threshold description of what the policy covers at all, separate from the §2.1
   exclusions. I read "accidental" in its ordinary sense (unintended, not deliberately brought
   about) as applying to the act itself, not just its ultimate severity: punching your own face
   on purpose, even as a stunt, is a deliberate act, not a chance event. On that reading the
   claim never reaches "sickness or accidental injury" in the first place, so I answered No.
   I want to flag this explicitly as contestable: the contract nowhere defines "accidental
   injury," and a reader who treats §2.1 as the exhaustive statement of what's excluded (with
   §1.1's "sickness or accidental injury" read as mere descriptive framing of the policy type)
   would reach Yes instead. I considered answering "I do not know" here but judged that the
   plain-English meaning of "accidental" (unintentional) more naturally excludes a deliberate
   self-inflicted act, so I committed to No rather than declining to answer.

5. **Q2, Q3, Q7 — reliance on the standing assumption.** These give an age and/or a cause of
   hospitalization (pneumonia, heart attack) with no connection to any §2.1 exclusion, and where
   wellness-visit timing is either unmentioned or comfortably inside both the 6- and 7-month
   windows. Per the task's standing instruction ("assume all other conditions are satisfied, and
   no exclusions apply unless explicitly referenced in the query"), I did not invent exclusions
   the queries don't raise, and answered Yes for all three.

No other clauses in the contract (arbitration, governing law, currency, premium timing, policy
term) affected any of the nine answers.
