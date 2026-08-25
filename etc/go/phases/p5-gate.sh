#!/usr/bin/env bash
# P5 — the adversarial gate (de novo path). THE STAGE RUNS THE JOINS; HG1 HOLDS
# THE GATE.
#
# SPEC.md §4 P5 states this gate's condition explicitly as a judgement:
# "independent adversarial review is satisfied the encoding is as good as it can
# be". A script cannot hold that. What a script can do is discharge the parts of
# the checklist that became mechanical when the three deposit contracts landed,
# and then say — on the receipt, in the report — exactly which parts it did not.
#
# The five checks SPEC.md §4 P5 names, and where each one actually lives:
#
#   1. house-style conformance      p3-check.sh (BRANCH over ELSE IF)
#   2. temporal closure             p3-check.sh (@ref per dated arm)
#   3. disposition of every P2 entry        HERE — the cross-file joins below
#   4. fork-register completeness           HG1 — unfalsifiable by construction
#   5. isomorphism spot-checks              HG1 — no checkable form
#
# Check 3 is the one that changed. "Every entry disposed" used to be a reviewer
# re-reading the source, which is exactly what failed in the BNA smoke run
# (SMOKE-REPORT.md §3.5: the human sweep disposed of four of five
# C-annotations and silently dropped one). It is now three joins with an exit
# code — `annotation-inventory-disposed` over the bundle's inventory,
# `fork-refs-resolve` from the register into the fork register, and
# `cross-refs-resolve` back the other way — and this stage runs all three at
# once by handing the validator all three deposits.
#
# Checks 4 and 5 are recorded as carried-by-HG1 notes on every receipt this
# stage writes, PASS included. A gate whose unmechanisable half is silent on a
# green run is a gate that has quietly become its mechanisable half.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "${GO_S_DENOVO_BUNDLE:-}" "${GO_S_DENOVO_REGISTER:-}" "${GO_S_DENOVO_FORKS:-}" \
    "${BASH_SOURCE[0]}" "$GO_ROOT/etc/go/lib/deposit-prelude.sh" \
    "$GO_ROOT/etc/go/lib/register-validate.mjs" \
    "$GO_ROOT/specs/todo/single-instruction-demo/schemas/source-bundle.schema.json" \
    "$GO_ROOT/specs/todo/single-instruction-demo/schemas/external-modifications.schema.json" \
    "$GO_ROOT/specs/todo/single-instruction-demo/schemas/fork-register.schema.json"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"
source "$GO_ROOT/etc/go/lib/deposit-prelude.sh"

# The two judgement halves, stated the same way whatever the mechanical half
# returns. They ride on the receipt, so they reach the report.
declare -a HG1_NOTES=(
  --note "CARRIED BY HG1 — fork-register completeness. No procedure establishes that every ambiguity in the source was found, so the register is checked for internal and cross-file consistency and never for exhaustiveness. SPEC.md §7.3; ORCHESTRATOR.md §5.2"
  --note "CARRIED BY HG1 — isomorphism spot-checks against the source text. SPEC.md §4's P3 deliverable is 'a domain expert can review it against the regulation section by section', which has no checkable form; this stage does not attempt one"
)

declare -a PRESENT=() ABSENT=()
for s in source-bundle external-modifications fork-register; do
  p="$(go_deposit_path "$s")"
  if [[ -z "$p" ]]; then
    ABSENT+=("$s (no $(go_deposit_key "$s") in $GO_S_DIR/subject.json)")
  elif [[ ! -f "$p" ]]; then
    ABSENT+=("$s ($p not deposited)")
  else
    PRESENT+=("$p")
  fi
done

