#!/usr/bin/env bash
# Stages the RESTORED-fixture arm: trials t1..t10 per cell under
# trials/restored-k10/. Same staging logic and leak check as setup-k10.sh; the
# treatment differences are exactly two, both declared in
# bench/PREREGISTRATION-restored.md:
#   - the fixture is fixtures/chubb-policy-restored.txt, staged under the SAME
#     in-sandbox name (chubb-policy.txt) so every cell prompt stays byte-identical;
#   - guided cells receive the schema-restored-* vocabulary (21 fields).
# Blindness is enforced by CONSTRUCTION: neither keys.json nor keys-restored.json
# nor the gold-bearing fixtures/queries.json is ever copied into a trial.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FROM="${1:-1}"; TO="${2:-10}"
OUT="$ROOT/trials/restored-k10"
mkdir -p "$OUT"

for cell in vanilla prolog-unguided prolog-guided l4-unguided l4-guided; do
  for n in $(seq "$FROM" "$TO"); do
    d="$OUT/$cell/t$n/inputs"
    [ -d "$d" ] && continue   # never restage an existing trial
    mkdir -p "$d"
    cp "$ROOT/fixtures/chubb-policy-restored.txt" "$d/chubb-policy.txt"
    cp "$ROOT/fixtures/queries-blind.md"          "$d/"
    cp "$ROOT/prompts/cell-$cell.md"              "$d/TASK.md"
    case "$cell" in
      prolog-guided) cp "$ROOT/bench/schema-restored-prolog.md" "$d/schema.md" ;;
      l4-guided)     cp "$ROOT/bench/schema-restored-l4.md"     "$d/schema.md" ;;
    esac
  done
done

# Leak check, identical in spirit to setup-k10.sh.
LEAKS=$(/usr/bin/grep -rlE '"gold"|paper_rationale|paper_results' "$OUT" 2>/dev/null || true)
LEAKS="$LEAKS $(/usr/bin/grep -rlE '"[1-9]"[[:space:]]*:[[:space:]]*"(Yes|No)"' "$OUT" 2>/dev/null || true)"
if [ -n "$(echo "$LEAKS" | tr -d '[:space:]')" ]; then
  echo "LEAK: an answer-shaped value was staged into a trial sandbox:" >&2
  echo "$LEAKS" | tr ' ' '\n' | /usr/bin/grep -v '^$' >&2
  exit 1
fi
echo "staged $(find "$OUT" -mindepth 2 -maxdepth 2 -type d | wc -l | tr -d ' ') trials under $OUT"
