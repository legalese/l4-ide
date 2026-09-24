#!/usr/bin/env bash
# P7 — the Catala leg.
#
# `l4 export catala FILE` lowers an L4 module to Catala, the French/EU tax-and-benefit
# language whose whole design is the default-logic structure that statutes
# actually have (a general rule plus exceptions that defeat it). The emitter is
# specified in specs/todo/CATALA-EXPORT-SPEC.md.
#
# WHY THIS LEG EXISTS, AND WHY `l4 export catala`'s OWN EXIT CODE IS NOT THE GATE.
# `l4 export catala` exits 0 on emissions that Catala then REJECTS. The measured shape
# is smucclaw/l4-ide#958: a non-`@export` helper routed between two `@export`
# rules lowers to a toplevel definition with a scope call inside it, which the
# emitter is happy to write and `catala typecheck` refuses. So an emitter that
# returned 0 tells you a file was produced and nothing whatever about whether
# Catala accepts it. The gate here is the external toolchain, via
# etc/validate-catala.mjs, and the emitter's exit code is only the first of the
# two things that can go wrong.
#
# THE THREE LAYERS, which are three different claims (the validator's own
# header is the long form):
#
#   1. `catala typecheck` — the emitted module is well-formed Catala and its
#      types agree. Syntax and arity; nothing semantic.
#   2. `catala proof` — the NoOverlappingExceptions half. The Mode B ladders
#      are emitted as a LINEAR chain precisely so two rungs can never both win,
#      and this is the only thing anywhere that notices if that stops being
#      true. It reports through WARNINGS and exits 0 whatever it finds, which
#      is why the validator greps its output rather than trusting its status.
#   3. `clerk test` — every ```catala-test-cli block in the emission is re-run
#      by Catala's own interpreter and its output compared. Those blocks hold
#      values computed by L4's evaluator (R7), so a green `clerk test` is the
#      claim that matters: two independently written evaluators agree on these
#      points. §10.3 of the spec records a ladder-direction bug that layer 1
#      was green on and layer 3 caught.
#
# ORACLE CLASS: `execution`, and the choice is argued rather than assumed.
# references/status-vocabulary.md defines `execution` as "the artifact ran on
# its target engine, on cases, and agreed". Layer 3 is exactly that: the
# emitted .catala_en is interpreted by Catala, over the cases the emission
# carries, and every value is compared against what L4 computed. `structural`
# would describe layers 1 and 2 alone — a checker modelling the artifact's
# semantics without running it — and would UNDERSTATE what happened, because
# code ran and numbers were compared. The DMN leg makes the same claim on the
# same grounds.
#
# THE LIMIT OF THAT CLAIM, stated because the class does not carry it. The
# expected values in those blocks were computed by L4's own evaluator during
# this same emission, so agreement is CROSS-LANGUAGE agreement — Catala's
# interpreter against L4's — and not a claim that either one says what the
# source law says. A shared misreading of the statute agrees with itself. What
# this leg falsifies is a lowering that changes the answer; isomorphism is
# HG1's, and it always was.
#
# WHAT A `DEGRADED` HERE MEANS: a finding about the ENCODING, not about the
# machine. The emitter refused, or Catala rejected what it wrote, or an
# emission carried no executable test at all. A missing toolchain is `SKIPPED`
# and says which binaries and which opam switch.

# The module set this leg iterates. The driver exports GO_MODULES as the
# SELECTED encoding's modules; invoked directly without it, fall back to the
# selected encoding's own set before the entry module, so a hand-run under
# `--encoding <id>` emits from THAT encoding rather than from the committed
# one. Same resolution p7-dmn's emit-only arm uses.
if [[ -z "${GO_MODULES+x}" ]]; then
  GO_MODULES="${GO_S_ENCODING_MODULES:-${GO_S_ENCODING:-}}"
fi

