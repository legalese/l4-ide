#!/usr/bin/env bash
# P6 — tests, without trusting the exit code.
#
# MEASURED (see etc/go/lib/assert-report.mjs for the capture): `l4 run` exits 0
# on a failed #ASSERT, on a runtime exception, and on a Stuck evaluation. Only a
# TYPECHECK error produces exit 1, and the `ok` field in --json tracks
# typechecking too. So the exit code is not the oracle here; results[] is.
#
# The corpus carries its tests as #ASSERT directives inside the .l4 files. This
# stage runs them and reports what they say. It does NOT write new tests: at G1
# there is no de novo encoding, so there are no new forks to discriminate.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "$GO_S_CORPUS" ${GO_S_WIZARD:+"$GO_S_WIZARD"} "${BASH_SOURCE[0]}" "$GO_ROOT/etc/go/lib/assert-report.mjs"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

REPORT="$GO_OUT/p6-assertions.txt"

# The subject's module set: the corpus proper, plus the wizard companion when
# the sidecar declares one. Each module's envelope lands under its own stem.
declare -a MODULES=("$GO_S_CORPUS")
[[ -n "${GO_S_WIZARD:-}" ]] && MODULES+=("$GO_S_WIZARD")

# `l4 run` prints LSP-ish noise on stderr; --json puts the envelope on stdout.
declare -a ENVELOPES=()
for m in "${MODULES[@]}"; do
  stem="$(basename "$m" .l4)"
  set +e
  "$L4" run "$m" --json --fixed-now "$GO_FIXED_NOW" >"$GO_OUT/$stem.run.json" 2>"$GO_OUT/$stem.run.stderr"
  rc=$?
  set -e
  # A non-zero exit from `l4 run` means a TYPECHECK failure, which p3-check
  # should already have caught. If it appears here the run is inconsistent
  # with itself.
  if [[ $rc -ne 0 ]]; then
    go_broken "l4 run exited $rc on $(basename "$m") (typecheck failure) — p3-check reported it checking clean, so the run is inconsistent with itself"
  fi
  ENVELOPES+=("$GO_OUT/$stem.run.json")
done

set +e
node "$GO_LIB/assert-report.mjs" "${ENVELOPES[@]}" | tee "$REPORT"
ORACLE_EXIT=${PIPESTATUS[0]}
set -e

# Guard against the vacuous pass: an empty results[] satisfies "no failed
# assertion" and proves nothing. The selftest calls this out explicitly.
node "$GO_LIB/assert-report.mjs" "${ENVELOPES[@]}" --json >"$GO_OUT/p6-assertions.json" || true
TOTAL=$(node -e '
  const r = require("'"$GO_OUT"'/p6-assertions.json");
  process.stdout.write(String(r.reduce((n, x) => n + x.assertions_total, 0)));
')

# The floor is the subject's own, pinned in its sidecar (subject.json,
# checks.min_assertions): a corpus is expected to carry at least that many
# committed #ASSERT directives, and a drop below it is a finding about the
# test carrier, never a pass.
MIN_ASSERTIONS="$GO_S_MIN_ASSERTIONS"
ENV_ARTS=()
for e in "${ENVELOPES[@]}"; do ENV_ARTS+=(--artifact "$e"); done

if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  go_receipt --status DEGRADED \
    --reason "only $TOTAL assertions ran across the module set (floor is $MIN_ASSERTIONS). An empty or near-empty results[] satisfies 'no failed assertion' vacuously, so a low count is a finding about the test carrier, not a pass." \
    --artifact "$REPORT" "${ENV_ARTS[@]}"
  exit "$GO_EXIT_FINDING"
fi

if [[ $ORACLE_EXIT -ne 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "assert-report found failing assertions or error results in results[]; see $REPORT. Note that 'l4 run' itself exited 0 for every module — the exit code is not the oracle." \
    --artifact "$REPORT" "${ENV_ARTS[@]}" \
    --metric "assertions_total=$TOTAL"
  exit "$GO_EXIT_FINDING"
fi

go_receipt \
  --status PASS \
  --oracle-cmd "node etc/go/lib/assert-report.mjs $(for e in "${ENVELOPES[@]}"; do printf '%s ' "$(basename "$e")"; done)" \
  --oracle-exit 0 \
  --oracle-class execution \
  --oracle-because "the module's own #ASSERT directives were evaluated by the L4 evaluator and every result[] entry of kind 'assertion' is true with no entries of kind 'error'. The process exit code and the envelope's 'ok' field are BOTH ignored: measured, a failing #ASSERT yields ok:true and exit 0." \
  --artifact "$REPORT" \
  "${ENV_ARTS[@]}" \
  --metric "assertions_total=$TOTAL" \
  --note "these are the corpus's own committed assertions; no fork-discriminating tests exist at G1 because G1 does no encoding"
