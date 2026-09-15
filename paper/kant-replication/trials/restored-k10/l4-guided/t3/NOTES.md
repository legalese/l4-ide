# Notes

## Checks run

Ran `l4 check` (typecheck only, no evaluation) on both files from the trial directory:

```
JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4   -> Check succeeded.
JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4    -> Check succeeded.
```

I did **not** run `l4 run` and did not evaluate any `#EVAL`, per the rules.

Two mechanical issues turned up while getting `policy.l4` to check, both fixed without changing
any meaning:

- The installed `l4` CLI's parser rejects a bare `_` wildcard inside a constructor pattern
  (`WHEN JUST _ THEN ...`), even though it parses in the bundled documentation examples. Verified
  in isolation with a throwaway scratch file. Worked around by using a named-but-unused binder
  (`WHEN JUST wc THEN ...`) everywhere I would otherwise have written `_`.
- The `` `arose out of` `` helper as given in `inputs/schema.md` has its second `GIVEN` line
  indented one column deeper than the first (`c` under `cs` lands one column right of where it
  needs to be), which the layout-sensitive parser rejects. Corrected the indentation by one column;
  the helper's text and behaviour are otherwise copied verbatim.

## Judgement calls on what the policy means

- **"the condition set out in Section 1.3 is still pending or has been satisfied in a timely
  fashion" (§1.1(3), §1.2).** Modeled as: _satisfied_ = written confirmation given by month 7 AND
  the wellness visit itself occurred by month 6 with a qualified provider (all three conjuncts, via
  the given `no later than` helper twice); _pending_ = confirmation not yet given
  (`written confirmation month` is `NOTHING`) and the hospitalization being assessed occurs at or
  before month 7. I did not additionally require, in the "pending" branch, that the visit's own
  month-6 sub-deadline has not already lapsed — i.e. I treat the month-7 confirmation deadline as
  the operative clock for "pending", not the earlier visit deadline. This is a simplification; the
  text does not fully spell out what "pending" means once the visit window has closed but the
  confirmation window has not.
- **Fraud / misrepresentation (§1.2)** is treated as cancelling the policy regardless of _when_ it
  occurred (`fraud month` or `misrepresentation month` present at all), since §1.2 attaches no
  deadline to this trigger the way §1.3 does to the wellness-visit condition.
- **§2.2's 365-day cap** ("not exceeding three hundred and sixty-five (365) days") is treated as a
  limit on how many days are _paid_, not a coverage gate: `covered` only requires
  `continuous confinement days` to be present and positive. A claim with, say, 400 days of
  confinement is still "covered" under this boolean predicate; the cap would only bite in a
  payout-amount calculation, which is out of scope for `covered`.
- **§4.2.1's "sixty (60) days after written proof of claim"** is checked against
  `recovery sought month` and `written proof of claim month`, both of which are in whole months.
  Sixty days was approximated as **2 months** (`recovery sought month AT LEAST written proof of
claim month PLUS 2`) since the fact schema does not carry day-level granularity. This is an
  approximation, not an exact translation.
- **Arbitration (§4.2) and the recovery-timing rule** are read as applying only when relevant
  facts are present: no dispute (`dispute arisen = FALSE`) makes the arbitration clause vacuously
  satisfied; no recovery yet sought (`recovery sought month = NOTHING`) makes the 60-day rule
  vacuously satisfied. Seeking recovery (`JUST rs`) with no proof of claim on file at all
  (`written proof of claim month = NOTHING`) is treated as a violation (the 60-day clock never
  started).
- **§3.1's "arising directly or indirectly out of ... service"** is read as being about the
  _cause_ of the injury, not the claimant's occupation. Question 9 states the claimant "was serving
  as a police officer at the time of hospitalization," but the hospitalization itself was caused by
  the claimant's own son biting them — unrelated to police duty. I did **not** put
  `` `Police service` `` in that claim's `causes` list; the claimant's occupational status and the
  causal chain behind the injury are treated as two separate facts, and only the latter is what
  §3.1 excludes.
- **Question 5** ("hospitalized for punching my own face to show off for my friends") was encoded
  with `` `hospitalization ground` = Neither ``, on the reading that a deliberate self-inflicted act
  is neither "sickness" nor an "accidental" injury (the schema's three-way `Ground` enum — with
  `Neither` as a bucket distinct from the two grounds §2.1 actually pays on — exists for exactly
  this kind of case).
- Where a query didn't state `hospitalization month`, I used a small in-term placeholder (month 1,
  or month 3 for Q8 which explicitly says "within the policy term"). I checked, while writing each
  claim, that this placeholder is never outcome-determinative for these nine scenarios: the
  wellness-visit-pending branch (the only piece of `covered` that reads `hospitalization month`
  outside the term-expiry check) only engages when `written confirmation month` is `NOTHING`, and
  every one of the nine claims sets that field to a concrete `JUST` value (either a satisfying
  default or the value stated in the query).
- All fields not referenced by a given query were set to values meant to satisfy every other
  condition and trigger no exclusion, per the standing preamble (agreement signed, premium paid,
  no dispute/arbitration/fraud, wellness-visit condition satisfied outright, claim made setting out
  its basis, confined in a US hospital for a few days, age well under 80, policy term of 12 months).
