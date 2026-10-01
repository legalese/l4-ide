# `l4 batch`: one export, many input rows (as built)

As built on `main` by this PR.
Source spec: `specs/todo/BATCH-PROCESSING-SPEC.md`, which `main` already has (on `unstable` the same file is `specs/done/BATCH-PROCESSING-SPEC.md`).
Differences from the source spec: the CLI is `l4 batch FILE --inputs PATH`, not `jl4-cli --batch BATCH_FILE L4FILE`; the default output is NDJSON, not "same format as input"; `--parallel`, `--verbose`, `--simple` and `--trace` are not built; with several exports and no `@export default`, the first export is used instead of reporting an error; CSV dates stay strings; `--validate-only` does not coerce values and does not warn about extra fields; a failing row carries `diagnostics` (or `errors`), not an `error` field, and no aggregated error summary is printed.
The work came from `unstable`; this page describes only what `main` has.
Line numbers are in this PR's tree, on `main` at `00298eb60`.

Source: PR #47 (`tier2/batch-processing`; branch commits `582b956c6`, `291cd0051`; batch merge `eeb432e7d`, landed on unstable through #77).
The `batch` verb existed before #47 (`74efdc5d7`, 2026-04-12), and `main` already had it; #47 completed it: output formats, `--output`, `--continue-on-error`, `--validate-only`, CSV type inference, and runtime exceptions counted as row failures.
Spec history: `BATCH-PROCESSING-SPEC.md` was added as `doc/todo/…` by `18215e82d` (2025-12-12), moved to `specs/todo/` by `09fbfd41f` (#730), and on unstable moved to `specs/done/` by `b4469830a` (PR #85), whose status line names PR #47.
`specs/todo/batch-json-output.md` (moved to `done/` on unstable by `ba95f0cdc`, "#46") specifies the JSON encoding of result values, which predates #47; it is not this PR's spec.
On `main` both files are under `specs/todo/`.

## What it does

`l4 batch FILE --inputs ROWS` type-checks FILE once, picks one `@export` function, and evaluates it once per input row from a JSON, YAML or CSV file (or stdin).
Each row yields a result envelope; by default the envelopes stream out as NDJSON, one line per row, as each row completes.

## Where it lives

- `jl4/app/L4/Cli/Batch.hs` (644 lines); wired as the `batch` command at `jl4/app/Main.hs:72-74` and dispatched at `:121`.
- Options: `BatchOptions` and `batchOptionsParser` (`Batch.hs:88-156`); `OutputFormat` = `FmtNdjson | FmtJson | FmtCsv | FmtYaml` (`:81-86`).
- Driver: `batchCmd` (`:162-228`); row loops `streamRows` (`:248-263`) and `bufferRows` (`:269-283`); per-row `processRow` (`:297-333`).
- Input: `parseBatchInput` (`:418-437`) and `inferCsvCell` (`:455-467`).
- Validation: `validateRow`, `primKind`, `unwrapMaybe` (`:350-397`).
- Output: `writeBuffered`, `encodeJsonArray`, `encodeCsv`, `orderedEnvCols`, `flattenEnvelope` (`:473-534`).
- Wrapper generation: `generateBatchWrapper` and helpers (`:550-625`); entrypoint choice `findExportFunction` (`:631-644`).

## Behaviour and rules

Options: `--inputs/-i PATH` (`-` = stdin), `--input-format json|yaml|csv` (else inferred from `.json`, `.yaml`, `.yml`, `.csv`), `--entrypoint/-e NAME`, `--format/--output-format/-f ndjson|jsonl|json|csv|yaml|yml` (default `ndjson`), `--output/-o FILE`, `--continue-on-error/-c`, `--validate-only`, and the shared `--fixed-now`.
Input: a JSON or YAML array gives one row per element, and any other single value is one row; CSV needs a header row (`Csv.decodeByName`).
CSV cells (`inferCsvCell`): after stripping whitespace, an empty cell becomes `null`; `true`/`false` in any case become booleans; a cell containing `e` or `E` stays a string; otherwise aeson's JSON number grammar decides, so `42` and `3.5` become numbers while `007`, `1,000` and `+5` stay strings.
Entrypoint: `--entrypoint` names the export exactly; else the `@export default` function; else the first export; else the error `no @export functions found in module`.
Parameters: the export's GIVENs become call arguments.
Evaluation pipeline, read in code: the checked module goes through `filterIdeDirectives` (dropping every `#EVAL`/`#ASSERT`) and is re-emitted as source by `prettyLayout` (`:205-206`).
Per row, a generated wrapper is appended to that text: `DECLARE InputArgs HAS …`, a `decodeArgs` function using `JSONDECODE`, `DECIDE inputJson IS "<row JSON>"`, and one `#EVAL` of `CONSIDER decodeArgs inputJson` applying the export.
The combined text is registered as the virtual file `<FILE>.batch<N>.l4`, next to FILE, and evaluated with `Rules.EvaluateLazy` in a fresh one-shot build (`:308-314`).
Envelope (evaluate mode): `{input, output, status, diagnostics}`; `output` is the array of directive results, e.g. `[{"result":20,"trace":null}]`.
The status is `error` if the wrapper failed to check (then `output` is `null`) or any directive raised an evaluation exception, else `success` (`:315-326`).
Envelope (`--validate-only`, no evaluation): `{input, status: valid|invalid, errors}`.
Validation checks that each required (non-`MAYBE`) parameter is present and non-null, and that NUMBER, BOOLEAN and STRING values (after unwrapping `MAYBE`) have the right JSON kind; compound types are not judged.
Failure and exit: a row with status `error` or `invalid` is a failure; without `-c` the run stops after emitting that row; with `-c` every row is processed; the exit code is 1 if any row failed, else 0.
Output: NDJSON is written and flushed row by row without keeping the list of envelopes; `json` is an array with one compact envelope per line; `yaml` is a YAML sequence; `csv` has sorted `input_<field>` columns, then `output`, `status`, `errors`, `diagnostics` where present, with compound cells encoded as compact JSON.

## Diagnostics

Fatal errors, printed to stdout before any row: `Error: --input-format is required when the extension can't be inferred (e.g. reading from stdin)`, `Error: failed to parse inputs: <parser message>`, `Error: type checking failed` (after the check diagnostics), `Error: no @export function named '<n>' found`, `Error: no @export functions found in module`.
An unknown `--format` is rejected by the option parser: `Invalid output format: <x> (expected ndjson|json|csv|yaml)`; an unknown `--input-format` surfaces as `Error: failed to parse inputs: Unsupported format: <x>`.
Validation messages (`:356-370`): `Missing required field: '<p>'`, `Field '<p>' is null but required`, `Type mismatch for field '<p>': expected <KIND>, got <KIND>`, each followed by ` (<@desc text>)` when the parameter has one; and `Input record is not a JSON object: <kind>`.

## Tests and fixtures that pin it

- From #47: `jl4/tests-cli/Main.hs:345-434` (NDJSON default, CSV inference, `--format json`, `--format csv`, `--output`, stop-on-error, `--continue-on-error`, `--validate-only`, exponent cells kept as strings, `MAYBE` validation).
- Their fixtures: `jl4/tests-cli/fixtures/batch-elig.l4`, `batch-data.json`, `batch-data.csv`, `batch-mixed.json`, `batch-code.l4`, `batch-exponent.csv`, `batch-maybe.l4`, `batch-maybe-bad.json`.
- Other `l4 batch` tests on `main` are not part of this change: the printer-bracket and grouping cases `describe "l4 batch keeps the grouping the rule wrote"` and `describe "l4 batch agrees with l4 run"` (`jl4/tests-cli/Main.hs:522` and `:541`).

## Limits and known defects

- Measured: typing is by cell content, so a digits-only CSV cell without a leading zero (`123456`; aeson rejects leading zeros, so `018956` stays text) sent to a STRING parameter arrives as a JSON number, and `JSONDECODE` raises `Expected JSON string but got: Number 123456.0` (`jl4-core/src/L4/EvaluateLazy/Machine.hs:1416`), so the row has status `error`.
  `main` before this change answered the same rows with status `success` and the text `"123456"`.
- Every row re-parses and re-type-checks the whole printed module in a new one-shot build (read in code; cost not measured).
- Correctness rests on `prettyLayout` reproducing the module's meaning; the printed text is the program that runs.
- Fatal errors go to stdout, not stderr.
- The wrapper adds the top-level names `InputArgs`, `decodeArgs` and `inputJson`; a module that already defines one was not probed.
- The row JSON is put into the wrapper by `escapeAsL4String` (`:598-602`), which escapes only the double quote; a separate change replaces it.

## What changes against `main`

`main`'s own `l4 batch` coerced string values to the declared NUMBER/BOOLEAN types on every input row (`coerceInputTypes`, `f6ebc282e`).
This PR's `Batch.hs` has no such step, so a JSON or YAML row with `"age": "25"` for a NUMBER input now fails, and `main` processed every row where this change stops at the first failing one.
Measured with the `l4` built from plain `main` and the one built from this PR, on `batch-elig.l4` with the row `{"age":"25","income":"50000","hasViolations":"false"}`: `main` answers `true` with status `success`; this PR answers status `error` with `Expected JSON number but got: String "25"`.
`main`'s backtick-quoting of natural-language export and parameter names (`quoteIdent`, `:618-625`, also from `f6ebc282e`) is kept.
`doc/tutorials/getting-started/l4-cli.md` (the paragraph under `l4 batch`) is rewritten to describe content-based typing, `--format` and `--output`, stop-at-first-failure with `--continue-on-error`, and `--validate-only`.

## Later changes on unstable that `main` does not have

- #51: the row JSON is quoted with the lexer's `showStringLit` instead of the hand-rolled escape.
- #214: `prettyLayout` made to re-emit parseable, re-checkable source, and a `batch` help text that says input is json|yaml|csv.
- #328: read ASSUMEs are bound by name via `rewriteModuleAssumes`, not passed as positional arguments.
- #330: an `#ASSERT` that raises counts as a row exception.
- #334: the `refused` status, which neither fails nor stops the batch.
- #440: `restoreMixfixPatterns` runs before printing, so operators sharing a head keyword survive the re-print.
