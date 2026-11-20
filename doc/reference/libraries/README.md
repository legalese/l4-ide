# Standard libraries

The standard libraries are L4 files that ship with every `l4` binary, the editor extension and Legalese Cloud. They are written in L4 and add functions for lists, dates, money, legal entities and more. Nothing from them is available until you `IMPORT` it, not even the prelude.

Functions built into the language, such as `TOSTRING`, `CONCAT` or `FETCH`, need no import: see [Built-in functions](../builtins/README.md).

## Libraries

### Core

- [prelude](prelude.md): lists, MAYBE and EITHER values, pairs and dictionaries.
- [sets](sets.md): `SET OF a`, `UNION`, `INTERSECT` and difference, and the set-aware `PLUS` and `MINUS`. Part of the prelude.
- [negation-as-failure](negation-as-failure.md): `holds`, `naf` and `presumed` over `MAYBE BOOLEAN`. It imports the prelude itself, so ``IMPORT `negation-as-failure` `` alone is enough.
- [math](math.md): `exp`, logarithms, square roots and trigonometry that give `NOTHING` instead of failing on bad input.

### Dates and time

- [daydate](daydate.md): build, compare and shift dates; weekdays, ISO weeks, months and leap years. Its page also covers `date-compat`, the older `DATE d m y` spelling.
- [time](time.md): time of day without a date or time zone, in 24-hour or AM/PM form.
- [datetime](datetime.md): a date, a time and a time zone together, compared across time zones.
- [timezone](timezone.md): constants such as `SGT` and `EST` for IANA time zone names.
- [excel-date](excel-date.md): Excel date serials and `DATEDIF`, `DAYS360`, `YEARFRAC`, `EDATE`, `EOMONTH`, `WORKDAY` and `NETWORKDAYS`.
- [calendar](calendar.md): business days, public-holiday lists, and the conventions that move a deadline off a weekend or holiday. A draft; the names were ruled on 24 October 2026.

### Money and finance

- [currency](currency.md): amounts in whole minor units (cents) with ISO 4217 currency codes.
- [holdings](holdings.md): cap tables, vesting, convertible notes and SAFEs, liquidation preferences and valuations.
- [actus](actus.md): ACTUS financial contract types, events, day count conventions and schedules.

### Legal entities and places

- [legal-persons](legal-persons.md): names, addresses, identity documents, age and legal capacity, corporate entities and beneficial ownership.
- [jurisdiction](jurisdiction.md): ISO 3166 country and subdivision codes, with checks and conversions.

### AI

- [llm](llm.md): call Anthropic, OpenAI or OpenRouter models over HTTP.

## IMPORT

`IMPORT` makes the definitions of another L4 file available in the current file. Put the `IMPORT` lines at the top of the file, before the first `§` section, one module per line. An `IMPORT` below a section heading is ignored without a warning: the names it should bring in are then reported as [not defined](../errors/README.md#i-could-not-find-a-definition-for-the-identifier).

**Example:** [import-example.l4](import-example.l4)

```l4
IMPORT prelude
IMPORT daydate
IMPORT `legal-persons`
```

### Module names

- A module is named by its file name without `.l4`: `IMPORT daydate` loads `daydate.l4`.
- A name with a hyphen goes in backticks: ``IMPORT `excel-date` ``, ``IMPORT `legal-persons` ``, ``IMPORT `date-compat` ``. Without them, `IMPORT excel-date` is a parse error ("unexpected -").
- `IMPORT` takes a module name, not a path or a quoted string. `IMPORT "helpers.l4"` is a parse error, and a folder in front of the name is ignored: ``IMPORT `rules/helpers` `` looks for `helpers.l4`.
- A basename with spaces or non-ASCII letters goes in backticks too: ``IMPORT `my helpers` `` and ``IMPORT `hvac-law-he` ``. On a build older than the fix for [smucclaw/l4-ide#971](https://github.com/smucclaw/l4-ide/issues/971) these resolved to nothing, and said nothing about it; see [Module names that are not plain ASCII](resolution.md#module-names-that-are-not-plain-ascii).

### What an import gives you

- Every top-level definition of the imported file: its types, constructors, functions and constants.
- Nothing is imported for you. A file that uses `map`, `sum` or `fromMaybe` needs `IMPORT prelude` like any other library.
- Import each library you use by name. The definitions a library imports for itself also reach your file, but do not count on it: `IMPORT datetime`, for example, does not give you `Date`; that needs `IMPORT daydate`.

### Where modules are found

For `IMPORT helpers`, L4 uses the first of these that exists:

1. `helpers.l4` in your project's root folder, or in the folder of the file that writes the `IMPORT`.
2. The standard library built into the `l4` you are running. It needs no files on disk and always matches that `l4`.

So a file of your own with the name of a standard library, such as `prelude.l4` beside your rules, is used instead of the standard one. Operators and library developers can change the search with the `JL4_LIBRARY_PATH` environment variable; [How IMPORT finds libraries](resolution.md) gives the full order, what Legalese Cloud does, and the warning shown when two different copies of a module are visible. When nothing is found, the error is [Module not found](../errors/README.md#module-not-found).
An `IMPORT` that resolves to nothing is an error even if your file never uses anything from it: the message names the module and every location that was searched.
It fails `l4 check` and `l4 run`; other commands print it and still exit 0.
See [When nothing resolves](resolution.md#when-nothing-resolves).

### When an imported name clashes with one of your own

A library hands you its definitions under the names its author chose.
If you happen to define something under the same name, and of the same shape, so that the compiler cannot tell the two apart by what goes in and what comes out, L4 does not guess which you meant.
It stops and asks:

```text
There are multiple definitions for the identifier

  EULER

and I do not have sufficient information to make a choice between them.
The options are:

  `Local Section`.EULER (defined at my-rules.l4:14:1-6) of type NUMBER
  Math.Constants.EULER (defined at math.l4:12:1-6) of type NUMBER
```

Each option is written out under the headings it sits beneath, in the file that defines it, joined by dots.
That longer form is the definition's **full name**, and it is the answer to the question the error is asking.
Write the full name of the one you meant, and the ambiguity is gone:

```l4
IMPORT math

§ `Local Section`
GIVETH A NUMBER
EULER MEANS 3

#EVAL Math.Constants.EULER    -- 2.718281828459045, the library's
#EVAL `Local Section`.EULER   -- 3, your own
```

Two things are worth knowing about full names.

**They reach across an `IMPORT`.**
The headings you write are the ones in the file where the definition lives, `§ Math` and `§§ Constants` in `math.l4` above, not headings in your own file.
You never name the library itself; the error message shows you the headings to use.

**A heading whose name contains spaces keeps its backticks**, exactly as the error prints them, so a full name can be copied out of an error message and pasted into your rules unchanged:

```l4
IMPORT prelude

#EVAL Prelude.`Numeric Aggregates`.sum (LIST 1, 2)   -- 3
```

Elsewhere you may see a full name called a _qualified name_; they are the same thing.
