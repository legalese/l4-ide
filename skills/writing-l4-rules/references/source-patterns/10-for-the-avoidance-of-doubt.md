# 10. "For the avoidance of doubt"

One area of the phrasebook. The index, the preamble and the other ten areas are in
[source-patterns.md](../source-patterns.md).

**The mapping for this whole area: a clause that says "for the avoidance of doubt" is an assertion
test case.** It states an outcome the rules are supposed to yield already. So write it as `#ASSERT`
(or `#ASSERT NOT`) over the rules you have, with the clause cited above it, and run the file.

Then read what happened, because the run is the point:

| the assertion          | what the clause turned out to be     | what to do                                                        |
| ---------------------- | ------------------------------------ | ----------------------------------------------------------------- |
| satisfied              | genuinely declaratory                | keep it; it is now a regression test on the clause it cites       |
| failed                 | **operative** — it changes a rule    | encode the change, and keep the assertion as that change's test   |
| could not be evaluated | reaching a fact you take as an input | restructure so the operative test has its own inputs — entry 10.5 |

**Read the diagnostics, not the exit code.** A failing `#ASSERT` is reported at
`DiagnosticSeverity_Error` and `l4 run` still **exits 0** (measured, probe `a2-operative.l4`). A
model that runs `l4 run f.l4 && echo green` will call a file with a failing assertion green and
never learn that its declaratory clause was operative. Grep the output for
`DiagnosticSeverity_Error`, which is what `doc/test-docs.sh` does.

**Directives are one line.** `#ASSERT` continued onto a second line beginning `EQUALS` is a parse
error. (`#ASSERT REFUSED e BECAUSE "…"` and `#TRACE … WITH` are the exceptions.) An assertion whose
subject is long wants a named case value above it, not a line break.

<a id="e10-1"></a>

## 10.1 "For the avoidance of doubt, X" — the declaratory case

**If the source says**

> "For the avoidance of doubt, a Direct Listing will not be deemed to be an underwritten offering
> and will not involve any underwriting services."
>
> — the definition of "Direct Listing" in a post-money Simple Agreement for Future Equity, carried
> in this repository at `jl4/experiments/safe-post.l4:296`. Its own header records the instrument
> as `SAFE (Post-Money)`, jurisdiction Singapore, version 1.2 (`:7-11`); the file names no
> publisher, so do not attribute one.

**It is doing** nothing to the rule. A declaratory clause exists because someone in negotiation
worried that the operative words might be read the other way. It settles the reading; it does not
change it. The test of whether that is true is mechanical, and you have the machine.

**Write** the assertion, with the clause it comes from cited above it and a named case value so the
directive stays on one line.

```l4
@ref Charitable Fundraising Act s 4(1)
GIVEN a IS AN Applicant
GIVETH A BOOLEAN
DECIDE `eligible to register` a IF
        a's `aged 18 or over`
    AND a's `resident in Singapore`

`the adult visitor` MEANS
    Applicant WITH `aged 18 or over`                  IS TRUE
                 , `resident in Singapore`            IS FALSE
                 , `months of residence in Singapore` IS 0

-- s 4(3): "For the avoidance of doubt, a person who is aged 18 or over but is
-- not resident in Singapore is not eligible to register." Declaratory: s 4(1)
-- already yields it. Recorded as the test it is.
@ref Charitable Fundraising Act s 4(3)
#ASSERT NOT `eligible to register` `the adult visitor`
```

(Probe `a1-declaratory.l4`, exit 0, `assertion satisfied`.) The `@ref` on the directive is what makes
it a record rather than a spot check: a later editor who weakens s 4(1) sees exactly which clause of
the Act broke.

**Not** a second rule. The reflex is to encode every sentence that looks like law, and the sentence
does look like law. Restating s 4(3) as another `DECIDE` of the same name does not even get past the
type checker (probe `a7-duplicate-rule.l4`, exit 1):

```
There are multiple definitions for the identifier

  `eligible to register`

and I do not have sufficient information to make a choice between them.
The options are:

  `eligible to register` (defined at a7-duplicate-rule.l4:18:8-30) of type FUNCTION FROM Applicant TO BOOLEAN
  `eligible to register` (defined at a7-duplicate-rule.l4:10:8-30) of type FUNCTION FROM Applicant TO BOOLEAN
```

Renaming it out of the clash is worse, not better: you then have two rules that must agree forever,
and nothing checks that they do.

