# Built-in functions

Built-in functions are part of the language, so they work in every file without an `IMPORT`. Functions that come from a library, such as `map`, `sum` or `Date`, are listed under [Standard libraries](../libraries/README.md).

Operators (`+`, `AND`, `EQUALS`, `UNLESS`, `FOLLOWED BY` and the rest) are described under [Operators](../operators/README.md). The conversions `TOSTRING`, `TONUMBER`, `TODATE`, `TOTIME`, `TODATETIME` and `AS STRING` are described under [Coercions](../types/coercions.md).

## Numbers

| Function            | Inputs         | Gives   | What it does                                                                                                                                                   |
| ------------------- | -------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ISINTEGER`         | NUMBER         | BOOLEAN | TRUE if the number has no fractional part                                                                                                                      |
| `FLOOR`             | NUMBER         | NUMBER  | Rounds down to a whole number                                                                                                                                  |
| `CEILING`           | NUMBER         | NUMBER  | Rounds up to a whole number                                                                                                                                    |
| `ROUND`             | NUMBER         | NUMBER  | Rounds to the nearest whole number; a half goes to the even number, so 2.5 gives 2 and 3.5 gives 4                                                             |
| `TRUNC`             | NUMBER, NUMBER | NUMBER  | `TRUNC x n` cuts `x` toward zero to `n` decimal places: `TRUNC 12.987 2` is 12.98. A negative `n` cuts to tens, hundreds and so on: `TRUNC 123.45 (-1)` is 120 |
| `EXPONENT`          | NUMBER, NUMBER | NUMBER  | `EXPONENT base power`: `EXPONENT 2 10` is 1024                                                                                                                 |
| `SQRT`              | NUMBER         | NUMBER  | Square root                                                                                                                                                    |
| `LN`                | NUMBER         | NUMBER  | Natural logarithm; an error for 0 or less                                                                                                                      |
| `LOG10`             | NUMBER         | NUMBER  | Base-10 logarithm; an error for 0 or less                                                                                                                      |
| `SIN`, `COS`, `TAN` | NUMBER         | NUMBER  | Trigonometry, in radians                                                                                                                                       |
| `ASIN`, `ACOS`      | NUMBER         | NUMBER  | Inverse sine and cosine; an error outside -1 to 1                                                                                                              |
| `ATAN`              | NUMBER         | NUMBER  | Inverse tangent                                                                                                                                                |

The [math](../libraries/math.md) library has lowercase versions (`ln`, `sqrt`, `asin`, ...) that give `NOTHING` instead of an error.

## Text

Positions in a STRING count from 0.

| Function       | Inputs                 | Gives          | What it does                                                      |
| -------------- | ---------------------- | -------------- | ----------------------------------------------------------------- |
| `CONCAT`       | STRING, STRING, ...    | STRING         | Joins any number of strings: `CONCAT "Hello, ", name, "!"`        |
| `STRINGLENGTH` | STRING                 | NUMBER         | The number of characters                                          |
| `TOUPPER`      | STRING                 | STRING         | Upper case                                                        |
| `TOLOWER`      | STRING                 | STRING         | Lower case                                                        |
| `TRIM`         | STRING                 | STRING         | Without spaces at the start and end                               |
| `CONTAINS`     | STRING, STRING         | BOOLEAN        | `CONTAINS text part`: TRUE if `part` occurs in `text`             |
| `STARTSWITH`   | STRING, STRING         | BOOLEAN        | `STARTSWITH text start`                                           |
| `ENDSWITH`     | STRING, STRING         | BOOLEAN        | `ENDSWITH text end`                                               |
| `INDEXOF`      | STRING, STRING         | NUMBER         | `INDEXOF text part`: the position of the first `part`, or -1      |
| `SPLIT`        | STRING, STRING         | LIST OF STRING | `SPLIT text separator`: `SPLIT "a,b" ","` is `LIST "a", "b"`      |
| `CHARAT`       | STRING, NUMBER         | STRING         | `CHARAT text position`: one character                             |
| `SUBSTRING`    | STRING, NUMBER, NUMBER | STRING         | `SUBSTRING text start length`: `SUBSTRING "hello" 1 3` is `"ell"` |
| `REPLACE`      | STRING, STRING, STRING | STRING         | `REPLACE text old new`: every `old` replaced by `new`             |

`STARTSWITH` and `ENDSWITH` are written as one word.

## Dates

| Function           | Inputs                 | Gives              | What it does                                                   |
| ------------------ | ---------------------- | ------------------ | -------------------------------------------------------------- |
| `DATE_FROM_DMY`    | NUMBER, NUMBER, NUMBER | DATE               | The date from day, month and year                              |
| `DATE_FROM_SERIAL` | NUMBER                 | DATE               | The date with this serial number                               |
| `DATE_SERIAL`      | DATE                   | NUMBER             | The date's serial number (a count of days)                     |
| `DATE_DAY`         | DATE                   | NUMBER             | The day of the month                                           |
| `DATE_MONTH`       | DATE                   | NUMBER             | The month                                                      |
| `DATE_YEAR`        | DATE                   | NUMBER             | The year                                                       |
| `DATEVALUE`        | STRING                 | EITHER STRING DATE | Reads date text such as `"2024-02-01"`; `LEFT` holds the error |
| `TODAY`            | none                   | DATE               | Today's date in the document's time zone; needs `TIMEZONE IS`  |

The [daydate](../libraries/daydate.md) library builds on these with `Date`, weekdays, months and more.

## Times of day

| Function           | Inputs                 | Gives                | What it does                                                                     |
| ------------------ | ---------------------- | -------------------- | -------------------------------------------------------------------------------- |
| `TIME_FROM_HMS`    | NUMBER, NUMBER, NUMBER | TIME                 | The time from hour, minute and second                                            |
| `TIME_FROM_SERIAL` | NUMBER                 | TIME                 | The time from a fraction of a day (0.5 is noon)                                  |
| `TIME_SERIAL`      | TIME                   | NUMBER               | The time as a fraction of a day                                                  |
| `TIME_HOUR`        | TIME                   | NUMBER               | 0 to 23                                                                          |
| `TIME_MINUTE`      | TIME                   | NUMBER               | 0 to 59                                                                          |
| `TIME_SECOND`      | TIME                   | NUMBER               | 0 to 59                                                                          |
| `TIMEVALUE`        | STRING                 | EITHER STRING NUMBER | Reads time text such as `"12:00"` as a fraction of a day; `LEFT` holds the error |
| `CURRENTTIME`      | none                   | TIME                 | The current time in the document's time zone; needs `TIMEZONE IS`                |

## Date and time together

| Function            | Inputs             | Gives    | What it does                                                  |
| ------------------- | ------------------ | -------- | ------------------------------------------------------------- |
| `DATETIME_FROM_DTZ` | DATE, TIME, STRING | DATETIME | A DATETIME from a date, a time and an IANA time zone name     |
| `DATETIME_DATE`     | DATETIME           | DATE     | The local date                                                |
| `DATETIME_TIME`     | DATETIME           | TIME     | The local time of day                                         |
| `DATETIME_TZ`       | DATETIME           | STRING   | The IANA time zone name                                       |
| `DATETIME_SERIAL`   | DATETIME           | NUMBER   | A serial number counted in UTC                                |
| `NOW`               | none               | DATETIME | The current moment; in UTC when the file has no `TIMEZONE IS` |
| `TIMEZONE`          | none               | STRING   | The document's time zone name; needs `TIMEZONE IS`            |

`TIMEZONE IS` is a line of its own at the top level of a file that sets the document's time zone, such as `TIMEZONE IS "Asia/Singapore"`. The [timezone](../libraries/timezone.md) library has constants for common zones, and [datetime](../libraries/datetime.md) builds on these functions.

## Regulative traces

| Function    | Inputs                                 | Gives       | What it does                                                                                        |
| ----------- | -------------------------------------- | ----------- | --------------------------------------------------------------------------------------------------- |
| `WAITUNTIL` | NUMBER                                 | EVENT a b   | An event that matches no party and no action; in a `#TRACE` it moves time forward to the given time |
| `EVALTRACE` | DEONTIC a b, NUMBER, LIST OF EVENT a b | DEONTIC a b | The function behind `#TRACE`: what remains of a rule after the events, starting at the given time   |

See [EVENT](../regulative/EVENT.md) and [Regulative rules](../regulative/README.md).

## HTTP and JSON

| Function     | Inputs                 | Gives           | What it does                                                      |
| ------------ | ---------------------- | --------------- | ----------------------------------------------------------------- |
| `FETCH`      | STRING                 | STRING          | Sends an HTTPS GET request and gives the response body            |
| `POST`       | STRING, STRING, STRING | STRING          | Sends an HTTPS POST request: URL, headers, body                   |
| `ENV`        | STRING                 | MAYBE STRING    | The value of an environment variable, or `NOTHING`                |
| `JSONENCODE` | a                      | STRING          | Any value as JSON text                                            |
| `JSONDECODE` | STRING                 | EITHER STRING a | JSON text as a value of the expected type; `LEFT` holds the error |

Details, including the header format and how records are encoded, are under [HTTP and JSON](http-json.md).
