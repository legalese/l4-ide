#!/usr/bin/env bash
# Build one wave-2 theme branch: the wave-2 base (8af7d332, pushed as
# claude/aug2026-w2-base) + exactly this theme's slice of what unstable
# gained since. Files are taken from origin/unstable verbatim, except the
# four spine files shared between blawx and docassemble, which come from
# the reconstructions in wave2/spine/<theme>/ (see make-spine.py).
#
#   build-branch.sh <theme> <worktree> <wave2-dir>
#
# No skills redirect here, unlike wave 1: the base already carries main's
# layout, and no wave-2 file lives under .claude/skills/writing-l4-rules.
set -euo pipefail
theme=$1; wt=$2; w2=$3
BASE_REF="claude/aug2026-w2-base"
branch="claude/aug2026-w2-${theme}"
manifest="${w2}/themes/${theme}.files"
[ -f "$manifest" ] || { echo "no manifest: $manifest" >&2; exit 1; }

git -C "$wt" checkout -q -B "$branch" "origin/${BASE_REF}"
git -C "$wt" reset -q --hard "origin/${BASE_REF}"
git -C "$wt" clean -qfd

# every wave-2 file exists on unstable (no deletions in the range; verified)
tr '\n' '\0' < "$manifest" | xargs -0 -n 200 git -C "$wt" checkout origin/unstable --

# spine overlay, if this theme has one
if [ -d "${w2}/spine/${theme}" ]; then
  (cd "${w2}/spine/${theme}" && find . -type f) | while read -r f; do
    f="${f#./}"
    mkdir -p "$wt/$(dirname "$f")"
    cp "${w2}/spine/${theme}/${f}" "$wt/$f"
    git -C "$wt" add -- "$f"
  done
fi

echo "== ${theme}: $(git -C "$wt" diff --cached --numstat "origin/${BASE_REF}" | wc -l | tr -d ' ') files staged"
