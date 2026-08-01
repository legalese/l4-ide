#!/usr/bin/env bash
# P1 — ingest the source (de novo path).
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
p1-ingest: SCAFFOLDED AND CANNOT RUN.

WHAT IT WOULD DO
  Retrieve 17 CFR Part 227 from the SEC entry point through eCFR, with
  provenance (URL, retrieval date, FR citations), covering the 2016
  adoption, the 2017 and 2022 inflation adjustments, the 2021 amendments,
  and the COVID-19 temporary rules.

BLOCKER
  SPEC.md §6 gates G2 entry on ruling R4 (ambiguity-fork representation),
  which is OPEN in SPEC.md §9. Independently, SPEC.md §8's own flag list
  records that P1 has NO bundle schema or manifest format defined anywhere
  in the spec, so there is nothing for an ingest stage to write into and no
  acceptance condition to check it against. Defining specs/todo/single-
  instruction-demo/schemas/source-bundle.schema.json is the prerequisite.

Nothing was written and no receipt was recorded.
MSG
exit 3
