#!/usr/bin/env bash
# Scores every staged pilot trial and aggregates. Safe to re-run.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
T="$ROOT/trials/pilot-k2"
O="$ROOT/out/pilot-k2"
mkdir -p "$O"

declare -A ARM=( [vanilla]=vanilla [prolog-unguided]=prolog [prolog-guided]=prolog \
                 [l4-unguided]=l4 [l4-guided]=l4 )

for cell in vanilla prolog-unguided prolog-guided l4-unguided l4-guided; do
  for d in "$T/$cell"/t*; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    node "$ROOT/bench/bench.mjs" trial \
      --arm "${ARM[$cell]}" --dir "$d" --label "$cell/$n" \
      --lib "$REPO/jl4-core/libraries" \
      --out "$O/$cell-$n.json" > "$O/$cell-$n.md" 2>&1
  done
done

# One aggregate per language arm, plus the shared vanilla control. bench.mjs
# groups by the harness arm, which would merge guided and unguided into one row
# and hide the very contrast the factorial exists to measure — so the cells are
# aggregated separately and printed together.
{
  echo "# Pilot k=2 — 2x3 factorial, model held fixed"
  echo
  echo "Encoder: one model family across all cells. Trials are blind by construction:"
  echo "no sandbox contains the answer key (see bench/setup-pilot.sh)."
  echo
  for cell in vanilla prolog-unguided prolog-guided l4-unguided l4-guided; do
    files=("$O/$cell"-t*.json)
    [ -e "${files[0]}" ] || continue
    echo "## $cell"
    echo
    node "$ROOT/bench/bench.mjs" aggregate "${files[@]}" | tail -n +2
    echo
  done
} > "$O/AGGREGATE.md"

echo "wrote $O/AGGREGATE.md"
grep -H "Key A" "$O"/*.md | sed "s|$O/||"
