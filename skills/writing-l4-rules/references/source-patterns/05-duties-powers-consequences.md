# 5. Duties, powers and consequences

One area of the phrasebook. The index, the preamble and the other ten areas are in
[source-patterns.md](../source-patterns.md).

<a id="e5-1"></a>

## 5.1 "may be granted", "may be made", "may be revoked" — the passive `may`

**If the source says**

> `-- "8.--(1) Probate may be granted to any executor appointed by a will."`
>
> — `jl4/examples/legal/sg-succession/sg-paa.l4:432`, encoded at `:450` as
> `` `probate may be granted to` p MEANS … ``, a `GIVETH A BOOLEAN`.

**It is doing** stating an **eligibility test**, not conferring a permission. Read who holds the
permission: in "the applicant may be granted a licence", the applicant is the grammatical subject
but the _object_ of the granting. Whatever discretion there is belongs to the Registrar, and the
sentence in front of you is about whether this applicant is inside the class the Registrar may
grant to. The same is true of "an order may be made", "a caveat may be entered", "registration may
be revoked".

**Write** a `GIVETH A BOOLEAN` decision, in the source's own words, with no deontic in it. The
corpus does this twice over: `` `probate may be granted to` `` above, and
`` `registration may be granted` person … `` (`jl4/examples/legal/bna/bna.l4:461`).

```l4
-- 6.—(1) The applicant may be granted a licence if the applicant is 18 years
--        of age or older and has not been disqualified under section 9.
@ref Licensing Act s 6(1)
GIVEN `the person` IS AN Applicant
GIVETH A BOOLEAN
`s 6(1) — a licence may be granted to` `the person` MEANS
        `the person`'s `age in years` AT LEAST 18
    AND NOT `the person`'s `has been disqualified under section 9`
```

_(Neither feature; checked on the section-`GIVEN` binary, exit 0.)_

**Reach for `MAY` only where the section goes on to say what the office-holder may do**, and then
the `PARTY` is that office-holder — never the person the passive put in front:

```l4
@ref Licensing Act s 6(1)
GIVEN `the person` IS AN Applicant
GIVETH A DEONTIC `A party under this Part` `An act under this Part`
`s 6(1) — the Registrar may grant a licence to` `the person` MEANS
    IF   `s 6(1) — a licence may be granted to` `the person`
    THEN PARTY  `the Registrar of Licences`
         MAY    `grant a licence to the applicant`
         WITHIN 30
    ELSE FULFILLED
```

`GIVETH A DEONTIC` takes two **type** names, and both may be backticked multi-word names, as here.

**Not** `PARTY the-applicant MAY be-granted-a-licence`, which is what the mechanical rule
"statutory _may_ → `MAY`" produces on this sentence. It puts the permission in the wrong party's
hands, and it turns a constitutive test — the thing every later section will want to consult as a
boolean — into a deontic that cannot be `EQUALS`-compared and has to be exercised with `#TRACE`.

**The tell.** Ask _who is permitted to do what_. If the answer is "nobody in this sentence — it says
when a thing is permissible", it is a boolean. Active voice with a named actor ("the Registrar may
refuse an application", "the tenant may terminate") is the real permission.

**See** [regulative.md](../regulative.md) for `MUST`/`MAY` polarity, and
[drafting-patterns.md](../drafting-patterns.md), "Mandatory vs discretionary", whose Part I / Part II
examples are both _active_ — "the court shall make an order" / "the court may make an order" — which
is why they do not raise this trap and this entry does.

---

<a id="e5-2"></a>

## 5.2 "shall", "must" — the duty, and the "must" that is only a condition

**If the source says**

> `"Upon the grant of any probate or letters of administration, the grantee shall take an oath in the prescribed form, faithfully to administer the estate and to account for the same."`
>
> — Probate and Administration Act 1934 s 28(1), quoted at
> `jl4/examples/legal/sg-succession/cleanroom-2026-08/probate-administration-act.l4:2715`

**It is doing** one of two quite different jobs, and the whole encoding turns on which. Either it
**imposes a duty** — there is a party who owes it, an act they owe, and an omission that is a wrong
— or it states a **condition** that some other rule consults, in which case the sentence has no
addressee and nothing turns on omission. The corpus states the test from the duty's side at
`probate-administration-act.l4:2683-2687`: "the difference between 'shall' and 'may' is the only
thing some of them decide. A constitutive predicate cannot carry that difference: it is TRUE or
FALSE either way." Read that backwards for the other case: where nothing turns on the difference, a
predicate carries everything the sentence decides.

**Three questions, in order.** Does the sentence name a **party**? Does it name an **act** that
party performs? Would **omitting** the act have a consequence this encoding is meant to produce?
Three yeses is a duty; anything else is a boolean. The corpus records a "no" at each of the first
and third. On the first, `jl4/examples/legal/ny-environmental-7.3.l4:211-213`: "The following two
functions are implemented as passive evaluations as no actor is defined in the text. It might be an
implied obligation of the commission to act, but it is not written as such." On the third,
§ 227.100(a)(4) — "The issuer complies with the requirements in section 4A(b) of the Securities Act
… and the related requirements in this part"
(`jl4/examples/legal/regcf/denovo/source/part227.txt:120`) — is a duty imposed by another statute,
but _here_ it is a condition of an exemption, so the encoding reads it off a record as a `BOOLEAN`
field (`regcf-denovo.l4:1535-1536`, over the field declared at `:832`) and it is no obligation at
all.

