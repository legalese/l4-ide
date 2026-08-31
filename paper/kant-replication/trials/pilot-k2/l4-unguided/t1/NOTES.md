# Notes on this encoding

## Check run

```
cd <trial dir>
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
```

Output: `Check succeeded.` (checked `apply.l4`, which `IMPORT`s `policy.l4`, so both
files were typechecked together). I did **not** run `l4 run` or otherwise evaluate any
`#EVAL` directive, and did not test the encoding against the nine questions beyond this
typecheck, per the task rules.

## Judgement calls

1. **Time unit.** Every date/time fact (other than age) is modelled as a plain `NUMBER`
   of months elapsed since the policy's effective date, with no `DATE`/`YMD` values or
   arithmetic anywhere. This follows directly from the brief ("there will never be a
   need to calculate the time elapsed between two dates") and matches how the source
   text itself states every deadline (6th-month anniversary, 7th-month anniversary,
   one-year term).

2. **Two wellness-visit deadlines collapsed to one reported figure.** Section 1.3
   actually imposes two distinct deadlines: the visit itself must occur by month 6, and
   *written confirmation* of it must be supplied by month 7. Every question that
   touches this, though, only ever reports a single number — "confirmation/proof ...
   provided/submitted N months after the effective date" — and never a separate
   visit-occurrence date. I mapped that single reported number onto the
   confirmation-deadline field (`wellness visit confirmation time`, checked against 7)
   and left `wellness visit time` (checked against 6) at its default "safely compliant"
   value of 0 for every query, on the view that the visit-occurrence sub-condition is
   not what any question is testing and Step 2's rule 6 says unrelated conditions
   should be set to be satisfied. This matters concretely for Q6's "6.5 months": under
   this reading it is inside the 7-month confirmation deadline and does not itself
   cause cancelation (Q6's exclusion comes from skydiving instead); a reading that
   applied the 6-month threshold to that same figure would also not change the answer
   to Q6 (skydiving already excludes it), but it would change the internal reasoning,
   which is why I record the choice here.

3. **"Still pending" not modelled as a separate temporal state.** Section 1.1 item 3
   is "the condition set out in Section 1.3 is still pending **or** has been satisfied
   in a timely fashion" — i.e. a hospitalization occurring before the 7-month deadline
   has even arrived should not be defeated by a wellness-visit failure that hasn't
   happened yet. I did not build this as a function of `hospitalization time` versus
   the confirmation deadline; `section 1.3 condition satisfied` is a simple two-
   threshold check, independent of when the hospitalization occurred. I checked and no
   question combines an early hospitalization time with a separately-late confirmation
   time in a way that would make the two readings diverge, so this simplification does
   not affect any of the nine answers as posed — but a more complete encoding meant to
   answer questions beyond this set should model pendency explicitly.

4. **Causation, not occupation, for the four service-related exclusions.** Section
   2.1 excludes sickness/injury "arising directly or indirectly out of" skydiving,
   military service, firefighter service, or police service. I modelled each as a fact
   about what *caused* the hospitalization (`caused by police service`, etc.), not
   about the claimant's job or status at the time. This is the deciding move on Q9: the
   claimant is "serving as a police officer at the time of hospitalization," but the
   hospitalization was caused by their son biting their ankle, which has nothing to do
   with police duty — so `caused by police service` is set to `FALSE` for `q9` even
   though the claimant's occupation is police officer. Q1 and Q8, by contrast, both
   state the cause itself is the service in question ("while doing my duty as a
   firefighter", "injured in a military training exercise"), so those flags are `TRUE`.

5. **Fraud/misrepresentation/withholding kept as three separate fields.** Section 1.2
   lists three distinct grounds ("fraud, or any misrepresentation or material
   withholding of any information"). I kept them as three independent booleans rather
   than collapsing to one, for faithfulness to the source's enumeration, even though
   the questions only ever address the first two (Q5, Q8) and never withholding.

6. **One-year term approximated as exactly 12 months.** `policy term has expired`
   checks `hospitalization time GREATER THAN 12`. This is never actually decisive for
   any of the nine questions (the largest reported time is 8 months in Q4), but the
   rule is included for a complete encoding of Section 1.2's last sentence / Section
   3.6, per the "fully define all functions" instruction.

7. **Procedural clauses left out of the coverage logic.** Sections 3.2 (arbitration),
   3.3 (governing law), 3.4 (currency of payment) and 3.5 (premium payable in one lump
   sum) are administrative/procedural and do not bear on whether a given
   hospitalization is covered, so I did not encode them as rules or fields. Section
   3.1.1 (worldwide, 24-hour coverage) is recorded only as a comment next to the
   exclusion rules, since it never varies the outcome (relevant to Q4's "traveling
   abroad", which is not excluded on that ground).

8. **Signing and premium payment not modelled at all**, per the brief's explicit
   instruction to assume both and not encode rules for them.

9. **Defaults for every fact a question does not mention**, per Step 2 rules 6-7: age
   40 (under the age-80 exclusion), 0 months elapsed for any unmentioned time field,
   all four cause-flags `FALSE`, and no fraud/misrepresentation/withholding, unless the
   question said otherwise.
