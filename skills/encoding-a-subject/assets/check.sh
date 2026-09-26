#!/usr/bin/env bash
# Run every .l4 module in an encoding and print, per module, the three numbers
# that matter: error diagnostics, assertions satisfied, assertions failed.
#
# Why not trust the exit code: `l4 run` exits 0 when an #ASSERT fails. The
# failure is a DiagnosticSeverity_Error line whose message is "assertion failed".
# An encoding that "ran green" by exit code can be carrying failed assertions.
#
# Usage:  check.sh [DIR]          (DIR defaults to the directory this script is in)
# Env:    L4   the l4 binary      (default: `l4` on PATH)
#
# Exit status: 0 only when every module has zero errors and zero failed assertions.
set -u
DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
L4="${L4:-l4}"

if ! command -v "$L4" >/dev/null 2>&1; then
  echo "check.sh: no l4 binary at '$L4'. Set L4=/path/to/l4 or put l4 on PATH." >&2
  exit 2
fi

total_err=0 total_ok=0 total_bad=0 n=0
printf '%-40s %7s %9s %7s\n' module errors satisfied failed
for f in "$DIR"/*.l4; do
  [ -e "$f" ] || { echo "check.sh: no .l4 files in $DIR" >&2; exit 2; }
  out="$("$L4" run "$f" 2>&1)"
  err=$(printf '%s\n' "$out" | grep -c 'DiagnosticSeverity_Error')
  ok=$(printf '%s\n' "$out" | grep -cE '^[[:space:]]*Message:[[:space:]]+assertion satisfied')
  bad=$(printf '%s\n' "$out" | grep -cE '^[[:space:]]*Message:[[:space:]]+assertion failed')
  printf '%-40s %7d %9d %7d\n' "$(basename "$f")" "$err" "$ok" "$bad"
  total_err=$((total_err + err)) total_ok=$((total_ok + ok)) total_bad=$((total_bad + bad)) n=$((n + 1))
done
printf '%-40s %7d %9d %7d\n' "TOTAL ($n modules)" "$total_err" "$total_ok" "$total_bad"
echo "(a failed assertion also counts as an error; errors minus failed = everything else)"
[ "$total_err" -eq 0 ] && [ "$total_bad" -eq 0 ]
