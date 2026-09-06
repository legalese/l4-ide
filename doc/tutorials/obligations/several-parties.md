# Several Parties

Three flatmates and one rent: all of these, any of these, one pays and the other repays, and paying in instalments — the arrangements that run today, and the two honest defects of the last one.

**Prerequisites:** [One Obligation](one-obligation.md) and [What Follows](what-follows.md) — the five parts, `#TRACE`, the "still owed" line, chains with `HENCE` and `LEST`, and the `ROR` you met in the second guarantee.

**Complete example:** [several-parties.l4](several-parties.l4), which holds every example below that runs today, in the order the page presents them.

---

## What You'll Build

The same flat, now let to three flatmates. Alice, Bob and Carol share it, Ms Ng is still the landlord, and the rent is still $1,500 a month, due by the seventh day. One debt, three people who owe it — and a lease can arrange that in several ways, each of which behaves differently the day somebody does not pay:

1. **Each owes a share.** $500 each; Alice paying hers does nothing for Bob.
2. **All three must sign** before the lease begins — and a single thing follows once they all have.
3. **Any one of them may pay the whole**, and that discharges everyone.
4. **One pays the whole, and the others repay their shares** to whoever paid.
5. **Any amounts, from anyone, until the rent is reached** — the way a shared household actually pays.

The first four are written with two words for combining obligations that are live at the same time: `RAND`, an _and_ between obligations: all of these; and `ROR`, an _or_ between obligations: any of these. The fifth is written with a rule that uses itself. All five run today. The last one runs with two defects that the page names, and that the next page, [What Is Coming](what-is-coming.md), is about.

---

## Step 1: Each Owes a Share — All of These

Three obligations, one per flatmate, each with its own share, its own deadline and its own breach, joined by `RAND`:

```l4
GIVETH A DEONTIC Actor Action
`each pays a share` MEANS
    (PARTY  Alice
     MUST   EXACTLY (Pay Alice `Ms Ng` 500)
     WITHIN 7
     HENCE  FULFILLED
     LEST   BREACH BY Alice BECAUSE "Alice's share was not paid")
    RAND
    (PARTY  Bob
     MUST   EXACTLY (Pay Bob `Ms Ng` 500)
     WITHIN 7
     HENCE  FULFILLED
     LEST   BREACH BY Bob BECAUSE "Bob's share was not paid")
    RAND
    (PARTY  Carol
     MUST   EXACTLY (Pay Carol `Ms Ng` 500)
     WITHIN 7
     HENCE  FULFILLED
     LEST   BREACH BY Carol BECAUSE "Carol's share was not paid")
```

Each side is a complete obligation in brackets. All three run against the same list of events at the same time, and the whole is fulfilled only when every one of them is. All three pay:

```l4
#TRACE `each pays a share` AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 500 AT 2
    PARTY Bob   DOES Pay Bob   `Ms Ng` 500 AT 3
    PARTY Carol DOES Pay Carol `Ms Ng` 500 AT 5
```

```
Result:
  FULFILLED
```

Two have paid and one has not:

```l4
#TRACE `each pays a share` AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 500 AT 2
    PARTY Bob   DOES Pay Bob   `Ms Ng` 500 AT 3
```

```
Result:
  FULFILLED AND FULFILLED AND PARTY Carol MUST EXACTLY Pay OF Carol, `Ms Ng`, 500 WITHIN 4 HENCE FULFILLED LEST (BREACH BY Carol BECAUSE "Carol's share was not paid")
```

The "still owed" line has three slots, joined by `AND` — that is how the screen writes `RAND` — and two of them are done. Read it as a checklist: Alice, done; Bob, done; Carol, $500 within four days.

Only Alice pays, and day 8 arrives:

```l4
#TRACE `each pays a share` AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 500 AT 2
    (`WAIT UNTIL` 8)
```

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY Bob
    BECAUSE "Bob's share was not paid"
