#!/usr/bin/env bash
# P7 — the dmnmd (markdown decision table) leg.
#
# PROJECTIONS.md calls this "the most honest artifact in the set and the least
# useful one, which is why it ships". Its status is DEGRADED by construction:
# the whole corpus collapses into one markdown table plus a long loss report,
# and there is no engine that executes markdown, so `execution` is not a class
# this leg can ever reach. The differential oracle against the committed golden
# is real; the artifact's usefulness is not what it measures.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "$GO_CORPUS" "${BASH_SOURCE[0]}" \
    "$GO_ROOT/jl4/examples/dmn/expected/regcf-corpus.dmn.md" \
    "$GO_ROOT/jl4/examples/dmn/expected/regcf-corpus.md.fidelity.txt" \
    "$GO_ROOT/etc/go/lib/canon-diff.mjs"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

OUT="$GO_OUT/regcf-corpus.dmn.md"
GOLDEN="$GO_ROOT/jl4/examples/dmn/expected/regcf-corpus.dmn.md"
GOLDEN_FID="$GO_ROOT/jl4/examples/dmn/expected/regcf-corpus.md.fidelity.txt"
DIFFLOG="$GO_OUT/p7-dmn-md.canon-diff.txt"

set +e
"$L4" export "$GO_CORPUS" --to dmn-md -o "$OUT" --fidelity-report 2>"$GO_OUT/p7-dmn-md.fidelity.stderr"
RC=$?
set -e
[[ $RC -eq 0 ]] || go_broken "l4 export --to dmn-md exited $RC on a module that typechecks"
cat "$GO_OUT/p7-dmn-md.fidelity.stderr"

# `-o out.dmn.md --fidelity-report` writes the sibling report next to it.
FID="$GO_OUT/regcf-corpus.md.fidelity.txt"
[[ -f "$FID" ]] || FID="$GO_OUT/regcf-corpus.dmn.fidelity.txt"

set +e
L4_GO_SOURCE_BASENAME="$(basename "$GO_CORPUS")" node "$GO_LIB/canon-diff.mjs" "$OUT" "$GOLDEN" --report "$DIFFLOG"
DIFF_RC=$?
set -e

read -r BLOCKING LOSSY ADVISORY < <(node "$GO_LIB/fidelity-counts.mjs" "$FID")

ARTS=(--artifact "$OUT" --artifact "$DIFFLOG")
[[ -f "$FID" ]] && ARTS+=(--artifact "$FID")

if [[ $DIFF_RC -ne 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "the regenerated dmnmd does not match the committed golden after declared canonicalisation; see $DIFFLOG" \
    "${ARTS[@]}" --metric "blocking=$BLOCKING" --metric "lossy=$LOSSY" --metric "advisory=$ADVISORY"
  exit "$GO_EXIT_FINDING"
fi

go_receipt --status DEGRADED \
  --reason "the dmnmd regenerates identically to the committed golden, and the artifact is lossy by construction: the whole corpus becomes ONE markdown table, with $BLOCKING blocking / $LOSSY lossy / $ADVISORY advisory findings recorded alongside. There is no engine that executes markdown, so this leg can never reach the 'execution' oracle class. It ships as an honesty exhibit, not as a runnable projection." \
  "${ARTS[@]}" \
  --metric "blocking=$BLOCKING" --metric "lossy=$LOSSY" --metric "advisory=$ADVISORY" \
  --metric "canonicalisations=D1-golden-runner-source-uri" \
  --note "the differential oracle passed; DEGRADED is a statement about the notation's carrying capacity, not about this run"
