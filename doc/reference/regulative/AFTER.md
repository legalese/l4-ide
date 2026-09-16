# AFTER (Opening Edge of the Window)

_After the order is delivered, the customer may place a new order after a three-day cooling-off period, within 30 days._ That sentence has a window with two edges: it **opens** three days after delivery and **closes** thirty days after that. `WITHIN` gives a window its closing edge; `AFTER` gives it its opening edge.

```l4
PARTY Buyer MUST order
AFTER  3
WITHIN 30
```

**Example file:** [after-example.l4](after-example.l4) — the rules on this page, each with a trace showing the instants its window produces.

## The two readings, and why the bare form re-anchors

English writes windows in two shapes, and they are not the same window.

- **Re-anchored:** _after a three-day cooling-off period, within 30 days_ — an offset, then a length measured from where the offset ends. Delivery at 10 gives the window **[13, 43]**.
- **Two-offset:** _not less than 3 nor more than 30 days after delivery_ — two offsets from one anchor. Delivery at 10 gives the window **[13, 40]**.

The bare form, `AFTER 3 WITHIN 30`, is the **re-anchored** window: the `WITHIN` counts from the instant the window opened. It is the reading the cooling-off sentence has, the one the contract calculus this evaluator follows gives it, and the one a process modeller draws by default (a timer starts when the task is reached). It is also the reading that cannot go wrong: opening at 3 and staying open for 30 after that can never be an empty window.

The two-offset window is written with an explicit anchor on the closing edge:

```l4
PARTY Buyer MUST order
AFTER  3
WITHIN 30 OF THE JOIN        -- [delivery+3, delivery+30]
```

