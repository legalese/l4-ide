# Notes on this encoding

## Load check

Ran exactly the sanctioned command from the trial directory root:

```
swipl -q -g halt policy.pl queries.pl
```

Output: silent, exit code 0. I also re-ran it without `-q` (still redirecting
both stdout and stderr) to make sure no warnings were being swallowed by the
quiet flag (e.g. discontiguous-clause or singleton-variable warnings) —
that run was also completely silent, 0 bytes of output. I did not run
`q1`..`q9`, or call `covered/1` on any claim, or otherwise evaluate the
encoding against the nine questions.

## Design summary

- `policy.pl` defines only rules. Every predicate a query needs to supply
  facts for (`hospitalization_event/1`, `hospitalization_cause/2`,
  `age_at_hospitalization/2`, `hospitalization_month/2`,
  `confirmation_supplied_month/2`, `wellness_visit_month/2`, `fraud/1`,
  `misrepresentation/1`, `material_withholding/1`) is declared `:- dynamic`
  in `policy.pl`, so a claim that never mentions one of them fails cleanly
  instead of raising a "procedure does not exist" error.
- Per the task brief, Section 1.1 items 1-2 (signature, premium paid) are
  assumed true throughout and are not modeled at all — no predicate exists
  for them, since there is nothing for a caller to ever assert.
- Times are months elapsed since the effective date (per the task's
  relative-dates instruction); age is a plain year count, not relative to
  the effective date.
- Sections 3.2-3.5 (arbitration procedure, governing law, currency,
  premium-payment mechanics) are not encoded as callable predicates. None
  of them bear on whether a hospitalization event is *covered*, and none of
  the nine questions exercise them; encoding them would add predicates the
  benchmark never calls, and rule 4 of the task ("all predicates used ...
  fully defined") is more easily kept if I don't invent unused surface
  area.
- Wherever a question is silent about a condition or exclusion, I asserted
  no fact for it at all (rather than an explicit "safe" dummy fact) and let
  `policy.pl`'s own defaults do the work: an exclusion with no cause/age
  fact backing it never fires, and Section 1.3 never fails without a
  confirmation-month or hospitalization-month fact establishing a problem.
  This directly implements the standing instruction ("assuming all other
  conditions are met and no other exclusions apply ... anything not
  referenced in the query").

## Judgment calls

1. **Section 1.3's two nested deadlines, collapsed to one tracked value.**
   Section 1.3 actually states two deadlines: the wellness *visit* itself
   must occur by the 6-month anniversary, and *written confirmation* of it
   must be *supplied* to the Company by the 7-month anniversary. Every
   question that mentions this ("confirmation ... given", "proof ...
   provided/submitted") describes only the supply/provision event, never
   the underlying visit date. I modeled both deadlines faithfully in
   `policy.pl` (`confirmation_supplied_month/2` vs. `wellness_visit_month/2`,
   checked against 7 and 6 respectively), but since no question ever gives
   a separate visit date, `wellness_visit_month/2` is never asserted in
   `queries.pl` and that middle clause of `section_1_3_failed/1` is
   currently dead code for these nine questions — it exists for
   faithfulness to the text, not because any question exercises it. In
   practice this means the 7-month confirmation deadline is what actually
   drives every answer that touches Section 1.3.
2. **A hospitalization before month 7 with no confirmation fact yet is
   "pending," not "failed" — but a claim that gives no hospitalization
   month at all and reports a late confirmation is modeled as failed
   outright** (see `section_1_3_failed/1`, clause 1, which does not
   condition on `hospitalization_month/2`). This matters for the fall/
   travel question, which gives a confirmation month (8, past the 7-month
   deadline) but no hospitalization month. I treated the late confirmation
   as dispositive on its own rather than assuming an early, unstated
   hospitalization date that would let the "still pending at the time"
   carve-out rescue the claim. I judged this the more natural reading of a
   claimant who is narrating that their confirmation was already 8 months
   late, but a reader who assumes the hospitalization definitely preceded
   month 7 would model it differently.
3. **The Section 2.1 occupation exclusions (skydiving/military/firefighter/
   police) are keyed to the *cause* of the hospitalization, not to the
   claimant's job or activity in general.** The clause excludes sickness or
   injury "arising directly or indirectly out of" the five listed things,
   which I read as a causation requirement. This matters for the question
   about a claimant who was serving as a police officer at the time of
   hospitalization but was hospitalized because their own son bit their
   ankle: I did not treat "currently a police officer" as itself
   triggering the police-service exclusion, because the stated cause of
   the injury has no connection to police duty. `hospitalization_cause` for
   that claim is asserted as `family_incident`, not `police_service`. The
   firefighter question, by contrast, explicitly says the burns were
   suffered "while doing my duty as a firefighter," which is a causal claim
   about the injury itself, not just a fact about the claimant's job, so I
   did key that one to `firefighter_service`.
4. **"Accidental injury" is read broadly enough to cover a voluntary act
   with an unintended, injurious result.** The question about a claimant
   hospitalized for punching their own face to show off for friends is not
   covered by any of the five named Section 2.1 exclusions, and the
   contract text I was given does not separately define "accidental
   injury" or carve out intentional/self-inflicted acts anywhere. I
   modeled the resulting hospitalization as an ordinary
   `hospitalization_event`, i.e. as within the "sickness or accidental
   injury" gate in Section 1.1, on the reasoning that the *harm* (a
   hospitalization-worthy injury) was not the thing intended, even though
   the underlying act (the punch) was voluntary. A stricter reading — that
   a self-inflicted, voluntary blow is never "accidental" regardless of
   whether the resulting harm was foreseen — is available from the same
   text and would flip this claim to excluded/not covered. I flagged this
   because the contract as given to me simply does not define the
   boundary, and nothing else in the document resolves it either way.
5. **Fraud, misrepresentation, and material withholding of information
   are modeled as three independent facts** (`fraud/1`, `misrepresentation/1`,
   `material_withholding/1`) rather than one bundled predicate, since
   Section 1.2 lists them disjunctively and a fully general encoding should
   let a caller assert any one of them independently. No question in this
   set needed more than "assert none of them," so this only affects how
   the file would generalize beyond these nine questions, not any of the
   nine answers themselves.
