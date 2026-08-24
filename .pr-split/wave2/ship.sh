#!/usr/bin/env bash
# Ship one wave-2 theme: build its branch, commit with the body's H1 as
# subject, force-push with lease, and open/update a draft PR based on
# claude/aug2026-w2-base.
#
#   ship.sh <theme> <worktree>
#
# SHIP_COAUTHOR / SHIP_SESSION override the trailers.
set -euo pipefail
theme=$1; wt=$2
w2="$(cd "$(dirname "$0")" && pwd)"
body="${w2}/bodies/${theme}.md"
[ -f "$body" ] || { echo "no body: $body" >&2; exit 1; }
grep -q '^## Provenance' "$body" || { echo "body not ready (no Provenance): $body" >&2; exit 1; }

"$w2/build-branch.sh" "$theme" "$wt" "$w2"

# H1 -> commit subject; [[:space:]] not \s -- BSD sed has no \s
title=$(head -1 "$body" | sed 's/^#[[:space:]]*//')
coauthor="${SHIP_COAUTHOR:-Claude Fable 5 <noreply@anthropic.com>}"
session="${SHIP_SESSION:-aug2026 (24ca18d2-ccb5-48c4-9976-c9c12cab1ff8)}"

git -C "$wt" commit -q -m "$title" -m "$(tail -n +2 "$body" | sed -e '/^$/,$!d')" \
  -m "Co-Authored-By: ${coauthor}" -m "Claude-Session: ${session}"
branch="claude/aug2026-w2-${theme}"
git -C "$wt" push -q --force-with-lease="refs/heads/${branch}" origin "HEAD:refs/heads/${branch}"

prbody=$(mktemp)
tail -n +2 "$body" > "$prbody"
[ -f "$w2/FOOTER.md" ] && cat "$w2/FOOTER.md" >> "$prbody"
if gh pr view "$branch" --repo legalese/l4-ide --json number -q .number >/dev/null 2>&1; then
  gh pr edit "$branch" --repo legalese/l4-ide --title "$title" --body-file "$prbody"
else
  gh pr create --repo legalese/l4-ide --draft --base claude/aug2026-w2-base \
    --head "$branch" --title "$title" --body-file "$prbody"
fi
rm -f "$prbody"
