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

NO LONGER BLOCKING (was, until 2026-08-02)
  R4 is ruled: R4-FORK-REPRESENTATION.md §7 adopts the Interpretation-
  parameter shape, extended to regulative rules. The register format now
  exists:
    specs/todo/single-instruction-demo/schemas/fork-register.schema.json
  with a validator (etc/go/lib/register-validate.mjs fork-register <file>
  [peers]) and worked fixtures under schemas/fixtures/ -- the valid one
  being the BNA smoke's twelve ambiguities transcribed. R4's 1:1 map (a
  materialised fork IS an Interpretation field) is enforced, as is the
  cross-reference into P2's register.

BLOCKER
  NOTHING TO FORK. A fork is opened at a site in an encoding, and no encode
  phase produces one: p3-encode.sh is itself scaffolded, so this stage has a
  format, a validator and no input. R4-FORK-REPRESENTATION.md §6 says the
  same thing from the design side -- no code changes until the demo's encode
  phase runs.
  Also unmechanisable by construction: fork-register COMPLETENESS. No
  procedure establishes that every ambiguity was found, so the register can
  be checked for internal and cross-file consistency (which it now is) and
  never for exhaustiveness. That judgement is the skill's and HG1's.

Nothing was written and no receipt was recorded.
MSG
exit 3
