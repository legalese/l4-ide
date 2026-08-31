# Notes on this encoding

## Checks run

- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4` -> **Check succeeded.**
- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4` -> **Check succeeded.**

No other command was run. Per the task rules, the nine `#EVAL` directives were never
evaluated (no `l4 run`) and the encoding was never tested against the questions.

One intermediate failure, fixed before the above: my first draft of `policy canceled`
and `excluded event` used the citation idiom from the `writing-l4-rules` skill's
drafting-patterns reference — pairing a verbatim statutory-text string with the real
condition via `...`, chained across disjuncts with `..`/`OR` (e.g.
`` "5. age >= 80" ... claim's `age at hospitalization` AT LEAST 80 ``). `l4 check`
reported an ambiguous-overload error on `AT LEAST` (`__GEQ__` had four candidate
overloads and "insufficient information to choose") specifically on the *last* rung of
each chain, the one using the spelled `OR` keyword next to a numeric comparison. I did
not chase down why that combination confuses overload resolution; I just replaced the
inline citation strings with plain `--` comments and plain `OR` chains, which
typechecks cleanly. Isomorphism to the source section numbers is preserved via `§`/`§§`
headers and comments instead.

## Judgement calls

1. **"Arising out of" is causal, not occupational.** General Exclusion §2.1 items 2-4
   exclude an event "arising directly or indirectly out of" military/firefighter/police
   service — a test on what caused the hospitalization, not on the claimant's job title.
   I modelled this as four `caused by ...` boolean flags on `Claim`, each meant to answer
   "did the hospitalizing event arise from this service", not "does the claimant hold
   this occupation". This mattered for Q9 (bitten by claimant's own son, while "serving
   as a police officer at the time of hospitalization"): the officer's occupation is
   incidental to a domestic incident, so I set `caused by police service` to FALSE for
   that query, in contrast to Q1 (burns "while doing my duty as a firefighter") and Q8
   ("injured in a military training exercise"), where the query's own wording ties the
   injury to the service, so I set the corresponding flag TRUE.

2. **§1.3 is one compliance act with two deadlines.** "No later than the 7th month...
   you will supply... confirmation... of a wellness visit... occurring no later than the
   6th month..." names two dates: when the visit happened (<= 6 months) and when
   confirmation of it reached the insurer (<= 7 months). I modelled both as
   `MAYBE NUMBER` fields (genuinely absent until the event happens — see
   `references/drafting-patterns.md`'s "optional record field" bucket for `MAYBE`), and
   defined "still pending" (§1.1 item 3) as: nothing supplied yet, but the hospitalization
   itself occurs before the 7-month mark. Several questions (Q4, Q6, Q7, Q9) give only
   the *confirmation* timing and never separately mention the underlying visit's own
   date; per the task's Step-2 Rule 6 ("set parameters unrelated to the query so that
   conditions are satisfied"), I treated the visit date as the unrelated one and set it
   to a value that independently satisfies its own <=6 threshold (and is <= the given
   confirmation month, since you cannot confirm a visit that has not happened yet). This
   is most consequential in Q4, where confirmation is given at month 8 — already beyond
   the 7-month deadline regardless of the visit date — so the visit is set to a
   comfortably-timely month 6 to isolate the late confirmation as the sole operative
   fact.

3. **No invented "was this really an accident" or intentional-conduct exclusion.** Q5
   describes a claimant "hospitalized for punching my own face to show off," which is a
   deliberate act rather than a mishap. The fixture's General Exclusions list (§2.1) is
   five enumerated items (skydiving / military / firefighter / police / age >= 80) and
   does not include an intentional-acts or self-inflicted-injury exclusion, nor does the
   fixture define "accidental injury" restrictively anywhere in the text given to me. I
   did not add a coverage gate the text does not contain; a self-inflicted but
   undramatic prank injury is treated as within the "sickness or accidental injury"
   trigger of §1.1, tested only against the exclusions and cancelation grounds actually
   written down. (Whether the source paper intends a stricter reading of "accidental" is
   exactly the kind of interpretive question this trial cannot look up the answer to.)

4. **§1.2's three cancelation-for-conduct grounds collapsed to one boolean.** "if there
   is fraud, or any misrepresentation or material withholding of information" is a
   disjunction of three grounds that the contract treats identically (any one cancels
   the policy); I gave `Claim` a single
   `` `guilty of fraud, misrepresentation, or withholding` `` flag rather than three
   separate ones, since no question in the set distinguishes between them (they only
   ever appear together, e.g. Q5's "I did not commit fraud or misrepresentation").

5. **§§3.1-3.5 carry no coverage-gating rule.** Worldwide/24-hour scope (§3.1),
   arbitration (§3.2), governing law (§3.3), currency (§3.4), and lump-sum premium
   timing (§3.5) are preserved as section headers with explanatory comments but
   contribute no conjunct to `covered`, because none of them make any given
   hospitalization event covered or not covered under the policy (§3.1 only expands
   scope with nothing to gate; the rest govern dispute/payment mechanics). §3.6 (one-year
   term) is not inert, and is folded into `policy canceled` as
   `` claim's `month of hospitalization` AT LEAST 12 `` — read as: the term runs
   `[0, 12)` months from the effective date, since cancelation occurs "at midnight...on
   the last day," i.e. exactly at the month-12 boundary.

6. **Signing and premium payment are absent from the model entirely**, per the task's
   own instruction not to encode rules for them — not even as `Claim` fields defaulted
   to `TRUE`.

## Other notes

- All temporal facts on `Claim` are `NUMBER`s of months elapsed since the policy's
  effective date (fractional where the question says so, e.g. `6.5`), never an absolute
  `DATE`; age is the one value the task brief exempts from that relative-time treatment,
  and is encoded as a plain `NUMBER` of years.
- `policy.l4` defines only the `Claim` record type and the decision rules (`covered`,
  `policy in effect at time of hospitalization`, `policy canceled`,
  `condition 1.3 pending or satisfied`, `wellness visit occurred timely`,
  `excluded event`); no `Claim` value is constructed there. All nine `Claim` literals
  (`q1`..`q9`) live in `apply.l4`.
