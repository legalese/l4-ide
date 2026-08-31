# Notes on judgement calls (vanilla cell, t4)

Reasoning was done privately per the task instructions (no explanations go into
`answers.json`); this file records where the contract text required interpretation rather
than a mechanical lookup.

## Q1, Q6, Q8 — straightforward exclusion hits
Firefighter burns-on-duty (Q1), skydiving injury (Q6), and military-training-exercise injury
(Q8) each fall squarely inside one of the five enumerated §2.1 exclusions ("arising directly or
indirectly out of" that activity). Answered No regardless of the other facts recited in the
query (age, wellness-visit timing, absence of fraud) — a single applicable exclusion is
sufficient on its own.

## Q9 — occupation is not the trigger, causation is
§2.1.4 excludes injury "arising directly or indirectly out of ... Service in the police," not
injury suffered by a person who merely happens to serve in the police. Being bitten on the
ankle by one's own son has no causal connection to police duties, so the exclusion does not
apply even though the claimant states they were "serving as a police officer at the time of
hospitalization." Treated the occupation detail as a distractor, by design parallel to Q8 (where
the analogous "I did not commit fraud" detail is also true but irrelevant, since the injury
still hits an exclusion by a different route — military service, causally).

## §1.3 wellness-visit condition (Q3, Q4, Q6, Q7, Q9)
§1.3 bundles two deadlines: the wellness visit must *occur* no later than the 6-month
anniversary, and written *confirmation* of it must be *supplied* no later than the 7-month
anniversary. §1.1(3)/§1.2 keep the policy in force if this condition is "still pending or has
been satisfied in a timely fashion"; late satisfaction is deemed a cancelation.
- Q3 (hospitalized at 5 months, no wellness fact stated): at 5 months neither deadline has
  passed yet, so the condition is necessarily "still pending" — policy stays in effect
  independent of whether the visit has happened. Yes (no exclusion applies either).
- Q4 (confirmation given at 8 months): later than the 7-month ceiling under any reading, so
  §1.3 was not satisfied in a timely fashion → cancelation deemed under §1.2 → policy not in
  effect. Answered No. (The query doesn't state exactly when the hospitalization fell relative
  to the 8-month confirmation; I treated the stated 8-month figure as the operative,
  already-crystallized breach rather than trying to construct a sub-scenario where
  hospitalization preceded the breach.)
- Q6 (proof provided at 6.5 months): within the 7-month confirmation deadline; whether the
  underlying visit itself predated the 6-month mark is not stated and is left unresolved,
  because the skydiving exclusion independently disposes of this query (No) regardless.
- Q7 (proof at 2 months) and Q9 (proof at 6 months): both within the 6-/7-month windows (6
  months is read as satisfying "no later than the 6th month anniversary," i.e. the boundary is
  inclusive). No cancelation triggered.

## Q5 — the genuinely hard call: self-inflicted injury
"Hospitalized for punching my own face to show off for my friends," with an explicit denial of
fraud or misrepresentation. This scenario matches none of the five §2.1 exclusions, and the
query forecloses the §1.2 fraud/misrepresentation cancelation route explicitly. The open
question is whether a deliberately self-administered punch counts as an "accidental injury" at
all under §1.1's coverage description, since the contract never defines "accidental" or
addresses self-inflicted harm.

I read "accidental" as turning on whether the *injury/result* was unintended, not on whether
the antecedent conduct was voluntary — the claimant did not intend to injure himself badly
enough to need hospitalization; he intended to show off. This reading is reinforced structurally
by §2.1 itself: skydiving, military service, firefighting and police service are all voluntary,
knowing exposures to risk, yet the drafters felt it necessary to carve them out explicitly as
exclusions from "accidental injury" coverage. That would be unnecessary if voluntary/intentional
participation in the underlying activity already disqualified an injury from being "accidental."
By the same logic, an unlisted voluntary act (punching one's own face) is not automatically
excluded merely because it was done on purpose — only the five enumerated categories are carved
out. Combined with the explicit non-fraud stipulation, nothing in the text bars the claim.
Answered Yes, but flagging this as the lowest-confidence answer in the set; a reading that
treats direct, self-administered physical trauma as categorically non-"accidental" (regardless
of the §2.1 structural argument) would flip this to No. I did not find the text itself decisive
enough to call this indeterminate ("I do not know"), so I committed to the better-supported
reading above rather than declining to answer.

## Q2 — no special reasoning
Age 78 is under the §2.1.5 threshold (≥80); nothing else in the query implicates any other
exclusion. Yes, per the standing "assume all other conditions are met" preamble.
