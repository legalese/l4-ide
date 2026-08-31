# Notes — l4-guided trial

## Checks run

- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4` — **Check succeeded.**
- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4` — **Check succeeded.**

Both were re-run once more after the files were finalized, immediately before writing this
note, with the same result. No `l4 run` (or any other evaluation) was performed on either file,
and no `#ASSERT`/`#EVAL` beyond the required nine `q1`..`q9` directives were added — per the task
rules, the nine questions were never evaluated against `covered`.

Before writing `policy.l4`, I used a scratch directory outside the trial (under the session's
`/private/tmp/.../scratchpad/`) to check several L4 syntax points empirically with throwaway
`Widget`-style dummy data — never the Chubb domain content or the nine questions — via `l4 run`
and `l4 check`. That confirmed, in particular: (a) `elem`/`isJust`/`isNothing` require an explicit
`IMPORT prelude` (the skill's own `builtins.md` says prelude "is loaded automatically" — that
appears to be stale documentation; empirically it is not, at least for this checkout), even though
the given `` `arose out of` `` helper calls `elem` bare; (b) the genitive-vs-application
precedence trap (`f r's foo` parses as `(f r)'s foo`) is real for ordinary named functions
(confirmed needing `` `no later than` (claim's `foo`) 7 `` with parens) but does **not** apply to
keyword operators (`NOT x's foo`, `x's foo AND ...`, `x's foo LESS THAN ...` all parse as expected
without extra parens); (c) multi-word backtick enum constructors (e.g. `` `Accidental injury` ``)
pattern-match fine in `CONSIDER`/`WHEN`; (d) nested `CONSIDER` inside a `WHEN JUST x THEN CONSIDER
...` arm, and multi-line parenthesized `AND`/`OR` groups, both parse and evaluate as intended.

## Judgement calls made when reading the policy

1. **"Still pending" (§1.1 condition 3) vs. "has not been satisfied in a timely fashion" (§1.2).**
   The contract gives §1.3 (wellness visit + written confirmation) two different framings: §1.1
   allows the condition to be merely "still pending", but §1.2's cancellation trigger is phrased
   as an unqualified "has not been satisfied". Read literally and combined naively, the "pending"
   allowance would be meaningless (any not-yet-satisfied state would already cancel the policy
   under §1.2). I resolved this by treating "still pending" as applying **only** when the month
   field in question is genuinely unrecorded (`NOTHING`) **and** its own deadline (month 7 for
   confirmation, month 6 for the visit) has not yet arrived as of `hospitalization month`. Once an
   actual month value is on record, only that value against the fixed deadline matters — a known
   *late* value (e.g. confirmation at month 8) is an unconditional failure regardless of when the
   hospitalization occurred, which is what makes the Q4-style fact pattern (a late confirmation,
   with no stated hospitalization month) decidable without gaming the "unrelated field" freedom on
   `hospitalization month`. This is implemented in `` `confirmation limb met` `` / `` `wellness
   visit limb met` `` in `policy.l4`.

2. **"Material withholding of information" (§1.2) has no field of its own.** The `Claim` schema
   gives fields for `fraud month` and `misrepresentation month` but nothing for withholding. I did
   not invent a field (the task says use ONLY the given fields), so `` `policy canceled` `` reads
   §1.2's fraud/misrepresentation/withholding triplet as covered by the two fields that exist. This
   is a fidelity gap inherited from the schema, not something `covered` can repair.

3. **60-day pre-recovery bar (§3.2.1) vs. a month-grained schema.** "You shall not seek to recover
   ... before the expiration of sixty (60) days after written proof of claim" is a day-denominated
   deadline, but `written proof of claim month` / `recovery sought month` are both in months. I
   approximated 60 days as 2 months (`` r AT LEAST (p PLUS 2) `` in `` `recovery timing condition
   satisfied` ``). This never affects any of the nine answers: none of the nine questions mention
   seeking recovery, so every query sets `recovery sought month` to `NOTHING`, which is vacuously
   fine under this helper regardless of the day/month approximation.

4. **Q5 — "punching my own face to show off" is `Neither` sickness nor accidental injury.** A
   deliberate, voluntary act aimed at entertaining friends is not an accident (not unintended) and
   is not a sickness, so `hospitalization ground` is set to `Neither`, which fails the §1.1
   chapeau ("hospitalization for sickness or accidental injury") outright, independent of the
   fraud/misrepresentation facts the question also supplies. The schema's inclusion of `Neither` as
   a third `Ground` constructor (rather than only `Sickness` / `` `Accidental injury` ``) reads as
   built for exactly this case.

5. **Q9 — a son biting the claimant's ankle while the claimant "was serving as a police officer at
   the time of hospitalization."** I read the §2.1 exclusion ("arising directly or indirectly out
   of ... service in the police") as requiring a causal nexus between the excluded activity and the
   injury, not mere temporal coincidence with employment status. A domestic bite has no causal
   connection to police duties, so `causes` is set to `LIST Other` rather than including `` `Police
   service` ``, and the police-service exclusion does not fire for this claim. This is the one
   query where I think a less careful reading could plausibly go the other way (treating "at the
   time of hospitalization" as sufficient on its own), so it is flagged here explicitly rather than
   silently baked into the fact pattern.

6. **`causes` is `EMPTY` for a bare sickness (pneumonia, heart attack) but `LIST Other` for a
   described non-excluded mechanism (a fall, a bite, punching one's own face).** The `Cause` type
   is about external causing *activities* (skydiving, military/police/firefighting service,
   `Other`), not about medical diagnoses. Pneumonia and a heart attack are illnesses with no
   described external activity, so I left `causes` `EMPTY` for those; a fall, a bite, and a
   self-inflicted punch are all described mechanisms/events that are not any of the four excluded
   activities, so I recorded them as `LIST Other` for fidelity even though it makes no difference to
   `covered` (neither `EMPTY` nor `LIST Other` ever satisfies any of the four `` `arose out of` ``
   exclusion checks).

7. **Premium-payment timing.** §1.1 condition 2 just says the premium "has been paid," with no
   explicit deadline. Since the field is `MAYBE NUMBER` (not `BOOLEAN`), I chose to require it was
   paid no later than the hospitalization month itself (`` `no later than` (claim's `premium paid
   month`) (claim's `hospitalization month`) ``), on the theory that a premium paid *after* the
   hospitalization it is meant to cover cannot support "the policy being in effect ... at the time
   of the hospitalization." All nine queries set `premium paid month` to `JUST 0`, so this choice
   does not affect any of the nine answers.

8. **Style: plain `AND`/`OR`/`NOT`/`CONSIDER` rather than asyndetic `...`/`..` sugar or inert
   quoted-prose strings.** The drafting-patterns reference documents an isomorphic house style using
   asyndetic operators and verbatim inert strings for enumerated statutory lists. I deliberately did
   not use that style here, to minimize syntax surface I could not verify by running the actual
   nine evaluations (only `l4 check`, not `l4 run`, is permitted on the real files). Section-number
   comments carry the traceability instead.

## Fields used

`covered` (via its helper predicates) references all 18 `Claim` fields and only those 18; verified
by grepping `policy.l4` for `` claim's `<field>` `` once per declared field. Both given helpers
(`` `no later than` ``, `` `arose out of` ``) are called (four times and four times respectively)
rather than re-implemented.
