# Notes on this encoding

## Check performed

Ran, from the trial directory root:

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
```

Both printed `Check succeeded.` with no warnings and exit code 0. This is a typecheck only —
per the task rules, I did **not** run `l4 run` or otherwise evaluate the nine `#EVAL`
directives, so I have no information about whether any answer is correct.

## Design choice: dates as months-since-effective-date

Per the task brief, every date/time other than the claimant's age is encoded as a plain
`NUMBER` counting months elapsed since the policy's effective date (`Claim`'s
`hospitalization months after the effective date`, `wellness visit occurred months after
the effective date`, `wellness visit confirmation given months after the effective date`).
No absolute `DATE`/`daydate` arithmetic is used anywhere, since the task brief says this is
never needed.

## Judgement calls

1. **Two separate §1.3 deadlines, not one.** The contract states two distinct facts: the
   wellness visit itself must occur by the 6-month mark, and written confirmation of it must
   reach the company by the 7-month mark. I modelled these as two separate `MAYBE NUMBER`
   fields rather than collapsing them into one, since the contract text distinguishes them
   even though none of the nine questions exercises a case where the two dates diverge.
   Where a query states only the confirmation/proof date (Q4, Q6, Q9) and says nothing about
   when the underlying visit itself happened, I set the visit date to a comfortably early,
   unrelated-and-favourable value (so the deadline for the visit is never independently the
   cause of any failure) and let only the stated confirmation date drive the result.

2. **"Still pending" (§1.1 condition 3).** I read this as: at the time of the
   hospitalization being claimed against, the 7-month deadline for §1.3 has not yet arrived.
   Combined with "has been satisfied in a timely fashion", condition 3 of §1.1 becomes:
   `hospitalization month <= 7 OR (visit <= 6 AND confirmation <= 7)`. This matters only for
   Q4 (see next point); for every other query I set the wellness-visit/confirmation facts to
   values that satisfy the timely-fashion branch outright, so the "still pending" branch
   never has to do any work for those.

3. **Q4's unstated hospitalization date.** The query gives a fall abroad and a confirmation
   given "8 months after the effective date," but never says when the hospitalization itself
   occurred. Setting it to an early, favourable value (e.g. month 2) would make the late
   confirmation practically irrelevant to the result (§1.1 condition 3 would already be
   satisfied via "still pending"), which seemed contrary to the evident point of including
   that fact in the question. I instead set `hospitalization months after the effective
   date` to 8, i.e. treated the hospitalization as contemporaneous with the narrated
   confirmation event, so that the stated lateness (8 > 7) is the operative fact. This is a
   genuine judgement call, not a reading forced by the contract text.

4. **Q4's "traveling abroad."** §2.2 says the Daily Hospital Income Benefit "will only be
   payable for ... confinement in a hospital in the United States," which sits in tension
   with §4.1's "Your Policy insures You ... anywhere in the world." I read §2.2 as the more
   specific, controlling provision on *payability* (§4.1 speaks to when the insured risk is
   "on cover," not to where a hospital stay must occur to be paid), and read "traveling
   abroad" as implying the hospitalization occurred at a non-US hospital. I set `hospital
   located in the United States` to `FALSE` for Q4 accordingly. This is a real interpretive
   choice, not a mechanical reading, and a different, equally defensible cell could set it
   `TRUE` on the theory that "abroad" describes only where the fall happened.

5. **Q9's "serving as a police officer at the time of hospitalization."** §3.1 excludes
   injury "arising directly or indirectly out of ... Service in the police" — a causal
   requirement, not a status requirement. Q9 is phrased as a temporal/occupational fact
   ("at the time of," not "while performing my duties" or "arising out of my police
   service"), unlike Q1 ("while doing my duty as a firefighter") and Q8 ("injured in a
   military training exercise"), which both state an explicit activity-to-injury causal
   link. A son's bite to the ankle has no apparent connection to police duties, so I
   set `excluded activity` to `NOTHING` for Q9 — i.e., I did not apply the police exclusion
   merely because the claimant's occupation is stated. This is the judgement call I am least
   sure about; a cell that reads "at the time of" as sufficient by itself would set this
   claim's `excluded activity` to `JUST \`Police Service\`` instead, and get the opposite
   `covered` result.

6. **Q5's self-inflicted injury.** §2.1 pays only for hospitalization "as a result of
   sickness or accidental Injury." §3 lists no explicit "self-inflicted injury" exclusion.
   I treated "punching my own face to show off for my friends" as a deliberate act, and
   therefore neither a sickness nor an *accidental* injury, so it fails at the §2.1
   definitional threshold rather than via any §3 exclusion. This is encoded via a third
   `Cause Of Hospitalization` constructor, `Intentional Self Inflicted Injury`, distinct
   from `Sickness` and `Accidental Injury`. This is a substantive judgement call about what
   "accidental" excludes, not a fact the contract states explicitly.

7. **§2.3 (claim filing), §4.2 (arbitration), §4.3 (governing law), §4.4 (currency).** None
   of these bear on whether a given, already-filed claim is covered; they concern claims
   procedure, dispute resolution, choice of law, and payment currency respectively. They are
   noted in `policy.l4`'s header comment but are not modelled as separate `Claim` fields or
   functions, consistent with the instruction to define only the rules needed to answer
   coverage queries.

## Defaults used for facts a query does not mention

Per the task's Step 2 instructions (§6/§7), for anything a query does not reference I chose
values that keep every *other* condition satisfied and every *other* exclusion inapplicable,
so only the stated facts drive the `covered` result:

- `cause of hospitalization`: `Sickness` when the query gives no medical cause at all (Q2);
  otherwise matched to the query's own description of the injury/illness.
- `excluded activity`: `NOTHING` unless the query itself names one of the four listed
  activities as the cause.
- `age at hospitalization`: 40 when not stated (comfortably under the 80-year exclusion).
- `hospital located in the United States`: `TRUE` when not stated (Q4 is the one exception,
  per judgement call 4 above).
- `days confined in hospital`: 1 throughout (well under the 365-day cap; no query tests it).
- Wellness visit/confirmation months: early values (1–3) comfortably inside both the 6- and
  7-month deadlines, when not stated by the query.
- `fraud misrepresentation or material withholding of information`: `FALSE` throughout
  (three queries state this explicitly; it is never asserted `TRUE` by any query).
