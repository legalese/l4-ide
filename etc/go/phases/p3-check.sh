#!/usr/bin/env bash
# P3-check — the mechanisable P3 house rules, over the milestone's module set.
#
# These are P3 HOUSE RULES, not corpus facts, so the same checks apply to
# whichever module set the driver resolved (2026-08-09): the committed
# encoding, or an additional encoding a run selected with `--encoding <id>`.
# The ACCEPTANCE half of P3 — "the deposit exists and the compiler accepts it"
# — is etc/go/phases/p3-encode.sh; the two stages deliberately layer.
#
# Two of P3's house rules are mechanically checkable and are checked here:
# BRANCH-over-ELSE-IF, and an @ref FR citation on every dated arm. The third —
# "isomorphic, reviewable section by section against the regulation" — is not
# checkable in principle, and it is RECORDED as unverified rather than omitted.

# The module set of the encoding THIS RUN IS ABOUT, resolved by the driver as
# GO_MODULES. There is no origin sentinel beside it any more: subject.mjs
# resolves the SELECTED encoding into the ordinary GO_S_ENCODING_MODULES and
# GO_S_MIN_* names, so this stage reads the encoding it was handed and never
# asks which one it is. When invoked directly without GO_MODULES — the
# documented direct-invocation route — the committed encoding's set is the
# default, preserving the pre-2026-08-09 contract. Kept byte-for-byte in step
# with the driver's own derivation (go.sh): a fallback that resolved a NARROWER
# set than a run does would make a direct invocation measure something other
# than what the receipt claims.
if [[ -z "${GO_MODULES+x}" ]]; then
  GO_MODULES="${GO_S_ENCODING_MODULES:-${GO_S_ENCODING:-}${GO_S_WIZARD:+ $GO_S_WIZARD}}"
fi

if [[ "${1:-}" == "--inputs" ]]; then
  # The dated-arm floor is a VERDICT INPUT this stage reads (sidecar-derived,
  # via GO_S_* env), so it is a digest contributor — `text:` entries are
  # literal contributors, per digestSet in lib/ledger.mjs. Without it a floor
  # edit escaped the digest and a resumed run replayed the old verdict
  # (measured 2026-08-09 on p6-tests' twin floor; this stage had the same
  # hole). The undeclared case is a distinct contributor because it changes
  # the receipt (the inapplicable-floor note below).
  # The per-origin branch that used to stand here is DELETED, not renamed:
  # once floors began travelling with their encoding, the resolver handed this
  # stage the SELECTED encoding's floor under the ordinary GO_S_MIN_DATED_ARMS
  # and the two arms became the same expression, character for character. What
  # still separates two encodings' digests is their MODULE PATHS, printed
  # below — the resolver forbids an additional encoding from re-declaring a
  # committed module, so the two sets cannot coincide.
  _floor="${GO_S_MIN_DATED_ARMS:-undeclared}"
  # THE PINNED CLOCK IS A VERDICT INPUT, so it is a digest contributor.
  # `--fixed-now` is what this stage passes to `l4` a few lines down, and it is
  # the answer to "as at what date does the law say this". It was in NO stage's
  # inputs: two runs of the same subject, same tree, same binary and DIFFERENT
  # --fixed-now produced byte-identical digests, and findReplayableAcrossRuns
  # filters on subject and digest only -- so the second run borrowed the first
  # run's answer about a different point in legal time. Declared per stage
  # rather than folded centrally like the l4 binary's sha, because only the
  # stages that actually pass --fixed-now should re-run when it moves.
  printf '%s\n' ${GO_MODULES:-} "${BASH_SOURCE[0]}" "text:min_dated_arms=$_floor" "text:fixed_now=${GO_FIXED_NOW:-unset}"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

