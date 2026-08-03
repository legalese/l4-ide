That split between "conditions of the exemption" and "duties that survive it" is
the single most legible structural fact in the encoding, because the two halves
are written in **different kinds of rule**.

The top-level decision is a conjunction of exactly five calls and nothing else:

```
DECIDE `the transaction qualifies for the section 4(a)(6) exemption` ... IF
        "(a) Exemption. An issuer may offer or sell securities in reliance ..."
    ... `issuer is eligible` issuer
    AND `offering is within the offering limit` offering
    AND `investor is within the investment limit` investor amount
    AND `intermediary obligations are met` arrangement
    AND `disclosure requirements are met` filing offering
```

The advertising restriction, the reporting obligation and the resale restriction
are **not** conjuncts of it. They are regulative rules — obligations and
prohibitions with parties, deadlines and lifecycles — and they live outside the
decision entirely. Rule 100(a)(4)'s proviso is therefore encoded as _structure_
rather than as a comment: a reporting default cannot make
[`the transaction qualifies for the section 4(a)(6) exemption`](src:jl4/examples/legal/regcf/regcf.l4#L771 "verbatim")
false, because it is not one of the things that decision reads.

**What the encoding did not manage to say.** The other half of that proviso —
that a default _does_ disqualify the next offering, through Rule 100(b)(5) — is
carried as a comment beside the rule and is not enforced structurally. Two
offerings by the same issuer, one after a default, are not linked by anything
the machine checks. That is recorded in the corpus's own list of honest limits;
it is a real gap, not a stylistic one.

**One conjunct swallows an entire regime.** `intermediary obligations are met`
looks like the other four. The deepest thing under it is a single yes-or-no
field the encoding simply accepts as given:

> [`the intermediary complies with section 4A(a) of the Securities Act and the related requirements in this part` IS A BOOLEAN](src:jl4/examples/legal/regcf/regcf.l4#L548 "verbatim")

Behind that one boolean stand the funding-portal registration rules and the
platform conduct rules — the part of 17 CFR Part 227 this encoding does not
reach at all. It is the same move as the bad-actor limb in the next section, at
a larger scale, and it is worth naming here because a reader looking at the
five-conjunct decision above would reasonably take the five to be comparable in
weight. They are not. The encoding can represent the consequence of the
intermediary regime being satisfied without being able to decide whether it is.

Notice also the first line of the decision. `"(a) Exemption. An issuer may offer
or sell securities …"` is a double-quoted string sitting inside a conjunction,
and it computes nothing at all. Inside an `AND` it behaves exactly like `TRUE`,
so deleting every such string would change no answer this file gives. It is
there so the statute reads down the left margin as prose while the arithmetic
happens in the backticked names beside it. This is the house style, and most of
what follows is only readable because of it.
