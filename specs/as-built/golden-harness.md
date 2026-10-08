# Golden harness repairs (as built)

As built on `main` by legalese/l4-ide#544.
Source spec: none.
The repairs came from `unstable`: #67 (inside batch #77, commit `1dde8d8aa9`), #82 (`754c44db05`), #419 (`b793264749`) and the directive-results filter of #567 (`57011bed2`); this page describes only what `main` has.
Line numbers are in this PR's tree, merged with `main` at `71ebf5ca1`.

## What it does

These are repairs to the golden test suite `jl4-test` and to how the type-check rule sorts diagnostics.
What L4 accepts and computes does not change.

- The suite resolves libraries on its own under a bare `cabal test`.
- Three top-level `not-ok/export-*.l4` fixtures that no glob matched are now run.
- A glob that matches no files fails the suite instead of passing vacuously.
- `empty.l4`, whose only diagnostics are warnings, moves from `not-ok/`, where no glob ran it, to `ok/`; it type-checks, and did before this change too.
- Warnings now sort with the non-blocking diagnostics, so the golden harness prints them after "Typechecking successful" (see "Warnings, and who reads them").
- `.schema.golden` files store each non-ASCII character once, not double-encoded.

## Where it lives

- Library path: `jl4/tests/Main.hs:51-60` (#67).
- Export-placement glob: `Main.hs:76-81`, and its block at `:96-97` (#67; the comment at `:79-80` is #82's).
- Corpus guard: `Main.hs:83-92` (#67, with the export-placement row).
- Sorting diagnostics: the partition at `jl4-lsp/src/LSP/L4/Rules.hs:546` and `success` at `:558`, with the field notes at `:128-129` (#82).
- Schema golden encoding: `jl4JsonSchemaGolden`, `Main.hs:181-221`, the fix at `:197-211`, its import at `:8` (#419).
- `jl4/jl4.cabal:101` adds `text` to `jl4-test`'s build-depends, which `Data.Text.Encoding` needs; on `unstable` that line came from #399.
- Directive-results filter: `checkDirectiveResults`, `jl4-core/src/L4/TypeCheck/Types.hs:184-194` (#567).
  It is called at `jl4-lsp/app/LSP/L4/Handlers.hs:209` (the directive-results notification) and `:797` (the `#CHECK` result lookup).

## Behaviour and rules (read in code)

Library path: if `JL4_LIBRARY_PATH` is unset when the suite starts, it is set to `<jl4-core data dir>/libraries`; an explicit setting is kept.
Export placement: the glob `not-ok/export-*.l4` runs with the same flags as the ok corpus (parse, check, exact-print, NLG, schema).
Its three files put `@export` after `GIVETH`, between `GIVEN` and `GIVETH`, and just before `DECIDE`; each `.schema.golden` pins `No @export annotations found in file`, i.e. an `@export` in those positions yields no default export.
Corpus guard: one `it` per glob asserts that the glob matched at least one file.
It has eight rows: ok, libraries, legal, tc-fails, nlg-fails, semantic-tokens, hover and export-placement.
Sorting diagnostics: the type-check rule partitions diagnostics as `partition ((/= TypeCheck.SError) . TypeCheck.severity)`.
`infos` holds `SInfo` and `SWarn`, and `errors` holds `SError` only.
`success = all ((/= TypeCheck.SError) . TypeCheck.severity) errors` is unchanged, and with `errors` holding `SError` only it is true exactly when `errors` is empty.
Every diagnostic is still published to the editor; the partition decides which go to `infos` and which to `errors`, as the note at `Rules.hs:542-545` says.
`SuccessfulTypeCheck` reads `success` (`Rules.hs:595-599`).
Schema encoding: the JSON from `AP.encodePretty` is UTF-8 bytes, and is now decoded with `TE.decodeUtf8` before `writeFile`.
Before #419, `BL.unpack` mapped each byte to a `Char` and `writeFile` re-encoded each one, so `ä` (`c3 a4`) was stored as `c3 83 c2 a4`.
It round-tripped through `readFile`, so golden and actual agreed and the suite stayed green on mojibake.

## Warnings, and who reads them

Before this change, `main` partitioned with `partition ((== TypeCheck.SInfo) . TypeCheck.severity)` (`Rules.hs:542` at `71ebf5ca1`), so `SWarn` diagnostics stayed in `errors` and `infos` held `SInfo` entries only.
`success` was the same expression then, so whether a module checks does not change.
`CheckInfo` is the only diagnostic with severity `SInfo` (`severity`, `jl4-core/src/L4/TypeCheck.hs:3060-3065`).
Of the readers of `infos`, only the golden harness shows the warnings:

- the golden harness prints them after "Typechecking successful" (`jl4/tests/Main.hs`, `checkFile`), as `ok/tests/empty.golden` shows;
- the language server's directive-results notification reads `infos` through `checkDirectiveResults`, which keeps `CheckInfo` entries only (`Handlers.hs:209`), so it lists `#CHECK` results and no warnings;
- the `#CHECK` result lookup reads `infos` through the same filter (`Handlers.hs:797`), so it can return only a `#CHECK` answer.

So the language server sends the same directive results as before, when both sites read `infos` unfiltered and `infos` held `CheckInfo` entries only.

The REPL's "Type error" branches also print `infos` (`jl4-repl/app/Main.hs:610`, `:691`, `:740` and `:968`), but they are unreachable: they sit behind `SuccessfulTypeCheck`, which yields nothing when a check fails.
The REPL's type lookup (`getExpressionType`, `jl4-repl/app/Main.hs:927`) takes `CheckInfo` entries only (`:963`).

## Tests and fixtures that pin it

- `jl4/examples/not-ok/export-{after-giveth,before-decide,between-given-giveth}.l4`, four goldens each in `jl4/examples/not-ok/tests/` (#67).
- `jl4/examples/ok/empty.l4` and `jl4/examples/ok/tests/empty.{golden,ep.golden,nlg.golden,schema.golden}` (#82): the golden reads "Typechecking successful" followed by its exhaustiveness and redundancy warnings.
  It records `main`'s checker, which for `xx` lists six missing cases and omits two (`faz bar qux`, `faz baz qux`).
- `jl4/examples/ok/export-non-ascii.l4` and its four goldens in `jl4/examples/ok/tests/` pin #419's fix.
  Its exported function's description and input name are not ASCII; none of the other 221 `.schema.golden` files in this tree holds a non-ASCII byte, so no existing golden changes.
  With the fix's output reverted to `BL.unpack`, its `json schema` test fails on the double-encoded text (`GebÃ¼hr` for `Gebühr`) and the other 221 still pass (measured with `-m "json schema"`: 222 examples, 1 failure).
- `jl4-core/test/CheckDirectiveResultsSpec.hs`, in `jl4-core-test`, pins the directive-results filter.
  On a module with one `#CHECK` and three `CONSIDER`s that each miss a case, the diagnostics that do not block a check are one `CheckInfo` and three `CheckWarning`s, and `checkDirectiveResults` keeps only the `CheckInfo`, on line 20.
- No test pins the library-path default or the corpus guard itself beyond the suite running.

## Limits (verified)

The guard proves only that each glob is non-empty; it does not find `.l4` files that are in no glob.
Eight such files remain under `jl4/examples/`: `advanced/legislative-ingestion.l4`, `advanced/llm-judgment-calls.l4`, the five files under `experiments/excel-date/`, and `implicit-assume-test.l4`.
Nothing pins the two call sites of `checkDirectiveResults`: `jl4-lsp` has no test suite on `main`, and `Handlers.hs` is in its executable (`jl4-lsp/jl4-lsp.cabal:110`, `hs-source-dirs: app` at `:119`).
The schema golden's `readFromFile` is still `readFile` (`jl4/tests/Main.hs:217`); correct now that the written text is decoded characters.
