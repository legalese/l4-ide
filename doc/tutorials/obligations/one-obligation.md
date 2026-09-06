# One Obligation

Who must do what, by when, and what follows — written as one rule, then played forward against what actually happened.

**Prerequisites:** [Your First L4 File](../getting-started/first-l4-file.md) — enough to read a rule, run a file with `l4 run`, and recognise `DECLARE`, `MEANS` and `#EVAL`. No programming is assumed, and every rule this page uses is written out on this page.

**Complete example:** [one-obligation.l4](one-obligation.l4), which holds every example below that runs today, in the order the page presents them.

---

## What You'll Build

A residential tenancy. Ms Ng lets a flat to Alice. The lease has many clauses; this page takes three of them, one of each kind that a lease can contain:

- **Alice must pay the rent of $1,500 by the seventh day of the month.**
- **Ms Ng may inspect the flat, on notice, once a month.**
- **Alice must not sublet the flat.**

Everything you have met in L4 so far has been a _definition_: given some facts, a rule works out an answer. A lease is different. It does not work anything out. It says who has to do what, and by when, and what happens if they do or do not. This page is about writing that down, and about the one thing you can do with it that you cannot do with a definition: hand it a list of what actually happened, and ask how things now stand.

---

## Step 1: The Shape of an Obligation

Read the rent clause slowly, and it comes apart into five pieces:

> _Alice_ **must** _pay the rent_ **within seven days**; if she does, that is the end of it; if she does not, she is in breach.

1. **Who** — Alice.
2. **What** — pay the rent, and whether it is a duty (must), a right (may) or a prohibition (must not).
3. **By when** — within seven days.
4. **Then what, if it is done** — nothing more is owed.
5. **Then what, if it is not** — Alice is in breach.

Every obligation in L4 has exactly those five parts, written one under the other with a keyword in front of each: `PARTY`, then `MUST` (or `MAY`, or `SHANT`), then `WITHIN`, then `HENCE`, then `LEST`. The five together are one unit, and L4 has a name for that unit: a **"Deonton"**, from the Greek word for a duty. You will meet the word in the reference pages; on this page it is simply _an obligation_.

That is all there is to write. The rest of the page is about what each part means and what the tool does with it.

---

## Step 2: Who Can Act, and What Can Be Done

Before writing the clause you say who the people are and what the acts are, the way a lease begins by naming the parties and defining its terms.

```l4
DECLARE Actor IS ONE OF Alice, `Ms Ng`

DECLARE Action IS ONE OF
    Pay     HAS payer     IS AN Actor
                payee     IS AN Actor
                amount    IS A NUMBER
    Inspect HAS inspector IS AN Actor
    Sublet  HAS tenant    IS AN Actor
```

`` DECLARE Actor IS ONE OF Alice, `Ms Ng` `` says that in this lease there are two people who can act, and names them. This is the cast: nobody else can appear in an obligation or in an event, and for any other name L4 reports that it cannot find a definition.

`DECLARE Action IS ONE OF …` lists the things that can be done. Each act carries the details that matter: a payment has a payer, a payee and an amount; an inspection has an inspector; a subletting has the tenant who did it. One convention runs through all three, and it is worth noticing now because the tool relies on it: **the first person named in an act is the person who does it.** The payer pays, the inspector inspects, the tenant sublets. Step 8 shows what L4 does with that.

To write a particular act, name it and fill in its details in order, exactly as [Your First L4 File](../getting-started/first-l4-file.md) built a `Person`: ``Pay Alice `Ms Ng` 1500`` is Alice paying Ms Ng $1,500.

---

## Step 3: Write the Obligation

Here is the rent clause, all five parts:

```l4
GIVETH A DEONTIC Actor Action
`the rent is due` MEANS
    PARTY  Alice
    MUST   EXACTLY (Pay Alice `Ms Ng` 1500)
    WITHIN 7
    HENCE  FULFILLED
    LEST   BREACH BY Alice BECAUSE "the rent was not paid by the seventh day"
```

Line by line:

