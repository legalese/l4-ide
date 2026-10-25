# Deadlines and consequences

A regulative rule says who must, may or must not act (see [PARTY, MUST, MAY, SHANT](PARTY.md)). This page covers the rest of the rule: the window in which the party acts (`WITHIN` and `BEFORE` here, `AFTER` on [its own page](AFTER.md)), what follows (`HENCE`, `LEST`), how the action is matched (`PROVIDED`, action patterns, and the deprecated `EXACTLY`), the end states (`FULFILLED`, `BREACH`), and rules that run side by side (`RAND`, `ROR`).

```text
PARTY party
MUST action PROVIDED condition
[AFTER opening]
WITHIN deadline          -- or BEFORE date
HENCE rule-if-complied
LEST rule-if-not
```

**Example files:** [deontic-example.l4](deontic-example.l4), [within-example.l4](within-example.l4)

## WITHIN

`WITHIN` gives the time the party has to act, as a NUMBER on the same timeline as the events in a `#TRACE`: the window's **closing edge**.
The timeline has no fixed unit: days, hours or business days all work, as long as the deadlines and the event times use the same one.
The window's **opening edge**, `AFTER`, has [its own page](AFTER.md); the closing edge's absolute form, `BEFORE date`, is [below](#before).

```l4
DECLARE Party IS ONE OF Buyer, Seller
DECLARE Action IS ONE OF `confirm order`, deliver

GIVETH A DEONTIC Party Action
`order and delivery` MEANS
  PARTY Buyer
  MUST `confirm order`
  WITHIN 30
  HENCE
    PARTY Seller
    MUST deliver
    WITHIN 5
    HENCE FULFILLED
    LEST BREACH BY Seller BECAUSE "late delivery"

#TRACE `order and delivery` AT 0 WITH
  PARTY Buyer DOES `confirm order` AT 10
  PARTY Seller DOES deliver AT 14
```

- A plain deadline counts from the moment its rule becomes active: from the start time for the first rule, from the event that completed the rule before it for a rule after `HENCE`, and from the moment the rule before it failed (its missed deadline) for a rule after `LEST`, not from the later event that brought the failure to light. Above, the buyer confirms at 10, so the seller must deliver by 15. [When the next clock starts](#when-the-next-clock-starts) has the `LEST` case.
- To count from something else, anchor the deadline with `OF` ([below](#anchoring-a-deadline-with-of)), or name a date with [`BEFORE`](#before).
- As events are read, the time left shrinks: after an event at 12, what was `WITHIN 14` from 0 has 2 left.
- A rule without `WITHIN` has no deadline. It waits for its action however long it takes, and time alone never takes it to `LEST`.
- L4 finds that a deadline has passed when it reads an event, or a `` `WAIT UNTIL` `` (see [EVENT](EVENT.md)), with a later time. That event only shows that time has moved on: it is offered in turn to the rule that follows, so a late payment that is the first thing recorded can still discharge the `LEST` reparation it was written for.

### Anchoring a deadline with OF

```l4
PARTY ...
MUST action
[AFTER opening [OF anchor]]
WITHIN duration [OF anchor]
```

The duration is a `NUMBER` of clock units — the same units the trace's timestamps use (days, if the trace is stamped in days). Written alone, it counts from where the language puts it: an obligation at the top level counts from when it was entered; an obligation under a `HENCE` counts from the moment the previous obligation was completed; an obligation under a `LEST` counts from the moment the previous obligation _failed_ — its missed deadline for a `MUST`, `DO` or `MAY`, the forbidden act itself for a `SHANT` (the [When the next clock starts](#when-the-next-clock-starts) has the rule in full).

The duration can be anchored with `OF`, and then the deadline is **absolute**: the anchor's instant plus the duration, whatever the clock read when the obligation was entered. The anchor is one of:

| Anchor            | Names                                                                                           |
| ----------------- | ----------------------------------------------------------------------------------------------- |
| `OF THE JOIN`     | the instant the enclosing obligation's `HENCE` fired (under `HENCE` this is the default, named) |
| `OF THE DEADLINE` | the enclosing obligation's deadline (its `WITHIN`)                                              |
| `OF THE ARMING`   | the instant the enclosing obligation was entered — under a `LEST`, the failure it repairs       |
| `OF expression`   | an instant: a `NUMBER` on the trace's clock, or a `DATE`                                        |

"The enclosing obligation" is the one whose `HENCE` or `LEST` this obligation is the continuation of — the one it is attached to when it runs. Usually that is the obligation it is written under; but a continuation can also arrive as a value (a rule with `GIVEN k IS A DEONTIC …` that ends `HENCE k`, or a `WHERE` local), and then the anchors name the obligation it is handed to, not the one it was written under — also when the value is one operand of a `RAND` or `ROR` there. It is the _nearest_ enclosing obligation: two levels down, `THE ARMING` is the middle obligation's arming, not the outermost rule's, so "within 10 days of this agreement" (below) works from one level down, where the phrase is written.

An obligation is _entered_ at the instant its plain `WITHIN` counts from: at the top level, when the trace begins; under a `HENCE`, at the act (or, after a kept prohibition, at the end of its window); under a `LEST`, at the failure — so `THE ARMING` read from inside a reparation's own `HENCE` or `LEST` is the missed deadline (or the forbidden act), not the later event that revealed it (`jl4/examples/ok/every/run-lest.l4` §10).

For a `MUST`, `DO` or `MAY`, the join is the act that completed it. For a prohibition (`SHANT`) that was kept, the join is the end of its window: the prohibition was discharged at its deadline, so its `HENCE` counts from there and `THE JOIN` names that instant, whenever the next event happens to come along. (The machine still only _learns_ it was kept at the first event after the deadline; that event is offered to the `HENCE`.) A prohibition that was broken has a join too: under its `LEST`, `THE JOIN` is the act that broke it, the same instant an unanchored `WITHIN` there counts from. Under the `LEST` of a `MUST`, `DO` or `MAY` nothing joined, and `THE JOIN` is refused.

`THE` is a keyword; `JOIN`, `DEADLINE` and `ARMING` are matched by spelling after it and are not reserved, so a program may still name a value `DEADLINE`.
But `THE DEADLINE` is then always the lifecycle position, never that value: write the value as `DEADLINE`, without `THE`.
Before 2026-10-24 the `THE` was an optional article, and `WITH start IS THE DEADLINE` passed the program's own value; since then it passes the enclosing obligation's deadline, and the checker warns wherever `THE` is written before a noun that the program also defines.
The warning names the value that `THE DEADLINE` hides, and says to write `DEADLINE` without `THE` to reach it.
When the program defines the value itself, renaming it also silences the warning; when the value comes from an `IMPORT`, the only remedy offered is to drop `THE`, because the module that defines it may not be yours to change.
`jl4-service` goes further and refuses to deploy a module that draws this warning, naming the hidden value: a deployment publishes answers, and this is the one spelling whose answer can change with no error.
The three are also ordinary values, usable anywhere a number is: [below](#the-anchor-words-as-values).

Inside the duration, `OF` is always the anchor — everywhere in it, not only at the front — so `WITHIN f OF x` means `f` anchored at `x`, and so does an `OF` inside an `IF` branch, an operator's operand or a `WHERE` in the duration. To apply a function there, bracket the call (`WITHIN (f OF x) OF THE JOIN`) or juxtapose its arguments (`WITHIN f x OF THE JOIN`); the checker's message says so when the duration turns out to be a function.

Beside an `AFTER`, a bare `WITHIN` counts from the instant the window **opened**: `AFTER 3 WITHIN 30` is the window `[a+3, a+33]`, the cooling-off sentence. To measure both edges from one anchor — _not less than 3 nor more than 30 days after delivery_, `[a+3, a+30]` — name the anchor on the closing edge: `AFTER 3 WITHIN 30 OF THE JOIN`. The [AFTER](AFTER.md) page has the two readings and what an act before the window opens does. A `WITHIN` takes a duration, never a date: `WITHIN (YMD 2026 6 30)` is a check error that names `BEFORE`.

### The anchor words as values

`THE JOIN`, `THE DEADLINE` and `THE ARMING` are not only anchors.
Each is a `NUMBER`, the instant on the trace's clock that the position had, and can be used wherever a number can: in arithmetic, as an argument to a function, in a `PROVIDED`, in a `RECORD`.

```l4
HENCE (PARTY Landlord MUST deliver WITHIN 0 OF (THE JOIN PLUS 5))
HENCE `refund within 30 of` THE JOIN
LEST  (PARTY Tenant MUST cure WITHIN 0 OF (THE DEADLINE PLUS 5))
```

The first says _by five days after the join_, which is the same deadline as `WITHIN 5 OF THE JOIN`.
Written without the brackets, `WITHIN 0 OF THE JOIN PLUS 5` means the same: when arithmetic follows the noun, the whole of it is the anchor.
The operator may also start the next line, indented as any continuation is.

**What a noun names depends on where it is written, and on what holds it.**
Usually it is the position in the life of the obligation whose `HENCE` or `LEST` the noun is written in (and `THE ARMING` written in a top-level obligation's own lines is that obligation's own arming).
The exception is a noun inside an obligation that is handed on as a value, in the fourth point below.
That has four consequences worth knowing before you rely on it:

- **A function or a rule defined elsewhere receives the instant as an argument.** A top-level rule cannot read `THE JOIN`, because it is not written under any `HENCE`. Give it a `GIVEN`, and pass the instant from where it is meaningful, as the second line of the example above does (or by name, `WITH start IS THE JOIN`).
- **A `WHERE` name for a noun keeps the instant it was written under.** In the example below, `receipt` is written in the `HENCE` of the tenant's obligation, so it is the tenant's signature, and it stays that instant two obligations further down. A bare `THE JOIN` in the refund's `WITHIN` would instead name the landlord's acknowledgement.

  ```l4
  PARTY Tenant MUST sign WITHIN 30
  HENCE (    PARTY Landlord MUST acknowledge WITHIN 5
             HENCE (PARTY Landlord MUST refund WITHIN 30 OF receipt)
         WHERE receipt MEANS THE JOIN)
  ```

- **In the next obligation's own `PROVIDED` or `WITHIN`, the noun still names the obligation before it.** In `HENCE (PARTY Bob MUST pay n PROVIDED n AT LEAST THE JOIN …)`, `THE JOIN` is the time of the act that completed the _previous_ obligation, not the time of the payment being tested. The `PROVIDED` is written in the previous obligation's `HENCE`, and that is the obligation the noun belongs to.
- **Inside an obligation handed on as a value, a noun is read where that obligation runs.** An obligation defined in a `WHERE`, passed in by a `GIVEN`, or returned by a function is attached under some other obligation's `HENCE` or `LEST` when it runs, and every noun inside it (in its `WITHIN`, its `PROVIDED`, its action) names a position of the obligation it is attached to, exactly as its anchors do (see [Where an anchor is refused](#where-an-anchor-is-refused)). That keeps a deadline where it was when a continuation written inline is factored out into a `WHERE`. A `NUMBER` is different: a `WHERE` name for a noun is fixed where it is written, as the second point says.

  **So moving a noun between an obligation and a `WHERE` name changes what it means, and nothing reports it.**
  Below, the tenant signs at 4 and the landlord acknowledges at 10, and `k` is attached under the acknowledgement's `HENCE`.
  Written as it is, `k`'s `THE JOIN` is the acknowledgement, so the refund is due at 15.
  Write the same deadline as `WITHIN 0 OF t WHERE t MEANS THE JOIN PLUS 5`, with the `WHERE` inside `k`'s definition, and `t` is a number fixed where `k` is defined, in the `HENCE` of the tenant's obligation: it is the signature plus 5, and the refund is due at 9.

  ```l4
  PARTY Tenant MUST sign WITHIN 30
  HENCE (    PARTY Landlord MUST acknowledge WITHIN 30
             HENCE k
         WHERE k MEANS PARTY Landlord MUST refund WITHIN 0 OF (THE JOIN PLUS 5))
  ```

  The same holds for a `PROVIDED` inside `k`: `n EQUALS THE JOIN` there tests against the acknowledgement's time, 10, not the signature's, 4.
  (`jl4/examples/ok/every/run-lifecycle-values.l4` §12 runs both pairs.)

On a join line (the `WITHIN` after `ONCE ALL HAVE`), `THE ARMING` as a value is the `EVERY`'s own arming, as `OF THE ARMING` is there, however deeply the `EVERY` is nested.
That holds for the noun written on the join line itself.
A `WHERE` name for `THE ARMING` written in the enclosing `HENCE` is a number fixed there, so it is the arming of the obligation that `HENCE` belongs to, not the `EVERY`'s (§10 of the same file).

**A default for an instant that may not exist.**
An anchor must be an instant, never a `MAYBE`: a `RECALL` of a fact that may never have been recorded is refused there, and the language supplies no default.
If the fact may not have been recorded, write the default yourself, for example the arming:

```l4
WITHIN 5 OF (fromMaybe THE ARMING (RECALL `notice served`))
```

Use this only when the fact is certain to be recorded _before_ the obligation is entered.
The anchor is worked out once, at the first event the obligation looks at.
If the notice is recorded later than that, the deadline still counts from the default, and nothing reports that it did: the result is a breach or a fulfilment computed from the wrong instant.

### Anchored examples

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

An anchored deadline may already be in the past when the obligation is entered — `WITHIN 5 OF closingDate` on a contract that begins after `closingDate + 5`. Such an obligation could never be met. It is not refused when the file is checked, because the deadline is a value the run works out; instead the run reports it in a note, under `Notes:`, naming the obligation, when it was entered and the deadline it already had. The obligation then fails at the instant it was entered, not before it existed, and its `LEST` counts from there: a `WITHIN 5 OF 0` entered at 20 with `LEST … WITHIN 10` fails at 20 and its reparation is due at 30. A `MAY` entered after its deadline lapses then, and a `SHANT` is kept then. The common way to write one by accident is `WITHIN d OF THE ARMING` inside a `HENCE` or `LEST`, where `THE ARMING` is when the obligation it continues was entered, not this one; the note says so when that is the cause.

### Dates as anchors

A `DATE` anchor is lowered to its serial (what `DATE_SERIAL` computes), so `WITHIN 0 OF (YMD 2026 6 30)` means _by 30 June 2026_ on a trace whose timestamps are date serials — start it `AT (DATE_SERIAL (YMD 2026 6 1))` and stamp its events the same way (`IMPORT daydate` for `YMD`); the one-word spelling of the same deadline is `BEFORE (YMD 2026 6 30)`, [below](#before). Nothing declares which scale a trace is on; what the machine does instead is refuse to lower a date onto a clock that no calendar date has a serial for — an obligation entered when the clock read less than `DATE_SERIAL (YMD 1 1 1)`, 365, which is every trace that starts `AT 0` — naming the edge and the date, rather than counting from a serial in the hundreds of thousands silently, as it did before 2026-09-16. A floating trace that starts at 365 or above is not caught.

### Where an anchor is refused

The type checker refuses a lifecycle anchor where the position it names does not exist, and says so:

- `THE JOIN` and `THE DEADLINE` on an obligation that is not inside any `HENCE` or `LEST` — there is no enclosing obligation. `THE ARMING` is allowed there: it is the obligation's own arming, which is the default.
- `THE JOIN` under `LEST` — the enclosing obligation was not completed, so its join never fired.
- `THE DEADLINE` where the enclosing obligation has no `WITHIN` at all.
- An `OF` expression that is neither a `NUMBER` nor a `DATE`.

The same refusals apply to the nouns used as [values](#the-anchor-words-as-values), wherever they are written: `THE JOIN` or `THE DEADLINE` in a top-level rule, in a top-level rule's `WHERE`, or in a function's body; `THE JOIN` under the `LEST` of a `MUST`, `DO` or `MAY`; `THE DEADLINE` under an obligation with no closing edge; and either of them anywhere in a join line's `WITHIN`.
`THE ARMING` as a value is refused wherever no obligation has been entered where it is written.
It can be read in an obligation's own lines (its party, its action and `PROVIDED`, its `AFTER` and `WITHIN`, an `EVERY`'s join line) and anywhere inside a `HENCE` or `LEST`.
Everywhere else it is refused when the file is checked: in a top-level rule's `WHERE t MEANS THE ARMING`, in a top-level rule's body, and in the body of a function or an `@export`ed decision, which is read where the function is defined, not where it is called.
An `EVERY`'s `IN` roll and its `WHO` or `WHOSE` filter are not among its own lines either: they are read before any member's obligation is entered, so `THE ARMING` there is refused unless the `EVERY` sits under a `HENCE` or `LEST`.
To use the instant in a function, pass it as an argument from one of those places: `WITHIN 0 OF (f THE ARMING)`.
(These used to check clean and be refused by the run on every input.)

The checker sees only where an anchor is _written_. A top-level rule referenced by name inside a `HENCE` (`HENCE cure`), and a `WHERE` local, are checked where they are written — outside any `HENCE` or `LEST` — and so cannot use `THE JOIN` or `THE DEADLINE`: write the anchored obligation inline under the `HENCE`. `THE ARMING` is accepted in such an obligation's own lines, and when the rule runs it names the arming of the obligation the continuation is attached to (its own, when there is none), so factoring an inline continuation out into a `WHERE` does not move its deadline, nor does putting the local inside a `RAND` or `ROR`.

Two refusals only a run can make, because the checker cannot see them, are reported when the rule runs, naming the cause:

- `THE DEADLINE` in the `HENCE` of a barrier (`ONCE ALL HAVE`) whose group turned out to be _empty_ and whose `ONCE` line has no `WITHIN` — nobody had a deadline to meet, so there is none to name.
- An obligation written under one `HENCE` and handed on as a value to a place where the position does not exist — `THE JOIN` attached under a `LEST`, `THE DEADLINE` attached under an obligation with no `WITHIN` — whether it is attached on its own or as one operand of a `RAND`/`ROR`.

Under `EVERY` the same anchors work on the act's `WITHIN`, and a join line's own `WITHIN` may be anchored to `THE ARMING` or to an instant; see [EVERY](EVERY.md#anchored-deadlines-under-a-join).

### What the exports do with an anchor

The evaluator is the only consumer that resolves an anchor. The others carry it as written, and say so:

- The state graph (`l4 state-graph`) labels the edge with the closing edge as the source spells it — `[5 OF THE JOIN]`, `ONCE ALL HAVE WITHIN 30 OF THE ARMING` — an applied duration bracketed, `[(period OF 2) OF THE ARMING]`, so the label re-parses as L4.
- The BPMN export (`l4 export bpmn`) draws a **plain** `WITHIN` as a timer boundary event. An **anchored** `WITHIN` gets no timer: the boundary event is a _conditional_ event whose condition is the text verbatim, and the fidelity report carries a blocking `P-DEADLINE` note on it naming the anchor — _the duration counts from THE JOIN, and this exporter does not resolve anchors_. That holds even where a timer would have been exact (`OF THE JOIN` on a `HENCE` task starts when the task does); the export declines to work that out. The task's `<documentation>` restates the rule with the anchor in it. See [DMN and BPMN](../../exports/dmn-bpmn.md#what-doesnt-survive).
- The MLIR/WASM export fails closed on an anchored `WITHIN`, as the [AFTER](AFTER.md#what-the-exports-do-with-it) page says.

### Boundary

The deadline boundary is inclusive: an action arriving _exactly at_ the deadline instant is timely. The failure/expiry path fires only once an event's timestamp is _strictly greater_ than the deadline (i.e. the deadline has _passed_).

### Counting days

Read as days, that boundary is the counting rule most statutes use: **the day you count from is not counted, and the last day is.** `WITHIN 14 OF 10` is due on day 24 — an act on day 24 is in time and one on day 25 is late (measured). That is the rule of the Singapore Interpretation Act s 50(a), of EU Regulation 1182/71 Art 3(1), and of the German Civil Code § 187(1), and it applies to both edges of a window: `AFTER 3` opens on the third day after its anchor, not on the day itself.

Two neighbours of that rule are yours to write, not the language's:

- **"Beginning with" the anchor day** (§ 187(2) BGB, and some contracts) counts the first day too, so fourteen days beginning with day 10 end on day 23: write `WITHIN 13 OF 10`.
- **Months, month-ends, business days and public holidays** are calendar questions, and the calendar belongs to a library rather than to `WITHIN`: compute the day with the date library and anchor on it (`WITHIN 0 OF <that day>`, or `BEFORE <that date>`). Numbers on their own are just days on the trace's clock.

(Ruled 21 September 2026, EVERY bench card B6.)

## BEFORE

Names an absolute deadline as the closing edge of the window, in one word: `BEFORE (YMD 2026 6 30)` is _by 30 June 2026_. It is the same deadline as `WITHIN 0 OF (YMD 2026 6 30)` (see [Dates as anchors](#dates-as-anchors)), spelled the way the sentence is. The edges are told apart by type: `WITHIN` takes a duration, `BEFORE` takes a date, and each refuses the other's argument by naming the other word — `BEFORE 30` says to write `WITHIN 30`.

```l4
PARTY ...
MUST action
[AFTER opening]
BEFORE date
```

The deadline instant is inclusive, as `WITHIN`'s is: an act stamped on the date itself is timely. `BEFORE` is accepted on the act only; on a join line (`ONCE ALL HAVE …`, `UPON EACH …`) write `WITHIN 0 OF date`, and the checker says so.

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

## HENCE and LEST

`HENCE` names what follows when the rule is complied with, and `LEST` what follows when it is not.
Each can be `FULFILLED`, `BREACH`, or another rule, so rules chain into a contract.
A `LEST` that is another rule expresses a remedy, such as a penalty or a grace period:

```l4
DECLARE Party IS ONE OF Borrower
DECLARE Action IS ONE OF pay HAS amount IS A NUMBER

GIVETH A DEONTIC Party Action
`payment with penalty` MEANS
  PARTY Borrower
  MUST pay 1000
  WITHIN 30
  HENCE FULFILLED
  LEST
    PARTY Borrower
    MUST pay 1100
    WITHIN 15
    LEST BREACH
```

Which branch is taken, and what is used when it is left out, depends on the modal:

| Modal              | `HENCE` is taken when                  | `LEST` is taken when                                      | `HENCE` default | `LEST` default |
| ------------------ | -------------------------------------- | --------------------------------------------------------- | --------------- | -------------- |
| `MUST`             | the action is taken in time            | the deadline passes without it                            | `FULFILLED`     | `BREACH`       |
| `MAY`              | the action is taken in time            | the deadline passes without it (permission not exercised) | `FULFILLED`     | `FULFILLED`    |
| `SHANT / MUST NOT` | the deadline passes without the action | the action is taken                                       | `FULFILLED`     | `BREACH`       |
| `DO`               | the action is taken in time            | the deadline passes without it                            | `FULFILLED`     | `BREACH`       |

For a prohibition the polarity flips: the deadline passing quietly is the good outcome. `HENCE` always names the outcome the rule wants, and `LEST` the one it does not.
Not using a permission is not a breach unless you make it one: a `LEST BREACH` after a `MAY` breaches when the permission goes unused.

A rule written on the same line as its `HENCE` needs parentheses when a `LEST` follows on the next line: `HENCE (PARTY Seller MUST deliver WITHIN 5)`. Without them, that `LEST` is an indentation error. A rule on lines of its own, as above, needs none.

### When the next clock starts

**When the next clock starts.** An obligation written under a `LEST` with a plain `WITHIN d` counts its `d` from the moment the failure happened, not from the later event that brought it to light:

| The obligation that failed                                                                    | Its `LEST` counts from                                                    |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `MUST`, `DO` or `MAY` whose deadline passed                                                   | that deadline                                                             |
| `SHANT` whose forbidden act was done                                                          | the act's own timestamp                                                   |
| `EVERY … ONCE ALL HAVE WITHIN d` where everyone acted, but the last act landed after that `d` | the group's deadline (`d` after the `EVERY` was entered, unless anchored) |

The last row applies only when the group did act. A member who never acts at all fails on the first row — its own `WITHIN`, when it has one — even if the `ONCE … WITHIN` deadline was the earlier of the two: with `EVERY Tenant t … WITHIN 14 … ONCE ALL HAVE WITHIN 10 … LEST … WITHIN 5`, one tenant who never signs puts the reparation at 14 + 5 = 19, not 10 + 5 = 15, and it would be 15 only if the members carried no `WITHIN` of their own. (Whether the group deadline should win there is an open question, recorded in the design spec.)

So in the penalty clause below, Alice's 60 days to pay the larger sum run from day 30, whether the miss came to light on day 31 or on day 90 — a party who misses a deadline and then goes quiet does not push back the start of its own cure period. The same instant can be named outright as `WITHIN 60 OF THE DEADLINE` (see [WITHIN](#within)); for a missed `MUST`, `DO` or `MAY` the two spellings mean the same thing. They differ for a `SHANT`: there `THE DEADLINE` is the end of the prohibition's window, while the plain `WITHIN` counts from the violation. L4 still only _learns_ of a missed deadline when a later event arrives, and that event is offered to the `LEST` obligation, so a late payment that is the first thing recorded can still discharge the reparation it was written for — if it falls within the reparation's own window, counted from the deadline. When one event is past several windows in a chain of `LEST`s — a first chance, a second, a third — it is offered to each in turn until it reaches the first whose window is still open, and that is the obligation it performs or fails; how many other events the trace carries makes no difference to the verdict, and neither does a layer in the chain whose deadline is no later than the one before it (`WITHIN 0`, or anchored at an instant already past). The one chain that walk cannot finish is a `LEST` that names itself with a window that is never open — `WITHIN 0`, a negative `WITHIN`, or an anchored deadline that never moves — so that every incarnation is already past when it is entered; L4 refuses such a contract by name after a thousand hand-offs in a row rather than walking it forever. A breach, when one is finally reported, is dated at the event that revealed it and carries the deadline that was missed; see [When a breach happened](#when-a-breach-happened) for the two instants every failure carries. (Before 2026-09-16 the `LEST` clock started at the revealing event instead. The tutorial [What Follows](../../tutorials/obligations/what-follows.md) works the rule through a late fee and a guarantor.)

## FULFILLED and BREACH

`FULFILLED` and `BREACH` are the two end states. `FULFILLED` means nothing more is owed; `BREACH` means a party failed and nothing absorbed the failure.

```text
LEST BREACH
LEST BREACH BY party
LEST BREACH BY LIST party, party
LEST BREACH BECAUSE reason
LEST BREACH BY party BECAUSE reason
LEST BREACH BY LIST party, party BECAUSE reason
```

`BY` names the party in breach, or a `LIST` of several, one line of the answer each, and [BECAUSE](BECAUSE.md) gives the reason, a STRING.

```l4
LEST BREACH BY LIST Seller, Carrier BECAUSE "goods lost in transit"
```

`FULFILLED` is also the natural result for a case where no duty arises: ``IF NOT `conditions are met` THEN FULFILLED ELSE PARTY …``.

## PROVIDED

`PROVIDED` adds a condition to the action. An event first has to match the action; then the condition is evaluated, with the names the action bound. If it is FALSE, the event does not count and the next one is tried.

```l4
DECLARE Party IS ONE OF Buyer
DECLARE Action IS ONE OF `pay invoice` HAS amount IS A NUMBER

GIVETH A DEONTIC Party Action
`minimum payment` MEANS
  PARTY Buyer
  MUST `pay invoice` amount PROVIDED amount >= 100
  WITHIN 30

#TRACE `minimum payment` AT 0 WITH
  PARTY Buyer DOES `pay invoice` 50 AT 5
  PARTY Buyer DOES `pay invoice` 150 AT 6
```

The payment of 50 does not count; the payment of 150 fulfils the rule. Without `PROVIDED`, the condition is TRUE.

## Action patterns: reference or wildcard

The action after the modal is a pattern, as in a [CONSIDER](../control-flow/CONSIDER.md): a value, such as `pay 1000` or `deliver "goods"`, matches only that value, and a name is read as follows.

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

## RAND and ROR

`RAND` and `ROR` combine two rules that run at the same time, on the same events.

- `A RAND B` is fulfilled when both are fulfilled, and breached as soon as either is breached. When both sides fail, the compound is breached at the **earlier** of the two failures, because the first failure already loses it, and the breach names both sides' failures, left first.
- `A ROR B` is fulfilled as soon as either is fulfilled, and breached only when both are breached. When all alternatives fail, the compound is breached at the **later** of the failures, when the last alternative missed its chance, and the breach names every alternative's failure, left first.

In both, the order the operands are written in makes no difference to when, or to which failure decided it; see [When a breach happened](#when-a-breach-happened).

```l4
DECLARE Party IS ONE OF Seller
DECLARE Action IS ONE OF ship, `arrange pickup`

GIVETH A DEONTIC Party Action
`either way of delivering` MEANS
     (PARTY Seller MUST ship WITHIN 14 HENCE FULFILLED LEST BREACH)
  ROR
     (PARTY Seller MUST `arrange pickup` WITHIN 7 HENCE FULFILLED LEST BREACH)
```

`RAND` binds more tightly than `ROR`: `A ROR B RAND C` means `A ROR (B RAND C)`.
A combination can follow `HENCE` or `LEST`, so one event can start several duties.

## When a breach happened

Every failure a breach names carries two instants.

- **When it took effect.** For a missed deadline, the deadline — or, for an obligation entered after its own deadline, the moment it was entered (see [WITHIN](#within)). For a broken prohibition, the act that broke it. For a `BREACH` written in a `HENCE` or `LEST`, the instant that continuation counts from: the missed deadline under a `LEST`, the act (or a kept prohibition's deadline) under a `HENCE`.
- **When it came to light.** The time of the event that showed it. L4 only learns that a deadline has passed when a later event arrives, so a deadline of 5 that nothing shows until an event at 10 took effect at 5 and came to light at 10.

A compound is breached at the instant its parts' failures took effect, worked out the way the operators read: a `RAND` at the earliest, an `ROR` at the latest, and inside out when they are nested. With `(P MUST x WITHIN 1 ROR Q MUST y WITHIN 10) RAND R MUST z WITHIN 5` and nobody acting, the `ROR` holds until Q's deadline at 10, so the `RAND` is lost at 5, by R — not at 1, because P's miss lost nothing while Q could still act. The failures that fix that instant are the **decisive** ones. The breach report prints the first of them in the usual words, then any others that failed at the same instant, then every failure in the order the rule is written:

```text
DEONTIC BREACHED:
  party
    NEVERMATCHESPARTY
  who did action
    NEVERMATCHESACT
  at
    10
  surpassed the deadline of party
    P
  who had to do obligatory action
    MUST x
  before their deadline, which was at
    5
  and at the same instant
    Q
      who had to do obligatory action
        MUST y
      before their deadline, which was at
        5
  and the breach names, in order
    P
      ...
    Q
      ...
```

That is `(PARTY P MUST x WITHIN 5) RAND (PARTY Q MUST y WITHIN 5)` with one event at 10. Written the other way round, it reports the same instant and the same two decisive failures; only the order of the lists follows the rule, and the first line names Q. The `at` is when the breach came to light; `NEVERMATCHESPARTY` and `NEVERMATCHESACT` are how a `` `WAIT UNTIL` `` event prints.

`l4 batch` gives the same answer as data: each object in `failures` has `effective` and `observed`, and the breach has the compound's `effective` and `observed` instants and `decisive`, the positions in `failures` of the decisive ones. `anchor` is the position of the one the scalars describe.

What this does **not** promise:

- **That the verdict never depends on the order of the operands.** It does not, for operands that only make and miss deadlines. But each operand is run over the whole trace before the next one starts, so an operand that reads a fact the other one records (`RECALL` of a `RECORD` made in the sibling's `HENCE`) can see it or not depending on which is written first. Do not write a `RAND` or `ROR` whose operands read each other's records; the design spec has the open question.
- **That an `ROR`'s operands both run.** Once one alternative is fulfilled, the other is not run further, so a `RECORD` it would have made is not made.
- **The decision service's answer.** `jl4-service` reports the same breach without the new `effective`, `observed` and `decisive` fields: `l4 batch` carries them, and `l4 run` prints the decisive failures.

## Related pages

- [Regulative rules](README.md): the parts of a rule and `#TRACE`
- [AFTER](AFTER.md): the window's opening edge, and the two readings of a two-edged window
- [EVERY](EVERY.md): one obligation for every member of a group
- [DEONTIC](DEONTIC.md): the type of rules, and how they are evaluated
- [How obligations unfold](../../concepts/legal-modeling/regulative-rules.md): the model behind deadlines and events
