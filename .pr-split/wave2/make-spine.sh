#!/usr/bin/env bash
# Reconstruct each wave-2 theme's version of the four spine files shared
# between the blawx and docassemble slices, by replaying only that theme's
# per-PR patches (in first-parent merge order) onto the wave-2 base.
#
#   make-spine.sh <base-commit> <out-dir>
#
# Verification is built in: for every spine file, git merge-file of the two
# reconstructions against the base must reproduce origin/unstable's blob
# byte-for-byte, or this script fails.
set -euo pipefail
BASE=$1; OUT=$2
SPINE="jl4-core/jl4-core.cabal jl4/jl4.cabal jl4/app/Main.hs jl4/tests-cli/Main.hs"
# first-parent merges of each theme's PRs, oldest first
BLAWX="261 270 272 273 276 277 278 279 280"
DOCA="264 265 267 268 269"

merges_for() { # $1 = space-separated PR list -> merge SHAs oldest-first
  local want=" $1 "
  git log --first-parent --reverse --format='%H %s' "$BASE"..origin/unstable |
  while read -r sha subj; do
    pr=$(grep -oE '#[0-9]+' <<<"$subj" | head -1 | tr -d '#') || true
    [ -n "${pr:-}" ] && [[ "$want" == *" $pr "* ]] && echo "$sha"
  done
}

reconstruct() { # $1 theme, $2 PR list
  local theme=$1 prs=$2 idx
  idx=$(mktemp); rm -f "$idx"
  GIT_INDEX_FILE=$idx git read-tree "$BASE"
  for m in $(merges_for "$prs"); do
    for f in $SPINE; do
      if ! git diff --quiet "$m^1" "$m" -- "$f"; then
        git diff --full-index "$m^1" "$m" -- "$f" |
          GIT_INDEX_FILE=$idx git apply --cached --3way ||
          { echo "APPLY FAILED: $theme $(git log -1 --format=%s "$m") $f" >&2; exit 1; }
      fi
    done
  done
  for f in $SPINE; do
    mkdir -p "$OUT/$theme/$(dirname "$f")"
    GIT_INDEX_FILE=$idx git show ":$f" > "$OUT/$theme/$f"
  done
  rm -f "$idx"
}

reconstruct blawx "$BLAWX"
reconstruct docassemble "$DOCA"

fail=0
for f in $SPINE; do
  git show "$BASE:$f" > "$OUT/.base.tmp"
  git show "origin/unstable:$f" > "$OUT/.final.tmp"
  if git merge-file -p "$OUT/docassemble/$f" "$OUT/.base.tmp" "$OUT/blawx/$f" > "$OUT/.merged.tmp" 2>/dev/null \
     && cmp -s "$OUT/.merged.tmp" "$OUT/.final.tmp"; then
    echo "SUM OK: $f"
  else
    echo "SUM MISMATCH: $f" >&2; fail=1
  fi
done
rm -f "$OUT"/.base.tmp "$OUT"/.final.tmp "$OUT"/.merged.tmp
exit $fail
