#!/usr/bin/env bash
# P3 — encode from source, isomorphically, in inert style (de novo path).
#
# THIS STAGE IS SCAFFOLDED AND CANNOT RUN.
#
# It exists as an entry point so the pipeline's shape is visible and so that
# asking for it yields a named blocker rather than a missing file. It is NOT a
# member of any milestone's declared stage list, so its absence cannot make a
# milestone INCOMPLETE, and it writes no receipt: a stage that did not run has
# nothing to record.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "${BASH_SOURCE[0]}"
  exit 0
fi

cat >&2 <<'MSG'
p3-encode: SCAFFOLDED AND CANNOT RUN.

WHAT IT WOULD DO
  Produce the first-class deliverable: L4 a domain expert can review against
  the regulation section by section, in inert style, with GIVEN over ASSUME,
  BRANCH over ELSE IF chains, and an @ref FR citation on every dated arm.

BLOCKER
  This stage is unbuilt. R4 was ruled 2026-08-02 (R4-FORK-REPRESENTATION.md
  §7): one Interpretation record threaded as an ordinary GIVEN, public
  interface delegating to private per-reading implementations — extended to
  regulative rules, whose MEANS-returned values take the same argument. The
  representation is decided; the encoding tooling that writes it is not
  built.
  Also unmechanisable by construction: SPEC.md §4's P3 stage names the
  deliverable as 'isomorphic -- a domain expert can review it against the
  regulation section by section', which has no checkable form and is carried
  by HG1 (SPEC.md §7.3).

Nothing was written and no receipt was recorded.
MSG
exit 3
