#!/usr/bin/env bash
# P4 — ambiguity forks and TYPICALLY defaults (de novo path).
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
p4-forks: SCAFFOLDED AND CANNOT RUN.

WHAT IT WOULD DO
  Open a fork for each ambiguous reading, register the source text each fork
  interprets, cross-reference P2's register so an authority-settled reading
  carries its resolution, and preload TYPICALLY defaults where world
  knowledge supports one.

BLOCKER
  Ruling R4 is OPEN. The design note R4-FORK-REPRESENTATION.md proposes the
  shape and its §6 says explicitly that no code changes until the demo's
  encode phase runs. Separately, SPEC.md defines no machine-readable fork
  register anywhere, so P5's fork-register completeness check has nothing to
  join over. specs/todo/single-instruction-demo/schemas/fork-register.schema
  .json does NOT exist: that directory is empty, and this blocker used to
  claim the schema shipped.

Nothing was written and no receipt was recorded.
MSG
exit 3
