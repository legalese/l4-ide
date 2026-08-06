#!/usr/bin/env bash
# P7 — the BPMN leg (three processes, one per regulative rule).
#
# The acceptance bar, per specs/todo/lexipedia-superset/PROCESS-TRACK.md §8, is
# acceptance + soundness + DMN wiring. Engine execution of the process is a
# declared NON-GOAL: the process runs on the parties, and jBPM is corroboration.
#
# THE THIRD ELEMENT OF THAT BAR — a businessRuleTask in the emitted BPMN wired
# to the emitted DMN — IS BUILT, AND THIS LEG CHECKS IT.
#
# This header and this leg's receipt both used to say the wiring was "NOT BUILT
# and has no checker", citing PROCESS-TRACK.md §8.3. That section now opens
# "mandated 2026-08-01, BUILT 2026-08-02" and reads "Status: BUILT"; each of the
# three committed goldens carries two `businessRuleTask` occurrences; and
# `etc/check-bpmn-dmn-refs.mjs` is the checker CI already runs
# (.github/workflows/pr-checks.yml:404). MEASURED 2026-08-03: that checker over
# the three goldens and the committed DMN exits 0, "all resolve". The leg was
# publishing a stale absence as a live finding — and the explainer republished
# it verbatim to a lay reader, beside a table row showing the wiring present.
#
# The references resolve against the COMMITTED DMN golden rather than this run's
# emitted one: a stage may not depend on another stage's output without
# declaring it as an input, and `p7-dmn` separately establishes that the emitted
# DMN is that golden byte for byte, or reports that it is not.
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
    "$GO_ROOT/etc/check-bpmn-soundness.mjs" "$GO_ROOT/etc/validate-bpmn.mjs" \
    "$GO_ROOT/etc/check-bpmn-dmn-refs.mjs" ${GO_S_DMN_GOLDEN:+"$GO_S_DMN_GOLDEN"}
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

# --- 5. the DMN wiring (PROCESS-TRACK.md §8.3) -------------------------------
# Every businessRuleTask names a (namespace, model, decision) triple, which is
# the whole of an engine's lookup key. A dangling one is the single defect this
# linkage can have that a reader cannot see: the diagram still draws, the file
# still parses, and the delegation silently does nothing.
WIRE_RC=0
WIRE_SAYS=""
if [[ -n "${GO_S_DMN_GOLDEN:-}" && -f "$GO_S_DMN_GOLDEN" ]]; then
  set +e
  node "$GO_ROOT/etc/check-bpmn-dmn-refs.mjs" "${FILES[@]}" "$GO_S_DMN_GOLDEN" >>"$LOG" 2>&1
  WIRE_RC=$?
  set -e
  echo "check-bpmn-dmn-refs → exit $WIRE_RC" | tee -a "$LOG"
  WIRE_SAYS="every businessRuleTask in the emitted processes names a (namespace, model, decision) triple that resolves in the committed DMN — which is the artifact p7-dmn compares this run's emitted DMN against, byte for byte"
else
  WIRE_RC=-1
  echo "check-bpmn-dmn-refs → NOT RUN (the subject declares no DMN golden)" | tee -a "$LOG"
  WIRE_SAYS="the subject declares no DMN golden, so the businessRuleTask references were resolved against nothing"
fi

# --- 6. the picture ----------------------------------------------------------
# `pictures.md` promises "a process diagram shows the same duty as a workflow",
# and until now the section printed the fidelity table and no diagram. The DI
# in each emitted file carries every coordinate, so this is a transform, not a
# layout engine — see the header of etc/bpmn-to-svg.mjs for why it is not
# bpmn-js. A render failure is a FINDING, not a warning: the renderer throws on
# any element outside the exporter's closed vocabulary, and that throw is how a
# newly-added node kind announces itself instead of silently vanishing from a
# legal diagram.
SVG_RC=0
declare -a SVGS=()
for f in "${FILES[@]}"; do
  svg="${f%.bpmn}.svg"
  if node "$GO_ROOT/etc/bpmn-to-svg.mjs" "$f" "$svg" >>"$LOG" 2>&1; then
    SVGS+=("$svg")
  else
    SVG_RC=1
    echo "bpmn-to-svg → FAILED on $(basename "$f")" | tee -a "$LOG"
  fi
done
echo "bpmn-to-svg → ${#SVGS[@]}/${#FILES[@]} rendered, exit $SVG_RC" | tee -a "$LOG"

ARTS=()
for f in "${FILES[@]}"; do
  ARTS+=(--artifact "$f")
  [[ -f "${f%.bpmn}.fidelity.txt" ]] && ARTS+=(--artifact "${f%.bpmn}.fidelity.txt")
  [[ -f "${f%.bpmn}.svg" ]] && ARTS+=(--artifact "${f%.bpmn}.svg")
