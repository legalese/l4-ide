#!/usr/bin/env bash
# Scores the POOLED k=10 set: the k=2 pilot's t1/t2 (trials/pilot-k2/) plus the
# k=10 top-up's t3..t10 (trials/k10/), n=10 per cell. Safe to re-run; every
# trial is re-scored from its committed artifacts, so this also re-verifies the
# pilot numbers rather than trusting a stale out/ directory. (The on-disk
# out/pilot-k2/AGGREGATE.md was once a mid-run snapshot that showed prolog-guided
# at 0/2 — scored before those trials had landed. Re-scoring from artifacts is
# the defence against ever quoting such a snapshot.)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
O="$ROOT/out/k10"
mkdir -p "$O"

declare -A ARM=( [vanilla]=vanilla [prolog-unguided]=prolog [prolog-guided]=prolog \
                 [l4-unguided]=l4 [l4-guided]=l4 )

for cell in vanilla prolog-unguided prolog-guided l4-unguided l4-guided; do
  for d in "$ROOT/trials/pilot-k2/$cell"/t* "$ROOT/trials/k10/$cell"/t*; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    node "$ROOT/bench/bench.mjs" trial \
      --arm "${ARM[$cell]}" --dir "$d" --label "$cell/$n" \
      --lib "$REPO/jl4-core/libraries" \
      --out "$O/$cell-$n.json" > "$O/$cell-$n.md" 2>&1
  done
done

# One aggregate per cell. bench.mjs groups by harness arm, which would merge
# guided and unguided into one row and hide the factorial's contrast, so the
# cells are aggregated separately and printed together.
{
  echo "# k = 10 — 2x3 factorial, model held fixed, pooled with the k=2 pilot"
  echo
  echo "n = 10 per cell: trials t1/t2 are the 2026-08-31 pilot, t3..t10 the"
  echo "2026-09-01 top-up. Pooling is legitimate because the only staged input"
  echo "that changed between the two is schema-l4.md, and that repair was"
  echo "syntactic (README.md §5.2). Encoder: one model family across all cells."
  echo "Trials are blind by construction: no sandbox contains the answer key."
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
grep -H "Key A" "$O"/*-t*.md 2>/dev/null | sed "s|$O/||" | sort
