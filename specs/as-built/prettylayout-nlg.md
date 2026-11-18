# A re-emitted module keeps its `@nlg` annotations (as built)

As built on `main` by this PR, measured on `main` at `4c887e0db`.
Source spec: none.
Differences from the source spec: not applicable.
The work came from `unstable`; this page describes only what `main` has.

Source: PR #427 (`45c2cc196b`, branch `fix/prettylayout-nlg`), which fixes smucclaw/l4-ide#966.
The carve commit used as the hunk map is `5c43fb680`, on the carve chain `scalpel/core-v1`; `0524efad1` on `refs/scalpel-join/vocab` has the same code diff and differs only in this page's wording.

Half of #427 was already on `main` before this PR, through `6520a3810`: `\[` as an `@nlg` escape (`jl4-core/src/L4/Lexer.hs:550-555`), the decoder comment in `jl4-core/src/L4/Nlg.hs`, the three `\[` cases in `jl4-core/test/NlgPercentSpec.hs:185,188,248`, and the `[see note \[3\] here]` row of `doc/reference/syntax/nlg.md:35`.
This PR carries the other half, the printer, and #427's two remaining doc hunks.

These differ from #427 by hand:

- **Annotations are opt-in.** #427 writes them back from `LayoutPrinter Name`, so every caller of `prettyLayout` gets `name [wording]`, and on `unstable` every one does. Here `prettyLayout` prints bare, as on `main`, and only `prettyLayoutWithNlg` writes annotations back. An earlier round of this PR kept #427's design and narrowed the callers that print a name as a label, one by one; a refuter then found six more that leak, among them the query planner, whose answer changed. The callers that re-emit a whole module to read it again are few, so they opt in instead.
- `printInlineNlg` matches `main`'s three-field `MkParsedNlg` and `MkResolvedNlg`, whose middle field is the language tag (#726), as `unstable` does after #429.
- A clause group's wording prints on a line of its own above the first clause, not after each clause's head. `main`'s clause printer is not in #427, and the bracket form there re-parsed onto the wrong node. The spelling is assumed, not ruled.
- A wording that runs over several lines prints on one line, because the line break put its continuation at the margin, where it ended the definition.

## What it does

- `l4 batch` re-emits the checked module with each name's `@nlg` annotation after it, in the bracket form, ``DECIDE `is large` [the amount %a% is large] a IS``, and a clause group's as `@nlg …` above its first clause.
  Before, the re-emitted module had no wordings at all.
- Nothing else changes: every other caller of `prettyLayout`, the REPL's re-emission included, prints exactly what it printed on `main` (measured below).

## Behaviour and rules (read in code)

- `prettyLayoutWithNlg` (`jl4-core/src/L4/Print.hs:53-54`) prints a module over `WithNlg` names (`:58`), whose printer appends `inlineNlgOf` (`:63-65`).
  Every module printer is generic in its name type, so this one instance reaches every name the module prints.
  `LayoutPrinter Name` itself prints bare (`Print.hs:123`).
- Its one caller is `l4 batch` (`jl4/app/L4/Cli/Batch.hs:223`).
  Every other site that prints a filtered module to read it again stays on `prettyLayout`: the REPL's evaluate, `:trace`, `:traceascii` and `:type` (`jl4-repl/app/Main.hs:635,731,780,1009`), none of which reads an annotation back, and the plain-printer tests `jl4-core/test/MultiClausePrintSpec.hs:52` and `RefuseSpec.hs:842`.
  jl4-service filters source text and prints no module.
- `inlineNlgOf` (`Print.hs:873-876`) prints a space and the default rendering (`annNlg`) in brackets.
  An annotation attaches to a `Name` and nothing else; #427's comment at `Print.hs:837-872` records the measurement.
