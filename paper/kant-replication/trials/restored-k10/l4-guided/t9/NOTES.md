# Notes on this encoding

## Check performed

Ran (typecheck only, no evaluation, per the task rules):

```
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check policy.l4
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/kant-chubb/jl4-core/libraries l4 check apply.l4
```

Both printed `Check succeeded.` I did not run `l4 run`, `#EVAL`, or otherwise evaluate any of the
nine claims against `covered`.

## Judgment calls

1. **"Still pending" (§1.1 condition 3) collapsed into "satisfied."** §1.1 lists a policy as in
   effect if "the condition set out in Section 1.3 is still pending or has been satisfied in a
   timely fashion." A literal reading wants a third, time-relative state ("not yet due") distinct
   from "done" / "failed." But the only clock available in the `Claim` schema is
   `hospitalization month`, which is not obviously the right reference point (the 6/7-month
   deadlines run from the policy's effective date, independent of when a hospitalization happens
   to occur), and treating it as the reference point creates a perverse interaction with the
   instruction to set fields "unrelated to the question" so that conditions are satisfied: an
   early `hospitalization month` chosen for unrelated reasons would silently rescue a genuinely
   late confirmation. The schema's own `no later than` helper resolves an absent event to `FALSE`
   outright, not to a third "pending" value, which reads as the intended treatment. I therefore
   encode §1.3 compliance as a straight compound deadline check (`condition 1.3 satisfied`) and do
   not add a separate "pending" branch. I kept condition (3) as its own conjunct in
   `policy in effect at hospitalization` anyway (duplicating part of `policy not canceled`),
   because the source text states the requirement twice and isomorphic encoding should preserve
   that rather than silently dedupe it — the duplication is logically inert (AND of the same
   truth with itself), so this is safe either way.

2. **Fraud / misrepresentation treated as simple "did it ever happen" checks**, not compared
   against `hospitalization month`. §1.1's "at the time of the hospitalization" framing could
   support a timing-relative reading (fraud committed *after* a hospitalization shouldn't
   retroactively un-cover it), but none of the nine questions test that nuance — they only ever
   assert "no fraud/misrepresentation" outright — so I chose the simpler reading for consistency
   with judgment call 1, rather than adding an interpretive mechanism nothing here exercises.

3. **§2.2's "hospital in the United States" is a hard, independent requirement for the daily
   benefit**, distinct from §4.1's "Your Policy insures You ... anywhere in the world." I read
   §4.1 as describing where the insured *risk* is covered, and §2.2 as separately conditioning the
   *daily hospital income benefit* specifically on US-hospital confinement. This is a genuine
   tension in the source text (Q4's hospitalization "while traveling abroad" sits squarely in the
   gap between the two clauses); I flag it rather than silently resolve it away, and encode
   `confined in us hospital` as required.

4. **"Arising directly or indirectly out of [profession]" requires a genuine causal link, not mere
   temporal coincidence with being on duty.** This is the most consequential call, made when
   constructing Q9's claim rather than in `covered` itself. Q9 describes the claimant "hospitalized
   due to my son biting me in the ankle ... while serving as a police officer." A domestic bite
   from one's own child has no plausible causal connection to police work — unlike Q1 (burns while
   fighting fires), Q6 (injury while skydiving), or Q8 (injury in a military training exercise),
   each of which has an obvious direct causal link between the named activity and the injury
   mechanism. I therefore set Q9's `causes` to `LIST Other`, not `LIST \`Police service\``, so the
   §3.1 exclusion does not fire on mere contemporaneity. `covered` itself is agnostic to this
   choice — it just checks list membership via the supplied `arose out of` helper — so a reviewer
   who disagrees with this reading can flip that one field in `apply.l4` without touching
   `policy.l4`.

5. **"Confirmation/proof of my wellness visit was provided/submitted/given X months after the
   effective date"** (Q4, Q6, Q7, Q9) is mapped to `written confirmation month` — the act of
   supplying written confirmation to the insurer — not `wellness visit month`, which is the date
   of the underlying medical visit itself and which no question ever states. `wellness visit
   month` is defaulted (month 2, well inside the 6-month deadline) in every claim.

6. **§4.2's "sixty (60) days"** is translated to 2 months (60 / 30) when comparing
   `written proof of claim month` against `recovery sought month`, since those two fields are
   expressed in the same fractional-month units used elsewhere in the schema (e.g. Q6's "6.5
   months").

7. **Arbitration/dispute fields** (`dispute arisen`, `unable to settle month`,
   `arbitration commenced month`, `valid arbitration award issued`, `written proof of claim
   month`, `recovery sought month`) are not mentioned by any of the nine questions. Every claim
   sets `dispute arisen` to `FALSE` and the remaining fields to values consistent with "no dispute
   ever arose," which trivially satisfies §4.2 regardless of how its sub-clauses are read.

8. **Unstated `hospitalization month`, `age at hospitalization`, `hospitalization ground`, and
   `causes`** (wherever a question doesn't speak to them) are set to values that plainly satisfy
   coverage and trigger no exclusion (e.g. age 40, ground `Sickness` or `\`Accidental injury\`` as
   fits the stated mechanism of injury, `causes` = `LIST Other`), per the task's instruction to
   set unrelated fields so "all conditions for coverage are satisfied and no exclusions are
   triggered."
