# What Is Coming

The three pieces of the regulative layer that close the gap this tutorial ended on. **Two of them landed on 8 September 2026 and run today**; the third, "enough of them", is still a design.

**Prerequisites:** [Several Parties](several-parties.md), and in particular its last column — the things the six arrangements of one debt cannot yet say.

**Two of the three pieces below now run**, and each block says which it is. The two that run — everyone-then-one-thing and each-with-its-own — have a reference page of their own, [EVERY](../../reference/regulative/EVERY.md), and a companion file you can run, [every-run-example.l4](../../reference/regulative/every-run-example.l4). Read this page for how the three pieces fit together and why they are three; read that page for how to write one. The third piece is still written as the design document spells it, and is marked so.

_Status (2026-09-08): pieces 1 and 2 are **built**; piece 3, "enough of them", is **proposed, not landed**. The design lives in the specification `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md` — its section 2.2.6 for the first two pieces, and its section 2.2.7 for the third. The spellings for pieces 1 and 2 were ruled on 7 September 2026 and are the ones the compiler accepts; piece 3's are still the design document's, and it says its naming is not settled._

---

## Why There Is a Gap

[Several Parties](several-parties.md) ended with a table, and its last column was a list of things that a lease can say and today's L4 cannot say in one place:

- a follow-on that fires _once_, after _all_ of a group have acted;
- a deadline on the _total_ paid, rather than on each payment;
- a breach that names _everyone_ who failed, rather than one of them.

All three have the same cause. Today, the things you can combine are obligations you have written out by hand, one per person, and the only place a follow-on can go is inside one of them. There is no way to say "these people, as a group", and so no way to hang anything on the group.

Three pieces close that gap, two of them built. They are separate pieces — each one answers a different question, and you would choose them independently — and the clearest way to see them is as three questions.

---

## 1. Everyone, Then One Thing

**The question: after all of them have acted, what happens — once?**

Three flatmates must sign, and when the last of them has, the tenancy begins. In [Several Parties](several-parties.md) that was three obligations joined by `RAND` and nowhere to write "then the tenancy begins". The proposal is a way to write an obligation _for everyone in a group_ at once, and to attach a single follow-on to the group:

```l4
-- BUILT (2026-09-08). This runs.
EVERY Flatmate f IN flatmates       -- the group, given as a list
    MUST   Sign (EXACTLY f)
    WITHIN 14
    ONCE   ALL HAVE                 -- the line that says when the follow-on fires
    HENCE  `the tenancy begins`     -- fires once, when the last of them has signed
    LEST   `the lease falls through`
```

