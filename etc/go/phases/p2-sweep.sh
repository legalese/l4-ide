#!/usr/bin/env bash
# P2 — the external-modification sweep (de novo path).
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
p2-sweep: SCAFFOLDED AND CANNOT RUN.

WHAT IT WOULD DO
  Search for courts striking, staying or reading down the rule; SEC C&DIs,
  no-action letters and staff bulletins; FR proposed rules and the
  regulatory agenda; litigation in flight. Route each finding as binding /
  interpretive guidance / prospective, and record provenance for every one.

BLOCKER
  Two blockers. (1) The sweep is a web-search stage and this orchestrator
  makes no outward network requests except the loopback deployment in
  p7-mcp.sh; a search stage would be the second, and it needs its own
  decision. (2) SPEC.md §8 names the absence of a machine-readable external-
  modification register as one of the two highest-leverage gaps in the whole
  pipeline — without it, P5's 'every entry disposed' cannot be checked.
  specs/todo/single-instruction-demo/schemas/external-modification-
  register.schema.json ships as the proposed shape; nothing reads it yet.

Nothing was written and no receipt was recorded.
MSG
exit 3
