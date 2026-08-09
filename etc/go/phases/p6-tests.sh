#!/usr/bin/env bash
# P6 — tests, without trusting the exit code.
#
# MEASURED (see etc/go/lib/assert-report.mjs for the capture): `l4 run` exits 0
# on a failed #ASSERT, on a runtime exception, and on a Stuck evaluation. Only a
# TYPECHECK error produces exit 1, and the `ok` field in --json tracks
# typechecking too. So the exit code is not the oracle here; results[] is.
#
# The module set carries its tests as #ASSERT directives inside the .l4 files.
# This stage runs them and reports what they say. It does NOT write new tests —
# writing a test is agent work at every milestone; this stage measures the
# committed carrier, whichever origin the driver resolved (2026-08-09: the
# corpus at g1, the de novo deposit at g2).

# The milestone-scoped module set, resolved by the driver as GO_MODULES with
# GO_MODULES_ORIGIN=corpus|denovo. When invoked directly without one — the
# documented direct-invocation route — the committed corpus set is the default,
# preserving the pre-2026-08-09 contract.
if [[ -z "${GO_MODULES+x}" ]]; then
  GO_MODULES="${GO_S_CORPUS:-}${GO_S_WIZARD:+ $GO_S_WIZARD}"
  GO_MODULES_ORIGIN="corpus"
fi

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' ${GO_MODULES:-} "${BASH_SOURCE[0]}" "$GO_ROOT/etc/go/lib/assert-report.mjs"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

REPORT="$GO_OUT/p6-assertions.txt"

# The deposit contract (ORCHESTRATOR.md §5.2): a module set the stage cannot
# see is a missing PREREQUISITE, reported as SKIPPED with the key to declare or
# the file to deposit — and fatal (exit 5) under L4_GO_REQUIRED=1 via go_skip.
declare -a MODULES=()
read -ra MODULES <<<"${GO_MODULES:-}"
if [[ ${#MODULES[@]} -eq 0 ]]; then
  go_skip "the '$GO_S_ID' sidecar declares no module set for this milestone's origin (${GO_MODULES_ORIGIN:-corpus}: denovo.modules), so there are no committed #ASSERT directives to run. Add it to $GO_S_DIR/subject.json; writing the module is agent work."
fi
declare -a MISSING=()
for m in "${MODULES[@]}"; do [[ -f "$m" ]] || MISSING+=("$m"); done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  go_skip "the declared module set has not been fully deposited yet: ${#MISSING[@]} of ${#MODULES[@]} module(s) are not files — ${MISSING[*]}. Depositing them is agent work; re-run this stage after."
fi

# `l4 run` prints LSP-ish noise on stderr; --json puts the envelope on stdout.
declare -a ENVELOPES=()
for m in "${MODULES[@]}"; do
  stem="$(basename "$m" .l4)"
  set +e
  "$L4" run "$m" --json --fixed-now "$GO_FIXED_NOW" >"$GO_OUT/$stem.run.json" 2>"$GO_OUT/$stem.run.stderr"
  rc=$?
  set -e
  # A non-zero exit from `l4 run` means a TYPECHECK failure, which the earlier
  # check stage over the same module set (p3-check; and p3-encode at g2) should
  # already have caught. If it appears here the run is inconsistent with itself.
  if [[ $rc -ne 0 ]]; then
    go_broken "l4 run exited $rc on $(basename "$m") (typecheck failure) — the earlier check stage reported this module set checking clean, so the run is inconsistent with itself"
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

# The floor is the subject's own for THIS ORIGIN's module set (D2, 2026-08-09:
# floors are per-origin — checks.min_assertions measures the committed corpus,
# denovo.checks.min_assertions measures the deposit; the count compared is
# assertions_total out of results[], NOT a grep over the source, so pin the
# floor to the executed figure). A drop below the floor is a finding about the
# test carrier, never a pass.
declare -a FLOOR_NOTES=()
if [[ "${GO_MODULES_ORIGIN:-corpus}" == "denovo" ]]; then
  MIN_ASSERTIONS="${GO_S_DENOVO_MIN_ASSERTIONS:-0}"
  if [[ -z "${GO_S_DENOVO_MIN_ASSERTIONS:-}" ]]; then
    FLOOR_NOTES+=(--note "the sidecar declares no denovo.checks.min_assertions; the assertion floor defaulted to 0, so the anti-vacuity guard had no teeth on this run. Measure the deposit and pin its floor.")
  fi
else
  MIN_ASSERTIONS="$GO_S_MIN_ASSERTIONS"
fi
ENV_ARTS=()
for e in "${ENVELOPES[@]}"; do ENV_ARTS+=(--artifact "$e"); done

if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  go_receipt --status DEGRADED \
    --reason "only $TOTAL assertions ran across the module set (floor is $MIN_ASSERTIONS). An empty or near-empty results[] satisfies 'no failed assertion' vacuously, so a low count is a finding about the test carrier, not a pass." \
    --artifact "$REPORT" "${ENV_ARTS[@]}" \
    --metric "module_origin=${GO_MODULES_ORIGIN:-corpus}" ${FLOOR_NOTES[@]+"${FLOOR_NOTES[@]}"}
  exit "$GO_EXIT_FINDING"
fi

if [[ $ORACLE_EXIT -ne 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "assert-report found failing assertions or error results in results[]; see $REPORT. Note that 'l4 run' itself exited 0 for every module — the exit code is not the oracle." \
    --artifact "$REPORT" "${ENV_ARTS[@]}" \
    --metric "assertions_total=$TOTAL" \
    --metric "module_origin=${GO_MODULES_ORIGIN:-corpus}" ${FLOOR_NOTES[@]+"${FLOOR_NOTES[@]}"}
  exit "$GO_EXIT_FINDING"
fi

# The closing caveat is origin-specific because the claim it hedges is: at g1
# the carrier is the committed corpus and no encoding happened; at g2 the
# carrier is the deposit, whose assertions were written by the same agent that
# wrote the encoding, and nothing here measures whether they discriminate
# between the fork register's readings.
if [[ "${GO_MODULES_ORIGIN:-corpus}" == "denovo" ]]; then
  CARRIER_NOTE="these are the de novo deposit's own committed assertions, written by the same agent act that wrote the encoding; whether they discriminate between the fork register's readings is not measured by this stage"
else
  CARRIER_NOTE="these are the corpus's own committed assertions; no fork-discriminating tests exist at G1 because G1 does no encoding"
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
  --metric "module_origin=${GO_MODULES_ORIGIN:-corpus}" ${FLOOR_NOTES[@]+"${FLOOR_NOTES[@]}"} \
  --note "$CARRIER_NOTE"
