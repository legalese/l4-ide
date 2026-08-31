# Notes — prolog-unguided / t2

## Load check

Ran `swipl -q -g halt policy.pl queries.pl` twice.

- First run: loaded with exit code 0, but printed a series of `discontiguous` warnings,
  because `queries.pl` groups facts by claim (one block per question) rather than by
  predicate, so each of `age_at_hospitalization/2`, `hospitalization_cause/2`,
  `hospitalization_time/2`, `wellness_visit_time/2` and `wellness_confirmation_time/2` has
  its clauses scattered through the file.
- Added `:- discontiguous` directives for those five predicates at the top of `queries.pl`
  (as SWI's own warning suggested) and re-ran: **silent, exit code 0.**

I did not run `q1`..`q9` or otherwise query the encoding, per the task rules.

## Judgement calls

1. **Causal-nexus reading of the Section 2.1 occupation exclusions.** Items 2–4 of the
   general exclusions ("Service in the military", "Service as a fire fighter", "Service in
   the police") are worded as exclusions of an *event* "arising directly or indirectly out
   of" that activity — not exclusions of a *person* who holds that occupation. I modeled
   this with a single `hospitalization_cause/2` fact per claim representing the operative
   cause of the sickness or injury, and matched the exclusion against that cause, not
   against the claimant's job title or on-duty status at the time. This is the load-bearing
   call for **Q9** (son biting the claimant's ankle, claimant serving as a police officer at
   the time): I encoded the cause as `bitten_by_family_member`, not `police_service`, on
   the reading that "I was serving as a police officer at the time of hospitalization"
   describes the claimant's status, not the cause of the injury, and the exclusion requires
   the latter. A stricter (status-based) reading would instead treat any injury occurring
   while on police duty as excluded, which would flip Q9.

2. **Section 1.3 modeled as two independent deadlines**, both relative to the effective
   date: the wellness visit itself must occur within 6 months (`wellness_visit_time/2`),
   and written confirmation of it must reach the insurer within 7 months
   (`wellness_confirmation_time/2`). Failing either is, per Section 1.2, a failure to
   satisfy Section 1.3 "in a timely fashion", which cancels the policy. Where a question
   states only a confirmation/submission time (Q4, Q6, Q7, Q9), I read that as the
   `wellness_confirmation_time` and set `wellness_visit_time` to a value that satisfies its
   own deadline separately, since the questions never test the visit's own occurrence date
   and the standing preamble asks that unrelated conditions be satisfied.

3. **"Still pending" (Section 1.1(3)) needs no separate clock.** Rather than modeling a
   distinct "current time" apart from the relative times a query supplies, I rely on
   `policy.pl`'s `:- dynamic` declarations: if a claim asserts no fact for, say,
   `wellness_confirmation_time/2`, the corresponding disjunct of `wellness_condition_failed/1`
   simply fails (rather than raising an existence error), which is the same outcome as
   "condition still pending, not yet violated". In `queries.pl` I nonetheless assert an
   explicit, comfortably-compliant value for every such fact on every claim (rather than
   leaving any of them unstated), per the task's instruction to *set* facts that satisfy
   conditions unrelated to the question, rather than leave them merely undefined.

4. **Worldwide coverage (Section 3.1.1) is modeled by omission.** Since the policy
   affirmatively covers the claimant "twenty-four (24) hours a day anywhere in the world",
   I did not create any location fact or exclusion at all. Q4's "traveling abroad" is
   therefore a non-issue for coverage; the only operative fact in that question is the late
   wellness-visit confirmation (8 months, past the 7-month deadline), which cancels the
   policy under Section 1.2 independent of geography.

5. **Not modeled at all:** signing and premium payment (Section 1.1(1)–(2)), per the task's
   own instruction to assume these are satisfied and not encode them; arbitration
   procedure and time limits (Section 3.2), governing law (3.3), currency of payment (3.4),
   and premium payment mechanics (3.5) — these are procedural/administrative provisions
   that do not bear on whether "my policy will apply" to a given hospitalization, and none
   of the nine questions test them.

6. **Fraud/misrepresentation/material withholding kept as three separate predicates**
   (`fraud/1`, `misrepresentation/1`, `material_withholding/1`) rather than collapsed into
   one, to track Section 1.2's own three distinct grounds, even though none of the nine
   questions ever needs to distinguish between them (Q5 and Q8 only ever deny "fraud" or
   "fraud or misrepresentation", which is satisfied by asserting none of the three facts).