| Line                                      | What it says                                                                                                                                                                                                                                                                                            |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GIVETH A DEONTIC Actor Action`           | this rule gives an obligation, between the people in `Actor`, about the acts in `Action`                                                                                                                                                                                                                |
| `` `the rent is due` MEANS ``             | and this is its name                                                                                                                                                                                                                                                                                    |
| `PARTY Alice`                             | the person bound is Alice                                                                                                                                                                                                                                                                               |
| ``MUST EXACTLY (Pay Alice `Ms Ng` 1500)`` | what she must do: make this payment — $1,500, from Alice, to Ms Ng. The brackets only group the act. `EXACTLY` says to take the act as written: $1,000 is not this payment (Step 5 shows that). [What Follows](what-follows.md) shows the other way to write an act, as a shape that accepts any amount |
| `WITHIN 7`                                | she has seven days, counting from when the obligation begins                                                                                                                                                                                                                                            |
| `HENCE FULFILLED`                         | if she does it in time, the obligation is over and nothing further is owed                                                                                                                                                                                                                              |
| `LEST BREACH BY Alice BECAUSE "…"`        | if she does not, she is in breach, and this is the sentence that says why. Write that sentence for the person who will read it — a clerk, a lawyer, Alice herself. It is what the screen prints (Step 4)                                                                                                |

`DEONTIC` is the word L4 uses for the kind of thing an obligation is, in the same place a rule that gives a number says `GIVETH A NUMBER`. The two names after it say whose acts and which acts the obligation is about.

`WITHIN 7` is seven of whatever unit you are counting in. L4 does not know whether 7 means days, weeks or hours; it only knows that deadlines and the times of events are measured in the same unit, from the same starting point. On this page, the unit is days and the month starts at day 0.

---

## Step 4: Play It Forward

A definition is used by giving it its inputs. An obligation is used by giving it what happened. That is a new instruction to L4, `#TRACE`: name the obligation, say when the clock starts, and then list the events, one per line, each saying who did what, and when.

Alice pays on day 5:

```l4
#TRACE `the rent is due` AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 1500 AT 5
```

`AT 0` starts the clock at day 0. The event line reads as English: _Alice does — pay, Alice to Ms Ng, $1,500 — at day 5._ Alice's name appears twice on that line, once as the person acting and once inside the act as the payer; Step 8 explains why L4 wants both.

Run the file, and under that instruction the screen says:

```
Result:
  FULFILLED
```

The obligation is over, and it ended well. (Above each result the screen also prints a heading with the line the instruction is on, and below it a note that no trace was captured. Ignore both; they belong to a feature this page does not use.)

Now the same instruction with the payment on day 9:

```l4
#TRACE `the rent is due` AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 1500 AT 9
```

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY Alice
    BECAUSE "the rent was not paid by the seventh day"
```

The obligation is over, and it ended badly: who is in breach, and the sentence you wrote to say why. Nothing about the payment on day 9 appears here, because by day 9 the obligation had already been broken. It was broken the moment the clock passed day 7 with no payment.

And the third thing that can happen — nothing has happened yet. Write the instruction with no events at all:

```l4
#TRACE `the rent is due` AT 0 WITH
```

```
Result:
  PARTY Alice MUST EXACTLY Pay OF Alice, `Ms Ng`, 1500 WITHIN 7 HENCE FULFILLED LEST (BREACH BY Alice BECAUSE "the rent was not paid by the seventh day")
```

That is neither a success nor a breach. It is the obligation itself, written back out on one line, exactly as it stands: still open, still seven days on the clock. The screen spells the payment ``Pay OF Alice, `Ms Ng`, 1500``, which is the tool's own way of writing what you wrote as ``Pay Alice `Ms Ng` 1500``; the two are the same payment. Read this line as **what is still owed**, and read its `WITHIN` as how long is left.

So an obligation, played forward, comes out as one of three things:

| The screen says                                      | It means                                                  |
| ---------------------------------------------------- | --------------------------------------------------------- |
| `FULFILLED`                                          | it ended, and nothing further is owed                     |
| `DEONTIC BREACHED:` and then who, and why            | it ended in breach                                        |
| the obligation, written out, with a smaller `WITHIN` | it has not ended; this is what is still owed, and by when |

The third is the one to get used to, because a real contract spends most of its life there. It is a snapshot of where things stand, and it is a complete obligation in its own right: you could hand it more events tomorrow and carry on from exactly this point.

---

## Step 5: The Clock

Four short experiments, because the clock is where readers guess wrong.

**Exactly on the day counts.** `WITHIN 7` means up to and including day 7:

```l4
#TRACE `the rent is due` AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 1500 AT 7
```

```
Result:
  FULFILLED
```

**Time can pass with nobody doing anything.** The events you list are the only way the clock moves, so to say "day 8 arrived and nothing had happened" you need an event that is not anybody doing anything. L4 provides one, `WAIT UNTIL`, written in brackets:

```l4
#TRACE `the rent is due` AT 0 WITH
    (`WAIT UNTIL` 8)
