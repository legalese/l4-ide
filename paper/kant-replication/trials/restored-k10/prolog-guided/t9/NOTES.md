# NOTES

## Load check

Ran the permitted load check:

```
swipl -q -g halt policy.pl queries.pl
```

First attempt printed `discontiguous` warnings (SWI-Prolog objects to `claim_*/2`
facts being grouped by claim rather than by predicate, which is how the task's own
example in TASK.md lays them out). Added `:- discontiguous` declarations for all 21
`claim_*/2` predicates at the top of `queries.pl` to make the grouping-by-claim
layout explicit rather than restructuring away from the TASK.md example format.
After that change, the command produced **no output and exit code 0** — confirmed
silent. Did not run `q1`..`q9` or otherwise evaluate the encoding against the nine
questions.

## Judgement calls

- **"Still pending or has been satisfied" (SS1.1 item 3 / SS1.3).** Modeled as: the
  SS1.3 condition is satisfied if the wellness visit happened by month 6 (with a
  qualified provider) and confirmation was given by month 7; otherwise it is only
  "pending" (not yet failed) if the relevant fact is `none` *and* the hospitalization
  month itself is not yet past that fact's deadline. A visit or confirmation that
  already happened, but late, is treated as a completed failure, not something
  "pending" can rescue. This directly drives claim `c3` (Q3): hospitalization at
  month 5, wellness visit/confirmation left `none`, which is "pending" under this
  reading (5 is before both the month-6 and month-7 deadlines) and so does not
  cancel the policy.
- **SS1.1 item 3 vs. SS1.2's cancelation trigger.** Read these as the same fact
  stated twice (being "not canceled" already subsumes "SS1.3 not failed"), so
  `policy_in_effect/1` checks only `\+ canceled/1`, and `canceled/1` includes
  "`SS1.3` not ok" as one of its four disjuncts, rather than checking it twice.
- **US-hospital requirement (SS2.2).** Read SS2.2's "only be payable for ...
  confinement in a hospital in the United States" as a real, independent gate on
  the benefit, distinct from SS4.1.1's "insures You ... anywhere in the world" (which
  I read as: the *insured event* can happen anywhere, but the *daily hospital
  income benefit* specifically requires the confinement itself to be in a US
  hospital). Applied to claim `c4` (Q4, "traveling abroad"), which I read as meaning
  the confinement was outside the US, so `claim_confined_in_us_hospital(c4, false)`.
- **Self-inflicted intentional acts (SS2.1's "sickness or accidental injury").**
  Claim `c5` (Q5, punching one's own face on purpose) is modeled with
  `claim_hospitalization_ground(c5, neither)`, on the reasoning that a voluntary,
  intentional act is not "accidental" even if the resulting injury was unwanted —
  distinct from, and independent of, the fraud/misrepresentation question the query
  explicitly disclaims.
- **Status vs. cause (SS3.1's "arising directly or indirectly out of ... service in
  the police").** Claim `c9` (Q9, bitten by claimant's son while claimant "was
  serving as a police officer at the time") is modeled with `claim_causes(c9,
  [other])`, not `[police_service]` — being a police officer at the time of
  hospitalization is a status, not a causal link between the injury and police
  service, and the exclusion is written in causal ("arising out of") terms, matching
  the `arose_out_of/2` helper's own doc comment.
- **"Proof of my wellness visit was provided/given N months after..." (Q4, Q6, Q9).**
  Read as describing the written-confirmation submission event
  (`claim_written_confirmation_month`), not the underlying wellness-visit date
  itself (`claim_wellness_visit_month`), which none of those three questions state.
  For those three claims I set a compliant, unstated visit month (before the
  confirmation month, at or before month 6) so the encoding isolates whatever the
  question is actually testing rather than incidentally also failing on an
  unstated visit date.
- **60-day recovery bar (SS4.2.1's last sentence).** The schema's arbitration-related
  facts are all in month units; translated "sixty (60) days" to 2 months for the
  `recovery_not_premature/1` check, consistent with the month-anniversary
  granularity used everywhere else in the policy. Not exercised by any of the nine
  claims (all set `claim_dispute_arisen` to `false` and the recovery/proof-of-claim
  months to `none`, since none of the nine questions concern a dispute or
  arbitration).
- **Premium timeliness (SS1.1 item 2 / SS4.5.1).** SS1.1 only requires the premium
  "has been paid," with no explicit numeric deadline (SS4.5.1's "at the signing of
  the policy" reads as describing the ordinary/expected manner of payment, not a
  hard condition of coverage), so `policy_in_effect/1` only checks
  `claim_premium_paid_month(C, PaidMonth), PaidMonth \= none`. All nine claims set
  this to `0`, consistent with the standing instruction that the premium was paid
  on time.
- **Continuous confinement (SS2.2's 365-day cap).** Modeled as requiring some
  positive number of continuous confinement days, without treating a value over 365
  as a disqualifier (SS2.2 caps how many days are *paid*, not whether the claim
  "applies" at all). Not exercised by any of the nine questions; all nine claims use
  a small placeholder value (3).
