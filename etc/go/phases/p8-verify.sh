#!/usr/bin/env bash
# P8 — formal verification (STRETCH).
#
# THIS STAGE IS SCAFFOLDED AND CANNOT RUN.
#
# It exists as an entry point so the pipeline's shape is visible and so that
# asking for it yields a named blocker rather than a missing file. It is NOT a
# member of any milestone's declared stage list, so its absence cannot make a
# milestone INCOMPLETE, and it writes no receipt: a stage that did not run has
# nothing to record.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "${BASH_SOURCE[0]}"
  exit 0
fi

cat >&2 <<'MSG'
p8-verify: SCAFFOLDED AND CANNOT RUN.

WHAT IT WOULD DO
  Find loopholes, double binds, dead branches, unreachable entitlements and
  unsatisfiable rule combinations, using CPU-based techniques (SAT/BDD/model
  checking), framed as legal-drafting analysis rather than as security-
  exploit hunting.

BLOCKER
  Ruling R5 is OPEN: the toolchain is undecided between in-compiler
  exhaustiveness machinery, the query-planner ROBDD for unsat and dead-
  branch detection, and an external model checker. There is also no CLI
  footing at all — the verified command list is
  run/check/format/ast/batch/trace/state-graph/render/export/openfisca and
  none of them verifies anything. SPEC.md §5 gives P8 no component row and
  §6 gives it no pass condition, so a stage here would be pure UNVERIFIED by
  construction. P8 gates nothing in G0-G4.

Nothing was written and no receipt was recorded.
MSG
exit 3
