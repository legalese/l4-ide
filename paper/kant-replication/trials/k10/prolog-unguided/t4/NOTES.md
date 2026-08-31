# Notes — prolog-unguided / t4

## Load check

Ran (as permitted, nothing more):

```
swipl -q -g halt policy.pl queries.pl
```

First attempt printed ~30 `Warning: ... Clauses of <pred>/2 are not together in the
source-file` warnings (harmless, but not silent): `:- dynamic` in `policy.pl` only
suppresses the *cross-file* "already defined elsewhere" warning, not SWI's within-file
discontiguous-clause check, and `queries.pl` groups facts by claim/question (for
readability) rather than by predicate, so each fact predicate's clauses are genuinely
scattered through the file. Fix: added explicit `:- discontiguous` directives for the six
claim-fact predicates at the top of `queries.pl`. Re-ran the exact command above afterwards:
exit code 0, zero output on stdout/stderr. The load is silent, as required.

I did not run q1..q9 and did not otherwise test the encoding against the nine questions.

## Judgement calls

1. **Two Sec. 1.3 deadlines, one date given per question.** Sec. 1.3 imposes two separate
   deadlines: the wellness visit itself must occur by the 6-month anniversary, and written
   confirmation of it must be supplied by the 7-month anniversary. `policy.pl` models both
   as independent facts (`wellness_visit_occurred/2`, `wellness_confirmation_submitted/2`)
   checked against their own fixed threshold. But every question that mentions this
   condition (Q4, Q6, Q9) gives only a single date ("confirmation ... provided N months
   after..."). I read that single date as fixing *both* facts at N — i.e., that the
   sentence describes one bundled event (visit-and-its-confirmation), not a confirmation
   trailing some unstated earlier visit. Under this reading the binding constraint always
   ends up being the earlier 6-month threshold. This didn't end up being outcome-determinative
   for any of the nine: Q4 (N=8) and Q6 (N=6.5) fail the 6-month test either way (and Q6 is
   independently excluded via skydiving regardless), and Q9 (N=6) passes both thresholds at
   once. Still, it is a real interpretive choice and a different question set could turn on it.

2. **Dropped hospitalization-time-relative "still pending" reasoning.** Sec. 1.1(3)/1.2 read
   literally ask whether, *as of the time of hospitalization*, the Sec. 1.3 condition was
   "still pending" (deadline not yet due) or "satisfied in a timely fashion" — a genuinely
   time-indexed disjunction that would require comparing the hospitalization date against
   the confirmation date. TASK.md instead says no query will ever require calculating
   elapsed time *between two dates*. I took that as a deliberate signal to simplify: treat
   the Sec. 1.3 condition as resolved by the single wellness-visit fact if the query
   supplies one (checked only against the contract's own fixed thresholds), and as simply
   not in issue (`condition_1_3_ok/1`'s first clause) if the query is silent on it — never
   comparing hospitalization time against wellness-visit time. I verified this simplification
   doesn't silently flip any of the nine answers versus the stricter time-indexed reading
   before committing to it.

3. **Q5 (punching own face to show off) fails the basic coverage trigger, not an
   exclusion.** Sec. 1.1 only ever pays for hospitalization "for sickness or accidental
   injury." Nothing in the General Exclusions (Sec. 2.1) mentions self-inflicted or
   intentional acts, but a deliberate act done to show off for friends is not, in ordinary
   sense, an *accident*. I encoded `hospitalization_cause(claim_5,
   intentional_self_inflicted_act)`, an atom that matches neither `sickness` nor
   `accidental_injury` in `qualifying_hospitalization/1`, so the claim fails Sec. 1.1
   itself rather than being caught by Sec. 2. The question's express denial of "fraud or
   misrepresentation" reads as forestalling the *other* plausible objection (Sec. 1.2
   cancellation-for-fraud); I did not need to encode that denial as a fact either way, since
   `fraud_or_misrepresentation/1` is only ever asserted where a claim actually alleges it.

4. **Q9 (police officer bitten by own son) — causal nexus, not occupational status.**
   Sec. 2.1's chapeau excludes sickness/injury "arising directly or indirectly out of" the
   five listed items; items 1-4 are activities, and the text requires the injury to arise
   *from* the activity, not merely to coincide with the claimant's occupation. Q1
   ("burns ... while doing my duty as a firefighter") and Q8 ("injured in a military
   training exercise") both supply that causal link explicitly. Q9 does not: the ankle bite
   has no connection to police duties, so I did not assert `activity(claim_9,
   police_service)`, and the claim is not excluded on that ground. This is the crux of Q9
   and the one place I'd flag as most likely to be argued the other way.

5. **Scope of what got executable rules.** Sec. 3.1 (worldwide/24-hour cover) is encoded by
   omission — deliberately writing no territorial exclusion. Sec. 3.2 (arbitration as a
   condition precedent to liability where a dispute exists) is encoded as a real predicate
   (`arbitration_condition_satisfied/1`) that defaults to true when no dispute is asserted,
   which is the case for all nine questions, so it's present for faithfulness but inert
   here. Sec. 3.3-3.5 (governing law, currency, lump-sum premium timing) and the Sec. 3.2
   sixty-day post-proof-of-claim waiting period are administrative/procedural rather than
   substantive coverage conditions, and none of the nine questions asks about litigation
   timing — I left these as comments rather than building unused executable predicates for
   them, to avoid adding untested logic with no bearing on any of the nine answers.

6. **Defaults for facts a question doesn't mention.** Per TASK.md Step 2 (6)-(7), for any
   condition or exclusion a question doesn't reference, I set facts so the condition is met
   / the exclusion doesn't fire: age defaults to 30 (well under the Sec. 2.1.5 threshold of
   80) wherever a question omits age; `hospitalization_cause(claim_2, sickness)` is a
   default stand-in cause for Q2, which asks only about age. No `activity/2` fact is
   asserted unless the question ties the injury to one of the four listed activities, and
   no `fraud_or_misrepresentation/1` or `dispute_exists/1` fact is ever asserted, since no
   question alleges either.

7. **`:- dynamic` on every claim-fact predicate in `policy.pl`.** Declared for
   `hospitalization_cause/2`, `hospitalization_time/2`, `age_at_hospitalization/2`,
   `activity/2`, `wellness_visit_occurred/2`, `wellness_confirmation_submitted/2`,
   `fraud_or_misrepresentation/1`, `dispute_exists/1`, `valid_arbitration_award/1`, and
   `arbitration_commenced_in_time/1`. Four of these (fraud, dispute, arbitration-award,
   arbitration-timing) end up with zero facts across all nine claims — without `dynamic`
   that would raise an "unknown procedure" existence error the first time `covered/1` tried
   `fraud_or_misrepresentation(Claim)` for a claim with no such fact, rather than simply
   failing as intended.
