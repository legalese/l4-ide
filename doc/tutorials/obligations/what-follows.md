# What Follows

What to write after `HENCE` and after `LEST`: a receipt follows a payment, a late fee follows a missed one, and a guarantor pays when the tenant does not.

**Prerequisites:** [One Obligation](one-obligation.md) — the five parts of an obligation, `#TRACE`, and the three things the screen can say. This page assumes you have met all three and can read the "still owed" line.

**Complete example:** [what-follows.l4](what-follows.l4), which holds every example below that runs today, in the order the page presents them.

---

## What You'll Build

The same tenancy. Ms Ng lets a flat to Alice; the rent is $1,500, due by the seventh day of the month. [One Obligation](one-obligation.md) wrote the rent clause on its own, with `HENCE FULFILLED` and `LEST BREACH`. A real lease rarely stops there. It says what comes next:

- **When Alice pays, Ms Ng must issue a receipt within five days.**
- **If Alice misses the seventh, she may still pay within fourteen more days, with a $50 late fee.**
- **Alice may pay more than the rent, and the receipt is for whatever she paid.**
- **Alice's father, Mr Lim, guarantees the rent** — and there are two quite different things that sentence can mean.

Each of those is written by putting something other than `FULFILLED` or `BREACH` after `HENCE` or `LEST`. What goes there is another obligation. That is the whole idea of this page: **the two "then what" lines can each name a further obligation, and a lease is a chain of them.**

---

## Step 1: A Receipt Follows the Payment

Here is the rent clause with the receipt written into its `HENCE`:

```l4
GIVETH A DEONTIC Actor Action
`rent, then receipt` MEANS
    PARTY  Alice
    MUST   EXACTLY (Pay Alice `Ms Ng` 1500)
    WITHIN 7
    HENCE  PARTY  `Ms Ng`
           MUST   EXACTLY (Receipt `Ms Ng` Alice 1500)
           WITHIN 5
           HENCE  FULFILLED
           LEST   BREACH BY `Ms Ng` BECAUSE "no receipt was issued"
    LEST   BREACH BY Alice BECAUSE "the rent was not paid by the seventh day"
```

Read it from the outside in. The outer obligation is Alice's: pay by day 7, or breach. Its `HENCE` — what follows if she does — is a second, complete obligation, indented underneath: Ms Ng must issue a receipt within five days, or she is the one in breach. The second obligation has its own five parts, its own deadline and its own `HENCE` and `LEST`, and the chain ends at its `HENCE FULFILLED`.

