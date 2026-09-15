# NOTES

## Load check

Ran exactly the permitted command from the trial directory:

```
swipl -q -g halt policy.pl queries.pl
```

Result: silent on both stdout and stderr, exit code 0. (Checked stdout/stderr
separately to be sure nothing was suppressed by `-q` alone.) I did not call
`q1`..`q9`, and did not otherwise query the loaded database, per the rules.

## Judgement calls on what the policy means

**1. The two nested deadlines in §1.3.** The clause requires (a) a wellness
visit to occur no later than the 6-month anniversary of the effective date,
and (b) written confirmation of that visit to be supplied no later than the
7-month anniversary. Every query that puts §1.3 in issue (Q4, Q6, Q9) only
ever gives a single number: the month at which confirmation was "provided" /
"submitted" / "given." None gives a separate date for the underlying visit.
I treated the 7-month confirmation deadline as the operative, checkable
constraint (`condition_1_3_pending_or_satisfied/1` in policy.pl checks
`Months =< 7`), and — per the standing instruction in queries-blind.md to
assume anything not referenced by the query is satisfied — assumed the visit
itself occurred in time. This is decisive only for the 6.5-month case (Q6,
where it is not actually outcome-determinative since skydiving independently
excludes the claim) and the 8-month case (Q4, which fails this deadline
under either reading, since 8 exceeds both 6 and 7).

**2. Territorial scope: §4.1.1 vs §2.2.** §4.1.1 says the policy "insures
You twenty-four (24) hours a day anywhere in the world." §2.2 says the Daily
Hospital Income Benefit "will only be payable for each ... day of continuous
confinement in a hospital in the United States." These are in tension. I
read §4.1.1 as fixing the territorial scope of what event can trigger cover
(an accident or sickness may happen anywhere in the world), while §2.2 is
the more specific rule that gates actual payment of the one benefit this
policy provides, and requires the confinement itself to be in a US hospital.
Encoded as `confined_in_us/1` in policy.pl, defaulting to "assumed US" when
a query does not put location in issue. This is decisive for Q4 (hospitalized
abroad), though Q4 already fails independently on the §1.3 timing above, so
the two judgement calls happen to be non-interacting for the given nine
questions.

**3. Whether deliberate self-infliction is an "accidental Injury" (Q5).**
§2.1 pays benefits for hospitalization "as a result of sickness or
accidental Injury." §3.1's five enumerated exclusions do not mention
self-inflicted or intentional injury at all. Q5 describes hospitalization
from the claimant deliberately punching his/her own face to show off for
friends, with fraud/misrepresentation explicitly disclaimed (so §1.2's fraud
cancellation trigger is not in play). I read "accidental" as a substantive
qualifier, not surplusage: a deliberate, voluntary act of self-harm is not
"accidental" merely because the claimant did not necessarily intend to be
hospitalized. I therefore encoded this claim as failing at the definitional
gate in §2.1 (`covered_cause/1` requires `\+ self_inflicted_intentional`
for the `accidental_injury` branch), not via any of the enumerated §3.1
exclusions. I considered the contrary reading — that since self-infliction
is not one of the five listed exclusions, a textualist/enumerated-list
approach would not deny coverage on this ground, and that some accident-
insurance doctrine (the "results" test for accidental means) treats an
unintended injury as accidental even where the underlying act was
voluntary. I judged the "punching one's own face" fact pattern, framed
explicitly as a deliberate act performed "to show off," to fall on the
excluded side of that line, but flag this as the single most contestable
call in this encoding.

**4. Causal nexus required by "arising ... out of" (Q9).** §3.1's chapeau
excludes an event "causing sickness or accidental injury arising directly or
indirectly out of" one of five activities, including "Service in the
police." Q9 describes hospitalization from the claimant's own son biting
his/her ankle, while the claimant happened to be "serving as a police
officer at the time of hospitalization." I read "arising ... out of" as
requiring an actual causal connection between the excluded activity and the
injury, not mere temporal/occupational coincidence — a domestic incident
with a family member has no connection to police duties. I therefore did
not assert `activity_cause(claim_9, police)` (which is what
`excluded/1` keys off for the police exclusion), so the exclusion does not
fire for this claim. This is the mirror image of Q1 ("doing my duty as a
firefighter") and Q8 ("military training exercise"), both of which I did
encode as causally connected to their respective exclusions, and Q6
(injury "while skydiving"), also causally connected.

**5. "Signed" and "premium paid" are not modeled at all**, per the explicit
task instruction ("Assume that the agreement has been signed and the
premium has been paid (on time). There is no need to encode rules or facts
for these conditions.") — not a judgement call, just noting the omission is
deliberate rather than an oversight.

**6. Default handling for facts a question does not put in issue.** Two
different mechanisms are used, matching the character of each condition:

- For genuinely peripheral conditions never put in issue by any of the nine
  questions (confinement duration under the 365-day cap in §2.2; whether a
  dispute has been raised at all under §4.2's arbitration clause),
  policy.pl's rules default to "satisfied" when the corresponding fact is
  simply absent (via `(Fact -> Check ; true)` for duration/location, and via
  a `\+ dispute_raised(Claim)` first clause for arbitration). This means
  queries.pl need not assert anything for these dimensions for any of the
  nine claims.
- For exclusion-triggering facts (activity_cause, claimant_age,
  self_inflicted_intentional, fraud_or_misrepresentation), the exclusion
  rules are written as positive triggers (e.g. `excluded(C) :-
activity_cause(C, skydiving)`), so a claim for which the fact is simply
  never asserted automatically fails to trigger the exclusion — again with
  no need for queries.pl to assert an explicit negative fact per claim.
- For facts central to every claim regardless of what the question asks
  about (hospitalization timing relative to the effective date, and the
  §1.3 wellness-confirmation timing), I did not rely on a lenient default;
  instead every one of the nine claims in queries.pl explicitly asserts a
  concrete, benign value (e.g. `hospitalization_time_months(claim_1, 1)`)
  when the question itself does not specify one, so that §1.3 and the
  12-month policy term (§4.6) are always genuinely checked against a value
  rather than silently skipped.

All fact predicates referenced by policy.pl's rules are declared
`:- dynamic/1` in policy.pl itself, so a claim that omits a given fact
entirely causes the relevant sub-goal to fail (which is the desired
"condition not triggered" behaviour) rather than throwing an
`existence_error`, regardless of which claims do or do not happen to supply
that fact elsewhere in queries.pl.

## Other notes

- `:- discontiguous` directives were added at the top of queries.pl for the
  fact predicates that are grouped by question (readability) rather than by
  predicate, since SWI-Prolog would otherwise print "clauses not together"
  warnings during consult and break the required silence of the load check.
- `canceled/1` (one "l") matches the contract's own American spelling
  ("Cancelation", "canceled") and is used consistently throughout.
