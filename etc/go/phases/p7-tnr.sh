#!/usr/bin/env bash
# P7 — the TNR / NLG (prose round-trip) leg.
#
# THIS STAGE REGENERATES ITS ARTIFACT AND DIFFS IT. It used to report
# NOT-REGENERATED, and the blocker it named was true at the time: no `l4`
# subcommand emitted NLG prose, the goldens were produced IN-PROCESS by
# jl4/tests/Main.hs (`jl4NlgAnnotationsGolden`), and reaching that needed
# `cabal test jl4:jl4-test` — which this orchestrator will not run, because the
# build lock is a shared resource (CLAUDE.md §2.1).
#
# `l4 nlg FILE` closes it. Its payload is the SAME expression the golden
# producer writes:
#
#   Text.unlines (fmap Nlg.simpleLinearizer (toListOf (gplate @(Directive Resolved)) mod'))
#
# so the two are byte-identical for any module that typechecks, and that
# equality is itself pinned by l4-cli-test ("reproduces the committed regcf NLG
# golden byte for byte"). That is what upgrades this leg from a status about a
# file it did not produce into a `differential` oracle: regenerate, then diff.
#
# The goldens are defended independently — jl4-test fails if the in-process
# producer drifts — so reproducing them is a claim about THIS run's output, and
# not a comparison of the run against itself.
#
# A DIFF IS A FINDING, NOT A PASS. The run never writes into the tree: the
# regenerated prose lands in the run directory. A non-empty diff means the
# committed golden and the current corpus disagree, which is exactly the thing
# this leg exists to notice.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "$GO_S_CORPUS" "${BASH_SOURCE[0]}" \
    "$GO_S_TNR_GOLDEN" \
    ${GO_S_WIZARD:+"$GO_S_WIZARD"} \
    ${GO_S_TNR_WIZARD_GOLDEN:+"$GO_S_TNR_WIZARD_GOLDEN"}
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

LOG="$GO_OUT/p7-tnr.txt"
: >"$LOG"

# CONTENT hash, not `digest.mjs`. digestSet folds the PATH into the digest — by
# design, so a moved input re-runs its stage — which means two byte-identical
# files at different paths hash differently. Printing that beside a line saying
# IDENTICAL is how a reader ends up believing the opposite of what was measured.
content_sha() {
  node -e '
    import("'"$GO_LIB"'/ledger.mjs").then((m) => {
      process.stdout.write(m.sha256File(process.argv[1]));
    });
  ' "$1"
}

# The (source, golden) pairs this subject declares. The wizard pair is optional
# — subject.mjs marks `wizard_golden` as `o` — so it joins only when both the
# module and its golden are declared.
declare -a PAIRS=("$GO_S_CORPUS|$GO_S_TNR_GOLDEN")
if [[ -n "${GO_S_WIZARD:-}" && -n "${GO_S_TNR_WIZARD_GOLDEN:-}" ]]; then
  PAIRS+=("$GO_S_WIZARD|$GO_S_TNR_WIZARD_GOLDEN")
fi

declare -a ARTS=()
declare -a METRICS=()
DIFFERING=0
PAIRCOUNT=0

for pair in "${PAIRS[@]}"; do
  SRC="${pair%%|*}"
  GOLDEN="${pair##*|}"
  STEM="$(basename "$SRC" .l4)"
  OUT="$GO_OUT/$STEM.nlg"
  PAIRCOUNT=$((PAIRCOUNT + 1))

  if [[ ! -f "$GOLDEN" ]]; then
    go_broken "the subject declares an NLG golden at ${GOLDEN#"$GO_ROOT"/} and it is not on disk; subject.mjs validates exactly this, so reaching here means the resolver and the tree disagree"
  fi

  set +e
  "$L4" nlg "$SRC" -o "$OUT" --fixed-now "$GO_FIXED_NOW" >>"$LOG" 2>&1
  RC=$?
  set -e
  # A module p3-check typechecks must linearize. If it does not, the defect is
  # in the harness or the CLI, not in the corpus.
  [[ $RC -eq 0 ]] || go_broken "l4 nlg exited $RC on ${SRC#"$GO_ROOT"/}, a module this run has already typechecked; see $LOG"

  ARTS+=(--artifact "$OUT")
  METRICS+=(--metric "$STEM.lines=$(wc -l <"$OUT" | tr -d ' ')")
  METRICS+=(--metric "$STEM.bytes=$(wc -c <"$OUT" | tr -d ' ')")

  {
    echo "=== ${SRC#"$GO_ROOT"/}"
    echo "    regenerated  $(basename "$OUT")  content $(content_sha "$OUT")"
    echo "    golden       ${GOLDEN#"$GO_ROOT"/}  content $(content_sha "$GOLDEN")"
  } >>"$LOG"

  set +e
  diff -u "$GOLDEN" "$OUT" >"$GO_OUT/$STEM.nlg.diff" 2>&1
  DRC=$?
  set -e
  if [[ $DRC -eq 0 ]]; then
    echo "    IDENTICAL" >>"$LOG"
    rm -f "$GO_OUT/$STEM.nlg.diff"
  else
    DIFFERING=$((DIFFERING + 1))
    echo "    DIFFERS — see ${STEM}.nlg.diff" >>"$LOG"
    ARTS+=(--artifact "$GO_OUT/$STEM.nlg.diff")
  fi
done

cat "$LOG"
ARTS+=(--artifact "$LOG")

if [[ $DIFFERING -gt 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "l4 nlg regenerated the prose for all $PAIRCOUNT declared module(s), and $DIFFERING of them does not reproduce its committed golden. The regenerated text is in the run directory with the unified diff beside it; nothing in the tree was rewritten. A difference here means the committed golden and the current corpus disagree — either the corpus moved without the golden being refreshed (run 'cabal test jl4:jl4-test', which rewrites it), or the linearizer changed." \
    "${ARTS[@]}" "${METRICS[@]}" \
    --metric "pairs=$PAIRCOUNT" --metric "differing=$DIFFERING"
  exit "$GO_EXIT_FINDING"
fi

go_receipt --status PASS \
  --oracle-cmd "l4 nlg <module> -o <run>/<stem>.nlg && diff <golden> <run>/<stem>.nlg  (x$PAIRCOUNT)" \
  --oracle-exit 0 \
  --oracle-class differential \
  --oracle-because "this run REGENERATED the prose with 'l4 nlg' and it reproduces every committed .nlg.golden byte for byte. The goldens are defended by a separate gate — jl4-test's jl4NlgAnnotationsGolden writes them in-process and fails on drift — and l4-cli-test pins that the CLI emits the same expression as that producer, so this compares against something another gate already holds still rather than against itself." \
  "${ARTS[@]}" "${METRICS[@]}" \
  --metric "pairs=$PAIRCOUNT" --metric "differing=0" \
  --note "This leg reproduces prose; it does not yet round-trip it. SPEC.md §P7 names Times-New-Roman prose regeneration whose edits can be carried back into the L4, and the return leg (the TNR prototype on the unpushed nlg-roundtrip branch) is reachable from no l4 subcommand. What is measured here is the forward direction only."
