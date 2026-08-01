# Built-in Functions (Not a Library)

L4 includes several **built-in functions** that are always available without importing any library. These are implemented in the compiler core.

> For operators (arithmetic, comparison, boolean), see also [Operators](../operators/README.md) for precedence and usage details.

### Type Coercion Builtins

| Function     | Signature                                    | Description                      |
| ------------ | -------------------------------------------- | -------------------------------- |
| `TOSTRING`   | `NUMBER/BOOLEAN/DATE/TIME/DATETIME → STRING` | Convert to string representation |
| `TONUMBER`   | `STRING → MAYBE NUMBER`                      | Parse string to number           |
| `TODATE`     | `STRING → MAYBE DATE`                        | Parse string to date             |
| `TOTIME`     | `STRING → MAYBE TIME`                        | Parse string to time             |
| `TODATETIME` | `STRING → MAYBE DATETIME`                    | Parse string to datetime         |
| `TRUNC`      | `NUMBER → NUMBER → NUMBER`                   | Truncate decimal places          |
| `AS STRING`  | `value AS STRING`                            | Inline string conversion         |

### Numeric Builtins

| Function            | Signature                  | Description                                           |
| ------------------- | -------------------------- | ----------------------------------------------------- |
| `IS INTEGER`        | `NUMBER → BOOLEAN`         | TRUE if the number has no fractional part             |
| `FLOOR`             | `NUMBER → NUMBER`          | Round down to integer                                 |
| `CEILING`           | `NUMBER → NUMBER`          | Round up to integer                                   |
| `ROUND`             | `NUMBER → NUMBER`          | Round to nearest integer                              |
| `EXPONENT`          | `NUMBER → NUMBER → NUMBER` | Exponentiation (base, power)                          |
| `LN`                | `NUMBER → NUMBER`          | Natural logarithm (runtime error if x ≤ 0)            |
| `LOG10`             | `NUMBER → NUMBER`          | Base-10 logarithm (runtime error if x ≤ 0)            |
| `SQRT`              | `NUMBER → NUMBER`          | Square root                                           |
| `SIN`, `COS`, `TAN` | `NUMBER → NUMBER`          | Trigonometric functions (radians)                     |
| `ASIN`, `ACOS`      | `NUMBER → NUMBER`          | Inverse trigonometric (runtime error outside [-1, 1]) |
| `ATAN`              | `NUMBER → NUMBER`          | Inverse tangent                                       |

> The [math library](../libraries/math.md) provides safe lowercase wrappers (`ln`, `sqrt`, `asin`, ...) that return `MAYBE NUMBER` instead of raising runtime errors on domain violations.

### String Builtins

| Function           | Signature                           | Description                            |
| ------------------ | ----------------------------------- | -------------------------------------- |
| `STRINGLENGTH`     | `STRING → NUMBER`                   | Length of string                       |
| `TOUPPER`          | `STRING → STRING`                   | Convert to uppercase                   |
| `TOLOWER`          | `STRING → STRING`                   | Convert to lowercase                   |
| `TRIM`             | `STRING → STRING`                   | Remove leading/trailing whitespace     |
| `CONTAINS`         | `STRING → STRING → BOOLEAN`         | Substring test                         |
| `STARTSWITH`       | `STRING → STRING → BOOLEAN`         | Prefix test                            |
| `ENDSWITH`         | `STRING → STRING → BOOLEAN`         | Suffix test                            |
| `INDEXOF`          | `STRING → STRING → NUMBER`          | Find position of substring             |
| `SPLIT`            | `STRING → STRING → LIST OF STRING`  | Split by delimiter                     |
| `CHARAT`           | `STRING → NUMBER → STRING`          | Character at index                     |
| `SUBSTRING`        | `STRING → NUMBER → NUMBER → STRING` | Substring (string, start, length)      |
| `REPLACE`          | `STRING → STRING → STRING → STRING` | Replace occurrences (string, old, new) |
| `CONCAT x, y, ...` | `STRING → ... → STRING`             | Concatenate multiple strings           |

**Note:** `STARTSWITH` and `ENDSWITH` are single tokens (no space).

### Date Builtins

| Function           | Signature                         | Description                             |
| ------------------ | --------------------------------- | --------------------------------------- |
| `DATE_FROM_DMY`    | `NUMBER → NUMBER → NUMBER → DATE` | Construct DATE from day, month, year    |
| `DATE_FROM_SERIAL` | `NUMBER → DATE`                   | Construct DATE from serial number       |
| `DATE_SERIAL`      | `DATE → NUMBER`                   | Get serial number from DATE             |
| `DATE_DAY`         | `DATE → NUMBER`                   | Extract day from DATE                   |
| `DATE_MONTH`       | `DATE → NUMBER`                   | Extract month from DATE                 |
| `DATE_YEAR`        | `DATE → NUMBER`                   | Extract year from DATE                  |
| `DATEVALUE`        | `STRING → EITHER STRING DATE`     | Parse date text (LEFT is error message) |
| `TODAY`            | `DATE`                            | Current date (requires `TIMEZONE IS`)   |

