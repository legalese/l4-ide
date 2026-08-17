#!/usr/bin/env bash
# M4 (spec §10) acceptance run: emit each M4 example, then drive the emitted
# interview in real docassemble.base and compare against the L4 #EVAL oracle.
#
# This is the BEHAVIOURAL half of the M4 acceptance suite. The other half —
# what the emitted YAML must SAY — is `cabal test l4-cli-test -m "M4: breadth"`.
# Neither passes until M4 lands; five of the six examples do not even emit,
# and this script prints each refusal verbatim so that the redness is legible
# rather than merely red.
#
# Usage, from the repo root:
#     jl4/examples/docassemble/m4_acceptance.sh <path-to-l4> <path-to-python>
#
# e.g.
#     jl4/examples/docassemble/m4_acceptance.sh \
#       dist-newstyle/build/aarch64-osx/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4 \
#       /tmp/da-venv/bin/python
#
# The venv recipe is in README.md §"the headless harness". Exit status is the
# number of examples that did not round-trip.

set -u

L4=${1:?usage: m4_acceptance.sh <l4 binary> <python in the docassemble venv>}
PY=${2:?usage: m4_acceptance.sh <l4 binary> <python in the docassemble venv>}

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

export JL4_LIBRARY_PATH="$ROOT/jl4-core/libraries"

# The M4 examples, in spec §10's own order: LIST OF, payload constructors,
# MAYBE NUMBER/DATE, date arithmetic, the review block, document assembly.
EXAMPLES="tenant-list payload-enum maybe-scalars statutory-age review-checklist notice-letter"

fails=0
for stem in $EXAMPLES; do
  src="$ROOT/jl4/examples/docassemble/$stem.l4"
  echo "═══════════════════════════════════════════════════════════════════"
  echo "── $stem"
  if ! "$L4" docassemble "$src" -o "$OUT/$stem.yml" >"$OUT/$stem.emit.log" 2>&1; then
    echo "   EMIT REFUSED — the M4 construct this example exists for is not landed:"
    sed 's/^/   | /' "$OUT/$stem.emit.log"
    fails=$((fails + 1))
    continue
  fi
  # Both artifact shapes, every example: R11 decision 6 says packaging must not
  # change the meaning of the interview, and the harness's `--also` compares
  # them case by case. The RED phase left this untested for the M4 constructs;
  # it is exactly where a `content file:` template reference (which raises at
  # PARSE time when the file is absent) would break the BARE artifact while the
  # packaged one still worked.
  if ! "$L4" docassemble "$src" --package "$OUT/pkg-$stem" \
       >"$OUT/$stem.pkg.log" 2>&1; then
    echo "   PACKAGE FAILED:"
    sed 's/^/   | /' "$OUT/$stem.pkg.log"
    fails=$((fails + 1))
    continue
  fi
  if "$PY" "$ROOT/jl4/examples/docassemble/roundtrip_check.py" \
       "$OUT/$stem.yml" "$stem" "--also=$OUT/pkg-$stem" --quiet; then
    echo "   ROUND-TRIP OK"
  else
    fails=$((fails + 1))
  fi
done

# The M2 inherited defect (spec §8.4), whose named owner is M4: the `citations`
# example carries a case that changes an earlier answer and re-drives. That one
# DOES emit today — the redness is a wrong answer, not a refusal.
echo "═══════════════════════════════════════════════════════════════════"
echo "── citations (M2 inherited debt: a changed answer)"
if "$L4" docassemble "$ROOT/jl4/examples/docassemble/citations.l4" \
     -o "$OUT/citations.yml" >/dev/null 2>&1 \
   && "$L4" docassemble "$ROOT/jl4/examples/docassemble/citations.l4" \
     --package "$OUT/pkg-citations" >/dev/null 2>&1; then
  if "$PY" "$ROOT/jl4/examples/docassemble/roundtrip_check.py" \
       "$OUT/citations.yml" citations "--also=$OUT/pkg-citations" --quiet; then
    echo "   ROUND-TRIP OK"
  else
    fails=$((fails + 1))
  fi
else
  echo "   EMIT FAILED (this one emits today; something else is broken)"
  fails=$((fails + 1))
fi

echo "═══════════════════════════════════════════════════════════════════"
echo "M4 acceptance: $fails of 7 did not round-trip."
exit "$fails"
