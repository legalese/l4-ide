# Notes — prolog-unguided / t5

## Load check

Ran `swipl -q -g halt policy.pl queries.pl` from the trial directory.

- **First attempt**: silent except for a run of `Warning: ... Clauses of
<predicate> are not together in the source-file` for `age_at_hospitalization/2`,
  `hospitalization_month/2`, `wellness_visit_month/2`, `wellness_confirmation_month/2`
  and `cause_activity/2`. These predicates are declared `dynamic` in `policy.pl`
  (so an absent fact fails cleanly instead of raising `existence_error`), but
  `dynamic` alone does not suppress SWI's discontiguous-clause warning — the
  facts in `queries.pl` are grouped by claim/question rather than by predicate.
- **Fix**: added explicit `:- discontiguous ...` directives for those five
  predicates at the top of `queries.pl`.
- **Second attempt**: completely silent, exit code 0. This is the state of
  the files now.

I did not run `q1`..`q9`, and did not otherwise query the encoding against
the nine questions, per the rules.

## Judgement calls

1. **Section 1.3 has two sub-deadlines, but the questions only ever state
   one date.** The clause reads: confirmation must be supplied "no later
   than the 7th month anniversary" of "a wellness visit ... occurring no
   later than the 6th month anniversary." I modeled these as two separate
   facts, `wellness_visit_month/2` and `wellness_confirmation_month/2`. Q4,
   Q6, Q7 and Q9 each state only when confirmation was "given" / "provided"
   / "submitted" — never a separate date for the underlying visit. I fixed
   `wellness_visit_month` at a comfortably compliant default (month 1) in
   every one of those claims and let the stated figure drive
   `wellness_confirmation_month`, since the visit's own timing is not what
   any question puts in issue. (This choice is inert for all nine
   questions: the one borderline case, Q6's 6.5 months, is independently
   excluded by the skydiving clause regardless of how this is resolved.)

2. **Condition-1.3 failure is modeled as unconditional, not
   time-indexed against the hospitalization.** Section 1.1(3)/1.2 read
   naturally as "cancel once the 1.3 deadline passes without timely
   compliance," which in principle could matter if a hospitalization
   preceded such a cancelation. None of the nine questions state both a
   hospitalization month _and_ a wellness-confirmation month, so this
   ordering is never actually in issue; I treated a late confirmation (or
   late visit) as defeating coverage outright rather than modeling a
   pending/failed state machine against the hospitalization clock. Worth
   flagging in case a held-out question exercises that interaction.

3. **Q5 (punching own face to show off): no exclusion applied.** Section
   2.1's five General Exclusions do not mention intentional acts,
   self-infliction, or recklessness. I treated Section 2.1 as an exhaustive
   list rather than importing an unwritten "accidental means
   unintentional-act" doctrine, so this claim is not excluded on that
   ground in my encoding. This is the most textually faithful reading I
   could construct from the document as given, but it is a genuine
   judgement call, not something the text states outright — a different
   (equally defensible) reading might contest whether an intentionally
   self-inflicted act is a "sickness or accidental injury" at all, which
   the given text never defines.

4. **Q9 (son's bite while serving as a police officer): occupation ≠
   causation, so no exclusion applied.** Section 2.1 item 4 excludes an
   event "arising directly or indirectly out of ... service in the
   police" — I read this as requiring the injury to arise out of that
   service, not merely to coincide with the claimant holding that job.
   A son biting an ankle has no causal link to police duty, so
   `cause_activity(claim_9, police_service)` was deliberately **not**
   asserted, unlike Q1 (firefighter duty directly caused the burns) and Q8
   (military training directly caused the injury), where the causal link
   is explicit in the question.

5. **Governance/scope clauses not encoded as coverage rules.** Section
   3.1 (worldwide, 24-hour coverage) is a grant, not a restriction, so
   nothing tests location or time of day (relevant to Q4's "traveling
   abroad," which is a red herring under this policy). Sections 3.3–3.5
   (New York law, US-currency payments, lump-sum premium timing) go to
   administration of the policy, not to whether a given hospitalization is
   covered, so they were not translated into rules bearing on `covered/1`.

6. **Section 3.2 (arbitration / 60-day waiting period) encoded but
   inert for all nine questions.** No question describes a dispute or an
   already-submitted proof of claim, so `arbitration_condition_satisfied/1`
   and `waiting_period_satisfied/1` default to true by the absence of
   `dispute_exists/1` and `proof_of_claim_submitted_days_ago/2` facts.
   Included for faithfulness to the full text (Step 1 asks for a complete
   translation of the contract, not just of the nine questions), at no
   cost to the nine answers.

7. **Policy-term boundary treated at month granularity.** "Automatically
   canceled at midnight ... on the last day of the policy term" (one year)
   is encoded as `hospitalization_month(Claim, M), M > 12` causing expiry —
   i.e. month 12 itself is still within term. None of the nine questions
   approach this boundary (largest stated figure is 8 months), so the
   exact day-vs-month rounding has no effect here.

## Disclosure: pre-existing session context

This session's standard project memory (auto-loaded into context before
this task began, not something I searched for or opened) contains a
one-line index entry for a "Kant/Chubb replication" project referencing
arXiv 2502.17638, noting that "the benchmark fixture has §2 DELETED, so
Q5's gold is underivable," and a separate entry noting that an _unguided_
NL-to-Prolog encoding is measured to perform worse than a no-logic
baseline in this same experimental family. I did not open any of the
forbidden files (`keys.json`, `queries.json`, `FOUNDATION.md`,
`source-defects.md`, the reference L4 corpus, etc.) and did not search the
web. I record this because it is the kind of thing the experiment design
would want to know about even when unavoidable: the "§2 deleted" note is
consistent with what I independently observed just from
`inputs/chubb-policy.txt` (the fixture stops at Section 3.6 with no
benefits/coverage section at all), and I did not use either memory item to
back-solve any specific answer — I don't have, and didn't seek, the actual
key or gold answers for any of the nine questions. The Q5 judgement call
above was constructed from the given text alone (see item 3); the
"unguided tends to underperform" note did not change my effort level or
approach.

## What was produced

- `policy.pl` — the contract's rules (`covered/1` plus its supporting
  predicates), all per-claim facts left undefined (dynamic-declared only).
- `queries.pl` — `q1`..`q9`, each `qN :- covered(claim_N).`, with the
  per-claim facts for that question plus every background condition
  needed to make everything _not_ tested by that question hold.
