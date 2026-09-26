#!/usr/bin/env bash
# P10 — publish.
#
# THIS STAGE IS SCAFFOLDED AND CANNOT RUN.
#
# It exists as an entry point so the pipeline's shape is visible and so that
# asking for it yields a named blocker rather than a missing file. It is NOT a
# member of either declared stage list, so its absence cannot make a run
# INCOMPLETE, and it writes no receipt: a stage that did not run has
# nothing to record.
#
# It does, however, COMPUTE AND PRINT THE DESTINATION it would write to. A
# refusal that names the exact repository, branch and directory is one the
# reader can check; a refusal that only says "somewhere in canon" is one they
# have to take on trust. It also means the fence — never the default branch,
# always somebody's drafts shelf — is built and exercised before the feature
# that would need it, which is how the MCP leg's loopback guard was done too.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "${BASH_SOURCE[0]}"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../lib"

cat >&2 <<'MSG'
p10-publish: SCAFFOLDED AND CANNOT RUN.

WHAT IT WOULD DO
  Deposit this encoding — the L4 modules, the registers, the projections and
  the conversion report — into the corpus-of-law repository, and either
  contribute to lexipedia or publish the comparison note in its place.
MSG

# The destination, derived rather than described. GO_S_CANON_PATH comes from the
# subject's sidecar; the row id is the encoding this run is about, which canon
# already agrees with; the branch is canon's main, ruled 2026-09-26 (see
# lib/canon-destination.mjs), unless L4_GO_CANON_BRANCH names a fork's branch.
echo "" >&2
echo "WHERE IT WOULD GO" >&2
if [[ -z "${GO_S_CANON_PATH:-}" ]]; then
  cat >&2 <<MSG
  This subject's sidecar declares no 'canon' block, so it has no destination.
  A guessed path on a public repository is worse than an absent one, so none
  is guessed. Add to etc/go/subjects/${GO_S_ID:-<id>}/subject.json:

      "canon": { "subject_path": "<jurisdiction>/<act-slug>" }

  The path grammar is canon's docs/directory-conventions.md — 'us/regcf',
  'uk/bna-1981', 'contracts/investment/yc-safe-postmoney'.
MSG
else
  CANON_ROW="${GO_S_ENCODING_ID:-primary}"
  [[ "$CANON_ROW" == "primary" ]] && CANON_ROW="${GO_S_CANON_PRIMARY_ROW:-primary}"
  DEST="$(node "$LIB/canon-destination.mjs" \
    --subject-path "$GO_S_CANON_PATH" \
    --row "$CANON_ROW" 2>&1)" && {
    echo "  $DEST" | sed 's/^  /  /' >&2
  } || {
    echo "  REFUSED: $DEST" >&2
  }
  cat >&2 <<'MSG'

  The branch is canon's `main` (ruled 2026-09-26): members of the legalese
  GitHub organisation commit there. A contributor outside Legalese sets
  L4_GO_CANON_BRANCH to a branch of their fork and opens a pull request.
  Either way the deposit is HG2's to open.
MSG
fi

cat >&2 <<'MSG'

BLOCKER
  Ruling R1 was RULED IN FULL on 2026-08-02: the repository is
  legalese/canon — public from day one with inspectable gates and encoding
  version numbers, sidecar class/instance layout, Apache-2.0 + carried
  source-terms + optional CC-BY on prose. SPEC.md is explicit that
  jl4/examples/ and experiments/ are NOT its long-term home. Ruling R2 was
  ruled the same day (probe done; comparison note at G4; contact only with
  a live page).

  The repository EXISTS — scaffolded 2026-08-02, public. (Two earlier
  versions of this text were wrong in the same way, one after the other:
  the first said it did not exist, written ten minutes before it was
  created; the second said it held ZERO subjects, which stopped being true
  as soon as subjects were filed. Both were counts of a repository this
  script cannot see. It no longer states one — the destination above is
  computed, and how full canon is can be read from canon.)

  What remains blocked is DEPOSITING. That is an outward-facing write, so
  it is HG2's, and it opens on a signature or not at all. This orchestrator
  therefore contains no code that can push anything, and this stage is
  where that absence is stated rather than assumed.

Nothing was written and no receipt was recorded.
MSG
exit 3