### Time Builtins

| Function           | Signature                         | Description                                     |
| ------------------ | --------------------------------- | ----------------------------------------------- |
| `TIME_HOUR`        | `TIME → NUMBER`                   | Extract hour (0-23)                             |
| `TIME_MINUTE`      | `TIME → NUMBER`                   | Extract minute (0-59)                           |
| `TIME_SECOND`      | `TIME → NUMBER`                   | Extract second (0-59)                           |
| `TIME_SERIAL`      | `TIME → NUMBER`                   | Get serial number (day fraction) from TIME      |
| `TIME_FROM_SERIAL` | `NUMBER → TIME`                   | Construct TIME from day fraction                |
| `TIME_FROM_HMS`    | `NUMBER → NUMBER → NUMBER → TIME` | Construct TIME from hour, minute, second        |
| `TIMEVALUE`        | `STRING → EITHER STRING NUMBER`   | Parse time text to day fraction (LEFT is error) |
| `CURRENTTIME`      | `TIME`                            | Current local time (requires `TIMEZONE IS`)     |

### DateTime Builtins

| Function            | Signature                         | Description                                                   |
| ------------------- | --------------------------------- | ------------------------------------------------------------- |
| `DATETIME_DATE`     | `DATETIME → DATE`                 | Extract the date part                                         |
| `DATETIME_TIME`     | `DATETIME → TIME`                 | Extract the time-of-day part                                  |
| `DATETIME_TZ`       | `DATETIME → STRING`               | Extract the IANA timezone name                                |
| `DATETIME_SERIAL`   | `DATETIME → NUMBER`               | Get UTC serial number from DATETIME                           |
| `DATETIME_FROM_DTZ` | `DATE → TIME → STRING → DATETIME` | Construct from date, time, and IANA timezone name             |
| `NOW`               | `DATETIME`                        | Current date and time (defaults to UTC without `TIMEZONE IS`) |

### Timezone Builtins

| Function      | Signature   | Description                                                   |
| ------------- | ----------- | ------------------------------------------------------------- |
| `TIMEZONE`    | `STRING`    | Returns the document timezone string (requires `TIMEZONE IS`) |
| `TIMEZONE IS` | declaration | Top-level declaration setting the document timezone           |

### Temporal and Bitemporal Builtins

These builtins interact with L4's temporal evaluation context. Days are scanned inclusively; while a predicate is evaluated for a day, the valid time and rules-effective date are set to that day.

| Function         | Signature                                  | Description                                                                                                         |
| ---------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `EVER BETWEEN`   | `DATE → DATE → (DATE → BOOLEAN) → BOOLEAN` | TRUE if the predicate holds on **any** day from start to end (inclusive). FALSE when start is after end.            |
| `ALWAYS BETWEEN` | `DATE → DATE → (DATE → BOOLEAN) → BOOLEAN` | TRUE if the predicate holds on **every** day from start to end (inclusive). Vacuously TRUE when start is after end. |
| `WHEN LAST`      | `DATE → (DATE → BOOLEAN) → MAYBE DATE`     | Most recent day at or before the given date on which the predicate holds; NOTHING if none is found.                 |
| `WHEN NEXT`      | `DATE → (DATE → BOOLEAN) → MAYBE DATE`     | Earliest day at or after the given date on which the predicate holds (searching up to 9999-12-31); NOTHING if none. |
| `VALUE AT`       | `DATE → (DATE → a) → a`                    | Evaluates the function at the given date, with valid time and rules-effective date set to that date.                |

