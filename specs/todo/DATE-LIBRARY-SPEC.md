# Date library — cross-backend requirements ledger

_Status: **requirements ledger, no implementation.** Opened 2026-08-18 by ruling R8 of
`BLAWX-EXPORT-SPEC.md`. This document does not design a library; it records, in one place, the
date/duration requirements that each transpiler backend has emanated, so that an eventual shared
date library (and the lowering support beneath it) is designed against the full set rather than
against whichever backend shipped last. Add a subsection when your backend discovers a
requirement; do not silently satisfy it locally without recording it here._

## 1. Why a ledger

Every backend so far has re-derived date handling independently, and the divergences are
semantic, not cosmetic: the same L4 expression can mean three different calendar days in three
targets. The witnesses below are all verified in their owning specs; this file cites, it does
not re-argue.

## 2. What L4 itself provides today

Verified at `afcef88f` (`jl4-core/libraries/daydate.l4`):

- Serial-day arithmetic (`DATE_SERIAL`/`DATE_FROM_SERIAL`) over proleptic Gregorian dates.
- **`Date d m y` is the lenient, rolling constructor** — `Date 31 2 y` rolls forward (Feb 31 →
  Mar 3); date arithmetic idioms rely on this (`Date 1 (month PLUS 6) year`).
- **`YMD y m d` refuses** out-of-range components via a deliberate `ASSUME` bottom
  (`` `YMD refused an out-of-range month or day` ``).
- No first-class duration type: durations are `NUMBER`s of days.
- The Excel compatibility layer (`excel-date.l4`, see `EXCEL-DATE-COMPAT-SPEC.md`) adds
  1900/1904 serials, `DATEDIF`, `YEARFRAC`, workday/holiday logic — on top of daydate, in L4.
- Recent breaking change: the four `EVAL` pins take `DATE`, not a serial `NUMBER`
  (commit `c57ca4df`) — backends that consumed serials at that boundary must follow.

## 3. Requirements by consumer

### 3.1 Blawx / s(CASP) (`BLAWX-EXPORT-SPEC.md` R8, verified `02eded1`)

- Target represents dates as **functor-wrapped POSIX seconds**: `date(N)`, `datetime(N)`,
  `time(secs-since-midnight)`, `duration(seconds)`.
- **Integers only**: the target's own fact-scenario path emits floats
  (`str(datetime.timestamp())`) which do not structurally unify with block-emitted integers —
  the bridge must render integer timestamps, convention: **UTC midnight**.
- Durations are day/hour/minute/second-granular seconds counts — **no calendar month/year
  components exist** in the target.
- A whole family of target date builtins is broken at HEAD and must be avoided (named in the
  Blawx spec §2); only `date_compare/3`, `duration_compare/3`, `date_add/3` are load-bearing.
- Three timezone regimes coexist in the target (browser TZ, container TZ, server-stamp at
  import time) — the bridge must pick one rendering convention and document it.

### 3.2 Catala (`CATALA-EXPORT-SPEC.md` R3, verified `d37aca74`)

- Month/year arithmetic is **ambiguous by default and fatal** (`AbortOnRound`), with explicit
  per-scope `date round up/down` policies — neither of which equals daydate's roll-forward
  (Feb 31 ↦ refusal vs Mar 3 vs Feb 28 vs Mar 1 is a four-way divergence across the two
  languages' constructors and Catala's two policies).
- Durations are first-class with calendar components; day-granular arithmetic is never
  ambiguous — the Catala bridge emits day-granular forms exclusively.

Paper findings contributed by the catala-bridge session (2026-08-17), from Monat, Fromherz &
Merigoux, ESOP 2024 (arXiv 2403.08935 — the semantics Catala 1.x ships) and the
CUTECat/DateSAT verification lineage:

- Catala date+period arithmetic **aborts at runtime** (`AmbiguousDateComputation`) unless the
  scope declares `date round up|down`; abort is the deliberate default because choosing a
  rounding direction is itself a legal ruling deserving a citation. The bridge's
  lenient-`Date` helper (1 Jan + (m−1) months + (d−1) days) never rounds by construction, so
  PR #266 emits no rounding declarations; any future lowering of native month/year
  arithmetic must emit them, per scope, sourced from an L4-side annotation.
