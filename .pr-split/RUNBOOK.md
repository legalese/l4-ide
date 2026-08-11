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

## Final QA pass (do this once every PR is open)

A PR-opening agent reported reading a body file one line shorter than it was on disk — the
drafting agent was very likely still writing it. The readiness gate (`## Provenance` present)
narrows that window but does not close it.

So, once all 26 PRs exist, verify each PR's body equals `bodies/<theme>.md` (minus the title line)
plus `FOOTER.md`, and update any that differ. Do it in a workflow, one agent per PR, so the bodies
never enter the orchestrator's context:

  read the PR body -> compare with the file bytes (use `sed -n '3,$p'`, not a summarising read)
  -> if different, call mcp__github__update_pull_request with the corrected body.


## Verification-pass state (as of the session-limit interruption)

Round 1 checked 15 of 26 PRs; 11 failed on the session limit. Of the 15: 4 exact, 7 repaired
(#232, #234, #237, #240, #241, #242, #243), 4 flagged **unresolved** because the drift ran the
*other* way — the live PR body was newer than the file, since it carried corrections made by hand
at posting time. Those agents were right not to clobber.

Those hand-corrections have since been folded back into the files:

- `bpmn-export.md`  — the `.cabal` registrations ARE carried (spine slicing), not missing.
- `corpus-regcf.md` — 59 files; the three rerouted goldens now belong to lsp / service-cli.
- `agent-tooling.md`— the `.claude/skills` symlink redirect; "twenty-six PRs".
- `ci-build.md`     — merge-last banner; eleven files; `turbo.json` moved to wizard-regcf;
                      #167's cabal half is lang-imports-stdlib, not service-cli; the third hard
                      dependency (corpus goldens red on main); wizard-housing / wizard-regcf.

**The file on disk is authoritative from here on.** Round 2 re-verifies the 16 outstanding PRs
(the 4 unresolved + #232, which round 1 reset to the pre-correction text, + the 11 never checked).
