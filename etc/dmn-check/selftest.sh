#!/usr/bin/env bash
#
# Does etc/dmn-check/run.sh still do what its README says? Run it by hand:
#
#   etc/dmn-check/selftest.sh
#
# It is not wired into CI or into etc/verify-branch.sh, for the same reason
# run.sh is not: dmn-check is optional evidence here (README, "Policy").
#
# Seven checks. The first three need Java 21+ and Maven and are skipped, loudly
# and with exit 0, on a machine that has neither; the other four need only bash.
#
#   1  POSITIVE CONTROL. fixtures/clean.dmn is reported as checked, with no
#      findings. A harness that cannot say "nothing found" cannot be believed
#      when it says "found".
#   2  NEGATIVE CONTROL. fixtures/overlap.dmn has a conflicting pair and a
#      duplicated row under a UNIQUE hit policy. Both are reported, by validator
#      name, with the exact count, and the run exits 1.
#   3  fixtures/number-type.dmn: typeRef="number", which `l4 export dmn` writes
#      and dmn-check 1.4.0 cannot parse, is reported once by
#      OutputTypeDeclarationValidator. If this check starts failing, dmn-check
#      has learned "number" and README.md's account of its findings is stale.
#   4  SKIP, Maven absent. One line, starting `skipped:`, exit 0.
#   5  SKIP, no JDK 21+. Same.
#   6  DMN_CHECK_REQUIRED=1 turns that skip into exit 1, still with one line.
#   7  SKIP, corpus mode without an `l4`. Same.
#
# Checks 3-6 look at the WHOLE of the output, not at a grep for the word: "one
# line" is the contract, and a skip that also prints a Maven stack trace is not it.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
run="$here/run.sh"
fails=0

ok()   { echo "ok    $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }

# Run run.sh with the given environment prefix; leave its output in $got and its
# exit status in $rc. No `local`, no arrays: this must work on macOS bash 3.2.
go() { got="$("$@" 2>&1)"; rc=$?; }

one_skipped_line() {
  [ "$(printf '%s\n' "$got" | wc -l | tr -d ' ')" = 1 ] \
    && printf '%s\n' "$got" | grep -q '^skipped: '
}

# ---- 1 and 2 -----------------------------------------------------------------
go "$run" "$here/fixtures/clean.dmn"
if printf '%s\n' "$got" | grep -q '^skipped: '; then
  echo "skipped: checks 1-3 need Java 21+ and Maven, and run.sh reports: ${got#skipped: }"
else
  if [ "$rc" = 0 ] \
     && printf '%s\n' "$got" | grep -q 'VERDICT: 1 file(s), 1 read, 0 unreadable, 0 error(s), 0 warning(s)' ; then
    ok "1 positive control: clean.dmn is checked and has no findings"
  else
    fail "1 positive control: clean.dmn (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'
  fi

  go "$run" "$here/fixtures/overlap.dmn"
  if [ "$rc" = 1 ] \
     && printf '%s\n' "$got" | grep -q 'ERROR *ConflictingRuleValidator' \
     && printf '%s\n' "$got" | grep -q 'ERROR *DuplicateRuleValidator' \
     && printf '%s\n' "$got" | grep -q 'ConflictingRuleValidator *1 error(s)' \
     && printf '%s\n' "$got" | grep -q 'DuplicateRuleValidator *1 error(s)' \
     && printf '%s\n' "$got" | grep -q 'ShadowedRuleValidator *2 error(s)' \
     && printf '%s\n' "$got" | grep -q 'VERDICT: 1 file(s), 1 read, 0 unreadable, 4 error(s), 0 warning(s), 0 validator crash(es), 21 validator(s)'; then
    ok "2 negative control: overlap.dmn is reported, by validator, and the run exits 1"
  else
    fail "2 negative control: overlap.dmn (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'
  fi

  go "$run" "$here/fixtures/number-type.dmn"
  if [ "$rc" = 1 ] \
     && printf '%s\n' "$got" | grep -q "OutputTypeDeclarationValidator.*Could not parse FEEL expression type 'number'" \
     && printf '%s\n' "$got" | grep -q 'VERDICT: 1 file(s), 1 read, 0 unreadable, 1 error(s), 0 warning(s)'; then
    ok "3 number-type.dmn: typeRef=\"number\" is the one thing dmn-check 1.4.0 objects to"
  else
    fail "3 number-type.dmn (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'
  fi
fi

# ---- 4: Maven absent ----------------------------------------------------------
# An empty directory as PATH: run.sh must reach its skip using builtins only.
empty="$(mktemp -d)"
go env PATH="$empty" /bin/bash "$run" "$here/fixtures/clean.dmn"
if [ "$rc" = 0 ] && one_skipped_line; then ok "4 skip, Maven absent: $got"; else
  fail "4 skip, Maven absent (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'; fi
rmdir "$empty"

# ---- 5, 6: no JDK 21+ --------------------------------------------------------
go env DMN_CHECK_JAVA_HOME=/nonexistent/jdk "$run" "$here/fixtures/clean.dmn"
if [ "$rc" = 0 ] && one_skipped_line; then ok "5 skip, no JDK 21+: $got"; else
  fail "5 skip, no JDK 21+ (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'; fi

go env DMN_CHECK_REQUIRED=1 DMN_CHECK_JAVA_HOME=/nonexistent/jdk "$run" "$here/fixtures/clean.dmn"
if [ "$rc" = 1 ] && one_skipped_line; then ok "6 DMN_CHECK_REQUIRED=1 makes the skip an exit 1"; else
  fail "6 DMN_CHECK_REQUIRED=1 (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'; fi

# ---- 7: corpus mode, no l4 ----------------------------------------------------
go env DMN_CHECK_L4=/nonexistent/l4 "$run" --corpus
if [ "$rc" = 0 ] && one_skipped_line; then ok "7 skip, corpus mode without an l4: $got"; else
  fail "7 skip, corpus mode without an l4 (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'; fi

if [ "$fails" = 0 ]; then echo "selftest: all checks passed"; exit 0; fi
echo "selftest: $fails check(s) FAILED"
exit 1
