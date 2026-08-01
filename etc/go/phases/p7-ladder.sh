#!/usr/bin/env bash
# P7 — the ladder-diagram leg.
#
# There is no `l4 ladder` and no `--to ladder`. The generator is a TypeScript
# entry point: `npm run demo:regcf` in ts-shared/ladder-svg, which drives a live
# jl4-lsp. Set JL4_LSP_CMD to a prebuilt jl4-lsp; this orchestrator never builds.
#
# The oracle is drift, not existence. `npm run demo:regcf` writes into the
# committed figures directory, so after it runs, a non-empty `git diff` over
# jl4/examples/legal/regcf/figures/ means the committed figures were STALE —
# which is a FAIL, never a pass. The run never commits and never stages.
# (turbo's own test/regcf-figures.test.ts is a one-directional drift guard by
# its header's own admission, so it cannot serve as the pass oracle.)

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "$GO_CORPUS" "${BASH_SOURCE[0]}" \
    "$GO_ROOT/ts-shared/ladder-svg/demo/regcf.ts" \
    "$GO_ROOT/ts-shared/ladder-svg/package.json"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

FIGURES="jl4/examples/legal/regcf/figures"
LOG="$GO_OUT/p7-ladder.txt"
DIFFOUT="$GO_OUT/p7-ladder.figure-diff.txt"

command -v npm >/dev/null 2>&1 || go_skip "npm is not on PATH; the ladder generator is an npm script (ts-shared/ladder-svg: npm run demo:regcf), not an l4 subcommand"

if [[ -z "${JL4_LSP_CMD:-}" ]]; then
  go_skip "JL4_LSP_CMD is unset. The ladder generator drives a live jl4-lsp and this orchestrator never runs cabal (CLAUDE.md §2.1, the build lock). Point JL4_LSP_CMD at a prebuilt jl4-lsp — sibling worktrees carry one at dist-newstyle/build/<arch>/ghc-9.10.3/jl4-lsp-0.1/x/jl4-lsp/build/jl4-lsp/jl4-lsp."
fi

# The tree must be clean over figures/ BEFORE we start, or the drift oracle is
# measuring somebody else's edit.
PRE_DIRTY="$(git -C "$GO_ROOT" status --porcelain -- "$FIGURES" || true)"
if [[ -n "$PRE_DIRTY" ]]; then
  go_receipt --status UNVERIFIED \
    --reason "the figures directory already had uncommitted changes before this stage ran, so a post-run diff cannot distinguish generator drift from a pre-existing local edit. Commit or stash $FIGURES and re-run." \
    --artifact "$GO_CORPUS"
  exit "$GO_EXIT_FINDING"
fi

set +e
(cd "$GO_ROOT/ts-shared/ladder-svg" && JL4_LSP_CMD="$JL4_LSP_CMD" npm run demo:regcf) >"$LOG" 2>&1
GEN_RC=$?
set -e
tail -5 "$LOG" || true

if [[ $GEN_RC -ne 0 ]]; then
  # Distinguish "this machine lacks a tool" from "the generator objected".
  # Skip is not fail, and treating a missing dev dependency as a finding about
  # the corpus is precisely the confusion etc/kie-dmn-check/run.sh's skip()/
  # broken() split exists to prevent.
  if grep -qE 'command not found|ENOENT|code 127|Cannot find module' "$LOG"; then
    go_skip "the ladder generator's toolchain is not installed in this checkout — $(grep -m1 -oE '(tsx: command not found|code 127|Cannot find module.*)' "$LOG" || echo "see $LOG"). Run 'npm ci' at the repo root first; the generator is 'tsx demo/regcf.ts' and tsx is a workspace devDependency." \
      --artifact "$LOG"
  fi
  go_receipt --status DEGRADED \
    --reason "npm run demo:regcf exited $GEN_RC; see $LOG" \
    --artifact "$LOG"
  exit "$GO_EXIT_FINDING"
fi

git -C "$GO_ROOT" diff --stat -- "$FIGURES" >"$DIFFOUT" 2>&1 || true
git -C "$GO_ROOT" status --porcelain -- "$FIGURES" >>"$DIFFOUT" 2>&1 || true
DRIFT="$(git -C "$GO_ROOT" status --porcelain -- "$FIGURES" || true)"

ARTS=(--artifact "$LOG" --artifact "$DIFFOUT")
for f in "$GO_ROOT/$FIGURES"/*.svg; do [[ -f "$f" ]] && ARTS+=(--artifact "$f"); done

if [[ -n "$DRIFT" ]]; then
  go_receipt --status DEGRADED \
    --reason "regenerating the ladder figures changed committed files, so the figures in the tree were STALE relative to regcf.l4. See $DIFFOUT. This orchestrator does not commit; regenerate and commit the figures in their own change." \
    "${ARTS[@]}"
  exit "$GO_EXIT_FINDING"
fi

go_receipt --status PASS \
  --oracle-cmd "JL4_LSP_CMD=… npm run demo:regcf && git diff --quiet -- $FIGURES" \
  --oracle-exit 0 \
  --oracle-class differential \
  --oracle-because "the committed SVG figures were regenerated from the current regcf.l4 and reproduced byte for byte; a non-empty diff would mean the committed figures were stale, which this leg treats as a FAIL and never as a pass" \
  "${ARTS[@]}" \
  --note "the generator writes into the committed figures directory; this stage never commits and never stages"