# The deposit contract (ORCHESTRATOR.md §5.2): a module set the stage cannot
# see is a missing PREREQUISITE, reported as SKIPPED with the key to declare or
# the file to deposit — and fatal (exit 5) under L4_GO_REQUIRED=1 via go_skip.
declare -a MODULES=()
read -ra MODULES <<<"${GO_MODULES:-}"
if [[ ${#MODULES[@]} -eq 0 ]]; then
  # WHICH KEY to name is one of the two things in this stage that legitimately
  # vary with the encoding (the other is FLOOR_KEY below): the committed
  # encoding's modules are `encoding.modules`, an additional encoding's are
  # `encodings.<id>.modules`. Built from GO_S_ENCODING_ID so the reader is sent
  # to a key that exists — the old reason said `denovo.modules`, which no
  # sidecar has any more.
  case "${GO_S_ENCODING_ID:-primary}" in
    primary) MODULES_KEY="encoding.modules" ;;
    # No additional encoding is DECLARED at all, so there is no id to
    # name — the reader has to create the entry, not fill one in.
    undeclared) MODULES_KEY="encodings.<id>.modules (none is declared yet)" ;;
    *) MODULES_KEY="encodings.${GO_S_ENCODING_ID}.modules" ;;
  esac
  go_skip "the '$GO_S_ID' sidecar declares no module set for this run's encoding (${GO_S_ENCODING_ID:-primary}: $MODULES_KEY), so there is nothing to hold the P3 house rules against. Add it to $GO_S_DIR/subject.json; writing the module is agent work."
fi
declare -a MISSING=()
for m in "${MODULES[@]}"; do [[ -f "$m" ]] || MISSING+=("$m"); done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  go_skip "the declared module set has not been fully deposited yet: ${#MISSING[@]} of ${#MODULES[@]} module(s) are not files — ${MISSING[*]}. Depositing them is agent work; re-run this stage after."
fi

LOG="$GO_OUT/p3-check.txt"
: >"$LOG"
FINDINGS=0

note() { echo "$*" | tee -a "$LOG"; }

# --- 1. typecheck ------------------------------------------------------------
for f in "${MODULES[@]}"; do
  set +e
  "$L4" check "$f" --fixed-now "$GO_FIXED_NOW" >>"$LOG" 2>&1
  rc=$?
  set -e
  note "l4 check $(basename "$f") → exit $rc"
  [[ $rc -eq 0 ]] || FINDINGS=$((FINDINGS + 1))
done

# --- 2. house style: BRANCH over ELSE IF ------------------------------------
# P3's house rules name `BRANCH` over `ELSE IF` chains. Comment lines are
# excluded: the corpus discusses the rule in prose in several places.
ELSEIF=$(grep -nE '^[[:space:]]*[^-[:space:]].*\bELSE[[:space:]]+IF\b|^[[:space:]]*ELSE[[:space:]]+IF\b' "${MODULES[@]}" || true)
ELSEIF_N=$(printf '%s' "$ELSEIF" | grep -c . || true)
if [[ -n "$ELSEIF" ]]; then
  note "FINDING: $ELSEIF_N ELSE IF site(s), against P3's BRANCH-over-ELSE-IF house rule:"
  note "$ELSEIF"
  FINDINGS=$((FINDINGS + 1))
else
  note "house style: no ELSE IF chain in any module"
fi

# --- 3. temporal closure: an @ref on every dated arm ------------------------
# P3 requires an @ref FR citation on every dated arm. The checkable shape, made
# precise so it does not fire on prose or on test directives:
#
#   a DATED ARM is a line that compares `RULES EFFECTIVE DATE` against a `Date`
#   LITERAL, is not a comment, and is not an `EVAL UNDER RULES EFFECTIVE AT`
#   test directive (those are #EVAL scaffolding, not rule text).
#
#   its @ref must appear in the SAME contiguous run of non-blank lines. That is
#   the declaration's own block, which is where the corpus in fact puts it — a
#   fixed n-line window gets this wrong in both directions.
#
# An earlier version of this check used a 3-line window and reported 20 false
# findings, including comment prose and every #EVAL line. A check that cries
# wolf is worse than no check, so it is stated precisely or not at all.
#
# Negative control, run 2026-08-02 on the inaugural subject: deleting one
# `@ref` makes the check report both arms of the declaration that lost it.
# The subject's NOTES.md records the exact site. It is capable of red.
COUNTFILE="$GO_OUT/p3-dated-arms.count"
UNREFD=$(node - "$COUNTFILE" "${MODULES[@]}" <<'NODEEOF'
const fs = require("node:fs");
const bad = [];
let armCount = 0;
const countFile = process.argv[2];
for (const path of process.argv.slice(3)) {
  const lines = fs.readFileSync(path, "utf8").split("\n");
  lines.forEach((l, i) => {
    if (/^\s*--/.test(l)) return;                       // prose
    if (/EVAL UNDER RULES EFFECTIVE AT/.test(l)) return; // test directive
    if (!/`RULES EFFECTIVE DATE`/.test(l)) return;
    if (!/\bDate\s+\d/.test(l)) return;                  // parameterised, not dated
    armCount++;
    let from = i, to = i;
    while (from > 0 && lines[from - 1].trim() !== "") from--;
    while (to < lines.length - 1 && lines[to + 1].trim() !== "") to++;
    const block = lines.slice(from, to + 1).join("\n");
    if (!/@ref/.test(block)) bad.push(`${path.split("/").pop()}:${i + 1}: ${l.trim()}`);
  });
}
fs.writeFileSync(countFile, String(armCount));
process.stdout.write(bad.join("\n"));
NODEEOF
)
DATED_ARMS=$(cat "$COUNTFILE" 2>/dev/null || echo 0)

