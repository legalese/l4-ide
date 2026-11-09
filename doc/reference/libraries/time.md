# time

Time of day, with no date and no time zone, for rules about opening hours, cut-off times and the like. Import it with `IMPORT time`. Times are kept in 24-hour form; arithmetic wraps around midnight.

**Example:** [time-example.l4](time-example.l4)

## Constants

| Constant                                    | Value    |
| ------------------------------------------- | -------- |
| `Midnight`                                  | 00:00:00 |
| `Noon`                                      | 12:00:00 |
| `Seconds in a minute`, `Minutes in an hour` | 60       |
| `Hours in a day`                            | 24       |
| `Seconds in an hour`                        | 3600     |
| `Seconds in a day`                          | 86400    |

`Meridiem Indicator` is an enumeration with the values `am` and `pm`.

## Building a time

| Function                      | Gives      | What it does                                             |
| ----------------------------- | ---------- | -------------------------------------------------------- |
| `Time` h m s                  | TIME       | From hours (0 to 23), minutes and seconds                |
| `Time` h m                    | TIME       | Seconds are 0                                            |
| `Time` h                      | TIME       | Minutes and seconds are 0                                |
| `Time` h m s `am` (or `pm`)   | TIME       | 12-hour form; also `Time h m am` and `Time h pm`         |
| `Time` text                   | MAYBE TIME | Reads `"HH:MM:SS"` or `"HH:MM"`                          |
| `Time` datetime               | TIME       | The time part of a DATETIME, ignoring date and time zone |
| serial `` `Serial to time` `` | TIME       | From a fraction of a day: 0 is midnight, 0.5 is noon     |

## Reading a time

| Function                 | Gives   | What it does                    |
| ------------------------ | ------- | ------------------------------- |
| `the hour of` t          | NUMBER  | 0 to 23                         |
| `the minute of` t        | NUMBER  | 0 to 59                         |
| `the second of` t        | NUMBER  | 0 to 59                         |
| t `` `Time to serial` `` | NUMBER  | The time as a fraction of a day |
| t `` `is morning` ``     | BOOLEAN | Before 12:00                    |
| t `` `is afternoon` ``   | BOOLEAN | 12:00 to 17:59                  |
| t `` `is evening` ``     | BOOLEAN | 18:00 or later                  |
| t `` `is before noon` `` | BOOLEAN | Before 12:00                    |
| t `` `is after noon` ``  | BOOLEAN | 12:00 or later                  |

## Moving a time

Each of these wraps around midnight: ``(Time 23 0 0) `plus hours` 2`` is 01:00. Put a time built with `Time` in parentheses, as here, before a word written after it.

| Function                                            | Gives |
| --------------------------------------------------- | ----- |
| t `` `plus hours` `` n, t `` `minus hours` `` n     | TIME  |
| t `` `plus minutes` `` n, t `` `minus minutes` `` n | TIME  |
| t `` `plus seconds` `` n, t `` `minus seconds` `` n | TIME  |

## Comparing times

- `=`, `<`, `<=`, `>`, `>=` and their word forms compare two times.
- t1 `MINUS` t2 is the difference in seconds.
- t1 `` `is before` `` t2 and t1 `` `is after` `` t2 read as sentences.
- `` `the earlier of` `` t1 t2 and `` `the later of` `` t1 t2 pick one of two times.
