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
# p3-check.sh, which since 2026-08-09 (D1) runs over the SAME deposit at g2:
# the two stages are one phase's two halves, acceptance here and house rules
# there. And isomorphism, the deliverable itself, has no checkable form at
# all: SPEC.md §7.3 carries it as HG1, and this stage records it as
# unverified rather than omitting it.
#
# Requirements source: jl4/examples/legal/bna/SMOKE-REPORT.md §2 (p3-encode) —
# "the real stage needs: the l4 skill's inert-style guidance as the prompt
# substrate; JL4_LIBRARY_PATH pinned; and its green gate must parse the run log
# for `assertion failed` rather than trust exit 0 (§3.2)." The first is the
# skill's deposit runbook. The second the driver does (go.sh exports it). The third
# belongs to P6, not here: this stage runs `l4 check`, whose exit code IS
# load-bearing — only a typecheck error produces exit 1, which is exactly what
# is being asked. `l4 run`'s exit code is the one that lies, and p6-tests.sh
# reads results[] instead for precisely that reason.

# THE MODULE SET IS THE DRIVER'S, and this stage was the one that did not ask.
#
# `GO_MODULES` is what the driver resolved for THIS RUN; `GO_S_ENCODING_MODULES`
# is what the SIDECAR declares for the resolved encoding, and on the
# `--encoding undeclared` path those differ: the driver deliberately empties
# `GO_MODULES` because there is no additional encoding to iterate, while
# `subject.mjs`, called with no `--encoding`, still exports the COMMITTED
# encoding's modules. Reading the sidecar name directly, this stage typechecked
# all seven of `sg-succession`'s committed modules and wrote `PASS` with an
# oracle reading "the deposit is L4 the toolchain accepts" — for a deposit that
# does not exist. Its own `plan` row said `undeclared` at the same time.
#
# Its four sibling measurement stages (p3-check, p6-tests, p8-verify, p7-dmn)
# all carried this fallback already; p3-encode was the only one that did not,
# which is why the empty set reached `l4 check` instead of `go_skip`. The
# fallback exists so that a DIRECT invocation outside the driver resolves the
# same set a run would — measuring anything else would make the receipt claim
# something the stage did not do.
if [[ -z "${GO_MODULES+x}" ]]; then
  GO_MODULES="${GO_S_ENCODING_MODULES:-${GO_S_ENCODING:-}${GO_S_WIZARD:+ $GO_S_WIZARD}}"
fi

if [[ "${1:-}" == "--inputs" ]]; then
  # THE PINNED CLOCK IS A VERDICT INPUT, so it is a digest contributor.
  # `--fixed-now` is what this stage passes to `l4` a few lines down, and it is
  # the answer to "as at what date does the law say this". It was in NO stage's
  # inputs: two runs of the same subject, same tree, same binary and DIFFERENT
  # --fixed-now produced byte-identical digests, and findReplayableAcrossRuns
  # filters on subject and digest only -- so the second run borrowed the first
  # run's answer about a different point in legal time. Declared per stage
  # rather than folded centrally like the l4 binary's sha, because only the
  # stages that actually pass --fixed-now should re-run when it moves.
  printf '%s\n' ${GO_MODULES:-} "${BASH_SOURCE[0]}" "text:fixed_now=${GO_FIXED_NOW:-unset}"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

if [[ -z "${GO_MODULES:-}" ]]; then
  # NAME A KEY THE SCHEMA ACCEPTS. `denovo.modules` stopped existing at R2/R3,
  # and there are three encoding cases — a diagnostic that names the wrong one
  # sends the reader to edit the committed encoding when what they need is to
  # create an `encodings` entry.
  case "${GO_S_ENCODING_ID:-primary}" in
    primary) _KEY="encoding.modules" ;;
    undeclared) _KEY="encodings.<id>.modules (none is declared yet)" ;;
    *) _KEY="encodings.${GO_S_ENCODING_ID}.modules" ;;
  esac
  go_skip "the '$GO_S_ID' sidecar declares no $_KEY, so this subject has nowhere to deposit a de novo encoding. Add it to $GO_S_DIR/subject.json; the paths' existence is optional, because writing the L4 is agent work owned by the deposit runbook in .claude/skills/running-the-l4-pipeline/SKILL.md and by the writing-l4-rules skill."
fi

declare -a MODULES=()
read -ra MODULES <<<"$GO_MODULES"

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
  --oracle-because "typechecking is the compiler's own verdict on the module, and for 'l4 check' the exit code is the oracle: only a typecheck error produces exit 1. It proves the deposit is L4 the toolchain accepts. It proves NOTHING about fidelity to the source, about house style, or about whether the encoding answers anything — no #ASSERT is run here (that is P6) and no house-style check is applied here (that is p3-check, which runs over this same deposit in this same run)." \
  --artifact "$LOG" "${METRICS[@]}" \
  --note "P3's actual deliverable — 'isomorphic: a domain expert can review it against $GO_S_CITATION section by section' — is unverified by this stage and is HG1's subject (SPEC.md §7.3). A module that typechecks and says something else entirely reaches this same PASS" \
  --note "the two mechanisable P3 house rules (BRANCH over ELSE IF, an @ref on every dated arm) are p3-check's half of this phase: it runs over this run's same resolved module set, so read its receipt beside this one"
