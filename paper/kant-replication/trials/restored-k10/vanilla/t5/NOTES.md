# Notes on judgement calls (vanilla cell, t5)

These are the places where the contract text required an interpretive call rather than a
mechanical lookup. Recorded per the task instructions; not part of `answers.json`.

1. **Q1 (firefighter burns).** Section 3.1.3 excludes injury "arising directly or indirectly
   out of ... Service as a fire fighter." The query states the burns occurred "while doing my
   duty as a firefighter," which is an explicit causal link to the excluded activity, so I
   treated the exclusion as triggered.

2. **Q4 (late wellness confirmation).** Section 1.3 requires written confirmation of the
   wellness visit "no later than the 7th month anniversary." The query states confirmation was
   given "8 months after the policy's effective date" — after that deadline. Under 1.2, failure
   to satisfy the Section 1.3 condition "in a timely fashion" is deemed a cancellation, and under
   1.1 the policy must be in effect (not canceled) at the time of hospitalization. I read this as
   dispositive on its own. Separately, I noticed a tension between 4.1.1 ("Your Policy insures
   You twenty-four (24) hours a day anywhere in the world") and 2.2 (benefit "will only be payable
   for each ... day of continuous confinement in a hospital in the United States"), which bears on
   the "traveling abroad" fact in this query. I did not need to resolve that tension because the
   late-confirmation point already determines the answer, but flag it here as a genuine internal
   inconsistency in the contract that a different query could hinge on.

3. **Q5 (punching own face to show off).** Section 2.1 conditions any benefit on confinement
   resulting from "sickness or accidental Injury." I read "accidental" as excluding injury that is
   the direct, foreseeable result of one's own deliberate act (punching oneself), even though the
   claimant did not intend or expect hospitalization and even though no listed exclusion in
   Section 3 specifically names self-inflicted injury. I treated this as a threshold coverage
   question (does the loss fall within the insuring clause at all) rather than an exclusion
   question, and concluded it does not. The query's aside ("I did not commit fraud or
   misrepresentation") I read as ruling out the separate 1.2 fraud/cancellation route, isolating
   the "accidental" question as the actual issue being tested.

4. **Q9 (son's bite while serving as a police officer).** Section 3.1.4 excludes injury "arising
   directly or indirectly out of ... Service in the police." I read this as requiring a causal
   nexus between police duties and the injury, not merely that the claimant's occupation is
   "police officer" at the time. Being bitten in the ankle by one's own son has no stated
   connection to police duties, so I did not apply the exclusion — in contrast to Q1, where the
   query explicitly ties the injury to the firefighting duty itself.

5. **"Still pending" (Q3).** Section 1.1(3) treats the policy as in effect if the Section 1.3
   condition "is still pending or has been satisfied in a timely fashion." For a hospitalization
   at 5 months post-effective-date, the 6-month/7-month deadlines have not yet arrived, so I
   treated the condition as "still pending" and the policy as in effect at the time of
   hospitalization.

6. **Unstated facts.** Per the standing preamble, any fact not raised in a given query (age,
   wellness-visit timing, location, cause of loss, etc.) was assumed to pose no problem — e.g., an
   unmentioned age was assumed to be under 80, and unmentioned wellness-visit compliance was
   assumed timely.
