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

**And here the checker declined to certify.** When this corpus is exported to
the decision modelling standard, the exporter tries to prove each decision
_total_ — that it terminates on every input — before flattening it into a table.
On this one it could not, and rather than assuming, it wrote down both what it
failed to prove and what it did instead. The whole finding, not the first half
of it:

> [`ongoing reporting obligation` could not be certified total (TERMINATES at main.l4:708:1-717:84: self-recursion could not be certified structurally terminating (no parameter position decreases through a FOLLOWED BY pattern on every recursive call)), so it is not un-lifted. Its deontic body is lowered to a verdict decision table (see D-VERDICT), which always answers one row, and no raw-L4 call site of it remains in the artifact; what could not be certified is the L4 source itself — the HENCE self-recursion may not terminate — and the artifact does not carry that recursion](src:jl4/examples/dmn/expected/regcf-corpus.fidelity.txt#L336 "verbatim")

Read the second half carefully, because the first half on its own tells a
flattering and wrong story. The exporter did **not** refuse. It produced a
table — you will find `ongoing_reporting_obligation` among the decision tables
listed in **Pictures**, and printed in full there — and what it declined to
carry across is the recursion. The table answers one row and stops. The renewal,
which is the whole point of the rule, lives in the L4 and not in the export.

The recursive call **does** decrease `annual cycles`, just not through the
pattern the certifier recognises, so a reader should not take this as the tool
being right. Take it as the tool being **specific about what it could not
establish**, in a report that ships with the artifact, at the site of the thing
it could not establish it about. A legal document has no equivalent of that
sentence, and the difference between "we could not prove termination" and "we
lowered it to a table that terminates by construction" is exactly the kind of
difference that vanishes in prose.

**The other thing this rule shows is why "constitutive" and "regulative" are
different kinds.** A decision is a function from facts to an answer; you
evaluate it and you are done. This is a duty with a lifecycle — live, fulfilled,
breached, renewed — and only something with a lifecycle can be drawn as a state
machine or as a process diagram. That is why the **Pictures** section can show a
workflow for this rule and cannot show one for the eligibility test.
