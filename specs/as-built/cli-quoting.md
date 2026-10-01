# `l4 batch`: input rows as exact string literals (as built)

As built on `main` by this PR.
Source spec: none.
Differences from the source spec: not applicable.
The work came from `unstable`; this page describes only what `main` has.
Line numbers are in this PR's tree, which is `main` at `00298eb60` plus the `l4 batch` changes this PR builds on.

Source: PR #51 (`fix/cli-quoting`; the fix is commit `3a8d77e76`; batch merge `c1c60fcd7`, landed on unstable through #77).
#51 also changed `l4 trace`, so that it runs Graphviz's `dot` directly instead of through a shell.
That half is not part of this PR, because `main` already has it: #534 (`93135eb02`, "l4 trace: render with dot without a shell") landed the same fix in `jl4/app/L4/Cli/Trace.hs`, with one more guard, `dotArg` (`Trace.hs:179`), which hands `dot` an output path that begins with `-` as a path and not as an option.
PR #51's other commit, `6c2e6c091`, adds a review log, `REVIEW-PART1-CODEBASE-MAP.md`, which is not on `main` and is not part of this PR.
The round-trip test and the fixture payload of the tests come from #632 (merge `3fa87dee6` on unstable), which found that the first version of the test caught only the loud half of the defect.

## What it does

`l4 batch` embeds each input row in a generated L4 wrapper as a string literal.
It used to escape only `"` when it did so.
On `main` before this change, a value containing a backslash, a newline or a tab came back either as a `null` result or as a DIFFERENT string, in a row marked `success` either way, and a value containing `"` failed to lex.
Now the row is quoted with the lexer's own `showStringLit`, so every character comes back as it was written.

Measured with the `l4` built from plain `main` and the one built from this PR, on `batch-code.l4` (`echoCode code MEANS code`) with the rows `C:\Users\meng`, `say "hi"`, `tab<TAB>here`, `line<LF>next`, `café5` and `back\5`: `main` answers `null` with status `success` for the backslash, tab, newline and `back\5` rows, a lexer error for the `"` row, and the text for `café5`. With this PR all six rows come back unchanged.

A second set of rows, `batch-escape-roundtrip.json`, is the one that shows the different-string case: with `main`'s `l4`, `\u0041` (a backslash, then `u0041`) comes back as `A`, `\\n` (two backslashes and an `n`) as one backslash and an `n`, and `C:\Users\x`, `back\slash`, a tab and a line break as `null`, every row `success`; with this PR all six come back as sent.

## Where it lives

- `jl4/app/L4/Cli/Batch.hs:917-931`: `escapeAsL4String` builds the row's JSON text and returns `showStringLit` of it; `generateJsonPayload` (`:913-915`) emits `DECIDE inputJson IS <that literal>`; `import L4.Lexer (showStringLit)` is at `:79`.
- `jl4-core/src/L4/Lexer.hs:963-965`: `showStringLit`, already on `main`, with the comment at `:960-962` that it "isn't truly precise, but it should be mostly fine"; the string-literal reader that reads its output back is `stringLiteral` (`:440-442`), which reads with megaparsec's `charLiteral`.

## Behaviour and rules

The row's JSON text is quoted with `showStringLit`, which writes Haskell-style escapes: `\"` and `\\`, mnemonics such as `\n` and `\DEL`, and decimal `\NNN` for non-ASCII, with `\&` where the next character would otherwise extend the escape.
The text is already JSON-encoded, so control characters arrive as JSON's own `\n`, `\t` or `\u00XX`; in practice the escapes that matter are those for JSON's `\` and `"` and for non-ASCII characters.
The L4 lexer reads string literals with `charLiteral`, the Haskell-report reader, so the payload comes back character for character; the lexer's own comment says `showStringLit` is not truly precise, so the claim rests on the round-trip test below and not on the code.
The old escaper replaced only `"`, so the lexer read every backslash in the JSON text as the start of an L4 escape: JSON's `\"` ended the L4 string, and JSON's `\\` and `\n` were decoded before `JSONDECODE` saw them, which then either failed and gave `null` or, when what was left spelled a different JSON escape (`\\u0041`, which JSON reads as `A`), succeeded with a different string.

## Tests and fixtures that pin it

- `jl4/tests-cli/Main.hs:732-743`: `l4 batch` on `batch-escape.l4` with `batch-escape-input.json` (a Windows path, embedded quotes, a newline, a tab, an apostrophe, braces and a percent sign) must report `"status":"success"`.
  This pins the loud half of the defect only: `echoFixed` ignores its input, so on the old escaper it fails only because the payload contains a `"`.
- `jl4/tests-cli/Main.hs:745-766`: `l4 batch` on `batch-code.l4` (`echoCode code MEANS code`) with `batch-escape-roundtrip.json` (six rows: a Windows path, a backslash, a tab, a line break, `\u0041`, `\\n`) must report `success` for every row and a `result` equal to the `code` sent.
  This pins the silent half: a corrupted value, `null` or a different string, shows as a result that is not the one sent.
  Run by hand with `main`'s `l4` (which has no `--continue-on-error`, so the test itself cannot run there), none of the six rows comes back as sent: four are `null` and two are a different string.
- The CRLF case of `describe "the CSV reader"` (the batch-cli change's `batch-crlf.csv`, a quoted cell holding a line break) asserts the answer as well as the input here: the cell `line one\nline two` comes back from `echoCode` unchanged, which the batch-cli change alone returns as `null`.
- Fixtures: `jl4/tests-cli/fixtures/batch-escape.l4`, `batch-escape-input.json` and `batch-escape-roundtrip.json`; all are in the suite's missing-fixture check (`Main.hs:310-312`).
- The `l4 trace` cases of #51 are not part of this PR; `main` already has them under `describe "l4 trace (output path safety)"` (`Main.hs:944`), from #534.
  Those are the cases that involve a shell; `l4 batch` runs none.

## Limits and known defects

- `escapeAsL4String` quotes the row as one L4 string; what `JSONDECODE` then does with the decoded text is unchanged.
- `showStringLit` is documented as not truly precise (`Lexer.hs:960-962`); the six rows in the round-trip test are what has been checked, not every character.
