#!/usr/bin/env bash
# P7 — the BPMN leg (three processes, one per regulative rule).
#
# The acceptance bar, per specs/todo/lexipedia-superset/PROCESS-TRACK.md §8, is
# acceptance + soundness + DMN wiring. Engine execution of the process is a
# declared NON-GOAL: the process runs on the parties, and jBPM is corroboration.
#
# THIS LEG REPORTS `DEGRADED` EVEN WHEN EVERY CHECKER IS GREEN, because the
# third element of its own bar — a businessRuleTask in the emitted BPMN wired to
# the emitted DMN — is NOT BUILT and has no checker (PROCESS-TRACK §8.3 says so
# in those words, and gates it on DMN Phase 5). A leg with an unbuilt mandatory
# half may not print PASS.
#
# The rule names are DISCOVERED, not transcribed: `l4 export FILE --to bpmn`
# with no --rule exits 1 and enumerates them. The rule -> output-filename map
# is a REPO convention, not a CLI fact, so it is written down — in the subject
# sidecar (subject.json, legs['p7-bpmn'].rules), read here via the resolver —
# and its key set is asserted equal to the discovered set, so a rename fails
# loudly naming the exact strings rather than silently emitting under a new
# name.
#
# On the jBPM baseline: etc/check-bpmn-kie-baseline.mjs compares against
# etc/bpmn-kie-baseline.txt, which covers the WHOLE committed BPMN corpus. A
# run that emits only this subject's processes therefore always reports the
# others as NOT CHECKED and exits 1 — measured. So the baseline comparator is
# CI's gate over the committed goldens and is not this leg's oracle. What this
# leg establishes instead is that its output IS those goldens, byte for byte,
# which is what makes CI's verdict apply to it.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "$GO_S_CORPUS" "${BASH_SOURCE[0]}" \
    "$GO_ROOT/etc/check-bpmn-soundness.mjs" "$GO_ROOT/etc/validate-bpmn.mjs"
  while IFS=$'\t' read -r _rule stem; do
    [[ -n "$stem" ]] && printf '%s\n' "$GO_S_BPMN_EXPECTED_DIR/$stem.bpmn"
  done < <(node "$(dirname "${BASH_SOURCE[0]}")/../lib/subject.mjs" "$GO_SUBJECT" bpmn-rules)
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

LOG="$GO_OUT/p7-bpmn.txt"
: >"$LOG"

# rule name -> the committed golden's basename, from the subject sidecar.
declare -A RULE_FILE=()
while IFS=$'\t' read -r rule stem; do
  [[ -n "$rule" ]] && RULE_FILE["$rule"]="$stem"
