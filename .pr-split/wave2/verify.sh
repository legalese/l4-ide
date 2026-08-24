#!/usr/bin/env bash
# Post-ship verification of the wave-2 branches. For each theme:
#   1. every manifest file's blob on the branch == origin/unstable's blob
#   2. each spine file's blob == the committed reconstruction for that theme
#   3. the branch touches NOTHING beyond manifest + spine (no strays)
# And globally: the union of manifests + the 4 spine paths == the full range diff.
set -euo pipefail
w2="$(cd "$(dirname "$0")" && pwd)"
BASE=origin/claude/aug2026-w2-base
SPINE="jl4-core/jl4-core.cabal jl4/jl4.cabal jl4/app/Main.hs jl4/tests-cli/Main.hs"
fail=0
blob() { git rev-parse -q --verify "$1:$2" 2>/dev/null || echo MISSING; }

for mf in "$w2"/themes/*.files; do
  theme=$(basename "$mf" .files)
  br="origin/claude/aug2026-w2-${theme}"
  git rev-parse -q --verify "$br" >/dev/null || { echo "NO BRANCH: $theme"; fail=1; continue; }
  n=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ "$(blob "$br" "$f")" = "$(blob origin/unstable "$f")" ] || { echo "BLOB MISMATCH: $theme $f"; fail=1; }
    n=$((n+1))
  done < "$mf"
  spine_n=0
  if [ -d "$w2/spine/$theme" ]; then
    for f in $SPINE; do
      want=$(git hash-object "$w2/spine/$theme/$f")
      [ "$(blob "$br" "$f")" = "$want" ] || { echo "SPINE MISMATCH: $theme $f"; fail=1; }
      spine_n=$((spine_n+1))
    done
  fi
  touched=$(git diff --name-only "$BASE" "$br" | wc -l | tr -d ' ')
  expect=$((n + spine_n))
  [ "$touched" = "$expect" ] || { echo "STRAYS: $theme touches $touched, manifest+spine = $expect"; fail=1; }
  echo "ok: $theme ($n files + $spine_n spine, no strays)"
done

cat "$w2"/themes/*.files > /tmp/w2union.$$
printf '%s\n' $SPINE >> /tmp/w2union.$$
if diff <(sort /tmp/w2union.$$) <(git diff --name-only 8af7d332 origin/unstable | sort) >/dev/null; then
  echo "ok: closure — union of manifests + spine == range diff"
else
  echo "CLOSURE BROKEN"; fail=1
fi
rm -f /tmp/w2union.$$
exit $fail