```

Bob and Carol both failed, and the screen names Bob. When several sides of a `RAND` fail together, today's screen reports the first of the failing sides as written, not the list; [What Follows](what-follows.md) met the same thing with `ROR`. Keep it in mind when you read a breach from a group: the `BY` is one of the people at fault, not necessarily all of them.

And the case that shows what kind of arrangement this is. Alice, feeling generous, pays $500 twice, and Carol pays hers:

```l4
#TRACE `each pays a share` AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 500 AT 2
    PARTY Alice DOES Pay Alice `Ms Ng` 500 AT 3
    PARTY Carol DOES Pay Carol `Ms Ng` 500 AT 5
```

```
Result:
  FULFILLED AND PARTY Bob MUST EXACTLY Pay OF Bob, `Ms Ng`, 500 WITHIN 2 HENCE FULFILLED LEST (BREACH BY Bob BECAUSE "Bob's share was not paid") AND FULFILLED
```

Alice's second $500 did nothing for Bob. His obligation is his own, and only a payment _from Bob_ discharges it; Ms Ng has $1,500 and Bob is still two days from breach. That is what a divided debt means, and it is exactly what the lease said. If it is not what the lease meant, the arrangement is one of the next three.

---

## Step 2: Three Signatures, and What Cannot Yet Follow Them

The same `RAND` shape serves for "all three must sign before the lease begins":

```l4
GIVETH A DEONTIC Actor Action
`all three sign` MEANS
    (PARTY Alice MUST Sign Alice WITHIN 14 HENCE FULFILLED LEST BREACH BY Alice)
    RAND
    (PARTY Bob   MUST Sign Bob   WITHIN 14 HENCE FULFILLED LEST BREACH BY Bob)
    RAND
    (PARTY Carol MUST Sign Carol WITHIN 14 HENCE FULFILLED LEST BREACH BY Carol)
```

```l4
#TRACE `all three sign` AT 0 WITH
    PARTY Alice DOES Sign Alice AT 1
    PARTY Carol DOES Sign Carol AT 2
```

```
Result:
  FULFILLED AND PARTY Bob MUST Sign Bob WITHIN 12 HENCE FULFILLED LEST (BREACH BY Bob) AND FULFILLED
```

(`Sign`, and `Reimburse` in Step 4, are new acts in this file's cast; the companion declares them beside `Pay`.) With Bob's signature on day 9 the whole is `FULFILLED`. Now try to write the next sentence of the lease: _once all three have signed, the tenancy begins and the first month's rent falls due._ That is one thing, which should happen once, after the last signature — and there is nowhere to put it. `HENCE` belongs to one obligation. Written inside Alice's brackets, it fires when Alice signs, whether or not the others have; written inside all three, it fires three times. There is no `HENCE` for the group.

What you can do today is keep the follow-on as a rule of its own and, when you play it forward, give `#TRACE` the day of the last signature as its `AT`. What you cannot do is write, in one place, "when all of these are done, then this, once". That is the first thing [What Is Coming](what-is-coming.md) is about.

---

## Step 3: Any One of Them May Pay It All — Any of These

Now the arrangement that a common-law lawyer would call a joint promise of the same performance: the three of them promise one rent, and whichever of them pays it discharges the other two. Written with `ROR`:

```l4
rent MEANS 1500

GIVETH A DEONTIC Actor Action
`any one pays the rent` MEANS
    (PARTY  Alice
     MUST   EXACTLY (Pay Alice `Ms Ng` rent)
     WITHIN 7
     HENCE  FULFILLED
     LEST   BREACH BY Alice BECAUSE "the rent was not paid")
    ROR
    (PARTY  Bob
     MUST   EXACTLY (Pay Bob `Ms Ng` rent)
     WITHIN 7
     HENCE  FULFILLED
     LEST   BREACH BY Bob BECAUSE "the rent was not paid")
    ROR
    (PARTY  Carol
     MUST   EXACTLY (Pay Carol `Ms Ng` rent)
     WITHIN 7
     HENCE  FULFILLED
     LEST   BREACH BY Carol BECAUSE "the rent was not paid")
```