Three things in that block were not in the first draft of this page. `IN flatmates` names the group as a list, which is what makes the rule runnable at all — see [Where the group comes from](../../reference/regulative/EVERY.md#where-the-group-comes-from-the-roll). `ONCE ALL HAVE` is a line of its own saying when the follow-on fires, and it is required whenever there is one; it was ruled on 7 September 2026. And `EXACTLY f` is how you say "this flatmate" inside the action; a bare `f` there would match anybody's signature.

(`IN` was ruled a day later, on 8 September 2026. Examples written before that put the same list inside the `WHO` condition, as `WHO elem f flatmates`. **That older spelling is deprecated**, ruled on the same day: it still runs, and nothing warns you if you write it, but `IN` is the one to use and everything we ship has been moved across. You will still meet the old shape in material written earlier, which is why it is worth being able to recognise; the [reference page](../../reference/regulative/EVERY.md#the-older-spelling-now-deprecated-a-roll-read-out-of-the-who-condition) gives the two-line rewrite.)

Read `EVERY Flatmate f` as "for every flatmate, call them f": one obligation per flatmate, all live at once, exactly as the `RAND` was — and then one `HENCE` for the whole. This shape is called a **"barrier"**: nothing follows until everyone has crossed it, and then one thing follows. If somebody does not sign, the `LEST` fires once for the group — and here is the third gap this page opened with, still open, and wider than this page used to say: the breach names **nobody**. Not all of the flatmates who failed, and not one of them either. It cannot: the `LEST` under a barrier belongs to the group and not to any one member, so there is no member for it to name, and writing `LEST BREACH BY f` is refused when the rule is checked. What you get is a bare breach. If you need to know who did not sign, ask the rule what is still outstanding instead — that answer does list them by name.

---

## 2. Each With Its Own

**The question: after each of them acts, what happens — for that one?**

A different sentence, and a different shape. Each flatmate who pays a share is to be given a receipt — three payments, three receipts, each following its own payment and not waiting for the others. Nothing here happens once for the group; everything happens once per person. The quantifier is the same word; what changes is the join line, `UPON EACH` in place of `ONCE ALL HAVE`:

```l4
-- BUILT (2026-09-08). This runs.
EVERY Flatmate f IN flatmates
    MUST   Pay (EXACTLY f) (EXACTLY theLandlord) amount
    WITHIN 7
    UPON   EACH                     -- the fork: once per flatmate who pays
    HENCE  (PARTY theLandlord
                MUST   Receipt (EXACTLY theLandlord) (EXACTLY f) (EXACTLY amount)
                WITHIN 5)
    LEST   BREACH BY f
```

This shape is called a **"fork"**: the group splits into its members, and each member carries its own follow-on, with `f` standing for that member inside it. Without a `HENCE` or `LEST` the two shapes are the same thing — one obligation per person — and the difference between them is only where the follow-on attaches. That is why the join line, and not the quantifier, is where the difference is written.

_A note on the words, kept because it records how they were settled. The specification's own discussion records that `EVERY` and `EACH` may not survive contact with a first-time reader, and it records a proposal to call the two shapes "jointly" and "severally" instead — The research done that night recommends against it, and no ruling has yet been made. Those words carry a settled legal meaning, about who may be sued and whether one person's payment discharges the rest, which is not this distinction — and on the point of discharge it is the opposite: a joint promisor's payment discharges the others, where under everyone-then-one-thing nobody's act does anything for anyone else. The alternative the research preferred was to mark the shape on a line of its own, so that `EVERY` serves for both. **That is what was ruled, on 2026-09-07:** a line of its own says when the follow-on fires — `ONCE ALL HAVE` for everyone-then-one-thing, `UPON EACH` for each-with-its-own — and it is required whenever there is a follow-on at all, because the two readings differ and the language declines to guess. The two shapes were never in doubt; only the words were._

_And the words themselves are settled (7 September 2026), and built (8 September 2026). There is one quantifier word, `EVERY`; `EACH` appears only inside `UPON EACH` and is not a keyword at all. The word after `EVERY` names the kind of party, as `Flatmate` does above, and it narrows the group; `EVERY f` with no kind word takes the whole roll. Which people are on that roll is said with `IN`, ruled on 8 September 2026 and built the same day._

---

## 3. Enough of Them

**The question: when has enough happened for the follow-on to fire?**

The rent example from [Several Parties](several-parties.md) is the one that motivates this piece. Three flatmates, any amounts, until $1,500 has arrived by the seventh — one deadline on the total, and if it is not reached, all three in breach. Today's encoding, a rule that uses itself, restarts the clock on every payment and blames one flatmate. The proposal puts the condition on its own line, with the word `ONCE`, and lets that line carry the deadline and the breach:

```l4
-- PROPOSED, NOT LANDED (2026-09-06). Does not run.
EVERY Flatmate f
    MAY    Pay f `Ms Ng` amount
    UPON   EACH
    HENCE  PARTY `Ms Ng` MUST Receipt `Ms Ng` f amount WITHIN 5
ONCE   sum OF amount AT LEAST rent        -- when the payments add up to the rent
WITHIN 7                                  -- one deadline, on the total
HENCE  FULFILLED
LEST   BREACH BY EVERY Flatmate           -- everyone, not one of them
```

Read it from the last line upward. `ONCE sum OF amount AT LEAST rent` is the condition: the payments, added up, have reached the rent. `WITHIN 7` on that line is a deadline on the _condition_, not on any one payment — which is exactly the deadline the lease has and the rule-that-uses-itself could not express. `LEST BREACH BY EVERY Flatmate` blames the group; that `LEST`, the `WITHIN` and the `HENCE` beside it all belong to the `ONCE` line, not to the `MAY` inside. And inside, each payment is a `MAY`, because no single flatmate owes any single payment; what is owed is the state at the end. `UPON EACH`, inside, is the spelling for each-with-its-own — one receipt per payment — and `EVERY` at the top only names the group. (The design document's own version of this example uses tenants with names rather than a fixed cast; nothing else differs.) The specification puts it as a slogan: acts inside, state outside.

Two smaller members of the same family. A condition can be a _count_ rather than a total — "any two of the three signatories" on a bank mandate, a quorum of two directors — and the proposal spells that `SOME 2 OF Director d MUST sign … HENCE …`. **`SOME 2 OF` means _at least_ two of them**: the specification records a ruling that `SOME m OF` and `AT LEAST m OF` are the same thing, and warns that modern English reads "some 200 people" as "roughly", which is not what is meant. And a condition can be two conditions at once, joined by `AND` — the specification's example is the Singapore Companies Act's quorum for a members' meeting, which needs both a number of members and a share of the company between them.

The two ends of this family are familiar. "Once any one of them has" is `ROR`, which you already have; "once all of them have" is piece 1, which you do not. What is new in between is everything that is not a count of everybody: two of three, a sum, a percentage.

---

## Why These Are Three Pieces and Not One

It is tempting to see all of this as one big feature. It is three, and they combine, because each answers a question the others do not:

| Piece                    | The question it answers                            | The words proposed                           | Chosen independently of…                    |
| ------------------------ | -------------------------------------------------- | -------------------------------------------- | ------------------------------------------- |
| everyone, then one thing | where does the follow-on attach — once, after all? | `EVERY … HENCE …` (or `HENCE ONCE ALL HAVE`) | what the condition is                       |
| each with its own        | where does the follow-on attach — once per person? | `EVERY … UPON EACH … HENCE …`                | what the condition is                       |
| enough of them           | when does the follow-on fire?                      | `ONCE …`, `SOME m OF …`                      | whether the follow-on is once or per person |

And all three sit beside `RAND` and `ROR` rather than replacing them. `RAND` and `ROR` combine obligations you have written out one by one, and will go on doing so. The three pieces above are for the case where the obligations are the same shape for everyone in a group, and something has to be said about the group. The specification also records the one combination that means nothing: a group with nothing waiting at the end — each-with-its-own on its own — together with a condition, since there is then no moment at which "enough" could be judged. The rent block above is not that: its receipts fire per payment, but the group still waits at the `ONCE` line.

---

## What Would Make The Rest Of This Page True

Pieces 1 and 2 landed on 8 September 2026, and what remains is piece 3, "enough of them". The specification lists what it needs, and this page repeats it so that a reader can check the state of things without opening the design document: a way for L4 to read a `ONCE` line that carries a count or a total rather than the word `ALL`; a way to run it, which is a running total kept where the group is counted; a breach that carries a set of people rather than one; and test files for the rent by total and by share and for the quorum.

One of those — **a breach that names everyone who failed** — is still missing for pieces 1 and 2 as well, and by a wider margin than an earlier version of this page said. A group obligation that fails today names **no** member at all: not everyone who did not act, and not one of them as a stand-in. So the third of the three gaps this page opened with is the one still open, it is open for all three pieces, and what is missing is the whole of it rather than the last part of it.

When piece 3 lands, this page is deleted and the material moves into [Several Parties](several-parties.md), where the gaps it fills were shown.

---

## Next Steps

- [EVERY](../../reference/regulative/EVERY.md) — the reference page for the two pieces that now run, with worked traces
- [Several Parties](several-parties.md) — the arrangements that run today, and the defects these pieces would fix
- [The Regulative Layer, Whole](../../concepts/legal-modeling/regulative-layer-whole.md) — all five ideas of the regulative layer in one place, with the same built/proposed line drawn through them
- `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md` — the design itself, for a reader who wants the rulings and the reasoning (it is written for maintainers, not for this page's reader)
