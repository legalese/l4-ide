# Notes

## Check run

Ran (typecheck only, no evaluation):

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
```

Both printed `Check succeeded.` I did not run `l4 run` and did not evaluate the nine `#EVAL`
directives or otherwise test `covered` against the questions.

One fix was needed to get there: the skill docs say the prelude is auto-imported, but `l4 check`
reported `elem` and `isJust` (both used inside `policy.l4`, the first from the given `arose out
of` helper, the second in my own fraud/misrepresentation check) as undefined until I added an
explicit `IMPORT prelude` at the top of `policy.l4`. This is a language-mechanics fix, not a
domain judgement call.

## Judgement calls in reading the policy

- **"Neither" gates coverage entirely.** Clause 1.1 premises the benefit on "the hospitalization
  for sickness or accidental injury." I read the `Ground` enum's `Neither` case as scoping the
  policy's subject matter altogether (e.g. an elective/cosmetic hospitalization), not as one more
  exclusion alongside §2.1, and encoded `hospitalization ground covered` as a standalone gate
  (`Sickness` or `` `Accidental injury` `` only).

- **Q5 (punching own face): classified as an accidental injury, not "Neither."** This was the
  hardest call. Deliberately punching yourself is an intentional _act_, but the resulting
  hospitalization-worthy harm was (per the question) not itself sought, and this policy — unlike
  many real accident policies — has no clause excluding intentional or self-inflicted injury. Given
  that absence, and that the question explicitly disclaims fraud/misrepresentation (suggesting that
  clause is the only live issue), I treated the outcome as an "accidental injury" rather than
  "Neither." A stricter accidental-_means_ reading (the act, not just the result, must be
  unintended) would instead put this at `Neither`/uninsured peril, which is a live alternative
  reading. `covered` itself does not encode a self-harm exclusion either way — that would require a
  policy clause that isn't in the text — so this call lives entirely in `apply.l4`'s construction
  of `q5`.

- **Q9 (son bit my ankle while I was on duty as a police officer): `causes` does not include
  `` `Police service` ``.** §2.1 excludes injury "arising directly or indirectly out of ... service
  in the police" — a causal test. Being on duty at the moment of an unrelated domestic injury is
  status, not causation, so I did not add `` `Police service` `` to the claim's `causes` list. This
  is the fact pattern I believe the question is designed to probe.

- **Fraud/misrepresentation cancels regardless of timing relative to the hospitalization.** Both
  `fraud month` and `misrepresentation month` are `MAYBE NUMBER` (suggesting a possible
  month-based comparison), but §1.2's text ("Cancelation will be deemed to have occurred if there
  is fraud...") states no deadline or comparator. I treated either field being `JUST _` (i.e.
  `isJust`) as sufficient to cancel the policy, with no comparison against `hospitalization month`.

- **Automatic term-expiry uses an inclusive boundary.** §1.2 cancels the policy "at midnight ... on
  the last day of the policy term," which I read as still covering that last day. Encoded as
  `hospitalization month AT MOST policy term months` (not strictly less than).

- **§1.3's "still pending" escape uses a strict boundary.** "No later than the 7th month
  anniversary" is the deadline itself; I read hospitalization occurring strictly before month 7 as
  "still pending" (`LESS THAN 7`), and hospitalization at or after month 7 as requiring the
  condition to already be satisfied. None of the nine questions land exactly on this boundary, so
  the choice does not affect any answer, but it is a real interpretive choice.

- **"Proof/confirmation of my wellness visit was provided/given/submitted _N_ months after the
  effective date"** (the phrasing used in Q4, Q6, Q7, Q9) is mapped to `written confirmation
month`, not `wellness visit month` — i.e. it describes the act of supplying written confirmation
  to the insurer under §1.3, not the date of the underlying visit. The underlying visit's own date
  is never stated by any of the nine questions, so in every claim I set `wellness visit month` to
  an early, compliant value (`JUST 1`) and `wellness visit provider qualified` to `TRUE`, isolating
  whichever fact each question actually states.

- **Sixty days ≈ two months.** §3.2.1's "sixty (60) days after written proof of claim" is
  approximated as 2 months (60 ÷ 30), reusing the given `no later than` helper against
  `written proof of claim month` with a computed limit of `recovery sought month MINUS 2`, since
  every other date fact in this schema is month-denominated. None of the nine questions touch
  arbitration, disputes, or recovery timing at all, so every claim sets those fields to inert
  defaults (`dispute arisen IS FALSE`, both settle/arbitration months `NOTHING`, `valid arbitration
award issued IS FALSE`, `recovery sought month IS NOTHING`) — the standing preamble's "assume all
  other conditions are met."

- **Q4's unstated `hospitalization month` is deliberately placed after the confirmation deadline.**
  The query states written confirmation was given at month 8 (after the month-7 deadline) but does
  not say when the hospitalization itself occurred. I set `hospitalization month IS 9` so the "still
  pending" escape in §1.3 cannot trivially rescue the claim — otherwise an early, unstated
  hospitalization month would make the late-confirmation fact irrelevant to the outcome, which
  would not actually exercise what I believe the question is testing.

- **`policy term months IS 12` in every claim.** §3.6's default term is one year; no question
  suggests a different term length, so this is used uniformly rather than treated as unstated per
  claim.

## Fields and helpers used

`covered` and its helpers reference all 18 `Claim` fields and both given helpers (`no later than`,
used three times; `arose out of`, used four times). No new field was invented and neither given
helper was redefined.
