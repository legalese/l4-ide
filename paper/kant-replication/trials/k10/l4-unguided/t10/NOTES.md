# NOTES

## Checks run

- `JL4_LIBRARY_PATH=<repo>/jl4-core/libraries l4 check apply.l4` (which transitively checks
  `policy.l4` via `IMPORT policy`) -> **`Check succeeded.`**
- `JL4_LIBRARY_PATH=<repo>/jl4-core/libraries l4 check policy.l4` standalone -> **`Check succeeded.`**

No `#EVAL` was run and no evaluation output was inspected, per the rules of this trial. Only
typechecking was performed.

## Judgement calls

1. **Time representation.** All times other than age are encoded as a plain `NUMBER` of months
   elapsed since the policy's effective date (e.g. `hospitalization month`, `wellness visit
month`, `wellness confirmation month`), per the task's instruction that every query gives
   times relative to the effective date. No `DATE`/`DATETIME` type or arithmetic is used anywhere.

2. **Splitting Section 1.3 into two sub-deadlines.** The clause requires both (a) the wellness
   visit itself to occur by the 6-month anniversary, and (b) written confirmation of it to be
   supplied by the 7-month anniversary. I modelled these as two separate `MAYBE NUMBER` fields on
   `Claim` (`wellness visit month`, `wellness confirmation month`) so the two deadlines are
   checked independently, matching the literal text.

3. **The "pending vs. violated" reading of Section 1.1, item 3.** The policy text says the
   Section 1.3 condition must be "still pending or ... satisfied in a timely fashion" for the
   policy to be in effect. I read "still pending" as: the relevant deadline (month 6 for the
   visit, month 7 for confirmation) has not yet passed as of the hospitalization, so nothing can
   yet be said to be late. Concretely, when a `MAYBE NUMBER` field is `NOTHING` (the event hasn't
   happened), I test `hospitalization month GREATER THAN` the deadline rather than treating an
   absent event as automatically late. When the field is `JUST m`, lateness is `m GREATER THAN`
   the deadline, independent of the hospitalization month (once an event has actually happened,
   whether it met its deadline is a fixed fact, not one that depends on when the claim was later
   made).

4. **None of the nine questions state when the wellness visit itself (as opposed to the written
   confirmation of it) took place.** Four questions (Q4, Q6, Q7, Q9) give a month for when
   confirmation/proof of the visit was "provided" or "submitted," but none give a separate month
   for the underlying visit. Per Step 2's instruction to satisfy every condition unrelated to a
   given question, I set `wellness visit month` to `JUST 1` (comfortably inside the 6-month
   deadline) in every one of the nine claims, isolating the confirmation-deadline fact as the only
   thing under test in those four questions. I recorded this as a deliberate, uniform default
   rather than trying to infer a visit date from the confirmation date.

5. **Q4's late confirmation (month 8) does not need a matching late hospitalization month.**
   Because lateness for an already-`JUST`-provided confirmation is checked against the deadline
   alone (see judgement call 3), the hospitalization month is irrelevant once confirmation is
   known to be late. I set `hospitalization month IS 1` for Q4 (and, for uniformity, for every
   question that doesn't give an explicit hospitalization month), rather than contriving a later
   hospitalization month to "unmask" the lateness -- it turned out not to be necessary.

6. **Q8: "military training exercise."** Read as service in the military for purposes of Section
   2.1, item 2 -- a training exercise undertaken as part of one's military service is still
   "service in the military," so the cause is excluded outright, independent of the
   within-policy-term and no-fraud facts the question also volunteers.

7. **Q9: being a police officer "at the time of hospitalization" vs. the cause of the injury.**
   Section 2.1 excludes injury "arising directly or indirectly out of ... service in the police,"
   not injury suffered by a person who happens to be a police officer. Q9's cause (the claimant's
   son biting his ankle) has no connection to police duties, so I encoded the cause as `Other`,
   not `` `Police Service` ``, and the claimant's occupation is otherwise not represented on
   `Claim` at all (only the causal link matters under the text).

8. **Q5: self-inflicted horseplay is not an exclusion.** The Section 2.1 exclusion list is closed
   (skydiving, military service, firefighting, police service, age >= 80); it does not mention
   self-inflicted injury or recklessness generally, so I did not add such an exclusion. The
   question's own "I did not commit fraud or misrepresentation" clause is encoded via `fraud or
misrepresentation IS FALSE`.

9. **Sections not modelled as coverage rules.** Section 1.1 items 1-2 (signed; premium paid) are
   assumed true per the task instructions and have no field. Section 3.1 (worldwide, 24-hour
   coverage) is why no geographic field exists on `Claim` at all -- "traveling abroad" in Q4 has
   nothing to attach to. Sections 3.2-3.5 (arbitration, currency, governing law, premium-payment
   timing) are procedural/administrative and do not bear on whether a given hospitalization is
   covered, so no rules were written for them, consistent with the task's framing of "rules that
   can be used to answer queries on this insurance contract."

10. **End of policy term.** Section 3.6 / 1.2's "last day of the policy term" (one year from the
    effective date) is encoded as `hospitalization month GREATER THAN 12` inside `` `policy
canceled` ``. None of the nine questions approach this boundary (the largest relative time
    figure used anywhere is 8 months), so this rule is not exercised in a way that would be
    sensitive to exactly where the boundary is drawn.