Example (see [temporal-acceptance.l4](https://github.com/legalese/l4-ide/blob/main/jl4/examples/ok/temporal-acceptance.l4)):

```l4
#EVAL `EVER BETWEEN` (Date 5 1 2024) (Date 7 1 2024) `weekend?`
#EVAL `WHEN NEXT` (Date 10 1 2024) `weekend?`
#EVAL `VALUE AT` (Date 4 7 1776) (GIVEN d YIELD d)
```

The `EVAL ...` builtins re-evaluate an expression under an altered temporal context, then restore the original context. The first argument is a date/time **serial number** (see `DATE_SERIAL`, `DATETIME_SERIAL`); the second is the expression to evaluate.

| Function                        | Signature        | Description                                                                  |
| ------------------------------- | ---------------- | ---------------------------------------------------------------------------- |
| `EVAL AS OF SYSTEM TIME`        | `NUMBER → a → a` | Evaluate as if the system (transaction) time were the given serial timestamp |
| `EVAL UNDER VALID TIME`         | `NUMBER → a → a` | Evaluate with the valid time set to the given date serial                    |
| `EVAL UNDER RULES EFFECTIVE AT` | `NUMBER → a → a` | Evaluate under the version of the rules effective at the given date          |
| `EVAL UNDER RULES ENCODED AT`   | `NUMBER → a → a` | Evaluate under the rules as they were encoded (known) at the given timestamp |

For regulative traces, `WAIT UNTIL` produces a synthetic event that matches no party or action and is only relevant for its timestamp — use it to advance time in an event list:

| Function     | Signature            | Description                                              |
| ------------ | -------------------- | -------------------------------------------------------- |
| `WAIT UNTIL` | `NUMBER → EVENT a b` | Event that advances contract time to the given timestamp |

```l4
#TRACE aContract AT 0 WITH
  PARTY S DOES delivery AT 2
  (`WAIT UNTIL` 10)
```

See [Regulative Rules](../regulative/README.md) and [EVENT](../regulative/EVENT.md) for details.

### Arithmetic Operators

These operators are always available without import.

| Operator   | Text Alias   | Signature                  | Description           |
| ---------- | ------------ | -------------------------- | --------------------- |
| `+`        | `PLUS`       | `NUMBER → NUMBER → NUMBER` | Addition              |
| `-`        | `MINUS`      | `NUMBER → NUMBER → NUMBER` | Subtraction           |
| `*`        | `TIMES`      | `NUMBER → NUMBER → NUMBER` | Multiplication        |
| `/`        | `DIVIDED BY` | `NUMBER → NUMBER → NUMBER` | Division              |
| `MODULO`   | --           | `NUMBER → NUMBER → NUMBER` | Remainder             |
| `EXPONENT` | --           | `NUMBER → NUMBER → NUMBER` | Exponentiation        |
| `FLOOR`    | --           | `NUMBER → NUMBER`          | Round down to integer |
| `CEILING`  | --           | `NUMBER → NUMBER`          | Round up to integer   |
| `TRUNC`    | --           | `NUMBER → NUMBER → NUMBER` | Truncate toward zero  |

### Comparison Operators

| Operator | Text Alias     | Signature         | Description               |
| -------- | -------------- | ----------------- | ------------------------- |
| `=`      | `EQUALS`       | `a → a → BOOLEAN` | Equality (not assignment) |
| `>`      | `GREATER THAN` | `a → a → BOOLEAN` | Greater than              |
| `<`      | `LESS THAN`    | `a → a → BOOLEAN` | Less than                 |
| `>=`     | `AT LEAST`     | `a → a → BOOLEAN` | Greater than or equal     |
| `<=`     | `AT MOST`      | `a → a → BOOLEAN` | Less than or equal        |

**Note:** `=` is equality, NOT assignment. L4 has no assignment (pure functional).

### Boolean Operators

| Operator  | Symbol Alias | Precedence  | Description             |
| --------- | ------------ | ----------- | ----------------------- |
| `NOT`     | --           | Highest     | Logical negation        |
| `AND`     | `&&`         | High        | Logical and             |
| `OR`      | `\|\|`       | Medium      | Logical or              |
| `IMPLIES` | `=>`         | Lowest      | Logical implication     |
| `UNLESS`  | --           | = `AND NOT` | Shorthand for `AND NOT` |

### List Construction

| Syntax             | Description    |
| ------------------ | -------------- |
| `LIST x, y, z`     | Literal list   |
| `EMPTY`            | Empty list     |
| `x FOLLOWED BY xs` | Cons (prepend) |

### Nullary Builtins

| Function      | Type       | Description                                                   |
| ------------- | ---------- | ------------------------------------------------------------- |
| `TODAY`       | `DATE`     | Current date in document timezone                             |
| `NOW`         | `DATETIME` | Current date and time (defaults to UTC without `TIMEZONE IS`) |
| `CURRENTTIME` | `TIME`     | Current local time (requires `TIMEZONE IS`)                   |
| `TIMEZONE`    | `STRING`   | Document timezone (IANA name)                                 |

---

### HTTP and JSON Builtins

| Function     | Signature                         | Description                  |
| ------------ | --------------------------------- | ---------------------------- |
| `FETCH`      | `STRING → STRING`                 | HTTP GET request             |
| `POST`       | `STRING, STRING, STRING → STRING` | HTTP POST request            |
| `ENV`        | `STRING → MAYBE STRING`           | Read environment variable    |
| `JSONENCODE` | `a → STRING`                      | Convert value to JSON string |
| `JSONDECODE` | `STRING → EITHER STRING a`        | Parse JSON string to value   |

For detailed HTTP/JSON documentation, see [HTTP and JSON](http-json.md).

For detailed coercion documentation, see [Coercions](../types/coercions.md).
