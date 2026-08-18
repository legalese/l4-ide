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

## 5. Non-goals

Implementing the library now; changing daydate's constructor semantics; unifying OpenFisca's
period model with the date model (periods are a different axis and stay with that backend).
