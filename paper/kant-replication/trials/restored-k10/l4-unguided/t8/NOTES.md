# Notes on this encoding

## Check run

Ran (typecheck only, no evaluation, per the task rules):

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
```

Both printed `Check succeeded.` with exit code 0. I did not run `l4 run`, `#EVAL`
evaluation, or anything else that would evaluate the nine claims against `covered`.

## Judgement calls

1. **Relative-time-only modelling.** Per the task brief, every temporal fact in a claim
   (other than age) is a NUMBER of months elapsed since the effective date. This meant
   no calendar-date arithmetic (`daydate`/`YMD`) was needed anywhere; all of Section
   1.3's "7th/6th month anniversary" language and Section 4.6's "one year" term are
   modelled as plain `AT MOST 7` / `AT MOST 6` / `AT MOST 12` comparisons on
   months-after-effective-date.

2. **Section 1.3 has two distinct deadlines, both modelled.** "No later than the 7th
   month anniversary ... you will supply ... written confirmation ... of a wellness
   visit ... occurring no later than the 6th month anniversary" states two separate
   facts: the visit itself (<=6 months) and the supply of confirmation of it (<=7
   months). `policy.l4` models both as separate `Claim` fields. Every query that
   mentions this condition gives only a single number ("confirmation ... 8 months
   after", "proof ... provided 6.5 months after", etc.); I used that one number for
   *both* fields, since the query does not distinguish visit-time from
   confirmation-time and this is the most natural reading of a single reported
   milestone.

3. **Dropped the "still pending" limb of S1.1(3) as never independently operative
   here.** Section 1.1(3) requires the S1.3 condition to be "still pending or ... 
   satisfied in a timely fashion." I modelled only the "satisfied" branch. Reasoning:
   every one of the nine questions reports the wellness-visit facts (when relevant) as
   completed, historical events relative to the effective date, never as an open or
   undetermined status. If a confirmation is reported as having been supplied at month
   M, that fact itself entails that at least M months have already elapsed -- so "the
   7-month deadline has not yet been reached" (still pending) can never be true
   whenever M > 7. The pending limb therefore cannot rescue a late confirmation in any
   fact pattern shaped like this benchmark's queries, so omitting it from the
   operative check changes no answer while avoiding the need for an undefined
   "current time" fact that the task's relative-dates-only instruction suggests isn't
   needed.

4. **Section 1.2's cross-reference to "the policy term described in Section 5 below"
   looks like a drafting slip.** Section 5 in the source is "Benefit and Premium
   Amounts" ($500/day, $2000 premium); the policy term is actually defined in Section
   4.6 ("will last for a period of one year from [the effective] date"). I used the
   substantive one-year term from 4.6 rather than propagating the mis-citation.

5. **Section 2.2's "hospital in the United States" limitation is treated as a real,
   independent condition on payment**, alongside (not overridden by) Section 4.1.1's
   "insures You ... anywhere in the world." I read 4.1 as defining the
   temporal/geographic scope of being insured (an accident or sickness abroad is not
   itself outside the policy), while 2.2 separately conditions the *benefit payment*
   on the confinement being in a U.S. hospital. For Q4 ("hospitalized due to a fall
   while traveling abroad"), I read the hospitalization itself as having occurred
   abroad and set `hospital located in the United States` = FALSE. This is the more
   consequential of two independent reasons my encoding finds Q4 unfavourable to the
   claimant (the other being the late wellness-visit confirmation); I flag it because
   a different reading of "traveling abroad" (e.g., injured abroad but hospitalized
   after returning to the US) would flip this one fact.

6. **Section 3.1 items 1-4 require a causal nexus ("arising directly or indirectly out
   of"), not mere status/profession.** Modelled each as a Boolean fact about
   *causation* (`sickness or injury arose from service in the police`, etc.), not
   "claimant is a police officer / firefighter / etc." This is the reason Q1 ("burns
   ... while doing my duty as a firefighter") and Q8 ("injured in a military training
   exercise") set their respective causal flags TRUE, while Q9 (claimant "serving as a
   police officer at the time of hospitalization" but injured by "my son biting me in
   the ankle") sets `arose from service in the police` = FALSE: the query gives a
   profession-at-the-time fact and a cause fact separately, and the cause has no
   connection to police duties.

7. **Section 3.1 item 5 (age >= 80) is modelled as a standalone, non-causal
   exclusion**, even though it is grammatically appended to a list otherwise governed
   by "arising ... out of." ("Arising out of ... if your age is >= 80" does not parse
   as a causal claim.) I treat it as an independent fifth disjunct.

8. **Did not read an unstated self-inflicted/intentional-injury exclusion into
   Section 2.1's "accidental Injury" for Q5** (hospitalized for "punching my own face
   to show off for my friends"). Section 3.1, "GENERAL EXCLUSIONS," is an explicit,
   enumerated, closed list of five grounds that does not mention self-inflicted or
   intentionally-caused injury. Rather than import an intent-based carve-out from the
   word "accidental" that the enumerated exclusions list does not itself state, I
   treated `confined due to sickness or injury` as satisfied and left exclusion to
   turn solely on the five enumerated grounds (none of which Q5's facts meet). This is
   a genuine judgement call the other way is defensible (an ordinary-meaning reading
   of "accidental" as excluding deliberate acts) but I preferred not to add a ground
   the drafter did not enumerate.

9. **Claim-notice mechanics (S2.3) and the assumed signing/premium conditions are
   uniform across all nine questions**, since none of the nine benchmark questions
   concern claim-submission procedure. `claim made to the Company` = TRUE and (per the
   task brief) signing/premium are not modelled at all.

10. **Omitted purely administrative clauses that do not bear on the yes/no coverage
    question**: arbitration (4.2), governing law (4.3), currency (4.4), premium-timing
    mechanics (4.5), and the specific dollar amounts in Section 5 (the $500 daily
    benefit, the $2000 premium, and the 365-day cap in 2.2). None of the nine
    questions ask about dispute process, amounts, or duration -- only whether the
    policy applies -- so these were left out of `policy.l4` to keep every defined
    function one that is actually exercised by the benchmark's `covered` question.

11. **Defaults for facts a given question does not mention** (per the task's
    instructction to satisfy unrelated conditions and not trigger unrelated
    exclusions): wellness-visit facts default to month 0; no fraud/misrepresentation;
    hospitalization month defaults to a small in-term value (or the value a question
    states/implies, e.g. Q3's 5 months, Q8's "within the policy term"); confined-due-
    to-sickness-or-injury = TRUE; hospital-in-US = TRUE (Q4 is the sole exception);
    claim-made = TRUE; all four causal exclusion flags FALSE except the one a
    question's own facts affirmatively state; age defaults to 40 when not mentioned.