done < <(node "$GO_LIB/subject.mjs" "$GO_SUBJECT" bpmn-rules)
[[ ${#RULE_FILE[@]} -gt 0 ]] || go_broken "the subject sidecar declares the p7-bpmn leg but its rules map came back empty"

# --- 0. discovery, then set-equality against the sidecar's map --------------
mapfile -t RULES < <(node "$GO_LIB/discover.mjs" rules "$GO_S_CORPUS")
[[ ${#RULES[@]} -gt 0 ]] || go_broken "the BPMN discovery call enumerated no regulative rules; the CLI's discovery shape changed"

DISCOVERED="$(printf '%s\n' "${RULES[@]}" | sort)"
MAPPED="$(printf '%s\n' "${!RULE_FILE[@]}" | sort)"
if [[ "$DISCOVERED" != "$MAPPED" ]]; then
  go_broken "the module's regulative rules have moved. Discovered: [$(echo "$DISCOVERED" | tr '\n' '|')] but the subject sidecar maps: [$(echo "$MAPPED" | tr '\n' '|')]. Update legs['p7-bpmn'].rules in $GO_S_DIR/subject.json and the committed goldens together."
fi
echo "discovered ${#RULES[@]} regulative rule(s), matching the golden map: ${RULES[*]}" | tee -a "$LOG"

# --- 1. emit one BPMN per rule, under the golden's own name ------------------
declare -a FILES=()
DIFFS=0
for rule in "${RULES[@]}"; do
  stem="${RULE_FILE[$rule]}"
  out="$GO_OUT/$stem.bpmn"
  set +e
  "$L4" export "$GO_S_CORPUS" --to bpmn --rule "$rule" -o "$out" --fidelity-report >>"$LOG" 2>&1
  rc=$?
  set -e
  [[ $rc -eq 0 ]] || go_broken "l4 export --to bpmn --rule '$rule' exited $rc"
  FILES+=("$out")

  # --- 2. differential oracle against the committed golden ------------------
  # MEASURED 2026-08-02: byte-identical, no canonicalisation needed — BPMN does
  # not carry the @ref source positions that make the DMN leg need one.
  golden="$GO_S_BPMN_EXPECTED_DIR/$stem.bpmn"
  if cmp -s "$out" "$golden"; then
    echo "$stem.bpmn: byte-identical to the committed golden" | tee -a "$LOG"
  else
    echo "$stem.bpmn: DIFFERS from $golden" | tee -a "$LOG"
    diff "$out" "$golden" >>"$LOG" 2>&1 || true
    DIFFS=$((DIFFS + 1))
  fi
  gfid="$GO_S_BPMN_EXPECTED_DIR/$stem.fidelity.txt"
  if [[ -f "$gfid" && -f "$GO_OUT/$stem.fidelity.txt" ]]; then
    cmp -s "$GO_OUT/$stem.fidelity.txt" "$gfid" || {
      echo "$stem.fidelity.txt: DIFFERS from $gfid" | tee -a "$LOG"
      DIFFS=$((DIFFS + 1))
    }
  fi
done

# --- 3. soundness (pure node, zero deps, no network) -------------------------
set +e
node "$GO_ROOT/etc/check-bpmn-soundness.mjs" "${FILES[@]}" >>"$LOG" 2>&1
SOUND_RC=$?
set -e
echo "check-bpmn-soundness → exit $SOUND_RC" | tee -a "$LOG"

# --- 4. interchange validity (the @10 pin is load-bearing) -------------------
set +e
npx --yes --package=bpmn-moddle@10 node "$GO_ROOT/etc/validate-bpmn.mjs" "${FILES[@]}" >>"$LOG" 2>&1
VALID_RC=$?
set -e
echo "validate-bpmn → exit $VALID_RC" | tee -a "$LOG"

ARTS=()
for f in "${FILES[@]}"; do
  ARTS+=(--artifact "$f")
  [[ -f "${f%.bpmn}.fidelity.txt" ]] && ARTS+=(--artifact "${f%.bpmn}.fidelity.txt")
done
ARTS+=(--artifact "$LOG")

RULE_METRIC="$(
  IFS=';'
  echo "${RULES[*]}"
)"

if [[ $DIFFS -gt 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "$DIFFS emitted BPMN artifact(s) differ from their committed goldens; see $LOG. Do NOT regenerate the goldens to make this green — jl4-test and the CI bpmn job both defend them." \
    "${ARTS[@]}" --metric "processes=${#FILES[@]}" --metric "rules=$RULE_METRIC"
  exit "$GO_EXIT_FINDING"
fi

if [[ $SOUND_RC -ne 0 || $VALID_RC -ne 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "a BPMN checker objected: soundness exit $SOUND_RC, interchange exit $VALID_RC. See $LOG." \
    "${ARTS[@]}" --metric "processes=${#FILES[@]}" --metric "rules=$RULE_METRIC" \
    --metric "soundness_exit=$SOUND_RC" --metric "interchange_exit=$VALID_RC"
  exit "$GO_EXIT_FINDING"
fi

# Green on every checker that exists — and still DEGRADED, because the leg's own
# acceptance bar has a third element with no implementation.
go_receipt --status DEGRADED \
  --reason "all ${#FILES[@]} emitted processes reproduce their committed goldens byte for byte, pass soundness (S1 option-to-complete, S2 deadlock-free, S3 no dead node, S4 1-bounded), and pass the bpmn-moddle interchange gate. Because the output IS the committed goldens, CI's jBPM baseline verdict over those goldens applies to it. The leg is nonetheless DEGRADED because the THIRD element of its own acceptance bar — a businessRuleTask wiring the emitted BPMN to the emitted DMN — is NOT BUILT and has no checker; PROCESS-TRACK.md §8.3 declares it mandated and unbuilt, gated on DMN Phase 5 BKM emission. A leg with an unbuilt mandatory half may not print PASS." \
  "${ARTS[@]}" \
  --metric "processes=${#FILES[@]}" \
  --metric "soundness_exit=$SOUND_RC" --metric "interchange_exit=$VALID_RC" \
  --metric "rules=$RULE_METRIC" \
  --note "engine execution of the process is a declared non-goal (R0): the process runs on the parties" \
  --note "the jBPM baseline comparator (etc/check-bpmn-kie-baseline.mjs) is NOT this leg's oracle: its baseline covers the whole committed BPMN corpus, so a three-file run reports the other three as NOT CHECKED and exits 1. Measured 2026-08-02."