(`rent` is now a defined figure rather than a number written out, and the payment is written ``EXACTLY (Pay Bob `Ms Ng` rent)`` around the whole act. [What Follows](what-follows.md) said why: with a named figure, that is the spelling that works.)

Bob pays the whole rent on day 3:

```l4
#TRACE `any one pays the rent` AT 0 WITH
    PARTY Bob DOES Pay Bob `Ms Ng` 1500 AT 3
```

```
Result:
  FULFILLED
```

Everyone is discharged: one payment, by anyone, ends the whole. Bob pays $1,000 instead:

```l4
#TRACE `any one pays the rent` AT 0 WITH
    PARTY Bob DOES Pay Bob `Ms Ng` 1000 AT 3
```

```
Result:
  PARTY Alice MUST EXACTLY Pay OF Alice, `Ms Ng`, rent WITHIN 4 HENCE FULFILLED LEST (BREACH BY Alice BECAUSE "the rent was not paid") OR PARTY Bob MUST EXACTLY Pay OF Bob, `Ms Ng`, rent WITHIN 4 HENCE FULFILLED LEST (BREACH BY Bob BECAUSE "the rent was not paid") OR PARTY Carol MUST EXACTLY Pay OF Carol, `Ms Ng`, rent WITHIN 4 HENCE FULFILLED LEST (BREACH BY Carol BECAUSE "the rent was not paid")
```

Not the rent, so nothing is discharged, and all three alternatives stand with four days left. (The screen writes `rent` by name in the "still owed" line; it is $1,500.) And if nobody pays by the seventh:

```l4
#TRACE `any one pays the rent` AT 0 WITH
    (`WAIT UNTIL` 8)
```

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY Carol
    BECAUSE "the rent was not paid"
```

All three of them failed. The screen names Carol — the last of the three as written. This is the honest defect of `ROR` for a shared debt: the law says the three are in breach together, and today's screen reports one. Nothing on the screen is false; it is incomplete, and you should know that it is.

---

## Step 4: One Pays the Whole, the Others Repay a Share

The commonest real arrangement adds a second half to Step 3: whoever pays the rent is entitled to be repaid by the others. Civil codes call the whole arrangement _solidary_; common-law drafting calls it joint and several. Two flatmates here, to keep the screen readable. Each side of the choice is Step 3's obligation with a `HENCE` that names the repayment:

```l4
GIVETH A DEONTIC Actor Action
`one pays, the other repays` MEANS
    (PARTY  Alice
     MUST   EXACTLY (Pay Alice `Ms Ng` 1500)
     WITHIN 7
     HENCE  PARTY  Bob
            MUST   EXACTLY (Reimburse Bob Alice 750)
            WITHIN 30
            HENCE  FULFILLED
            LEST   BREACH BY Bob BECAUSE "Bob did not repay his half"
     LEST   BREACH BY Alice BECAUSE "the rent was not paid")
    ROR
    (PARTY  Bob
     MUST   EXACTLY (Pay Bob `Ms Ng` 1500)
     WITHIN 7
     HENCE  PARTY  Alice
            MUST   EXACTLY (Reimburse Alice Bob 750)
            WITHIN 30
            HENCE  FULFILLED
            LEST   BREACH BY Alice BECAUSE "Alice did not repay her half"
     LEST   BREACH BY Bob BECAUSE "the rent was not paid")
```

Bob pays the rent on day 3 and Alice repays him on day 20:

```l4
#TRACE `one pays, the other repays` AT 0 WITH
    PARTY Bob   DOES Pay Bob `Ms Ng` 1500     AT 3
    PARTY Alice DOES Reimburse Alice Bob 750  AT 20
```

```
Result:
  FULFILLED
```

Stop after Bob's payment, and look carefully at what is owed:

```l4
#TRACE `one pays, the other repays` AT 0 WITH
    PARTY Bob DOES Pay Bob `Ms Ng` 1500 AT 3
