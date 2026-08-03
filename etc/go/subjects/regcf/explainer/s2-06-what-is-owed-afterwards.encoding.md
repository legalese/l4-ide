A duty that renews itself is the only genuinely recursive thing in this
regulation, and it is written as such:

```
`ongoing reporting obligation` status `annual cycles` MEANS
    IF   `ongoing reporting obligation may terminate` status
    THEN PARTY Issuer MUST `file a Form C-TR termination of reporting` WITHIN ...
    ELSE IF   `annual cycles` AT MOST 0
         THEN FULFILLED
         ELSE PARTY Issuer MUST `file a Form C-AR annual report` WITHIN ...
              HENCE `ongoing reporting obligation` status (`annual cycles` MINUS 1)
```

`HENCE` is "and then this duty stands next". The `annual cycles` parameter
bounds how far the obligation is unrolled, so what remains after evaluating a
few years is finite and printable. Run it against a compliant issuer and the
residual you get back is next year's report — the duty renewed, not discharged.

**And here the checker said no.** When this corpus is exported to the decision
modelling standard, the exporter tries to certify each decision total — that it
terminates on every input — before flattening it. On this one it could not, and
it says so rather than assuming:

> [`ongoing reporting obligation` could not be certified total (TERMINATES at main.l4:697:1-706:84: self-recursion could not be certified structurally terminating (no parameter position decreases through a FOLLOWED BY pattern on every recursive call)), so it is not un-lifted.](src:jl4/examples/dmn/expected/regcf-corpus.fidelity.txt#L324 "verbatim")

The recursive call **does** decrease `annual cycles`, just not through the
pattern the certifier recognises. The point is not that the checker is right; it
is that a tool that cannot prove something says so at the site, in a report that
ships with the artifact, instead of producing an export that quietly assumes it.
A legal document has no equivalent of that sentence.

**The other thing this rule shows is why "constitutive" and "regulative" are
different kinds.** A decision is a function from facts to an answer; you
evaluate it and you are done. This is a duty with a lifecycle — live, fulfilled,
breached, renewed — and only something with a lifecycle can be drawn as a state
machine or as a process diagram. That is why the **Pictures** section can show a
workflow for this rule and cannot show one for the eligibility test.
