# Notes

## Load check

Ran `swipl -q -g halt policy.pl queries.pl` from the trial root.

First attempt produced 840 `discontiguous` warnings (no errors, exit code 0) because each
`claim_*/2` predicate is defined once per query block in `queries.pl`, so its clauses are
scattered through the file rather than grouped together. Added a block of
`:- discontiguous claim_*/2.` declarations (one per claim fact, 21 total) at the top of
`queries.pl` to suppress these. Re-ran; output was completely silent with exit code 0. I did
not run `q1` through `q9`, and did not otherwise evaluate the encoding against the questions.

## Judgment calls in `policy.pl`

- **"Still pending or has been satisfied in a timely fashion" (S1.3, S1.1(3)).** Read as a
  disjunction anchored on the hospitalization month: if hospitalization occurs before month 7
  (the confirmation deadline), the condition cannot yet have been breached, so it is
  automatically fine regardless of the confirmation/visit facts. If hospitalization occurs at
  month 7 or later, the full condition (confirmation &le; 7, visit &le; 6, qualified provider)
  must actually hold. I put the boundary at `HospitalizationMonth < 7` (strict), so a
  hospitalization at exactly month 7 requires the condition to already be satisfied rather than
  treating it as still pending. This exact boundary is not exercised by any of the nine
  questions with an hospitalization month of exactly 7, but it is a genuine reading choice — the
  contract text does not say which side of the deadline "the 7th month anniversary" itself falls
  on.

- **Fraud / misrepresentation timing (S1.2).** The schema gives a month for each (or `none`),
  not a plain boolean, so I treated cancellation as taking effect from that month onward rather
  than voiding the policy retroactively: a hospitalization strictly before the fraud/
  misrepresentation month is unaffected; one at or after it is not covered. Implemented as
  `\+ no_later_than(FraudMonth, HospitalizationMonth)`, which also handles `none` for free via
  the supplied predicate's own base case.

- **Premium timing (S1.1(2)).** "The applicable premium ... has been paid" is checked as
  `no_later_than(PremiumPaidMonth, HospitalizationMonth)` — i.e., paid by the time of the
  hospitalization — rather than merely "paid at some point (past or future)". The contract does
  not give premium payment its own deadline other than "at signing" (S4.5.1), so I anchored it to
  the hospitalization instead, consistent with S1.1's framing that everything is evaluated "at
  the time of the hospitalization."

- **365-day confinement cap (S2.2).** Read as a payment-amount cap ("payable ... for a period
  not exceeding 365 days"), not an eligibility cutoff. `covered/1` only requires
  `claim_continuous_confinement_days` to be a positive number (i.e., some continuous confinement
  actually occurred); it does not reject a claim for having more than 365 days of confinement,
  since even in that case a benefit would still be payable for the first 365.

- **60-day recovery waiting period (S4.2.1).** The clause is stated in days ("sixty (60) days
  after written proof of claim"), but the schema's only relevant facts are month-granular
  (`claim_written_proof_of_claim_month`, `claim_recovery_sought_month`). I approximated 60 days
  as two 30-day months and required `RecoverySoughtMonth >= ProofOfClaimMonth + 2`. This check is
  skipped entirely (vacuously true) when `claim_recovery_sought_month` is `none`, i.e., when
  recovery is not part of the scenario being described.

- **Arbitration as a dispute-conditional gate (S4.2.1).** The three-month arbitration-commencement
  deadline and the "valid arbitration award as condition precedent" clause are both read as
  applying only when `claim_dispute_arisen(C, true)`; when no dispute has arisen they don't
  constrain `covered/1` at all. When a dispute has arisen but `claim_unable_to_settle_month` is
  `none`, arbitration timeliness can't be established, so that branch fails closed (not covered).

- **`hospitalization_ground = neither`.** Treated as never covered, since S2.1 only pays a
  benefit for hospitalization resulting from sickness or accidental injury.

- **Exclusion causes vs. incidental status (S3.1).** `no_exclusion_applies/1` checks
  `claim_causes` (what the event arose out of) via `arose_out_of/2`, not any separate notion of
  the claimant's occupation or status at the time. This matters for one of the nine queries,
  where the claimant's injury is clearly domestic in origin but the question separately mentions
  an occupation that appears in the exclusion list; see the `queries.pl` note below for how I
  resolved that in the fact-setting (a `policy.pl` modeling choice, since it's `arose_out_of` that
  decides materiality, not mere contemporaneous status).

## Judgment calls in `queries.pl`

- **Mapping "proof/confirmation of my wellness visit was provided/submitted/given at month X" to
  `claim_written_confirmation_month`, not `claim_wellness_visit_month`.** Four of the nine
  questions describe a wellness-visit confirmation/proof being provided or submitted at a
  specific month. I read "provided/submitted/given" as the act of supplying written confirmation
  to the company (S1.3's "you will supply us with written confirmation"), which is
  `claim_written_confirmation_month`, and left the underlying `claim_wellness_visit_month` (the
  visit itself) at a satisfying baseline value (well within the 6-month sub-deadline), since none
  of the nine questions describe when the underlying visit occurred, only when it was confirmed.

- **Choice of hospitalization month where the confirmation month given is 8 (past the 7-month
  deadline).** For the one question giving a confirmation month of 8, I set the hospitalization
  month to 8 as well (rather than an unstated month before 7), because setting it earlier would
  make the S1.3 condition "still pending" regardless of the confirmation's lateness and would
  mean the query never actually exercises the fact the question is built around. Setting it to a
  month at or after the stated confirmation month was the only way to make that fact
  operative, and I did not choose it to steer the outcome either way — I have not run `q1`–`q9`
  and don't know what `covered/1` returns for this claim.

- **Occupation mentioned only as a contemporaneous status, not a cause, of the hospitalization
  event.** One question describes an injury from a clearly domestic cause (a family member's
  bite) and separately states the claimant's occupation at the time of hospitalization, where
  that occupation happens to appear in the S3.1 exclusion list. Since `arose_out_of/2` (per the
  supplied predicate and S3.1's own "arising directly or indirectly out of") asks what the injury
  arose out of, not who the claimant is or what they do, I set `claim_causes` to `[other]` for
  that claim rather than including the occupation-linked atom, on the reading that an unrelated
  domestic injury does not arise out of the claimant's job merely because they held it at the
  time. A different, more literal encoder could reasonably fold the stated occupation into
  `claim_causes` instead; I flag this because it is the one fact-setting choice in `queries.pl`
  that turns on interpreting the question rather than transcribing it.

- **Baseline values for facts not mentioned by a question.** Per the task's standing instruction,
  every fact not referenced by a question is set to a value that satisfies coverage and triggers
  no exclusion under my own `covered/1`: agreement signed, premium paid at month 0, hospitalization
  within a 12-month policy term, no fraud/misrepresentation, wellness visit and confirmation early
  and by a qualified provider, no dispute (making arbitration and the award requirement vacuous),
  no recovery yet sought (making the 60-day wait vacuous), confinement in a US hospital for 5
  continuous days, and the claim made setting out its basis. Where a question gives an explicit
  value for one of these (e.g., a specific hospitalization month, age, or cause), that value is
  used instead of the baseline.
