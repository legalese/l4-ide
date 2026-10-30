#!/usr/bin/env bash
#
# Export every L4 file under the given roots with `l4 export dmn`, and say what
# happened to each. Called by run.sh --corpus; usable alone:
#
#   etc/dmn-check/export-corpus.sh <l4> <outdir> <root> [<root> ...]
#
# Considers every *.l4 under each root, except:
#   * anything below a `not-ok` directory: negative fixtures, written to be refused;
#   * *.evaldiff.l4 (CLAUDE.md section 3.2.1: scratch files the round-trip leaves).
# `tests` directories are NOT skipped. They hold the goldens, but jl4/examples/legal/tests
# also holds a real corpus file, imaginary-alcohol-act.l4, which exports; an earlier
# version of this script skipped every `tests` directory and lost it.
# The jl4-core/libraries preludes and doc/ examples are not under jl4/examples and
# are not swept unless a root names them.
#
# "DMN-exportable" means exactly this: `l4 export dmn FILE` exited 0 and wrote a
# non-empty file containing `<definitions`. Everything else is counted, with a
# reason, so that the files dmn-check never saw are as visible as the ones it did.
#
# Writes under <outdir>:
#   dmn/<path of the .l4, .l4 replaced by .dmn>   one per exported file
#   dmn/<same path, .fidelity.txt for .dmn>       what the exporter itself says it lost,
#                                                 to read a dmn-check finding against
#   exported.txt                                  those paths, sorted, one per line
#   export-status.tsv                             src, status, exit, seconds, reason
# and prints a summary. Status is one of
#   exported   exit 0, a non-empty file with <definitions>
#   refused    non-zero exit; the reason is the last non-blank line of stderr, or
#              "no output on stderr" when there is none (a crash, a kill, a silent exit 1)
#   timeout    killed after DMN_CHECK_EXPORT_TIMEOUT seconds (default 180)
#   empty      exit 0 but no <definitions> (the exporter wrote nothing usable)
set -euo pipefail

if [ "${1:-}" = "--one" ]; then
  # internal: export-corpus.sh --one <l4> <outdir> <timeout> <src.l4>
  l4bin="$2"; outdir="$3"; tmo="$4"; src="$5"
  rel="${src#./}"
  dest="$outdir/dmn/${rel%.l4}.dmn"
  mkdir -p "${dest%/*}"
  start=$SECONDS
  set +e
  perl -e 'alarm shift; exec @ARGV or exit 127' "$tmo" \
    "$l4bin" export dmn "$src" -o "$dest" --fidelity-report > /dev/null 2> "$dest.err"
  rc=$?
  set -e
  secs=$((SECONDS - start))
  if [ "$rc" = 142 ] || [ "$rc" = 124 ]; then
    status=timeout; reason="killed after ${tmo}s"
  elif [ "$rc" = 0 ]; then
    if [ -s "$dest" ] && grep -q '<definitions' "$dest"; then
      status=exported; reason=""
    else
      status=empty; reason="exit 0 but no <definitions> in the output"
    fi
  else
    status=refused
    # The refusal is the LAST non-blank line of stderr. The first lines can be the
    # engine's own diagnostics dump (measured: 13 of 85 refusals on 2026-10-30
    # begin with a multi-line `Info | updateFileDiagnostics` block), and the
    # exporter says why it stopped last.
    # grep exits 1 on an empty file, which under pipefail would kill this child
    # before its printf and lose the row: an l4 that segfaults, is OOM-killed or
    # exits 1 silently writes nothing to stderr.
    reason="$({ grep -v '^[[:space:]]*$' "$dest.err" || true; } | tail -1 | tr '\t' ' ' | cut -c1-200)"
    reason="${reason:-no output on stderr (exit $rc)}"
  fi
  if [ "$status" != exported ]; then rm -f "$dest"; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$src" "$status" "$rc" "$secs" "$reason"
  exit 0
fi

l4bin="${1:?usage: export-corpus.sh <l4> <outdir> <root>...}"
outdir="${2:?usage: export-corpus.sh <l4> <outdir> <root>...}"
shift 2
[ $# -gt 0 ] || { echo "export-corpus.sh: no root given" >&2; exit 2; }
jobs="${DMN_CHECK_JOBS:-4}"
tmo="${DMN_CHECK_EXPORT_TIMEOUT:-180}"
here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

mkdir -p "$outdir"
list="$outdir/considered.txt"
: > "$list"
for root in "$@"; do
  [ -d "$root" ] || { echo "export-corpus.sh: $root is not a directory" >&2; exit 2; }
  # -prune below the root, not -not -path: a root that is itself a not-ok directory,
  # named on purpose, is swept.
  find "$root" -mindepth 1 \( -type d -name not-ok -prune \) \
    -o -type f -name '*.l4' -not -name '*.evaldiff.l4' -print >> "$list"
done
LC_ALL=C sort -u -o "$list" "$list"
n="$(wc -l < "$list" | tr -d ' ')"
echo "# considering $n .l4 file(s); exporting with up to $jobs job(s), ${tmo}s each" >&2

status="$outdir/export-status.tsv"
printf 'src\tstatus\texit\tseconds\treason\n' > "$status"
# The IMPORT resolution is relative to each file, so the exporter runs from the
# directory the caller is in and the .l4 path is passed as given.
tr '\n' '\0' < "$list" \
  | xargs -0 -n 1 -P "$jobs" "$here/export-corpus.sh" --one "$l4bin" "$outdir" "$tmo" \
  >> "$status" || true
# A child that dies before its printf leaves no row, and a missing row is a file
# the summary would silently not count. Say so, and name the cause.
rows=$(( $(wc -l < "$status") - 1 ))
if [ "$rows" != "$n" ]; then
  echo "export-corpus.sh: $rows status row(s) for $n file(s); a child died before recording its row" >&2
  exit 1
fi
# xargs -P interleaves nothing within a line (each child writes one printf), but
# the order is arrival order; sort for a stable file.
{ head -1 "$status"; tail -n +2 "$status" | LC_ALL=C sort; } > "$status.sorted"
mv "$status.sorted" "$status"

awk -F'\t' 'NR > 1 && $2 == "exported" { sub(/\.l4$/, ".dmn", $1); sub(/^\.\//, "", $1); print d "/dmn/" $1 }' \
  d="$outdir" "$status" > "$outdir/exported.txt"
LC_ALL=C sort -o "$outdir/exported.txt" "$outdir/exported.txt"

echo
echo "EXPORT SUMMARY (l4 export dmn over $n file(s))"
awk -F'\t' 'NR > 1 { c[$2]++ } END { for (k in c) printf "  %-9s %6d\n", k, c[k] }' "$status" | LC_ALL=C sort
echo "  refusals by reason (last line of stderr, numbers and quoted names flattened):"
awk -F'\t' 'NR > 1 && $2 != "exported" { r = $5; gsub(/[0-9]+/, "N", r); gsub(/\x27[^\x27]*\x27/, "\x27..\x27", r); gsub(/`[^`]*`/, "`..`", r); c[$2 ": " substr(r, 1, 110)]++ }
            END { for (k in c) printf "  %6d  %s\n", c[k], k }' "$status" | LC_ALL=C sort -rn | head -25 || true
# (head closing the pipe early would hand sort a SIGPIPE, which pipefail reports as a failure.)
