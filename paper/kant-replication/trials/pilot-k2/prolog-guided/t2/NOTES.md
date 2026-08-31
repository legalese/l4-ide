# Notes on this encoding

## Load check

Ran, from the trial directory root:

```
swipl -q -g halt policy.pl queries.pl
```

Output was empty and the exit code was 0 — silent, as required. I did not run `q1`..`q9` or
otherwise query `covered/1` against any of the nine claims.

One thing the silence depended on: `queries.pl` groups facts by claim (per the `TASK.md`
example), so each of the 18 `claim_*` predicates has its 9 clauses scattered non-contiguously
through the file. Left alone, SWI-Prolog's consult warns "Clauses ... are not together" for
every one of them. I added a `:- discontiguous claim_X/2.` declaration for each of the 18
predicates at the top of `queries.pl` to suppress that, rather than reordering the facts to
group by predicate (which would have broken the one-claim-at-a-time readability the example
shows) or blanket-disabling the warning class.

## Judgement calls in `policy.pl`

- **Premium payment (§1.1.2).** Modeled as "a number was recorded" (`claim_premium_paid_month`
  is not `none`), with no deadline relative to hospitalization. Unlike the wellness-visit/
  confirmation condition in §1.3, which states explicit numeric deadlines (6th/7th month
  anniversary), §1.1.2 and §3.5.1 only say the premium is paid, in one lump sum, at signing —
  there is no stated numeric threshold to compare `claim_premium_paid_month` against, so I did
  not invent one.

- **"Still pending" (§1.1.3, read against §1.3 and the cancelation trigger in §1.2).** This is
  the least textually determinate part of the policy. I modeled §1.3 as satisfied-or-pending:
  - *Satisfied*: a wellness visit at a qualified provider no later than month 6, **and** written
    confirmation supplied no later than month 7 (`section_1_3_satisfied/1`).
  - *Pending*: no written confirmation has been supplied yet (`claim_written_confirmation_month`
    is `none`) **and** the hospitalization occurs at or before month 7 — i.e. the deadline by
    which §1.3 must be resolved hasn't passed yet (`section_1_3_pending/1`).

  I deliberately did *not* make "pending" a function of hospitalization month alone (i.e. "early
  hospitalization ⇒ pending regardless of the confirmation fact"), because that would make the
  confirmation-month fact irrelevant whenever a query is silent about hospitalization month —
  which is the case for 8 of the 9 questions here, including the one (a confirmation given at
  month 8, past the month-7 deadline) that most plausibly exists to test exactly this clause.
  Tying "pending" to "no confirmation supplied yet" instead means a concretely-late confirmation
  always fails the condition, regardless of what hospitalization month I default in.

- **Fraud / misrepresentation (§1.2).** Treated as an unconditional bar — any recorded month
  (as opposed to `none`) cancels the policy — again because the text gives no relative-timing
  qualifier for these the way §1.3 does. "Misrepresentation or material withholding of
  information" is collapsed into the single `claim_misrepresentation_month` fact, per the
  schema's own vocabulary (there is no separate "withholding" fact to encode).

- **Policy term (§1.2, §3.6).** Modeled as `claim_hospitalization_month =< claim_policy_term_months`
  (inclusive), reading "canceled at midnight on the *last day* of the term" as meaning the term
  covers that whole last day.

- **Age exclusion (§2.1.5).** Encoded literally as `Age >= 80` ("equal to or greater than 80").

- **Arbitration and the proof-of-claim waiting period (§3.2.1).** `claim_dispute_arisen(C,
  false)` short-circuits the whole clause. When a dispute has arisen, I require arbitration
  commenced within 3 months of the unable-to-settle date **and** a valid arbitration award, per
  the text's two stated preconditions to liability. Separately, "no case shall you seek to
  recover... before the expiration of sixty (60) days after written proof of claim" is modeled
  as `claim_recovery_sought_month >= claim_written_proof_of_claim_month + 2` — approximating 60
  days as 2 months, since the schema's only time unit is (fractional) months. This whole
  predicate is vacuously true whenever the corresponding month facts are `none`, which is the
  case for all nine questions here.

## Judgement calls in `queries.pl`

- Facts a question doesn't mention were set to a coverage-favoring baseline: agreement signed;
  premium paid and hospitalized at month 1; age 40; a wellness visit at month 1 with a qualified
  provider but **no** written confirmation yet supplied (so §1.3 reads as "still pending" under
  the model above, absent a stated confirmation fact); no fraud, misrepresentation, or dispute;
  a 12-month policy term (the contract's own stated one-year term, §3.6).

- **Hospitalization ground**, when the question doesn't name a specific cause (Q2), was set to
  `sickness` arbitrarily — the choice doesn't affect coverage either way, it only needs to be
  something other than `neither`.

- **Q4** (fall while traveling abroad; confirmation given at month 8) doesn't state a
  hospitalization month. I defaulted it to 1. Under the model above this default is immaterial
  to Q4's outcome either way, because a concrete (non-`none`) confirmation month routes
  evaluation through the "satisfied in a timely fashion" test (`8 =< 7`), not the "pending" test
  — so no choice of default hospitalization month changes the result for this claim. "Traveling
  abroad" was not encoded as any restriction, since §3.1.1 affirmatively covers the policyholder
  worldwide and the schema has no location fact.

- **Q9** ("I was serving as a police officer at the time of hospitalization," cause: son biting
  claimant's ankle): I did **not** add `police_service` to `claim_causes`. The general
  exclusions in §2.1 exclude events "arising directly or indirectly out of" police service, etc.
  — a causal test, not an occupation test. The stated cause of this hospitalization (the bite)
  has no connection to police duty, so `claim_causes(c9, [other])`, treating the mention of the
  claimant's job as a distractor with no corresponding claim fact.

- **Q6** (skydiving injury; age 79; confirmation at month 6.5) and **Q8** (military training
  injury; fraud explicitly denied) each have a directly-named excluded cause
  (`skydiving`/`military_service`). The other numbers given in those questions (age 79 vs. the
  80 threshold; confirmation at 6.5 vs. the 7-month deadline; "no fraud") are near-misses or
  denials that don't independently affect coverage — I encoded them as stated regardless, since
  the exclusion fires on `claim_causes` independently of them.
