#!/usr/bin/env bash
# P9.1 — the explainer: the reader-facing sibling of the conversion report.
#
# The conversion report is an AUDIT document. It accounts for what a run did, it
# refuses to print a number that has no journal row, and it is unreadable to
# anyone who is not already inside this project. This stage renders the other
# document: what the body of law requires, and — interleaved, never bolted on —
# what happened when somebody tried to make it executable.
#
# It reads journal.ndjson, the subject's CHECKED-IN narrative (drafted, reviewed
# and version-controlled under etc/go/subjects/<id>/explainer/), and the
# artifacts this run's own receipts attest. It reads nothing else, and it writes
# nothing into the tree.
#
# WHY THIS IS A DECLARED STAGE rather than a second render inside p9-report.sh:
# a declared stage appears in run_begin's declared_stages, and the milestone
# verdict reports INCOMPLETE for any declared stage with no receipt. A run that
# produced no explainer therefore says so in its verdict. Folding the render
# into p9-report would make the explainer's absence invisible, and would put a
# second and riskier render inside a script whose PASS currently means something
# narrow and well defined.
#
# WHY IT IS HG1-GATED: it publishes reviewed narrative. An ungated explainer
# stage would render HG1-unreviewed prose and every downstream honesty check
# would report clean, because the driver's gate test defaults to UNGATED, and
# verify-run.mjs reads the gated set out of run_begin so it would agree with the
# omission. See selftest.mjs's "every declared stage after p6-tests is gated by
# HG1", which exists because of this stage.
#
# Like the report, the explainer is written INTO THE RUN DIRECTORY, not into the
# tree. Copying it anywhere a person other than the operator can see it is
# publication, which is P10, which is HG2's.

if [[ "${1:-}" == "--inputs" ]]; then
  # DELIBERATELY EMPTY, for exactly p9-report.sh's reason.
  #
  # The explainer is a function of the journal, and the journal grows as this
  # very stage runs — a stage cannot digest its own future. The narrative files
  # are also inputs and are also NOT declared here, because declaring them and
  # not the journal is the under-declared-digest hazard in its most damaging
  # form: a stale explainer reporting as `replayed` over a journal that had
  # since changed. Their digests ride on the receipt as metrics instead, which
  # is where a claim about content belongs.
  #
  # The cost is real and named: this is the SECOND stage that never replays.
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

if [[ -z "${GO_S_EXPLAINER_DIR:-}" ]]; then
  go_skip "subject '$GO_S_ID' declares no 'explainer' section in subject.json, so it has no checked-in narrative to render. Declaring the directory is deliberate rather than discovered: a mistyped directory name would otherwise yield a fully-absent document with no error anywhere."
fi

# Refuse to render into a run that never declared this stage.
#
# `milestoneVerdict` checks declared -> receipt and never receipt -> declared,
# so a stage resumed into an older run directory writes a receipt and four
# hashed artifacts that the run's own verdict cannot see, while the artifacts
# land in the audit report's artifact table. MEASURED: run
# 2026-08-02-97b15013-005, whose `run_begin` lists thirteen stages and not this
# one, was resumed with this driver and reported `VERDICT: g1 COMPLETE` with a
# full explainer beside it. That is a general property of the driver, not of
# this stage — but this stage is the one that would publish a DOCUMENT out of
# it, so it declines here rather than waiting for the general fix.
if ! node -e '
  const fs = require("node:fs");
  const rows = fs.readFileSync(process.argv[1], "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l));
  const b = rows.find((r) => r.kind === "run_begin");
  process.exit(!b || (b.declared_stages ?? []).includes("p9-explain") ? 0 : 1);
' "$GO_RUN/journal.ndjson" 2>/dev/null; then
  go_skip "this run's own run_begin record does not declare p9-explain, so the run's milestone verdict cannot account for a receipt from it. Rendering anyway would put a document — and four hashed artifacts — into a run whose verdict is blind to them. Start a run that declares the stage instead."
fi

# Preliminary render into the ARTIFACTS directory, hashed on this stage's own
# receipt. go.sh renders the final $RUN/explainer.{md,html} after run_end, when
# the run's own verdict exists; that one is deliberately unattested, because
# anyone can re-run the renderer over the journal and get the same bytes, which
# is a stronger guarantee than a hash of a file somebody could have replaced.
set +e
node "$GO_ROOT/etc/go/report/render-explainer.mjs" "$GO_RUN" --format md,html --out "$GO_OUT" >"$GO_OUT/p9-explain.txt" 2>&1
RC=$?
set -e
cat "$GO_OUT/p9-explain.txt"

case $RC in
  0) ;;
  3) go_skip "the renderer declined: $(tail -3 "$GO_OUT/p9-explain.txt" | tr '\n' ' ')" ;;
  4) go_broken "render-explainer.mjs refused to render: the template carries a typed number, a placeholder had no journal row, or the narrative deposit is malformed. See $GO_OUT/p9-explain.txt" ;;
  *) go_broken "render-explainer.mjs exited $RC" ;;
esac

