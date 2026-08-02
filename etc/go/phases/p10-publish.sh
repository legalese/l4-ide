#!/usr/bin/env bash
# P10 — publish.
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
p10-publish: SCAFFOLDED AND CANNOT RUN.

WHAT IT WOULD DO
  Create the corpus-of-law repository, populate it with the encoding, the
  projections and the conversion report, and either contribute to lexipedia
  or publish the comparison note in its place.

BLOCKER
  Ruling R1 was RULED IN FULL on 2026-08-02: the repository is
  legalese/canon — public from day one with inspectable gates and encoding
  version numbers, sidecar class/instance layout, Apache-2.0 + carried
  source-terms + optional CC-BY on prose. It does not exist yet, and
  SPEC.md is explicit that jl4/examples/ and experiments/ are NOT its
  long-term home. Ruling R2 was ruled the same day (probe done; comparison
  note at G4; contact only with a live page). Every outward-facing act
  here is HG2's — including CREATING legalese/canon and any lexipedia
  contact; the ruling names the repo, it does not create it. This orchestrator therefore contains no code that
  can publish anything, and this stage is where that absence is stated
  rather than assumed.

Nothing was written and no receipt was recorded.
MSG
exit 3
