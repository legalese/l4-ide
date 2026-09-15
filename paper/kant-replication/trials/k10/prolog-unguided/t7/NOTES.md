# Notes — prolog-unguided / t7

## Load check

Ran, exactly as permitted:

```
swipl -q -g halt policy.pl queries.pl
```

Result: silent on both stdout and stderr, exit code 0. (Checked twice: once via the plain
invocation, once redirecting stdout and stderr to separate files to be sure nothing was being
swallowed by the terminal — both were empty.) I did **not** run `q1`..`q9` or otherwise query the
loaded program.

The main risk to a silent load in this design was SWI-Prolog's "Clauses of Foo/N are not together
in the source-file" discontiguous warning, since `queries.pl` groups facts by claim (all of
claim_1's facts together, then claim_2's, etc.) rather than by predicate, so e.g. `claimant_age/2`
clauses are scattered across the file. Declaring all the shared fact predicates
(`hospitalization_time/2`, `claimant_age/2`, `wellness_visit_time/2`,
`wellness_confirmation_time/2`, `cause/2`, `fraud_or_misrepresentation/1`) as `dynamic` in
`policy.pl` was enough by itself to suppress that warning (dynamic predicates aren't subject to the
contiguity style-check); the `:- discontiguous` directives added in `queries.pl` are a belt-and-
braces measure on top of that and are not, by experiment, actually load-bearing here.

## Design

- All times other than the claimant's age are encoded as a number of months since the effective
  date (effective date = month 0), per the task's "relative to the effective date" instruction.
  Thresholds are inlined directly from the contract text (6, 7, 12 months; 80 years) rather than
  named as facts, to keep `policy.pl` strictly rule-only.
- `policy.pl` declares all per-claim data predicates `dynamic` and defines zero clauses for them,
  so `queries.pl` supplies 100% of the claim data and an absent fact fails cleanly (no "procedure
  does not exist" error) rather than raising an exception.
- Per Step 2 items 6–7, every claim in `queries.pl` sets baseline "safe" values (age 40,
  hospitalization at month 3, wellness visit at month 3, confirmation at month 4, no cause, no
  fraud) for every axis a question doesn't speak to, and overrides only the axes the question text
  actually names.

## Judgement calls

1. **Causal exclusions vs. status exclusions (Section 2.1).** Items (1)–(4) of the general
   exclusions ("skydiving", "service in the military", "service as a fire fighter", "service in
   the police") share the stem "any event ... arising directly or indirectly out of" — a causal
   requirement. Item (5) (age ≥ 80 "at the time of the hospitalization") is grammatically bolted
   onto the same list but is substantively a status test with no causal element. I encoded (1)–(4)
   as keyed on a `cause/2` fact (the alleged cause of the hospitalization) and (5) as keyed on
   `claimant_age/2` directly, with no causal gate. This is the load-bearing design choice behind
   Q9 (son biting the claimant's ankle, while the claimant happens to be a serving police officer
   at that moment): being a police officer is not, on this reading, itself a "cause" of a dog- or
   family-member bite, so I did **not** assert `cause(claim_9, police_service)`; only Q1 and Q8
   (burns "while doing my duty as a firefighter", injury "in a military training exercise") assert
   the corresponding service cause, since those narratives state the activity as the actual cause
   of the injury.
2. **Section 1.3's two deadlines.** "No later than the 7th month anniversary ... written
   confirmation ... of a wellness visit ... occurring no later than the 6th month anniversary" was
   read as two independently failing conditions: the visit itself (≤ 6 months) and the written
   confirmation of it (≤ 7 months). None of the nine questions states when the underlying visit
   itself occurred — each only states when confirmation/proof was "provided", "given", or
   "submitted" — so I mapped that language to `wellness_confirmation_time/2` in every case (Q4,
   Q6, Q7, Q9) and left `wellness_visit_time/2` at its safe baseline throughout.
3. **"Pending" vs. "failed" (Section 1.1(3) / 1.3).** I modelled Section 1.3 failure directly from
   the stated deadlines (confirmation time > 7, or visit time > 6) rather than from any comparison
   against the hospitalization time, since the task states no query will ever require computing
   elapsed time between two dates. Absent a fact showing a deadline was missed, the condition is
   treated as still "pending" and does not block coverage — this only matters for the general
   `policy.pl` encoding, since every claim in `queries.pl` supplies an explicit confirmation time
   whenever the question mentions one at all.
4. **Q5 (self-inflicted injury).** The policy text given to this cell (Section 2.1) lists exactly
   five exclusions — skydiving, military/firefighter/police service, and age ≥ 80 — and none of
   them addresses intentionally self-inflicted injury. I did not invent an exclusion that is not
   in the supplied text, so `claim_5` has no exclusionary `cause/2` fact and no
   `fraud_or_misrepresentation/1` fact, matching "I did not commit fraud or misrepresentation".
5. **Arbitration, choice of law, currency, premium mechanics (Sections 3.2–3.5).** None of these
   bear on whether a given hospitalization is, in principle, a covered event, so they are recorded
   only as comments in `policy.pl` and are not given operative predicates.
