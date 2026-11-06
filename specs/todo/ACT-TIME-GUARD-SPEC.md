# Act-time guards and business-day deadlines

**Status: draft (2026-10-24).**
The function names are ruled (card CAL, 2026-10-24, §7).
What is built is a library (`jl4-core/libraries/calendar.l4`), two fixtures, a doc page and this spec, on branch `lang/act-time-guard`, draft PR legalese/l4-ide#744 into `unstable`.
It was stacked on `lang/lifecycle-values` (#743) until #743 merged into `unstable` on 2026-10-25 as `047311f36`.
No Haskell changed.
Everything marked "assumed, not ruled" is a build decision that can be reverted alone.

## 1. The question

A clause that mentions business days or public holidays can mean one of two things, and they need different machinery.

**(a) The act must happen on a business day.**
"Service shall not be effected on a Sunday or a public holiday."
"The payment must be made on a business day."
This is a condition on the act: an act on the wrong day does not count (a `MUST`), or is the violation (a `SHANT`).
It needs the time of the act being judged.

**(b) The deadline moves to a business day.**
"Within five days; if the fifth day falls on a Saturday, Sunday or public holiday, the next business day."
"Not later than the third business day following the close of the comment period."
This is arithmetic on the deadline.
It needs a calendar and a day to start from, and nothing about the act.

A third family, **(c) deemed and counted days** ("deemed given on the business day after posting", "within five business days of receipt"), is (b) with a different starting day and a business-day count instead of a roll.

The two readings compose: "serve on a business day, within ten days, the period running to a business day" is (a) on the act and (b) on the deadline.
They do not substitute for each other.
A guard on the act does not move the deadline: if ten days end on a Saturday, the guard refuses the Saturday act and Monday is late (fixture §2, third trace, BREACHED).

## 2. Evidence

**Corpus.** `EVERY-EACH-WINDOW-CORPUS-EVIDENCE-2026-09-16.md` §5 counts day-counting conventions over 1,520 sampled hits per register.
"Weekend / holiday / period rollover" is 22 in contracts and 16 in legislation; business-, working-, trading- or banking-day units are 242 and 83.
Two independent re-reads of the 3,040 sampled contexts (single labeller each, made for the design competition that produced this brief, not re-run here) found 26 and 44 holiday mentions respectively and **no** case of reading (a).
The weight is on rollover, deemed-given clauses, business-day offsets and counting exclusions, all of which are reading (b) or (c).
The limit is real and is the instrument's: that corpus samples **deadline phrases**, so it cannot see a stand-alone prohibition such as "no service on a Sunday" or Sunday-trading rules.
Reading (a) is **unmeasured**, not absent.

**Ruling B6 already puts the calendar in a library.** `EVERY-EACH-QUANTIFIER-SPEC.md` §2.6, card B6 (2026-09-21): months, business days and holidays are the library's.
`doc/reference/regulative/consequences.md`, "Counting days": business days and public holidays "are calendar questions, and the calendar belongs to a library rather than to `WITHIN`: compute the day with the date library and anchor on it".

**Reading (b) needs no compiler work.** The anchor slot already takes an expression (`WITHIN 0 OF <expr>`, §5.1.3 W3).
Measured 2026-10-24: `jl4/examples/ok/calendar-rollover.l4` (one assertion, 20 traces) gives the same 21 results, line for line, on this branch's `l4` and on an older installed `l4` (`~/.local/bin/l4`, a `dev` build linked 2026-09-28, commit not recorded), and that older `l4` also runs all 47 checks of `calendar.l4` (`calendar.l4` beside the fixture, no `JL4_LIBRARY_PATH`).
So the library and that fixture do not depend on B1.

**Reading (a) is writable today, as an idiom that is already house style.** The act carries its own day as a field and `PROVIDED` reads it: `jl4/examples/legal/ceo-performance-award.l4` (`MUST vest earned shares tranche no date PROVIDED … date AT LEAST vesting date`) and `jl4/examples/legal/ny-environmental-7.3.l4`.
A `PROVIDED` that is false passes the act over for every modal alike: `jl4-core/src/L4/EvaluateLazy/Machine.hs`, the `ValBool False` branch of the guard (lines 2943-2950 on this branch), logs `GuardFailed` only when the deontic log is on and then calls `tryNextEvent`.
So the `MUST` case ("does not count") and the `SHANT` case ("forbidden only off business days") are one mechanism (fixture §2 and §5).

**There was no library to do (b), and a shipped encoding shows the cost.** `jl4/examples/canon/us/regcf/cleanroom/regcf-denovo.l4:350` defines `` `five business days` MEANS 5 ``, and `jl4/examples/canon/us/regcf/regcf-wizard.l4:576` says, in a string, that "where a weekend or a holiday falls inside the window, the true business-day deadline is later than the count used here".
`regcf-denovo.l4:444` writes its own weekend-only `business days after`.
`jl4-core/libraries/excel-date.l4` has `ExcelWorkday` and `ExcelNetworkDays` (weekends plus a holiday list, no roll conventions, no calendar argument); measured 2026-10-24, `ExcelNetworkDays` counts both ends (Monday to Monday is 1) and `ExcelWorkday` with 0 days returns a Saturday unchanged.
`jl4-core/libraries/actus-core.l4:185` declares a `Business Day Convention` of its own (`SCR`, `SCRF`, `SCRP`, `SCRMF`, `SCRMP`) and implements none of it.
Those are not the ACTUS codes: checked 2026-10-25 against `actusfrf/actus-dictionary` version 1.4 (term `businessDayConvention`), ACTUS names nine conventions (`NOS`, `SCF`, `SCMF`, `CSF`, `CSMF`, `SCP`, `SCMP`, `CSP`, `CSMP`), keeping shift-then-calculate apart from calculate-then-shift, and the dictionary prints `SCMP` twice (the second is Calculate-Shift Modified-Preceding).

## 3. Design

**Reading (b): a calendar library plus the existing anchor slot.**
`jl4-core/libraries/calendar.l4`, built (§6).

- A **calendar** is a `FUNCTION FROM NUMBER TO BOOLEAN`, `TRUE` meaning "is a business day" (assumed, not ruled).
  Positive polarity keeps guards free of `NOT`; a holiday list is a one-line wrapper over `elem`.
  Calendars compose by `AND`: a day is a business day at two places only if both are open, which is the shape of BGB § 193 (it rolls a day that is a holiday at the place of declaration _or_ the place of performance).
  An earlier draft of the library header said `OR` for that; the polarity was wrong, because a calendar is a business-day predicate and § 193 is stated over holidays (review, 2026-10-24).
- Every function takes the calendar first and a day as a **day number** (days from 1 January 0000, as `DATE_SERIAL` computes: 740283 for Friday 30 October 2026), the scale `WITHIN` and a `#TRACE … AT` on dates compare on; each roll function has a `DATE` twin.
  The shipped helpers `weekdays only` and `weekdays except` fix the weekend at Saturday and Sunday; a Friday–Saturday weekend needs a hand-written calendar, and `doc/reference/libraries/calendar-example.l4` has one.
- **The scale is not Excel's, and nothing refuses a number from the wrong one.**
  Measured 2026-10-24: `DATE_SERIAL (YMD 2026 10 30)` is 740283, `excelSerial1900 (YMD 2026 10 30)` is 46325, and the difference is 693958 for 1 March 1900 and for 1 January 2000 as well (693959 for 28 February 1900, Excel's invented leap day).
  693958 leaves 6 when divided by 7, so an Excel serial read as a day number gives a weekday one day late: `is weekday` of Excel's Friday is `FALSE` and `Weekday of` gives 6, Saturday; Excel's Monday 2 November reads as a Tuesday.
  46325 is above 365, so the floating-trace refusal never fires.
  The header of `calendar.l4` and the doc page name the scale and say to add 693958 or use the `DATE` forms.
  **A guard that would catch it, proposed and not built:** refuse below 693,960, the day number of 1 January 1900, which refuses every Excel serial of a date before about the year 3800.
  Its cost is that it also refuses every genuine L4 date before 1 January 1900.
  Refusing a floating trace that reaches day 365 or more is a benefit and not a cost, since the 365 test leaves that gap open today.
  So the trade is one silent wrong answer (an Excel serial read a day late) against a loud refusal of dates before 1900, and it is Meng's.
- **L4 has no partial application** (measured: `` `weekdays except` holidays `` with a two-input definition is the check error "expects 2 inputs, but here it is given 1 input").
  So `` `weekdays except` `` takes the list and _returns_ the calendar (`GIVEN d YIELD …`), and `` `weekdays except` holidays `` is a whole calendar.
  The `DATE`-list twin is `` `weekdays except the dates` ``, a distinct name, so that `` `weekdays except` EMPTY `` is not ambiguous (assumed, not ruled).
- Honesty guards (assumed, not ruled):
  - every entry point refuses a day number below 365, which is a floating `AT 0` trace and not a calendar date (on the `YMD` pattern, `daydate.l4`'s `` `YMD refused an out-of-range month or day` ``, a named `REFUSE`).
    **`is a business day` forces the check itself** (`day AT LEAST 365 AND calendar day`): the review of 2026-10-24 found that a calendar ignoring its input (`GIVEN d YIELD TRUE`) answered `TRUE` at day number 5, because nothing ever asked for the checked day.
    The other entry points return or compare the checked day, so a refusal reaches the caller; the edge is pinned at 364 refused and 365 accepted on two entry points, with calendars that say `TRUE` for everything;
  - each search refuses after 366 consecutive non-business days, so an all-`FALSE` calendar stops (measured: a calendar of `FALSE` gives "calendar found no business day within 366 days"); the bound is exact, pinned in `calendar.l4`: a lone business day 365 days away is found and one 366 days away is refused, in both directions, and for `` `add business days` `` by one (which starts a day later than `` `next business day on or after` ``) 366 found and 367 refused;
  - a fractional day number is floored, and so is each entry of a holiday list given to `` `weekdays except` `` (a holiday stated at noon is still that holiday; before 2026-10-24 it was silently ignored); `` `add business days` `` refuses a negative or fractional count; `` `business days between` `` refuses a span that ends before it starts;
  - the count recursion stops at `n AT MOST 0`, not `n EQUALS 0`, so a negative or fractional count that got past its guard would return a day and fail an assertion at once instead of recursing until the timeout (the 47-assertion version did loop: the reviewer's mutants that removed those guards hit the timeout);
  - counts are not bounded the way searches are: measured 2026-10-24, `` `add business days` `` works at a count of 50,000 and stops with "Stack overflow: Recursion depth of 1000000 exceeded" at 70,000, and `` `business days between` `` works over 200,000 days and overflows over 500,000.
    Loud, not silent; stated on the doc page's Limits and not changed;
  - `` `modified following business day` `` compares the year as well as the month of the rolled day, so a roll that lands in the same month number a year on goes back instead of forward.
- `` `business days between` `` excludes the first day and includes the last, the counting rule `WITHIN` uses (consequences.md "Counting days"), so it inverts `` `add business days` ``; it is **not** `ExcelNetworkDays`, which counts both ends, and its `@desc` says so (assumed, not ruled).
  The brief called it "NETWORKDAYS-style"; this is the one deliberate departure, because a count that does not invert `` `add business days` `` would make `WITHIN`-style deadlines off by one.
- `` `add business days` `` with n = 0 returns the day unchanged, rolled or not (assumed, not ruled; `ExcelWorkday` in `excel-date.l4` does the same, measured).
- No jurisdiction's holidays ship with it.
  Holiday data has its own provenance and goes one module per jurisdiction on the template of `jl4/examples/ok/closing-the-loop/feiertage.l4`, whose `gesichert` predicate is the honest pattern for a table that runs out.

**Reading (a): deferred, with a written trigger.**
No act-time noun or binder is built.
The documented form is the act-carried day under `PROVIDED` (fixture §2, §3, §5, §6).
The trigger for revisiting is §5.

**THE JOIN, now that B1 is built in part.**
`THE JOIN`, `THE DEADLINE` and `THE ARMING` are values on `unstable` since #743 merged (`047311f36`, 2026-10-25; B1 built in part 2026-10-24).
So reading (b) can count from the previous act's own stamp instead of a day the act carries: ``WITHIN 0 OF (`next business day on or after` `weekdays only` (THE JOIN PLUS 5))`` (`jl4/examples/ok/calendar-rollover-join.l4` §1, FULFILLED on Monday, BREACHED on Tuesday).
That fixture is kept in its own file and commit so the library and the main fixture do not depend on B1 (measured 2026-10-24: the older `l4` rejects it, "unexpected (" at the bracket that opens `(THE JOIN PLUS 5)`).
It also pins the trap that `THE JOIN` in a continuation's `PROVIDED` is the **previous** act (§3 of that file: notice Friday, payment Saturday, FULFILLED), already taught in consequences.md, "The anchor words as values", third bullet.
`THE JOIN` does not serve reading (a): there is no noun for the act under test.

## 4. Grafted from the rejected binder design

The competing design was an act-time binder or noun under `PROVIDED`.
It lost on evidence (zero measured demand for (a); it collides with B1; it changes how valid programs parse; it owes a scoping rework), and four of its findings are kept:

1. **The act's own day can disagree with its `AT` stamp, and nothing reports it (its probe p10).**
   With the act-carried-day idiom, `PARTY Landlord DOES serve <Monday> AT <Saturday>` is judged on the Monday it carries and counts.
   Pinned as a known silent wrong answer: `calendar-rollover.l4` §4, FULFILLED.
   This is the standing case for a later act-time binder or `THE ACT`; only such a construct closes it.
2. **Two pre-existing crashes, to be filed upstream regardless of this design (its probes p9 and p5).**
   A kept `SHANT`'s `HENCE`, and a barrier's `HENCE`, that name a pattern binder of the action pass `l4 check` and fail at run time with "Internal error: d is not in scope. Please report this as a bug."
   p9 reproduced 2026-10-24 on `lang/act-time-guard`: a `SHANT deliver d WITHIN 5 HENCE … WITHIN 0 OF (d PLUS 10)` with no delivery checks with exit 0 and runs with exit 1 and that message.
   p5 not reproduced here; it rests on that design's probe.
   The root is grep-confirmed: `jl4-core/src/L4/TypeCheck.hs` `checkDeontonBody` (line 3189 on this branch) checks `hence` under `extendKnownMany boundByPattern` for every modal, and a kept `SHANT` reaches its `HENCE` with no act, so nothing binds `d`.
   **Not filed in this sitting** (the brief forbids filing issues); owed.
3. **A bare `AT name` binder would swallow the `#CONTRACT … AT start` head.**
   `jl4-core/src/L4/Parser.hs:825-832` parses `#CONTRACT expr [STARTING] AT expr WITH`, and the first `expr` is a `singleLineExpr`, so an `AT name` suffix on an action inside a contract expression is ambiguous with the directive's own `AT`.
   A precondition for any future `AT name` binder: guard the directive head (an Env flag, or a distinct keyword).
4. **`THE JOIN` in a continuation's `PROVIDED` is the previous act.** On the doc page (`doc/reference/libraries/calendar.md`, "Counting from the act itself") and pinned in `calendar-rollover-join.l4` §3.

## 5. Reading (a): deferred, and when to revisit

**Trigger.** Build an act-time noun or binder when **two independent encodings** need reading (a) and the act-carried day is unacceptable for them (for instance because the day arrives only as the event's stamp), and rule its spelling on a bench.
Preconditions recorded for that build: §4 point 3 (the directive head), and the scoping rework that §4 point 2 already owes.

**Open, for a ruling, not part of this design.** Should a guard failure produce a run-time note?
Today an act refused by `PROVIDED` is silent in `l4 run`: measured, no line of `l4 run calendar-rollover.l4` mentions it, while `l4 lts --steps` prints "the act matched but its condition did not hold; passed over" (`jl4-core/src/L4/Lts/List.hs:580`).
An early act under `AFTER` does get a note (R-X6).
A party who acts on a holiday and believes it counted gets exit 0.
A note would move trace goldens and be noisy for ordinary guards; it is a separate decision.

## 6. What is built

On `lang/act-time-guard` (stacked on `lang/lifecycle-values` @ `8ff21007d` until #743 landed, with `unstable` at `047311f36` merged in since), in separate commits so each can be reverted alone:

| piece             | path                                                                                                                                                                     | proof it is load-bearing                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| library           | `jl4-core/libraries/calendar.l4`, four goldens in `jl4-core/libraries/tests/calendar.*`, README row                                                                      | 73 `#ASSERT`s: each convention both ways; a fractional day number at every entry point (including 0.9, which rounding to nearest would send to the next day) and a holiday given at noon; a day number below 365 refused at every entry point; the 364/365 edge on two entry points; each `DATE` twin on a day where it differs from its nearest sibling, so swapping a twin for that sibling fails; the four named refusals as `#ASSERT REFUSED … BECAUSE`; the search bound at its edge in both directions, and 366 found and 367 refused for `add business days` by one. Run by hand 2026-10-25, after the ruling dropped the separate "strictly after" function, one mutation at a time on a copy: 48 mutations, 47 killed, each by between one and eleven assertions and none by a timeout. They are: strict on-or-after, an `add business days` whose step rolls on-or-after instead of moving past the day, preceding that searches forward, modified-following that never goes back or ignores the year or the month, holidays ignored, a holiday list not floored, the DATE-list wrapper ignoring its list, the forward and backward bounds at 365, 367 and tested after the look, the searches of `previous`, `on or after` and the `add` step starting their count at 1 (and the `add` step at -1), an off-by-one and an extra step in `add business days`, n = 0 that rolls, `between` counting both ends, the rounding removed, the 365 guard removed or moved to 364 or 366, `is a business day` not forcing the check or forcing at 366, the day not rounded or checked in `previous`, `on or after` and `add`, `between` with either end or both unrounded or its comparison unchecked, the negative-count, fractional-count and span guards removed, and eight mutations of the DATE twins. The one survivor is equivalent: `modified following business day` rounds and checks its day once at the top, and its two callees round and check it again, so removing the top call changes no answer (identical results on fractional, month-end and below-365 probes, and 0 mismatches in the oracle comparison below). It is kept as a second line of defence |
| fixture, B1-free  | `jl4/examples/ok/calendar-rollover.l4`, four goldens                                                                                                                     | one assertion and 20 traces. Run by hand on copies: removing the roll in §1 flips the rolled-Monday payment to BREACHED; removing the guard in §2 flips the Saturday-only service and the "guard does not move the deadline" trace to FULFILLED; removing the roll in §3 flips the composed trace to BREACHED; removing the `SHANT` guard in §5 flips the Friday delivery to BREACHED; removing the guard in §6 flips the holiday-only lodging trace to FULFILLED; ignoring the holiday list in §7 and a non-strict deemed receipt in §8 each flip their traces; the strict-roll library mutation flips §1's "Wed 4 Nov is late" to FULFILLED                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| fixture, needs B1 | `jl4/examples/ok/calendar-rollover-join.l4`, four goldens                                                                                                                | parse error ("unexpected (", at the bracket before `THE JOIN`) on an `l4` without B1, measured on the 2026-09-28 `dev` build                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| doc               | `doc/reference/libraries/calendar.md` and `calendar-example.l4`; linked from `doc/SUMMARY.md`, the libraries index, and the B6 bullet in consequences.md "Counting days" | `doc/test-docs.sh` type-checks the example                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| spec              | this file; a dated note in `EVERY-EACH-QUANTIFIER-SPEC.md` §2.6                                                                                                          | —                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |

The library was also compared, function by function, with an independent weekday oracle over every day of 2026 and 2027, for `weekdays only` and for a calendar with 17 holidays chosen to sit on month ends and next to each other (32 query families, no disagreement; run again after the review's fixes, 2026-10-24: 0 mismatches).
That script is not kept in the tree.

The fixtures cover: a deadline rolling to the next business day (§1, and over a listed holiday in §7); "provided not a public holiday" with a `GIVEN` list of holiday dates on a date-serial trace (§6); reading (a) with its "guard does not move the deadline" case (§2); (a) and (b) composed (§3); the p10 silent case (§4); a `SHANT` off business days (§5); deemed receipt (§8).

**Not built, named so they are not lost.**
The upstream issues for p9 and p5 (§4 point 2).
The Reg CF `` `five business days` MEANS 5 `` fix, which lands in `legalese/commons` first and then `etc/sync-canon.mjs --bump`; this library deliberately does not reuse the name `` `business days after` `` that `regcf-denovo.l4:444` defines.
Jurisdiction holiday modules.
Wiring actus-core's `Business Day Convention` to these functions.

## 7. The names: ruled

CAL: option A as revised (plain-English roll names: next business day on or after, previous business day on or before, modified following business day, add business days, business days between; calendars weekdays only, weekdays except; next business day after dropped; no aliases; library opens as a draft PR stacked on #743). Meng's note: "I’m minded to accept the recommendation but also write ACTUS and ISDA AND FpML compatibility libraries to match exactly their definitions. When we need to borrow from their usages we would have the libs already in place, and we could have a note in our writing l4 skill showing how to reuse these libs. Further it seems like the same shape as an encoding of a rule from a jurisdiction that has an Interpretation Act that we encode first and then make available as a library for importing." Ruled 2026-10-24, bench https://claude.ai/artifact/PgiYUak5fBxjUJ1dd3FZ2F (collection l4-event-time-1024).

**What was asked, kept so that the reasoning stays with the ruling.**
Every encoding that uses the roll functions carries their names, and the bare English word "following" means something different from the ISDA term.

- **(A) Plain English that says whether the day itself counts:**
  `next business day on or after` (= ISDA Following), `previous business day on or before` (= Preceding), `modified following business day` kept as the one term of art, plus `add business days` and `business days between`.
  The first draft also had a separate function for "strictly after"; the ruling dropped it, because `add business days` by one is exactly that.
- **(B) ISDA/FpML vocabulary:** `following business day`, `modified following business day`, `preceding business day`, `modified preceding business day`, plus `add business days`.
  It matches finance drafting and the vocabulary of ACTUS's own conventions (`SCF`, `CSF`, `SCMF`, `CSMF`), but a reader who takes "the following business day" in its English sense gets an answer one business day off on every day that is already a business day, with exit 0.
  The corpus's own offset clauses use the English sense ("not later than the following Business Day", 7 hits in the competing design's count).

No aliases in either option: two names for one function doubles what a reader has to learn.
The recommendation was A.
Measured: the fixture's §1 "Wed 4 Nov is late" trace turns FULFILLED when on-or-after is made strict, which is exactly the misreading B invites.

**Not built, on purpose:** the ACTUS, ISDA and FpML compatibility libraries that Meng's note proposes.
They are to be discussed first; this library does not wire up actus-core's `Business Day Convention` either.
Placement ruled: such standards libraries live in `legalese/commons`, not in `jl4-core/libraries`. Meng, in chat 2026-10-25: "I’d rather put the standards in commons tbh. Wanna keep the core library small." Building them is not yet ruled.
The first thing such a library would have to settle is the mismatch recorded in §2: actus-core's five codes are not ACTUS's nine.

Still assumed, not ruled: the calendar as a positive `NUMBER`-to-`BOOLEAN` function; the refusal below day number 365; the 366-day search bound; `business days between` excluding the first day; reading (a) deferred until two encodings need it.

## 8. Retention

The ruling is recorded in §7 in one line, and the note in `EVERY-EACH-QUANTIFIER-SPEC.md` §2.6 says so.
Keep the file after discharge: the fixtures and the library header cite its section numbers.
The deferral note in `EVERY-EACH-QUANTIFIER-SPEC.md` §2.6 repeats §5's trigger and the open question: change them together.
