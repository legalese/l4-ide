# Coercions

These built-in functions convert values from one type to another. They need no `IMPORT`.
Functions that parse text return a `MAYBE`: `JUST` the value, or `NOTHING` when the text cannot be read.

## Functions

### TOSTRING

Converts a value to its string representation.

**Signature:** `NUMBER | BOOLEAN | DATE | TIME | DATETIME | STRING → STRING`

**Behavior:**

- Numbers render with canonical decimal text (no trailing zeros)
- Booleans render as `TRUE` or `FALSE`
- Dates render as `YYYY-MM-DD`
- Times render as `HH:MM:SS`
- DateTimes render as ISO-8601 with an offset (e.g., `2024-06-15T02:30:00+0000`)
- Strings pass through unchanged

**Example:**

[coercion-example.l4](coercion-example.l4)

---

### TONUMBER

Parses a string to a number.

**Signature:** `STRING → MAYBE NUMBER`

**Behavior:**

- Accepts trimmed ASCII numeric literals
- Supports optional sign (`+` or `-`)
- Supports decimal point
- Supports scientific notation (e.g., `1.2E3`)
- Returns `NOTHING` on parse failure

**Accepted formats:**

- `"42"` → `JUST 42`
- `"-12.50"` → `JUST -12.5`
- `"  3.14  "` → `JUST 3.14` (whitespace trimmed)
- `"1.2E3"` → `JUST 1200`
- `"oops"` → `NOTHING`

---

### TODATE

Parses a string to a date.

**Signature:** `STRING → MAYBE DATE`

**Accepted formats:**

- `YYYY-MM-DD` (ISO 8601): `"2024-02-29"`
- `YYYY/MM/DD`: `"2024/02/29"`
- `DD-MMM-YYYY`: `"29-Feb-2024"`
- `DD/MM/YYYY`: `"29/02/2024"`
- `MMM DD, YYYY`: `"Feb 29, 2024"`

**Behavior:**

- Month names are case-insensitive
- Rejects dates outside `0001-01-01` to `9999-12-31`
- Returns `NOTHING` for invalid dates (e.g., `"31/02/2024"`)

---

### TOTIME

Parses a string to a time.

**Signature:** `STRING → MAYBE TIME`

**Accepted formats (24-hour clock only):**

- `HH:MM:SS`: `"14:30:00"`, also with fractions of a second: `"14:30:00.5"`
- `HH:MM`: `"14:30"`

**Behavior:**

- Returns `NOTHING` for anything else, including 12-hour times such as `"2:30 PM"`

---

### TODATETIME

Parses a string to a datetime.

**Signature:** `STRING → MAYBE DATETIME`

**Accepted formats:**

- ISO-8601 with an offset: `"2024-06-15T10:30:00+08:00"`
- ISO-8601 with Z (UTC): `"2024-06-15T10:30:00Z"`
- A space in place of the `T`: `"2024-06-15 10:30:00Z"`

**Behavior:**

- Returns `NOTHING` for invalid datetime strings
- The value is stored in UTC: `"2024-06-15T10:30:00+08:00"` becomes `2024-06-15T02:30:00+0000`

---

### TRUNC

Truncates a number toward zero.

**Signature:** `NUMBER, NUMBER → NUMBER`

**Parameters:**

- `value` - The number to truncate
- `digits` - Number of decimal places to keep (rounded to nearest integer)

**Behavior:**

- Non-negative `digits` truncate fractional places
- Negative `digits` truncate to the left of the decimal point
- Truncates toward zero (not floor/ceiling)

**Examples:**

- `TRUNC 12.987 0` → `12`
- `TRUNC 12.987 2` → `12.98`
- `TRUNC 123.45 (-1)` → `120`
- `TRUNC (-12.987) 1` → `-12.9`

---

### AS STRING

Inline syntax for type conversion, equivalent to `TOSTRING`.

**Syntax:** `value AS STRING`

**Examples:**

- `42 AS STRING` → `"42"`
- `TRUE AS STRING` → `"TRUE"`
- `(Date 1 1 2024) AS STRING` → `"2024-01-01"` (`Date` comes from [daydate](../libraries/daydate.md))

---

## Locale independence

All coercion functions give the same result on every system: they do not depend on the locale.

---

## Related pages

- [Types](README.md)
- [Built-in functions](../builtins/README.md)
- [daydate](../libraries/daydate.md), [time](../libraries/time.md), [datetime](../libraries/datetime.md): more on dates and times