(`Receipt` is a new act in this file's cast — an issuer, who it is to, and an amount — and Mr Lim, who arrives in Step 4, is a new person in it. The companion file declares both.)

Alice pays on day 6, and Ms Ng issues the receipt on day 11:

```l4
#TRACE `rent, then receipt` AT 0 WITH
    PARTY Alice   DOES Pay Alice `Ms Ng` 1500     AT 6
    PARTY `Ms Ng` DOES Receipt `Ms Ng` Alice 1500 AT 11
```

```
Result:
  FULFILLED
```

**The second clock starts when the first obligation is done.** Ms Ng's five days run from day 6, when Alice paid, so day 11 is the last day. A receipt on day 12 is one day late:

```l4
#TRACE `rent, then receipt` AT 0 WITH
    PARTY Alice   DOES Pay Alice `Ms Ng` 1500     AT 6
    PARTY `Ms Ng` DOES Receipt `Ms Ng` Alice 1500 AT 12
```

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY `Ms Ng`
    BECAUSE "no receipt was issued"
```

Notice who is in breach. Alice did everything she had to. The chain moved on to Ms Ng's obligation, and that is the one that failed, so the screen names Ms Ng and prints the sentence written against her obligation, not Alice's.

Now stop the story after Alice's payment:

```l4
#TRACE `rent, then receipt` AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 1500 AT 6
```

```
Result:
  PARTY `Ms Ng` MUST EXACTLY Receipt OF `Ms Ng`, Alice, 1500 WITHIN 5 HENCE FULFILLED LEST (BREACH BY `Ms Ng` BECAUSE "no receipt was issued")
```

The "still owed" line no longer mentions Alice at all. What is still owed is the receipt, and it is owed by Ms Ng. A chain, played forward, shows you only the link you have reached.

And if Alice never pays, the receipt never becomes due, because the chain never gets that far:

```l4
#TRACE `rent, then receipt` AT 0 WITH
    (`WAIT UNTIL` 8)
```

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY Alice
    BECAUSE "the rent was not paid by the seventh day"
```

---

## Step 2: A Second Chance Follows a Missed Payment

`LEST` can do the same thing. Instead of ending the story in breach, it can name the obligation that arises _because_ the first one was missed. The lease gives Alice fourteen more days, at $50 more:

```l4
GIVETH A DEONTIC Actor Action
`rent, with a late fee` MEANS
    PARTY  Alice
    MUST   EXACTLY (Pay Alice `Ms Ng` 1500)
    WITHIN 7
    HENCE  FULFILLED
    LEST   PARTY  Alice
           MUST   EXACTLY (Pay Alice `Ms Ng` 1550)
           WITHIN 14
           HENCE  FULFILLED
           LEST   BREACH BY Alice BECAUSE "the rent and the late fee were not paid"
```

This is how a lease says "grace period", "penalty" or "cure": the failure of one obligation is not the end, it is the start of a harsher one. The inner obligation's own `LEST` is a plain `BREACH`, and that is where the chain ends: a file of obligations has to end somewhere, and every chain ends at a `FULFILLED` or a `BREACH`.

Alice misses the seventh, then pays $1,550 on day 15:

```l4
#TRACE `rent, with a late fee` AT 0 WITH
    (`WAIT UNTIL` 8)
    PARTY Alice DOES Pay Alice `Ms Ng` 1550 AT 15
```

```
Result:
  FULFILLED
```

Look at what is owed on day 8, when the miss has just come to light:

```l4
#TRACE `rent, with a late fee` AT 0 WITH
    (`WAIT UNTIL` 8)
```

```
Result:
  PARTY Alice MUST EXACTLY Pay OF Alice, `Ms Ng`, 1550 WITHIN 14 HENCE FULFILLED LEST (BREACH BY Alice BECAUSE "the rent and the late fee were not paid")
```

The original obligation is gone; the second chance is what stands, with fourteen days on its clock. **Where does the second clock start?** At day 8 — the first event after the deadline, the moment the miss came to light — and not at day 7, the deadline itself. Fourteen days from day 8 is day 22. That difference is not fixed at one day. L4 learns that a deadline has passed only when the next event arrives, and the next obligation begins then — so a late payment that is itself the next event is on time by its own clock. That is why every miss on this page is recorded as ``(`WAIT UNTIL` 8)`` before anything else: it pins the second clock to the day after the deadline. Even so, the window ends on day 22, one day later than a lease saying "fourteen more days from the seventh" would have it; to end it on day 21, write `WITHIN 13`, and say why in a comment.

Alice pays the plain rent on day 15, forgetting the fee:

```l4
#TRACE `rent, with a late fee` AT 0 WITH
    (`WAIT UNTIL` 8)
    PARTY Alice DOES Pay Alice `Ms Ng` 1500 AT 15
```

```
Result:
  PARTY Alice MUST EXACTLY Pay OF Alice, `Ms Ng`, 1550 WITHIN 7 HENCE FULFILLED LEST (BREACH BY Alice BECAUSE "the rent and the late fee were not paid")
```

Not the payment the second chance asks for, so it is passed over, and she has seven days left to make the right one. And if nobody does anything for a month, both chances are gone and the sentence on the screen is the inner one:

```l4
#TRACE `rent, with a late fee` AT 0 WITH
    (`WAIT UNTIL` 8)
    (`WAIT UNTIL` 40)
```

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY Alice
    BECAUSE "the rent and the late fee were not paid"
```

So the two "then what" lines are symmetrical. `HENCE` names what the good outcome leads to; `LEST` names what the bad one leads to; either may be `FULFILLED`, `BREACH`, or another obligation; and a chain can go as deep as the lease does.

---

## Step 3: Paying Any Amount, and Handing It On

Every payment so far has been written with `EXACTLY`: this payment and no other. Sometimes the clause is looser. Alice may pay the rent together with something towards the deposit, and the receipt should be for whatever she paid. So the act has to accept _any_ amount, then decide whether it was enough, then carry the amount forward into the receipt.

Leave the amount as a blank, and test it with `PROVIDED`:

```l4
GIVETH A DEONTIC Actor Action
`rent, receipt for the amount paid` MEANS
    PARTY  Alice
    MUST   Pay Alice `Ms Ng` amount PROVIDED amount AT LEAST 1500
    WITHIN 7
    HENCE  `a receipt to` Alice amount
    LEST   BREACH BY Alice BECAUSE "the rent was not paid by the seventh day"
```

Three new things on the `MUST` line, and one on the `HENCE` line.

There is no `EXACTLY`. Without it, the act is a shape to be matched rather than a value to be equalled: a payment from Alice to Ms Ng of _some_ amount. The word `amount` — any word would do — is not a value you have defined anywhere; it is a blank, and the event that matches the shape fills it in. Then `PROVIDED amount AT LEAST 1500` is the test: a payment counts only if the blank, once filled, passes it. A payment that fails the test is passed over as if it had not fitted at all.

On the `HENCE` line, the blank is handed on. `` `a receipt to` Alice amount `` is a rule being used with two inputs, the way [One Obligation](one-obligation.md) used `Pay` with three — and the rule is one that gives an obligation:

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
```

Given a person and an amount, it gives the obligation to issue that person a receipt for that amount. This is the ordinary `GIVEN … GIVETH …` rule you already know; the only novelty is that what it gives is an obligation. So the chain now reads: Alice pays some amount that is at least the rent; _hence_ Ms Ng must issue a receipt for that amount.

Alice pays $1,600 on day 6, and the receipt on day 9 is for $1,600:

```l4
#TRACE `rent, receipt for the amount paid` AT 0 WITH
    PARTY Alice   DOES Pay Alice `Ms Ng` 1600     AT 6
    PARTY `Ms Ng` DOES Receipt `Ms Ng` Alice 1600 AT 9
```

```
Result:
  FULFILLED
```

Stop the story after the payment:

```l4
#TRACE `rent, receipt for the amount paid` AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 1600 AT 6
```

```
Result:
  PARTY `Ms Ng` MUST EXACTLY Receipt OF `Ms Ng`, who, amount WITHIN 5 HENCE FULFILLED LEST (BREACH BY `Ms Ng` BECAUSE "no receipt was issued")
```

The receipt is owed — but the screen writes it with the rule's own input names, `who` and `amount`, rather than Alice and 1600. The figure has been carried in (the next example proves it, by offering a receipt for the wrong amount); the screen does not print it in a "still owed" line.

A receipt for $1,500 is not the receipt that is owed, and by day 12 Ms Ng is in breach:

```l4
#TRACE `rent, receipt for the amount paid` AT 0 WITH
    PARTY Alice   DOES Pay Alice `Ms Ng` 1600     AT 6
    PARTY `Ms Ng` DOES Receipt `Ms Ng` Alice 1500 AT 9
    (`WAIT UNTIL` 12)
```

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY `Ms Ng`
    BECAUSE "no receipt was issued"
```

And a payment of $1,000 on day 3 fails the test, so it is passed over and the clock moves on:

```l4
#TRACE `rent, receipt for the amount paid` AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 1000 AT 3
```

```
Result:
  PARTY Alice MUST Pay Alice `Ms Ng` amount PROVIDED (amount AT LEAST 1500) WITHIN 4 HENCE (`a receipt to` OF Alice, amount) LEST (BREACH BY Alice BECAUSE "the rent was not paid by the seventh day")
```

The "still owed" line writes the act as you wrote it — there is no `EXACTLY` to turn it into the `Pay OF …` form — with the blank still unfilled, the test still to be passed, and the receipt rule still waiting for its inputs.

**Why the receipt is a rule of its own.** It need not be. The receipt obligation can be written directly under `HENCE`, with ``EXACTLY (Receipt `Ms Ng` Alice amount)`` inside it, as Step 1 did with a fixed figure, and the blank is carried in just the same. The house rule prefers a rule for the reason a lease defines a term once: in a real lease the same receipt is owed after several different payments, and a rule can be used from as many places as need it, where an obligation written out under one `HENCE` serves that one place. The next page uses the same device to hand a shrinking balance back to the same rule.

One more thing about `EXACTLY` while it is in view. There are two places to write it: around the whole act, ``EXACTLY (Pay Alice `Ms Ng` 1500)``, as every example on this page does, or around one figure, ``Pay Alice `Ms Ng` (EXACTLY 1500)``. The second works only when the figure is written out as a number. Give it a name instead — a defined rent, a rule's input, or a blank such as `amount` — and the run stops when the event arrives:

```
Internal error:
  amount
is not in scope.
Please report this as a bug.
```

The whole-act spelling has no such limit, and it is the one to reach for.

---

## Step 4: A Guarantor

Alice is a student. Her father, Mr Lim, signs the lease as guarantor: if Alice does not pay the rent, he will. Written in the first way a lawyer would read that sentence, Mr Lim's obligation arises only on Alice's default, and that is exactly what `LEST` says:

```l4
GIVETH A DEONTIC Actor Action
`rent, guaranteed by Mr Lim` MEANS
    PARTY  Alice
    MUST   EXACTLY (Pay Alice `Ms Ng` 1500)
    WITHIN 7
    HENCE  FULFILLED
    LEST   PARTY  `Mr Lim`
           MUST   EXACTLY (Pay `Mr Lim` `Ms Ng` 1500)
           WITHIN 14
           HENCE  FULFILLED
           LEST   BREACH BY `Mr Lim` BECAUSE "the guarantor did not pay the rent"
```

This is the same shape as the late fee in Step 2, with a different person in the second link. Alice pays, and Mr Lim is never called on:

```l4
#TRACE `rent, guaranteed by Mr Lim` AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 1500 AT 5
```

```
Result:
  FULFILLED
```

Alice misses the seventh; Mr Lim pays on day 15:

```l4
#TRACE `rent, guaranteed by Mr Lim` AT 0 WITH
    (`WAIT UNTIL` 8)
    PARTY `Mr Lim` DOES Pay `Mr Lim` `Ms Ng` 1500 AT 15
```

```
Result:
  FULFILLED
```

Now the case that shows what kind of guarantee this is. Mr Lim, being careful, pays on day 3, before Alice has missed anything:

```l4
#TRACE `rent, guaranteed by Mr Lim` AT 0 WITH
    PARTY `Mr Lim` DOES Pay `Mr Lim` `Ms Ng` 1500 AT 3
```

```
Result:
  PARTY Alice MUST EXACTLY Pay OF Alice, `Ms Ng`, 1500 WITHIN 4 HENCE FULFILLED LEST (PARTY `Mr Lim` MUST EXACTLY Pay OF `Mr Lim`, `Ms Ng`, 1500 WITHIN 14 HENCE FULFILLED LEST (BREACH BY `Mr Lim` BECAUSE "the guarantor did not pay the rent"))
```

It did nothing. On day 3 the only obligation standing is Alice's, and Mr Lim's payment is not Alice paying, so it is passed over like the inspection was in [One Obligation](one-obligation.md). His obligation does not exist until hers has failed. That is the guarantee the civil codes call _simple_, and it comes with a right the lawyers call the benefit of discussion: go to the debtor first.

What if the first thing to happen after day 7 is Mr Lim paying, on day 20, with no earlier event in the list?

```l4
#TRACE `rent, guaranteed by Mr Lim` AT 0 WITH
    PARTY `Mr Lim` DOES Pay `Mr Lim` `Ms Ng` 1500 AT 20
```

```
Result:
  FULFILLED
```

His payment on day 20 is the event that reveals Alice's default, and it is then offered to the obligation that the default brings into being — his own — which it satisfies. Step 2's rule about the second clock is at work here: Mr Lim's fourteen days begin at day 20, the moment the default came to light, and his payment is on time by that clock. In a real record of events that is a reason to write down the day a deadline passed, as this page's other examples do with `WAIT UNTIL`: otherwise a late payment that is the first thing recorded is never late.

And if neither of them pays, the breach is Mr Lim's, because the last obligation standing was his:

```l4
#TRACE `rent, guaranteed by Mr Lim` AT 0 WITH
    (`WAIT UNTIL` 8)
    (`WAIT UNTIL` 30)
```

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY `Mr Lim`
    BECAUSE "the guarantor did not pay the rent"
```

---

## Step 5: The Same Guarantee, Read the Other Way

There is a second thing "Mr Lim guarantees the rent" can mean, and it is the commoner one in commercial practice: Ms Ng may go to either of them, from the first day, and whoever pays discharges the debt. Mr Lim is not a fallback; he is a second debtor. The civil codes call that guarantee _solidary_, and Singapore and English drafting reaches it by having the guarantor promise "as principal debtor".

In L4, that is a choice between two obligations that are both live at once, joined by `ROR` — an _or_ between obligations: any of these:

```l4
GIVETH A DEONTIC Actor Action
`rent, Alice or Mr Lim` MEANS
    (PARTY  Alice
     MUST   EXACTLY (Pay Alice `Ms Ng` 1500)
     WITHIN 7
     HENCE  FULFILLED
     LEST   BREACH BY Alice BECAUSE "the rent was not paid by the seventh day")
    ROR
    (PARTY  `Mr Lim`
     MUST   EXACTLY (Pay `Mr Lim` `Ms Ng` 1500)
     WITHIN 7
     HENCE  FULFILLED
     LEST   BREACH BY `Mr Lim` BECAUSE "the guarantor did not pay the rent")
```

Each side is a complete obligation in brackets, and the two run against the same list of events at the same time. The whole is fulfilled as soon as either side is. Set the two guarantees side by side and the difference is one word: **the `LEST` of Step 4 has become the `ROR` of Step 5.** Two smaller things follow from it: Alice's link now ends with its own `LEST BREACH`, since nothing hangs off it any more; and Mr Lim's clock is now the same seven days as hers, since he is bound from day one and not from her default. That one word is the difference between a guarantor who pays only after the tenant's default and one whom the landlord may pursue first, and it is worth checking, in any guarantee you encode, which of the two the source text actually says.

Mr Lim pays on day 3, and this time it settles everything:

```l4
#TRACE `rent, Alice or Mr Lim` AT 0 WITH
    PARTY `Mr Lim` DOES Pay `Mr Lim` `Ms Ng` 1500 AT 3
```

```
Result:
  FULFILLED
```

Alice paying on day 5 settles it just the same. With nothing paid yet, both obligations stand, and the screen shows them joined by `OR`:

```l4
#TRACE `rent, Alice or Mr Lim` AT 0 WITH
    (`WAIT UNTIL` 3)
```

```
Result:
  PARTY Alice MUST EXACTLY Pay OF Alice, `Ms Ng`, 1500 WITHIN 4 HENCE FULFILLED LEST (BREACH BY Alice BECAUSE "the rent was not paid by the seventh day") OR PARTY `Mr Lim` MUST EXACTLY Pay OF `Mr Lim`, `Ms Ng`, 1500 WITHIN 4 HENCE FULFILLED LEST (BREACH BY `Mr Lim` BECAUSE "the guarantor did not pay the rent")
```

(The screen writes `ROR` as `OR` in a "still owed" line. It is the same choice.)

And if neither pays by the seventh:

```l4
#TRACE `rent, Alice or Mr Lim` AT 0 WITH
    (`WAIT UNTIL` 8)
```

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY `Mr Lim`
    BECAUSE "the guarantor did not pay the rent"
```

Both of them failed, and the screen names one of them. A choice between obligations is only broken when every one of its sides is lost, and when that happens today the screen reports a single side — the last to be lost, or the right-hand one when they are lost together — rather than everyone who failed. [Several Parties](several-parties.md) comes back to this, because it matters more when there are three flatmates than when there is one guarantor.

---

## Reading the Screen for a Chain

The three things the screen can say are the same as for one obligation, but they now say something about a chain, and it is worth being exact:

| The screen says                           | For a chain, it means                                                                                                              |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `FULFILLED`                               | the whole chain reached a `FULFILLED`, by whatever route: paid on time, or paid late with the fee, or paid by the guarantor        |
| `DEONTIC BREACHED:` and then who, and why | some link ended in `BREACH`; the `BY` and the `BECAUSE` are the ones written against that link, so they tell you which link it was |
| an obligation, written out                | the link the chain has reached, and nothing about the links before it; its `WITHIN` is measured from the event that reached it     |

---

## What You Learned

- **`HENCE` and `LEST` can each name another obligation.** A lease is a chain of them, and every chain ends at a `FULFILLED` or a `BREACH`.
- **The next clock starts at the event that reached it**: for `HENCE`, the act that discharged the previous link; for `LEST`, the first event after the deadline — the moment the default came to light — which is not the deadline itself.
- **An act can accept any amount**: leave the amount as a blank, test it with `PROVIDED`, and hand it on to a rule that gives the next obligation, so that the same obligation can be used from more than one place.
- **`EXACTLY` around the whole act** is the spelling that works with a named figure; `EXACTLY` around one figure works only when the figure is written out.
- **Two guarantees, one word apart.** A guarantor who pays only after the tenant's default is a `LEST`. A guarantor the landlord may go to first is a `ROR`. Which one the source text says is a question of law, and the encoding has to answer it.
- **A choice is broken only when every side is lost**, and the screen then names one side, not all of them.

---

## Next Steps

- [Several Parties](several-parties.md) — three flatmates and one rent: all of these, any of these, one pays and the other repays, and paying in instalments
- [The Regulative Layer, Whole](../../concepts/legal-modeling/regulative-layer-whole.md) — the five separate ideas and how they fit
- [Regulative Rules](../../concepts/legal-modeling/regulative-rules.md) — reparation clauses, recursive obligations, and the rest of the reference-style account
- [`BECAUSE`](../../reference/regulative/BECAUSE.md) — the forms of `BREACH`, and what to write after it
