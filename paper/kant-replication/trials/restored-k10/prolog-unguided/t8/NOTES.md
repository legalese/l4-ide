# Notes on this encoding

## Load check

Ran `swipl -q -g halt policy.pl queries.pl` from the trial directory.

- First attempt printed 20 `Warning: ... Clauses of claim_*/N are not together in the
source-file` warnings (SWI groups clauses by predicate name/arity and warns when a
  predicate's clauses are interleaved with other predicates' clauses across the file).
  Declaring the predicate `dynamic` did **not** suppress this warning by itself.
- Fixed by adding explicit `:- discontiguous claim_cause/2, claim_activity/2, claim_age/2,
claim_confirmation_month/2.` declarations at the top of `queries.pl` (these are the four
  claim-fact predicates that are asserted once per claim, grouped by claim rather than by
  predicate, across the file).
- Second run: **silent**, exit code 0. No warnings or errors.

Per the rules, I did not call `q1`..`q9` or otherwise test the encoding against the nine
questions.

## Judgement calls

1. **Section 3 exclusions require causation, not mere status.** The exclusion text is "any
   event causing sickness or accidental injury arising directly or indirectly out of:
   [skydiving / military service / firefighting / police service]". I read this as requiring
   the sickness/injury-causing event itself to arise from the listed activity, not merely
   that the claimant held that occupation "at the time" of hospitalization. This is why
   `policy.pl`'s `activity_exclusion/1` is keyed off a `claim_activity/2` fact that
   `queries.pl` only asserts when the question's own wording ties the injury causally to the
   activity ("while doing my duty as a firefighter", "injured in a military training
   exercise", "injury sustained while skydiving") and deliberately withholds it for the one
   question that states an occupation/status without a causal link to the injury (son biting
   claimant's ankle, while claimant "was serving as a police officer at the time" -- a
   temporal/status statement, not a causal one). This is the one judgement call in this
   encoding that is outcome-determinative on its own (it is the difference between the
   claim being excluded and not), so it is worth a reviewer's particular attention.

2. **"Accidental Injury" excludes deliberate self-inflicted acts.** Section 2.1 only pays
   for hospitalization "as a result of sickness or accidental Injury". I read "accidental"
   as doing real work here (as opposed to being decorative next to "sickness"): a
   deliberate act -- punching one's own face on purpose to show off -- is not an accident in
   the ordinary sense, so it satisfies neither "sickness" nor "accidental injury", and fails
   to trigger coverage at all under 2.1, independent of the Section 3 exclusion list (which
   has no explicit "self-inflicted injury" exclusion) and independent of Section 1.2's
   fraud/misrepresentation cancellation ground (which the question explicitly disclaims).
   Encoded via a `claim_cause/2` value (`intentional_self_harm`) that is neither `sickness`
   nor `accidental_injury`.

3. **Section 2.2's "hospital in the United States" is taken literally, in tension with
   Section 4.1's "insures You ... anywhere in the world".** These two clauses are in genuine
   tension: 4.1 states the policy covers the claimant worldwide, but 2.2 specifically
   restricts payability of the Daily Hospital Income Benefit to confinement "in a hospital in
   the United States". Rather than resolving this in the claimant's favour, I encoded 2.2
   literally as an additional condition on `triggers_benefit/1` (`hospital_in_us/1`), on the
   view that 2.2 is the operative, benefit-specific provision and 4.1 is a general statement
   of risk scope that does not textually override it. In the one question this affects
   (hospitalization while traveling abroad), the claim is independently denied on a second,
   unambiguous ground (written confirmation of the wellness visit given after the Section 1.3
   deadline), so this particular judgement call does not change that question's outcome by
   itself -- but it is encoded as a general rule and would bind on a hypothetical claim that
   raised only the location issue.

4. **Section 1.3's two sub-deadlines (visit by month 6, confirmation by month 7) are kept as
   two separate facts (`claim_visit_month/2`, `claim_confirmation_month/2`), each defaulting
   to month 0 (compliant) when a question does not separately address it.** Every question
   that mentions wellness-visit timing phrases it as when confirmation/proof was "provided"
   or "submitted", never as a separate visit date, so in every such case only
   `claim_confirmation_month/2` is asserted and `claim_visit_month/2` is left at its default.
   This means the stricter 6-month visit sub-deadline is faithfully encoded as a rule but is
   not actually exercised by any of the nine questions as I've encoded their facts -- it
   would only bind on a hypothetical claim that separately reported a late underlying visit.

5. **Section 1.1(3)'s "still pending or has been satisfied in a timely fashion" and Section
   1.2's "has not been satisfied in a timely fashion" cancellation ground are modelled as
   two sides of the same fact**, via a single `wellness_condition_ok/1` predicate rather than
   two independently-tracked conditions: if the Section 1.3 deadlines have not yet been
   reached (or have been met), the condition is compliant; only a genuine, reported miss (a
   confirmation or visit month past its deadline) counts as failure and triggers
   cancellation. I did not build a fuller temporal model of retroactive cancellation (e.g., a
   hospitalization that occurs before month 6 remaining covered even if the claimant later
   misses the month-7 deadline); none of the nine questions require that distinction given
   how I've filled in their facts.

6. **Sections 2.3 (claim-filing mechanics), 4.2 (arbitration), 4.3 (NY governing law), 4.4
   (US currency) and 4.5 (premium-payment mechanics) are not modelled as coverage
   conditions.** They are procedural/boilerplate terms that do not bear on whether a
   described hypothetical event is a covered event, and the task instructions already
   stipulate signature and timely premium payment as given.

7. Conditions 1 (agreement signed) and 2 (premium paid) of Section 1.1 are not modelled at
   all, per the task instructions to assume both are satisfied and to encode no rules or
   facts for them.
