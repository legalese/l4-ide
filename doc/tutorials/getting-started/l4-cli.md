# Using the l4 CLI

Run, check, render, and deploy L4 files from the command line.

**Prerequisites:** [Install L4 and write your first rule](first-l4-file.md)

---

## What You'll Learn

The `l4` command-line tool is the fastest way to validate and evaluate L4 files outside VS Code — in a terminal, a script, or a CI pipeline. This tutorial tours every subcommand using a small example file you create yourself.

---

## Step 1: Get the Binary

### Option A: From the VS Code extension

If you have the [L4 VS Code extension](https://marketplace.visualstudio.com/items?itemName=Legalese.l4-vscode) installed, it ships with a bundled `l4` binary and offers to put it on your PATH ("Install the L4 CLI? This lets you run `l4 run file.l4`, etc. from any terminal."). You can also trigger this any time with the **L4: Install L4 CLI** command from the command palette.

### Option B: Build from source

Clone the [l4-ide repository](https://github.com/legalese/l4-ide) and build with Cabal (requires GHC 9.10.2 and Cabal 3.10+):

```bash
cabal build jl4:l4          # build just the CLI
cabal list-bin jl4:l4       # print the path to the built binary
```

Add the printed path to your PATH, or run it in place. You can also run it through Cabal without installing:

```bash
cabal run l4 -- run myfile.l4
```

### Check it works

```bash
l4 --help
```

```
l4 — the L4 computational-law CLI

Usage: l4 [--version]
          (COMMAND | FILE [--json] [-t|--trace MODE] [--fixed-now ISO8601])

Available commands:
  run                      Typecheck and evaluate an L4 file (prints diagnostics
                           + #EVAL results)
  check                    Typecheck an L4 file only (fast path; no evaluation)
  format                   Print an L4 file to stdout exactly as written
  ast                      Dump the parsed AST of an L4 file
  batch                    Evaluate an @export function against many input rows
                           (json|yaml|csv in, NDJSON streaming out)
  trace                    Render #EVALTRACE evaluation traces as GraphViz
                           (dot|png|svg)
  state-graph              Extract regulative-rule state transition graphs as
                           GraphViz DOT
  render                   Render an L4 file to a formatted document
                           (html|text|json|plan)
  deploy                   Deploy an L4 file and its imports as a new deployment
                           (Legalese Cloud, or --server)
  redeploy                 Update an existing deployment; refuses breaking
                           changes unless --force
  undeploy                 Delete a deployment
  deployments              List deployments
  install                  Install a companion tool: `l4 install legalese` (the
                           Legalese Cloud CLI)
```

Run `l4 <command> --help` for the options of any subcommand.

### Which build is this?

```bash
l4 --version
```

This prints one line that names the build you are running, so you can say which one you have when you report a problem, or check that an upgrade took:

```
1.6.91 (main, a1b2c3d, 2026-10-14)
```

The line is the release, then in brackets the branch it was built from, the commit, and the day it was built.

A build that someone made from a working copy of the source is not a release, and says just `dev`.

`jl4-lsp --version`, the language server that the editor runs, prints the same line. The server also sends it to the editor as its `serverInfo` when the editor connects, and writes it to its log when it starts.

---

## Step 2: Create a File to Work With

Create `late-fee.l4`:

```l4
-- late-fee.l4
-- A small policy: 2% late fee up to 30 days overdue, 5% beyond that.

§ `Late Fee Policy`

DECLARE Invoice
    HAS `amount`       IS A NUMBER
        `days overdue` IS A NUMBER

GIVEN invoice IS AN Invoice
GIVETH A NUMBER
DECIDE `late fee` IS
    IF invoice's `days overdue` AT MOST 0
    THEN 0
    ELSE IF invoice's `days overdue` AT MOST 30
         THEN invoice's `amount` TIMES 0.02
         ELSE invoice's `amount` TIMES 0.05

`a slightly late invoice` MEANS Invoice WITH
    `amount`       IS 1000
    `days overdue` IS 12

`a very late invoice` MEANS Invoice WITH
    `amount`       IS 1000
    `days overdue` IS 45

#EVAL `late fee` `a slightly late invoice`
#EVAL `late fee` `a very late invoice`
```

---

## Step 3: `l4 run` — Evaluate a File

`l4 run` typechecks the file and evaluates every `#EVAL` (and `#EVALTRACE`) directive:

```bash
l4 run late-fee.l4
```

```
Evaluation[1] @ late-fee.l4:27:1-43

Result:
  20


Evaluation[2] @ late-fee.l4:28:1-39

Result:
  50
```

Each `Evaluation[n]` block corresponds to one `#EVAL` directive, in file order, with the source range it came from. Diagnostics (errors, warnings) are printed to stderr; results go to stdout. The exit code is `0` when the file typechecks and every directive evaluates without crashing; type errors and runtime evaluation errors (such as a `CONSIDER` with no matching branch, or an `#ASSERT` whose expression raises) exit non-zero. Warnings alone do not change the exit code — a file with warnings still evaluates.
An error in a file that it imports counts too, and so does an `IMPORT` that finds no file and an `IMPORT` cycle (`a.l4` imports `b.l4`, which imports `a.l4`).
Whether a directive makes `l4 run` fail depends on whether it can be evaluated at all.
An `#EVAL` that gives a result exits `0`, and so does an `#ASSERT` that comes out false (it prints `assertion failed`).
An `#EVAL` or `#ASSERT` that cannot be evaluated exits non-zero: a `CONSIDER` with no matching branch, a division by zero, or a `POST` that cannot connect.
A `POST` that cannot connect prints the HTTP library's error on standard error, which begins `VanillaHttpException`, and no `Evaluation[n]` block for that directive.

As a convenience, `l4 late-fee.l4` (no subcommand) is shorthand for `l4 run late-fee.l4`.

### Machine-readable output

Add `--json` for a single JSON envelope, useful for editors, CI, and other tools:

```bash
l4 run late-fee.l4 --json
```

```json
{
  "file": "late-fee.l4",
  "ok": true,
  "diagnostics": ["..."],
  "results": [
    { "kind": "value", "range": "late-fee.l4:27:1-43", "value": "20" },
    { "kind": "value", "range": "late-fee.l4:28:1-39", "value": "50" }
  ]
}
```

### Pinning the clock

If your rules use `NOW` or `TODAY`, pin the evaluation clock so results are reproducible:

```bash
l4 run --fixed-now 2025-01-31T15:45:30Z myfile.l4
```

---

## Step 4: `l4 check` — Typecheck Without Running

`l4 check` runs the parser and typechecker but skips evaluation entirely, so even files with expensive `#EVAL` bodies check quickly. It is the right command for CI lint jobs and pre-commit hooks:

```bash
l4 check late-fee.l4
```

```
Check succeeded.
```

Exit code `0` means the file is valid L4; non-zero means there were errors (printed as diagnostics).
`--json` and `--fixed-now` work here too.
The check covers the files it imports too: an error in an imported file, an `IMPORT` that finds no file, or an `IMPORT` cycle is a non-zero exit as well.
An import cycle is reported in terms of the checker's internals, not as a cycle.
`l4 check a.l4` prints a diagnostic whose `File:` line names one of the files in the ring, whose `Source:` is `compiler`, and whose message begins like this:

```
GraphException: SuccessfulTypeCheck; file:///…/a.l4
GetMixfixRegistry; file:///…/b.l4
GetMixfixRegistry; file:///…/a.l4
```

It never says `IMPORT` or "cycle".
The files it names include the ones in the ring, so look for two or more files that `IMPORT` each other, directly or through a third.
[Import cycle](../../reference/errors/README.md#import-cycle) says what to change.

Only `l4 check`, `l4 run`, `l4 deploy` and `l4 redeploy` look at errors in the files a file imports.
`l4 render`, `l4 nlg` and `l4 trace` print the error on standard error and exit `0` when a file they read imports a broken one.
`l4 state-graph` exits `0` and prints its graph, and prints no error at all.
`l4 format`, `l4 ast` and `l4 batch` exit `0` as well.
Use `l4 check` as the CI gate for a project of several files.

`l4 deploy` and `l4 redeploy` refuse a file that `l4 check` refuses, before they send anything.
They print the diagnostics `l4 check` prints, then ``FILE doesn't typecheck; fix it before deploying (see `l4 check`).``, and exit `1`.
That covers an error in the file you name, an error in a file it imports, an `IMPORT` that finds no file and an `IMPORT` cycle.
A warning does not stop a deploy.
A file that passes `l4 check` goes on to the upload.
One limit follows from this: an `l4` older than the service cannot deploy a file that imports a standard-library module that only the newer service has, because `l4 check` fails on that file too.
Use an `l4` at least as new as the service you deploy to.

---

## Step 5: Libraries and `JL4_LIBRARY_PATH`

When a file says `IMPORT daydate` (or `time`, `currency`, ...), the tools resolve the library module by checking, in order:

1. The `JL4_LIBRARY_PATH` environment variable (user/operator override)
2. The project root directory
3. The directory of the importing file
4. The standard library built into the `l4` you are running
5. The XDG data directory (`~/.local/share/jl4/libraries/`)
6. The libraries bundled with the VS Code extension

When `JL4_LIBRARY_PATH` is set, it takes explicit control: the built-in standard library is skipped. This matters when you work from a source checkout and want the CLI to use the checkout's libraries rather than a previously installed copy:

```bash
JL4_LIBRARY_PATH=jl4-core/libraries l4 run myfile.l4
```

Try it with a file that needs an import. Create `library-tour.l4`:

```l4
-- library-tour.l4
IMPORT daydate

`the closing date` MEANS Date 15 1 2025

#EVAL `the closing date`
```

```bash
l4 run library-tour.l4
```

```
Evaluation[1] @ library-tour.l4:6:1-25

Result:
  DATE OF 15, 1, 2025
```

See the [library reference](../../reference/libraries/README.md) for what each library provides.

---

## Step 6: The Other Subcommands

### `l4 format` — print a file as written

Prints a file to stdout exactly as it is written: the same layout, comments, line endings and spelling of every literal. It does not change the layout. It only parses the file, without type-checking it (use `l4 check` for that); if the file does not parse, it prints the parse errors instead and exits with status 1.

```bash
l4 format late-fee.l4
```

### `l4 render` — a readable document

Renders the rules as a formatted document for non-programmer review:

```bash
l4 render late-fee.l4 --format text
```

```
Late Fee Policy
===============


Definitions

• Invoice means a record with:
    - amount — NUMBER
    - days overdue — NUMBER


Provisions

• Late fee means:
    - if the invoice's days overdue is at most 0: 0
    - otherwise, if the invoice's days overdue is at most 30: the invoice's amount × 0.02
    - otherwise: the invoice's amount × 0.05
```

Options: `--format html|text|json|plan|akn` (`xml` is accepted as a synonym for `akn`, which emits Akoma Ntoso 3.0), `-o/--output FILE`, `--toc` (table of contents), `--number-sections`, `--number-clauses`, `--include-unused`, and `--lang SUBTAG` (render the `@nlg:SUBTAG` wordings; in `html` this also sets `<html lang=…>` and, for a right-to-left language, `dir="rtl"`, and in `akn` the language of the FRBR Expression URIs).

### `l4 nlg` — the directives, as sentences

Writes each `#EVAL`, `#ASSERT` and other directive of a file as one line of prose.
It is the quick way to read what a set of test cases says without running them.
Where a definition has an `@nlg` wording, `l4 nlg` uses it in place of the name.

```l4
GIVEN days_overdue IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is late` @nlg the invoice is late
  IF days_overdue GREATER THAN 30

#EVAL `is late` 45
#EVAL NOT `is late` 5
```

```bash
l4 nlg is-late.l4
```

```
the invoice is late with 45
not the invoice is late with 5
```

`l4 nlg` prints nothing and exits non-zero if the file does not typecheck, rather than writing prose about a module that does not hold together.
It does not look into the files that file imports: if one of them is broken, `l4 nlg` writes the prose, prints the error on standard error, and exits `0`.
Options: `-o/--output FILE` writes to a file instead of standard output, and `--lang SUBTAG` uses the `@nlg:SUBTAG` wordings for the rules that have them (and the module's default wording for those that do not).
See [one encoding, several languages](../natural-language-functions/optimising-natural-language-generation.md#one-encoding-several-languages).

### `l4 batch` — many cases at once

Evaluates one `@export` function against many input rows, streaming one NDJSON result line per row. Given this exported rule:

```l4
@export Calculate the late fee for an overdue invoice
GIVEN amount IS A NUMBER @desc The invoice amount
      days_overdue IS A NUMBER @desc How many days past due
GIVETH A NUMBER
DECIDE fee IS
    IF days_overdue AT MOST 0
    THEN 0
    ELSE IF days_overdue AT MOST 30
         THEN amount TIMES 0.02
         ELSE amount TIMES 0.05
```

and a JSON file of cases (`invoices.json`):

```json
[
  { "amount": 1000, "days_overdue": 12 },
  { "amount": 1000, "days_overdue": 45 },
  { "amount": 2500, "days_overdue": 0 }
]
```

```bash
l4 batch late-fee-export.l4 --inputs invoices.json
```

```
{"diagnostics":[],"input":{"amount":1000,"days_overdue":12},"output":[{"result":20,"trace":null}],"status":"success"}
{"diagnostics":[],"input":{"amount":1000,"days_overdue":45},"output":[{"result":50,"trace":null}],"status":"success"}
{"diagnostics":[],"input":{"amount":2500,"days_overdue":0},"output":[{"result":0,"trace":null}],"status":"success"}
```

`--inputs` accepts `.json`, `.yaml`, or `.csv` (use `--input-format` when reading from stdin with `-`); `--entrypoint FUNCTION` selects which exported function to run when there is more than one.

Natural-language names work too: exported functions and parameters written with backticks and spaces (`` `the base rate` ``) are matched by input keys spelled the same way (`"the base rate": 100`).
A value is read as the type its parameter declares, whichever kind of file the case comes from.
A parameter declared as `NUMBER` or `BOOLEAN` that is given as text is read as the number or boolean the text spells: a CSV cell is always text, so a `100` or `true` cell arrives as a number or boolean, and so does `"100"` or `"true"` in a JSON or YAML file.
Text that does not spell one is left as it is, and the line is an error that names the text.
A parameter declared through a synonym, such as `DECLARE Year IS A NUMBER`, is read as the type the synonym stands for, and so is a synonym for a `MAYBE`.
A synonym that takes a type, such as `DECLARE Optional OF a IS A MAYBE a` used as `Optional OF NUMBER`, is not read this way from a CSV cell or from text: a cell `2020` or the text `"2020"` is refused, so give such a parameter a plain number in a JSON file.
Every other kind of parameter keeps a non-blank CSV cell exactly as written, however much it looks like a number or a boolean.
A `STRING` receives `123456`, `018956` and `1.50` as the codes they are, a choice such as `DECLARE Answer IS ONE OF True, False, Unknown` receives the name `True` and not a boolean, and a `DATE` receives `2026-10-13` as text, so a cell that is not a date, such as `20261013`, is an error that names it.
A number given for a `STRING` parameter in a JSON or YAML file is an error, because those files already say which values are strings.
A blank CSV cell is not text, for a `STRING` parameter as for any other: an empty cell, a cell holding only spaces and a quoted `""` all leave the fact out, exactly as a column missing from the file does. A fact that has to be given is then missing, which makes the line an error that says `Missing required field` and names it; a `MAYBE` fact is `NOTHING`.
So a line of nothing but empty cells, such as `,,`, is an error when the rules need any fact, and the run stops there unless you pass `--continue-on-error`.
A CSV file cannot carry empty text, or text of only spaces, as a value: to give a fact that value, use a JSON or YAML file (`"note": ""`).
A line with nothing on it, or only spaces or tabs, is not a case at all, while a quoted `""` or `"   "` is a case whose cell is blank.
A byte-order mark at the start of the file, which Excel's CSV UTF-8 export writes, is ignored.
A line with more or fewer cells than the header is refused and counted as an error, and the message gives its line number.
A CSV cell for any other kind of parameter is typed by its content: `true` or `false` (any case) is a boolean, a plain number such as `3.5` is a number (a cell containing `e` or `E` stays text), and anything else is a string.

`--format ndjson|json|csv|yaml` and `--output FILE` choose the result format and destination; the run stops at the first failing row unless you pass `--continue-on-error`, and `--validate-only` checks rows against the function's inputs without evaluating them.

#### What each line says

Every case that is run produces one line, or one item with `--format json` or `yaml`, with four keys:

- `input` is the case as the rules read it: a CSV cell is shown as the number, boolean or text it was read as, and a blank cell that was left out is not shown.
- `output` is what the rules came to for the case: a list holding one `result`, or `null` when no answer could be reached at all.
- `status` says how the case went, as below.
- `diagnostics` is the list of messages for a case that did not succeed, and `[]` for one that did.

`status` is one of two words:

- `success`: the rules gave an answer.
- `error`: the rules could not be run on the case, or raised an error. A fact is missing, a value cannot be read as the type the fact declares, a CSV line has a different number of cells from the header, or the rules themselves failed (the `result` is then an object holding the message); `diagnostics` says which. The batch stops after the first such case unless you pass `--continue-on-error`.

The command exits with status 0 when every case was `success`, and 1 when any case was `error`, once every case that was going to run has run.

#### Checking cases without running them

`--validate-only` checks each case against the facts the rules need, and runs nothing. Its lines have three keys, not four: `input`, `status` (`valid` or `invalid`) and `errors`, the list of problems, which is `[]` for a valid case. The command exits with status 1 when any case is `invalid`, and `--continue-on-error` works as it does in a run.

It checks that every fact the rules need, other than a `MAYBE`, is in the case and is not `null`, and that a value given for a `NUMBER`, `BOOLEAN` or `STRING` fact, or a `MAYBE` of one, is of that type, counting text that spells a number or a boolean as a run does. A fact declared through a synonym (`DECLARE Year IS A NUMBER`) is judged as the type the synonym stands for, and so is a synonym for a `MAYBE`. A synonym that takes a type (`Optional OF NUMBER`) is not: a case can be `valid` that a run refuses, and `invalid` that a run answers.

**It judges those three types only.** For any other type, such as a `DATE`, a list, a record or a list of choices, whatever is given is let through, and a bad value fails only when the case is run. With this rule:

```l4
@export Echo a date
GIVEN d IS A DATE
GIVETH A DATE
`echo date` MEANS d
```

and the cases `[{"d": "2024-01-15"}, {"d": "not a date"}]`, validation passes both, and a run fails the second:

```
$ l4 batch echo-date.l4 --inputs dates.json --validate-only
{"errors":[],"input":{"d":"2024-01-15"},"status":"valid"}
{"errors":[],"input":{"d":"not a date"},"status":"valid"}

$ l4 batch echo-date.l4 --inputs dates.json --continue-on-error
{"diagnostics":[],"input":{"d":"2024-01-15"},"output":[{"result":"2024-01-15","trace":null}],"status":"success"}
{"diagnostics":["Could not parse date string 'not a date'. Expected format: YYYY-MM-DD"],"input":{"d":"not a date"},"output":[{"result":{"error":"Could not parse date string 'not a date'. Expected format: YYYY-MM-DD\n"},"trace":null}],"status":"error"}
```

So `valid` means a case has the right shape, not that the rules will accept every value in it.

#### What the rules and the file have to be

`l4 batch` does not run your rules file as it stands. It checks the file, prints the checked module back as source with its directives taken out, and for each case adds a small wrapper that reads the case and applies the exported function; then it checks and runs that text. Four things follow.

- **The printed module has to be valid source.** If it is not, every case is an `error` line with the parser's message, and the cause is the rules file and not the cases. One shape that does this is a bare quoted string used as a condition inside a boolean expression, such as `a AND "and also" AND TRUE`.
- **An exported function whose `MAYBE` input is followed by another input cannot be run.** The wrapper it needs is not valid, and every case is an `error` line. Put the `MAYBE` input last.
- **Every case checks the whole module again,** and the modules it imports, so a large rules file with many cases takes time.
- **A CSV file has to be UTF-8** (in Excel, save as "CSV UTF-8"). A file in another encoding stops the command at the first bad byte, with an error message from the Haskell runtime and a backtrace, exit status 1, and no `Error:` line; in the default streaming output, the cases before the bad byte have already run and printed.

#### When the command cannot start

If `l4 batch` cannot read the cases or the rules, it prints no line for any case and exits with status 1. It says why in one plain line that starts `Error:`, on standard output, which is where the case lines go, so a script that reads the output as JSON should look at the exit status before it parses:

- `Error: failed to parse inputs: …` for a cases file that is not valid JSON, YAML or CSV; for a CSV file it names the line, as in ``line 2 of the CSV file is not valid CSV, near `"c` ``, an empty CSV file is said to be empty, and a quote that opens a cell and is never closed is refused at the line where it opens;
- `Error: --input-format is required when the extension can't be inferred (e.g. reading from stdin)`;
- `Error: type checking failed` for rules that do not type-check, with the type errors themselves on standard error;
- `Error: no @export functions found in module`, or `Error: no @export function named 'name' found` when `--entrypoint` names one that is not there.

A cases file or a rules file that does not exist ends the command with the operating system's message on standard error instead.

### `l4 trace` and `l4 state-graph` — visualization

- `l4 trace myfile.l4` renders every `#EVALTRACE` in the file as GraphViz DOT (`--format dot|png|svg`, `-o DIR` for image output; PNG/SVG need GraphViz installed).
- `l4 state-graph myfile.l4` extracts the state transition graph of regulative rules (`PARTY ... MUST ...`) as GraphViz DOT.

### `l4 ast` — the parsed syntax tree

`l4 ast myfile.l4` dumps the parsed AST. You will rarely need it unless you are debugging L4 tooling itself.

---

## Step 7: Deploy as an API

`l4 deploy` turns a file into a live REST API on [Legalese Cloud](https://legalese.cloud), as the VS Code extension's **Deploy** tab does. Only rules marked `@export` become endpoints; [Exporting Rules for Deployment](../deploying-rules/exporting-rules-for-deployment.md) explains how to mark them.

### Sign in

`l4` gets your Legalese Cloud credentials from the `legalese` CLI, so you sign in once and `l4` never stores a token:

```bash
l4 install legalese    # downloads it (checksum-verified) to /usr/local/bin or ~/.local/bin
legalese login         # signs you in through the browser and picks your organization
```

`l4 install legalese` runs on macOS and Linux. Run it again to upgrade.

### Deploy, update, list, remove

```bash
l4 deploy late-fee.l4 --description "Late fees for overdue invoices"
```

```
Deploying 'late-fee' to Legalese Cloud org 'acme' (as you@example.com): late-fee.l4
Compiling…
Deployed 'late-fee' (version 1.0.0) with 1 function:
  fee
API: https://api.legalese.cloud/acme/late-fee
```

The deployment is named after the file unless you pass `--name`. `l4` runs the same check as `l4 check` on the file first, then uploads it with the files it imports. The standard libraries are not uploaded: a deployment finds `prelude`, `daydate` and the others in the copy built into the service.

| Command            | What it does                                                                                                                                                        |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `l4 deploy FILE`   | Creates a deployment. Refuses if the name is taken.                                                                                                                 |
| `l4 redeploy FILE` | Updates an existing deployment. If the update would break existing integrations (a rule removed, a parameter changed), it is rejected; `--force` applies it anyway. |
| `l4 deployments`   | Lists your organization's deployments.                                                                                                                              |
| `l4 undeploy NAME` | Deletes a deployment after you type its name to confirm. In scripts, pass `--yes`.                                                                                  |

`--json` prints machine-readable results, and `--no-wait` returns as soon as the upload is accepted instead of waiting for it to compile.

### Your own jl4-service

To deploy to a jl4-service you run yourself, name it with `--server`:

```bash
l4 deploy late-fee.l4 --server http://localhost:8080
```

If it needs an API key, put the key in the `L4_API_KEY` environment variable or in a file passed with `--api-key-file`. `l4` won't send a key over plain `http` to anything but `localhost`.

---

## Step 8: The REPL

For interactive exploration there is a separate REPL executable. From a source checkout:

```bash
cabal run jl4-repl -- late-fee.l4
```

Then evaluate expressions live:

```
> `late fee` `a very late invoice`
50
```

Useful REPL commands: `:help`, `:load <file>` / `:reload`, `:type <expr>`, `:info <name>` / `:env`, `:decides` and `:queryplan` (query planning), and `:trace` / `:traceascii` / `:tracefile` (evaluation traces). See [jl4-repl's README](https://github.com/legalese/l4-ide/tree/main/jl4-repl) for the full list.

---

## What You Learned

- How to install or build the `l4` binary
- `l4 run` evaluates `#EVAL` directives; `l4 check` typechecks fast for CI
- `--json` gives machine-readable output; `--fixed-now` pins the clock
- `JL4_LIBRARY_PATH` controls where `IMPORT`ed libraries come from
- `format`, `render`, `batch`, `trace`, `state-graph`, and `ast` round out the toolset
- `l4 deploy`, `redeploy`, `deployments`, and `undeploy` manage live APIs on Legalese Cloud or your own jl4-service
- `cabal run jl4-repl` starts an interactive session

---

## Next Steps

- [Testing Your Rules](testing-your-rules.md) — assertions and contract simulation with `#ASSERT` and `#TRACE`
- [Debugging Type Errors](debugging-type-errors.md) — reading and fixing the errors `l4 check` reports
- [Exporting Rules for Deployment](../deploying-rules/exporting-rules-for-deployment.md) — turn a file into a live API
