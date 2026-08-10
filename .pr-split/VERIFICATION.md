# What was verified, and what was not

## Verified mechanically

- **The partition is exact and disjoint.** All 2,021 files in
  `git diff --name-only origin/main...origin/unstable` are assigned to exactly one of 26 themes
  (2,016) or are one of the 6 shared files sliced across PRs. `sort | uniq -d` over the union of
  all manifests is empty; nothing is missing.
- **Every branch's content matches its manifest.** Checked branch-by-branch against
  `origin/claude/aug2026-*`. Two deliberate deviations, both documented in their own PR:
  `agent-tooling` writes the skill edits to `skills/writing-l4-rules/` because `.claude/skills/`
  is a symlink on `main`; `wizard-housing` carries a regenerated root `package-lock.json` so it
  installs standalone.
- **The 22 rename sources are removed, not orphaned.** `specs` shows 13 renames
  (`specs/todo/` -> `specs/done/`), `ladder-viz` 5 (`jl4/ok/inert/` -> `jl4/examples/ok/inert/`),
  `lang-syntax-typecheck` 3. Verified per branch: source gone, destination present.
- **The shared spine is fully claimed.** All 224 added lines of `jl4/tests/Main.hs` and all 89
  added `.cabal` lines are claimed by exactly one theme.
- **Cabal/module consistency.** Every module named in a `.cabal` on every branch resolves to a
  source file on that branch (`cabalcheck.mjs`). Baseline `main` passes the same check.
- **Formatting.** Every slice passes `prettier@3.4.2 --check` on its formattable files.
- **Cross-theme dependencies.** Seven edges, found by resolving every Haskell import against every
  sibling's file list and by running `npm ci` — see `DEPENDENCIES.md`.

## NOT verified

- **Nothing was compiled.** GHC and cabal are not installed in the container this work ran in, so
  no Haskell slice has been built or tested. Every claim about Haskell correctness in these PR
  bodies is quoted from the source PR that originally made it, not re-measured here. CI on the PRs
  is the first real compile.
- **No TypeScript app was built or tested.** `npm ci` was run only far enough to establish the
  `@repo/ladder-core` dependency and to regenerate the housing wizard's lockfile.
- **The lockfile was regenerated with npm 10.9.7**, while the repo pins `npm@11.11.0`.
  `lockfileVersion` is unchanged, but a `npm@11` run may still churn it.
