#!/usr/bin/env bash
#
# Does etc/dmn-check/run.sh still do what its README says? Run it by hand:
#
#   etc/dmn-check/selftest.sh
#
# It is not wired into CI or into etc/verify-branch.sh, for the same reason
# run.sh is not: dmn-check is optional evidence here (README, "Policy").
#
# Sixteen checks (0 to 15). Checks 1-3 and 10-14 need Java 21+ and Maven and are
# skipped, loudly and with exit 0, on a machine that has neither; check 8 needs
# Maven 3.9+ as well; the others need only bash.
#
#   0  Every script parses (`bash -n`), including the branches no other check reaches.
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
#   8  SKIP, dmn-check cannot be resolved (Maven offline, empty local repository,
#      fresh work directory). Same, and nothing else printed before it.
#
#   9  The corpus sweep survives an `l4` that refuses SILENTLY (exit 1 or a kill,
#      nothing on stderr): every file gets a row, with a default reason. It also
#      sweeps a `tests` directory and ignores `not-ok` and *.evaldiff.l4.
#  10  A RELATIVE DMN_CHECK_WORKDIR is taken relative to the caller, and nothing is
#      written beside run.sh.
#  11  A pom.xml Maven cannot read is BROKEN, exit 1, and NOT a `skipped:` line.
#  12  classes/ is trusted only while classes.stamp describes it: a planted or
#      altered .class, an added file, and an edited source whose mtime is OLDER
#      than the classes (a hash, not an mtime) each cause a recompile.
#  13  A classpath with an empty entry is BROKEN.
#  14  SKIP, neither shasum nor sha256sum on PATH. Same, and before any download.
#  15  `--corpus --tsv F` is refused (exit 2): the corpus run writes its own
#      findings.tsv, and a second --tsv used to replace it without a word.
#
# Checks 4-8 and 14 look at the WHOLE of the output, not at a grep for the word:
# "one line" is the contract, and a skip that also prints a Maven stack trace is not it.
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

# ---- 0: the scripts parse -----------------------------------------------------
# bash reads a script as it runs it, so a syntax error in the corpus branch of
# run.sh stays hidden until someone reaches it (an apostrophe inside a quoted
# ${var:-...} did exactly that). `bash -n` reads all of it, under the stock macOS
# bash 3.2 when that is what /bin/bash is.
syntax_ok=1
for f in run.sh export-corpus.sh summarise.sh selftest.sh; do
  /bin/bash -n "$here/$f" 2>/dev/null || { fail "0 syntax: $f does not parse under /bin/bash"; syntax_ok=0; }
done
[ "$syntax_ok" = 1 ] && ok "0 syntax: run.sh, export-corpus.sh, summarise.sh, selftest.sh parse under /bin/bash"

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

# ---- 8: dmn-check absent ------------------------------------------------------
# MAVEN_ARGS is read by Maven 3.9 and later only; an older Maven ignores it and
# would resolve from the network, so there is nothing to test.
mvn_mm="$(mvn -v 2>/dev/null | sed -n '1s/^Apache Maven \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p')"
mvn_major="${mvn_mm% *}"; mvn_minor="${mvn_mm#* }"
if [ -z "$mvn_mm" ] || [ "$mvn_major" -lt 3 ] || { [ "$mvn_major" = 3 ] && [ "$mvn_minor" -lt 9 ]; }; then
  echo "skipped: check 8 needs Maven 3.9+ (MAVEN_ARGS); this is ${mvn_mm:-no Maven}"
else
  repo="$(mktemp -d)"; wd="$(mktemp -d)"
  go env MAVEN_ARGS="-o -Dmaven.repo.local=$repo" DMN_CHECK_WORKDIR="$wd" "$run" "$here/fixtures/clean.dmn"
  if [ "$rc" = 0 ] && one_skipped_line; then ok "8 skip, dmn-check not resolvable: ${got%%(*}"; else
    fail "8 skip, dmn-check not resolvable (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'; fi
  rm -rf "$repo" "$wd"
fi