- `printInlineNlg` (`Print.hs:886-893`) prints nothing for `MkInvalidNlg`, and joins fragments without inserting spaces, so `%b%'s` survives.
- `inlineNlgFragment` (`Print.hs:895-900`) prints a reference as `%name%` through `bareName` (`:906`).
- `escapeInlineNlgText` (`Print.hs:932`): a line break, with the spaces around it, becomes one space; an existing `\x` pair is copied; a bare `]` becomes `\]`; a lone trailing `\` is doubled.
- A type name prints bare even under `WithNlg` (`Print.hs:142`, `:196`).
- A clause group: `writtenClauses` prints its head bare on each clause and puts `ownLineNlg hd` above the first (`Print.hs:369`).
  `ownLineNlg` is a `LayoutPrinter` method that answers nothing (`:117-118`) except for a `WithNlg` name, which answers `ownLineNlgOf` (`:395`), so a clause group printed by plain `prettyLayout` writes no `@nlg` line.

## Measured against `main`

**Re-parsing re-emitted modules.** Every tracked `.l4` file (685) was parsed, printed with `prettyLayoutWithNlg`, re-parsed, and its table of annotated names and their decoded, language-tagged wordings compared with the source's.
72 files carry 922 annotations.
59 come back with every annotation on the same name, in the same words and language.
6 do not re-parse through either printer, at the same first error and position (`currency`, `holdings`, `jurisdiction`, `legal-persons` and `llm` in `jl4-core/libraries/`, and `tests-cli/fixtures/nlg-owner-main.l4`): `main`'s printer cannot print those files for reasons that have nothing to do with annotations.
7 differ:

| File                                                                                                                | What changes                                                                                               |
| ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `ok/nlg-module-lang.l4`                                                                                             | `@lang he` is not printed, so both Hebrew wordings come back tagged `en`; the `:en` alternative is dropped |
| `not-ok/nlg/nlg_lang_conflict.l4`, `nlg_lone_tag.l4`, `nlg_lone_tag_head.l4`, `tests-cli/fixtures/lang-tag-case.l4` | a tagged wording comes back untagged, so in the module's language (`en`)                                   |
| `ok/pattern-matching-inline-annotations.l4`                                                                         | one annotation, written after a body to see that it is not the first overload's, is dropped                |
| `tests-cli/fixtures/batch-nlg-two-lines.l4`                                                                         | the wording's line break comes back as a space, by design                                                  |

**Evaluating re-emitted modules.** `l4 run` on the 66 re-emitted modules that re-parse, printed by `prettyLayoutWithNlg` and by `prettyLayout`, under `JL4_FIXED_NOW=2025-01-31T15:45:30Z`, 149 results: every result is the same, and so is every exit code (`prelude.l4` and `experiments/dogs.l4` exit 1 on both sides).
4 outputs differ: 3 in line and column numbers only, from the added `@nlg` lines and the longer lines, and in `not-ok/nlg/nlg_spaced_slot.l4` the module with annotations raises the `lint/spaced-nlg-slot` warning that its source raises.
This stands in for `CLAUDE.md` §3.2.1's differential, which needs a harness `main` does not have.
`l4 batch` against `l4 run` on `#TRACE` files was not run: printed by `prettyLayout`, none of the 23 files with a `#TRACE` in `ok/`, `legal/` and `doc/` parses again (measured on this branch), for reasons outside this PR.

**The binaries on the corpus.** `main`'s `l4` and this PR's on the 665 tracked `.l4` files that do not reach the network, under the same clock: `l4 run`, `l4 nlg`, `l4 render --format json`, `l4 render --format text` and `l4 state-graph` give byte-identical output and exit codes on every file.
The 20 files left out use `FETCH`, `POST` or `ENV`, or import a file that does, `orchestrator.l4` through `anthropicClient.l4` and the `llm` library's users through `llm.l4`.
`l4 batch` on the 30 fixtures an independent refuter wrote (escapes, quotes, non-ASCII, AKA, mixfix, LET, ASSUME, a multi-line wording, name collisions) gives byte-identical output and exit codes; two of them, a mixfix and an ASSUME, fail on both.

**The refuter's leaks, re-run.** Each of these differed from `main` at `c11af32c1`, and each is now byte-identical to `main`'s output, except where noted:

- jl4-service query plans for a rule with `@nlg` under its conditions, with no bindings and with `{"p":{"resident":false}}`, `{"p.resident":false}` and `{"p's resident":false}`: labels, atomIds, asks, and `determined: false` with the binding. Also the plans for the other bundle. The deploy reply differs only in its `updateId`, a fresh id per deployment, and the OpenAPI document only in the server's port.
- jl4-service's decline for `fee in year` (its `rule` field), the deontic answer for `payment` (`action: "pay price"`, `deadline: "price"`), and `is adult` with `?trace=full&graphviz=true`.
- The REPL's `:qp` on that rule, against the same file with its annotations stripped: identical.
- `l4 trace --format dot` and `l4 run` (`#EVALTRACE` text and every diagnostic) on the refuter's `defonly.l4`, `uses.l4`, `exh.l4` (`lint/non-exhaustive-match`), `clauses.l4` (the missing-clause hint), `refuse.l4` and `pasted.l4`.
- `jl4-mlir wasm` on `m.l4`: `schema.json` (`fnName`, `bindingLabel`, `exampleCode`), `.wasm` and `.mlir`.

