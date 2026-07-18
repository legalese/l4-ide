# The Charities (Jersey) Law 2014, written out in L4

### A report on formalising an entire Law, for legislative drafters

---

## 0. What we did, and what we are asking you to look at

We took the [Charities (Jersey) Law 2014](https://www.jerseylaw.je/laws/current/l_41_2014) — all 43 Articles
and both Schedules — and rewrote it in **L4**, a programming language designed for law. Not a summary of the
Law, not a flowchart *about* the Law: a line-by-line rendering in which the words of the Law and the logic of
the Law sit in the same file, side by side, and the logic **runs**.

The result is twelve files, about 12,800 lines, carrying **754 assertions** — worked examples that the machine
re-checks every time the model is touched. All 754 pass.

We are not claiming to have found errors in your Law. We are claiming something more modest and, we think,
more useful: that **formalisation is a reading technique**. It forces a reader to answer questions the prose
lets them walk past. This report is mostly a list of the questions it forced us to answer, and how we answered
them — because *those* are the places where a drafter's eye is worth more than ours.

There are about twenty of them. Roughly four are, we think, worth your actual attention. One of them concerns
an amendment that came into force on 16 October 2025.

A note on the audience. This report is written for a drafter, not a programmer. Where we need a piece of logic
or computer science to make sense, we stop and explain it in a **sidebar**. There is a lot of talk in
government about "low-code" and "no-code" — about making programming accessible to people who are not
programmers. Much of that is achievable. But some of it is not, and it is more honest to say so: at a certain
point, to write rules that a machine can check, **you have to understand a little logic**. Not much. But some.
The sidebars are our attempt to hand over exactly that much and no more. Section 9 is a candid list of what we
could not hide.

---

## 1. How to run it

```sh
l4 check part-3-charity-test.l4    # typecheck: does the model hold together?
l4 run   part-3-charity-test.l4    # typecheck, then run every worked example
```

The `l4` binary comes from the [L4 repository](https://github.com/smucclaw/l4-ide). It needs the standard
library on its path:

```sh
mkdir -p ~/.local/share/jl4/libraries
ln -sf /path/to/l4-ide/jl4-core/libraries/{prelude,daydate}.l4 ~/.local/share/jl4/libraries/
```

### The corpus

| File | Articles | Lines | Worked examples |
|---|---|---:|---:|
| `charities-common.l4` | shared vocabulary | 80 | — |
| `part-1-interpretation.l4` | 1–2 — entity, Jersey entity, governor, misconduct | 506 | 23 |
| `part-2-commissioner.l4` | 3–4 — establishment; general functions | 580 | 26 |
| `part-3-charity-test.l4` | 5–7 — **the charity test** | 719 | 35 |
| `part-4-register-and-application.l4` | 8–12 — the register; **the registration test**; names | 2,065 | 114 |
| `part-4-effects-and-deregistration.l4` | 13–17 — effects; court powers; deregistration | 1,833 | 92 |
| `part-5-governors.l4` | 18–20 — duties; reportable matters; disqualification | 1,533 | 96 |
| `part-6-use-of-terms.l4` | 21–25 — "charity", "Jersey charity"; the offences | 1,228 | 112 |
| `part-7-information.l4` | 26–31 — information; required steps notices; disclosure | 1,679 | 107 |
| `part-8-appeals.l4` | 32–36 — the tribunal; standing; grounds of appeal | 1,272 | 85 |
| `part-9-final.l4` | 37–43 — corporate liability; savings; citation | 705 | 30 |
| `schedules-1-and-2.l4` | Schedules 1–2 — the Commissioner; the Tribunal | 562 | 34 |
| | | **12,762** | **754** |

Source: the **Official Consolidated Version**, showing the law from **16 October 2025** to Current.

---

## 2. The method: the Act stays in the file

The obvious way to formalise a statute is to read it, understand it, and then write code that does what you
understood. The result is a program that is *about* the Act. Six months later nobody can tell whether it is
still faithful, because the Act is in one document and the logic is in another, and the only thing joining them
is somebody's memory.

We do the opposite. **The words of the Law stay inside the code.** Here is Article 2(10), the definition of
"misconduct", exactly as it appears in our file:

```l4
`is misconduct` m MEANS
        "In this Law, unless the context otherwise requires, 'misconduct' means -"
    ..  `(a) — a contravention by the charity or a governor` m
    ..  `(b) — the commission of an offence in relation to a charity` m
```

and, one level down, limb (a):

```l4
`(a) — a contravention by the charity or a governor` m MEANS
        "(a) a contravention, by a registered charity or by any of its governors, of a provision -"
    ... m's `the actor is the registered charity or one of its governors`
    AND     "(i) of this Law, or of any enactment under this Law,"
        ..  m's `(a)(i) contravention of a provision of this Law ...`
        ..  "(ii) of the constitution of the registered charity, ..."
        ..  m's `(a)(ii) contravention of ... the constitution of the charity ...`
        ..  "(iii) of a required steps notice, or"
        ..  m's `(a)(iii) contravention of a provision of a required steps notice`
        ..  "(iv) of an order of the court under this Law ..."
        ..  m's `(a)(iv) contravention of ... an order of the court ...`
```

Read down the left margin and you are reading Article 2(10)(a). The quoted lines are the Act. The lines
beginning `m's` are the *facts* — the things you would have to establish about a case. The `AND` and the `..`
are the logic.

You may reasonably ask: if those quoted lines are just the Act sitting there, what are they *doing*? How does
the machine not choke on them?

> ### 📘 Sidebar 1 — "Inert" text, and why a quoted line is safe
>
> This is the one genuinely clever trick in the whole encoding, and it takes ninety seconds to understand.
>
> In logic, `AND` and `OR` each have an **identity** — a value you can add to the chain without changing the
> answer. For `AND` the identity is TRUE: `TRUE AND X` is just `X`, always. For `OR` the identity is FALSE:
> `FALSE OR X` is just `X`, always. (It is the same idea as adding 0, or multiplying by 1: `0 + X = X`,
> `1 × X = X`. Zero is the identity for addition. TRUE is the identity for AND.)
>
> So: a quoted line of the Act, dropped into an `AND` chain, is treated as TRUE. Dropped into an `OR` chain, it
> is treated as FALSE. **Either way it cannot change the answer.** It is *inert*. It rides along in the file,
> in full view, next to the logic it describes — and it is guaranteed not to interfere with it.
>
> That is what lets the Act and the code be *the same document*. The prose is not a comment that might drift
> out of date; it is not a separate mapping table; it is in the expression itself, and the expression still
> computes the right answer.
>
> **The practical consequence for a drafter:** you can audit the model against the Law without leaving the
> file, and without trusting us.

The two symbols that appear everywhere:

- `...` means **AND** (it reads as "and also"), and
- `..` means **OR** (it reads as "or else").

They are deliberately quiet, because most of the time the connective is obvious from the statutory prose sitting
next to it, and we would rather the eye rest on the words of the Act than on our punctuation.

### And now the part that should interest a drafter most

> ### 📘 Sidebar 2 — Layout is the bracketing. Punctuation is a false friend.
>
> Consider a provision of the form:
>
> > *(a) X, (b) Y, or (c) Z, and (d) W.*
>
> Does `(d)` attach to `(c)` alone, or to the whole of `(a) or (b) or (c)`? English cannot tell you. Commas
> cannot tell you. In *Chew v The Queen*, the High Court of Australia divided 5–1–1 on precisely this kind of
> question — where a comma bound in a criminal provision. Three judges, three readings, one comma.
>
> In L4 the question **cannot be left open**. The *indentation* determines the grouping:
>
> ```l4
>         a
>     ..  b
>     OR  c
>     AND d            -- (d) attaches to the whole disjunction
> ```
>
> versus
>
> ```l4
>         a
>     ..  b
>     ..      c
>         AND d        -- (d) attaches to (c) only
> ```
>
> The encoder **must** commit. And having committed, the commitment is *visible* — a reader can see it, and
> disagree with it, at a glance.
>
> We think this is the single most valuable thing formalisation does for a drafter. It does not resolve
> ambiguity by magic. It **converts an invisible ambiguity into a visible decision.** The ambiguity was always
> there. Formalisation just refuses to let anyone pretend otherwise.

---

## 3. Naming the world before you can say anything about it

Before you can ask "is this entity a Jersey entity?", something has to say what an entity *is* — what facts one
has, what questions can sensibly be asked of it. In L4 that is a `DECLARE`.

> ### 📘 Sidebar 3 — `DECLARE` is your interpretation Article, made executable
>
> ```l4
> DECLARE Entity HAS
>     name                                            IS A STRING
>     `(c) an incorporated 1862 association`          IS A BOOLEAN
>     `(d) a foundation`                              IS A BOOLEAN
>     `(f) a company`                                 IS A BOOLEAN
>     ...
> ```
>
> This says: an Entity is a thing that has a name (some text), and a set of yes/no facts, each named after the
> sub-paragraph of Article 2(1) it comes from. A `BOOLEAN` is simply a fact that is either true or false.
>
> The machine will now refuse to let anyone ask a question of an Entity that the Entity has no answer to. If you
> mistype a field name, or ask whether a *purpose* is a company, it is an error before the thing ever runs. This
> is a **type system**, and it is doing for your definitions what a good interpretation Article does for your
> substantive provisions: fixing the vocabulary once, so the rest can rely on it.
>
> The discipline it imposes is exactly the discipline of drafting. You cannot use a term you have not defined.

### Why Article 2(1) is a set of checkboxes, not a dropdown

There is a real modelling decision buried here, and the Law itself makes it for us.

Article 2(1) lists what can be an "entity": (a) the trustees of a trust; (b) fidéicommissaires; (ba) a Jersey
NPO body corporate; (c)–(j) various others. The tempting move is to treat this as a **choice** — every entity is
exactly one of these, like a dropdown menu.

That would be wrong, and Article 8(3)(a)(i) proves it. It requires the register to note, "in the case of an
entity falling within one of sub-paragraphs (f) to (j) ... **whether it also falls within sub-paragraph (a)**".
A company (f) that is *also*, taken together with others, the trustee of a trust (a). The Law expressly
contemplates the overlap. Sub-paragraph (b) is likewise expressly a *subset* of (a) ("without prejudice to the
generality of sub-paragraph (a)").

> ### 📘 Sidebar 4 — Checkboxes vs radio buttons
>
> A **radio button** (in logic, an *enumeration*) says: exactly one of these, and no more. A **checkbox** says:
> any combination of these, including several at once, or none.
>
> Getting this wrong is one of the commonest ways a formalisation quietly diverges from its statute — and once
> you have chosen a radio button, the overlapping case cannot even be *expressed*, so it never shows up in
> testing. The model does not report the problem. It simply has no way to say the true thing.
>
> Article 2(1) is checkboxes. We encoded checkboxes. If Article 8(3)(a)(i) had not existed we might have got
> this wrong, and the Law would have caught us.

---

## 4. Two kinds of rule, and the machinery for each

Legislation does two quite different things, and it is worth having different tools for them.

**Constitutive rules** say what things *are*. "An entity meets the charity test if…". "A reportable matter in
relation to a person is the fact that the person…". These are definitions, tests, classifications. They are
true or false of a state of affairs, and the natural machinery for them is the AND/OR tree you have been
looking at.

**Regulative rules** say what people must *do*. "The Commissioner must register the applicant…". "A person must
not act as a governor…". "A registered charity must promptly report…". These are not true or false; they are
*complied with* or *breached*, and they unfold over time.

L4 has separate machinery for the second kind.

> ### 📘 Sidebar 5 — MUST, MAY, SHANT — and the meaning of doing nothing
>
> ```l4
> PARTY Commissioner MUST  `register the applicant as a charity`  WITHIN 30
> PARTY Court        MAY   `make a disqualification order`        WITHIN 30
> PARTY Governor     SHANT `act as a governor`                    WITHIN 365
> ```
>
> The three are distinguished by **what happens when nothing happens** — which is exactly how a lawyer
> distinguishes a duty from a power from a prohibition, and it is pleasing that it falls out so cleanly:
>
> | | if the party does it | if the party does nothing |
> |---|---|---|
> | **MUST** (duty) | fulfilled | **breach** |
> | **MAY** (power) | fulfilled | fulfilled — *no breach* |
> | **SHANT** (prohibition) | **breach** | fulfilled |
>
> That middle row is the whole of what makes a power discretionary. A court that declines to make an order it
> *may* make has done nothing wrong. A Commissioner who declines to make a decision she *must* make has.
>
> This means that when we write `MAY` rather than `MUST`, we are making a substantive legal claim, and the
> model will behave differently. We have tried to get every one of them right, and to say so where the statute
> is unclear.

The `WITHIN 30` is a deadline in days. This raises an honesty problem which we address squarely in section 8:
**your Law very often does not give a number**, and we have had to supply one.

> ### 📘 Sidebar 6 — The trace: running a duty against a timeline
>
> A duty is not a static thing; it plays out. L4 lets you feed a chain of obligations an actual sequence of
> events and ask what is left standing. Here is Article 5(6)–(8) — consult, report, provide to the Minister,
> lay before the States:
>
> ```l4
> #TRACE `Articles 5(6) to (8) — the consultation and laying chain` AT 0 WITH
>     PARTY Commissioner DOES `consult before issuing or amending guidance`   AT 30
>     PARTY Commissioner DOES `publish a report on the consultation`          AT 50
>     PARTY Commissioner DOES `provide the guidance and report to the Minister` AT 70
> ```
>
> The Commissioner does everything required of her. The Minister never lays the guidance before the States. The
> machine reports what remains:
>
> ```
> PARTY Minister
> MUST `lay the guidance and report before the States`
> HENCE FULFILLED
> ```
>
> The chain has *residuated* — the fulfilled steps have fallen away, and what is left is precisely the
> outstanding duty, sitting on the person who owes it. Nobody had to reason about this. The model did.
>
> This is the closest thing we have to a compliance dashboard that is *derived from the Act itself* rather than
> written alongside it.

---

## 5. The charity test: a worked example of the whole method

Part 3 is the heart of the Law, and it is a good showcase, because it is not a simple conjunction. It is a
three-storey **defeasible** structure, and the storeys fight each other.

- **Article 5(1)** — the positive test: all purposes charitable or ancillary, *and* public benefit provided.
- **Article 5(2)** — a **defeater**: an entity that "otherwise meets the charity test, **nevertheless does not
  meet that test, despite paragraph (1)**", if its constitution lets a Minister or a States member direct it.
- **Article 5(3)** — a **defeater on the defeater**: the Minister may by Order disapply 5(2).

> ### 📘 Sidebar 7 — Defeasibility, and why "despite paragraph (1)" is a technical instruction
>
> Most logic is *monotonic*: once you have proved something, more facts cannot un-prove it. Law is not like
> that. Law is full of provisions that say, in effect, "everything I just told you — never mind, in this case."
>
> Article 5(2) is exactly that. It does not add a condition to the test in 5(1); it **subtracts an entity that
> has already passed it**. The words "otherwise meets" and "despite paragraph (1)" are the drafter telling the
> reader the order of operations.
>
> In L4 that is a subtraction, and it composes:
>
> ```l4
> `meets the charity test` c MEANS
>         `Article 5(1) — the positive test` c
>     AND NOT `the Article 5(2) knock-out bites` c
>
> `the Article 5(2) knock-out bites` c MEANS
>         `Article 5(2) — constitution expressly permits government direction or governorship` c
>     AND NOT c's `an Order under Article 5(3) disapplies paragraph (2) in relation to this entity`
> ```
>
> Read it aloud: *the test is met if the positive test is met and the knock-out does not bite; and the knock-out
> bites if the government-control condition holds and no Order disapplies it.* Three storeys, three lines.
>
> A drafter will recognise this shape immediately — it is a proviso to a proviso. What formalisation adds is
> that the nesting is now **unambiguous and testable**. In the test suite, the same quango fails the charity
> test and then passes it, on the flip of the single Article 5(3) field, and nothing else.

### Article 6(5) — a piece of drafting we want to praise

Article 6(5) says the purpose of advancing a political party is "**neither** a charitable purpose **nor** a
purpose ancillary or incidental to a charitable purpose, **irrespective of** whether it would otherwise fall
within paragraph (1) or Article 5(1)(a)(ii)".

Both limbs are load-bearing, and formalisation makes it obvious *why*. Article 5(1)(a) admits a purpose if it is
**either** charitable **or** merely ancillary. If Article 6(5) had killed only the first, a charity could dress
up its campaigning as "purely incidental" to its school and walk straight through the second gate. The second
limb of 6(5) is an **anti-laundering provision**, and it is doing real work.

We encoded it as two separate subtractions, at both gates, and the test suite contains exactly that evasion —
a purpose that *would* fall within head (b) (education), *is* pleaded as merely incidental, and is nonetheless
excluded:

```l4
#ASSERT `falls within a head of Article 6(1)` `campaigning ...`      -- it WOULD fall within (b)...
#ASSERT NOT `is a charitable purpose` `campaigning ...`              -- ...but gate 1 is shut
#ASSERT NOT `is a purpose purely ancillary ...` `campaigning ...`    -- ...and gate 2 is shut
```

Whoever drafted 6(5) had thought about the evasion. It is nice to be able to *show* that.

### Article 7(3)(b) — hortatory in form, operative in substance

Article 7(3) reads like an instruction about how to *reason*: "The person determining the question must not —
(a) presume any particular charitable purpose to be for the public benefit; or (b) treat one particular natural
person or a group of identified natural persons as being a section of the public…".

You could easily read all of that as a direction to the decision-maker and nothing more. But look at how (b)
ends: "**and accordingly must not treat an entity that benefits only such a person or persons as providing
public benefit**."

That is not a direction about *how* to think. That is a conclusion the determiner is **forbidden to reach**.
It therefore changes the truth value of Article 5(1)(b), and it must be lifted into the logic — which we did.
7(2) and 7(3)(a), by contrast, genuinely do constrain reasoning without dictating the answer, and we carry
those as duties on the determiner instead.

The distinction matters: in our model, a family trust with impeccably educational purposes and real money
behind it **fails the charity test**, and it fails it at Article 5(1)(b), not for want of a charitable purpose.

---

## 6. The findings

Below are the places where the Law made us stop. We have sorted them by how much we think they warrant your
attention. Every one is flagged in the source with a `>>>` marker at the site, and every one has a runnable
worked example attached.

To be clear about our standing: we are not Jersey lawyers, we have no view on the policy, and several of these
will have obvious answers that we simply do not know. They are offered as *questions raised by a machine that
was not allowed to skim*.

---

### 🔴 Finding 1 — The `(ba)` gap. Three months old, and it may cost a class of charities their name.

**Article 2(1)(ba)** was **inserted between (b) and (c)** by R&O.56/2025, in force **16 October 2025**
(endnote [2]). It covers a body corporate that is a Jersey-established NPO and is not already within (c)–(h).

**Article 2(3)(a)** — the definition of **"Jersey entity"** — was not touched. It still reads:

> an entity is a "Jersey entity" if — (a) it falls within any of sub-paragraphs **(a) to (h)** of paragraph (1)

**Does the range "(a) to (h)" carry the newly inserted (ba)?**

If it does not, then a body corporate that is **by definition established under the law of Jersey** (that is
what Article 2(1)(ba)(ii) *says*) is **not a "Jersey entity"**. And since Article 23(3)(b) requires a "Jersey
charity" to be a Jersey entity, such a body — however impeccably Jersey, however properly registered — **could
never lawfully call itself a "Jersey charity"**. It would commit an offence under Article 23(1) if it tried.

That cannot be the intention. We encoded the purposive reading — (ba) is *inside* the range — and flagged it.
But the two readings are **one line apart** in our file:

```l4
`falls within any of sub-paragraphs (a) to (h)` e MEANS
        "(a) the person or persons, taken together, who are the trustees of a trust;"
    ..  e's `(a) the trustees of a trust, taken together`
    ..  "(b) ... the fideicommissaires of a court-approved fideicommis;"
    ..  e's `(b) the fideicommissaires of a court-approved fideicommis, taken together`
    ..  `(ba) — a body corporate that is a Jersey NPO outside (c) to (h)` e   -- <<< THE LINE
    ..  `falls within any of sub-paragraphs (c) to (h)` e
```

Delete the marked line and this assertion fails:

```l4
#ASSERT `is a Jersey entity` `Grands Vaux Mutual, a Jersey NPO body corporate`
```

This is what we mean by formalisation as a reading technique. The gap is not subtle *once you are forced to
compute the range*. It is very easy to miss when reading, because "(a) to (h)" looks like it obviously includes
everything between (a) and (h), and (ba) *is* between (a) and (h) — positionally. It is only when you have to
decide whether a *lettered range* enumerates *positions* or *labels* that the question becomes visible at all.

**Our question for you:** is this worth a tidying amendment to Article 2(3)(a)?

---

### 🔴 Finding 2 — Article 11(4)/(5): the applicant who is neither registered nor refused

Article 11(4):

> **If the applicant complies with paragraph (2), with any Regulations under paragraph (3), and with Article
> 19(5)**, the Commissioner **must register** the applicant as a charity **if satisfied that** — (a) … (f).

Article 11(5):

> **If not so satisfied**, the Commissioner must **refuse** to register the applicant.

Note what "**not so satisfied**" attaches to. It attaches to the **satisfaction** condition — the (a)–(f) test.
It does not, on its face, attach to the **compliance gate** in the opening words of 11(4).

So consider an applicant who **fails the gate** — an incomplete application, say, or one that has not complied
with Article 19(5) (the governors' declarations). Read literally:

- 11(4) does not bite, because the gate is not passed, so there is **no duty to register**; and
- 11(5) does not bite either, because 11(5) is triggered by *not being satisfied of (a)–(f)*, and the
  Commissioner never reached that question — so there is **no duty to refuse**.

The Commissioner is simply not seized of a decidable application. In practice this is probably fine and is
probably closed by the Order under Article 11(8)(a) and the Regulations under Article 11(3). But *the Law itself
does not say so*, and the applicant is left in a state the Law does not name — with, incidentally, nothing to
appeal against under Article 33(1)(a), which requires "a decision … to refuse to register".

We encoded **both** readings, side by side, and let the reader choose:

- `Article 11(4) and 11(5) — the registration decision` — the **two-arm** reading, folding gate-failure into the
  refusal arm.
- `Article 11(4) and 11(5) — the registration decision (the literal three-way reading)` — gate-failure yields
  **no duty at all**.

**Our question for you:** is the three-way reading intended? If not, would "*If the Commissioner is not so
satisfied, or the applicant does not so comply,*" close it?

---

### 🟠 Finding 3 — Article 33(5): "at both times" — over *what*?

Article 33(5) lets a third party appeal against someone else's registration, but only on the ground that —

> **at both the time of the application and the time of the appeal** — (a) the applicant did not meet the
> charity test; **or** (b) if the appellant has an interest in the registered name, that name was undesirable
> under Article 12(1).

Where does "at both times" bind? Two readings, and they are not equivalent:

- **Ground-wise** (we adopted this): *one ground* must subsist at both times.
  `( (a)@application AND (a)@appeal ) OR ( (b)@application AND (b)@appeal )`
- **Time-wise**: *some* ground at each time — but it may be a **different** ground at each.
  `( (a) OR (b) )@application AND ( (a) OR (b) )@appeal`

On the time-wise reading, the ground may **shape-shift**: an appellant could say "it failed the charity test
when it was registered, and its *name* is objectionable now", and have standing, though **no single complaint
ever held at both times**. That seems unlikely to be intended, so we took the ground-wise reading — but we
encoded both, and there is a scenario in the test suite where the two give **opposite answers**.

The ground-wise reading has a consequence worth surfacing on its own: a charity that **cures** the defect before
the appeal is heard **defeats the challenge entirely**. The rival who was right all along, about a charity that
genuinely should not have been registered, loses — because the charity fixed its purposes in the meantime. That
may be exactly the policy you want (it rewards remediation, and the register is about the present). But it
should be a policy you *chose*.

There is a second, smaller question in the same paragraph. Limb (b) opens "**if** the appellant has an interest
in the registered name". Is that "if" a **condition on limb (b)** (so an appellant with no interest in the name
simply cannot use limb (b)), or is it a **material implication** in the logician's sense? Because if it is the
latter, then an appellant with **no interest in the name at all** satisfies it *vacuously* — and could challenge
any registration on limb (b). We read it as a condition. See Sidebar 8.

---

### 🟠 Finding 4 — Article 18(4)(a) read with Article 2(10)(b): the defrauded governor

Article 18(4) says when *a governor* engages in misconduct. Limb (a): "the governor contravenes a provision, **or
commits an offence, mentioned in Article 2(10)**".

Now look at what Article 2(10)(b) is. It is the commission, **by any person**, of certain offences in relation to
the charity. *By any person.* Not by the governor. Not by the charity. **Any person** — including a total
stranger who defrauds the charity.

Compose the two naively — as a machine will, if you let it — and you get: an outsider defrauds the charity;
that is "an offence mentioned in Article 2(10)"; and therefore *the governor* "engages in misconduct" under
Article 18(4)(a). The governor is now liable to a required steps notice (Article 27(1)(c)) and to disqualification
(Article 20), **for having been the victim of a fraud**.

That is obviously not intended, and no court would reach it. But the reason no court would reach it is that a
human reader silently supplies the attribution — "*the governor* contravenes … or commits". We had to supply it
explicitly, as a conjunct, and flag it:

```l4
`Article 18(4)(a) — ... mentioned in Article 2(10)` g MEANS
        "(a) the governor contravenes a provision, or commits an offence, mentioned in Art 2(10);"
    ... `is misconduct` (g's `the Article 2(10) allegation`)
    AND ... g's `the governor is the person who contravened or committed the offence`
```

Both cases are tested — the outsider's fraud (not attributed) and the governor's own fraud (attributed).

**This is the class of finding we think formalisation is best at.** Nothing is *wrong* here. The provision works.
But it works because of something a reader supplies, and that unstated something is now written down.

---

### 🟠 Finding 5 — An excepted foreign charity always breaches Article 21(1)

This one we got wrong first, and the machine caught us — which is the point of the exercise, so we record it
honestly.

Article 22 defines an "excepted foreign charity" — broadly, a genuine foreign charity, managed from its home
jurisdiction, entitled to call itself a charity there. Article 21(5)/(6) then leave it alone: it may use the word
"charity" in Jersey.

We initially assumed that made an excepted foreign charity safe under Article 21 generally. It does not.

Article 22(3)(b) **defines** an excepted foreign charity as one that **"is not a registered charity"**. And
Article 21(1) prohibits any entity that is not a registered charity from **referring to itself as being
registered by the Commissioner**.

So **Article 21(1) bites on every excepted foreign charity, always, by definition.** Article 22 licenses the word
*"charity"*. It never licenses a claim of *registration*. They are different prohibitions and the exception
reaches only one of them. Oxfam GB, operating in Jersey as a textbook excepted foreign charity, may call itself a
charity — and commits an offence the moment it says it is registered with the Jersey Commissioner.

That is almost certainly the intended result. But it is not a result anyone stated, and we did not see it until
an assertion failed.

---

### 🟡 Finding 6 — Article 34(1) → 35(1): the appeal that is wrong on the law but cannot reach the court

**Article 34(1)** — appeal to the tribunal:

> on the ground that the decision of the Commissioner was **wrong or unreasonable** on its **merits, the facts,
> or the law**.

**Article 35(1)** — appeal from the tribunal to the court:

> on the ground that the decision was **unreasonable** having regard to all the circumstances of the case.

The trichotomy is gone, and so is "wrong". A decision that is **wrong on the law but not unreasonable** is
squarely within Article 34(1) and squarely **outside** Article 35(1). The tribunal can hear it; the court cannot.

The only route to the court on a pure point of law is Article 35(3) — the tribunal *may* refer a point of law.
That key is in the **tribunal's** hand, not the litigant's. A tribunal that is confidently, reasonably, and
comprehensively wrong about the law, and declines to refer, is the end of the road.

This may be a deliberate narrowing. It is a striking one, and the model states it flatly: the same appeal is
asserted **competent** before the tribunal and **incompetent** before the court.

---

### 🟡 Finding 7 — Article 4(4): a self-judging duty, and a missing word

Article 4(4) of the consolidated text reads:

> In performing his or her functions, the Commissioner must, **so far appears to him or her** to be reasonably
> practicable, seek to act in a way that…

The word "**as**" appears to be missing. We checked the underlying HTML of the official consolidation directly,
to rule out an error in our own extraction: the text really does read "so far appears to him or her". A trivial
slip, and we mention it only because we happened to trip over it.

The substantive point is the one underneath. "So far as appears **to him or her** to be reasonably practicable"
makes the duty **self-judging**: the standard is the Commissioner's own view of practicability, not the
tribunal's. Our test suite contains a pair of cases with **identical conduct** and an **identical event stream**,
which come out BREACH and FULFILLED respectively — the only difference being the Commissioner's own view of what
was practicable.

That is a real property of the drafting, not an artefact of the model. Whether it is the desired property is a
policy question.

---

### 🟡 Finding 8 — Article 8(4): the charity run from a spare bedroom

Article 11(4)(d) requires an applicant to **have** a principal address in Jersey "within the meaning of Article
8(4)". Article 8(4) tells you *which* address that is, by a three-limb cascade:

- (a) if the entity must have a registered office / business address in Jersey — that address;
- (b) if not — the main Jersey premises from which it is managed, **"unless the premises are a private dwelling
  house"**;
- (c) if neither (a) nor (b) applies — the Jersey address of one of the governors.

The sting is in limb (b). If the charity's only Jersey premises **is** a private dwelling house, limb (b) yields
**no address at all** — and the cascade falls through to limb (c). So a small charity run from someone's spare
bedroom still *has* a principal address, and can still be registered, provided some governor has a Jersey
address. Limb (c) catches it.

We flag this only because the drafting invites the opposite reading on a quick pass — "not a private dwelling
house" looks like a *disqualification*, and it is really a *routing instruction*. It is tested both ways.

---

### 🟢 Findings 9–20 — briefly

The remaining flagged calls, in one line each. All are in the source with `>>>` markers.

- **Sch 1 para 4(3) — three decisions cannot be delegated.** Registration (Art 11), refusal to deregister
  (Art 15(3)) and deregistration (Art 16) may not be exercised by staff, **however fully the Commissioner
  purports to authorise it**. The authorisation is irrelevant, and we made that computable: a clerk signing off
  a registration is *ultra vires* even with the Commissioner's blessing.
- **Art 20(5) — passing the test is not the same as having the power.** A 20-year disqualification against a
  person the court is satisfied is unfit on *both* Article 20(4) grounds passes the 20(4) gate and is *still*
  ultra vires, because 20(5) caps the period at 15 years. The trace of the court purporting to make it collapses
  to FULFILLED — there is no power there to exercise.
- **Art 28(3) — severability.** A required steps notice served on an organized religious charity is "invalid **to
  the extent that**" it requires a governor's removal. We refused to collapse that to one valid/invalid flag, and
  validated each *requirement* separately. The same notice yields
  `["removal of the governor", "the other steps"]` for an ordinary charity and `["the other steps"]` for an
  organized religious one. The removal is severed; the rest stands and remains enforceable.
- **Art 26(8) — privilege subtracts, it does not excuse.** Privileged material was never validly "required", so
  the requirement never existed. You therefore commit no offence by withholding it **even with no reasonable
  excuse** — a different mechanism from the Art 26(7) "without reasonable excuse" defence sitting beside it.
- **Arts 17(4) and 36(4) — the "merely" rhyme.** Both provide that a past act is not rendered an offence
  "**merely** by virtue of" a retrospective operation. The load-bearing word is *merely*: an act that was
  independently criminal stays criminal. The saving is not an amnesty. Both encoded as named safety properties
  and tested against an independently criminal act.
- **Art 9(6) — satisfaction lifts a prohibition; it does not create a duty.** "Must not enter … unless
  satisfied" means: satisfied ⇒ **may** enter. It does not mean satisfied ⇒ **must** enter.
- **Art 12(4) — there is no duty to grant.** 12(4) obliges refusal on a ground; it is silent on the converse.
  Permission remains discretionary.
- **Art 37 — there is no "neglect" limb.** Most corporate-liability provisions catch "consent, connivance **or
  neglect**". Article 37 catches only consent or connivance. We did not supply the missing limb, and note its
  absence.
- **Art 14(1) — the court cannot act of its own motion.** "on an application by the Commissioner or the Attorney
  General" is read as a conjunct, not scene-setting.
- **Art 19(1)(a) — "being misconduct that led to the service of a required steps notice"** read as *restrictive*,
  not appositive: bare misconduct with no notice is not a reportable matter.
- **Art 19(10)'s "unless"** read as a conjunction: permission **and** compliance with its conditions. A governor
  with permission who breaches its conditions is inside the prohibition.
- **Art 13(13) and Art 18(3) — "to the extent that"** appears twice more, and in neither case does the Law
  provide a calculus of *degree*. We collapsed each to a single boolean and said so.

---

## 7. Things the machine made us learn about logic (and could not hide)

This section is the honest one.

> ### 📘 Sidebar 8 — Four bits of logic you cannot avoid
>
> **(1) Vacuous truth.** Article 5(1)(a) says "**all** of its purposes are charitable or ancillary". What about
> an entity with **no purposes at all**? In logic, "all of them are X" is **true** when there are none — there is
> no counterexample. So the empty shell **passes** Article 5(1)(a).
>
> This is not a bug; it is what "all" means, and it is what your Law says. The exclusion happens instead at
> Article 5(1)(b): with no purposes, there are no purposes to which it can "give effect", so no public benefit is
> provided *in consequence*. We tested exactly this, and it is worth knowing **which limb is load-bearing** for
> the empty case — because if you ever amended 5(1)(b), you would be amending the only thing keeping empty shells
> off the register.
>
> **(2) The proviso is an implication, and implications are vacuously satisfied.** "If X, then Y" — a limb that
> only *bites* when X holds — is written `(NOT X) OR Y`. When X is false, the whole limb is **true**, i.e.
> satisfied. That is correct, and it is also a trap: a limb that is "satisfied" because it never applied looks
> exactly like a limb that is "satisfied" because it was complied with. Article 33(5)(b)'s "if the appellant has
> an interest in the registered name" is precisely this shape, which is why we had to decide (Finding 3) whether
> it is a condition or an implication. On the implication reading, an appellant with **no** interest in the name
> satisfies limb (b) *for free*.
>
> **(3) "Not proved" is not "proved not".** A model that says `NOT (misconduct m)` is saying *the facts as
> pleaded do not make out misconduct* — not *this person is innocent*. Everything in this corpus is relative to
> the facts you feed it. It answers "on these facts, does the provision bite?", never "what happened?".
>
> **(4) An identity element is not nothing.** Sidebar 1's trick — that quoted prose is TRUE under AND and FALSE
> under OR — is genuinely load-bearing. If you paste an inert line into the *wrong* kind of chain, it still does
> not change the answer. That is the whole point. But it means you cannot tell, by looking at an inert line alone,
> which chain it is in. **The indentation is the only thing that tells you** — which is Sidebar 2 again, from the
> other side.

**The low-code question, answered honestly.** We were asked to make this accessible. Most of it is: the domain
model reads like an interpretation Article, the AND/OR trees read like the Law, the duties read like duties, and
the worked examples read like worked examples. A drafter can review all of that without knowing what a compiler
is.

But the four items in Sidebar 8 are **irreducible**. They are not artefacts of L4; they would arise in any formal
treatment, including a rigorously careful prose one. Vacuous truth is *in your Law already* — "all of its
purposes", with no purposes — whether or not anyone formalises it. All formalisation did was make somebody
notice.

Our position is that this is the correct amount of logic to ask a drafter to learn: **roughly one page**. It is
less than the amount of statutory interpretation we would have to learn to do your job, and we would not expect
to be excused that either.

---

## 8. Where we had to invent numbers, and where we did not

A duty in L4 needs a deadline: `PARTY Commissioner MUST register WITHIN 30`. Your Law, very often, does not give
one. It says "**promptly**" (Art 13(6)), "**as soon as practicable**" (Art 5(8)), "**within a reasonable time**"
(Arts 16(1), 18(4)(d)(ii)), "**at any time**" (Art 19(8)), or it leaves the period to be prescribed by an Order
that we cannot see (Arts 11(8)(a), 36(2)).

We did not want to launder a guess into something that looks like a statutory figure. So:

- **Every deadline that is not in the Law is a flagged placeholder.** It carries a `>>>` marker at the site,
  saying so in terms. There are roughly forty of them. `grep '>>>' *.l4` will list them all.
- **Every deadline that *is* in the Law is encoded, tested, and tested at its boundary.** Schedule 1 para 4(9)'s
  four-month report longstop (4 months passes; 5 fails; **4 exactly** passes). Article 20(5)'s 15-year
  disqualification cap (15 lawful; 20 ultra vires). Schedule 2 para 1(1)'s "at least 4 and no more than 8"
  tribunal members (3 fails; 4 passes; 8 passes; 9 fails). Article 26(5)'s "the **longer** of one year and, if
  proceedings are commenced, until their conclusion" — including the corner where proceedings commence but
  conclude on day 200, and "the longer of" still gives you the year.

This is a genuine finding in itself, and a mildly uncomfortable one: **the open-textured deadlines are the parts
of the Law a machine cannot check.** "Promptly" is unfalsifiable until somebody litigates it. Every one of those
forty placeholders is a place where compliance cannot be monitored automatically, and where a supervisory body's
expectations are, in practice, doing the work the statute declined to do.

That is not a criticism — open texture is often exactly right, and precision has its own costs. But if anyone
ever asks why the Commissioner's compliance dashboard is harder to build than expected, this is the answer, and
it is forty items long.

---

## 9. What we deliberately did not model

Pure Order- and Regulation-making powers have no computable content. Encoding one would mean inventing the Order.
We did not. They are carried as labelled **inert-prose stubs** — the verbatim text, present in the file, marked as
having no operative logic — so that the corpus has **no silent gaps**. A reader scrolling through Part 4 will find
Article 13(8), (9), (10) and (12) exactly where they belong, quoted in full, and explicitly marked as carrying no
logic. That is the honest representation of "this provision does not decide anything by itself".

Where a power's *output* matters to a live rule — "any other circumstance **prescribed by the Minister by Order**"
in Article 16(1)(d) — we expose the output as a single boolean, so the disjunct stays live and the model does not
quietly under-approximate the Law.

---

## 10. How it was actually built (the process)

Since the process is part of what you asked about:

1. **Get the authentic text.** The consolidated HTML from jerseylaw.je, stripped to plain text, 2,586 lines. Every
   inert string in the corpus is pinned to it.
2. **Establish the idiom on the hardest thing first.** We hand-wrote Part 1 (Interpretation) and Part 3 (the
   charity test) and got them typechecking and passing, because those two files define the vocabulary and the
   central test that everything else refers to. They became the house style.
3. **Fan out.** With a validated exemplar in hand, seven parallel agents took the remaining Parts, each given the
   exact source line-range, the shared vocabulary, the two exemplars, and a hard requirement: *your file must
   typecheck and every assertion must pass, or the task has failed*.
4. **Verify independently.** We re-ran `l4 check` and `l4 run` on every file ourselves rather than trusting the
   reports. 754 assertions, 0 failures.

Two things went wrong, and both are instructive.

- One agent's first-draft **traces silently disagreed with their own comments**. It had written comments claiming
  a duty was breached, but the trace residuated to a *standing duty* instead, because the event stream stopped
  *inside* the deadline window rather than passing it. It caught this itself, probed the semantics on a scratch
  file, and fixed the traces. **A comment that lies about its trace is worse than no comment**, and this is a
  hazard specific to the regulative layer that we now know to watch for.
- Another agent asserted that an excepted foreign charity commits no Article 21 offence. The assertion **failed**,
  and that failure is Finding 5. It is the clearest single demonstration in the project of what the 754 assertions
  are actually *for*: they are not decoration, and they are not documentation. They are the part of the system
  that can tell you that you are wrong.

---

## 11. What this is not

- **It is not legal advice, and it is not a Jersey lawyer's reading.** Several of the twenty findings will have
  obvious answers we don't know.
- **It is not a substitute for the Law.** It is a reading of it, with its interpretive commitments written down
  instead of assumed. Where we chose, we said so, and you can flip the choice and re-run.
- **It does not decide facts.** Every model here answers "*on these facts*, does the provision bite?" It has
  nothing to say about what happened.
- **It is not finished.** The obvious next step is a single top-level entry point — feed in an application, get
  back "registered / refused, and here is the chain of Articles that got you there, with citations". Every part
  needed for that is present; nothing joins them up yet.

---

## 12. The one-paragraph version

Formalisation did not find bugs in the Charities (Jersey) Law 2014. It is, on the whole, a well-made Law — Article
6(5)'s anti-laundering limb and Article 28(3)'s severability are both nicer than they had to be. What
formalisation did was **refuse to skim**. It made us decide, out loud and in public, twenty questions that a
careful reader resolves silently and an ordinary reader never notices — and of those twenty, two (the `(ba)`
range in Article 2(3)(a), and the applicant who is neither registered nor refused under Article 11(4)/(5)) look
to us like they might be worth an amendment, and two more (Article 33(5)'s "at both times", and Article 35(1)'s
narrowing) look like they might be worth a policy decision that somebody made by accident.

That is what a machine that cannot skim is for.
