# Notes on this encoding

## Load check

Ran `swipl -q -g halt policy.pl queries.pl` (consult-only; did not call `q1`..`q9` or
otherwise query the encoding, per the task rules).

- **First attempt**: loaded successfully (exit code 0) but printed 17 `discontiguous-clauses`
  warnings to stderr. Cause: `queries.pl` groups facts by claim/question (`claim_1`'s facts
  together, then `claim_2`'s, etc.) rather than by predicate, so a predicate like
  `hospitalized_due_to/2` has its clauses spread across the file, interleaved with clauses of
  other predicates. I had assumed declaring these predicates `dynamic` in `policy.pl` would
  suppress this warning in `queries.pl` too, since dynamic predicates are normally allowed to
  gain clauses at arbitrary points; that assumption was wrong for facts loaded from a
  *different* file — `dynamic` and `discontiguous` are evidently tracked separately by the
  loader.
- **Fix**: added explicit `:- discontiguous hospitalized_due_to/2.` (and the same for
  `age_at_hospitalization/2`, `injury_caused_by/2`, `wellness_confirmation_month/2`) at the top
  of `queries.pl`, since those are the four predicates that recur across non-adjacent
  `claim_N` blocks. `hospitalization_month/2`, `confined_outside_us/1` and
  `intentional_self_harm/1` each occur for only one claim, so they never triggered the warning.
- **Second attempt**: completely silent, exit code 0. This is the version committed.

## Judgement calls

1. **Section 1.3's two deadlines collapsed to one.** Section 1.3 literally bundles two dates:
   the wellness visit itself must occur no later than the 6-month anniversary, and written
   confirmation of it must be supplied no later than the 7-month anniversary. Every question in
   `queries-blind.md` that touches this condition gives only a single relative time, phrased as
   when confirmation/proof of the visit was "provided" or "submitted" (Q4: 8 months, Q6: 6.5
   months, Q7: 2 months, Q9: 6 months) — none separately state when the underlying visit
   happened. I therefore encoded `wellness_condition_breached/1` against the single, outer
   7-month deadline (the one Section 1.2 itself cross-references as the cancelation trigger),
   treating "confirmation provided at month T" as the operative fact. This only has bite for Q6
   (6.5 months: after the unstated 6-month visit deadline, but before the 7-month confirmation
   deadline) — under my reading this does not breach the condition, though Q6's answer is
   unaffected either way because the skydiving exclusion independently controls it.

2. **"Accidental Injury" excludes deliberate self-harm (Q5).** Section 2.1 conditions the
   benefit on hospitalization due to "sickness or accidental Injury". Section 3 lists five
   specific exclusions, none of which mention self-inflicted or intentional injury. Q5 describes
   punching one's own face "to show off for my friends" and explicitly disclaims fraud or
   misrepresentation. I read the fraud disclaimer as forestalling the wrong objection (Section
   1.2's fraud-based cancelation ground) so that the real issue is whether a deliberately
   self-inflicted injury is "accidental" at all — I judged that it is not, in the ordinary sense
   of the word, regardless of the absence of a named exclusion for it, and encoded
   `intentional_self_harm/1` as negating `covered_cause/1` on the injury branch. The contrary
   reading (self-inflicted-but-unintended-harm still counts as "accidental result", so Q5 should
   be covered absent an explicit exclusion) is available and is noted here in case the intended
   key takes it.

3. **Section 3 exclusions require a causal link, not mere status (Q1 vs. Q9).** Section 3.1
   excludes injury/sickness "arising directly or indirectly out of" skydiving, military service,
   firefighter service, or police service. Q1 (burns "suffered while doing my duty as a
   firefighter") states a direct causal link, so I encoded `injury_caused_by(claim_1,
   firefighter_service)` and the exclusion fires. Q9 (bitten by the claimant's own son, with the
   claimant separately noted as "serving as a police officer at the time of hospitalization")
   gives status only — the bite has no stated connection to police duties — so I did *not*
   assert `injury_caused_by(claim_9, police_service)`, and the exclusion does not fire. This
   contrast is deliberate and is the main structural reason `general_exclusion/1` is keyed on a
   causal fact (`injury_caused_by/2`) rather than a status fact.

4. **Section 2.2 ("hospital in the United States") vs. Section 4.1.1 ("anywhere in the
   world") — Q4.** These two clauses are in tension: 2.2 says the Daily Hospital Income Benefit
   is "only... payable for... confinement in a hospital in the United States"; 4.1.1 says the
   policy "insures You twenty-four (24) hours a day anywhere in the world." I resolved this by
   reading 4.1.1 as fixing the territorial scope of the insured peril (the sickness/accidental
   injury can happen anywhere) while 2.2 separately requires the resulting hospital confinement
   itself to be in a US hospital before the daily benefit is paid — the two clauses then govern
   different things and neither is read out of the policy. Q4 ("hospitalized due to a fall while
   traveling abroad") is encoded as `confined_outside_us(claim_4)` under this reading, and so is
   barred under Section 2.2 (`benefit_location_barred/1`). This is a genuine judgement call — a
   reading giving 4.1.1 full control over location, full stop, is equally available — but it is
   moot for Q4's answer either way, since Q4's confirmation is independently given as supplied
   at month 8, after the 7-month deadline, which alone already cancels the policy under Sections
   1.2/1.3.

5. **Signing, premium payment, and claim-filing (Sections 1.1(1)-(2), 2.3) not modeled.** Per
   the task brief, signing and timely premium payment are assumed and were not given
   predicates. Section 2.3's requirement that "a claim must be made to the Company" is treated
   as implicit in each question's own framing ("I was hospitalized... will my policy apply") and
   likewise was not given a separate togglable fact, since no question turns on whether a claim
   was filed.

6. **Arbitration and the 60-day waiting period (Section 4.2) not modeled.** These govern the
   mechanics and timing of *recovering on* the policy once there is "a dispute or disagreement",
   not whether the risk itself is covered. None of the nine questions posit a dispute with the
   insurer, so this section is out of scope for a "will my policy apply" determination and was
   left unencoded (no predicate references it).

7. **Policy term (12 months) modeled for completeness, untested by any of the nine
   questions.** `policy_term_expired/1` fires only when `hospitalization_month/2` exceeds 12;
   no question's hospitalization time approaches that, so this clause is inert against the
   current query set but is included for faithfulness to Section 4.6 (cross-referenced by 1.2).

## Design pattern used throughout

Every predicate that queries.pl can assert is a *triggering* fact for an outcome unfavourable
to the claim (an exclusion, a cancelation ground, a bar on the benefit). An unasserted fact
therefore always defaults to the reading favourable to coverage, which lines up directly with
the task brief's instruction, for each question, to set facts so that every condition/exclusion
*not* the subject of that question is satisfied / not triggered — each `queries.pl` block only
needs to assert what the question's own wording actually states. The one exception is
`hospitalized_due_to/2`, which is required positively for every claim since every question
presupposes some hospitalizing medical cause and there is no sensible favourable default for it.
