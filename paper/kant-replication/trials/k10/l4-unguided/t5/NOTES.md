# Notes on this encoding

## Checks run

Only `l4 check` (typecheck only, no evaluation) was run, per the task rules. No `#EVAL` was
evaluated and no comparison against expected answers was made.

```
$ JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4
Check succeeded.

$ JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4
Check succeeded.
```

Both files typecheck cleanly. `apply.l4` was checked as a whole (it `IMPORT`s `policy`), so
this also re-confirms `policy.l4`'s types and the `Claim` field names line up with every
`WITH` block in `apply.l4`.

## Judgement calls

- **Signed / premium paid**: omitted entirely, per the task instructions ("Assume that the
  agreement has been signed and the premium has been paid (on time). There is no need to
  encode rules for these conditions."). S.1.1's conditions (1) and (2) are not modeled.

- **Relative time representation**: every temporal fact other than the claimant's age is a
  plain `NUMBER` of months elapsed since the policy's effective date (`hospitalization time`,
  `wellness visit time`, `wellness visit confirmation time`), per the task's instruction to
  avoid absolute dates and elapsed-time-between-two-dates arithmetic. Age is an ordinary
  `NUMBER` of years, not relative to the effective date.

- **Causal ("arising ... out of") exclusions are facts, not inferences, in the rule**: S.2.1
  excludes an event "causing sickness or accidental injury arising directly or indirectly out
  of" skydiving / military service / fire-fighting / police service. `policy.l4` models each
  as a boolean field (`arose out of skydiving`, etc.) that the claim-data author must set
  correctly from the narrative -- the rule itself just OR's them together. The one place this
  matters is **Q9**: the claimant "was serving as a police officer at the time of
  hospitalization," but the actual cause of the hospitalization was being bitten by their own
  son. I set `arose out of service in the police` to `FALSE` for `q9`, because merely holding
  that occupation at the moment of hospitalization is not the same as the injury *arising out
  of* that service -- there is no causal link between a domestic dog/child-bite-style incident
  and police duties. This is the central interpretive judgement call in the whole exercise; an
  encoder that conflates "is a police officer" with "arose out of police service" would wrongly
  exclude this claim.

- **S.1.3's two deadlines, fed from one reported figure**: the text sets two distinct
  deadlines -- the wellness visit itself must occur "no later than the 6th month anniversary,"
  and written confirmation of it must be supplied "no later than the 7th month anniversary."
  `policy.l4` keeps both as separate named constants and separate comparisons (`wellness visit
  deadline in months` = 6, `wellness visit confirmation deadline in months` = 7), applied to
  two separate `Claim` fields. None of the nine queries, however, report the wellness visit's
  own date separately from when its confirmation was "provided" / "submitted" / "given" --
  they report only one figure. In `apply.l4` I feed that one reported figure into *both*
  `wellness visit time` and `wellness visit confirmation time` for q4, q6, and q9 (the queries
  that mention it), which effectively binds the two deadlines to their stricter, 6-month
  reading for those claims. I checked by hand that this choice does not change the final
  covered/not-covered answer for any of the nine queries: Q4's figure (8 months) fails even
  the more lenient 7-month reading; Q6 is independently excluded via skydiving regardless of
  how the 6-vs-7 boundary is read; Q9's figure (6 months) satisfies both readings since it sits
  at or under the stricter boundary. This is flagged here rather than silently baked in,
  because a different set of queries could make the choice outcome-determinative.

- **"Still pending" (S.1.1(3)) is modeled but not exercised**: `condition 1.3 is still
  pending` captures the case where confirmation has not yet been supplied but the 7-month
  deadline hasn't passed either. Every claim in `apply.l4` supplies a definite (`JUST`, never
  `NOTHING`) wellness figure, so this branch is never the reason any of the nine answers comes
  out the way it does; it is included in `policy.l4` for faithfulness to the text's explicit
  "still pending OR satisfied" disjunction, not because a query needs it.

- **Hospitalization-time defaults for queries that give one temporal fact but not others**:
  for Q4, Q6, and Q9 (which state when wellness confirmation was given but not when the
  hospitalization itself occurred), I set `hospitalization time` to be at or after the
  reported wellness figure (Q4: 9, after 8; Q6: 7, after 6.5; Q9: 6, at 6). This reflects the
  natural reading that the claimant is narrating a complete history up through their
  hospitalization, rather than a hospitalization that precedes and is unaffected by a later
  compliance failure. Had I instead defaulted `hospitalization time` to something small and
  arbitrary (e.g. 1), the "still pending" clause could have (correctly, per a strict reading
  of S.1.1(3)) rescued Q4's late confirmation for a hospitalization narrated as happening
  before the breach crystallized -- which is not the reading I believe the question intends.
  For queries silent on both hospitalization timing and wellness timing (Q1, Q2, Q5, Q8), I
  used small, unremarkable defaults (2-3 months) well clear of the one-year term.

- **"Caused by sickness or accidental injury" gate, including Q5**: S.1.1 scopes the whole
  policy to "hospitalization for sickness or accidental injury." I set this `TRUE` for all
  nine claims. The only claim where this is a live question is **Q5** (hospitalized for
  "punching my own face to show off for my friends"): Section 2 contains no exclusion for
  self-inflicted, reckless, or foolhardy conduct, and the query's own denial of "fraud or
  misrepresentation" points at the one textually-grounded route (S.1.2) by which such conduct
  could disqualify a claim. I treated the resulting hospitalization as an "accidental injury"
  on the reasoning that the act (punching) was voluntary but the injury requiring
  hospitalization was not itself the intended object of the stunt -- the standard sense in
  which a voluntary act can still produce an "accidental" injury. The alternative reading
  (that a self-inflicted act can never be "accidental") is available but is not supported by
  any clause in the given text, so I did not encode it as an implicit exclusion.

- **Age exclusion (S.2.1(5))** is computed directly from `claimant age at hospitalization
  AT LEAST 80`, rather than as an independently-set boolean, since it is a directly observable
  numeric fact rather than a causal finding about the origin of the injury.

- **Section 3 clauses are documented, not gated on**: 3.1 (worldwide, 24-hour coverage), 3.2
  (arbitration / condition precedent to liability / 60-day standstill), 3.3 (New York law),
  3.4 (US currency), and 3.5 (lump-sum premium) are represented as comments in `policy.l4`
  rather than as boolean fields or checks in `covered`. 3.1 is a pure non-restriction (there is
  nothing to gate: worldwide coverage means no territorial field is ever consulted, so "fall
  while traveling abroad" in Q4 is not penalized). 3.2 presupposes an actual dispute or a claim
  already lodged and is about the mechanics of recovering payment, not about whether a given
  hospitalization is, on its face, a covered event; none of the nine queries describe a
  dispute in progress. 3.3-3.5 are purely administrative and have no bearing on coverage.

## Naming and prelude-safety

Checked `jl4-core/libraries/prelude.l4` and `doc/reference/GLOSSARY.md` for collisions before
choosing names; none of `Claim`, `covered`, or any of the backtick-quoted multi-word names
used here collide with a prelude identifier.
