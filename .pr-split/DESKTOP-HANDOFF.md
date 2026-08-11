# Picking this up on a machine that has GHC

## First, what a red check does and does not mean

CI **has** GHC; the container this split was cut in did not. So nothing will fail *because of*
the missing toolchain — the effect is only that no Haskell error was caught before pushing. A red
Haskell check is therefore a real finding, not an artifact, and the list below is where to look
first.

Fourteen of the twenty-six PRs touch no Haskell at all (`papers`, `docs`, `specs`,
`agent-tooling`, `corpus-*`, `experiments`, `go-pipeline`, `tests-cli`, `wizard-*`, `ci-build`,
`actus-archive`). If one of those is red, suspect prettier or a path filter, not the compiler.

## Ranked: where a Haskell failure is most likely

**1. The `Exponent` batch — expected to fail if merged singly.** `lang-syntax-typecheck`,
`lang-eval-ledger`, `lang-printer`, `service-cli`, `mlir`. `unstable` deletes the `Expr`
constructor `Exponent`; all five pattern-match it on `main`, in both directions (see
`DEPENDENCIES.md`). Fix: put the five in the merge queue as one batch. Do **not** try to reorder
them — it is not an ordering problem.

**2. Sliced `jl4/tests/Main.hs` imports.** Seven themes carry a slice of the golden-test driver.
One real break was already found and fixed (`lang-printer` called `lookupEnv` with no import).
Under `-Wall -Werror` both directions are fatal — a missing import *and* an unused one — so this
is the most likely remaining class. The attribution is in `.pr-split/spine/hunks.json`; the
line-level rules are at the top of `.pr-split/apply-spine.mjs`.

**3. Goldens encoding a sibling's behaviour.** Each PR's **Independence** section names the ones
that will need re-blessing if a sibling lands after it. `corpus-regcf`'s `tests/regcf.golden` and
the three `promissory-note` / `ceo-performance-award` goldens in `corpus-legal-new` are the
known cases.

**4. `-Wunused-packages`.** Checked statically and clean: the six added `build-depends` lines all
sit in the same theme as their consumer (`time`→dmn-export/DmnExport.hs,
`deepseq`→lang-eval-ledger/TracePostprocessSpec.hs, `megaparsec >=9.7`→lang-printer (a bound
tightening, not a new dep), `jl4-query-plan`/`containers`/`optics`/`servant-server`→service-cli,
and the new `jl4-lsp` test-suite stanza→lsp). Low risk, but it is fatal when it does fire.

## Reproducing a single PR locally

Per `CLAUDE.md` §2: never build in the reference checkout, one `dist-newstyle` per worktree, and
only one `cabal` at a time inside a worktree.

    git -C ~/src/legalese/l4-ide worktree add -b check/aug2026-<theme> \
      ~/src/legalese/l4wt/<theme> origin/claude/aug2026-<theme>
    cd ~/src/legalese/l4wt/<theme>
    cabal build all
    JL4_LIBRARY_PATH=$PWD/jl4-core/libraries cabal test jl4-test

Pin `JL4_LIBRARY_PATH` (§3.1) or you get unrelated failures that look like regressions.

To check the five-PR batch as it would actually merge, build the union rather than each branch:

    git checkout -B check/aug2026-batch origin/main
    for t in lang-syntax-typecheck lang-eval-ledger lang-printer service-cli mlir; do
      git merge --no-edit origin/claude/aug2026-$t || break
    done

Expect exactly one conflict, on `jl4/tests/Main.hs`'s `import System.Environment` line, between
`lang-printer` `(lookupEnv)` and `lang-imports-stdlib` `(lookupEnv, setEnv)`. Keep the union form.

## Re-cutting a slice if one is wrong

The manifests, not the branches, are the source of truth. Edit
`.pr-split/themes/<theme>.files`, then re-run the invariants and rebuild:

    node .pr-split/partition.mjs                     # 2021 files, 0 unresolved
    node .pr-split/depcheck.mjs .pr-split/themes     # import-level cross-theme edges
    bash .pr-split/ship.sh <theme> <worktree> .pr-split/themes .pr-split/bodies \
         .pr-split/spine/hunks.json

`ship.sh` force-pushes with lease, so the open PR updates in place.

**Remember `depcheck.mjs` only sees imports.** It missed the `Exponent` edge because that runs
through a data constructor of a module `main` already has. If you move Haskell files between
themes, check constructor- and class-level uses by hand as well.