**Not** a new field on the record. "Is not eligible despite being 18" is a conclusion, not a fact
about the applicant, and a field would let a caller assert it directly.

**See** [drafting-patterns.md](../drafting-patterns.md),
`When the source supplies no label, DECOMPOSE`, for when a sentence _does_ deserve its own
definition.

<a id="e10-2"></a>

## 10.2 The same clause, when the assertion fails

**If the source says** the same words — "For the avoidance of doubt, a person who has been resident
in Singapore for less than 6 months is not eligible to register" — over rules that carry no
six-month test.

**It is doing** legislating, whatever it says it is doing. Draftsmen put substance behind "for the
avoidance of doubt" more often than they will admit, and the label is not evidence. This is why the
mapping is an assertion and not a comment: the assertion is what tells you which kind you have.

**Write** the assertion first, exactly as in 10.1, and run it. Probe `a2-operative.l4` reports

```
  Severity: DiagnosticSeverity_Error
  Message:  assertion failed
```

and exits **0**. The clause is operative: it adds a limb section 4(1) does not have.

Now encode the limb and keep the assertion as its test. Label the new limb with the subsection it
came from, so the rule shows on its face that it is the union of two provisions, and add the
boundary case the failing assertion did not cover.

```l4
-- s 4(4) is OPERATIVE: it adds a limb s 4(1) does not have. It goes in the
-- rule, and the assertion below stays as its test.
@ref Charitable Fundraising Act s 4(1), s 4(4)
GIVEN a IS AN Applicant
GIVETH A BOOLEAN
DECIDE `eligible to register` a IF
        a's `aged 18 or over`
    AND a's `resident in Singapore`
    AND "(4)" ... a's `months of residence in Singapore` AT LEAST 6

@ref Charitable Fundraising Act s 4(4)
#ASSERT NOT `eligible to register` `the recent arrival`
#ASSERT     `eligible to register` `the settled resident`
```

(Probe `a3-repaired.l4`, exit 0, both assertions satisfied.) `the settled resident` has exactly 6
months, which is the boundary the source draws with "less than". `ABOVE` is strict and `AT LEAST` is
not — `6 ABOVE 6` is `FALSE`, `6 AT LEAST 6` is `TRUE` (probe `i12-above.l4`) — so the second
assertion is the one that catches the off-by-one.

**Not** the other repair — weakening the assertion until it passes, or deleting it.
The failing assertion is the finding. It is the one moment the encoding tells you that a clause
everyone treated as a clarification moves an outcome, and that is worth more to the client than the
encoding is.

**Not** an automatic conclusion that the clause is operative, either. An assertion can fail because
your rule is wrong. Check the rule against the source before you widen it:
if s 4(1) should have carried the six-month test all along, the fix is a bug fix, and s 4(4) really
was declaratory.

