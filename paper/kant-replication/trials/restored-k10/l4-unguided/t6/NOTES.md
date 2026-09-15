# Notes on this encoding

## Checks run

Ran, from the trial directory:

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
```

Both printed `Check succeeded.` with exit code 0. `l4 check` type-checks only; it does
not evaluate `#EVAL` directives, so this does not run the nine evaluations. Per the
task rules, I did **not** run `l4 run` or otherwise evaluate `apply.l4` against the
questions, and I have not seen the answer key.

## Judgement calls

- **Two relative-time facts, not one.** The contract's §1.3 condition has two
  events: the wellness visit itself (deadline: 6th month anniversary) and written
  confirmation of it (deadline: 7th month anniversary). None of the nine queries
  gives a separate time for the visit — only for when "confirmation"/"proof" of it
  was provided (Q4, Q6, Q7, Q9) — so I default
  `` `the wellness visit occurred within 6 months of the effective date` `` to
  `TRUE` in every claim (it is a condition the query does not reference, so per
  the standing preamble it is assumed met), and drive the 7-month test off the
  confirmation time actually given.

- **"Still pending" is independent of the hospitalization date.** I define
  §1.1(3) ("still pending or satisfied in a timely fashion") as: no confirmation
  has been given yet _and_ the 7-month deadline has not yet passed as of the
  hospitalization, OR a confirmation was given and it was on time. This makes Q3
  (hospitalized at month 5, nothing said about the wellness visit) covered via
  the "still pending" branch, and Q4 (confirmation given at month 8, i.e. late)
  fail via the "not satisfied in time" branch regardless of exactly when the
  hospitalization itself occurred — the late confirmation is a fact about the
  confirmation event, not about the hospitalization date, so I did not need to
  invent an unstated hospitalization time for Q4 to reach that conclusion. Where
  a query gives no timing information at all (Q1, Q2, Q5), I set the
  hospitalization-time field to `0` and confirmation to `NOTHING`, which trivially
  satisfies "still pending".

- **"Accidental Injury" (Q5).** The policy nowhere defines "accidental Injury"
  and §3 does not list self-inflicted or intentional acts as an exclusion. I
  read "accidental" by its ordinary meaning (unintended) as part of §2.1's
  insuring clause itself, not as an unwritten exclusion: an intentionally
  self-inflicted act (punching one's own face to show off) is not "accidental",
  so it simply never satisfies §2.1 in the first place. I considered the
  contrary reading — that because §3's exclusions are enumerated and
  self-infliction is not among them, the claim should be covered — but concluded
  the exclusions canon governs carve-outs _from_ an established coverage grant,
  not the threshold question of what counts as a covered peril at all. This is
  a genuine, close textual call; a different, defensible encoding would set
  `` `the injury was self-inflicted intentionally` `` to not gate
  `` `the hospitalization was due to an accidental injury` `` at all. I kept
  Q5's own denial of fraud/misrepresentation as a wholly separate fact
  (`committed fraud or misrepresentation IS FALSE`), since that goes to a
  different clause (§1.2) than whether the injury was "accidental".

- **Exclusions require a causal nexus, not mere status (Q9).** §3.1 excludes
  sickness/injury "arising directly or indirectly out of" skydiving/military/
  firefighting/police service — i.e. that activity must have caused the event,
  not merely have been the claimant's occupation at the time. For Q9 (claimant
  is a police officer, but the injury is a dog/family bite with no connection to
  police duties), I set `` `the injury arose from service in the police` `` to
  `FALSE`. By contrast Q1 (burns while on firefighting duty) and Q8 (injury in a
  military training exercise) both state the causal link explicitly, so those
  flags are `TRUE`.

- **§2.2 (US-hospital requirement) vs §4.1 (worldwide coverage) — Q4.** §4.1.1
  says the policy insures the person "anywhere in the world"; §2.2 separately
  says the Daily Hospital Income Benefit "will only be payable for ... continuous
  confinement in a hospital in the United States". I read these as two different
  things: §4.1 is about where the insured peril may occur; §2.2 is an additional,
  independent situs requirement on the qualifying _confinement_. For Q4
  ("hospitalized ... while traveling abroad"), I read the confinement itself as
  having occurred abroad and set
  `` `confined in a hospital in the United States` `` to `FALSE`, which fails
  §2.2 on its own, in addition to the late wellness confirmation (also given in
  Q4) failing §1.3/§1.2. Both routes to "not covered" are encoded faithfully and
  are individually sufficient; they are not meant to be read as alternatives I
  was choosing between.

- **Non-operative clauses.** §4.1 (worldwide personal coverage, reflected by _not_
  requiring the sickness/injury itself to occur in the US), §4.3 (New York law),
  §4.4 (US currency) and §4.5 (lump-sum premium timing) add no independent
  condition on whether a given claim is covered, so they are recorded only as
  comments in `policy.l4`, not as `Claim` fields.

- **Procedural conditions not exercised by any query.** §2.3 ("a claim must be
  made setting out the basis") and §4.2 (arbitration as a condition precedent to
  liability where a dispute exists) are encoded as real fields/rules for
  fidelity, but no query turns on them, so every claim in `apply.l4` sets them to
  their non-blocking values (claim properly made = `TRUE`; no dispute exists).

- **§5 benefit amount.** Included a `` `benefit amount payable` `` function
  ($500/day, per §5.1) for fidelity to the source text, even though none of the
  nine questions ask for a dollar figure — only `covered` (boolean) is exercised
  by `apply.l4`.
