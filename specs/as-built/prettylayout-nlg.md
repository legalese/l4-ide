# prettyLayout keeps `@nlg` annotations (as built)

As built on `main` by this PR, measured on `main` at `4c887e0db`.
Source spec: none.
Differences from the source spec: not applicable.
The work came from `unstable`; this page describes only what `main` has.

Source: PR #427 (`45c2cc196b`, branch `fix/prettylayout-nlg`), which fixes smucclaw/l4-ide#966.
The carve commit used as the hunk map is `5c43fb680`, on the carve chain `scalpel/core-v1`; `0524efad1` on `refs/scalpel-join/vocab` has the same code diff and differs only in this page's wording.

Half of #427 was already on `main` before this PR, through `6520a3810`: `\[` as an `@nlg` escape (`jl4-core/src/L4/Lexer.hs:550-555`), the decoder comment in `jl4-core/src/L4/Nlg.hs`, the three `\[` cases in `jl4-core/test/NlgPercentSpec.hs:185,188,248`, and the `[see note \[3\] here]` row of `doc/reference/syntax/nlg.md:35`.
This PR carries the other half, the printer, and #427's two remaining doc hunks.

These differ from #427 by hand:

- `printInlineNlg` matches `main`'s three-field `MkParsedNlg` and `MkResolvedNlg`, whose middle field is the language tag (#726), as `unstable` does after #429.
- `main`'s NF printer, which #427 never saw, prints a constructor bare, and an obligation's expressions print without their annotations (`withoutNlg`). #427's own rule is that a value is a result, not source, and `main` pins it: `l4 run prints a value without its annotations` in `jl4/tests-cli/Main.hs:4322`.
- A name shown as a label, or used as a lookup key, prints bare through `prettyBareName`: the core and LSP ladders, the LSP inspector, and jl4-service's answer for an unapplied constructor. Assumed, not ruled; `unstable` still prints the annotation at every one of those call sites.
- A clause group's wording prints on a line of its own above the first clause, not after each clause's head. `main`'s clause printer is not in #427, and the bracket form there re-parsed onto the wrong node. The spelling is assumed, not ruled.

## What it does

- `L4.Print.prettyLayout` prints each name's `@nlg` annotation back, in the bracket form, straight after the name: ``DECIDE `is large` [the amount %a% is large] a IS``.
  Before, it dropped every one, so `l4 batch` and the REPL, which re-parse a printed module, ran a module with no wordings.
- A clause group prints its wording as `@nlg …` between the signature and the first clause.
- Types, evaluation results, ladder labels, the inspector, and the service's constructor answers print as on `main`, without annotations.

## Behaviour and rules (read in code)

- `LayoutPrinter Name` appends `inlineNlgOf n` (`jl4-core/src/L4/Print.hs:98`), which prints a space and the default rendering (`annNlg`) in brackets (`Print.hs:846-849`).
  An annotation attaches to a `Name` and nothing else, so this one hook reaches all of them; #427's comment at `Print.hs:812-845` records the measurement.
- `printInlineNlg` (`Print.hs:859-866`) prints nothing for `MkInvalidNlg`, and joins fragments without inserting spaces, so `%b%'s` survives.
  It is not the hover printer `LayoutPrinter Nlg`, which puts a space after a reference.
- `inlineNlgFragment` (`Print.hs:868-873`) prints a reference as `%name%` through `bareName`, so a name's own annotation never recurses into it.
- `escapeInlineNlgText` (`Print.hs:901-920`): fragment text is stored with its escapes, so an existing `\x` pair is copied, a bare `]` becomes `\]`, and a lone trailing `\` is doubled, because it would otherwise escape the `]` the printer appends.
- `bareName` (`Print.hs:879-880`) is a name with no annotation, and it is what `main`'s printer printed for every name.
  Types use it (`Print.hs:117`, and `goDisplayTy` at `:171`, which is what a `#CHECK` answer goes through), and so do the value printers (`Print.hs:958-993`) and the NF printers (`Print.hs:1011`, `:1017`, `:1119`).
