# calendar

Business days, public holidays, and deadlines that move when they land on a day the office is shut.
Import it with `IMPORT calendar`, together with `IMPORT daydate` if you build dates with `YMD` or `Date`.

**Status: proposed, not ruled (24 October 2026).**
The function names on this page may change before the library is released.

**The names are assumed, not ruled.**
This page uses option A: plain English that says whether the day itself counts, as in `next business day on or after`.
Option B is the finance vocabulary of the ISDA definitions, which ACTUS also uses: `following business day`, `preceding business day`, `modified preceding business day`.
It matches how banks draft, but a reader who takes "the following business day" in its ordinary English sense, strictly after the day, gets an answer one business day off whenever the day is already a business day, and nothing says so.
Option A is the recommendation.
The question is recorded in `specs/todo/ACT-TIME-GUARD-SPEC.md`, section 7.

**Example:** [calendar-example.l4](calendar-example.l4)

## What a business-day convention is

Contracts and statutes often count in business days, or say what happens when a day falls on a weekend or a public holiday.
"Payment is due within five days; if the fifth day is not a business day, on the next business day."
"A notice sent by post is deemed received on the second business day after posting."
"Service may not be effected on a Sunday."

L4's `WITHIN` counts plain days on the trace's clock.
It knows nothing about weekends or holidays, by design: which days count is a question about a calendar, and calendars differ by country, by city and by market.
So you work out the day with this library and anchor the deadline on it, as the page on [deadlines](../regulative/consequences.md#counting-days) says.

Banks and lawyers have names for the usual ways of moving a day, called **business-day conventions**.
"Following" moves a day that is not a business day forward to the next one, and leaves a business day alone.
"Preceding" moves it back.
"Modified Following" moves it forward unless that would cross into the next month, and then moves it back instead.

## Days and calendars

Every function works on days as **date serials**: the number `DATE_SERIAL` gives for a date, which is also the number a trace on dates is stamped with (`#TRACE … AT (DATE_SERIAL (YMD 2026 10 26))`).
Each function that gives back a day also has a form that takes and gives a `DATE`.

A **calendar** says which days are business days.
It is a function from a day to `TRUE` (a business day) or `FALSE` (not one).

| Calendar                          | Business days                                                 |
| --------------------------------- | ------------------------------------------------------------- |
| `weekdays only`                   | Monday to Friday                                              |
| `weekdays except` days            | Monday to Friday, except the listed days (a `LIST OF NUMBER`) |
| `weekdays except the dates` dates | Monday to Friday, except the listed dates (a `LIST OF DATE`)  |
| your own                          | whatever it says                                              |

To write your own, give it one input, the day, say that it is a number, and say when it is a business day:

```l4
GIVEN d IS A NUMBER
GIVETH A BOOLEAN
`our calendar` d MEANS
    `is a business day` (`weekdays except the dates` (LIST YMD 2026 12 25, YMD 2026 12 26)) d
```

Name your calendar as a function with a declared `GIVEN d IS A NUMBER`, as above.
A calendar written inline as `GIVEN d YIELD …` works when it is passed straight to a function of this library, but one that is named on its own and calls an overloaded function such as `is weekday` is rejected as ambiguous: `is weekday` has a form for numbers and a form for dates, and nothing says which you mean.

No public holidays come with the library.
Holidays are data with their own source, and they change; a jurisdiction's holidays belong in a module of their own.
[`feiertage.l4`](https://github.com/legalese/l4-ide/blob/unstable/jl4/examples/ok/closing-the-loop/feiertage.l4) in the examples shows one for Germany, which computes the movable feasts and says when it is asked about a year it does not cover.

## Functions

| Function                                          | Gives   | What it does                                                                                                                  |
| ------------------------------------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `is a business day` calendar day                  | BOOLEAN | `TRUE` when the day is a business day on the calendar                                                                         |
| `next business day on or after` calendar day      | day     | The day itself if it is a business day, otherwise the next one. This is the "Following" convention.                           |
| `next business day after` calendar day            | day     | The first business day strictly after the day, even when the day itself is a business day                                     |
| `previous business day on or before` calendar day | day     | The day itself if it is a business day, otherwise the last one before it. This is the "Preceding" convention.                 |
| `modified following business day` calendar day    | day     | "Modified Following": as `next business day on or after`, unless that leaves the month, and then the last business day before |
| `add business days` calendar n day                | day     | The n-th business day after the day. The day itself is not counted. With n = 0 the day comes back unchanged.                  |
| `business days between` calendar first last       | NUMBER  | How many business days come after the first day and on or before the last                                                     |

**"Following" is not "the following business day".**
In ordinary English, "the following business day" is the day after: a notice sent on a Monday is received on "the following business day", Tuesday.
The "Following" convention leaves a Monday where it is.
That is why the two are named `next business day after` and `next business day on or after`.
Choose by asking whether the day itself can be the answer.

`business days between` counts the way `WITHIN` does: the day you count from is not counted, and the last day is.
So `business days between` cal d (`add business days` cal n d) is n.
Excel's `NETWORKDAYS` (in [excel-date](excel-date.md)) counts both ends, and so gives one more when the first day is a business day.

## Three kinds of business-day clause

| The clause says                                  | What serves it                                                          |
| ------------------------------------------------ | ----------------------------------------------------------------------- |
| (1) the deadline moves to a business day         | `next business day on or after` in the `OF` anchor of `WITHIN`          |
| (2) the act must happen on a business day        | `is a business day` in a `PROVIDED` (or `NOT` of it, for a prohibition) |
| (3) a day is deemed, or counted in business days | `next business day after`, `add business days`, `business days between` |

**(1) The deadline moves.** "Within five days; if the fifth day is not a business day, the next business day."
Roll the day and anchor on it:

```l4
PARTY Seller MUST notify d WITHIN 10
HENCE PARTY Buyer MUST pay WITHIN 0 OF (`next business day on or after` `weekdays only` (d PLUS 5))
```

Here the notice carries its own day, `d`.

**(2) The act must happen on a business day.** "Service shall be effected on a business day."
That is a condition on the act, so it is a [`PROVIDED`](../regulative/consequences.md#provided):

```l4
PARTY Landlord MUST serve d PROVIDED `is a business day` `weekdays only` d
WITHIN 10
```

A Saturday service does not count, and the next event is tried.
The act carries its day here too, because a `PROVIDED` cannot read the time an act is stamped `AT`.

**The guard does not move the deadline.**
If the ten days end on a Saturday, the guard refuses the Saturday service and the deadline still passes that Saturday: a service on Monday is late.
If the clause means "on a business day, and the period runs to a business day", write both, so the last day of the window is a day on which the act can be done:

```l4
GIVEN start IS A NUMBER
GIVETH A DEONTIC Party Action
`serve within ten days` start MEANS
    PARTY Landlord MUST serve d PROVIDED `is a business day` `weekdays only` d
    WITHIN 0 OF (`next business day on or after` `weekdays only` (start PLUS 10))
```

A prohibition works the same way: ``SHANT deliver d PROVIDED NOT (`is a business day` `weekdays only` d)`` forbids delivery only on a day that is not a business day.

**(3) A day is deemed, or counted in business days.** "Deemed received on the business day after sending; reply within three business days of receipt":

```l4
PARTY Tenant MUST `send notice` d WITHIN 30
HENCE PARTY Landlord MUST reply
      WITHIN 0 OF (`add business days` `weekdays only` 3 (`next business day after` `weekdays only` d))
```

### Counting from the act itself, without carrying a day

**After B1 lands.**
Where the anchor words are [values](../regulative/consequences.md#the-anchor-words-as-values), the notice need not carry its day: `THE JOIN` is the time it was given.
That is ruling B1 of the `EVERY` bench, built on the branch `lang/lifecycle-values` and not yet merged to `unstable`, so the block below is not yet something an installed `l4` accepts.

```
PARTY Seller MUST notify WITHIN 10
HENCE PARTY Buyer MUST pay WITHIN 0 OF (`next business day on or after` `weekdays only` (THE JOIN PLUS 5))
```

On an `l4` built before B1, the bracket that opens `(THE JOIN PLUS 5)` is a parse error; there, carry the day in the notice, as in the first example.

**`THE JOIN` inside the next obligation's `PROVIDED` is the previous act.**
``HENCE PARTY Buyer MUST pay PROVIDED `is a business day` `weekdays only` THE JOIN`` reads as "the payment must be made on a business day", and what it tests is the day of the notice.
A notice on Friday and a payment on Saturday passes it.
No word names the time of the act being tested, so to guard the payment's own day the payment has to carry it.

## Limits

These are the places where the library, or the way it is used, can give a wrong answer without saying so.

- **An act refused by a business-day guard leaves no trace in `l4 run`.** It is passed over like any act whose `PROVIDED` is false. A party who acted on a holiday and believes it counted sees no message. [`l4 lts --steps`](../regulative/lts-list.md) does list it: _the act matched but its condition did not hold; passed over_.
- **The day an act carries is not checked against the time it is stamped.** `PARTY Landlord DOES serve <Monday> AT <Saturday>` is judged on the Monday it carries, and counts.
- **A holiday list that runs out answers silently.** A calendar says `TRUE` or `FALSE` for every day, so a list for 2026 calls every weekday of 2027 a business day. A holiday module should say which years it covers, as `feiertage.l4` does.
- **A day is just a number.** The library refuses a day below 365, which is what a trace that starts `AT 0` produces and is not a calendar date. It cannot tell a date serial from a count of days since the contract began, if that count happens to be large.
- **Times of day are not covered.** A fractional day is rounded down to its day, so "by 5 p.m. on the business day" cannot be written with this library.
- **A calendar that has no business days is refused** after 366 days in a row with none, rather than searched for ever.
- **Exports.** A rolled deadline is an anchored `WITHIN`. The BPMN export draws it as a conditional event with a warning, not a timer, and the MLIR/WASM export refuses it: see [what the exports do with an anchor](../regulative/consequences.md#what-the-exports-do-with-an-anchor).
