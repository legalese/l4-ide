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
  Retrieve the subject's source text from its declared entry point
  (subject.json: source_url, e.g. the eCFR page the citation names), with
  provenance (URL, retrieval date, citations), covering the adoption and
  every subsequent amendment layer.

BLOCKER
  R4 (ambiguity-fork representation) was ruled 2026-08-02, so no ruling
  blocks G2 entry from this side any more. What blocks: NO bundle schema or manifest
  format is defined anywhere in SPEC.md -- grepped 2026-08-02, 'bundle'
  occurs once, in §4's P1 deliverable ("a source bundle with provenance"),
  and 'manifest' not at all -- so there is nothing for an ingest stage to
  write into and no acceptance condition to check it against. Defining
  specs/todo/single-instruction-demo/schemas/source-bundle.schema.json is
  the prerequisite; that directory exists and is EMPTY.

Nothing was written and no receipt was recorded.
MSG
exit 3
