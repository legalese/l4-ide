# What Is Coming

The pieces of the regulative layer that are designed but not built: everyone-then-one-thing, each-with-its-own, and "enough of them".

**Prerequisites:** [Several Parties](several-parties.md), and in particular its last column — the things the six arrangements of one debt cannot yet say.

**There is no companion file for this page.** Nothing on it runs. Every piece of L4 below is written as a design document spells it, and is marked so. If you type any of it into a file today, L4 will not accept it.

_Proposed, not landed (2026-09-06): everything on this page. The design lives in the specification `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md` — its section 2.2.6 for the first two pieces, and its section 2.2.7, added on 2026-09-06, for the third. The spellings below are that document's current spellings, and the document itself says its naming is not settled. Read this page for the shape of what is coming, not for spellings to learn._

---

## Why There Is a Gap

[Several Parties](several-parties.md) ended with a table, and its last column was a list of things that a lease can say and today's L4 cannot say in one place:

- a follow-on that fires _once_, after _all_ of a group have acted;
- a deadline on the _total_ paid, rather than on each payment;
- a breach that names _everyone_ who failed, rather than one of them.

All three have the same cause. Today, the things you can combine are obligations you have written out by hand, one per person, and the only place a follow-on can go is inside one of them. There is no way to say "these people, as a group", and so no way to hang anything on the group.

Three proposed pieces close that gap. They are separate pieces — each one answers a different question, and you would choose them independently — and the clearest way to see them is as three questions.

---

## 1. Everyone, Then One Thing

**The question: after all of them have acted, what happens — once?**

Three flatmates must sign, and when the last of them has, the tenancy begins. In [Several Parties](several-parties.md) that was three obligations joined by `RAND` and nowhere to write "then the tenancy begins". The proposal is a way to write an obligation _for everyone in a group_ at once, and to attach a single follow-on to the group:

```l4
-- PROPOSED, NOT LANDED (2026-09-06). Does not run.
EVERY Flatmate f
    MUST   Sign f
    WITHIN 14
    HENCE  `the tenancy begins`     -- fires once, when the last of them has signed
    LEST   `the lease falls through`
```

Read `EVERY Flatmate f` as "for every flatmate, call them f": one obligation per flatmate, all live at once, exactly as the `RAND` was — and then one `HENCE` for the whole. The specification calls this shape a **"barrier"**: nothing follows until everyone has crossed it, and then one thing follows. Each flatmate who does not sign is in breach on their own account.

---

## 2. Each With Its Own

**The question: after each of them acts, what happens — for that one?**

A different sentence, and a different shape. Each flatmate who pays a share is to be given a receipt — three payments, three receipts, each following its own payment and not waiting for the others. Nothing here happens once for the group; everything happens once per person. The specification spells that with a second word:

```l4
-- PROPOSED, NOT LANDED (2026-09-06). Does not run.
EACH Flatmate f
    MUST   EXACTLY (Pay f `Ms Ng` 500)
    WITHIN 7
    HENCE  `a receipt to` f 500     -- fires for each flatmate who pays
    LEST   BREACH BY f
```

The specification calls this shape a **"fork"**: the group splits into its members, and each member carries its own follow-on. Without a `HENCE` or `LEST` the two shapes are the same thing — one obligation per person — and the difference between them is only where the follow-on attaches. That is why the two words are proposed as a pair.

_A note on the words, because it is the part most likely to change. The specification's own discussion records that `EVERY` and `EACH` may not survive contact with a first-time reader, and it records a proposal to call the two shapes "jointly" and "severally" instead — The research done that night recommends against it, and no ruling has yet been made. Those words carry a settled legal meaning, about who may be sued and whether one person's payment discharges the rest, which is not this distinction — and on the point of discharge it is the opposite: a joint promisor's payment discharges the others, where under everyone-then-one-thing nobody's act does anything for anyone else. The alternative the research prefers is to mark the shape on the follow-on line itself, so that one word serves for both: `HENCE ONCE ALL HAVE …` for everyone-then-one-thing, and `HENCE FOR EACH …` for each-with-its-own. Which spelling ships is not decided. What is decided is the pair of shapes._

_One thing about the words is settled (7 September 2026). The word after `EVERY` or `EACH` names the kind of party, as `Flatmate` does above, and it is that word which picks out the group; `EVERY f` with no kind word means every party there is. Whether the two words themselves stay `EVERY` and `EACH` is the part still open._

---

## 3. Enough of Them

**The question: when has enough happened for the follow-on to fire?**

The rent example from [Several Parties](several-parties.md) is the one that motivates this piece. Three flatmates, any amounts, until $1,500 has arrived by the seventh — one deadline on the total, and if it is not reached, all three in breach. Today's encoding, a rule that uses itself, restarts the clock on every payment and blames one flatmate. The proposal puts the condition on its own line, with the word `ONCE`, and lets that line carry the deadline and the breach:

