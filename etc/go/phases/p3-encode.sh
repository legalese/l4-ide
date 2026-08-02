#!/usr/bin/env bash
# P3 — encode from source, isomorphically, in inert style (de novo path).
# THE STAGE CHECKS THE DEPOSIT; THE AGENT WRITES THE ENCODING.
#
# SPEC.md §4 P3 names the first-class deliverable: L4 a domain expert can review
# against the regulation section by section, in inert style, with GIVEN over
# ASSUME, BRANCH over ELSE IF chains, and an @ref citation on every dated arm.
# Writing that is a model act — the encode prompt, the l4 skill's inert-style
# guidance, the judgement of what each provision means — and this orchestrator
# calls no model (ORCHESTRATOR.md §2.1). What it owns is the acceptance
# condition on the deposited module: it exists, and the compiler accepts it.
#
# THE FLOOR IS DELIBERATELY LOW, AND SAYING SO IS THE POINT. `l4 check` is the
# compiler's own verdict on the module and nothing more. The two mechanisable
# house rules — BRANCH-over-ELSE-IF and an @ref on every dated arm — live in
# p3-check.sh, which reads the subject's COMMITTED corpus; pointing that stage
# at a de novo deposit is unbuilt (ORCHESTRATOR.md §5.2). And isomorphism, the
# deliverable itself, has no checkable form at all: SPEC.md §7.3 carries it as
# HG1, and this stage records it as unverified rather than omitting it.
#
# Requirements source: jl4/examples/legal/bna/SMOKE-REPORT.md §2 (p3-encode) —
# "the real stage needs: the l4 skill's inert-style guidance as the prompt
# substrate; JL4_LIBRARY_PATH pinned; and its green gate must parse the run log
# for `assertion failed` rather than trust exit 0 (§3.2)." The first is the
# skill's G2 section. The second the driver does (go.sh exports it). The third
# belongs to P6, not here: this stage runs `l4 check`, whose exit code IS
# load-bearing — only a typecheck error produces exit 1, which is exactly what
# is being asked. `l4 run`'s exit code is the one that lies, and p6-tests.sh
# reads results[] instead for precisely that reason.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' ${GO_S_DENOVO_MODULES:-} "${BASH_SOURCE[0]}"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

if [[ -z "${GO_S_DENOVO_MODULES:-}" ]]; then
  go_skip "the '$GO_S_ID' sidecar declares no denovo.modules, so this subject has nowhere to deposit a de novo encoding. Add it to $GO_S_DIR/subject.json; the paths' existence is optional, because writing the L4 is agent work owned by the G2 section of .claude/skills/running-the-l4-pipeline/SKILL.md and by the writing-l4-rules skill."
fi

declare -a MODULES=()
read -ra MODULES <<<"$GO_S_DENOVO_MODULES"

declare -a MISSING=()
for m in "${MODULES[@]}"; do [[ -f "$m" ]] || MISSING+=("$m"); done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  go_skip "the de novo encoding has not been deposited yet: ${#MISSING[@]} of ${#MODULES[@]} declared module(s) are not files — ${MISSING[*]}. Encoding from the P1 bundle is agent work; deposit the module(s) and re-run this stage."
fi

LOG="$GO_OUT/p3-encode.txt"
: >"$LOG"
FINDINGS=0

for m in "${MODULES[@]}"; do
  set +e
  "$L4" check "$m" --fixed-now "$GO_FIXED_NOW" >>"$LOG" 2>&1
  rc=$?
  set -e
  echo "l4 check $(basename "$m") → exit $rc" | tee -a "$LOG"
  [[ $rc -eq 0 ]] || FINDINGS=$((FINDINGS + 1))
done

METRICS=(--metric "modules=${#MODULES[@]}" --metric "typecheck_failures=$FINDINGS")

if [[ $FINDINGS -gt 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "$FINDINGS of ${#MODULES[@]} deposited de novo module(s) do not typecheck; see $LOG" \
    --artifact "$LOG" "${METRICS[@]}"
  exit "$GO_EXIT_FINDING"
fi

ORACLE_CMD="$(for m in "${MODULES[@]}"; do printf 'l4 check %s && ' "$(basename "$m")"; done | sed 's/ && $//')"
go_receipt --status PASS \
  --oracle-cmd "$ORACLE_CMD" \
  --oracle-exit 0 \
  --oracle-class structural \
  --oracle-because "typechecking is the compiler's own verdict on the module, and for 'l4 check' the exit code is the oracle: only a typecheck error produces exit 1. It proves the deposit is L4 the toolchain accepts. It proves NOTHING about fidelity to the source, about house style, or about whether the encoding answers anything — no #ASSERT is run here (that is P6) and no house-style check is applied (p3-check reads the committed corpus, and pointing it at a de novo deposit is unbuilt)." \
  --artifact "$LOG" "${METRICS[@]}" \
  --note "P3's actual deliverable — 'isomorphic: a domain expert can review it against $GO_S_CITATION section by section' — is unverified by this stage and is HG1's subject (SPEC.md §7.3). A module that typechecks and says something else entirely reaches this same PASS" \
  --note "the two mechanisable P3 house rules (BRANCH over ELSE IF, an @ref on every dated arm) are NOT applied to the de novo deposit: p3-check.sh applies them to the subject's committed corpus, and re-pointing it is unbuilt — see ORCHESTRATOR.md §5.2"
