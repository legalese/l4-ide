# 11. When the encoding cannot answer

One area of the phrasebook. The index, the preamble and the other ten areas are in
[source-patterns.md](../source-patterns.md).

This area comes last on purpose, and is kept apart from the other ten. `REFUSE` is
obscure: you could encode a dozen laws or contracts and never use it. Work down
[the questions to ask, in order](#e11-questions) before you write one, and stop at the
first `yes` — six of its seven rows send you somewhere else.

<a id="e11-1"></a>

## 11.1 "The Minister may by regulations prescribe …" — the power, not exercised

**If the source says**

> `6(3)-(4) (the States' power to add heads by Regulations)` — listed among the parts that "are out of scope"
>
> — `jl4/examples/legal/charities-cleanroom/charity-test.l4:22-25`

**It is doing** one of two things, and you must decide which before writing anything:

- **The power has not been exercised, and the statute supplies its own default.** Then the default
  is the law, and you encode the default. Nothing is missing.
- **The power has not been exercised and there is no default** — or it has been exercised and this
  encoding did not reach the instrument. Then the model has no answer, and should say so.

**The test is one question: does the section supply its own fallback?** Read the sentence to the
end. "The levy is 2% of the value, **or such other rate as the Minister may prescribe**" supplies
one — 2% is the law until an instrument displaces it, and there is nothing missing to declare.
"The Minister **may by order extend** this Act to trusts" supplies none — with no order, the
sentence leaves you with no rule to encode at all. Both limbs routinely appear in **one Act**, so
decide it per section, never per statute:

```l4
DECLARE `The levy on the transaction` IS ONE OF
    `the levy is` HAS amount IS A NUMBER

-- 2. The levy is 2% of the value, OR SUCH OTHER RATE as the Minister may
--    prescribe by regulations.  The power is unexercised and the section
--    supplies its own rate, so the 2% is the law: encode it.
@ref Transactions Levy Act s 2; no regulations prescribing another rate have been made
GIVETH A NUMBER
`s 2 — the rate of the levy` MEANS 2%

-- 6. The Minister MAY BY ORDER extend this Act to trusts.  No order, and the
--    section supplies no fallback, so there is nothing to encode: a refusal.
@ref Transactions Levy Act s 6 — no order extending this Act to trusts has been made
GIVETH A `The levy on the transaction`
`no order under section 6 extending this Act to trusts is encoded in this model` MEANS
    REFUSE "no order under section 6 extending this Act to trusts is encoded in this model"

#ASSERT `s 2 — the rate of the levy` EQUALS 0.02
#ASSERT REFUSED `no order under section 6 extending this Act to trusts is encoded in this model`
```

_(`REFUSE`; checked on the `REFUSE` binary, exit 0, both assertions satisfied.)_ On `2%`, which is
a real percent literal and not a comment, see [entry 3.2](03-quantities-and-calculation.md#e3-2).

**Write**, for the second case, one named definition per refusal: the definition's name **is** its
message, an `@ref` above it says why, and every rule that needs it calls the name.

```l4
@ref Charities (Jersey) Law 2014 Article 6(3)-(4) — the States' power to add heads by Regulations
GIVETH A BOOLEAN
`no Regulations adding a head of charity are encoded in this model` MEANS
    REFUSE "no Regulations adding a head of charity are encoded in this model"
```

**Not** a `-- NOT MODELLED` comment on a provision a rule can actually reach. A comment stops
nothing: the evaluation runs on, the export schema does not mention it, and the wizard asks nothing
about it. A comment is right only where **no rule reaches** the gap.

**Not** `FALSE`, and not `0`. "No Regulations have been made" and "the Regulations say no" are
different answers, and a caller cannot tell them apart once you have written the second.

**Careful which side of the line you are on.** A power the legislature has never exercised is closer
to "the law provides no figure" — the entry-6 shape — than to "the model does not cover this". The
instances in **this** corpus happen all to fall on the refusal side, because in each of them the
encoding chose not to reach the instrument. Read that as a fact about what has been encoded here,
**not as a prior**: it is not evidence about the section in front of you, and taking it as one is
how a section that supplies its own default gets written as a refusal. Apply the fallback test
above to the sentence you actually have.

**See** [entry 11.5](#e11-5), which is the same construct for the general case.

---

<a id="e11-2"></a>

## 11.2 "[amount to be inserted]", a clause not yet drafted

**If the source says** a blank. This does **not** occur in the encoded corpus — no bracketed
"to be inserted", no `TBD`, no row of capital Xs, in any of the 26 files under
`jl4/examples/legal/`, because these are encodings of enacted law and enacted law has no blanks. The phrase belongs to a bill in progress or
a contract in negotiation, which this phrasebook also serves.

**It is doing** marking a hole that a human will fill later.

**Write** `TBD`, the prelude's refusal meaning exactly "not written yet" (needs `IMPORT prelude`).

```l4
IMPORT prelude

GIVETH A NUMBER
`the surcharge, [rate to be inserted]` MEANS TBD
```

`#EVAL` of it prints, under `Result:`,

```text
The model refuses to answer:
  TBD: this rule has not been written yet
```

**State the limit.** `TBD` is **not yet** reported differently from a hand-written `REFUSE`; warning
it separately as a placeholder is proposed, not landed (2026-09-04). So the drafting note in your
identifier does not reach the output at all — every `TBD` in the file prints the same one line.

**Which to write, by default: a named refusal, and `TBD` only for the one-blank scratch draft.**
The moment a file has two blanks, `TBD` stops telling the reader anything, and the reader who most
needs to know which blank they hit is the drafter who has to fill it. Measured, both on the `REFUSE`
binary, exit 0 — four `#EVAL`s over four blanks:

```l4
IMPORT prelude

-- Two blanks under TBD. The output tells the reader neither of them apart.
GIVETH A NUMBER
`the surcharge, [rate to be inserted]` MEANS TBD

GIVETH A NUMBER
`the late fee, [amount to be inserted]` MEANS TBD

-- The same two blanks, each named. The name IS the message.
GIVETH A NUMBER
`clause 4.2 — the surcharge rate is not yet drafted` MEANS
    REFUSE "clause 4.2 — the surcharge rate is not yet drafted"

GIVETH A NUMBER
`clause 9.1 — the late fee is not yet drafted` MEANS
    REFUSE "clause 9.1 — the late fee is not yet drafted"

#EVAL `the surcharge, [rate to be inserted]`
#EVAL `the late fee, [amount to be inserted]`
#EVAL `clause 4.2 — the surcharge rate is not yet drafted`
#EVAL `clause 9.1 — the late fee is not yet drafted`
```

The four `#EVAL` results, in order. The first two are the same line twice; the second two name
their own blank:

```text
The model refuses to answer:
  TBD: this rule has not been written yet
The model refuses to answer:
  TBD: this rule has not been written yet
The model refuses to answer:
  clause 4.2 — the surcharge rate is not yet drafted
The model refuses to answer:
  clause 9.1 — the late fee is not yet drafted
```

Keep `TBD` where it earns its brevity: a draft with a single hole, or a sketch you will finish in
the same sitting. Everything a negotiating counterparty or a second drafter will read gets a name.

**Not** `0`, `""` or `NOTHING` as a placeholder. Each is a value the rest of the file will happily
compute with, and a draft that silently prices a blank at zero is worse than one that stops.

**See** [entry 11.5](#e11-5) and [entry 11.6](#e11-6).

---

<a id="e11-3"></a>

## 11.3 "…, if any", "where there is no …"

**If the source says**

> `s 7 rule 3 — "Subject to the rights of the surviving spouse, if any, the estate (both as to the undistributed portion and the reversionary interest) of an intestate who leaves issue shall be distributed by equal portions per stirpes"`
>
> — `jl4/examples/legal/sg-succession/cleanroom-2026-08/intestate-succession-act.l4:1126`

**It is doing** the drafter's own hedge that a thing may not exist, together with an instruction on
what follows when it does not. The absence is a fact about the case, as solid as any number.

**Write** `MAYBE`, matched with `CONSIDER`, and give the absent arm a name or a value that says what
follows from the absence.

```l4
DECLARE Estate HAS
    `the net value of the estate`       IS A NUMBER
    `the share of the surviving spouse` IS A MAYBE NUMBER

@ref Intestate Succession Act 1967 s 7 rule 3
GIVEN e IS AN Estate
GIVETH A NUMBER
`the portion distributable among the issue of` e MEANS
    e's `the net value of the estate`
    MINUS
    CONSIDER e's `the share of the surviving spouse`
    WHEN NOTHING THEN 0
    WHEN JUST s  THEN s
```

`MAYBE` is by far the most common non-answer in real encodings: **106** `IS A[N] MAYBE` slots in the
legal corpus alone, against 51 module-level `ASSUME` declarations. Do not migrate them anywhere.

**Not** a refusal. An absent value is one the rule can and should handle — the statute told you how.

**Not** an unnamed `NOTHING` arm in a result the caller reads. Where the source **names** the absent
outcome ("no issuance", "the application is refused"), the outcome belongs in the result type as a
named member; see the two-question test in [drafting-patterns.md](../drafting-patterns.md), "Where
`MAYBE` is right — and it usually is", which also lists the four cases where folding it would be a
mistake.

**See** `concepts/legal-modeling/non-answers.md` (new in this release), section 1.

---

<a id="e11-4"></a>

## 11.4 "must be a positive number", a date that does not exist — invalid input

**If the source says** a requirement that rules an **input** out, rather than deciding a case: a
negative quantity, a month of 13, a form field that contradicts itself.

**It is doing** rejecting the question, not answering it. The caller can act on this: fix the form
and ask again.

**Write** `EITHER`, with a named problem on the left, so the caller must handle both shapes.

```l4
DECLARE `A problem with the filing` IS ONE OF
    `the number of securities offered is negative`
    `the offering date is not a date in the calendar`

GIVEN `the number offered` IS A NUMBER
GIVETH AN EITHER `A problem with the filing` NUMBER
`the number of securities in the filing` MEANS
    IF   `the number offered` LESS THAN 0
    THEN LEFT `the number of securities offered is negative`
    ELSE RIGHT `the number offered`
```

A caller matches with `CONSIDER … WHEN LEFT p … WHEN RIGHT n …` and turns the left into a message.

**Three facts about `EITHER` that save you a workaround.** All measured on the section-`GIVEN`
binary, exit 0.

- **`EQUALS` works on an `EITHER` value, and on an enum constructor carrying fields.** You do not
  need a boolean helper to assert which side you got. (`DEONTIC` is the type that cannot be
  `EQUALS`-compared — see [drafting-patterns.md](../drafting-patterns.md), "Exercising a DEONTIC".)

  ```l4
  #ASSERT `the number of securities in the filing` (0 MINUS 5) EQUALS LEFT `the number of securities offered is negative`
  #ASSERT `the number of securities in the filing` 200 EQUALS RIGHT 200
  ```

  **Keep each `#ASSERT` on one line.** Continuing one onto the next line with `EQUALS` is a parse
  error: `unexpected EQUALS`, `expecting %, ;, end of input, or space token`. The one split form
  that does parse is `#ASSERT REFUSED` with its `BECAUSE` on the second line — [entry 11.6](#e11-6).

- **A one-constructor `IS ONE OF` is legal**, and is the right shape for a problem type with exactly
  one problem in it. Do not invent a second member to make it look like the examples.

- **Read the printed forms as printed forms, not as source.** `#EVAL` renders an applied
  constructor with an `OF` that you never write:

  ```text
  `the levy is` OF 200
  LEFT OF `the stated value is not a positive amount`
  RIGHT OF (`the levy is` OF 200)
  ```

  In source these are ordinary application — `` `the levy is` 200 ``, `LEFT p`, `RIGHT x`. The word
  `OF` belongs to the printer. Copying output back into a file is the one way to get this wrong.

**Not** `REFUSE`. The standard library agrees, deliberately: `YMD 2023 2 29` — no such leap day —
evaluates to the distinguished term `` `YMD refused an out-of-range month or day` ``, and **despite
the word in its name that is not a `REFUSE`**. Out-of-range date components were left as invalid
input on purpose. Do not tidy them into refusals.

**Not** a silent clamp. `Date 1 (3 MINUS 6) 2025` clamps to January 2025 rather than rolling back to
September 2024; `YMD` is the bounds-checked constructor and is what new code should use for literals.

**See** [gotchas.md](../gotchas.md), "The `daydate` month-subtraction footgun", and
`concepts/legal-modeling/non-answers.md` (new in this release), section 2.

---

<a id="e11-5"></a>

## 11.5 Scope this encoding deliberately does not cover

**If you are about to write** `-- NOT MODELLED`, `-- OUT OF SCOPE`, or a comment beginning "we do
not handle". This is the encoder speaking, not the statute, and it is the largest single category of
prose in the corpus — 25-plus sites. One of them:

> `-- ... the honest answer is a refusal, not a guess. Outside the band the ordinary tiers were unaffected and the answer stands.`
>
> — `jl4/examples/legal/regcf/regcf.l4:482-484`, on the temporary rules made during the coronavirus
> disease 2019 pandemic

**It is doing** marking the boundary of the model. The question is only whether a rule can **reach**
that boundary at run time.

**Write**, where a rule can reach it, a named refusal — one definition per refusal, the name is the
message, an `@ref` above it says why:

```l4
DECLARE FinancialStatementRequirement IS ONE OF
    `financial statements certified by the principal executive officer`
    `financial statements reviewed by a public accountant`
    `financial statements audited by a public accountant`

@ref 85 FR 27116 (Rule 201(z)); 86 FR 3496 instr. 5 (Rule 201(bb))
GIVETH A FinancialStatementRequirement
`the COVID-19 temporary rules, Rule 201(z) and (bb), are not modelled here` MEANS
    REFUSE "the COVID-19 temporary rules, Rule 201(z) and (bb), are not modelled here"
```

A refusal is an expression at **any** type, so it needs no sentinel constructor in
`FinancialStatementRequirement` and cannot be mistaken for one of the three real answers.

**Where no rule reaches the boundary, a comment is still the right thing** — it documents a gap that
cannot be hit. State which way the omission errs, as the corpus does
(`jl4/examples/legal/sg-succession/sg-wills.l4:278-280`):

```text
-- WHICH WAY THE OMISSION ERRS. s 5 only ever ADDS ways of being properly
-- executed -- "shall be treated as properly executed if" -- so leaving it out
-- can only make `the will is formally valid` too STRICT.
```

**Not** an `ASSUME`. That says "this is an unknown fact", so it is promoted to a parameter of every
exported function that reads it — which is why a caller of the Regulation Crowdfunding money
decisions is still asked, today, to supply a value for _"no Regulation Crowdfunding figure exists
before commencement on 2016-05-16"_. Nobody can supply that. A refusal appears in no export schema,
because it is not an input.

**Not** `NOTHING`, because a later rule can quietly default it:

```l4
IMPORT prelude

GIVETH A MAYBE NUMBER
`the figure before commencement (wrong)` MEANS NOTHING

GIVETH A NUMBER
`the figure a caller sees (wrong)` MEANS
    fromMaybe 0 `the figure before commencement (wrong)`
```

That answers `0`. The decline became an answer, one line away, and nothing in the output says so.

**And a refusal is only safe from that once something forces it.** A `REFUSE` you build into a
value — ``RIGHT (`the levy on` t)`` where the levy is the blank — is a decline that never runs,
and the caller gets an ordinary answer just as the `fromMaybe 0` above does. [Entry 11.8](#e11-8) measures it
and gives the repair, which is one line: **return the refusal; do not store it.**

**Not** a computed message. `REFUSE` takes a string literal: a refusal's reason should be readable
without running the program.

**See** the `REFUSE` reference page (new in this release) and
`concepts/legal-modeling/non-answers.md` (new in this release), section 5.

---

<a id="e11-6"></a>

## 11.6 Testing a refusal

**If you have just written** a `REFUSE`, it needs a test like anything else — and a plain `#ASSERT`
will not do it.

**Write** `#ASSERT REFUSED e`, adding `BECAUSE "…"` to pin the wording:

```l4
@ref Regulation Crowdfunding commenced on 2016-05-16
GIVETH A NUMBER
`no Regulation Crowdfunding figure exists before commencement on 2016-05-16` MEANS
    REFUSE "no Regulation Crowdfunding figure exists before commencement on 2016-05-16"

GIVEN y IS A NUMBER
GIVETH A NUMBER
`offering maximum in a 12-month period, in year` y MEANS
    BRANCH IF y AT LEAST 2021 THEN 5000000
           IF y AT LEAST 2016 THEN 1000000
           OTHERWISE `no Regulation Crowdfunding figure exists before commencement on 2016-05-16`

#ASSERT `offering maximum in a 12-month period, in year` 2021 EQUALS 5000000
#ASSERT REFUSED `offering maximum in a 12-month period, in year` 2015
        BECAUSE "no Regulation Crowdfunding figure exists before commencement on 2016-05-16"
#ASSERT REFUSED `no Regulation Crowdfunding figure exists before commencement on 2016-05-16`
```

_(Checked on the release binary, exit 0, no errors.)_ All three print `assertion satisfied`. A
failing one prints `assertion failed: expected a refusal, but the expression produced a value`, or
`assertion failed: expected the refusal "x", got "y"` when the `BECAUSE` message differs. The
directive may be split over two lines, as above, and asserts equally on a named refusal called with
an argument and on one called bare.

The year parameter above is this page's simplification. The corpus selects the figure on a rule
date rather than a year — `jl4/examples/legal/regcf/regcf.l4:148-154`, whose `OTHERWISE` arm over
`` `the rules in force include` `` is reached through `EVAL UNDER RULES EFFECTIVE AT`. That arm is
still an `ASSUME`, not yet a refusal; the shape is what to copy, not the keyword.
`jl4/examples/ok/refuse.l4:25-26` is the smallest runnable pair in the tree.

Two facts worth knowing when you read the output:

- A **plain** `#ASSERT e` whose `e` refuses reports `assertion refused:` — not _failed_, and not
  _could not be evaluated_. It is telling you the assertion never got to run.
- `l4 run` **exits 0** for a file containing a refusing `#EVAL` (reported at Warning severity) or a
  refused assertion. It exits **1** for a file whose `#EVAL` reads an input nobody supplied. So a
  refusal may appear in a runnable documentation example where an unsupplied section `GIVEN` may
  not.
- **A `#ASSERT` that fails does not make `l4 run` exit non-zero.** Measured on both binaries: a
  bare `#ASSERT 1 EQUALS 2` prints `assertion failed` at **Error** severity and the process still
  exits **0**. So "the file ran green" is not evidence that the assertions passed — check the
  diagnostics for `DiagnosticSeverity_Error`, which is what `doc/test-docs.sh` does and what a
  hand-rolled `l4 run; echo $?` does not.

**Not** `#ASSERT NOT e` to show that a rule declines. That reports a refusal too, and says nothing
about the message.

**And `#ASSERT REFUSED e` is a claim about `e`, not about the refusal inside it.** If `e` can reach
the refusal without forcing it, the assertion **fails** with `expected a refusal, but the expression
produced a value` — which is the test doing its job, telling you the decline is not on the path the
caller takes. Do not repair that by asserting on the inner refusal instead; that only tests the
definition. Read [entry 11.8](#e11-8) first and decide whether the wrapping was right.

**See** the `REFUSE` reference page (new in this release), and [entry 11.8](#e11-8).

---

<a id="e11-7"></a>

## 11.7 Migrating an existing `ASSUME`

**If the file already has** a block of module-level `ASSUME`s standing in for facts about the case:

```l4
ASSUME `the person is a body corporate` IS BOOLEAN
ASSUME `the person engages in business for profit` IS BOOLEAN
```

— the first two of seven such lines at `jl4/examples/legal/imaginary-alcohol-act.l4:33-39`, read
by the rule at `:41`.

**It is doing** three different jobs across a corpus, and each has its own destination:

| the `ASSUME` is                                     | it becomes                                                                                              |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| a fact about the case, to be supplied by the caller | a section `GIVEN` under the heading of the section whose rules read it                                  |
| an uninterpreted type (`ASSUME T IS A TYPE`)        | `DECLARE T` — **which does not parse today**; leave these as `ASSUME`                                   |
| a stand-in for something the model does not cover   | a named `REFUSE` ([entry 11.5](#e11-5)) — it was never a fact, and it should never have been suppliable |

**Write** the first case as one section `GIVEN`, names comma-separated, under the provision's
heading:

```l4
§§ `Section 1 — Prohibition on sale`
    GIVEN `is a body corporate`             IS A BOOLEAN,
          `engages in business for profit`  IS A BOOLEAN

GIVETH A BOOLEAN
`the person must not sell alcohol` MEANS
        `is a body corporate`
    AND `engages in business for profit`
```

**Behaviour in this release is identical.** A module-level `ASSUME` and a section `GIVEN` both
evaluate as assumed terms and both export as parameters. The migration buys scoping and the reader's
eye, not new behaviour — so do it when you are editing the section anyway, and do not sweep a corpus
for it.

**Not** a migration that expects `@export` to start working. A **function-typed** input is rejected
for `@export` whichever way it is declared: `Function type inputs are not supported for @export`.
Moving it to a section `GIVEN` does not change that.

**Not** a claim that `ASSUME` has stopped working. It parses, checks and exports as before, and no
deprecation warning is emitted.

**See** [entry 1.2](01-definitions-and-scope.md#e1-2) (where to put it), [entry 11.5](#e11-5) (when it was a refusal all along), and
the skill's own page, "Declaring inputs: one record, or a section `GIVEN`".

---

<a id="e11-8"></a>

## 11.8 A refusal only refuses when something forces it

**If you have written** a `REFUSE` and want to rely on "nothing downstream can catch it".

**It is doing** less than the sentence suggests. The guarantee is real: no `CONSIDER`, `IF`, `AND`,
`WHERE` or `MAYBE` match can observe a refusal and convert it to a value. But L4 evaluates lazily,
so a refusal that nothing **forces** never runs at all, and an unrun refusal is indistinguishable
from no refusal. Both halves are measured below.

**Write** the refusal in **return** position — as the answer the rule gives — not stored inside a
value the rule hands back.

The failure first, because it is the one that ships. A rule that wraps the refusal in a constructor
and a second rule that only looks at the constructor:

```l4
IMPORT prelude

DECLARE `A problem with the return` IS ONE OF
    `the stated value is not a positive amount`

@ref Transactions Levy Act s 4 — the amount is a blank in the draft
GIVETH A NUMBER
`s 4 — the levy where there is no stated value, [amount to be inserted]` MEANS TBD

GIVEN `the stated value` IS A MAYBE NUMBER
GIVETH AN EITHER `A problem with the return` NUMBER
`the return for a stated value of` `the stated value` MEANS
    CONSIDER `the stated value`
    WHEN NOTHING THEN RIGHT `s 4 — the levy where there is no stated value, [amount to be inserted]`
    WHEN JUST v  THEN IF   v AT MOST 0
                      THEN LEFT `the stated value is not a positive amount`
                      ELSE RIGHT (v TIMES 2%)

GIVEN `the stated value` IS A MAYBE NUMBER
GIVETH A BOOLEAN
`the return is rejected for a stated value of` `the stated value` MEANS
    CONSIDER `the return for a stated value of` `the stated value`
    WHEN LEFT p  THEN TRUE
    WHEN RIGHT r THEN FALSE

#EVAL `the return is rejected for a stated value of` NOTHING
```

_(`REFUSE`; checked on the `REFUSE` binary, exit 0.)_ That `#EVAL` answers **`FALSE`**. The blank
from s 4 is sitting inside the `RIGHT`, and asking whether the return is rejected never opens it, so
a return built on an amount nobody has drafted is reported as _not rejected_ — a decision, made on a
value that does not exist. The file is green, no warning fires, and nothing in the output mentions a
refusal. This is the same failure the entry-17 `fromMaybe 0` example warns about, arriving through
the construct that was supposed to prevent it.

**The repair is to return the refusal rather than store it**, and it replaces the two definitions
above rather than joining them — pasting both leaves two definitions of each name, which is its own
error. Declare it once at any type
(`GIVEN a IS A TYPE` / `GIVETH AN a`) and give it back as the answer:

```l4
@ref Transactions Levy Act s 4 — the amount is a blank in the draft
GIVEN a IS A TYPE
GIVETH AN a
`s 4 — the levy where there is no stated value, [amount to be inserted]` MEANS
    REFUSE "s 4 — the levy where there is no stated value, [amount to be inserted]"

GIVEN `the stated value` IS A MAYBE NUMBER
GIVETH AN EITHER `A problem with the return` NUMBER
`the return for a stated value of` `the stated value` MEANS
    CONSIDER `the stated value`
    WHEN NOTHING THEN `s 4 — the levy where there is no stated value, [amount to be inserted]`
    WHEN JUST v  THEN IF   v AT MOST 0
                      THEN LEFT `the stated value is not a positive amount`
                      ELSE RIGHT (v TIMES 2%)

#ASSERT REFUSED `the return is rejected for a stated value of` NOTHING BECAUSE "s 4 — the levy where there is no stated value, [amount to be inserted]"
#ASSERT `the return is rejected for a stated value of` (JUST (0 MINUS 5))
#ASSERT NOT `the return is rejected for a stated value of` (JUST 100)
```

_(`REFUSE`; checked on the `REFUSE` binary, exit 0, all three satisfied.)_ Now the decline reaches
the boundary **through** a downstream `CONSIDER`, which is the guarantee working as advertised: the
`CONSIDER` cannot see it, cannot match on it, and cannot answer instead of it.

**The same laziness at limb scale, and there it is a feature.** `FALSE AND r` answers `FALSE`
without forcing `r`; `r AND FALSE` refuses. So a limb chain whose earlier limbs already decide the
case skips a refusal further down, which is the right legal answer — [entry 1.6](01-definitions-and-scope.md#e1-6)'s 17-year-old fails on
age whether or not s 9 is encoded. Order your limbs so the ones the model can answer come first.

**Not** a `#ASSERT REFUSED` on the inner definition as proof that the caller will see it. That tests
the definition, not the path. Assert on the thing a caller actually calls.

**Not** the reading that laziness makes `REFUSE` unsafe. It makes the _placement_ load-bearing:
a refusal in return position is uncatchable exactly as advertised.

**See** [entry 11.5](#e11-5) (the shape and its `@ref`), [entry 11.6](#e11-6) (`#ASSERT REFUSED`), and the closing table,
row 7.

---

<a id="e11-9"></a>

## 11.9 Exercising a rule that reads a section `GIVEN`

**If you have written** the house-style input — a `GIVEN` indented under a `§` heading — and now
want directives that show the rule working.

**It is doing** something no directive can supply from inside the file. Supplying a section `GIVEN`
with `WITH` is proposed, not landed (2026-09-04); values come from a web form, from
`l4 batch --inputs cases.json`, or from the service request. So a `#EVAL` or `#ASSERT` that reaches an unsupplied
section `GIVEN` stops and makes `l4 run` **exit 1** — see [entry 1.5](01-definitions-and-scope.md#e1-5) for the two messages it prints and
why neither of them is about the construct it names.

**Write** two rules where you were going to write one: the operative test as an ordinary **rule
`GIVEN`**, which any case can be passed to, and the section's own rule as a one-line delegation that
reads the section `GIVEN`. Exercise the first with `#ASSERT`, and the second with `#CHECK`.

```l4
DECLARE Applicant HAS
    `age in years`                          IS A NUMBER
    `has been disqualified under section 9` IS A BOOLEAN

§ `Part 2 — Licences`
    GIVEN `the applicant` IS AN Applicant

-- The operative test, as an ordinary rule GIVEN: exercisable with any case.
@ref Licensing Act s 6(1)
GIVEN `the person` IS AN Applicant
GIVETH A BOOLEAN
`s 6(1) — a licence may be granted to` `the person` MEANS
        `the person`'s `age in years` AT LEAST 18
    AND NOT `the person`'s `has been disqualified under section 9`

-- The Part's own rule, in the Part's own words, reading the section GIVEN.
@ref Licensing Act s 6(1)
GIVETH A BOOLEAN
`s 6(1) — the applicant may be granted a licence` MEANS
    `s 6(1) — a licence may be granted to` `the applicant`

`an applicant aged 25 who is not disqualified` MEANS Applicant WITH
    `age in years`                          IS 25
    `has been disqualified under section 9` IS FALSE

#ASSERT `s 6(1) — a licence may be granted to` `an applicant aged 25 who is not disqualified`
#CHECK  `s 6(1) — the applicant may be granted a licence`
```

_(Section `GIVEN`; checked on the section-`GIVEN` binary, exit 0.)_ The `#ASSERT` prints
`assertion satisfied`; the `#CHECK` prints `BOOLEAN ` at Information severity and costs the run
nothing, because it type-checks without evaluating. **`#CHECK` is the only directive that is safe on
a rule with an unsupplied section `GIVEN`**, and it is what keeps a file in the house style runnable.

The delegation is not scaffolding you delete later. It is the same split the statute makes: a test
stated in general terms, and a Part that applies it to the person the Part is about. Both names are
worth having, and when supply lands the second becomes callable as it stands.

**Not** a `#EVAL` or `#ASSERT` on the section-`GIVEN` rule. Exit 1, and on a page under `doc/` it
fails the docs harness.

**Not** a section `GIVEN` abandoned for a rule `GIVEN` because you could not test it. The repetition
the section `GIVEN` removes is real — 62 identical lines in one corpus file ([entry 1.2](01-definitions-and-scope.md#e1-2)) — and one
extra delegating rule per section is a much smaller price.

**Not** `#CHECK … WITH x IS v`. `WITH` at a directive names a **rule's own** inputs, so it works on
the delegating rule's `GIVEN`-parameterised twin and not on the section `GIVEN`; naming a section
`GIVEN` there is a check error, not a parse error.
[Entry 1.5](01-definitions-and-scope.md#e1-5) has the detail.

**Reading the run.** `l4 run` prints everything **twice**: once as a diagnostic block, and again as
an `Evaluation[n]` block with its `Result:` and `Trace:`. A file with ninety directives produces
close to two thousand lines, and an assertion you see twice has not run twice. **`#CHECK` is the
one directive that appears in only the first half** — it produces a diagnostic at Information
severity and no `Evaluation[n]` block at all, so a file with two `#ASSERT`s and one `#CHECK` gives
three directives and **two** `Evaluation` blocks (probe `r11-illustrations-scope.l4`, exit 0). That
is correct, not a dropped directive. Grep the output for `DiagnosticSeverity_Error`, which is what
`doc/test-docs.sh` does and what the exit code will not tell you — see
[entry 11.6](#e11-6).

**See** [entry 1.2](01-definitions-and-scope.md#e1-2) (why the section `GIVEN` is the house style), [entry 1.5](01-definitions-and-scope.md#e1-5) (the two failure messages),
and the `section GIVEN` reference page (new in this release).

---

<a id="e11-10"></a>

## 11.10 "such amount as the parties may agree", "on terms to be agreed"

**If the source says** a figure the instrument does not state, because it leaves it to the parties.
The statutory form is common:

> `(a) to pay to the other party the sum which it is agreed in the contract by which the marriage was arranged is to be paid by the party in breach of the contract`
>
> — Administration of Muslim Law Act 1966 (Singapore) s 94(1)(a), in the repository at
> `jl4/examples/legal/sg-succession/cleanroom-2026-08/source/AMLA1966.txt:4166-4168`

and the contract form — "the renewal fee shall be such amount as the parties may agree", "on terms
to be agreed" — is the same words from the other side.

**It is doing** one of two completely different things, and the phrase does not tell you which.
**The question is whether the missing number is a fact about this case, or a hole in the document.**

- **The parties agreed something, and the case file either records it or does not.** Then it is an
  input, and one the boundary can perfectly well ask for. If the instrument also says what happens
  failing agreement, the absence is a `MAYBE` the rule matches — entry
  [11.3](#e11-3).
- **Nothing has been agreed and the instrument provides no fallback.** Then there is no number
  anywhere, this case or any other, and nobody can be asked. That is the undrafted clause of entry
  [11.2](#e11-2).

**Write** both, and they look nothing alike:

```l4
IMPORT prelude

DECLARE Renewal HAS
    -- What the parties agreed is a fact about THIS contract, so the boundary
    -- asks for it. MAYBE, because clause 7.4 says what follows if they did not.
    `the sum agreed by the parties` IS A MAYBE NUMBER

-- 7.3 The renewal fee shall be such amount as the parties may agree.
-- 7.4 Failing agreement, the renewal fee is the fee for the preceding year.
GIVEN r IS A Renewal
GIVETH A NUMBER
`clause 7.4 — the renewal fee` r MEANS
    CONSIDER r's `the sum agreed by the parties`
    WHEN JUST s  THEN s
    WHEN NOTHING THEN `the fee for the preceding year`

`the fee for the preceding year` MEANS 800

-- 9.1 The commission shall be on terms to be agreed. No terms, no fallback:
-- a hole in the DOCUMENT, which nobody can be asked to fill.
GIVETH A NUMBER
`clause 9.1 — the commission is on terms to be agreed` MEANS
    REFUSE "clause 9.1 — the commission is on terms to be agreed"
```

_(`REFUSE`; checked on the release binary, exit 0, no errors.)_ Three assertions are satisfied over
it: the agreed sum is returned, the unagreed one falls back to 800, and
`` #ASSERT REFUSED `clause 9.1 — the commission is on terms to be agreed` `` passes.

**Not** a refusal for the first case. It is the row-3-as-row-7 mistake the table below is ordered to
prevent, and the cost is concrete: a refusal is uncatchable, so the instrument's **own** fallback
clause cannot reach past it. Write the agreed sum as a refusal and clause 7.4 stops working —

```l4
GIVETH A NUMBER
`the sum agreed by the parties` MEANS
    REFUSE "the parties have not told us what sum they agreed"

`the fee for the preceding year` MEANS 800

GIVETH A NUMBER
`clause 7.4 — the renewal fee` MEANS
    IF   `the sum agreed by the parties` GREATER THAN 0
    THEN `the sum agreed by the parties`
    ELSE `the fee for the preceding year`

#EVAL `clause 7.4 — the renewal fee`
```

— and `` #EVAL `clause 7.4 — the renewal fee` `` answers, instead of 800:

```text
The model refuses to answer:
  the parties have not told us what sum they agreed
```

The `IF` cannot see the refusal, so the `ELSE` limb the parties actually agreed to never runs. That
is the general shape of the mistake: **if a later clause of the instrument is meant to rescue the
gap, the gap is not a refusal.**

**Not** `TBD` for the second case in anything a counterparty will read. `TBD` is the right mark for a
single blank in a draft you are finishing in the same sitting; the moment there are two, the output
names neither. Entry [11.2](#e11-2) measures both and says where the line is.

**Not** zero. A renewal fee that silently prices an unagreed term at nothing is the one outcome
neither party would have signed.

**See** entry [11.2](#e11-2), entry [11.3](#e11-3), and the table below — this entry is rows 1, 3 and
7, told apart by a single question.

---

<a id="e11-questions"></a>

## The questions to ask, in order

When a rule cannot produce an ordinary value, work down this list and stop at the first `yes`. The
order matters: the expensive mistakes are all a case answered by a later row being written as an
earlier one.

| #   | Ask                                                                                        | If yes, write                                                                           | Who handles it                      | Can a later rule catch it? |
| --- | ------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------- | ----------------------------------- | -------------------------- |
| 1   | Does the source itself contemplate the thing being absent — "if any", "where there is no"? | `MAYBE`, matched with `CONSIDER`                                                        | the rule, by matching               | yes, as a value            |
| 2   | Is the **input** invalid — a negative count, a month of 13, a self-contradicting form?     | `EITHER`, with a named problem on the left                                              | the rule or its caller              | yes, as a value            |
| 3   | Is it simply a fact **nobody has told us yet**?                                            | an input: a record parameter or section `GIVEN`                                         | the boundary, by asking             | not applicable             |
| 4   | Does the **law** say it does not apply, or was not yet in force?                           | an ordinary value, or a gate consulted first                                            | savings and transitional provisions | yes                        |
| 5   | Is it a **duty that was not performed**?                                                   | `LEST` on the obligation                                                                | the obligation's own branch         | structured                 |
| 6   | Is the conclusion **overridden** by another provision?                                     | arm order, or `UNLESS` naming the overriding rule (`SUBJECT TO` is not a keyword today) | the overriding rule                 | structured                 |
| 7   | Does **the model** not cover this — the encoder declining, not the law?                    | `REFUSE "…"` (`TBD` if the reason is "not written yet")                                 | the boundary only                   | **no**                     |

Row 7 is the only one nothing downstream can catch, and that is what it is for: an absent value can
be quietly defaulted by a later rule, a refusal cannot — **provided something forces it**, which is
a question about where you put the `REFUSE` and is settled in [entry 11.8](#e11-8). Rows 4 and 7 are the pair
that gets confused, and the test between them is whose sentence it is — the law's, or yours.

Three tests worth having to hand while you work down the table, each the answer to a question the
rows above do not settle on their own:

| when you are unsure                           | ask                                                                      | it is in                                           |
| --------------------------------------------- | ------------------------------------------------------------------------ | -------------------------------------------------- |
| a delegated power, unexercised (rows 4 vs 7)  | does the section supply its own fallback?                                | [entry 11.1](#e11-1)                               |
| a cross-reference outside your slice          | can a caller answer it without running the missing rule?                 | [entry 1.6](01-definitions-and-scope.md#e1-6)      |
| a statutory `may` — deontic, or a plain test? | who is permitted to do what? if nobody is named, it is a boolean test    | [entry 5.1](05-duties-powers-consequences.md#e5-1) |
| an amount left to the parties to agree        | is the missing number a fact about this case, or a hole in the document? | [entry 11.10](#e11-10)                             |
