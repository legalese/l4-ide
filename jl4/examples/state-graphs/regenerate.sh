#!/usr/bin/env bash
#
# Regenerate every .dot/.svg/.png in this directory from its L4 source.
#
# These artefacts are not goldens — nothing in CI compares them to anything, so
# a change to L4.StateGraph will not fail a test if they are left stale. That
# makes them exactly the kind of file that drifts, and it is why they had a
# caption in them that the extractor had stopped emitting.
#
# It is also why they must never be hand-patched. A file edited by hand looks
# regenerated and is not, and the next person to diff it against a real run gets
# churn they cannot attribute. Run this instead, and commit what it writes.
#
# Usage:  jl4/examples/state-graphs/regenerate.sh
#
# Requires `dot` on PATH. Uses `cabal run l4` from the repo root; set L4 to
# point at an already-built binary to skip the cabal round-trip.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
cd "$root"

# Every source that contributes a diagram here. Keep in step with the table in
# README.md.
sources=(
  jl4/examples/ok/prohibition.l4
  jl4/examples/ok/contracts.l4
  jl4/experiments/actors.l4
  jl4/experiments/looping-with-recursion.l4
  jl4/experiments/patterns_and_idioms.l4
  jl4/experiments/safe-post.l4
  jl4/experiments/wedding.l4
)

run_l4() {
  if [ -n "${L4:-}" ]; then
    "$L4" "$@"
  else
    cabal run -v0 jl4:exe:l4 -- "$@"
  fi
}

written=0
for src in "${sources[@]}"; do
  if ! out=$(run_l4 state-graph "$src" 2>/dev/null) || [ -z "$out" ]; then
    echo "WARNING: $src produced no state graphs (does it still typecheck?); leaving its diagrams as they are" >&2
    continue
  fi
  # Split the stream into one file per `digraph`, named after the graph's own
  # label with spaces removed — the convention the committed filenames follow.
  n=$(printf '%s\n' "$out" | awk -v dir="$here" '
    /^digraph \{/ { body = $0 "\n"; inside = 1; next }
    inside        { body = body $0 "\n" }
    /^,?label=/   { }
    inside && /^\}$/ {
      name = ""
      split(body, lines, "\n")
      for (i in lines) {
        if (match(lines[i], /^[ \t]*,label=/)) {
          name = substr(lines[i], RSTART + RLENGTH)
          gsub(/^"|"$/, "", name)
          gsub(/ /, "", name)
        }
      }
      if (name == "") { print "UNNAMED GRAPH" > "/dev/stderr"; exit 1 }
      printf "%s", body > (dir "/" name ".dot")
      close(dir "/" name ".dot")
      count++
      inside = 0
    }
    END { print count }
  ')
  echo "$src -> $n graph(s)"
  written=$((written + n))
done

echo "regenerated $written .dot files; rendering"
for d in "$here"/*.dot; do
  b=${d%.dot}
  dot -Tsvg "$d" -o "$b.svg"
  dot -Tpng "$d" -o "$b.png"
done
echo "done. graphviz: $(dot -V 2>&1)"
