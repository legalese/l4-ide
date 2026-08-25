#!/usr/bin/env bash
# P1 — ingest the source (de novo path). THE STAGE VALIDATES THE DEPOSIT; THE
# AGENT PRODUCES IT.
#
# SPEC.md §4 P1's deliverable is "a source bundle with provenance (URL,
# retrieval date, FR cites) that P3 encodes from and P9 cites". Producing one
# means fetching the subject's source text, which is an outward network act this
# orchestrator does not perform — its one and only outward request is the
# loopback jl4-service deployment in p7-mcp.sh (ORCHESTRATOR.md §6.4). Fetching
# is therefore agent-side work owned by the G2 section of
# .claude/skills/running-the-l4-pipeline/SKILL.md, including the archive-fallback
# route the BNA smoke run needed when legislation.gov.uk answered an AWS WAF
# challenge (SMOKE-REPORT.md §2, p1-ingest) — which the schema records as
# retrieval_method 'archive'.
#
# What is mechanisable is the acceptance condition, and that is this stage: the
# bundle validates against schemas/source-bundle.schema.json and its x-rules, it
# is about THIS subject, and its cross-file joins run against whichever peer
# deposits exist. Provenance that cannot be checked is checked anyway where it
# can be — `digest-matches-local-file` re-hashes the captured bytes, and
# `integrity-digest-or-immutable-capture` refuses a document that is neither
# hashed nor pinned to an archive URL.
#
# Requirements source: jl4/examples/legal/bna/SMOKE-REPORT.md §2 ("the real
# stage needs: input = an act/section citation; output = exactly such a
# provenance-headed source artifact; requirements = an archive-fallback fetch
# strategy, capture of the in-force banner, and preservation of the F/C
# annotation inventory — downstream stages consume the annotations, not just the
# words"). All three are schema fields: `retrieval_method`/`archive_url`,
# `in_force`, and `documents[].annotations[]` with its `inventory_complete` flag.

if [[ "${1:-}" == "--inputs" ]]; then
  # The deposit is declared even when absent: lib/ledger.mjs's digestSet names a
  # missing file ABSENT rather than skipping it, so depositing the bundle
  # changes this stage's digest and the stage re-runs instead of replaying a
  # SKIPPED receipt over a file that has since appeared.
  printf '%s\n' "${GO_S_DENOVO_BUNDLE:-}" "${GO_S_DENOVO_REGISTER:-}" "${GO_S_DENOVO_FORKS:-}" \
    "${BASH_SOURCE[0]}" "$GO_ROOT/etc/go/lib/deposit-prelude.sh" \
    "$GO_ROOT/etc/go/lib/register-validate.mjs" \
    "$GO_ROOT/specs/todo/single-instruction-demo/schemas/source-bundle.schema.json"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"
source "$GO_ROOT/etc/go/lib/deposit-prelude.sh"

RC=0
go_deposit_check source-bundle || RC=$?

METRICS=(--metric "deposit=$GO_DEPOSIT" --metric "peers_present=$GO_DEPOSIT_PEERS"
  --metric "rules_checked=$GO_DEPOSIT_RULES" --metric "joins_skipped=$GO_DEPOSIT_SKIPS")

# A join that could not run is stated on the receipt, not left to the artifact:
# the journal names the artifact by sha256, and a sha256 is not invertible.
declare -a SKIPNOTE=()
[[ "$GO_DEPOSIT_SKIPS" -gt 0 ]] && SKIPNOTE=(--note "$GO_DEPOSIT_SKIPS cross-file join(s) could not run because a peer deposit is absent; the artifact reports each as 'skip' with its reason, never as a pass")

if [[ -n "$GO_DEPOSIT_SHAPE" ]]; then
  go_receipt --status DEGRADED \
    --reason "the deposit at $GO_DEPOSIT $GO_DEPOSIT_SHAPE" \
    --artifact "$GO_DEPOSIT_LOG" "${METRICS[@]}"
  exit "$GO_EXIT_FINDING"
fi

if [[ $RC -ne 0 ]]; then
  # Own findings and peer findings are stated separately. The validator's exit
  # code is a total over every file on its command line, so a clean source bundle
  # sitting next to a broken peer exits 1 — and calling that "the source bundle
  # does not satisfy its own format" names the wrong file.
  if [[ -n "$GO_DEPOSIT_OWN" ]]; then
    REASON="the source bundle at $GO_DEPOSIT does not satisfy its own format; rule(s) that fired against it: $GO_DEPOSIT_OWN."
    [[ -n "$GO_DEPOSIT_PEER_FIRED" ]] && REASON="$REASON Further finding(s) against peer deposit(s), which their own stages report: $GO_DEPOSIT_PEER_FIRED."
  else
    REASON="the source bundle at $GO_DEPOSIT is internally well formed — no rule fired against it — but it was validated alongside its peer deposit(s) and the run reports: $GO_DEPOSIT_PEER_FIRED. Those belong to the peers' own stages; this stage cannot report PASS over a validator run that exited $RC."
  fi
  go_receipt --status DEGRADED \
    --reason "$REASON See $GO_DEPOSIT_LOG." \
    --artifact "$GO_DEPOSIT_LOG" "${METRICS[@]}"
  exit "$GO_EXIT_FINDING"
fi

go_receipt --status PASS \
  --oracle-cmd "node etc/go/lib/register-validate.mjs source-bundle $GO_DEPOSIT (+$GO_DEPOSIT_PEERS peer deposit(s))" \
  --oracle-exit 0 \
  --oracle-class structural \
  --oracle-because "the validator models the bundle's semantics rather than its syntax: it audits the schema before using it and refuses any keyword it does not implement, it enforces $GO_DEPOSIT_RULES declared cross-field rules whose ids must match its implementations in both directions, and it re-hashes every captured document that names a local_path. It does NOT establish that the fetched text is the law, that the capture is current, or that the annotation inventory is complete — the schema records the last of those as a self-declared flag, which is exactly why P2's disposition join exists." \
  --artifact "$GO_DEPOSIT_LOG" "${METRICS[@]}" "${SKIPNOTE[@]}" \
  --note "whether the bundle is the RIGHT text — the correct point-in-time version, the whole of the subject, the amendment layers SPEC.md §4 P1 names — is unverified by this stage; the schema can only check that what was recorded is internally coherent and hashes as claimed"
