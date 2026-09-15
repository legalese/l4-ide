# Notes

## Load check

Ran exactly the sanctioned command from `inputs/TASK.md`:

```
swipl -q -g halt policy.pl queries.pl
```

Exit code 0, and both stdout and stderr were empty (checked by redirecting each to a
separate file and inspecting them). No warnings (e.g. no "discontiguous", no
"singleton variable", no "procedure does not exist"). I did **not** run `q1` .. `q9`
or otherwise query the loaded database, per the rules.

## Judgement calls

1. **Per-claim keying.** The task's own example (`q1 :- covered(claim_1).`) implies
   `covered/1` takes a claim identifier, so every dynamic predicate in `policy.pl` is
   keyed on that same identifier (`Claim` as first argument). Without this, facts
   asserted for one question (e.g. an age for Q2) would leak into every other
   question's evaluation, since all nine `qN` facts live in one `queries.pl` loaded
   into a single global database at once.

2. **"Unrelated conditions/exclusions default to satisfied" is implemented as a
   structural property of `policy.pl`'s rules**, not as explicit dummy facts added
   per claim in `queries.pl`. E.g. `wellness_condition_met/1` and
   `within_policy_term/1` fall through to `true` when the relevant fact was never
   asserted for a claim, and `excluded/1`'s clauses simply fail to match when no
   matching fact exists. I considered the alternative of leaving the rules strict and
   instead asserting an explicit favourable fact for every unrelated condition on
   every claim (e.g. a dummy `hospitalization_time_months(claim_1, 0)` for Q1 purely
   to satisfy the wellness-visit clause), but that reads as more fragile (easy to
   forget one) and less reusable as a general-purpose policy engine, which is what
   Step 1 asks for ("so that a Prolog query can be run on the code regarding whether
   or not **some claim** is covered" — not just these nine). Task instruction 6/7
   for Step 2 also names "rules" as well as "facts/parameters" as legitimate places
   to secure this, which supports doing it in `policy.pl`'s rules.

3. **Section 1.3's two deadlines, and how a single reported timestamp maps onto
   them.** Section 1.3 sets two distinct dates: the wellness visit itself must occur
   no later than the 6-month anniversary, and written confirmation of it must be
   supplied no later than the 7-month anniversary. Four questions (Q4, Q6, Q7, Q9)
   report only one number ("proof/confirmation of the wellness visit was
   provided/submitted X months after the effective date"), with no separate date for
   when the visit itself took place. `policy.pl` models both dates as separate
   dynamic facts (`wellness_visit_time_months/2` and
   `wellness_confirmation_time_months/2`), but since the questions only ever give one
   timestamp, I encoded that single value as `wellness_confirmation_time_months/2`
   only, and had the policy's fallback rule (when no separate visit date is on
   record) test that same value against **both** the 6-month and 7-month thresholds,
   on the reasoning that a report of "proof was provided at time X" is the only
   evidence available of when the visit happened, so it is the figure that has to
   clear both bars absent better information. The alternative reading — treat the
   unstated visit date as an "unrelated" fact and default it to compliant regardless
   of X — would only change the outcome for Q6 (X = 6.5, i.e. strictly between the
   two thresholds); every other such question's value (8, 2, 6) clears or fails both
   thresholds together, so the choice is immaterial there. It is immaterial for Q6
   too, because Q6's claim is independently excluded outright by the skydiving
   ground (Sec 2.1 item 1), so this judgement call does not change any of the nine
   answers either way. Flagging it because it is the one point in the encoding where
   the fixture is genuinely underspecified rather than merely terse.

4. **Exclusions attach to the cause of the injury, not to the claimant's status or
   occupation.** Section 2.1 excludes an event "causing sickness or accidental injury
   arising directly or indirectly out of" skydiving/military/firefighting/police
   service. `injury_arises_from/2` is written to require that the injury itself stem
   from the listed activity. This matters for Q9: the claimant "was serving as a
   police officer at the time of hospitalization," but the injury (a bite from the
   claimant's own son) plainly did not arise out of that service, so
   `injury_arises_from(claim_9, police_service)` is deliberately not asserted. Q1 and
   Q8, by contrast, describe the injury itself as arising from the duty (burns "while
   doing my duty as a firefighter"; injury "in a military training exercise"), so
   those are asserted.

5. **Section 3.2 (arbitration / dispute resolution)** is translated for completeness
   of Step 1 (a full translation of the contract, not just of the nine questions),
   but none of the nine questions raise a dispute, so `arbitration_precondition_met/1`
   is a structural no-op for all nine claims (verified by inspection: none of
   `dispute_exists/1`, `arbitration_commenced_in_time/1`,
   `valid_arbitration_award_issued/1` or `seeking_recovery_before_60_days/1` is
   asserted anywhere in `queries.pl`, so the predicate reduces to `true` for every
   claim). Sections 3.3 (governing law), 3.4 (currency) and 3.5 (premium paid as a
   lump sum, already assumed true per the task brief) are administrative terms with
   no bearing on whether a claim is covered, so they were not given coverage rules of
   their own; Section 3.1 (worldwide, 24-hour coverage) is reflected by the simple
   absence of any territorial exclusion, which is what lets Q4's "traveling abroad"
   fact pass without any special-casing.

6. **Q8's "hospitalization occurred within the policy term"** is not encoded as a
   specific `hospitalization_time_months/2` value, because no actual number is given
   and asserting an arbitrary one would manufacture specificity the question does not
   contain. `within_policy_term/1` already defaults to `true` when no such fact is
   asserted, which is exactly what "within the policy term" amounts to here.
