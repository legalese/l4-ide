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
  # R4's read-set rides beside the digest it proves. Guarded on the file
  # existing rather than passed unconditionally: a stage that declares no
  # inputs has neither a digest nor a read-set, and receipt.mjs REFUSES a
  # --read-set naming a file that is not there — correctly, because a read-set
  # that cannot be read is not an empty read-set.
  local rs=()
  [[ -n "${GO_READ_SET:-}" && -f "${GO_READ_SET}" ]] && rs=(--read-set "$GO_READ_SET")
  node "$GO_LIB/receipt.mjs" stage-end \
    --run "$GO_RUN" \
    --stage "$GO_STAGE" \
    --inputs-digest "${GO_INPUTS_DIGEST:-}" \
    "${rs[@]}" \
    "$@"
}

# go_skip REASON — record SKIPPED, and honour L4_GO_REQUIRED=1 by making it fatal.
# House convention (etc/kie-dmn-check/run.sh): a missing toolchain is forgiven
# locally and fatal in CI; a harness that does not compile is neither.
# go_require_blessing REASON — refuse to perform an OUTWARD-FACING act unless
# this run holds a granting gate row.
#
# R11's second sentence is about the SERVING path, and the receipt-level rule
# cannot reach it: p7-mcp POSTs to a live jl4-service BEFORE it writes any
# receipt, so by the time verdict.mjs sees anything, the deployment exists. A
# rule that runs after the act is not a gate over the act.
#
# Read from the journal, not from an environment variable the caller sets: the
# granting row is in the same hash-chained file a second party would read, and
# a phase script cannot manufacture one. `waived` counts, because
# `gate-allowed-signers` ships with no key and a waiver is a verdict with a
# reason attached rather than an absence — but the reason is PRINTED, so nobody
# deploys under a waiver without seeing what it said.
go_require_blessing() {
  local what="${1:-this outward-facing act}"
  local state
  state=$(node -e '
    import("'"$GO_LIB"'/ledger.mjs").then((m) => {
      const rows = m.read(process.argv[1]);
      const begin = rows.find((r) => r.kind === "run_begin");
      let gate = null;
      try {
        const gs = typeof begin?.gated_stages === "string" ? JSON.parse(begin.gated_stages) : (begin?.gated_stages ?? {});
        for (const [g, list] of Object.entries(gs))
          if (Array.isArray(list) && list.includes(process.argv[2])) gate = g;
      } catch {}
      if (!gate) { process.stdout.write("ungated\t\t"); return; }
      const row = rows.filter((r) => r.kind === "gate" && r.gate === gate && (r.state === "satisfied" || r.state === "waived")).at(-1);
      process.stdout.write(`${row ? row.state : "unblessed"}\t${gate}\t${row?.reason ?? ""}`);
    });
  ' "$GO_RUN/journal.ndjson" "$GO_STAGE")
  local st="${state%%$'\t'*}"
  local rest="${state#*$'\t'}"
  local gate="${rest%%$'\t'*}"
  local reason="${rest#*$'\t'}"
  case "$st" in
    satisfied) return 0 ;;
    waived)
      echo "go: $GO_STAGE is proceeding with $what under a WAIVED $gate — $reason" >&2
      return 0
      ;;
    ungated)
      echo "::error::$GO_STAGE calls go_require_blessing but run_begin does not list it as gated. An outward-facing act must sit behind a gate." >&2
      go_broken "$GO_STAGE performs $what and is not a gated stage; the gate set in run_begin must include it"
      ;;
    *)
      go_broken "refusing $what: this run holds no granting $gate row. An outward-facing act may not precede the human gate that covers it (SPEC.md §7.3)."
      ;;
  esac
}

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
