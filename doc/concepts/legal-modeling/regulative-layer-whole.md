# The Regulative Layer, Whole

Five separate questions make up an obligation in L4. This page asks all five of one lease, shows that each can be answered without touching the others, and draws the line through them between what is built and what is only proposed.

**Who this is for.** A reader who has met the pieces — an obligation, a chain, `RAND` and `ROR`, a trace, the performer rule — and does not yet see how they fit. If you have met none of them, the tutorial series [One Obligation](../../tutorials/obligations/one-obligation.md) → [What Follows](../../tutorials/obligations/what-follows.md) → [Several Parties](../../tutorials/obligations/several-parties.md) builds them up one screen at a time; this page is the map to come back to. The reference-style account of the same material is [Regulative Rules](regulative-rules.md).

**Example file:** [regulative-layer-whole-example.l4](regulative-layer-whole-example.l4). Every piece of L4 on this page that runs today is in it; the pieces marked proposed are not, because they do not run.

---

## The lease

One example is threaded through the whole page, so that the five questions are visibly five questions about _one thing_. Ms Ng lets a flat. Alice is the tenant; later Bob shares it; Alice's father, Mr Lim, guarantees the rent. The rent is $1,500 a month, due by the seventh day. When it is paid, Ms Ng issues a receipt.

Before any of the five questions — it is Question 4, answered first, because every other question uses its answer — the file says who can act and what can be done:

```l4
DECLARE Actor IS ONE OF Alice, Bob, `Ms Ng`, `Mr Lim`

DECLARE Action IS ONE OF
    Pay     HAS payer  IS AN Actor
                payee  IS AN Actor
                amount IS A NUMBER
    Receipt HAS issuer IS AN Actor
                to     IS AN Actor
                amount IS A NUMBER
    Inspect HAS inspector IS AN Actor
```

Everything that runs below uses these two declarations unchanged. That is the first sign that the questions are separate: the cast and the acts are settled once, and none of the five answers needs to alter them.

---

## Question 1. What is one obligation?

_Who must do what, by when, and then what?_ An obligation in L4 is one unit with five parts, in a fixed order, and L4's name for that unit — from the Greek word for a duty — is a **"Deonton"**:

```l4
GIVETH A DEONTIC Actor Action
`the rent is due` MEANS
    PARTY  Alice
    MUST   EXACTLY (Pay Alice `Ms Ng` 1500)
    WITHIN 7
    HENCE  FULFILLED
    LEST   BREACH BY Alice BECAUSE "the rent was not paid by the seventh day"
```

| Part                     | Question it answers                                      | What may go there                                                                               |
| ------------------------ | -------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `PARTY`                  | who is bound                                             | one member of the cast                                                                          |
| `MUST` / `MAY` / `SHANT` | what, and whether it is a duty, a right or a prohibition | an act — exactly this one (`EXACTLY`), or a shape to be matched (Question 3)                    |
| `WITHIN`                 | by when                                                  | a number of your units, counted from when the obligation begins; omit it for an open-ended duty |
| `HENCE`                  | then what, if it goes well                               | `FULFILLED`, or another obligation (Question 2)                                                 |
| `LEST`                   | then what, if it goes badly                              | `BREACH`, with `BY` whom and `BECAUSE` why, or another obligation (Question 2)                  |

`DEONTIC Actor Action` is the kind of thing an obligation is — the word programming language theorists would call its type, given in the same place a rule that gives a number says `GIVETH A NUMBER` — and the two names after it say whose acts and which acts it is about. There is also a fourth word, `DO`, which this page does not use; the keyword reference describes it.

Played forward (Question 3), one obligation ends in one of three ways, and this is the fixed vocabulary of the whole layer:

| Outcome                       | The screen says                                             | Meaning                                                            |
| ----------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------ |
| fulfilled                     | `FULFILLED`                                                 | it ended, and nothing more is owed                                 |
| breached                      | `DEONTIC BREACHED:` then `BREACH`, `BY` whom, `BECAUSE` why | it ended badly, and this is who and why                            |
| still owed (a **"residual"**) | the obligation written back out, with its `WITHIN` reduced  | it has not ended; this is where things stand, and how long is left |

The third is the important one. It is a complete obligation in its own right — a snapshot that could be given more events tomorrow and carried on from — which is what lets a long-running lease be examined at any point in its life.