# ---- 9: a silent refusal does not kill the sweep ------------------------------
# An `l4` that segfaults, is OOM-killed or exits 1 writes nothing to stderr. The
# refusal-reason pipeline used to die on the empty file under `pipefail`, taking
# the whole sweep with it and leaving no row. Fake `l4`, so this needs only bash.
fk="$(mktemp -d)"
cat > "$fk/l4" <<'FAKE'
#!/bin/sh
# fake `l4 export dmn SRC -o DEST --fidelity-report`
src="$3"; dest="$5"
case "$src" in
  *silent.l4) exit 1 ;;
  *crash.l4)  kill -9 $$ ;;
  *loud.l4)   echo "noise" >&2; echo >&2; echo "the real reason" >&2; exit 1 ;;
  *)          printf '<definitions/>' > "$dest" ;;
esac
FAKE
chmod +x "$fk/l4"
mkdir -p "$fk/root/tests" "$fk/root/not-ok"
for f in ok silent crash loud tests/inside not-ok/negative; do : > "$fk/root/$f.l4"; done
: > "$fk/root/stray.evaldiff.l4"
got="$(cd "$fk" && "$here/export-corpus.sh" "$fk/l4" "$fk/out" root 2>&1)"; rc=$?
st="$fk/out/export-status.tsv"
row() { awk -F'\t' -v f="$1" '$1 ~ f { print $2 "|" $3 "|" $5 }' "$st"; }
if [ "$rc" = 0 ] \
   && [ "$(($(wc -l < "$st") - 1))" = 5 ] \
   && [ "$(row 'silent\.l4$')" = "refused|1|no output on stderr (exit 1)" ] \
   && [ "$(row 'crash\.l4$')" = "refused|137|no output on stderr (exit 137)" ] \
   && [ "$(row 'loud\.l4$')" = "refused|1|the real reason" ] \
   && [ "$(row 'root/ok\.l4$')" = "exported|0|" ] \
   && [ "$(row 'tests/inside\.l4$')" = "exported|0|" ] \
   && [ -z "$(row 'not-ok')" ] && [ -z "$(row 'evaldiff')" ] \
   && [ "$(wc -l < "$fk/out/exported.txt" | tr -d ' ')" = 2 ]; then
  ok "9 export sweep: a silent exit 1 and a kill are rows with a default reason; tests/ is swept; not-ok/ and *.evaldiff.l4 are not"
else
  fail "9 export sweep with a silently refusing l4 (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'; sed 's/^/      /' "$st" 2>/dev/null
fi
rm -rf "$fk"

# ---- 10-14: what only a real run can show -------------------------------------
# These need the toolchain, so they run only if a real run got as far as a verdict.
go "$run" "$here/fixtures/clean.dmn"
if printf '%s\n' "$got" | grep -q '^skipped: '; then
  echo "skipped: checks 10-14 need Java 21+ and Maven, and run.sh reports: ${got#skipped: }"
