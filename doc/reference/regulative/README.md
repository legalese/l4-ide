# Regulative Rule Keywords

Regulative keywords express legal obligations, permissions, prohibitions, and their consequences. They form the core of L4's contract and regulation modeling.

> **See also:** [Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md) — how L4 decides _who may perform which action_ (the performer/agreement rule, duplex actions, parameterised actions applied by a rule, and higher-order procurement), with worked ✅/❌ examples.

## Overview

### Deontic Modalities

| Keyword           | Meaning                    |
| ----------------- | -------------------------- |
| [MUST](MUST.md)   | Obligation (required)      |
| [MAY](MAY.md)     | Permission (allowed)       |
| [SHANT](SHANT.md) | Prohibition (forbidden)    |
| MUST NOT          | Synonym for SHANT          |
| DO                | Bare form; behaves as MUST |

`DO` is the bare form, with no modal word. Measured on the current release, it behaves exactly as `MUST` does: the same defaults when `HENCE` or `LEST` is omitted (`FULFILLED` and `BREACH`), and the same outcomes when the action is taken and when the deadline passes.

**Types:** **[DEONTIC](DEONTIC.md)** - the regulative rule type; **[EVENT](EVENT.md)** - the event type consumed by traces

### Rule Structure

| Keyword               | Purpose                                                                                                        |
| --------------------- | -------------------------------------------------------------------------------------------------------------- |
| [PARTY](PARTY.md)     | Who has the obligation/permission                                                                              |
| [EVERY](EVERY.md)     | Every member of a group has it                                                                                 |
| [AFTER](AFTER.md)     | When the window opens (a duration, or a date)                                                                  |
| WITHIN                | Temporal deadline (relative, or absolute with `OF`)                                                            |
| BEFORE                | Absolute deadline: the window closes on a date                                                                 |
| HENCE                 | Consequence on fulfillment                                                                                     |
| LEST                  | Consequence on breach                                                                                          |
| PROVIDED              | Guard condition on action                                                                                      |
| EXACTLY (deprecated)  | See [below](#action-patterns-reference-or-wildcard) — a name in an action already refers to the thing it names |
| BREACH                | Terminal violation state                                                                                       |
| [BECAUSE](BECAUSE.md) | Reason for breach                                                                                              |
| FULFILLED             | Terminal success state                                                                                         |

### Parallel Obligation Combinators

| Keyword | Purpose                               |
| ------- | ------------------------------------- |
| RAND    | Parallel AND -- all must be fulfilled |
| ROR     | Parallel OR -- any one sufficient     |

## Basic Rule Structure

```l4
PARTY partyName
MUST/MAY/SHANT/DO action
[AFTER opening]
[WITHIN deadline | BEFORE date]
```

### Example

```l4
DECLARE Person IS ONE OF Alice, Bob
DECLARE Action IS ONE OF pay HAS amount IS A NUMBER

paymentObligation MEANS
  PARTY Alice
  MUST pay 100
  WITHIN 30
```

## WITHIN (Temporal Deadline)

Specifies a time duration within which an action must/may be performed: the window's **closing edge**. The window's **opening edge**, `AFTER`, has [its own page](AFTER.md); the closing edge's absolute form, `BEFORE date`, is [below](#before-absolute-deadline).

### Syntax

```l4
PARTY ...
MUST action
[AFTER opening [OF anchor]]
WITHIN duration [OF anchor]
```

The duration is a `NUMBER` of clock units — the same units the trace's timestamps use (days, if the trace is stamped in days). Written alone, it counts from where the language puts it: an obligation at the top level counts from when it was entered; an obligation under a `HENCE` counts from the moment the previous obligation was completed; an obligation under a `LEST` counts from the moment the previous obligation _failed_ — its missed deadline for a `MUST`, `DO` or `MAY`, the forbidden act itself for a `SHANT` (the [LEST](#lest-breach-consequence) section has the rule in full).

The duration can be anchored with `OF`, and then the deadline is **absolute**: the anchor's instant plus the duration, whatever the clock read when the obligation was entered. The anchor is one of:

| Anchor            | Names                                                                                           |
| ----------------- | ----------------------------------------------------------------------------------------------- |
| `OF THE JOIN`     | the instant the enclosing obligation's `HENCE` fired (under `HENCE` this is the default, named) |
| `OF THE DEADLINE` | the enclosing obligation's deadline (its `WITHIN`)                                              |
| `OF THE ARMING`   | the instant the enclosing obligation was entered — under a `LEST`, the failure it repairs       |
| `OF expression`   | an instant: a `NUMBER` on the trace's clock, or a `DATE`                                        |

"The enclosing obligation" is the one whose `HENCE` or `LEST` this obligation is the continuation of — the one it is attached to when it runs. Usually that is the obligation it is written under; but a continuation can also arrive as a value (a rule with `GIVEN k IS A DEONTIC …` that ends `HENCE k`, or a `WHERE` local), and then the anchors name the obligation it is handed to, not the one it was written under — also when the value is one operand of a `RAND` or `ROR` there. It is the _nearest_ enclosing obligation: two levels down, `THE ARMING` is the middle obligation's arming, not the outermost rule's, so "within 10 days of this agreement" (below) works from one level down, where the phrase is written.

An obligation is _entered_ at the instant its plain `WITHIN` counts from: at the top level, when the trace begins; under a `HENCE`, at the act; under a `LEST`, at the failure — so `THE ARMING` read from inside a reparation's own `HENCE` or `LEST` is the missed deadline (or the forbidden act), not the later event that revealed it (`jl4/examples/ok/every/run-lest.l4` §10).

For a `MUST`, `DO` or `MAY`, the join is the act that completed it. For a prohibition (`SHANT`) that was kept, the `HENCE` fires when the machine _learns_ it was kept — the first event after its deadline, not the deadline itself — and `THE JOIN` is that instant, the same one an unanchored `WITHIN` counts from. To count from the day a prohibition was discharged, anchor to `THE DEADLINE`.

`THE` is a keyword; `JOIN`, `DEADLINE` and `ARMING` are matched by spelling in this one position and are not reserved, so a program may still name a value `DEADLINE`.

Inside the duration, `OF` is always the anchor — everywhere in it, not only at the front — so `WITHIN f OF x` means `f` anchored at `x`, and so does an `OF` inside an `IF` branch, an operator's operand or a `WHERE` in the duration. To apply a function there, bracket the call (`WITHIN (f OF x) OF THE JOIN`) or juxtapose its arguments (`WITHIN f x OF THE JOIN`); the checker's message says so when the duration turns out to be a function.

Beside an `AFTER`, a bare `WITHIN` counts from the instant the window **opened**: `AFTER 3 WITHIN 30` is the window `[a+3, a+33]`, the cooling-off sentence. To measure both edges from one anchor — _not less than 3 nor more than 30 days after delivery_, `[a+3, a+30]` — name the anchor on the closing edge: `AFTER 3 WITHIN 30 OF THE JOIN`. The [AFTER](AFTER.md) page has the two readings and what an act before the window opens does. A `WITHIN` takes a duration, never a date: `WITHIN (YMD 2026 6 30)` is a check error that names `BEFORE`.

### Examples

**Example file:** [within-example.l4](within-example.l4) — these rules, each with a trace showing the deadline its anchor produces.

```l4
DECLARE Person IS ONE OF Buyer, Seller
DECLARE Action IS ONE OF pay HAS amount IS A NUMBER
                         deliver
closingDate MEANS 20

-- Simple deadline: 30 units from when the obligation is entered
GIVETH A DEONTIC Person Action
simple MEANS PARTY Buyer MUST pay 100 WITHIN 30

-- The cure period runs from when payment fell due, not from the day the
-- buyer finally paid
GIVETH A DEONTIC Person Action
cure MEANS
  PARTY Buyer MUST pay 100 WITHIN 30
  HENCE (PARTY Seller MUST deliver WITHIN 5 OF THE DEADLINE)
  LEST  BREACH

-- "Within 10 days of this agreement": counts from when the outer obligation
-- was entered, however long the buyer took to pay. (One level down only:
-- an obligation nested a level deeper would count from the seller's
-- arming, the nearest enclosing obligation.)
GIVETH A DEONTIC Person Action
`of this agreement` MEANS
  PARTY Buyer MUST pay 100 WITHIN 30
  HENCE (PARTY Seller MUST deliver WITHIN 10 OF THE ARMING)
  LEST  BREACH

-- An absolute deadline on the trace's own clock: due at 20 + 5 = 25
GIVETH A DEONTIC Person Action
absolute MEANS PARTY Seller MUST deliver WITHIN 5 OF closingDate
```

A unit word is ordinary L4, not syntax: `WITHIN 5 days OF THE DEADLINE` checks once `days` is defined (`GIVEN n IS A NUMBER GIVETH A NUMBER DECIDE n days IS n`). Until it is, the file fails — how depends on what else is in scope. In a file with no imports and no other mixfix definition, like the one above, `5 days` parses as an application and the checker reports _could not find a definition for the identifier `days`_; once any mixfix operator is in scope (after `IMPORT prelude`, say, or one `DECIDE a plus b IS …`), the parser only accepts operator words it knows, and stops at `days` with _unexpected days_. Either way the fix is the one-line definition.

An anchored deadline may already be in the past when the obligation is entered — `WITHIN 5 OF closingDate` on a contract that begins after `closingDate + 5`. That is not an error: the first event reveals the expiry, exactly as if the deadline had been missed by waiting. Its `LEST` then counts from that deadline like any other (see [When the next clock starts](#lest-breach-consequence)), which can put the reparation's own deadline before the obligation it repairs was ever entered: a `WITHIN 5 OF 0` entered at 20 with `LEST … WITHIN 10` is due at 15, and the first event after 20 reveals both misses at once. That is the rule taken literally; whether the reparation's clock should instead start no earlier than the failed obligation's entry is an open question, recorded in the design spec.

### Dates as anchors

A `DATE` anchor is lowered to its serial (what `DATE_SERIAL` computes), so `WITHIN 0 OF (YMD 2026 6 30)` means _by 30 June 2026_ on a trace whose timestamps are date serials — start it `AT (DATE_SERIAL (YMD 2026 6 1))` and stamp its events the same way (`IMPORT daydate` for `YMD`); the one-word spelling of the same deadline is `BEFORE (YMD 2026 6 30)`, [below](#before-absolute-deadline). Nothing declares which scale a trace is on; what the machine does instead is refuse to lower a date onto a clock that no calendar date has a serial for — an obligation entered when the clock read less than `DATE_SERIAL (YMD 1 1 1)`, 365, which is every trace that starts `AT 0` — naming the edge and the date, rather than counting from a serial in the hundreds of thousands silently, as it did before 2026-09-16. A floating trace that starts at 365 or above is not caught.

### Where an anchor is refused

The type checker refuses a lifecycle anchor where the position it names does not exist, and says so:

- `THE JOIN` and `THE DEADLINE` on an obligation that is not inside any `HENCE` or `LEST` — there is no enclosing obligation. `THE ARMING` is allowed there: it is the obligation's own arming, which is the default.
- `THE JOIN` under `LEST` — the enclosing obligation was not completed, so its join never fired.
- `THE DEADLINE` where the enclosing obligation has no `WITHIN` at all.
- An `OF` expression that is neither a `NUMBER` nor a `DATE`.

The checker sees only where an anchor is _written_. A top-level rule referenced by name inside a `HENCE` (`HENCE cure`), and a `WHERE` local, are checked where they are written — outside any `HENCE` or `LEST` — and so cannot use `THE JOIN` or `THE DEADLINE`: write the anchored obligation inline under the `HENCE`. `THE ARMING` is accepted there, and when the rule runs it names the arming of the obligation the continuation is attached to (its own, when there is none), so factoring an inline continuation out into a `WHERE` does not move its deadline, nor does putting the local inside a `RAND` or `ROR`.

Two refusals only a run can make, because the checker cannot see them, are reported when the rule runs, naming the cause:

- `THE DEADLINE` in the `HENCE` of a barrier (`ONCE ALL HAVE`) whose group turned out to be _empty_ and whose `ONCE` line has no `WITHIN` — nobody had a deadline to meet, so there is none to name.
- An obligation written under one `HENCE` and handed on as a value to a place where the position does not exist — `THE JOIN` attached under a `LEST`, `THE DEADLINE` attached under an obligation with no `WITHIN` — whether it is attached on its own or as one operand of a `RAND`/`ROR`.

Under `EVERY` the same anchors work on the act's `WITHIN`, and a join line's own `WITHIN` may be anchored to `THE ARMING` or to an instant; see [EVERY](EVERY.md#anchored-deadlines-under-a-join).

### What the exports do with an anchor

The evaluator is the only consumer that resolves an anchor. The others carry it as written, and say so:

- The state graph (`l4 state-graph`) labels the edge with the closing edge as the source spells it — `[5 OF THE JOIN]`, `ONCE ALL HAVE WITHIN 30 OF THE ARMING` — an applied duration bracketed, `[(period OF 2) OF THE ARMING]`, so the label re-parses as L4.
- The BPMN export (`l4 export --to bpmn`) draws a **plain** `WITHIN` as a timer boundary event. An **anchored** `WITHIN` gets no timer: the boundary event is a _conditional_ event whose condition is the text verbatim, and the fidelity report carries a blocking `P-DEADLINE` note on it naming the anchor — _the duration counts from THE JOIN, and this exporter does not resolve anchors_. That holds even where a timer would have been exact (`OF THE JOIN` on a `HENCE` task starts when the task does); the export declines to work that out. The task's `<documentation>` restates the rule with the anchor in it. See [DMN and BPMN](../../exports/dmn-bpmn.md#what-doesnt-survive).
- The MLIR/WASM export fails closed on an anchored `WITHIN`, as the [AFTER](AFTER.md#what-the-exports-do-with-it) page says.

### Boundary

The deadline boundary is inclusive: an action arriving _exactly at_ the deadline instant is timely. The failure/expiry path fires only once an event's timestamp is _strictly greater_ than the deadline (i.e. the deadline has _passed_).

### See Also

- **[AFTER](AFTER.md)** -- the window's opening edge: `AFTER d [OF anchor]`, `AFTER date`
- **[BEFORE](#before-absolute-deadline)** -- the closing edge's absolute form, `BEFORE date`

## HENCE (Fulfillment Consequence)

Specifies what happens on the "success" path of a deontic rule. Chains obligations sequentially so that fulfilling one triggers the next.

The meaning of "success" depends on the deontic modal:

| Modal   | HENCE triggers when...                  | Default if omitted |
| ------- | --------------------------------------- | ------------------ |
| `DO`    | action is taken                         | `FULFILLED`        |
| `MUST`  | action is taken                         | `FULFILLED`        |
| `MAY`   | action is taken                         | `FULFILLED`        |
| `SHANT` | deadline passes (prohibition respected) | `FULFILLED`        |

### Syntax

```l4
PARTY ...
MUST action
WITHIN deadline
HENCE consequentRule
```

### Examples

```l4
-- Chain of obligations
PARTY Alice
MUST pay 500
WITHIN 7
HENCE (
  PARTY Bob
  MUST deliver "goods"
  WITHIN 14
)

-- Explicit fulfillment
PARTY Seller
MUST deliver
WITHIN 14
HENCE FULFILLED
```

### See Also

- **LEST** -- the "failure" path counterpart
- **FULFILLED** -- terminal success state

## LEST (Breach Consequence)

Specifies what happens on the "failure" path of a deontic rule. Typically used for penalty clauses or fallback obligations.

The meaning of "failure" depends on the deontic modal:

| Modal   | LEST triggers when...                      | Default if omitted |
| ------- | ------------------------------------------ | ------------------ |
| `DO`    | deadline passes                            | `BREACH`           |
| `MUST`  | deadline passes without action             | `BREACH`           |
| `MAY`   | deadline passes (permission not exercised) | `FULFILLED`        |
| `SHANT` | action is taken (prohibition violated)     | `BREACH`           |

Note that SHANT flips the polarity: for prohibitions, the action happening is the failure case (LEST), while the deadline passing without action is the success case (HENCE).

**When the next clock starts.** An obligation written under a `LEST` with a plain `WITHIN d` counts its `d` from the moment the failure happened, not from the later event that brought it to light:

| The obligation that failed                                                                    | Its `LEST` counts from                                                    |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `MUST`, `DO` or `MAY` whose deadline passed                                                   | that deadline                                                             |
| `SHANT` whose forbidden act was done                                                          | the act's own timestamp                                                   |
| `EVERY … ONCE ALL HAVE WITHIN d` where everyone acted, but the last act landed after that `d` | the group's deadline (`d` after the `EVERY` was entered, unless anchored) |

The last row applies only when the group did act. A member who never acts at all fails on the first row — its own `WITHIN`, when it has one — even if the `ONCE … WITHIN` deadline was the earlier of the two: with `EVERY Tenant t … WITHIN 14 … ONCE ALL HAVE WITHIN 10 … LEST … WITHIN 5`, one tenant who never signs puts the reparation at 14 + 5 = 19, not 10 + 5 = 15, and it would be 15 only if the members carried no `WITHIN` of their own. (Whether the group deadline should win there is an open question, recorded in the design spec.)

So in the penalty clause below, Alice's 60 days to pay the larger sum run from day 30, whether the miss came to light on day 31 or on day 90 — a party who misses a deadline and then goes quiet does not push back the start of its own cure period. The same instant can be named outright as `WITHIN 60 OF THE DEADLINE` (see [WITHIN](#within-temporal-deadline)); for a missed `MUST`, `DO` or `MAY` the two spellings mean the same thing. They differ for a `SHANT`: there `THE DEADLINE` is the end of the prohibition's window, while the plain `WITHIN` counts from the violation. L4 still only _learns_ of a missed deadline when a later event arrives, and that event is offered to the `LEST` obligation, so a late payment that is the first thing recorded can still discharge the reparation it was written for — if it falls within the reparation's own window, counted from the deadline. When one event is past several windows in a chain of `LEST`s — a first chance, a second, a third — it is offered to each in turn until it reaches the first whose window is still open, and that is the obligation it performs or fails; how many other events the trace carries makes no difference to the verdict, and neither does a layer in the chain whose deadline is no later than the one before it (`WITHIN 0`, or anchored at an instant already past). The one chain that walk cannot finish is a `LEST` that names itself with a window that is never open — `WITHIN 0`, a negative `WITHIN`, or an anchored deadline that never moves — so that every incarnation is already past when it is entered; L4 refuses such a contract by name after a thousand hand-offs in a row rather than walking it forever. A breach, when one is finally reported, is dated at the event that revealed it and carries the deadline that was missed. (Before 2026-09-16 the `LEST` clock started at the revealing event instead. The tutorial [What Follows](../../tutorials/obligations/what-follows.md) works the rule through a late fee and a guarantor.)

### Syntax

```l4
PARTY ...
MUST action
WITHIN deadline
LEST breachConsequence
```

### Examples

```l4
-- Simple breach
PARTY Alice
MUST pay 100
WITHIN 30
LEST BREACH

-- Penalty clause
PARTY Alice
MUST pay 100
WITHIN 30
LEST (
  PARTY Alice
  MUST pay 150
  WITHIN 60
)
```

### See Also

- **HENCE** -- the "success" path counterpart
- **BREACH** -- terminal failure state

## PROVIDED (Guard Condition)

Adds a guard condition to a deontic action. After an event matches the action pattern, the PROVIDED expression is evaluated. If it returns FALSE, the match is rejected and the system tries the next event. Defaults to TRUE if omitted.

Think of it as a pattern-match guard: the action shape must match first, then the guard condition is checked.

### Syntax

```l4
MUST action parameter PROVIDED condition
```

### Examples

```l4
-- Conditional payment
PARTY Bob
MUST payment price PROVIDED price >= 20
WITHIN 3

-- Guard on transferred amount
PARTY borrower
MUST `Amount Transferred`
  PROVIDED `is money at least equal` `Amount Transferred` `Payment Due`
```

### See Also

- **Action Patterns** -- what a name in an action means, [below](#action-patterns-reference-or-wildcard)

## Action Patterns: Reference or Wildcard

A name written in an action slot means one of two things, and the checker
decides which by looking the name up:

1. **The name refers to something already in scope** -- a `GIVEN` input, a
   `WHERE` local, a name an outer action already bound, a same-module rule, an
   import. Then the action requires _that_ value: the event must equal it,
   the way `WHEN` does in `CONSIDER`.
2. **The name refers to nothing at all.** Then it is a fresh placeholder that
   matches any value in that position, usable afterwards in `PROVIDED`,
   `HENCE` and `LEST`. (A name that refers only to the action's own field
   selector -- `amount` naming the `amount` field being matched -- is treated
   the same way, because a selector is a function and can never be the value
   the slot wants.)

There is no keyword to choose between them: whichever is true of the name is
what it means.

```l4
-- pay is a pattern; amount matches any figure and is bound for later use
PARTY buyer MUST pay amount PROVIDED amount >= 20

-- price is a GIVEN input, so it must be paid exactly, not matched loosely
GIVEN price IS A NUMBER
GIVETH A DEONTIC Actor Action
`fixed payment` MEANS PARTY buyer MUST pay price WITHIN 30
```

**Whole actions and other expressions** are read the same way they always
were: evaluated, and compared against the event for equality. A compound
expression should be parenthesized so it does not swallow what follows it:

```l4
PARTY lender MUST (send capital to borrower)
PARTY Alice  MUST transfer (price PLUS 50) recip WITHIN 30
```

`recip` above still follows the rule at the top of this section: a reference
if something in scope is called `recip`, a placeholder otherwise.

### EXACTLY (deprecated)

`EXACTLY` used to be the keyword that spelled the first branch above -- "this
argument is a value to require," not a name to bind. It still parses and
still works exactly as it always did, but it is no longer needed: the checker
now takes the reference on its own. Where dropping it is safe, the checker's
warning says exactly what to write instead -- for a name, just the name; for
any other expression, the expression with its parentheses kept:

```l4
MUST EXACTLY (send capital to borrower)   -- deprecated
MUST (send capital to borrower)           -- means the same thing
```

One case keeps its warning without a suggested drop: an `EXACTLY` operand
that refers to nothing in scope (a typo, or a name not yet defined) would
become a silent placeholder if the keyword were simply removed, so the
checker flags it without offering that rewrite. Fix the name instead of
dropping the keyword there.

### See Also

- **PROVIDED** -- guard condition evaluated after the pattern matches

## BREACH (Terminal Violation State)

Terminal deontic value indicating that an obligation has been violated. Used as the consequence in LEST clauses. Can optionally specify the responsible party — one, or a `LIST` of several — and a reason.

### Syntax

```l4
LEST BREACH
LEST BREACH BY party
LEST BREACH BY LIST party, party
LEST BREACH BECAUSE reason
LEST BREACH BY party BECAUSE reason
LEST BREACH BY LIST party, party BECAUSE reason
```

### Examples

```l4
-- Simple breach
LEST BREACH

-- With responsible party
LEST BREACH BY Seller

-- With several responsible parties, one line of the answer each
LEST BREACH BY LIST Seller, Carrier BECAUSE "goods lost in transit"

-- With reason
LEST BREACH BECAUSE "delivery deadline exceeded"

-- Full form
LEST BREACH BY Seller BECAUSE "failed to deliver within 14 days"
```

See **[BECAUSE](BECAUSE.md)** for detailed documentation on breach reasons.

### See Also

- **LEST** -- the clause where BREACH typically appears
- **FULFILLED** -- the success counterpart

## FULFILLED (Terminal Success State)

Terminal deontic value indicating that all obligations have been satisfied and no further action is needed. Commonly used as the consequence in HENCE clauses, and as the base case in conditional deontic rules.

### Syntax

```l4
HENCE FULFILLED
```

### Examples

```l4
-- After successful delivery
PARTY Seller
MUST deliver
WITHIN 14
HENCE FULFILLED

-- Base case in conditional rule
IF NOT `conditions precedent are met`
THEN FULFILLED
ELSE PARTY lender MUST ...
```

### See Also

- **HENCE** -- the clause where FULFILLED typically appears
- **BREACH** -- the failure counterpart

## RAND (Parallel AND of Obligations)

Parallel conjunction of deontic obligations. ALL component obligations must be fulfilled for the compound to be fulfilled. If either side breaches, the whole compound breaches (short-circuit).

In concurrency theory terms, this is parallel composition where all threads must complete successfully.

### Syntax

```l4
deonton1 RAND deonton2
```

### Examples

```l4
-- Both obligations must be fulfilled
(PARTY seller MUST deliver WITHIN 14 HENCE FULFILLED LEST BREACH)
RAND
(PARTY buyer MUST pay WITHIN 30 HENCE FULFILLED LEST BREACH)
```

### See Also

- **ROR** -- disjunctive choice (any one sufficient)
- **HENCE**, **LEST** -- consequence clauses within each component

---

## ROR (Parallel OR of Obligations)

Disjunctive choice between deontic obligations. EITHER obligation being fulfilled suffices for the compound to be fulfilled. If either side fulfills, the whole compound fulfills (short-circuit).

If ALL alternatives are breached, the compound is breached; the reported breach is the latest one (the last alternative "missed its chance"), falling back to the right operand when the breaches carry no distinguishing timestamps.

In concurrency theory terms, this is a race where the first to complete determines the outcome.

### Syntax

```l4
deonton1 ROR deonton2
```

### Precedence

RAND binds tighter than ROR, so `A ROR B RAND C` means `A ROR (B RAND C)`.

### Examples

```l4
-- Either obligation can fulfill the contract
(PARTY seller MUST ship WITHIN 14 HENCE FULFILLED LEST BREACH)
ROR
(PARTY seller MUST `arrange pickup` WITHIN 7 HENCE FULFILLED LEST BREACH)
```

### See Also

- **RAND** -- parallel conjunction (all must be fulfilled)
- **HENCE**, **LEST** -- consequence clauses within each component

---

## BEFORE (Absolute Deadline)

Names an absolute deadline as the closing edge of the window, in one word: `BEFORE (YMD 2026 6 30)` is _by 30 June 2026_. It is the same deadline as `WITHIN 0 OF (YMD 2026 6 30)` (see [Dates as anchors](#dates-as-anchors)), spelled the way the sentence is. The edges are told apart by type: `WITHIN` takes a duration, `BEFORE` takes a date, and each refuses the other's argument by naming the other word — `BEFORE 30` says to write `WITHIN 30`.

### Syntax

```l4
PARTY ...
MUST action
[AFTER opening]
BEFORE date
```

The deadline instant is inclusive, as `WITHIN`'s is: an act stamped on the date itself is timely. `BEFORE` is accepted on the act only; on a join line (`ONCE ALL HAVE …`, `UPON EACH …`) write `WITHIN 0 OF date`, and the checker says so.

### Example

```l4
IMPORT daydate

DECLARE Person IS ONE OF Buyer, Seller
DECLARE Action IS ONE OF pay HAS amount IS A NUMBER

-- By 30 June, and not before 4 June (the window opens three days after arming on 1 June)
GIVETH A DEONTIC Person Action
`by june` MEANS PARTY Buyer MUST pay 100 AFTER 3 BEFORE (YMD 2026 6 30)

#TRACE `by june` AT (DATE_SERIAL (YMD 2026 6 1)) WITH
  PARTY Buyer DOES pay 100 AT (DATE_SERIAL (YMD 2026 6 4))
```

**The limit.** A date lands on the trace's clock only when the trace is stamped in date serials, as above. Nothing yet declares a contract's scale, so an obligation entered when the clock read less than `DATE_SERIAL (YMD 1 1 1)` — every trace that starts `AT 0` — has its `BEFORE` refused by name at run time rather than silently compared against a serial in the hundreds of thousands; a floating trace that starts at 365 or above is not caught. The [AFTER](AFTER.md#the-absolute-forms-after-date-before-date) page has the same sentence for `AFTER date`.

### See Also

- **[WITHIN](#within-temporal-deadline)** -- the closing edge as a duration, relative as `WITHIN d`, anchored as `WITHIN d OF instant`
- **[AFTER](AFTER.md)** -- the opening edge

---

## Testing with #TRACE

Use `#TRACE` to simulate contract execution.

### Syntax

```l4
#TRACE contractName AT startTime WITH
  PARTY partyName DOES action AT eventTime
  ...
```

### Example

```l4
#TRACE paymentObligation AT 0 WITH
  PARTY Alice DOES pay 100 AT 15
```

`l4 run` prints what the contract has become after the events. To have that read out as a list — what is owed now, what would discharge it, what would put someone in breach, and the next deadline — run `l4 lts` on the same file; see **[What is owed now: `l4 lts`](lts-list.md)**.

## Complete Example

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
  )
  LEST BREACH

#TRACE saleContract AT 0 WITH
  PARTY Seller DOES delivery AT 2
  PARTY Buyer DOES payment 100 AT 5
```

## Related Pages

- **[PARTY](PARTY.md)** - Party declarations
- **[EVERY](EVERY.md)** - One obligation for every member of a group; the group is given as a list after `IN`, as `EVERY Tenant t IN tenants`
- **[AFTER](AFTER.md)** - The window's opening edge; the two readings of a two-edged window
- **[MUST](MUST.md)** - Obligations
- **[MAY](MAY.md)** - Permissions
- **[SHANT](SHANT.md)** - Prohibitions (also written MUST NOT)
- **[DEONTIC](DEONTIC.md)** - The regulative rule type
- **[EVENT](EVENT.md)** - The event type consumed by traces
- **[What is owed now: `l4 lts`](lts-list.md)** - Read a `#TRACE` out as a list: what is owed, what would discharge it, what would breach it
- **[State graph and `--dominators`](STATE-GRAPH.md)** - The map of a rule's `HENCE`/`LEST` paths: **Show state graph** in the editor, `l4 state-graph` on the command line, which acts every path to `FULFILLED` or `BREACH` must pass through, and what the map does not say

## See Also

- **[Foundation Course: Regulative Rules](../../courses/foundation/module-6-regulative.md)** - Tutorial
- **[Regulative Rules Concept](../../concepts/legal-modeling/regulative-rules.md)** - Conceptual overview