```

```
Result:
  PARTY Alice MUST EXACTLY Pay OF Alice, `Ms Ng`, 1500 WITHIN 4 HENCE (PARTY Bob MUST EXACTLY Reimburse OF Bob, Alice, 750 WITHIN 30 HENCE FULFILLED LEST (BREACH BY Bob BECAUSE "Bob did not repay his half")) LEST (BREACH BY Alice BECAUSE "the rent was not paid") OR PARTY Alice MUST EXACTLY Reimburse OF Alice, Bob, 750 WITHIN 30 HENCE FULFILLED LEST (BREACH BY Alice BECAUSE "Alice did not repay her half")
```

The right-hand side of the `OR` is what you expect: Alice must repay Bob $750 within thirty days. But the left-hand side is still there — Alice's own obligation to pay the rent, with four days left, and inside its brackets the repayment Bob would owe her if she did, which is not owed now — even though Ms Ng has been paid. Why? Because a `ROR` is settled only when one of its sides reaches the end of _its_ chain, and Bob's side has not: its chain runs on into the repayment. Until Alice repays, the choice is still open, and the file still regards Alice paying the rent herself as one way of closing it. Let day 7 pass with Bob paid and Alice not yet having repaid him:

```l4
#TRACE `one pays, the other repays` AT 0 WITH
    PARTY Bob DOES Pay Bob `Ms Ng` 1500 AT 3
    (`WAIT UNTIL` 8)
```

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY Alice
    BECAUSE "the rent was not paid" OR PARTY Alice MUST EXACTLY Reimburse OF Alice, Bob, 750 WITHIN 25 HENCE FULFILLED LEST (BREACH BY Alice BECAUSE "Alice did not repay her half")
```

Read that carefully, because it looks like a fourth kind of screen. The left-hand side has lapsed and prints as a breach, under the `DEONTIC BREACHED:` heading; the right-hand side, after the `OR`, is still live. The whole is not broken — a choice is broken only when every side is lost — and Alice's repayment on day 20 still ends it `FULFILLED`. A breach heading over an `OR` means one side is gone, not that the matter is closed.

Push that to its odd conclusion. Alice, not knowing Bob has paid, pays the rent too, on day 5:

```l4
#TRACE `one pays, the other repays` AT 0 WITH
    PARTY Bob   DOES Pay Bob   `Ms Ng` 1500 AT 3
    PARTY Alice DOES Pay Alice `Ms Ng` 1500 AT 5
```

```
Result:
  PARTY Bob MUST EXACTLY Reimburse OF Bob, Alice, 750 WITHIN 30 HENCE FULFILLED LEST (BREACH BY Bob BECAUSE "Bob did not repay his half") OR PARTY Alice MUST EXACTLY Reimburse OF Alice, Bob, 750 WITHIN 28 HENCE FULFILLED LEST (BREACH BY Alice BECAUSE "Alice did not repay her half")
```

Now the file says that _either_ Bob repays Alice _or_ Alice repays Bob will do — and whichever happens first closes the choice, leaving the other repayment unowed. Ms Ng has been paid twice, and the encoding has an opinion about the $750 that no lease would share.

The lesson is not that `ROR` is wrong; it is where the repayment was written. A follow-on written inside one side of a choice stays inside that side, and joins in the race. What the lease means — _the rent is a choice between the two of them; the repayment is a separate matter, between the two of them, that arises once the rent is paid_ — has no single place to be written today, because a `HENCE` cannot be attached to the choice as a whole. That is Step 2's gap again. In practice: keep the repayment as a rule of its own between the flatmates, played forward from the day of the payment, rather than nesting it inside the race.

---

## Step 5: Any Amounts, from Anyone, Until the Rent Is Reached

None of the four arrangements above is how three flatmates actually pay. What really happens is that Alice transfers $500, Bob transfers $500 the next day, Carol pays $500 on Friday — or Alice pays $1,000 and Carol $500 — and Ms Ng does not mind who paid what as long as $1,500 arrived by the seventh. The obligation is on the _total_, and it is discharged by _any_ payments that add up to it.

The way to write that today is a rule that uses itself. Given the balance still owed, it gives a choice: any flatmate may pay any amount, and _hence_ the same rule again, with the balance reduced by what was paid. When the balance reaches zero, the rule gives `FULFILLED` instead:

