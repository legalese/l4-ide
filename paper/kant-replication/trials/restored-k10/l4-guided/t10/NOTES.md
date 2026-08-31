# NOTES

## Checks run

Only `l4 check` was run (type-check only, no evaluation of `#EVAL`s), per the task rules:

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
-> Check succeeded.

JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
-> Check succeeded.
```

Both files type-check cleanly. `l4 run` / `l4 batch` were never invoked, and the nine `#EVAL`
results were never inspected.

## Judgement calls in `covered` (policy.l4)

1. **Premium payment has no separate deadline.** `1.1(2)` only requires the premium "has been
   paid" (no month comparison), and `4.5.1` describes *how* it is paid (lump sum, at signing)
   rather than stating a consequence for lateness. Section `1.2`'s cancellation triggers are an
   enumerated list (fraud, misrepresentation, the §1.3 condition failing, end of term) and do
   *not* include late premium payment. So `premium paid month` is checked only for presence
   (`isJust`), not against any numeric limit.

2. **"Still pending" (§1.1(3)) is read relative to the hospitalization month.** §1.1 assesses
   whether the policy is in effect "at the time of the hospitalization," which is the only time
   reference available on the `Claim` for this purpose. I treat the §1.3 condition as "still
   pending" whenever `hospitalization month AT MOST 7` (the confirmation deadline has not yet
   passed as of the hospitalization), and otherwise require it to have actually been satisfied
   on time (visit `AT MOST` 6, qualified provider, confirmation `AT MOST` 7).

3. **The 60-day "no recovery before proof + wait" clause (§4.2.1, last sentence) is rounded to 2
   months**, to match the schema's month-denominated fields (`written proof of claim month`,
   `recovery sought month`). This is gated on `recovery sought month` being present at all
   (`NOTHING` there makes the clause vacuous — nobody is yet trying to recover); if recovery is
   sought but no proof was ever submitted, the clause fails.

4. **`unable to settle month = NOTHING` is read as "the arbitration clock has not started,"** i.e.
   not yet a failure, mirroring the "still pending" treatment elsewhere. `arbitration commenced
   month = NOTHING` once the clock *has* started is a failure (via the given `no later than`
   helper's own `NOTHING -> FALSE` branch), matching "any cause of action... shall be
   extinguished."

5. **`valid arbitration award issued` and the 3-month arbitration deadline are gated on `dispute
   arisen`** — irrelevant unless a dispute actually arose, per the text's own conditioning
   ("Where there is a dispute or disagreement...").

6. **`continuous confinement days` is checked against the 365-day cap** by reusing the given
   `no later than` helper (structurally identical: a `MAYBE NUMBER` compared `AT MOST` a limit),
   even though the helper's field names talk about "months" — its logic is unit-agnostic.
   `NOTHING` here is treated as "no confinement to speak of" and fails the benefit condition; this
   is a small stretch of the helper's naming but not of its logic.

7. **`Ground = Neither`** is used for hospitalizations that are neither sickness nor accidental
   injury (see Q5 below) — it fails coverage at the basic §2.1 grant, before any exclusion is even
   reached.

## Judgement calls in `apply.l4`

- **Q5** (punching own face "to show off"): encoded as `hospitalization ground IS Neither`. A
  deliberate act performed for show is not naturally "sickness," and is arguably not "accidental"
  either (the injury was not unintended in the way "accident" ordinarily implies), even though the
  claimant asserts no fraud/misrepresentation. This is the one query where I read the fact pattern
  as failing the basic coverage grant rather than triggering a named exclusion.

- **Q9** (bitten by claimant's son while "serving as a police officer at the time"): `causes` is
  left `EMPTY`. §3.1 excludes injury "arising directly or indirectly out of ... service in the
  police" — a causal requirement. The query gives an explicit, unrelated cause (the bite) and
  separately notes the claimant's employment status at the time; I read status and causation as
  distinct, so mere contemporaneous police employment does not put "Police service" into the
  causal chain here. (Contrast Q1's "while doing my duty as a firefighter" and Q8's "injured in a
  military training exercise," both of which assert the causal link explicitly, and are encoded
  with the corresponding `causes` entry.)

- **Hospitalization month for Q4, Q6, Q7, Q9**: none of these give an explicit hospitalization
  month, only a wellness-visit/confirmation month. Leaving `hospitalization month` at an arbitrary
  early default (e.g. 1) would make the §1.1(3) "still pending" branch trivially true and the
  stated wellness/confirmation fact irrelevant to the outcome — which would make the query's own
  numbers pointless. Instead I set `hospitalization month` equal to the latest explicitly-given
  month figure in each such query (Q4: 8, Q6: 6.5, Q7: 2, Q9: 6), so the stated fact stays
  operative and no field is temporally impossible (confirmation cannot postdate the claim).

- All fields not discussed above are set to values chosen to keep every *other* condition
  satisfied for that query, per the task's instruction and the standing preamble ("assuming all
  other conditions are met... where by 'other' I mean anything not referenced in the query").
  Uniform defaults used throughout: `agreement signed = TRUE`, `premium paid month = JUST 0`,
  `fraud month`/`misrepresentation month = NOTHING`, `dispute arisen = FALSE` (with the
  arbitration-chain fields set to their vacuous defaults), `written proof of claim
  month`/`recovery sought month = NOTHING`, `policy term months = 12`, `confined in us hospital =
  TRUE`, `continuous confinement days = JUST 1`, `claim made setting out basis = TRUE`, and (where
  not the tested fact) `wellness visit month = JUST 1`/`wellness visit provider qualified =
  TRUE`/`written confirmation month = JUST 1`.
