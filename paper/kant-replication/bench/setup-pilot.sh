#!/usr/bin/env bash
# Stages one sandbox per trial. Blindness is enforced by CONSTRUCTION: the answer
# key (bench/keys.json) and the gold-bearing fixtures/queries.json are never copied
# into a trial, so an encoder cannot read them even by accident. The reference
# encodings in artifacts/ are withheld for the same reason.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K="${1:-2}"
OUT="$ROOT/trials/pilot-k2"
rm -rf "$OUT"; mkdir -p "$OUT"

for cell in vanilla prolog-unguided prolog-guided l4-unguided l4-guided; do
  for n in $(seq 1 "$K"); do
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

# Leak check. Nothing staged may carry a gold answer or a reference encoding.
# The second pattern is not paranoia: the vanilla prompt's output EXAMPLE originally
# read {"1": "No", "2": "Yes", ...}, which are the true answers to Q1 and Q2. An
# illustrative example is exactly where a key leaks without anyone meaning it to.
LEAKS=$(/usr/bin/grep -rlE '"gold"|paper_rationale|paper_results' "$OUT" 2>/dev/null || true)
LEAKS="$LEAKS $(/usr/bin/grep -rlE '"[1-9]"[[:space:]]*:[[:space:]]*"(Yes|No)"' "$OUT" 2>/dev/null || true)"
if [ -n "$(echo "$LEAKS" | tr -d '[:space:]')" ]; then
  echo "LEAK: an answer-shaped value was staged into a trial sandbox:" >&2
  echo "$LEAKS" | tr ' ' '\n' | /usr/bin/grep -v '^$' >&2
  exit 1
fi
echo "staged $(find "$OUT" -mindepth 2 -maxdepth 2 -type d | wc -l | tr -d ' ') trials under $OUT"