**Write** the duty as the five-keyword rule, and the condition as an ordinary predicate. Both of
these are one file:

```l4
-- (a) A DUTY: a named party, a named act, and an omission that is a breach.
@ref Probate and Administration Act 1934 s 28(1)
GIVETH A DEONTIC `A party under this Part` `An act under this Part`
`s 28(1) — the grantee shall take an oath` MEANS
    PARTY `the grantee`
    MUST  `take an oath in the prescribed form`
    HENCE FULFILLED

-- (b) NOT A DUTY: "no grant shall be made unless the applicant has attained
--     21 years of age" names no actor and no act -- it is a CONDITION on a
--     later rule, so it is a BOOLEAN.
@ref Probate and Administration Act 1934 s 6(2)
GIVEN `the applicant's age in years` IS A NUMBER
GIVETH A BOOLEAN
`s 6(2) — a grant may be made to the applicant` `the applicant's age in years` MEANS
    `the applicant's age in years` AT LEAST 21
```

_(Probe `d01-shall-duty.l4`, exit 0, no errors. `PARTY`, `MUST` and the act name are the only
required parts; `WITHIN`, `HENCE` and `LEST` all default — see [regulative.md](../regulative.md).)_

**Not** a duty for the sake of fidelity to the word "shall". Everything downstream gets harder: an
obligation is a `DEONTIC` value, and a `DEONTIC` cannot be `EQUALS`-compared, so the assertion you
reach for does not run —

```
assertion could not be evaluated:
Trying to check equality on types that do not support it
These were the values you tried to compare:
  PARTY `the grantee` MUST `take an oath in the prescribed form` HENCE FULFILLED
  FULFILLED
```

at Error severity, exit 1 (probe `d01b-anti-deontic-equals.l4`). Duties are exercised with `#TRACE`,
not asserted; a condition wrongly promoted to a duty takes its own assertions with it. This is not a
general warning about structured values: records, `LIST`s and `EITHER` values all compare fine, and
the only other thing that draws the same diagnostic is a function value, printed as `<function>`
(measured 2026-09-05, probe `v-equals-types.l4`).

**See** [regulative.md](../regulative.md), "The five-keyword skeleton" and the `HENCE`/`LEST` default
table, and [drafting-patterns.md](../drafting-patterns.md), "Exercising a DEONTIC", for the
assert-the-boolean, trace-the-deontic division of labour.

---

<a id="e5-3"></a>

## 5.3 "must not", "shall not", "no person shall" — the prohibition

**If the source says**

> `@ref § 227.206(a) last sentence — "No solicitation or acceptance of money or other consideration ... is permitted until the offering statement is filed"`
>
> — `jl4/examples/legal/regcf/denovo/regcf-denovo.l4:2076`, encoded at `:2078-2082`

**It is doing** forbidding an act, which is not the same as obliging an omission: for a prohibition,
**doing the act is the failure**, and the deadline passing quietly is the good outcome. `SHANT`
carries that polarity. `MUST NOT` is accepted and behaves identically (probe `d02c-mustnot.l4`: the
same event produces the same breach record under both spellings). A residual prints either of them
back as `MUST NOT`.

**Write** `SHANT`, with the offence-creating words in the `BECAUSE` string, and — this is the part
that goes wrong — **no `WITHIN` unless the source states a period**:

```l4
-- UNDEADLINED: the rule states no period, so the prohibition holds for the
-- life of the contract.
@ref 17 CFR 227.204(a)(1)
GIVETH A DEONTIC `Reg CF party` `Reg CF act`
`the issuer must not advertise the terms of the offering` MEANS
    PARTY `the issuer`
    SHANT `advertise the terms of the offering`
    HENCE FULFILLED
    LEST  BREACH BY `the issuer`
          BECAUSE "§ 227.204(a)(1): the terms of the offering were advertised"
```

_(Probe `d02-shant.l4`, exit 0. Advertising at 400 gives `DEONTIC BREACHED` with that reason. With
no event at all the trace prints the standing prohibition back, `PARTY … MUST NOT … HENCE FULFILLED
LEST (BREACH …)` — probe `d02b-shant-noevent.l4`.)_

**Not** a `WITHIN` borrowed from a neighbouring rule. **`SHANT … WITHIN n` sunsets at `n`**: after
the deadline the prohibition is spent and the act is free. The same file, same events, with
`WITHIN 365` added and the act at 400, returns `FULFILLED` (probe `d02-shant.l4`, second trace).
This is not hypothetical — `jl4/examples/legal/regcf/regcf.l4:653-656` records it as a defect that
shipped and was removed, in the encoder's own words:

```text
`SHANT ... WITHIN n` SUNSETS at n, so the borrowed deadline made
the prohibition expire after a year and an issuer advertising on day 400
evaluated to FULFILLED. Removed 2026-07-28. An unqualified SHANT holds for
the life of the contract, which is what the rule says.
```

