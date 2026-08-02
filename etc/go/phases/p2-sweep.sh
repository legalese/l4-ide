#!/usr/bin/env bash
# P2 — the external-modification sweep (de novo path). THE STAGE VALIDATES THE
# REGISTER; THE AGENT PERFORMS THE SWEEP.
#
# SPEC.md §4 P2 asks what the printed text cannot say: has a court struck,
# stayed or read down a provision; has the regulator settled — or created — an
# ambiguity through interpretive guidance; are amendments proposed. That is a
# web-search stage, and this orchestrator makes no outward network request
# except §6.4's loopback. Searching, and judging what a finding means, is
# agent-side work owned by the skill's G2 section.
#
# What IS mechanisable is the discipline SPEC.md §4 attaches to it — "the report
# states what was searched, not only what was found, so 'no post-enactment
# modification found' is a checked claim rather than an assumption" — and that
# is a schema section (`searches[]`, each entry required to record its scope,
# its date and what it does NOT cover) plus the rules that tie the two halves
# together: an outcome of 'no-findings' with findings listed, an entry citing a
# search that does not list it, a binding modification disposed as 'encoded'
# that names nowhere it landed.
#
# Requirements source: jl4/examples/legal/bna/SMOKE-REPORT.md §2 (p2-sweep) —
# "the real stage needs: input = the annotated source; output = a COMPLETE
# disposition table over the annotation inventory — every F and C key either
# cited in the encoding or named in a scope-out — and that completeness must be
# machine-checked, because 'reviewer reads the source again' is exactly what
# failed." The measured defect (§3.5: the human sweep disposed of four of the
# five C-annotations and silently dropped one) is now the cross-file rule
# `annotation-inventory-disposed`, which runs here whenever the P1 bundle is
# also deposited — and is reported as a SKIPPED JOIN, never as a pass, when it
# is not.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "${GO_S_DENOVO_REGISTER:-}" "${GO_S_DENOVO_BUNDLE:-}" "${GO_S_DENOVO_FORKS:-}" \
    "${BASH_SOURCE[0]}" "$GO_ROOT/etc/go/lib/deposit-prelude.sh" \
    "$GO_ROOT/etc/go/lib/register-validate.mjs" \
    "$GO_ROOT/specs/todo/single-instruction-demo/schemas/external-modifications.schema.json"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"
source "$GO_ROOT/etc/go/lib/deposit-prelude.sh"

RC=0
go_deposit_check external-modifications || RC=$?

# The sweep's own non-vacuity figures, read out of the deposit rather than out
# of the validator: a register that searched nothing and found nothing is
# perfectly valid, and the report has to be able to say so. This is the same
# stance as p3-check's dated-arm floor — a check satisfied by an empty matched
# set is not a check — except that here there is no honest floor to pin, because
# "nothing has happened to this regulation" is a possible true answer. So the
# numbers are recorded and the judgement stays HG1's.
read -r SEARCHES ENTRIES DISPOSITIONS < <(node -e '
  const j = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
  const n = (x) => (Array.isArray(x) ? x.length : 0);
  process.stdout.write(`${n(j.searches)} ${n(j.entries)} ${n(j.dispositions)}\n`);
' "$GO_DEPOSIT" 2>/dev/null || echo "0 0 0")

METRICS=(--metric "deposit=$GO_DEPOSIT" --metric "peers_present=$GO_DEPOSIT_PEERS"
  --metric "rules_checked=$GO_DEPOSIT_RULES" --metric "joins_skipped=$GO_DEPOSIT_SKIPS"
  --metric "searches=$SEARCHES" --metric "entries=$ENTRIES" --metric "dispositions=$DISPOSITIONS")

declare -a SKIPNOTE=()
[[ "$GO_DEPOSIT_SKIPS" -gt 0 ]] && SKIPNOTE=(--note "$GO_DEPOSIT_SKIPS cross-file join(s) could not run because a peer deposit is absent — most importantly 'annotation-inventory-disposed', which is the BNA C2 defect turned into an exit code and needs the P1 bundle. The artifact reports each as 'skip' with its reason, never as a pass")

if [[ -n "$GO_DEPOSIT_SHAPE" ]]; then
  go_receipt --status DEGRADED \
    --reason "the deposit at $GO_DEPOSIT $GO_DEPOSIT_SHAPE" \
    --artifact "$GO_DEPOSIT_LOG" "${METRICS[@]}"
  exit "$GO_EXIT_FINDING"
fi

if [[ $RC -ne 0 ]]; then
  # Own findings and peer findings are stated separately. The validator's exit
  # code is a total over every file on its command line, so a clean external-modification register
  # sitting next to a broken peer exits 1 — and calling that "the external-modification register
  # does not satisfy its own format" names the wrong file.
  if [[ -n "$GO_DEPOSIT_OWN" ]]; then
    REASON="the external-modification register at $GO_DEPOSIT does not satisfy its own format; rule(s) that fired against it: $GO_DEPOSIT_OWN."
    [[ -n "$GO_DEPOSIT_PEER_FIRED" ]] && REASON="$REASON Further finding(s) against peer deposit(s), which their own stages report: $GO_DEPOSIT_PEER_FIRED."
  else
    REASON="the external-modification register at $GO_DEPOSIT is internally well formed — no rule fired against it — but it was validated alongside its peer deposit(s) and the run reports: $GO_DEPOSIT_PEER_FIRED. Those belong to the peers' own stages; this stage cannot report PASS over a validator run that exited $RC."
  fi
  go_receipt --status DEGRADED \
    --reason "$REASON See $GO_DEPOSIT_LOG." \
    --artifact "$GO_DEPOSIT_LOG" "${METRICS[@]}"
  exit "$GO_EXIT_FINDING"
fi

go_receipt --status PASS \
  --oracle-cmd "node etc/go/lib/register-validate.mjs external-modifications $GO_DEPOSIT (+$GO_DEPOSIT_PEERS peer deposit(s))" \
  --oracle-exit 0 \
  --oracle-class structural \
  --oracle-because "$GO_DEPOSIT_RULES declared cross-field and cross-file rules ran over the register and its peers, including the searched-vs-found joins that make SPEC.md §4 P2's 'what was searched, not only what was found' checkable, the routing rules that force a binding modification to name where it landed in the encoding, and — when the P1 bundle is present — the completeness join over the bundle's annotation inventory. It does NOT establish that the sweep was thorough: no procedure enumerates the searches that should have been run." \
  --artifact "$GO_DEPOSIT_LOG" "${METRICS[@]}" "${SKIPNOTE[@]}" \
  --note "$SEARCHES search(es) and $ENTRIES finding(s) are recorded here; whether that sweep was WIDE ENOUGH is unfalsifiable by construction and is HG1's, and a register that searched nothing validates exactly as cleanly as one that searched everything"
