#!/usr/bin/env bash
# P8-diff — SPEC.md §8's acceptance comparator, as a stage (D4, 2026-08-09).
#
# Runs etc/go/lib/denovo-diff.mjs over the subject's declared surface map
# (subject.json denovo.surface_map). THIS IS THE ONE STAGE LICENSED TO READ
# BOTH the committed corpus and the de novo deposit: the map's sides.left /
# sides.right name the two modules, and §8's whole question is what they
# answer differently over a shared fact battery. Every other g2 stage must
# not touch the committed corpus — measuring replay artifacts under a de novo
# label is the false claim ORCHESTRATOR.md §5.2 exists to prevent; comparing
# the two on the record is the exhibit §8 exists to demand.
#
# STATUS RULE, and the two deliberate deviations it carries:
#
#   comparator exit 0 or 1  ->  PASS / structural. Exit 1 means divergences,
#       and a divergence DOES NOT demote: §8 says "a de novo run that merely
#       reproduces the corpus is a pass; one that finds a defect in it is a
#       better pass". The triage of each divergence — encoding error vs
#       genuine ambiguity vs improvement — is a reading of the law, owned by
#       the skill and then HG1, never by this script; the receipt carries the
#       divergence count and the untriaged count as metrics instead.
#   comparator exit 2 or 4  ->  DEGRADED naming the harness error. Exit 4 is
#       the comparator's own BROKEN class, and the house rule for a defective
#       harness is go_broken; D4 maps it to DEGRADED instead so the run
#       continues to the report with the error named — a recorded deviation,
#       chosen because a comparator defect is a finding about the ORACLE and
#       the report must be able to say so. Note that exit 2 is not only
#       usage: an unresolvable pair rule and a battery row missing a declared
#       field both exit 2, and those are exactly the harness errors this
#       branch is for.
#
# The deposit contract applies to the map itself: undeclared or absent ->
# SKIPPED naming the key, exit 5 under L4_GO_REQUIRED=1.

# --inputs: the map, BOTH module paths read out of it (the comparator's real
# inputs — an edit to either encoding must re-run this stage), the comparator,
# its schema, and this script. When the map is unreadable the two module rows
# are simply absent, and the map's own digest carries the change.
if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' ${GO_S_DENOVO_SURFACE_MAP:+"$GO_S_DENOVO_SURFACE_MAP"} \
    "${BASH_SOURCE[0]}" \
    "$GO_ROOT/etc/go/lib/denovo-diff.mjs" \
    "$GO_ROOT/specs/todo/single-instruction-demo/schemas/surface-map.schema.json"
  if [[ -n "${GO_S_DENOVO_SURFACE_MAP:-}" && -f "${GO_S_DENOVO_SURFACE_MAP:-}" ]]; then
    node -e '
      try {
        const m = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
        const { resolve } = require("node:path");
        for (const side of ["left", "right"]) {
          const p = m?.sides?.[side]?.module;
          if (typeof p === "string" && p) process.stdout.write(resolve(process.argv[2], p) + "\n");
        }
      } catch { /* unreadable map: its own digest carries the change */ }
    ' "$GO_S_DENOVO_SURFACE_MAP" "$GO_ROOT" || true
  fi
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

MAP="${GO_S_DENOVO_SURFACE_MAP:-}"
if [[ -z "$MAP" ]]; then
  go_skip "the '$GO_S_ID' sidecar declares no denovo.surface_map, so the §8 comparator has no pairing declaration to run over. Add it to $GO_S_DIR/subject.json; writing the map (which decisions correspond, over which shared fact slots) is agent work owned by the skill's G2 section and DENOVO-DIFF-ORACLE.md."
fi
if [[ ! -f "$MAP" ]]; then
  go_skip "the declared denovo.surface_map has not been deposited yet: $MAP is not a file. Producing it is agent work; deposit it and re-run this stage."
fi

OUTDIR="$GO_OUT/p8-diff"
mkdir -p "$OUTDIR"
LOG="$GO_OUT/p8-diff.txt"

set +e
node "$GO_LIB/denovo-diff.mjs" run --map "$MAP" --root "$GO_ROOT" --out "$OUTDIR" >"$LOG" 2>&1
DIFF_RC=$?
set -e
cat "$LOG"

REPORT_JSON="$OUTDIR/denovo-diff.json"
REPORT_MD="$OUTDIR/denovo-diff.md"
ROWS_JSON="$OUTDIR/denovo-diff.rows.json"

