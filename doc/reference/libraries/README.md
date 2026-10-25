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
- A module name is a name, not a quoted string: `IMPORT "helpers.l4"` is a parse error. To import a file from another folder, write its path in backticks, with a slash: ``IMPORT `../shared/helpers` ``. See [Importing a file from another folder](#importing-a-file-from-another-folder).
- A name with a dot or an extension, such as ``IMPORT `helpers.l4` `` or `IMPORT helpers.v2`, is still read as a bare module name, cut at its last dot, so both mean `IMPORT helpers`. The import works as it always did, and `l4 check` now warns that the name written is not the module found. Write `IMPORT helpers` and the warning goes away.
- A basename with spaces or non-ASCII letters goes in backticks too: ``IMPORT `my helpers` `` and ``IMPORT `hvac-law-he` ``. On a build older than the fix for [smucclaw/l4-ide#971](https://github.com/smucclaw/l4-ide/issues/971) these resolved to nothing, and said nothing about it; see [Module names that are not plain ASCII](resolution.md#module-names-that-are-not-plain-ascii).

### Importing a file from another folder

A module in another folder is imported by its path, written in backticks with a slash:

```l4
IMPORT `../shared/definitions`
IMPORT `./helpers`
IMPORT `rules/section-3`
```

**Example:** [rules/main.l4](path-import-example/rules/main.l4) imports [shared/definitions.l4](path-import-example/shared/definitions.l4) from the folder beside its own.

- **The path starts from the file that writes the `IMPORT`**, not from the folder you run `l4` in. `..` is the folder above and `.` is this one. The same file means the same thing whoever runs it, and from wherever they run it.
- **Leave off `.l4`.** ``IMPORT `../shared/definitions.l4` `` names the same file.
- **Always write `/`**, on every system. A backslash is an ordinary letter in a name.
- **The backticks are required.** ``IMPORT `../shared/definitions` `` works; `IMPORT ../shared/definitions` is a parse error.
- **A path names one file.** L4 looks for that file and no other: the standard library, `JL4_LIBRARY_PATH`, the project root and the per-user store are not searched, so nothing can stand in for it. If it is not there, the error says which path was tried: [I could not find a module at this path](../errors/README.md#i-could-not-find-a-module-at-this-path).
- **Two files with one name in different folders are two modules.** ``IMPORT `a/rates` `` and ``IMPORT `b/rates` `` can both appear in one program, and neither replaces the other. If both define a name you then use, L4 asks which you meant, as it does for any two imports that define the same name.
- **One file is one module, however it was reached.** `sub/../core` and `core` are the same file, so a definition in it is not "defined twice".
- **A path cannot start with `/`.** A leading slash is reserved and refused: [This import leaves the root of this deployment](../errors/README.md#this-import-leaves-the-root-of-this-deployment).

#### Where path imports work, and where they do not

| where you run the file                                         | what a path import does                                                                                                                                                                             |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `l4` on your machine, the REPL, the VS Code editor             | Works. The path may leave the folder of the file you started from: `cases/main.l4` can import `../domain`. Whatever your account can read, a path can reach.                                        |
| a deployment on `jl4-service` or Legalese Cloud                | Works **inside the files you deployed**. A path that would climb above them is refused, and the service never looks at its own disk. See [what a deployment contains](#what-a-deployment-contains). |
| the browser editor, and anything else built on the WASM module | **Not yet.** A browser document has no folder to be relative to, so a path import there does not work.                                                                                              |

An imported module's own bare-name imports are not affected: inside `mod.l4`, `IMPORT prelude` still finds the standard library, and `IMPORT helper` still finds `helper.l4` beside `mod.l4`.

##### What a deployment contains

A deployment is the set of files that were uploaded, and a path import can only name a file in that set, relative to the importing file's folder. Upload `rows/a/main.l4` and `rows/b/mod.l4` together and ``IMPORT `../b/mod` `` works; upload only the first and it is reported missing.

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
