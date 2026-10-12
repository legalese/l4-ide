# `l4 batch`: one export, many input rows (as built)

As built on `main` by this PR.
Source spec: `specs/todo/BATCH-PROCESSING-SPEC.md`, which `main` already has (on `unstable` the same file is `specs/done/BATCH-PROCESSING-SPEC.md`).
Differences from the source spec: the CLI is `l4 batch FILE --inputs PATH`, not `jl4-cli --batch BATCH_FILE L4FILE`; the default output is NDJSON, not "same format as input"; `--parallel`, `--verbose`, `--simple` and `--trace` are not built; with several exports and no `@export default`, the first export is used instead of reporting an error; CSV dates stay strings; `--validate-only` reads each value by the declared type, as evaluation does, and does not warn about extra fields; a failing row carries `diagnostics` (or `errors`), not an `error` field, and no aggregated error summary is printed.
The work came from `unstable`; this page describes only what `main` has.
Line numbers are in this PR's tree, on `main` at `00298eb60`.

Source: PR #47 (`tier2/batch-processing`; branch commits `582b956c6`, `291cd0051`; batch merge `eeb432e7d`, landed on unstable through #77), and, for the third commit of this PR, #625 (`0af1211a7` on unstable), which makes `l4 batch` read each value by the type its input declares.
The `batch` verb existed before #47 (`74efdc5d7`, 2026-04-12), and `main` already had it; #47 completed it: output formats, `--output`, `--continue-on-error`, `--validate-only`, CSV type inference, and runtime exceptions counted as row failures.
Spec history: `BATCH-PROCESSING-SPEC.md` was added as `doc/todo/…` by `18215e82d` (2025-12-12), moved to `specs/todo/` by `09fbfd41f` (#730), and on unstable moved to `specs/done/` by `b4469830a` (PR #85), whose status line names PR #47.
`specs/todo/batch-json-output.md` (moved to `done/` on unstable by `ba95f0cdc`, "#46") specifies the JSON encoding of result values, which predates #47; it is not this PR's spec.
On `main` both files are under `specs/todo/`.

## What it does

`l4 batch FILE --inputs ROWS` type-checks FILE once, picks one `@export` function, and evaluates it once per input row from a JSON, YAML or CSV file (or stdin).
Each row yields a result envelope; by default the envelopes stream out as NDJSON, one line per row, as each row completes.

## Where it lives

- `jl4/app/L4/Cli/Batch.hs` (703 lines); wired as the `batch` command at `jl4/app/Main.hs:72-74` and dispatched at `:121`.
- Options: `BatchOptions` and `batchOptionsParser` (`Batch.hs:89-157`); `OutputFormat` = `FmtNdjson | FmtJson | FmtCsv | FmtYaml` (`:82-87`).
- Driver: `batchCmd` (`:163-229`); row loops `streamRows` (`:249-264`) and `bufferRows` (`:270-284`); per-row `processRow` (`:298-338`).
- Input: `BatchRow` and `RowSource` (`:423-433`), `parseBatchInput` (`:435-460`), `declareInputs` with `jsonNumber` and `jsonBool` (`:462-501`), and `inferCsvCell` (`:503-526`).
- Validation: `validateRow`, `primKind`, `unwrapMaybe` (`:355-402`).
- Output: `writeBuffered`, `encodeJsonArray`, `encodeCsv`, `orderedEnvCols`, `flattenEnvelope` (`:532-593`).
- Wrapper generation: `generateBatchWrapper` and helpers (`:609-684`); entrypoint choice `findExportFunction` (`:690-703`).

## Behaviour and rules

Options: `--inputs/-i PATH` (`-` = stdin), `--input-format json|yaml|csv` (else inferred from `.json`, `.yaml`, `.yml`, `.csv`), `--entrypoint/-e NAME`, `--format/--output-format/-f ndjson|jsonl|json|csv|yaml|yml` (default `ndjson`), `--output/-o FILE`, `--continue-on-error/-c`, `--validate-only`, and the shared `--fixed-now`.
Input: a JSON or YAML array gives one row per element, and any other single value is one row; CSV needs a header row (`Csv.decodeByName`).
Typing (`declareInputs`, `:462-488`): a CSV cell is read as text, an empty one as `null`, and every case is then typed against the export's inputs, whichever file it came from.
A NUMBER or BOOLEAN input (a `MAYBE` one too) given as text is read as the number or boolean the text spells, with aeson's JSON number grammar and `true`/`false` in any case, so `"25"` in a JSON file and a `25` cell in a CSV file both arrive as the number 25; text that does not spell one is left alone, so the decode error names that value.
A STRING input keeps a CSV cell as the text written, so `123456`, `018956`, `1.50` and `1e3` arrive as the codes they are; a JSON or YAML number sent for a STRING input stays an error, because those files already say which values are strings.
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

Fatal errors, printed to stdout before any row: `Error: --input-format is required when the extension can't be inferred (e.g. reading from stdin)`, `Error: failed to parse inputs: <parser message>`, `Error: type checking failed` (after the check diagnostics), `Error: no @export function named '<n>' found`, `Error: no @export functions found in module`.
An unknown `--format` is rejected by the option parser: `Invalid output format: <x> (expected ndjson|json|csv|yaml)`; an unknown `--input-format` surfaces as `Error: failed to parse inputs: Unsupported format: <x>`.
Validation messages (`:361-375`): `Missing required field: '<p>'`, `Field '<p>' is null but required`, `Type mismatch for field '<p>': expected <KIND>, got <KIND>`, each followed by ` (<@desc text>)` when the parameter has one; and `Input record is not a JSON object: <kind>`.

## Tests and fixtures that pin it

- From #47: `jl4/tests-cli/Main.hs:360-522` (NDJSON default, CSV inference, `--format json`, `--format csv`, `--output`, stop-on-error, `--continue-on-error`, `--validate-only`, exponent cells kept as strings, `MAYBE` validation); the case at `:439-448`, a line break and a tab inside a string literal, is #595's, and the nested `describe "reads a value by the type its input declares"` at `:462-522` is #625's.
- From #625 (`:462-522`): text for a NUMBER or BOOLEAN input is read as a number or boolean in JSON and in YAML and passes `--validate-only`; a CSV cell for a STRING input keeps the text written (`123456`, `018956`, `1.50`, `1e3`); a JSON number for a STRING input is still an error; text that is not a number is left alone, so the error names it.
- From #595: `jl4-core/test/PrintRoundtripSpec.hs:27` (a string with a line break and a tab prints with its escapes and re-parses) and the fixtures `jl4/tests-cli/fixtures/batch-string-line-break.l4` and `.json`.
- Fixtures (#47): `jl4/tests-cli/fixtures/batch-elig.l4`, `batch-data.json`, `batch-data.csv`, `batch-mixed.json`, `batch-code.l4`, `batch-exponent.csv`, `batch-maybe.l4`, `batch-maybe-bad.json`.
- Fixtures (#625): `jl4/tests-cli/fixtures/batch-declared-strings.json`, `batch-declared-strings.yaml`, `batch-declared-string-cells.csv`, `batch-declared-bad-number.json`, `batch-declared-number-for-string.json`.
- Other `l4 batch` tests on `main` are not part of this change: the printer-bracket and grouping cases `describe "l4 batch keeps the grouping the rule wrote"` and `describe "l4 batch agrees with l4 run"` (`jl4/tests-cli/Main.hs:610` and `:629`).

## Limits and known defects

- A CSV cell for an input whose type is not NUMBER, BOOLEAN or STRING, or which the export does not declare, is typed by its content (`inferCsvCell`); read in code, not probed.
- Every row re-parses and re-type-checks the whole printed module in a new one-shot build (read in code; cost not measured).
- Correctness rests on `prettyLayout` reproducing the module's meaning; the printed text is the program that runs.
- Fatal errors go to stdout, not stderr.
- The wrapper adds the top-level names `InputArgs`, `decodeArgs` and `inputJson`; a module that already defines one was not probed.
- The row JSON is put into the wrapper by `escapeAsL4String` (`:657-661`), which escapes only the double quote; a separate change replaces it.

## What changes against `main`

`main`'s own `l4 batch` coerced string values to the declared NUMBER/BOOLEAN types on every input row (`coerceInputTypes`, `f6ebc282e`).
This PR's first commit (#47) replaced that with typing by cell content, which broke two inputs that work on `main`: a JSON or YAML row with `"age": "25"` for a NUMBER input, and a digits-only CSV cell such as `123456` for a STRING input.
The third commit (#625) reads each value by the type its input declares instead (`declareInputs`), which restores both and also covers `MAYBE` inputs and YAML.
Measured with the `l4` built from plain `main` and the one built from this PR: `batch-elig.l4` with the row `{"age":"25","income":"50000","hasViolations":"false"}` answers `true` with status `success` in both, and `batch-code.l4` with the CSV cells `123456` and `018956` answers the text `"123456"` and `"018956"` with status `success` in both.
What still differs from `main` is that the run stops at the first failing row unless `--continue-on-error` is given, where `main` processed every row.
`main`'s backtick-quoting of natural-language export and parameter names (`quoteIdent`, `:677-684`, also from `f6ebc282e`) is kept.
`doc/tutorials/getting-started/l4-cli.md` (the paragraph under `l4 batch`) is rewritten to describe reading by declared type, `--format` and `--output`, stop-at-first-failure with `--continue-on-error`, and `--validate-only`.

## Later changes on unstable that `main` does not have

- #51: the row JSON is quoted with the lexer's `showStringLit` instead of the hand-rolled escape.
- #214: `prettyLayout` made to re-emit parseable, re-checkable source, and a `batch` help text that says input is json|yaml|csv.
- #595: its change to the `Inert` arm of the printer is not here; `main` prints an inert string as `"..." <+> dquotes (pretty txt)` (`Print.hs:440-441`), which needs its own change first.
- #328: read ASSUMEs are bound by name via `rewriteModuleAssumes`, not passed as positional arguments.
- #330: an `#ASSERT` that raises counts as a row exception.
- #334: the `refused` status, which neither fails nor stops the batch.
- #440: `restoreMixfixPatterns` runs before printing, so operators sharing a head keyword survive the re-print.
