# Notes on this trial

## Checks run

- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4` -> `Check succeeded.`
  (also re-ran with `--json`: `{"diagnostics":[],"file":"policy.l4","ok":true}`)
- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4` -> `Check succeeded.`
  (also re-ran with `--json`: `{"diagnostics":[],"file":"apply.l4","ok":true}`)

Both files typecheck with zero diagnostics (no errors, no warnings). One syntax
error was hit and fixed along the way: `WHEN JUST _ THEN FALSE` is rejected by
the parser (`unexpected '_'` at that position) even though `_` works as a list
wildcard elsewhere in the language docs; replaced with a named (unused)
binding `WHEN JUST n THEN FALSE`, which checks cleanly.

I did **not** run `l4 run` or evaluate any `#EVAL` directive, per the rules.

## Judgement calls

1. **Q5 -- "punching my own face to show off" is not an accidental injury.**
   Section 2.1 pays only for confinement "as a result of sickness or
   accidental injury." I read a deliberate act performed on oneself for a
   deliberate purpose (however silly) as neither a sickness nor an accident:
   the injury was the knowing, intended-or-at-least-knowingly-risked result
   of a voluntary act, not an unforeseen mishap. The contract has no separate
   "intentional self-inflicted injury" exclusion clause -- I resolved this at
   the threshold definition (whether Section 2.1's trigger is met at all)
   rather than by inventing an exclusion the text doesn't contain. The "I did
   not commit fraud or misrepresentation" detail in the query only forecloses
   Section 1.2's first cancelation ground; it does not supply a triggering
   event under Section 2.1, so I treated it as a partial red herring. This is
   the shakiest call in the file -- a different, more literal reading ("an
   injury is accidental if its precise severity/consequence wasn't intended,
   even if the act was voluntary") would flip `due to accidental injury` to
   TRUE for q5. I encoded my best-faith reading, not certainty.

2. **Q1 vs Q9 -- "arising out of" requires causation, not mere status.**
   Section 3.1 excludes injury "arising directly or indirectly out of"
   military/firefighter/police service. Q1's burns are caused by firefighting
   duty itself (clear causal link) -- excluded. Q9's ankle bite is caused by
   the claimant's son, and the claimant merely "was serving as a police
   officer at the time of hospitalization" (temporal/status coincidence, no
   causal link to the bite) -- not excluded. I built the `Claim` record's
   exclusion flags to mean "the hospitalization was caused by X," specifically
   so this distinction has somewhere to live, rather than a flag meaning
   merely "claimant's occupation is X."

3. **Section 1.3 modelled via the confirmation's submission date only.**
   Section 1.3 actually names two dates: the wellness visit itself (must
   occur by month 6) and the written confirmation of it (must be supplied by
   month 7). None of the nine queries give an independent number for when the
   visit itself occurred -- they only ever say when confirmation/proof "was
   provided" or "given" (q4, q6, q9). I modelled Section 1.3 solely as
   "confirmation supplied, at or before month 7," on the assumption that an
   honestly-supplied confirmation attests to a visit that was itself timely.
   I did not invent a second, independent "visit date" fact that no query
   supplies.

4. **Q4 -- read as a claim with two independent defects, not one.**
   "Hospitalized due to a fall while traveling abroad" is read as the
   confinement itself happening outside the United States (not merely the
   fall). That interacts with a clause I initially almost missed: Section 2.2
   conditions the daily benefit's payability on confinement being "in a
   hospital in the United States," which is narrower than Section 4.1.1's
   "insures You ... anywhere in the world." I read 4.1.1 as worldwide scope
   for the underlying insured *risk* (no territorial exclusion on the event),
   and 2.2 as a separate, narrower condition specifically on when the *daily
   benefit* is payable -- so both are encoded, and q4 fails coverage on two
   independent grounds: the late wellness-visit confirmation (8 months, past
   the Section 1.3 seven-month deadline) and the non-US hospital location.
   Flagging this because it's the one place I changed my model mid-encoding
   after a second, closer read of Section 2.2 -- worth double-checking against
   the source text if this trial's score looks off on q4.

5. **Scope decisions (not really "calls," just boundaries drawn).**
   - Section 1.2's cross-reference to "Section 5" for the policy term is a
     drafting error in the source (Section 5 is the benefit/premium amounts;
     the term is actually defined in Section 4.6). I used Section 4.6's
     one-year term, since that's the only place a term is actually stated.
   - Sections 4.2 (arbitration/dispute procedure), 4.3 (governing law), 4.4
     (currency), and 4.5 (premium payment timing) are not modelled as
     coverage gates -- they are dispute-resolution and payment-mechanics
     clauses that no benchmark question raises (none of the nine queries
     mention a dispute or a payment-currency issue), and 4.5 is subsumed by
     the task's standing assumption that the premium was paid on time.
   - Section 2.2's 365-day cap on payable days is mentioned in a comment but
     not wired into `covered`: it bounds how much is paid over a long
     confinement, not whether the policy applies at all, and no question
     gives a confinement length.
   - Section 5's dollar amounts ($500/day benefit, $2000 premium) are not
     encoded -- all nine questions are yes/no coverage questions, not
     benefit-quantum questions.
