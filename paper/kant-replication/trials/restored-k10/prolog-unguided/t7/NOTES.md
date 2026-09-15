# Notes on this encoding

## Load check

Ran (as permitted by TASK.md, and only this -- q1..q9 were never invoked):

```
swipl -q -g halt policy.pl queries.pl
```

First attempt printed seven `discontiguous` warnings (exit code 0, no errors): the fact
predicates `hospitalization_month/2`, `wellness_confirmation_month/2` and
`age_at_hospitalization/2` are each asserted once per relevant question, so their clauses
are scattered across `queries.pl` rather than grouped together, which SWI warns about by
default. Rather than leave that warning in place, I added explicit
`:- discontiguous hospitalization_month/2, wellness_confirmation_month/2,
age_at_hospitalization/2.` declarations at the top of `queries.pl`. Re-ran the same command
afterwards: exit code 0, **no output at all** (fully silent, as required).

## Judgement calls

- **Section 1.3's two sub-deadlines collapsed into one fact.** The clause requires (a) a
  wellness visit occurring no later than month 6, and (b) written confirmation of it
  supplied no later than month 7 -- two dates. None of the nine questions ever states the
  visit's own date separately from "confirmation was given/provided/submitted at month X",
  so I modelled a single `wellness_confirmation_month/2` fact and tested it against the
  outer, 7-month deadline only. I treat a confirmation given at month X =< 7 as satisfying
  Section 1.3 in full (i.e. I assume the underlying visit was also timely whenever the
  confirmation itself was timely, since no query ever gives a reason to think otherwise).
  This reading is also what makes Q6 turn cleanly on the skydiving exclusion alone (its
  confirmation month, 6.5, is <= 7) rather than on a second, unstated sub-deadline.

- **"Still pending" (Section 1.1 item 3).** Modelled as: no confirmation fact is on record
  for the claim, and the hospitalization is at or before month 7. If a claim has no
  confirmation fact and is hospitalized after month 7, I treat Section 1.3 as `failed`
  rather than perpetually `pending`. No question in this set actually reaches that branch
  (every question either supplies a confirmation month, or has no stated hospitalization
  time at all, which defaults to month 0 -- see next point) but it is included in
  `policy.pl` for a faithful, general reading of the clause.

- **Default hospitalization time.** When a question does not say when the hospitalization
  happened (Q1, Q2, Q4, Q5, Q6, Q7, Q9), I treat it as month 0 (the effective date itself)
  via `effective_hospitalization_month/2`'s fallback clause, since that timing is then, by
  the standing preamble, unrelated to the question and month 0 trivially clears every
  timing threshold in the policy (the 7-month and 12-month deadlines). Where a question
  does state a time (Q3: 5 months; Q8: "within the policy term", recorded as month 3 for
  concreteness) I encoded that value directly via `hospitalization_month/2`, which takes
  priority over the default.

- **Late confirmation cancels the policy outright, independent of hospitalization timing
  (Q4).** Section 1.2 says cancellation "will be deemed to have occurred if ... the
  condition set out in Section 1.3 has not been satisfied in a timely fashion" -- I read
  this as an unconditional breach once the 7-month deadline passes without confirmation,
  not as something a well-timed hospitalization could pre-empt or a late hospitalization
  could excuse. So in `condition_1_3_status/3`, a confirmation fact with `Months > 7`
  yields `failed` regardless of the `HospMonths` argument. Q4 (confirmation at month 8)
  is designed around this reading: the fall itself is an ordinary, otherwise-covered
  accidental injury (Section 4.1.1 covers the insured worldwide, so "traveling abroad" is
  not itself an exclusion), and the only thing defeating it is the late confirmation.

- **Q5 (punching my own face to show off for my friends) is the one genuine open question
  in this contract, and I did not resolve it by inventing an exclusion.** Section 2.1 pays
  for confinement "as a result of sickness or accidental Injury"; one could argue a
  deliberate, self-inflicted act is not "accidental" at all, which would make this claim
  fail at the coverage-grant stage rather than at the exclusions stage. But Section 3.1's
  General Exclusions are a specific, closed list (skydiving, military service, firefighting
  service, police service, age >= 80) with no catch-all for intentional or self-inflicted
  conduct, and the question is explicit that no fraud or misrepresentation was involved.
  I chose the literal-text reading: nothing in the contract as written excludes this claim,
  so I encoded it as covered (no `caused_by_*/1` fact asserted for `claim_5`, and
  `fraud/1`/`misrepresentation/1` left unasserted). I flag this here rather than silently
  picking a side, since a reader who thinks "accidental" should be read narrowly would
  encode Q5 the other way.

- **"Service in the military" reaches a training exercise (Q8).** The exclusion text says
  "Service in the military" without qualification; I read a training exercise as an
  incident of that service rather than something separate from it, so `claim_8` is flagged
  `caused_by_military_service/1`.

- **What was deliberately left unmodelled**, per the file header of `policy.pl`: Section
  1.1 items 1-2 and Section 4.5 (signature and premium, per the task's own instructions);
  Section 2.1/2.3's "a claim has been made for a hospitalization" gating (every scenario in
  this benchmark already is such a claim, so I treated this the same way as the
  signature/premium assumption rather than adding a boilerplate fact that every single
  query would otherwise have to assert for no benefit); Section 4.2 (arbitration -- a
  remedy/enforcement mechanism that only bites once a dispute already exists, which no
  question raises), 4.3 (New York law), 4.4 (US currency); and Section 5.1/5.2's dollar
  amounts (quantum, not eligibility -- and expressing them would require ground fact
  literals in `policy.pl`, which the task instructions forbid).

- **Robustness against "procedure does not exist".** `policy.pl` declares every optional
  per-claim predicate (`hospitalization_month/2`, `wellness_confirmation_month/2`,
  `age_at_hospitalization/2`, the four `caused_by_*/1` predicates, and `fraud/1`,
  `misrepresentation/1`, `material_withholding/1`) as `dynamic`. This matters concretely for
  `fraud/1`, `misrepresentation/1` and `material_withholding/1`: no question in this set
  ever asserts any of them (Q5 and Q8 explicitly say those things did not happen, and no
  other question mentions them at all), so without the `dynamic` declaration those three
  predicates would have zero clauses anywhere in the loaded program and calling
  `fraud_or_misrepresentation/1` would raise an `existence_error`, not just fail.