- `withoutNlg` (`Print.hs:884-885`) clears `annNlg` and `annNlgAlts` on every name in an expression; the `ValObligation` arm applies it to party, action and deadlines (`Print.hs:974`).
- `writtenClauses` prints the head bare on each clause and puts `ownLineNlgOf` above the first (`Print.hs:344`, `:370-373`).
  The line form ends at the end of its line, which is the end of the annotation, and every escape `printInlineNlg` writes decodes the same in both forms.
- `prettyBareName` (`Print.hs:43-44`) is `bareName` as `Text`.
  Its callers: `jl4-core/src/L4/Viz/Ladder.hs:258,291,448`, `jl4-lsp/src/LSP/L4/Viz/Ladder.hs:492`, `jl4-lsp/src/LSP/L4/Inspector.hs:180,187,188`, `jl4-service/src/Backend/Jl4.hs:1316`.

## Measured against `main`

**Re-parsing printed modules.** Every tracked `.l4` file (684) was parsed, printed with this PR's printer, re-parsed, and its table of annotated names and their decoded, language-tagged wordings compared with the source's.
"Before" is the same module printed with every annotation stripped first, which is byte-for-byte what `main`'s printer emitted.
71 files carry 921 annotations.
59 come back with every annotation on the same name, in the same words and language.
6 do not re-parse, before or after, at the same first error and position (`currency`, `holdings`, `jurisdiction`, `legal-persons` and `llm` in `jl4-core/libraries/`, and `tests-cli/fixtures/nlg-owner-main.l4`): `main`'s printer cannot print those files for reasons that have nothing to do with annotations.
6 differ:

| File                                                                                                                | What changes                                                                                               |
| ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `ok/nlg-module-lang.l4`                                                                                             | `@lang he` is not printed, so both Hebrew wordings come back tagged `en`; the `:en` alternative is dropped |
| `not-ok/nlg/nlg_lang_conflict.l4`, `nlg_lone_tag.l4`, `nlg_lone_tag_head.l4`, `tests-cli/fixtures/lang-tag-case.l4` | a tagged wording comes back untagged, so in the module's language (`en`)                                   |
| `ok/pattern-matching-inline-annotations.l4`                                                                         | one annotation, written after a body to see that it is not the first overload's, is dropped                |

Before the clause-group commit, two more files differed, `pattern-matching-first-clause-annotations.l4` and `pattern-matching-annotations-after-group.l4`, with the rule's wording moved onto the group's input and onto a constructor.

**Evaluating printed modules.** `l4 run` on the 65 printed modules that re-parse, printed with and without annotations, under `JL4_FIXED_NOW=2025-01-31T15:45:30Z`, 149 results: every result is the same.
4 outputs differ: 3 in line and column numbers only, from the added `@nlg` lines and the longer lines, and in `not-ok/nlg/nlg_spaced_slot.l4` the printed module now raises the `lint/spaced-nlg-slot` warning that the source raises.
This stands in for `CLAUDE.md` §3.2.1's differential, which needs a harness `main` does not have.
`l4 batch` against `l4 run` on `#TRACE` files was not run: printed by `prettyLayout`, none of the 23 files with a `#TRACE` in `ok/`, `legal/` and `doc/` parses again (measured on this branch), for reasons outside this PR, so that comparison could not tell this change apart.

**The binaries on the corpus.** `main`'s `l4` and this PR's, on the 657 tracked `.l4` files that make no network call, under the same clock: `l4 run`, `l4 nlg`, `l4 render --format json` and `l4 render --format text` give byte-identical output and exit codes on every file.
On the PR's printer commit alone, `l4 run` differed on one file, `tests-cli/fixtures/annotated-values.l4`, the value leak the NF commit closes.

**Labels.** With `GIVEN amount [the amount claimed]` and ``DECIDE `may proceed` @nlg …``, before the label commit: the code lens named the rule `` `may proceed` [the claim for %amount% may proceed] ``, the ladder's input nodes read `amount [the amount claimed]`, and ``l4VisualizeByName … "`may proceed`"`` answered not found.
After it, all three are as on `main`.
Type-check diagnostics were not narrowed; they are unchanged on the corpus, and on a probe of two annotated overloads of one name, called ambiguously, the candidates print bare.

