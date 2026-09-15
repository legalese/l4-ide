# Notes on this encoding

## Load check

Ran `swipl -q -g halt policy.pl queries.pl` from the trial directory root.

- First attempt produced 16 `discontiguous`-clause warnings (no errors; exit
  code 0) because `queries.pl` groups facts by question rather than by
  predicate, and `hospitalized/1`, `age_at_hospitalization/2`, and
  `wellness_confirmation_month/2` each recur across several question blocks.
- Added `:- discontiguous(...)` declarations for those three predicates at
  the top of `queries.pl` (the fix SWI itself suggests) and re-ran.
- Second run: **silent, exit code 0.** No warnings, no errors. I did not run
  q1..q9 or any other query against the encoding, per the rules.

## Judgement calls

1. **Section 1.3's two internal deadlines collapse to one check.** The text
   sets two different deadlines: the wellness visit itself must occur "no
   later than the 6th month anniversary," and written confirmation of it
   must be supplied "no later than the 7th month anniversary." Every
   question that mentions this only gives a single relative time -- when
   proof/confirmation was "provided," "given," or "submitted" -- with no
   separate figure for when the underlying visit happened. I encoded
   `condition_1_3_ok/1` to check that single reported time against the
   7-month (confirmation-supply) deadline, and did not separately model or
   default-fail the 6-month (visit-occurred) sub-deadline, since no fact in
   any question speaks to it directly and inventing a stricter reading would
   go beyond what's given. Where no confirmation time is given at all, I
   fall back to checking the hospitalization time (if known) against month
   7, and otherwise default to "condition not yet due / fine," consistent
   with 1.1(3)'s "still pending" language and with the instruction to treat
   facts unrelated to a question as satisfied.

2. **"Service in the police" (and the other 3.1 service exclusions) require
   a causal link, not mere status.** Section 3.1 excludes an injury
   "arising directly or indirectly out of" skydiving/military/firefighting/
   police service. Q9 states the claimant "was serving as a police officer
   at the time of hospitalization" but the injury itself was a dog-bite-like
   incident (the claimant's son biting their ankle) with no stated
   connection to police duties. I read this as status-without-causation and
   did not assert `caused_by_police_service` for that claim, in contrast to
   Q1 and Q8, which each state the injury arose directly while performing
   the relevant duty ("while doing my duty as a firefighter,"
   "in a military training exercise") and so do get the corresponding
   exclusion fact asserted.

3. **No exclusion for intentionally self-inflicted injury.** Q5 describes a
   hospitalization from punching one's own face "to show off," while stating
   no fraud or misrepresentation occurred. Section 3's General Exclusions
   list only skydiving, military service, firefighting service, police
   service, and age >= 80 -- there is no exclusion in the text for
   self-inflicted or intentionally caused injury. I therefore encoded no
   such exclusion; `excluded/1` has no clause that could fire for this
   scenario, and the explicit absence of fraud removes the one textual route
   (Section 1.2's cancellation-for-fraud trigger) by which this claim could
   have failed.

4. **Worldwide territorial scope is a non-exclusion, encoded by omission.**
   Section 4.1.1 insures the claimant "twenty-four hours a day anywhere in
   the world." Q4's "traveling abroad" detail is therefore not modelled as
   an exclusion at all -- there simply is no location-based rule in
   `excluded/1` for it to trigger.

5. **Scoped out as not bearing on any of the nine yes/no coverage
   questions:** the arbitration/dispute-referral mechanics of Section 4.2
   (about a precondition to recovering on a claim once a dispute exists, not
   about whether the policy covers the event), the governing-law (4.3),
   currency (4.4), and premium-payment-mechanics (4.5) clauses, and the
   365-day/24-hour confinement-period benefit-amount mechanics of Section
   2.2 (about how much and for how long a benefit is paid, not whether the
   policy applies at all). None of the nine questions turn on any of these,
   and the task brief separately stipulates that signing and timely premium
   payment are already assumed true.

6. **Baseline defaults to "covered."** Because every optional fact predicate
   in `policy.pl` is written so that its absence keeps the corresponding
   condition satisfied or exclusion untriggered, each question in
   `queries.pl` only asserts the facts the question text actually states
   (plus `hospitalized/1`, required for every claim). This directly
   implements the standing preamble ("assuming all other conditions are met
   and no other exclusions apply") and the output contract's instructions
   to set unrelated conditions/exclusions to their non-blocking values.
