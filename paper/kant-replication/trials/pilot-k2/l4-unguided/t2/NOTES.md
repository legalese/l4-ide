# Notes on this encoding

## Checks run

Ran, from the trial directory root:

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
```

Both returned `Check succeeded.` with no warnings (in particular, no CONSIDER-exhaustiveness
warnings, so the `Cause of Hospitalization` enum match and the two `MAYBE NUMBER` matches are
complete). I did **not** run `l4 run`, `#EVAL`, or otherwise evaluate the nine claims against
`covered` -- only typechecking, per the task's constraint.

One syntax fix needed along the way: `WHEN JUST _ THEN ...` does not parse (the lexer rejects a
bare `_` immediately after `JUST`, expecting an actual binder). Replaced with a named-but-unused
binder, `WHEN JUST t THEN ...`, which typechecks cleanly.

## Judgement calls

- **Causation, not status, drives § 2.1.** `Claim`'s `cause of the hospitalization` is a single
  closed enum describing what the sickness/injury arose *out of*, not a checklist of the
  claimant's occupations or activities in general. This is the crux of Q9: the claimant is a
  serving police officer, but the ankle bite came from their son, not from police duty, so no
  exclusion applies. By contrast Q1's burns arose directly from firefighting duty, and Q8's
  injury arose from a military training exercise (treated as itself "service in the military"),
  so both are excluded.
- **§ 2.1's list is closed.** Q5's self-inflicted "punching my own face to show off" is not one of
  the five enumerated exclusions (skydiving / military / firefighting / police / age >= 80), so it
  is not excluded, however reckless it sounds -- the policy has no general intentional-conduct or
  self-harm exclusion.
- **§ 1.3 is modelled as two separate `MAYBE NUMBER` facts** (`written confirmation supplied at`,
  `wellness visit occurred at`), both in months-after-effective-date, matching the contract's own
  two sub-deadlines (confirm by month 7, of a visit that itself happened by month 6). None of the
  nine queries states a wellness-visit date distinct from the confirmation date, so
  `wellness visit occurred at` is `NOTHING` (defaults to satisfied) in every one of the nine
  claims -- that field is fully operative in `policy.l4` but inert across this fixture set.
- **"Still pending" (§ 1.1(3)) is resolved this way:** if a confirmation has been supplied at all,
  its own timeliness is dispositive, independent of when the hospitalization falls. Only when *no*
  confirmation has been supplied does the code fall back to asking whether the hospitalization
  itself is being assessed at or before month 7 -- i.e. the deadline simply hasn't arrived yet, so
  nothing has failed. This is what makes Q3 (pneumonia at month 5, no confirmation mentioned)
  come out with the policy still in effect.
- **§ 3.6 (one-year term) and § 1.2's fraud/misrepresentation ground** are both modelled in
  `policy.l4` for faithfulness to the text, though across these nine queries only Q4's late
  (8-month) confirmation actually drives a cancelation.
- **§ 3.1.1 (worldwide, 24-hour coverage)** and **§§ 3.2-3.5 plus Section 5** (arbitration,
  governing law, currency, premium mechanics/schedule) were read but given no field or rule: 3.1.1
  is a coverage-affirming clause with no exceptions (no time-of-day or location fact could ever
  make it fail), and the rest govern the relationship between the parties without ever bearing on
  whether a given hospitalization is covered.
- **`time of hospitalization` defaults to `0`** for every claim not built around a specific
  hospitalization-timing fact (Q3 sets it to `5`, Q8 to `6` to reflect its explicit "within the
  policy term" fact). Because a supplied confirmation is dispositive on its own (see above), this
  default never creates a spurious "still pending" escape for the claims that instead turn on a
  confirmation date (Q4, Q6, Q7, Q9).
