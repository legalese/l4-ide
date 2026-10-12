# `l4 batch`: one export, many input rows (as built)

As built on `main` by this PR.
Source spec: `specs/todo/BATCH-PROCESSING-SPEC.md`, which `main` already has (on `unstable` the same file is `specs/done/BATCH-PROCESSING-SPEC.md`).
Differences from the source spec: the CLI is `l4 batch FILE --inputs PATH`, not `jl4-cli --batch BATCH_FILE L4FILE`; the default output is NDJSON, not "same format as input"; `--parallel`, `--verbose`, `--simple` and `--trace` are not built; with several exports and no `@export default`, the first export is used instead of reporting an error; CSV dates stay strings; `--validate-only` reads each value by the declared type, as evaluation does, and does not warn about extra fields; a failing row carries `diagnostics` (or `errors`), not an `error` field, and no aggregated error summary is printed.
The work came from `unstable`; this page describes only what `main` has.
Line numbers are in this PR's tree, on `main` at `00298eb60`.

Source: PR #47 (`tier2/batch-processing`; branch commits `582b956c6`, `291cd0051`; batch merge `eeb432e7d`, landed on unstable through #77), for the third commit of this PR, #625 (`0af1211a7` on unstable), which makes `l4 batch` read each value by the type its input declares, and for the tests, fixtures and `doc/` text of the fourth, #632 (merge `3fa87dee6` on unstable), with the blank-cell reading of the ruling T3c adapted to `main` (see below).
The `batch` verb existed before #47 (`74efdc5d7`, 2026-04-12), and `main` already had it; #47 completed it: output formats, `--output`, `--continue-on-error`, `--validate-only`, CSV type inference, and runtime exceptions counted as row failures.
Spec history: `BATCH-PROCESSING-SPEC.md` was added as `doc/todo/…` by `18215e82d` (2025-12-12), moved to `specs/todo/` by `09fbfd41f` (smucclaw/l4-ide#730), and on unstable moved to `specs/done/` by `b4469830a` (PR #85), whose status line names PR #47.
`specs/todo/batch-json-output.md` (moved to `done/` on unstable by `ba95f0cdc`, "#46") specifies the JSON encoding of result values, which predates #47; it is not this PR's spec.
On `main` both files are under `specs/todo/`.

## What it does

`l4 batch FILE --inputs ROWS` type-checks FILE once, picks one `@export` function, and evaluates it once per input row from a JSON, YAML or CSV file (or stdin).
Each row yields a result envelope; by default the envelopes stream out as NDJSON, one line per row, as each row completes.

## Where it lives

- `jl4/app/L4/Cli/Batch.hs` (710 lines); wired as the `batch` command at `jl4/app/Main.hs:72-78` and dispatched at `:125`.
- Options: `BatchOptions` and `batchOptionsParser` (`Batch.hs:89-157`); `OutputFormat` = `FmtNdjson | FmtJson | FmtCsv | FmtYaml` (`:82-87`).
- Driver: `batchCmd` (`:163-229`); row loops `streamRows` (`:249-264`) and `bufferRows` (`:270-284`); per-row `processRow` (`:298-338`).
- Input: `BatchRow` and `RowSource` (`:423-433`), `parseBatchInput` (`:435-466`), `declareInputs` with `jsonNumber` and `jsonBool` (`:468-508`), and `inferCsvCell` (`:510-533`).
- Validation: `validateRow`, `primKind`, `unwrapMaybe` (`:355-402`).
- Output: `writeBuffered`, `encodeJsonArray`, `encodeCsv`, `orderedEnvCols`, `flattenEnvelope` (`:539-600`).
- Wrapper generation: `generateBatchWrapper` and helpers (`:616-691`); entrypoint choice `findExportFunction` (`:697-710`).

## Behaviour and rules

Options: `--inputs/-i PATH` (`-` = stdin), `--input-format json|yaml|csv` (else inferred from `.json`, `.yaml`, `.yml`, `.csv`), `--entrypoint/-e NAME`, `--format/--output-format/-f ndjson|jsonl|json|csv|yaml|yml` (default `ndjson`), `--output/-o FILE`, `--continue-on-error/-c`, `--validate-only`, and the shared `--fixed-now`.
Input: a JSON or YAML array gives one row per element, and any other single value is one row; CSV needs a header row (`Csv.decodeByName`).
Typing (`parseBatchInput`, `declareInputs`): a CSV cell is read as text, except that a blank one is left out of the case; every case is then typed against the export's inputs, whichever file it came from.
A blank CSV cell (empty, spaces only, or a quoted `""`) is absent, exactly as if its column were missing from the file, for every type of input: ruling T3c, in `specs/todo/TYPICALLY-ONE-BEHAVIOUR-SPEC.md` on `unstable` ("In `l4 batch` CSV input, an empty cell is absent, not null").
An input that has to be given is then reported as `Missing required field '<p>' in JSON object` (status `error`; `--validate-only` says `Missing required field: '<p>'`), and a `MAYBE` input is `NOTHING`.
A NUMBER or BOOLEAN input (a `MAYBE` one too) given as text is read as the number or boolean the text spells, with aeson's JSON number grammar and `true`/`false` in any case, so `"25"` in a JSON file and a `25` cell in a CSV file both arrive as the number 25; text that does not spell one is left alone, so the decode error names that value.
A STRING input keeps a non-blank CSV cell as the text written, so `123456`, `018956`, `1.50` and `1e3` arrive as the codes they are; a JSON or YAML number sent for a STRING input stays an error, because those files already say which values are strings.
An input of any other type, or one the export does not declare, is left alone for JSON and YAML; a CSV cell for it is typed by content (`inferCsvCell`): `true`/`false` in any case become booleans, a cell containing `e` or `E` stays a string, and otherwise aeson's JSON number grammar decides, so `42` and `3.5` become numbers while `007`, `1,000` and `+5` stay strings.
The typed case is what validation, the generated wrapper and the echoed `input` all see (`:338`).
Entrypoint: `--entrypoint` names the export exactly; else the `@export default` function; else the first export; else the error `no @export functions found in module`.
Parameters: the export's GIVENs become call arguments.
Evaluation pipeline, read in code: the checked module goes through `filterIdeDirectives` (dropping every `#EVAL`/`#ASSERT`) and is re-emitted as source by `prettyLayout` (`:206-207`).
A string literal in that printed source has its line breaks, tabs and carriage returns written as escapes (`escapeSourceStringLiteral`, `jl4-core/src/L4/Print.hs:896-901`, used at `:580`), because a raw newline would become a layout line break that takes the body's indentation (smucclaw/l4-ide#1028, from #595).
Per row, a generated wrapper is appended to that text: `DECLARE InputArgs HAS …`, a `decodeArgs` function using `JSONDECODE`, `DECIDE inputJson IS "<row JSON>"`, and one `#EVAL` of `CONSIDER decodeArgs inputJson` applying the export.
The combined text is registered as the virtual file `<FILE>.batch<N>.l4`, next to FILE, and evaluated with `Rules.EvaluateLazy` in a fresh one-shot build (`:309-315`).
Envelope (evaluate mode): `{input, output, status, diagnostics}`; `output` is the array of directive results, e.g. `[{"result":20,"trace":null}]`.
The status is `error` if the wrapper failed to check (then `output` is `null`) or any directive raised an evaluation exception, else `success` (`:316-327`).
Envelope (`--validate-only`, no evaluation): `{input, status: valid|invalid, errors}`.
Validation checks, on the typed case, that each required (non-`MAYBE`) parameter is present and non-null, and that NUMBER, BOOLEAN and STRING values (after unwrapping `MAYBE`) have the right JSON kind; compound types are not judged.
Failure and exit: a row with status `error` or `invalid` is a failure; without `-c` the run stops after emitting that row; with `-c` every row is processed; the exit code is 1 if any row failed, else 0.
Output: NDJSON is written and flushed row by row without keeping the list of envelopes; `json` is an array with one compact envelope per line; `yaml` is a YAML sequence; `csv` has sorted `input_<field>` columns, then `output`, `status`, `errors`, `diagnostics` where present, with compound cells encoded as compact JSON.

## Diagnostics

Fatal errors, printed to stdout (not stderr) before any row, with exit code 1: `Error: --input-format is required when the extension can't be inferred (e.g. reading from stdin)`, `Error: failed to parse inputs: <parser message>`, `Error: type checking failed` (after the check diagnostics), `Error: no @export function named '<n>' found`, `Error: no @export functions found in module`.
An unknown `--format` is rejected by the option parser: `Invalid output format: <x> (expected ndjson|json|csv|yaml)`; an unknown `--input-format` surfaces as `Error: failed to parse inputs: Unsupported format: <x>`.
Validation messages (`:361-375`): `Missing required field: '<p>'`, `Field '<p>' is null but required`, `Type mismatch for field '<p>': expected <KIND>, got <KIND>`, each followed by ` (<@desc text>)` when the parameter has one; and `Input record is not a JSON object: <kind>`.

## Tests and fixtures that pin it

- From #47: `jl4/tests-cli/Main.hs:376-455` (NDJSON default, CSV cells typed by declared type, `--format json`, `--format csv`, `--output`, stop-on-error, `--continue-on-error`, `--validate-only`, an exponent cell kept as a string, `MAYBE` validation at `:540`); the case at `:529`, a line break and a tab inside a string literal, is #595's, and the nested `describe "reads a value by the type its input declares"` at `:556-626` is #625's (with #632's `MAYBE` test at its end).
- From #625 (`:556-612`): text for a NUMBER or BOOLEAN input is read as a number or boolean in JSON and in YAML and passes `--validate-only`; a CSV cell for a STRING input keeps the text written (`123456`, `018956`, `1.50`, `1e3`); a JSON number for a STRING input is still an error; text that is not a number is left alone, so the error names it.
- From #632, as adapted to `main`:
  - `:614-626` a `MAYBE` NUMBER input given as text is read as the number it spells, and text that is not one is an error that names it (fixture `batch-maybe-text.json`);
  - `:471` a CSV cell in a column no input declares is typed by how it looks, and `1E5` stays text (fixture `batch-undeclared-column.csv`; this is the one test that reaches `inferCsvCell`, so the two tests before it, `:383` and `:455`, are renamed for what they do: they read by the declared type);
  - `:638` the step `l4 trace` prints for a string literal holds a backslash and an `n`, where `main` broke it across lines (fixture `evaltrace-line-break.l4`);
  - `jl4-service/test/IntegrationSpec.hs:691-712` the same for the `exampleCode` of the reasoning tree, and that `explanation` keeps the line break (`lineBreakJL4` in `jl4-service/test/TestData.hs`).
- Written for this PR's reading of T3c: `:482-527` a blank CSV cell is absent, for a required STRING input (`Missing required field 'code'`), a `MAYBE` STRING input (`NOTHING`) and a required NUMBER input, and `--validate-only` says `Missing required field: 'income'` (fixtures `batch-blank.l4`, `batch-blank.csv`, `batch-blank-income.csv`); and `:397` a cases file holding one object is one case (`batch-single-object.json`).
- From #595: `jl4-core/test/PrintRoundtripSpec.hs:27` (a string with a line break and a tab prints with its escapes and re-parses) and the fixtures `jl4/tests-cli/fixtures/batch-string-line-break.l4` and `.json`.
- Fixtures (#47): `jl4/tests-cli/fixtures/batch-elig.l4`, `batch-data.json`, `batch-data.csv`, `batch-mixed.json`, `batch-code.l4`, `batch-exponent.csv`, `batch-maybe.l4`, `batch-maybe-bad.json`.
- Fixtures (#625): `jl4/tests-cli/fixtures/batch-declared-strings.json`, `batch-declared-strings.yaml`, `batch-declared-string-cells.csv`, `batch-declared-bad-number.json`, `batch-declared-number-for-string.json`.
- Other `l4 batch` tests on `main` are not part of this change: the printer-bracket and grouping cases `describe "l4 batch keeps the grouping the rule wrote"` and `describe "l4 batch agrees with l4 run"` (`jl4/tests-cli/Main.hs:733` and `:752`).
- Run against `main`'s own `l4` (`L4_BIN`), 22 of the 57 tests in that file fail.
  Most of them fail because `main` has no `--format`, `--output`, `--continue-on-error` or `--validate-only`, which says nothing about the behaviour; the ones that fail for the behaviour itself, with only options `main` has, are the single-object case (`:397`), the string-literal step in `l4 trace` (`:638`) and the line-break case (`:529`).
  The other behaviours were each measured by hand with `main`'s own options, as listed under "What changes against `main`".

## Limits and known defects

- A CSV cell for an input whose type is not NUMBER, BOOLEAN or STRING, or which the export does not declare, is typed by its content (`inferCsvCell`); the undeclared-column case is pinned by `:471`, the non-primitive one was not probed.
- `--validate-only` judges NUMBER, BOOLEAN and STRING inputs (and a `MAYBE` of one) only.
  For any other type, such as a DATE, a list or a record, whatever is given passes: with an `@export` taking a DATE, the cases `2024-01-15` and `not a date` are both `valid`, and the second fails when run (`Could not parse date string 'not a date'`).
- A module that contains an inert string (a bare quoted string in a boolean expression, such as `a AND "and also" AND TRUE`) cannot be batched: the printed module does not re-parse, and every row has status `error` with the parser's message (loud, exit 1).
  `main` does the same, so this PR neither adds nor fixes it.
- An `@export` whose `MAYBE` input is followed by another input cannot be batched: the generated wrapper has an indentation error, and every row has status `error` (loud, exit 1; `main` too).
  Put the `MAYBE` input last.
- Every row re-parses and re-type-checks the whole printed module in a new one-shot build (read in code; cost not measured).
- Correctness rests on `prettyLayout` reproducing the module's meaning; the printed text is the program that runs.
- Fatal errors go to stdout, not stderr, as one line starting `Error:` (a cases file or rules file that does not exist is the exception: the operating system's message goes to stderr).
- The wrapper adds the top-level names `InputArgs`, `decodeArgs` and `inputJson`; a module that already defines one was not probed.
- The row JSON is put into the wrapper by `escapeAsL4String` (`:664-668`), which escapes only the double quote; a separate change replaces it.

## What changes against `main`

Every item below was measured with the `l4` built from plain `main` (`00298eb60`) and the one built from this PR, on the cases named; the tests that pin them are listed above, and each of them fails on `main`'s `l4` except where the item says otherwise.

**Reading by declared type, which restores what the first commit broke.**
`main`'s own `l4 batch` coerced string values to the declared NUMBER/BOOLEAN types on every input row (`coerceInputTypes`, `f6ebc282e`).
This PR's first commit (#47) replaced that with typing by cell content, which broke two inputs that work on `main`: a JSON or YAML row with `"age": "25"` for a NUMBER input, and a digits-only CSV cell such as `123456` for a STRING input.
The third commit (#625) reads each value by the type its input declares instead (`declareInputs`), which restores both and also covers `MAYBE` inputs and YAML.
`batch-elig.l4` with the row `{"age":"25","income":"50000","hasViolations":"false"}` answers `true` with status `success` in both, and `batch-code.l4` with the CSV cells `123456` and `018956` returns them unchanged in both.

**What differs from `main`, all of it deliberate:**

1. **The run stops at the first failing row** unless `--continue-on-error` is given; `main` processed every row and has no such option.
   On `batch-mixed.json` (three rows, the second with `"income":"NOT_A_NUMBER"`) `main` writes three lines; this PR writes two and exits 1, and with `--continue-on-error` writes three and exits 1.
2. **A row whose evaluation raises an error has status `error`, and the exit code is 1.**
   `main` reports the same row with status `success`, the error as an object in `result`, and exits 0.
   Same file, second row: `main` `"status":"success"` with `{"error":"…"}` as the result; this PR `"status":"error"` with the message in `diagnostics`.
3. **A blank CSV cell is absent, not text** (T3c, see Typing above).
   `main` read an empty or spaces-only cell as the text it held.
   With `batch-blank.l4` (a STRING input `code`, a `MAYBE STRING` input `note`) and `batch-blank.csv`: an empty or spaces-only `code` is `""` or `"  "` on `main`, and `Missing required field 'code' in JSON object` (status `error`) here; a blank `note` is `JUST ""` or `JUST "  "` on `main`, and `NOTHING` here.
   With `batch-elig.l4` and `batch-blank-income.csv`, a blank NUMBER cell gave status `success` with `{"error":"Expected JSON number but got: String \"\""}` as the result on `main`, and is `Missing required field 'income' in JSON object` (status `error`) here.
4. **A `MAYBE` NUMBER or BOOLEAN input given as text is read as what the text spells.**
   `batch-maybe.l4` with `{"premium":"25"}`: `main` returned status `success` with `{"error":"Expected JSON number but got: String \"25\""}` as the result; this PR returns `25`.
   Text that is not a number (`"abc"`) is an error here, naming the text.
5. **A cases file that holds one JSON object is one case.**
   `main` stopped with `Error: failed to parse inputs: Error in $: parsing [] failed, expected Array, but encountered Object`.
6. **A CSV cell in a column that no input declares is typed by its content in the echoed `input`**, so `true` is `true` and `123456` is `123456` there.
   `main` echoed every such cell as text.
   `batch-undeclared-column.csv` against `batch-elig.l4`: `main` echoes `"flag":"true"`; this PR `"flag":true`.
   The cell is not used by the rules in either; only the echo differs.
7. **The REPL keeps a line break inside a string literal.**
   `:load` a file with `greeting MEANS "line\nnext"`, then `greeting`: `main` prints `"line` and `  next"` (the second line takes the body's indentation); this PR prints `"line` and `next"`.
   This is the printer fix from #595 (smucclaw/l4-ide#1028), and it is what lets `l4 batch` re-print a module that holds such a string (see Evaluation pipeline above).
8. **A string literal in a printed step is spelled as source.**
   `l4 trace` prints the step `IF (x GREATER THAN 0) THEN "line\nnext" ELSE "tab\there"` with a backslash and an `n`, where `main` printed it across two lines with a real tab; and the `exampleCode` of the `jl4-service` reasoning tree is spelled the same way (a service call with `?trace=full` on a rule that returns such a string: two `exampleCode` entries held a raw line break on `main`, none does here).
   `explanation` prints the value and still holds the line break.
   Assumed, not ruled (2026-10-13): the escaped form is kept, because it is the valid spelling of the source.
   `l4 run` prints no trace steps on `main` ("no trace captured"), so it is not affected.
9. **The `batch` summary in `l4 --help`** says `(json|yaml|csv in, NDJSON streaming out)`, where `main` said `(NDJSON streaming)`.

The command, the options it had, the output keys and `main`'s backtick-quoting of natural-language export and parameter names (`quoteIdent`, also from `f6ebc282e`) are otherwise as on `main`.
`doc/tutorials/getting-started/l4-cli.md` (under `l4 batch`) is rewritten to describe reading by declared type, blank cells, `--format` and `--output`, what each line says, stop-at-first-failure with `--continue-on-error`, `--validate-only` and its limits, and where fatal errors go.

## Later changes on unstable that `main` does not have

- #51: the row JSON is quoted with the lexer's `showStringLit` instead of the hand-rolled escape.
- #214: `prettyLayout` made to re-emit parseable, re-checkable source. (Its `batch` help text, which says input is json|yaml|csv, is written here independently.)
- #595: its change to the `Inert` arm of the printer is not here; `main` prints an inert string as `"..." <+> dquotes (pretty txt)` (`Print.hs:440-441`), which needs its own change first.
- #328: read ASSUMEs are bound by name via `rewriteModuleAssumes`, not passed as positional arguments.
- #330: an `#ASSERT` that raises counts as a row exception.
- #334: the `refused` status, which neither fails nor stops the batch.
- #440: `restoreMixfixPatterns` runs before printing, so operators sharing a head keyword survive the re-print.