- The Monat semantics, adopted wholesale if L4 ever grows month/year addition: addition and
  rounding are **separate operators**; three modes (down = last day of month, up = first day
  of next month, abort) with abort default; year addition is defined as 12× month addition;
  composite periods round **once**, after years+months, before days; the rounding
  declaration attaches at scope/function level and carries a legal citation (Catala today is
  scope-level only; toplevel extension is CatalaLang/catala#431).
- **Non-commutativity/non-associativity are proved**, F★-mechanised, in the ESOP paper:
  Mar 31 + 1 day + 1 month ≠ + 1 month + 1 day, and + 1m + 1m ≠ + 2m (May 30 or Jun 1 vs
  May 31, mode-dependent). This is the proof behind portfolio invariant I9 and R-D8 below.
- **Symbolic tools cover calendar arithmetic poorly**: Monat et al. explicitly rejected SMT
  for date ambiguity (recursive + non-linear; they use abstract interpretation in Mopsa);
  CUTECat has no symbolic encoding for month/year date arithmetic and falls back to concrete
  evaluation silently, weakening exhaustiveness verdicts on date-heavy corpora. Day-granular
  dates as epoch integers ARE linear and SMT-safe. DateSAT (arXiv 2605.25180, 2026) is the
  adoption candidate for date/period constraints beyond that.

### 3.3 OpenFisca (`jl4/examples/openfisca/`, shipped)

- Period-based temporality: a conventional `period` GIVEN threaded to the engine's period
  argument; `definition_period` granularities; **dated formulas** select rule arms by date at
  the engine level (year/month arms, strictly descending — mis-ordering is rejected).

### 3.4 swipl / relational middle-end (`LOGIC-PROGRAMMING-BACKENDS-SPEC.md` §5.1)

- Proposes **Modified Julian Day integers** wrapped in a `date/1` functor (the DMN exporter
  already imports `toModifiedJulianDay` for the same purpose) — a _different_ integer basis
  from Blawx's POSIX seconds; both are serial encodings of the same civil date.

### 3.5 DMN / FEEL (`DMN-EXPORT-PROGRAM-MODEL-SPEC.md`; BNA smoke report)

- FEEL has typed `date("YYYY-MM-DD")` literals; the BNA corpus recorded a **YMD→FEEL date
  gap** (L4 date values reaching the exporter without a FEEL-typed rendering path).

### 3.6 Excel (`EXCEL-DATE-COMPAT-SPEC.md`, PARTIAL-shipped)

- 1900/1904 epoch serials including the 1900 leap-year bug; `DATEDIF`/`YEARFRAC`/workday
  functions encode accrual and deadline policy directly.

### 3.7 docassemble (`DOCASSEMBLE-EXPORT-SPEC.md` §8.12/R12; M4 = PR #268; contributed by the docassemble session 2026-08-18)

All findings below were executed against the L4 evaluator as oracle; the sweep sizes are
real, not estimates.

- **L4's three date constructors have three different out-of-range behaviours**, and a
  lowering must not flatten them onto one target constructor: `Date 29 2 2022` **rolls** to
  1 Mar 2022 (lenient); `DATE_FROM_DMY 29 2 2022` **refuses** ("produced an invalid date");
  `YMD 2022 2 29` **refuses** via its `ASSUME` bottom. The bridge keeps them
  distinguishable: `YMD` literals are bounds-checked at lower time; an all-literal
  `Date d m y` is rolled at compile time.
- **Anniversary/age arithmetic: L4 rolls, `dateutil.relativedelta` clamps, and the
  difference is a legal answer.** Sweep: every birth date 1970-01-01..2006-12-31, each
  tested on the L4 majority date and the day before — 13,514 dates, **27,028 comparisons**:

  | target idiom                       | disagreements with L4 | where                  |
  | ---------------------------------- | --------------------- | ---------------------- |
  | `date_difference(…).years >= 18`   | 6,629 (24.5%)         | on the birthday itself |
  | `born.plus(years=18) <= assessed`  | 9 (0.03%)             | leap-day births        |
  | `born <= assessed.minus(years=18)` | **0**                 | —                      |

  `date_difference(…).years` is elapsed days over 365.2425 as a **float** (docassemble
  `dates.py:482` at pin `1b6678384`): it returns 17.999 on the applicant's own eighteenth
  birthday — the one day the question is asked. Any target library exposing a `.years` on a
  duration is guilty until measured (R-D10). The witness is executable, not prose:
  `jl4/examples/docassemble/date_idiom_sweep.py` (PR #268, commit `46728d3f`) re-derives
  all four figures against real docassemble.base and exits non-zero on drift; its oracle is
  a Python model of L4's rolling `Date` — and because a model of an oracle is not an
  oracle, `--emit-oracle-l4` writes 1096 `#EVAL`s over every date where a convention could
  differ, checked by `l4 run`: 1096 TRUE, 0 FALSE. Re-run it before believing it.

- **The shipped lowering is not the literal backward form.** `.plus()`/`.minus()` are not
  interchangeable (`.plus()` clamps 2004-02-29 + 18y to 2022-02-28 where L4 rolls to
  2022-03-01). The bridge emits an anniversary as a shift from the **first of the month**:
  `born.minus(days=born.day-1).plus(years=18).plus(days=born.day-1)` — exact for the same
  reason the backward inequality is (no month lacks a first, so no clamp can fire), but it
  preserves the named binding the lawyer wrote: `the eighteenth birthday` stays a rule with
  a name instead of dissolving into an inequality that appears nowhere in the source. This
  generalises as R-D11.
- **Fractional calendar durations occur in the corpus**: `years after` with `n = 7.5` in
  `jl4/examples/legal/ceo-performance-award.l4`. Calendar-exact anniversary arithmetic has
  no answer for half a year; the bridge refuses. Needs a ledger ruling (§5).
- Refused by name in the bridge's v1, each a candidate ledger row: `Day`, `Date to days`,
  `the week after`, `the date that many years earlier`, `DATE_FROM_DMY`, `DATE_SERIAL`,
  `DATE_FROM_SERIAL`, `DATEVALUE`, `TODAY`, and all of `DATETIME`/`TIME`/`TIMEZONE`.
  (`DATE_FROM_DMY` appears both here and in the constructor bullet above — different layers:
  that bullet describes the L4 evaluator's semantics, this list is what the docassemble
  backend declines to lower.)
- Component extraction is the easy case: `DATE_YEAR`/`DATE_MONTH`/`DATE_DAY` →
  `.year`/`.month`/`.day`, no convention hazard.
- Process notes, generalised as R-D12/R-D13: date-builtin recognition is by name and tried
  only **after** in-module bindings, so a module defining its own `Date` shadows the builtin
  surface rather than colliding with it; and the bridge's CLI test asserts the strings
  `date_difference` and `365.2425` appear **nowhere** in any emitted interview — a negative
  assertion that makes the 24.5% finding un-regressable.

## 4. Requirements

- **R-D1 (one canonical basis, many renderers).** One internal representation — the daydate
  serial — with total, integer-exact renderers per target: POSIX-seconds (Blawx), MJD (swipl
  leg), FEEL date literal (DMN), Excel serial (either epoch), Catala `date` literal. No
  backend hand-rolls its own conversion.
- **R-D2 (durations are two kinds).** Day-granular durations (exact everywhere) vs
  calendar-month/year durations (policy-dependent). The type distinguishes them; each backend
  declares which it accepts; lowering rejects or compiles away calendar components per target
  rather than guessing.
- **R-D3 (month-arithmetic policy is named, never defaulted).** The four observed behaviours —
  refuse (`YMD`), roll forward (`Date`), clamp down, overflow up (Catala's two) — form the
  policy enum. Emitted code never silently picks one; a bridge either maps L4's behaviour
  exactly or rejects with a diagnostic (the Catala R3 precedent).
- **R-D4 (civil dates are timezone-free).** L4 `DATE` is a civil date. Any rendering to a
  timestamp states its convention explicitly (Blawx: UTC midnight). No wall-clock or local-TZ
  value may leak into emitted artifacts or goldens.
- **R-D5 (integer exactness end to end).** No float representation of a date, time, or
  duration at any boundary. Witness: Blawx's float-vs-integer unification failure inside
  `date(...)`.
- **R-D6 (deterministic goldens).** Date values in golden files derive from source literals,
  never from `now()`-stamping (the evaldiff clock-dependence lesson, repo `CLAUDE.md` §3.2.1).
- **R-D7 (Monat semantics for calendar arithmetic, if adopted).** If L4 grows native
  month/year addition, adopt the ESOP 2024 semantics wholesale: addition and rounding as
  separate operators; three modes (down/up/abort) with abort default; year = 12× month;
  composite periods round once (after years+months, before days); the rounding policy is
  declared, carries a legal citation, and is never defaulted (§3.2).
- **R-D8 (no algebraic rewrites over date expressions).** Date addition is neither
  commutative nor associative (F★-mechanised proof, §3.2). No printer, normaliser,
  optimiser, or DNF pass may merge, reorder, or split period additions. Binds
  `prettyLayout`, DMN/FEEL, OpenFisca, docassemble, and the relational middle-end alike —
  already restated there as portfolio invariant I9 (`RELATIONAL-M1-BRIEF.md`). Scope note:
  R-D8 governs _algebraic rewriting of L4 date expressions_, where non-associativity makes
  equivalence unprovable in general; it does not forbid a _target-side lowering choice_
  whose equivalence to L4's semantics has been measured (§3.7's first-of-month shift,
  27,028 cases — R-D11's domain). Do not cite R-D8 to reject R-D11.
- **R-D9 (constructor behaviours are three-way distinct).** `Date` rolls, `DATE_FROM_DMY`
  refuses, `YMD` refuses via `ASSUME` (§3.7). A backend maps each behaviour exactly or
  rejects the construct; mapping all three onto one target constructor silently picks a
  convention the source did not.
- **R-D10 (fractional duration accessors are guilty until measured).** Never lower an
  age/anniversary comparison through a target's float-valued `.years`-style accessor;
  witness: 24.5% disagreement with the L4 oracle, concentrated on the legally decisive day —
  reproducible by `jl4/examples/docassemble/date_idiom_sweep.py` (§3.7), which exits
  non-zero on drift. Use calendar-exact anniversary forms and measure them.
- **R-D11 (prefer the equivalent lowering that keeps the source's named intermediate).**
  Where several lowerings are provably equivalent, choose the one in which the lawyer's
  named binding survives as a named unit in the target (§3.7's first-of-month anniversary
  vs the backward inequality).
- **R-D12 (recognition by name, after in-module bindings).** Date-surface recognition in a
  lowering is by name and is tried only after in-module bindings, so user shadowing wins
  over builtin recognition.
- **R-D13 (negative assertions in CI).** Each backend's tests assert that its known-guilty
  target idioms appear nowhere in emitted artifacts (docassemble: `date_difference`,
  `365.2425`), making measured findings un-regressable.
- **R-D14 (symbolic coverage is granularity-dependent).** Verification plans may assume SMT
  coverage for day-granular epoch-integer dates (linear) but not for month/year calendar
  arithmetic (recursive, non-linear — rejected by Monat et al.; CUTECat falls back to
  concrete evaluation silently). Beyond day granularity, DateSAT is the adoption candidate
  (§3.2). Bears on the prospective `l4 prove` (seam S3).

## 5. Rulings needed

Open questions the ledger has surfaced that no backend may answer unilaterally:

- **Fractional calendar durations.** `7.5 years after` occurs in
  `jl4/examples/legal/ceo-performance-award.l4`. Day-count convention (×365.2425? 6 calendar
  months per half-year? refuse)? Until ruled, backends refuse.
- **The refused-builtin rows.** Each name in §3.7's refusal list needs either a portable
  semantics here or a permanent per-backend rejection entry.

## 6. Non-goals

Implementing the library now; changing daydate's constructor semantics; unifying OpenFisca's
period model with the date model (periods are a different axis and stay with that backend).
