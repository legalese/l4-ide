# Notes on this encoding

## Load check

Ran `swipl -q -g halt policy.pl queries.pl` from the trial directory root.

First attempt produced ~18 `Warning: Clauses of ... are not together in the source-file
(discontiguous)` warnings, because `queries.pl` groups each claim's facts
together by question (Q1, Q2, ...) rather than grouping all facts of the
same predicate together. The load still succeeded (exit code 0) but was
not silent.

Fixed by adding `:- discontiguous` declarations (alongside the existing
`:- dynamic` ones) for every claim-fact predicate in `policy.pl`. Re-ran
the same command: exit code 0, no output at all (stdout and stderr both
empty). I did not run q1..q9 or otherwise query the encoding against the
nine questions, per the rules.

## Judgement calls

1. **Q5 ("punching my own face to show off") is read as failing the
   initial coverage grant, not as an exclusion.** Section 2.1 only covers
   hospitalization "as a result of sickness or accidental Injury." I
   judged that deliberately punching oneself in the face is neither a
   sickness nor an _accidental_ injury -- it's an intentional
   self-inflicted act, distinct from the "no fraud or misrepresentation"
   fact the question separately (and truthfully) volunteers. So `claim_5`
   gets neither `sickness/1` nor `accidental_injury/1` asserted, and
   `covered_event/1` fails for it before any exclusion or cancelation
   logic is even reached. This is the most consequential interpretive
   call in the encoding, since nothing in Section 3's exclusion list
   speaks to self-inflicted injury directly -- the argument has to be
   made from the scope of the Section 2.1 grant itself.

2. **Q9 ("serving as a police officer at the time of hospitalization")
   does not by itself trigger the police-service exclusion.** Section
   3.1 excludes an event "arising directly or indirectly out of ...
   Service in the police" -- i.e. it requires the injury to be _caused
   by_ police duties, not merely contemporaneous with the claimant's
   occupation. Being bitten by one's own son is a domestic incident with
   no causal connection to police work, so I did not assert
   `cause_of_injury(claim_9, police_service)`. (By contrast, Q1's
   firefighter burns and Q8's military training injury are explicitly
   caused by the excluded service, so those do get a `cause_of_injury/2`
   fact.) This is a deliberate design choice in `cause_of_injury/2`
   itself: it records the _cause_ of the injury, never the claimant's
   status or occupation, precisely so a fact like "was serving as a
   police officer at the time" cannot be mistaken for grounds to assert
   it.

3. **Section 2.2's "hospital in the United States" and Section 4.1.1's
   worldwide-coverage clause are read as compatible, not contradictory.**
   I read 4.1.1 ("insures You twenty-four hours a day anywhere in the
   world") as describing where the insured _peril_ (the sickness or
   injury) may occur without losing cover, and 2.2's "confinement in a
   hospital in the United States" as a separate, specific condition on
   which days of confinement actually generate the payable Daily
   Hospital Income Benefit. Under this reading a claim is not defeated
   merely because the underlying accident happened abroad, but _is_
   defeated if none of the confinement itself was in a US hospital. I
   applied this to Q4 ("hospitalized due to a fall while traveling
   abroad"), reading that phrase as describing a hospitalization -- not
   just an accident -- located outside the US, and asserted
   `hospitalized_outside_us(claim_4)` accordingly. This is asserted
   alongside (not instead of) the independently-sufficient late wellness
   confirmation for the same claim (8 months, past the 7-month deadline)
   -- both facts are recorded faithfully; either alone already defeats
   `covered(claim_4)`, so this judgement call does not change Q4's
   outcome, only how many independent reasons the encoding gives for it.

4. **Section 1.2's cross-reference to "the policy term described in
   Section 5 below" is treated as a drafting slip.** Section 5 is
   "BENEFIT AND PREMIUM AMOUNTS" (the $500 daily benefit and $2000
   premium) and never mentions a term length. The one-year term actually
   appears in Section 4.6 ("Policy Term"). `policy_term_expired/1` is
   encoded from the one-year figure in 4.6.

5. **Section 1.3's two-part deadline (visit by month 6; written
   confirmation by month 7) is modeled as two separate facts,
   `wellness_visit_month/2` and `wellness_confirmation_month/2`, but
   every question that mentions this condition (Q4, Q6, Q7, Q9) gives
   only a single number** ("confirmation/proof of my wellness visit
   provided/submitted N months after the effective date"). I read that
   single figure as the date the written confirmation was supplied
   (checked against the 7-month deadline in `wellness_confirmation_month`)
   and left `wellness_visit_month` unasserted for all nine claims, on the
   view that the underlying visit's own timing is a fact the questions
   never separately volunteer, so per the task's instruction to satisfy
   conditions unrelated to the query, it defaults to compliant via
   omission. Practically this only has bite for Q6 (6.5 months): under a
   stricter reading that treated the single figure as also fixing the
   visit date, 6.5 > 6 would independently fail the visit deadline too --
   but Q6 is already defeated outright by the skydiving exclusion, so
   this choice does not change any of the nine answers, only the
   reasoning `policy.pl` would give if asked to explain itself.

6. **Section 1.1's conditions 3 and 4 are collapsed into a single
   `\+ canceled/1` check.** Condition 3 ("the condition set out in
   Section 1.3 is still pending or has been satisfied in a timely
   fashion") is the exact negation of what Section 1.2 treats as a
   cancelation trigger ("the condition set out in Section 1.3 has not
   been satisfied in a timely fashion"), so encoding cancelation once
   (via `condition_1_3_failed/1`, one of the disjuncts of `canceled/1`)
   already captures both conditions together; a separate predicate for
   condition 3 alone would have been redundant.

7. **Out of scope for a yes/no "will my policy apply" determination:**
   arbitration (4.2, including the 60-day pre-suit waiting period and the
   3-month arbitration-commencement deadline), governing law (4.3), the
   US-currency requirement (4.4), the lump-sum premium timing (4.5, and
   items 1-2 of 1.1 generally, per the task brief), and the 365-day cap /
   per-diem mechanics of 2.2. None of the nine questions turn on these,
   and they concern claim recovery procedure or benefit _quantum_ rather
   than the coverage threshold the questions ask about, so no predicates
   were written for them.

## Design note on defaulting

Every "bad" fact in `policy.pl` (an exclusion cause, a cancelation
trigger, an out-of-country confinement, a failed wellness-visit deadline)
is written so that its _absence_ is the safe/covered default, and every
"good" fact required by the initial coverage grant (`sickness/1` or
`accidental_injury/1`) is asserted explicitly per claim. This lines up
with the task's instruction to set any fact "unrelated to the query" so
that it satisfies conditions and triggers no exclusion: for most claims
this is achieved simply by never asserting the corresponding fact at all,
rather than by asserting an explicit "safe" value.
