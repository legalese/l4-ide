# How to write a waiver with the L4 you already have — DRAFT

> **Status (2026-09-28): a tutorial draft and a measurement, not a ruling.**
> Asked for in Meng's note on ruling N9 of `NORM-LOG-SPEC.md`, left on the rulings bench on 2026-09-28 without a mark: "let's try a "userspace-only" alternative to this new primitive; try writing a tutorial for how a user could synthesize the waiver using existing syntax and semantics; if that's easy enough to teach, we can be conservative and not create a WAIVE primitive. Perhaps that "primitive" becomes a lib function in prelude or elsewhere."
> **Unlike the norm-log how-to, every line of L4 on this page runs today.**
> The two contracts are `jl4/experiments/norm-log-waiver/waiver-userspace.l4` and `waiver-untimed.l4`; both were run on 2026-09-28 with the installed `l4` (built 2026-09-28 07:49) and, for the timed file, also on the norm-log probe's snapshot binary, with identical results.
> The verdict is in the last section.

---

## The situation

A patron who returns a book late may not borrow another while the default is **continuing**: the late return has not been put right, and the librarian has not waived it.
Waiving is something the **librarian** does; it is not a step in the patron's obligation.

## Step 1 — have the loan record its own failure

L4 does not yet keep a history of obligations for you (that is the norm log, not built), so the loan's author records the failure by hand, in the `LEST`, and records the cure when the fine is paid:

```l4
GIVETH DEONTIC Person Action
loan MEANS
  PARTY patron MUST `return` 1 WITHIN 14
  HENCE FULFILLED
  LEST  RECORD `overdue since` IS 14
        HENCE PARTY patron MUST payFine t WITHIN 100
              HENCE RECORD `cured at` IS t
              HENCE FULFILLED
```

This step needs the loan's author to cooperate.
If the loan rules and the borrowing rules have different authors, the borrowing author cannot write this themselves; that is the gap the norm log exists to close.

## Step 2 — give the librarian a power to waive

A waiver is a standing permission of the other party; exercising it writes to the official record:

```l4
GIVETH DEONTIC Person Action
waiverPower MEANS
  PARTY librarian MAY waive t WITHIN 100
  HENCE COMMIT `waived at` IS t
  HENCE FULFILLED
```

`COMMIT` rather than `RECORD`, because a waiver is an official act, not a note in the librarian's own ledger.

## Step 3 — say what "continuing" means, at a given moment

```l4
GIVEN now IS A NUMBER
      cell IS A MAYBE NUMBER
GIVETH A BOOLEAN
`happened by` MEANS
  CONSIDER cell
  WHEN NOTHING THEN FALSE
  WHEN JUST x THEN x AT MOST now

GIVEN now IS A NUMBER
GIVETH A BOOLEAN
`default continuing at` MEANS
      `happened by` now (RECALL patron's `overdue since`)
  AND NOT `happened by` now (RECALL patron's `cured at`)
  AND NOT `happened by` now (RECALL OFFICIAL's `waived at`)
```

## Step 4 — guard the borrowing, and put the rules together

```l4
GIVETH DEONTIC Person Action
borrowing MEANS
  PARTY patron MAY borrow 2 t PROVIDED NOT `default continuing at` t WITHIN 100

GIVETH DEONTIC Person Action
lwb MEANS loan RAND waiverPower RAND borrowing
```

Measured:

| trace                                           | expected | got     |
| ----------------------------------------------- | -------- | ------- |
| W1 late, fine unpaid, not waived, borrows at 30 | blocked  | blocked |
| W2 late, waived at 25, borrows at 30            | allowed  | allowed |
| W3 late, borrows at 30, waived at 40            | blocked  | blocked |
| W4 late, fine paid at 21, borrows at 30         | allowed  | allowed |

## Why every act carries a time, and the three traps

Every action above carries a number that is its own time (`payFine t`, `waive t`, `borrow 2 t`).
That is not decoration; each of the three traps below returns a wrong answer with exit code 0.

**Trap 1 — without times, a later waiver unlocks an earlier borrow.**
The first version of this tutorial (`waiver-untimed.l4`) recorded `waived` as `TRUE` with no time.
In W3, the librarian's waiver at 40 let the patron's borrow at 30 through.
The reason is that L4 runs the operands of a `RAND` one after another over the whole trace, and a plain `RECALL` reads the whole ledger, so the borrowing rule, running last, saw a waiver that had not happened yet at 30.
Comparing times, as Step 3 does, fixes it.

**Trap 2 — the times are whatever the party says they are.**
A guard has no name for the contract clock's "now", so the only way to get the time into the guard is to put it in the action, and the acting party supplies it.
W7: the patron borrows at 30 but claims `borrow 2 10`; since 10 is before the failure at 14, the guard finds nothing continuing and the borrow is **allowed**.
A guard cannot see the event's own `AT` (`NORM-LOG-SPEC.md` §7 N4), so nothing checks the claimed time against it.

**Trap 3 — the rule that reads must come after the rules that write.**
W6 is W1 with the borrowing rule written first (`borrowing RAND waiverPower RAND loan`).
It is **allowed**: the borrowing rule ran over the whole trace before the loan had recorded anything, so it saw an empty ledger.
Order the operands so that every writer precedes every reader.

## Verdict: teachable, but not yet safe to teach

The pattern is short and uses nothing exotic: a `RECORD` in the `LEST`, a `MAY` that `COMMIT`s, and a guard that `RECALL`s and compares.
As a prelude function it would be the `happened by` helper plus a documented idiom for the waiver power; the cell names would still be the drafter's, since a function cannot take a cell name as an argument today.

But the three traps are all silent, and a tutorial that has to warn about three silent traps is teaching around missing features rather than a pattern.
Each trap goes away with a ruling already made or pending, **not** with a waiver primitive:

| trap                        | goes away with                                                                                                     |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| 2, party-asserted time      | N4 (answered): a name for the contract clock's instant, so ``COMMIT `waived at` IS THE INSTANT`` needs no argument |
| 1, whole-log `RECALL`       | the same name, compared in the guard; or an as-of read on the contract clock for black ink                         |
| 3, reader before writer     | N10 (open): lockstep evaluation of operands, or at least the run-time refusal                                      |
| Step 1's cooperating author | the norm log itself (N1–N8), which records the failure and the cure without the loan's author                      |

So the evidence supports Meng's conservative instinct.
A `WAIVE` primitive is not what makes waiver hard; the contract-clock name and operand order are.
With those two in place, waiver is a `MAY` that `COMMIT`s its instant, read by a guard against the norm log, and it belongs in the prelude or a library as an idiom, not in the grammar.
