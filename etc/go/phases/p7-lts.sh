#!/usr/bin/env bash
# P7 — the LTS (labelled-transition-system) leg.
#
# SPEC.md §5 declares the proper visualiser unbuilt and names `l4 state-graph`
# DOT via graphviz as the INTERIM. That interim exists and works, so this leg
# runs — and the interim label rides in the reason string rather than being
# quietly dropped.
#
# The oracle is a cross-check, not a presence check: `l4 state-graph` emits one
# `digraph` block per regulative rule, and the BPMN discovery call independently
# reports how many regulative rules the module has. Two different code paths in
# the compiler have to agree on that number. MEASURED 2026-08-02: 3 and 3.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "$GO_S_CORPUS" "${BASH_SOURCE[0]}" "$GO_ROOT/etc/go/lib/split-digraphs.mjs"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

DOT="$GO_OUT/$GO_S_ID.state-graph.dot"
SPLITDIR="$GO_OUT/state-graphs"
LOG="$GO_OUT/p7-lts.txt"

set +e
"$L4" state-graph "$GO_S_CORPUS" >"$DOT" 2>"$GO_OUT/p7-lts.stderr"
RC=$?
set -e
if [[ $RC -ne 0 ]]; then
  go_receipt --status NOT-BUILT \
    --reason "l4 state-graph exited $RC; it exits 1 with 'No regulative rules found in module' when a module has none" \
    --blocker "$(head -1 "$GO_OUT/p7-lts.stderr" 2>/dev/null || echo "l4 state-graph exit $RC")" \
    --artifact "$GO_OUT/p7-lts.stderr"
  exit "$GO_EXIT_FINDING"
fi

# The independent count: the BPMN discovery call.
mapfile -t RULES < <(node "$GO_LIB/discover.mjs" rules "$GO_S_CORPUS")
EXPECT=${#RULES[@]}

set +e
node "$GO_LIB/split-digraphs.mjs" "$DOT" --expect "$EXPECT" --out "$SPLITDIR" | tee "$LOG"
CROSS_RC=${PIPESTATUS[0]}
set -e

ARTS=(--artifact "$DOT" --artifact "$LOG")
for f in "$SPLITDIR"/*.dot; do [[ -f "$f" ]] && ARTS+=(--artifact "$f"); done

if [[ $CROSS_RC -ne 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "the state-graph emitted a number of digraph blocks that disagrees with the number of regulative rules the BPMN discovery call reports; see $LOG" \
    "${ARTS[@]}" --metric "expected_rules=$EXPECT"
  exit "$GO_EXIT_FINDING"
fi

# Optional: render SVG when graphviz is on the machine. Absence is named, not
# silent, and does not change the verdict — the DOT is the artifact.
SVG_NOTE="graphviz absent; DOT emitted but not rendered"
if command -v dot >/dev/null 2>&1; then
  for f in "$SPLITDIR"/*.dot; do
    dot -Tsvg "$f" -o "${f%.dot}.svg" 2>>"$LOG" || true
    [[ -f "${f%.dot}.svg" ]] && ARTS+=(--artifact "${f%.dot}.svg")
  done
  SVG_NOTE="graphviz present; each digraph also rendered to SVG"
fi

go_receipt --status PASS \
  --oracle-cmd "node etc/go/lib/split-digraphs.mjs $(basename "$DOT") --expect $EXPECT" \
  --oracle-exit 0 \
  --oracle-class structural \
  --oracle-because "the number of digraph blocks the state-graph emitter produces is cross-checked against the number of regulative rules the BPMN exporter's discovery call independently reports; two separate compiler paths agree on $EXPECT. This is stronger than 'the file is non-empty', which would be a presence oracle and could not license PASS." \
  "${ARTS[@]}" \
  --metric "digraphs=$EXPECT" \
  --metric "bytes=$(wc -c <"$DOT" | tr -d ' ')" \
  --label "INTERIM" \
  --note "INTERIM. SPEC.md §5 declares the proper LTS visualiser (the superset spec's P2 visualiser) unbuilt and names graphviz DOT as the stand-in. This PASS is a pass of the interim, not of the leg the spec ultimately wants. $SVG_NOTE."
