# What is owed now: `l4 lts`

You have a contract written in L4, and a record of what has happened so far — who did what, and when. The question a party asks at that point is not "what does the contract say" but:

> **Given what has happened, what do I owe right now, what would discharge it, and what would put me in breach?**

`l4 lts` answers that question as a plain list. It reads every `#TRACE` in a file — a trace is a contract plus the events that have happened to it, as taught in [Testing with #TRACE](README.md#testing-with-trace) — and for each one it prints:

1. **where the contract stands** — still in progress, fulfilled, or breached;
2. **what is owed now** — by whom, to do what, by when;
3. **what would discharge it** — which act, done now, ends the contract fulfilled;
4. **what would put someone in breach** — usually, the deadline passing;
5. **what would move things along** without ending anything;
6. **the next deadline**.

Every one of those answers comes from **running the contract**. The list does not read the rule and guess what a `MUST` or a `SHANT` means; for each thing that could happen it appends that event to the trace, runs the whole contract again, and reports what came out. (The name, for the curious: the view it belongs to is the contract's **"labelled transition system"** — its positions and the moves between them — and this list is the first rendering of it. A picture may follow; see the last section.)

**Status (2026-09-15):** built. The command, the `--steps` history, `--json`, and `--contract` all run; the outputs below are pasted from a real run, and the three corpus files it is pinned on are in `jl4/examples/lts/expected/`.

## A worked example

**Example file:** [lts-list-example.l4](lts-list-example.l4)

A sale. The seller must deliver within three days; once delivered, the buyer must pay 100 within seven days, and if the buyer misses that, a late price of 120 is owed within fourteen more. The seller delivered on day 2.

```l4
saleContract MEANS
  PARTY Seller
  MUST delivery
  WITHIN 3
  HENCE (
    PARTY Buyer
    MUST payment EXACTLY 100
    WITHIN 7
    LEST (
      PARTY Buyer
      MUST payment EXACTLY 120
      WITHIN 14
    )
  )
  LEST BREACH BY Seller

#TRACE saleContract AT 0 WITH
  PARTY Seller DOES delivery AT 2
```

Run it:

```bash
l4 lts lts-list-example.l4
```

What comes back, exactly:

```
saleContract — after 1 event, the clock stands at 2 (the #TRACE on line 27)
    PARTY Seller DOES delivery AT 2
  Standing: in progress.

  Owed now:
    - Buyer MUST payment OF 100 — due by 9 (7 from now)

  What would discharge it (the contract ends fulfilled):
    - Buyer does payment OF 100 now (at 2) → fulfilled

  What would move things along (neither ends nor breaches it):
    - nothing happens by 9 (the clock reaches 10) → then:
          · Buyer MUST payment (EXACTLY 120) — due by 23 (13 from now)

  Next deadline: 9 (Buyer: payment OF 100)
```

Reading it from the top:

- **The heading** names the contract, counts the events, and says where the **contract clock** stands — the time of the last event, here day 2. Every "due by" below is on that clock. The events themselves are listed under it, as written in the file.
- **Standing** is the one-word answer: _in progress_, _FULFILLED_, or _BREACHED_ with who and why — or, if the contract could not be run, _could not be worked out_ with the reason.
- **Owed now** is the list of obligations in force. There is one: the buyer must pay 100, due by day 9 — that is 7 from now, because the seven days started when the seller delivered on day 2. The act is written out as it would be done (`payment OF 100`): where the rule says `EXACTLY n` and `n` is defined elsewhere, the list looks `n` up and prints the number, so you do not have to.
- **What would discharge it** lists the acts that, done now, end the contract fulfilled. Paying 100 does.
- **What would move things along** lists what changes the position without ending it. Here, if nothing happens by day 9, the buyer is not yet in breach: the late-price clause takes over, and the buyer owes 120 by day 23 — its `WITHIN 14` counts from the deadline that was missed (day 9), not from the day the miss was seen (see [LEST](README.md#lest-breach-consequence)). The list prints what would be owed after that ("then:").
- There is no **What would put someone in breach** section, because in this position nothing does — the late-price clause catches the missed deadline. In the tenancy example below, whose rule ends in `LEST BREACH`, the deadline passing does breach, and the section appears.
- **Next deadline** is the soonest date anything is due, and whose it is — counting only the deadlines the list could confirm by running the contract past them. If an obligation has a deadline the list could not work out, the line says so and names it, rather than quietly leaving it out: `Next deadline: 9 (Buyer: payment OF 100) — not counting Seller: delivery, whose deadline is not known here`.

## The sections, and when each appears

A section is printed only when it has something in it (**Owed now** is the exception: while the contract is in progress it says `nothing` rather than vanishing). The full set:

| Section                               | What it lists                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Owed now**                          | every obligation, permission and prohibition in force: who, `MUST`/`MAY`/`SHANT`, the act, and the due date. Under an `EVERY`, which group the member belongs to (see below). Also, marked as such, what is not in force but still part of the position: an obligation `not yet started`, one `in breach`, and, under `ROR`, an alternative already lost, marked `no longer available` |
| **What would discharge it**           | an act that, done now, ends the contract fulfilled. Where the rule leaves a value to the party (`MUST Pay … amount`), this is a SET of acts — "with any `amount`" — and the two lines under it say so and name the one act that was run to check it                                                                                                                                    |
| **What would put someone in breach**  | an act, or a deadline passing, that ends the contract breached — with who is blamed and what they missed                                                                                                                                                                                                                                                                               |
| **What would move things along**      | an act, or a deadline passing, that leads to a new position — and what would be owed there                                                                                                                                                                                                                                                                                             |
| **What the contract would pass over** | an act the contract does not take: it is not the awaited act, not this party's to do, or its `PROVIDED` condition does not hold. Nothing changes. The reason is the one the contract gave for that party's own obligation, even when another obligation looked at the act first.                                                                                                       |
| **What could not be tried**           | a shape the list can name but cannot run — see [Limits](#limits)                                                                                                                                                                                                                                                                                                                       |
| **Next deadline**                     | the soonest due date among everything owed, and whose it is; any obligation whose deadline could not be confirmed is named on the same line                                                                                                                                                                                                                                            |

The things the list tries are exactly the obligations' own acts (each one, done now by the party who owes it) and, for each distinct deadline, the clock running just past it with nothing happening — one unit past, or half-way to the next deadline when that is nearer, which is why a line can read `the clock reaches 7.5`. That is what "what could happen" means here; it is not every conceivable event.

## Acts the rule leaves open

A rule often does not name the act exactly. `PARTY B MUST return` leaves the whole act to B; `MUST Pay (EXACTLY t) (EXACTLY theLandlord) amount` leaves the sum; `MUST payment price PROVIDED price >= 20` leaves the price but tests it. In each case what discharges the obligation is not one act but a **set** of them, and that is what the list prints:

```
  What would discharge it (the contract ends fulfilled):
    - B does anything now (at 10) → fulfilled
      any act by B counts: the rule binds `return` rather than naming an act
      checked by replaying one act from that set, with `return` = delivery
```

Three things are being said, and it is worth keeping them apart:

1. **the set** — "anything", "with any `amount`", "with any `price` for which `price AT LEAST 20` holds". This comes from the rule's own text: a name in that position is filled in by the event, and a `PROVIDED` condition that mentions it is the only thing that narrows it.
2. **the verdict** — `→ fulfilled`. This is the contract's own answer, and it is an answer about **one** act: the list picked a value, ran the whole trace again with that act appended, and reports what came back.
3. **which act that was** — the last line. The value is never invented: it is the other side of the condition when there is one (`price AT LEAST 20` → 20), else the simplest value of the type the rule declares for that place (`0` for a number, the first choice of a `DECLARE … IS ONE OF`), else, for an act the rule leaves open entirely, an act the file's own `#TRACE` already writes.

If the contract turns out not to take the act the list picked — a `PROVIDED price GREATER THAN 20` is not satisfied by 20 — then nothing has been shown about the rest of the set, and the line moves to **What could not be tried** saying exactly that. The same happens when no value could be built at all.

## Groups: the barrier and the fork

When an obligation is written with [EVERY](EVERY.md), every member of the group owes it at once, and the list says how they relate. `jl4/examples/bpmn/tenancy.l4` holds the reference pair — three tenants who must each sign (a **barrier**: the landlord's delivery waits for all of them), and three who must each pay (a **fork**: each payment earns its own receipt). The file has no `#TRACE`, so the list is asked for each rule at its outset with `--contract`:

```bash
l4 lts tenancy.l4 --contract "the tenancy" --contract receipts
```

For the barrier, the group is announced on each member's line, and one extra line says what the group is waiting for:

```
  Owed now:
    - Tenant OF "Alice" MUST Sign OF (Tenant OF "Alice") — due by 14 (14 from now) (one of 3 who must all act before the next step)
    - Tenant OF "Bob" MUST Sign OF (Tenant OF "Bob") — due by 14 (14 from now) (one of 3 who must all act before the next step)
    - Tenant OF "Carol" MUST Sign OF (Tenant OF "Carol") — due by 14 (14 from now) (one of 3 who must all act before the next step)
    - the next step is held back until all have acted: 0 of 3 have
```

and the deadline passing breaches — the rule says `LEST BREACH` without naming anyone, and the list says so rather than guessing:

```
  What would put someone in breach:
    - nothing happens by 14 (the clock reaches 15) → the contract is in breach (no party is named)
```

while one tenant signing does not end anything — it moves the count to 1 of 3:

```
  What would move things along (neither ends nor breaches it):
    - Tenant OF "Alice" does Sign OF (Tenant OF "Alice") now (at 0) → then:
          · Tenant OF "Bob" MUST Sign (EXACTLY t) — due by 14 (14 from now) (one of 3 who must all act before the next step)
          · Tenant OF "Carol" MUST Sign (EXACTLY t) — due by 14 (14 from now) (one of 3 who must all act before the next step)
          · the next step is held back until all have acted: 1 of 3 have
```

For the fork there is no "held back" line, because nothing waits: each member's line says so, and each member's act would start that member's own next step. Here the rule leaves the sum to the tenant, so what moves that member's branch along is a set of acts rather than one — see [Acts the rule leaves open](#acts-the-rule-leaves-open):

```
  Owed now:
    - Tenant OF "Alice" MUST Pay OF (Tenant OF "Alice"), theLandlord, amount — due by 7 (7 from now) (one of 3, each with a next step of their own)

  What would move things along (neither ends nor breaches it):
    - Tenant OF "Alice" does Pay OF (Tenant OF "Alice"), theLandlord, amount, with any `amount` now (at 0) → then:
          · theLandlord MUST Receipt (EXACTLY theLandlord) (EXACTLY t) (EXACTLY amount) — due within 5 from now
          · Tenant OF "Bob" MUST Pay (EXACTLY t) (EXACTLY theLandlord) amount — due by 7 (7 from now) (one of 3, each with a next step of their own)
          · Tenant OF "Carol" MUST Pay (EXACTLY t) (EXACTLY theLandlord) amount — due by 7 (7 from now) (one of 3, each with a next step of their own)
      any `amount` counts: the rule binds it and does not test it
      checked by replaying one act from that set, with `amount` = 0
```

The full output for both, taken with `--steps`, is the golden `jl4/examples/lts/expected/tenancy.txt`.

## `--steps`: what the contract did with each event

The list is about **now**. Add `--steps` and it also prints the history: one line per look the contract took at an event, contract clock first, in the order the contract took them. That order is the contract's, not the calendar's: under an `EVERY` the contract works through the events member by member, and parallel parts — a `RAND`/`ROR`, or the members of an `UPON EACH` fork, which the contract runs as parallel parts — side by side, so the clock does not run steadily down the page — `at 1, at 1, at 2, at 1, at 2, at 9` below is member 1's look, then member 2's two looks, then member 3's three. From the first trace of [every-run-example.l4](every-run-example.l4), where three tenants sign on days 1, 2 and 9 and the landlord delivers on day 13:

```
  Steps, in order:
    at 1: Tenant OF "Alice" does Sign OF … at 1; Tenant OF "Alice" MUST (member 1 of 3) — done; on to what follows (1 of 3 have acted; the shared next step waits for the rest)
    at 1: Tenant OF "Alice" does Sign OF … at 1; Tenant OF "Bob" MUST (member 2 of 3) — not this party's event; passed over
    at 2: Tenant OF "Bob" does Sign OF … at 2; Tenant OF "Bob" MUST (member 2 of 3) — done; on to what follows (2 of 3 have acted; the shared next step waits for the rest)
    at 1: Tenant OF "Alice" does Sign OF … at 1; Tenant OF "Carol" MUST (member 3 of 3) — not this party's event; passed over
    at 2: Tenant OF "Bob" does Sign OF … at 2; Tenant OF "Carol" MUST (member 3 of 3) — not this party's event; passed over
    at 9: Tenant OF "Carol" does Sign OF … at 9; Tenant OF "Carol" MUST (member 3 of 3) — done; on to what follows (3 of 3 have acted; the shared next step waits for the rest)
    at 9: the group — everyone has acted; the shared next step begins
    at 13: Landlord OF "Ms Ng" does Deliver OF … at 13; Landlord OF "Ms Ng" MUST — done; on to what follows
```

Each line reads: the clock; the event looked at; whose obligation looked at it; what it decided. The same event appears once per obligation that looked at it — Alice's signature on day 1 is "done" for Alice and "passed over" for Bob and Carol — so the count of lines is not the count of events. The clock at the start of the line (`at 2:`) is the time the obligation had in hand when it looked — the last event it had seen — and the event's own time follows it, so a line can read `at 2: the event at 20; … deadline 14 passed without the act`: the obligation, last updated on day 2, looked at an event from day 20 and found its deadline gone. A line ending `[the same event, offered a second time]` is a look at an event that had already been looked at further up the same chain and handed on: by an obligation whose deadline that event showed to be missed (its `LEST` is handed the event that revealed the miss), or by a group's members (a `LEST` on the `ONCE` line is handed what the members had already seen, from the first event past the group's deadline). It is the same event, not a new one; count it as none.

Two things about this history are worth knowing:

- A party is named in full — `Tenant OF "Bob"`, the same words the **Owed now** lines use — once the contract has looked at every part of it. Comparing it with an event's party is the first thing an obligation does with an event that is in time, and that comparison looks at the parts in order and stops at the first one that differs. So a line that looked at an event names who looked when the two parties matched, or when they differed only in the last part — which is every case for a party with one part, like the `Tenant OF "Bob"` here — and names who acted where the contract got as far as looking at them (an expiry is found from the event's time alone, so that line says only `the event at 20`). A party with several parts, say `Tenant OF "Bob", 40`, whose first part already differed from the actor's, is shown as `Tenant OF …, …` on that `not this party's event` line and on the `still waiting` line after it, because its later parts were never looked at. An act shown as `Sign OF …`, or a party shown as `Tenant OF …`, is one the contract had not fully looked at when the step was recorded (an act is only unpacked as far as the rule's pattern needs; a party is looked at only when an event arrives): the log writes down what the contract had in hand at that moment, and does not go and fetch the rest. A `still waiting` line before any event has arrived is the usual case of a party still shown as `Tenant OF …`; there, the **member number** (`member 2 of 3`) is what tells the members apart, and the events are listed in full under the heading.
- A party the contract has not looked at at all is written **as the rule wrote it**, and marked so: `theLandlord (as written; not yet resolved) MUST — deadline 15 passed without the act; that is a breach`. That happens when a rule names its party by a defined name (`PARTY theLandlord`, where `theLandlord MEANS Landlord OF "Ms Ng"`) and the obligation runs out of time with no `LEST` to go on to: the deadline is found from the event's time alone, nothing ever compares the party, and the log writes down what it has, which is the name in the rule. The same wording appears on a `still waiting` line before any event, for the same reason. The marker matters: `theLandlord` on that line and `Landlord OF "Ms Ng"` on the **Standing** line above it are one party under two spellings, not two parties, and a line without the marker — `Landlord OF "Ms Ng" MUST — …` — is one where the contract did look. (Since 2026-09-19; before that the line read `(party not yet known) MUST — …`, which still appears where a breach lists the several obligations it names, since those come from the breach itself rather than from a rule's line.)
- `at —` marks a step with no clock. Four steps have none: a look before any event has arrived; the moment two parallel parts of a contract are combined — a `RAND`/`ROR`, or the members of an `UPON EACH` fork, which the contract runs as parallel parts; a `BREACH` the rule declares outright (`LEST BREACH`), which is a verdict, not a look at an event; and a group with no `LEST` of its own whose member ended without a time — a member's permission lapsed, or a member's own `LEST BREACH` fired. (A group whose member missed a deadline is clocked at the moment the miss was seen when the group has no `LEST`; a group with a `LEST` of its own is clocked at the deadline the member missed, which is when its `LEST` starts — so the second trace of `every-run-example.l4`, where Carol never signs and the landlord's event on day 20 reveals it, reads `at 14: the group — a member did not come through; on to the fallback` — the golden `jl4/examples/lts/expected/every-run-example.txt` has it.)

## `--json`

`--json` prints the same answers as JSON, one object per trace, for a program to read. The keys are the section names: `standing`, `owed`, `discharging`, `breaching`, `advancing`, `passedOver`, `untried`, `nextDeadline`, `deadlineNotKnown` (the obligations the "not counting" clause names; usually empty), plus `contract`, `line`, `events`, `clock`, `format`, and, with `--steps`, `steps`. The golden `jl4/examples/lts/expected/contracts.json`, taken with `--steps`, is a complete specimen.

Two rules make it safe to switch on:

- **Every value a program would branch on is a fixed token, never a sentence.** The sentences are the plain listing's; here they appear only under `why` and `reason` fields kept for a human reading the file. The tokens, by key:
  - `format`: `1`. Bumped if a key or token below ever changes meaning; a consumer should check it.
  - `standing.status`: `inProgress` · `fulfilled` · `breached` (with `breach`) · `notEvaluated` (with `why`).
  - `owed[].kind`: `owed` (with `party`, `modal`, `action`, and `dueBy`/`dueWithin`/`remaining` as known; `dueAnchor` beside `dueWithin` when the rule's `WITHIN` counts from an anchor, `THE JOIN`, `THE DEADLINE` or `THE ARMING`, rather than from now; `dueBefore` for a `BEFORE` date; and, while a window with an opening edge has yet to open, `opensAt` on the contract clock — or, before the first event, `opensAfter` with the `AFTER` as written and `opensAnchor` when it names one) · `heldBack` (with `done`, `total`, `until`: `allHave`) · `notStarted` (with `source`) · `inBreach` · `lapsed` (both with `breach`).
  - `modal`, wherever it appears: `MUST` · `MAY` · `SHANT` · `DO` — the keywords.
  - `owed[].group.join`: `barrier` · `fork` · `none`.
  - A candidate event's `kind`: `act` (with `party`, `action`, and `at` when it could be tried) · `tick` (with `deadline`, `whose`) · `noTick` (a deadline the list could not confirm; `whose`).
  - `passedOver[].reason`: `guardFalse` · `tooEarly` (with `opensAt`: the act came before the window's [`AFTER`](AFTER.md) opened, and counts for nothing) · `wrongAct` · `wrongParty` · `noTaker`.
  - `steps[].event.kind`: `act` (with `party`, `action`) · `clock` (the contract's own clock running on).
  - `steps[].norm`: `party` (the party as the contract has resolved it; null until it has looked), `modal`, `activation` (the _n_-th entry into that rule's line in this trace), and under an `EVERY` `member` and `of`. When `party` is null and the rule wrote its party as an expression, `partyAsWritten` carries that expression's text (`"theLandlord"`) — the spelling in the rule, which is not the resolved party and does not compare equal to one (added 2026-09-19; `party`'s meaning is unchanged).
  - `steps[].outcome.what`: `waiting` · `partyMismatch` · `actionMismatch` · `guardFailed` · `earlyAct` (with `opensAt`) · `matched` · `expired` · `breached` (with `by`, `names`, `anchor`; each of `names` says `named` — whether the rule's `BREACH BY` named anyone — beside `party`, which is null until the contract has worked out who) · `joined` (with `operator`: `and`/`or`; `result`: `fulfilled`/`breached`/`pending`; `winner`: `left`/`right`/`both`, null while pending; `tieBreak`; and, for a breached join, the same `by`, `names`, `anchor` as `breached`) · `joinReleased` · `joinExpired` · `joinFailed` · `joinStalled`. Where a step moved on, `then` is `hence` · `lest` · `breach`.
  - `steps[].join.kind`: `barrier` (with `done`, `total`) · `fork` (with `member`, `total`).
  - `steps[].scrutiny`: `consumed` · `witnessedOnly` · `reoffered` · `noEvent`.
- **Times are JSON numbers on the contract clock.** A time that is not a terminating decimal (a third of a day) is rounded to a double; the plain listing prints it exactly.

## `--contract NAME`

A file with no `#TRACE` has nothing to list. `--contract NAME` lists the rule called `NAME` at its outset — before anything has happened — exactly as a `#TRACE NAME AT 0 WITH` with no events would, without editing the file. Write the name without its backticks (`--contract "the tenancy"`), repeat the option for several rules, and note that only a rule that takes no inputs can be listed this way. An unknown name is an error, not an empty list.

## Limits

State plainly, because a reader will find them anyway:

- **The list tries the obligations' own shapes, not every event there could be.** What it puts under "discharge", "breach" and "move things along" is exact for the acts it tried — each verdict is the contract's own — but the shapes come from reading the position, before the contract has been asked whether it would take them. So a shape can be listed and then turn out to be passed over (that is what the **pass over** section is for), and an event nobody's obligation names — a payment of the wrong amount, an act by a third party — is not listed at all, although it would still move the clock. In the language of the design document this is the enabled set as an **over-approximation** (`specs/todo/lexipedia-superset/LTS-VISUALISER.md` §1.1b, loss G9): "no listed act breaches" is sound; "nothing else could" is not something the list says.
- **An act the rule leaves open is answered for the SET, on the strength of ONE act.** `MUST payment price PROVIDED price >= 20` is listed as "with any `price` for which `price AT LEAST 20` holds", and the verdict beside it — fulfilled, breached, or a new position — is the contract's answer for the single act the list ran, not for every value at once. That the rule accepts any value in that place is read off the rule; that the act does what the line says is read off the run. See [Acts the rule leaves open](#acts-the-rule-leaves-open) for how the value is chosen. Two cases still land under **What could not be tried**: the value the list picked was passed over by the contract (a `PROVIDED price GREATER THAN 20` is not met by 20), and no value could be built at all. Both say so in the line.
- **A value the contract has been told but not yet looked at cannot be supplied either.** A landlord's `Receipt theLandlord t amount`, owed to a tenant whose own payment fixed `amount`, before anything has compared it; a rule input like `price` in `MUST pay (price PLUS 50)` before the first event; a `WHERE` local the rule fixes, like `y` in `MUST pay (y PLUS 1) … WHERE y MEANS 41`, before the contract has worked it out. These are listed under **What could not be tried** with "the action binds `amount`, which the what-if cannot choose" — a different case from the one above, because here the list cannot even say what the set of acts _is_. They are listed rather than dropped: a list that omitted them would say "nothing else can happen", which is false. The name is always spelled as the rule wrote it, even for a rule under a `§` heading (`y`, not `inner.y`). Once the contract has looked at the value (a mismatched receipt for the wrong sum, say), the act is written out in full and tried like any other. What the list never does is show you the contract's own error text for this: "Internal error: amount is not in scope" was what it printed for the receipt case until 2026-09-19, and that was a bug in the list, not in your contract.
- **Each answer is a full re-run.** For every shape tried, the whole trace is run again from the start with that event appended. On a contract with many obligations in force, or a long trace, that is many runs; on the three corpus files `l4 lts` finishes in about the time `l4 check` takes — the listing adds a few hundredths of a second at most, and the wall clock is dominated by loading the file and any prelude it imports — but a large cast will be slower, in proportion to the number of obligations live at once.
- **It says nothing about _where_ in the contract you are, or about what happens _after_ the next step.** "Move things along" shows the position one event ahead, and no further. The shape of the whole contract is `l4 state-graph`'s job, and the picture that would put the position on that shape is designed, not built (the design is the same document, §1.1a; whether it is built depends on whether this list turns out to be enough).
- **Dates are on the contract clock**, a plain number that counts whatever unit the contract's `WITHIN`s count — days, in every example here. There are no calendar dates.
- **A due date is printed only when the contract confirmed it.** For an obligation that has not yet seen an event, the list works out the deadline itself and then checks its arithmetic by running the clock past it; only if the contract agrees (the deadline actually expires) is the date printed under "Owed now" and counted in "Next deadline". If the contract disagrees, the obligation reads "due within 7 from now" instead of "due by 9", and the "Next deadline" line names it as one whose deadline is not known here. A `WITHIN` that counts from an anchor rather than from now (`WITHIN 5 OF THE DEADLINE`) is dated the same way but worded as the rule wrote it — "due by 35 (WITHIN 5 OF THE DEADLINE)" — because "5 from now" would not be true of it. An obligation with no `WITHIN` at all reads "no deadline" and is not counted either way.
- **A window that has not opened yet is dated from its opening.** An obligation with an [`AFTER`](AFTER.md) — `PARTY Alice MUST deliver AFTER 5 WITHIN 10`, a window from 5 to 15 — lists as "due by 15 (13 from now; the window opens at 5)" once the contract has looked at an event, and before that, worded as the rule wrote it, "due by 15 (AFTER 5 WITHIN 10)": the bare `WITHIN` counts from the opening, so "10 from now" would be false of it. An act tried before the opening is passed over — "the window has not opened yet (it opens at 5; an act before then counts for nothing)" — and `--steps` shows the look, as it shows any other. What the list does not do is offer the act _at_ the opening: the acts it tries are dated now, and now is too early. An `AFTER` whose offset is a date rather than a number is not worked out here until the contract has looked at an event; before that the obligation is listed as one "whose deadline is not known here", as an unforced `BEFORE` date is — and once an event has been seen, the residual carries the window as numbers and the obligation is dated like any other.
- **An act is written out only when the list can.** "Owed now" prints the act as it would be done (`payment OF 100`) when every part of it is fixed by the rule; an act that leaves something to the party keeps that part by its own name, with everything around it filled in (`Pay OF (Tenant OF "Alice"), theLandlord, amount` — the tenant is known, the sum is the tenant's to choose); an act the list could read only part of is printed as far as it got (`Receipt OF (Landlord OF "Ms Ng"), (Tenant OF "Alice"), amount`). The "then:" lines under "move things along" always print the pattern, so the same obligation can appear under two spellings in one listing.

## Related pages

- **[Regulative rules](README.md)** — the keywords, and `#TRACE`
- **[EVERY](EVERY.md)** — groups, the barrier and the fork
- **[EVENT](EVENT.md)** — the events a trace is made of
- **[Using the l4 CLI](../../tutorials/getting-started/l4-cli.md)** — the other subcommands