if [[ $DIFF_RC -ne 0 && $DIFF_RC -ne 1 ]]; then
  go_receipt --status DEGRADED \
    --reason "the §8 comparator could not complete: denovo-diff.mjs exited $DIFF_RC (2 = an invalid map or a harness error that reads like usage — an unresolvable pair rule, a battery row missing a declared field; 4 = a comparator/CLI-shape defect). This is a finding about the ORACLE, not about either encoding; see $LOG." \
    --artifact "$LOG" \
    --metric "comparator_exit=$DIFF_RC" \
    --note "deviation from the house harness rule, on the record: a defective harness is normally go_broken (BROKEN, run over); D4 (2026-08-09) maps comparator exits 2 and 4 to DEGRADED so the run reaches the report with the harness error named in it"
  exit "$GO_EXIT_FINDING"
fi

# The metrics come from the report JSON, never from stdout (the CLI's battery
# line has a known cosmetic defect; the JSON coerces it). The perturbation
# figures ride along (2026-08-09): the headline agreement count was published
# with the comparator's anti-vacuity instrument switched off — the committed
# map declares battery.perturbation.enabled=false — and neither the receipt
# nor the documents quoting the number said so. A receipt reader must be able
# to see whether the Sensitivity axis measured anything.
read -r ROWS PAIRS EVALS AGREED DIVERGED WITNESSES UNTRIAGED PERTURBATIONS LEAVES_PERTURBED LEAVES_INERT PERTURB_ENABLED LEFT_MOD RIGHT_MOD < <(node -e '
  const j = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
  const { resolve } = require("node:path");
  const untriaged = (j.witnesses ?? []).filter(
    (w) => (w.disposition ?? "UNTRIAGED") === "UNTRIAGED",
  ).length;
  let enabled = "undeclared";
  try {
    const m = JSON.parse(require("node:fs").readFileSync(process.argv[3], "utf8"));
    if (typeof m.battery?.perturbation?.enabled === "boolean")
      enabled = String(m.battery.perturbation.enabled);
  } catch {
    /* the comparator already accepted the map; an unreadable one here stays "undeclared" */
  }
  process.stdout.write(
    [
      j.battery?.rows ?? 0,
      j.pairs ?? 0,
      j.totals?.evaluated ?? 0,
      j.totals?.agreed ?? 0,
      j.totals?.diverged ?? 0,
      j.totals?.witnesses ?? 0,
      untriaged,
      j.battery?.perturbations ?? 0,
      j.totals?.leaves_perturbed ?? 0,
      j.totals?.leaves_inert ?? 0,
      enabled,
      resolve(process.argv[2], j.sides.left.module),
      resolve(process.argv[2], j.sides.right.module),
    ].join(" ") + "\n",
  );
' "$REPORT_JSON" "$GO_ROOT" "$MAP")

# §8.1's density axis, as numbers on a receipt. The method is NAMED because no
# tool reports it: numerator = executable #ASSERT directive lines
# (^\s*#ASSERT — the grep -c figure over-counts prose mentions), denominator =
# non-comment GIVETH|DECIDE|MEANS occurrences, the proxy that reproduces
# SPEC.md §8.1's published decision counts (191 replay / 485 de novo) and its
# densities (0.43 / 0.08) exactly. `l4 verify`'s summary.decisions is the
# compiler's own count and DIFFERS (109 / 253); a receipt citing §8.1 must
# not silently publish a different denominator.
read -r L_ASSERTS L_DECISIONS L_DENSITY R_ASSERTS R_DECISIONS R_DENSITY DENSITY_DELTA < <(node -e '
  const { readFileSync } = require("node:fs");
  const count = (path) => {
    const lines = readFileSync(path, "utf8").split("\n");
    let asserts = 0, decisions = 0;
    for (const l of lines) {
      if (/^\s*--/.test(l)) continue;
      if (/^\s*#ASSERT/.test(l)) asserts++;
      decisions += (l.match(/\b(MEANS|DECIDE|GIVETH)\b/g) ?? []).length;
    }
    return [asserts, decisions, decisions ? asserts / decisions : 0];
  };
  const [la, ld, lden] = count(process.argv[1]);
  const [ra, rd, rden] = count(process.argv[2]);
  process.stdout.write(
    [la, ld, lden.toFixed(4), ra, rd, rden.toFixed(4), (rden - lden).toFixed(4)].join(" ") + "\n",
  );
' "$LEFT_MOD" "$RIGHT_MOD")

METRICS=(
  --metric "rows=$ROWS" --metric "pairs=$PAIRS" --metric "evaluations=$EVALS"
  --metric "agreed=$AGREED" --metric "diverged=$DIVERGED"
  --metric "witnesses=$WITNESSES" --metric "untriaged=$UNTRIAGED"
  --metric "comparator_exit=$DIFF_RC"
  --metric "perturbations=$PERTURBATIONS"
  --metric "leaves_perturbed=$LEAVES_PERTURBED" --metric "leaves_inert=$LEAVES_INERT"
  --metric "perturbation_enabled=$PERTURB_ENABLED"
  --metric "left_assertions=$L_ASSERTS" --metric "left_decisions=$L_DECISIONS" --metric "left_density=$L_DENSITY"
  --metric "right_assertions=$R_ASSERTS" --metric "right_decisions=$R_DECISIONS" --metric "right_density=$R_DENSITY"
  --metric "density_delta=$DENSITY_DELTA"
  --metric "density_method=#ASSERT directive lines / non-comment GIVETH|DECIDE|MEANS occurrences (the SPEC.md §8.1 proxy; l4 verify's summary.decisions is a different denominator and is not used)"
)

DIVERGE_NOTE="divergences do not demote this status: SPEC.md §8 rules that a run finding a defect is a BETTER pass, and each witness's disposition is a reading of the law — the report artifact carries every one as UNTRIAGED for the skill and HG1 to triage, never this script"
# The sensitivity note must not point at an empty table as if it were
# reassurance. When nothing was perturbed, say that nothing was measured on
# that axis; the old note said "read the Sensitivity table beside the
# agreement count" while the table was empty by construction.
if [[ "$LEAVES_PERTURBED" == "0" ]]; then
  SENSITIVITY_NOTE="the battery's perturbation instrument produced NO perturbed leaves on this run (perturbation_enabled=$PERTURB_ENABLED — the committed map declares it off by construction), so the report's Sensitivity table is empty and the agreement count is UNWEIGHTED by inertness: no (pair, fact) leaf was shown to move an answer, and none was shown inert either — that axis measured nothing. The battery covers $PAIRS declared pair(s) over $ROWS row(s); decisions outside the map are not compared at all, and a divergence confined to the deontic layer would not appear here (DENOVO-DIFF-ORACLE.md carries the full blind-spot list)"
else
  SENSITIVITY_NOTE="read the report's Sensitivity table beside the agreement count: a (pair, fact) leaf the battery perturbed ($LEAVES_PERTURBED perturbed, $LEAVES_INERT inert) without ever moving an answer is a surface on which agreement is silence, not evidence. The battery covers $PAIRS declared pair(s) over $ROWS row(s); decisions outside the map are not compared at all, and a divergence confined to the deontic layer would not appear here (DENOVO-DIFF-ORACLE.md carries the full blind-spot list)"
fi

# The oracle's acceptance condition is exactly "the comparator ran to
# completion": its exit contract defines BOTH 0 (agreement) and 1 (divergence)
# as completed measurements, so the oracle command wraps the run in that
# acceptance and ITS exit is what is recorded. The raw comparator exit is on
# the receipt as a metric.
go_receipt --status PASS \
  --oracle-cmd "node etc/go/lib/denovo-diff.mjs run --map $MAP; rc=\$?; [ \$rc -eq 0 ] || [ \$rc -eq 1 ]  # 0 = agreement, 1 = divergence: both are completed measurements per its exit contract" \
  --oracle-exit 0 \
  --oracle-class structural \
  --oracle-because "the §8 comparator evaluated both encodings over the shared fact battery and completed with zero harness errors (no unresolvable pair, no missing battery field, no non-value row on either side). What PASS asserts is that the comparison RAN and its findings are on the record — $AGREED/$EVALS agreed, $DIVERGED diverged, $UNTRIAGED untriaged — not that the encodings agree: §8 calls a divergence-finding run the better pass." \
  --artifact "$REPORT_JSON" --artifact "$REPORT_MD" --artifact "$ROWS_JSON" --artifact "$LOG" \
  "${METRICS[@]}" \
  --note "$DIVERGE_NOTE" \
  --note "$SENSITIVITY_NOTE"
