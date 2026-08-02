#!/usr/bin/env bash
# Sourced by every etc/go/phases/*.sh. Never executed directly.
#
# Provides the four things a phase script needs and nothing else: the pinned
# environment, a digest helper, a probe helper, and the single call that writes
# a receipt. A phase script that wants to record a status has exactly one way
# to do it, and that way validates the status against etc/go/lib/verdict.mjs.

set -euo pipefail

if [[ -z "${GO_RUN:-}" || -z "${GO_ROOT:-}" || -z "${GO_STAGE:-}" ]]; then
  echo "phase-prelude.sh: GO_ROOT, GO_RUN and GO_STAGE must be set; phases are launched by etc/go/go.sh, not directly." >&2
  exit 2
fi

GO_LIB="$GO_ROOT/etc/go/lib"

# Exit codes, matching etc/check-bpmn-kie.sh's 0/1/2/3/4 and extending it.
readonly GO_EXIT_CLEAN=0
readonly GO_EXIT_FINDING=1
readonly GO_EXIT_USAGE=2
readonly GO_EXIT_GATE=3
readonly GO_EXIT_BROKEN=4
readonly GO_EXIT_SKIPPED_REQUIRED=5

# Where this stage's artifacts go. Never the tree: build products stay out of
# the repo (house convention), and a projection run must not be able to
# overwrite the committed goldens it is being compared against.
GO_OUT="$GO_RUN/artifacts"
mkdir -p "$GO_OUT"

# --- helpers ----------------------------------------------------------------

# go_digest FILE… -> a single sha256 over the named set. Missing files are
# named ABSENT rather than skipped, so an input that disappears changes the
# digest and the stage re-runs instead of reporting `replayed`.
go_digest() {
  node -e '
    import("'"$GO_LIB"'/ledger.mjs").then(m => {
      process.stdout.write(m.digestSet(process.argv.slice(1)));
    });
  ' "$@"
}

# go_probe NAME -> 0 present, 1 absent (with a named reason on stderr).
go_probe() {
  node "$GO_LIB/probe.mjs" --need "$1"
}

# go_receipt --status S [--reason …] [--artifact P]… — the ONLY way to record.
go_receipt() {
  node "$GO_LIB/receipt.mjs" stage-end \
    --run "$GO_RUN" \
    --stage "$GO_STAGE" \
    --inputs-digest "${GO_INPUTS_DIGEST:-}" \
    "$@"
}

# go_skip REASON — record SKIPPED, and honour L4_GO_REQUIRED=1 by making it fatal.
# House convention (etc/kie-dmn-check/run.sh): a missing toolchain is forgiven
# locally and fatal in CI; a harness that does not compile is neither.
go_skip() {
  local reason="$1"
  shift || true
  go_receipt --status SKIPPED --reason "$reason" "$@"
  if [[ "${L4_GO_REQUIRED:-0}" == "1" ]]; then
    echo "::error::$GO_STAGE SKIPPED while L4_GO_REQUIRED=1 — $reason" >&2
    exit $GO_EXIT_SKIPPED_REQUIRED
  fi
  exit $GO_EXIT_CLEAN
}

# go_broken REASON — the harness itself is defective. A repo defect. Fatal
# everywhere, and never replayable (ledger.mjs refuses to replay a BROKEN stage).
go_broken() {
  go_receipt --status BROKEN --reason "$1" || true
  echo "::error::$GO_STAGE BROKEN — $1" >&2
  exit $GO_EXIT_BROKEN
}

# go_run CMD… — run a command, tee its combined output into the run dir, and
# leave the exit status in GO_LAST_EXIT rather than aborting under `set -e`.
go_run() {
  local log="$GO_OUT/$GO_STAGE.log"
  set +e
  "$@" >>"$log" 2>&1
  GO_LAST_EXIT=$?
  set -e
  printf '%s\n' "\$ $* → exit $GO_LAST_EXIT" >>"$GO_OUT/$GO_STAGE.cmds"
  return 0
}

export GO_LIB GO_OUT
