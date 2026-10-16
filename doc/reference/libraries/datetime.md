# datetime

Absolute points in time: a date, a time of day and a time zone together, for deadlines that fall at a particular moment and for comparisons across time zones. Import it with `IMPORT datetime`. Import `daydate` and `time` as well if you also build `DATE` or `TIME` values with `Date` and `Time`.

A DATETIME is stored as a moment in UTC together with its IANA time zone name. The functions that read it give local values in that time zone.

**Example:** [datetime-example.l4](datetime-example.l4)

## The document time zone

The forms of `Datetime` without a time zone use the document's time zone, so the file needs a `TIMEZONE IS` line. The [timezone](timezone.md) library has constants for common zones:

```l4
IMPORT datetime
IMPORT timezone

TIMEZONE IS SGT
```

## Building a DATETIME

Every form below also takes a time zone as a last input, an IANA name such as `"Europe/Paris"`, to use instead of the document's.

| Function                | Gives          | What it does                                         |
| ----------------------- | -------------- | ---------------------------------------------------- |
| `Datetime` date time    | DATETIME       | A DATE and a TIME                                    |
| `Datetime` date h m s   | DATETIME       | A DATE and the hour, minute and second               |
| `Datetime` date         | DATETIME       | Midnight at the start of the date                    |
| `Datetime` d m y h mn s | DATETIME       | Day, month, year, hour, minute and second            |
| `Datetime` d m y h mn   | DATETIME       | Seconds are 0                                        |
| `Datetime` d m y h      | DATETIME       | Minutes and seconds are 0                            |
| `Datetime` d m y        | DATETIME       | Midnight on that day                                 |
| `Datetime` m y          | DATETIME       | Midnight on the 1st of the month                     |
| `Datetime` y            | DATETIME       | Midnight on 1 January                                |
| `Datetime` text         | MAYBE DATETIME | Reads ISO 8601 text such as `"2024-06-15T10:30:00Z"` |
| `Datetime` text tz      | MAYBE DATETIME | The same, shown in the time zone `tz`                |

The number forms take the day before the month, as in `Datetime 15 6 2024 10 30 0`.

## Reading a DATETIME

| Function                                                        | Gives   | What it does                                                |
| --------------------------------------------------------------- | ------- | ----------------------------------------------------------- |
| `Date of` dt                                                    | DATE    | The local date                                              |
| `Time of` dt                                                    | TIME    | The local time of day                                       |
| `Timezone of` dt                                                | STRING  | The IANA time zone name                                     |
| `the hour of` dt                                                | NUMBER  | Local hour, 0 to 23                                         |
| `the minute of` dt                                              | NUMBER  | Local minute                                                |
| `the second of` dt                                              | NUMBER  | Local second                                                |
| `the day of` dt                                                 | NUMBER  | Local day of the month                                      |
| `the month of` dt                                               | NUMBER  | Local month                                                 |
| `the year of` dt                                                | NUMBER  | Local year                                                  |
| dt `` `Datetime to serial` ``                                   | NUMBER  | A serial number counted in UTC                              |
| dt `` `is morning` ``, `` `is afternoon` ``, `` `is evening` `` | BOOLEAN | Before 12:00; 12:00 to 17:59; 18:00 or later, in local time |
| dt `` `is before noon` ``, `` `is after noon` ``                | BOOLEAN | Before 12:00; 12:00 or later                                |

## Moving a DATETIME

| Function           | Gives    | What it does                                  |
| ------------------ | -------- | --------------------------------------------- |
| `at midnight` dt   | DATETIME | The same date at 00:00, in the same time zone |
| `at noon` dt       | DATETIME | The same date at 12:00                        |
| dt `` `at` `` time | DATETIME | The same date at another time of day          |

## Comparing DATETIME values

Comparisons use the moment in UTC, so 09:00 in Singapore is before 09:00 in London on the same day.

- `=`, `<`, `<=`, `>`, `>=` and their word forms compare two DATETIME values.
- dt1 `` `is before` `` dt2 and dt1 `` `is after` `` dt2 read as sentences.
- `` `the earlier of` `` dt1 dt2 and `` `the later of` `` dt1 dt2 pick one of two values.