**Cost.** Printing is linear in the number of rules, the depth of an expression and the length of an annotation (best of 5, fresh parse each time, this PR's printer with annotations against the same module stripped):

| Input                                        | Size               | With annotations      | Stripped (`main`)     |
| -------------------------------------------- | ------------------ | --------------------- | --------------------- |
| rules, each with an annotated head and input | 100 / 1000 / 4000  | 0.29 / 4.0 / 20.6 ms  | 0.17 / 2.4 / 22.0 ms  |
| one body nested, every use annotated         | 10 / 100 / 1000    | 0.01 / 0.08 / 0.92 ms | 0.00 / 0.03 / 0.36 ms |
| one annotation of n words, half of them `]`  | 100 / 1000 / 10000 | 0.04 / 0.44 / 1.78 ms | nothing to print      |

`l4 batch` costs more, and the cost is not the printer's.
Each row re-checks the printed module, which now carries the annotations, and checking annotations is already superlinear on `main`: `main`'s `l4 check` on the generated files takes 0.21 / 0.74 / 2.07 / 4.91 s at 200 / 800 / 2000 / 4000 rules, against 0.14 / 0.46 / 1.11 / 2.14 s with the annotations removed, and the parser alone accounts for most of it (annotation overhead 0.17 / 0.67 / 1.95 s at 800 / 2000 / 4000).
So `l4 batch` with 3 rows takes 0.65 / 2.7 / 7.8 / 20.5 s here against 0.48 / 1.9 / 5.1 / 11.3 s on `main`, with identical output.
Where in `L4.Parser.ResolveAnnotation` the superlinear part is was not profiled.

## Tests that pin it

- `jl4-core/test/PrettyLayoutNlgSpec.hs`, registered at `jl4-core/jl4-core.cabal:203`.
  `survivesPrinting` (8 cases, `:95-180`) parses, prints, re-parses, compares the decoded annotation on every annotated name, and pins the printed spelling: an appform head, parameters and a use occurrence; a reference abutting a word; a `GIVEN` parameter with `5%`; a record field and a `DECLARE` head; a line annotation with a bare `]`; one ending in a lone `\`; a non-escape `\q`; a clause group's wording.
  Two cases (`:198`, `:202`) pin the ladder: the code lens names the rule bare, and the rule is found by that name, with its inputs labelled bare.
  All seven of #427's cases fail on `main`; the clause-group case and the two ladder cases fail without their commits.
- `jl4/tests-cli/Main.hs:4322`, `l4 run prints a value without its annotations`, from `main`: a constructor inside a value, and an obligation's party and action.
- `jl4/tests-cli/Main.hs:4312`, `l4 batch runs an export whose annotation names its input`, from `main`: the annotation is now printed back and the row still runs.
- `doc/reference/syntax/annotation-example.l4:42` uses `\[`; `doc/test-docs.sh` type-checks it.
- No golden captures `prettyLayout` output.

## Docs

- `doc/reference/syntax/README.md:150-151`: the `@ref` escape paragraph names `\[` among the `@nlg` escapes.
- `doc/reference/syntax/annotation-example.l4:28-45`: `the surcharge on`, with an escaped bracket pair.
- No page described `prettyLayout` dropping annotations, so none had to change; nothing a user reads from `l4 batch` or the REPL shows an annotation.

## Limits and known defects

- The bracket form has no spelling for a language tag, and the printer prints only the default rendering, so a re-printed module loses its tags and its other languages, and `@lang` is not printed either. Measured above; the same is true on `unstable`.
- An annotation that failed to parse (`MkInvalidNlg`) prints as nothing, with no diagnostic.
- Every other caller of the name printer gets the `[…]` suffix: diagnostics, `#EVALTRACE` text, hover text of an expression, the service's error messages. None changed on the corpus; that is the evidence, not a guarantee.
- `l4 batch` now pays `main`'s superlinear annotation checking once per row (see Cost).
