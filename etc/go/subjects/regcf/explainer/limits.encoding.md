This is the boundary of the claim. Everything below is something the encoding
does not do, listed because a reader who discovers it later is entitled to think
the rest was oversold.

**Scope.** This is not a formalisation of the whole of 17 CFR Part 227. It
mirrors one external summary of the regulation, which presents it as eight
requirement groups, and encodes those eight to the depth that summary reaches.
Left out: the funding-portal registration regime in Subpart C, the bad-actor
detail in Rule 503, the Rule 201 disclosure itemisation beyond the financial
statement tiers, and Rules 205 and 206.

**Things the encoding says more precisely than the regulation does.** Each of
these is a decision somebody made, not a fact about the law:

- **The one-year resale period's endpoint.** The regulation does not decide it;
  the encoding does, as a half-open interval, and says so at the site.
- **The financial-statement assurance ordering.** The rule says supply better
  statements if you have them; it never states an ordering, and the ordering is
  the encoding's invention. Whether the better statements _exist_ is not
  modelled at all.
- **The exhaustive-and-exclusive reading of the two investment-limit limbs.**
  Correct, and still a reading.

**Things it counts more crudely than the regulation does.**

- **Business days are counted as plain days.** Right only when no weekend or
  holiday intervenes.
- **The one-year restricted period is
  [365 days](src:jl4/examples/legal/regcf/regcf.l4#L250).** Wrong across a leap
  year.

**Things it takes as given rather than deciding.** Reasonable-belief standards
are inputs, not derivations: the encoding can represent the consequence of a
standard being met and cannot decide whether it was met. The same is true of
"total assets", "annual income" and "net worth", which are unmodelled
primitives, and of the bad-actor disqualification, which is one field where the
regulation has a sub-regime.

**Things it models but does not connect.** Rule 100(a)(4)'s proviso — a
reporting default costs the next offering, not this one — is documented at the
site and is not enforced structurally. Integration under Rule 152 is a reference,
not a computation.

**Dead limbs.** The corpus declares two acts that no rule ever performs, and one
period that only the citizen-facing wizard's prose reads. The decision-table
exporter flags the unused period as an inert decision, which is how they were
found.

**One house rule broken and tolerated.** The corpus contains chained
`ELSE IF` constructs where the project's own drafting guidance calls for a
`BRANCH`. The pipeline's encoding check rides degraded on that count rather than
forgiving it, and the subject's notes say plainly: tolerated, not endorsed, and
do not add more.

**And one limit of the checker rather than the corpus.** The check that counts
dated arms matches on a single physical line, so reflowing a dated `BRANCH`
across lines makes an arm invisible to it. The subject declares a floor on the
count for exactly that reason — to stop the temporal-closure check passing
vacuously over an empty set — with the instruction to raise the floor as the
corpus gains arms and never to lower it to make a run go green.