**Cost.** `prettyLayoutWithNlg` is linear in the number of rules, the depth of an expression and the length of an annotation (best of 5, fresh parse each time):

| Input                                        | Size               | `prettyLayoutWithNlg` | `prettyLayout` (`main`) |
| -------------------------------------------- | ------------------ | --------------------- | ----------------------- |
| rules, each with an annotated head and input | 100 / 1000 / 4000  | 0.51 / 5.1 / 20.5 ms  | 0.11 / 1.3 / 5.7 ms     |
| one body nested, every use annotated         | 10 / 100 / 1000    | 0.01 / 0.07 / 0.77 ms | 0.00 / 0.02 / 0.19 ms   |
| one annotation of n words, half of them `]`  | 100 / 1000 / 10000 | 0.02 / 0.16 / 1.82 ms | nothing to print        |

`l4 batch` costs more, and the cost is not the printer's.
Each row re-checks the re-emitted module, which now carries the annotations, and checking annotations is already superlinear on `main`: `main`'s `l4 check` on the generated files takes 0.21 / 0.74 / 2.07 / 4.91 s at 200 / 800 / 2000 / 4000 rules, against 0.14 / 0.46 / 1.11 / 2.14 s with the annotations removed, and the parser alone accounts for most of it (annotation overhead 0.17 / 0.67 / 1.95 s at 800 / 2000 / 4000).
So `l4 batch` with 3 rows takes 0.69 / 2.9 / 8.1 / 20.6 s here against 0.52 / 2.0 / 5.2 / 11.5 s on `main`, with identical output.
Where in `L4.Parser.ResolveAnnotation` the superlinear part is was not profiled.
The REPL does not pay it: on the refuter's generated files, five further expressions cost 0.33 s each at 1,000 annotated rules and 0.68 s at 2,000, the same as on the same files with their annotations stripped, and the sessions print the same.

## Tests that pin it

- `jl4-core/test/PrettyLayoutNlgSpec.hs`, registered at `jl4-core/jl4-core.cabal:203`.
  `survivesPrinting` (8 cases, `:97-180`) parses, prints with `prettyLayoutWithNlg`, re-parses, compares the decoded annotation on every annotated name, and pins the printed spelling: an appform head, parameters and a use occurrence; a reference abutting a word; a `GIVEN` parameter with `5%`; a record field and a `DECLARE` head; a line annotation with a bare `]`; one ending in a lone `\`; a non-escape `\q`; a clause group's wording.
  `:189` prints a two-line wording on one line; `:205` pins that plain `prettyLayout` writes neither a bracket nor an `@nlg` line; `:238` and `:242` pin the ladder's code lens and lookup by name.
  All seven of #427's cases fail on `main`.
- `jl4/tests-cli/Main.hs:4313`, `l4 batch runs an export whose annotation names its input`, from `main`: the annotation is now printed back and the row still runs.
- `jl4/tests-cli/Main.hs:4318`, `l4 batch runs an export whose wording runs over two lines`, on `fixtures/batch-nlg-two-lines.l4`; it fails without the one-line commit.
- `jl4/tests-cli/Main.hs:4328`, `l4 run prints a value without its annotations`, from `main`, and `:4349`, `l4 state-graph labels an edge without its annotations`, on the same fixture.
- `doc/reference/syntax/annotation-example.l4:42` uses `\[`; `doc/test-docs.sh` type-checks it.
- No golden captures `prettyLayout` output.

## Docs

- `doc/reference/syntax/README.md:150-151`: the `@ref` escape paragraph names `\[` among the `@nlg` escapes.
- `doc/reference/syntax/annotation-example.l4:28-45`: `the surcharge on`, with an escaped bracket pair.
- No page needed a change for the printer: nothing a user reads changes, because `l4 batch` reports results and diagnostics, not the module it re-emits.

## Limits and known defects

- The bracket form has no spelling for a language tag, and the printer prints only the default rendering, so a re-emitted module loses its tags and its other languages, and `@lang` is not printed either. Measured above; the same is true on `unstable`.
- An annotation that failed to parse (`MkInvalidNlg`) prints as nothing, with no diagnostic.
- `l4 batch` now pays `main`'s superlinear annotation checking once per row (see Cost), and nothing in its output reads an annotation back.
- A new caller that re-emits a module to read it again must choose `prettyLayoutWithNlg` itself; by default it gets `main`'s bare printing.
