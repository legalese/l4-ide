**This is the place where the regulation genuinely does not decide, and no
encoding can rescue it.** "During the one-year period beginning when the
securities were issued" does not say whether the first anniversary itself falls
inside the period or outside it. A person selling on that exact day is either
within the restriction or free of it, and the text supports both.

The corpus does not paper over the gap; it records it, picks a reading, says
which, and tests the boundary from both sides. The note at the site is worth
quoting in full because it is the honest shape of an interpretive choice:

> [A drafter who cared could remove the question with four words; a reader who cares must litigate it.](src:jl4/examples/legal/regcf/regcf.l4#L722-L723 "verbatim")

The reading taken is a half-open interval: the day before the anniversary is
restricted, the anniversary itself is free. Both sides are asserted, so anyone
who disagrees can see exactly which assertion to flip.

**And a smaller infidelity, of a different kind.** The one-year period is
rendered as [365 days](src:jl4/examples/legal/regcf/regcf.l4#L250). That is
wrong across a leap year, and unlike the endpoint question it is fixable with
proper date arithmetic. The two sit next to each other in the corpus's own list
of limits, which is the useful distinction: one is a defect somebody could
repair this afternoon, and the other is a hole in the regulation.

**The inert-style showcase.** This decision's four exceptions are written with
each statutory paragraph label riding beside its operative limb:

```
..  "(1)" ... transfer's `to the issuer of the securities`
```

So the reading is a visible choice rather than an accident of punctuation, and
the statutory label travels with the limb it labels. It is also, by some
distance, the widest figure the ladder generator produces from this corpus, for
a reason that is not a defect: the fourth exception's field name is the
regulation's own sentence, and leaf labels do not wrap. Trimming it would be
transcription, and a trimmed ladder is a different rule.
