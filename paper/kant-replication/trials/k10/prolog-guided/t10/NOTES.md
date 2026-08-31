# Notes

## Load check

Ran `swipl -q -g halt policy.pl queries.pl` from the trial directory. Output was
completely silent, exit code 0. No syntax errors, no singleton-variable warnings, no
discontiguous-clause warnings (the latter suppressed by explicit `:- discontiguous`
directives at the top of `queries.pl`, since each `claim_*/2` predicate's nine clauses
are deliberately split one-per-question-block rather than grouped together).

Per the rules, I did **not** call q1..q9 or otherwise evaluate the encoding against the
questions.

## Judgment calls in `policy.pl`

1. **Section 1.3 has two independent deadlines, not one.** "No later than the 7th month
   anniversary ... you will supply ... written confirmation ... of a wellness visit ...
   occurring no later than the 6th month anniversary" is read as: the visit itself must
   occur by month 6, and the written confirmation of it must be supplied by month 7,
   checked separately. (Q6's "6.5 months" scenario is exactly the case this distinction
   matters for: it is past the visit's month-6 mark but within the confirmation's
   month-7 deadline.)

2. **"Still pending" (1.1(3)) is a time-relative escape, not a permanent one.** A
   hospitalization occurring before month 7 cannot yet be penalized for
   non-satisfaction of Section 1.3, because the deadline hasn't arrived. A
   hospitalization at or after month 7 requires the condition to have actually been
   satisfied by then. Encoded as `section_1_3_pending(C) :- claim_hospitalization_month(C,
   H), H < 7.` — strict `<`, treating month 7 itself as "the deadline has arrived."

3. **Fraud and misrepresentation (1.2) void the policy unconditionally**, i.e. without
   checking whether the fraud/misrepresentation month falls before or after the
   hospitalization month. The clause reads as an absolute bar ("Cancelation will be
   deemed to have occurred if there is fraud..."), and a fraudulent claim is naturally
   discovered only after the triggering event, so gating on temporal order seemed wrong.

4. **Premium payment must occur no later than the hospitalization it is meant to
   cover** (`claim_premium_paid_month =< claim_hospitalization_month`). The contract
   gives no explicit numeric deadline for premium payment (3.5.1 just says "at the
   signing"), so I anchored "has been paid" (1.1(2)) to the time the policy's effectivity
   is being tested, i.e. the hospitalization.

5. **Policy term end (3.6) is inclusive**: `claim_hospitalization_month =<
   claim_policy_term_months` counts as within the term, consistent with the `=<`
   convention already used by the given `no_later_than/2`.

6. **60 days (3.2.1) is read as 2 months**, since every claim fact in the schema is
   month-granular (including fractional months, e.g. Q6's 6.5) and no day-level fact
   exists to compare against. `R >= P + 2` where P = written proof of claim month, R =
   recovery sought month.

7. **Arbitration/dispute condition precedent**: modeled as a no-op when
   `claim_dispute_arisen = false`. When true, coverage requires (a) the arbitration right
   not to have been extinguished — either the parties haven't yet reached an "unable to
   settle" impasse, or arbitration was commenced within 3 months of that impasse — and
   (b) a valid arbitration award to have issued (the condition precedent to liability).
   None of the nine questions exercise this branch (all set `dispute_arisen = false`),
   so this is a best-effort faithful reading rather than something the queries stress.

8. **Age exclusion** uses `Age >= 80` per "equal to or greater than 80 years of age."

9. **Hospitalization ground**: only `sickness` or `accidental_injury` satisfy Section
   1.1's "hospitalization for sickness or accidental injury"; `neither` does not.

## Judgment calls in `queries.pl`

- **Default filler values**, used whenever a question doesn't speak to a fact: hospitalization
  month = 3 (matching the worked example in TASK.md itself), age = 40, wellness visit
  month = a value comfortably `=< 6`, provider qualified = true, written confirmation
  month comfortably `=< 7`, no fraud/misrepresentation, no dispute/arbitration activity,
  proof-of-claim and recovery-sought both `none` (i.e. the 60-day clock is not yet
  running), policy term = 12 months, premium paid at month 0 (signing).

- **Q4** (fall abroad; wellness confirmation given at month 8): the question never states
  a hospitalization month. I set it to 8 rather than the usual default of 3, because at
  month 3 my own `section_1_3_pending` clause (`H < 7`) would swallow the late
  confirmation entirely and the one fact the question actually turns on would never be
  exercised. I treated the confirmation month as *not* "unrelated to the question" in
  the sense TASK.md means, even though the hospitalization month itself is literally
  unstated, and picked a value that lets the stated fact operate.

- **Q5** (punching own face to show off, no fraud/misrepresentation): read as
  `claim_hospitalization_ground(c5, neither)` — a deliberate, self-inflicted stunt is
  neither a sickness nor an accidental injury. The explicit disclaiming of fraud and
  misrepresentation reads as ruling out one path to non-coverage so as to isolate this
  one, rather than being itself the operative fact.

- **Q9** (son bit claimant's ankle; claimant "was serving as a police officer at the
  time"): `claim_causes(c9, [other])`, deliberately **not** including `police_service`.
  The given `arose_out_of/2` tests whether the event arose out of a cause; merely holding
  the job of police officer at the time of an unrelated domestic dog/child-bite incident
  does not mean the injury arose out of police service (contrast Q1's firefighter, which
  explicitly says the burns arose "while doing my duty as a firefighter" — an actual
  causal nexus). This is the one call in this file I'd flag as most contestable.

- Causes not among the four excluded activities are written as `[other]` when the
  question describes some specific (non-excluded) originating event (pneumonia, a fall,
  a heart attack, a bite, punching one's own face), and as `[]` only for Q2, which gives
  no causal information at all.
