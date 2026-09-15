# Notes on this encoding

## Checks run

- `JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4`
  → **`Check succeeded.`**
- `JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4`
  → **`Check succeeded.`**

Both are typecheck-only (`l4 check`, not `l4 run`); the nine `#EVAL`s in `apply.l4` were never
evaluated and I did not look at their results.

Before writing the real files, I unit-tested the _mechanics_ of the two given helpers
(`` `no later than` ``, `` `arose out of` ``) and of my own `covered` logic against small,
synthetic scenarios that do **not** reuse any fact pattern from `inputs/queries-blind.md` (e.g.
age 95, a generic "skydiving" cause claim, a generic dispute/arbitration claim) — purely to
confirm calling conventions and operator precedence in a scratch file outside the trial
directory, never against the nine benchmark questions themselves. Two syntax facts worth
recording because they aren't obvious from the skill docs:

- `` `no later than` `` and `` `arose out of` `` are called **prefix**, in the order their `GIVEN`
  parameters are declared: `` `no later than` eventMonth limitMonth `` and
  `` `arose out of` causesList cause ``.
- A bare `claim's `field`used **as a function argument** must be parenthesized —` isJust claim's `fraud month` `mis-parses as` (isJust claim)'s `fraud month` ``(a parse
error), so every such call site in `policy.l4` is written`` isJust (claim's `fraud month`) ``.
- L4 has no record-update syntax: every `Claim` in `apply.l4` is built from scratch with
  `Claim WITH` listing all eighteen fields — you cannot start from a "baseline" claim and
  override a couple of fields.

## Judgement calls in `policy.l4`

- **§1.3 "still pending" vs "satisfied timely."** Section 1.1(3) lets the policy stay in effect
  if the Section 1.3 condition is "still pending or has been satisfied in a timely fashion." I
  read the operative deadline as the 7-month confirmation checkpoint: before month 7 the
  condition is "still pending" regardless of whether the visit/confirmation have happened yet;
  at or after month 7 it must actually have been satisfied (visit ≤ month 6 by a qualified
  provider, confirmation ≤ month 7), or the policy is canceled under §1.2. Both the "still
  pending" gate and the cancelation trigger are evaluated **as of `hospitalization month`**,
  since §1.1 opens with "in effect at the time of the hospitalization."
- **Misrepresentation vs. "misrepresentation or material withholding."** §1.2 cancels for
  "fraud, or any misrepresentation or material withholding of any information." The schema
  gives only `fraud month` and `misrepresentation month` — no separate withholding field — so
  `misrepresentation month` is read as standing for that whole disjunct (misrepresentation
  _or_ withholding) rather than narrowly for misrepresentation alone.
- **Premium payment has no numeric deadline.** §1.1(2) just says the premium "has been paid";
  §3.5 describes payment mechanics (lump sum at signing) but sets no separate coverage-defeating
  deadline. I encode this as `isJust (claim's `premium paid month`)` — paid at all — rather than
  inventing a cutoff month.
- **60-day recovery-waiting-period unit mismatch.** §3.2.1's "shall not seek to recover before
  the expiration of sixty (60) days after written proof of claim" is stated in days, but the
  schema's `written proof of claim month` / `recovery sought month` fields are in months. I
  approximated 60 days as 2 months (`` `premature recovery sought` `` requires
  `recovery sought month AT LEAST written proof of claim month PLUS 2`). None of the nine
  queries exercise this clause, so the approximation doesn't affect any answer here, but it's a
  genuine unit mismatch rather than an exact reading.
- **Age exclusion is standalone.** §2.1's five sub-items are worded as one list ("arising ...
  out of: 1. Skydiving; ... 5. If your age ... is ... 80"), but item 5 isn't a _cause_ — it's an
  unconditional age cutoff. I modeled it as its own top-level exclusion (`excluded by age`),
  independent of the `causes` list, rather than trying to fit it through `` `arose out of` ``.
- **Status vs. causation for the occupation-based exclusions.** §2.1 excludes an event
  "arising directly or indirectly out of" skydiving/military/firefighting/police service — a
  causal test on the `causes` list, not a test of the claimant's occupation or status at the
  time of hospitalization. This matters for Q9 (police officer bitten by his own son): the
  cause is a domestic accident, not police duty, so `causes` is left empty there even though a
  policing-status fact is mentioned in the question.

## Judgement calls in `apply.l4`

- Every claim sets `agreement signed IS TRUE` and `premium paid month IS JUST 0` per the
  standing preamble ("assume ... the premium has been paid on time"), and defaults every field
  the question doesn't mention to the most coverage-favorable value (no dispute, no fraud/
  misrepresentation, no excluded cause, wellness-visit condition satisfied-or-not-yet-due).
- Where a question gives a "proof of the wellness visit was provided/given N months after..."
  fact (Q4, Q6, Q9), I mapped it to `written confirmation month` (the act of supplying written
  confirmation to the insurer under §1.3), not to `wellness visit month` (the visit itself,
  which none of these three questions date) — the policy text's own phrase for that act is
  "supply us with written confirmation ... of a wellness visit."
- **Q4's `hospitalization month`** is not stated in the question at all. Since the question is
  clearly built to test the late (8-month) written confirmation against the 7-month deadline, I
  set `hospitalization month IS 8` so that fact is actually load-bearing (at a hospitalization
  month before 7, §1.3 would simply be "still pending" and the late-confirmation fact would be
  moot). This is the one field in the whole file I inferred rather than transcribed.
- **Q6's `hospitalization month`** is similarly unstated; I set it to `7`, consistent with the
  stated confirmation month (6.5) having "already" happened. Unlike Q4 this choice doesn't
  actually change the outcome either way here, since 6.5 ≤ 7 makes the confirmation timely
  regardless of whether §1.3 is judged as "still pending" or "satisfied."
- **Ground classification** (`Sickness` / `Accidental injury` / `Neither`) was inferred from each
  question's described medical event: pneumonia and heart attack → `Sickness`; a fall, a
  skydiving injury, a military-training injury, and a dog^H^H^Hson bite → `Accidental injury`;
  deliberately punching one's own face → `Neither` (intentional, not an accident, and not a
  sickness). Q2 states no cause at all, so I used the neutral, unexcluded `Sickness` purely so
  the "hospitalized for sickness or accidental injury" gate doesn't itself block a question that
  is clearly only testing the age threshold.
