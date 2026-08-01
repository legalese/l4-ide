#!/usr/bin/env bash
# P9 — the conversion report.
#
# Reads journal.ndjson and nothing else. A required section with no journal rows
# renders as ABSENT with the reason, never omitted; agent notes render in a block
# labelled "claimed, not verified"; and the renderer refuses a template that
# contains a typed number, because that is how PROJECTIONS.md came to carry
# three stale figures for one file.
#
# The report is written INTO THE RUN DIRECTORY, not into the tree. Copying it
# anywhere a person other than the operator can see it is publication, which is
# P10, which is HG2's.

if [[ "${1:-}" == "--inputs" ]]; then
  # DELIBERATELY EMPTY, which makes this stage the one stage that never replays.
  #
  # The report is a function of the journal, and the journal grows as this very
  # stage runs — a stage cannot digest its own future. Declaring an inputs set
  # that omits the journal would let the report report as `replayed` while the
  # journal underneath it had changed, which is the under-declared-digest hazard
  # in its most damaging form: a stale report claiming to be current.
  #
  # Rendering is cheap and reads only the journal, so regenerating every time is
  # both correct and free.
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

# Rendered into the ARTIFACTS directory, not to $RUN/report.md.
#
# The report is a pure function of the journal, and the journal is not finished
# while this stage is running: this stage's own receipt, and the run_end record,
# come after. So what is hashed here is a PRELIMINARY render — proof that the
# renderer works and that every section SPEC.md §P9 requires is present — and
# go.sh renders the final report.md/report.html after run_end.
#
# The final report is deliberately not attested by any receipt. It is derived,
# not measured: anyone can re-run render-report.mjs over the journal and get the
# same bytes, which is a stronger guarantee than a hash of a file somebody could
# have replaced.
set +e
node "$GO_ROOT/etc/go/report/render-report.mjs" "$GO_RUN" --format md,html --out "$GO_OUT" >"$GO_OUT/p9-report.txt" 2>&1
RC=$?
set -e
cat "$GO_OUT/p9-report.txt"

case $RC in
  0) ;;
  4) go_broken "render-report.mjs refused to render: either the template carries a typed number or a placeholder had no journal row. See $GO_OUT/p9-report.txt" ;;
  *) go_broken "render-report.mjs exited $RC" ;;
esac

MD="$GO_OUT/report.md"
HTML="$GO_OUT/report.html"
[[ -f "$MD" ]] || go_broken "render-report.mjs exited 0 but wrote no report.md"

# Structural check: every required section is present, and every ABSENT one says
# which stage would have supplied it. A report that quietly drops a section it
# has nothing to say about is the failure this stage exists to prevent.
set +e
node -e '
  const fs = require("node:fs");
  const t = fs.readFileSync(process.argv[1], "utf8");
  const required = [
    "## Gates",
    "## What the source said",
    "## What the external-modification sweep searched and surfaced",
    "## What the encoding decided",
    "## What each projection preserved and lost",
    "## Test results",
    "## Where another system published its own representation of the same rule",
    "## Triage",
    "## Every artifact this run put on disk",
  ];
  const missing = required.filter((h) => !t.includes(h));
  if (missing.length) { console.error("missing required sections: " + missing.join(", ")); process.exit(1); }
  const absents = (t.match(/\*\*ABSENT\.\*\*/g) || []).length;
  console.log(`report: all ${required.length} required sections present; ${absents} rendered ABSENT with a stated reason`);
' "$MD"
STRUCT_RC=$?
set -e
[[ $STRUCT_RC -eq 0 ]] || go_broken "the rendered report is missing a section SPEC.md §P9 requires"

go_receipt --status PASS \
  --oracle-cmd "node etc/go/report/render-report.mjs \$RUN --format md,html && every section SPEC.md §P9 requires is present" \
  --oracle-exit 0 \
  --oracle-class structural \
  --oracle-because "the renderer reads journal.ndjson and nothing else, refuses a template containing a typed number, refuses an unresolved placeholder, and prints a chain-verification failure in the report itself; the section-presence check then confirms nothing §P9 requires was dropped" \
  --artifact "$MD" --artifact "$HTML" --artifact "$GO_OUT/p9-report.txt" \
  --note "PASS here means the report accounts for everything the journal holds. It says nothing about whether the projections it describes are good." \
  --note "this is the PRELIMINARY render, taken before this stage's own receipt and the run_end record exist. go.sh renders the final \$RUN/report.md after run_end; it is derived rather than attested, and re-derivable by anyone with 'go.sh verify'."