else
  tmp="$(mktemp -d)"
  before="$(ls -A "$here" | tr '\n' ' ')"

  # 10: a relative workdir
  mkdir "$tmp/cwd"
  got="$(cd "$tmp/cwd" && DMN_CHECK_WORKDIR=relwd "$run" "$here/fixtures/clean.dmn" 2>&1)"; rc=$?
  if [ "$rc" = 0 ] && printf '%s\n' "$got" | grep -q 'VERDICT: 1 file(s), 1 read, 0 unreadable, 0 error(s)' \
     && [ -s "$tmp/cwd/relwd/cp.txt" ] && [ "$(ls -A "$here" | tr '\n' ' ')" = "$before" ]; then
    ok "10 a relative DMN_CHECK_WORKDIR is resolved against the caller, and run.sh's directory is untouched"
  else
    fail "10 relative DMN_CHECK_WORKDIR (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'
  fi

  # 11: a pom Maven cannot read. Work on a COPY of this directory: run.sh reads
  # pom.xml from beside itself.
  cp -R "$here" "$tmp/repo"
  head -c 700 "$here/pom.xml" > "$tmp/repo/pom.xml"
  go env DMN_CHECK_WORKDIR="$tmp/wd-bad" "$tmp/repo/run.sh" "$here/fixtures/clean.dmn"
  if [ "$rc" = 1 ] && printf '%s\n' "$got" | grep -q '^BROKEN ' && ! printf '%s\n' "$got" | grep -q '^skipped:'; then
    ok "11 a pom.xml Maven cannot read is BROKEN with exit 1, not a skip"
  else
    fail "11 unreadable pom.xml (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'
  fi

  # 12: classes/ against classes.stamp. A second copy, so the source can be edited.
  cp -R "$here" "$tmp/repo2"
  wd="$tmp/wd"
  go env DMN_CHECK_WORKDIR="$wd" "$tmp/repo2/run.sh" "$here/fixtures/overlap.dmn"
  stamp1="$(cat "$wd/classes.stamp" 2>/dev/null)"
  printf 'not a class file' > "$wd/classes/DmnCheckRun.class"
  printf 'not a class file' > "$wd/classes/Planted.class"
  go env DMN_CHECK_WORKDIR="$wd" "$tmp/repo2/run.sh" "$here/fixtures/overlap.dmn"
  if [ "$rc" = 1 ] && printf '%s\n' "$got" | grep -q '4 error(s), 0 warning(s), 0 validator crash(es), 21 validator(s)' \
     && [ ! -e "$wd/classes/Planted.class" ] && ! grep -q Planted "$wd/classes.stamp" \
     && [ -n "$stamp1" ]; then
    ok "12a a planted or altered .class is wiped and the driver recompiled before it runs"
  else
    fail "12a planted .class (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'
  fi
  # An edited source that looks OLDER than the classes. An mtime test would keep
  # the stale driver.
  printf '\n// edited by selftest.sh\n' >> "$tmp/repo2/src/main/java/DmnCheckRun.java"
  touch -t 200001010000 "$tmp/repo2/src/main/java/DmnCheckRun.java"
  go env DMN_CHECK_WORKDIR="$wd" "$tmp/repo2/run.sh" "$here/fixtures/clean.dmn"
  if [ "$rc" = 0 ] && [ "$(sed -n 1p "$wd/classes.stamp")" != "$(printf '%s\n' "$stamp1" | sed -n 1p)" ]; then
    ok "12b an edited driver source is recompiled even when its mtime is older than the classes"
  else
    fail "12b edited source with an old mtime (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'
  fi

  # 13: an empty classpath entry. cp.txt is keyed on pom.xml's hash, so this
  # edited file is the one run.sh reads.
  printf '%s:' "$(cat "$wd/cp.txt")" > "$wd/cp.txt"
  go env DMN_CHECK_WORKDIR="$wd" "$tmp/repo2/run.sh" "$here/fixtures/clean.dmn"
  if [ "$rc" = 1 ] && printf '%s\n' "$got" | grep -q '^BROKEN .*empty entry'; then
    ok "13 a classpath with an empty entry is BROKEN"
  else
    fail "13 empty classpath entry (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'
  fi

  # 14: no sha tool. A PATH holding only what run.sh needs to get that far.
  mkdir "$tmp/bin"
  for t in mvn sed head; do ln -s "$(command -v "$t")" "$tmp/bin/$t"; done
  go env PATH="$tmp/bin" /bin/bash "$run" "$here/fixtures/clean.dmn"
  if [ "$rc" = 0 ] && one_skipped_line && printf '%s\n' "$got" | grep -q 'neither shasum nor sha256sum'; then
    ok "14 skip, no sha tool: $got"
  else
    fail "14 skip, no sha tool (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'
  fi
  rm -rf "$tmp"
fi

# ---- 15: --corpus with --tsv ---------------------------------------------------
go "$run" --corpus --tsv "$(mktemp -u)"
if [ "$rc" = 2 ] && printf '%s\n' "$got" | grep -q -- '--tsv cannot be combined with --corpus'; then
  ok "15 --corpus --tsv is refused with exit 2"
else
  fail "15 --corpus --tsv (exit $rc)"; printf '%s\n' "$got" | sed 's/^/      /'
fi

if [ "$fails" = 0 ]; then echo "selftest: all checks passed"; exit 0; fi
echo "selftest: $fails check(s) FAILED"
exit 1
