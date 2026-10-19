# daydate

Dates for deadlines and time-based rules: building dates, adding days, months and years, weekdays, ISO weeks and leap years. Import it with `IMPORT daydate`. Weeks start on Monday, following ISO 8601.

Most functions take either a `DATE` or a day number (the date's serial number, as given by `Day`), so `` `Weekday of` (Date 1 1 2024) `` and `` `Weekday of` 739250 `` give the same answer.

**Example:** [daydate-example.l4](daydate-example.l4)

## Constants

| Constant                                      | Value                                              |
| --------------------------------------------- | -------------------------------------------------- |
| `Monday` to `Saturday` (also `Mon` to `Sat`)  | 1 to 6                                             |
| `Sunday` (also `Sun`)                         | 0                                                  |
| `January` to `December` (also `Jan` to `Dec`) | 1 to 12                                            |
| `Days in a week`                              | 7                                                  |
| `Months in a year`                            | 12                                                 |
| `Days in a year`                              | 365.2425, the average over the 400-year leap cycle |
| `Days in a month`                             | 30.436875, the average month                       |

The month names also build dates: `January 15 2024` is 15 January 2024.

## Building a date

| Function                               | Gives      | What it does                                                                 |
| -------------------------------------- | ---------- | ---------------------------------------------------------------------------- |
| `Date` day month year                  | DATE       | The date from its parts: `Date 25 12 2024`                                   |
| `Date` days                            | DATE       | The date with this day number                                                |
| `Date` text                            | MAYBE DATE | Reads an ISO date such as `"2025-06-15"`; any time and time zone are ignored |
| `Date` datetime                        | DATE       | The date part of a DATETIME, ignoring time and time zone                     |
| `Week` week year                       | DATE       | The Monday of that ISO week                                                  |
| `Month` month year                     | DATE       | The first day of that month                                                  |
| `Year` year                            | DATE       | 1 January of that year                                                       |
| `Month` date, `Week` date, `Year` date | DATE       | The first day of the month, ISO week or year that contains `date`            |
| `January` day year, ...                | DATE       | The date in that month: `March 1 2025`                                       |

`Date` rolls a day that does not exist in the month forward: `Date 29 2 2025` is 1 March 2025. `Days to date` is another name for `Date`.

## Reading a date

| Function                                     | Gives   | What it does                                          |
| -------------------------------------------- | ------- | ----------------------------------------------------- |
| `Day` date                                   | NUMBER  | The date's day number; `Date to days` is another name |
| `Weekday of` date                            | NUMBER  | 1 for Monday to 6 for Saturday, 0 for Sunday          |
| `Week of the year` date                      | NUMBER  | The ISO week number                                   |
| `Month of the year` date                     | NUMBER  | 1 to 12                                               |
| `Name of month` date                         | STRING  | `"February"`                                          |
| `Name of weekday` date                       | STRING  | `"Monday"`                                            |
| `is weekend` date                            | BOOLEAN | Saturday or Sunday                                    |
| `is weekday` date                            | BOOLEAN | Monday to Friday                                      |
| `is leap year` year (or date)                | BOOLEAN | 366 days in the year                                  |
| `Days in month` month year (or date)         | NUMBER  | 28 to 31                                              |
| `Days in year` year (or date)                | NUMBER  | 365 or 366                                            |
| `Weeks in year` year (or date)               | NUMBER  | 52 or 53 ISO weeks                                    |
| `Weekday of 1st day of month` month year     | NUMBER  | The weekday of the 1st of the month                   |
| `Weekday of 1st day of year` year            | NUMBER  | The weekday of 1 January                              |
| `Months since year start to days` month year | NUMBER  | The days in the year before that month begins         |
| `Years to days` year                         | NUMBER  | The day number of 1 January of that year              |

To read the day, month or year of a date as a number, use the built-ins `DATE_DAY`, `DATE_MONTH` and `DATE_YEAR`, or [date-compat](#date-compat).

## Moving a date

| Function                  | Gives | What it does                                                                                 |
| ------------------------- | ----- | -------------------------------------------------------------------------------------------- |
| date `PLUS` n, date `+` n | DATE  | `n` days later                                                                               |
| date `MINUS` n            | DATE  | `n` days earlier                                                                             |
| `add months` date months  | DATE  | The same day, whole months later (or earlier for a negative number)                          |
| `add years` date years    | DATE  | The same day, whole years later (or earlier)                                                 |
| `the day after` date      | DATE  | The next day                                                                                 |
| `the day before` date     | DATE  | The previous day                                                                             |
| `the week after` date     | DATE  | The Monday of the following week                                                             |
| `the week before` date    | DATE  | The Monday of the previous week                                                              |
| `the month after` date    | DATE  | The 1st of the following month                                                               |
| `the month before` date   | DATE  | The 1st of the previous month                                                                |
| `the year after` date     | DATE  | 1 January of the following year                                                              |
| `the year before` date    | DATE  | 1 January of the previous year                                                               |
| `on day` n date           | DATE  | The `n`th day counting `date` as day 1: `` `on day` 15 (Month 2 2024) `` is 15 February 2024 |

`add months` and `add years` round a fractional number down. When the day does not exist in the month they land in, they use that month's last day, as Excel's `EDATE` does: 31 January plus one month is 29 February in 2024 and 28 February in 2023, and 29 February 2024 plus one year is 28 February 2025. Use `add years` for an anniversary, since `Date 29 2 2025` rolls forward to 1 March.

## Comparing dates

- `=`, `<`, `<=`, `>`, `>=` and their word forms (`EQUALS`, `LESS THAN`, `AT MOST`, `GREATER THAN`, `AT LEAST`) compare two dates.
- date1 `MINUS` date2 is the number of days between them.
- d1 `` `is before` `` d2 and d1 `` `is after` `` d2 read as sentences. Put each date in parentheses: ``(Date 10 1 2024) `is before` (Date 11 1 2024)``.
- `` `the earlier of` `` d1 d2 and `` `the later of` `` d1 d2 pick one of two dates.

## date-compat

`date-compat` is a separate library for files written before `DATE` became a built-in type. Import it with ``IMPORT `date-compat` `` (the backticks are needed because of the hyphen). `daydate` uses it internally, but importing `daydate` does not make its functions available to you.

| Function                        | Gives  | What it does                                                  |
| ------------------------------- | ------ | ------------------------------------------------------------- |
| `DATE` day month year           | DATE   | The older spelling of `Date day month year`: `DATE 15 3 1990` |
| `DATE` days                     | DATE   | The date with this day number                                 |
| `Day of` date (or `day of`)     | NUMBER | The day of the month, like `DATE_DAY`                         |
| `Month of` date (or `month of`) | NUMBER | The month, like `DATE_MONTH`                                  |
| `Year of` date (or `year of`)   | NUMBER | The year, like `DATE_YEAR`                                    |

New files should use `Date` from `daydate`, and `DATE_DAY`, `DATE_MONTH` and `DATE_YEAR`.