# The joins are the whole mechanical content of this stage, and every one of
# them needs two deposits. With a deposit missing the validator would report its
# joins as `skip` and still exit 0 — a green receipt for a gate that checked
# nothing, which is the vacuous pass this lattice exists to refuse.
if [[ ${#ABSENT[@]} -gt 0 ]]; then
  go_skip "P5's mechanisable half is the cross-file joins over all three de novo deposits, and ${#ABSENT[@]} of 3 is/are unavailable: ${ABSENT[*]}. Every join needs two deposits, so with one missing this stage would validate each file alone, report its joins as 'skip', and exit 0 — a PASS for a gate that checked nothing. Deposit the missing register(s) and re-run." "${HG1_NOTES[@]}"
fi

LOG="$GO_OUT/p5-gate.txt"
BUNDLE="$(go_deposit_path source-bundle)"
REGISTER="$(go_deposit_path external-modifications)"
FORKS="$(go_deposit_path fork-register)"

# Shape first, for the same reason p1/p2/p4 do it: the validator's exit 2 must
# be allowed to mean "the SCHEMAS are unenforceable", which is BROKEN, and not
# "one of these files is not JSON", which is a finding about the deposit.
declare -a SHAPE_ERRS=()
for pair in "source-bundle:$BUNDLE" "external-modifications:$REGISTER" "fork-register:$FORKS"; do
  schema="${pair%%:*}"
  file="${pair#*:}"
  rc=0
  msg="$(go_deposit_shape "$file" "$schema")" || rc=$?
  [[ $rc -eq 0 ]] || SHAPE_ERRS+=("$file $msg")
done
if [[ ${#SHAPE_ERRS[@]} -gt 0 ]]; then
  printf '%s\n' "${SHAPE_ERRS[@]}" >"$LOG"
  go_receipt --status DEGRADED \
    --reason "${#SHAPE_ERRS[@]} of the three de novo deposits is/are not the deposit they are declared to be: ${SHAPE_ERRS[*]}" \
    --artifact "$LOG" "${HG1_NOTES[@]}"
  exit "$GO_EXIT_FINDING"
fi

# All three on one command line: every file is validated in its own right with
# the other two as peers, so a join owned by any of the three schemas runs,
# whichever was named primary.
RC=0
node "$GO_REGISTER_VALIDATE" external-modifications "$REGISTER" "$BUNDLE" "$FORKS" >"$LOG" 2>&1 || RC=$?

if [[ $RC -eq 2 ]]; then
  go_broken "register-validate.mjs exited 2 over three deposits whose JSON, kind and subject this stage had already checked, so what remains is a defect in the SCHEMAS — an unimplemented keyword, or an x-rules/implementation mismatch. See $LOG."
fi

RULES=$(grep -oE '[0-9]+ rule\(s\) checked' "$LOG" | awk '{s += $1} END {print s + 0}')
SKIPS=$(grep -c '^  skip ' "$LOG" || true)
SKIPS=${SKIPS:-0}
FIRED="$(go_deposit_rules_fired "$LOG")"

METRICS=(--metric "deposits=3" --metric "rules_checked=$RULES" --metric "joins_skipped=$SKIPS")

if [[ $RC -ne 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "P5's mechanisable joins over the three de novo deposits report findings; rule(s) that fired: ${FIRED:-(none named)}. SPEC.md §4 P5 refuses to start projection work until they are satisfied. See $LOG." \
    --artifact "$LOG" "${METRICS[@]}" "${HG1_NOTES[@]}"
  exit "$GO_EXIT_FINDING"
fi

# A skipped join here would mean a peer was absent, which the ABSENT gate above
# already refused — so this is a tripwire on that reasoning, not a status.
declare -a SKIPNOTE=()
[[ "$SKIPS" -gt 0 ]] && SKIPNOTE=(--note "$SKIPS join(s) still reported 'skip' with all three deposits present. That should not happen — every cross-file rule's peer is on the command line — so read it as a defect in this stage's peer assembly rather than as coverage")

go_receipt --status PASS \
  --oracle-cmd "node etc/go/lib/register-validate.mjs external-modifications $REGISTER $BUNDLE $FORKS" \
  --oracle-exit 0 \
  --oracle-class structural \
  --oracle-because "$RULES declared rules ran across all three de novo deposits with every peer present, which is what makes SPEC.md §4 P5's third check — 'disposition of every entry in P2's external-modification register (consumed by the encoding, consumed by a fork, or explicitly deferred with a reason)' — an exit code: 'annotation-inventory-disposed' joins the disposition table against the bundle's declared-complete annotation inventory, 'fork-refs-resolve' and 'cross-refs-resolve' check the register/fork cross-references in both directions, and the routing rules force a binding modification to name where it landed. Two of P5's five checks are discharged elsewhere (p3-check), and two are not discharged at all — see the notes." \
  --artifact "$LOG" "${METRICS[@]}" "${SKIPNOTE[@]}" "${HG1_NOTES[@]}" \
  --note "this PASS is NOT the P5 gate. SPEC.md §4's P5 condition is 'independent adversarial review is satisfied the encoding is as good as it can be' — a judgement, held by HG1. What passed here is the mechanisable third of its checklist"
