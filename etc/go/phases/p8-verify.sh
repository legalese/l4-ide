#!/usr/bin/env bash
# P8 — formal verification (STRETCH). Rung 1 of the R5 ladder.
#
# THIS STAGE RUNS. It was scaffolded-and-refusing until `l4 verify` existed;
# ruling R5 (2026-08-02) put the query-planner ROBDD first, and this is that
# first rung: unsatisfiable rules, dead branches, vacuous guards and unreachable
# outcomes over the boolean skeleton of every DECIDE in the subject's modules.
# The R4 fork-space agreement/divergence sweep (rung 2) and an external model
# checker (rung 3) are still unbuilt, and the note on the receipt says so.
#
# NOT A DECLARED MILESTONE STAGE. `etc/go/go.sh` still lists `p8-verify` in
# UNIMPLEMENTED_STAGES and G1_STAGES does not contain it, so a plain
# `go.sh run --milestone g1` does not reach this script. That one-line driver
# change is owned elsewhere; until it lands, this leg is exercised by invoking
# the script directly with GO_ROOT/GO_RUN/GO_STAGE and the subject environment
# set, which writes a real receipt into a real journal. Everything below is
# written to be correct the moment the driver declares it.
#
# == The pass condition, and why the negative controls carry it
#
# The oracle here is NOT "the corpus came back clean". A consistency checker
# that can never go red reports every corpus clean, so a green corpus is
# evidence about the checker only once the checker is shown to be capable of
# going red — and of going red for the reason it claims. So this stage runs the
# verifier over five committed control fixtures with declared expectations
# (house convention 4: every positive control ships a negative sibling) and
# treats a control that misbehaves as BROKEN, not as a finding.
#
#   PASS      every control reproduces its declared verdict, AND every declared
#             corpus module was analysed with zero findings
#   DEGRADED  every control reproduces its declared verdict, AND some corpus
#             module has findings — that is this stage's OUTPUT, reported in the
#             report's own words, not a harness failure
#   BROKEN    a control did not reproduce its declared verdict; the checker is
#             defective or a control has gone stale, and either way nothing this
#             stage says about the corpus can be trusted
#
# == What a PASS here is worth
#
# Less than the word "verification" suggests, and the receipt says so on the
# record rather than in a comment. `l4 verify --help` carries the full bound;
# the short version is: the analysis is propositional (every leaf is an opaque
# atom, so no numeric or date contradiction is visible), it reads each DECIDE on
# its own without inlining callees, and it is sound but not complete. Silence is
# not a consistency proof.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "$GO_S_CORPUS" "${BASH_SOURCE[0]}" \
    ${GO_S_WIZARD:+"$GO_S_WIZARD"} \
    "$GO_ROOT/jl4/tests-cli/fixtures/verify-clean.l4" \
    "$GO_ROOT/jl4/tests-cli/fixtures/verify-unsat.l4" \
    "$GO_ROOT/jl4/tests-cli/fixtures/verify-dead-branch.l4" \
    "$GO_ROOT/jl4/tests-cli/fixtures/verify-vacuous-guard.l4" \
    "$GO_ROOT/jl4/tests-cli/fixtures/verify-seam.l4"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

LOG="$GO_OUT/p8-verify.txt"
: >"$LOG"

# --- the controls ------------------------------------------------------------
#
# These live beside the CLI test suite rather than in a subject sidecar on
# purpose: they are facts about the CHECKER, not about any body of law, and the
# same five files license this leg for every subject. l4-cli-test asserts the
# same expectations in-process, so a drift breaks the build before it reaches
# here — this is the belt to that suite's braces, and it is what lets a receipt
# written on a machine with no cabal still claim the checker works.
#
# Format: FIXTURE-STEM|EXPECTED-EXIT|EXPECTED-FINDING-KIND ("" = none)
CTRLDIR="$GO_ROOT/jl4/tests-cli/fixtures"
declare -a CONTROLS=(
  "verify-clean|0|"
  "verify-unsat|1|unsat"
  "verify-dead-branch|1|dead-branch"
  "verify-vacuous-guard|1|vacuous-guard"
  "verify-seam|1|unreachable-outcome"
)

declare -a ARTS=()
CTRL_OK=0
CTRL_BAD=0

{
  echo "P8 rung 1 — propositional consistency of the boolean decision skeleton."
  echo
  echo "NEGATIVE/POSITIVE CONTROLS (what licenses this leg's oracle):"
} >>"$LOG"

