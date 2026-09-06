#!/usr/bin/env bash
# P6 — tests, without trusting the exit code.
#
# MEASURED (see etc/go/lib/assert-report.mjs for the capture and the 2026-09-04
# re-measure): `l4 run` exits 0 on a failed #ASSERT — a clean FALSE — with
# ok:true, and that is the case the exit code cannot see. A TYPECHECK error
# exits 1 with results[] empty; a directive that CRASHES — a raising #EVAL, and
# since fix/assert-check-reporting an #ASSERT that raises or is stuck on an
# assumed term — exits 1 with the full envelope still on stdout. So the exit
# code is not the oracle here; results[] is.
#
# The module set carries its tests as #ASSERT directives inside the .l4 files.
# This stage runs them and reports what they say. It does NOT write new tests —
# writing a test is agent work whichever encoding is under test. This stage
# measures the carrier of THE ENCODING IT WAS HANDED, and does not ask which one
# that is: the selected encoding arrives in the ordinary GO_S_ENCODING_* and
# GO_S_MIN_* variables, so the module set and the floor are already the right
# ones by the time this file runs.

# The module set for the encoding this run is about, resolved by the driver as
# GO_MODULES. When invoked directly without one — the documented
# direct-invocation route — the committed encoding's set is the default, which
# is exactly what subject.mjs resolves when no --encoding is named. Kept
# byte-for-byte in step with the driver's own derivation (go.sh): a fallback
# that resolved a NARROWER set than a run does would make a direct invocation
# measure something other than what the receipt claims.
if [[ -z "${GO_MODULES+x}" ]]; then
  GO_MODULES="${GO_S_ENCODING_MODULES:-${GO_S_ENCODING:-}${GO_S_WIZARD:+ $GO_S_WIZARD}}"
fi

if [[ "${1:-}" == "--inputs" ]]; then
  # The assertion floor is a VERDICT INPUT this stage reads (sidecar-derived,
  # via GO_S_* env), so it is a digest contributor — `text:` entries are
  # literal contributors, per digestSet in lib/ledger.mjs. Without this line,
  # editing the floor and resuming a run REPLAYED the old verdict: measured
  # 2026-08-09, the encoding-under-test's min_assertions 39 → 1000 then
  # --run-id resume printed "p6-tests: PASS (replayed)" — a PASS the edited
  # configuration would refuse. The undeclared case is a distinct contributor
  # because it changes the receipt (the toothless-guard note below).
  #
  # ONE read where there used to be a two-armed branch on the module set's
  # origin. Both arms collapsed to the same line once floors began travelling
  # WITH their encoding: the selected encoding's floor IS GO_S_MIN_ASSERTIONS,
  # whichever encoding was selected, so there is no longer anything to tell
  # apart here. The branch was deleted rather than renamed.
  _floor="${GO_S_MIN_ASSERTIONS:-undeclared}"
  # THE PINNED CLOCK IS A VERDICT INPUT, so it is a digest contributor.
  # `--fixed-now` is what this stage passes to `l4` a few lines down, and it is
  # the answer to "as at what date does the law say this". It was in NO stage's
  # inputs: two runs of the same subject, same tree, same binary and DIFFERENT
  # --fixed-now produced byte-identical digests, and findReplayableAcrossRuns
  # filters on subject and digest only -- so the second run borrowed the first
  # run's answer about a different point in legal time. Declared per stage
  # rather than folded centrally like the l4 binary's sha, because only the
  # stages that actually pass --fixed-now should re-run when it moves.
  printf '%s\n' ${GO_MODULES:-} "${BASH_SOURCE[0]}" "$GO_ROOT/etc/go/lib/assert-report.mjs" "text:min_assertions=$_floor" "text:fixed_now=${GO_FIXED_NOW:-unset}"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

REPORT="$GO_OUT/p6-assertions.txt"

