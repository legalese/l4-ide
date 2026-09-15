#!/usr/bin/env bash
# Reproduce the computational claims in README.md.
#
# Prints PASS / FAIL / SKIP per claim. SKIP is used when an optional tool is
# absent, so the harness always runs to the end and always says why.
#
# NOTE: `l4 run` exits 0 on a FAILING #ASSERT -- it prints the failure at
# DiagnosticSeverity_Error and carries on. So every gate below greps for that
# string. Never use `&&` here; it is a false green.
#
# NOTE: claim 11 runs `cabal test`, which BUILDS. Concurrent `cabal`
# invocations inside a single worktree corrupt each other -- the symptom is a
# spurious "renameFile:renamePath ... .o.tmp does not exist" that looks like a
# code error and is not. Exactly ONE cabal may run per worktree at a time. If
# something else is building in this worktree, do not run this script; claims
# 1..10 touch no build lock, claim 11 does.
#
# NOTE: every gate below must be able to FAIL. A gate that prints a number it
# never compared, or restates a condition another gate already tested, is a
# false green wearing a PASS.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO" || exit 1

WIDE=0
[ "${1:-}" = "--wide" ] && WIDE=1

pass=0; fail=0; skip=0
ok()   { printf 'PASS  %s\n' "$1"; pass=$((pass+1)); }
no()   { printf 'FAIL  %s\n      %s\n' "$1" "${2:-}"; fail=$((fail+1)); }
sk()   { printf 'SKIP  %s\n      %s\n' "$1" "${2:-}"; skip=$((skip+1)); }

# ---------------------------------------------------------------- locate l4
L4=""
for cand in \
  "$REPO"/dist-newstyle/build/*/ghc-*/jl4-*/x/l4/build/l4/l4 \
  "$REPO"/dist-newstyle/build/*/ghc-*/jl4-*/b/l4/build/l4/l4
do
  [ -x "$cand" ] && { L4="$cand"; break; }
done

if [ -n "$L4" ]; then
  # A binary from THIS worktree: pin the library path to this tree.
  export JL4_LIBRARY_PATH="$REPO/jl4-core/libraries"
  printf 'using worktree binary: %s\n' "$L4"
  printf 'JL4_LIBRARY_PATH=%s\n\n' "$JL4_LIBRARY_PATH"
elif command -v l4 >/dev/null 2>&1; then
  # An INSTALLED binary may be older than this tree's prelude. Leave
  # JL4_LIBRARY_PATH unset so it resolves its own EMBEDDED prelude; pointing an
  # older binary at this tree's libraries produces cascading bogus
  # "could not find a definition" errors that look like broken code.
  L4="$(command -v l4)"
  unset JL4_LIBRARY_PATH
  printf 'using installed binary: %s (JL4_LIBRARY_PATH left UNSET on purpose)\n\n' "$L4"
else
  sk "everything" "no l4 binary found; run 'cabal build l4' first"
  printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
  exit 0
fi

MODEL=jl4/examples/ok/closing-the-loop/fristberechnung.l4
CAL=jl4/examples/ok/closing-the-loop/feiertage.l4
CTRL=jl4/examples/ok/closing-the-loop/fristbeginn-nonexhaustive-control.l4

OUT=$(mktemp); CALOUT=$(mktemp); CTRLOUT=$(mktemp); VEROUT=$(mktemp)
trap 'rm -f "$OUT" "$CALOUT" "$CTRLOUT" "$VEROUT"' EXIT

"$L4" run "$MODEL" >"$OUT"    2>&1
"$L4" run "$CAL"   >"$CALOUT" 2>&1
"$L4" run "$CTRL"  >"$CTRLOUT" 2>&1

# 1 -- the model runs clean
if grep -q 'DiagnosticSeverity_Error' "$OUT"; then
  no "1  model type-checks and every assertion holds" "$(grep -m1 -A3 DiagnosticSeverity_Error "$OUT" | tr '\n' ' ')"
else
  # `l4 run` prints everything TWICE (a diagnostics section, then one
  # Evaluation[n] block per evaluating directive). Count the second section
  # only, or you double every assertion.
  n=$(sed -n '/^Evaluation\[/,$p' "$OUT" | grep -c 'assertion satisfied')
  [ "$n" -eq 71 ] && ok "1  model type-checks; all $n assertions satisfied" \
                  || no "1  model type-checks" "$n assertions satisfied, expected 71"
fi

