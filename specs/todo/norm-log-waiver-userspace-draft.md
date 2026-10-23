# How to write a waiver with the L4 you already have — DRAFT

> **Status (2026-09-28): a tutorial draft and a measurement, not a ruling.**
> Asked for in Meng's note on ruling N9 of `NORM-LOG-SPEC.md`, left on the rulings bench on 2026-09-28 without a mark: "let's try a "userspace-only" alternative to this new primitive; try writing a tutorial for how a user could synthesize the waiver using existing syntax and semantics; if that's easy enough to teach, we can be conservative and not create a WAIVE primitive. Perhaps that "primitive" becomes a lib function in prelude or elsewhere."
> **Unlike the norm-log how-to, every line of L4 on this page runs today.**
> The contracts are in `jl4/experiments/norm-log-waiver/`: `waiver-userspace.l4` and `waiver-untimed.l4`, and, added 2026-10-09 from the N9 card's skeptic, `waiver-two-defaults.l4` (trap 4) and `waiver-targeted.l4` (the version to teach). The first two both were run on 2026-09-28 with the installed `l4` (built 2026-09-28 07:49) and, for the timed file, also on the norm-log probe's snapshot binary, with identical results.
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

## Why every act carries a time, and the four traps

Every action above carries a number that is its own time (`payFine t`, `waive t`, `borrow 2 t`).
That is not decoration; each of the four traps below returns a wrong answer with exit code 0.

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

**Trap 4 — a waiver that names nothing waives everything.**
Found by the N9 card's skeptic on 2026-10-09 and re-run here.
`waived at` and `cured at` above name no default, so with two loans (`waiver-two-defaults.l4`) a waiver of the first late book at 25 also clears the second, late at 60, and a borrow at 70 is **allowed**; without the waiver it is blocked.
A waiver given at 5, before any default exists, likewise clears a default at 14 (whether an advance waiver should count is a legal question; the idiom should make it a choice, not an accident).
The fix is in the idiom: each waiver and each cure names the book it answers (`waive b t`, `RECORD `cured` IS Mark b t`), and the guard reads every default with `RECALL ALL` and asks whether **some** default is still continuing (`waiver-targeted.l4`: one of two defaults waived blocks, both waived allows).
That is the version to teach.

## Verdict: teachable, but not yet safe to teach

The pattern uses nothing exotic: a `RECORD` in the `LEST`, a `MAY` that `COMMIT`s, and a guard that `RECALL ALL`s and compares; the targeted version is about 45 lines.
A prelude helper has little to do. Today it would be the time comparison, and once N12's as-of `RECALL` lands even that goes, because a guard's read is already as of its own instant.
A generic library function ("is some default continuing?") would need a variable to name a cell, and today a cell is a literal: the parser lowers it to a string key (`Parser.hs` ~2806 on `origin/unstable` @ `a8ec02a81`, "data (a key), not a variable reference"), while the type checker and evaluator already treat it as a `STRING` expression — so the limit is the parser's alone.

But the traps are all silent, and a tutorial that has to warn about silent traps is teaching around missing features rather than a pattern.
Three go away with rulings made or pending, and the fourth with the targeted idiom, **not** with a waiver primitive:

| trap                        | goes away with                                                                                                                             |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| 1, a later waiver is read   | N12 (open): a `RECALL` inside a contract reads as of its own instant, and the latest by instant, not by log position                       |
| 2, party-asserted time      | N4 (answered, spelling not chosen): a name for the contract instant, so ``COMMIT `waived at` IS THE INSTANT`` takes no time from the party |
| 3, reader before writer     | not cured: N12 rule (4) and N10's run-time check make it a loud error; N10's lockstep option would make it right                           |
| 4, untargeted waiver        | the targeted idiom today (`waiver-targeted.l4`); for reads of the norm log, N2's address with argument patterns                            |
| Step 1's cooperating author | the norm log itself (N1–N8), which records the failure and the cure without the loan's author                                              |

So the evidence supports Meng's conservative instinct.
A `WAIVE` primitive is not what makes waiver hard; the contract instant, as-of reads and operand order are, and naming the target is a habit the idiom can teach.
With those in place, waiver is a `MAY` that `COMMIT`s what it waives at its instant, read by a guard against the norm log, and it belongs on an idiom page, not in the grammar.
One honest caveat: a primitive would name its target by construction (`HOMOICONICITY-SPEC.md`'s `WAIVE` takes the obligation), where the idiom relies on the drafter; but that `WAIVE` takes a live obligation, and the norm log needs the pardon of a failure already incurred, which it does not cover.
