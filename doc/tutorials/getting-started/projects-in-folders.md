# Split a project into folders

_Status (2026-10-26): **proposed, not landed.**
None of the folder `IMPORT` lines taught on this page works in a released version of L4 yet.
They are built in two draft pull requests that have not merged, legalese/l4-ide#748 and #751 (#751 builds on #748).
Until both have merged and a release carries them, only an `l4` built from the #751 branch reads them.
**To find out whether your `l4` does,** make the files of [section 2](#2-split-it-into-a-shared-folder-and-a-rules-folder) and run `l4 check rules/notice.l4` from the `tenancy-rules` folder.
`Check succeeded.` means it does.
`I could not find a module with this name: terms` means it does not, and the rest of this page will not work for you.
(`l4 --version` cannot tell you: it printed only `dev` for the build this page was written with and for an older `l4`.)
**Deploying a project that keeps its folders does not work yet:** `l4 deploy` sends every file under its plain file name, so a deployed copy cannot find what these `IMPORT` lines name.
[If you need to deploy now](#if-you-need-to-deploy-now) says what does work.
A deploy that keeps folders is draft pull request #749.
Its page, "Deploy a project that has folders" (`doc/tutorials/deploying-rules/deploy-a-project-with-folders.md`), is not published yet: it sat in commits that were not in that pull request when this page was written, so it is named here and not linked.
Nothing was run on Windows ([If you work on Windows](#if-you-work-on-windows)); [How this page was checked](#how-this-page-was-checked) gives the rest._

You have written a few single-file L4 programs.
A single file is easy to open, easy to email and easy to check, and for one short instrument it is the right shape.
A real project grows.
The same definitions are wanted by several rules, two people want to work at once, and the file you scroll through is longer than the statute it encodes.

This tutorial splits one file into a small project of folders, and teaches the three ways one file can say "use the definitions in that other file".
The story is one you can follow with a text editor and the `l4` command: Alex is drafting rules for a residential tenancy.

**Before you start:** [Install L4 and write your first rule](first-l4-file.md), and be comfortable running `l4 check` and `l4 run` on a file.

**Before you make the files:**

- Use any editor that saves plain text; [the first tutorial](first-l4-file.md#install-l4) sets one up.
  Mind the file's name: `terms.l4` ends in `.l4`, and the project file of section 4 is named exactly `l4-project.json`, because a name with something extra on the end, such as `l4-project.json.txt`, is a different file.
- An `IMPORT` line goes inside an `.l4` file, with the rest of the L4.
  You never type one at the terminal.
- The `cd` command followed by a folder moves your terminal into that folder.
  The examples are run from inside the `tenancy-rules` folder; another folder works too if the path you give to the file is right from where you stand.
- Write `/` between folders in an `IMPORT` line and in the project file, Windows included, and never `\`.
  [If you work on Windows](#if-you-work-on-windows) says why.

Where the page says Alex "tried" something, someone ran it while the page was written, on a Mac.
It is evidence for what the page says, and you need not repeat it.
Where you may want to repeat it, the page says how to put things back afterwards.

---

## Where we are going

By the end, Alex's project is five files in the project folder `tenancy-rules`, spread over three folders inside it:

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

## 2. Split it into a shared folder and a rules folder

Alex makes one folder for the whole project, `tenancy-rules`, and inside it two folders: `shared` for what several rules use, and `rules` for the rules themselves.
The old `tenancy.l4` stays outside `tenancy-rules`, or is deleted; nothing below reads it again.
The names are plain on purpose: lower-case letters and hyphens, no spaces and no accents.
Other names can fail once the project is deployed; see [Plain names are the safe names](#other-limits).

```
tenancy-rules/
├── shared/
│   └── terms.l4
└── rules/
    └── notice.l4
```

The three numbers **move** to `shared/terms.l4` ([the file](projects-in-folders-example/shared/terms.l4)).
Cut them out of the rule file and paste them into `terms.l4`, so that each is defined in one file only.
(Copy them instead and L4 refuses, because every name is then defined twice; see [A name defined twice](#a-name-defined-twice).)

```l4
-- The numbers that the tenancy rules share, kept in one place.
-- The rule files in ../rules import this file in three different spellings.

`notice period in days` MEANS 30
`deposit cap in months of rent` MEANS 2
`grace period in days` MEANS 5
```

The rule stays in `rules/notice.l4` ([the file](projects-in-folders-example/rules/notice.l4)), with one new line near the top, where the examples put it:

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

(L4 also accepted an `IMPORT` line written below the rule in a test, but this page does not recommend it.)
Alex runs it from inside the `tenancy-rules` folder:

```bash
l4 check rules/notice.l4
```

```
Check succeeded.
```

`l4 run rules/notice.l4` gives the same two results as before.

When all is well, `l4 check` prints that one line.
When something is wrong it prints more: lines that begin `Info | updateFileDiagnostics`, details such as `Range:` and `Severity:`, and often the same message twice.
Read the text under the first `Message:`.
The blocks on this page show only that text.

### What you can put in a shared file

What an imported file defines at its top level reaches the file that imports it: its types, constructors, rules and plain values ([what an import gives you](../../reference/libraries/README.md#what-an-import-gives-you)).
Alex tried a `terms.l4` that also held a type written with `DECLARE` and a rule written with `GIVEN`, and `rules/notice.l4` used both with no further `IMPORT`.
`#EVAL` lines behave differently: `l4 run rules/notice.l4` printed only the results of the `#EVAL` lines in `notice.l4` itself, numbered from 1, and an `#EVAL` line in `terms.l4` ran only when Alex ran `l4 run shared/terms.l4` on that file by itself.

A rule of thumb, which is advice and not something L4 enforces: move into a shared file what two or more rules need, such as the numbers and the kinds of thing the rules talk about, and leave in each rule's own file the rule and the `#EVAL` lines that test it.
Write an `IMPORT` for every file whose names you use, and do not rely on a name reaching you through a second file.

### What the `IMPORT` line says

Read ``IMPORT `../shared/terms` `` from left to right:

- `IMPORT` brings the definitions of another file into this one.
  Nothing from another file is available until you import it.
- The name is in **backticks** because it contains slashes.
  The backticks are required; without them the line is an error (see [Forgetting the backticks](#forgetting-the-backticks)).
- `..` means "go up one folder".
  `notice.l4` lives in `rules/`, so `..` is `tenancy-rules/`.
- `shared/terms` goes down into the folder `shared` and picks the file `terms`.
  You leave off `.l4`; writing it, as in ``IMPORT `../shared/terms.l4` ``, names the same file and was accepted without a message.
- A **path** is just the address of a file: the folders to go through, written with slashes between them.
  `.` means "this folder" and `..` means "the folder above".
- A name with no slash is not a path.
  `IMPORT terms` makes L4 look for `terms.l4` beside the file that writes the `IMPORT`, and then among the libraries built into L4, and never in the other folders of your project ([Where modules are found](../../reference/libraries/README.md#where-modules-are-found)).
- Two files with the same name in different folders are two different modules: Alex imported a `rates.l4` from each of two folders into one file, used a name from each, and it worked.

**The path starts from the file that writes the `IMPORT`**, and not from the folder you are standing in when you type the `l4` command.
Alex ran `l4 check` on this file three ways, from the folder above `tenancy-rules` (`l4 check tenancy-rules/rules/notice.l4`), from inside `rules` (`l4 check notice.l4`) and from inside `tenancy-rules`, and each printed `Check succeeded.`.
The same file therefore means the same thing to whoever runs it, from wherever they run it.

The reference describes this form in [Importing a file from another folder](../../reference/libraries/README.md#importing-a-file-from-another-folder), and [Path imports](../../reference/libraries/resolution.md#path-imports) says exactly how a path is worked out.

---

## 3. When a file moves, a path from the file breaks

Suppose the `rules` folder gets crowded, and Alex moves `notice.l4` into a new folder, `rules/notices/`, and checks it again:

```bash
l4 check rules/notices/notice.l4
```

It fails, and the first message says:

```
I could not find a module at this path: ../shared/terms
Nothing it defines is in scope here; names you expected from it are reported as undefined.
Relative to rules/notices/notice.l4 that is rules/shared/terms.l4, which does not exist.
```

The file did not change, but `..` now means `rules/`, and there is no `rules/shared/`.
Writing ``IMPORT `../../shared/terms` `` fixes it (two steps up, not one), and `l4 check` then prints `Check succeeded.`.
But every file that moves needs its `IMPORT` lines rewritten, and a mistake does not show until someone checks the file.

**Try it, then put it back.**
To see this on your own copy, do what Alex did.
Afterwards move `notice.l4` back into `rules/` and write the line again as ``IMPORT `../shared/terms` ``, so that your files match the tree in section 2.
The commands in the rest of this page expect that tree.

The next two sections give a way to say "from the top of the project" and a way to give a folder a short name.
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
(If you try this, move it back to `rules/` afterwards.)
A file that sits directly in the project folder is the slash and its name: Alex put a `parties.l4` in `tenancy-rules/`, wrote ``IMPORT `/parties` `` in a file under `rules/`, and `l4 check` printed `Check succeeded.`.

### What the project root is

The project root is the folder of the nearest file named `l4-project.json`.
"Nearest" means this: starting in the folder of the file that writes the `IMPORT`, L4 looks for a file with that name; if there is none, it looks in the folder above, and so on upwards, and the first folder that holds one is the project root.
For Alex it is `tenancy-rules`, the folder that holds `shared` and `rules`.
If you keep several cases in one folder, give each case folder that uses a root import or an alias its own `l4-project.json`; [A stray project file](#other-limits) says what goes wrong otherwise.
L4 looks upwards from the importing file, not from the folder you ran `l4` in; `l4 check late-fee.l4` run from inside `rules/arrears` printed `Check succeeded.`.

**To create it,** make a new plain-text file in the top folder of the project, `tenancy-rules/`, name it exactly `l4-project.json`, and type these two characters into it:

```json
{}
```

That is all a root import needs: L4 only looks for the file, and does not read what is in it.
The file is written in JavaScript Object Notation (JSON), a plain-text way of writing a list of named things between curly braces; `{}` is the list with nothing in it.
The next section puts something in it.

A file called `l4-project.json.txt` is a different file, and L4 will not see it.
If L4 says no project root was found although you made the file, check its whole name first, ending included.
Alex renamed the file to `l4-project.json.txt` and got exactly that message ([No `l4-project.json` above the file](#no-l4-projectjson-above-the-file)).

The reference describes this form in [Importing from the root of a project](../../reference/libraries/README.md#importing-from-the-root-of-a-project).
In VS Code, [the editor does not notice a changed project file](#other-limits).

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
Type the quotation marks as plain straight ones (`"`), not the curly ones that a word processor draws.

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
(If you try this, move it back to `rules/arrears/` afterwards.)

An alias pays off when the shared folder itself moves.
Suppose `shared/` moves to `library/tenancy-terms/`.
Alex changed one line of the project file to `{ "aliases": { "common": "library/tenancy-terms" } }`, and `late-fee.l4`, untouched, printed `Check succeeded.`.
With the other two spellings every importing file would have been edited.
(If you try this, put the folder and the alias back before going on: `notice.l4` and `deposit.l4` name `shared`.)

Some things to know about aliases and the project file:

- An alias is defined only in the project file, never in an `IMPORT` line, and it names a folder, not a single file or a name inside one.
  There is no `AS` form: ``IMPORT `../shared/terms` AS t `` is an error, and `l4 check` says `unexpected AS` and `expecting ;, end of input, or space token`.
- The alias name is whatever you write before the colon.
  Alex tried `shared` (the folder's own name), `common-terms`, `Common` and `my common`, and all four worked; `Common` and `common` are two different aliases.
  Plain lower-case letters and hyphens are the safe choice, which is advice and not something L4 enforces.
- The folder an alias stands for is written with `/` between folders, as in `"library/tenancy-terms"`.
  In JSON a backslash starts a special character, so a folder address copied from a file manager goes wrong.
  Alex tried two spellings on a Mac, and neither folder was found.
  `"library\\tenancy-terms"` is read as a name that holds a backslash, and the message said the alias stands for `library\tenancy-terms`.
  `"library\tenancy-terms"` is read with a tab character where the `\t` was, and the message showed the name with a gap in it and the `t` gone.
  What Windows does with such a value was not tried.
- The aliases come from the nearest `l4-project.json`, as in the last section, and from that file alone.
  Keys other than `aliases` are ignored, so the file can also hold notes for yourself.
  L4 reads the contents of the file only when an alias import needs it ([A project file that is not JSON](#a-project-file-that-is-not-json)).
- An alias is written with `@`, then the alias, then a `/`, then the path under the folder it stands for.
  ``IMPORT `@common` `` with no slash is not an alias import: L4 reads it as a plain file name, `@common`, and says `I could not find a module with this name: @common` followed by the places it looked.

The reference describes this form in [Importing by alias](../../reference/libraries/README.md#importing-by-alias).

---

## 6. Which spelling to use

All three spellings reach the same file, and L4 treats two spellings of one file as one module, so a name it defines is not "defined twice".
(Alex put all three, and `./../shared/terms` as well, in one file; it checked, and `#EVAL` of the notice period gave 30.)
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
Where a message printed the full address of a folder on the machine it ran on, this page shows `…` in its place, because that address starts differently on every machine.

**Read the first message, not the last.**
A missing import also makes L4 complain about every name the missing file would have supplied, for example `I could not find a definition for the identifier` followed by `` `notice period in days` ``, and about a comparison it can no longer tell the kind of (`There are multiple definitions for the identifier`, followed by `` `__GEQ__` ``).
Those follow from the first message, and they go away when it is fixed.
One case runs the other way: when a name is defined twice, the first message is about the comparison and the second names the real problem ([A name defined twice](#a-name-defined-twice)).

### A path that finds no module

Alex mistyped the file name, `` IMPORT `../shared/term` ``, and ran `l4 check rules/notice.l4`:

```
I could not find a module at this path: ../shared/term
Nothing it defines is in scope here; names you expected from it are reported as undefined.
Relative to rules/notice.l4 that is shared/term.l4, which does not exist.
```

The first line repeats what you wrote, which is counted from the file that writes the `IMPORT`.
Only the last line is written from the folder you ran `l4` in: it says which file L4 looked for, with `.l4` added and the `..` worked out.
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

The first line says "deployment" even though nothing was deployed: it is the same sentence in every place L4 runs, and the import is refused here as well.
Remove the `..`, or move the file into the project.
A path that starts from the importing file, such as ``IMPORT `../../elsewhere/terms` ``, is still allowed to reach a folder outside the project on your own machine; Alex tried it, and it printed `Check succeeded.`.
An alias import that climbs out, such as ``IMPORT `@common/../../elsewhere/terms` ``, gets the same first line (`This import leaves the root of this deployment: @common/../../elsewhere/terms`) and a second and third line written for aliases.
The reference entry is [This import leaves the root of this deployment](../../reference/errors/README.md#this-import-leaves-the-root-of-this-deployment).

### No `l4-project.json` above the file

Alex deleted `l4-project.json` and checked `rules/deposit.l4`, which imports from the root:

```
This import is relative to the project root, but no project root was found above rules/deposit.l4
Add a file named l4-project.json at the top of your project; it may contain just {}.
```

You get the same message when the file is there under the wrong name: Alex renamed it `l4-project.json.txt` and `l4 check` said exactly this.
If you are sure you made the file, check its whole name, ending included.

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

The line and column say where JSON gave up reading, which is sometimes the mistake itself and sometimes the line after it.
Here the stray comma is on line 3, and the message names line 4, the `}` that cannot follow a comma.
If the line it names looks fine, look at the line before it.
A curly quotation mark is named at the mark itself: a file typed with `“aliases”` in place of `"aliases"` gave `line 1, column 3, unexpected` followed by the curly mark.
The usual causes are a comma after the last item, a missing colon or comma, single or curly quotes in place of straight double quotes, and a file that stops before its closing `}`.
Only the alias imports were affected: `l4 check rules/deposit.l4`, which imports from the root, still printed `Check succeeded.`.
The reference entry is [I could not read the project file](../../reference/errors/README.md#i-could-not-read-the-project-file).

### A name defined twice

If a name is defined in two places, L4 cannot tell which one a rule means.
Two accidents produce it.

Alex copied the three numbers into `terms.l4` and also left them in `rules/notice.l4`, under the `IMPORT` line.
The first message is about the comparison (`There are multiple definitions for the identifier` followed by `` `__GEQ__` ``), and the second names the real problem:

```
There are multiple definitions for the identifier

  `notice period in days`

and I do not have sufficient information to make a choice between them.
The options are:

  `notice period in days` (defined at notice.l4:6:1-24) of type NUMBER
  `notice period in days` (defined at terms.l4:4:1-24) of type NUMBER
```

The last two lines name the file and place of each definition.
Cut the numbers out of the rule file, so that each is defined in one file only.

The other accident is one folder spelled two ways.
On a disk that ignores capital letters, `` IMPORT `../shared/terms` `` and `` IMPORT `../Shared/terms` `` reach one file but count as two modules, and a file that writes both gets the same two messages: `__GEQ__` first, then `notice period in days`, with both last lines naming `terms.l4:4:1-24`.
Write the folder's name the same way every time.

### A file that starts with a byte-order mark

A **byte-order mark** is a few invisible bytes at the very start of a text file.
L4 refuses one at the start of an `.l4` file.
Alex added one to `shared/terms.l4` and checked `rules/notice.l4`.
The first message names `terms.l4`, points at line 1, column 1, and says `unexpected` followed by a quoted character you cannot see, then lists what it expected.
The messages after it follow from it, as with a missing import.
Save the file again without the mark; the setting is in your editor's save or encoding options, and no editor was tried for this page.

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
The specification of this feature lists, among the things it did not check, that it did not test any Windows behaviour (`specs/proposals/RELATIVE-IMPORTS-SPEC.md`, section 9, item 8).
What follows separates what the code and the reference state from what was tried on a Mac, and says where neither tells us.

- **In an `IMPORT`, always write the slash `/`, never the backslash `\`.**
  Windows writes the folders of an address with backslashes, as in the reference's own `C:\Users\<you>\AppData\Roaming\jl4\libraries\`, but L4 does not treat a backslash as a separator on any system, and the reference says to write `/` on every system.
  A name with no `/` in it is not a path at all; it is read as a plain file name.
  On the Mac, `` IMPORT `..\shared\terms` `` printed `I could not find a module with this name: .` (the name is cut at its last dot, which leaves a single `.`) and a list of the places tried, and `` IMPORT `shared\terms` `` in `rules/notice.l4` printed `I could not find a module with this name: shared\terms`.
  If you see that message followed by a name with a backslash in it, or by a single dot, check that you did not write a backslash.
  What Windows itself does with such a name when it looks for the file was not tried.
  The same goes for the project file: write `/` in an alias's folder ([section 5](#5-give-a-folder-a-short-name-aliases)).
- **Do not write a drive letter or a full address in an `IMPORT`.**
  A leading `/` means the top of the project, as above.
  A name that starts with a drive letter, such as `C:/...`, was not tried.
- **The commands on this page were typed with forward slashes** (`l4 check rules/notice.l4`).
  Whether your terminal accepts that for the file you give to `l4`, or wants backslashes there, was not tried.
- **The project file's name is exactly `l4-project.json`,** and it goes in the top folder of the project.
  If L4 reports no project root although you made it, check the whole name first ([No `l4-project.json` above the file](#no-l4-projectjson-above-the-file)).
- **Line endings and the byte-order mark.**
  The three rule files and `shared/terms.l4` were read correctly with Windows-style line endings (a carriage return before each line break), and a project file with those line endings and a byte-order mark at its start was read correctly too.
  Both were tried on the Mac by converting the files.
  A byte-order mark at the start of an `.l4` file is a different matter: it is refused ([A file that starts with a byte-order mark](#a-file-that-starts-with-a-byte-order-mark)).
- **Folder names and capital letters** can matter once a project is deployed; see "Plain names are the safe names" and "Write capital letters the same way every time" in [Other limits](#other-limits).

---

## What does not work yet

These are limits, not oversights.
They are listed so that you find them here and not in a failed deployment.

### If you need to deploy now

Keep a flat copy of the rules for deploying.
Put the rule file and the shared file side by side in one folder, write the import as a plain name with no slash, and mark the rule you want to publish with `@export`.
`l4 deploy` sends exactly this shape of project.
Alex made a folder `tenancy-flat` holding `terms.l4` (the file from section 2) and this `notice.l4`:

```l4
-- How much notice a landlord must give a tenant.
-- A plain name: terms.l4 sits beside this file.
IMPORT terms

@export default Is the notice long enough
GIVEN `days of notice given` IS A NUMBER
GIVETH A BOOLEAN
DECIDE `notice is long enough` IF `days of notice given` AT LEAST `notice period in days`

#EVAL `notice is long enough` 45
#EVAL `notice is long enough` 10
```

`@export` marks a rule for deployment, and none of the three rules of Alex's project in folders has it.
Alex deployed the flat copy with `l4 deploy notice.l4 --server <address>` to a `jl4-service` running on the same Mac, which is the program that keeps deployed rules and answers calls to them.
`l4` printed `Deploying 'notice' to …: notice.l4, terms.l4` and `Deployed 'notice' (version 0.0.0) with 1 function:`, a call made with `curl` with 45 days of notice answered `true`, and a call with 10 answered `false`.
The service wrote no `Bundle IMPORT resolves to nothing` warning.
This worked with the `l4` of the #751 branch and again with an older `l4` that printed `dev`.
Without `--server`, `l4 deploy` goes to Legalese Cloud, where you sign in first with the `legalese` command (this is what `l4 deploy --help` says); that was not tried for this page.
[Deploy your rules](../deploying-rules/exporting-rules-for-deployment.md) shows how to sign in, deploy and call a rule on Legalese Cloud.

### Deploying does not work yet

A deployed project is one zip file holding your files, and the service works out each `IMPORT` against the files inside it.
For the root form, the top of the zip has to be the project root; for aliases, the top of the zip also has to hold the `l4-project.json` that defines them.
`l4 deploy` and the VS Code deploy action put every file at the top level of the zip under its file name alone, and upload only the file you deploy and the files it imports (read in `jl4/app/L4/Cli/Deploy.hs` and `ts-apps/vscode/src/sidebar-provider.ts` on 2026-10-26), so the folders are lost and the project file is never uploaded.

**`l4 deploy` does not stop you.**
Alex ran it on each of the three rules, against a `jl4-service` on the same machine.
Each time `l4` printed a line like `Deploying 'notice' to …: notice.l4, terms.l4`, which shows the files going up flat, and sent them.
What happened next depended on the rule.

- **Refused.**
  The service refused all three of Alex's rules, and `l4` reported the failure.
  The message is one long line; here its runs of spaces are closed up and the list of options that follows is left out:

  ```
  Update rejected: compilation failed: I found a problem while checking the definition of `notice is long enough`: There are multiple definitions for the identifier `__GEQ__` and I do not have sufficient information to make a choice between them.
  ```

  The comparison it names is `__LEQ__` for `deposit.l4` and `__GT__` for `late-fee.l4`.
  It is the same follow-on message as under [Messages you will see](#messages-you-will-see): the number the rule should have been compared with never arrived, so L4 cannot tell what kind of thing is being compared.

- **Accepted, then failing.**
  Alex wrote a fourth rule, in a file that is not part of the example, which uses the shared number in a sum and not in a comparison:

  ```l4
  IMPORT `../shared/terms`

  @export default Late fee for a number of days
  GIVEN `days late` IS A NUMBER
  GIVETH A NUMBER
  DECIDE `fee` IS `days late` TIMES `grace period in days`
  ```

  `l4 check` printed `Check succeeded.` on it.
  `l4 deploy` then printed `Deployed 'fee' (version 0.0.0) with 1 function:` and reported no failure, and the service said it was `ready`, its word for "compiled and answering".
  Calling the rule, as [Deploy your rules](../deploying-rules/exporting-rules-for-deployment.md#step-5-call-a-rule) shows, answered with the error code 422, a web service's way of saying that it cannot process the request, and this message:

  ```
  Internal error:
    `grace period in days`
  is not in scope.
  Please report this as a bug.
  ```

In both cases the service wrote `Bundle IMPORT resolves to nothing` to its log, naming the file and the import; for a deployment that is accepted, the reference records that this warning is the only trace.
Which of the two you get depends on how the rule uses what it imports, so a `Deployed` line does not show that the imports were found.
After you deploy a project in folders, call each rule once and read the answer.

One case is loud.
If two files that you import have the same name in different folders, `l4 deploy` stops before sending anything, because a flat upload cannot hold both.
Its message begins `These imported files share a name, but the upload is flat (as from VS Code). Rename one of each:` and then lists the full address of each file.

**One way round this was measured, for all three forms.**
Alex made a zip of the whole project with its folders kept (`l4-project.json`, `rules/` and `shared/` at the top of the zip, with an `@export` line added above each rule so that there was something to call) and sent it to the service directly, as [what a deployment contains](../../reference/libraries/README.md#what-a-deployment-contains) describes:

```bash
zip -r tenancy.zip l4-project.json rules shared
curl -F 'sources=@tenancy.zip;type=application/zip' -F id=tenancy http://localhost:8080/deployments
```

The service said `ready`, and calling each of the three rules answered correctly (45 days of notice `true` and 10 `false`; a deposit of 2500 on 1000 rent `false` and 1800 `true`; 12 days late `true` and 3 `false`).
The service wrote no `Bundle IMPORT resolves to nothing` warning.
That was a `jl4-service` on the same Mac, started on another port; the address above stands for wherever your own service runs.
The zip tool and `curl` were not tried on Windows, and nothing was tried against Legalese Cloud.

### Other limits

- **The editor does not notice a changed `l4-project.json`.**
  If you add, remove or edit the project file while a file that imports from the root or by alias is open, that file keeps the answer it found until you type a change in it, such as a new line at its end.
  The reference records that saving the file, closing and reopening it, and editing a different file did not make the editor's checker (the language server) look again when this was measured with a scripted client on 2026-10-26; VS Code itself was not tried.
  `l4 check` on the command line always looks afresh.
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
  `l4 run rules/deposit.l4` then read that file: it printed no warning and no error, and its two results were `TRUE` and `TRUE` where the project's own numbers give `TRUE` and `FALSE`.
  Put an `l4-project.json` at the top of every project that uses the root form or aliases, and none in a folder above your projects that you do not mean as a project root.

- **A project inside a project has its own root on your machine.**
  `l4` takes the nearest `l4-project.json`, so a folder that holds its own file is a project of its own: a copy of `deposit.l4` in `rules/inner/`, with a `{}` file in that folder too, could not find `/shared/terms` because the root had become `rules/inner/`.
  The reference records that a deployment takes the top of the uploaded files and looks for no other project file, so the same files can name one file here and another there, with no warning.
- **Plain names are the safe names.**
  The example uses lower-case letters and hyphens, and an `l4` on a Mac read folders and files named like that without trouble.
  On the Mac, `l4` also read a folder called `Gemeinsame Regeln-für` (with spaces and an accented letter) through all three spellings.
  But the reference records that the service does not find a file at the top of an upload whose own name has a space or a non-ASCII letter (a letter outside A to Z, such as `ü`), nor a file inside a top-level folder whose name has a space, a non-ASCII letter or punctuation such as `#`, `'`, `+`, `(` or `%`.
  The reference says a deployment of such a project reports `ready` and every call then answers 422.
  The reference says this was measured for a bare import, and that a path import into such a folder was seen to fail the same way in review; a file inside a plain top-level folder is found whatever its own name or deeper folders are called, and `l4` on your own machine is not affected ([How IMPORT finds libraries](../../reference/libraries/resolution.md), under "What a path import cannot do yet").
  This page did not repeat those measurements.
  If the project will be deployed, give its folders and files plain names: ASCII letters (A to Z) and hyphens, as in the example.
- **Write capital letters the same way every time, and the way the folder is spelled on disk.**
  The reference says that on a system that ignores capitals in file names, two spellings of one folder reach one file but count as two modules to L4 (the message is under [A name defined twice](#a-name-defined-twice)).
  A wrong capital on its own was not noticed on the disk this was tried on, which ignores capitals: with only ``IMPORT `../Shared/terms` `` in `rules/notice.l4`, where the folder is `shared`, `l4 check rules/notice.l4` printed `Check succeeded.`.
  A system that tells capitals apart is less forgiving, and the service is one.
  Alex zipped `rules/notice.l4` and `shared/terms.l4` with their folders kept, and sent the zip straight to the service.
  With ``IMPORT `../shared/terms` `` it deployed and answered a call; with ``IMPORT `../Shared/terms` `` the service's log said `Bundle IMPORT resolves to nothing` and the deploy was rejected.
  `l4` itself was not tried on a disk that tells capitals apart.
  A line that passes on your machine only because your disk ignores capitals can fail somewhere else, so match the folder's spelling exactly.
- **The browser editor has none of these forms yet.**
  The reference says the browser editor gets the path import, the root import and the alias import when a separate change that gives the browser build its own path resolver has also landed.

---

## How this page was checked

Every command and message on this page was run on 2026-10-26, on a Mac, with the `l4` built from the #751 branch that morning.
That `l4` prints only `dev` for `--version`, so the branch is its only name; the branch's code directories (`jl4-core`, `jl4`, `jl4-service`, `jl4-lsp`) were not changed after that build, only the documentation and the specification were.
The deploying runs used a `jl4-service` built from the same branch, started on the same Mac.
The three pull requests, #748, #749 and #751, were all still open drafts that day (read with `gh pr view`).

The one run that used another build is the one for #749, which has neither #748 nor #751.
On this page's project, `l4 deploy rules/notice.l4` with that build stopped before sending anything, printing `I could not find a module with this name: terms` and `rules/notice.l4 doesn't typecheck; fix it before deploying (see `l4 check`).`
In that build a slash in an `IMPORT` name is not a folder, and `l4` reads the name as its last part only, `terms` here.
So #749 does not deploy the `IMPORT` lines taught on this page, and a build that has #748, #751 and #749 together was not tried.
The page "Deploy a project that has folders" describes that build; it was not published when this page was written, and it was not re-checked here.

Where a sentence rests on the reference pages and not on a run, it says so.
Nothing was run on Windows, and neither VS Code nor the browser editor was opened.
The claims about the language server come from the reference's own measurement with a scripted client.

---

## See also

- [Importing a file from another folder](../../reference/libraries/README.md#importing-a-file-from-another-folder), [Importing from the root of a project](../../reference/libraries/README.md#importing-from-the-root-of-a-project) and [Importing by alias](../../reference/libraries/README.md#importing-by-alias): the reference for each form, with its own small example project.
- [How IMPORT finds libraries](../../reference/libraries/resolution.md): exactly how a path, a root import and an alias are worked out.
- [Errors and Troubleshooting](../../reference/errors/README.md): every message on this page, with how to fix it.
- [Manage rules in git and CI](version-control-for-rules.md): where to put a project's files in a repository.
- [Deploy your rules](../deploying-rules/exporting-rules-for-deployment.md): publishing rules, for a project that is still a single file or a flat copy of a project.
