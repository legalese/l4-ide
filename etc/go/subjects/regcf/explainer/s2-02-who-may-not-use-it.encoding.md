Because the rule is drafted as a list of disqualifiers, the encoding is drafted
as a list of disqualifiers: six limbs, disjoined under the statutory chapeau,
and then negated exactly once.

```
`issuer is excluded by Rule 100(b)` issuer MEANS
        "(b) Applicability. The crowdfunding exemption shall not apply ..."
    ..  `(b)(1) — not organized under State or territorial law` issuer
    ..  `(b)(2) — an Exchange Act reporting company` issuer
    ..  `(b)(3) — an investment company` issuer
    ..  `(b)(4) — subject to a bad-actor disqualification` issuer
    ..  `(b)(5) — delinquent in ongoing annual reports` issuer
    ..  `(b)(6) — no specific business plan, or a blank-check business plan` issuer

DECIDE `issuer is eligible` issuer IF
    NOT `issuer is excluded by Rule 100(b)` issuer
```

Eligibility is the single negation of that disjunction:
[issuer is eligible](src:jl4/examples/legal/regcf/regcf.l4#L321 "verbatim")
holds exactly when the issuer is not
[excluded by Rule 100(b)](src:jl4/examples/legal/regcf/regcf.l4#L322 "verbatim").
That one `NOT`
is the whole translation from the regulation's polarity to the reader's. Turning
six exclusions into a positive list of conditions would have been shorter and
would have been a different rule — the reader could no longer check the encoding
against the regulation limb by limb.

**What each limb carries.** The field names are the regulation's own words, not
paraphrases. Limb five's field is literally
`has sold securities in reliance on section 4(a)(6) and has not filed the
ongoing annual reports required during the two years immediately preceding the
filing of the offering statement`. That is what makes the ladder figure for this
decision the useful one: six short rungs, where a rung that is missing is
visible. The top-level decision's ladder is in **Pictures** too, because that
section prints what the run produced rather than what this document would have
chosen, but it is five calls in a row and it teaches nothing that the five lines
above do not.

**And this is where isomorphic encoding paid.** A published summary of this
regulation that the corpus was checked against lists **four** eligibility
conditions. There are six. The genuinely missing one is limb five, the
delinquent-filer disqualifier. In prose, a missing sentence is invisible — there
is nothing on the page where it should have been. In a six-rung ladder, a
missing rung is a hole. Limb five has its own fixture, its own assertion, and
its own scenario in the corpus's test block, which fails on that limb and
nothing else.

**What the encoding could not do.** The bad-actor limb collapses to a single
yes-or-no field —
[`subject to a disqualification as specified in section 227.503(a)`](src:jl4/examples/legal/regcf/regcf.l4#L259-L266 "verbatim")
— where Rule 503(a) is a sub-regime. The corpus does not pretend otherwise: the field is an
_input_, and the encoding can represent the consequence of the standard being
met without being able to decide the standard. That distinction — between a rule
a machine can evaluate and a judgement it can only accept as given — recurs
throughout, and is the honest boundary of this whole exercise.
