# How to read a contract's own history — DRAFT

> **Status (2026-09-28): a draft, written before anything exists.**
> Nothing on this page parses today.
> It was asked for in Meng's note on ruling N5 of `NORM-LOG-SPEC.md` (§6.1): _"with an L4 deontic chain of some form, how do we get out the information we need; if we have ledgers written in both red and black ink, how does the reader access both sides?"_
> It is written as the `doc/` how-to page would be, so that the design can be judged by how it reads to a drafter before it is built.
> **Every spelling in capitals below that is not already L4 is a placeholder**, because ruling N4 deliberately left the surface unchosen; `THE INSTANT` follows Meng's suggestion on N4 (_eo instante_).
> Where the page depends on a ruling that is still open, it says so in a box.
> When the feature ships, this becomes a page under `doc/` and this file is deleted.

---

## What this page is for

You are writing a rule that depends on what happened to **another** rule: whether an obligation was met, whether it was breached, whether a breach was put right, how often it has been missed.

A library is the running example.
A patron who returned a book late may not borrow another until the late return has been dealt with, even though the loan rules offer a fine as a way to settle a late return.
The loan rules and the borrowing rules were written by different people, and the borrowing rules must work without the loan rules having been written with them in mind.

## Two ledgers: black ink and red ink

Every contract evaluation keeps two kinds of record, and they answer different questions.

| ink       | who writes it                                  | what it says                                                 | how you read it               |
| --------- | ---------------------------------------------- | ------------------------------------------------------------ | ----------------------------- |
| **black** | the parties, with `RECORD`, `COMMIT`, `NOTIFY` | facts a party asserted: "the patron's card number is 17"     | `RECALL`, `RECALL ALL`        |
| **red**   | the machine, automatically                     | what happened to each obligation, prohibition and permission | the history expressions below |

Nobody writes red ink.
When an obligation is met, missed, or put right, the machine notes it, whether or not the drafter of that obligation thought anyone would ask.

**The two never mix.**
`RECALL` cannot see red ink, and the history expressions cannot see black ink (ruling N5).
This is deliberate: an audit printout must never show a party asserting something only the machine observed.
When a printout lists red-ink entries they carry the machine's own verb and a `bearer=`, never `RECORD` and `party=`.

## The chain

```text
-- illustrative, not L4 (the loan side is ordinary L4 today)
GIVETH DEONTIC Person Action
loan MEANS
  PARTY patron MUST `return` book WITHIN 14
  LEST PARTY patron MUST payFine WITHIN 7
```

The loan's author wrote nothing about history.
There is no `RECORD` in it, and there does not need to be.

## Step 1 — name the obligation you are asking about

You name it by **who** bears it, **what** they must do, the **modal**, and — when it matters — whether it is the **original** obligation or the one reached through a `LEST` (rulings N2, N8).

```text
-- illustrative, not L4
PARTY patron MUST `return` _          -- the loan itself
PARTY patron MUST payFine _ UNDER LEST -- the fine
```

You do not name the rule it came from, and you do not need the loan's author to have labelled anything.
If your description matches more than one place in the contract, L4 warns you; add a label to tell them apart.

## Step 2 — ask the question

| you want to know                                               | ask (placeholder spellings)                                   |
| -------------------------------------------------------------- | ------------------------------------------------------------- |
| has it ever failed?                                            | ``EVER FAILED (PARTY patron MUST `return` _)``                |
| is a failure still outstanding?                                | ``FAILED AND NOT CURED (PARTY patron MUST `return` _)``       |
| was a failure put right by its reparation, not by performance? | ``CURED BY REPARATION (PARTY patron MUST `return` _)``        |
| how many failures in the last year?                            | `THE NUMBER OF FAILURES OF (…) WITHIN 365 BEFORE THE INSTANT` |
| when did it fail?                                              | `THE INSTANT OF THE LAST FAILURE OF (…)`                      |

"Failed" means the deadline passed without performance; "cured by reparation" means everything its `LEST` required was then done by the same party (ruling N8, still open — see the box).

`THE INSTANT` is the **contract clock**: the moment in the trace at which your rule is being checked.
It is **not** `NOW`, which is the computer's wall clock, and using `NOW` in a `PROVIDED` gets a warning (ruling N4).

## Step 3 — put it in a guard

```text
-- illustrative, not L4
GIVETH DEONTIC Person Action
borrowing MEANS
  PARTY patron MAY borrow b
  PROVIDED NOT (FAILED AND NOT CURED (PARTY patron MUST `return` _))
  WITHIN 100
```

The table below is what the design must produce; the crude probe of `NORM-LOG-SPEC.md` §7 produced exactly this on traces T1–T3, by a route no drafter could write.

| trace                                    | borrow is |
| ---------------------------------------- | --------- |
| returned on time, then borrows           | allowed   |
| returned late, fine unpaid, then borrows | blocked   |
| returned late, fine paid, then borrows   | allowed   |

The strict ("moralistic") library — a late return blocks borrowing even after the fine is paid, until something else lifts it — asks `EVER FAILED`, or `THE INSTANT OF THE LAST FAILURE` against a period, instead.
Which you choose is a legal question, not an L4 one; the language makes both easy to write and hard to confuse.

## Reading both inks in one rule

Some rules need both: a waiver is something a party asserts (black), and "continuing" means failed (red) and not waived (black).

```text
-- illustrative, not L4
PROVIDED FAILED AND NOT CURED (PARTY borrower MUST payInterest _)
     AND RECALL OFFICIAL's `default waived` EQUALS NOTHING
```

Each half reads its own ink.
Until L4 has a proper waiver act (ruling N9, still open), this black-ink half is the way to write it, and the page says so plainly.

## What the history cannot tell you, and what it will not guess

These are the limits a drafter meets; they are stated here because each would otherwise be a wrong answer with no error.

- **A breach with nobody named.** A bare `LEST BREACH` is charged to whoever bore the obligation that failed. A breach that truly names nobody is reported as such, never silently dropped from a count (ruling N7).
- **A party L4 has not worked out yet.** If a count by party meets an obligation whose party is still unknown when you ask, the evaluation stops with an error naming the obligation, rather than returning a smaller number (N7).
- **Windows use the contract clock.** A failure counts from its missed deadline, not from when the machine noticed it (N3).
- **History lasts one evaluation.** A deployed contract that resumes from a saved position must carry its ledgers, both inks, with it (N11, still open).

> **Open — N10: rules side by side.**
> If `loan` and `borrowing` are two sides of one `RAND`, the side written first cannot today see the second side's history, because L4 runs the first side through the whole trace before starting the second — so the answer depends on which you write first (measured: `NORM-LOG-SPEC.md` §7 N10).
> The recommendation on the bench is that such a read is refused with an error until L4 evaluates both sides step by step together.
> Until N10 is ruled, this page cannot promise the library example works as one compound.

> **Open — N8: "cured".**
> The meaning of "cured by reparation" above is the bench's recommendation, not yet ruled.

> **Pending elsewhere — SEESAW.**
> When a compound breaches, the instant it reports is being ruled in another session; the "when did it fail" row follows that ruling.
