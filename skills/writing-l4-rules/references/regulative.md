# Regulative Rules Reference

Deep dive on L4's regulative machinery: obligations, permissions, prohibitions, deadlines, consequences, obligations that bind a whole group at once, and contract-trace simulation. This is L4's unique strength and the part most likely to trip a general-purpose large language model.

**Canonical reference:** <https://legalese.com/l4/reference/regulative.md>

---

## Contents

- [The five-keyword skeleton](#the-five-keyword-skeleton)
- [Deontic modals: MUST, MAY, SHANT, DO](#deontic-modals-must-may-shant-do)
- [HENCE and LEST — the success and failure paths](#hence-and-lest--the-success-and-failure-paths)
- [BREACH, FULFILLED, and BECAUSE](#breach-fulfilled-and-because)
- [PROVIDED and action patterns — reference and wildcard matching](#provided-and-action-patterns--reference-and-wildcard-matching)
- [WITHIN — deadlines](#within--deadlines)
- [Composition: RAND and ROR](#composition-rand-and-ror)
- [EVERY — one obligation per member of a group](#every--one-obligation-per-member-of-a-group)
  - [The group must be given as a list, after `IN`](#1-the-group-must-be-given-as-a-list-after-in)
  - [The join line is mandatory whenever there is a `HENCE` or a `LEST`](#2-the-join-line-is-mandatory-whenever-there-is-a-hence-or-a-lest)
  - [`t` already refers to the member — no `EXACTLY` needed](#3-t-already-refers-to-the-member--no-exactly-needed)
  - [Do not write the deprecated `WHO elem` roll](#do-not-write-the-deprecated-who-elem-roll)
- [Recursive obligations](#recursive-obligations)
- [#TRACE — simulating contract execution](#trace--simulating-contract-execution)
  - [What may go in the `WITH` block](#what-may-go-in-the-with-block)
- [Complete example](#complete-example)

---

## The five-keyword skeleton

```l4
PARTY   actor
MUST    action parameters      -- or MAY / SHANT / DO
WITHIN  deadline
HENCE   nextState              -- optional; consequence on success
LEST    penaltyState           -- optional; consequence on failure
```

Only `PARTY` + modal + action are required. `WITHIN`, `HENCE`, and `LEST` all have sensible defaults (see the tables below).

---

## Deontic modals: MUST, MAY, SHANT, DO

| Keyword | Meaning                   | Reference                                               |
| ------- | ------------------------- | ------------------------------------------------------- |
| `MUST`  | Obligation (required)     | <https://legalese.com/l4/reference/regulative/MUST.md>  |
| `MAY`   | Permission (allowed)      | <https://legalese.com/l4/reference/regulative/MAY.md>   |
| `SHANT` | Prohibition (forbidden)   | <https://legalese.com/l4/reference/regulative/SHANT.md> |
| `DO`    | Optionality / possibility |                                                         |

```l4
PARTY Alice MUST pay 100 WITHIN 30                      -- obligation
PARTY Bob   MAY  withdraw funds                         -- permission
PARTY Alice SHANT smoke WITHIN 30                       -- prohibition
```

`SHANT` is fully supported. If anything you have seen says "no MUST NOT in L4" it is out of date.

---

## HENCE and LEST — the success and failure paths

`HENCE` is the consequence on success; `LEST` is the consequence on failure. **What counts as "success" depends on the modal**, and this is the single most non-obvious thing about L4 regulative rules.

| Modal   | HENCE fires when                        | LEST fires when                        | HENCE default | LEST default |
| ------- | --------------------------------------- | -------------------------------------- | ------------- | ------------ |
| `DO`    | action is taken                         | deadline passes                        | _(required)_  | _(required)_ |
| `MUST`  | action is taken                         | deadline passes without action         | `FULFILLED`   | `BREACH`     |
| `MAY`   | action is taken                         | deadline passes (permission unused)    | `FULFILLED`   | `FULFILLED`  |
| `SHANT` | deadline passes (prohibition respected) | action is taken (prohibition violated) | `FULFILLED`   | `BREACH`     |

**`SHANT` flips the polarity**: for a prohibition, doing the action is the failure. This is why `SHANT … HENCE` fires when the deadline passes quietly — that is the good outcome.

`LEST` can chain another obligation for a reparation clause:

```l4
-- Pay-or-pay-more penalty clause
PARTY `The Borrower`
MUST  pay `outstanding amount`
WITHIN `due date`
HENCE FULFILLED
LEST (
    PARTY `The Borrower`
    MUST  pay `outstanding amount with 5% penalty`
    WITHIN `default deadline`
    -- no LEST: missing this deadline is a breach
)
```

Without a `LEST` clause on the inner obligation, missing that deadline is a terminal breach.

---

## BREACH, FULFILLED, and BECAUSE

Both are **keywords**, not just outcomes from the evaluator.

All four spellings parse:

```l4
HENCE FULFILLED
LEST  BREACH
LEST  BREACH BY Seller
LEST  BREACH BECAUSE "delivery deadline exceeded"
LEST  BREACH BY Seller BECAUSE "failed to deliver within 14 days"
```

**Write the last one.** `BECAUSE` attaches a reason to a breach and is reported verbatim in the trace output, under the `BY` line:

```
Result:
  DEONTIC BREACHED:
    BREACH
    BY Seller
    BECAUSE "the goods were not delivered within 3 days"
```

Breach reasons are the thing a legal reviewer or a downstream system actually reads, so every example in this file carries one. `SKILL.md` states the same rule under "Model obligations and deadlines".

Reference: <https://legalese.com/l4/reference/regulative/BECAUSE.md>

---

## PROVIDED and action patterns — reference and wildcard matching

### PROVIDED — guard condition

`PROVIDED` adds a boolean guard to an action. After an event matches the action pattern structurally, the guard is evaluated; if it returns `FALSE`, the match is rejected and the system tries the next event.

```l4
-- Conditional payment: only counts if >= 20
PARTY Bob
MUST payment price PROVIDED price AT LEAST 20
WITHIN 3

-- Guard on a transferred amount
PARTY borrower
MUST `Amount Transferred`
     PROVIDED `Amount Transferred` AT LEAST `Payment Due`
```

### Reference and wildcard names

A bare name in an action's argument position does one of two things, and the checker decides which
by looking the name up — you never have to say which you mean:

- **If it names something already in scope** — a `GIVEN`, a lambda parameter, a `WHERE`/`LET`
  local, a name an enclosing action already bound, a `CONSIDER` or `EVERY` variable, or a
  top-level, section-level, `ASSUME`d, or imported term — the pattern **refers** to that thing: the
  event must equal it.
- **If it names nothing in scope** (or only a field selector of the action's own record type) the
  pattern is a **wildcard**: a fresh name, bound to whatever the event supplies, matching anything.

```l4
-- Wildcard: matches any pay-shaped event, binding `amount` to whatever was paid
PARTY buyer MUST pay amount

-- Reference: price is a GIVEN, so this matches only an event paying exactly `price`
GIVEN price IS A NUMBER
PARTY Alice MUST pay price WITHIN 30

-- Literal: already an exact value, no keyword needed
PARTY Alice MUST pay 100 WITHIN 30
```

A name that refers to a top-level, section-level, `ASSUME`d, or imported term (as opposed to a
lexical local) also gets a notice, naming what it refers to and where it is defined — the one case a
reader cannot see just by looking at the rule: a name defined elsewhere in the file that turns what
used to be a wildcard into a reference. The notice asks for nothing; it is information, not a
diagnostic to fix.

### `EXACTLY` — deprecated

`EXACTLY e` still parses and still means what it always meant. But it no longer changes anything a
bare name would not already do on its own: the checker resolves a bare name to a reference
automatically wherever `EXACTLY` used to be needed. Every remaining use warns, with the
meaning-preserving replacement:

| written today    | replacement | why                                       |
| ---------------- | ----------- | ----------------------------------------- |
| `EXACTLY name`   | `name`      | the name already resolves to a reference  |
| `EXACTLY (expr)` | `(expr)`    | keep the parentheses around an expression |

Write plain names and parenthesised expressions in new rules; do not write new `EXACTLY`.

One case gets no suggested replacement: `EXACTLY someName` where `someName` names nothing in scope
at all. Dropping the keyword there would turn a compile error into a wildcard matching anything —
the exact defect the reference rule exists to prevent — so the warning says the keyword is retiring
without offering to remove it until the name itself is fixed.

---

## WITHIN — deadlines

`WITHIN` takes a bare number. The unit is a convention of the file, not part of
the language: `WITHIN 30` means thirty of whatever the file's clock counts, so
record the unit once in a comment or in the name of the constant.

```l4
PARTY Alice  MUST pay 100 WITHIN 30          -- days, by this file's convention
```

`WITHIN d OF anchor` anchors the deadline (built 2026-09-15): `OF THE JOIN`,
`OF THE DEADLINE` or `OF THE ARMING` name the enclosing obligation's completion,
deadline or entry, and `OF e` an instant — a `NUMBER` on the trace's clock or a
`DATE`; the deadline is then the anchor plus `d`, absolute. Everywhere inside an
unbracketed duration `OF` is the anchor, never a call — also inside an `IF`
branch, an operand or a `WHERE` there — so an applied duration is bracketed,
`WITHIN (f OF x) OF THE JOIN`, or juxtaposed, `WITHIN f x OF THE JOIN`.

`WITHIN 5 days` does not check unless `days` is defined; one line,
`GIVEN n IS A NUMBER GIVETH A NUMBER DECIDE n days IS n`, makes it check. HOW it
fails depends on what is in scope (measured 2026-09-15): with no import and no
other mixfix definition in the file, `days` is read as a function applied to
`5` and the checker reports `could not find a definition for the identifier`;
with any mixfix operator in scope (`IMPORT prelude` is enough) the parser only
accepts operator words it knows and stops at `days` with `unexpected days`. The
same is true of ``WITHIN 5 days OF `order confirmation` ``, which since
2026-09-15 parses — the `OF` is the anchor — and then checks only if both
`days` and `` `order confirmation` `` are defined. See
[source-patterns/04-dates-and-periods.md](source-patterns/04-dates-and-periods.md#e4-3),
entry 4.3, for the measured forms.

**There is no `BEFORE` for an absolute deadline in this release.** `MUST pay BEFORE 30` does not
read as a deadline at all — the parser takes it as applying the action to two arguments, and the
check fails with `You are giving 2 inputs to pay … but it is not a function, so it takes none`
(probe `g14-before-deadline.l4`, exit 1). Use `WITHIN`: relative as `WITHIN d`, absolute as
`WITHIN d OF instant` — `WITHIN 0 OF (YMD 2026 6 30)` is "by 30 June 2026".

---

## Composition: RAND and ROR

`RAND` and `ROR` compose obligations in parallel.

- **`RAND`** — parallel AND. All components must be fulfilled; if any side breaches, the compound breaches. When both sides are lost the breach names both sides' failures, left first, one line each with that side's own action-and-deadline or `BECAUSE` (`BY seller BECAUSE "…"` / `BY buyer BECAUSE "…"`).
- **`ROR`** — parallel OR. Fulfilling any one side fulfills the compound; it breaches only when every side is lost, and then names every side's failure the same way.
- **Which side dates a compound breach.** Only a missed deadline carries a time (the stamp of the event that revealed it); a declared `LEST BREACH` carries none. When both sides carry a time, the breach is dated at the earlier stamp for `RAND` and the later for `ROR`. When **either** side is a declared `LEST BREACH`, the pair counts as simultaneous and the date falls to the left side for `RAND` and the right for `ROR` — regardless of which side was actually lost first — which may mean no date at all. Only the date is affected; every side's own reason or deadline is printed either way.
- **Precedence:** `RAND` binds tighter than `ROR`, so `A ROR B RAND C` means `A ROR (B RAND C)`.

```l4
-- Both parties must fulfill their halves
(PARTY seller MUST deliver WITHIN 14 HENCE FULFILLED
  LEST BREACH BY seller BECAUSE "goods not delivered within 14 days")
RAND
(PARTY buyer  MUST pay     WITHIN 30 HENCE FULFILLED
  LEST BREACH BY buyer  BECAUSE "price not paid within 30 days")

-- Seller has two ways to satisfy the obligation
(PARTY seller MUST ship             WITHIN 14 HENCE FULFILLED
  LEST BREACH BY seller BECAUSE "not shipped within 14 days")
ROR
(PARTY seller MUST `arrange pickup` WITHIN 7  HENCE FULFILLED
  LEST BREACH BY seller BECAUSE "no pickup arranged within 7 days")
```

`AND` and `OR` at the top level of a regulative rule are also accepted as composition forms in many programs; the authoritative semantics live at <https://legalese.com/l4/reference/regulative.md>.

---

## EVERY — one obligation per member of a group

`PARTY` names one actor. `EVERY` binds the same obligation to **every member of a group at once**, and — this is the part `PARTY` cannot do at all — gives you one place to say what happens when they have acted.

```l4
EVERY Tenant t IN tenants          -- one obligation per tenant, all live at once
    MUST   Sign t
    WITHIN 14
    ONCE   ALL HAVE                -- the JOIN LINE: fires once, at the last signature
    HENCE  FULFILLED
    LEST   BREACH
```

Read it aloud and it says what it does: _every tenant t in tenants must sign, within fourteen days; once all of them have, it is fulfilled, and otherwise it is breached._

Everything after the first line is the same as under `PARTY` — same modals, same `WITHIN`, `HENCE`, `LEST`, `PROVIDED`. **Three things are new, and all three are places a general-purpose model reliably gets wrong.**

### 1. The group must be given as a list, after `IN`

A party type is normally open: `Tenant HAS name IS A STRING` has one constructor and infinitely many values, so "every tenant" is not something the machine can count out. You have to hand it the list. That list is called the **roll**.

**A rule with no roll parses and type-checks and then refuses at run time.** Verified against the compiler on 2026-09-09; the message is:

> EVERY has nothing to draw its cast from. Running a quantified obligation needs a list of the parties it ranges over, because a party type is normally open… Name the list with IN, as `EVERY Tenant t IN tenants MUST ...`, with `tenants` a LIST of the party type.

So `l4 check` passing is **not** evidence that a quantified rule will run. Give it an `IN`.

The roll may be any expression of type `LIST` of the party type — a literal, a name, a call. Three things about it are worth knowing before you debug them:

- **It is read once**, when the rule meets its event stream, and the group is fixed from then on. Somebody added to the list later does not join a group already running.
- **It cannot mention the member.** `EVERY Tenant t IN (peersOf t)` asks the list to know its own answer; the member is not in scope there. To narrow by something about each member, use `WHO`, where it is. One sharp edge: what the checker rejects is a name it cannot find, so if the file happens to define something else called `t` at the top level, the `t` inside `IN` quietly means **that** one and nothing is reported. Give the member a name nothing else in the file uses.
- **A name listed twice is counted twice.** Under a barrier that is harmless; under a fork the continuation fires once per copy, so one payment earns two receipts.

### 2. The join line is mandatory whenever there is a `HENCE` or a `LEST`

There are two ways a group can trigger a follow-on, they mean different things, and L4 refuses to guess:

| join line       | shape       | fires                                |
| --------------- | ----------- | ------------------------------------ |
| `ONCE ALL HAVE` | **barrier** | once, when the last member has acted |
| `UPON EACH`     | **fork**    | once per member, as each one acts    |

Use the barrier when the follow-on is about the group (`ONCE ALL HAVE HENCE` `` `the tenancy begins` ``). Use the fork when it is about the individual (`UPON EACH HENCE PARTY landlord MUST` issue **that** tenant a receipt). Under a fork the member is in scope in the continuation, which is what makes "a receipt to whoever paid" expressible.

Omitting it is a check-time error, and the message names both spellings:

> An EVERY with a HENCE or LEST needs a join line saying when it fires. Write one of `ONCE ALL HAVE` … `UPON EACH` … There is no default: the two readings differ, and guessing one would silently change the rule.

The line goes **between the act's `WITHIN` and the `HENCE`**, indented past the `EVERY`. A rule with no `HENCE` and no `LEST` needs no join line.

**Clause order silently decides which deadline you wrote.** A `WITHIN` _before_ the join line bounds each member's act; the same `WITHIN` _after_ it bounds the whole group. Both parse, both check, and the formatter prints either back unchanged, so nothing will tell you which one you got. Write the act's `WITHIN` first, as every example here does.

### 3. `t` already refers to the member — no `EXACTLY` needed

`t` is the quantifier's own variable, in scope for the action exactly as a `GIVEN` would be, so
`MUST Sign t` means what it reads: the member signs. This used to need `MUST Sign (EXACTLY t)` —
under the older rule every bare name in an action was a **fresh** name regardless of what it
matched elsewhere, so plain `t` silently introduced a second `t` matching any signer at all, and the
checker refused the rule:

> The action of this EVERY binds a new name `t` … which is spelled like the quantifier's own variable `t`. An action is a pattern, so this would be a fresh name matching anyone, not a reference to the member. To mean the member, write `EXACTLY t` in that position.

That check (`QuantifierVariableRebound`) is retired: a name already in scope now refers to it rather
than shadowing it, at every depth of nesting, so the old advice to write `EXACTLY` for an _outer_
quantifier's variable in a nested rule is also no longer needed — it too now just refers. `EXACTLY
t` still parses and still means the same reference, but it is the deprecated spelling; write plain
`t`.

Other arguments still work the same way: `MUST Pay t theLandlord amount` pins payer and payee by
reference (`t` to the member, `theLandlord` to whatever it names in scope) and leaves `amount` a
wildcard, bound to whatever was paid and then in scope in `PROVIDED`, `HENCE` and `LEST`.

### `WHO` narrows the group

Three things filter, in this order: the roll gives the starting list, the kind word after `EVERY` drops anyone not of that kind, and `WHO` drops anyone it is false for.

```l4
EVERY Tenant t IN tenants
    WHO NOT (t EQUALS (Tenant OF "Carol"))
```

`WHO` takes any Boolean expression in which the member is free — a field comparison, a prelude call, a named helper applied to it.

### Do not write the deprecated `WHO elem` roll

Before `IN` existed the roll had to be smuggled into the `WHO` condition:

```l4
EVERY Tenant t
    WHO elem t tenants          -- DEPRECATED (2026-09-08). Do not write this.
```

**It still runs and nothing warns you**, which is exactly why it needs to be in this file: a model trained on older L4 will produce it, and neither the compiler nor the test suite will object. Recognise it, and write `IN` instead. The rewrite is mechanical:

| old                             | new                     |
| ------------------------------- | ----------------------- |
| `WHO elem t tenants`            | `IN tenants`            |
| `WHO elem t tenants AND <rest>` | `IN tenants WHO <rest>` |

An `elem` condition **beside** an `IN` roll is an ordinary narrowing condition and is perfectly fine — only an `elem` standing in for a missing roll is deprecated.

### What is coarser than it looks

Say these plainly to a user rather than letting them discover them:

- **A barrier's own `LEST BREACH` names NOBODY.** A barrier's `LEST` belongs to the join, not to any member, so it may not name `t` — the run refuses `LEST BREACH BY t` — and a bare `LEST BREACH` yields a bare `BREACH` with no party. A constant works, one party or a list (`LEST BREACH BY LIST theLandlord, theAgent BECAUSE "…"`), but is a party you chose, not the one who failed. Leave the `LEST` off and the breach names **every** member who failed, in roll order, each with their own deadline (built 2026-09-15); with a `LEST` that has to stay, who is outstanding shows up in the **residual**, not the breach. Use the fork if the failure has to name the member.
- **The count and measure joins are not built.** `ONCE SOME 2 OF … HAVE` and `ONCE sum OF amount AT LEAST rent` do not parse. Only `ONCE ALL HAVE` and `UPON EACH` do.
- **`NO Tenant t MAY …`** is designed but not built; write the `SHANT` form.
- **A residual barrier loses its join line**, so feeding a residual more events runs the members and not the join. Run the whole stream at once.
- **The BPMN export draws a barrier and a fork identically**, and its fidelity report does not mention the join at all — so the two rules produce byte-identical output. Read the `.l4`, never the diagram, to tell which join a rule has. The reference page reports that the WASM export refuses an `EVERY` rule outright rather than compiling it wrongly; that one is not re-verified here.

Full treatment, including the state-graph behaviour and the measured sharp edges: <https://legalese.com/l4/reference/regulative/EVERY.md>.

---

## Recursive obligations

For recurring payments (loans, subscriptions, installments), define a function that emits the next period's obligation:

```l4
GIVEN remainingBalance IS A NUMBER
`monthly payments` remainingBalance MEANS
    IF remainingBalance GREATER THAN 0
    THEN PARTY `The Borrower`
         MUST pay `monthly installment`
         WITHIN `next due date`
         HENCE `monthly payments` (remainingBalance MINUS `monthly installment`)
         LEST  `monthly payments` (remainingBalance PLUS `late penalty`)
    ELSE FULFILLED
```

The `HENCE` branch reduces the balance; the `LEST` branch increases it with a penalty and re-emits the obligation. The recursion base is `FULFILLED`.

---

## #TRACE — simulating contract execution

`#TRACE` runs a contract against a sequence of timestamped events and reports either `FULFILLED`, a `BREACH`, or a **residual obligation** (what's still owed).

### Syntax

```l4
#TRACE contractName AT startTime WITH
    PARTY partyName DOES action AT eventTime
    PARTY partyName DOES action AT eventTime
    ...
```

Timestamps are numbers on a shared timeline. For date-based contracts, the canonical docs show a `Day (…)` form; use whatever form your rule uses for `WITHIN`.

### What may go in the `WITH` block

One event per line, in the order they happen. There are exactly **two** kinds and they mix freely
(probe `g11-trace-events.l4`, exit 0, no errors, six traces):

```l4
-- An act: PARTY … DOES … AT n
#TRACE `the payment duty` AT 0 WITH
    PARTY `the Company` DOES `pay the invoice` AT 12

-- A clock advance with no act: `WAIT UNTIL` n
#TRACE `the payment duty` AT 0 WITH
    (`WAIT UNTIL` 31)

-- Both kinds in one block, in authored order — the only way to show a LEST
-- chain expiring on its first rung and then discharging on its second.
#TRACE `the payment duty` AT 0 WITH
    (`WAIT UNTIL` 45)
    PARTY `the Company` DOES `pay the unpaid amount with interest` AT 50
```

- **`` `WAIT UNTIL` `` is built into the compiler, not a library name.** The probe above has no
  `IMPORT` line at all and every trace runs. The parentheses are the house form and what the corpus
  writes; a bare `` `WAIT UNTIL` 31 `` on its own line also parses and gives the same result
  (probes `g11b`, `g11c`).
- **The deadline is inclusive.** An act `AT 30` against `WITHIN 30` is timely; it takes
  ``(`WAIT UNTIL` 31)`` to expire it.
- **A rule that takes arguments is applied before `AT`, and more than one argument is fine.**
  ``#TRACE `cl 6 -- confidentiality` `the Contractor` (`disclose` "the world") AT 0 WITH`` runs and
  produces the breach. Parenthesise a constructed argument.
- **`#TRACE` is the one directive whose body wraps onto following lines.** Everything else is a
  one-line construct, `#ASSERT REFUSED … BECAUSE` excepted.

Entry 5.11 of the phrasebook,
[source-patterns/05-duties-powers-consequences.md](source-patterns/05-duties-powers-consequences.md#e5-11),
works the same ground from the drafting side.

### Happy-path example

```l4
#TRACE paymentObligation AT 0 WITH
    PARTY Alice DOES pay 100 AT 15
-- Result: FULFILLED
```

### Residual-obligation example

```l4
#TRACE paymentObligation AT 0 WITH
    -- no events within deadline
-- Result: the LEST branch — either BREACH, or the reparation obligation
-- if the rule has a LEST clause
```

A `WITH` block with no events is legal and is the way to ask "what is still
standing if nothing happens": the result is the obligation printed back, not a
breach, because with no events the clock does not advance. Dropping the `WITH`
altogether (`#TRACE c AT 0` and nothing after it) is a parse error.

The residual is the most useful output from a trace: it is the contract in its current state, as a machine-readable value, showing exactly what is still owed by whom.

Reference: <https://legalese.com/l4/reference/regulative.md>

---

## Complete example

From the canonical README — a two-party sale with delivery and payment:

```l4
DECLARE Person IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF
    delivery
    payment HAS amount IS A NUMBER

saleContract MEANS
    PARTY Seller
    MUST delivery
    WITHIN 3
    HENCE (
        PARTY Buyer
        MUST payment 100
        WITHIN 7
        LEST BREACH BY Buyer BECAUSE "the price was not paid within 7 days of delivery"
    )
    LEST BREACH BY Seller BECAUSE "the goods were not delivered within 3 days"

#TRACE saleContract AT 0 WITH
    PARTY Seller DOES delivery AT 2
    PARTY Buyer  DOES payment 100 AT 5
-- Result: FULFILLED

#TRACE saleContract AT 0 WITH
    (`WAIT UNTIL` 4)
-- Result: DEONTIC BREACHED: BREACH BY Seller
--         BECAUSE "the goods were not delivered within 3 days"
```

---

## See also

- <https://legalese.com/l4/reference/regulative.md> — full keyword reference
- <https://legalese.com/l4/reference/regulative/MUST.md>
- <https://legalese.com/l4/reference/regulative/MAY.md>
- <https://legalese.com/l4/reference/regulative/SHANT.md>
- <https://legalese.com/l4/reference/regulative/PARTY.md>
- <https://legalese.com/l4/reference/regulative/BECAUSE.md>
- <https://legalese.com/l4/reference/regulative/DEONTIC.md>
- <https://legalese.com/l4/concepts/legal-modeling/regulative-rules.md> — conceptual overview
- <https://legalese.com/l4/courses/foundation/module-5-regulative.md> — foundation course module
