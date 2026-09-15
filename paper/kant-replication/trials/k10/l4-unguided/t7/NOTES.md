# Notes on this encoding

## Checks run

- Ran `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4` (which also typechecks
  `policy.l4`, since `apply.l4` imports it) and separately `l4 check policy.l4`. **Both succeeded**
  ("Check succeeded.") on the final version of the files.
- Did **not** run `l4 run` and did not evaluate any `#EVAL` directive, per the task rules.
- One check failure occurred along the way and was fixed before the final check: my first draft
  wrote every rule as `` `name` claim IS <body> `` without a leading `DECIDE` keyword. L4 only
  allows the bare (no-`DECIDE`) form with `MEANS`; `IS` (and `IF`) require an explicit `DECIDE`.
  The parser error was `unexpected IS, expecting (, AKA, EXACTLY, ... MEANS, ...`. Fixed by
  rewriting all seven top-level rules in `policy.l4` to use `claim MEANS` instead of `claim IS`
  (no behavioural difference — `IS`/`MEANS` are the same construct, `MEANS` is just the
  DECIDE-optional spelling).

## Judgment calls

1. **All times as relative months, no `DATE` type at all.** Per the task instructions, every
   time in a query (other than the claimant's age) is relative to the effective date, so
   `policy.l4` never imports `daydate` and represents "N months after the effective date" as a
   plain `NUMBER`. Thresholds drawn from the text (6, 7, and 12 months) are compared directly.

2. **Harmonizing §1.1(3) and §1.2 on the wellness-visit condition.** §1.1(3) keeps the policy in
   effect if §1.3 "is still pending **or** has been satisfied in a timely fashion"; §1.2 cancels
   the policy if §1.3 "has **not** been satisfied in a timely fashion." Read completely literally,
   these two clauses conflict: if confirmation merely hasn't been supplied _yet_ (well within the
   grace period), it is arguably also true that it "has not been satisfied" in the present-perfect
   sense, which would trigger cancellation from day one and make the 7-month grace period
   meaningless. I resolved this by treating §1.2's trigger as the logical negation of §1.1(3)'s
   full disjunction (pending-or-satisfied), which is the only reading under which the grace period
   in §1.3 can ever actually be relied on. This is encoded as a single predicate,
   `` `condition 1.3 is satisfied or still pending` ``, used (positively) in
   `` `policy is in effect...` `` and (negated) in `` `policy has been canceled` ``.

3. **§1.3's two sub-deadlines are modeled asymmetrically.** §1.3 requires (a) written confirmation
   supplied no later than month 7, of (b) a wellness visit that itself occurred no later than
   month 6. Field (a) is `` `wellness visit confirmation month` `` (`MAYBE NUMBER`: `NOTHING` =
   not yet supplied). Field (b) is a plain `BOOLEAN`,
   `` `wellness visit occurred no later than the 6th month` ``, rather than a second relative-month
   number — because none of the nine benchmark queries independently states when the underlying
   visit itself occurred; they only ever state when confirmation/proof was "given," "provided," or
   "submitted." `apply.l4` sets this flag `TRUE` for every query (the unrelated-condition default).

4. **The four §2.1 activity exclusions are causal, not occupational.** The text excludes an event
   "arising directly or indirectly out of" skydiving/military/firefighting/police service — so the
   `Claim` fields are named `` `event arose out of ...` ``, not "claimant is a ...". This is the
   operative call in **Q9**: the claimant is "serving as a police officer at the time of
   hospitalization," but the injury is "my son biting me in the ankle" — a domestic incident with
   no causal link to police duties. I set `` `event arose out of service in the police` `` to
   `FALSE` for Q9, reading the occupation-at-the-time fact as status, not cause. (Contrast Q1 and
   Q8, where the query itself supplies the causal link: "burns suffered while doing my duty as a
   firefighter," "injured in a military training exercise" — both set `TRUE`.)

5. **Q5 (punching own face to "show off") is treated as an accidental injury.** The contract
   conditions payment on "hospitalization for sickness or accidental injury" (§1.1.1) but §2.1's
   exclusion list has no self-inflicted-injury or intentional-injury item. Under the ordinary
   "accidental result" reading (a voluntary act with an unintended, unwanted outcome is still
   "accidental"), and absent any textual exclusion on point, I set
   `` `hospitalization is for sickness or accidental injury` `` to `TRUE` for Q5. This is the
   judgment call I am least certain about in this encoding — a stricter "accidental means" reading
   would treat the deliberate punch itself as disqualifying, which the text does not clearly
   compel either way.

6. **Q8's "hospitalization occurred within the policy term" is encoded via the month field, not a
   separate boolean.** `policy.l4` tests term membership as
   ``claim's `hospitalization month` GREATER THAN 12`` (§3.6: one year from the effective date).
   Since Q8 states term-membership as a bare fact rather than a number, I set
   `` `hospitalization month` `` to `0`, which trivially satisfies it, rather than adding a second,
   independent "within term" primitive to the schema.

7. **§3.2 arbitration is encoded as a real (if never-exercised) condition precedent.** "The
   issuance of a valid arbitration award shall also be a condition precedent to our liability,"
   but only "where there is a dispute or disagreement." Modeled as
   `NOT dispute OR valid-award-issued`, with `dispute exists between the parties = FALSE` in every
   one of the nine queries (none of them raise a dispute), so this predicate is always satisfied
   here but is present for isomorphism with the text.

8. **§3.1 (territorial scope), §3.3 (New York law), §3.4 (US currency), §3.5 (lump-sum premium)
   are not encoded as predicates.** §3.1 is an unconditional worldwide grant (relevant to Q4's
   "traveling abroad," which is therefore not treated as any kind of exclusion); §3.3-3.5 are
   procedural/payment-mechanics terms that do not bear on whether a given hospitalization is
   covered. Each is left as a comment in `policy.l4` referencing its section number, per the
   isomorphic-encoding principle, without adding a no-op predicate to `covered`.

9. **Sections 4 and 5 are absent from the source fixture.** §3.6 refers to "the policy term
   described in Section 5 below," but the supplied contract text ends at §3.6 with no Section 4 or
   5 present. I used the one-year term stated directly in §3.6 (encoded as 12 months) as the only
   available term length, since no other figure is given anywhere in the text.

10. **Ages and hospitalization months not mentioned by a query default to values that trivially
    satisfy every unrelated condition**: age defaults to 40 (well under the 80 exclusion
    threshold) and hospitalization month defaults to 0 (within the 12-month term, and within the
    7-month wellness-visit grace period), per the task's instruction to set unrelated
    values/parameters so that all unrelated conditions are satisfied and no unrelated exclusion is
    triggered.