for spec in "${CONTROLS[@]}"; do
  STEM="${spec%%|*}"
  REST="${spec#*|}"
  WANT_EXIT="${REST%%|*}"
  WANT_KIND="${REST##*|}"
  SRC="$CTRLDIR/$STEM.l4"
  OUT="$GO_OUT/$STEM.verify.json"

  if [[ ! -f "$SRC" ]]; then
    echo "::error::the p8-verify control $STEM.l4 is missing from jl4/tests-cli/fixtures. A control that is not on disk is not a control." >&2
    go_broken "control fixture ${SRC#"$GO_ROOT"/} is absent"
  fi

  set +e
  "$L4" verify "$SRC" --format json -o "$OUT" --fixed-now "$GO_FIXED_NOW" >>"$LOG" 2>&1
  GOT_EXIT=$?
  set -e

  GOT_KIND="absent"
  if [[ -f "$OUT" ]] && [[ -n "$WANT_KIND" ]] && grep -q "\"$WANT_KIND\"" "$OUT"; then
    GOT_KIND="$WANT_KIND"
  fi

  if [[ "$GOT_EXIT" == "$WANT_EXIT" ]] && { [[ -z "$WANT_KIND" ]] || [[ "$GOT_KIND" == "$WANT_KIND" ]]; }; then
    CTRL_OK=$((CTRL_OK + 1))
    printf '  %-26s exit %s%s  REPRODUCES\n' "$STEM" "$GOT_EXIT" "${WANT_KIND:+, ${WANT_KIND}}" >>"$LOG"
  else
    CTRL_BAD=$((CTRL_BAD + 1))
    printf '  %-26s expected exit %s%s, got exit %s, kind %s  DID NOT REPRODUCE\n' \
      "$STEM" "$WANT_EXIT" "${WANT_KIND:+/${WANT_KIND}}" "$GOT_EXIT" "$GOT_KIND" >>"$LOG"
  fi
  ARTS+=(--artifact "$OUT")
done

if [[ $CTRL_BAD -gt 0 ]]; then
  cat "$LOG"
  echo "::error::$CTRL_BAD of ${#CONTROLS[@]} p8-verify controls did not reproduce their declared verdict. Until that is resolved, nothing this stage reports about the corpus means anything — a checker that cannot be shown to go red cannot license a green corpus. Fix l4 verify, or delete the stale control and say why in the same change." >&2
  go_broken "$CTRL_BAD of ${#CONTROLS[@]} control fixtures did not reproduce their declared verdict; see $LOG"
fi

# --- the corpus --------------------------------------------------------------

declare -a MODULES=("$GO_S_CORPUS")
[[ -n "${GO_S_WIZARD:-}" ]] && MODULES+=("$GO_S_WIZARD")

declare -a METRICS=()
TOTAL_FINDINGS=0
TOTAL_DECISIONS=0
TOTAL_ANALYSED=0
TOTAL_SKIPPED=0
TOTAL_MERGED=0
TOTAL_NESTED=0

{
  echo
  echo "CORPUS:"
} >>"$LOG"

