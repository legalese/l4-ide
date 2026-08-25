#!/usr/bin/env bash
# P7 — the web-wizard leg.
#
# There is no `l4 wizard`. `l4 render FILE --format plan` is the closest
# reachable surface, and it is NOT the interview query plan: it emits a
# disposition/reachability plan (which units are inline, which are reachable).
# The interview plan lives behind a running jl4-service's /query-plan.
#
# So the oracle available here is well-formedness — the JSON parses — which
# etc/go/lib/verdict.mjs bars from PASS by construction. That is the correct
# outcome: "the plan parses" is not "the wizard asks the right questions".

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "$GO_S_WIZARD" "${BASH_SOURCE[0]}" "$GO_S_KNOWN_DEFECTS"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

PLAN="$GO_OUT/$(basename "$GO_S_WIZARD" .l4).plan.json"
LOG="$GO_OUT/p7-wizard.txt"

set +e
"$L4" render "$GO_S_WIZARD" --format plan -o "$PLAN" --fixed-now "$GO_FIXED_NOW" >"$LOG" 2>&1
RC=$?
set -e
[[ $RC -eq 0 ]] || go_broken "l4 render --format plan exited $RC on a module that typechecks"

# Well-formedness, plus the measured defect list as negative controls. A known
# defect that STOPS reproducing is a BROKEN verdict with an ::error:: telling you
# to delete the entry — house convention 4, every positive control ships a
# negative sibling.
set +e
node "$GO_LIB/known-defects.mjs" wizard "$PLAN" >>"$LOG" 2>&1
DEFECT_RC=$?
set -e
cat "$LOG"

case $DEFECT_RC in
  4)
    echo "::error::a defect recorded in $GO_S_KNOWN_DEFECTS no longer reproduces. Delete the entry; a stale negative control is a lie about what this leg measures." >&2
    go_broken "a known-defect negative control stopped reproducing; see $LOG"
    ;;
  2) go_broken "known-defects.mjs usage error" ;;
esac

# Count what the plan actually offers the interview. MEASURED 2026-08-02: 406
# units and zero `asks`. The count is read out of the artifact, never typed.
read -r UNITS ASKS < <(node "$GO_LIB/plan-shape.mjs" "$PLAN")

go_receipt --status DEGRADED \
  --reason "l4 render --format plan produced a well-formed plan over $UNITS units, and it is NOT the interview query plan the wizard leg needs: it is a disposition/reachability plan (which units inline, which are reachable), with $ASKS populated 'asks' arrays. The interview plan is served by a running jl4-service, which no l4 subcommand reaches. The strongest oracle available here is well-formedness, which etc/go/lib/verdict.mjs bars from PASS on purpose: 'the plan parses' is not 'the wizard asks the right questions'." \
  --artifact "$PLAN" --artifact "$LOG" \
  --metric "units=$UNITS" --metric "populated_asks=$ASKS" \
  --note "SPEC.md §P7 names a query-planner interview; no CLI entry point for it exists (there is no l4 wizard and no --to wizard)"
