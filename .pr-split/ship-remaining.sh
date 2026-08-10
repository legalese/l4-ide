#!/usr/bin/env bash
# Ship every theme whose body is finished and whose branch has not been pushed yet.
#   ship-remaining.sh <worktree> <themes-dir> <bodies-dir> <hunks.json> <status.tsv>
set -uo pipefail
wt=$1; mdir=$2; bdir=$3; hunks=$4; status=$5
here=$(dirname "$0")

for t in $(cut -f1 "$mdir/INDEX.tsv"); do
  grep -q "^${t}	" "$status" 2>/dev/null && { echo "skip $t (already shipped)"; continue; }
  [ -f "$bdir/$t.md" ] || { echo "skip $t (no body yet)"; continue; }
  grep -q '^## Provenance' "$bdir/$t.md" || { echo "skip $t (body still drafting)"; continue; }
  if bash "$here/ship.sh" "$t" "$wt" "$mdir" "$bdir" "$hunks" 2>&1 | tail -1; then
    printf '%s\tpushed\t\n' "$t" >> "$status"
  else
    echo "FAILED $t"
  fi
done
sort -u -o "$status" "$status"