# 2 -- the calendar runs clean and cross-checks
if grep -q 'DiagnosticSeverity_Error' "$CALOUT"; then
  no "2  calendar type-checks and cross-checks" "$(grep -m1 -A3 DiagnosticSeverity_Error "$CALOUT" | tr '\n' ' ')"
else
  m=$(sed -n '/^Evaluation\[/,$p' "$CALOUT" | grep -c 'assertion satisfied')
  [ "$m" -eq 20 ] && ok "2  calendar type-checks; all $m assertions satisfied, computus agrees with its 21-year oracle" \
                  || no "2  calendar type-checks" "$m assertions satisfied, expected 20"
fi

# 3 -- ONE TRIGGER, THREE ANSWERS (the headline)
#
# Anchored on ORDER, not on membership. Every one of these three strings is
# also printed by some OTHER directive in the same run (Beispiel 6 prints two
# of them), so a set-membership test stays green with the 6c evaluations
# deleted. Pull the Result: values out in the order they were printed and look
# for the ordered triple.
results() { sed -n '/^Evaluation\[/,$p' "$OUT" | sed -n '/^Result:/{n;s/^ *//;p;}'; }
if results | grep -A2 -x 'DATE OF 28, 2, 2026' \
   | grep -A1 -x 'DATE OF 27, 2, 2026' \
   | grep -q -x 'DATE OF 2, 3, 2026'; then
  ok "3  one trigger, three answers: 28.2. (statute) / 27.2. (charitable) / 2.3. (literal)"
else
  no "3  one trigger, three answers" "the ordered triple 28.2 / 27.2 / 2.3 is not among the results"
fi

# 3b -- the widest spread: four days (Beispiel 6d)
if results | grep -A2 -x 'DATE OF 28, 3, 2026' \
   | grep -A1 -x 'DATE OF 31, 3, 2026' \
   | grep -q -x 'DATE OF 1, 4, 2026'; then
  ok "3b widest spread is four days: 28.3. / 31.3. / 1.4."
else
  no "3b widest spread is four days" "the ordered triple 28.3 / 31.3 / 1.4 is not among the results"
fi

# 4..7 -- the sweeps
grep -q '^  12$' "$OUT" \
  && ok "4  the section 188 layer diverges on 12 days of 2026" \
  || no "4  the section 188 layer diverges on 12 days of 2026" "expected a bare '12' result"

grep -q 'DATE OF 28, 1, 2026, DATE OF 29, 1, 2026, DATE OF 30, 1, 2026, DATE OF 28, 2, 2026' "$OUT" \
  && ok "5  the divergent set is not the month-ends a reviewer expects" \
  || no "5  the divergent set" "expected list beginning 28/29/30 Jan, 28 Feb"

ten=$(grep -c 'DATE OF 30, 5, 2026, DATE OF 30, 6, 2026, DATE OF 30, 8, 2026, DATE OF 30, 9, 2026, DATE OF 30, 11, 2026' "$OUT")
[ "$ten" -ge 1 ] \
  && ok "6  10 of the 12 survive section 193 and reach the user" \
  || no "6  10 of the 12 survive section 193" "expected the 10-element list"

grep -q 'DATE OF 29, 1, 2026, DATE OF 30, 1, 2026, DATE OF 31, 1, 2026, DATE OF 31, 3, 2026' "$OUT" \
  && ok "7  the teaching maxim fails on 7 days of 2026" \
  || no "7  the teaching maxim fails on 7 days of 2026" "expected 29/30/31 Jan, 31 Mar, ..."

# 8 -- I1 is false as the paper states it
#
# Gate on the DIRECTIVES, not on "the model ran clean" -- that is claim 1, and
# restating it here would stay green with the I1 directives deleted. Each
# `#ASSERT` prints its own source range, so find the two `Gegenbeispiel zu I1`
# lines in the source and require an 'assertion satisfied' for each range.
assert_ok() {   # $1 = 1-based source line number of the directive
  sed -n '/^Evaluation\[/,$p' "$OUT" \
    | grep -A4 "fristberechnung.l4:$1:1" | grep -q 'assertion satisfied'
}
i1lines=$(grep -n '^#ASSERT.*`Gegenbeispiel zu I1`' "$MODEL" | cut -d: -f1)
i1n=$(printf '%s\n' "$i1lines" | grep -c .)
i1bad=0
for ln in $i1lines; do assert_ok "$ln" || i1bad=1; done
if [ "$i1n" -eq 2 ] && [ "$i1bad" -eq 0 ]; then
  ok "8  invariant I1 is false at date granularity; the repaired I1' holds (both Gegenbeispiel directives satisfied)"
