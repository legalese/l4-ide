#!/usr/bin/env bash
# P5 — the adversarial gate (de novo path).
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
p5-gate: SCAFFOLDED AND CANNOT RUN.

WHAT IT WOULD DO
  Run the five adversarial checks over the de novo encoding and its fork
  register, and refuse to start projection work until they are satisfied.

BLOCKER
  SPEC.md §4's P5 stage states this gate's condition EXPLICITLY as a
  judgement — 'independent adversarial review is satisfied the encoding is
  as good as it can be'. Two of its five checks are automatable and already run inside
  p3-check.sh (house style, temporal closure); the other three — isomorphism
  spot-checks, fork-register completeness, and disposition of every P2 entry
  — are not mechanisable, and two of them are joins over registers whose
  format does not exist yet. A script cannot hold this gate; the skill's P5
  checklist and HG1 do.

Nothing was written and no receipt was recorded.
MSG
exit 3
