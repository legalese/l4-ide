# Notes

## Check performed

Ran, from the trial directory root:

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
```

Both printed `Check succeeded.` No other command was run against these files: the nine
`#EVAL` directives were not evaluated (`l4 run` was never invoked), and no scenario was
compared against an expected answer.

## Modeling approach

`policy.l4` represents each claim as one `Claim` record (11 fields: age, a hospitalization
time and two wellness-compliance times expressed only in months elapsed since the effective
date, two event-type flags, four exclusion-activity flags, and a fraud/misrepresentation
flag). All temporal facts are compared only against the fixed thresholds stated in the
contract (6, 7, 12 months) or against each other's own fixed threshold — no two
claimant-supplied relative times are ever compared against one another, per the task's
instruction that there is never a need to compute elapsed time between two dates.

## Judgement calls

1. **"Accidental injury" excludes deliberate self-harm (drives Q5).** Section 1.1 only pays
   for hospitalization "for sickness or accidental injury." The contract never defines
   "accidental," but ordinary meaning excludes a deliberate act (punching one's own face to
   show off). I modeled this as a fact on the Claim (`accidental injury`) rather than as an
   exclusion, and set it FALSE for the punching scenario, so the claim fails the base
   coverage-trigger rather than tripping any of the five enumerated exclusions. This is
   genuinely debatable — a reading that "accidental" only requires the _harm_ to be
   unintended (not the act) would set this TRUE instead — and it is the single most
   consequential interpretive call in this encoding.

2. **Exclusions (1)-(4) of Section 2.1 require causal nexus, not mere status (drives Q9).**
   The chapeau reads "any event ... arising directly or indirectly out of: 1. Skydiving; ... 4. Service in the police." I modeled each as "the hospitalization arose from X," not "the
   claimant does/was doing X at the time." For Q9 (a claimant who is a police officer,
   hospitalized because her son bit her ankle), I set `arose from service in the police` to
   FALSE: the bite has no stated connection to police duties, only to her occupation at the
   time of the injury. A stricter status-based reading would treat "serving as a police
   officer at the time" alone as sufficient and exclude the claim; I judged the causal
   reading truer to "arising ... out of."

3. **A late confirmation is a definite, permanent failure of Section 1.3, independent of
   when the hospitalization occurs (drives Q4).** Section 1.3 requires confirmation "no later
   than the 7th month anniversary." Q4 states confirmation was given at month 8 but never
   states the hospitalization's own relative time. Rather than trying to infer an ordering
   between the hospitalization and the confirmation, I encoded "confirmation was late" as an
   unconditional fact once a supplied confirmation month exceeds 7 — this always defeats
   Section 1.1(3) regardless of the (unstated) hospitalization time, which sidesteps needing
   to compare two claimant-supplied relative times against each other. I set the underlying
   wellness _visit_ itself to on-time (month 5) so that the isolated, tested fact is purely
   the late confirmation, per the instruction to satisfy unrelated conditions.

4. **"Confirmation implies a prior visit" was used to fill in an unstated visit time (Q6,
   Q7, Q9).** Where a query gives a wellness-confirmation time but not the underlying visit
   time, I set the visit time at or before the confirmation time (since one cannot confirm a
   visit that has not happened yet). For Q7 and Q9 this places the visit safely within its
   own 6-month deadline; for Q6 it is moot because the skydiving exclusion is dispositive
   regardless of the wellness condition's outcome.

5. **Q3 exercises the "still pending" branch of Section 1.1(3) rather than the "satisfied"
   branch.** Q3 gives a hospitalization time (5 months) but no wellness-visit or
   confirmation facts at all, so I left both as `NOTHING` (nothing yet reported) rather than
   assuming they had already happened. Because 5 months is before the 7-month final
   deadline, `condition 1-3 is still pending` is what carries this claim, independent of
   whatever the claimant eventually does about the wellness visit.

6. **A training exercise counts as "service in the military" (Q8).** Read as a routine
   incident of military service, not a borderline case.

7. **Sections 3.2-3.5 (arbitration procedure, governing law, currency, premium mechanics)
   were not encoded as rules.** None of the nine questions turn on them, and the task asks
   only for "rules that can be used to answer queries on this insurance contract." Section
   3.1 (worldwide territorial scope) is noted in a comment rather than as a Claim field,
   since it grants unconditional coverage rather than excluding anything.

8. Per the task instructions, Section 1.1 conditions (1) agreement signed and (2) premium
   paid are assumed always true and are not represented as Claim fields or rules.
