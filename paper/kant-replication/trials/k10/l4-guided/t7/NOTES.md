# NOTES

## Checks run

- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4` -> `Check succeeded.`
- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4` -> `Check succeeded.`

Only `l4 check` (typecheck-only, no evaluation) was run, on both files, each once. `l4 run`
was never invoked, so the nine `#EVAL` directives in `apply.l4` were never evaluated and the
nine answers were never seen.

## Judgement calls

1. **"Still pending" vs "satisfied" for the Section 1.3 wellness-visit condition.** Section
   1.1(3) lets the policy stay in effect if 1.3 is "still pending or has been satisfied in a
   timely fashion"; Section 1.2 cancels the policy if 1.3 "has not been satisfied in a timely
   fashion" (no explicit pending carve-out there). Read literally and independently these two
   clauses conflict (on the literal words of 1.2, the policy would be cancelled from day one,
   before the 7-month deadline has even arrived, since nothing has been "satisfied" yet). I
   harmonised them the way that makes both clauses consistent: `policy canceled` treats 1.3 as
   failed only once it is no longer pending AND not satisfied, so `wellness visit condition met
or pending` (satisfied OR pending) is exactly the negation of that failure. I then defined
   "still pending" narrowly: no written confirmation has been supplied yet (`written
confirmation month` is `NOTHING`) and the hospitalization occurs at or before month 7. Once a
   confirmation HAS been supplied, it is judged directly against the month-7/month-6 deadlines,
   whether timely or not — it is no longer "pending" regardless of when the hospitalization
   happened. I deliberately avoided the alternative reading where "pending" is just
   "hospitalization month <= 7" independent of whether confirmation was already supplied,
   because that reading would let a late-supplied confirmation (see Q4) be neutralised merely by
   choosing an early, unstated hospitalization month — which would make the encoding's answer to
   Q4 depend on a fact the query never gives, rather than on the late-confirmation fact it does
   give.

2. **Q5 — "punching my own face to show off for my friends."** The schema's `Ground` enum
   offers `Sickness`, `` `Accidental injury` ``, and `Neither`, and Section 1.1 only pays
   benefits for hospitalization "for sickness or accidental injury." I read a deliberate,
   voluntary act (punching oneself to show off) as not "accidental" in the ordinary sense
   (accidental = unintended), and not sickness either, so I encoded `hospitalization ground IS
Neither` for `q5`, which fails `covered peril` regardless of every other fact — including the
   claimant's truthful disclaimer of fraud/misrepresentation, which I read as a deliberate
   distractor pointing at the wrong issue. This is a genuine interpretive call: the given policy
   text has no express "intentional/self-inflicted injury" exclusion or definition of
   "accidental," so a reader could instead argue the resulting hospitalization was still an
   unintended _result_ even though the act was intentional. I went with the stricter reading and
   flag it here rather than picking silently.

3. **Q9 — "serving as a police officer at the time of hospitalization."** Section 2.1 excludes
   hospitalization "arising directly or indirectly out of ... service in the police" — causal
   language, not claimant-status language. Since the stated cause of hospitalization is the
   claimant's son biting their ankle, which has no causal connection to police duty, I set
   `causes IS EMPTY` (no excluded cause present) rather than including `` `Police service` ``,
   treating "I was serving as a police officer at the time" as a status fact that does not by
   itself put the hospitalization's cause in the excluded list. Same reasoning kept `causes`
   `EMPTY` (rather than populated) for every other claim where the stated mechanism of injury
   isn't one of the four enumerated activities.

4. **Q6 — "proof of my wellness visit was provided 6.5 months after the effective date."**
   Section 1.3 distinguishes the wellness visit itself (must occur no later than month 6) from
   the written confirmation of it (must be supplied no later than month 7). I read "proof ... was
   provided" as referring to the act of supplying the written confirmation (`written
confirmation month IS JUST 6.5`), not to the date the underlying visit occurred, and left the
   visit's own month at a comfortably-compliant, unstated value (month 4). This choice is moot
   for Q6's outcome either way, since the skydiving exclusion (Section 2.1(1)) is independently
   dispositive, but it is recorded here since it's an interpretive call about a fact the query
   does state.

5. **Premium payment and fraud/misrepresentation are treated as presence-only, not
   date-compared.** `` `premium paid month` `` gates coverage only via `isJust` (paid at all);
   the policy text ties the premium due date to signing but the schema has no "signing month"
   field to compare against, so no numeric deadline check was added. Likewise `` `fraud month` `` and `` `misrepresentation month` `` cancel the policy via `isJust` alone, without comparing
   the recorded month to `hospitalization month` — the text states cancellation "if there is
   fraud" with no timing qualifier, so any occurrence (at any month) was treated as
   disqualifying.

6. **No separate field for "material withholding of information."** Section 1.2 cancels for
   "fraud, or any misrepresentation or material withholding of any information," but the schema
   supplies only `` `misrepresentation month` ``. That one field is read as standing for the
   whole "misrepresentation or material withholding" disjunct, since the schema gives no
   narrower alternative and I was told to use only the given fields.

7. **60-day recovery bar (Section 3.2.1) approximated in months.** The schema is month-granular
   throughout (no day-level field), so "sixty (60) days after written proof of claim" was
   approximated as 2 months when comparing `` `recovery sought month` `` against `` `written
proof of claim month` ``. None of the nine queries exercise this clause (or the dispute/
   arbitration clause above it), so every claim in `apply.l4` sets `` `dispute arisen` IS FALSE ``, both settlement/arbitration month fields to `NOTHING`, `` `valid arbitration award issued`
IS FALSE ``, `` `written proof of claim month` IS NOTHING ``, and `` `recovery sought month`
IS NOTHING `` — all facts unrelated to every one of the nine questions.

8. **Age exclusion and term-completion boundaries.** "Equal to or greater than 80" was encoded
   as `AT LEAST 80` (inclusive). Automatic cancellation "on the last day of the policy term" was
   read as taking effect only once that day has fully elapsed, so a hospitalization occurring
   exactly on `` `policy term months` `` is still within the term (`AT MOST`, not strict `LESS
THAN`); only a hospitalization month strictly greater than the term length falls outside it.

## Field usage

`covered` and its helpers use all eighteen `Claim` fields and both supplied helpers (`` `no
later than` `` used three times: written confirmation vs. month 7, wellness visit vs. month 6,
and arbitration vs. unable-to-settle-plus-3; `` `arose out of` `` used four times, once per
enumerated excluded activity). No new record fields were introduced; no supplied helper was
redefined.
