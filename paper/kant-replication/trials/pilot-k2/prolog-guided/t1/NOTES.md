# Notes — prolog-guided/t1

## Load check

Ran `swipl -q -g halt policy.pl queries.pl` from the trial directory. Exit code 0,
no output at all (no warnings, no errors) — silent, as required. I did not run
`q1`..`q9` or otherwise query `covered/1` against the nine claims.

`queries.pl` opens with eighteen `:- discontiguous claim_*/2.` directives. Without
them, grouping the facts by claim (one block per question, matching the TASK.md
worked example) would spread each `claim_*/2` predicate's clauses across all nine
blocks, which SWI-Prolog's style checker flags by default; the directives make that
deliberate and keep the load silent.

## Judgement calls

- **Section 1.3, "still pending or has been satisfied in a timely fashion"
  (§1.1(3)).** The only time-anchor Section 1.1 gives is "at the time of the
  hospitalization," and the schema has no separate "current month" fact, so I
  read this as: as of the hospitalization month, has the compliance deadline (the
  7-month anniversary for supplying written confirmation) already passed? If not
  (`hospitalization_month < 7`), the condition is still pending and cannot yet
  have failed, regardless of the wellness-visit/confirmation facts. If it has
  passed, both the wellness-visit deadline (month 6, qualified provider) and the
  confirmation deadline (month 7) must actually have been met. This is what makes
  Q3 (hospitalized at month 5, no wellness-visit facts given) resolve without
  needing those facts, and what makes Q4's late confirmation (month 8) matter only
  because I placed the hospitalization after it.

- **`claim_premium_paid_month`.** The policy gives no deadline for premium payment
  other than "at signing" (§3.5.1) — unlike the wellness-visit/confirmation
  facts, there's no second month to compare it against. I treated it as satisfied
  whenever it is a number at all (not `none`), and used `0` uniformly (paid at
  signing/on time, per the standing preamble that applies to every question).

- **Fraud / misrepresentation (§1.2).** The text says cancelation "will be deemed
  to have occurred if there is fraud, or any misrepresentation..." with no
  qualification about when relative to the hospitalization. I treated either one,
  at any month, as canceling the policy outright — I did not require it to precede
  or follow the hospitalization to count.

- **§2.1 item 5 (age ≥ 80) is a free-standing exclusion**, not a fifth "arising
  out of" cause — grammatically it doesn't fit "arising directly or indirectly out
  of ... [age]", so I encoded it as `not_age_excluded/1`, checked independently of
  `claim_causes`/`arose_out_of`.

- **Occupation vs. causation (Q9).** "Serving as a police officer at the time of
  hospitalization" is a status, not itself a listed cause; §2.1 excludes injury
  "arising directly or indirectly out of ... service in the police," and nothing
  in Q9 ties the son's bite to that service. I set `claim_causes(c9, [other])`,
  not `[police_service]`, on the reading that mere contemporaneous occupation
  doesn't satisfy "arising out of."

- **Q4's hospitalization month is unstated** — the question gives only "I had
  given confirmation of my wellness visit 8 months after the policy's effective
  date." I read the past perfect ("had given") as placing that confirmation
  before the hospitalization, and picked `9` for `claim_hospitalization_month`
  specifically so the late confirmation is not shielded by the "still pending"
  branch above (an early default, like the `3` used elsewhere, would make the
  stated fact inert regardless of how §1.3 is read, which seemed like the wrong
  way to resolve an unstated fact here).

- **"Proof of the wellness visit was provided/submitted" (Q6, Q7, Q9)** — mapped
  to `claim_written_confirmation_month` (the confirmation supplied to the
  insurer under §1.3), not `claim_wellness_visit_month` (the underlying medical
  visit). The underlying visit's own month is left at the same unrelated/default
  value (`5`, qualified `true`) used everywhere else it isn't mentioned.

- **The 60-day recovery-waiting rule (§3.2.1, "In no case shall You seek to
  recover...")** is written as a standalone sentence, not confined to the
  preceding dispute/arbitration clause, so `recovery_timing_ok/1` applies it to
  every claim regardless of `claim_dispute_arisen`. Sixty days is approximated as
  2 months, matching the whole-month granularity used by every other date fact
  in the schema. None of the nine questions mention proof-of-claim or recovery
  timing, so every claim uses the same compliant background values
  (`written_proof_of_claim_month = 0`, `recovery_sought_month = 6`).

- **Defaults for facts a question doesn't mention** follow the standing preamble
  ("no other exclusions apply"): `claim_causes` defaults to `[other]` when the
  hospitalization isn't tied to any of the four excluded activities,
  `claim_hospitalization_month` defaults to `3` (as in the TASK.md worked
  example) except where a question's own facts require otherwise (Q3, Q4, as
  above), unstated ages default to `40`, and the arbitration/dispute facts are
  uniformly "no dispute" across all nine claims since none of the questions raise
  one.
