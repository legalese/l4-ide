# NOTES

## Load check

Ran the permitted load check twice, per the task rules (q1..q9 were never called):

```
swipl -q -g halt policy.pl queries.pl
```

First run: exit code 0, but with ~60 `discontiguous` warnings, e.g.:

```
Warning: .../queries.pl:31:
Warning:    Clauses of hospitalization_cause/2 are not together in the source-file
Warning:    Earlier definition at .../queries.pl:17
...
Warning:    Use :- discontiguous hospitalization_cause/2. to suppress this message
```

This is because `queries.pl` groups each claim's facts together by question
(claim_1's eight facts, then claim_2's eight facts, ...) rather than grouping
clauses by predicate, which is more readable for matching a claim back to its
question but is exactly what triggers this warning. Added `:- discontiguous`
declarations for the eight fact predicates in `policy.pl` (alongside their
existing `:- dynamic` declarations) to fix it.

Second run, after that fix: exit code 0, zero bytes of output (stdout and
stderr both empty) - fully silent, as the task requires.

## Judgment calls

**1. Section 2.2 ("hospital in the United States") vs. Section 4.1.1
("anywhere in the world").** Section 2.2 says the Daily Hospital Income
Benefit "will only be payable for each (24 hour) day of continuous
confinement in a hospital in the United States," while Section 4.1.1 says
"Your Policy insures You twenty-four (24) hours a day anywhere in the
world." These sit in tension. I read 4.1.1 as being about where a covered
sickness/injury may occur (worldwide), and 2.2 as a separate, narrower
condition specifically on where the confinement generating the daily benefit
must be located (the US) - so I encoded `benefit_payable/1` as requiring
`hospitalization_location(Claim, us)`. This is the fact that decides Q4
(hospitalization while traveling abroad), alongside an independent Section
1.3 timeliness failure in the same claim - see `queries.pl`'s comment on
claim_4. An equally defensible reading would treat 2.2's "United States" as
a drafting artifact superseded by 4.1.1's worldwide language; I did not take
that reading, since 2.2 is specific, operative language about the benefit
itself and Section 3's exclusions (which do enumerate specific carve-outs)
say nothing about location, suggesting geography is handled separately.

**2. Section 1.3's two deadlines.** "No later than the 7th month
anniversary ... you will supply us with written confirmation ... of a
wellness visit ... occurring no later than the 6th month anniversary"
contains two distinct temporal facts: when the visit itself happened
(<=6 months) and when confirmation of it was supplied (<=7 months). Every
benchmark question that raises this condition (Q4, Q6, Q7, Q9) only states
when confirmation/proof "was provided" or "submitted" - none separately
states when the underlying visit occurred. I modeled both as separate facts
(`wellness_visit_month/2`, `wellness_confirmation_month/2`) for fidelity to
the text, and in `queries.pl` set the visit-month fact to a compliant
default when the question is silent about it, consistent with the
instruction to satisfy conditions unrelated to the query. Where the given
confirmation month is itself <= 6 (Q9: 6 months), this default is actually
forced rather than assumed: confirmation of a visit cannot precede the
visit, so a confirmation month of 6 already guarantees the visit happened at
or before month 6. The one case with genuine residual ambiguity is Q6
(confirmation at 6.5 months, which is past month 6 but within month 7, so
the visit could have occurred on either side of its own 6-month deadline
and the question does not say); it does not affect Q6's answer either way,
because Q6's hospitalization independently falls under the skydiving
exclusion (Section 3.1.1) regardless of how the wellness-visit condition
resolves.

**3. "Accidental Injury" excludes a deliberate act (Q5).** Section 2.1 pays
benefits for hospitalization "as a result of sickness or accidental
Injury." Section 3's exclusions list five specific carve-outs and do not
mention self-inflicted or intentional injury at all. I read "accidental" on
its ordinary meaning - unintended - so a deliberate act performed on
purpose (punching one's own face to show off) does not meet Section 2.1's
own threshold definition of a covered event, independently of Section 3's
exclusion list having nothing to say about it. I encoded this as a third,
non-qualifying value of `hospitalization_cause/2`
(`intentional_self_inflicted_act`) rather than as an exclusion, so that
`qualifying_event/1` simply never succeeds for it. The alternative reading -
that "accidental Injury" is just descriptive shorthand for "injury" as
opposed to "sickness," with no intent requirement, and that this gap in
Section 3's exclusion list is deliberate (i.e. self-harm here actually is
covered) - is not unreasonable, and the question's clause "I did not commit
fraud or misrepresentation" (foreclosing the Section 1.2 cancellation route)
reads as though it expects the answer to turn on something else. I judged
the ordinary meaning of "accidental" as the more faithful reading of this
specific contract's text.

**4. Causal nexus for the activity-based exclusions (Q1 vs. Q9).** Section
3.1 excludes sickness/injury "arising directly or indirectly out of"
skydiving, military service, firefighting, or police service. Q1's burns
are suffered "while doing my duty as a firefighter" - a clear causal
connection, so I asserted `injury_activity(claim_1, firefighter_service)`.
Q9 states the claimant "was serving as a police officer at the time of
hospitalization" but the injury itself is a bite from the claimant's own
son - there is no causal link between the police occupation and the
injury. I treated "serving as a police officer at the time" as describing
occupation/status, not causation, and did not assert
`injury_activity(claim_9, police_service)` (I asserted `none` instead), so
the exclusion does not fire for Q9. This is the main substantive difference
between how Q1 and Q9 are encoded despite their surface similarity (both
mention a uniformed-service role).

**5. Section 1.2's three cancellation grounds folded into one fact.**
Section 1.2 cancels the policy for "fraud, or any misrepresentation or
material withholding of any information." None of the nine questions
distinguish between these three grounds (they only ever assert the
negative, e.g. Q5/Q8's "I did not commit fraud[, or misrepresentation]"), so
I represented all three with a single boolean fact,
`fraud_or_misrepresentation/2`, documented in `policy.pl` as standing in for
all three.

**6. Out of scope for "does the policy apply."** I treated the following as
procedural rather than substantive to the yes/no coverage question asked by
each query, and did not encode them: Section 2.3's claim-filing mechanics,
Section 4.2's arbitration/condition-precedent-to-suit provisions, Section
4.3 (governing law), Section 4.4 (currency of payment), and Section 4.5
(premium payment mechanics, also covered by the task's standing assumption
that the premium has been paid on time). I likewise did not encode the
dollar figures in Section 5 (the $500 daily benefit and $2000 premium),
since none of the nine questions ask about benefit amounts, only about
whether the policy applies at all.

**7. "Section 5" cross-reference in 1.2.** Section 1.2 refers to "the
policy term described in Section 5 below," but the policy term is actually
defined in Section 4.6 ("Policy Term"); Section 5 is "Benefit and Premium
Amounts" and says nothing about the term's length. I treated this as a
cross-reference slip in the source text and used Section 4.6's one-year
term (`within_policy_term/1` checks `Month =< 12`).
