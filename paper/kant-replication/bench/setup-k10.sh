#!/usr/bin/env bash
# Stages trials t3..t10 for the full k=10 run, POOLING with the k=2 pilot: the
# pilot's t1/t2 (trials/pilot-k2/) are the first two trials of each cell and are
# not restaged or touched here. Same staging logic and same leak check as
# setup-pilot.sh; the only differences are the output root and the trial range.
#
# Pooling is legitimate because the only staged input that changed since the
# pilot is schema-l4.md, and that repair was syntactic — same 18 fields, same
# order, same helper semantics (README.md §5.2). Blindness is enforced by
# CONSTRUCTION: the answer key (bench/keys.json) and the gold-bearing
# fixtures/queries.json are never copied into a trial.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FROM=3; TO=10
OUT="$ROOT/trials/k10"
rm -rf "$OUT"; mkdir -p "$OUT"

for cell in vanilla prolog-unguided prolog-guided l4-unguided l4-guided; do
  for n in $(seq "$FROM" "$TO"); do
    d="$OUT/$cell/t$n/inputs"; mkdir -p "$d"
    cp "$ROOT/fixtures/chubb-policy.txt"  "$d/"
    cp "$ROOT/fixtures/queries-blind.md"  "$d/"
    cp "$ROOT/prompts/cell-$cell.md"      "$d/TASK.md"
    case "$cell" in
      prolog-guided) cp "$ROOT/bench/schema-prolog.md" "$d/schema.md" ;;
      l4-guided)     cp "$ROOT/bench/schema-l4.md"     "$d/schema.md" ;;
    esac
  done
done

# Leak check, identical to setup-pilot.sh. The second pattern is not paranoia:
# the vanilla prompt's output EXAMPLE originally read {"1": "No", "2": "Yes", ...},
# which are the true answers to Q1 and Q2.
LEAKS=$(/usr/bin/grep -rlE '"gold"|paper_rationale|paper_results' "$OUT" 2>/dev/null || true)
LEAKS="$LEAKS $(/usr/bin/grep -rlE '"[1-9]"[[:space:]]*:[[:space:]]*"(Yes|No)"' "$OUT" 2>/dev/null || true)"
if [ -n "$(echo "$LEAKS" | tr -d '[:space:]')" ]; then
  echo "LEAK: an answer-shaped value was staged into a trial sandbox:" >&2
  echo "$LEAKS" | tr ' ' '\n' | /usr/bin/grep -v '^$' >&2
  exit 1
fi
echo "staged $(find "$OUT" -mindepth 2 -maxdepth 2 -type d | wc -l | tr -d ' ') trials under $OUT"
