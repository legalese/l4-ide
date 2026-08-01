#!/usr/bin/env bash
# P3 at G1 — CHECK the existing corpus. There is no encoding here.
#
# SPEC.md §6 G1: "orchestrator skeleton drives the EXISTING corpus through every
# currently-green projection … No de novo encoding." The de novo half of P3 is
# etc/go/phases/p3-encode.sh, which refuses with a named blocker.
#
# Two of P3's house rules are mechanically checkable and are checked here:
# BRANCH-over-ELSE-IF, and an @ref FR citation on every dated arm. The third —
# "isomorphic, reviewable section by section against the regulation" — is not
# checkable in principle, and it is RECORDED as unverified rather than omitted.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "$GO_CORPUS" "$GO_WIZARD" "${BASH_SOURCE[0]}"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

LOG="$GO_OUT/p3-check.txt"
: >"$LOG"
FINDINGS=0

note() { echo "$*" | tee -a "$LOG"; }

# --- 1. typecheck ------------------------------------------------------------
for f in "$GO_CORPUS" "$GO_WIZARD"; do
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
ELSEIF=$(grep -nE '^[[:space:]]*[^-[:space:]].*\bELSE[[:space:]]+IF\b|^[[:space:]]*ELSE[[:space:]]+IF\b' "$GO_CORPUS" "$GO_WIZARD" || true)
ELSEIF_N=$(printf '%s' "$ELSEIF" | grep -c . || true)
if [[ -n "$ELSEIF" ]]; then
  note "FINDING: $ELSEIF_N ELSE IF site(s), against P3's BRANCH-over-ELSE-IF house rule:"
  note "$ELSEIF"
  FINDINGS=$((FINDINGS + 1))
else
  note "house style: no ELSE IF chain in either file"
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
# Negative control, run 2026-08-02: deleting the `@ref` at regcf.l4:472 makes
# the check report both arms of `the rule date is inside the COVID-19 temporary
# rules window` (lines 475, 476). It is capable of red.
COUNTFILE="$GO_OUT/p3-dated-arms.count"
UNREFD=$(node - "$COUNTFILE" "$GO_CORPUS" "$GO_WIZARD" <<'NODEEOF'
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
# MATCHER and is reported as one. The pin is the corpus's own measured count:
# regcf.l4 has 5 `RULES EFFECTIVE DATE` sites of which 2 are dated arms (the
# other 3 are comment prose ×2 and one parameterised `AT LEAST amendment`);
# regcf-wizard.l4 has 1, a comment. Raise MIN_DATED_ARMS when the corpus gains
# arms; do not lower it to make this pass.
MIN_DATED_ARMS=2

if [[ -n "$UNREFD" ]]; then
  note "FINDING: dated arms with no @ref anywhere in their own declaration block:"
  note "$UNREFD"
  FINDINGS=$((FINDINGS + 1))
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

# --- 4. the half that is not checkable, recorded rather than omitted --------
note ""
note "NOT CHECKED HERE, and not checkable in principle:"
note "  P3's 'isomorphic — a domain expert can review it against the regulation"
note "  section by section'. That is a judgement. SPEC.md §7.3 carries it as HG1."
note "  This stage's PASS means the two automatable house rules hold and the"
note "  module typechecks. It does not mean the encoding is faithful."

# Every figure this stage states is recorded as a metric, so a reader of the
# journal can reproduce the prose without opening the artifact. `ELSE IF` count
# used to live only in $LOG, which the journal names by path and sha256 — and a
# sha256 is not invertible, so "nine ELSE IF sites" was a number nobody could
# get back out of the journal it was said to come from.
METRICS=(--metric "else_if_sites=$ELSEIF_N" --metric "dated_arms=$DATED_ARMS" --metric "min_dated_arms=$MIN_DATED_ARMS")

if [[ $FINDINGS -gt 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "$FINDINGS of the automatable P3 house-style checks failed; see $LOG" \
    --artifact "$LOG" "${METRICS[@]}"
  exit "$GO_EXIT_FINDING"
fi

go_receipt \
  --status PASS \
  --oracle-cmd "l4 check regcf.l4 && l4 check regcf-wizard.l4 && no ELSE IF chain && an @ref inside the declaration block of every dated arm, over at least $MIN_DATED_ARMS matched arms" \
  --oracle-exit 0 \
  --oracle-class structural \
  --oracle-because "typechecking is the compiler's own verdict on the module; the two grep checks are the mechanisable half of P3's house rules, and the dated-arm floor stops the second one passing over an empty matched set. Faithfulness to the source regulation is NOT covered and is carried by HG1." \
  --artifact "$LOG" "${METRICS[@]}" \
  --note "isomorphism against 17 CFR Part 227 is unverified by this stage and is HG1's subject"
