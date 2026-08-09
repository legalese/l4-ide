#!/usr/bin/env bash
# P7 — the DMN leg.
#
# THE STATUS THIS LEG REPORTS DEPENDS ON WHETHER THE CORPUS CASES FILE EXISTS.
#
# Until 2026-08-02 it reported `NOT-EXECUTABLE`, and that was correct then: R0
# ("the execution is the exhibit") makes non-execution a DEFECT, not a caveat,
# and SPEC.md §6 permits it at G1 *only if the report says so in Blocking
# terms*. No cases file existed for the CORPUS DMN — only the 101-line toy's
# jl4/examples/dmn/reg-cf.cases.json — and writing cases against 80 boxed
# literal expressions that could not evaluate would have manufactured a green
# the artifact had not earned.
#
# PR #194 (unstable 4122355a, 2026-08-02) discharged that for the inaugural
# subject: fidelity went 95 blocking → 0 and a corpus cases file landed with
# 16 dated cases whose expected values are L4-evaluated. With the subject's
# cases file present, the branch at the bottom of this script executes the
# emitted DMN on BOTH engine harnesses and the leg's oracle class rises to
# `execution`.
#
# The golden, fidelity golden and cases file come from the subject sidecar
# (subject.json, legs['p7-dmn']); the cases path is declared there even when
# the file does not exist yet, because its ABSENCE is this leg's designed
# NOT-EXECUTABLE story rather than a configuration error.
#
# AT G2 (GO_MODULES_ORIGIN=denovo, 2026-08-09, D6) THIS LEG RUNS EMIT-ONLY
# OVER THE DEPOSIT: there is no committed golden for a de novo module, so the
# golden machinery below is g1's and is not touched. The g2 oracle set is:
# emission + the dmn-moddle structural gate + a no-cases ENGINE-LOAD PROBE on
# both harnesses (they accept a bare FILE.dmn). An engine refusing to load the
# emitted model is a DEGRADED receipt naming the error — a finding about the
# EXPORTER over this encoding's constructs, which is exactly the §8.1 exhibit.
# A model both engines load, with no denovo.legs['p7-dmn'].cases declared, is
# NOT-EXECUTABLE with that blocker: dmn-moddle acceptance is `wellformedness`,
# which ORCHESTRATOR.md §3.1 bars from PASS.

# The milestone-scoped module set. At corpus origin this leg emits the corpus
# MAIN module only (the wizard is not part of the DMN golden), so the g1
# branch keeps reading GO_S_CORPUS; the resolved set drives the g2 branch.
if [[ -z "${GO_MODULES+x}" ]]; then
  GO_MODULES="${GO_S_CORPUS:-}"
  GO_MODULES_ORIGIN="corpus"
fi

if [[ "${1:-}" == "--inputs" ]]; then
  if [[ "${GO_MODULES_ORIGIN:-corpus}" == "denovo" ]]; then
    printf '%s\n' ${GO_MODULES:-} "${BASH_SOURCE[0]}" \
      "$GO_ROOT/etc/validate-dmn.mjs" \
      ${GO_S_DENOVO_DMN_CASES:+"$GO_S_DENOVO_DMN_CASES"} \
      "$GO_ROOT/etc/kie-dmn-check/run.sh" \
      "$GO_ROOT/etc/camunda-dmn-check/run.sh"
  else
    printf '%s\n' "$GO_S_CORPUS" "${BASH_SOURCE[0]}" \
      "$GO_S_DMN_GOLDEN" \
      "$GO_S_DMN_FIDELITY_GOLDEN" \
      "$GO_ROOT/etc/validate-dmn.mjs" \
      "$GO_ROOT/etc/go/lib/canon-diff.mjs" \
      "$GO_S_DMN_CASES" \
      "$GO_ROOT/etc/kie-dmn-check/run.sh" \
      "$GO_ROOT/etc/camunda-dmn-check/run.sh"
  fi
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