# The non-vacuity floor, symmetric with p6-tests.sh's MIN_ASSERTIONS.
#
# "every dated arm carries an @ref" is satisfied VACUOUSLY by an empty matched
# set, and the matcher is a single-physical-line regex: it requires
# `RULES EFFECTIVE DATE` and a `Date <digit>` literal on the SAME line. Reflow
# the two arms so the literal sits on the next line — by hand, or by any future
# formatter width change; `l4 format` preserves the split rather than repairing
# it — and armCount goes to 0 while the check prints a green
# "all 0 dated arm(s) carry an @ref". Measured 2026-08-02 on a copy of the
# corpus with every `@ref` deleted and the two arms reflowed: UNREFD empty,
# armCount 0, `l4 check` still exit 0.
#
# So a zero, or a drop below the known population, is a finding about the
# MATCHER and is reported as one. The floor is the subject's own measured
# dated-arm count for THIS ENCODING's module set (D2, 2026-08-09: floors
# travel with their encoding — subject.json checks.min_dated_arms for the
# committed one, encodings.<id>.checks.min_dated_arms for an additional one,
# and the resolver hands whichever the run selected down as
# GO_S_MIN_DATED_ARMS) with the population census in the sidecar's NOTES.md.
# Raise the floor when the module set gains arms; do not lower it to make this
# pass.
#
# THE ZERO-FLOOR CASE IS NOT A GREEN. A pinned floor of 0 over a matched count
# of 0 is exactly the vacuous pass this floor exists to prevent, so it prints
# NOT CHECKED with the reason on the receipt instead of "all 0 dated arm(s)
# carry an @ref". Measured on regcf's `cleanroom-2026-08` encoding
# (2026-08-09): the module IS temporally parameterised (8 decisions read the
# rule date, per the DMN exporter's D-RULEDATE advisory) but routes every arm
# through a helper abstraction over YMD constants, which this line-shaped
# matcher cannot see — 0 matched arms is that module's true population under
# THIS matcher, and the sidecar's NOTES.md carries the census.
declare -a TEMPORAL_NOTES=()
# The one thing here that genuinely varies with WHICH encoding this run was
# handed: the sidecar key a note tells the reader to edit. The committed
# encoding's floor is the top-level `checks.min_dated_arms`; an additional
# encoding's sits inside the encoding it measures. Naming the wrong one sends
# the reader to a key that does not exist — which is what the old note did, it
# said `denovo.checks.min_dated_arms`. The arms also differ in whether an
# UNDECLARED floor is reachable at all: subject.mjs REQUIRES `checks` on the
# committed encoding, so only an additional one can arrive with the floor
# empty, and when it does the receipt says so rather than passing quietly on a
# borrowed 0.
if [[ "${GO_S_ENCODING_ID:-primary}" == "primary" ]]; then
  MIN_DATED_ARMS="$GO_S_MIN_DATED_ARMS"
  FLOOR_KEY="checks.min_dated_arms"
