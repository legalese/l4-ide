# actus

An L4 implementation of ACTUS, the Algorithmic Contract Types Unified Standards ([actusfrf.org](https://www.actusfrf.org)): types and functions for modelling standardised financial contracts.

`IMPORT actus` gives you every module below. To use only part of it, import a module by name, such as ``IMPORT `actus-core` ``.

## Modules

| Module           | Contents                                     |
| ---------------- | -------------------------------------------- |
| `actus`          | Everything below, plus the evaluation engine |
| `actus-core`     | Contract types, roles and other enumerations |
| `actus-terms`    | Contract terms                               |
| `actus-state`    | Contract state                               |
| `actus-events`   | Event types and events                       |
| `actus-daycount` | Day count conventions and year fractions     |
| `actus-schedule` | Schedule generation                          |

## Core types (`actus-core`)

**Contract Type Taxonomy** (~32 ACTUS contract types organised into families):

- `Basic Contract Type` — PAM, LAM, NAM, ANN, CLM, CSH, STK, UMP, COM
- `Exotic Basic Contract Type` — LAX, NAX, ANX
- `Combined Contract Type` — SWAPS, SWPPV, OPTNS, FUTUR, FXOUT, CAPFL, BCS
- `Credit Enhancement Contract Type` — CEG, CEC, MAR

**Contract Role** — RPA, RPL, CLO, CNO, COL, LG, ST, BUY, SEL, RFL, PFL, RF, PF

- `` `role sign` `` — sign multiplier for payoff calculations (+1 or -1)

**Contract Performance** — PF (performant), DL (delayed), DQ (delinquent), DF (default), MA (matured), TE (terminated)

- `` `is non-performing` ``, `` `is active` `` — performance predicates

**Day Count Convention** — AA, A360, A365, `30E360`, `30E360ISDA`, BUS252; `` `days in year for` `` gives the days in a year under a convention

**Other Enums:**

- `End of Month Convention` — EOM, SD, EOMP
- `Business Day Convention` — SCR, SCRF, SCRP, SCRMF, SCRMP
- `Calendar Type` — NoCalendar, MondayToFriday, Calendar
- `Period Unit` — Days, Weeks, Months, Quarters, Years
- `Stub Convention` — Long/Short Initial/Final
- `Interest Payment Convention` — PayInterest, CapitalizeInterest
- `Penalty Type` — NoPenalty, AbsolutePenalty, RelativePenalty, InterestPenalty
- `Option Type` / `Option Exercise Type` — Call, Put, Straddle / European, American, Bermudan
- `Scaling Effect` — NoScaling, InterestScaling, PrincipalScaling, BothScaling
- `ACTUS Currency` — `` `ACTUS USD` ``, `` `ACTUS EUR` ``, `` `ACTUS GBP` ``, `` `ACTUS JPY` ``, `` `ACTUS CHF` ``, `` `ACTUS CAD` ``, `` `ACTUS AUD` ``, `` `ACTUS CNY` ``, `` `ACTUS HKD` ``, `` `ACTUS SGD` ``, or `` `ACTUS Other` `` with an ISO code; `` `currency code` `` gives the ISO 4217 code as a STRING

**ACTUS Amount** — record with `value` and `currency`; `` `ACTUS_USD` ``, `` `ACTUS_EUR` ``, `` `ACTUS_GBP` `` and `` `ACTUS_SGD` `` build one from a number

**Cycle** — record with `period`, `periodUnit`, `stub`; convenience constructors: `` `Monthly Cycle` ``, `` `Quarterly Cycle` ``, `` `Semi-Annual Cycle` ``, `` `Annual Cycle` ``

## Contract terms (`actus-terms`)

- `ACTUS Contract Terms` — core contract parameters (ID, type, role, dates, principal, rate, day count convention)
- `FXOUT Terms` — FX outright transaction parameters
- `` `implied exchange rate` `` — derive rate from FX term amounts

## Contract state (`actus-state`)

- `Contract State` — runtime state (statusDate, contractPerformance, notionalPrincipal, accruedInterest, nominalInterestRate, feeAccrued)
- `` `is fully paid` ``, `` `is in default` ``, `` `outstanding balance` `` — state predicates
- `` `empty state` `` — default initial state

## Contract events (`actus-events`)

**Event Types:** IED, PR, PP, MD, IP, IPCI, RR, RRF, FP, PY, TD, XD, STD, DV, CE, AD

- `Contract Event` — record with eventType, eventDate, payoff, currency, notionalPrincipal, nominalInterestRate, accruedInterest
- `` `make event` `` — event constructor
- `` `event sequence` ``, `` `event name` ``, `` `event acronym` `` — event metadata
- `` `is principal event` ``, `` `is interest event` ``, `` `has cash flow` `` — event predicates
- `` `total payoff` `` — sum payoffs across a list of events

## Day count conventions (`actus-daycount`)

- `` `year fraction` `` — Y(S,E) calculation dispatching on convention
- `` `year fraction A365` ``, `` `year fraction A360` `` — specific convention implementations
- `` `days between` `` — raw day count between two dates
- `` `accrued interest for period` `` — interest accrual given principal, rate, dates, and convention

## Schedule generation (`actus-schedule`)

- `` `add days` `` — date arithmetic on a number of days
- `` `add months` `` — month arithmetic with month-end clamping; it is defined in [`daydate`](daydate.md), which `actus-schedule` imports and passes on
- `` `monthly schedule` `` — generate a list of monthly dates from a start date
- `` `schedule length` `` — count dates in a schedule

## Evaluation engine (`actus`)

**Payoff Functions (POF):**

- `` `POF_IED` `` — Initial Exchange Date payoff
- `` `POF_IP` `` — Interest Payment payoff
- `` `POF_MD` `` — Maturity payoff
- `` `POF_PR` `` — Principal Redemption payoff

**State Transition Functions (STF):**

- `` `STF_IED` `` — initialise state after initial exchange
- `` `STF_IP` `` — reset accrued interest after payment
- `` `STF_MD` `` — contract reaches maturity
- `` `STF_PR` `` — reduce notional by redemption amount

**Interest Accrual:**

- `` `accrue interest to` `` — accrue interest from current state date to a target date

**FX Transaction (FXOUT):**

- `` `FXOUT pay event` ``, `` `FXOUT receive event` `` — generate FX cash flow events

**Cash Flow Projection:**

- `` `net cash flow` `` — sum all cash flows from a list of events