# ============================== the g2 branch ================================
if [[ "${GO_MODULES_ORIGIN:-corpus}" == "denovo" ]]; then
  declare -a MODULES=()
  read -ra MODULES <<<"${GO_MODULES:-}"
  if [[ ${#MODULES[@]} -eq 0 ]]; then
    go_skip "the '$GO_S_ID' sidecar declares no denovo.modules, so there is no de novo module to emit DMN from. Add it to $GO_S_DIR/subject.json; writing the module is agent work."
  fi
  declare -a MISSING=()
  for m in "${MODULES[@]}"; do [[ -f "$m" ]] || MISSING+=("$m"); done
  if [[ ${#MISSING[@]} -gt 0 ]]; then
    go_skip "the declared module set has not been fully deposited yet: ${#MISSING[@]} of ${#MODULES[@]} module(s) are not files — ${MISSING[*]}. Depositing them is agent work; re-run this stage after."
  fi

  CASES="${GO_S_DENOVO_DMN_CASES:-}"
  TOTAL_BLOCKING=0
  TOTAL_LOSSY=0
  TOTAL_ADVISORY=0
  VALIDATE_FAILURES=0
  declare -a OUTS=()
  declare -a ARTS=()

  for m in "${MODULES[@]}"; do
    STEM="$(basename "$m" .l4)"
    OUT="$GO_OUT/$STEM.dmn"
    set +e
    "$L4" export "$m" --to dmn -o "$OUT" --fidelity-report 2>"$GO_OUT/$STEM.dmn.emit.stderr"
    EXPORT_RC=$?
    set -e
    cat "$GO_OUT/$STEM.dmn.emit.stderr"
    if [[ $EXPORT_RC -ne 0 ]]; then
      # At g1 an export failure is go_broken (a harness defect against a module
      # the repo defends). Over a DEPOSIT it is a finding about the exporter's
      # coverage of this encoding's constructs — D6 rules it DEGRADED, named.
      go_receipt --status DEGRADED \
        --reason "l4 export --to dmn exited $EXPORT_RC on $STEM.l4, a deposited module that typechecks (p3-encode certified it this run). That is an exporter gap over this encoding's constructs, not a defect in the deposit; see $GO_OUT/$STEM.dmn.emit.stderr. This is the §8.1 exhibit: the de novo encoding cannot yet ride run 1's projection suite." \
        --artifact "$GO_OUT/$STEM.dmn.emit.stderr" \
        --metric "module_origin=denovo" --metric "export_exit=$EXPORT_RC"
      exit "$GO_EXIT_FINDING"
    fi
    FID="${OUT%.dmn}.fidelity.txt"
    set +e
    npx --yes --package=dmn-moddle node "$GO_ROOT/etc/validate-dmn.mjs" "$OUT" >"$GO_OUT/$STEM.dmn.validate.txt" 2>&1
    VRC=$?
    set -e
    tail -3 "$GO_OUT/$STEM.dmn.validate.txt" || true
    [[ $VRC -eq 0 ]] || VALIDATE_FAILURES=$((VALIDATE_FAILURES + 1))
    read -r B L A < <(node "$GO_LIB/fidelity-counts.mjs" "$FID")
    TOTAL_BLOCKING=$((TOTAL_BLOCKING + B))
    TOTAL_LOSSY=$((TOTAL_LOSSY + L))
    TOTAL_ADVISORY=$((TOTAL_ADVISORY + A))
    OUTS+=("$OUT")
    ARTS+=(--artifact "$OUT" --artifact "$FID" --artifact "$GO_OUT/$STEM.dmn.validate.txt")
  done

  METRICS=(--metric "module_origin=denovo" --metric "modules=${#MODULES[@]}"
    --metric "blocking=$TOTAL_BLOCKING" --metric "lossy=$TOTAL_LOSSY" --metric "advisory=$TOTAL_ADVISORY")

  if [[ $VALIDATE_FAILURES -gt 0 ]]; then
    go_receipt --status DEGRADED \
      --reason "etc/validate-dmn.mjs rejected $VALIDATE_FAILURES of ${#MODULES[@]} emitted DMN file(s); see the .validate.txt artifacts" \
      "${ARTS[@]}" "${METRICS[@]}"
    exit "$GO_EXIT_FINDING"
  fi

  # The engine-load probe: both harnesses accept a bare FILE.dmn (no --cases)
  # and load + XSD-check + validate + build it, printing a VERDICT banner. The
  # house rule holds — assert on the banner, never the exit code, because a
  # toolchain-absent harness skips LOUDLY with exit 0 and no banner.
  probe() { # ENGINE-RUNNER LOGFILE -> ok | refused | unavailable
    local runner="$1" log="$2"
    set +e
    "$runner" "${OUTS[@]}" >"$log" 2>&1
    local rc=$?
    set -e
    if ! grep -q "VERDICT" "$log"; then
      echo "unavailable"
    elif [[ $rc -eq 0 ]]; then
      echo "ok"
    else
      echo "refused"
    fi
  }
  KIE_LOG="$GO_OUT/p7-dmn.kie.txt"
  CAM_LOG="$GO_OUT/p7-dmn.camunda.txt"
  KIE_PROBE=$(probe "$GO_ROOT/etc/kie-dmn-check/run.sh" "$KIE_LOG")
  CAM_PROBE=$(probe "$GO_ROOT/etc/camunda-dmn-check/run.sh" "$CAM_LOG")
  ARTS+=(--artifact "$KIE_LOG" --artifact "$CAM_LOG")
  METRICS+=(--metric "kie_probe=$KIE_PROBE" --metric "camunda_probe=$CAM_PROBE")
  grep "VERDICT" "$KIE_LOG" || true
  grep "VERDICT" "$CAM_LOG" || true

  # A declared-and-present cases file upgrades the leg to the execution oracle,
  # exactly as at g1. Today no subject declares one for the deposit.
  if [[ -n "$CASES" && -f "$CASES" ]]; then
    set +e
    KIE_CHECK_REQUIRED="${L4_GO_REQUIRED:-0}" "$GO_ROOT/etc/kie-dmn-check/run.sh" "${OUTS[@]}" --cases "$CASES" >"$GO_OUT/p7-dmn.kie.cases.txt" 2>&1
    KIE_RC=$?
    CAMUNDA_CHECK_REQUIRED="${L4_GO_REQUIRED:-0}" "$GO_ROOT/etc/camunda-dmn-check/run.sh" "${OUTS[@]}" --cases "$CASES" >"$GO_OUT/p7-dmn.camunda.cases.txt" 2>&1
    CAM_RC=$?
    set -e
    ARTS+=(--artifact "$GO_OUT/p7-dmn.kie.cases.txt" --artifact "$GO_OUT/p7-dmn.camunda.cases.txt")
    if [[ $KIE_RC -ne 0 || $CAM_RC -ne 0 ]] || ! grep -q "VERDICT" "$GO_OUT/p7-dmn.kie.cases.txt" || ! grep -q "VERDICT" "$GO_OUT/p7-dmn.camunda.cases.txt"; then
      go_receipt --status DEGRADED \
        --reason "an engine harness did not print a VERDICT banner, or exited non-zero (kie $KIE_RC, camunda $CAM_RC) over the declared de novo cases file. House convention: assert on the liveness banner, not the exit code." \
        "${ARTS[@]}" "${METRICS[@]}"
      exit "$GO_EXIT_FINDING"
    fi
    go_receipt --status PASS \
      --oracle-cmd "etc/kie-dmn-check/run.sh + etc/camunda-dmn-check/run.sh over $CASES, both printing a VERDICT banner" \
      --oracle-exit 0 --oracle-class execution \
      --oracle-because "the emitted de novo DMN was executed by both target engines on the declared cases and agreed" \
      "${ARTS[@]}" "${METRICS[@]}"
    exit "$GO_EXIT_CLEAN"
  fi

  if [[ "$KIE_PROBE" == "refused" || "$CAM_PROBE" == "refused" ]]; then
    KIE_ERR="$(grep -m1 -E 'ERROR|INVALID' "$KIE_LOG" || true)"
    CAM_ERR="$(grep -m1 -E 'ERROR|INVALID' "$CAM_LOG" || true)"
    go_receipt --status DEGRADED \
      --reason "the emitted de novo DMN passes the dmn-moddle structural gate but an engine REFUSES to load it (kie: $KIE_PROBE${KIE_ERR:+ — ${KIE_ERR}}; camunda: $CAM_PROBE${CAM_ERR:+ — ${CAM_ERR}}). The exporter self-reports $TOTAL_BLOCKING blocking fidelity codes — constructs it can only emit as L4 source text inside a literalExpression, which no FEEL engine parses. This is a finding about the EXPORTER's coverage of this encoding's constructs, and it is the §8.1 exhibit: the de novo corpus cannot yet ride run 1's projection suite. Full engine output in the artifacts." \
      "${ARTS[@]}" "${METRICS[@]}" \
      --note "the structural gate (dmn-moddle) accepted what both engines refuse — the gate is not sensitive to this defect class, which is why it is barred from licensing PASS (ORCHESTRATOR.md §3.1)"
    exit "$GO_EXIT_FINDING"
  fi

  if [[ "$KIE_PROBE" == "ok" && "$CAM_PROBE" == "ok" ]]; then
    BLOCKER="no denovo.legs['p7-dmn'].cases is declared in $GO_S_DIR/subject.json (or the declared file is absent), so neither engine harness can EXECUTE the model it just loaded. Writing cases with L4-evaluated expected values is agent work; declaring the path is one sidecar line."
  else
    BLOCKER="no denovo.legs['p7-dmn'].cases is declared, AND the engine-load probe could not run (kie: $KIE_PROBE, camunda: $CAM_PROBE — a harness with no toolchain skips loudly and prints no VERDICT banner). The strongest oracle that ran is emission + dmn-moddle wellformedness, which ORCHESTRATOR.md §3.1 bars from PASS."
  fi
  go_receipt --status NOT-EXECUTABLE \
    --reason "the de novo DMN was emitted (${#MODULES[@]} module(s)) and passes the dmn-moddle interchange gate, and it CANNOT BE claimed executed: no cases file is declared for the deposit${KIE_PROBE:+; engine-load probe kie=$KIE_PROBE camunda=$CAM_PROBE}. R0 makes non-execution a defect, not a caveat, and this receipt is the Blocking line SPEC.md §6 requires." \
    --blocker "$BLOCKER" \
    "${ARTS[@]}" "${METRICS[@]}"
  exit "$GO_EXIT_CLEAN"
fi
# ============================ end of the g2 branch ===========================

GOLDEN="$GO_S_DMN_GOLDEN"
GOLDEN_FID="$GO_S_DMN_FIDELITY_GOLDEN"
CASES="$GO_S_DMN_CASES"
# The regenerated artifact lands under the golden's own basename, so the diff
# reads name-against-name.
OUT="$GO_OUT/$(basename "$GOLDEN")"
DIFFLOG="$GO_OUT/p7-dmn.canon-diff.txt"

# --- 1. regenerate -----------------------------------------------------------
set +e
"$L4" export "$GO_S_CORPUS" --to dmn -o "$OUT" --fidelity-report 2>"$GO_OUT/p7-dmn.fidelity.stderr"
EXPORT_RC=$?
set -e
[[ $EXPORT_RC -eq 0 ]] || go_broken "l4 export --to dmn exited $EXPORT_RC on a module that typechecks"
cat "$GO_OUT/p7-dmn.fidelity.stderr"

# `--fidelity-report` with `-o out.dmn` writes a sibling out.fidelity.txt.
FID="${OUT%.dmn}.fidelity.txt"

# --- 2. differential oracle against the committed golden --------------------
# NOT a bare byte-diff: that is red on day one and the cause is a defect in the
# GOLDEN RUNNER, not the exporter. See etc/go/lib/canon-diff.mjs, whose single
# canonicalisation carries its `because` (DmnExport.hs:3212) and the condition
# for its own deletion.
set +e
L4_GO_SOURCE_BASENAME="$(basename "$GO_S_CORPUS")" \
  node "$GO_LIB/canon-diff.mjs" "$OUT" "$GOLDEN" --report "$DIFFLOG"
DIFF_RC=$?
L4_GO_SOURCE_BASENAME="$(basename "$GO_S_CORPUS")" \
  node "$GO_LIB/canon-diff.mjs" "$FID" "$GOLDEN_FID" --report "$GO_OUT/p7-dmn.fidelity.canon-diff.txt"
FID_DIFF_RC=$?
set -e

# --- 3. structural check: the same interchange gate CI runs -----------------
set +e
npx --yes --package=dmn-moddle node "$GO_ROOT/etc/validate-dmn.mjs" "$OUT" >"$GO_OUT/p7-dmn.validate.txt" 2>&1
VALIDATE_RC=$?
set -e
tail -3 "$GO_OUT/p7-dmn.validate.txt" || true

# --- 4. fidelity counts, parsed — never typed -------------------------------
read -r BLOCKING LOSSY ADVISORY < <(node "$GO_LIB/fidelity-counts.mjs" "$FID")

# --- 5. the execution question ----------------------------------------------
EXECUTABLE=0
if [[ -f "$CASES" ]]; then EXECUTABLE=1; fi

if [[ $DIFF_RC -ne 0 || $FID_DIFF_RC -ne 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "the regenerated DMN does not match the committed golden after declared canonicalisation; see $DIFFLOG. Either the exporter changed or the golden is stale — do NOT regenerate the golden from the CLI to make this green: jl4-test defends that file." \
    --artifact "$OUT" --artifact "$FID" --artifact "$DIFFLOG" \
    --metric "blocking=$BLOCKING" --metric "lossy=$LOSSY" --metric "advisory=$ADVISORY"
  exit "$GO_EXIT_FINDING"
fi

if [[ $VALIDATE_RC -ne 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "etc/validate-dmn.mjs rejected the emitted DMN; see $GO_OUT/p7-dmn.validate.txt" \
    --artifact "$OUT" --artifact "$FID" --artifact "$GO_OUT/p7-dmn.validate.txt" \
    --metric "blocking=$BLOCKING" --metric "lossy=$LOSSY" --metric "advisory=$ADVISORY"
  exit "$GO_EXIT_FINDING"
fi

if [[ $EXECUTABLE -eq 0 ]]; then
  go_receipt --status NOT-EXECUTABLE \
    --reason "the DMN regenerates identically to the committed golden (after the D1 canonicalisation) and passes the dmn-moddle interchange gate, and it CANNOT BE EXECUTED: neither engine harness can be pointed at it, because no cases file for the corpus DMN exists. This is a Blocking line in the conversion report, which is the only condition under which SPEC.md §6 permits G1 to proceed. R0 makes it a defect, not a caveat." \
    --blocker "no $CASES exists. etc/kie-dmn-check/run.sh and etc/camunda-dmn-check/run.sh both require --cases CASES.json, and the subject's sidecar declares that path without the file existing yet. Writing cases against $BLOCKING boxed literal expressions that cannot evaluate would manufacture a green the artifact has not earned — that is DMN Phase 5 (BKM emission) work, tracked in specs/todo/DMN-PHASE5-BUILD-PLAN.md." \
    --artifact "$OUT" --artifact "$FID" --artifact "$DIFFLOG" --artifact "$GO_OUT/p7-dmn.validate.txt" \
    --metric "blocking=$BLOCKING" --metric "lossy=$LOSSY" --metric "advisory=$ADVISORY" \
    --metric "canonicalisations=D1-golden-runner-source-uri"
  exit "$GO_EXIT_CLEAN"
fi

# Reached only once a corpus cases file exists — at which point the engines
# become the oracle and this leg's class rises from differential to execution.
set +e
KIE_CHECK_REQUIRED="${L4_GO_REQUIRED:-0}" "$GO_ROOT/etc/kie-dmn-check/run.sh" "$OUT" --cases "$CASES" >"$GO_OUT/p7-dmn.kie.txt" 2>&1
KIE_RC=$?
CAMUNDA_CHECK_REQUIRED="${L4_GO_REQUIRED:-0}" "$GO_ROOT/etc/camunda-dmn-check/run.sh" "$OUT" --cases "$CASES" >"$GO_OUT/p7-dmn.camunda.txt" 2>&1
CAM_RC=$?
set -e
if [[ $KIE_RC -ne 0 || $CAM_RC -ne 0 ]] || ! grep -q "VERDICT" "$GO_OUT/p7-dmn.kie.txt" || ! grep -q "VERDICT" "$GO_OUT/p7-dmn.camunda.txt"; then
  go_receipt --status DEGRADED \
    --reason "an engine harness did not print a VERDICT banner, or exited non-zero (kie $KIE_RC, camunda $CAM_RC). House convention: assert on the liveness banner, not the exit code — a harness that died before running also exits non-zero." \
    --artifact "$OUT" --artifact "$GO_OUT/p7-dmn.kie.txt" --artifact "$GO_OUT/p7-dmn.camunda.txt"
  exit "$GO_EXIT_FINDING"
fi
go_receipt --status PASS \
  --oracle-cmd "etc/kie-dmn-check/run.sh + etc/camunda-dmn-check/run.sh over $CASES, both printing a VERDICT banner" \
  --oracle-exit 0 --oracle-class execution \
  --oracle-because "the emitted DMN was executed by both target engines on committed cases and agreed" \
  --artifact "$OUT" --artifact "$FID" --artifact "$GO_OUT/p7-dmn.kie.txt" --artifact "$GO_OUT/p7-dmn.camunda.txt" \
  --metric "blocking=$BLOCKING" --metric "lossy=$LOSSY" --metric "advisory=$ADVISORY"
