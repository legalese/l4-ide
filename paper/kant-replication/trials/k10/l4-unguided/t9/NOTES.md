# Notes on this trial

## Checks run

- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4` -> **`Check succeeded.`**
- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4` -> **`Check succeeded.`** (also
  clean on its own, not just as imported by `apply.l4`)
- No warnings were printed by either invocation.
- I did **not** run `l4 run`, `l4 batch`, or otherwise evaluate any `#EVAL` directive, and did not
  hand-simulate the queries against the parser/interpreter. The only executable feedback used was
  the typechecker.
- One real bug was caught and fixed this way: my first draft wrote `` `name` IF `` for six
  boolean-returning definitions, omitting the leading `DECIDE` keyword (I had over-generalized from
  a doc example that also happened to omit a parameter repetition, and conflated "parameter
  repetition is optional" with "DECIDE is optional before IF"). `l4 check` reported a parse error
  at the first such line ("unexpected IF ... expecting ... MEANS ..."), which cascaded into
  "Claim"/"covered not found" errors in `apply.l4` because the whole of `policy.l4` had failed to
  parse. Adding `DECIDE` before each of the six `... IF` definitions fixed it.
- Since I could not evaluate the file, I hand-traced the boolean algebra of `covered` for all nine
  claims against my own encoding to sanity-check internal consistency (not against any external
  answer key, which I did not have and did not look for). The trace is consistent: Q1, Q4, Q6, Q8
  reduce to FALSE and Q2, Q3, Q5, Q7, Q9 reduce to TRUE, matching what I believe the contract text
  actually says for each fact pattern.

## Judgement calls

1. **"Arose out of" is causal, not occupational.** The exclusions in Section 2.1 (skydiving,
   military, fire fighter, police, age >= 80) require the sickness or injury to arise "directly or
   indirectly out of" the named activity. I modelled the four activity exclusions as facts about
   the *cause* of the hospitalization (`` `hospitalization arose out of ...` ``), not as facts about
   the claimant's occupation or status. This matters most for Q9 ("my son biting me in the ankle
   ... I was serving as a police officer at the time of hospitalization"): the cause is a domestic
   incident wholly unconnected to police duties, so I set
   `` `hospitalization arose out of police service` `` to **FALSE** for that claim even though the
   claimant is, in that scenario, on duty. By contrast Q1 ("burns suffered while doing my duty as a
   fire fighter") and Q8 ("injured in a military training exercise") both tie the cause directly to
   the activity, so those exclusion fields are **TRUE**. This is the single most consequential
   interpretive choice in the encoding, since it is the only thing that makes Q1/Q8 and Q9 come out
   differently despite all three mentioning a listed activity.

2. **Section 1.3 has two deadlines, but the queries only ever state one.** The clause requires (a)
   the wellness visit itself to occur no later than the 6-month anniversary, and (b) written
   confirmation of it to be supplied no later than the 7-month anniversary. Every query that
   mentions this at all (Q4, Q6, Q7, Q9) states only when confirmation/proof was "given",
   "provided" or "submitted" -- never when the underlying visit itself took place. Following the
   standing instruction to satisfy every condition not referenced by a given query, I kept these as
   two separate `MAYBE NUMBER` fields in `Claim`, always set the "visit occurred" field to a safe
   early value (`JUST 1`, i.e. within the 6-month sub-deadline) in every one of the nine claims, and
   only ever plugged the query's literal figure into the "confirmation given" field. This isolates
   the fact actually under test (the 7-month confirmation deadline) from the fact no query ever
   supplies.

3. **A late Section 1.3 confirmation voids the policy outright**, not merely from the deadline
   onward. My `` `the policy has been canceled` `` rule looks only at the final value of "was
   confirmation given, and when" -- it does not additionally ask whether the hospitalization
   happened before or after that confirmation was (belatedly) supplied. This is why, for Q4, the
   exact month I chose for the hospitalization itself (I used month 8, matching the narrative) does
   not affect the result: the "confirmation was given late" branch of the logic never consults the
   hospitalization date at all (only the "confirmation never given" branch does, to decide whether
   the condition is merely still "pending"). I re-derived this by hand to confirm the choice of
   hospitalization month for Q4 is inert.

4. **Q5 ("punched own face to show off for my friends") is covered.** Section 2.1's exclusions are
   a closed, enumerated list (skydiving / military / fire fighter / police / age >= 80) with no
   catch-all for intentional, reckless, or self-inflicted injury -- a clause that is extremely
   common in real-world accident policies but is simply absent from this contract's text. I did not
   invent one. The query's explicit "I did not commit fraud or misrepresentation" reads as
   pre-empting the one clause (Section 1.2) that could otherwise have been argued to apply, which
   further suggests the intended answer is that the policy applies.

5. **Sections 3.1-3.5 are not wired into `covered`.** Section 3.1 (worldwide, 24-hours-a-day scope)
   is represented only as a comment: since it imposes no geographic restriction, there is nothing
   for "traveling abroad" (Q4) to trigger, so I did not add a location field at all. Sections 3.2
   (arbitration), 3.3 (governing law), 3.4 (currency) and 3.5 (premium timing, assumed satisfied per
   the encoding brief) govern dispute procedure, choice of law, and payment mechanics, not whether a
   given hospitalization is a covered event, so none of them feeds into the coverage decision.

6. **The Section 1.1 threshold ("hospitalization ... for sickness or accidental injury") is an
   explicit field**, always `TRUE` in all nine claims, kept mainly for faithfulness to the source
   text's own framing of the insured event; none of the nine fact patterns plausibly falls outside
   it.

## Other notes

- Every date/time fact in the encoding other than the claimant's age is a plain `NUMBER` of months
  after the policy's effective date (per the encoding brief), so the file uses no `DATE`/`DATETIME`
  values or arithmetic anywhere, and there is no `IMPORT daydate`/`datetime`.
- Checked the field/function names I introduced (`covered`, `Claim`, and all the backtick-quoted
  phrases) against the identifiers defined in `jl4-core/libraries/prelude.l4`; none collide.
- `policy.l4` declares the `Claim` record type and all rules; it defines no claim instances.
  `apply.l4` defines exactly `q1` .. `q9` as `Claim` values and nine `#EVAL covered q<n>` lines, each
  carrying its bare `qN` token, and no other `#EVAL`/`#ASSERT` directives.
