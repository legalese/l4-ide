# NOTES

## Checks run

- `JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4`
  from the trial directory: **"Check succeeded."**
- `JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4`
  (standalone): **"Check succeeded."**
- I did **not** run `l4 run` and did not evaluate the nine `#EVAL` directives, per the task
  constraints. All nine questions were reasoned through by hand against the rules in `policy.l4`
  only to sanity-check internal consistency (e.g. that an exclusion or the self-inflicted-injury
  gate independently decides a question regardless of an unrelated fact also being satisfied); I
  did not consult any answer key, fixture, or external source.

## Judgement calls

1. **Relative-time modelling.** Every date/time fact other than age is modelled as a plain
   `NUMBER` of months elapsed since the effective date (`hospitalization months since the
effective date`, `wellness visit months since the effective date`, `wellness visit
confirmation months since the effective date`), compared only against the fixed thresholds the
   contract states (6, 7, 12 months) — never against each other — per the task's instruction that
   there is never a need to compute elapsed time between two dates.

2. **Section 1.3 has two distinct deadlines**, which I kept as two separate facts: the wellness
   visit itself must occur by month 6, and written confirmation of it must be supplied by month 7.
   None of the nine questions gives a separate "visit occurred" date (they only ever say
   "confirmation of my wellness visit" or "proof ... was provided" at month X), so I read that
   quantity as the _confirmation_ date and default the (never-queried) visit date to an early,
   satisfying value in every question in `apply.l4`.

3. **"Still pending" (Section 1.1(3)).** I modelled the 1.1(3)/1.2 interaction as: the
   wellness-visit condition is fine for a given hospitalization if it was actually satisfied in
   time (visit ≤ month 6 and confirmation ≤ month 7), _or_ if the hospitalization itself occurs
   before month 7 (the confirmation deadline hasn't yet passed, so nothing has yet been breached).
   Only Q4 turns on this: the question says "I _had given_ confirmation ... 8 months after the
   effective date" and then describes the hospitalization, which I read as placing the
   hospitalization after month 8 (hence set to month 9 in `apply.l4`) — after the missed month-7
   deadline — so the policy is deemed canceled. For every other question the confirmation month
   given is ≤ 7, so this "pending" branch is immaterial to the outcome regardless of which
   (unstated) hospitalization month is used; I defaulted those to month 1 for uniformity.

4. **Section 2.1 vs. Q5 (self-inflicted injury).** The contract's Section 3.1 exclusions list
   skydiving/military/firefighting/police/age≥80 and nothing else — there is no express exclusion
   for self-inflicted or intentional injury. I read Q5 ("hospitalized for punching my own face to
   show off for my friends") as turning on a more basic gate: Section 2.1 only insures "sickness or
   accidental Injury," and a deliberate act against oneself is not an _accident_. I encoded a
   three-way `Hospitalization Cause` (`Sickness` / `Accidental Injury` / `Intentional
Self-Inflicted Injury`) so this definitional question is answered independently of Section 3.1
   and independently of fraud/misrepresentation (which Q5 also raises, but which goes to a
   different provision, Section 1.2). This is the most consequential interpretive call in the
   encoding — a reader could instead conclude the absence of an express exclusion means such an
   injury is covered — so I have flagged it prominently in `policy.l4`'s comments as well.

5. **Section 2.2 vs. Section 4.1.1 (territorial scope) and Q4.** Section 4.1.1 says the policy
   "insures You twenty-four (24) hours a day anywhere in the world," but Section 2.2 separately
   conditions the Daily Hospital Income Benefit on "continuous confinement in a hospital in the
   United States." I read these as compatible rather than contradictory: 4.1.1 covers the insured
   risk (where the sickness/injury may occur) worldwide, while 2.2 imposes its own, narrower
   territorial condition on where the resulting hospital _confinement_ must occur for the benefit
   to be payable. I modelled `confinement in a hospital in the United States` as a fact
   independent of, e.g., the general exclusions, and treated Q4's "hospitalized ... while
   traveling abroad" as meaning the confinement (not just the precipitating fall) took place
   outside the United States, so it fails this condition — independently of, and in addition to,
   the missed wellness-visit deadline in the same question.

6. **Causal exclusions vs. occupational status (Q9).** Section 3.1 excludes events "arising
   directly or indirectly out of" the five listed grounds. I modelled each of the four
   activity-based exclusions (skydiving/military/firefighting/police) as a fact about what the
   _hospitalization_ arose out of, not the claimant's occupation in general. Q9 states the
   claimant "was serving as a police officer at the time of hospitalization" but the
   hospitalization itself was "due to my son biting me in the ankle" — a domestic incident with no
   connection to police duty — so I set `arising out of police service` to `FALSE` for Q9 even
   though the claimant is, generally, a police officer.

7. **Section 2.3** (a claim must be made setting out the basis, and for there being no exclusion
   or cancellation) is read as adding no independent condition beyond what the rest of the file
   already computes — evaluating `covered` for a claim already presupposes a claim has been made —
   so it has no rule of its own, only an explanatory comment.

8. **Section 4.2 (Arbitration)** is read as a set of procedural prerequisites to _litigating or
   recovering on_ the policy once a dispute has already arisen (commence arbitration within 3
   months or the claim is extinguished; a 60-day post-proof-of-claim waiting period), not a
   condition of substantive coverage. None of the nine questions describes a dispute, and "will my
   policy apply if ..." reads as a coverage question asked prior to any dispute, so Section 4.2 is
   documented in `policy.l4` but is not wired into `covered`. Likewise Sections 4.3 (governing
   law), 4.4 (currency) and 4.5 (premium timing, assumed satisfied per the task instructions) add
   no rule.

9. **365-day benefit cap and "confinement occurred" (Section 2.2).** These bound how _much_
   benefit is payable (a stay of, say, 400 days is still covered for its first 365 days), not
   whether the policy responds to the claim at all, so — unlike the United States-confinement
   condition, whose failure can zero out the _entire_ claim — they are defined as standalone rules
   for completeness but are not part of the top-level `covered` gate. All nine questions set `days
of continuous confinement` to a small positive default (3), since none of them puts confinement
   duration in issue.

10. **Age and other unrelated facts** not mentioned by a given question (age, cause, exclusion
    flags, confinement location, confinement duration, fraud) are set in `apply.l4` to a
    non-triggering default (age 40, `Sickness` cause where no injury is described, all exclusion
    flags `FALSE`, `confinement in a hospital in the United States` `TRUE`, `days of continuous
confinement` `3`, `fraud or misrepresentation or material withholding` `FALSE`), per the task's
    instruction to satisfy all conditions unrelated to the question being asked.
