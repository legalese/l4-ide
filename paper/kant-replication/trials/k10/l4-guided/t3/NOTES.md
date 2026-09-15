# Notes on this encoding

## Checks run

Ran, from the trial directory root:

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
```

Both printed `Check succeeded.` with exit code 0. Re-ran `apply.l4` with `--json` and got
`{"diagnostics":[],"file":"apply.l4","ok":true}` — zero diagnostics, including no CONSIDER
exhaustiveness warnings. I did **not** run `l4 run` and did not evaluate any `#EVAL` directive, per
the task's rule 4.

## Judgement calls

1. **Q5 — "punching my own face to show off for my friends."** Classified
   `hospitalization ground` as `` `Accidental injury` ``, not `Neither`. The claimant's voluntary
   act was punching himself to show off; the injury itself was not the sought outcome of that act,
   so under an "accidental result" reading (the injury was unintended, even though the act causing
   it was deliberate) this counts as an accidental injury rather than an excluded, non-insured event.
   A contrary reading — that a self-administered blow is never "accidental" regardless of the actor's
   purpose — is also available; I did not find anything in the policy text itself that resolves this
   either way, so this is a genuine judgement call, not a derivation.

2. **Q9 — "serving as a police officer at the time of hospitalization."** Left `causes` as the
   catch-all `Other`, deliberately **not** including `` `Police service` ``. §2.1 excludes an event
   "arising directly or indirectly **out of**" the listed activities — a causal requirement, matching
   the pre-defined `` `arose out of` `` helper's own name. Being bitten by one's own son in the ankle
   has no causal connection to police duty; the claimant merely _held the status_ of police officer
   at that moment. This is the deliberate contrast with Q1 ("burns suffered **while doing my duty as**
   a firefighter") and Q8 ("injured **in** a military training exercise"), both of which state an
   actual causal nexus between the excluded activity and the injury and so are encoded with the
   matching `Cause` populated.

3. **§1.1(3)/§1.3 — "still pending or has been satisfied in a timely fashion."** Modelled as: if no
   written confirmation has been supplied at all, the condition is satisfied while the 7-month
   deadline (measured against `hospitalization month`, since that is the only "as of" instant §1.1
   gives us to test) has not yet passed; if a confirmation _has_ been supplied, it is checked on its
   own terms — was it supplied by month 7, was the underlying visit itself by month 6, was the
   provider qualified — independent of `hospitalization month`. This is why `hospitalization month`
   for Q4 is immaterial to the result even though Q4 never states it directly: the stated fact ("I
   had given confirmation ... 8 months after") already puts the claim in the "confirmation supplied,
   but late" branch, which does not consult `hospitalization month` at all. I set
   `hospitalization month` IS 8 there only for narrative consistency with the past-perfect phrasing
   ("I _had_ given confirmation ... 8 months after", read as preceding the hospitalization), not
   because the formula needs it.

4. **§3.2.1's 60-day waiting period is unconditional.** "In no case shall You seek to recover on this
   Policy before the expiration of sixty (60) days after written proof of claim has been submitted"
   is written as its own sentence, not inside the "where there is a dispute" sentence that precedes
   it (which explicitly says "**where there is a dispute or disagreement**, the issuance of a valid
   arbitration award shall _also_ be a condition precedent"). So `covered` applies the 60-day check
   regardless of `dispute arisen`, while the arbitration-commencement and valid-award checks are
   gated on it. None of the nine queries state arbitration or proof-of-claim facts, so this is inert
   for all of them (every claim sets `dispute arisen` IS FALSE, `written proof of claim month` IS
   NOTHING, etc.), but the fields are still real conjuncts in `covered`, per the "use ALL OF these
   fields" instruction.

5. **60 days ≈ 2 months.** The schema's `written proof of claim month` / `recovery sought month`
   fields are whole months, not days, so the 60-day wait is approximated as 2 months
   (`r AT LEAST (p PLUS 2)`). This is a unit-granularity compromise forced by the schema, not a
   reading of the contract.

6. **Fraud/misrepresentation is an absolute, not a time-gated, bar.** §1.2 says cancelation "will be
   deemed to have occurred if there is fraud, or any misrepresentation..." without tying it to a
   particular month relative to the hospitalization. `covered` treats any `JUST` value in
   `fraud month` or `misrepresentation month` as voiding "policy in effect", regardless of the
   specific month recorded.

7. **§3.1 (worldwide 24-hour coverage), §3.3 (New York law), §3.4 (US currency), §3.5 (premium paid
   as one lump sum at signing)** contribute no conjunct to `covered`. None of them state a condition
   on whether a benefit is payable, and none map to a `Claim` field — the schema's silence on
   location is itself the encoding of "insures You ... anywhere in the world" (§3.1.1), which is why
   Q4's "while traveling abroad" adds no exclusion.

8. **`hospitalization ground` = `Neither` is an absolute bar.** §1.1 conditions any benefit on "the
   hospitalization for sickness or accidental injury on which the claim ... is premised", so
   `covered`'s first conjunct rejects `Neither` outright, independent of every other condition.

9. **Placeholder `hospitalization month` values** for Q6/Q7/Q9 (not stated in those questions) are set
   to small, unrelated values (3) that satisfy the policy-term and §1.3 checks without being the
   tested fact. Q8 states "the hospitalization occurred within the policy term" directly, so
   `hospitalization month` IS 4 and `policy term months` IS 12 are chosen to make that literally true
   rather than as an arbitrary filler.

## Calling convention for the two pre-defined helpers

Neither `` `no later than` `` nor `` `arose out of` `` repeats its GIVEN parameters on the left of
`MEANS` in `inputs/schema.md`; both are called here as ordinary prefix functions in GIVEN-declared
argument order (`` `no later than` (claim's `field`) (limit) ``, `` `arose out of` (claim's `causes`)
Skydiving ``), with the genitive `claim's \`field\``always parenthesized when it is itself an
argument to a further function call — L4 parses`f r's foo`as`(f r)'s foo`, not `f (r's foo)` (a documented gotcha), so an unparenthesized `` `no later than`claim's`x`claim's`y` `` would
parse wrong. `l4 check` raised no complaint about either the verbatim helper definitions or these
call sites.