# WHICH SIDECAR KEYS THIS RUN'S DIAGNOSTICS MUST NAME. The stage never branches
# on which encoding it was handed to decide what to MEASURE — that travels in
# the ordinary variables — but a note telling a human to go and edit a key has
# to name a key that is actually in their file, and the committed encoding's
# declarations sit at the top level of subject.json while an additional
# encoding's sit under its own id. Derived once, from the id the driver
# resolved, so no message below can point at a key that does not exist — the
# old note said "denovo.checks.min_assertions", which is now no key at all.
# Both floor spellings are derived even though only the additional encoding's
# note can fire today (subject.mjs makes `checks` mandatory on the committed
# encoding, so its floor is never absent): the pair is the mapping, and a
# half-derived mapping is what goes stale when the schema next moves.
# THREE cases, not two. `undeclared` means no additional encoding is declared
# at all, so there is no id to name and the reader must CREATE the entry rather
# than fill one in — collapsing it into `primary` sent them to `encoding.*`,
# which is advice about the committed encoding in the one case that ever fires.
_ENC_ID="${GO_S_ENCODING_ID:-primary}"
case "$_ENC_ID" in
  primary)
    SIDECAR_MODULES_KEY="encoding.modules"
    SIDECAR_FLOOR_KEY="checks.min_assertions"
    ;;
  undeclared)
    SIDECAR_MODULES_KEY="encodings.<id>.modules (none is declared yet)"
    SIDECAR_FLOOR_KEY="encodings.<id>.checks.min_assertions"
    ;;
  *)
    SIDECAR_MODULES_KEY="encodings.$_ENC_ID.modules"
    SIDECAR_FLOOR_KEY="encodings.$_ENC_ID.checks.min_assertions"
    ;;
esac

