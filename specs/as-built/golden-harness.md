# Golden harness repairs (as built)

As built on unstable at 73a953821. Source spec: none. Differences from the source spec: not applicable.

This PR carries three units: #67 (inside batch #77, commit `1dde8d8aa9`), #82 (`754c44db05`) and #419 (`b793264749`).
`specs/todo/CANON-REGRESSION-CORPUS-SPEC.md` (on unstable; not on main or in this PR) covers only #398 (the canon glob), which is a separate change on unstable and is described there.
`specs/todo/MULTILINGUAL-NLG-SPEC.md` §2.6 (on unstable, `:263`; not on main or in this PR) records the defect #419 fixes (smucclaw/l4-ide#962) as a precondition for Hebrew goldens; it is not this PR's spec.

## What it does

These are repairs to the golden test suite `jl4-test` and to how the type-check rule sorts diagnostics.
What L4 accepts and computes does not change, but where a warning is reported does (see "Relation to main").

- The suite resolves libraries on its own under a bare `cabal test`.
- Three top-level `not-ok/export-*.l4` fixtures that no glob matched are now run.
- A glob that matches no files fails the suite instead of passing vacuously.
- `empty.l4`, whose only diagnostics are warnings, already type-checks on main (see "Relation to main"); it moves from `not-ok/`, where no glob ran it, to `ok/`.
- `.schema.golden` files store each non-ASCII character once, not double-encoded.

## Where it lives

- Library path: `jl4/tests/Main.hs:65-74 @ 73a953821` (#67).
- Export-placement glob and its block: `Main.hs:97-102` and `:164-165` @ 73a953821 (#67; the comment at `:100-101` is #82's).
- Corpus guard: `Main.hs:116-128` @ 73a953821 (#67, with later rows).
- Success rule: `jl4-lsp/src/LSP/L4/Rules.hs:886-890, 898 @ 73a953821`, field notes at `:132-133` (#82).
- Schema golden encoding: `jl4JsonSchemaGolden`, `Main.hs:483-523` @ 73a953821, fix at `:499-513`, import at `:9` (#419).
- `jl4/jl4.cabal:146 @ 73a953821` lists `text` in `jl4-test`'s build-depends, which `Data.Text.Encoding` needs; that line came from #399, not from #419.

## Behaviour and rules (read in code on unstable)

Library path: if `JL4_LIBRARY_PATH` is unset when the suite starts, it is set to `<jl4-core data dir>/libraries`; an explicit setting is kept.
Export placement: the glob `not-ok/export-*.l4` runs with the same flags as the ok corpus (parse, check, exact-print, NLG, schema).
Its three files put `@export` after `GIVETH`, between `GIVEN` and `GIVETH`, and just before `DECIDE`; each `.schema.golden` pins `No @export annotations found in file`, i.e. an `@export` in those positions yields no default export.
Corpus guard: one `it` per glob asserts that the glob matched at least one file.
#67 created it with nine rows; #82 removed `not-ok-root-tc`; with this change it has eight rows (ok, libraries, legal, tc-fails, nlg-fails, semantic-tokens, hover, export-placement), and on unstable eleven (those plus canon, import-refusal, import-unresolved).
Success rule: the type-check rule partitions diagnostics as `partition ((/= TypeCheck.SError) . TypeCheck.severity)`.
`infos` holds `SInfo` and `SWarn`, `errors` holds `SError` only, and `success = null errors`.
Every diagnostic is still published to the editor; the partition only decides what blocks `SuccessfulTypeCheck`.
Schema encoding: the JSON from `AP.encodePretty` is UTF-8 bytes, and is now decoded with `TE.decodeUtf8` before `writeFile`.
Before #419, `BL.unpack` mapped each byte to a `Char` and `writeFile` re-encoded each one, so `ä` (`c3 a4`) was stored as `c3 83 c2 a4`.
It round-tripped through `readFile`, so golden and actual agreed and the suite stayed green on mojibake; the `.ep.golden` beside it, written from `Text`, was the control that exposed it.

## Tests and fixtures that pin it

- `jl4/examples/not-ok/export-{after-giveth,before-decide,between-given-giveth}.l4`, four goldens each in `jl4/examples/not-ok/tests/` (#67).
- `jl4/examples/ok/empty.l4` and `jl4/examples/ok/tests/empty.{golden,ep.golden,nlg.golden,schema.golden}` (#82): the golden reads "Typechecking successful" followed by its exhaustiveness and redundancy warnings.
  It records main's checker, which for `xx` lists six missing cases and omits two (`faz bar qux`, `faz baz qux`); unstable's golden covers all eight with four patterns, through #182's checker, so the two goldens differ in content as well as layout.
- Measured on unstable: 14 `.schema.golden` files contain non-ASCII bytes; 13 are in the canon mirror, and the other is `jl4/examples/ok/closing-the-loop/tests/fristberechnung.schema.golden`, which #419 re-blessed.
- #419 also re-blessed `legal/regcf/denovo/tests/regcf-denovo.schema.golden`, which #489 later removed from `legal/`; on unstable its copy is at `jl4/examples/canon/us/regcf/cleanroom/tests/`.
- No test pins the library-path default or the corpus guard itself beyond the suite running.

## Relation to main

Main already treats warnings as non-fatal, with a different line: `success = all ((/= TypeCheck.SError) . TypeCheck.severity) errors` (`jl4-lsp/src/LSP/L4/Rules.hs:568` at main `66c30f987`, from `7531f1d9a`).
The two agree on `success`; they differ in `TypeCheckResult.errors`, which on main still holds `SWarn` diagnostics and on unstable does not.
Moving `SWarn` out of `errors` puts warnings into `TypeCheckResult.infos`, and every reader of `infos` now sees them (read in code on unstable and in this PR):

- the golden harness prints them after "Typechecking successful" (`jl4/tests/Main.hs`, `checkFile`), as `ok/tests/empty.golden` shows;
- the language server's directive-results notification turns every `infos` entry with a range into an item with `success = Just True` (`jl4-lsp/app/LSP/L4/Handlers.hs:199-209 @ 73a953821`), so warnings are listed beside `#CHECK` results;
- the `#CHECK` result lookup reads `infos` (`jl4-lsp/app/LSP/L4/Handlers.hs:797` with this change), so a warning that starts exactly at a `#CHECK` can be returned as its result.

The REPL's "Type error" branch also prints `infos`, but it is unreachable: it sits behind `SuccessfulTypeCheck`, which yields nothing when a check fails (`jl4-repl/app/Main.hs`).

At main, `empty.l4` is still at `not-ok/empty.l4`, and `jl4/tests/Main.hs` has none of the three repairs.

## Limits (verified)

The guard proves only that each glob is non-empty; it does not find `.l4` files that are in no glob.
The schema golden's `readFromFile` is still `readFile` (`jl4/tests/Main.hs:217` with this change); correct now that the written text is decoded characters.

## Later changes

- #369: the path scrubber (`mkPathScrubber`) and the `import-refusal` glob; #451: the `import-unresolved` glob.
- #398: the `canon/**` glob, its guard row, and the shared `goldenCorpus` list (a separate change on unstable).
