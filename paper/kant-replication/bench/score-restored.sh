#!/usr/bin/env bash
# Scores the RESTORED-fixture arm: trials/restored-k10/, n up to 10 per cell,
# against bench/keys-restored.json (bench.mjs records the key per trial and
# aggregate refuses to mix keys). Safe to re-run; partial cells score as what
# they are and the aggregate prints whatever n exists.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
T="$ROOT/trials/restored-k10"
O="$ROOT/out/restored-k10"
mkdir -p "$O"

declare -A ARM=( [vanilla]=vanilla [prolog-unguided]=prolog [prolog-guided]=prolog \
                 [l4-unguided]=l4 [l4-guided]=l4 )

for cell in vanilla prolog-unguided prolog-guided l4-unguided l4-guided; do
  for d in "$T/$cell"/t*; do
    [ -d "$d" ] || continue
    # skip sandboxes whose encoder has not produced anything yet: inputs/ only
    [ -n "$(find "$d" -maxdepth 1 -type f | head -1)" ] || continue
    n="$(basename "$d")"
    node "$ROOT/bench/bench.mjs" trial \
      --arm "${ARM[$cell]}" --dir "$d" --label "restored/$cell/$n" \
      --keys "$ROOT/bench/keys-restored.json" \
      --lib "$REPO/jl4-core/libraries" \
      --out "$O/$cell-$n.json" > "$O/$cell-$n.md" 2>&1
  done
done

{
  echo "# Restored fixture — five cells against keys-restored.json"
  echo
  echo "Pre-registered in bench/PREREGISTRATION-restored.md BEFORE any of these"
  echo "trials ran. Golds equal keys.json's; what changed is their derivability."
  echo "Cells with n < 10 are partial and say so in their n column."
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
