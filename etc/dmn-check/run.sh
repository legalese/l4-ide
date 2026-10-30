#!/usr/bin/env bash
#
# Run red6/dmn-check (https://github.com/red6/dmn-check, Apache-2.0) over DMN
# files, or over the DMN that `l4 export dmn` writes for every L4 file in the
# corpus. See README.md in this directory, and src/main/java/DmnCheckRun.java.
#
#   etc/dmn-check/run.sh jl4/examples/dmn/expected/reg-cf.dmn [more.dmn ...]
#   etc/dmn-check/run.sh --corpus [ROOT ...]          # ROOT defaults to jl4/examples of this checkout
#
# OPTIONAL EVIDENCE, NOT A GATE. Nothing in .github/workflows runs this, and
# nothing in etc/verify-branch.sh does. When Maven, a JDK 21+, the pinned jars (or,
# with --corpus, an `l4`) are not there it prints ONE line starting `skipped:` and
# exits 0, and prints no VERDICT banner, so a skip cannot be mistaken for a pass.
# Set DMN_CHECK_REQUIRED=1 to make that skip an exit 1 (the same switch the
# sibling harnesses have: CAMUNDA_CHECK_REQUIRED, KIE_CHECK_REQUIRED).
#
# ZERO-INSTALL, like etc/camunda-dmn-check: Maven resolves the classpath into
# $DMN_CHECK_WORKDIR (default $TMPDIR/l4-dmn-check), nothing is written into the
# repo, and package.json and the lockfile are untouched.
#
# Environment:
#   DMN_CHECK_JAVA_HOME     a JDK 21+. Else the first usable candidate below. CI
#                           for the Camunda leg runs 21; pin this to a 21 if you
#                           want your result to mean what that one means.
#   DMN_CHECK_WORKDIR       where the classpath, classes and corpus export go.
#   DMN_CHECK_L4            the `l4` for --corpus. Else `l4` on PATH. Put YOUR
#                           worktree's binary first: an `l4` older than the
#                           corpus misreads newer syntax (CLAUDE.md section 3.1).
#   DMN_CHECK_JOBS          parallel exports in --corpus mode (default 4).
#   DMN_CHECK_EXPORT_TIMEOUT  seconds per export in --corpus mode (default 180).
#   DMN_CHECK_REQUIRED=1    a skip is an exit 1.
#
# Exit status: 0 when no file had an ERROR-severity finding, was unreadable, or
# crashed a validator; 1 otherwise (WARNINGs do not fail the run unless
# --fail-on-warning). That is dmn-check's own rule, and the Camunda leg's.
#
# Everything before the first skip uses only bash builtins, so selftest.sh can
# test the skip paths with an empty PATH.
set -euo pipefail

case "${BASH_SOURCE[0]}" in */*) here="${BASH_SOURCE[0]%/*}" ;; *) here=. ;; esac
here="$(cd "$here" && pwd)"

skip() {
  echo "skipped: dmn-check: $1"
  if [ "${DMN_CHECK_REQUIRED:-0}" = "1" ]; then exit 1; fi
  exit 0
}

# NOT a skip: a harness that does not compile, or a classpath whose jars are not
# the pinned ones, is a defect (or an attack), and fails on every machine.
broken() {
  echo "BROKEN  dmn-check: $1" >&2
  echo "        This is a defect in the repo or its dependencies, not a missing toolchain." >&2
  exit 1
}

corpus=0
roots=()
passthru=()
while [ $# -gt 0 ]; do
  case "$1" in
    --corpus) corpus=1; shift ;;
    --tsv) passthru+=("$1" "${2:?--tsv needs a file}"); shift 2 ;;
    --fail-on-warning) passthru+=("$1"); shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) roots+=("$1"); shift ;;
  esac
done
if [ "$corpus" = 0 ] && [ "${#roots[@]}" = 0 ]; then
  echo "usage: run.sh [--tsv F] [--fail-on-warning] FILE.dmn ...   |   run.sh --corpus [ROOT ...]" >&2
  exit 2
fi

command -v mvn >/dev/null 2>&1 || skip "mvn not on PATH (brew install maven)"

# ---- the JDK -----------------------------------------------------------------
# dmn-check 1.4.0 is compiled for Java 21 (its parent pom sets java.version 21;
# the class files are version 65). Take the first candidate that is 21 or newer.
if [ -z "${DMN_CHECK_JAVA_HOME:-}" ]; then
  for candidate in \
      /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
      /opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home \
      /usr/lib/jvm/java-21-openjdk-amd64 \
      /usr/lib/jvm/java-21-openjdk \
      "$(/usr/libexec/java_home -v 21+ 2>/dev/null || true)"; do
    [ -n "$candidate" ] && [ -x "$candidate/bin/java" ] && { DMN_CHECK_JAVA_HOME="$candidate"; break; }
  done
fi
[ -n "${DMN_CHECK_JAVA_HOME:-}" ] && [ -x "$DMN_CHECK_JAVA_HOME/bin/java" ] \
  || skip "no JDK 21+ found (set DMN_CHECK_JAVA_HOME); dmn-check 1.4.0 needs class file 65"
export JAVA_HOME="$DMN_CHECK_JAVA_HOME"

major="$("$JAVA_HOME/bin/java" -XshowSettings:properties -version 2>&1 \
  | sed -n 's/.*java\.specification\.version = \([0-9][0-9]*\).*/\1/p' | head -1)"
[ -n "$major" ] && [ "$major" -ge 21 ] \
  || skip "JAVA_HOME is Java ${major:-?}; dmn-check 1.4.0 needs 21+"

