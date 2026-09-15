# Notes — l4-guided / t8

## Checks run

- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4` — **Check succeeded.**
  (This also typechecks `policy.l4`, which `apply.l4` imports.)
- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4` (standalone) — **Check succeeded.**
- First attempt at `l4 check` failed with "I could not find a definition for the identifier
  `elem` / `isJust`" — the prelude was not in scope by default in this checkout. Fixed by adding
  `IMPORT prelude` at the top of `policy.l4`. No other errors encountered.
- Per the task rules, I did **not** run `l4 run` and did not evaluate any of the nine `#EVAL`
  directives or otherwise test `covered` against the questions.

## Judgement calls

1. **"Still pending" (§1.1(3)).** Read as a disjunct anchored to the same "at the time of the
   hospitalization" reference point §1.1 itself uses: the §1.3 condition keeps the policy in
   effect either because it has already been satisfied on time, _or_ because, as of the
   hospitalization being assessed, the 7-month confirmation deadline has not yet arrived (so
   nothing has failed yet). Encoded as `wellness confirmation timely or pending` in `policy.l4`.
   This is what makes Q3 (hospitalized at month 5, nothing yet submitted) come out as pending
   rather than failed.

2. **Premium payment (§1.1(2)).** The source text gives no explicit deadline for this condition
   (§4.5's "lump sum at signing" is payment mechanics, not phrased as a coverage gate the way
   §1.3's two deadlines are). Encoded as merely `isJust` on `premium paid month` — paid at all,
   with no comparison against hospitalization month.

3. **`hospitalization ground = Neither` (Q5).** Deliberately punching one's own face to show off
   is neither a sickness nor an accidental injury (it is intentional, not accidental), so §2.1
   never triggers regardless of the absence of fraud/misrepresentation — the two are independent
   reasons, and the question tests that "no fraud" does not rescue a claim that fails on a
   different ground.

4. **`causes` is about causation, not occupation (Q9).** The claimant being a police officer at
   the time of hospitalization does not by itself put `Police service` into `causes` — only an
   injury that actually arose out of that service would. A son's bite to the ankle is encoded as
   `Other`. This distinguishes status from causation per §3.1's "arising ... out of" language.

5. **§2.2's "confinement in a hospital in the United States."** Read literally as a real
   condition on `confined in us hospital` (used as a hard requirement in `hospital benefit
payable`), read alongside — not overridden by — §4.1.1's "insures you ... anywhere in the
   world" (taken to describe where the insured _event_ may occur, not where the paid confinement
   itself must be). For Q4 ("traveling abroad"), I nonetheless set `confined in us hospital` to
   `TRUE`: none of the nine questions is best read as turning on this field, §4.1.1's worldwide
   promise is the more prominent and specific textual signal about geography, and Q4's answer
   already turns cleanly on the late wellness confirmation (see point 6). `confined in us
hospital` is set to `TRUE` in all nine constructed claims.

6. **Hospitalization month for Q4 is unstated** ("I had given confirmation of my wellness visit 8
   months after the policy's effective date" — no month is given for the hospitalization itself).
   Read the pluperfect "had given" as placing the confirmation before the hospitalization
   narrated in the same sentence, and set `hospitalization month` to `8`. Combined with judgement
   call 1, this makes the §1.3 condition a completed failure (confirmation was actually given, at
   month 8, which is after the 7-month deadline) rather than "still pending."

7. **§4.2's 60-day wait is in days; the schema's clocks are all in months.** Approximated 60 days
   as 2 months in `recovery wait respected`. This never actually binds for any of the nine
   claims, since all nine set `recovery sought month` to `NOTHING` (recovery not yet sought is
   not addressed by any of the nine questions).

8. **Arbitration/dispute fields (§4.2).** None of the nine questions concerns a dispute, so all
   nine claims set `dispute arisen IS FALSE` and leave the rest of the arbitration-related fields
   at vacuous defaults (`NOTHING` / `FALSE`), which make `arbitration precondition met` and
   `recovery wait respected` trivially `TRUE` without exercising their more interesting branches.

## Field coverage

`covered` and its helpers use all 21 `Claim` fields at least once; none were left unused, and no
fields beyond the schema's were added to `Claim`.

## Post-restoration correction (2026-09-15)

`policy.l4`'s `NOT x OR y` line above was ambiguous under L4's own precedence
rules — `NOT` reaches to the end of its line, so it parsed as `NOT (x OR y)`,
not the intended `(NOT x) OR y`. This trial's own "Check succeeded" note
above was true when it was written: the checker started refusing this
specific ambiguity only in commit 1d061009 (2026-09-07), six days after this
trial's `inputs/` were prepared (2026-09-01). Restoring the trial under the
current toolchain therefore failed `l4 check`.

Repaired by parenthesizing to the reading the surrounding comment and field
usage make unambiguous (see the rule immediately above this note). Verified
by running the file's #EVAL cases under both parses side by side: all nine
results are identical between the old (ambiguous-as-parsed) and new
(explicit) parenthesization, so this correction changes zero recorded
outcomes for this trial — it repairs a syntax/toolchain mismatch, not the
model's answer.
