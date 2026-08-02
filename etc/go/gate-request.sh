#!/usr/bin/env bash
# Print the payload a human must sign to open a gate, and the digest of it.
#
#   etc/go/gate-request.sh HG1 --run RUNDIR
#
# The payload is derived from the journal, not typed: it names the run, the
# repo HEAD, and the sha256 of every corpus file and prerequisite receipt the
# gate is being asked to bless. Signing it therefore binds the approval to
# CONTENT — touch a corpus file after HG1 and the digest changes, the signature no
# longer verifies, and P7 refuses again.
#
# The signature is made OUT OF BAND, with a key that never enters the worktree:
#
#   ssh-keygen -Y sign -f ~/.ssh/id_ed25519 -n l4-go-gate <payload>
#
# Agents can verify (gate-verify.sh) and cannot sign. That asymmetry is the
# whole point; see specs/todo/single-instruction-demo/ORCHESTRATOR.md §6.
#
# Exit: 0 payload written · 2 usage

set -euo pipefail

GATE="${1:-}"
shift || true
RUN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run)
      RUN="$2"
      shift 2
      ;;
    *)
      echo "gate-request.sh: unknown option $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$GATE" || -z "$RUN" ]]; then
  echo "usage: gate-request.sh HG1|HG2 --run RUNDIR" >&2
  exit 2
fi

case "$GATE" in
  HG1) NAMESPACE="l4-go-gate" ;;
  HG2) NAMESPACE="l4-go-gate-hg2" ;;
  *)
    echo "gate-request.sh: unknown gate '$GATE'; SPEC.md §7.3 defines exactly two: HG1, HG2" >&2
    exit 2
    ;;
esac

if [[ ! -f "$RUN/journal.ndjson" ]]; then
  echo "gate-request.sh: $RUN/journal.ndjson does not exist — run at least p0-preflight first" >&2
  exit 2
fi

PAYLOAD="$RUN/$GATE.payload.txt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

node "$SCRIPT_DIR/lib/gate-payload.mjs" "$GATE" "$RUN" >"$PAYLOAD"

DIGEST=$(node -e '
  import("'"$SCRIPT_DIR"'/lib/ledger.mjs").then(m =>
    process.stdout.write(m.sha256File(process.argv[1])));
' "$PAYLOAD")

cat <<EOF

$GATE payload written to:
  $PAYLOAD

digest:
  $DIGEST

To grant this gate, sign the payload out of band with a key that is NOT in
this worktree, then hand back the signature file:

  ssh-keygen -Y sign -f ~/.ssh/id_ed25519 -n $NAMESPACE $PAYLOAD

That writes $PAYLOAD.sig. Then re-run with:

  etc/go/go.sh run --milestone g1 --subject <subject> --run-id <id>

go.sh looks for \$RUN/$GATE.payload.txt.sig and verifies it against
specs/todo/single-instruction-demo/gate-allowed-signers.

--- payload begins ---
EOF
cat "$PAYLOAD"
echo "--- payload ends ---"
