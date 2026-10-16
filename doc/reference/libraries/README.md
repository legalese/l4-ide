# Standard libraries

The standard libraries are L4 files that ship with every `l4` binary, the editor extension and Legalese Cloud. They are written in L4 and add functions for lists, dates, money, legal entities and more. Nothing from them is available until you `IMPORT` it, not even the prelude.

Functions built into the language, such as `TOSTRING`, `CONCAT` or `FETCH`, need no import: see [Built-in functions](../builtins/README.md).

## Libraries

### Core

- [prelude](prelude.md): lists, MAYBE and EITHER values, pairs and dictionaries.
- [math](math.md): `exp`, logarithms, square roots and trigonometry that give `NOTHING` instead of failing on bad input.

### Dates and time

- [daydate](daydate.md): build, compare and shift dates; weekdays, ISO weeks, months and leap years. Its page also covers `date-compat`, the older `DATE d m y` spelling.
- [time](time.md): time of day without a date or time zone, in 24-hour or AM/PM form.
- [datetime](datetime.md): a date, a time and a time zone together, compared across time zones.
- [timezone](timezone.md): constants such as `SGT` and `EST` for IANA time zone names.
- [excel-date](excel-date.md): Excel date serials and `DATEDIF`, `DAYS360`, `YEARFRAC`, `EDATE`, `EOMONTH`, `WORKDAY` and `NETWORKDAYS`.

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

### What an import gives you

- Every top-level definition of the imported file: its types, constructors, functions and constants.
- Nothing is imported for you. A file that uses `map`, `sum` or `fromMaybe` needs `IMPORT prelude` like any other library.
- Import each library you use by name. The definitions a library imports for itself also reach your file, but do not count on it: `IMPORT datetime`, for example, does not give you `Date`; that needs `IMPORT daydate`.

### Where modules are found

For `IMPORT helpers`, L4 uses the first of these that exists:

1. `helpers.l4` in your project's root folder, or in the folder of the file that writes the `IMPORT`.
2. The standard library built into the `l4` you are running. It needs no files on disk and always matches that `l4`.

So a file of your own with the name of a standard library, such as `prelude.l4` beside your rules, is used instead of the standard one. Operators and library developers can change the search with the `JL4_LIBRARY_PATH` environment variable; [How IMPORT finds libraries](resolution.md) gives the full order, what Legalese Cloud does, and the warning shown when two different copies of a module are visible. When nothing is found, the error is [Module not found](../errors/README.md#module-not-found).
