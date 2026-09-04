# Built-ins and Libraries Reference

The functions and values Claude is most likely to need but least likely to know from Haskell transfer.

**Canonical references:**

- Built-in coercions: <https://legalese.com/l4/reference/types/coercions.md>
- HTTP (Hypertext Transfer Protocol) / JSON (JavaScript Object Notation) built-ins: <https://legalese.com/l4/reference/builtins/http-json.md>
- Library index: <https://legalese.com/l4/reference/libraries.md>
- Glossary of everything: <https://legalese.com/l4/reference/GLOSSARY.md>

---

## Contents

- [Type coercions (always available)](#type-coercions-always-available)
- [HTTP and JSON built-ins (always available)](#http-and-json-built-ins-always-available)
- [Temporal globals](#temporal-globals)
- [Library index](#library-index)
  - [`hierarchy` — numbered outlines](#hierarchy--numbered-outlines)
  - [`daydate` — dates and day arithmetic](#daydate--dates-and-day-arithmetic)
- [Prelude — most-used functions](#prelude--most-used-functions)

---

## Type coercions (always available)

L4 does **no implicit coercion** between types. Use these explicit conversions. They are in the compiler core — no `IMPORT` required.

| Function          | Signature                                                          | Notes                                                                                                                           |
| ----------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| `TOSTRING`        | `NUMBER \| BOOLEAN \| DATE \| TIME \| DATETIME \| STRING → STRING` | Numbers render canonically; dates `YYYY-MM-DD`; datetimes in the International Organization for Standardization (ISO) 8601 form |
| `TONUMBER`        | `STRING → MAYBE NUMBER`                                            | Accepts optional sign, decimals, `1.2E3` scientific                                                                             |
| `TODATE`          | `STRING → MAYBE DATE`                                              | Accepts `YYYY-MM-DD`, `YYYY/MM/DD`, `DD-MMM-YYYY`, `DD/MM/YYYY`, `MMM DD, YYYY`                                                 |
| `TOTIME`          | `STRING → MAYBE TIME`                                              | Accepts `HH:MM:SS`, `HH:MM`, `h:MM AM/PM`                                                                                       |
| `TODATETIME`      | `STRING → MAYBE DATETIME`                                          | ISO 8601 with timezone or `Z`                                                                                                   |
| `TRUNC`           | `NUMBER NUMBER → NUMBER`                                           | `TRUNC value digits` — truncates toward zero                                                                                    |
| `value AS STRING` | inline                                                             | Equivalent to `TOSTRING value`                                                                                                  |

All parse functions return `MAYBE` and yield `NOTHING` on failure — there are no exceptions. Coercions are deterministic and locale-independent.

```l4
#EVAL TOSTRING 42                 -- "42"
#EVAL TONUMBER "  3.14  "         -- JUST 3.14
#EVAL TODATE "29-Feb-2024"        -- JUST <2024-02-29>
#EVAL TRUNC 12.987 2              -- 12.98
#EVAL 42 AS STRING                -- "42"
```

Reference: <https://legalese.com/l4/reference/types/coercions.md>

---

## HTTP and JSON built-ins (always available)

The bridge from L4 rules to real-world data. No `IMPORT` required.

| Function     | Signature                           | Purpose                                                                                                                     |
| ------------ | ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `FETCH`      | `STRING → STRING`                   | HTTP GET; returns response body as STRING. **Lazy + cached** — multiple references to the same call return the same result. |
| `POST`       | `STRING → STRING → STRING → STRING` | HTTP POST: `POST url headers body` where `headers` is a JSON string                                                         |
| `ENV`        | `STRING → STRING`                   | Read environment variable; returns `""` if unset. Use this for application programming interface (API) keys.                |
| `JSONENCODE` | `a → STRING`                        | Serialize a value to a JSON string                                                                                          |
| `JSONDECODE` | `STRING → a`                        | Parse a JSON string into a typed value                                                                                      |

```l4
DECIDE uuid     IS FETCH "https://www.uuidtools.com/api/generate/v4"
DECIDE apiKey   IS ENV "ANTHROPIC_API_KEY"
DECIDE response IS POST
    "https://api.example.com/data"
    "{\"Content-Type\": \"application/json\"}"
    "{\"name\": \"test\"}"
```

**Security:** keep secrets in `ENV`, never inline in source.

Reference: <https://legalese.com/l4/reference/builtins/http-json.md>

---

## Temporal globals

| Constant      | Type         | Notes                                                              |
| ------------- | ------------ | ------------------------------------------------------------------ |
| `TRUE`        | `BOOLEAN`    |                                                                    |
| `FALSE`       | `BOOLEAN`    |                                                                    |
| `NOTHING`     | `MAYBE a`    |                                                                    |
| `JUST x`      | `MAYBE a`    |                                                                    |
| `LEFT x`      | `EITHER a b` |                                                                    |
| `RIGHT y`     | `EITHER a b` |                                                                    |
| `EMPTY`       | `LIST a`     |                                                                    |
| `TODAY`       | `DATE`       | Requires `TIMEZONE IS …` at top of file                            |
| `NOW`         | `DATETIME`   | Defaults to UTC (Coordinated Universal Time) without `TIMEZONE IS` |
| `CURRENTTIME` | `TIME`       | Requires `TIMEZONE IS …`                                           |
| `TIMEZONE`    | `STRING`     | The document's declared timezone                                   |

**`TIMEZONE IS` is a document-level declaration**, not an expression:

```l4
TIMEZONE IS "Asia/Singapore"

-- Now TODAY, CURRENTTIME, and TIMEZONE all resolve to Singapore values.
```

If you use `TODAY` or `CURRENTTIME` without `TIMEZONE IS`, the compiler errors.

For reproducible evaluation, pin the clock from the command line (CLI):

```bash
l4 run --fixed-now=2025-01-01T00:00:00Z my-rules.l4
# or
JL4_FIXED_NOW=2025-01-01T00:00:00Z l4 run my-rules.l4
```

---

## Library index

**Every library requires `IMPORT`, the prelude included.** A library you import for another reason
may bring the prelude with it — `hierarchy` opens with its own `IMPORT prelude`, which is why an
outline file gets `LIST` and `map` for free — but do not rely on that. A file with no `IMPORT` line
at all does not have `sum`: it exits 1 with `I could not find a definition for the identifier / sum`
(probe `g1-no-import.l4`, and `IMPORT prelude` fixes it in `g1b-with-import.l4`).

This table is the whole set: twenty-two files, one row each, all measured to import cleanly on this
release.

| Library               | Import line                       | Purpose                                                                         |
| --------------------- | --------------------------------- | ------------------------------------------------------------------------------- |
| `prelude`             | `IMPORT prelude`                  | Lists, `MAYBE`, `Pair`, booleans, numbers, sets                                 |
| `daydate`             | `IMPORT daydate`                  | Calendar dates and day arithmetic — see the signature table below               |
| `time`                | `IMPORT time`                     | Wall-clock time-of-day operations                                               |
| `datetime`            | `IMPORT datetime`                 | Absolute points in time with timezones                                          |
| `timezone`            | `IMPORT timezone`                 | Timezone constants from the IANA (Internet Assigned Numbers Authority) database |
| `excel-date`          | ``IMPORT `excel-date` ``          | Excel serial-date compatibility                                                 |
| `date-compat`         | ``IMPORT `date-compat` ``         | Legacy `DATE` syntax compatibility                                              |
| `math`                | `IMPORT math`                     | Mathematical functions                                                          |
| `currency`            | `IMPORT currency`                 | Currency codes and their decimal places (ISO 4217) — a table, not a money type  |
| `hierarchy`           | `IMPORT hierarchy`                | Nested lists — recitals, schedules, numbered paragraphs; renders an outline     |
| `negation-as-failure` | ``IMPORT `negation-as-failure` `` | `MAYBE BOOLEAN` under an open- or closed-world default (`holds`, `naf`)         |
| `legal-persons`       | ``IMPORT `legal-persons` ``       | Legal entity types and capacity                                                 |
| `jurisdiction`        | `IMPORT jurisdiction`             | Jurisdiction definitions                                                        |
| `holdings`            | `IMPORT holdings`                 | Ownership and holdings                                                          |
| `llm`                 | `IMPORT llm`                      | Large-language-model API integration from within L4                             |
| `actus`               | `IMPORT actus`                    | ACTUS (Algorithmic Contract Types Unified Standards) — the umbrella library     |
| `actus-core`          | ``IMPORT `actus-core` ``          | ACTUS core types                                                                |
| `actus-terms`         | ``IMPORT `actus-terms` ``         | ACTUS contract terms                                                            |
| `actus-state`         | ``IMPORT `actus-state` ``         | ACTUS contract state variables                                                  |
| `actus-events`        | ``IMPORT `actus-events` ``        | ACTUS contract event types                                                      |
| `actus-schedule`      | ``IMPORT `actus-schedule` ``      | ACTUS schedule generation                                                       |
| `actus-daycount`      | ``IMPORT `actus-daycount` ``      | ACTUS day-count conventions (year fractions for interest accrual)               |

The six `actus-*` files are the parts `actus` is assembled from; import `actus` unless you want one
piece on its own.

**Filenames with a hyphen must be backtick-quoted in the `IMPORT` line**, as the table shows. A
custom library goes by file path:

```l4
IMPORT "my-custom-lib.l4"
```

Reference: <https://legalese.com/l4/reference/libraries.md>

### `hierarchy` — numbered outlines

The library area 9 of the phrasebook runs on, and the one this index used to leave out. `item`
builds a node and takes its children as further arguments; `` `render outline` scheme root ``
returns the document as a `LIST OF STRING`, one entry per node — the root's own text unnumbered as
a heading, then `"<dotted path>\t<text>"` for everything beneath it. Three
constructors pin an irregular marker, and they differ in what they do to the siblings' count:
`labeled "2b"` slots in **without** bumping (`1, 2b, 2`), `numbered "2b"` consumes a slot (`1, 2b,
3`), and `restartAt 7` resumes the count from a chosen value (`1, 2, 7, 8`).

`render outline` takes a **scheme**: a positional `LIST` of `NumberStyle`, one entry per depth.
There are exactly six constructors, and a scheme shorter than the outline is deep falls back to
`Decimal` for the levels past its end (probe `g2-numbering-styles.l4`, exit 0, eleven assertions
satisfied):

| constructor  | position 4 renders as |
| ------------ | --------------------- |
| `Decimal`    | `"4"`                 |
| `UpperAlpha` | `"D"`                 |
| `LowerAlpha` | `"d"`                 |
| `UpperRoman` | `"IV"`                |
| `LowerRoman` | `"iv"`                |
| `Bulleted`   | `"•"`                 |

`` `default scheme` `` is the conventional legal cascade,
`LIST Decimal, UpperAlpha, LowerRoman, LowerAlpha`.

For the drafting side of this — what belongs in an outline and what belongs in a rule — see area 9
of the phrasebook, [source-patterns/09-text-that-is-not-a-rule.md](source-patterns/09-text-that-is-not-a-rule.md).

### `daydate` — dates and day arithmetic

Used across four reference files and introduced in none until now. `daydate` overloads its names
heavily — `Date` has five definitions and `Day` three — so the arity you saw at one call site is not
the whole story. Types below are as the compiler printed them, either from a `#CHECK` (probe
`g4-daydate.l4`, exit 0, fourteen assertions satisfied) or from the overload listing an ambiguous
`#CHECK` produces (probe `g4c-daydate-overloads.l4`, exit 1, four listings):

| name                                  | signature                                | note                                                           |
| ------------------------------------- | ---------------------------------------- | -------------------------------------------------------------- |
| `YMD year month day`                  | `NUMBER AND NUMBER AND NUMBER TO DATE`   | big-endian and bounds-checked; write literals with this        |
| `Date day month year`                 | `NUMBER AND NUMBER AND NUMBER TO DATE`   | little-endian and lenient — it rolls and clamps                |
| `Date days`                           | `NUMBER TO DATE`                         | a day count back to a date                                     |
| `Date str`                            | `STRING TO MAYBE OF DATE`                | one of `Date`'s five definitions; `Date dt` takes a `DATETIME` |
| `Day date`                            | `DATE TO NUMBER`                         | a date to its day count                                        |
| `Day day month year`                  | `NUMBER AND NUMBER AND NUMBER TO NUMBER` | straight to a day count                                        |
| `` `add months` date n ``             | `DATE AND NUMBER TO DATE`                | date first, then the count; clamps the day of the month        |
| `` `add years` date n ``              | `DATE AND NUMBER TO DATE`                | same shape, same clamping                                      |
| `` `is weekday` date ``               | `DATE TO BOOLEAN`                        | also defined on a `NUMBER` day count                           |
| `` `is weekend` date ``               | `DATE TO BOOLEAN`                        | Saturdays and Sundays only; no library ships holidays          |
| `` `is leap year` date ``             | `DATE TO BOOLEAN`                        | also defined on a `NUMBER` year                                |
| `` `Days in month` month year ``      | `NUMBER AND NUMBER TO NUMBER`            | also on a `DATE` and on a day count                            |
| `` `Days in a year` ``                | `NUMBER`, `365.2425`                     | the **average** year; not the length of any actual year        |
| `` `Days in a month` ``               | `NUMBER`, `30.436875`                    | the **average** month; wrong for a legal period                |
| `` `Days in a week` ``                | `NUMBER`, `7`                            |                                                                |
| `` `Months in a year` ``              | `NUMBER`, `12`                           |                                                                |
| `DATE_DAY`, `DATE_MONTH`, `DATE_YEAR` | `DATE TO NUMBER`                         | built in, not from `daydate`                                   |

Three things the table cannot show, all from the same probe:

- `DATE PLUS NUMBER` yields a `DATE`; the number is a count of days.
- `DATE`s compare directly with `AT LEAST`, `AT MOST` and `EQUALS`. Do not compare a `DATE` with a
  day count.
- `add months` clamps rather than overflowing: `` `add months` (YMD 2027 1 31) 1 `` is
  `YMD 2027 2 28`. The month-subtraction footgun that follows from this is in
  [gotchas.md](gotchas.md).

**`#CHECK` is how you find a signature you do not have.** On a name with one definition it prints
the type at Information severity and costs the run nothing. On an **overloaded** name it is an
error — and the error is the documentation, because it lists every definition with its file and line
(probe `g4b-daydate-overload.l4`, exit 1):

```
There are multiple definitions for the identifier

  `is leap year`

and I do not have sufficient information to make a choice between them.
The options are:

  `is leap year` (defined at daydate.l4:564:1-15) of type FUNCTION FROM DATE TO BOOLEAN
  `is leap year` (defined at daydate.l4:555:1-15) of type FUNCTION FROM NUMBER TO BOOLEAN
```

Provoke it deliberately, read the list, then delete the `#CHECK`.

For the drafting side — "within 30 days", period boundaries, the holiday calendar — see area 4 of
the phrasebook, entry 4.12,
[source-patterns/04-dates-and-periods.md](source-patterns/04-dates-and-periods.md#e4-12).

---

## Prelude — most-used functions

Write `IMPORT prelude` first; nothing below is available without it. These are the functions you will reach for constantly. The full reference is at <https://legalese.com/l4/reference/libraries/prelude.md>.

### Numbers and aggregates

What a banded fee, an aggregate and a liability cap are made of (probe `g5-prelude-arith.l4`, exit 0, fourteen assertions satisfied).

| Function     | Type                       | Purpose                           |
| ------------ | -------------------------- | --------------------------------- |
| `min a b`    | `Number → Number → Number` | the lesser of two — a cap         |
| `max a b`    | `Number → Number → Number` | the greater of two — a floor      |
| `sum xs`     | `[Number] → Number`        | the aggregate; `sum EMPTY` is `0` |
| `product xs` | `[Number] → Number`        | `product EMPTY` is `1`            |
| `maximum xs` | `[Number] → Number`        | the largest in a list             |
| `minimum xs` | `[Number] → Number`        | the smallest in a list            |
| `and bs`     | `[Bool] → Bool`            | conjunction of a list of booleans |
| `or bs`      | `[Bool] → Bool`            | disjunction of a list of booleans |

`sum`, `product`, `and` and `or` each have one definition, so `#CHECK` on the bare name answers
(`FUNCTION FROM LIST OF NUMBER TO NUMBER`, `FUNCTION FROM LIST OF BOOLEAN TO BOOLEAN`). `min`,
`max`, `maximum` and `minimum` each have a `MAYBE`-typed twin, so `#CHECK min` is an error listing
both (probe `g5b-min-overload.l4`, exit 1) rather than an answer. Exercise those four with an
`#ASSERT` instead.

For these names as drafting phrases — "the lesser of", "the aggregate of" — see entry 3.12 of the
phrasebook, [source-patterns/03-quantities-and-calculation.md](source-patterns/03-quantities-and-calculation.md#e3-12).

### Lists

| Function           | Type                            | Purpose                |
| ------------------ | ------------------------------- | ---------------------- |
| `null list`        | `[a] → Bool`                    | Is list empty?         |
| `count list`       | `[a] → Number`                  | Length                 |
| `map f list`       | `(a→b) → [a] → [b]`             | Transform each element |
| `filter f list`    | `(a→Bool) → [a] → [a]`          | Keep matching elements |
| `foldr f z list`   | `(a→r→r) → r → [a] → r`         | Right fold             |
| `foldl f z list`   | `(r→a→r) → r → [a] → r`         | Left fold              |
| `append l1 l2`     | `[a] → [a] → [a]`               | Concatenate            |
| `concat lists`     | `[[a]] → [a]`                   | Flatten                |
| `reverse list`     | `[a] → [a]`                     |                        |
| `at list i`        | `[a] → Number → a`              | 0-based indexing       |
| `take n list`      | `Number → [a] → [a]`            | First n elements       |
| `drop n list`      | `Number → [a] → [a]`            | Drop first n           |
| `elem x list`      | `a → [a] → Bool`                | Membership             |
| `sort list`        | `[Number] → [Number]`           | Ascending              |
| `zip l1 l2`        | `[a] → [b] → [Pair a b]`        | Pair up                |
| `nub list`         | `[a] → [a]`                     | Remove duplicates      |
| `partition f list` | `(a→Bool) → [a] → Pair [a] [a]` | Split by predicate     |

### Quantifiers

```l4
all (GIVEN n YIELD n GREATER THAN 0) numbers    -- all elements positive
any (GIVEN n YIELD n EQUALS 0)      numbers     -- any element zero
```

### Maybe

```l4
CONSIDER maybeValue
WHEN NOTHING THEN defaultResult
WHEN JUST x  THEN process x
```

`fromMaybe`, `isJust`, `isNothing` are also available in the prelude.

### Lambdas with YIELD

```l4
-- Anonymous function: positive?
GIVEN n YIELD n GREATER THAN 0

-- Passed to a higher-order function
filter (GIVEN n YIELD n GREATER THAN 0) numbers
```

`YIELD` is L4's lambda. Without it you cannot pass an anonymous predicate.
