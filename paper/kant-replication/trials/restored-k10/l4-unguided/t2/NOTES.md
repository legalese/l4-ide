# Notes on this encoding

## Checks run

- `JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4`
  -> `Check succeeded.`
- `JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4`
  -> `Check succeeded.`

Only `l4 check` (typecheck only) was run, on both files, as the last step after writing
each. The nine `#EVAL` directives in `apply.l4` were **not** run (no `l4 run`), and the
encoding was not otherwise tested against the queries, per the task rules.

## Design choices / judgement calls

1. **Relative time, not absolute dates.** Per the brief, `Claim` carries plain `NUMBER`
   fields for "months from effective date to X" rather than `DATE`/`DATETIME` values, and
   no two such relative times are ever compared against each other. This also meant the
   "still pending" branch of Sec.1.1(3)/Sec.1.3 does not need its own modelled state: a
   query that doesn't mention the wellness-visit timing gets a compliant filler value (0
   months) per the standing preamble ("assume conditions unrelated to the query are
   satisfied"), which has the same effect as "still pending" would for every one of the
   nine benchmark claims.

2. **Sec.1.3's two sub-deadlines collapsed onto one input number.** The clause has two
   dates: the wellness visit itself (no later than the 6th month anniversary) and the
   supply of written confirmation of it (no later than the 7th month anniversary). Every
   query that speaks to Sec.1.3 gives only one number ("confirmation/proof
   given/provided/submitted N months after the effective date") -- never a separate visit
   date -- so this encoding uses that single figure for both `wellness visit occurred in
time` (<=6) and `wellness visit confirmation supplied in time` (<=7). This is
   equivalent, for this benchmark, to requiring the figure be <=6, since a number in
   (6,7] would only arise in Q6, and Q6 is independently excluded by the skydiving
   exclusion regardless of how the Sec.1.3 timing is resolved. I did not find a query
   where this choice is outcome-determinative.

3. **"Accidental Injury" excludes deliberate self-harm (Q5).** Sec.2.1 pays only for
   hospitalization "as a result of sickness or accidental Injury." Punching one's own
   face on purpose to show off is a deliberate act, not an accident, so I modelled it as
   `hospitalization caused by accidental injury = TRUE` together with `injury was
self-inflicted = TRUE`, and the policy's insured-event gate requires accidental injury
   to NOT be self-inflicted. This is an interpretive call -- the contract text never
   defines "accidental" and never lists self-inflicted injury as a Sec.3.1 exclusion --
   but "accidental" ordinarily requires the causing act to be unintended, and the
   immediate cause here (the punch) was deliberate.

4. **The Sec.3.1 police-service exclusion is causal, not a status test (Q9).** The
   chapeau of Sec.3.1 excludes an event "arising directly or indirectly out of...service
   in the police" -- i.e. the injury has to be causally connected to that service. Q9's
   stated cause is "my son biting me in the ankle"; the claimant's separate remark that
   they were "serving as a police officer at the time of hospitalization" is a
   contemporaneous-status fact, not a claim that the bite arose out of police duty. I
   modelled `hospitalization arose out of service in the police = FALSE` for that claim
   accordingly. (Contrast with Q1 and Q8, where the query's own wording ties the injury
   to the excluded service directly: "while doing my duty as a firefighter", "injured in
   a military training exercise".)

5. **A heart attack (Q7) is modelled as "sickness", not "accidental injury"** -- it is an
   internal medical event, not caused by an accident.

6. **Sec.1.2's cross-reference to "the policy term described in Section 5 below" appears
   to be a drafting slip** in the source text: Section 5 is "Benefit and Premium Amounts"
   and does not describe a term length anywhere; the one-year term is actually specified
   in Sec.4.6 ("Policy Term...will last for a period of one year"). The encoding's
   `policy term in months` constant (12) is taken from Sec.4.6.

7. **Sections 2.2 and 5 (the $500/day benefit, $2,000 premium, and 365-day confinement
   cap) are encoded as simple named constants** for completeness, but are not wired into
   any boolean gate, since none of the nine queries ask about benefit amount or
   confinement duration -- only whether the policy applies at all.

8. **Sections 4.1-4.5 (territory, arbitration, governing law, currency, premium
   mechanics) are documented with comments only**, with no corresponding Claim field or
   predicate, since none of them bear on whether a given claim is covered. In particular,
   Sec.4.1.1's "insures You...anywhere in the world" is why Q4's "traveling abroad" detail
   was not modelled as an exclusionary field at all.

9. **Filler defaults.** Where a query does not mention a fact, I used generic
   non-exclusionary fillers: `age at hospitalization = 40`, and `0` months for either
   time field not mentioned by that query (Q8 uses `3` months for "hospitalization
   occurred within the policy term" instead of `0`, as an arbitrary value comfortably
   inside the 12-month term, matching that query's own explicit wording).
