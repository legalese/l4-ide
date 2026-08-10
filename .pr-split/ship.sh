#!/usr/bin/env bash
# Build, commit and push one theme branch.
#   ship.sh <theme> <worktree> <themes-dir> <bodies-dir> [hunks.json]
set -euo pipefail

theme=$1; wt=$2; mdir=$3; bdir=$4; hunks=${5:-}
branch="claude/aug2026-${theme}"
body="${bdir}/${theme}.md"

[ -f "$body" ] || { echo "no body for $theme" >&2; exit 1; }
title=$(head -1 "$body" | sed 's/^#\s*//')
[ -n "$title" ] || { echo "empty title for $theme" >&2; exit 1; }

bash "$(dirname "$0")/build-branch.sh" "$theme" "$wt" "$mdir"

if [ -n "$hunks" ] && [ -f "$hunks" ]; then
  node "$(dirname "$0")/apply-spine.mjs" "$theme" "$wt" "$hunks" || true
fi

# cabal.project carries two unrelated one-line edits — dropping the archived
# package and adding the new one. Each belongs with the PR that does the work,
# so neither PR leaves `cabal build all` pointing at a directory that is not there.
case "$theme" in
  actus-archive)
    sed -i '\|^  \./jl4-actus-analyzer$|d' "$wt/cabal.project"
    git -C "$wt" add -- cabal.project ;;
  proleg)
    sed -i 's|^  \./jl4-service$|  ./jl4-service\n  ./jl4-proleg|' "$wt/cabal.project"
    git -C "$wt" add -- cabal.project ;;
esac

# The housing wizard adds a workspace under the root `ts-apps/*` glob, so the
# root lockfile must learn about it or `npm ci` fails. It depends on nothing
# that is not already on main, so the lockfile can be regenerated here and the
# PR stands alone. (The Reg CF wizard cannot: it needs @repo/ladder-core, which
# arrives with the ladder-viz PR.)
if [ "$theme" = "wizard-housing" ]; then
  ( cd "$wt" && npm install --package-lock-only --engine-strict=false >/dev/null 2>&1 || true )
  git -C "$wt" add -- package-lock.json 2>/dev/null || true
fi

n=$(git -C "$wt" diff --cached --name-only origin/main | wc -l)
if [ "$n" -eq 0 ]; then echo "$theme: nothing staged, skipping" >&2; exit 1; fi

prs=$(cut -f1 "${mdir}/${theme}.prs" 2>/dev/null | grep . | paste -sd, - || true)

git -C "$wt" -c user.name="Claude" -c user.email="noreply@anthropic.com" \
  commit -q -m "$title" -m "Re-cut from the unstable integration branch for review against main.
Upstream unstable PRs folded in: ${prs:-n/a}

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_015FabdLGbnDrbNWpQfFGNtK"

for attempt in 1 2 3 4 5; do
  if git -C "$wt" push -q -u origin "$branch" --force-with-lease 2>/tmp/push-err; then
    echo "$theme: pushed $n files -> $branch"; exit 0
  fi
  cat /tmp/push-err >&2
  sleep $((2 ** attempt))
done
echo "$theme: PUSH FAILED" >&2; exit 1