done
ARTS+=(--artifact "$LOG")

RULE_METRIC="$(
  IFS=';'
  echo "${RULES[*]}"
)"

# Ordered after RULE_METRIC deliberately: every receipt below cites it, and an
# unset metric would be reported as an empty rule list rather than as an error.
if [[ $SVG_RC -ne 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "$((${#FILES[@]} - ${#SVGS[@]})) of ${#FILES[@]} emitted processes could not be rendered to SVG. etc/bpmn-to-svg.mjs covers exactly the closed vocabulary L4.Bpmn.IR emits and throws on anything else, so this is how a new node kind reports itself rather than disappearing from a legal diagram. See $LOG for the element it refused." \
    "${ARTS[@]}" --metric "processes=${#FILES[@]}" --metric "rules=$RULE_METRIC" \
    --metric "svg_exit=$SVG_RC"
  exit "$GO_EXIT_FINDING"
fi

if [[ $DIFFS -gt 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "$DIFFS emitted BPMN artifact(s) differ from their committed goldens; see $LOG. Do NOT regenerate the goldens to make this green — jl4-test and the CI bpmn job both defend them." \
    "${ARTS[@]}" --metric "processes=${#FILES[@]}" --metric "rules=$RULE_METRIC"
  exit "$GO_EXIT_FINDING"
fi

if [[ $SOUND_RC -ne 0 || $VALID_RC -ne 0 || $WIRE_RC -gt 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "a BPMN checker objected: soundness exit $SOUND_RC, interchange exit $VALID_RC, DMN-wiring exit $WIRE_RC. See $LOG." \
    "${ARTS[@]}" --metric "processes=${#FILES[@]}" --metric "rules=$RULE_METRIC" \
    --metric "soundness_exit=$SOUND_RC" --metric "interchange_exit=$VALID_RC" \
    --metric "dmn_wiring_exit=$WIRE_RC"
  exit "$GO_EXIT_FINDING"
fi

# The wiring check could not run at all. That is a coverage gap, not a green:
# with nothing to resolve against, every reference would pass vacuously.
if [[ $WIRE_RC -lt 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "all ${#FILES[@]} emitted processes reproduce their committed goldens byte for byte, pass soundness (S1 option-to-complete, S2 deadlock-free, S3 no dead node, S4 1-bounded) and pass the bpmn-moddle interchange gate — but the third element of this leg's acceptance bar was not checked at all: $WIRE_SAYS. A dangling businessRuleTask reference is the one defect this linkage can have that a reader cannot see." \
    "${ARTS[@]}" --metric "processes=${#FILES[@]}" --metric "rules=$RULE_METRIC" \
    --metric "soundness_exit=$SOUND_RC" --metric "interchange_exit=$VALID_RC" \
    --metric "dmn_wiring_exit=$WIRE_RC"
  exit "$GO_EXIT_FINDING"
fi

# Every element of this leg's own acceptance bar now has a checker, and every
# checker is green. PROCESS-TRACK.md §8's bar is acceptance + soundness + DMN
# wiring; engine execution of the process is a declared non-goal (R0).
go_receipt --status PASS \
  --oracle-cmd "l4 export --to bpmn, one per discovered rule, then cmp against each committed golden; check-bpmn-soundness.mjs; bpmn-moddle validate-bpmn.mjs; check-bpmn-dmn-refs.mjs against the committed DMN" \
  --oracle-exit 0 \
  --oracle-class differential \
  --oracle-because "all ${#FILES[@]} emitted processes reproduce their committed goldens byte for byte, pass soundness (S1 option-to-complete, S2 deadlock-free, S3 no dead node, S4 1-bounded), pass the bpmn-moddle interchange gate, and $WIRE_SAYS. Because the output IS the committed goldens, CI's jBPM baseline verdict over those goldens applies to it" \
  "${ARTS[@]}" \
  --metric "processes=${#FILES[@]}" \
  --metric "soundness_exit=$SOUND_RC" --metric "interchange_exit=$VALID_RC" \
  --metric "dmn_wiring_exit=$WIRE_RC" \
  --metric "rules=$RULE_METRIC" \
  --metric "svg_exit=$SVG_RC" \
  --note "each process is also rendered to a standalone SVG from its own diagram interchange, so the explainer's process subsection can show the duty rather than only describe it. The renderer is a coordinate transform, not a layout engine, and it throws on any element outside the exporter's vocabulary" \
  --note "engine execution of the process is a declared non-goal (R0): the process runs on the parties" \
  --note "the jBPM baseline comparator (etc/check-bpmn-kie-baseline.mjs) is NOT this leg's oracle: its baseline covers the whole committed BPMN corpus, so a three-file run reports the other three as NOT CHECKED and exits 1. Measured 2026-08-02."
