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

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "$GO_S_CORPUS" "${BASH_SOURCE[0]}" \
    "$GO_S_DMN_GOLDEN" \
    "$GO_S_DMN_FIDELITY_GOLDEN" \
    "$GO_ROOT/etc/validate-dmn.mjs" \
    "$GO_ROOT/etc/go/lib/canon-diff.mjs" \
    "$GO_S_DMN_CASES" \
    "$GO_ROOT/etc/kie-dmn-check/run.sh" \
    "$GO_ROOT/etc/camunda-dmn-check/run.sh"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

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
