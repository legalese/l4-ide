# NOTES

## Load check

Ran (as permitted, no q1..q9 execution):

```
swipl -q -g halt policy.pl queries.pl
```

First attempt printed 16 warnings, all of the form "Clauses of X/2 are not
together in the source-file" for `hospitalization_ground/2`,
`age_at_hospitalization/2`, `wellness_confirmation_months/2`, and
`hospitalization_time_months/2` — because `queries.pl` groups its facts by
question (Q1's facts, then Q2's, etc.) rather than by predicate, so clauses
for the same predicate are scattered through the file. `:- dynamic` alone
did not suppress these in this SWI-Prolog (9.2.9); I added explicit
`:- discontiguous` directives in `policy.pl` for those four predicates
(kept next to the existing `:- dynamic` declarations) rather than
reorganising `queries.pl` away from its readable one-block-per-question
layout. After that change, the load check is silent with exit code 0.

No other errors or warnings appeared (no existence errors, no
redefined-system-predicate warnings, no singleton-variable warnings).

## Judgment calls

1. **"Sickness or accidental injury" as a threshold requirement, not just
   an exclusion (Q5).** Section 1.1 conditions payment on "the
   hospitalization for sickness or accidental injury." I read this as a
   substantive requirement on the type of event, not mere preamble:
   punching one's own face on purpose, to show off, is a deliberate act,
   not an accident, and isn't a sickness either. I encoded this as
   `hospitalization_ground(claim_5, intentional_self_inflicted)`, which
   `qualifying_hospitalization/1` rejects (it only accepts `sickness` or
   `accidental_injury`), independent of the Section 2.1 exclusion list
   (which does not mention self-inflicted or intentional acts at all).
   This is the "accidental means" reading of accident-insurance law
   (the causing *act* must be unintended, not just the *result*); the
   competing "accidental results" reading would treat this as covered
   since no exclusion clause names it. I judged the first reading more
   textually grounded, given that "accidental" is doing real work in
   1.1's own wording, but flag this as the single most debatable
   interpretive choice in this encoding.

2. **Status vs. cause for the four service-related exclusions (Q9,
   also relevant to Q1/Q8).** Section 2.1 excludes events "arising
   directly or indirectly out of" skydiving/military/firefighter/police
   service — a causal test, not a status test. For Q9 (bitten by one's
   own son while on duty as a police officer), I did not assert
   `caused_by_police_service(claim_9)`, because the bite does not arise
   out of police work even though the claimant happened to be serving
   at the time. For Q1 and Q8, by contrast, the stated cause (burns from
   firefighting duty; injury from a military training exercise) is
   itself the service activity, so I did assert the corresponding
   `caused_by_*` fact. `general_exclusion_applies/1` is built entirely
   from these causal facts (plus the age threshold) rather than from
   claimant-status facts, so this distinction is load-bearing in the
   rules, not just in how I filled in the per-claim facts.

3. **Section 1.3 collapsed to a single reported time per claim.**
   Section 1.3 actually states two deadlines: the wellness visit itself
   must occur by the 6-month anniversary, and written confirmation of it
   must be supplied by the 7-month anniversary. `policy.pl` keeps both as
   separate dynamic facts (`wellness_visit_months/2` for the visit,
   `wellness_confirmation_months/2` for the confirmation), each
   defaulting to "on time" if unstated. Every question that mentions this
   condition only gives one number — "proof/confirmation was
   provided/submitted N months after the effective date" — which I
   treated as `wellness_confirmation_months` (checked against the
   7-month deadline), leaving `wellness_visit_months` unstated (and thus
   assumed satisfied) for every claim. I did not need to resolve what
   happens if a claim gave both numbers with the visit itself late but
   confirmation timely, since none of the nine questions does.

4. **A late Section 1.3 confirmation cancels the policy outright, not
   just "as of" some date (Q4).** Q4 gives a confirmation time (8
   months, i.e. late) but no hospitalization time. I modeled
   `wellness_condition_ok/1` as a fact about the claim as a whole (an
   unconditional deadline check), so a stated late confirmation triggers
   cancelation regardless of when the hospitalization happened, rather
   than making cancelation depend on comparing the hospitalization time
   to the 7-month mark. This matches Section 1.2's "will be deemed to
   have occurred" phrasing (a determination made once the facts are
   known, not a state that only takes effect from the moment of
   breach). No question actually exercises the alternative reading
   (none pairs an explicit hospitalization time with a late confirmation
   time), so this choice does not change any of the nine answers either
   way.

5. **Arbitration (3.2), governing law (3.3), currency (3.4), and premium
   timing (3.5) were read but not encoded as predicates.** None of the
   nine questions turns on dispute-resolution procedure, choice of law,
   payment currency, or premium timing (the last is also covered by the
   task's blanket assumption that the premium was paid on time), so
   encoding them would not affect any `covered/1` result. Section 3.6
   (one-year term) and Section 3.1.1 (worldwide, 24-hour coverage) *are*
   used: the former sets the 12-month bound in `term_not_expired/1`, and
   the latter is why Q4's "traveling abroad" detail was not turned into
   an exclusion fact of its own (there is no geography-based exclusion
   to trigger).

6. **Claim identifiers follow the task's own example.** `TASK.md`'s
   worked example uses `covered(claim_1)`, so claims are named
   `claim_1` .. `claim_9` (matching each question's number) rather than
   some other scheme.
