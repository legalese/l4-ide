# Daydate Library

Date arithmetic and temporal logic for legal deadlines and time-based rules. Follows ISO 8601 conventions.
Can be imported into L4 files with `IMPORT daydate`. Automatically imports `date-compat` for backwards-compatible DATE accessors.

### Location

[jl4-core/libraries/daydate.l4](https://github.com/legalese/l4-ide/blob/main/jl4-core/libraries/daydate.l4)

### Features

- Date construction from year/month/day (`YMD`, bounds-checked) or day/month/year (`Date`), serial numbers, strings, or DATETIME extraction
- Date arithmetic (add/subtract days, weeks, months, years)
- Weekday and weekend detection
- Week-of-year calculations
- Month and year helpers
- Leap year detection
- String parsing for JSON interoperability
- DATETIME date extraction

### Key Functions

**Constants:**

- `Monday` through `Sunday` (0-6)
- `January` through `December` (1-12)
- `Days in a week`, `Days in a year`, etc.

**Date Construction:**

- `YMD year month day` - **Recommended for new code.** Create date from components in ISO 8601 order, **bounds-checked**: `YMD` builds the candidate through `Date` and then requires its year, month and day to equal the arguments, so a rolled component (`YMD 2026 28 7`, a transposition; `YMD 2023 2 29`, no such leap day; month 0; day 32) stops evaluation with an assumed-term error naming `YMD refusal`, instead of computing a wrong date.
  `Date d m y` remains the lenient, rolling constructor, and stays supported. A transposed `Date 7 28 2026` is not rejected: month 28 silently overflows into 2028-04-07.
  If you give an out-of-range `YMD` a name, as in `` `bad day` MEANS YMD 2023 2 29 ``, the first `#EVAL` of that name prints the assumed-term error and every later one in the same run prints `Infinite loop detected while trying to evaluate:` instead.
- `Date day month year` - Create date from components
- `Date serialNumber` - Create date from serial number
- `Date str` - Parse date string (ISO format, ignores time/timezone if present), returns MAYBE DATE
- `Date dt` - Extract date from DATETIME (ignores time and timezone)
- `Week weekNumber year` - First day of week
- `Month month year` - First day of month
- `Year year` - First day of year

**Date Arithmetic:**

- `date PLUS days` - Add days to date
- `date MINUS days` - Subtract days from date
- `` `add months` `` date months, `` `add years` `` date years - Add whole months or years to a date, counting backwards for a negative number and rounding a fractional one down.
  When the day does not exist in the month it lands in, the date is clamped to that month's last day, as Excel's `EDATE` does: 31 January plus one month is 29 February in 2024 and 28 February in 2023, and 29 February 2024 plus one year is 28 February 2025.
  `Date d m y` does the opposite and rolls forward, so `Date 29 2 2025` is 1 March 2025: use `` `add years` `` for an anniversary.
- `the day after`, `the week before`, etc.

**Queries:**

- `Weekday of date` - Get weekday (0-6)
- `Week of the year date` - Get ISO week number
- `is weekend`, `is weekday` - Check day type
- `is leap year` - Check leap year

**Comparators:**

- `the earlier of` d1 d2
- `the later of` d1 d2
- d1 `is before` d2, d1 `is after` d2
- Standard comparison operators: LESS THAN, GREATER THAN, AT MOST, AT LEAST

### Example: Date Calculations

[daydate-example.l4](daydate-example.l4)

**See [daydate.l4](https://github.com/legalese/l4-ide/blob/main/jl4-core/libraries/daydate.l4) source for all functions.**
