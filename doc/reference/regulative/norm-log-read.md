# Reading what became of a norm

A contract's later terms often depend on what happened to an earlier duty.
A late fee is owed only if the delivery failed.
A second payment counts only once the first is settled.
A waiver applies only to a duty that is still outstanding.
While a contract runs, L4 keeps a record of what became of each duty, permission and prohibition in it, and the phrases on this page ask that record a question from inside a rule.

**Status (2026-11-24): the spelling on this page is decided by Claude 2026-11-24, pending Meng's review.**
Whether the four phrases below are the right words is a question for Meng (card N4b of the norm log's rulings, `specs/todo/NORM-LOG-SPEC.md` §6.5).
If Meng rules for other words, the words on this page change and what they do does not.
Nothing on this page is in a released `l4` until the branch that builds it is merged.

## Words used here

A **"norm"** is one duty (`MUST`), permission (`MAY`) or prohibition (`SHANT`) as it applies to one party in one running contract.
The **"norm log"** is the record L4 keeps while the contract runs, of what became of each norm: it was armed, performed, left to lapse, failed, or repaired by a `LEST`.
A norm **"failed"** when its deadline passed with nothing done, or when a prohibited thing was done.
A failure is **"cured"** when the reparation its `LEST` armed was itself fulfilled.
An **"instant"** is a time on the contract's own clock, a `NUMBER` like the times in a `#TRACE`.

## The four questions

Each phrase is a question about a norm, as at an instant.
Each is a `BOOLEAN`: true when any norm that matches the pattern (below) is in that state.

| Phrase                 | True when, as at the instant                                                   |
| ---------------------- | ------------------------------------------------------------------------------ |
| `OUTSTANDING`          | the norm has been armed and nothing has been decided about it yet              |
| `EVER FAILED`          | the norm has failed, whether or not a reparation later cured it                |
| `FAILED AND NOT CURED` | the norm has failed and the reparation its `LEST` armed has not been fulfilled |
| `CURED BY REPARATION`  | the norm has failed and the reparation its `LEST` armed has been fulfilled     |

## The pattern

A pattern says which norms the question is about, by who is bound, the modal, and the action:

```text
OUTSTANDING (PARTY patron MUST `return` _)
EVER FAILED (PARTY _ MUST pay _ UNDER LEST)
```

- `PARTY patron` is a bearer written as in a rule; `PARTY _` matches any bearer.
- The modal is `MUST`, `MAY` or `SHANT`.
- The action is the **name** of an action, with one `_` for each of its fields: a read matches a norm by the name of its action and does not compare the arguments.
  `pay _` matches every `pay` whatever the amount.
- `UNDER LEST` or `UNDER HENCE` at the end narrows the pattern to norms that a `LEST` (or a `HENCE`) armed.
  A pattern with neither matches the norm wherever it was armed.
- `AS OF <instant>` after the closing bracket asks as at that instant, in the past or now.
  An instant after the contract's clock is refused (below).
- `MUST` also matches a norm written with `DO`, which fails on the same terms.

## Where a read may be written

A read is true or false as at an instant, so it needs one.
Inside a `PROVIDED` guard its instant is the event the guard is checking, `THE INSTANT` (see [the time of the event](consequences.md#the-time-of-the-event-the-instant)); anywhere else it needs an explicit `AS OF`.
Written with neither, it is a check error that says so.

A read is answered from the record as it stands when the read is reached, and only as at an instant the contract has reached.
The contract's clock is the latest instant the run has been at: the event a guard is being checked against, or the latest instant in a norm already recorded.
An `AS OF` after it asks about what has not happened yet, so it is refused by name and not answered from the part of the record written so far.
A read written with no `AS OF` in a guard asks at the event's own instant, which is never in the future.
A rule that holds a read is asked again every time something uses it, so its answer in one guard is never kept for the next.
To share a read between guards, give the rule the instant it asks at, and pass `THE INSTANT` from each guard, as `pending (THE INSTANT)` below does: a rule cannot reach `THE INSTANT` itself.
A norm may read itself in its own guard with `PARTY _` and sees itself as outstanding; with a named party the read stops, as described below, because the norm has not met its party yet.

```l4
GIVETH A DEONTIC Person Action
`late fee` MEANS
  PARTY Alice MUST deliver WITHIN 3
  LEST (PARTY Alice MUST pay fee
          PROVIDED EVER FAILED (PARTY Alice MUST deliver) AND fee >= 5
          WITHIN 10)
```

The delivery fails at 3, which arms the fee.
The fee counts only from 5 up, so a payment of 1 at 5 is skipped and a payment of 7 at 6 fulfils it.
The second example of the file asks as of an earlier instant: a delivery made at 4 was still outstanding as of 2.
**Example file:** [norm-log-read-example.l4](norm-log-read-example.l4)

A read shared by two guards takes the instant as an input:

```text
GIVEN t IS A NUMBER
GIVETH A BOOLEAN
pending t MEANS OUTSTANDING (PARTY _ MUST deliver) AS OF t
```

and each guard says `PROVIDED pending (THE INSTANT)`.

## What happens when a read cannot be answered

Loud, each a named error and never a quiet "no":

- A `_` anywhere but inside a read pattern.
- A read with no instant: not in a `PROVIDED` and with no `AS OF`.
- A read inside an operand of `RAND`, `ROR` or `EVERY`.
  The operands run side by side, so what the read saw would depend on which sibling ran first; the check that makes this safe is not built.
  A read written in the operand itself is a check error; one written in a rule the operand uses stops the run when it is reached.
- An `AS OF` later than the contract's clock, and any read made before a contract has run (a plain `#EVAL` of a read).
- The wrong number of `_` for the action's fields.
- Anything but `_` in an argument place, such as `pay 3`: a parse error at that argument, which does not say that only `_` is allowed.
- A pattern that names an action declared in this module with a modal no norm of the module has: it could never match.
- A bearer the machine never had to look at (a norm still waiting, whose party nothing has evaluated yet), when the pattern names one: the read stops, saying so.
  `PARTY _` is never refused for this.
- A norm whose deadline or alternative cannot be placed in time well enough to answer.
- A read that runs with the record switched off, which can happen only for a read in an imported module (below).

Silent, because the answer is a plain "no" with nothing to say that it is wrong:

- **A pattern that names an action an imported module declares** is not checked against that module's norms, so a misspelling of the modal answers "no".
- **`UNDER LEST` and `UNDER HENCE` are not checked against the module.**
  The check that a pattern matches some norm of the module looks at the modal and the action only, so `UNDER LEST` where no `LEST` ever arms such a norm answers "no" on every trace.
- **The arguments are not compared.**
  `pay _` asks about every payment, not about a payment of a given amount.
- **A permission that lapsed counts as a cure** of the failure it repairs, because a `MAY` that is not exercised is not a breach.
  That is a reading of the rule, decided by Claude 2026-11-24, pending Meng's review.
- **`EVER FAILED` counts a failure that was later cured**; ask `FAILED AND NOT CURED` for the ones still standing.
- **From inside a reparation's own continuation, a failure is not yet cured**, because the continuation is part of what has to be fulfilled.
  `CURED BY REPARATION` asked there is false, and `FAILED AND NOT CURED` is true.

## When the record is kept

L4 keeps the record only for a contract that reads it: running a module that contains a read switches it on.
A read written in a module that is imported does not switch it on, so the read stops with an error naming it.
Each contract run in one directive (two `EVALTRACE`s in one `#EVAL`) keeps its own record: a read in the second does not see the first's norms.

## Where the read has been run

Through `l4 run` (`#EVAL` and `#TRACE`), by the tests and the example on this page.
Not run with a read in it: `l4 explore`, `l4 lts --steps`, `jl4-service`, `l4 batch`, the REPL, and the WASM build.
What each does with a read is not known yet, so do not rely on a read there until this page says it has been run.

## See also

- [Deadlines and consequences](consequences.md): `PROVIDED`, `HENCE`, `LEST`, and `THE INSTANT`.
- `specs/todo/NORM-LOG-SPEC.md` §6.5: the decisions behind this page, and what is not built.
