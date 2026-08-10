# Spine-file hunk attribution — notes

Companion to `hunks.json`. Covers the five files that no single theme can own:

| file                          | git hunks (`-U3`) | JSON entries | single-theme hunks | split hunks |
| ----------------------------- | ----------------- | ------------ | ------------------ | ----------- |
| `jl4-core/jl4-core.cabal`     | 8                 | 15           | 5                  | 3           |
| `jl4/jl4.cabal`               | 4                 | 7            | 2                  | 2           |
| `jl4-lsp/jl4-lsp.cabal`       | 1                 | 1            | 1                  | 0           |
| `jl4-service/jl4-service.cabal` | 1               | 1            | 1                  | 0           |
| `jl4/tests/Main.hs`           | 7                 | 15           | 5                  | 2           |
| **total**                     | **21**            | **39**       | **14**             | **7**       |

## How to read the JSON

Hunks are numbered 1..N in the order `git diff origin/main...origin/unstable -- <file>` prints
them at default `-U3` context. Verify the numbering with:

```
git diff origin/main...origin/unstable -- <file> | grep -n '^@@'
```

Seven of the twenty-one hunks are *not* single-theme: git's hunk boundaries here are an artifact of
three lines of context, not of authorship. A `exposed-modules` block that gained BPMN, DMN and
ledger modules in three different PRs is one git hunk. Splitting those on theme lines is the whole
point of the exercise, so for those hunks the JSON carries **several entries with the same `hunk`
number**, each marked `"split": true` and each carrying a `lines` array naming the added (or
removed) lines that theme owns. Every added and removed line in every hunk is claimed by exactly
one theme; no line is claimed twice, and none is left over. Line counts were reconciled against the
`@@ -a,b +c,d @@` arithmetic for all 21 hunks.

Where a `lines` entry paraphrases a multi-line comment block, the paraphrase is marked as such —
the comment travels with the code it annotates.

## Hunks that needed a judgement call

### `jl4/tests/Main.hs` hunk 4 — the corpus-sanity block

The `describe "corpus sanity (every glob matched something)"` block is generic harness hygiene: it
asserts that each of the eight corpus globs matched at least one file, so a glob that silently goes
empty fails loudly instead of passing vacuously. On its face it belongs to no feature theme at all.

Two facts decided it for **lang-syntax-typecheck**:

1. Its last assertion is `corpusNonEmpty "export-placement" exportPlacementFiles`, so it does not
   compile without the `not-ok/export-*.l4` glob added a few lines above in the same hunk.
2. It arrived in the same commit as that glob — `ee67baa7`, "test(jl4): wire orphaned not-ok
   fixtures, self-resolve libraries, guard empty corpus (review T12)" — whose only other files are
   the twelve `jl4/examples/not-ok/tests/export-*.golden` files, all of which
   `lang-syntax-typecheck.files` owns.

So the export-placement glob, the corpus-sanity block and the `describe "export placement"`
registration travel together in the lang-syntax-typecheck PR. If a reviewer would rather see the
sanity block land on its own, it is a clean three-line excision (drop the `export-placement`
assertion, keep the other seven) — but then it needs a home, and none of the ~25 themes is a
"test-harness hygiene" theme. `tests-cli` owns `jl4/tests-cli/Main.hs`, a different binary, so it is
not that one.

### `jl4/tests/Main.hs` hunks 3 and 5 — `JL4_LIBRARY_PATH` handling, split across two commits

The `setEnv "JL4_LIBRARY_PATH"` default in `main` (hunk 3) and `mkLibraryPathScrubber` (hunk 5) are
a matched pair — the first guarantees the variable is always set, the second replaces its absolute
value with a stable `$JL4_LIBRARY_PATH` token so goldens are machine-independent — but they landed
in different commits (`ee67baa7` and `6a33968b`) with different companion files. Both are attributed
to **lang-imports-stdlib**, on the strength of what they are for rather than what shipped beside
them: the only golden text either one affects is `[Import Resolution]` log output
(`Found on filesystem: $JL4_LIBRARY_PATH/prelude.l4`), emitted by `L4.Import.Resolution`, which
lang-imports-stdlib owns along with `jl4-core/libraries/`.

**Ordering constraint worth flagging to whoever sequences the PRs.** The three goldens that actually
contain the scrubbed token —
`jl4/examples/not-ok/tc/tests/{section-scoping-import-collision,set-and-unoverloaded,set-equals-ambiguous}.golden` —
are owned by **lang-syntax-typecheck**, not by lang-imports-stdlib. So: if lang-syntax-typecheck
lands first, those goldens carry a `$JL4_LIBRARY_PATH` token that nothing yet produces, and they
fail. Either lang-imports-stdlib goes first, or lang-syntax-typecheck's PR temporarily carries
hunk 5 as well. I have recorded the attribution the way the code reads; the sequencing is a call for
whoever orders the PRs.

### `jl4-core/jl4-core.cabal` hunks 1–2 — the `data-files` move

Three themes have a claim. `ci-build` owns `.github/workflows/pr-checks.yml`, where the guard the
comment points at (`cabal check` plus a grep of `cabal sdist --list-only`) lives. `service-cli` owns
`jl4-core/src/L4/API/EmbeddedLibraries.hs` and its TH splice, which is the code that consumes
`data-files`. `lang-imports-stdlib` owns `jl4-core/libraries/*.l4` — the files the glob names — and
`L4.Import.Resolution`, whose cascade the whole fix exists to keep working.

