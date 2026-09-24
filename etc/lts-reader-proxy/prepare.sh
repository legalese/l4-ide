#!/usr/bin/env bash
# Regenerates the three artifacts (A, B, C) for each of the four contracts in
# the §7.3 LLM-reader proxy, from an `l4` binary and the committed corpus.
# See README.md in this directory. Ground truth (truth.json) is hand-derived
# from lts.json and probes.l4 and is NOT regenerated here; the probes are
# re-run so a drifted answer shows up as a diff in probes.out.
#
#   L4=/path/to/l4 etc/lts-reader-proxy/prepare.sh
#
# Run from the repo root. Needs jq.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
L4="${L4:-l4}"
export JL4_LIBRARY_PATH="$root/jl4-core/libraries"

# Print block N (1-based) of `l4 lts` output. A block starts at a line that
# begins in column 0 and runs to the next such line; the trailing blank line
# is dropped.
lts_block() {
  awk -v want="$1" '/^[^ \t]/{b++} b==want{print}' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

# Print the one `digraph` whose graph label is $1 from `l4 state-graph` output.
dot_for() {
  awk -v want="$1" '
    /^digraph/ { n++; buf[n]=""; }
    { buf[n] = buf[n] $0 "\n"; if ($0 ~ /^ *,label=/ && !(n in lbl)) { l=$0; sub(/^ *,label=/,"",l); lbl[n]=l } }
    END { for (i=1;i<=n;i++) if (lbl[i]==want) printf "%s", buf[i] }'
}

# ---- 1. contracts.l4 / aContract, the file's own first #TRACE (line 23) ----
d="$here/contracts"; src="$root/jl4/examples/ok/contracts.l4"
"$L4" lts "$src"        | lts_block 1                          > "$d/A.txt"
"$L4" lts "$src" --json | jq '.[0]'                            > "$d/lts.json"
"$L4" state-graph "$src" | dot_for 'aContract'                 > "$d/B.dot"
"$L4" export bpmn "$src" --rule aContract                 > "$d/C.bpmn" 2>/dev/null
"$L4" export bpmn "$src" --rule aContract --fidelity-report 2>&1 >/dev/null | sed -n '/^fidelity report/,$p' > "$d/C.fidelity.txt"
"$L4" lts "$d/probes.l4" --steps                               > "$d/probes.out"

# ---- 2. every-run-example.l4 / `the tenancy` (barrier), a position the file
#         does not carry: position.l4 = the source file + one appended #TRACE ----
d="$here/every-run-example"; src="$root/doc/reference/regulative/every-run-example.l4"
{ cat "$src"; echo; cat "$d/position.trace"; } > "$d/position.l4"
"$L4" lts "$d/position.l4"        | lts_block 5                > "$d/A.txt"
"$L4" lts "$d/position.l4" --json | jq '.[4]'                  > "$d/lts.json"
"$L4" state-graph "$src" | dot_for '"the tenancy"'             > "$d/B.dot"
cp "$root/jl4/examples/bpmn/expected/tenancy-barrier.bpmn"       "$d/C.bpmn"
cp "$root/jl4/examples/bpmn/expected/tenancy-barrier.fidelity.txt" "$d/C.fidelity.txt"
# the golden is cut from jl4/examples/bpmn/tenancy.l4; prove the doc file's
# rule exports byte-identically, so C is the P1 golden for THIS rule too
"$L4" export bpmn "$src" --rule 'the tenancy' 2>/dev/null | diff -q - "$d/C.bpmn" >/dev/null \
  || { echo "every-run-example: 'the tenancy' no longer matches tenancy-barrier.bpmn" >&2; exit 1; }
"$L4" lts "$d/probes.l4" --steps                               > "$d/probes.out"

# ---- 3. tenancy.l4 / receipts (fork), at its outset via --contract ----
d="$here/tenancy"; src="$root/jl4/examples/bpmn/tenancy.l4"
"$L4" lts "$src" --contract receipts        | lts_block 1      > "$d/A.txt"
"$L4" lts "$src" --contract receipts --json | jq '.[0]'        > "$d/lts.json"
"$L4" state-graph "$src" | dot_for 'receipts'                  > "$d/B.dot"
cp "$root/jl4/examples/bpmn/expected/tenancy-fork.bpmn"          "$d/C.bpmn"
cp "$root/jl4/examples/bpmn/expected/tenancy-fork.fidelity.txt"  "$d/C.fidelity.txt"
"$L4" lts "$d/probes.l4" --steps                               > "$d/probes.out"

# ---- 4. promissory-note.l4 / `Payment Obligations`, the file's own second
#         #TRACE (line 192): one late payment, sitting in the LEST arm ----
d="$here/promissory-note"; src="$root/jl4/examples/legal/promissory-note.l4"
"$L4" lts "$src"        | lts_block 2                          > "$d/A.txt"
"$L4" lts "$src" --json | jq '.[1]'                            > "$d/lts.json"
"$L4" state-graph "$src" | dot_for '"Payment Obligations"'     > "$d/B.dot"
"$L4" export bpmn "$src" --rule 'Payment Obligations'     > "$d/C.bpmn" 2>/dev/null
"$L4" export bpmn "$src" --rule 'Payment Obligations' --fidelity-report 2>&1 >/dev/null | sed -n '/^fidelity report/,$p' > "$d/C.fidelity.txt"
"$L4" run "$d/probes.l4" 2>&1 | grep -E '^  (Range|  Message|Message)' > "$d/probes.out" || true
"$L4" lts "$d/probes.l4"                                       >> "$d/probes.out"

node "$here/build-manifest.mjs"
echo "prepared: $(ls "$here"/*/A.txt | wc -l | tr -d ' ') contracts"