`OF THE JOIN` is the anchor vocabulary of [WITHIN](README.md#within-temporal-deadline): the instant the enclosing obligation's `HENCE` fired — here, the delivery. Any anchor `WITHIN` accepts works on the closing edge, and on the opening edge too: `AFTER 3 OF THE JOIN WITHIN 30` opens three after the delivery and, with the `WITHIN` bare, still re-anchors ([13, 43]); `AFTER 3 OF THE ARMING WITHIN 30 OF THE JOIN` measures the two edges from two different instants.

A two-offset window can close before it opens. `AFTER 30 WITHIN 5 OF THE JOIN` is refused by the type checker when both offsets are literals; when they are computed, the run reports it beside the result and the obligation runs as written — every act is early or late.

## An early act is a nullity, and the run says so

An act before the window opens **does not count**. It is not performance, and it is not a breach: the obligation stays live, its deadline is what it was, and the party may act again once the window is open. What the machine adds is a report. A silent nullity is how a party loses a deadline it believed it had met, so the run prints a note beside the result:

```
PARTY Buyer MUST order AFTER 1 WITHIN 30 HENCE FULFILLED
NOTE: PARTY Buyer did order at 12, before the window opened at 13: the act
does not count as performance. The obligation stays live, with its deadline
untouched (the window closes at 43), and may be performed once the window
is open.
```

The residual printed above is the window as it stands at instant 12: it opens in 1 and runs 30 from there. Once the window has opened, the residual prints as a plain `WITHIN` with the time remaining, as an anchored deadline's does.

For a prohibition the early act is likewise not a violation — the prohibition has not started — and the note says so. `PARTY Buyer SHANT smoke AFTER 3 WITHIN 30` forbids smoking from 3 to 33: smoking at 2 is reported and ignored, smoking at 5 is the violation, and a prohibition kept through 33 is fulfilled.

## AFTER alone

An `AFTER` with no closing edge is a window that opens and never closes — a right that vests and does not expire.

```l4
PARTY Buyer MAY order AFTER 3
```

An act at 1000 is in time. Before the window opens the residual prints `AFTER n`; after it, the permission prints with no window at all.

## Under LEST, and under a join

Under a `LEST` the clock is the missed deadline (see [LEST](README.md#lest-breach-consequence)), so `AFTER 3 WITHIN 30` there opens three after the deadline that was missed and closes thirty after that — `[deadline+3, deadline+33]` — with or without `OF THE DEADLINE` written on the `AFTER`. In the `HENCE` of a barrier (`ONCE ALL HAVE`) it counts from the last member's act; on the members' own line it counts from the `EVERY`'s arming, for each member. A join line's own `WITHIN` bounds the whole and is not re-anchored by a member's `AFTER`: with `AFTER 3` on the act and `WITHIN 30` on the join line, each member's window is `[3, 30]` from the arming. The join line takes no `AFTER` of its own. See [EVERY](EVERY.md#what-runs-today-and-what-does-not).

## The absolute forms: AFTER date, BEFORE date

Each edge also has an absolute form. `AFTER` takes a date as well as a duration — the type says which — and the closing edge's absolute form has its own word, `BEFORE`:

```l4
PARTY Buyer MUST pay 100
AFTER  3
BEFORE (YMD 2026 6 30)       -- opens three days after arming, closes on 30 June
```

`WITHIN` takes a duration and `BEFORE` takes a date, as in English — _within 30 days_, _before 30 June_, never _within 30 June_ — and each refuses the other's argument by naming the other word. `AFTER (YMD 2026 6 10) WITHIN 5` opens on 10 June and runs five days from there. A date already names an instant, so `AFTER date` takes no `OF` anchor. `BEFORE` is accepted on the act only; on a join line write `WITHIN 0 OF date`.

**The limit.** A date is lowered to its serial (what `DATE_SERIAL` computes), which lands on the trace's clock only when the trace is stamped in date serials — start it `AT (DATE_SERIAL (YMD 2026 6 1))` and stamp its events the same way (`IMPORT daydate` for `YMD`). Nothing yet declares, at the contract level, which scale a contract's clock is on; until it does, the machine refuses to lower a date onto a clock that no calendar date has a serial for — an obligation entered when the clock read less than `DATE_SERIAL (YMD 1 1 1)`, which is 365, i.e. every trace that starts `AT 0` — and says so by name, instead of counting from a serial in the hundreds of thousands. A floating trace that happens to start at 365 or above is not caught: that is the one sentence this page owes you. The same refusal now protects `WITHIN d OF date`.

## Order

The opening edge is written before the closing edge — `AFTER 3 WITHIN 30`, `AFTER 3 BEFORE date` — and a deonton has one of each. `WITHIN 30 AFTER 3` is a parse error that says so. (The two orders do not mean two different windows; that idea was considered and rejected, because word order is the wrong place to carry a meaning an anchor already carries.)

## What the exports do with it

- The natural-language annotation reads the bare window aloud as _after 3, within 30 of that_.
- The document export prints the window as one phrase with its own prepositions: _after 3, within 30 of that_; _before 30 June_.
- The BPMN export does not draw an opening edge — a BPMN task is enabled as soon as it is reached — and its fidelity report says so on the task (`P-WINDOW-OPENING`, blocking). A `BEFORE` date is carried onto the boundary event verbatim as a condition, not as a timer.
- The MLIR/WASM export fails closed on any obligation with an `AFTER`, as it already does on an anchored `WITHIN`.

## What `l4 lts` shows

[`l4 lts`](lts-list.md) lists an obligation whose window has yet to open with the deadline the window actually closes on — `Buyer MUST order — due by 43 (31 from now; the window opens at 13)` after the early act at 12 in the first trace of `after-example.l4` — and files that early act under _What the contract would pass over_: "the window has not opened yet (it opens at 13; an act before then counts for nothing)". With `--steps` the early act's look is in the history like any other, worded "the act came before the window opens at 13; it counts for nothing and is passed over". The golden `jl4/examples/lts/expected/after-example.txt` is the whole listing of this page's example file. Two limits: the list tries the act _now_, which before the opening is always too early — it does not try the act at the opening — and an `AFTER date` is not worked out by the list before the contract has looked at an event, so until then such an obligation is named as one whose deadline is not known there (after an event it is dated like any other).

## See Also

- **[WITHIN](README.md#within-temporal-deadline)** — the closing edge, and the anchor vocabulary both edges use
- **[LEST](README.md#lest-breach-consequence)** — when the next clock starts
- **[EVERY](EVERY.md)** — windows under a join