MD="$GO_OUT/explainer.md"
HTML="$GO_OUT/explainer.html"
SUMMARY="$GO_OUT/explainer.summary.json"
[[ -f "$MD" ]] || go_broken "render-explainer.mjs exited 0 but wrote no explainer.md"
[[ -f "$SUMMARY" ]] || go_broken "render-explainer.mjs exited 0 but wrote no explainer.summary.json"

# Structural check: every slot the spine requires is present. A document that
# quietly drops a section it has nothing to say about is the failure this stage
# exists to prevent, exactly as for the audit report.
set +e
node -e '
  const fs = require("node:fs");
  const t = fs.readFileSync(process.argv[1], "utf8");
  const required = [
    "## What this is, and who it binds",
    "## The rules",
    "## Pictures",
    "## Time",
    "## Limits",
    "## What was never searched",
    "## Use it",
    "## How to check this document",
  ];
  const missing = required.filter((h) => !t.includes(h));
  if (missing.length) { console.error("missing required sections: " + missing.join(", ")); process.exit(1); }
  const absents = (t.match(/\*\*ABSENT\.\*\*/g) || []).length;
  const drafts = (t.match(/\*\*DRAFT — claimed, not verified/g) || []).length;
  console.log(`explainer: all ${required.length} spine slots present; ${absents} rendered ABSENT with a stated reason; ${drafts} section(s) marked draft`);
' "$MD"
STRUCT_RC=$?
set -e
[[ $STRUCT_RC -eq 0 ]] || go_broken "the rendered explainer is missing a slot its spine requires"

# The counts the receipt carries come from the renderer's own summary, so the
# report and the receipt cannot disagree about the same document.
read -r SECTIONS DRAFTS CIT UNCH UNRES NFIND < <(node -e '
  const s = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
  process.stdout.write([s.sections, s.draft_sections, s.citations_total,
    s.citations_unchecked, s.citations_unresolved, s.findings.length].join(" ") + "\n");
' "$SUMMARY")

NARRATIVE_DIGEST=$(go_digest "$GO_S_EXPLAINER_DIR"/*.md "$GO_S_EXPLAINER_DIR/manifest.json" "$GO_S_EXPLAINER_DIR/provenance.json")

METRICS=(
  --metric "narrative_sections=$SECTIONS"
  --metric "narrative_unreviewed=$DRAFTS"
  --metric "citations=$CIT"
  --metric "citations_unchecked=$UNCH"
  --metric "citations_unresolved=$UNRES"
  --metric "deposit_findings=$NFIND"
  --metric "narrative_digest=$NARRATIVE_DIGEST"
)
ARTS=(--artifact "$MD" --artifact "$HTML" --artifact "$SUMMARY" --artifact "$GO_OUT/p9-explain.txt")

# The lattice, applied honestly.
#
# An unreviewed section, a drifted source, a lint complaint and an unresolved
# citation are all findings ABOUT THE DEPOSIT, so they degrade. They are not
# BROKEN: BROKEN is reserved for a defect in this script or in the renderer, and
# calling a content finding a harness defect would let a real harness defect
# hide among them.
#
# And note what a green here would have to mean: that every section carries a
# signature over its text and its sources. This repository enrols no signer
# today, so DEGRADED is the correct and expected state, not a near miss.
if [[ "$NFIND" -gt 0 || "$DRAFTS" -gt 0 ]]; then
  REASON="the document rendered in full"
  [[ "$DRAFTS" -gt 0 ]] && REASON="$REASON; $DRAFTS of $SECTIONS narrative sections are agent-drafted and carry no review signature, and each renders behind a draft banner"
  [[ "$NFIND" -gt 0 ]] && REASON="$REASON; $NFIND deposit finding(s) — drift, lint or unresolved citation — are listed in the document's own provenance section and in $SUMMARY"
  [[ "$UNRES" -gt 0 ]] && REASON="$REASON; $UNRES citation(s) did not resolve and print the figure followed by a visible complaint rather than silently losing their source"
  go_receipt --status DEGRADED --reason "$REASON" "${METRICS[@]}" "${ARTS[@]}" \
    --note "DEGRADED here is about the DEPOSIT, not about the run: the renderer worked, the spine is complete, and every claim that could be checked was checked. What is missing is human review of the prose." \
    --note "this is the PRELIMINARY render, taken before this stage's own receipt and the run_end record exist. go.sh renders the final \$RUN/explainer.{md,html} after run_end; it is derived rather than attested, and re-derivable by anyone."
else
  go_receipt --status PASS \
    --oracle-cmd "node etc/go/report/render-explainer.mjs \$RUN --format md,html && every slot the spine requires is present" \
    --oracle-exit 0 \
    --oracle-class structural \
    --oracle-because "every run fact in the document resolved from a journal row, every figure resolved either from the journal or from a source line this renderer re-read and matched, every narrative section carries a review signature over its text and its sources, and the slot-presence check confirms nothing the spine requires was dropped" \
    "${METRICS[@]}" "${ARTS[@]}" \
    --note "PASS here means the document accounts for its own claims. It says nothing about whether the law it explains is explained WELL." \
    --note "this is the PRELIMINARY render, taken before this stage's own receipt and the run_end record exist. go.sh renders the final \$RUN/explainer.{md,html} after run_end; it is derived rather than attested, and re-derivable by anyone."
fi
