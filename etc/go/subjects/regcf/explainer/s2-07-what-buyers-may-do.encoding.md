**This is the place where the regulation genuinely does not decide, and no
encoding can rescue it.** "During the one-year period beginning when the
securities were issued" does not say whether the first anniversary itself falls
inside the period or outside it. A person selling on that exact day is either
within the restriction or free of it, and the text supports both.

The corpus does not paper over the gap; it records it, picks a reading, says
which, and tests the boundary from both sides. The note at the site is worth
quoting in full because it is the honest shape of an interpretive choice:

> [A drafter who cared could remove the question with four words; a reader who cares must litigate it.](src:jl4/examples/legal/regcf/regcf.l4#L788-L790 "verbatim")

The reading taken is a half-open interval: the day before the anniversary is
restricted, the anniversary itself is free. Both sides are asserted, so anyone
who disagrees can see exactly which assertion to flip.

**And a smaller infidelity of a different kind, since repaired.** The one-year
period used to be rendered as a flat count of days, with the predicate comparing
elapsed days against a constant. That is wrong across a leap year, by exactly one
day. Unlike the endpoint question it was a defect and not a hole, and it has been
fixed: the record now carries the issuance date and the transfer date, and the
period ends at a computed anniversary —
[`add years` (transfer's `date the securities were issued`)](src:jl4/examples/legal/regcf/regcf.l4#L781-L782 "verbatim"),
which the corpus notes is
[366 across a 29 February, 365 otherwise](src:jl4/examples/legal/regcf/regcf.l4#L764-L765 "verbatim").

**How it was found is the part worth keeping, and it is not the flattering
version.** The defect was never hidden. It was
[disclosed in this list from the corpus's first commit](src:jl4/examples/legal/regcf/README.md#L347-L348 "verbatim"),
which named the cause, the remedy — carry an issuance date instead of an elapsed
count — and its price. Then it sat there. Being written down and being repaired
are different states, and a disclosed defect can outlive several readings of the
disclosure.

What moved it was a **second, independent encoding of the same rule**, written
without reference to the first. That one carried dates from the start and
computed its own anniversary by reconstructing the components — which rolls a
leap-day issuance forward to the first of March instead of clamping. Run the two
encodings over a battery of cases that differ by one fact at a time, and the day
where they disagree names itself.

**Note that neither side could have got there alone, for different reasons.**
This corpus could not state the case at all: its record held an elapsed day count
and no dates, so a leap-spanning holding was not expressible in its own
vocabulary. The independent encoding could state it — and its assertions still
would not have found this, because they exercise that encoding, and a test cannot
fail on a defect in a file it does not import. What the comparison supplied was
not the knowledge. It was the **witness**: a concrete pair of answers that
differ, on a case both sides evaluate.

**And repairing it did not remove a question. It exposed one.** A calendar
anniversary has to decide what one year after a leap day is, and the encoding
takes the reading its target systems already implement:
[`add years` CLAMPS: the first anniversary of a 29 February issuance is 28 February](src:jl4/examples/legal/regcf/regcf.l4#L767-L768 "verbatim").
That was measured on the two decision engines this corpus exports to, and it is
also what a spreadsheet's month-arithmetic does. The alternative — that the
period runs a full year and lands on the next day that exists, one day later — is
not wrong as law, and it is not hypothetical either: it is what the independent
encoding above computes, and what L4's own lenient date constructor gives you if
you rebuild the components by hand. What it is not is what either target engine
does, so an encoding that took it here would answer differently from its own
export. So this rule now discloses two interpretive forks where it used to
disclose one, and the corpus says which is which:
[This is a genuine fork; the UNIT question below was not](src:jl4/examples/legal/regcf/regcf.l4#L790-L791 "verbatim").
Both are registered under **Where the law is unsettled**.

**The inert-style showcase.** This decision's four exceptions are written with
each statutory paragraph label riding beside its operative limb:

```
..  "(1)" ... transfer's `to the issuer of the securities`
```

So the reading is a visible choice rather than an accident of punctuation, and
the statutory label travels with the limb it labels.

Until the decomposition described below, this was also, by some distance, the
widest figure the ladder generator produced from this corpus, because the fourth
exception was a single field whose name was the regulation's own sentence,
verbatim, and leaf labels do not wrap. That was reported here as "not a defect". It was one, and not the
width: a name is read as a label, not as a proposition, so four statutory
alternatives sitting inside one name were four alternatives nobody could audit —
not a reviewer, not the diagram, not the wizard. The limb is now six fields under a decision of its own,
[a family or trust transferee, or a death-or-divorce circumstance](src:jl4/examples/legal/regcf/regcf.l4#L825 "verbatim"),
grouped so that the three that name a **recipient** and the three that name an
**occasion** are visibly different things, and the figure is a third of its
former width as a side effect. What was not decomposed is the defined term
"member of the family of the purchaser or the equivalent": Rule 501(c) defines it
with "includes", so it is an open list, and enumerating it would encode an open
term as a closed one. Trimming a label would still be transcription, and a
trimmed ladder is still a different rule; splitting a name that hid a disjunction
is neither.
