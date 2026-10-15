# Printer: one arm per line for CONSIDER (as built)

As built by legalese/l4-ide#676, which was open when this page was written: it describes `main` only once that PR merges.
Source spec: none.
The CONSIDER case and `vcatHard` come from `unstable`'s `07a95495b` (smucclaw/l4-ide#932); the `nest 2` on each arm is this PR's own, and is not on `unstable` (see Limits).
This page describes only what the PR carries; the rest of `07a95495b` stays on `unstable`.

Scope: the `Consider` case of `printWithLayout` in `jl4-core/src/L4/Print.hs`, and the `vcatHard` helper beside `prettyConj`.
Nothing else in `prettyLayout` changes.
Its sibling page is `printer-bracket.md`, which owns the bracketing of `AND`/`OR` operands.

## What it does

`prettyLayout` turns a checked module back into L4 source.
`l4 batch` and the REPL re-emit a module through it and then parse and run the printed text, so a printer whose output reads differently from its input changes answers, sometimes with no diagnostic.
Before this change a CONSIDER's arms were printed comma-separated on one hanging indent (`CONSIDER c WHEN Red THEN 1,` with the arms after it under the first).
`L4.Parser.consider` reads the arm list by column, and a comma at the end of a line is eaten by whatever comma list the arm ended in, so three things went wrong:
- A CONSIDER inside an arm of another one swallowed the outer's later arms as its own.
  On another type that is a type error on every row; on the same type it type-checks and answers wrongly, in both directions, with `"status":"success"`.
- An arm that ends in a comma list (`WHEN Red THEN LIST 1, 2`) had its separating comma read as the next element of the list.
- A `WHERE` under an arm of a CONSIDER with an arm after it did not parse (see below).

Now each arm is on its own line with no comma, and each arm is nested two columns past the column the arms start at.

## Where it lives

- `jl4-core/src/L4/Print.hs:521-540`: the note and the `Consider` case, `hang 2 $ vcatHard $ ("CONSIDER" <+> printWithLayout expr) : fmap (nest 2 . printWithLayout) branches`.
- `jl4-core/src/L4/Print.hs:1014-1023`: `vcatHard` and its note, a `vcat` whose separators are `hardline`s.
- Consumers: the ones listed in `printer-bracket.md`, and every place that prints an expression as text (trace text, `reasoning.exampleCode`, residual obligations in `#EVAL` output, ladder and query-plan `atomId` on `main`).

## Behaviour and rules (read in code, measured where said)

- `vcat` and `vsep` separators are `FlatAlt Line _`, so inside a `group` they collapse and jam the arms together; `layoutPretty` with `Unbounded` always resolves a `group` in favour of the flat branch.
  `vcatHard` separates with `hardline`, which `group` cannot flatten.
- `hang 2` is `align . nest 2`, so the arms sit two columns past the `CONSIDER` keyword's column, one per line.
- `nest 2 . printWithLayout` on an arm moves every line of the arm after its first by two more columns, and does not move the first line.
  It matters when an arm's text breaks lines at the current nesting.
- The case that needs it is a `WHERE` under an arm: the `Where` printer (`Print.hs:546-551`) is `vcat [indent 2 e, "WHERE", indent 2 decls]`, so its `WHERE` is placed at the current nesting.
  Unnested, that is the column of the arm's `WHEN`, which ends the definition, and the next arm is a parse error.
  Measured on the printed text (`l4 batch -c`, the three fixtures below): with the arms unnested, a `WHERE` under the first or a middle arm fails with "unexpected WHEN" on every row; with `nest 2` all three give the answers `l4 run` gives.
- A `WHERE` under the last arm has no arm after it, so it parsed either way, and the fixture for it is a control that passes before and after.
- A CONSIDER inside an arm is itself a `hang 2`, so its arms sit at its own column and the outer's next `WHEN`, at the outer's, is not one of them.

## Diagnostics

None; this is a printer change.

## Tests and fixtures that pin it

- `jl4/tests-cli/Main.hs`, "a CONSIDER whose arms are printed back": 15 examples, each comparing what `l4 batch -c` and the REPL give with what `l4 run` gives on the fixture's own `#EVAL`s.
  `batchAnswers` passes `-c` (`--continue-on-error`): since #643 a row that raises is `"status":"error"` and stops the batch unless `-c` says to go on, so without it a file with a raising row yields fewer rows than it has.
  `replAnswers` runs the REPL in a directory of its own made by `withSystemTempDirectory`, because the REPL keeps a history file in the directory it runs in.
- Fixtures in `jl4/tests-cli/fixtures/`: `batch-nested-consider-types.l4` and `batch-nested-consider-silent.l4` (a CONSIDER in an arm, on another type and on the same type), `batch-nested-consider-last.json` (the rows for the `inner last` export of the second, where the inner CONSIDER is the last arm), `batch-consider-list-arms.l4` (an arm ending in a comma list), and `batch-consider-where-{first,middle,last}.l4` (a `WHERE` under that arm).
- Measured with one test binary and `L4_BIN` and `L4_REPL_BIN` set from each build: against `main`'s `l4` and `jl4-repl`, 8 of 15 fail (the six `l4 batch` and REPL cases for the nested and comma-list files, and the `WHERE` under the middle arm through both); against the PR before this change (`f8899a60d` merged with `main` at `53337e2d3`), 4 fail (the `WHERE` under the first and the middle arm, each through `l4 batch` and the REPL); against this change, none.
  The `l4 run` examples and the last-arm controls pass on every build, as they should.
- Five trace and `#EVAL` goldens move with the new layout and are re-blessed, each diff read: `ok/lazytrace`, `ok/lazytrace2`, `ok/lazytrace-exception`, `legal/directive-showcase` and `legal/ny-environmental-7.3`.
  `nest 2` moved none of them a second time.

## Limits

- An arm whose constructor pattern has several arguments still wraps at the argument, as `main` does (`jl4/examples/ok/tests/lazytrace2.golden:31-32`: `WHEN MkPair p1` and then `p2 THEN p1 PLUS p2` on the next line).
  A nested CONSIDER with such a pattern reads as written under this change: measured through `l4 batch -c` against `l4 run`, three rows, one of which fails on `main`.
- `jl4-core/src/L4/EvaluateLazy/GraphViz2.hs:529` and `:538-539` build a node's label from `firstLine (prettyLayout expr)`, so a CONSIDER node's label is its first line, `CONSIDER <scrutinee>`, and shows no arm.
  Read in code; not measured.
  Showing the first arm in that label is a change to `GraphViz2.hs`, not to the printer, and is not done here.
- `nest 2` is not on `unstable`, and `unstable` does not need it for a `WHERE`: its `Where` printer is `align $ vcatHard [...]` (from the same commit, `07a95495b`), which aligns the `WHERE` and its bindings to the column where the `Where` expression itself starts.
  Read in code at `5c4ed4e2d`, and measured with a prebuilt `l4` from `unstable` dated 2026-09-28 (its provenance is the file date; it passes the nested-CONSIDER fixtures, so it has that commit): all three `WHERE` fixtures give the answers `l4 run` gives.
  A later merge of `unstable`'s `Print.hs` into `main` will conflict on the `Consider` line.
- Nothing in the test suites checks that every corpus file re-prints to source with the same answers; §3.2.1 of `CLAUDE.md` describes the evaluation differential, which is run by hand and is deliberately not a test.
