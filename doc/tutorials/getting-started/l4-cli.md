# Using the l4 CLI

Run, check, format, and render L4 files from the command line.

**Prerequisites:** [Your First L4 File](first-l4-file.md)

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

Usage: l4 (COMMAND | FILE [--json] [-t|--trace MODE] [--fixed-now ISO8601])

Available commands:
  run                      Typecheck and evaluate an L4 file (prints diagnostics
                           + #EVAL results)
  check                    Typecheck an L4 file only (fast path; no evaluation)
  format                   Reformat an L4 file and print to stdout
  ast                      Dump the parsed AST of an L4 file
  batch                    Evaluate an @export function against many input rows
                           (NDJSON streaming)
  trace                    Render #EVALTRACE evaluation traces as GraphViz
                           (dot|png|svg)
  state-graph              Extract regulative-rule state transition graphs as
                           GraphViz DOT
  render                   Render an L4 file to a formatted document
                           (html|text|json|plan)
```

Run `l4 <command> --help` for the options of any subcommand.

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

Each `Evaluation[n]` block corresponds to one `#EVAL` directive, in file order, with the source range it came from. Diagnostics (errors, warnings) are printed to stderr; results go to stdout. The exit code is `0` when the file typechecks and every directive evaluates without crashing; type errors and runtime evaluation errors (such as a `CONSIDER` with no matching branch) exit non-zero. Warnings alone do not change the exit code — a file with warnings still evaluates.

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

Exit code `0` means the file is valid L4; non-zero means there were errors (printed as diagnostics). `--json` and `--fixed-now` work here too.

---

## Step 5: Libraries and `JL4_LIBRARY_PATH`

When a file says `IMPORT daydate` (or `time`, `currency`, ...), the tools resolve the library module by checking, in order:

1. The `JL4_LIBRARY_PATH` environment variable (user/operator override)
2. The project root directory
3. The directory of the importing file
4. The XDG data directory (`~/.local/share/jl4/libraries/`)
5. The libraries bundled with the VS Code extension

When `JL4_LIBRARY_PATH` is set, it takes explicit control: the embedded fallback libraries are skipped. This matters when you work from a source checkout and want the CLI to use the checkout's libraries rather than a previously installed copy:

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

### `l4 format` — canonical formatting

Reformats a file and prints the result to stdout (like `gofmt`):

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

Options: `--format html|text|json|plan`, `-o/--output FILE`, `--toc` (table of contents), `--number-sections`, `--number-clauses`, and `--include-unused`.

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

Natural-language names work too: exported functions and parameters written with backticks and spaces (`` `the base rate` ``) are matched by input keys spelled the same way (`"the base rate": 100`). With CSV inputs, cells are plain text in the file, but values for parameters declared as `NUMBER` or `BOOLEAN` are converted automatically — a `100` or `true` cell arrives as a number or boolean, not a string.

### `l4 trace` and `l4 state-graph` — visualization

- `l4 trace myfile.l4` renders every `#EVALTRACE` in the file as GraphViz DOT (`--format dot|png|svg`, `-o DIR` for image output; PNG/SVG need GraphViz installed).
- `l4 state-graph myfile.l4` extracts the state transition graph of regulative rules (`PARTY ... MUST ...`) as GraphViz DOT.

### `l4 ast` — the parsed syntax tree

`l4 ast myfile.l4` dumps the parsed AST. You will rarely need it unless you are debugging L4 tooling itself.

---

## Step 7: The REPL

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
- `cabal run jl4-repl` starts an interactive session

---

## Next Steps

- [Testing Your Rules](testing-your-rules.md) — assertions and contract simulation with `#ASSERT` and `#TRACE`
- [Debugging Type Errors](debugging-type-errors.md) — reading and fixing the errors `l4 check` reports
- [Exporting Rules for Deployment](../deploying-rules/exporting-rules-for-deployment.md) — turn a file into a live API