# The deposit contract (ORCHESTRATOR.md §5.2): a module set the stage cannot
# see is a missing PREREQUISITE, reported as SKIPPED with the key to declare or
# the file to deposit — and fatal (exit 5) under L4_GO_REQUIRED=1 via go_skip.
declare -a MODULES=()
read -ra MODULES <<<"${GO_MODULES:-}"
if [[ ${#MODULES[@]} -eq 0 ]]; then
  go_skip "the '$GO_S_ID' sidecar declares no module set for the encoding this run is about ($_ENC_ID: $SIDECAR_MODULES_KEY), so there are no committed #ASSERT directives to run. Add it to $GO_S_DIR/subject.json; writing the module is agent work."
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
  # A non-zero exit from `l4 run` is one of two things. With results[] EMPTY it
  # is a TYPECHECK failure, which the earlier check stage over the same module
  # set (p3-check; and p3-encode when the run is about an additional encoding)
  # should already have caught — if it appears here the run is inconsistent
  # with itself. With results[] NON-EMPTY the module got past the typechecker
  # and a directive CRASHED during evaluation: a raising #EVAL (kind "error"),
  # or — since fix/assert-check-reporting — an #ASSERT that raises or is stuck
  # on an assumed term (kind "assertion", value null). That is an assertion
  # finding, and assert-report.mjs reads results[], so it is routed there.
  if [[ $rc -ne 0 ]] && ! node -e 'const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); process.exit(Array.isArray(r.results) && r.results.length > 0 ? 0 : 1)' "$GO_OUT/$stem.run.json" 2>/dev/null; then
    go_broken "l4 run exited $rc on $(basename "$m") with no evaluation results (typecheck failure) — the earlier check stage reported this module set checking clean, so the run is inconsistent with itself"
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

# The floor is the SELECTED ENCODING's own (D2, 2026-08-09: a floor measures the
# population it was pinned against, so each encoding carries its own; the
# committed encoding's lives at checks.min_assertions, an additional encoding's
# at encodings.<id>.checks.min_assertions, and the driver hands whichever one
# was selected over as GO_S_MIN_ASSERTIONS). The count compared is
# assertions_total out of results[], NOT a grep over the source, so pin the
# floor to the executed figure. A drop below the floor is a finding about the
# test carrier, never a pass.
declare -a FLOOR_NOTES=()
# THIS BRANCH SURVIVES, and it is not about origin: it is about whether the
# floor CAN be absent. `checks` is required on the committed encoding, so its
# floor is always a declared number; an additional encoding's `checks` is
# optional and arrives EMPTY when omitted. The stage must not invent a floor
# quietly, so the empty case defaults to 0 and SAYS SO on the receipt, naming
# the key the reader has to add.
if [[ "$_ENC_ID" == "primary" ]]; then
  MIN_ASSERTIONS="$GO_S_MIN_ASSERTIONS"
else
  MIN_ASSERTIONS="${GO_S_MIN_ASSERTIONS:-0}"
  if [[ -z "${GO_S_MIN_ASSERTIONS:-}" ]]; then
    FLOOR_NOTES+=(--note "the sidecar declares no $SIDECAR_FLOOR_KEY; the assertion floor defaulted to 0, so the anti-vacuity guard had no teeth on this run. Measure this encoding and pin its floor.")
  fi
fi
ENV_ARTS=()
for e in "${ENVELOPES[@]}"; do ENV_ARTS+=(--artifact "$e"); done

if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  go_receipt --status DEGRADED \
    --reason "only $TOTAL assertions ran across the module set (floor is $MIN_ASSERTIONS). An empty or near-empty results[] satisfies 'no failed assertion' vacuously, so a low count is a finding about the test carrier, not a pass." \
    --artifact "$REPORT" "${ENV_ARTS[@]}" \
    --metric "encoding_id=$_ENC_ID" ${FLOOR_NOTES[@]+"${FLOOR_NOTES[@]}"}
  exit "$GO_EXIT_FINDING"
fi

# THE ZERO-ASSERTION CASE IS NOT A GREEN (2026-08-09). With the floor at 0 —
# what an additional encoding that declares no `checks` resolves to, the natural
# state of a fresh deposit — a module set carrying no #ASSERT at all fell
# through the floor check and earned PASS with oracle-class `execution`, whose
# ORCHESTRATOR.md §3.1 promise is "ran on its target engine, on cases, and
# agreed". Nothing ran and nothing agreed; measured RED before this branch
# existed. Unlike p3-check — where temporal closure is one sub-check among
# several and a 0-over-0 case demotes to NOT CHECKED without moving the status —
# the assertions ARE this stage's whole oracle, so an empty set demotes the
# status itself.
if [[ "$TOTAL" -eq 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "0 assertions ran across the module set (floor: $MIN_ASSERTIONS). 'No failed assertion' over an empty results[] is vacuous, and this stage's PASS claims oracle-class execution — something ran and agreed — which nothing did. A module set with no #ASSERT directives is a finding about the test carrier; a 0 floor is honest only when 0 is the measured population, and even then the absence of tests is reportable, not green." \
    --artifact "$REPORT" "${ENV_ARTS[@]}" \
    --metric "assertions_total=0" \
    --metric "encoding_id=$_ENC_ID" ${FLOOR_NOTES[@]+"${FLOOR_NOTES[@]}"}
  exit "$GO_EXIT_FINDING"
fi

if [[ $ORACLE_EXIT -ne 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "assert-report found failing assertions or error results in results[]; see $REPORT. Note that 'l4 run' itself exited 0 for every module — the exit code is not the oracle." \
    --artifact "$REPORT" "${ENV_ARTS[@]}" \
    --metric "assertions_total=$TOTAL" \
    --metric "encoding_id=$_ENC_ID" ${FLOOR_NOTES[@]+"${FLOOR_NOTES[@]}"}
  exit "$GO_EXIT_FINDING"
fi

# THE CLOSING CAVEAT IS A GENUINE DIFFERENCE, not an origin sentinel in
# disguise: it describes WHERE THESE ASSERTIONS CAME FROM, and that is not the
# same story for the two cases. A run about the committed encoding writes no
# encoding, so its assertions were already in the tree and were written by
# whoever committed them; a run about an additional encoding is measuring
# assertions written by the same agent act that wrote that encoding, which is a
# weaker independence claim and has to be said out loud.
if [[ "$_ENC_ID" == "primary" ]]; then
  CARRIER_NOTE="these are the committed encoding's own assertions, already in the tree before this run: a run about the committed encoding does no encoding, so none of them were written to discriminate between the fork register's readings"
else
  CARRIER_NOTE="these are the assertions committed alongside encoding '$_ENC_ID', written by the same agent act that wrote that encoding; whether they discriminate between the fork register's readings is not measured by this stage"
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
  --metric "encoding_id=$_ENC_ID" ${FLOOR_NOTES[@]+"${FLOOR_NOTES[@]}"} \
  --note "$CARRIER_NOTE"
