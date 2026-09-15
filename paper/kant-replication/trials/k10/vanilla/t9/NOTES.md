# Notes on judgement calls (vanilla cell, t9)

These are the places where the contract text required interpretive judgement rather than
mechanical lookup. No files outside the trial directory were consulted; no web search was done.

## Relevant contract structure (as given)

- §1.1: benefit payment requires the policy to be "in effect" at the time of hospitalization.
  Policy is in effect if: (1) signed, (2) premium paid, (3) the §1.3 condition is _still pending
  or has been satisfied in a timely fashion_, and (4) not canceled.
- §1.2: cancelation is deemed to occur on fraud/misrepresentation/material withholding, OR on
  failure to satisfy §1.3 in a timely fashion, OR automatically at the end of the one-year term.
- §1.3: two nested deadlines measured from the effective date — the wellness visit itself must
  occur by the 6-month anniversary, and written confirmation of that visit must be supplied by
  the 7-month anniversary.
- §2.1: a closed, enumerated list of five general exclusions (skydiving; military service; fire
  fighter service; police service; age ≥ 80 at time of hospitalization) — each phrased as
  applying to an event "arising directly or indirectly out of" the listed activity/status.
- §3.1.1: the policy applies worldwide, 24 hours a day (so foreign travel is not itself a bar).

## Judgement calls

1. **§1.3 "timely" checks, where only the confirmation date is given (Q4, Q6, Q7, Q9).** The
   text gives two deadlines (visit by month 6, confirmation by month 7), but the queries only
   ever state when confirmation was _provided_, not when the underlying visit occurred. I treated
   the confirmation date against the 7-month anniversary as the operative test: ≤ 7 months →
   condition satisfied/timely; > 7 months → not timely, triggering §1.2 cancelation. This is a
   reading-in, since the queries don't give us the visit date separately to check against the
   6-month sub-deadline.

2. **Q3: hospitalization before either §1.3 deadline has arrived.** At 5 months post-effective-
   date, neither the 6-month (visit) nor 7-month (confirmation) deadline has yet passed. I read
   §1.1(3)'s "still pending" disjunct as covering exactly this case — the condition hasn't failed,
   it just isn't due yet — so the policy is in effect. Nothing in the query suggests the visit/
   confirmation was ever missed, only that hospitalization happened early.

3. **Q4: the fall/hospitalization date isn't stated relative to the late (8-month) confirmation.**
   The query only tells us confirmation was given at month 8, past the month-7 deadline. It does
   not say whether the fall happened before or after that failure crystallized. I treated the
   stated fact (late confirmation) as the controlling, decisive fact the query intends to test —
   i.e., that late confirmation makes §1.3 unsatisfied "in a timely fashion," triggering §1.2
   cancelation — rather than trying to rescue coverage via an unstated assumption that the
   hospitalization predated the failure. Foreign travel (§3.1.1) is not the issue here; it's
   affirmatively covered territory and doesn't change this outcome.

4. **Q1 vs. Q9: causal nexus for the occupation-based exclusions.** §2.1's military/fire
   fighter/police exclusions apply to an event "arising directly or indirectly out of" that
   service. Q1's burns are explicitly incurred "while doing my duty as a firefighter" — a direct
   causal link to the excluded activity. Q9 states the claimant "was serving as a police officer
   at the time of hospitalization," but the actual cause of injury is unrelated (a son biting an
   ankle) — merely holding that occupation at the time, with no causal connection between the
   occupation and the injury, does not trigger the exclusion on this text. I read these two
   questions as a deliberately paired contrast and answered them accordingly (Q1 excluded, Q9
   not).

5. **Q5: "punching my own face to show off," no fraud/misrepresentation.** This isn't on §2.1's
   closed exclusion list (no self-inflicted-injury exclusion appears anywhere in the text as
   given), and the query explicitly forecloses the one cancelation ground that might otherwise
   seem relevant (§1.2's fraud/misrepresentation trigger). I treated the explicit denial of fraud
   as pointed to §1.2 specifically, and, absent any stated exclusion matching this cause of
   injury, read the claim as covered. I did not import an "intentional/self-inflicted injury"
   exclusion that isn't present in the text, since the task instructs answering from the contract
   text as given rather than from what such policies typically contain elsewhere.

6. **Q6 and Q8: multiple facts stated, only one controlling.** Q6 gives age 79 (under the ≥80
   threshold) and a timely wellness-visit proof (6.5 months) alongside "injury sustained while
   skydiving" — I read the skydiving exclusion as controlling outright regardless of the other
   (non-excluding) facts. Q8 similarly gives "within the policy term" and "no fraud" alongside
   "injured in a military training exercise" — I read those two facts as closing off alternative
   objections (term expiration, fraud-cancelation) so that the military-service exclusion is
   isolated as the sole basis for the answer.
