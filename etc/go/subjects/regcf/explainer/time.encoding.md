A rule with different content at different dates is not one rule with a
parameter. It is a **family of rules indexed by a date**, and there are two
clocks: when did the facts happen, and which rules were in force. A wiki page
has one version axis and it is the wrong one — "the page as of revision r" is
not "the rules in force on day d".

So every figure that has ever moved is bound once, as a staircase, newest regime
first:

```
`offering maximum in a 12-month period` MEANS
    BRANCH IF `the rules in force include` `the 2021 amendments`           THEN 5000000
           IF ^                            `the 2017 inflation adjustment` THEN 1070000
           IF ^                            `Reg CF commenced`              THEN 1000000
           OTHERWISE `no Regulation Crowdfunding figure exists before commencement on 2016-05-16`
```

Four named dates, each carrying its Federal Register citation. One shared guard,
`the rules in force include`, which reads the rule date. A typed floor at the
bottom, so that asking about a day before commencement stops and names the
binding rather than inventing a figure. And a timezone —
[TIMEZONE IS "America/New_York"](src:jl4/examples/legal/regcf/regcf.l4#L9 "verbatim")
— because an effective date is a Washington date and midnight has to happen
somewhere.

**The hard part is closure, not dating.** A function is dateable only when
_every constant it transitively reads_ is dated over the same window. Dating a
proper subset is not a partial improvement; it is a defect, because the
half-dated function answers **confidently and wrongly inside its own answerable
window**. The corpus pins that with a dedicated regression: an investor above
the second limb's cap, where the answer _is_ the cap — which moved in the same
release, by a different instruction, on the same day. Under a partially dated
module the assertion at
[$107,000](src:jl4/examples/legal/regcf/regcf.l4#L1174) silently returns the
current figure instead.

**Shapes are dated too, not only numbers.** The change from _lesser_ to
_greater_ is a change in the shape of the formula, and the accredited-investor
carve-out did not exist before it. Both are dated arms like any other, so asking
the question under the earlier rules gives the earlier answer rather than an
error.

**What it costs, named rather than hidden.**

- **Per-arm citation has no home in the language.** The operators that carry
  quoted text through a rule are Boolean-only, and these constants return
  numbers, so each arm's Federal Register authority is a comment beside it
  rather than a checkable annotation. That is the sharpest limit the temporal
  work ran into.
- **Nothing lints the dated arms** for exhaustiveness, overlap or citation. The
  discipline held because somebody held it, not because a tool enforced it.
- **The ordinary assertions are deliberately unpinned** and ride the harness's
  fixed clock, which currently sits inside the present regime. After the next
  inflation release they must be pinned or re-verified, and the corpus says so
  at the site rather than leaving it to be discovered.
