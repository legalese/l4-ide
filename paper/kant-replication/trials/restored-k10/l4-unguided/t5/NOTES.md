# Notes

## Check performed

Ran, from the trial directory:

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
```

Both printed `Check succeeded.` (the `--json` form of the `apply.l4` check reports
`{"diagnostics":[],"file":"apply.l4","ok":true}` -- zero diagnostics, not even an exhaustiveness
warning on the one `CONSIDER` over `MAYBE NUMBER`). I did **not** run `l4 run` and did not evaluate
any `#EVAL` directive, per the rules for this trial.

## Judgement calls

1. **§1.2's cross-reference to "the policy term described in Section 5 below."** Section 5 of the
   contract only contains the benefit and premium _amounts_ (§5.1-§5.2); the one-year term itself is
   actually defined in §4.6 ("will last for a period of one year from that date"). I used §4.6's
   twelve-month figure as the operative policy-term length in `policy term in months`, since that is
   the only place in the text a term length is actually stated.

2. **The two sub-deadlines inside §1.3.** §1.3 has two dates: the wellness visit itself must occur no
   later than the 6-month anniversary, and written confirmation of it must reach the Company no later
   than the 7-month anniversary. None of the nine questions ever states when the underlying visit
   occurred -- every question that touches §1.3 only states when confirmation/proof was "provided" or
   "submitted" to the Company. So `Claim` models the visit itself as a plain
   `wellness visit occurred within six months of the effective date` boolean (defaulted to `TRUE`,
   i.e. treated as an unaddressed condition per the standing preamble), while the confirmation side
   gets the fuller treatment: a `MAYBE NUMBER` submission month, tested against the 7-month deadline,
   with a "still pending" fallback (`hospitalization not yet past the wellness confirmation deadline`)
   for the case where no submission month is supplied at all -- mirroring §1.1(3)'s own wording, "is
   still pending or has been satisfied in a timely fashion." No query actually exercises the
   `NOTHING` branch (every `#EVAL` in `apply.l4` supplies `JUST <month>`), but the branch is there for
   fidelity to the text.

3. **Q4 - "hospitalized due to a fall while traveling abroad."** I read this as describing where the
   disabling event (the fall) took place, not where the claimant was subsequently hospitalized.
   §4.1.1 ("Your Policy insures You twenty-four (24) hours a day anywhere in the world") means the
   _location of the accident_ does not itself defeat coverage. §2.2 separately requires confinement
   "in a hospital in the United States" -- since the question never says where the claimant was
   _hospitalized_, I treated that fact as unaddressed by the question and defaulted it to `TRUE`
   (satisfied), per the task's instruction to satisfy conditions unrelated to the query. Q4's outcome
   therefore turns only on the late (8-month) wellness confirmation, not on geography.

4. **Q5 - "hospitalized for punching my own face ... I did not commit fraud or misrepresentation."**
   The policy's five enumerated §3.1 exclusions (skydiving, military service, firefighter service,
   police service, age >= 80) do not include a general exclusion for intentional or self-inflicted
   injury, unlike many real-world accident policies. I did not add one: the encoding excludes a claim
   only via the five limbs the text actually enumerates, so a self-inflicted injury that isn't any of
   those five is not excluded by `exclusion applies`.

5. **Q9 - "... I was serving as a police officer at the time of hospitalization"** (injury caused by
   the claimant's son biting his ankle). §3.1 excludes sickness/injury "arising directly or indirectly
   out of ... service in the police" -- i.e. the exclusion is about the _cause_ of the injury, not the
   claimant's occupation at the moment of hospitalization. A dog-bite-style domestic injury from one's
   own son plainly does not arise out of police service merely because the claimant happens to hold
   that job, so I set `injury arose from police service` to `FALSE` for Q9 even though the claimant is
   a police officer.

6. **§1.1(1)-(2) (signature; timely premium payment).** Per the task's Step 1 instructions, these are
   assumed always to hold and are not modelled as `Claim` fields or tested by any rule in `policy.l4`.

7. **Default filler values.** For every fact a given question does not mention, `apply.l4` sets a
   value that keeps the policy applying (age 40; 1 month since the effective date at hospitalization;
   wellness visit within six months = `TRUE`; confirmation submitted immediately = `JUST 0`; no fraud;
   confined in a US hospital; 1 day of continuous confinement; claim properly made; all four
   "injury arose from ..." flags `FALSE`), per Step 2 instructions #6-#7 ("assume all other conditions
   ... are met and no other exclusions apply").