```

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY Alice
    BECAUSE "the rent was not paid by the seventh day"
```

**Other events move the clock too.** Ms Ng inspects the flat on day 2. That is not Alice paying, so it does not discharge Alice's obligation; but it is something that happened, and it happened on day 2, so the clock is now at day 2:

```l4
#TRACE `the rent is due` AT 0 WITH
    PARTY `Ms Ng` DOES Inspect `Ms Ng` AT 2
```

```
Result:
  PARTY Alice MUST EXACTLY Pay OF Alice, `Ms Ng`, 1500 WITHIN 5 HENCE FULFILLED LEST (BREACH BY Alice BECAUSE "the rent was not paid by the seventh day")
```

The same obligation, with five days left instead of seven. Every event in the list is looked at in order; one that does not fit the obligation is passed over, and the clock keeps moving.

**The starting point is yours to choose.** `AT 0` is a convenience, not a requirement. If the month starts on day 100, the deadline is day 107:

```l4
#TRACE `the rent is due` AT 100 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 1500 AT 106
```

```
Result:
  FULFILLED
```

And one experiment about the act rather than the clock. Alice pays $1,000 on day 5, not $1,500:

```l4
#TRACE `the rent is due` AT 0 WITH
    PARTY Alice DOES Pay Alice `Ms Ng` 1000 AT 5
```

```
Result:
  PARTY Alice MUST EXACTLY Pay OF Alice, `Ms Ng`, 1500 WITHIN 2 HENCE FULFILLED LEST (BREACH BY Alice BECAUSE "the rent was not paid by the seventh day")
```

Not the payment the clause asked for, so it is passed over like the inspection was, and Alice has two days left to make the right one. That is what writing the figure into the act bought you. [What Follows](what-follows.md) shows the other way to write an act — as a shape that accepts any amount and then decides whether it was enough.

---

## Step 6: May — a Right, Not a Duty

Ms Ng may inspect the flat once a month. She is entitled to; she is not required to. Change one word:

```l4
GIVETH A DEONTIC Actor Action
`the inspection right` MEANS
    PARTY  `Ms Ng`
    MAY    Inspect `Ms Ng`
    WITHIN 30
    HENCE  FULFILLED
    LEST   FULFILLED
```

Both outcomes say `FULFILLED`, because there is no way to break a right: use it or leave it, nobody is in breach. Ms Ng inspects on day 12:

```l4
#TRACE `the inspection right` AT 0 WITH
    PARTY `Ms Ng` DOES Inspect `Ms Ng` AT 12
```

```
Result:
  FULFILLED
```

Thirty days pass and she never comes:

```l4
#TRACE `the inspection right` AT 0 WITH
    (`WAIT UNTIL` 31)
```

```
Result:
  FULFILLED
```

The point of a right is what it makes possible afterwards. On this page its `HENCE` is `FULFILLED`; in a real lease, exercising the right to inspect is usually what puts the landlord under a duty to give notice, or the tenant under a duty to let her in. [What Follows](what-follows.md) is about writing that.

One habit to form now: **write the `HENCE` and `LEST` lines out, even when they are `FULFILLED`.** L4 fills them in for you if you leave them out, and the defaults are sensible (a `MUST` breaches, a `MAY` does not), but a reader of your file should not have to know the defaults, and the message L4 prints for a breach it filled in itself is longer and harder to read than the one you write.

---

## Step 7: Shall Not — the Two Outcomes Swap Places

Alice must not sublet the flat. A prohibition is written with `SHANT`, and it is worth pausing over what "success" means for one:

```l4
GIVETH A DEONTIC Actor Action
`no subletting` MEANS
    PARTY  Alice
    SHANT  Sublet Alice
    WITHIN 365
    HENCE  FULFILLED
    LEST   BREACH BY Alice BECAUSE "the flat was sublet"
```

For a duty, the good outcome is that the act happens. For a prohibition, the good outcome is that the year passes and it never does. So `HENCE` and `LEST` keep their places — `HENCE` is still the outcome the clause wants, and `LEST` the other one — but what triggers them is the reverse of a `MUST`. Alice sublets on day 40:

```l4
#TRACE `no subletting` AT 0 WITH
    PARTY Alice DOES Sublet Alice AT 40
```

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY Alice
    BECAUSE "the flat was sublet"
```

A year passes and she never does:

```l4
#TRACE `no subletting` AT 0 WITH
    (`WAIT UNTIL` 366)
```

```
Result:
  FULFILLED