The three words `MUST`, `MAY` and `SHANT` change which event triggers which outcome, and nothing else. A duty's good outcome is the act happening; a prohibition's good outcome is the deadline passing with no act; a right has no bad outcome at all.

**Built:** all of this. It is the oldest part of the layer.

---

## Question 2. How do obligations combine?

_What comes after this one — and what is live at the same time as it?_ Two entirely different ways of combining, and a lease uses both.

**In sequence.** `HENCE` and `LEST` can each name a further obligation instead of `FULFILLED` or `BREACH`, and the result is a chain. A receipt follows the payment; a guarantor's duty follows the tenant's default:

```l4
GIVETH A DEONTIC Actor Action
`rent, receipt, guarantee` MEANS
    PARTY  Alice
    MUST   EXACTLY (Pay Alice `Ms Ng` 1500)
    WITHIN 7
    HENCE  PARTY  `Ms Ng`
           MUST   EXACTLY (Receipt `Ms Ng` Alice 1500)
           WITHIN 5
           HENCE  FULFILLED
           LEST   BREACH BY `Ms Ng` BECAUSE "no receipt was issued"
    LEST   PARTY  `Mr Lim`
           MUST   EXACTLY (Pay `Mr Lim` `Ms Ng` 1500)
           WITHIN 14
           HENCE  FULFILLED
           LEST   BREACH BY `Mr Lim` BECAUSE "the guarantor did not pay the rent"
```

A chain ends at a `FULFILLED` or a `BREACH`, and the screen, when a chain is still owed, shows only the link that has been reached. A `LEST` that names an obligation is how a lease says grace period, late fee, penalty or guarantee: the failure of one link starts another. The literature on contract logic calls that a reparation chain, and L4 spells it `LEST`.

**At the same time.** `RAND` (all of these) and `ROR` (any of these) join obligations that are live together and run against the same events. Two flatmates who each owe a share, and two who may either of them pay the whole:

```l4
GIVETH A DEONTIC Actor Action
`two shares` MEANS
    (PARTY Alice MUST EXACTLY (Pay Alice `Ms Ng` 750) WITHIN 7 HENCE FULFILLED LEST BREACH BY Alice)
    RAND
    (PARTY Bob   MUST EXACTLY (Pay Bob   `Ms Ng` 750) WITHIN 7 HENCE FULFILLED LEST BREACH BY Bob)

GIVETH A DEONTIC Actor Action
`either pays the whole` MEANS
    (PARTY Alice MUST EXACTLY (Pay Alice `Ms Ng` 1500) WITHIN 7 HENCE FULFILLED LEST BREACH BY Alice)
    ROR
    (PARTY Bob   MUST EXACTLY (Pay Bob   `Ms Ng` 1500) WITHIN 7 HENCE FULFILLED LEST BREACH BY Bob)
```

`RAND` is fulfilled when every side is; `ROR` is fulfilled when any side is, and is broken only when every side has been lost. Without brackets, `A RAND B ROR C` is read as `(A RAND B) ROR C`; bracket every side, as the tutorials do. In a "still owed" line the screen writes them `AND` and `OR`.

Two things about combining that are true today and that a reader should carry:

- **A follow-on belongs to one obligation.** There is no `HENCE` for a `RAND` or a `ROR` as a whole. "When all have signed, then this, once" has no single place to be written, and a follow-on nested inside one side of a choice stays inside that side and joins the race. [Several Parties](../../tutorials/obligations/several-parties.md), Steps 2 and 4, shows both.
- **A breach from a group names one person.** When several sides of a `RAND` or `ROR` fail together, the screen reports a single side — the first written for `RAND`, the last for `ROR` — rather than everyone who failed. The rule is written into L4 itself, as a tie-break between two breaches, and the tutorials call it the honest defect.

**Built:** chains, `RAND`, `ROR`, and a rule that gives an obligation and uses itself (instalments). **Not built:** a follow-on for a group, and a breach that names a set. Both are Question 5.

---

## Question 3. What happened?

_Against which events is the obligation played, and how does an event match an act?_ An obligation by itself decides nothing. It is played forward with `#TRACE`: a starting time, then events, each saying who did what and when, consumed in order:

```l4
#TRACE `the rent is due` AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 1500 AT 5
```

```
Result:
  FULFILLED
```

