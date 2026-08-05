This is a prohibition, so it is written as one: a party, an act, and no
deadline.

```
`advertising restriction` notice MEANS
    IF   `notice complies with Rule 204(b)` notice
    THEN FULFILLED
    ELSE PARTY Issuer SHANT `advertise the terms of the offering`
```

**And this rule is where the encoding had its worst bug.** An earlier draft
wrote `WITHIN ` and borrowed the resale rule's one-year period, on the reasoning
that a deadline is decoration on a prohibition. It is not. In this language a
bounded prohibition **sunsets**: the comment now standing at the site records
that
[`SHANT ... WITHIN n` SUNSETS at n](src:jl4/examples/legal/regcf/regcf.l4#L636 "verbatim"),
so the borrowed deadline made the prohibition expire and
[an issuer advertising on day 400](src:jl4/examples/legal/regcf/regcf.l4#L637 "verbatim")
evaluated to compliant. An unqualified prohibition holds for the life of the
contract, which is what the rule says, and that is what the code now says.

**The part worth dwelling on is that the trace output could not have caught
it.** When this evaluator reports a prohibition it names the deadline as the
event time, so a bounded prohibition and an unbounded one print identically. The
bug was found by reasoning about the operator, not by reading output — which is
a useful correction to the idea that executable law is self-checking. Execution
finds the bugs that change an answer you thought to ask for.

**Where the statute's own words survive whole.** Almost everywhere else in this
corpus, a quoted fragment that merely restates the field beside it has been
deleted, because a diagram prints the quotation and the field name side by side
and a reader should not have to diff them by eye. Rule 204(b) is the exception:
the three permitted content items are _permissions_, and no operative node
carries their words — the operative node refers to them only as "information
beyond that permitted by paragraph (b)". So the closed list rides verbatim, and
the definition in Rule 204(e) rides verbatim beside a node that is literally
`TRUE`. The rule for when a quotation stays is mechanical: **inert text never
shadows active text.**
