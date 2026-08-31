# Notes on this encoding

## Load check

Ran, as permitted:

```
swipl -q -g halt policy.pl queries.pl
```

First attempt printed ~40 `discontiguous` warnings (exit code 0, but not silent): each
per-claim fact predicate (`claim_made/1`, `confined_in_hospital/1`, `hospital_in_us/1`, etc.)
had its clauses spread across the nine per-claim blocks in `queries.pl` rather than grouped
together, and `dynamic/1` alone does not suppress that warning in SWI-Prolog. Fixed by adding
matching `:- discontiguous` declarations for all fourteen fact predicates in `policy.pl`
(alongside the existing `:- dynamic` declarations). Re-ran the same command afterward: exit
code 0, zero bytes of output on stdout or stderr — silent, as required.

I did **not** run `q1`, `q2`, ..., `q9`, and did not otherwise query the loaded database beyond
the bare consult-and-halt above.

## Design

`policy.pl` defines one claim-parameterised predicate tree rooted at `covered(Claim)`:
`claim_made`, `policy_in_effect` (i.e. not `canceled`, per Sec 1.1-1.2), `benefit_applies`
(Sec 2.1-2.2), and `\+ excluded` (Sec 3.1 general exclusions). Every fact it depends on
(cause of injury, age, wellness-visit/confirmation timing, fraud, location, term) is declared
`dynamic` + `discontiguous` in `policy.pl` but never given a value there; `queries.pl` supplies
exactly the facts each question states, one `claim_N` per question, and nothing else -- so an
unmentioned condition or exclusion defaults, by negation-as-failure, to "not proven to have
failed / not triggered," which is what the standing preamble ("assuming all other conditions
are met and no other exclusions apply") calls for.

## Judgement calls

1. **Q5 ("punching my own face to show off for my friends"): treated as not triggering the
   benefit at all, not merely as an unexcluded event.** Sec 2.1 pays only for hospitalization
   "as a result of sickness or accidental Injury." I read a deliberate, voluntary act of
   self-harm (even one done in jest, without intent to cause the specific injury that
   resulted) as not "accidental" in the insurance sense, and obviously not a "sickness"
   either. So in `queries.pl` I assert neither `caused_by_sickness(claim_5)` nor
   `caused_by_accidental_injury(claim_5)`, which makes `benefit_applies(claim_5)` fail on its
   own terms, independent of Sec 3.1's exclusion list (which has no clause addressing
   self-inflicted or intentional acts at all). I considered the opposite reading -- that
   absent an explicit exclusion for intentional self-harm, and given the preamble's "no other
   exclusions apply," the claim should be treated as within Sec 2.1's coverage grant -- and
   think the question's explicit aside "I did not commit fraud or misrepresentation" is there
   precisely to steer the reader away from the (Sec 1.2) fraud/cancellation route and toward
   the (Sec 2.1) coverage-trigger question, which is what convinced me the intended issue is
   whether this is "accidental" at all. This is the one call in this encoding I am least
   certain of.

2. **Sec 2.2's "hospital in the United States" clause is encoded as a real, additional
   precondition (`hospital_in_us/1`) alongside Sec 2.1's sickness/injury trigger**, in tension
   with Sec 4.1's "insures You ... anywhere in the world." I encoded both clauses as written
   rather than treating one as silently overriding the other: Sec 4.1 (general conditions,
   "where does your policy apply") I read as going to the territorial scope of the *risk*
   insured against, while Sec 2.2 (benefits) I read as an additional, more specific mechanical
   precondition on when the Daily Hospital Income Benefit is actually *payable*. This
   surfaces only in claim_4 (hospitalized "while traveling abroad"), where I leave
   `hospital_in_us(claim_4)` unasserted; it turns out not to be outcome-determinative there
   either way, because that claim already fails Sec 1.3 timeliness (see below) before
   `benefit_applies/1` is even reached in the `covered/1` conjunction. Flagging it anyway
   since it is a genuine textual tension in the source document, not a settled point.

3. **Sec 1.3's two deadlines (visit occurring by month 6; confirmation supplied by month 7)
   kept as two separate fact predicates**, `wellness_visit_occurred_month/2` and
   `confirmation_supplied_month/2`, rather than collapsed into one. None of the nine questions
   ever states the date the underlying wellness visit itself took place -- each states only
   when proof/confirmation was "provided," "submitted," or "given," which I map to
   `confirmation_supplied_month/2` and treat as the operative fact under the literal text
   ("you will supply us with written confirmation ... no later than the 7th month
   anniversary"). I deliberately did not fabricate a value for
   `wellness_visit_occurred_month/2` in any of the four claims that mention this timing
   (claim_4, claim_6, claim_7, claim_9), since the question never gives that date; the rule
   in `policy.pl` still checks it (so a hypothetical future claim that *did* supply both
   dates would be handled correctly), but for these nine claims that half of the rule is
   simply never in a position to fire. I checked by hand that this choice does not change the
   answer for any of the nine claims relative to the alternative of assuming the visit
   happened at the same time as the confirmation.

4. **Sec 3.1's occupation-based exclusions (military/firefighting/police) require the
   sickness or injury to arise "directly or indirectly out of" the named service, not merely
   that the claimant holds that job at the time of hospitalization.** This is what
   distinguishes Q1 (burns "while doing my duty as a firefighter" -- causal nexus present,
   `caused_by_firefighting_service(claim_1)` asserted, excluded) from Q9 (bitten by claimant's
   own son, while merely "serving as a police officer at the time of hospitalization" -- no
   causal nexus to the injury, so `caused_by_police_service(claim_9)` is deliberately left
   unasserted, and the claim is not excluded). Consequently `caused_by_police_service/1` has
   no true instance anywhere in `queries.pl`; it is still declared dynamic/discontiguous in
   `policy.pl` so the predicate is safely callable (fails, rather than erroring) for every
   claim.

5. **Claim_2 (age 78, no stated cause of hospitalization) is given a filler
   `caused_by_sickness(claim_2)` fact**, since the question tests only the age threshold and
   the standing preamble directs that all other conditions be treated as met -- some
   qualifying, non-excluded cause has to be posited for `benefit_applies/1` to be reachable at
   all.

6. Not modeled, as out of scope for a yes/no coverage determination and/or requiring date
   arithmetic the task says is unnecessary: Sec 2.2's 365-day cap on the number of paid days;
   Sec 4.2 arbitration (a dispute-resolution precondition, not triggered by any of the nine
   fact patterns, none of which mention a dispute); Sec 4.3-4.5 (governing law, currency,
   premium timing -- assumed satisfied per the task instructions).