```l4
GIVEN balance IS A NUMBER
GIVETH A DEONTIC Actor Action
`rent still owed` balance MEANS
    IF   balance AT MOST 0
    THEN FULFILLED
    ELSE (PARTY  Alice
          MUST   Pay Alice `Ms Ng` amount
          WITHIN 7
          HENCE  `rent still owed` (balance MINUS amount)
          LEST   BREACH BY Alice BECAUSE "the rent was not paid in full")
         ROR
         (PARTY  Bob
          MUST   Pay Bob `Ms Ng` amount
          WITHIN 7
          HENCE  `rent still owed` (balance MINUS amount)
          LEST   BREACH BY Bob BECAUSE "the rent was not paid in full")
         ROR
         (PARTY  Carol
          MUST   Pay Carol `Ms Ng` amount
          WITHIN 7
          HENCE  `rent still owed` (balance MINUS amount)
          LEST   BREACH BY Carol BECAUSE "the rent was not paid in full")
```

Three things to notice. The rule has an input, `balance`, so the obligation you play forward is `` `rent still owed` 1500 ``: the rule used with the full rent. Each payment is a shape with a blank, `amount`, filled by whatever the flatmate paid, exactly as in [What Follows](what-follows.md). And each `HENCE` hands the reduced balance back to the same rule — the pattern that page taught, of handing a figure to a rule that gives the next obligation, used to give the _same_ obligation with a smaller number in it.

Three payments of $500:

```l4
#TRACE `rent still owed` 1500 AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 500 AT 2
    PARTY Bob   DOES Pay Bob   `Ms Ng` 500 AT 3
    PARTY Carol DOES Pay Carol `Ms Ng` 500 AT 5
```

```
Result:
  FULFILLED
```

Two unequal payments, $1,000 and $500, give the same answer. Now stop after one instalment, Alice's $500 on day 2:

```l4
#TRACE `rent still owed` 1500 AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 500 AT 2
```

```
Result:
  PARTY Alice MUST Pay Alice `Ms Ng` amount WITHIN 7 HENCE (`rent still owed` OF (balance MINUS amount)) LEST (BREACH BY Alice BECAUSE "the rent was not paid in full") OR PARTY Bob MUST Pay Bob `Ms Ng` amount WITHIN 7 HENCE (`rent still owed` OF (balance MINUS amount)) LEST (BREACH BY Bob BECAUSE "the rent was not paid in full") OR PARTY Carol MUST Pay Carol `Ms Ng` amount WITHIN 7 HENCE (`rent still owed` OF (balance MINUS amount)) LEST (BREACH BY Carol BECAUSE "the rent was not paid in full") OR PARTY Bob MUST Pay Bob `Ms Ng` amount WITHIN 5 HENCE (`rent still owed` OF (balance MINUS amount)) LEST (BREACH BY Bob BECAUSE "the rent was not paid in full") OR PARTY Carol MUST Pay Carol `Ms Ng` amount WITHIN 5 HENCE (`rent still owed` OF (balance MINUS amount)) LEST (BREACH BY Carol BECAUSE "the rent was not paid in full")
```

Two things to notice in that line, both consequences of what the earlier steps taught. It never says that $1,000 is still owed: the balance is written as `balance MINUS amount`, unfilled, because the screen prints the rule as written rather than the number. And it has five sides, not three: Alice's payment produced a fresh choice of three (`WITHIN 7`), while the two untouched sides of the first choice, Bob's and Carol's, are still standing on their old clocks (`WITHIN 5`) — for Step 4's reason, that a side whose chain runs on does not close the choice. Now the two defects.

**The clock restarts after every payment.** The rent was due by day 7. Alice pays $500 on day 6, Bob on day 12, Carol on day 18:

```l4
#TRACE `rent still owed` 1500 AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 500 AT 6
    PARTY Bob   DOES Pay Bob   `Ms Ng` 500 AT 12
    PARTY Carol DOES Pay Carol `Ms Ng` 500 AT 18
```

