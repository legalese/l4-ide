This is the boundary of the claim. Everything below is something the encoding
does not do, listed because a reader who discovers it later is entitled to think
the rest was oversold.

**Scope.** This is not a formalisation of the whole of 17 CFR Part 227. It
mirrors one external summary of the regulation, which presents it as eight
requirement groups, and encodes those eight to the depth that summary reaches.
Left out, in the corpus's own words:
[Subpart C's funding-portal registration regime (Rules 400-404), the bad-actor disqualification detail (Rule 503), and the Rule 201 disclosure itemisation beyond the financial statement tiers](src:jl4/examples/legal/regcf/regcf.l4#L28-L31 "verbatim"),
along with Rules 205 and 206.

**And a scope note about this document rather than the encoding.** The sections
above cover seven of the eight groups. The eighth — the intermediary's own
obligations — has no section of its own, because what the encoding has to say
about it is one accepted boolean, which is said under **The bargain**. A reader
who wants the funding-portal regime will not find it here and will not find it
in the encoding either.

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

This list used to have a second entry: the one-year resale period was rendered as
a flat count of days, which is wrong across a leap year. It has since been fixed,
and the fix is described under **What buyers may do**. The entry is named here
rather than deleted, because a limit that quietly disappears between two readings
of this document is indistinguishable from a limit that was never disclosed.
Repairing it did not close the question — it turned a defect into a stated
reading, which is now registered under **Where the law is unsettled** alongside
the endpoint above.

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

**Dead limbs.** Three of the acts the corpus declares are performed by no rule
at all — they occur exactly once each, in the declaration:
[file a Form C offering statement](src:jl4/examples/legal/regcf/regcf.l4#L96 "verbatim"),
[file a Form C-U progress update](src:jl4/examples/legal/regcf/regcf.l4#L97 "verbatim")
and
[transmit funds to the issuer](src:jl4/examples/legal/regcf/regcf.l4#L101 "verbatim").
There is also one period that only the citizen-facing wizard's prose reads; the
decision-table exporter flags it as an inert decision —
[advisory — decision_business_days_to_file_a_progress_update](src:jl4/examples/dmn/expected/regcf-corpus.fidelity.txt#L293 "verbatim")
— which is how it was found. A projection noticing something dead in the source
is not what a projection is for, and it is the second-best argument in this
document for building them.

**One house rule the corpus does not follow, and the pipeline tolerates.** The corpus contains chained
`ELSE IF` constructs where the project's own drafting guidance calls for a
`BRANCH`. The pipeline's encoding check reports the count against the corpus
rather than forgiving it, and the subject's notes say plainly: tolerated, not
endorsed, and do not add more. What that check said about _this_ run is in the
audit report, not here.

**And one limit of the checker rather than the corpus.** The check that counts
dated arms matches on a single physical line, so reflowing a dated `BRANCH`
across lines makes an arm invisible to it. The subject declares a floor on the
count for exactly that reason — to stop the temporal-closure check passing
vacuously over an empty set — with the instruction to raise the floor as the
corpus gains arms and never to lower it to make a run go green.
