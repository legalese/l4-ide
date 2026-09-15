# Notes on this encoding

## Checking performed

Ran `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4` (which typechecks
`policy.l4` transitively via its `IMPORT`) repeatedly while drafting, and again on the
final version with `--json`:

```
{"diagnostics":[],"file":"apply.l4","ok":true}
```

Zero diagnostics — no errors, no warnings (in particular, all `CONSIDER` blocks are
exhaustive). I did **not** run `l4 run` on `apply.l4` and did not evaluate or otherwise
inspect the value of any `#EVAL covered qN` directive, per the rules.

I did use `l4 run` on a handful of small, throwaway scratch files (outside this trial
directory, in my own scratchpad) with dummy data unrelated to this policy, purely to
confirm generic L4 syntax mechanics before relying on them here:

- that a genitive expression (`claim's `field``) passed as one of several arguments to
a prefix function must be parenthesized (`f (claim's `field`) x`), or it silently
mis-parses as `(f claim)'s field` and then fails to typecheck. This bit even for a
single-argument call like `isJust claim's `field``, which needed
  `isJust (claim's `field`)`.
- that `NOT` and infix comparisons (`AT MOST`, `GREATER THAN`, ...) applied directly to
  a genitive expression do _not_ have this problem (`NOT claim's `flag`` and
`claim's `a` GREATER THAN claim's `b`` both parse and evaluate as intended).
- that a `CONSIDER` nested inside a `WHEN` branch of an outer `CONSIDER` (used in the
  arbitration and 60-day-window helpers) lays out and evaluates correctly.

None of this touched the Chubb policy text, the schema, or the nine questions.

## Judgement calls

1. **"Still pending" (1.1(3)), not just "satisfied" (1.2).** 1.1 conditions the benefit
   on the policy being in effect "at the time of the hospitalization," and explicitly
   allows condition 1.3 to be either satisfied _or still pending_ at that moment.
   I modelled each of 1.3's two deadlines (wellness visit by month 6, confirmation by
   month 7) as "timely, OR the deadline hasn't arrived yet as of the hospitalization
   month" — not simply "was it eventually done on time," which would ignore the
   "pending" alternative the text explicitly grants. `condition 1.3 satisfied or still
pending` in `policy.l4` is the compositional AND of the two per-deadline checks.

2. **Fraud/misrepresentation timing.** By the same "at the time of hospitalization"
   logic, I treat fraud/misrepresentation as disqualifying only if it occurred at or
   before the hospitalization month (reusing the given `no later than` helper against
   `hospitalization month` as the limit, rather than a fixed literal), not merely "ever,
   at any time." None of the nine queries turn on this distinction (Q5 and Q8 say flatly
   "I did not commit fraud [or misrepresentation]," which is `NOTHING` either way), but
   it seemed the more defensible reading of 1.2 given 1.1's framing.

3. **"Material withholding of information" folded into `misrepresentation month`.**
   1.2's cancelation trigger lists three things — fraud, misrepresentation, _and_
   material withholding of information — but the schema provides only two fields
   (`fraud month`, `misrepresentation month`). Since I may use only the given fields, I
   read `misrepresentation month` as standing in for both misrepresentation and
   material withholding.

4. **"Sixty (60) days" (arbitration, §3.2) read as 2 months.** Every other temporal
   field in the schema is in whole months; the arbitration clause is the only place the
   source text uses days. I converted 60 days to 2 months (60/30) for
   `written proof of claim month` → `recovery sought month` comparisons, rather than
   inventing a separate day-granularity field. This doesn't affect any of the nine
   queries — none mentions arbitration, disputes, or recovery timing, so I set
   `dispute arisen` to FALSE and the related fields to values that trivially satisfy
   §3.2 in every claim.

5. **Q5 — Ground = `Neither`, not `Accidental injury`.** "Punching my own face to show
   off for my friends" is a deliberate, self-inflicted act, not an _accident_. Since the
   schema gives three grounds (`Sickness`, `Accidental injury`, `Neither`) rather than
   two, and 1.1 only pays benefits for "hospitalization for sickness or accidental
   injury," I classified this claim's ground as `Neither` — the claim is disqualified by
   the nature of the event itself, independently of the (correctly negated) fraud/
   misrepresentation facts the question also supplies.

6. **Q9 — `causes` = `EMPTY`, not `Police service`.** The question states the claimant
   "was serving as a police officer at the time of hospitalization," but the
   hospitalization was caused by "my son biting me in the ankle." §2.1 excludes events
   "arising directly or indirectly out of ... service in the police" — a causal
   requirement, not a mere occupational-status-at-the-time requirement. A domestic dog-
   bite-equivalent injury has no causal connection to police duties, so I did not add
   `Police service` to this claim's `causes` list. (Contrast Q1 and Q8, where the query
   explicitly ties the injury to the excluded activity — "while doing my duty as a
   firefighter," "injured in a military training exercise" — which I did encode as the
   corresponding `Cause`.)

7. **Q4 — `hospitalization month` chosen as 9.** The query gives the written-
   confirmation month (8, which is after the 7-month deadline) but not the
   hospitalization month itself. I placed the hospitalization after month 8 (the query's
   "I _had given_ confirmation ... 8 months after" reads as already-completed by the
   time of the events described), which makes the outcome the same under either a
   strict or a generous reading of judgement call #1: by month 9 the confirmation
   deadline has passed and confirmation was in fact late, so condition 1.3 has
   definitively failed either way.

8. **Premium payment — presence only.** `premium paid month` is checked for `isJust`
   (paid at all), with no separate deadline comparison. §1.1(2)/§3.5 say the premium is
   paid as a lump sum "at signing," but the text gives no explicit month-limit for
   payment distinct from that, so there is nothing else in the schema's vocabulary to
   compare it against.

9. **Unspecified fields.** For every field a given question doesn't address, I set a
   value that keeps that clause satisfied (agreement signed; premium paid at month 0;
   wellness visit and confirmation timely; no fraud/misrepresentation/dispute; policy
   term of 12 months with hospitalization safely inside it), per the task instruction to
   set unrelated fields so that no exclusion is inadvertently triggered.

## Scope discipline

I did not open `bench/keys.json`, `fixtures/queries.json`, `artifacts/`,
`FOUNDATION.md`, `source-defects.md`, `README.md`, or `jl4/examples/legal/chubb/`, and
did not search the web. Language reference came only from the `writing-l4-rules` skill,
`doc/reference/`, and other `.l4` files under `jl4-core/libraries/` (specifically
`prelude.l4`, to confirm `elem`, `isJust`, `isNothing` signatures and calling
conventions, and to check whether forward references between definitions are allowed).