if [[ "${1:-}" == "--inputs" ]]; then
  # THE PINNED CLOCK IS A VERDICT INPUT, so it is a digest contributor.
  # `--fixed-now` is what this stage passes to `l4 export catala` below, and it is the
  # answer to "as at what date does the law say this". Two runs of the same
  # subject, same tree, same binary and DIFFERENT --fixed-now must not digest
  # alike, or the second borrows the first's answer about a different point in
  # legal time. Same reasoning, and the same spelling, as p7-akn's.
  #
  # etc/validate-catala.mjs is listed because it IS the oracle: an edit to what
  # it enforces must re-run this stage rather than replay its verdict.
  printf '%s\n' ${GO_MODULES:-} "${BASH_SOURCE[0]}" \
    "$GO_ROOT/etc/validate-catala.mjs" \
    "text:fixed_now=${GO_FIXED_NOW:-unset}"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

LOG="$GO_OUT/p7-catala.txt"
: >"$LOG"

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

if [[ "${GO_S_ENCODING_ID:-primary}" == "primary" ]]; then
  S_MODULES_KEY="encoding.modules"
else
  S_MODULES_KEY="encodings['$GO_S_ENCODING_ID'].modules"
fi

declare -a MODULES=()
read -ra MODULES <<<"${GO_MODULES:-}"
if [[ ${#MODULES[@]} -eq 0 ]]; then
  go_skip "the '$GO_S_ID' sidecar declares no $S_MODULES_KEY, so there is no module to lower to Catala. Add it to $GO_S_DIR/subject.json; writing the module is agent work."
fi

# --- does this binary have the subcommand at all? ---------------------------
#
# A BROKEN, not a finding: the leg is declared, so the repo believes `l4
# export catala` exists. If it does not, nothing this stage could report would be a
# statement about the encoding. Probed once, before any emission, so the
# diagnostic names the cause rather than arriving as N identical failures.
#
# THE EXIT CODE IS NOT THE PROBE, and this is the trap. `l4`'s bare form is
# `l4 FILE`, so an unrecognised first word is read as a FILENAME rather than
# refused as an unknown subcommand: MEASURED, `l4 bogusverb --help` prints the
# TOP-LEVEL help and exits 0. A missing subcommand would therefore pass an
# exit-code check silently, which is the one thing this probe exists to catch.
# What distinguishes them is the Usage line: the subcommand's own help opens
# `… export catala FILE …`, the top-level help opens `… (COMMAND | FILE …)`.
#
# THE PROGRAM NAME IS NOT PART OF THE PATTERN, and anchoring on it was a defect
# here. optparse-applicative prints `Usage: <argv0> catala …` from the
# binary's own basename, so a probe matching the literal `Usage: l4 export catala `
# reports BROKEN — which STOPS THE WHOLE RUN — for any `l4` that is not named
# exactly `l4`. That is not an exotic configuration: CLAUDE.md §3.2.1 tells you
# to copy the binary somewhere unique before probing with it, and §3.1 has
# people pointing `L4` at whatever build they need. Measured 2026-09-21 on a
# snapshot named `l4-milescard-snapshot`, which printed
# `Usage: l4-milescard-snapshot catala ` and was called broken.
set +e
"$L4" export catala --help >"$GO_OUT/p7-catala.help.txt" 2>&1
HELP_RC=$?
set -e
if [[ $HELP_RC -ne 0 ]] || ! grep -qE '^Usage: [^ ]+ export catala ' "$GO_OUT/p7-catala.help.txt"; then
  go_broken "the l4 binary at $L4 has no usable 'catala' subcommand: \`l4 export catala --help\` exited $HELP_RC and did not print a 'Usage: <program> export catala …' line — it printed \"$(head -1 "$GO_OUT/p7-catala.help.txt" 2>/dev/null)\". An unknown first word is parsed as a FILENAME by this CLI, so the exit code alone would not have shown this. Leg legs['p7-catala'] is declared for subject '$GO_S_ID', so either the binary predates the emitter or the subcommand was renamed; rebuild, or undeclare the leg."
fi

# --- emit, one module at a time ---------------------------------------------
declare -a EMITTED=()
declare -a ARTS=()
declare -a NO_EXPORT=()
MODULES_TOTAL=${#MODULES[@]}

for m in "${MODULES[@]}"; do
  REL="${m#"$GO_ROOT"/}"
  # A module with no `@export` lowers to a Catala module with no scope anyone
  # can call, which proves nothing and would drag the whole leg red for a
  # subject that simply has a helper module. Recorded as a COUNT, never as a
  # failure — and never silently, because "0 of 3 modules emitted" and "3 of 3
  # emitted and all green" must not print the same receipt.
  if ! grep -q '@export' "$m"; then
    NO_EXPORT+=("$REL")
    echo "=== $REL — no @export annotation; nothing deployable to lower. Skipped." >>"$LOG"
    continue
  fi

  STEM="$(basename "$m" .l4)"
  # THE OUTPUT BASENAME IS NOT FREE: IT BECOMES THE CATALA MODULE NAME.
  #
  # `l4 export catala -o FILE` derives the emitted `> Module X` from FILE's basename,
  # and Catala identifiers admit only letters, digits and `_`, starting with a
  # letter. So `-o dbs-yuu.catala_en` is REFUSED outright — "`dbs-yuu` cannot be
  # a Catala module name … e.g. `dbsyuu.catala_en`" — and the emitter exits 1
  # before writing anything.
  #
  # Naming the emission after the L4 stem was therefore a defect in THIS LEG,
  # not a finding about any encoding, and it presented as one: the first
  # hyphenated module in the set failed with `modules_emitted=0` and the
  # toolchain gate never ran. It survived the leg's first review because every
  # module the controls used happened to have a hyphen-free stem. Measured
  # 2026-09-21 on `sg-miles-card` (13 modules, every issuer stem hyphenated) and
  # reproduced in this repo on `jl4/examples/catala/flat-tax.l4`.
  #
  # Strip rather than substitute, because that is what the emitter's own remedy
  # line suggests, and record the mapping below so an artifact can still be
  # traced back to the module it came from.
  SAFE="${STEM//[^A-Za-z0-9_]/}"
  # A stem of punctuation alone strips to nothing, and a leading digit is as
  # invalid as a hyphen. Both get a prefix rather than a silent empty name.
  [[ -z "$SAFE" ]] && SAFE="m_${#EMITTED[@]}"
  [[ "$SAFE" =~ ^[0-9] ]] && SAFE="m_$SAFE"
  OUT="$GO_OUT/$SAFE.catala_en"
  # Two modules in different directories may share a basename, and STRIPPING
  # CREATES COLLISIONS THAT DID NOT EXIST — `dbs-yuu.l4` and `dbsyuu.l4` both
  # land on `dbsyuu`. The validator stages each emission in a directory named
  # after this file, so a collision would have one silently overwrite the other.
  # The disambiguator is `_2`, not `-2`: a hyphen here would reintroduce exactly
  # the refusal this block exists to avoid.
  N=1
  while [[ -e "$OUT" ]]; do
    N=$((N + 1))
    OUT="$GO_OUT/${SAFE}_$N.catala_en"
  done
  # THE MAPPING LINE, and WHY the name moved. There are two different reasons
  # and they must not print the same sentence: `dbsyuu` IS a valid Catala module
  # name, so saying it is not — which an earlier draft of this line did, because
  # it tested only whether the name had changed — is a false statement in the
  # artifact a reader traces the emission through.
  WHY=""
  [[ "$SAFE" != "$STEM" ]] && WHY="'$STEM' is not a Catala module name"
  if [[ $N -gt 1 ]]; then
    [[ -n "$WHY" ]] && WHY="$WHY, and "
    WHY="${WHY}another module in this set already emitted as '$SAFE.catala_en'"
  fi
  if [[ -n "$WHY" ]]; then
    RENAMED=$((${RENAMED:-0} + 1))
    echo "=== $REL -> $(basename "$OUT")  [renamed: $WHY]" >>"$LOG"
  else
    echo "=== $REL -> $(basename "$OUT")" >>"$LOG"
  fi
  # Per module, into its own file. The combined log is an artifact and is
  # useful; it is NOT something to slice a diagnostic out of, because `l4`
  # prints a long `Info | updateFileDiagnostics` dump of every satisfied
  # assertion before it says anything about Catala.
  # Named after the EMISSION, not the module: the emission's basename is
  # already unique within this run (the loop above made it so), and a log named
  # after the module would collide for exactly the pairs the loop just
  # disambiguated.
  MOUT="$GO_OUT/p7-catala.emit-$(basename "$OUT" .catala_en).txt"
  set +e
  "$L4" export catala "$m" -o "$OUT" --fixed-now "$GO_FIXED_NOW" >"$MOUT" 2>&1
  RC=$?
  set -e
  cat "$MOUT" >>"$LOG"
  if [[ $RC -ne 0 ]]; then
    [[ -f "$OUT" ]] && ARTS+=(--artifact "$OUT")
    ARTS+=(--artifact "$MOUT")
    # THE REFUSAL, NOT A TAIL OF THE LOG. `l4 export catala` prints one header line
    # and then one `  - in <decision>: <why>` bullet per decision it cannot
    # compile. Slicing the last N lines instead — which this script did until
    # its own first live run — quotes an arbitrary SUFFIX of that list and
    # reports fewer findings than there are, with nothing saying so. Measured
    # 2026-09-21 on chubb: five bullets, of which a `tail -3` showed three.
    REFUSAL="$(sed -n '/^l4 export catala: /,$p' "$MOUT")"
    [[ -z "$REFUSAL" ]] && REFUSAL="$(grep -v '^  ' "$MOUT" | tail -5)"
    NBULLETS="$(printf '%s\n' "$REFUSAL" | grep -c '^  - ' || true)"
    QUOTED="$(printf '%s\n' "$REFUSAL" | head -6 | tr '\n' ' ' | tr -s ' ')"
    ELIDED=""
    [[ "${NBULLETS:-0}" -gt 5 ]] && ELIDED=" (showing 5 of $NBULLETS; all of them are in $(basename "$MOUT"))"
    go_receipt --status DEGRADED \
      --reason "l4 export catala exited $RC on $REL, so no Catala was emitted for it and the toolchain gate never ran. The emitter refusing is a finding about the ENCODING, not about this machine: it names each decision it cannot lower and why. Emitter said: ${QUOTED}${ELIDED}" \
      "${ARTS[@]}" --artifact "$LOG" \
      --metric "modules_total=$MODULES_TOTAL" \
      --metric "modules_emitted=${#EMITTED[@]}" \
      --metric "modules_without_export=${#NO_EXPORT[@]}" \
      --metric "basenames_rewritten=${RENAMED:-0}" \
      --metric "emitter_exit=$RC" \
      --metric "emitter_refusals=${NBULLETS:-0}"
    exit "$GO_EXIT_FINDING"
  fi
  EMITTED+=("$OUT")
  ARTS+=(--artifact "$OUT")
  echo "    emitted $(basename "$OUT")  $(wc -c <"$OUT" | tr -d ' ') bytes" >>"$LOG"
done

if [[ ${#EMITTED[@]} -eq 0 ]]; then
  cat "$LOG"
  go_receipt --status DEGRADED \
    --reason "every one of the $MODULES_TOTAL module(s) this encoding declares carries no \`@export\` annotation, so there is nothing to lower: a Catala module with no callable scope cannot be typechecked into a claim about anything. The leg is declared for subject '$GO_S_ID' and there is no deployable surface for it to measure. Either mark the decisions this subject is about with \`@export\`, or undeclare legs['p7-catala'] in $GO_S_DIR/subject.json and say there why. Modules scanned: ${NO_EXPORT[*]}" \
    --artifact "$LOG" \
    --metric "modules_total=$MODULES_TOTAL" \
    --metric "modules_emitted=0" \
    --metric "modules_without_export=${#NO_EXPORT[@]}"
  exit "$GO_EXIT_FINDING"
fi

# --- COUNT THE EXECUTABLE TESTS PER FILE, before the validator runs ----------
#
# The validator's own floor is `ran >= staged.length` — at least one test
# across all files. That is a TOTAL, so a two-file run where one file carries
# twelve tests and the other carries none clears it, and the silent file rides
# the loud one's evidence. Counting the ```catala-test-cli fences per emission
# closes exactly that hole, and it is one grep.
declare -a NO_TESTS=()
BLOCKS_TOTAL=0
for f in "${EMITTED[@]}"; do
  n=$(grep -c '^```catala-test-cli' "$f" || true)
  BLOCKS_TOTAL=$((BLOCKS_TOTAL + n))
  echo "    $(basename "$f"): $n catala-test-cli block(s)" >>"$LOG"
  [[ "$n" -eq 0 ]] && NO_TESTS+=("$(basename "$f")")
done

# --- the toolchain gate ------------------------------------------------------
set +e
node "$GO_ROOT/etc/validate-catala.mjs" "${EMITTED[@]}" >"$GO_OUT/p7-catala.validate.txt" 2>&1
VRC=$?
set -e
strip_ansi <"$GO_OUT/p7-catala.validate.txt" >"$GO_OUT/p7-catala.validate.clean.txt"
mv "$GO_OUT/p7-catala.validate.clean.txt" "$GO_OUT/p7-catala.validate.txt"
cat "$GO_OUT/p7-catala.validate.txt" >>"$LOG"
ARTS+=(--artifact "$GO_OUT/p7-catala.validate.txt")
VOUT="$GO_OUT/p7-catala.validate.txt"
cat "$LOG"

METRICS=(
  --metric "modules_total=$MODULES_TOTAL"
  --metric "modules_emitted=${#EMITTED[@]}"
  --metric "modules_without_export=${#NO_EXPORT[@]}"
  --metric "basenames_rewritten=${RENAMED:-0}"
  --metric "test_blocks_emitted=$BLOCKS_TOTAL"
)

# EXIT 0 IS NOT A PASS, and the skip line is why. validate-catala.mjs prints
# ONE line and exits 0 when catala/clerk cannot be found by any route — that is
# R9's "optional when present, never a build dependency" — so reading its
# status alone would score an absent toolchain as three green layers.
if grep -q '^skipped: no catala toolchain' "$VOUT"; then
  go_skip "the Catala toolchain is absent on this machine, so nothing checked the ${#EMITTED[@]} emitted module(s): etc/validate-catala.mjs found neither \`catala\` nor \`clerk\` on PATH, in CATALA_EXE/CLERK_EXE, or in the opam switch it tries (\`${CATALA_OPAM_SWITCH:-catala}\`). The emissions are in the run directory and are hashed on this receipt; what is missing is the checker, not the artifact. Remedy: install Catala 1.2.1 into an opam switch named 'catala' (the build recipe is R9 of specs/todo/CATALA-EXPORT-SPEC.md — upstream ships Linux amd64 .deb only, so macOS builds from source), or point CATALA_EXE/CLERK_EXE at an existing pair." \
    "${ARTS[@]}" --artifact "$LOG" "${METRICS[@]}"
fi

# Exit 2 is the validator refusing to START: an explicit CATALA_EXE that does
# not exist, or `clerk start` failing in its scratch directory. That is a
# machine lacking a USABLE toolchain rather than a machine lacking one at all,
# and it is the same kind of thing as the skip above — forgiven on a laptop,
# fatal under L4_GO_REQUIRED=1. It is deliberately NOT `BROKEN`: a broken opam
# switch is not a repo defect, and BROKEN stops the whole run.
if [[ $VRC -eq 2 ]]; then
  go_skip "the Catala toolchain was FOUND but could not be initialised, so no layer ran over the ${#EMITTED[@]} emitted module(s): etc/validate-catala.mjs exited 2. That is its start-up refusal — an explicit CATALA_EXE/CLERK_EXE path that does not exist, or \`clerk start\` failing in its scratch directory. Distinct from the absent-toolchain skip above, and the difference is in $VOUT: $(grep -m1 '^FAIL' "$VOUT" 2>/dev/null || tail -1 "$VOUT")" \
    "${ARTS[@]}" --artifact "$LOG" "${METRICS[@]}"
fi

# `OK    clerk test over N file(s), M test(s)` on success; the banner table's
# `tests FAILED PASSED TOTAL RATIO` row underneath it carries the split.
CLERK_FILES=$(sed -n 's/^OK    clerk test over \([0-9]*\) file(s).*/\1/p' "$VOUT" | tail -1)
CLERK_RAN=$(sed -n 's/^OK    clerk test over [0-9]* file(s), \([0-9]*\) test(s).*/\1/p' "$VOUT" | tail -1)
# `|| true` IS LOAD-BEARING, and it cost a silent no-receipt to find. `read`
# returns 1 when its input is empty, and under `set -e` that ABORTS the phase
# script — before any go_receipt call, so the stage writes NO row at all and
# the run goes INCOMPLETE with nothing said. The input is empty exactly when
# clerk never ran, which is the commonest failure this leg reports: measured
# 2026-09-21, a layer-1 typecheck rejection produced a phase that exited 1
# (indistinguishable from GO_EXIT_FINDING) and an empty journal.
read -r T_FAILED T_PASSED T_TOTAL < <(sed -n 's/.*tests[[:space:]]\{1,\}\([0-9]\{1,\}\)[[:space:]]\{1,\}\([0-9]\{1,\}\)[[:space:]]\{1,\}\([0-9]\{1,\}\).*/\1 \2 \3/p' "$VOUT" | tail -1) || true
TYPECHECK_OK=$(grep -c 'catala typecheck: successful' "$VOUT" || true)
PROOF_OK=$(grep -c 'catala proof: no overlapping exceptions' "$VOUT" || true)
METRICS+=(
  --metric "typecheck_ok=$TYPECHECK_OK"
  --metric "proof_ok=$PROOF_OK"
  --metric "clerk_tests_passed=${T_PASSED:-0}"
  --metric "clerk_tests_total=${T_TOTAL:-${CLERK_RAN:-0}}"
  --metric "clerk_tests_failed=${T_FAILED:-0}"
  --metric "clerk_files=${CLERK_FILES:-0}"
)

if [[ $VRC -ne 0 ]]; then
  # Name WHICH layer refused, because the three are different findings and a
  # reader a year from now needs to know which. The validator stops at the
  # first layer that fails and says so in its own trailer line.
  if grep -q '(catala typecheck)' "$VOUT"; then
    WHICH="layer 1, \`catala typecheck\`: Catala REJECTED what the emitter wrote. This is the #958 class of finding — \`l4 export catala\` exited 0 on every module and the emission is still not Catala. Do not read the emitter's 0 as evidence"
  elif grep -q '(catala proof' "$VOUT"; then
    WHICH="layer 2, \`catala proof\`: the emitted exception ladder has sibling rungs that can both fire, which is a Conflict at run time. The Mode B ladders are emitted linear precisely so that cannot happen, so this says the ladder builder or the encoding it read has changed shape"
  elif grep -q 'clerk test ran' "$VOUT"; then
    WHICH="layer 3, \`clerk test\`: it executed FEWER tests than there are emitted files, so at least one emission carries no \`\`\`catala-test-cli block and was never run. ALL TESTS PASSED over zero tests is not a pass"
  elif grep -q 'FAIL  clerk test' "$VOUT"; then
    WHICH="layer 3, \`clerk test\`: Catala's interpreter DISAGREED with the values L4 computed. Two independently written evaluators read the same rules and returned different answers, which is the finding this leg exists to surface"
  else
    WHICH="etc/validate-catala.mjs exited $VRC without matching any of its three known failure shapes; read $VOUT before believing anything about which layer refused"
  fi
  go_receipt --status DEGRADED \
    --reason "${#EMITTED[@]} module(s) were emitted and the Catala toolchain refused them at $WHICH. First failure: $(grep -m1 '^FAIL' "$VOUT" 2>/dev/null | cut -c1-400). The full three-layer transcript is in p7-catala.validate.txt and the emissions are beside it; nothing in the tree was written." \
    "${ARTS[@]}" --artifact "$LOG" "${METRICS[@]}"
  exit "$GO_EXIT_FINDING"
fi

# Exit 0 with the layers green. Two things still have to hold before this is a
# PASS, and neither is implied by the exit code.
if [[ ${#NO_TESTS[@]} -gt 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "all three Catala layers returned clean over the ${#EMITTED[@]} emitted module(s), and ${#NO_TESTS[@]} of those emissions carries NO \`\`\`catala-test-cli block, so Catala never EXECUTED it — its scopes were typechecked and proved and never run. The validator's own floor is a total across all files (at least one test per file emitted), which a file with none clears whenever a sibling carries enough; this leg counts the blocks per file so it cannot. An emission with no equivalence grid proves that Catala accepts the syntax, and nothing about whether it computes what L4 computes. Files with no executable test: ${NO_TESTS[*]}. The cause is upstream in the module: R7 emits one \`#[test]\` scope per \`#EVAL\`/\`#ASSERT\`, so a module with neither gets none." \
    "${ARTS[@]}" --artifact "$LOG" "${METRICS[@]}"
  exit "$GO_EXIT_FINDING"
fi

if [[ -z "${T_TOTAL:-}" || "${T_TOTAL:-0}" -eq 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "etc/validate-catala.mjs exited 0 over the ${#EMITTED[@]} emitted module(s) and this leg could not read a test count out of its output, so nothing establishes that Catala executed anything. \`clerk test\` prints its ALL TESTS PASSED banner over zero tests, which is why the count and not the banner is the evidence; a count that cannot be parsed is the same absence in a different shape. Read $VOUT — most likely the validator's summary format moved and this leg's parse needs updating in the same change." \
    "${ARTS[@]}" --artifact "$LOG" "${METRICS[@]}"
  exit "$GO_EXIT_FINDING"
fi

go_receipt --status PASS \
  --oracle-cmd "l4 export catala <module> -o <run>/<stem>.catala_en --fixed-now $GO_FIXED_NOW  (x${#EMITTED[@]}) && node etc/validate-catala.mjs <emitted…>" \
  --oracle-exit 0 \
  --oracle-class execution \
  --oracle-because "Catala's own interpreter RAN the emitted modules and agreed. \`clerk test\` re-executed all $T_TOTAL \`\`\`catala-test-cli block(s) across ${#EMITTED[@]} emission(s) with $T_FAILED failures, and every expected value in those blocks was computed by L4's evaluator (R7), so this is two independently written evaluators returning the same answers over the same rules — the artifact ran on its target engine, on cases, and agreed. Layers 1 and 2 ran first and are structural rather than executional: \`catala typecheck\` accepted all $TYPECHECK_OK, and \`catala proof\` reported no overlapping exceptions on all $PROOF_OK, which is the only check anywhere that would notice a Mode B ladder whose rungs stopped being linear. The class is claimed on layer 3 alone; layers 1 and 2 would only license \`structural\`." \
  "${ARTS[@]}" --artifact "$LOG" "${METRICS[@]}" \
  --note "WHAT AGREEMENT HERE DOES NOT ESTABLISH. The expected values clerk re-checked were produced by L4 during this same emission, so a misreading of the source law that both languages share agrees with itself and passes. This leg falsifies a LOWERING that changes the answer; whether the L4 says what $GO_S_CITATION says is HG1's, and no count on this row bears on it." \
  --note "${#NO_EXPORT[@]} of the $MODULES_TOTAL declared module(s) carry no \`@export\` and were not lowered: a module with no deployable surface emits no callable scope. They are counted, not failed.$([[ ${#NO_EXPORT[@]} -gt 0 ]] && echo " Skipped: ${NO_EXPORT[*]}")"