else
  MIN_DATED_ARMS="${GO_S_MIN_DATED_ARMS:-0}"
  FLOOR_KEY="encodings.${GO_S_ENCODING_ID}.checks.min_dated_arms"
  if [[ -z "${GO_S_MIN_DATED_ARMS:-}" ]]; then
    TEMPORAL_NOTES+=(--note "the sidecar declares no $FLOOR_KEY; the dated-arm floor defaulted to 0, which makes the temporal-closure sub-check inapplicable rather than green. Measure this encoding and pin its floor.")
  fi
fi

if [[ -n "$UNREFD" ]]; then
  note "FINDING: dated arms with no @ref anywhere in their own declaration block:"
  note "$UNREFD"
  FINDINGS=$((FINDINGS + 1))
elif [[ "$DATED_ARMS" -eq 0 && "$MIN_DATED_ARMS" -eq 0 ]]; then
  note "temporal closure: NOT CHECKED — the matcher found no dated arms in this module set and the pinned floor ($FLOOR_KEY) is 0."
  note "  'every dated arm carries an @ref' over an empty matched set is a vacuous pass, and this stage refuses to print one as a green."
  note "  A 0 floor is honest only when 0 is the measured population; the sidecar's NOTES.md must carry that census."
  TEMPORAL_NOTES+=(--note "temporal closure NOT CHECKED (does not affect status): 0 dated arms matched and the pinned floor for this encoding ($FLOOR_KEY) is 0, so the @ref-per-dated-arm rule had nothing to hold — a vacuous pass refused, not a green earned; see the sidecar's NOTES.md for the population census")
elif [[ "$DATED_ARMS" -lt "$MIN_DATED_ARMS" ]]; then
  note "FINDING: the temporal-closure check matched only $DATED_ARMS dated arm(s), below the pinned floor of $MIN_DATED_ARMS."
  note "  An empty or near-empty matched set satisfies 'every dated arm carries an @ref' vacuously,"
  note "  so this is a finding about the matcher (or about a corpus that lost its dated arms), not a pass."
  note "  The matcher requires \`RULES EFFECTIVE DATE\` and a \`Date <digit>\` literal on the SAME line;"
  note "  a reflow across two lines makes an arm invisible to it and \`l4 format\` will not put it back."
  FINDINGS=$((FINDINGS + 1))
else
  note "temporal closure: all $DATED_ARMS dated arm(s) carry an @ref inside their own declaration block (floor: $MIN_DATED_ARMS)"
fi

# --- 4. label order over the surviving label-only inert strings -------------
# Under the enumeration-label ruling (2026-08-03) an inert string that restates
# the active node beside it is deleted, and the item's statutory label survives
# on the node's own line: `.. "(1)" ... transfer's `to the issuer``. What is left
# is a sequence, and a sequence can be read.
#
# WARNING LEVEL, deliberately, and Meng's ruling is the reason: "real legislation
# goes wobbly". A consolidated Act quotes repealed limbs by omission, so (a) (c)
# (d) is the normal shape of live text — GAPS are counted and reported as
# information, never as a warning. Out-of-ORDER labels are rarer and earn a
# warning line. NEITHER moves this stage's status: a check that turned a corpus
# red for quoting its source faithfully would be worse than no check.
#
# The scheme reading is in etc/go/lib/label-order.mjs, which reads each run under
# every scheme its tokens admit — (i) is both a letter and a roman one — and
# calls a run disordered only when NO reading orders it.
LABEL_OUT=$(node "$GO_LIB/label-order.mjs" "${MODULES[@]}")
LABELS=$(printf '%s\n' "$LABEL_OUT" | head -1 | /usr/bin/awk '{print $1}')
LABEL_GAPS=$(printf '%s\n' "$LABEL_OUT" | head -1 | /usr/bin/awk '{print $2}')
LABEL_WARNINGS=$(printf '%s\n' "$LABEL_OUT" | head -1 | /usr/bin/awk '{print $3}')
LABEL_LINES=$(printf '%s\n' "$LABEL_OUT" | tail -n +2)

note ""
if [[ "$LABEL_WARNINGS" -gt 0 ]]; then
  note "WARNING: $LABEL_WARNINGS rule(s) quote their statutory labels out of order:"
  note "$LABEL_LINES"
  note "  This does NOT affect this stage's status. Legislation goes wobbly, and a"
  note "  quotation that follows its source is not a defect; read the source before"
  note "  reordering anything."