The rules of the clock are few and worth having in one place:

- the deadline day itself is in time (`WITHIN 7` includes day 7);
- time passes only through events, so ``(`WAIT UNTIL` 8)`` is how to say "day 8 came and nobody did anything";
- an event that does not fit the obligation is passed over, but the clock still moves to its time;
- a chain's next clock starts at the event that reached it — for `HENCE`, the act; for `LEST`, the first event _after_ the deadline, which is the moment the default comes to light, and not the deadline itself.

**How an event matches an act** is the part of this question that carries the most weight, because it is where a fact from the world enters the obligation. Two ways:

- **Exactly this act.** ``EXACTLY (Pay Alice `Ms Ng` 1500)``: the event must be this payment and no other. $1,000 does not count; Bob's payment does not count.
- **An act of this shape.** ``Pay Alice `Ms Ng` amount PROVIDED amount AT LEAST 1500``: a payment from Alice to Ms Ng of _some_ amount. `amount` is not defined anywhere — it is a blank, and the matching event fills it. `PROVIDED` then tests the filled blank, and a payment that fails the test is passed over as if it had not fitted.

A blank filled from an event can be used in the `PROVIDED` test and can be handed to a rule that gives the next obligation — which is how a figure from the world travels down a chain:

```l4
GIVEN who    IS AN Actor
      amount IS A NUMBER
GIVETH A DEONTIC Actor Action
`a receipt to` who amount MEANS
    PARTY  `Ms Ng`
    MUST   EXACTLY (Receipt `Ms Ng` who amount)
    WITHIN 5
    HENCE  FULFILLED
    LEST   BREACH BY `Ms Ng` BECAUSE "no receipt was issued"

GIVETH A DEONTIC Actor Action
`rent, any amount over` MEANS
    PARTY  Alice
    MUST   Pay Alice `Ms Ng` amount PROVIDED amount AT LEAST 1500
    WITHIN 7
    HENCE  `a receipt to` Alice amount
    LEST   BREACH BY Alice BECAUSE "the rent was not paid by the seventh day"
```

One limit, measured on the current release: `EXACTLY` around a single figure, `(EXACTLY 1500)`, works only when the figure is written out as a number. With a defined name, a rule's input or a blank it stops with an internal error, so use `EXACTLY` around the whole act, which has no such limit. That is not a design, and it is why the tutorials use the spelling they use. The blank can equally be read inside a next obligation written directly under `HENCE`; the rule above is preferred because it can be used from more than one place.

The time of an event is not something an obligation can read: there is no blank for it. That is why a rule that pays a debt in instalments cannot carry a single deadline down through the instalments (Question 5).

**Built:** all of this, with the two limits stated.

---

## Question 4. Who may act?

_Which member of the cast may be bound to, or perform, which act?_ The answer is a convention and a check.

The convention: **the first member of the cast named inside an act is the one who performs it** — the payer of a payment, the issuer of a receipt, the inspector of an inspection. This is why the cast is a list of people and every act carries its people as its first details. It reads as English does: subject, verb, object.

The check: the party in front of `MUST` (or `MAY`, or `SHANT`), and the party in front of `DOES` in an event, must be that performer. Alice cannot be bound to Ms Ng's inspection, and no event can record Alice performing it:

```l4
`inspect the flat` MEANS Inspect `Ms Ng`

GIVETH A DEONTIC Actor Action
`wrong party` MEANS
    PARTY Alice MUST `inspect the flat` WITHIN 30 HENCE FULFILLED LEST BREACH BY Alice
```

```
An actor may only perform its own actions.
  `inspect the flat` is performed by `Ms Ng`, not by `Alice`.
```

Three consequences follow from the convention, and each is its own small feature:

- **One act, both directions.** An act with two people in it — a message with a sender and a receiver, a payment with a payer and a payee — is performed by whoever is named first, so one act serves both directions. Bob paying Alice and Alice paying Bob are the same `Pay` with the names swapped.
- **An act with the doer left open.** A rule can give an act with its performer as an input:

  ```l4
  GIVEN who    IS AN Actor
        amount IS A NUMBER
  GIVETH AN Action
  `payment by` who amount MEANS Pay who `Ms Ng` amount

  GIVETH A DEONTIC Actor Action
  `rent, by whoever is named` MEANS
      PARTY  Alice
      MUST   EXACTLY (`payment by` Alice 1500)
      WITHIN 7
      HENCE  FULFILLED
      LEST   BREACH BY Alice
  ```

  Such an act must be written into an obligation with `EXACTLY`, because a bare rule name in that position is read as a shape to be matched, not a rule to be used, and L4 reports that it cannot find a definition for it. The check still fires: `PARTY Bob` in front of `` `payment by` Alice 1500 `` is rejected.

