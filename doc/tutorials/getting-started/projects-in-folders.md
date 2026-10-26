# Split a project into folders

_Status (2026-10-26): **proposed, not landed.**
Nothing on this page works in a released version of L4 yet.
Importing a file from another folder is built in draft pull request legalese/l4-ide#748.
Importing from the project root, and importing by alias, are built in draft pull request legalese/l4-ide#751, which builds on top of #748.
This page becomes true when both have merged and you are running an L4 that contains them; until then, a released L4 is not promised to read the `IMPORT` lines taught here.
Deploying such a project is a separate piece, draft pull request legalese/l4-ide#749, and it is not part of the branch this page was written against; see [What does not work yet](#what-does-not-work-yet).
Every command and message shown below was run on 2026-10-26 with the `l4` built from the #751 branch, on a Mac; where a sentence rests on the reference pages instead of a run, it says so.
Nothing was run on Windows; the section [If you work on Windows](#if-you-work-on-windows) says what that means for you._

You have written a few single-file L4 programs.
A single file is easy to open, easy to email and easy to check, and for one short instrument it is the right shape.
A real project grows.
The same definitions are wanted by several rules, two people want to work at once, and the file you scroll through is longer than the statute it encodes.

This tutorial splits one file into a small project of folders, and teaches the three ways one file can say "use the definitions in that other file".
The story is one you can follow with a text editor and the `l4` command: Alex is drafting rules for a residential tenancy.

**Before you start:** [Install L4 and write your first rule](first-l4-file.md), and be comfortable running `l4 check` and `l4 run` on a file.

---

## Where we are going

By the end, Alex's project is five files, spread over the folder `tenancy-rules` and the three folders inside it:

```
tenancy-rules/
├── l4-project.json
├── shared/
│   └── terms.l4
└── rules/
    ├── notice.l4
    ├── deposit.l4
    └── arrears/
        └── late-fee.l4
```

The finished project is kept in this manual as [projects-in-folders-example](projects-in-folders-example/l4-project.json); wherever the story says `tenancy-rules/`, that is the folder.
Its files are [l4-project.json](projects-in-folders-example/l4-project.json), [shared/terms.l4](projects-in-folders-example/shared/terms.l4), [rules/notice.l4](projects-in-folders-example/rules/notice.l4), [rules/deposit.l4](projects-in-folders-example/rules/deposit.l4) and [rules/arrears/late-fee.l4](projects-in-folders-example/rules/arrears/late-fee.l4).

A word that appears in L4's messages: L4 calls a file that you import a **module**.
The word is only a name for "a file whose definitions another file borrows".

---

## 1. One file that has grown

Alex starts with everything in one file, `tenancy.l4`.
Three numbers sit at the top, and one rule uses the first of them:

```l4
-- Tenancy rules, all in one file.

`notice period in days` MEANS 30
`deposit cap in months of rent` MEANS 2
`grace period in days` MEANS 5

GIVEN `days of notice given` IS A NUMBER
GIVETH A BOOLEAN
DECIDE `notice is long enough` IF `days of notice given` AT LEAST `notice period in days`

#EVAL `notice is long enough` 45
#EVAL `notice is long enough` 10
```

```bash
l4 run tenancy.l4
```

```
Evaluation[1] @ tenancy.l4:11:1-33

Result:
  TRUE
...

Evaluation[2] @ tenancy.l4:12:1-33

Result:
  FALSE
...
```

(The `...` stands for a `Trace:` note that `l4 run` prints under each result, which this tutorial leaves out.)
Forty-five days of notice is long enough and ten is not.

Two more rules are coming, one for the deposit and one for late fees, and both need the numbers at the top.
Alex would rather keep the numbers in one place and let each rule file borrow them.

---

## 2. Split it into two folders

Alex makes a folder called `tenancy-rules`, and inside it two folders: `shared` for what several rules use, and `rules` for the rules themselves.

```
tenancy-rules/
├── shared/
│   └── terms.l4
└── rules/
    └── notice.l4
```

The three numbers move to `shared/terms.l4` ([the file](projects-in-folders-example/shared/terms.l4)):

```l4
-- The numbers that the tenancy rules share, kept in one place.
-- The rule files in ../rules import this file in three different spellings.

`notice period in days` MEANS 30
`deposit cap in months of rent` MEANS 2
`grace period in days` MEANS 5
```

The rule stays in `rules/notice.l4` ([the file](projects-in-folders-example/rules/notice.l4)), with one new line near the top:

```l4
-- How much notice a landlord must give a tenant.
-- Imports the shared terms by a path that starts from THIS file's folder:
-- `..` is the folder above (the project), then `shared`, then `terms`.
IMPORT `../shared/terms`

GIVEN `days of notice given` IS A NUMBER
GIVETH A BOOLEAN
DECIDE `notice is long enough` IF `days of notice given` AT LEAST `notice period in days`

#EVAL `notice is long enough` 45
#EVAL `notice is long enough` 10
```

Alex runs it from inside the `tenancy-rules` folder:

```bash
l4 check rules/notice.l4
```

```
Check succeeded.
```

`l4 check` ends with exit status 0 when the file is fine, and `l4 run rules/notice.l4` gives the same two results as before.

### What the `IMPORT` line says

Read ``IMPORT `../shared/terms` `` from left to right:

- `IMPORT` brings the definitions of another file into this one.
  Nothing from another file is available until you import it.
- The name is in **backticks** because it contains slashes.
  The backticks are required; without them the line is an error (see [Forgetting the backticks](#forgetting-the-backticks)).
- `..` means "go up one folder".
  `notice.l4` lives in `rules/`, so `..` is `tenancy-rules/`.
- `shared/terms` goes down into the folder `shared` and picks the file `terms`.
  You leave off `.l4`.
  Writing it, as in ``IMPORT `../shared/terms.l4` ``, names the same file and was accepted without a message.
- A **path** is just the address of a file: the folders to go through, written with slashes between them.
  `.` means "this folder" and `..` means "the folder above".

**The path starts from the file that writes the `IMPORT`**, and not from the folder you are standing in when you type the `l4` command.
Alex ran `l4 check` on this file three ways, from the folder above `tenancy-rules` (`l4 check tenancy-rules/rules/notice.l4`), from inside `rules` (`l4 check notice.l4`) and from inside `tenancy-rules`, and each printed `Check succeeded.`.
The same file therefore means the same thing to whoever runs it, from wherever they run it.

The reference describes this form in [Importing a file from another folder](../../reference/libraries/README.md#importing-a-file-from-another-folder), and [Path imports](../../reference/libraries/resolution.md#path-imports) says exactly how a path is worked out.

---

## 3. When a file moves, a path from the file breaks

The `rules` folder is getting crowded.
Alex moves `notice.l4` into a new folder, `rules/notices/`, and checks it again:

```bash
l4 check rules/notices/notice.l4
```

It fails (exit status 1), and the first message says:

```
I could not find a module at this path: ../shared/terms
Nothing it defines is in scope here; names you expected from it are reported as undefined.
Relative to rules/notices/notice.l4 that is rules/shared/terms.l4, which does not exist.
```

The file did not change, but `..` now means `rules/`, and there is no `rules/shared/`.
Writing ``IMPORT `../../shared/terms` `` fixes it (two steps up, not one), and `l4 check` then prints `Check succeeded.`.
But every file that moves needs its `IMPORT` lines rewritten, and a mistake does not show until someone checks the file.

That is what the next two sections are for: a way to say "from the top of the project" and a way to give a folder a short name.
Both keep working when the file that writes them moves.

---

## 4. Import from the project root

Alex now writes `rules/deposit.l4` ([the file](projects-in-folders-example/rules/deposit.l4)) with a different kind of `IMPORT` line:

```l4
-- How large a deposit a landlord may ask for.
-- Imports the shared terms by their place in the PROJECT: the leading slash
-- means "from the folder that holds l4-project.json".
IMPORT `/shared/terms`

GIVEN `monthly rent` IS A NUMBER
      `deposit asked` IS A NUMBER
GIVETH A BOOLEAN
DECIDE `deposit is within the cap` IF `deposit asked` AT MOST `monthly rent` TIMES `deposit cap in months of rent`

#EVAL `deposit is within the cap` 1000 1800
#EVAL `deposit is within the cap` 1000 2500
```

A name that starts with a slash is counted from the **project root**: the top folder of the project, `tenancy-rules/`.
It does not matter which folder `deposit.l4` is in.
Alex moved it into `rules/deposits/` and the same line still worked: `l4 check rules/deposits/deposit.l4` printed `Check succeeded.`.

### What the project root is

The project root is the folder of the nearest file named `l4-project.json`.
"Nearest" means this: starting in the folder of the file that writes the `IMPORT`, L4 looks for a file with that name; if there is none, it looks in the folder above, and so on upwards, and the first folder that holds one is the project root.
It looks upwards from the importing file, not from the folder you ran `l4` in.

The project file is how you tell L4 where your project begins, so the folder it sits in is the one the `/` means.
**To create it,** make a new plain-text file in the top folder of the project, `tenancy-rules/`, name it exactly `l4-project.json`, and type these two characters into it:

```json
{}
```

That is all a root import needs: L4 only looks for the file, and does not read what is in it.
The file is written in JavaScript Object Notation (JSON), a plain-text way of writing a list of named things between curly braces; `{}` is the list with nothing in it.
The next section puts something in it.
The name has to be exactly `l4-project.json`: a file called `l4-project.json.txt` is a different file, and L4 will not see it.

Without a project file, a root import is an error, not a guess; see [No project root](#no-l4-projectjson-above-the-file).
The reference describes this form in [Importing from the root of a project](../../reference/libraries/README.md#importing-from-the-root-of-a-project).

**A leading `/` is the top of the project, never the top of your drive.**
Writing a full address from your file manager, such as ``IMPORT `/Users/alex/tenancy-rules/shared/terms` ``, does not work: L4 looks for `Users/alex/tenancy-rules/shared/terms.l4` under the project root, and says it does not exist.

---

## 5. Give a folder a short name: aliases

Deep in a real project the shared files can sit many folders down.
An **alias** is a short name for a folder.
You write the aliases in the project file, so the file Alex made now gets something in it ([the file](projects-in-folders-example/l4-project.json)):

```json
{ "aliases": { "common": "shared" } }
```

Read it as: `aliases` is a list, and in that list the name `common` stands for the folder `shared`.
The folder is written from the folder that holds the project file, so `"shared"` is `tenancy-rules/shared`.

An `IMPORT` uses an alias by starting with `@`.
Alex's third rule, `rules/arrears/late-fee.l4` ([the file](projects-in-folders-example/rules/arrears/late-fee.l4)), sits one folder deeper than the others:

```l4
-- When a landlord may charge a late fee.
-- Imports the shared terms by an alias: `common` is a short name for the
-- folder `shared`, defined in l4-project.json. This file is one folder deeper
-- than the others, and its import line is the same as it would be anywhere.
IMPORT `@common/terms`

GIVEN `days late` IS A NUMBER
GIVETH A BOOLEAN
DECIDE `a late fee may be charged` IF `days late` GREATER THAN `grace period in days`

#EVAL `a late fee may be charged` 3
#EVAL `a late fee may be charged` 12
```

``IMPORT `@common/terms` `` reads as: the file `terms`, in the folder that `common` stands for.
Like the other forms, it works wherever the importing file is: Alex moved `late-fee.l4` to a different folder and it still printed `Check succeeded.`.

An alias pays off when the shared folder itself moves.
Alex moved `shared/` to `library/tenancy-terms/`, changed one line of the project file to `{ "aliases": { "common": "library/tenancy-terms" } }`, and `late-fee.l4`, untouched, printed `Check succeeded.`.
With the other two spellings every importing file would have been edited.

Some things to know about the project file:

- The aliases come from the nearest `l4-project.json`, found as in the last section, and from that file alone.
- Keys other than `aliases` are ignored, so the file can also hold notes for yourself.
- L4 reads the contents of the file only when an alias import needs it.
  A root import such as ``IMPORT `/shared/terms` `` works even when the file is not valid JSON, and only the alias imports break.
- An alias is written with `@`, then the alias, then a `/`, then the path under the folder it stands for.
  ``IMPORT `@common` `` with no slash is not an alias import.
- A project file saved with Windows-style line endings and with a byte-order mark (a few invisible bytes that some programs put at the start of a text file) was read correctly; this was tried on a Mac, see [If you work on Windows](#if-you-work-on-windows).

The reference describes this form in [Importing by alias](../../reference/libraries/README.md#importing-by-alias).

---

## 6. Which spelling to use

All three spellings reach the same file, and L4 treats two spellings of one file as one module, so a name it defines is not "defined twice".
They differ in what they are counted from, and in what breaks when something moves.

| spelling                      | counted from                                | the importing file moves | the shared file moves                        | needs                               |
| ----------------------------- | ------------------------------------------- | ------------------------ | -------------------------------------------- | ----------------------------------- |
| ``IMPORT `../shared/terms` `` | the folder of the file that writes the line | breaks (section 3)       | breaks                                       | nothing                             |
| ``IMPORT `/shared/terms` ``   | the project root                            | keeps working            | breaks                                       | an `l4-project.json`, can be `{}`   |
| ``IMPORT `@common/terms` ``   | the folder the alias stands for             | keeps working            | keeps working if you change the alias's line | an `l4-project.json` with the alias |

If two files sit side by side and will stay there, a path from the file is enough.
If many files in many folders import the same file, the root form or an alias saves editing each of them when they move.

---

## Messages you will see

Every message below was produced by running `l4 check` on the file named, from inside the `tenancy-rules` folder, after changing one thing in an otherwise working project.
`l4 check` prints its messages after lines that begin `Info | updateFileDiagnostics`, around details such as `Range:` and `Severity:`, and it prints the same message more than once.
Each block below is the text under `Message:`, with its indentation removed.
The editor draws its red underline from the same checker; the command line is used here because its output can be copied onto a page.
Where a message printed the full address of a folder on the machine it ran on, this page shows `…` in its place, because that address starts differently on every machine.

**Read the first message, not the last.**
A missing import also makes L4 complain about every name the missing file would have supplied, for example `I could not find a definition for the identifier` followed by `` `notice period in days` ``, and about a comparison it can no longer tell the kind of (`There are multiple definitions for the identifier`, followed by `` `__GEQ__` ``).
Those follow from the first message, and they go away when it is fixed.
Each failing case below ended with exit status 1.

### A path that finds no module

Alex mistyped the file name, `` IMPORT `../shared/term` ``:

```bash
l4 check rules/notice.l4
```

```
I could not find a module at this path: ../shared/term
Nothing it defines is in scope here; names you expected from it are reported as undefined.
Relative to rules/notice.l4 that is shared/term.l4, which does not exist.
```

The first line repeats what you wrote.
The last line says which file L4 looked for, with `.l4` added and the `..` worked out, written from the folder you ran `l4` in.
Compare it with where the file really is.
Forgetting the `..` is the other usual cause: with `` IMPORT `shared/terms` `` in `rules/notice.l4`, the last line reads `Relative to rules/notice.l4 that is rules/shared/terms.l4, which does not exist.`, which shows it looking in `rules/shared/`.

For a root import the last line names the project root instead, and for an alias it also names the folder the alias stands for.
With the alias folder mistyped as `"sharde"` in the project file, `late-fee.l4` gave:

```
I could not find a module at this path: @common/terms
Nothing it defines is in scope here; names you expected from it are reported as undefined.
The alias @common stands for sharde (in …/tenancy-rules/l4-project.json); relative to the project root …/tenancy-rules that is sharde/terms.l4, which does not exist.
```

The reference entry is [I could not find a module at this path](../../reference/errors/README.md#i-could-not-find-a-module-at-this-path).

### An import that leaves the project root

A root import may not climb above the project.
Alex wrote `` IMPORT `/../elsewhere/terms` `` in `rules/deposit.l4`:

```
This import leaves the root of this deployment: /../elsewhere/terms
Worked through, that path is ../elsewhere/terms.l4, which is above the project root.
A root-relative import may reach any file inside the project root and nothing outside it.
```

The first line says "deployment" even though nothing was deployed: it is the same sentence in every place L4 runs.
It is refused here as well as in a deployment.
Remove the `..`, or move the file into the project.
A path that starts from the importing file, such as ``IMPORT `../../elsewhere/terms` ``, is still allowed to reach a folder outside the project on your own machine.
Alex tried it, and it printed `Check succeeded.`.
An alias import that climbs out, such as ``IMPORT `@common/../../elsewhere/terms` ``, gets the same first line (`This import leaves the root of this deployment: @common/../../elsewhere/terms`) and a second and third line written for aliases.
The reference entry is [This import leaves the root of this deployment](../../reference/errors/README.md#this-import-leaves-the-root-of-this-deployment).

### No `l4-project.json` above the file

Alex deleted `l4-project.json` and checked `rules/deposit.l4`, which imports from the root:

```
This import is relative to the project root, but no project root was found above rules/deposit.l4
Add a file named l4-project.json at the top of your project; it may contain just {}.
```

For `rules/arrears/late-fee.l4`, which uses an alias, the message is different, because `{}` is not enough for an alias:

```
This import uses the alias @common, but no project root was found above rules/arrears/late-fee.l4
An alias is defined in the file l4-project.json at the top of your project, like {"aliases": {"common": "subjects/vn"}}.
```

(The example in the second line is a sample of the shape, not the aliases of Alex's project.)
`rules/notice.l4`, whose import starts from the file, still printed `Check succeeded.` with no project file at all.
L4 does not guess a root from the folder you are in, because the answer would then change with where you ran it.
Create the file as in [What the project root is](#what-the-project-root-is).
The reference entries are [This import is relative to the project root, but no project root was found](../../reference/errors/README.md#this-import-is-relative-to-the-project-root-but-no-project-root-was-found) and [This import uses an alias, but there is no project file to read it from](../../reference/errors/README.md#this-import-uses-an-alias-but-there-is-no-project-file-to-read-it-from).

### An alias that is not defined

Alex wrote `` IMPORT `@commn/terms` ``, one letter short:

```
This import uses an alias that is not defined: @commn
The aliases defined in …/tenancy-rules/l4-project.json are: @common.
```

The second line lists the aliases the file does define, so a misspelling shows up beside the right spelling.
A capital letter makes a different alias.
If the file defines none, which is the case with `{}`, the second line reads `…/tenancy-rules/l4-project.json defines no aliases.`
The reference entry is [This import uses an alias that is not defined](../../reference/errors/README.md#this-import-uses-an-alias-that-is-not-defined).

### A project file that is not JSON

Alex left a comma after the last alias, which JSON does not allow:

```text
{
  "aliases": {
    "common": "shared",
  }
}
```

```
I could not read the project file …/tenancy-rules/l4-project.json, which this import needs: @common/terms
It is not valid JSON: line 4, column 3, unexpected `}`.
A project file that defines an alias looks like {"aliases": {"vn10": "subjects/vn"}}.
```

Go to the line and column it names and correct the file.
The usual causes are a comma after the last item, a missing colon or comma, single quotes in place of double quotes, and a file that stops before its closing `}`.
Only the alias imports were affected: `l4 check rules/deposit.l4`, which imports from the root, still printed `Check succeeded.`.
The reference entry is [I could not read the project file](../../reference/errors/README.md#i-could-not-read-the-project-file).

### Forgetting the backticks

A name with slashes needs backticks.
Alex wrote `IMPORT ../shared/terms`:

```
  |
4 | IMPORT ../shared/terms
  |        ^^
unexpected ..
expecting identifier or space token
```

Writing the name as a quoted string, `IMPORT "../shared/terms"`, fails the same way, with `unexpected "../shared/terms"`.
Use backticks, not quotation marks.
See [Fix errors](debugging-type-errors.md) for reading other messages.

---

## If you work on Windows

Nothing on this page was run on Windows.
Every command ran on a Mac.
The specification of this feature lists, among the things it did not check, that it did not test any Windows behaviour, and that its golden test files (the saved expected outputs) are written in the path style of Mac and Linux (`specs/proposals/RELATIVE-IMPORTS-SPEC.md`, section 9, item 8).
What follows separates what the code and the reference state from what was tried on a Mac, and says where neither tells us.

- **In an `IMPORT`, always write the slash `/`, never the backslash `\`.**
  Windows writes the folders of an address with backslashes, as in the reference's own `C:\Users\<you>\AppData\Roaming\jl4\libraries\`, but L4 does not treat a backslash as a separator on any system, and the reference says to write `/` on every system.
  A name with no `/` in it is not a path at all; it is read as a plain file name.
  On the Mac, `` IMPORT `..\shared\terms` `` printed

  ```
  I could not find a module with this name: .
  Nothing it defines is in scope here; names you expected from it are reported as undefined.
  I have tried the following locations:
  ```

  followed by a list of places (the name is cut at its last dot, which leaves a single `.`), and `` IMPORT `shared\terms` `` in `rules/notice.l4` printed `I could not find a module with this name: shared\terms`.
  If you see "I could not find a module with this name" followed by a name that has a backslash in it, or by a single dot, check that you did not write a backslash.
  What Windows itself does with such a name when it looks for the file was not tried, so do not rely on a backslash import seeming to work.

- **Do not write a drive letter or a full address in an `IMPORT`.**
  A leading `/` means the top of the project, as above.
  A name that starts with a drive letter, such as `C:/...`, was not tried.
- **The commands on this page were typed with forward slashes** (`l4 check rules/notice.l4`).
  Whether your terminal accepts that for the file you give to `l4`, or wants backslashes there, was not tried.
- **The project file's name is exactly `l4-project.json`,** and it goes in the top folder of the project.
- **Plain names are the safe names.**
  The example uses lower-case letters and hyphens, and an `l4` on a Mac read folders and files named like that without trouble.
  On the Mac, `l4` also read a folder called `Gemeinsame Regeln-für` (with spaces and an accented letter) through all three spellings.
  But the reference records that a deployed service did not find a file at the top of an upload whose own name has a space or an accented letter, nor a file inside a top-level folder whose name has a space, an accented letter or punctuation such as `#`, `'`, `+`, `(` or `%`.
  That was measured on 2026-10-26, by others, with hand-made zip files (compressed bundles of files) against a local service; a file inside a plain top-level folder was found whatever its own name or deeper folders were called.
  If the project will be deployed, give its folders and files plain names: ASCII letters and hyphens, as in the example.
- **Write capital letters the same way every time.**
  The reference says that on a system that ignores capitals in file names, two spellings of one folder reach one file but count as two modules to L4.
  On the disk this was tried on, which ignores capitals, a file that wrote both `` IMPORT `../shared/terms` `` and `` IMPORT `../Shared/terms` `` was refused with `There are multiple definitions for the identifier` followed by `` `notice period in days` ``.
- **Line endings and the byte-order mark.**
  The three rule files and `shared/terms.l4` were read correctly with Windows-style line endings (a carriage return before each line break), and a project file with those line endings and a byte-order mark at its start was read correctly too.
  Both were tried on the Mac by converting the files.

---

## What does not work yet

These are limits, not oversights.
They are listed so that you find them here and not in a failed deployment.

- **The editor does not notice a changed `l4-project.json`.**
  If you add, remove or edit the project file while a file that imports from the root or by alias is open, that file keeps the answer it found until you type a change in it, such as a new line at its end.
  The reference records that saving the file, closing and reopening it, and editing a different file did not make the editor's checker (the language server) look again when this was measured with a scripted client on 2026-10-26; VS Code itself was not tried.
  `l4 check` on the command line always looks afresh.
- **A project that uses `/` or `@` cannot be deployed through the deploy tools yet.**
  A deployed project is a bundle of files.
  For the root form, the top of the bundle has to be the project root; for aliases, the top of the bundle also has to hold the `l4-project.json` that defines them.
  `l4 deploy` and the VS Code deploy action put every file at the top level of the bundle under its file name alone, and upload only the file you deploy and the files it imports (read in `jl4/app/L4/Cli/Deploy.hs` and `ts-apps/vscode/src/sidebar-provider.ts` on 2026-10-26), so the folders are lost and the project file is never uploaded.
  A project that uses only paths from the file (`../shared/terms`) checks and runs on your machine, and the reference records that it can be deployed without complaint and then fail in the deployed copy, with only a warning in the service's log.
  Deploying a project in folders is the subject of the deploying page in legalese/l4-ide#749; that page is not on the branch this one was written against, so it is named here and not linked.
- **A stray `l4-project.json` in a folder above your project becomes its root.**
  L4 looks upwards without stopping, past the folder you opened and past a git repository's top folder, to the top of the disk.
  If your project has no project file of its own, a forgotten one in a parent folder, left by another program for example, is taken as the root.
  Alex tried it with a `{}` file one folder above `tenancy-rules` and none inside; `rules/deposit.l4` then said:

  ```
  I could not find a module at this path: /shared/terms
  Nothing it defines is in scope here; names you expected from it are reported as undefined.
  Relative to the project root … that is ../shared/terms.l4, which does not exist.
  ```

  The `…` is the folder above the project.
  The giveaway is a project root that is not the folder you meant.
  The worse case says nothing at all.
  Alex put a different `shared/terms.l4`, with a notice period of 999 days and a deposit cap of 99 months, in that same parent folder.
  `l4 run rules/deposit.l4` then read that file: it exited with status 0, printed no warning, and its two results were `TRUE` and `TRUE` where the project's own numbers give `TRUE` and `FALSE`.
  Put an `l4-project.json` at the top of every project that uses the root form or aliases, and none in a folder above your projects that you do not mean as a project root.

- **A project inside a project has its own root on your machine.**
  `l4` takes the nearest `l4-project.json`, so a folder that holds its own file is a project of its own: a copy of `deposit.l4` in `rules/inner/`, with a `{}` file in that folder too, could not find `/shared/terms` because the root had become `rules/inner/`.
  The reference records that a deployment takes the top of the uploaded files and looks for no other project file, so the same files can name one file here and another there, with no warning.
- **The browser editor has none of these forms yet.**
  The reference says the browser editor gets the path import, the root import and the alias import when a separate change that gives the browser build its own path resolver has also landed.

---

## See also

- [Importing a file from another folder](../../reference/libraries/README.md#importing-a-file-from-another-folder), [Importing from the root of a project](../../reference/libraries/README.md#importing-from-the-root-of-a-project) and [Importing by alias](../../reference/libraries/README.md#importing-by-alias): the reference for each form, with its own small example project.
- [How IMPORT finds libraries](../../reference/libraries/resolution.md): exactly how a path, a root import and an alias are worked out.
- [Errors and Troubleshooting](../../reference/errors/README.md): every message on this page, with how to fix it.
- [Manage rules in git and CI](version-control-for-rules.md): where to put a project's files in a repository.
- [Deploy your rules](../deploying-rules/exporting-rules-for-deployment.md): publishing rules, for a project that is still a single file.