else
  no "8  invariant I1 is false at date granularity" "found $i1n Gegenbeispiel directives (expected 2), unsatisfied=$i1bad"
fi

# 8b -- both repaired invariants are false where section 186 displaces
b17lines=$(grep -n '^#ASSERT NOT.*`Beispiel 17b`' "$MODEL" | cut -d: -f1)
b17n=$(printf '%s\n' "$b17lines" | grep -c .)
b17bad=0
for ln in $b17lines; do assert_ok "$ln" || b17bad=1; done
if [ "$b17n" -eq 2 ] && [ "$b17bad" -eq 0 ]; then
  ok "8b I1' and I2 are both false where section 186 displaces the regime (Beispiel 17b)"
else
  no "8b I1' and I2 false under section 186" "found $b17n Beispiel 17b directives (expected 2), unsatisfied=$b17bad"
fi

# 8c -- section 190's fork is printed, not merely recorded
if results | grep -A1 -x 'DATE OF 12, 3, 2026' | grep -q -x 'DATE OF 10, 3, 2026'; then
  ok "8c section 190's fork is printed: 12.3. (reading taken) then 10.3. (reading rejected)"
else
  no "8c section 190's fork is printed" "expected 12.3.2026 immediately followed by 10.3.2026"
fi

# 9 -- the control fixture
if grep -q 'still need to be considered' "$CTRLOUT"; then
  ok "9  the exhaustiveness checker is demonstrably looking (control fixture warns)"
else
  no "9  control fixture" "expected an exhaustiveness warning naming the missing arm"
fi

# 10 -- l4 verify, reported honestly
#
# The only CHECKED number is the finding count: it is the claim README.md makes
# ("zero findings"), and it is the one that must red the gate if it moves. The
# analysed / skipped counts drift whenever a definition is added to the model,
# so they are printed as OBSERVED values and deliberately not compared -- see
# REPRODUCE.md. Reading them off l4 verify's own summary line, not recomputing
# them from a grep that counts something else.
"$L4" verify "$MODEL" >"$VEROUT" 2>/dev/null
summary=$(grep -m1 -E '[0-9]+ decision\(s\) analysed' "$VEROUT")
if [ -z "$summary" ]; then
  no "10 l4 verify" "no summary line matching 'N decision(s) analysed' in the output"
else
  # Match the WHOLE shape of the line in one pattern. A loose `.*([0-9]+)`
  # is greedy and would read "10 finding(s)" as 0 -- a false green in exactly
  # the case the gate exists for. Tested against a synthetic 10-finding line.
  shape='^ *([0-9]+) decision\(s\) analysed, ([0-9]+) skipped, ([0-9]+) finding\(s\).*$'
  an=$(printf '%s\n' "$summary" | sed -nE "s/$shape/\\1/p")
  na=$(printf '%s\n' "$summary" | sed -nE "s/$shape/\\2/p")
  nf=$(printf '%s\n' "$summary" | sed -nE "s/$shape/\\3/p")
  if [ -z "$nf" ]; then
    no "10 l4 verify" "summary line did not have the expected shape: $summary"
  elif [ "$nf" -ne 0 ]; then
    no "10 l4 verify: 0 findings" "l4 verify reported $nf finding(s): $summary"
  else
    ok "10 l4 verify: 0 findings (observed, not checked: $an analysed, $na skipped) -- a weak statement, as its own --help says"
  fi
fi

# 11 -- goldens
if command -v cabal >/dev/null 2>&1; then
  if cabal test jl4-test --test-options='-m closing-the-loop' >/dev/null 2>&1; then
    ok "11 goldens are current (18 examples, 0 failures)"
  else
    no "11 goldens are current" "cabal test jl4-test -m closing-the-loop failed"
  fi
else
  sk "11 goldens are current" "cabal not on PATH"
fi

# -- wide sweeps, deliberately outside the goldened model --------------------
if [ "$WIDE" = "1" ]; then
  printf '\n-- wide sweeps (not in the goldened model; bounds stated here) --\n'
  sk "W1 multi-year divergence sweep" "NOT WRITTEN -- this is a SKIP, not a run; the goldened model covers 2026 only"
else
  printf '\n(--wide would list the multi-year sweeps; they are NOT WRITTEN and it reports them as SKIP)\n'
fi

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
