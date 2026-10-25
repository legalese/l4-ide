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
- **Always write `/`**, on every system, and never `\`. A name without a `/` is a bare module name, whatever else is in it.
- **The backticks are required.** ``IMPORT `../shared/definitions` `` works; `IMPORT ../shared/definitions` is a parse error.
- **A path names one file.** L4 looks for that file and no other: the standard library, `JL4_LIBRARY_PATH`, the session root and the per-user store are not searched, so nothing can stand in for it. If it is not there, the error says which path was tried: [I could not find a module at this path](../errors/README.md#i-could-not-find-a-module-at-this-path).
- **Two files with one name in different folders are two modules.** ``IMPORT `a/rates` `` and ``IMPORT `b/rates` `` can both appear in one program, and neither replaces the other. If both define a name you then use, L4 asks which you meant, as it does for any two imports that define the same name.
- **Two spellings of one path are one module.** `sub/../core`, `./core` and `core` all name the same file, so a definition in it is not "defined twice". L4 works this out from the words of the path, not by looking at the disk, so a symbolic link, a different capitalisation on a system that ignores capitals, or a folder name with an accented letter written once as a single character and once as a letter followed by a combining accent (the same text to the eye, two spellings to the computer) still reaches one file as two modules.
- **A path that starts with `/` is counted from the root of the project instead.** See [Importing from the root of a project](#importing-from-the-root-of-a-project).
- **A path that starts with `@` is a folder with a short name instead.** See [Importing by alias](#importing-by-alias). A relative path through a folder whose own name starts with `@` is written ``IMPORT `./@folder/mod` ``, with the `./`, for that reason.

#### Importing from the root of a project

A path that starts with `/` is counted from the **project root**, not from the file that writes the `IMPORT`:

```l4
IMPORT `/shared/definitions`
IMPORT `/subjects/vn/nouns`
```

**Example:** [rules/main.l4](project-root-example/rules/main.l4) imports [shared/definitions.l4](project-root-example/shared/definitions.l4) from the root of its project, which is marked by [l4-project.json](project-root-example/l4-project.json).

- **The project root is the folder of the nearest `l4-project.json`.** `l4` looks in the folder of the file that writes the `IMPORT`, then in the folder above it, and so on upwards, and stops at the first folder that holds a file with that name. The file can contain just `{}`: a root-relative import looks only for the file, and the one thing that reads what is inside it is an [alias](#importing-by-alias). A project inside a project has its own root, so the inner `l4-project.json` decides for the files below it.
- **The same line works from every folder of the project.** ``IMPORT `../shared/definitions` `` changes when the file that writes it moves to another folder; ``IMPORT `/shared/definitions` `` does not.
- **No `l4-project.json` above the file is an error, not a guess.** `l4` does not fall back to the folder of the file or the folder you ran it in, because the answer would then change with where you ran it: [This import is relative to the project root, but no project root was found](../errors/README.md#this-import-is-relative-to-the-project-root-but-no-project-root-was-found).
- **A leading `/` names the root of the project, not the root of the disk.**
  An absolute path from a file manager or a terminal does not work here: ``IMPORT `/Users/me/work/proj/shared/definitions` `` is looked for under the project root, as `<project root>/Users/me/work/proj/shared/definitions.l4`, and is not found.
  The error repeats the path you wrote and shows it joined onto the end of the project root: [I could not find a module at this path](../errors/README.md#i-could-not-find-a-module-at-this-path).
  Write the path from the project root instead: ``IMPORT `/shared/definitions` ``.
- **An `l4-project.json` in any folder above the file counts.**
  The search goes up to the top of the disk, and does not stop at the folder you opened, at your home folder or at the root of a git repository.
  A file left in a folder above, in your home folder by another tool say, becomes the project root of every project below it that has no file of its own.
  A root-relative import in such a project then reads files from outside the folder you opened, and says nothing.
  Put an `l4-project.json` at the top of each project, and none in a folder above your projects that you do not mean as a project root.
- **A root-relative path never leaves the project.** ``IMPORT `/../elsewhere` `` is refused, on your own machine as well as in a deployment: [This import leaves the root of this deployment](../errors/README.md#this-import-leaves-the-root-of-this-deployment). A path that starts from the importing file, such as ``IMPORT `../elsewhere` ``, may still leave the folder you started in.
  The check is made on the path as written, not on the file it reaches.
  A symbolic link inside the project that points outside it still leads out, on your own machine, because `l4` follows links.
  A deployment is not affected: the service looks for the file among the uploaded files only.
- **Leave off `.l4`, and always write `/`**, as for any path import. The backticks are required.
- **Two spellings of one file are one module.** `/identity/core`, `./core` and `../identity/core` can all name the same file, and then it is one module and nothing in it is "defined twice".
- **A deployment has no `l4-project.json` to find.** In `jl4-service` and Legalese Cloud the project root is the top of the uploaded files, and a leading `/` is counted from there. The file is needed there only for [aliases](#importing-by-alias).

**What this cannot do yet.** These are limits, not oversights:

- **The browser editor** does not have root-relative imports, as it does not have path imports. It gets both forms when the two changes that add them have both landed: this one, and the separate one that gives the browser build its own path resolver.
- **A deployed project has to be uploaded with its project root at the top of the upload.** If the folder that holds `l4-project.json` is not the top of the zip, ``IMPORT `/shared/definitions` `` is looked up from the top of the zip and not found there, though it works on your machine. Today `l4 deploy` and the VS Code deploy action put every file at the top level, whatever its folder, so they cannot deploy a project that uses either form; see [what a deployment contains](#what-a-deployment-contains). Both also upload only the entry file and the files it imports. A deploy tool that supports root-relative projects has to find the project root, the folder of the nearest `l4-project.json` above the entry file, and make that folder the top of the zip.
- **The language server does not watch `l4-project.json`.**
  The VS Code extension shows it only L4 files, so a marker counts once it is on disk.
  If you add or remove one while a file that imports from the root is open, that file keeps the project root it found until you type a change in it.
  Saving that file, closing and reopening it, and editing another file do not make it look again.
  That was measured with a scripted client against the built language server on 2026-10-26, and not in VS Code itself.
  `l4 check` always looks afresh.
- **A project inside a project is read differently by `l4` and by a deployment.**
  `l4` takes the nearest `l4-project.json`, so a folder that holds its own file has its own project root.
  A deployment takes the top of the uploaded files and looks for no other file, so the same files can name one file on your machine and another one there.
  Nothing refuses it and nothing warns of it, and the deployment says `ready`.

#### Importing by alias

A project that keeps its shared rules deep in a folder tree can give a folder a short name, an **alias**, and import from it by that name:

```l4
IMPORT `@common/definitions`
IMPORT `@vn10/nouns`
```

The aliases are written in the `l4-project.json` that marks the root of the project:

```json
{ "aliases": { "common": "shared", "vn10": "subjects/vn/nd67" } }
```

**Example:** [rules/main.l4](alias-example/rules/main.l4) imports [shared/definitions.l4](alias-example/shared/definitions.l4) by the alias `common` and [nouns.l4](alias-example/subjects/vn/nd67/nouns.l4) by the alias `vn10`, which [l4-project.json](alias-example/l4-project.json) defines.

- **An alias stands for a folder.**
  `@vn10/nouns` is the file `nouns.l4` in the folder that `vn10` stands for.
  The folder is written from the folder that holds `l4-project.json`, which is the project root, and it has to be inside the project.
  Leave off `.l4` after the file, as for any path import.
- **The name starts with `@` and has a `/` after the alias.**
  A name like ``IMPORT `@vn10` ``, with no `/`, is not an alias import: it is read as a module called `@vn10`, as it always was.
- **The aliases come from the nearest `l4-project.json`**, found as the project root is (see above), and from that file alone.
  A project inside a project has its own aliases, and does not inherit its outer project's.
  That is so for `l4`; a deployment reads the file at the top of the uploaded files instead (see the limits below).
- **An alias that is not defined is an error that lists the ones that are:** [This import uses an alias that is not defined](../errors/README.md#this-import-uses-an-alias-that-is-not-defined).
- **An alias cannot stand for another alias.**
  A folder that starts with `@` is refused; to name a folder that really starts with `@`, write it with `./`: `"./@common"`.
  See [An alias in l4-project.json cannot be used](../errors/README.md#an-alias-in-l4-projectjson-cannot-be-used).
- **If an alias is written twice, the first one is used.**
  Another program that reads the same file as JSON, a deploy tool or an editor written in TypeScript say, may use the last one.
- **The file has to be JSON.**
  A file that is not JSON, or an `aliases` that is not an object of folders written as text, is an error that names the file and says where: [I could not read the project file](../errors/README.md#i-could-not-read-the-project-file).
  Keys other than `aliases` are ignored.
  On your own machine, L4 opens the file only when an alias import needs it, so an `l4-project.json` that does not parse breaks the imports that use an alias and nothing else.
  In a deployment a file like that can reject the whole deployment: the service reads every uploaded file as L4 first, and a line of the file that L4 takes for an annotation, such as `@exprot foo`, refuses the upload.
  Valid JSON was not affected in any file tried, because an `@` inside a JSON string is part of the string.
- **An alias never leads out of the project.**
  A folder that climbs above the project root is refused, and so is a path under the alias that does: ``IMPORT `@common/../../elsewhere` ``.
  Both are refused on your own machine as well as in a deployment.
  A path under an alias may use `..` to reach another folder of the project.
  The check is made on the folder and the path as written, not on the file they reach.
  A symbolic link inside the project that points outside it still leads out, on your own machine, because `l4` follows links.
  A deployment is not affected: the service looks for the file among the uploaded files only.
- **Two spellings of one file are one module.**
  `@common/core`, `/shared/core` and `../shared/core` can all name the same file, and then it is one module and nothing in it is "defined twice".
- **In a deployment the aliases come from the `l4-project.json` at the top of the uploaded files.**
  The service does not search for another one, and it keeps the file with the sources across a restart.
  A deployment whose top holds none says so: [This import uses an alias, but there is no project file to read it from](../errors/README.md#this-import-uses-an-alias-but-there-is-no-project-file-to-read-it-from).

**What this cannot do yet.** These are limits, not oversights, and they are the limits of the root-relative form as well:

- **The browser editor** does not have aliases, as it does not have root-relative imports.
  It gets both when the changes that add them have both landed.
- **A deployed project has to be uploaded with its project root, and its `l4-project.json`, at the top of the upload.**
  `l4 deploy` and the VS Code deploy action put every file at the top level, whatever its folder, so they cannot build such an upload today.
  They also upload only the entry file and the files it imports, so neither would upload the `l4-project.json` even with folders kept.
  A deploy tool that supports alias projects has to add the nearest `l4-project.json` itself and make its folder the top of the zip.
- **The language server does not watch `l4-project.json`.**
  The VS Code extension shows it only L4 files, so the file counts once it is on disk.
  An alias you add, remove or change while a file that uses it is open is not noticed until you type a change in that file.
  Saving that file, closing and reopening it, and editing another file did not make the language server read the project file again when this was measured with a scripted client on 2026-10-26; VS Code itself was not tried.
  `l4 check` always checks afresh.
- **A project inside a project reads its aliases from different files in `l4` and in a deployment.**
  `l4` reads the nearest `l4-project.json`, and the service reads the one at the top of the uploaded files and no other.
  An alias that only the inner file defines is then not defined in the deployment, and an alias that both define can stand for a different folder there.
  The deployment is accepted either way, with at most a warning in the service's log, as for the project root above.
- **A deployed bundle that cannot resolve an alias import is accepted**, as it is for any import that finds nothing, and the only trace is a warning in the service's log.

#### Where path imports work, and where they do not

| where you run the file                                         | what a path import does                                                                                                                                                                                         |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `l4` on your machine, MLIR, the VS Code editor                 | Works. The path may leave the folder of the file you started from: `cases/main.l4` can import `../domain`. Whatever your account can read, a path can reach.                                                    |
| the REPL (`jl4-repl`)                                          | Works only when the REPL is started in the loaded file's own folder. It evaluates through a copy kept in the folder it was started in, so every import in a loaded file, bare or path, is looked up from there. |
| a deployment on `jl4-service` or Legalese Cloud                | Works **inside the files you deployed**. A path that would climb above them is refused, and the service never reads its own disk for it. See [what a deployment contains](#what-a-deployment-contains).         |
| the browser editor, and anything else built on the WASM module | **Not yet.** A browser document has no folder to be relative to, so a path import there does not work.                                                                                                          |

An imported module's own bare-name imports are not affected: inside `mod.l4`, `IMPORT prelude` still finds the standard library, and `IMPORT helper` still finds `helper.l4` beside `mod.l4`.

##### What a deployment contains

A deployment is the set of files that were uploaded, and a path import can only name a file in that set, relative to the importing file's folder. Upload `rows/a/main.l4` and `rows/b/mod.l4` together and ``IMPORT `../b/mod` `` works; upload only the first and the import finds nothing.

**Today the two deploy tools do not upload folders.** `l4 deploy` and the VS Code deploy action put every file at the top of the upload, named by file name alone. A project that imports by path therefore checks and runs on your machine, deploys without complaint, and then fails in the deployed copy: the service cannot find `../b/mod` among files that are all at the top. Until those tools keep the folder structure, deploy such a project by uploading a zip that does (`POST /deployments` on `jl4-service`).

**The deploy does not tell you.** When a path import finds nothing in a deployment, whether it names a file that was not uploaded or climbs out of the upload, the service accepts the deployment and writes a warning to its log (`Bundle IMPORT resolves to nothing`, naming the file and the import). The names the missing file should have supplied are then reported as undefined, which the compiler may turn into extra inputs of the deployed function. This is how an `IMPORT` of a bare name that finds nothing already behaved.

### What an import gives you

- Every top-level definition of the imported file: its types, constructors, functions and constants.
- Nothing is imported for you. A file that uses `map`, `sum` or `fromMaybe` needs `IMPORT prelude` like any other library.
- Import each library you use by name. The definitions a library imports for itself also reach your file, but do not count on it: `IMPORT datetime`, for example, does not give you `Date`; that needs `IMPORT daydate`.

### Where modules are found

For `IMPORT helpers`, L4 uses the first of these that exists:

1. `helpers.l4` in the **session root**, or in the folder of the file that writes the `IMPORT`. The session root is the folder `l4` starts from: the folder of the file you name on the command line, the folder the editor's language server was started in, or the working directory of the REPL.
2. The standard library built into the `l4` you are running. It needs no files on disk and always matches that `l4`.

The session root is not the [project root](#importing-from-the-root-of-a-project): an `l4-project.json` does not change where a bare name is looked for.

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