else
  note "label order: $LABELS label-only inert string(s), none out of order"
fi
note "label gaps: $LABEL_GAPS missing step(s) between consecutive labels (informational — a repealed limb is a legitimate gap)"

# The warning rides in the receipt's own notes as well as in $LOG, because a
# reader of the journal must not have to open an artifact to learn that a
# warning fired. Gaps get a note too, and say in the note that they are not one.
declare -a LABEL_NOTES=()
if [[ "$LABEL_WARNINGS" -gt 0 ]]; then
  LABEL_NOTES+=(--note "WARNING (does not affect status): $LABEL_WARNINGS rule(s) quote their statutory labels out of order; see $LOG")
fi
if [[ "$LABEL_GAPS" -gt 0 ]]; then
  LABEL_NOTES+=(--note "$LABEL_GAPS gap(s) in the label sequences — informational, not a warning: a repealed or omitted limb is a legitimate gap in a consolidated text")
fi

# --- 5. the half that is not checkable, recorded rather than omitted --------
note ""
note "NOT CHECKED HERE, and not checkable in principle:"
note "  P3's 'isomorphic — a domain expert can review it against $GO_S_CITATION"
note "  section by section'. That is a judgement. SPEC.md §7.3 carries it as HG1."
note "  This stage's PASS means the two automatable house rules hold and the"
note "  module typechecks. It does not mean the encoding is faithful."

# Every figure this stage states is recorded as a metric, so a reader of the
# journal can reproduce the prose without opening the artifact. `ELSE IF` count
# used to live only in $LOG, which the journal names by path and sha256 — and a
# sha256 is not invertible, so "nine ELSE IF sites" was a number nobody could
# get back out of the journal it was said to come from.
METRICS=(--metric "modules=${#MODULES[@]}" --metric "encoding_id=${GO_S_ENCODING_ID:-primary}" \
         --metric "else_if_sites=$ELSEIF_N" --metric "dated_arms=$DATED_ARMS" --metric "min_dated_arms=$MIN_DATED_ARMS" \
         --metric "label_only_strings=$LABELS" --metric "label_order_warnings=$LABEL_WARNINGS" --metric "label_gaps=$LABEL_GAPS")

if [[ $FINDINGS -gt 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "$FINDINGS of the automatable P3 house-style checks failed; see $LOG" \
    --artifact "$LOG" "${METRICS[@]}" ${LABEL_NOTES[@]+"${LABEL_NOTES[@]}"} ${TEMPORAL_NOTES[@]+"${TEMPORAL_NOTES[@]}"}
  exit "$GO_EXIT_FINDING"
fi

# The oracle statement must not claim the temporal-closure half when it was
# NOT CHECKED (zero matched arms over a zero floor).
if [[ "$DATED_ARMS" -eq 0 && "$MIN_DATED_ARMS" -eq 0 ]]; then
  ORACLE_TEMPORAL="temporal closure NOT CHECKED (0 matched arms, floor 0 — see note)"
else
  ORACLE_TEMPORAL="an @ref inside the declaration block of every dated arm, over at least $MIN_DATED_ARMS matched arms"
fi
ORACLE_CHECKS="$(for f in "${MODULES[@]}"; do printf 'l4 check %s && ' "$(basename "$f")"; done)"
go_receipt \
  --status PASS \
  --oracle-cmd "${ORACLE_CHECKS}no ELSE IF chain && $ORACLE_TEMPORAL" \
  --oracle-exit 0 \
  --oracle-class structural \
  --oracle-because "typechecking is the compiler's own verdict on the module; the two grep checks are the mechanisable half of P3's house rules, and the dated-arm floor stops the second one passing over an empty matched set (a 0 floor demotes that sub-check to NOT CHECKED on the receipt rather than passing it). Faithfulness to the source regulation is NOT covered and is carried by HG1." \
  --artifact "$LOG" "${METRICS[@]}" ${LABEL_NOTES[@]+"${LABEL_NOTES[@]}"} ${TEMPORAL_NOTES[@]+"${TEMPORAL_NOTES[@]}"} \
  --note "isomorphism against $GO_S_CITATION is unverified by this stage and is HG1's subject"