Attributed to **lang-imports-stdlib**, matching the task's own reading ("the data-files/embedded-stdlib
comment is about imports") and because the observable symptom the comment describes is an import
failure: an installed `l4` answering "Module not found: prelude". Hunks 1 and 2 are two halves of one
move and cannot be separated — hunk 1 inserts the field above the first section, hunk 2 deletes it
from below — so they carry the same theme by necessity, not by judgement.

### `jl4-core/jl4-core.cabal` hunk 3 — the `megaparsec >=9.7` bound

The in-file comment says the bound is for "the lexer's ditto (^) column metric", which reads as
`lang-syntax-typecheck` (that theme owns `jl4-core/src/L4/Lexer.hs`). It is not. The bound exists for
`Text.Megaparsec.Unicode.isWideChar`, and that symbol has exactly one importer anywhere in the tree:

```
jl4-core/src/L4/Print/Columnar.hs:31:import Text.Megaparsec.Unicode (isWideChar)
```

which `lang-printer` owns. The commit that raised the bound is `7bb6879c`, "fix(columnar): defer
column width to megaparsec isWideChar; pin megaparsec >=9.7", and it touched only
`jl4-core/jl4-core.cabal` and `jl4-core/src/L4/Print/Columnar.hs`. Attributed to **lang-printer**,
paired with hunk 6, which adds `L4.Print.Columnar` to `exposed-modules`. If the comment's wording
survives the split it will keep misdirecting readers; worth rewording to name `L4.Print.Columnar` in
the lang-printer PR.

### Shared imports in `jl4/tests/Main.hs` hunk 3

Three import lines in hunk 3 are attributed by first use, but two of them have a second consumer:

- `import System.Environment (lookupEnv, setEnv)` → **lang-imports-stdlib** (the `setEnv` block in
  `main`). But hunk 6, attributed to lang-printer, also calls `lookupEnv` twice, for
  `JL4_PRETTY_DUMP_DIR` and `JL4_EVALDIFF`.
- `import Data.Char (isAlphaNum)` (hunk 1) and `import Text.Read (readMaybe)` (hunk 3) → both
  **lang-printer**, both used only inside hunk 6.

Whichever of lang-imports-stdlib and lang-printer lands second will find `System.Environment` already
imported; whichever lands first must carry it. Since `-Wall -Werror` is on and an unused *import* is
a warning, a PR that carries the import without a use will not build. Concretely: if lang-printer
lands before lang-imports-stdlib it must bring the `System.Environment` line with it, and
lang-imports-stdlib then drops that line from its own diff. This is the one place in the five spine
files where the split is order-dependent at the line level rather than at the file level.

## Hunks that needed no judgement at all

For the record, these were mechanical — the module named in the hunk appears verbatim in exactly one
`<theme>.files` manifest:

- `jl4-core.cabal` hunks 4, 5, 6, 7 and 8 (every `exposed-modules` / `other-modules` line).
- `jl4.cabal` hunks 2 and 3 (`L4.Cli.*` and the test modules).
- `jl4-lsp.cabal` hunk 1 — the entire `test-suite jl4-lsp-test` stanza, both of whose modules
  (`HoverDisplaySpec`, `LibraryResolutionSpec`) plus `test/Spec.hs` are in `lsp.files`. Note
  `LibraryResolutionSpec` is the *jl4-lsp* one; do not confuse it with `lang-imports-stdlib`'s
  `jl4-core/test/ResolutionCascadeSpec.hs`.

Two build-depends hunks were decided by finding the consumer rather than by manifest lookup, and
both came out unambiguous:

- `jl4.cabal` hunk 4 (`time` in `jl4-test`) → **dmn-export**: `jl4/tests/DmnExport.hs` is the only
  test module in that suite importing `Data.Time` (`Data.Time.Calendar (fromGregorian)`), and the
  dep was added by `5d22ec9f`, "feat(dmn): law time on a date axis".
- `jl4-core.cabal` hunk 8's `deepseq` → **lang-eval-ledger**: `jl4-core/test/TracePostprocessSpec.hs`
  is the only module in `jl4-core-test` importing `Control.DeepSeq`.
- `jl4-service.cabal` hunk 1 (`servant-server` in `jl4-service-test`) → **service-cli**: added by
  `d2dd71f9`, "feat(service): GET /functions/:name/ladder, and the two bugs it uncovered", the commit
  that grew `jl4-service/test/IntegrationSpec.hs`. Every `jl4-service/test/*.hs` is in
  `service-cli.files`. The endpoint is a ladder endpoint, but no ladder-viz-owned file is involved.

## Themes that draw nothing from the spine

`actus-archive`, `agent-tooling`, `ci-build`, `corpus-legal-new`, `corpus-regcf`, `docs`,
`experiments`, `go-pipeline`, `lang-sets`, `mlir`, `papers`, `proleg`, `specs`, `tests-cli` and
`wizards` need no part of these five files. In particular no corpus glob was added or changed in
`jl4/tests/Main.hs` on this range other than the `not-ok/export-*.l4` one discussed above — the
`ok/**`, `legal/**` and `libraries/*.l4` globs are context lines, already on `main` — so the corpus
themes carry no spine hunk. `ci-build` is named in the hunk-1 comment but owns none of its lines.