**See** [11-when-the-encoding-cannot-answer.md](11-when-the-encoding-cannot-answer.md#e11-6) for
what a failing assertion looks like when the expression refuses instead of returning a value —
`assertion refused:` rather than `assertion failed`, and a different repair.

<a id="e10-3"></a>

## 10.3 "Nothing in this clause prevents …", "Nothing in this Act shall affect …"

**If the source says**

> "Nothing in this section shall be construed so as to prevent the Public Trustee from applying for
> or being granted letters of administration of the estate of a deceased person with or without the
> will annexed before the expiration of a period of 6 months of the death of the deceased."
>
> — Probate and Administration Act 1934 s 55(2), at
> `jl4/examples/legal/sg-succession/cleanroom-2026-08/probate-administration-act.l4:2465`

or, in a contract, "Nothing in this clause prevents the Company from terminating immediately for
material breach."

**It is doing** asserting an **invariance**: some other right survives whatever this clause does.

**Ask first whether the right it preserves is in your model at all**, because the answer decides
which area you are in. The corpus took the other fork on s 55(2). The six-month periods it protects
against _are_ encoded — s 55(1)(a), (b) and (f), at `…/probate-administration-act.l4:2308` and
`:2453-2463`. What is not encoded is the right the saving preserves: the Public Trustee's power to
apply sooner, which comes from some other provision. With no encoded rule for the invariance to be a
property _of_, the saving "confers nothing, … has no operative encoding and is carried inert"
(`…/probate-administration-act.l4:2466-2469`). If that is your case, this is an
[area 9](09-text-that-is-not-a-rule.md) job — carry the words as a named inert string with its
`@ref`, and stop. What follows is for when the preserved right **is** encoded beside the clause,
and the invariance is therefore a claim your file can be made to check.

The corpus's statutory witness for that fork is British Nationality Act 1981 s 1(6), where
citizenship acquired under subsection (5) survives the adoption order later ceasing to have effect.
The encoder's note states the technique exactly: "Encoded by deliberately NOT reading the cesser
field — the predicate below equals `a British citizen by virtue of subsection (5)` whatever the
cesser flag says, and the tests assert exactly that" (`jl4/examples/legal/bna/bna.l4:564-568`).

**Write** the surviving right as a rule that does not read the field the other clause turns on, and
assert that it answers the same way whichever way that field goes.

```l4
-- cl 11.4: "Nothing in this clause prevents the Company from terminating
-- immediately for material breach." An INVARIANCE. Encoded by deliberately
-- NOT reading `the notice period has expired` -- the predicate below gives
-- the same answer whatever that field says, and the assertions say so.
@ref Consultancy Agreement cl 11.4
GIVEN e IS AN Engagement
GIVETH A BOOLEAN
DECIDE `the Company may terminate for material breach` e IF
    "11.4" ... e's `the Consultant is in material breach`

#ASSERT `the Company may terminate for material breach` `in breach, notice period running`
#ASSERT `the Company may terminate for material breach` `in breach, notice period expired`
#ASSERT NOT `the Company may terminate on notice` `in breach, notice period running`
```

(Probe `a4-invariance.l4`, exit 0, all three satisfied.) The first two assertions are the invariance:
same answer, both settings of the field. The third is what makes them mean something — it shows the
field does move the _other_ rule, so the invariance is a property of this one rather than of a field
nothing reads.

**Not** an exception carved into the clause it protects. "Nothing in this clause prevents X" does not
add a condition to the notice rule; it says X was never inside the notice rule's territory. Writing
``DECIDE `may terminate on notice` … IF NOT `in material breach` …`` inverts it, and would tell the
Company it loses its notice right the moment breach appears.

**Not** left implicit because "the other rule obviously still applies". Obvious to you today is not
obvious to whoever edits the notice rule next quarter. The pair of assertions is the guardrail.

<a id="e10-4"></a>

## 10.4 "It is declared that …", "This clause is without prejudice to clause 12"

**If the source says**

> "Without prejudice to subsection (2), the following shall be treated as properly executed:"
>
> — Wills Act 1838 s 5(3), carried as the chapeau of both halves of the encoding at
> `jl4/examples/legal/sg-succession/cleanroom-2026-08/wills-act.l4:911` and `:930`

or, in a contract, "It is hereby declared that a payment made under protest does not waive any
claim", or "The remedies in this clause are without prejudice to any other remedy available at law."

**It is doing** the same job as 10.1 by other words. The Wills Act encoder wrote down what the
phrase resolved to, in a comment above the rule (`…/wills-act.l4:900-902`):

```
-- "Without prejudice to subsection (2)": both halves stand whether or not any
-- limb of s 5(2) is made out. So s 5(3) is a disjunction BESIDE s 5(2), never a
-- qualification of it.
```

_Beside, never a qualification of_ — that is the proposition, and it is exactly what a pair of
assertions can hold in place.

Two wrinkles are worth pausing on.

- **"It is declared that"** in a statute is sometimes retrospective, declaring what the law "always
  was". A declaration that changes an answer for a past date is not declaratory at all; it is an
  amendment with a backdated commencement, and it belongs with the temporal machinery in area 4.
  Ask: does this move an outcome for a date before the clause was enacted? If yes, it is not this
  entry.
- **"Without prejudice to clause 12"** is the operative half of the phrase that entry
  [9.6](09-text-that-is-not-a-rule.md#e9-6) treats as inert. There, the phrase opened a provision
  and merely declined to cut down another. Here it closes one and preserves a cumulative right — the
  clause lists remedies and says the list is not exhaustive. That is a real proposition, and it is
  testable in the same way.

**Write** a pair of assertions: the fact that triggers the other route, asserted against **both**
rules, so the file records that neither swallows the other.

```l4
#ASSERT NOT `the Registrar may cancel under section 18` `the deceptive registration`
#ASSERT     `the Registrar may cancel under section 12` `the deceptive registration`
```

(Probe `i6-without-prejudice.l4`, exit 0, both satisfied. The rules and the case value are in entry
[9.6](09-text-that-is-not-a-rule.md#e9-6).) Where the source says the remedies are cumulative rather
than alternative, add the case where **both** are available and assert both — that is the sentence,
written down.

**Not** a `NOT` linking the two rules. Making one route conditional on the other failing is the
misreading measured in 9.6: it type-checks, it runs clean, and it answers `FALSE` where the law gives
the party the right twice over.

**Not** silence because the clause "adds nothing". If it adds nothing, the assertions pass and cost
you three lines. If it adds something, you have just found it.

<a id="e10-5"></a>

## 10.5 When the clause is about a fact you take as an input

**If the source says** "For the avoidance of doubt, an appeal soliciting exactly the prescribed
threshold must be registered" — where "the prescribed threshold" is a figure the encoding asks the
caller for rather than one it knows.

**It is doing** fixing a **boundary**: at, not above. That is the class of clause most worth testing
and, in the house style, the one you most often cannot test as written — because no directive inside
the file can supply a section `GIVEN`.

The assertion does not fail. It cannot run (probe `a5-input-blocked.l4`, exit 1):

```
assertion could not be evaluated:
I could not continue evaluating, because I needed to know the value of
  `the prescribed threshold`
but it is an assumed term.
```

**Write** the operative test as a rule with its **own** `GIVEN` parameters, and a one-line rule above
it that reads the section `GIVEN` and delegates. The application calls the delegating rule; the
assertions exercise the operative one.

```l4
§ `Charitable Fundraising Act s 9`
    GIVEN `the prescribed threshold` IS A NUMBER

-- The operative test, with the threshold as its own rule GIVEN, so a
-- directive can supply it.
@ref Charitable Fundraising Act s 9(1)
GIVEN `the amount solicited` IS A NUMBER
      threshold              IS A NUMBER
GIVETH A BOOLEAN
DECIDE `registration is required at` `the amount solicited` threshold IF
    `the amount solicited` AT LEAST threshold

-- The reader the application calls: the section GIVEN arrives from outside.
@ref Charitable Fundraising Act s 9(1)
GIVEN `the amount solicited` IS A NUMBER
GIVETH A BOOLEAN
DECIDE `the appeal must be registered` `the amount solicited` IF
    `registration is required at` `the amount solicited` `the prescribed threshold`

@ref Charitable Fundraising Act s 9(3)
#ASSERT `registration is required at` 50000 50000
#ASSERT NOT `registration is required at` 49999 50000

#CHECK `the appeal must be registered`
```

(Probe `a6-input-repaired.l4`, exit 0. `#CHECK` reports
`FUNCTION FROM NUMBER TO BOOLEAN` at information severity and, crucially, does **not** force the
section `GIVEN` — which is the only reason the delegating rule can be exercised at all in a file that
must exit 0.)

The clause said "exactly the threshold", so the pair is `50000` against `50000` and `49999` against
`50000`. One assertion on its own does not pin a boundary.

**Not** a `WITH` that supplies the section `GIVEN` at the directive. _Proposed, not landed
(2026-09-04)_ — it lands with the discharge change. Today `WITH` names only a rule's **own** inputs,
and both spellings a model reaches for are errors. With a positional value in front of it, the
parser stops (probe `a8-with-positional.l4`, exit 1):

```
11 | #ASSERT `the appeal must be registered` 50000 WITH `the prescribed threshold` IS 50000
   |                                               ^^^^
unexpected WITH
```

Without one, it parses and the type checker reports two things — the rule's real input unsupplied,
and the name you tried to bind undefined (probe `a9-with-named.l4`, exit 1):

```
In the application of

  `the appeal must be registered` (defined at a9-with-named.l4:8:8-39)

you forgot to supply the following arguments:

  `the amount solicited` of type NUMBER
```

```
I could not find a definition for the identifier

  `the prescribed threshold`
```

Until discharge lands, values for section `GIVEN`s come from outside the file: a web form,
`l4 batch FILE --inputs cases.json`, or the service request.

**Not** an arbitrary constant substituted into the rule so the assertion runs. That silently answers
a different question — one where the threshold is fixed — and the file will keep passing after the
regulation changes it.

**See** [11-when-the-encoding-cannot-answer.md](11-when-the-encoding-cannot-answer.md#e11-9),
"Exercising a rule that reads a section `GIVEN`", for the same delegation pattern in full, and
[01-definitions-and-scope.md](01-definitions-and-scope.md#e1-2) for when a role belongs on the
section heading in the first place.
