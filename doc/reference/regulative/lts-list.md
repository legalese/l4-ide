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
    - Buyer MUST payment (EXACTLY 100) — due by 9 (7 from now)

  What would discharge it (the contract ends fulfilled):
    - Buyer does payment OF 100 now (at 2) → fulfilled

  What would move things along (neither ends nor breaches it):
    - nothing happens by 9 (the clock reaches 10) → then:
          · Buyer MUST payment (EXACTLY 120) — due by 24 (14 from now)

  Next deadline: 9 (Buyer: payment (EXACTLY 100))
```

Reading it from the top:

- **The heading** names the contract, counts the events, and says where the **contract clock** stands — the time of the last event, here day 2. Every "due by" below is on that clock. The events themselves are listed under it, as written in the file.
- **Standing** is the one-word answer: _in progress_, _FULFILLED_, or _BREACHED_ with who and why.
- **Owed now** is the list of obligations in force. There is one: the buyer must pay exactly 100, due by day 9 — that is 7 from now, because the seven days started when the seller delivered on day 2.
- **What would discharge it** lists the acts that, done now, end the contract fulfilled. Paying 100 does.
- **What would move things along** lists what changes the position without ending it. Here, if nothing happens by day 9, the buyer is not yet in breach: the late-price clause takes over, and the buyer owes 120 by day 24. The list prints what would be owed after that ("then:").
- There is no **What would put someone in breach** section, because in this position nothing does — the late-price clause catches the missed deadline. In the tenancy example below, whose rule ends in `LEST BREACH`, the deadline passing does breach, and the section appears.
- **Next deadline** is the soonest date anything is due, and whose it is.

## The sections, and when each appears

A section is printed only when it has something in it. The full set:

| Section                               | What it lists                                                                                                                                                                    |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Owed now**                          | every obligation, permission and prohibition in force: who, `MUST`/`MAY`/`MUST NOT`, the act, and the due date. Under an `EVERY`, which group the member belongs to (see below). |
| **What would discharge it**           | an act that, done now, ends the contract fulfilled                                                                                                                               |
| **What would put someone in breach**  | an act, or a deadline passing, that ends the contract breached — with who is blamed and what they missed                                                                         |
| **What would move things along**      | an act, or a deadline passing, that leads to a new position — and what would be owed there                                                                                       |
| **What the contract would pass over** | an act the contract does not take: it is not the awaited act, not this party's to do, or its `PROVIDED` condition does not hold. Nothing changes.                                |
| **What could not be tried**           | a shape the list can name but cannot run — see [Limits](#limits)                                                                                                                 |
| **Next deadline**                     | the soonest due date among everything owed, and whose it is                                                                                                                      |

The things the list tries are exactly the obligations' own acts (each one, done now by the party who owes it) and, for each distinct deadline, the clock running just past it with nothing happening. That is what "what could happen" means here; it is not every conceivable event.

## Groups: the barrier and the fork

When an obligation is written with [EVERY](EVERY.md), every member of the group owes it at once, and the list says how they relate. `jl4/examples/bpmn/tenancy.l4` holds the reference pair — three tenants who must each sign (a **barrier**: the landlord's delivery waits for all of them), and three who must each pay (a **fork**: each payment earns its own receipt). The file has no `#TRACE`, so the list is asked for each rule at its outset with `--contract`:

```bash
l4 lts tenancy.l4 --contract "the tenancy" --contract receipts
```

For the barrier, the group is announced on each member's line, and one extra line says what the group is waiting for:

```
  Owed now:
    - Tenant OF "Alice" MUST Sign (EXACTLY t) — due by 14 (14 from now) (one of 3 who must all act before the next step)
    - Tenant OF "Bob" MUST Sign (EXACTLY t) — due by 14 (14 from now) (one of 3 who must all act before the next step)
    - Tenant OF "Carol" MUST Sign (EXACTLY t) — due by 14 (14 from now) (one of 3 who must all act before the next step)
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

For the fork there is no "held back" line, because nothing waits: each member's line says so, and each member's act would start that member's own next step.

```
  Owed now:
    - Tenant OF "Alice" MUST Pay (EXACTLY t) (EXACTLY theLandlord) amount — due by 7 (7 from now) (one of 3, each with a next step of their own)
