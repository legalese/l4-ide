#!/usr/bin/env bash
# P0 — preflight. Establish, and record, what this run is running against.
#
# Nothing here is a projection. This stage exists so that every later receipt
# can be read against a known tree, a known binary, a known clock, and a known
# CLI surface. It fails loudly (exit 4, BROKEN) when the CLI surface the stage
# table depends on has moved, because a run against a changed surface reports
# nonsense rather than a finding.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "$GO_S_CORPUS" ${GO_S_WIZARD:+"$GO_S_WIZARD"} "${BASH_SOURCE[0]}" "$GO_S_PINS"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

PROBES="$GO_OUT/probes.json"
PINLOG="$GO_OUT/cli-surface.txt"

# --- 1. the binary and the clock --------------------------------------------
# There is no `l4 --version` (verified 2026-08-02: it prints "Invalid option
# `--version'" plus the usage block and exits 1), so the binary is identified by
# its own sha256, which is what a report can cite.
#
# go.sh has already hashed it — it folds that digest into every stage's inputs
# digest, which is what makes a resumed run notice a rebuilt binary — so reuse
# the value rather than reading 200 MB a second time.
L4_PATH="${GO_L4_PATH:-$(command -v "$L4" || echo "$L4")}"
L4_SHA="${GO_L4_SHA:-$(node "$GO_LIB/digest.mjs" "$L4_PATH")}"

# --- 2. toolchain probes; every miss carries a named reason ------------------
node "$GO_LIB/probe.mjs" >"$PROBES"

# --- 3. the CLI surface the stage table reads -------------------------------
# Narrow by design: four enumerations plus the module's regulative rule names,
# recovered by discovery calls. NOT a hash of `l4 --help` — that fires on any
# unrelated reflow, and a tripwire that cries wolf gets deleted. The pin file
# is the subject's own: it was measured against that subject's corpus.
set +e
node "$GO_LIB/discover.mjs" check "$GO_S_CORPUS" "$GO_S_PINS" >"$PINLOG" 2>&1
PIN_EXIT=$?
set -e
cat "$PINLOG"
if [[ $PIN_EXIT -ne 0 ]]; then
  go_broken "the CLI surface the stage table depends on has moved; see $PINLOG. Re-verify etc/go/phases/*.sh against the new surface, then update $GO_S_PINS."
fi

# --- 4. every checker a later stage will invoke must exist -------------------
MISSING=""
while read -r c; do
  [[ -n "$c" ]] || continue
  [[ -e "$GO_ROOT/$c" ]] || MISSING="$MISSING $c"
done < <(node -e '
  const p = require("'"$GO_S_PINS"'");
  process.stdout.write((p.checkers_that_must_exist||[]).join("\n"));
')
if [[ -n "$MISSING" ]]; then
  go_broken "checkers named in $GO_S_PINS are missing from the tree:$MISSING"
fi

# --- 5. the upgrade tripwire for the `l4 run` workaround --------------------
# etc/go/lib/assert-report.mjs exists ONLY because `l4 run` exits 0 on a failed
# #ASSERT. The day that changes, the workaround is wrong and must be deleted.
# So: a fixture with a deliberately failing assertion must KEEP exiting 0.
TRIPWIRE="$GO_OUT/tripwire-failing-assert.l4"
cat >"$TRIPWIRE" <<'L4EOF'
GIVEN x IS A NUMBER
GIVETH A NUMBER
`double` MEANS x TIMES 2

#ASSERT `double` 21 EQUALS 43
L4EOF
set +e
"$L4" run "$TRIPWIRE" --json >"$GO_OUT/tripwire.json" 2>/dev/null
TRIP_EXIT=$?
set -e
if [[ $TRIP_EXIT -ne 0 ]]; then
  cat >&2 <<EOF
::error::UPGRADE TRIPWIRE FIRED — 'l4 run' now exits $TRIP_EXIT on a failed #ASSERT.
  It exited 0 when etc/go/lib/assert-report.mjs was written, which is the entire
  reason that module exists. If '--fail-on-assert' or equivalent has shipped:
    1. delete etc/go/lib/assert-report.mjs and its selftest,
    2. make etc/go/phases/p6-tests.sh use the exit code directly,
    3. delete this tripwire block from p0-preflight.sh.
EOF
  go_broken "l4 run now exits $TRIP_EXIT on a failed #ASSERT; the assert-report workaround is stale (see the ::error:: above)"
fi

# --- 6. record ---------------------------------------------------------------
CORPUS_SHA="$(node "$GO_LIB/digest.mjs" "$GO_S_CORPUS")"
METRICS=(--metric "corpus_sha_$(basename "$GO_S_CORPUS")=$CORPUS_SHA")
if [[ -n "${GO_S_WIZARD:-}" ]]; then
  WIZARD_SHA="$(node "$GO_LIB/digest.mjs" "$GO_S_WIZARD")"
  METRICS+=(--metric "corpus_sha_$(basename "$GO_S_WIZARD")=$WIZARD_SHA")
fi
# The rule-name discovery only applies to a subject whose sidecar pins
# regulative rules; a purely constitutive corpus has none to discover.
if node -e 'process.exit(require("'"$GO_S_PINS"'").regulative_rules ? 0 : 1)'; then
  RULES="$(node "$GO_LIB/discover.mjs" rules "$GO_S_CORPUS" | tr '\n' ';')"
  METRICS+=(--metric "regulative_rules=$RULES")
fi

go_receipt \
  --status PASS \
  --oracle-cmd "node etc/go/lib/discover.mjs check $(basename "$GO_S_CORPUS") $GO_S_PINS && every checker in the pin file exists && the failing-#ASSERT tripwire still exits 0" \
  --oracle-exit 0 \
  --oracle-class structural \
  --oracle-because "the four CLI enumerations and the module's regulative rule names are recovered by discovery calls and compared as SETS against the subject's pins.json, so a rename fails loudly naming the exact strings; the tripwire independently confirms the l4-run workaround is still needed" \
  --artifact "$PROBES" \
  --artifact "$PINLOG" \
  --artifact "$GO_OUT/tripwire.json" \
  "${METRICS[@]}" \
  --metric "l4_binary=$L4_PATH" \
  --metric "l4_binary_sha=$L4_SHA" \
  --metric "fixed_now=$GO_FIXED_NOW"
