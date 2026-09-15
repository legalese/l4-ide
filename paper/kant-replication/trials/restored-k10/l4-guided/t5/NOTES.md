# Notes on this encoding

## Checks run

- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4` — **Check succeeded** (after
  adding `IMPORT prelude`; without it, `elem` and `isJust` were reported as undefined
  identifiers, contradicting the skill's claim that the prelude is always available in this
  environment — so I added the explicit import rather than removing the calls).
- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4` — **Check succeeded**.
- I did **not** run `l4 run` and did not evaluate any `#EVAL` directive, per the rules. `apply.l4`
  does not `IMPORT prelude` itself — it only constructs `Claim` records and calls `covered`, which
  it gets transitively via `IMPORT policy`.

## Judgement calls in `policy.l4` (what the policy means)

- **Premium "paid on time" (§1.1.2 / §4.5.1).** The policy says the premium "shall be paid in one
  lump sum at the signing of the policy," so I treated "paid" as needing to be no later than
  month 0, reusing the `` `no later than` `` helper with limit month `0`.
- **§1.2's "condition in Section 1.3 ... not satisfied in a timely fashion."** The schema has no
  "as of" / "today" field, so I could not model "still pending as of the hospitalization date."
  I instead treat a `Claim` as the eventual, completed dossier and check the two section-1.3
  deadlines (wellness visit no later than month 6; written confirmation no later than month 7)
  against whatever months are recorded, regardless of `hospitalization month`'s relative position.
  This also means `hospitalization month` only does one piece of work in `covered`: the §1.2
  automatic-cancelation-at-term-end check (`hospitalization month` vs `policy term months`).
- **Fraud / misrepresentation.** Treated as voiding the policy if `fraud month` /
  `misrepresentation month` is `JUST` anything at all (existence, via `isJust`), since §1.2 does
  not condition cancelation on when the fraud/misrepresentation occurred.
- **§4.2.1's 60-day "In no case shall You seek to recover" rule.** This sentence sits inside the
  arbitration clause (4.2.1), but unlike the adjacent sentence ("**Where there is a dispute or
  disagreement**, the issuance of a valid arbitration award shall also be a condition precedent"),
  it is phrased as an unconditional "in no case," not "where there is a dispute." I therefore
  encoded `` `recovery was not sought prematurely` `` as a general condition, independent of
  `dispute arisen`, rather than gating it on a dispute having arisen. This is genuinely ambiguous;
  a reading that scopes it to disputes-only is also defensible.
- **60 days vs. months.** `written proof of claim month` / `recovery sought month` are
  month-granularity fields (per the schema's own naming and the rest of the schema's month-based
  clock), so I approximated the contract's "sixty (60) days" as two months when comparing them.
- **§4.1 ("insures You ... anywhere in the world"), §4.3 (NY law), §4.4 (US currency), §4.5
  (premium procedure), §4.6 (policy term), §5 (dollar amounts).** These contribute no independent
  boolean conjunct to `covered` beyond what's already captured elsewhere (there is no "location of
  injury" field to restrict, term length is already the `policy term months` field, and dollar
  amounts are out of scope for a coverage boolean), so I left them as comments rather than
  fabricating extra fields/logic not licensed by the schema.
- **Exclusions require causation, not mere status.** §3.1 excludes sickness/injury "arising
  directly or indirectly **out of**" the five listed activities. I read this as requiring the
  excluded activity to be in the claim's `causes` list (checked via the schema's `` `arose out
of` `` / `elem` helper), not merely that the claimant held some status (e.g. being a police
  officer) at the time of hospitalization.

## Judgement calls in `apply.l4` (building each Claim)

- Each query's stated wellness-visit timing (e.g. "confirmation ... 8 months after," "proof ...
  provided 6.5 months after") was read as the **`written confirmation month`** fact (the act of
  supplying confirmation to the insurer), since that is what the questions literally describe. The
  underlying, unstated `wellness visit month` (the visit itself, separately deadlined at month 6)
  was set to a safe early value (`JUST 1`) in every query, per the instruction to set fields
  unrelated to the question so that conditions are satisfied.
- **Q5** ("punching my own face to show off for my friends"): encoded `hospitalization ground` as
  `Neither`, on the reading that a deliberate, voluntary act done to show off is not "accidental"
  (not unintended) and is not a sickness — so the claim fails the basic §2.1 coverage trigger, not
  because of fraud/misrepresentation (which the query explicitly rules out and which I set to
  `NOTHING`).
- **Q9** ("son biting me in the ankle" while "serving as a police officer at the time"): encoded
  `causes` as `EMPTY`, not `` `Police service` ``, on the reading above that the §3.1 exclusion
  requires the injury to have arisen out of the excluded activity — being a police officer at the
  time of an unrelated domestic injury is occupational status, not causation.
- All other "unrelated" fields (dispute/arbitration/recovery fields, `claim made setting out
basis`, `confined in us hospital`, `continuous confinement days`, `wellness visit provider
qualified`, `agreement signed`, `premium paid month`) were set to the same favorable baseline in
  every query (no dispute, claim properly made, confined in a US hospital for 3 days, qualified
  provider, signed, premium paid at month 0), since none of the nine questions turn on them.
