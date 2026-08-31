# Notes on this encoding

## Checks run

- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4` -> `Check succeeded.`
- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4` -> `Check succeeded.`

Only `l4 check` (typecheck-only, no evaluation) was run, on both files, per the task rules. The
nine `#EVAL` directives were never executed and their results are unknown to me. The `l4 check`
pass does, incidentally, confirm that every `Claim WITH ...` in `apply.l4` supplies exactly the
21 schema fields with correct names and types (a missing/extra/misnamed/mistyped field would have
been a type error), and that `covered` type-checks as `Claim -> BOOLEAN`.

## Structure of policy.l4

The `DECLARE`s and the two supporting helpers (`` `no later than` ``, `` `arose out of` ``) are
copied verbatim from `inputs/schema.md`. `covered` is built from small named predicates, one per
contract section (SS1 policy-in-effect, SS2 benefits, SS3 exclusions, SS4.2 arbitration/60-day
wait), composed as a single top-level conjunction. Every one of the 21 `Claim` fields is used
somewhere in `covered`'s logic.

## Judgement calls

1. **SS1.1(3) "still pending" reading.** SS1.3 sets two nested deadlines: the wellness visit
   itself by month 6, written confirmation of it by month 7. SS1.1(3) says the whole condition is
   fine if it "is still pending or has been satisfied in a timely fashion." I read "still pending"
   as available only up to the *earlier* of the two sub-deadlines (month 6) — before that point
   neither sub-obligation is even due, so nothing can yet have failed. At or after month 6, I
   require the full conjunction (visit on time, provider qualified, confirmation on time). This
   is a genuine simplification of a compound clause; the alternative reading (pending until month
   7, the outer deadline) is also defensible and would change the outcome for a hospitalization
   between months 6 and 7 with a late-but-still-pre-7 confirmation. None of the nine questions'
   hospitalization timing falls in that narrow window under the values I chose, so this choice
   should not by itself change any of the nine answers as encoded.

2. **"Wellness visit" vs "written confirmation" field mapping in the questions.** The questions
   (Q4, Q6, Q7, Q9) all speak of "confirmation of my wellness visit" or "proof of my wellness
   visit" being *given/provided/submitted* N months after the effective date. I mapped this
   phrase to the schema's `written confirmation month` (the SS1.3 submission-to-the-company
   deadline, month 7), not to `wellness visit month` (the underlying visit's own occurrence,
   month 6 deadline), since "provided/given/submitted ... to us" is naturally the act of
   confirming, not the act of visiting. Since no question states when the underlying visit
   itself occurred, `wellness visit month` is set to a safe early default (month 1) in every
   claim, isolating each question to the fact it actually states.

3. **Q4's hospitalization month (not stated in the question).** `hospitalization month` is a
   mandatory field with no "unrelated -> safe default" option that would leave the question's own
   fact inert: if hospitalization were set to an early, safe month (e.g. 1), the SS1.1(3)
   "still-pending" shortcut would make the late (month-8) confirmation irrelevant to the result,
   which seemed to defeat the evident point of the question. I instead set `hospitalization
   month` to 9 (after the stated month-8 confirmation), so the policy's in-force status is being
   assessed at a point where SS1.3's timeliness is actually at issue. This is an inference beyond
   what the question states, flagged here rather than treated as settled.

4. **Q5's "hospitalization ground" (punching own face to show off).** The schema's `Ground` enum
   offers `Sickness`, `` `Accidental injury` ``, or `Neither`. I encoded this claim as `Neither`:
   a deliberate act performed to show off is not a "sickness," and is not "accidental" in the
   ordinary insurance sense because the act itself was intentional (only the resulting harm, if
   any, was presumably unwanted). Under this reading `covered q5` turns on SS2.1's ground
   requirement, not on the fraud/misrepresentation facts the question volunteers — those facts
   are satisfied (both `NOTHING`) but do not by themselves establish a covered ground.

5. **Q9's causation (police officer at time of a son-bite injury).** SS3.1(4) excludes
   injury "arising directly or indirectly out of ... service in the police." The question states
   the claimant "was serving as a police officer at the time of hospitalization," but the
   proximate cause given is "my son biting me in the ankle" — a cause unconnected to police
   duties on the facts stated. I encoded `causes` as `LIST Other`, not `` LIST `Police service` ``,
   on the reading that a status fact (on duty at the time) does not by itself make the injury
   arise "out of" that service; the exclusion requires a causal connection the question does not
   supply.

6. **Premium-paid and confinement-duration fields have no explicit deadline in the contract text**
   beyond "paid at signing" (SS4.5.1) and "not exceeding 365 days" (SS2.2). `covered` treats
   "premium paid" as simply `isJust` (some month recorded), consistent with the standing
   assumption that it was paid on time, and treats `continuous confinement days` as needing to be
   a positive number at most 365 (using SS2.2's cap as a range check rather than as a
   claim-voiding condition, since the text caps how many days are *paid*, not whether the claim
   is covered at all).

7. **The 60-day proof-of-claim wait (SS4.2.1) is expressed in months** (as `p PLUS 2`, i.e. 60
   days approximated as 2 months) to match the schema's month-granularity fields
   (`written proof of claim month`, `recovery sought month`). All nine claims leave
   `recovery sought month` as `NOTHING`, so this clause is vacuously satisfied in every one of the
   nine evaluations and does not affect any of the nine answers as encoded.

None of these judgement calls were checked against the benchmark's answer key, the source paper,
or any reference encoding — per the task rules, none of those were consulted.