```

And with nothing having happened yet:

```l4
#TRACE `no subletting` AT 0 WITH
```

```
Result:
  PARTY Alice MUST NOT Sublet Alice WITHIN 365 HENCE FULFILLED LEST (BREACH BY Alice BECAUSE "the flat was sublet")
```

The screen writes `SHANT` as `MUST NOT`. The two are the same word in L4, and you may write either in your file; `MUST NOT` reads closer to most source texts.

The three kinds side by side:

| You write | If the act happens in time | If the deadline passes with no act  |
| --------- | -------------------------- | ----------------------------------- |
| `MUST`    | `HENCE` (good)             | `LEST` (breach)                     |
| `MAY`     | `HENCE` (good)             | `LEST` (also good: nobody breached) |
| `SHANT`   | `LEST` (breach)            | `HENCE` (good)                      |

---

## Step 8: Who May Do What

Look again at the event line in Step 4: ``PARTY Alice DOES Pay Alice `Ms Ng` 1500 AT 5``. Alice is named twice — as the person acting, and as the payer inside the act. That is not redundancy; it is a check.

Step 2 said that the first person named in an act is the person who does it. L4 holds you to that. The party in front of `MUST` (or `MAY`, or `SHANT`), and the party in front of `DOES` in an event, must be the person the act itself names first. Write Alice as the party and Ms Ng as the inspector —

```l4
`inspect the flat` MEANS Inspect `Ms Ng`

GIVETH A DEONTIC Actor Action
`wrong party` MEANS
    PARTY Alice MUST `inspect the flat` WITHIN 30 HENCE FULFILLED LEST BREACH BY Alice
```

— and L4 stops before running anything:

```
An actor may only perform its own actions.
  `inspect the flat` is performed by `Ms Ng`, not by `Alice`.
```

The same message appears if an event says `` PARTY Alice DOES `inspect the flat` ``. So a lease cannot, by a slip, put the tenant under a duty to do the landlord's act, and a list of events cannot record one person doing another's act. (That example is deliberately wrong, so it is not in the companion file: a file under this documentation has to run cleanly.)

L4 makes this check wherever it can read from the text who the performer is: a named person, a named act, a rule's own inputs. A person built on the spot from particulars — written into the obligation as a name and some details, the way [Your First L4 File](../getting-started/first-l4-file.md) built a `Person`, rather than picked from a fixed cast — is not checked, because there is no fixed list to check against. The cast in Step 2 is a fixed list, which is why every example on this page is checked. [The Regulative Layer, Whole](../../concepts/legal-modeling/regulative-layer-whole.md) says more about the choice.

---

## What You Learned

- **An obligation has five parts**, and L4 writes them in order: `PARTY` who, `MUST`/`MAY`/`SHANT` what, `WITHIN` by when, `HENCE` then what if it is done, `LEST` then what if it is not. The five together are one unit, which the reference pages call a Deonton.
- **Before the clause come the cast and the acts**: `DECLARE Actor IS ONE OF …` for who can act, `DECLARE Action IS ONE OF …` for what can be done. Each act names its doer first.
- **An obligation is used by playing it forward**: `#TRACE`, a starting time, and a list of who did what, when. The screen then says one of three things: `FULFILLED`, a breach with who and why, or the obligation written back out with the time that is left — what is still owed.
- **The clock** counts in your unit from the start you name; the deadline day itself is in time; `WAIT UNTIL` lets time pass with nobody acting; an event that does not fit the obligation is passed over but still moves the clock.
- **`MAY` cannot be broken** — both outcomes are good. **`SHANT` swaps the triggers**: the act happening is the breach, and the deadline passing quietly is the success.
- **The party must be the act's own performer**, and L4 checks it in the obligation and in every event.

---

## Next Steps

- [What Follows](what-follows.md) — a receipt follows a payment, a late fee follows a missed one, a guarantor pays when the tenant does not: what to write after `HENCE` and `LEST`
- [Several Parties](several-parties.md) — three flatmates and one rent
- [The Regulative Layer, Whole](../../concepts/legal-modeling/regulative-layer-whole.md) — how the five separate ideas fit together, and which are still proposed
- [Regulative Rules](../../concepts/legal-modeling/regulative-rules.md) — the reference-style account of everything on this page
- [`DEONTIC`](../../reference/regulative/DEONTIC.md), [`PARTY`](../../reference/regulative/PARTY.md), [`MUST`](../../reference/regulative/MUST.md), [`MAY`](../../reference/regulative/MAY.md), [`SHANT`](../../reference/regulative/SHANT.md) — the keyword reference pages
