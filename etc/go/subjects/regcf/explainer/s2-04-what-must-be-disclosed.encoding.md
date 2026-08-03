**"Supply the better statements if you have them" is an ordering, and the rule
never states one.** To encode it the corpus had to invent one: an
`assurance level` running from certified through reviewed to audited, so that
"at least as good as the tier requires" becomes an arithmetic comparison. The
corpus's own list of honest limits says plainly that this is
[our invention, not the rule's](src:jl4/examples/legal/regcf/README.md#L369 "verbatim"),
and it says something sharper too: the "if available" trigger — whether the
better statements _exist_ — is not modelled at all. The encoding answers a
question the rule asks only in part.

**A curated refusal, and why it is banded.** During the pandemic the Commission
made temporary relief available to certain issuers raising modest amounts, in
Rule 201(z) and later Rule 201(bb). Eligibility for it turned on facts this
corpus does not model — how old the company is, whether it was previously
delinquent. So instead of guessing, the encoding declares a typed bottom:

```
ASSUME `the COVID-19 temporary rules, Rule 201(z) and (bb), are not modelled here`
       IS A FinancialStatementRequirement
```

Any evaluation that reaches it stops and names that binding rather than
answering. The interesting part is that the refusal is **banded, not blanket**:
it fires only when the rule date is inside the temporary window _and_ the
aggregate sits in the affected range. Ask a question outside that band and you
get an ordinary answer, pinned by assertions on both sides. A blanket refusal
would have been easier to write and would have made a large, correct part of the
corpus unanswerable for two years of legal time.

**Exhaustiveness as a standing obligation.** The three tiers are an enumerated
type, and the ordering function matches on all three with no catch-all and no
opt-out. That is not a check that fired here — nothing in this corpus's history
records the exhaustiveness checker rejecting anything. It is a check that
_would_ fire: add a fourth tier tomorrow and both modules stop compiling until
somebody says what the new tier's assurance level is. A document that said "the
type system caught a bug here" would be more impressive and would be false.
