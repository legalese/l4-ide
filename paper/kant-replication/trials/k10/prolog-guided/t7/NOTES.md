# Notes

## Load check

Ran (as permitted):

```
swipl -q -g halt policy.pl queries.pl
```

Output: silent — 0 bytes on both stdout and stderr, exit code 0. (Checked by redirecting
each stream separately.) I did not run `q1`..`q9` or otherwise query `covered/1` against
the nine claims; the only interaction with the loaded program was the empty `halt` goal.

I also cross-checked, by grepping rather than running anything, that the set of
`claim_*` predicate names referenced in `policy.pl` is identical to the set defined in
`queries.pl`, and identical to the 18 claim facts listed in `inputs/schema.md`.

## Judgement calls

**1.1(3) "still pending or ... satisfied in a timely fashion" (condition 1.3).** I read
this disjunction as evaluated *as of the hospitalization month*: the policy counts as
"in effect" for a given hospitalization if, by that month, either (a) the 7-month
wellness-confirmation deadline has not yet arrived (`hospitalization_month < 7` —
"still pending"), or (b) the confirmation and visit were in fact each supplied on time
by then. I did not treat a *later* failure of condition 1.3 as retroactively voiding
coverage for a hospitalization that had already occurred while the condition was still
pending — the "in effect" test is a snapshot at the time of hospitalization, not a
final settling-up at month 7. This affects Q3 (hospitalization at month 5, before the
deadline: pending, so in effect regardless of what happens on the wellness-visit front
later) and interacts with Q4/Q9 below.

**Q4 — hospitalization month not stated.** The question gives only the month the
wellness-visit confirmation was supplied (month 8, after the 7-month deadline) and not
when the hospitalization itself occurred. Since `claim_hospitalization_month` is a
mandatory (non-`none`) fact, some value had to be chosen. Setting it to anything before
month 7 would make the late confirmation moot (the "still pending" branch would apply
regardless of the eventual late filing), which seemed like it would duck the fact
pattern the question is evidently designed to test. I set it to month 9 — after both the
deadline and the actual (late) confirmation — so the claim squarely tests whether a
confirmation supplied after the 7-month deadline satisfies condition 1.3. Under my
reading of 1.1(3)/1.3, it does not, so `covered(c4)` fails on this encoding.

**Q5 — "punching my own face to show off for my friends."** The schema's
`claim_hospitalization_ground` has three values: `sickness`, `accidental_injury`,
`neither`. I treated a deliberate, self-inflicted act as neither a sickness nor an
*accidental* injury (accidental implying unintended), so I set the ground fact to
`neither` for this claim. Under `covered/1`'s top-level gate (1.1: the hospitalization
must be for sickness or accidental injury), this fails regardless of the claim's
stated absence of fraud or misrepresentation — which read to me as confirming that
those two disqualifying grounds specifically are not in play, not as confirming that
the underlying event is a covered one at all. This is the most contestable call in the
set; a reader who treats "accidental" as "not deliberately fraudulent" rather than "not
a deliberate act" would classify the ground as `accidental_injury` and reach the
opposite result.

**Q6 — "proof of my wellness visit was provided 6.5 months after."** I read "proof ...
was provided" as the act of supplying the written confirmation (`claim_written_
confirmation_month = 6.5`), not the date of the underlying visit, and picked a
plausible antecedent visit month (6, satisfying the separate no-later-than-month-6
requirement for the visit itself) since the question does not state it separately.
This choice is immaterial to the outcome I compute, since the general exclusion for
skydiving (2.1.1) applies independently of the 1.3 timeline.

**Q9 — "serving as a police officer at the time of hospitalization."** Exclusion 2.1
excludes events "arising directly or indirectly out of ... service in the police." I
read this as requiring the injury to arise *from* that service, not merely that the
claimant happened to hold that job when hospitalized. Being bitten by one's own son
does not arise out of police duty on any reading I could construct, so I did not
include `police_service` in `claim_causes` for this claim — unlike Q1 (firefighter
injured "doing my duty as a firefighter") and Q8 (injured "in a military training
exercise"), where the narrative ties the injury directly to the service activity. I
also used month 8 for the hospitalization (after the stated confirmation month of 6)
so that condition 1.3 is tested on its "satisfied" branch (confirmation and visit both
on time) rather than trivially by the "still pending" branch.

**Fraud / misrepresentation timing (1.2).** The policy does not say whether fraud or
misrepresentation occurring *after* a hospitalization retroactively voids coverage for
that earlier event. I applied the same "as of the hospitalization" reasoning as for
condition 1.3: only fraud/misrepresentation at or before the hospitalization month
cancels the policy for that claim (`no_later_than(claim_fraud_month, hospitalization_
month)`, etc.). None of the nine questions turn on this, since fraud/misrepresentation
months are `none` throughout, but it is a live modelling choice in `policy.pl`.

**"Material withholding of any information" (1.2).** The contract text lists three
cancellation triggers — fraud, misrepresentation, or material withholding of
information — but the schema supplies claim facts for only two of them
(`claim_fraud_month`, `claim_misrepresentation_month`). Per the instruction to use only
the given claim facts, `covered/1` models cancellation from fraud and misrepresentation
only; "material withholding" has no corresponding fact and so is not separately
encoded.

**60-day recovery waiting period (3.2.1), and the arbitration clock.** Converted "sixty
(60) days" to 2 months, the finest granularity the schema's month-numbered facts
support. The 3-month arbitration-commencement window (3.2.1) is used as given, in the
same units. Neither constraint binds any of the nine claims — all nine set
`claim_dispute_arisen = false` and `claim_recovery_sought_month = none`, since none of
the nine questions raise a dispute or an early-recovery attempt, and the standing
preamble directs setting facts unrelated to a question so that all conditions for
coverage are satisfied.

**Premium payment (1.1(2) / 3.5.1).** The contract says the premium is paid "in one
lump sum at the signing of the policy," but the schema has no "signing month" fact to
compare against, and the paper's own standing instructions stipulate the premium was
paid on time for every question. I treated `claim_premium_paid_month` as satisfying
1.1(2) whenever it is a number (i.e., paid at all), without an additional timeliness
check against another date, and set it to month 0 in every claim.

**Policy term (3.6) and general exclusions' age threshold (2.1.5).** Read literally
against the schema's supporting predicates: term expiry uses `no_later_than(hospitalization_
month, policy_term_months)`; the age exclusion is `Age >= 80` (so 79 is not excluded,
matching the "equal to or greater than 80" wording). `claim_policy_term_months` is set
to 12 throughout, matching the one-year term in clause 3.6.
