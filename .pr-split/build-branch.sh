#!/usr/bin/env bash
# Build one theme branch: main + exactly this theme's slice of unstable.
#
#   build-branch.sh <theme> <worktree> <manifest-dir>
#
# Files present on unstable are taken from unstable verbatim; files unstable
# deleted are deleted here too. Nothing else on main is touched.
set -euo pipefail

theme=$1
wt=$2
mdir=$3
branch="claude/aug2026-${theme}"
manifest="${mdir}/${theme}.files"

[ -f "$manifest" ] || { echo "no manifest: $manifest" >&2; exit 1; }

git -C "$wt" checkout -q -B "$branch" origin/main
git -C "$wt" reset -q --hard origin/main
git -C "$wt" clean -qfd

# Partition the manifest into "exists on unstable" and "deleted by unstable".
take=$(mktemp) ; drop=$(mktemp)
trap 'rm -f "$take" "$drop"' EXIT
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if git -C "$wt" cat-file -e "origin/unstable:$f" 2>/dev/null; then
    printf '%s\n' "$f" >> "$take"
  else
    printf '%s\n' "$f" >> "$drop"
  fi
done < "$manifest"

# `.claude/skills/writing-l4-rules` is a symlink on main pointing at
# `skills/writing-l4-rules`; on unstable it is a real directory. Redirect the
# content to main's canonical location instead of fighting the symlink.
redirect=$(mktemp); : > "$redirect"
if grep -q '^\.claude/skills/writing-l4-rules/' "$take" 2>/dev/null; then
  grep '^\.claude/skills/writing-l4-rules/' "$take" > "$redirect"
  grep -v '^\.claude/skills/writing-l4-rules/' "$take" > "$take.tmp" || true
  mv "$take.tmp" "$take"
fi

if [ -s "$take" ]; then
  # xargs in chunks: the manifests run to hundreds of paths.
  xargs -a "$take" -d '\n' -n 200 git -C "$wt" checkout origin/unstable --
fi

while IFS= read -r f; do
  [ -z "$f" ] && continue
  dest="skills/writing-l4-rules/${f#.claude/skills/writing-l4-rules/}"
  mkdir -p "$wt/$(dirname "$dest")"
  git -C "$wt" show "origin/unstable:$f" > "$wt/$dest"
  git -C "$wt" add -- "$dest"
done < "$redirect"
rm -f "$redirect"

if [ -s "$drop" ]; then
  xargs -a "$drop" -d '\n' -n 200 git -C "$wt" rm -q -r --ignore-unmatch --
fi

echo "== ${theme}: $(git -C "$wt" diff --cached --numstat origin/main | wc -l) files staged"