```

The full output for both is the golden `jl4/examples/lts/expected/tenancy.txt`.

## `--steps`: what the contract did with each event

The list is about **now**. Add `--steps` and it also prints the history: one line per look the contract took at an event, contract clock first, in the order it happened. From the first trace of [every-run-example.l4](every-run-example.l4), where three tenants sign on days 1, 2 and 9 and the landlord delivers on day 13:

```
  Steps, in order:
    at 1: Tenant OF … does Sign OF … at 1; Tenant OF … MUST (member 1 of 3) — done; on to what follows (1 of 3 have acted; the shared next step waits for the rest)
    at 1: Tenant OF … does Sign OF … at 1; Tenant OF … MUST (member 2 of 3) — not this party's event; passed over
    at 2: Tenant OF … does Sign OF … at 2; Tenant OF … MUST (member 2 of 3) — done; on to what follows (2 of 3 have acted; the shared next step waits for the rest)
    ...
    at 9: Tenant OF … does Sign OF … at 9; Tenant OF … MUST (member 3 of 3) — done; on to what follows (3 of 3 have acted; the shared next step waits for the rest)
    at 9: (party not yet known) MUST — everyone has acted; the shared next step begins
    at 13: Landlord OF … does Deliver OF … at 13; Landlord OF … MUST — done; on to what follows
```

Each line reads: the clock; the event looked at; whose obligation looked at it; what it decided. The same event appears once per obligation that looked at it — Alice's signature on day 1 is "done" for Alice and "passed over" for Bob and Carol — so the count of lines is not the count of events.

Two things about this history are worth knowing:

- A party or an act shown as `Tenant OF …` is one the contract had not fully looked at when the step was recorded: the log writes down only what the contract had in hand at that moment, and does not go and fetch the rest. The **member number** (`member 2 of 3`) is what tells the members apart; the events are listed in full under the heading.
- `at —` marks a step with no clock: a look before any event has arrived, or the moment two parallel parts of a contract (`RAND`/`ROR`) are combined.

## `--json`

`--json` prints the same answers as JSON, one object per trace, for a program to read. The keys are the section names: `standing`, `owed`, `discharging`, `breaching`, `advancing`, `passedOver`, `untried`, `nextDeadline`, plus `contract`, `line`, `events`, `clock`, and, with `--steps`, `steps`. Times are numbers on the contract clock. The golden `jl4/examples/lts/expected/contracts.json` is a complete specimen.

## `--contract NAME`

A file with no `#TRACE` has nothing to list. `--contract NAME` lists the rule called `NAME` at its outset — before anything has happened — exactly as a `#TRACE NAME AT 0 WITH` with no events would, without editing the file. Write the name without its backticks (`--contract "the tenancy"`), repeat the option for several rules, and note that only a rule that takes no inputs can be listed this way. An unknown name is an error, not an empty list.

## Limits

State plainly, because a reader will find them anyway:

- **The list tries the obligations' own shapes, not every event there could be.** What it puts under "discharge", "breach" and "move things along" is exact for the acts it tried — each verdict is the contract's own — but the shapes come from reading the position, before the contract has been asked whether it would take them. So a shape can be listed and then turn out to be passed over (that is what the **pass over** section is for), and an event nobody's obligation names — a payment of the wrong amount, an act by a third party — is not listed at all, although it would still move the clock. In the language of the design document this is the enabled set as an **over-approximation** (`specs/todo/lexipedia-superset/LTS-VISUALISER.md` §1.1b, loss G9): "no listed act breaches" is sound; "nothing else could" is not something the list says.
- **Some shapes cannot be tried.** An act whose amount the contract leaves open (`MUST payment price PROVIDED price >= 20` — the buyer chooses the price) is listed under **What could not be tried** with the reason, because the list has no basis for picking a value. It is listed rather than dropped: a list that omitted it would say "nothing else can happen", which is false. The reason as printed still uses the compiler's word for this — "the action binds `price`" — which means: the rule leaves `price` to be filled in by the event.
- **Each answer is a full re-run.** For every shape tried, the whole trace is run again from the start with that event appended. On a contract with many obligations in force, or a long trace, that is many runs; the three corpus files list in under a third of a second each, but a large cast will be slower, in proportion to the number of obligations live at once.
- **It says nothing about _where_ in the contract you are, or about what happens _after_ the next step.** "Move things along" shows the position one event ahead, and no further. The shape of the whole contract is `l4 state-graph`'s job, and the picture that would put the position on that shape is designed, not built (the design is the same document, §1.1a; whether it is built depends on whether this list turns out to be enough).
- **Dates are on the contract clock**, a plain number that counts whatever unit the contract's `WITHIN`s count — days, in every example here. There are no calendar dates.

## Related pages

- **[Regulative rules](README.md)** — the keywords, and `#TRACE`
- **[EVERY](EVERY.md)** — groups, the barrier and the fork
- **[EVENT](EVENT.md)** — the events a trace is made of
- **[Using the l4 CLI](../../tutorials/getting-started/l4-cli.md)** — the other subcommands
