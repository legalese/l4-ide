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

NO LONGER BLOCKING (was, until 2026-08-02)
  The register format now exists:
    specs/todo/single-instruction-demo/schemas/external-modifications.schema.json
  with a validator (etc/go/lib/register-validate.mjs external-modifications
  <file> [peers]) and worked fixtures under schemas/fixtures/. It carries a
  searches[] section, so SPEC.md §4 P2's "the report states what was
  searched, not only what was found" is a checked contract: a search records
  its scope, its date and — required — what it does NOT cover. P5's "every
  entry disposed" now has something to join over, including a cross-file
  completeness check against the source bundle's annotation inventory, which
  is the BNA C2 defect (SMOKE-REPORT.md §3.5) turned into an exit code.

BLOCKER
  SEARCHING. The sweep is a web-search stage, and this orchestrator makes no
  outward network request except the loopback jl4-service deployment in
  p7-mcp.sh (ORCHESTRATOR.md §6.4). Widening that fence is a decision, not
  an implementation detail. Performing the sweep -- and judging what a
  finding means -- is agent-side work owned by the G2 section of the skill
  at .claude/skills/running-the-l4-pipeline/; this stage's honest future
  role is to VALIDATE the register the agent wrote, not to write it.
  Second, no subject sidecar declares where its register lives, so this
  stage has a format but no path.

Nothing was written and no receipt was recorded.
MSG
exit 3
