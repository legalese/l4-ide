#!/usr/bin/env bash
# P7 EXTRA — the Akoma Ntoso leg.
#
# `l4 render FILE --format akn` emits LegalDocML (Akoma Ntoso 3.0) with FRBR
# metadata. It is real, it works, and it appears in NO spec: the command's own
# description lists only `html|text|json|plan`, SPEC.md §P7's projection table
# does not name it, and neither does PROJECTIONS.md. For a demo whose thesis is
# "cooperate with the standards", an unlisted LegalDocML leg is worth surfacing.
#
# It is declared EXTRA rather than a P7 leg, which has a structural consequence:
# it is not in G1's declared stage list contributing to the milestone rule the
# way the mandated legs are, and its oracle is well-formedness, which
# etc/go/lib/verdict.mjs bars from PASS. So this leg cannot raise the milestone
# verdict no matter what it reports.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "$GO_CORPUS" "${BASH_SOURCE[0]}"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

OUT="$GO_OUT/regcf.akn.xml"
LOG="$GO_OUT/p7-akn.txt"

set +e
"$L4" render "$GO_CORPUS" --format akn -o "$OUT" --fixed-now "$GO_FIXED_NOW" >"$LOG" 2>&1
RC=$?
set -e
if [[ $RC -ne 0 ]]; then
  go_receipt --status NOT-BUILT \
    --reason "l4 render --format akn exited $RC" \
    --blocker "the akn render format is undocumented — the command description lists only html|text|json|plan — so it may have been removed without notice; see $LOG" \
    --artifact "$LOG"
  exit "$GO_EXIT_FINDING"
fi

# Well-formedness only. There is no Akoma Ntoso schema in this repo and no
# checker for one, so nothing here says the document is VALID AKN, let alone
# that it says what 17 CFR Part 227 says.
set +e
node -e '
  const fs = require("node:fs");
  const t = fs.readFileSync(process.argv[1], "utf8");
  // A deliberately shallow check: the declaration, the AKN namespace, and
  // balanced angle brackets at the top level. Anything stronger would need a
  // parser this repo does not carry for AKN.
  if (!/^<\?xml/.test(t)) { console.error("no XML declaration"); process.exit(1); }
  if (!/xmlns="http:\/\/docs\.oasis-open\.org\/legaldocml\/ns\/akn\/3\.0"/.test(t)) { console.error("no AKN 3.0 namespace"); process.exit(1); }
  const open = (t.match(/<akomaNtoso\b/g) || []).length, close = (t.match(/<\/akomaNtoso>/g) || []).length;
  if (open !== 1 || close !== 1) { console.error(`akomaNtoso open=${open} close=${close}`); process.exit(1); }
  console.log(`akn: XML declaration present, AKN 3.0 namespace present, one balanced akomaNtoso root, ${t.length} bytes`);
' "$OUT" >>"$LOG" 2>&1
WF_RC=$?
set -e
tail -2 "$LOG"

if [[ $WF_RC -ne 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "the emitted AKN is not well formed at even the shallow level this leg checks; see $LOG" \
    --artifact "$OUT" --artifact "$LOG"
  exit "$GO_EXIT_FINDING"
fi

go_receipt --status UNVERIFIED \
  --reason "an Akoma Ntoso 3.0 document was emitted and is well formed at the shallow level checked here (declaration, AKN namespace, one balanced root). It is UNVERIFIED because well-formedness is the only oracle available: this repo carries no AKN schema and no AKN checker, so nothing establishes that the document is schema-valid, let alone that it says what 17 CFR Part 227 says. etc/go/lib/verdict.mjs bars a wellformedness-class oracle from PASS for exactly this reason." \
  --artifact "$OUT" --artifact "$LOG" \
  --metric "bytes=$(wc -c <"$OUT" | tr -d ' ')" \
  --label "EXTRA" \
  --note "EXTRA leg. render --format akn is UNDOCUMENTED (its own command description lists only html|text|json|plan) and appears in no P7 projection table. Surfaced here because a demo arguing 'cooperate with the standards' should not be sitting on an unlisted LegalDocML output."
