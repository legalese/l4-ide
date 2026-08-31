# Notes — judgement calls (vanilla cell, t5)

Read only `inputs/chubb-policy.txt` and `inputs/queries-blind.md`. No other files in the
repo were consulted, and no web search was performed. Reasoning below is derived solely
from the contract text as given.

Relevant clauses relied on:

- 1.1 / 1.3: policy is in effect only if (among other things) the Section 1.3 condition
  is "still pending or has been satisfied in a timely fashion." Section 1.3 itself has two
  nested deadlines: the wellness visit must occur no later than the 6-month anniversary,
  and written confirmation of it must be supplied no later than the 7-month anniversary.
- 1.2: cancelation is deemed to occur on fraud/misrepresentation/material withholding, OR
  on failure to satisfy the 1.3 condition "in a timely fashion."
- 2.1: five closed-list exclusions — skydiving, military service, firefighter service,
  police service, age ≥ 80 at hospitalization — each keyed to the event "arising directly
  or indirectly out of" the listed cause.
- 3.1.1: worldwide, 24/7 coverage (no territorial exclusion for travel abroad).

Judgement calls:

1. **Q5 (punching own face to show off).** The contract's coverage grant is for
   "sickness or accidental injury" (1.1), and Section 2's exclusion list is a closed set
   that does not mention self-inflicted or intentional acts. Treated the voluntary act
   (throwing the punch) as distinct from the injurious result (an unplanned, unintended
   hospitalization-level injury), and read "accidental injury" as reachable by an
   unintended severe outcome of a voluntary act, absent any contract language narrowing
   "accidental" to exclude that. The query's explicit "I did not commit fraud or
   misrepresentation" stipulation reads as closing off the only other plausible route to
   denial (1.2's fraud ground), which supported reading the intended claim as covered.
   Answered **Yes**, but flagging this as the single most contestable call in the set —
   a stricter "accidental means" reading (the initiating act must itself be involuntary)
   would instead exclude it, and the contract text does not itself resolve which reading
   governs.

2. **Q4 (confirmation given 8 months after effective date).** Read "I had given
   confirmation ... 8 months after the effective date" as establishing, independent of
   exactly when the hospitalization occurred, that the Section 1.3 confirmation deadline
   (7-month anniversary) had already been missed. A late-but-eventually-supplied
   confirmation does not satisfy 1.3 "in a timely fashion," so this trips 1.2's
   cancelation clause (and independently fails clause 1.1(3), which requires the
   condition to be "still pending" — no longer true once the 7-month deadline has passed
   — "or" timely satisfied). Traveling abroad is not itself an issue given 3.1.1.
   Answered **No** on that basis.

3. **Q9 (son biting ankle; claimant is a police officer).** Read "serving as a police
   officer at the time of hospitalization" as a status fact, not a causal one, and
   distinguished it from the stated proximate cause of the injury (the claimant's son
   biting their ankle — a domestic incident). Exclusion 2.1(4) requires the injury to
   arise "directly or indirectly out of ... service in the police," which requires a
   causal nexus to police duties that is absent here. Answered **Yes** (confirmation at
   6 months is also within the 7-month 1.3 deadline).

4. **Wellness-visit sub-deadline.** Section 1.3 nominally requires both (a) the visit to
   occur by the 6-month anniversary and (b) confirmation of it to be supplied by the
   7-month anniversary. Every query that mentions timing only gives the date confirmation
   was "provided"/"submitted"/"given," never the visit's own date. Treated "confirmation
   supplied by the 7-month anniversary" as the operative, checkable proxy for timely
   Section 1.3 compliance in each such query (Q4, Q6, Q7, Q9), since the visit's own date
   is never independently stated and the standing preamble directs assuming unstated
   conditions are satisfied.

5. **Causally-linked service exclusions (Q1, Q6, Q8) vs. status-only (Q9).** Where the
   query states the injury arose *while* performing the excluded activity (firefighting
   duty, skydiving, a military training exercise), applied the 2.1 exclusion directly
   regardless of other favorable facts recited in the same query (e.g., "did not commit
   fraud," "within the policy term") — those facts don't cure an exclusion that has
   already been triggered by the cause of injury itself.