- **Procuring an act.** "Ms Ng undertakes to procure that her agent inspects" is an act that wraps another act; the outer obligation binds the procurer and the inner act keeps its own performer, so principal and agent are told apart by the check. [Actors, Actions, and Agreement](actors-and-actions.md) works this through.

What is checked, exactly, was measured for this page. The check fires wherever the performer can be read from the text: a named person, a named act, a rule's own inputs compared by name. It is silent for a person built on the spot from particulars — `Tenant OF "Bob"` written directly into an obligation — because such a person is made up as the file runs, and there is no list to check against; and it is silent when the act is declared in another file and brought in with `IMPORT`. A cast with particulars is not shown on this page; [Actors, Actions, and Agreement](actors-and-actions.md) has one. So a cast written as a fixed list, as on this page, is checked throughout; a cast whose members carry details is checked only where those members are given names.

One more thing the cast settles. A cast is a type, and no cast is a special case of another — what programming language theorists call **"subtyping"** does not exist here. `Landlord` and `Tenant` are two members of one `Actor` type, not two types with something in common. A name that is not on the cast list is a plain error saying L4 could not find a definition for it; a party from a different cast is an error about the kind of thing the obligation is about.

**Built:** all of this.

---

## Question 5. What about a group?

_When the same obligation falls on everyone in a group, what can be said about the group?_ This is the question the four above cannot answer, and it is the proposed part of the layer.

_Proposed, not landed (2026-09-06): everything in this section. The design is `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md`; its section on "enough of them" was added on 2026-09-06. Nothing here runs, and the spellings are the design document's current ones. [What Is Coming](../../tutorials/obligations/what-is-coming.md) gives each piece a page's worth of explanation._

_Settled on 7 September 2026: the word after `EVERY` or `EACH` names the kind of party and picks out the group, as `Flatmate` does in the table; `EVERY f` with no kind word means every party there is._

Three pieces, each answering a question the others do not:

| Piece                    | Question                                              | Proposed spelling                                                     |
| ------------------------ | ----------------------------------------------------- | --------------------------------------------------------------------- |
| everyone, then one thing | after all of them have acted, what follows — once?    | `EVERY Flatmate f MUST … HENCE …` (a **"barrier"**)                   |
| each with its own        | after each of them acts, what follows — for that one? | `EACH Flatmate f MUST … HENCE …` (a **"fork"**)                       |
| enough of them           | when has enough happened for the follow-on to fire?   | `ONCE sum OF amount AT LEAST rent`, `SOME 2 OF …` (a **"threshold"**) |

The first two differ only in where the follow-on attaches, and without a follow-on they are the same thing. The third is independent of both: it says _when_ the follow-on fires — a count of the group, or a total — and the design notes that its two ends are things you already have: "once any one has" is `ROR`, "once all have" is `RAND` with a single follow-on. `SOME m OF` means _at least_ m; that is the one ruling in this part of the design that has been given.

The rent, in the proposed form, shows all three at once — a group, a receipt per payment, and a deadline on the total with a breach that names everyone. The `MAY` inside has no bad outcome of its own; the `WITHIN`, `HENCE` and `LEST` at the end belong to the `ONCE` line:

```l4
-- PROPOSED, NOT LANDED (2026-09-06). Does not run.
EVERY Flatmate f
    MAY    Pay f `Ms Ng` amount
    UPON   EACH
    HENCE  PARTY `Ms Ng` MUST Receipt `Ms Ng` f amount WITHIN 5
ONCE   sum OF amount AT LEAST 1500
WITHIN 7
HENCE  FULFILLED
LEST   BREACH BY EVERY Flatmate
```

---

## Why these are five questions and not one

Set the five side by side, and say what separate means: an answer to one question never constrains the answer to another. A `MAY` chains exactly as a `MUST` does; a shape with a blank sits under a `RAND` exactly as an exact act does; a fixed cast or one with particulars changes no obligation's five lines.

