# `l4 batch`: one export, many input rows (as built)

As built on `main` by this PR.
Source spec: `specs/todo/BATCH-PROCESSING-SPEC.md`, which `main` already has (on `unstable` the same file is `specs/done/BATCH-PROCESSING-SPEC.md`).
Differences from the source spec: the CLI is `l4 batch FILE --inputs PATH`, not `jl4-cli --batch BATCH_FILE L4FILE`; the default output is NDJSON, not "same format as input"; `--parallel`, `--verbose`, `--simple` and `--trace` are not built; with several exports and no `@export default`, the first export is used instead of reporting an error; CSV dates stay strings; `--validate-only` reads each value by the declared type, as evaluation does, and does not warn about extra fields; a failing row carries `diagnostics` (or `errors`), not an `error` field, and no aggregated error summary is printed.
The work came from `unstable`; this page describes only what `main` has.
Line numbers are in this PR's tree, on `main` at `00298eb60`.

Source: PR #47 (`tier2/batch-processing`; branch commits `582b956c6`, `291cd0051`; batch merge `eeb432e7d`, landed on unstable through #77), for the third commit of this PR, #625 (`0af1211a7` on unstable), which makes `l4 batch` read each value by the type its input declares, and for the tests, fixtures and `doc/` text of the fourth, #632 (merge `3fa87dee6` on unstable), with the blank-cell reading of the ruling T3c adapted to `main` (see below), and, for the fourth commit's CSV reader, unstable's `csvRows` (a ruling, below), and #635 (`af06ea470` on unstable) for a CSV cell for a choice or a date.
The `batch` verb existed before #47 (`74efdc5d7`, 2026-04-12), and `main` already had it; #47 completed it: output formats, `--output`, `--continue-on-error`, `--validate-only`, CSV type inference, and runtime exceptions counted as row failures.
Spec history: `BATCH-PROCESSING-SPEC.md` was added as `doc/todo/…` by `18215e82d` (2025-12-12), moved to `specs/todo/` by `09fbfd41f` (smucclaw/l4-ide#730), and on unstable moved to `specs/done/` by `b4469830a` (PR #85), whose status line names PR #47.
`specs/todo/batch-json-output.md` (moved to `done/` on unstable by `ba95f0cdc`, "#46") specifies the JSON encoding of result values, which predates #47; it is not this PR's spec.
On `main` both files are under `specs/todo/`.

## What it does

`l4 batch FILE --inputs ROWS` type-checks FILE once, picks one `@export` function, and evaluates it once per input row from a JSON, YAML or CSV file (or stdin).
Each row yields a result envelope; by default the envelopes stream out as NDJSON, one line per row, as each row completes.

## Where it lives

- `jl4/app/L4/Cli/Batch.hs` (878 lines); wired as the `batch` command at `jl4/app/Main.hs:72-78` and dispatched at `:125`.
- Options: `BatchOptions` and `batchOptionsParser` (`Batch.hs:99-167`); `OutputFormat` = `FmtNdjson | FmtJson | FmtCsv | FmtYaml` (`:91-97`).
- Driver: `batchCmd` (`:173-243`); row loops `streamRows` (`:258-278`) and `bufferRows` (`:280-298`); per-row `processRow` (`:300-370`), whose first clause answers a refused CSV record (`:313`).
- Input: `BatchRow` and `RowSource` (`:455-468`), `parseBatchInput` (`:470-507`), `declareInputs` with `declaredInputs`, `typeSynonyms`, `moduleDeclares`, `allDependencies`, `jsonNumber` and `jsonBool` (`:509-605`), the CSV reader `CsvRow` and `csvRows` (`:607-676`), and `inferCsvCell` (`:678-701`).
- Validation: `validateRow`, `primKind`, `unwrapMaybe` (`:383-434`).
- Output: `writeBuffered`, `encodeJsonArray`, `encodeCsv`, `orderedEnvCols`, `flattenEnvelope` (`:707-768`).
- Wrapper generation: `generateBatchWrapper` and helpers (`:784-859`); entrypoint choice `findExportFunction` (`:865-878`).

## Behaviour and rules

Options: `--inputs/-i PATH` (`-` = stdin), `--input-format json|yaml|csv` (else inferred from `.json`, `.yaml`, `.yml`, `.csv`), `--entrypoint/-e NAME`, `--format/--output-format/-f ndjson|jsonl|json|csv|yaml|yml` (default `ndjson`), `--output/-o FILE`, `--continue-on-error/-c`, `--validate-only`, and the shared `--fixed-now`.
Input: a JSON or YAML array gives one row per element, and any other single value is one row; CSV needs a header row, and is read record by record by `csvRows` (below), not by cassava's `decodeByName`.
CSV reading (`csvRows`, `CsvRow`): the file is read record by record, not by cassava's `decodeByName`, which drops every record that parses to one empty field and so dropped both a blank line and a line holding only `""`.
A UTF-8 byte-order mark before the header is skipped; it used to become part of the first column's name, so that input was missing from every row.
A blank line, and an unquoted line of only spaces or tabs, is not a record, in a one-column file too; a quoted `""` or `"   "` is a record whose one cell is blank, so absent.
A record with fewer or more cells than the header is refused, naming its line (`Line 3 has 2 cells, but the header has 3, so the row is refused: …`): the row is `RefusedRow`, with the cells it had under the header's names, typed by how they look, as its `input` (a cell beyond the header's width has no name and is dropped), status `error` (`invalid` under `--validate-only`), no output, and it counts as a failure like any other.
Line numbers count physical lines, so a quoted cell that holds a line break moves the next record's number.
Not ruled: the refusal of a ragged record, and the skipping of an unquoted line of only spaces or tabs in a one-column file, are decided by Claude overnight 2026-10-02, pending Meng's review (unstable's `TYPICALLY-ONE-BEHAVIOUR-SPEC.md`, "Decided by Claude overnight"; the alternative named there is that such a line is a row whose cell is absent).
Ruled 2026-10-12: that a cell of spaces and a quoted `""` are blank, and that `l4 batch` takes `csvRows` whole.
The byte-order mark skip is a plain bugfix and needed no ruling.
Typing (`parseBatchInput`, `declareInputs`): a CSV cell is read as text, except that a blank one is left out of the case; every case is then typed against the export's inputs, whichever file it came from.
A blank CSV cell (empty, spaces only, or a quoted `""`) is absent, exactly as if its column were missing from the file, for every type of input.
This is ruling T3c, `specs/todo/TYPICALLY-ONE-BEHAVIOUR-SPEC.md:308` on `unstable` at `f48a0ed75`: "In `l4 batch` CSV input, an empty cell is absent, not `null`", RULED 2026-10-02.
T3c says "empty"; that a cell of only spaces and a quoted `""` are blank too was ruled on 2026-10-12, together with taking unstable's `csvRows` whole.
An input that has to be given is then reported as `Missing required field '<p>' in JSON object` (status `error`; `--validate-only` says `Missing required field: '<p>'`), and a `MAYBE` input is `NOTHING`.
A NUMBER or BOOLEAN input (a `MAYBE` one too) given as text is read as the number or boolean the text spells, with aeson's JSON number grammar and `true`/`false` in any case, so `"25"` in a JSON file and a `25` cell in a CSV file both arrive as the number 25; text that does not spell one is left alone, so the decode error names that value.
An input declared through a synonym (`DECLARE Year IS A NUMBER`) is read the same way when the text spells a number or a boolean, but text that does not is not reported: it reaches the rules as text, the answer is `success`, and `--validate-only` calls the case valid (see Limits; `main` answered `Internal error` under `success`).
A STRING input keeps a non-blank CSV cell as the text written, so `123456`, `018956`, `1.50` and `1e3` arrive as the codes they are; a JSON or YAML number sent for a STRING input stays an error, because those files already say which values are strings.
Every other declared input keeps a non-blank CSV cell as the text written (#635): a choice named `True` receives the name and not a boolean, and a `DATE` receives `20261013` as text, so the decoder reports it as a bad date.
Only a column that no input declares, and an input whose type the export does not give, is typed by content (`inferCsvCell`): `true`/`false` in any case become booleans, a cell containing `e` or `E` stays a string, and otherwise aeson's JSON number grammar decides, so `42` and `3.5` become numbers while `007`, `1,000` and `+5` stay strings.
A JSON or YAML value for an input of another type is left alone.
The typed case is what validation, the generated wrapper and the echoed `input` all see (`:370`).
Entrypoint: `--entrypoint` names the export exactly; else the `@export default` function; else the first export; else the error `no @export functions found in module`.
Parameters: the export's GIVENs become call arguments.
Evaluation pipeline, read in code: the checked module goes through `filterIdeDirectives` (dropping every `#EVAL`/`#ASSERT`) and is re-emitted as source by `prettyLayout` (`:216-217`).
A string literal in that printed source has its line breaks, tabs and carriage returns written as escapes (`escapeSourceStringLiteral`, `jl4-core/src/L4/Print.hs:896-901`, used at `:580`), because a raw newline would become a layout line break that takes the body's indentation (smucclaw/l4-ide#1028, from #595).
Per row, a generated wrapper is appended to that text: `DECLARE InputArgs HAS …`, a `decodeArgs` function using `JSONDECODE`, `DECIDE inputJson IS "<row JSON>"`, and one `#EVAL` of `CONSIDER decodeArgs inputJson` applying the export.
The combined text is registered as the virtual file `<FILE>.batch<N>.l4`, next to FILE, and evaluated with `Rules.EvaluateLazy` in a fresh one-shot build (`:341-347`).
Envelope (evaluate mode): `{input, output, status, diagnostics}`; `output` is the array of directive results, e.g. `[{"result":20,"trace":null}]`.
The status is `error` if the wrapper failed to check (then `output` is `null`) or any directive raised an evaluation exception, else `success` (`:348-366`).
Envelope (`--validate-only`, no evaluation): `{input, status: valid|invalid, errors}`.
Validation checks, on the typed case, that each required (non-`MAYBE`) parameter is present and non-null, and that NUMBER, BOOLEAN and STRING values (after unwrapping `MAYBE`) have the right JSON kind; compound types are not judged.
Failure and exit: a row with status `error` or `invalid` is a failure, and so is a refused CSV record (below); without `-c` the run stops after emitting that row; with `-c` every row is processed; the exit code is 1 if any row failed, else 0.
Output: NDJSON is written and flushed row by row without keeping the list of envelopes; `json` is an array with one compact envelope per line; `yaml` is a YAML sequence; `csv` has sorted `input_<field>` columns, then `output`, `status`, `errors`, `diagnostics` where present, with compound cells encoded as compact JSON.

## Diagnostics

Fatal errors, printed to stdout (not stderr) before any row, with exit code 1: `Error: --input-format is required when the extension can't be inferred (e.g. reading from stdin)`, `Error: failed to parse inputs: <parser message>`, `Error: type checking failed` (after the check diagnostics), `Error: no @export function named '<n>' found`, `Error: no @export functions found in module`.
An unknown `--format` is rejected by the option parser: `Invalid output format: <x> (expected ndjson|json|csv|yaml)`; an unknown `--input-format` surfaces as `Error: failed to parse inputs: Unsupported format: <x>`.
Validation messages (`:383-407`): `Missing required field: '<p>'`, `Field '<p>' is null but required`, `Type mismatch for field '<p>': expected <KIND>, got <KIND>`, each followed by ` (<@desc text>)` when the parameter has one; and `Input record is not a JSON object: <kind>`.

## Tests and fixtures that pin it

- From #47: `jl4/tests-cli/Main.hs:398-486` (NDJSON default, CSV cells typed by declared type, `--format json`, `--format csv`, `--output`, stop-on-error, `--continue-on-error`, `--validate-only`, an exponent cell kept as a string, `MAYBE` validation at `:639`); the case at `:628`, a line break and a tab inside a string literal, is #595's, and the nested `describe "reads a value by the type its input declares"` at `:655-758` is #625's, with #635's and #632's cases added to it.
- From #625 (`:655-711`): text for a NUMBER or BOOLEAN input is read as a number or boolean in JSON and in YAML and passes `--validate-only`; a CSV cell for a STRING input keeps the text written (`123456`, `018956`, `1.50`, `1e3`); a JSON number for a STRING input is still an error; text that is not a number is left alone, so the error names it.
- From #635 (`:713-744`): a CSV cell for a choice input is the name written (`True`), also for a `MAYBE` choice with a blank cell left out; a cell for a `DATE` input is text, so `20261013` is reported as a bad date; a synonym of NUMBER or BOOLEAN is still read as one (a pin, not a regression test) (fixtures `batch-declared-text.l4`, `batch-declared-text-answers.csv`, `-optional.csv`, `-dates.csv`, `-synonyms.csv`).
- From #632, as adapted to `main`:
  - `:746-758` a `MAYBE` NUMBER input given as text is read as the number it spells, and text that is not one is an error that names it (fixture `batch-maybe-text.json`);
  - `:488-502` a CSV cell in a column no input declares is typed by how it looks, and `1E5` stays text (fixture `batch-undeclared-column.csv`; this is the one test that reaches `inferCsvCell`, so the two tests before it, `:405` and `:477`, are renamed for what they do: they read by the declared type);
  - `:760-778` the step `l4 trace` prints for a string literal holds a backslash and an `n`, where `main` broke it across lines (fixture `evaltrace-line-break.l4`);
  - `jl4-service/test/IntegrationSpec.hs:691-712` the same for the `exampleCode` of the reasoning tree, and that `explanation` keeps the line break (`lineBreakJL4` in `jl4-service/test/TestData.hs`).
- Written for this PR's reading of T3c: `:504-547` a blank CSV cell is absent, for a required STRING input (`Missing required field 'code'`), a `MAYBE` STRING input (`NOTHING`) and a required NUMBER input, and `--validate-only` says `Missing required field: 'income'` (fixtures `batch-blank.l4`, `batch-blank.csv`, `batch-blank-income.csv`); and `:419-425` a cases file holding one object is one case (`batch-single-object.json`).
- Written for the ruled CSV reader, `describe "the CSV reader"` at `:549-626`: a one-column file with `alice`, `""`, `bob` is three cases and the `""` case is missing its input (`batch-onecol.l4`, `batch-onecol.csv`); a line of spaces, and a blank line, is not a case (`batch-onecol-spaces.csv`); a byte-order mark is not part of the first column's name (`batch-bom.csv`); a record with too few or too many cells is refused naming its line, with the sentence that says what would otherwise have happened, in `--validate-only` too (`batch-ragged.csv`); and CRLF line ends with a quoted cell holding a line break are read as before (`batch-crlf.csv`, a no-change pin).
- From #595: `jl4-core/test/PrintRoundtripSpec.hs:27` (a string with a line break and a tab prints with its escapes and re-parses) and the fixtures `jl4/tests-cli/fixtures/batch-string-line-break.l4` and `.json`.
- Fixtures (#47): `jl4/tests-cli/fixtures/batch-elig.l4`, `batch-data.json`, `batch-data.csv`, `batch-mixed.json`, `batch-code.l4`, `batch-exponent.csv`, `batch-maybe.l4`, `batch-maybe-bad.json`.
- Fixtures (#625): `jl4/tests-cli/fixtures/batch-declared-strings.json`, `batch-declared-strings.yaml`, `batch-declared-string-cells.csv`, `batch-declared-bad-number.json`, `batch-declared-number-for-string.json`.
- Other `l4 batch` tests on `main` are not part of this change: the printer-bracket and grouping cases `describe "l4 batch keeps the grouping the rule wrote"` and `describe "l4 batch agrees with l4 run"` (`jl4/tests-cli/Main.hs:866` and `:885`).
- Run against `main`'s own `l4` (`L4_BIN`), 31 of the 66 tests in that file fail.
  Most of them fail because `main` has no `--format`, `--output`, `--continue-on-error` or `--validate-only`, and the new cases pass `--continue-on-error`; that says nothing about the behaviour.
  The ones that fail for the behaviour itself, with only options `main` has, are the single-object case (`:419-425`), the string-literal step in `l4 trace` (`:760-778`) and the line-break case (`:628`).
  The other behaviours were each measured by hand with `main`'s own options, as listed under "What changes against `main`".
- Run against the `l4` built from this branch before the CSV reader and #635 (`150bd6547`), 7 of the 66 fail: the four cases of `describe "the CSV reader"` that change behaviour (a one-column `""` row, a line of spaces, a byte-order mark, a ragged record) and three of #635's four (a choice cell, a `MAYBE` choice cell, a `DATE` cell).
  The synonym case and the CRLF case are pins that pass there, as their comments say.

## Limits and known defects

- A CSV cell in a column that no input declares, or for an input whose type the export does not give, is typed by its content (`inferCsvCell`); the undeclared-column case is pinned by `:488-502`.
- A CSV file cannot carry empty text, or text of only spaces, as a value, because a blank cell is absent (ruled 2026-10-12); to give an input that value, use a JSON or YAML file.
- A CSV file must be UTF-8: a Latin-1 file stops the command with a backtrace and no `Error:` line (`main` too).
- A line of empty cells, such as `,,`, is a case with nothing given: if any input has to be given it is an `error` row, and without `--continue-on-error` the run stops there.
- The message that refuses a record of the wrong length says what the reader would otherwise have done: "a cell missing from a short row would otherwise be read as left out (NOTHING for a `MAYBE` input, a missing field for any other), and a long row's extra cells would be dropped".
  Unstable's message says "would otherwise take its default" instead, because unstable has `TYPICALLY` defaults and `main` has none; the wording is changed here because the unstable sentence would be false on `main`, and the rest of the message ("Line 3 has 2 cells, but the header has 3, so the row is refused") is the same.
  Pinned in `describe "the CSV reader"`.
- `--validate-only` judges NUMBER, BOOLEAN and STRING inputs (and a `MAYBE` of one) only.
  For any other type, such as a DATE, a list, a record, or a type declared through a synonym (`DECLARE Year IS A NUMBER`), whatever is given passes: with an `@export` taking a DATE, the cases `2024-01-15` and `not a date` are both `valid`, and the second fails when run (`Could not parse date string 'not a date'`).
- A module that contains an inert string (a bare quoted string in a boolean expression, such as `a AND "and also" AND TRUE`) cannot be batched: the printed module does not re-parse, and every row has status `error` with the parser's message (loud, exit 1).
  `main` does the same, so this PR neither adds nor fixes it.
- An `@export` whose `MAYBE` input is followed by another input cannot be batched: the generated wrapper has an indentation error, and every row has status `error` (loud, exit 1; `main` too).
  Put the `MAYBE` input last.
- Every row re-parses and re-type-checks the whole printed module in a new one-shot build (read in code; cost not measured).
- Correctness rests on `prettyLayout` reproducing the module's meaning; the printed text is the program that runs.
- Fatal errors go to stdout, not stderr, as one line starting `Error:` (a cases file or rules file that does not exist is the exception: the operating system's message goes to stderr).
- The wrapper adds the top-level names `InputArgs`, `decodeArgs` and `inputJson`; a module that already defines one was not probed.
- The row JSON is put into the wrapper by `escapeAsL4String` (`:832-836`), which escapes only the double quote; a separate change replaces it.

## What changes against `main`

Every item below was measured with the `l4` built from plain `main` (`00298eb60`) and the one built from this PR, on the cases named; the tests that pin them are listed above, and each of them fails on `main`'s `l4` except where the item says otherwise.

**Reading by declared type, which restores what the first commit broke.**
`main`'s own `l4 batch` coerced string values to the declared NUMBER/BOOLEAN types on every input row (`coerceInputTypes`, `f6ebc282e`).
This PR's first commit (#47) replaced that with typing by cell content, which broke two inputs that work on `main`: a JSON or YAML row with `"age": "25"` for a NUMBER input, and a digits-only CSV cell such as `123456` for a STRING input.
The third commit (#625) reads each value by the type its input declares instead (`declareInputs`), which restores both and also covers `MAYBE` inputs and YAML.
That reading still typed a CSV cell for a choice or a `DATE` by how it looked, which broke a third input that works on `main`; #635 (commit 10) keeps those cells as text.
With `batch-declared-text.l4`: the cells `True` and `False` for a choice input answer `"yes"` and `"no"` on `main`, were errors in this PR before #635 (the cell had become the boolean), and answer `"yes"` and `"no"` now.
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
4. **The CSV file is read by `csvRows`.**
   Ruled 2026-10-12: it is taken whole, and a cell of spaces or a quoted `""` is blank.
   Not ruled, decided by Claude overnight 2026-10-02, pending Meng's review: the refusal of a ragged record, and the skipping of a line of spaces in a one-column file.
   A one-column file with the lines `alice`, `""`, `bob` is three cases: `main` dropped the `""` line and wrote two lines, both `success`; this PR writes three, and the `""` case is `Missing required field 'name'` (status `error`).
   A line of only spaces in that file is not a case: `main` read it as the case `{"name":"   "}` and answered `success`; this PR skips it.
   A file that starts with a byte-order mark: `main` named the first column `\ufeffage` and the rule answered `Missing required field 'age'` under status `success`; this PR reads `age`.
   A record with the wrong number of cells is refused, naming its line, in `batch-ragged.csv` (`30,40000` under a three-column header, and a record with a fourth cell): `main` ran the short one with its last input missing (a decode error under `success`) and ran the long one as `success`, dropping the extra cell; this PR makes both `error` rows.
   The refusal and the skipped line of spaces are decided by Claude overnight, not ruled, as the Typing section says.
5. **A `MAYBE` NUMBER or BOOLEAN input given as text is read as what the text spells.**
   `batch-maybe.l4` with `{"premium":"25"}`: `main` returned status `success` with `{"error":"Expected JSON number but got: String \"25\""}` as the result; this PR returns `25`.
   Text that is not a number (`"abc"`) is an error here, naming the text.
   An input declared through a synonym (`DECLARE Year IS A NUMBER`) given the CSV cell `2026` is read as the number 2026; `main` answered `Internal error: …` under status `success` (`batch-declared-text.l4`, `-e "echo year"`).
6. **A cases file that holds one JSON object is one case.**
   `main` stopped with `Error: failed to parse inputs: Error in $: parsing [] failed, expected Array, but encountered Object`.
7. **A CSV cell in a column that no input declares is typed by its content in the echoed `input`**, so `true` is `true` and `123456` is `123456` there.
   `main` echoed every such cell as text.
   `batch-undeclared-column.csv` against `batch-elig.l4`: `main` echoes `"flag":"true"`; this PR `"flag":true`.
   The cell is not used by the rules in either; only the echo differs.
8. **The REPL keeps a line break inside a string literal.**
   `:load` a file with `greeting MEANS "line\nnext"`, then `greeting`: `main` prints `"line` and `  next"` (the second line takes the body's indentation); this PR prints `"line` and `next"`.
   This is the printer fix from #595 (smucclaw/l4-ide#1028), and it is what lets `l4 batch` re-print a module that holds such a string (see Evaluation pipeline above).
9. **A string literal in printed source is spelled as source**, with `\n`, `\t` and `\r` for a line break, tab and carriage return, wherever the system prints an expression or pattern.
   Ruled 2026-10-12: printed string literals stay escaped on every surface, on condition that every such surface is listed in the PR body; the list is the one below, checked against this tree.
   Where a client sees both forms in one answer, the steps are escaped and the values are raw.
   "Probed" means run with the `l4`, `jl4-service` or `jl4-repl` built from `main` and from this PR on a rule that holds `"line\nnext"`; "read in code" means the printer call was read and not run.
   - Escaped, as source:
     - `l4 trace`: the step text on standard error, which is the same text the editor shows for `#EVALTRACE` (probed: `IF (x GREATER THAN 0) THEN "line\nnext" ELSE "tab\there"`; `main` broke the line inside the literal).
     - The REPL's `:traceascii` steps (probed), including a step that is just the literal.
     - `l4 trace` GraphViz node labels (probed): a step is no longer cut at the first line of a literal, which `main` did (`t OF "a`); Graphviz draws the written `\n` as a line break, as it drew the raw one, and shows a tab as `\t`.
       `l4 state-graph` labels (probed) are byte for byte the same on both, because the DOT writer already wrote a line break as `\n`.
     - `jl4-service` `reasoning.exampleCode` (probed, with `?trace=full`).
     - `jl4-service` `/query-plan` (probed): an atom's `label` is rule source, so a literal in it is escaped, and the atom's `atomId` (a UUID over the function name, the label and the input references, `jl4-core/src/L4/Viz/Ladder.hs:476-495`) changes when the label holds a line break, tab or carriage return inside a string literal; the `impactByAtomId` keys move with it. On `check s b MEANS s EQUALS "a\nb" AND b` the atom `s EQUALS "a\nb"` goes from `f4b0a98a-f1a8-5cf0-8abf-c9a3906139b8` on `main` to `7809d60b-0147-5d08-8d8b-3b934e5da3c4`, and the atom `b` keeps `07f78b9c-53af-58ac-947b-022366f8ee04` on both. No atom without such a literal changes its id.
     - `jl4-service` for a function that returns a `DEONTIC` contract (probed): the contract in `explanation` (its `Result:` line prints the rule as source), each obligation's `action`, and the party, operands and deadline of an obligation that has not been evaluated (`Backend/Jl4.hs:1282`, `:1287`, `:1293`, read in code).
     - Error text that prints an expression: type-check diagnostics such as "The expression being matched here is" (probed), and the evaluation error for an infinite loop (`L4/EvaluateLazy/Exceptions.hs:88`, read in code); the division-by-zero and non-integer errors print only the operator (`Print.hs:735-757`) and are unchanged.
     - Editor only (read in code): the ladder diagram's node labels (`jl4-lsp/src/LSP/L4/Viz/Ladder.hs:392`, `:450`) and the outline entry for a directive (`jl4-lsp/app/LSP/L4/Handlers.hs:559`).
   - Raw, as values:
     - The value a trace ends in, the `Result:` block and the REPL's `Result:` line (probed: the line break is a real one).
     - The `explanation` of the service's reasoning tree for an ordinary value (probed).
     - The GraphViz result label, which is also cut at its first line.
     - The text of a value in an evaluation error ("expected a STRING but got …").
   - Not escaped on this branch: an inert string (`"..."` in a boolean expression), because this PR leaves out #595's change to the `Inert` arm (`Print.hs:440`).
   - Not applicable here: `l4 run` prints no trace steps on `main` ("no trace captured"), and the deontic forms for an opening and for `EVERY` are not on `main`.
10. **The `batch` summary in `l4 --help`** says `(json|yaml|csv in, NDJSON streaming out)`, where `main` said `(NDJSON streaming)`.
11. **A malformed CSV file has lost the location in its message.** A stray quote (`"30"x,1,false`) is still a fatal `Error: failed to parse inputs: …`, but the text is `endOfInput`, where `main` said `parse error (Failed reading: satisfy) at "x,1,false\n"`. Unstable has the same message, and a fix for it is planned there.

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
