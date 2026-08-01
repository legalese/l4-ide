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
  printf '%s\n' "$GO_CORPUS" "$GO_WIZARD" "${BASH_SOURCE[0]}" "$GO_ROOT/etc/go/lib/assert-report.mjs"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

CORPUS_JSON="$GO_OUT/regcf.run.json"
WIZARD_JSON="$GO_OUT/regcf-wizard.run.json"
REPORT="$GO_OUT/p6-assertions.txt"

# `l4 run` prints LSP-ish noise on stderr; --json puts the envelope on stdout.
set +e
"$L4" run "$GO_CORPUS" --json --fixed-now "$GO_FIXED_NOW" >"$CORPUS_JSON" 2>"$GO_OUT/regcf.run.stderr"
RC1=$?
"$L4" run "$GO_WIZARD" --json --fixed-now "$GO_FIXED_NOW" >"$WIZARD_JSON" 2>"$GO_OUT/regcf-wizard.run.stderr"
RC2=$?
set -e

# A non-zero exit from `l4 run` means a TYPECHECK failure, which p3-check should
# already have caught. If it appears here the run is inconsistent with itself.
if [[ $RC1 -ne 0 || $RC2 -ne 0 ]]; then
  go_broken "l4 run exited $RC1/$RC2 (typecheck failure) on a module that p3-check reported as checking clean — the run is inconsistent with itself"
fi

set +e
node "$GO_LIB/assert-report.mjs" "$CORPUS_JSON" "$WIZARD_JSON" | tee "$REPORT"
ORACLE_EXIT=${PIPESTATUS[0]}
set -e

# Guard against the vacuous pass: an empty results[] satisfies "no failed
# assertion" and proves nothing. The selftest calls this out explicitly.
node "$GO_LIB/assert-report.mjs" "$CORPUS_JSON" "$WIZARD_JSON" --json >"$GO_OUT/p6-assertions.json" || true
TOTAL=$(node -e '
  const r = require("'"$GO_OUT"'/p6-assertions.json");
  process.stdout.write(String(r.reduce((n, x) => n + x.assertions_total, 0)));
')

MIN_ASSERTIONS=20
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  go_receipt --status DEGRADED \
    --reason "only $TOTAL assertions ran across both modules (floor is $MIN_ASSERTIONS). An empty or near-empty results[] satisfies 'no failed assertion' vacuously, so a low count is a finding about the test carrier, not a pass." \
    --artifact "$REPORT" --artifact "$CORPUS_JSON" --artifact "$WIZARD_JSON"
  exit "$GO_EXIT_FINDING"
fi

if [[ $ORACLE_EXIT -ne 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "assert-report found failing assertions or error results in results[]; see $REPORT. Note that 'l4 run' itself exited 0 for both modules — the exit code is not the oracle." \
    --artifact "$REPORT" --artifact "$CORPUS_JSON" --artifact "$WIZARD_JSON" \
    --metric "assertions_total=$TOTAL"
  exit "$GO_EXIT_FINDING"
fi

go_receipt \
  --status PASS \
  --oracle-cmd "node etc/go/lib/assert-report.mjs regcf.run.json regcf-wizard.run.json" \
  --oracle-exit 0 \
  --oracle-class execution \
  --oracle-because "the module's own #ASSERT directives were evaluated by the L4 evaluator and every result[] entry of kind 'assertion' is true with no entries of kind 'error'. The process exit code and the envelope's 'ok' field are BOTH ignored: measured, a failing #ASSERT yields ok:true and exit 0." \
  --artifact "$REPORT" \
  --artifact "$CORPUS_JSON" \
  --artifact "$WIZARD_JSON" \
  --metric "assertions_total=$TOTAL" \
  --note "these are the corpus's own committed assertions; no fork-discriminating tests exist at G1 because G1 does no encoding"