| Question                   | Asked of                       | Its choices                                          | Changing it leaves alone                            |
| -------------------------- | ------------------------------ | ---------------------------------------------------- | --------------------------------------------------- |
| 1. What is one obligation? | one `PARTY … LEST` block       | duty / right / prohibition; deadline or none         | how it combines, what happened, who may act         |
| 2. How do they combine?    | two or more obligations        | in sequence (`HENCE`/`LEST`); at once (`RAND`/`ROR`) | the first three lines of each; the cast; the events |
| 3. What happened?          | the trace and the act-matching | exact act, or shape plus test                        | the obligations; the cast                           |
| 4. Who may act?            | the cast and the acts          | a fixed list, or people with details                 | everything else — it is settled before any of it    |
| 5. What about a group?     | an obligation on everyone      | once-after-all; once-each; enough-of-them            | 1 through 4, all of which it is built on            |

The lease made the point concretely. The declarations at the top of the page never changed. The rent obligation in Question 1 was reused unchanged in the trace in Question 3; the chain in Question 2 kept its first three lines and rewrote its last two, which is where a chain lives. The `RAND` and the `ROR` in Question 2 would take a shape-matched side as readily as an exact one — [Several Parties](../../tutorials/obligations/several-parties.md), Step 5, puts shapes with blanks under a `ROR`. And the performer check in Question 4 applied identically to every obligation, chain, race and trace on the page, because it is a fact about the cast and the acts, not about any obligation.

One place where two questions meet deserves to be named, because it is where readers most often feel the pieces do not fit. Question 2's `RAND` and `ROR` combine obligations you have written out one by one; Question 5's pieces are for an obligation that is the same for everyone in a group. The six arrangements of one debt in [Several Parties](../../tutorials/obligations/several-parties.md) — each owes a share; all must act then one thing; any one may pay the whole; one pays and the others repay; any amounts to a total; a guarantor — are all combinations of Question 2's two ways of combining, and the last column of that page's table is exactly the list of things Question 5 adds: a follow-on for the group, one deadline on a total, a breach that names a set.

---

## Built, and proposed

| Built, in the current release                                                                                         | Proposed, not landed (2026-09-06)                                                             |
| --------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| the five-part obligation; `MUST`, `MAY`, `SHANT`, `DO`; `WITHIN`; `FULFILLED`, `BREACH BY … BECAUSE …`                | `EVERY` / `EACH` for a group                                                                  |
| chains through `HENCE` and `LEST`; a rule that gives an obligation, including one that uses itself                    | `ONCE` with a count or a total; `SOME m OF` ≡ `AT LEAST m OF`                                 |
| `RAND`, `ROR`, and how they group without brackets                                                                    | a follow-on attached to a `RAND` or `ROR` as a whole                                          |
| `#TRACE`, `AT`, `DOES`, `WAIT UNTIL`; the inclusive deadline; the clock rules for `HENCE` and `LEST`                  | a breach that names every party who failed                                                    |
| `EXACTLY` around the whole act; a shape with a blank; `PROVIDED`; handing a blank to a rule                           | `EXACTLY` around a named figure (today, only around the whole act)                            |
| the cast as a fixed list; the performer convention and check; one act in both directions; open-doer acts; procurement | an obligation that says whom it is owed to (the layer has a party and an act, but no obligee) |

The last row of the right-hand column is one the design documents record as the next axis after this one, and it is not on this page: an L4 obligation says who is bound and to do what, but not to whom it is owed, so "payment to any one of several creditors discharges the debt" cannot yet be written at all.

---

## Further reading

- [One Obligation](../../tutorials/obligations/one-obligation.md), [What Follows](../../tutorials/obligations/what-follows.md), [Several Parties](../../tutorials/obligations/several-parties.md), [What Is Coming](../../tutorials/obligations/what-is-coming.md) — the tutorial series this page maps
- [Regulative Rules](regulative-rules.md) — the reference-style account: defaults, the lifecycle, reparation, recursion
- [Actors, Actions, and Agreement](actors-and-actions.md) — Question 4 in full, with what is and is not checked
- [Constitutive vs Regulative Rules](constitutive-vs-regulative.md) — why definitions and duties are kept apart
- [Regulative keyword reference](../../reference/regulative/README.md) — every keyword on this page, one entry each