```l4
-- PROPOSED, NOT LANDED (2026-09-06). Does not run.
EVERY Flatmate f
    MAY    Pay f `Ms Ng` amount
    HENCE FOR EACH
           PARTY `Ms Ng` MUST Receipt `Ms Ng` f amount WITHIN 5
ONCE   sum OF amount AT LEAST rent        -- when the payments add up to the rent
WITHIN 7                                  -- one deadline, on the total
HENCE  FULFILLED
LEST   BREACH BY EVERY Flatmate           -- everyone, not one of them
```

Read it from the last line upward. `ONCE sum OF amount AT LEAST rent` is the condition: the payments, added up, have reached the rent. `WITHIN 7` on that line is a deadline on the _condition_, not on any one payment — which is exactly the deadline the lease has and the rule-that-uses-itself could not express. `LEST BREACH BY EVERY Flatmate` blames the group; that `LEST`, the `WITHIN` and the `HENCE` beside it all belong to the `ONCE` line, not to the `MAY` inside. And inside, each payment is a `MAY`, because no single flatmate owes any single payment; what is owed is the state at the end. `HENCE FOR EACH`, inside, is the note's spelling for each-with-its-own — one receipt per payment — and `EVERY` at the top only names the group. (The design document's own version of this example uses tenants with names rather than a fixed cast; nothing else differs.) The specification puts it as a slogan: acts inside, state outside.

Two smaller members of the same family. A condition can be a _count_ rather than a total — "any two of the three signatories" on a bank mandate, a quorum of two directors — and the proposal spells that `SOME 2 OF Director d MUST sign … HENCE …`. **`SOME 2 OF` means _at least_ two of them**: the specification records a ruling that `SOME m OF` and `AT LEAST m OF` are the same thing, and warns that modern English reads "some 200 people" as "roughly", which is not what is meant. And a condition can be two conditions at once, joined by `AND` — the specification's example is the Singapore Companies Act's quorum for a members' meeting, which needs both a number of members and a share of the company between them.

The two ends of this family are familiar. "Once any one of them has" is `ROR`, which you already have; "once all of them have" is piece 1, which you do not. What is new in between is everything that is not a count of everybody: two of three, a sum, a percentage.

---

## Why These Are Three Pieces and Not One

It is tempting to see all of this as one big feature. It is three, and they combine, because each answers a question the others do not:

| Piece                    | The question it answers                            | The words proposed                           | Chosen independently of…                    |
| ------------------------ | -------------------------------------------------- | -------------------------------------------- | ------------------------------------------- |
| everyone, then one thing | where does the follow-on attach — once, after all? | `EVERY … HENCE …` (or `HENCE ONCE ALL HAVE`) | what the condition is                       |
| each with its own        | where does the follow-on attach — once per person? | `EACH … HENCE …` (or `HENCE FOR EACH`)       | what the condition is                       |
| enough of them           | when does the follow-on fire?                      | `ONCE …`, `SOME m OF …`                      | whether the follow-on is once or per person |

And all three sit beside `RAND` and `ROR` rather than replacing them. `RAND` and `ROR` combine obligations you have written out one by one, and will go on doing so. The three pieces above are for the case where the obligations are the same shape for everyone in a group, and something has to be said about the group. The specification also records the one combination that means nothing: a group with nothing waiting at the end — each-with-its-own on its own — together with a condition, since there is then no moment at which "enough" could be judged. The rent block above is not that: its receipts fire per payment, but the group still waits at the `ONCE` line.

---

## What Would Make This Page True

The specification lists it plainly, and this page repeats it so that a reader can check the state of things without opening the design document: a way for L4 to read the `ONCE` line and the count; a way to run it, which is either a rule that uses itself with the clock carried through properly or a running total kept where the group is counted; a breach that carries a set of people rather than one; test files for the rent by total and by share and for the quorum; and a page under this documentation before the work is closed. Six rulings on the design are open, and one — that `SOME m OF` means at least — has been given.

When those land, this page is deleted and the material moves into [Several Parties](several-parties.md), where the gaps it fills were shown. Until then, the honest encoding of a shared debt is the one on that page, with its two defects named.

---

## Next Steps

- [Several Parties](several-parties.md) — the arrangements that run today, and the defects these pieces would fix
- [The Regulative Layer, Whole](../../concepts/legal-modeling/regulative-layer-whole.md) — all five ideas of the regulative layer in one place, with the same built/proposed line drawn through them
- `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md` — the design itself, for a reader who wants the rulings and the reasoning (it is written for maintainers, not for this page's reader)