# ---- the l4 (corpus mode only) -----------------------------------------------
if [ "$corpus" = 1 ]; then
  l4bin="${DMN_CHECK_L4:-}"
  [ -n "$l4bin" ] || l4bin="$(command -v l4 2>/dev/null || true)"
  [ -n "$l4bin" ] && [ -x "$l4bin" ] \
    || skip "--corpus needs an l4 (put one on PATH or set DMN_CHECK_L4)"
fi

# ---- the classpath -----------------------------------------------------------
out="${DMN_CHECK_WORKDIR:-${TMPDIR:-/tmp}/l4-dmn-check}"
mkdir -p "$out"
cp="$out/cp.txt"
# Keyed on pom.xml's mtime, so bumping the pin cannot leave the old classpath behind.
if [ ! -s "$cp" ] || [ "$here/pom.xml" -nt "$cp" ]; then
  rm -f "$cp"
  echo "# resolving de.redsix:dmn-check-cli into $out (first run only)" >&2
  mvn -q -B -f "$here/pom.xml" -Dmdep.outputFile="$cp" dependency:build-classpath \
    > "$out/mvn.log" 2>&1 \
    || skip "could not resolve dmn-check from Maven (offline? see $out/mvn.log)"
fi
[ -s "$cp" ] || skip "empty classpath after dependency:build-classpath (see $out/mvn.log)"

# ---- the checksum pin --------------------------------------------------------
# Maven checks a jar against the checksum the SAME repository publishes, which
# stops a corrupt download and nothing else. jars.sha256 is the pin: one
# `sha256  file-name` line per jar on the classpath, sorted.
if command -v shasum >/dev/null 2>&1; then sha() { shasum -a 256 "$1"; }
elif command -v sha256sum >/dev/null 2>&1; then sha() { sha256sum "$1"; }
else skip "neither shasum nor sha256sum on PATH, so the jar pin cannot be checked"
fi
actual="$out/jars.actual"
: > "$actual"
# cp.txt has no trailing newline, so read returns 1 at EOF having filled the array
IFS=: read -r -a jars < "$cp" || true
for jar in "${jars[@]}"; do
  [ -f "$jar" ] || broken "classpath names $jar, which is not a file"
  printf '%s  %s\n' "$(sha "$jar" | cut -d' ' -f1)" "${jar##*/}" >> "$actual"
done
LC_ALL=C sort -o "$actual" "$actual"
if ! diff -u "$here/jars.sha256" "$actual" > "$out/jars.diff"; then
  cat "$out/jars.diff" >&2
  broken "the resolved jars are not the ones jars.sha256 pins (diff above; '-' is the pin)"
fi

# ---- the driver --------------------------------------------------------------
# `--release 21` so the cached class loads on every JDK this script accepts. The
# Camunda leg compiles without it, and its README records the stale-cache trap
# that follows; this harness does not inherit that trap.
src="$here/src/main/java/DmnCheckRun.java"
if [ ! -s "$out/classes/DmnCheckRun.class" ] || [ "$src" -nt "$out/classes/DmnCheckRun.class" ]; then
  mkdir -p "$out/classes"
  "$JAVA_HOME/bin/javac" --release 21 -nowarn -cp "$(cat "$cp")" -d "$out/classes" "$src" \
    || broken "javac failed on $src (see above)"
fi

# The pin, read out of the pom rather than duplicated here, and handed to the
# driver ONLY so it can compare it with the version it observed off the classpath.
pinned="$(sed -n 's/.*<dmncheck\.version>\(.*\)<\/dmncheck\.version>.*/\1/p' "$here/pom.xml" | head -1)"
[ -n "$pinned" ] || broken "no <dmncheck.version> in $here/pom.xml"

run_driver() {
  "$JAVA_HOME/bin/java" -Dorg.slf4j.simpleLogger.defaultLogLevel=off \
    -Dl4.dmncheck.version.expected="$pinned" \
    -cp "$out/classes:$(cat "$cp")" DmnCheckRun "$@"
}

if [ "$corpus" = 0 ]; then
  exec "$JAVA_HOME/bin/java" -Dorg.slf4j.simpleLogger.defaultLogLevel=off \
    -Dl4.dmncheck.version.expected="$pinned" \
    -cp "$out/classes:$(cat "$cp")" DmnCheckRun ${passthru[@]+"${passthru[@]}"} "${roots[@]}"
fi

# ---- corpus mode -------------------------------------------------------------
# The default root is this checkout's jl4/examples, found from this script and not
# from the caller's directory; named roots are taken relative to the caller's.
if [ "${#roots[@]}" = 0 ]; then
  cd "$here/../.."
  roots=(jl4/examples)
fi
work="$out/corpus"
rm -rf "$work"
mkdir -p "$work"
echo "# l4: $l4bin   JL4_LIBRARY_PATH: ${JL4_LIBRARY_PATH:-(unset: the embedded prelude)}"
echo "# roots: ${roots[*]} (relative to $(pwd))   workdir: $work"
"$here/export-corpus.sh" "$l4bin" "$work" "${roots[@]}"

list="$work/exported.txt"
if [ ! -s "$list" ]; then
  echo "dmn-check VERDICT: 0 exported file(s), nothing to check   <<< FAILED"
  exit 1
fi
# xargs would split the list across processes and print several banners; one JVM
# and one banner it is. Paths with newlines are not supported (none exist).
files=()
while IFS= read -r line; do files+=("$line"); done < "$list"
set +e
run_driver --tsv "$work/findings.tsv" ${passthru[@]+"${passthru[@]}"} "${files[@]}" > "$work/report.txt"
rc=$?
set -e
sed -n '/^BY VALIDATOR/,$p' "$work/report.txt"
echo "# full report: $work/report.txt   findings: $work/findings.tsv   exports: $work/export-status.tsv"
exit "$rc"
