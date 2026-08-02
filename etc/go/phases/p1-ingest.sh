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

NO LONGER BLOCKING (was, until 2026-08-02)
  R4 (ambiguity-fork representation) was ruled 2026-08-02.
  The bundle format now exists:
    specs/todo/single-instruction-demo/schemas/source-bundle.schema.json
  with a validator (etc/go/lib/register-validate.mjs source-bundle <file>)
  and worked fixtures under schemas/fixtures/. So "nothing to write into,
  no acceptance condition" -- the blocker this text used to carry -- is
  false, and a bundle this stage wrote could be checked today.

BLOCKER
  RETRIEVAL. Producing a bundle means fetching the subject's source text
  from source_url, which is an outward network act this orchestrator does
  not perform: its one and only outward request is the loopback jl4-service
  deployment in p7-mcp.sh (see ORCHESTRATOR.md §6.4), and widening that
  fence is a decision, not an implementation detail. Fetching is agent-side
  work owned by the G2 section of the skill at
  .claude/skills/running-the-l4-pipeline/ -- including the archive-fallback
  route the BNA smoke run needed when legislation.gov.uk answered an AWS WAF
  challenge, which the schema records as retrieval_method 'archive'.
  Second, no subject sidecar declares where its bundle lives, so this stage
  has a format but no path: adding it is a subject.json change plus its
  resolver (etc/go/lib/subject.mjs) and selftest.

Nothing was written and no receipt was recorded.
MSG
exit 3