```
Result:
  FULFILLED
```

L4 says the rent was paid in time. It was not: two-thirds of it arrived after the seventh. The reason is in the rule. Each `HENCE` gives a _fresh_ obligation, and a fresh obligation gets a fresh `WITHIN 7`, counted from the payment that produced it. The lease has one deadline on the total; the rule has a new deadline after every instalment. You might think to fix it by handing the days left down along with the balance — but the rule has no way to see _when_ a payment happened, only how much it was, so it cannot count the days down.

**When nobody pays, one flatmate is blamed.** Day 8 arrives with nothing paid:

```l4
#TRACE `rent still owed` 1500 AT 0 WITH
    (`WAIT UNTIL` 8)
```

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY Carol
    BECAUSE "the rent was not paid in full"
```

This is Step 3's defect again, and it bites harder here: the debt is everyone's, and the screen names the flatmate written last.

Both defects have the same root. What the lease describes is a single obligation on a _state_ — the amount received — with one deadline and one group in breach; what L4 lets you write today is a race between obligations on _acts_, each with its own deadline and its own breach. The proposal on the next page is a way to write the first thing directly: one line saying when enough has been paid, one deadline on that line, and a breach that names everyone.

---

## The Map

Six arrangements of one debt have now appeared across this page and the last, and it is worth seeing them in one table, because the law distinguishes them first by a question the words _joint_ and _several_ never quite ask: does one person's payment discharge the others?

| The arrangement                                          | One payment discharges the others? | Written with today                                               | What is missing today                                   |
| -------------------------------------------------------- | ---------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------- |
| each owes a share (Step 1)                               | no                                 | `RAND`, one obligation per person                                | nothing                                                 |
| all must act, then one thing follows (Step 2)            | no                                 | `RAND` — but with no place for the one thing                     | a follow-on for the group                               |
| any one may pay the whole (Step 3)                       | yes                                | `ROR`                                                            | a breach that names everyone                            |
| one pays the whole, the others repay a share (Step 4)    | yes, then repayment                | `ROR` with the repayment inside each side                        | a follow-on for the choice as a whole                   |
| any amounts until the total is reached (Step 5)          | to the extent paid                 | a rule that uses itself, over `ROR`                              | one deadline on the total; a breach that names everyone |
| a guarantor ([What Follows](what-follows.md), Steps 4–5) | yes, in sequence                   | `LEST` (pays only after default) or `ROR` (may be pursued first) | nothing                                                 |

Read the last column as the agenda for [What Is Coming](what-is-coming.md).

---

## What You Learned

- **`RAND` is all of these**: every side must reach its end; the "still owed" line is a checklist joined by `AND`; one person's act discharges only that person's side.
- **`ROR` is any of these**: the first side to reach its end settles the whole; the "still owed" line is joined by `OR`; the whole is broken only when every side is lost.
- **A breach from a group names one person**, not all who failed together: the first written for `RAND`, the last for `ROR`. Read the `BY` as one of the people at fault.
- **A follow-on belongs to one obligation, not to a group or a choice**, so "when all have done this, then that, once" cannot be written in one place today, and a repayment nested inside one side of a choice joins the race.
- **A rule that uses itself** turns a debt into instalments — with a clock that restarts on every instalment and a breach that names one payer.
- **Six arrangements of one debt** are told apart by whether one payment discharges the others, and by where the follow-on attaches. Two run with nothing missing; the other four each run with a stated gap.

---

## Next Steps

- [What Is Coming](what-is-coming.md) — the proposed pieces that close the gaps in the last column: everyone-then-one-thing, each-with-its-own, and "enough of them"
- [The Regulative Layer, Whole](../../concepts/legal-modeling/regulative-layer-whole.md) — the five separate ideas, and this page's place among them
- [Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md) — who may perform which act, in full, with what is and is not checked
- [Regulative Rules](../../concepts/legal-modeling/regulative-rules.md) — `RAND`, `ROR`, and recursive obligations in the reference-style account