**Not** a boolean `` `the issuer did not advertise` `` either, where the source creates an offence or
a contractual default: a prohibition that nobody can breach produces no breach record, and the
`BECAUSE` string is the only part of the encoding an auditor reads.

**See** [regulative.md](../regulative.md), "Deontic modals" for the keyword and "`HENCE` and `LEST`
— the success and failure paths", whose table is where the polarity actually lives, and "`WITHIN` —
deadlines"; entry [4.3](04-dates-and-periods.md#e4-3) for the unit the number does not carry; and
entry [5.7](#e5-7) for what to do with the penalty the prohibition attracts.

---

<a id="e5-4"></a>

## 5.4 "the court may", "the tenant may terminate" — the active permission

**If the source says**

> `"the LEST arm is therefore a PERMISSION and not a penalty — s 55(1) says letters "may be granted to the Public Trustee" — so it is a MAY, and an unexercised MAY collapses to FULFILLED rather than to a breach"`
>
> — the encoding's note at
> `jl4/examples/legal/sg-succession/cleanroom-2026-08/probate-administration-act.l4:2751-2754`, on
> Probate and Administration Act 1934 s 55(1)(c)

**It is doing** conferring a power on a **named actor** — the mark of the real permission, and what
separates this from the passive "may be granted" of entry [5.1](#e5-1). Not exercising it is not a
wrong, so an unexercised `MAY` is `FULFILLED`, not a breach. That is the whole content of
"discretionary": the contrast the corpus draws at `probate-administration-act.l4:2782-2785` is
between s 18(1) and s 25(2), which are permissive, and s 27, "the one place in this Act where a
further grant is compelled."

**Write** `MAY`, with the office-holder as the `PARTY`:

```l4
@ref Probate and Administration Act 1934 s 55(1)(c)
GIVETH A DEONTIC `A party under this Act` `An act under this Act`
`s 55(1) — letters of administration may be granted to the Public Trustee` MEANS
    PARTY  `the court`
    MAY    `grant letters of administration with or without the will annexed to the Public Trustee`
    WITHIN 30
```

_(Probe `d03-may.l4`, exit 0. Two traces: the court grants at 10 → `FULFILLED`; the court never
acts and the clock is advanced past the deadline with ``(`WAIT UNTIL` 31)`` → `FULFILLED`. A
permission cannot be breached by not using it.)_

**Not** `MUST`, on the theory that a court told it "may" act will act. The identical rule written
`MUST`, on the identical events, breaches:

```
DEONTIC BREACHED:
  party
    NEVERMATCHESPARTY
  who did action
    NEVERMATCHESACT
  at
    31
  surpassed the deadline of party
    `the court`
  who had to do obligatory action
    MUST `grant letters of administration with or without the will annexed to the Public Trustee`
  before their deadline, which was at
    30
```

(probe `d03b-may-as-must.l4`, exit 0 — a breach in a trace is a **result**, not an error, so nothing
in the exit code tells you the modality is wrong). `NEVERMATCHESPARTY` and `NEVERMATCHESACT` are the
sentinels for "the deadline expired and nothing matched"; read them as "nobody did it".

**See** [drafting-patterns.md](../drafting-patterns.md), "Mandatory vs discretionary", whose Part I /
Part II housing-possession pair is the same contrast in one statute; [regulative.md](../regulative.md)
for the `HENCE`/`LEST` defaults that make a `MAY` benign; entry [5.1](#e5-1) for the passive "may",
which is not this.

---

<a id="e5-5"></a>

## 5.5 "is entitled to", "is not required to", "it shall not be necessary"

**If the source says**

> `DECIDE \`entitled to be registered under subsection (4)\` person IF …`
>
> — `jl4/examples/legal/bna/bna.l4:433`, on British Nationality Act 1981 s 1(4); and, for the
> negative, `` `s 64(1) — it shall not be necessary for the Public Trustee to give notice of his
intention to distribute the estate` `` at
> `jl4/examples/legal/sg-succession/cleanroom-2026-08/probate-administration-act.l4:2677`

**It is doing** stating a **status**, not conferring a power. "Is entitled to" says the applicant is
inside a class; whatever the office-holder then does about it is a separate provision. "Is not
required to" and "it shall not be necessary" say a duty **does not arise** — which is a fact about
the world, not a permission to omit. Both are booleans. The corpus is explicit about keeping them
apart: `bna.l4:24-27` encodes subsections (3), (3A) and (4) as "BOOLEAN entitlement predicates …
with the s 41A good-character restriction as a separate grant-gate predicate, not folded into the
s 1 entitlements."

**Write** the entitlement as one predicate and the gate on acting upon it as another, so a reader
can see which provision each belongs to:

```l4
-- (a) THE ENTITLEMENT. A right is a BOOLEAN test, not a permission.
@ref British Nationality Act 1981 s 1(4)
GIVEN person IS A PersonProfile
GIVETH A BOOLEAN
DECIDE `entitled to be registered under subsection (4)` person IF
        person's `born in the United Kingdom after commencement`
    AND person's `the first ten years of that person's life`

-- (c) "it shall not be necessary to ..." -- a negative duty is also a BOOLEAN:
--     the duty simply does not arise.
@ref Probate and Administration Act 1934 s 64(1)
GIVEN `the total value of the property administered by the Public Trustee` IS A NUMBER
GIVETH A BOOLEAN
`s 64(1) — it shall not be necessary to give notice of intention to distribute`
        `the total value of the property administered by the Public Trustee` MEANS
    `the total value of the property administered by the Public Trustee` AT MOST 10_000
```

_(Probe `d04-entitled.l4`, exit 0, three assertions satisfied. The middle predicate, the s 41A
grant gate, takes the entitlement as an ordinary `BOOLEAN` parameter and conjoins the character
requirement — the shape at `bna.l4:458-463`.)_

**Not** an entitlement written as the holder's permission. `` PARTY `the applicant` MAY `be
registered as a British citizen` `` is the wrong party (entry [5.1](#e5-1)) and it also takes the
predicate out of reach of the assertions that prove it:

```
An ASSERT directive is expected to be of type

  BOOLEAN

but is here of type

  DEONTIC OF Applicant, `An act under this Act`
```

exit 1 (probe `d04b-entitled-as-deontic.l4`). The `OF` in that printed type is how the checker
renders an applied type constructor; it is not something you write.

**Not** a `MAY` for "is not required to". A permission to omit and a duty that never arose are
different legal animals and they export differently — entry [2.1](02-conditions-and-logic.md#e2-1)
makes the same point about exemptions, with the corpus's own words.

**See** [drafting-patterns.md](../drafting-patterns.md), "Constitutive limbs (the predicate tree)";
entry [5.1](#e5-1) for the passive "may", the commonest way an entitlement gets mis-encoded.

---

<a id="e5-6"></a>

## 5.6 "if P fails to do so, P must …" — the reparation that follows a breach

**If the source says**

> `"If the investor fails to reconfirm his or her investment within those five business days, the intermediary within five business days thereafter must: …"`
>
> — `17 CFR 227.304(c)(1)`, at
> `jl4/examples/legal/regcf/denovo/source/part227.txt:632`, encoded at
> `jl4/examples/legal/regcf/denovo/regcf-denovo.l4:2392-2412`, which the encoder calls "the richest
> deontic chain in the part: notice -> reconfirm within five business days -> else cancel, notify
> and refund within a further five" (`:2386-2387`)

**It is doing** attaching a **second obligation** to the failure of the first. Legal drafting
chains these routinely, and the chain is the point: a failure at step one does not end the matter,
it opens step two, and only a failure at the last step is a wrong nobody can cure. `LEST` is that
link. `HENCE` is its opposite — the obligation that follows **performance**.

**Write** the chain nested, one `LEST` per rung, and let only the last rung reach `BREACH`:

```l4
@ref 17 CFR 227.304(c)(1)
GIVETH A DEONTIC `Reg CF party` `Reg CF act`
`the material change reconfirmation chain` MEANS
    PARTY  `the intermediary`
    MUST   `give or send the investor notice of the material change`
    WITHIN `five business days`
    HENCE  ( PARTY  `the investor`
             MUST   `reconfirm the investment commitment`
             WITHIN `five business days`
             HENCE  FULFILLED
             LEST   ( PARTY  `the intermediary`
                      MUST   `direct the refund of investor funds`
                      WITHIN `five business days`
                      HENCE  FULFILLED
                      LEST   BREACH BY `the intermediary`
                             BECAUSE "§ 227.304(c)(1)(ii): the refund was not directed within five business days of the failure to reconfirm" ) )
    LEST   BREACH BY `the intermediary`
           BECAUSE "§ 227.304(c)(1): the investor was not given notice of the material change"
```

_(Probe `d05-fails-to.l4`, exit 0, three traces. Everyone performs → `FULFILLED`. The investor lets
the reconfirmation period lapse and the intermediary refunds in time → `FULFILLED`, by the second
rung. Nobody refunds → `DEONTIC BREACHED … BECAUSE "§ 227.304(c)(1)(ii) …"`, naming the rung that
failed.)_

`` `five business days` `` in that snippet is **not** a unit the language understands. `WITHIN` takes
a bare number; this is an ordinary definition sitting in the same file —

```l4
GIVETH A NUMBER
`five business days` MEANS 5
```

— which is how one period is recorded once and read at three depths of the chain. Copy the chain
without it and the file does not check: `I could not find a definition for the identifier` /
`` `five business days` ``, once per `WITHIN`, exit 1 (measured 2026-09-05, probe
`v-fbd-undefined.l4`). Entry [4.3](04-dates-and-periods.md#e4-3) has the bare-number form and the
reason neither `WITHIN 5 days` nor `WITHIN 5 days OF …` parses.

The snippet is the corpus chain with one rung dropped for length — the corpus interposes a duty to
notify the investor of the cancellation before the refund duty, and guards the reconfirmation with
`PROVIDED commitment's \`reconfirmed within five business days of receipt of the notice\``. Give
**every** rung its own `BECAUSE`: the breach record carries one reason, and it is the only place the
trace says which limb of a chain several rungs deep gave way.

**Not** the reparation hung on `HENCE`. The keywords are easy to swap and the type-checker cannot
tell them apart, so the file runs and the answers invert: with the refund duty on `HENCE`, an
investor who **does** reconfirm, in time, triggers a refund duty and the un-refunded case reads

```
DEONTIC BREACHED:
  party
    NEVERMATCHESPARTY
  who did action
    NEVERMATCHESACT
  at
    20
  surpassed the deadline of party
    `the intermediary`
  who had to do obligatory action
    MUST `direct the refund of investor funds`
  before their deadline, which was at
    7
```

(probe `d05b-hence-swap.l4`, exit 0 — performing the duty produced the breach). **Not** the
consequence written as a second, free-standing rule: nothing then connects it to the failure, and a
trace of the first rule stops at `BREACH` without ever reaching it.

**See** [regulative.md](../regulative.md), "`HENCE` and `LEST` — the success and failure paths" (its
table gives the defaults per modal, which is where the polarity actually lives), and "Recursive
obligations" for a chain that re-emits itself — `jl4/examples/legal/promissory-note.l4:88-118` is
that shape, three rungs deep: pay, then pay with penalty, then pay everything outstanding.

---

<a id="e5-7"></a>

## 5.7 "commits an offence and is liable to a fine not exceeding $1,000"

**If the source says**

> `"Any person who, without lawful authority, removes or attempts to remove from Singapore any portion of the property of which a receiver has been appointed under section 39, or destroys, conceals, or refuses to yield up the same to the receiver, shall be guilty of an offence and shall be liable on conviction by a Magistrates' Court to a fine not exceeding $1,000 or to imprisonment for a term not exceeding 6 months or to both."`
>
> — Probate and Administration Act 1934 s 42, at
> `jl4/examples/legal/sg-succession/cleanroom-2026-08/source/PAA1934.txt:842-853`, whose running
> header between `:845` and `:849` the quotation elides. **No offence in `jl4/examples/legal/` is
> encoded**. The word "offence" appears there in exactly three `.l4` files, and in each it
> is a scope-out: that module lists "the s 42 offence" among the provisions it deliberately leaves
> out (`probate-administration-act.l4:2883-2884`), as does its earlier draft (`sg-paa.l4:1082`), and
> the Jersey charities module puts "offences" out of scope in its opening note
> (`jl4/examples/legal/charities-cleanroom/charity-test.l4:21-23`). The count is of
> `jl4/examples/legal/` only. `jl4/experiments/`, which entry [5.10](#e5-10) draws on for the
> housing grounds, holds offence vocabulary of its own — `macma2.l4` declares an `Offence` type and
> predicates over it — but no offence-creating rule: not one of its files that mentions an offence
> carries a `SHANT` or a `MUST NOT`. The pattern below is therefore written from the source, not
> lifted from an encoding.

**It is doing** three separable things in one sentence, and they take three different shapes.
**(1)** It forbids conduct — regulative. **(2)** It says the conduct constitutes an offence, which
is a test over elements — constitutive. **(3)** It fixes the **maximum** sentence, which bounds a
discretion the court exercises; the sentence actually passed is a fact about a case, not a
consequence the rules compute.

**Write** all three, and keep the ceiling a ceiling:

```l4
-- (2) THE OFFENCE. Whether the conduct IS the offence is constitutive: a
--     BOOLEAN over the elements the section states.
@ref Probate and Administration Act 1934 s 42
GIVEN c IS A `Conduct under section 42`
GIVETH A BOOLEAN
DECIDE `s 42 — guilty of an offence` c IF
        c's `acted without lawful authority`
    AND (   c's `removed or attempted to remove from Singapore property of which a receiver was appointed under section 39`
         OR c's `destroyed, concealed or refused to yield up the property to the receiver` )

-- (3) THE PENALTY IS A CEILING, NOT AN AMOUNT. "not exceeding $1,000" bounds
--     the court's discretion; the sentence actually passed is an input.
@ref Probate and Administration Act 1934 s 42
GIVETH A NUMBER
`the section 42 maximum fine in Singapore dollars` MEANS 1_000
```

_(Probe `d06-offence.l4`, exit 0, three assertions satisfied. The full probe adds the prohibition —
``PARTY `any person` SHANT `remove from Singapore …` … LEST BREACH BY … BECAUSE "s 42: …"`` — and
a `` `s 42 — the fine is within the maximum` `` predicate that tests a sentence against the ceiling,
satisfied at 500 and refuted at 1,500.)_

**Not** a duty to pay the maximum. Written as ``MUST `pay a fine` EXACTLY 1_000``, an offender
fined $500 by the court — a sentence s 42 plainly permits — who pays it in full produces

```
DEONTIC BREACHED:
  BREACH
  BY `the offender`
  BECAUSE "s 42: the fine was not paid"
```

(probe `d06b-fine-as-duty.l4`, exit 0). The encoding has converted a maximum into a tariff and a
lawful sentence into a default. **Not** a deadline for paying it either, unless the section gives
one — see entry [5.9](#e5-9).

**Note what you are taking on.** Offence provisions bring in the criminal standard of proof, mental
elements ("wilfully", "knowingly"), defences and sentencing practice, none of which the shape above
models. If the scope of the encoding is civil liability or compliance, say in the module's own
comments that offences are out of scope, as the corpus does, rather than encoding a fragment of one.

**See** entry [5.3](#e5-3) for the prohibition half; [drafting-patterns.md](../drafting-patterns.md),
`Statutory tables as DATA`, the shape to reach for where the penalties are a schedule of rows
rather than one ceiling.

---

<a id="e5-8"></a>

## 5.8 "by giving five business days' notice" — the notice, and the period it opens

**If the source says**

> `@ref § 227.304(b)(3) — "at least five business days after the notice ... is provided"`
>
> — `jl4/examples/legal/regcf/denovo/regcf-denovo.l4:2361`, beside the three things the notice must
> say at `:2353-2359`

**It is doing** two things a drafter writes as one clause. The notice has **contents** the law
prescribes — constitutive, a predicate over what it said. And giving it **starts a clock**: the
period runs from the notice, not from the start of the relationship. In a contract the same
sentence usually does a third thing, conferring the power to give the notice at all ("either party
may terminate by giving 14 days' written notice"), which is entry [5.4](#e5-4)'s `MAY`.

**Write** the contents as a predicate, hang it on the notice act as a `PROVIDED` guard, and put the
period **inside** the `HENCE`, where the clock re-anchors at the event:

```l4
@ref 17 CFR 227.304(b)(2)-(3)
GIVEN n IS A Notice
GIVETH A DEONTIC `Reg CF party` `Reg CF act`
`the early-close notice and the period it opens` n MEANS
    PARTY  `the issuer`
    MUST   `give notice of the new, anticipated deadline of the offering`
           PROVIDED `304(b)(2) — the early-close notice says what it must` n
    WITHIN 30
    HENCE  ( PARTY  `the investor`
             MAY    `cancel the investment commitment`
             WITHIN `five business days` )
    LEST   BREACH BY `the issuer`
           BECAUSE "§ 227.304(b)(2): the early-close notice was not given, or did not say what (i) to (iii) require"
```

_(Probe `d07-notice.l4`, exit 0. The notice is given at 20 and the clock advanced to 24; the
residual prints ``PARTY `the investor` MAY `cancel the investment commitment` WITHIN 1 HENCE
FULFILLED`` — one day left of the five, counted from the notice. That `WITHIN 1` is the whole
point of nesting.)_

A notice that does not say what the law requires **is not a notice**: the `PROVIDED` guard rejects
the event, the outer deadline runs on, and the outer `LEST` fires. Measured — the same rule given
`` `a notice that omits the cancellation right` ``, the notice event at 20 and the clock advanced to
31 (probe `d07c-bad-notice.l4`, exit 0):

```text
DEONTIC BREACHED:
  BREACH
  BY `the issuer`
  BECAUSE "§ 227.304(b)(2): the early-close notice was not given, or did not say what (i) to (iii) require"
```

That is usually the right legal answer, and it is why the contents predicate belongs on the act
rather than in a separate rule nobody consults.

**Not** the two duties laid side by side. Written flat —

```l4
`the notice and the reconfirmation window, flattened` MEANS
    (PARTY `the issuer`   MUST `give or send the investor notice of the material change` WITHIN 30
                          HENCE FULFILLED LEST BREACH)
    RAND
    (PARTY `the investor` MUST `reconfirm the investment commitment` WITHIN 5
                          HENCE FULFILLED LEST BREACH)
```

— both clocks start at the trace's own `AT 0`, so the second party's window closes on day 5 whatever
the notice does. On events the nested form fulfils (notice at 20, reconfirmation at 24), the
flattened form returns `DEONTIC BREACHED: BREACH` and the nested one `FULFILLED` — the two
directives are in one file, probe `d07b-notice-flat.l4`, exit 0. `RAND` is for duties that genuinely
run in parallel; a period measured from an event is not one of them.

**See** [regulative.md](../regulative.md), "`PROVIDED` and `EXACTLY` — action matching", and
"Composition: `RAND` and `ROR`"; entry [4.3](04-dates-and-periods.md#e4-3) for the unit that `WITHIN
5` does not record — "five business days" and "five days" are the same `5` here, and only your
comment says which — and entry [5.6](#e5-6) for the `` `five business days` `` definition the block
above depends on.

---

<a id="e5-9"></a>

## 5.9 "shall …", with no time stated

**If the source says**

> `"the probate shall be revoked, and a new probate shall be granted of the will and codicil together"`
>
> — Probate and Administration Act 1934 s 12(2), quoted at
> `jl4/examples/legal/sg-succession/cleanroom-2026-08/probate-administration-act.l4:2768` and encoded
> at `:2773-2779`

**It is doing** imposing a duty and saying nothing about when. Most statutory duties are like this.
The corpus states the rule at `probate-administration-act.l4:2689-2693`: of the four duties in that
Act, one is dated by another section, and "the other three duties are undated in the Act, so they
carry no `WITHIN`; writing one in would be inventing a period Parliament did not enact."

**Write** no `WITHIN`. The duty then stands until it is performed, and a trace with no matching
event prints it back rather than reporting a breach:

```l4
-- s 12(2) says the probate "shall be revoked, and a new probate shall be
-- granted"; it names no period, so the rule carries no WITHIN.
@ref Probate and Administration Act 1934 s 12(2)
GIVETH A DEONTIC `A party under this Act` `An act under this Act`
`s 12(2) — the probate shall be revoked and a new probate granted` MEANS
    PARTY `the court`
    MUST  `revoke the probate and grant a new probate of the will and codicil together`
    HENCE FULFILLED

-- Not yet performed: the duty stands, and the trace prints it back.
#TRACE `s 12(2) — the probate shall be revoked and a new probate granted` AT 0 WITH
    (`WAIT UNTIL` 900)
```

_(Probe `d08-no-deadline.l4`, exit 0. Performed at 900 → `FULFILLED`; the clock advanced to 900 with
nothing done → ``PARTY `the court` MUST `revoke the probate …` HENCE FULFILLED``, the standing
obligation. ``(`WAIT UNTIL` n)`` is how a trace moves the clock without an event.)_

**Not** a deadline you supply because the shape looks bare. Add `WITHIN 30` to the rule above and a
court that acts on day 40 — compliance, on any reading of s 12(2) — is reported as

```
DEONTIC BREACHED:
  BREACH
  BY `the court`
  BECAUSE "s 12(2): the probate was not revoked within 30 days"
```

(probe `d08b-invented-deadline.l4`, exit 0). Nothing in the language marks the 30 as invented, so
the false period propagates into every projection of the file.

Where a deadline for the duty lives in **another section**, take it, and say in a comment that the
two come from different provisions — the corpus does exactly this for s 29(7), dated by s 55(1)(c)
(`probate-administration-act.l4:2749-2751`).

**See** [regulative.md](../regulative.md), "`WITHIN` — deadlines" and "`#TRACE` — simulating contract
execution"; entry [4.3](04-dates-and-periods.md#e4-3), which measures the residual and the
`WITH`-block-with-no-events form at length.

---

<a id="e5-10"></a>

## 5.10 "termination for breach" — the breach is a fact, the remedy is the duty

**If the source says**

> `"Both at the date of the service of the notice under section 8 of this Act relating to the proceedings for possession and at the date of the hearing— … (b) if rent is payable monthly, at least three months' rent is unpaid;"`
>
> — Housing Act 1988 Sch 2 Ground 8 (as amended), carried verbatim at
> `jl4/experiments/housing-act-ground-8.l4:138-139` and `:150`, with the remedy at `:174-177`

**It is doing** naming a **default** and attaching a **remedy** to it. The trap is the word
"breach": `BREACH` in L4 is what a trace reports when a modelled obligation goes undischarged, and
that is a different object from the contractual or statutory default that entitles a party to
terminate. The default is almost always a **fact** — arrears at two dates, a milestone missed, a
warranty untrue — that the rules test. The remedy is the duty or power that fact unlocks.

**Write** the default as a predicate and the remedy as a guarded deontic, exactly as the corpus does:

```l4
@ref Housing Act 1988 Sch 2 Ground 8
GIVEN claim IS A Ground8Claim
GIVETH A BOOLEAN
`Ground 8 made out` claim MEANS
        "Both at the date of the service of the notice under section 8 of this Act relating to the proceedings for possession and at the date of the hearing—"
    ... `per-period threshold met` claim (claim's `rent unpaid at the date of service of the section 8 notice`)
    AND `per-period threshold met` claim (claim's `rent unpaid at the date of the hearing`)

@ref Housing Act 1988 Sch 2 Part I; Ground 8
GIVEN claim IS A Ground8Claim
GIVETH A DEONTIC Actor Action
`ground 8 possession order` claim MEANS
    IF   `Ground 8 made out` claim
    THEN PARTY Court MUST `order possession` WITHIN 30
    ELSE FULFILLED
```

_(Probe `d09-termination.l4`, exit 0. `` `per-period threshold met` `` is the corpus's own helper,
at `jl4/experiments/housing-act-ground-8.l4:137-140`, carrying the Ground 8 (a) and (b)
alternatives; the probe reproduces it. `#ASSERT` lands on `` `Ground 8 made out` `` — satisfied on
three months' arrears at both dates, refuted where the tenant pays down before the hearing — and
`#TRACE` exercises the order. That division, assert the fact and trace the remedy, is forced: a
`DEONTIC` cannot be asserted, entry [5.2](#e5-2).)_

The `ELSE FULFILLED` arm matters: where the ground is not made out there is no duty, and
`FULFILLED` is how a deontic-valued rule says "nothing is owed here".

**Not** a rule that reads the breach out of a trace. Feeding an obligation into an `IF` does not
type-check:

```
The condition in IF-THEN-ELSE and BRANCH-IF-THEN-OTHERWISE constructs is expected to be of type

  BOOLEAN

but is here of type

  DEONTIC OF Actor, Action
```

exit 1 (probe `d09b-breach-as-fact.l4`). Traces are exercised at the boundary and their results do
not flow back into the rules; if a later rule needs to know that a party defaulted, the default has
to be a fact the rules can see.

**Escalating remedies** — grace period, then penalty, then acceleration of the whole debt — are the
`LEST` chain of entry [5.6](#e5-6), not three separate rules;
`jl4/examples/legal/promissory-note.l4:88-118` is the worked instance, ending at
`` `All Outstanding Debts` ``.

**See** [drafting-patterns.md](../drafting-patterns.md), "Mandatory vs discretionary" and "Exercising
a DEONTIC"; [regulative.md](../regulative.md), "`BREACH`, `FULFILLED`, and `BECAUSE`"; entry
[5.6](#e5-6) for the chain, and entry [5.3](#e5-3) for the prohibition whose breach this often is.

---

<a id="e5-11"></a>

## 5.11 Reading a duty back: the `#TRACE` event block

**If the source says** nothing — this entry is the mechanics of exercising everything else in the
area. A `DECIDE` is tested with `#ASSERT`; a `DEONTIC` cannot be, because its answer is a state
machine and not a boolean. `#TRACE` is how you run one, and the entries above use it a dozen times
without ever stating its shape.

**It is doing** replaying a duty against a history. You give the clock a start (`AT 0`), then a
`WITH` block of what happened, and the result is what the duty has become: `FULFILLED`, a
`DEONTIC BREACHED` with its `BECAUSE` string, or — if nothing has resolved it yet — the residual
obligation printed back at you.

**Write** one event per line inside the `WITH` block, in the order they happen. There are exactly
two kinds, and they may be mixed freely:

```l4
-- Paid on day 12, inside the 30-day deadline: the first rung discharges.
#TRACE `cl 4 -- the Company must pay each invoice` AT 0 WITH
    PARTY `the Company` DOES `pay the invoice` AT 12

-- Paid exactly ON the deadline: still in time.
#TRACE `cl 4 -- the Company must pay each invoice` AT 0 WITH
    PARTY `the Company` DOES `pay the invoice` AT 30

-- The clock advanced and nothing done: `WAIT UNTIL` moves time without an act.
#TRACE `cl 4 -- the Company must pay each invoice` AT 0 WITH
    (`WAIT UNTIL` 31)

-- Both kinds in one block, in the order they happen: the deadline passes
-- un-met, and the reparation is then performed.
#TRACE `cl 4 -- the Company must pay each invoice` AT 0 WITH
    (`WAIT UNTIL` 45)
    PARTY `the Company` DOES `pay the unpaid amount with interest` AT 50
```

_(Probe `r6-trace-block.l4`, exit 0, no errors.)_ The four results, in order: `FULFILLED`;
`FULFILLED`; the second rung standing as
``PARTY `the Company` MUST `pay the unpaid amount with interest` HENCE FULFILLED LEST (BREACH BY …)``;
and `FULFILLED` again, the chain discharged on its second rung.

Six facts, all measured on that probe, none of them stated anywhere else:

- **``(`WAIT UNTIL` n)`` is built in.** It is not a prelude name and it needs no `IMPORT`. The
  parentheses are required: it is an application in event position.
- **The two kinds mix, in one block, in authored order.** A clock advance may precede an act, which
  is the only way to show a `LEST` chain fulfilling on its second rung.
  `jl4/examples/ok/deontic-breach-semantics.l4:131-133` stacks two waits and an act in one block.
- **The deadline is inclusive.** An act `AT 30` against `WITHIN 30` is timely; ``(`WAIT UNTIL` 30)``
  leaves the duty standing with `WITHIN 0` remaining; ``(`WAIT UNTIL` 31)`` is what expires it.
  Entry [4.3](04-dates-and-periods.md#e4-3) carries this too, because it is the reading a source's
  "within 30 days" leaves you to make.
- **A rule that takes arguments is applied before `AT`.** `#TRACE rule arg AT 0 WITH` is the one
  shape the other entries show; **more than one argument is equally legal** —
  ``#TRACE `cl 6(1) — …` `the Contractor` `a disclosure to the world` AT 0 WITH`` runs, and
  produces the breach. Parenthesise a constructed argument.
- **A block with no events, only a comment, is legal**, and prints the standing obligation; a
  `#TRACE` with the `WITH` dropped altogether is a parse error. Entry
  [4.3](04-dates-and-periods.md#e4-3) quotes both.
- **`#TRACE` is the exception to the one-line rule for directives.** Its events belong on the
  following lines, indented; only `#ASSERT REFUSED … BECAUSE` is otherwise allowed to wrap.

**Not** `#ASSERT` over a `DEONTIC`. There is nothing to compare it against — a deontic is not
`EQUALS`-comparable — and the trace result is not a fact the rules can read back. Entry
[5.10](#e5-10) says what to do when a later rule needs to know that a party defaulted.

**Not** a trace whose events invent a deadline the instrument does not state. If the source fixes no
further date after the first, the second rung carries no `WITHIN` and stands until performed — entry
[5.9](#e5-9). Putting the first rung's number on the second turns a rule that suppresses a
consequence into a second deadline, which is [4.11](04-dates-and-periods.md#e4-11)'s error in a
different costume.

**See** [regulative.md](../regulative.md), "`WITHIN` — deadlines", entry [5.6](#e5-6) for the `LEST`
chain these traces exercise, and `jl4/examples/ok/deontic-breach-semantics.l4`, which is the
language's own regression test for every case above.
