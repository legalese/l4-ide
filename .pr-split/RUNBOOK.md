# Runbook — resuming the aug2026 PR split

Everything needed to finish is on this branch. Nothing lives only in a session.

## State

- `.pr-split/themes/<theme>.files` — the manifest: every file that PR carries. **Source of truth.**
- `.pr-split/themes/<theme>.prs`  — the unstable PR numbers behind it.
- `.pr-split/themes/INDEX.tsv`    — theme, file count, PR count.
- `.pr-split/bodies/<theme>.md`   — line 1 is the PR title (after `# `), the rest is the PR body.
- `.pr-split/spine/hunks.json`    — line-level attribution of the 5 shared files.
- `.pr-split/FOOTER.md`           — appended to every PR body.
- `.pr-split/DEPENDENCIES.md`     — the 7 measured edges and the merge order they imply.

## Rebuild and push one branch

    SP=<scratch>   # holds a worktree `wt` and a copy of themes/
    git worktree add --detach $SP/wt origin/main
    bash .pr-split/ship.sh <theme> $SP/wt .pr-split/themes .pr-split/bodies .pr-split/spine/hunks.json

`ship.sh` builds `claude/aug2026-<theme>` from `origin/main`, applies the theme's spine slice,
makes the two special-case `cabal.project` edits, regenerates the lockfile for `wizard-housing`,
commits with the body's title, and pushes with retries.

## Open the PR

Draft, base `main`, head `claude/aug2026-<theme>`, title = body line 1, body = rest + `FOOTER.md`.
Then add the `aug2026` label with the issues API (it auto-creates).

## Invariants to re-check after any manifest edit

    node .pr-split/partition.mjs            # 2021 files, 0 unresolved
    node .pr-split/depcheck.mjs .pr-split/themes    # cross-theme Haskell imports
    node .pr-split/cabalcheck.mjs $SP/wt            # every .cabal module resolves

Partition test: `cat .pr-split/themes/*.files | sort | uniq -d` must be empty, and the union plus
`.pr-split/analysis/spine.txt` must equal `git diff --name-only origin/main...origin/unstable`.

## Progress

See `.pr-split/STATUS.tsv` — one row per theme: pushed?, PR number.