for SRC in "${MODULES[@]}"; do
  STEM="$(basename "$SRC" .l4)"
  OUT="$GO_OUT/$STEM.verify.json"
  TXT="$GO_OUT/$STEM.verify.txt"

  set +e
  "$L4" verify "$SRC" --format json -o "$OUT" --fixed-now "$GO_FIXED_NOW" 2>>"$LOG"
  RC=$?
  "$L4" verify "$SRC" -o "$TXT" --fixed-now "$GO_FIXED_NOW" 2>>"$LOG"
  set -e
  # 0 = clean, 1 = findings. Anything else is the CLI failing on a module this
  # run has already typechecked, which is a harness defect.
  if [[ $RC -ne 0 && $RC -ne 1 ]]; then
    go_broken "l4 verify exited $RC on ${SRC#"$GO_ROOT"/}, a module this run has already typechecked; see $LOG"
  fi

  # The trailing newline is load-bearing: `read` returns 1 at EOF without a
  # delimiter, and the prelude runs under `set -e`, so a summary line without
  # one aborted this stage between the controls and the receipt — silently,
  # because the abort happened before the log was echoed.
  read -r D A S F M N < <(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const s = j.summary;
    process.stdout.write([s.decisions, s.analysed, s.skipped, s.findings,
                          s.mergedAtomOccurrences, s.nestedNotVisited].join(" ") + "\n");
  ' "$OUT")

  TOTAL_DECISIONS=$((TOTAL_DECISIONS + D))
  TOTAL_ANALYSED=$((TOTAL_ANALYSED + A))
  TOTAL_SKIPPED=$((TOTAL_SKIPPED + S))
  TOTAL_FINDINGS=$((TOTAL_FINDINGS + F))
  TOTAL_MERGED=$((TOTAL_MERGED + M))
  TOTAL_NESTED=$((TOTAL_NESTED + N))

  printf '  %-24s %s decisions, %s analysed, %s skipped (non-boolean), %s nested-not-visited, %s finding(s)\n' \
    "$STEM" "$D" "$A" "$S" "$N" "$F" >>"$LOG"

  METRICS+=(--metric "$STEM.decisions=$D")
  METRICS+=(--metric "$STEM.analysed=$A")
  METRICS+=(--metric "$STEM.skipped=$S")
  METRICS+=(--metric "$STEM.nested_not_visited=$N")
  METRICS+=(--metric "$STEM.findings=$F")
  ARTS+=(--artifact "$OUT" --artifact "$TXT")
done

cat "$LOG"
ARTS+=(--artifact "$LOG")

METRICS+=(--metric "controls_reproduced=$CTRL_OK/${#CONTROLS[@]}")
METRICS+=(--metric "decisions=$TOTAL_DECISIONS")
METRICS+=(--metric "analysed=$TOTAL_ANALYSED")
METRICS+=(--metric "skipped_non_boolean=$TOTAL_SKIPPED")
METRICS+=(--metric "nested_not_visited=$TOTAL_NESTED")
METRICS+=(--metric "findings=$TOTAL_FINDINGS")
METRICS+=(--metric "merged_atom_occurrences=$TOTAL_MERGED")

BOUND_NOTE="A clean run is a WEAK statement and the receipt refuses to imply otherwise. The analysis is propositional: every leaf (a projection, a comparison, an arithmetic test, a call to another DECIDE) is an opaque atom, so no numeric, interval, date or string contradiction is in range, and neither is anything that only appears once two named rules are unfolded against each other. Each DECIDE is read on its own. Findings are sound; silence is not a consistency proof. Full statement: l4 verify --help."

RUNG_NOTE="Rung 1 of 3. R5 (2026-08-02) ordered the P8 ladder as ROBDD first, the R4 fork-space agreement/divergence sweep second, an external model checker (TLA+/NuSMV/UPPAAL class) last. Rungs 2 and 3 are unbuilt: rung 2 needs the fork register P4 does not yet produce, rung 3 waits on the LTS semantics. $TOTAL_SKIPPED of $TOTAL_DECISIONS decisions are outside rung 1 entirely because they do not return BOOLEAN — they are counted, named in the artifact, and not reported as clean. A further $TOTAL_NESTED are outside it for a different reason: they are defined inside a WHERE clause, and neither this command nor the ladder's own entry point descends into one, so they are in NEITHER the analysed nor the skipped column. That is why the figure is on the receipt: 'analysed + skipped' does not total the corpus, and an exclusion nobody can size is an exclusion nobody believes."

if [[ $TOTAL_FINDINGS -gt 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "the verifier ran over ${#MODULES[@]} corpus module(s) and reported $TOTAL_FINDINGS propositional finding(s) across $TOTAL_ANALYSED analysed decision(s). Each finding names its decision, its site in the ladder, the atoms involved and what is wrong with it; see the .verify.txt artifacts. All ${#CONTROLS[@]} controls reproduced, so the checker was working when it said so — these are findings about the corpus, not about the harness." \
    "${ARTS[@]}" "${METRICS[@]}" \
    --note "$BOUND_NOTE" \
    --note "$RUNG_NOTE"
  exit "$GO_EXIT_FINDING"
fi

go_receipt --status PASS \
  --oracle-cmd "l4 verify <module> --format json  (x${#MODULES[@]}), plus ${#CONTROLS[@]} control fixtures with declared verdicts" \
  --oracle-exit 0 \
  --oracle-class structural \
  --oracle-because "the oracle is not 'the corpus came back clean' — a checker that cannot go red reports every corpus clean, so that would be a presence check wearing a stronger word. It is that the same binary, in the same run, reproduced the declared verdict of all ${#CONTROLS[@]} control fixtures: one clean module reporting zero findings, and one module per finding family (unsat, dead-branch, vacuous-guard, unreachable-outcome) each reporting exactly the family it is named for and exiting 1. Only then is 'zero findings over $TOTAL_ANALYSED analysed decisions' evidence of anything." \
  "${ARTS[@]}" "${METRICS[@]}" \
  --note "$BOUND_NOTE" \
  --note "$RUNG_NOTE"
