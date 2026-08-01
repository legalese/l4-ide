#!/usr/bin/env bash
# The default-deny check for a human gate.
#
#   etc/go/gate-verify.sh HG1 --run RUNDIR
#
# Exit: 0 a valid signature over the CURRENT payload exists
#       3 no signature, an invalid signature, or no enrolled signer (GATE)
#       2 usage
#
# There is no --skip-gate and no environment override. Adding one would have to
# be a diff, which is the property this design claims: it is UNDENIABLE, not
# unfakeable. An agent with write access can edit this file or the allowed-signers
# list — and doing so leaves a diff in the repo, PINS-style hashing catches the
# common case, and `etc/go/go.sh verify --gates`, run later by a second party,
# recomputes every gate against the journal without trusting this run at all.

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
      echo "gate-verify.sh: unknown option $1" >&2
      exit 2
      ;;
  esac
done
[[ -n "$GATE" && -n "$RUN" ]] || {
  echo "usage: gate-verify.sh HG1|HG2 --run RUNDIR" >&2
  exit 2
}

case "$GATE" in
  HG1) NAMESPACE="l4-go-gate" ;;
  HG2) NAMESPACE="l4-go-gate-hg2" ;;
  *)
    echo "gate-verify.sh: unknown gate '$GATE'" >&2
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SIGNERS="$REPO_ROOT/specs/todo/single-instruction-demo/gate-allowed-signers"

if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "GATE $GATE: REFUSED — ssh-keygen is not on PATH, so no signature can be verified." >&2
  exit 3
fi

if [[ ! -f "$SIGNERS" ]]; then
  echo "GATE $GATE: REFUSED — $SIGNERS does not exist." >&2
  exit 3
fi

# An allowed-signers file with no real key is the shipped state. Say so plainly
# rather than failing with an ssh-keygen parse error.
if ! grep -qE '^[^#[:space:]]+[[:space:]]+(ssh-(ed25519|rsa)|ecdsa-)' "$SIGNERS"; then
  cat >&2 <<EOF
GATE $GATE: REFUSED — no signer is enrolled.

$SIGNERS contains no public key, so no signature can ever verify and every
gated stage will refuse. This is the shipped state and it is deliberate: the
orchestrator will not invent an approver.

To enrol:
  1. append one line to that file, in ssh allowed_signers format:
       mengwong@gmail.com ssh-ed25519 AAAA… comment
  2. etc/go/gate-verify.sh reads it; nothing else does.

To proceed WITHOUT a signature, waive the gate explicitly:
  etc/go/go.sh run … --waive $GATE="why this run may proceed unsigned"
A waiver is recorded on the journal and printed in the report's Gates section.
It is not an absence; it is a verdict with your reason attached.
EOF
  exit 3
fi

PAYLOAD="$RUN/$GATE.payload.txt"
SIG="$PAYLOAD.sig"

# Rebuild the payload from the journal every time. A stale payload file on disk
# must never be what gets verified: the gate binds to CURRENT content.
node "$SCRIPT_DIR/lib/gate-payload.mjs" "$GATE" "$RUN" >"$PAYLOAD.current"

if [[ ! -f "$SIG" ]]; then
  echo "GATE $GATE: REFUSED — no signature at $SIG. Run: etc/go/gate-request.sh $GATE --run $RUN" >&2
  exit 3
fi

if ! cmp -s "$PAYLOAD" "$PAYLOAD.current" 2>/dev/null; then
  echo "GATE $GATE: REFUSED — the payload changed since it was signed." >&2
  echo "  A corpus file or an earlier receipt moved after the gate was granted, so the" >&2
  echo "  signature no longer covers what this run would do. Re-request and re-sign." >&2
  exit 3
fi

IDENTITY=$(awk '!/^#/ && NF {print $1; exit}' "$SIGNERS")
if ssh-keygen -Y verify -f "$SIGNERS" -I "$IDENTITY" -n "$NAMESPACE" -s "$SIG" <"$PAYLOAD" >/dev/null 2>&1; then
  FPR=$(awk '!/^#/ && NF {$1=""; print substr($0,2); exit}' "$SIGNERS" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
  echo "GATE $GATE: SATISFIED — signature by $IDENTITY over $PAYLOAD verifies in namespace $NAMESPACE"
  echo "  allowed-signers fingerprint: ${FPR:-(unreadable)}"
  exit 0
fi

echo "GATE $GATE: REFUSED — $SIG does not verify against $SIGNERS in namespace $NAMESPACE." >&2
exit 3
