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
# nothing in etc/verify-branch.sh does. It prints ONE line starting `skipped:` and
# exits 0, and prints no VERDICT banner (so a skip cannot be mistaken for a pass),
# when the toolchain is not there:
#   * no Maven on PATH;
#   * no JDK 21 or later (see DMN_CHECK_JAVA_HOME below: JAVA_HOME and a `java` on
#     PATH are NOT consulted);
#   * neither shasum nor sha256sum on PATH, so the jar pin cannot be checked;
#   * dmn-check cannot be resolved from Maven (offline, or the first-run download
#     failed);
#   * with --corpus, no `l4`.
# A defect in the repo or in the resolved jars is NOT a skip: it is `BROKEN` on
# stderr and exit 1 (a pom Maven cannot read, a jar that is not the pinned one, a
# classpath with an empty entry, a driver that does not compile).
# Set DMN_CHECK_REQUIRED=1 to make a skip an exit 1 (the same switch the sibling
# harnesses have: CAMUNDA_CHECK_REQUIRED, KIE_CHECK_REQUIRED).
#
# ZERO-INSTALL, like etc/camunda-dmn-check: Maven resolves the classpath into
# $DMN_CHECK_WORKDIR (default $TMPDIR/l4-dmn-check-<uid>), nothing is written into
# the repo, and package.json and the lockfile are untouched. The FIRST run
# downloads dmn-check and its dependencies from Maven Central (about 18 jars).
#
# Environment:
#   DMN_CHECK_JAVA_HOME     a JDK 21+. Else the first usable candidate below.
#                           JAVA_HOME and a `java` on PATH are IGNORED, on purpose
#                           (assumed, not ruled; README, "Which JDK"): on the machine this was
#                           built on they are a JDK 26 for other work, and a result
#                           should not change with the shell it was run from. CI for
#                           the Camunda leg runs 21; pin this to a 21 if you want
#                           your result to mean what that one means.
#   DMN_CHECK_WORKDIR       where the classpath, classes and corpus export go.
#                           Made absolute before use; a relative one is taken
#                           relative to the caller's directory.
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
# Everything before the Maven check uses only bash builtins, so selftest.sh can
# test that skip with an empty PATH.
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
# --corpus passes its own --tsv to the driver, and a second one would win and make
# the kinds table vanish without a word.
if [ "$corpus" = 1 ] && [ "${#passthru[@]}" -gt 0 ]; then
  for a in "${passthru[@]}"; do
    [ "$a" = "--tsv" ] && { echo "run.sh: --tsv cannot be combined with --corpus (it writes <workdir>/corpus/findings.tsv itself)" >&2; exit 2; }
  done
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
  || skip "no JDK 21+ found (JAVA_HOME and PATH java are not consulted; set DMN_CHECK_JAVA_HOME); dmn-check 1.4.0 needs class file 65"
export JAVA_HOME="$DMN_CHECK_JAVA_HOME"

major="$("$JAVA_HOME/bin/java" -XshowSettings:properties -version 2>&1 \
  | sed -n 's/.*java\.specification\.version = \([0-9][0-9]*\).*/\1/p' | head -1)"
[ -n "$major" ] && [ "$major" -ge 21 ] \
  || skip "DMN_CHECK_JAVA_HOME ($JAVA_HOME) is Java ${major:-?}; dmn-check 1.4.0 needs 21+"

# ---- the l4 (corpus mode only) -----------------------------------------------
if [ "$corpus" = 1 ]; then
  l4bin="${DMN_CHECK_L4:-}"
  [ -n "$l4bin" ] || l4bin="$(command -v l4 2>/dev/null || true)"
  [ -n "$l4bin" ] && [ -x "$l4bin" ] \
    || skip "--corpus needs an l4 (put one on PATH or set DMN_CHECK_L4)"
  # Absolute, because the default root below changes directory.
  case "$l4bin" in
    /*) ;;
    */*) l4bin="$(cd "${l4bin%/*}" && pwd)/${l4bin##*/}" ;;
    *) l4bin="$(pwd)/$l4bin" ;;
  esac
fi

# ---- the sha tool ------------------------------------------------------------
# Before anything is downloaded: the pin below cannot be checked without one, and
# a skip that has already fetched 18 jars is a worse skip.
if command -v shasum >/dev/null 2>&1; then sha() { shasum -a 256 "$1"; }
elif command -v sha256sum >/dev/null 2>&1; then sha() { sha256sum "$1"; }
else skip "neither shasum nor sha256sum on PATH, so the jar pin cannot be checked"
fi
sha_of() { sha "$1" | cut -d' ' -f1; }

# ---- the work directory ------------------------------------------------------
# Absolute BEFORE any use: mvn resolves a relative -Dmdep.outputFile against the pom's
# directory (so a relative workdir wrote cp.txt into the repo and then skipped for
# an "empty classpath"), and the corpus branch changes directory.
if [ -n "${DMN_CHECK_WORKDIR:-}" ]; then
  out="$DMN_CHECK_WORKDIR"
  mkdir -p "$out"
else
  # Per user: /tmp is shared on Linux, and a directory another user can write to
  # holds a classpath and classes this script would run.
  out="${TMPDIR:-/tmp}/l4-dmn-check-$(id -u)"
  mkdir -p "$out"
  [ -O "$out" ] || broken "$out exists and is not owned by you; set DMN_CHECK_WORKDIR"
fi
out="$(cd "$out" && pwd)"

# ---- the classpath -----------------------------------------------------------
[ -f "$here/pom.xml" ] || broken "$here/pom.xml is missing"
cp="$out/cp.txt"
# Keyed on the pom's hash, not its mtime: two checkouts sharing a workdir, or a
# checkout switched to another branch, can each have the newer file.
pomsha="$(sha_of "$here/pom.xml")"
if [ ! -s "$cp" ] || [ "$(cat "$out/cp.pom.sha256" 2>/dev/null || true)" != "$pomsha" ]; then
  rm -f "$cp" "$out/cp.pom.sha256"
  # Nothing is printed before this can skip: a skip is ONE line.
  if ! mvn -q -B -f "$here/pom.xml" -Dmdep.outputFile="$cp" dependency:build-classpath \
      > "$out/mvn.log" 2>&1; then
    # A pom Maven cannot read is this repo's defect, whatever machine it is on.
    # Everything else Maven can fail at (resolving, downloading) is the machine's.
    if grep -qE 'The build could not read|Non-parseable POM|Malformed POM' "$out/mvn.log"; then
      broken "Maven cannot read $here/pom.xml (see $out/mvn.log)"
    fi
    skip "could not resolve dmn-check from Maven (offline? see $out/mvn.log)"
  fi
  echo "# resolved de.redsix:dmn-check-cli into $out (first run only)" >&2
  if [ -s "$cp" ]; then printf '%s\n' "$pomsha" > "$out/cp.pom.sha256"; fi
fi
[ -s "$cp" ] || skip "empty classpath after dependency:build-classpath (see $out/mvn.log)"

# Read ONCE and used for javac and java alike, so what was checked is what runs.
classpath="$(cat "$cp")"
# An empty entry is the current directory to Java. `read -a` drops a trailing one,
# so the jar loop below could not see it.
case "$classpath" in
  ''|:*|*:|*::*) broken "the classpath in $cp has an empty entry, which Java reads as the current directory" ;;
esac

# ---- the checksum pin --------------------------------------------------------
# Maven checks a jar against the checksum the SAME repository publishes, which
# stops a corrupt download and nothing else. jars.sha256 is the pin: one
# `sha256  file-name` line per jar on the classpath, sorted.
actual="$out/jars.actual"
: > "$actual"
IFS=: read -r -a jars <<< "$classpath"
for jar in "${jars[@]}"; do
  case "$jar" in /*) ;; *) broken "classpath entry '$jar' is not an absolute path" ;; esac
  [ -f "$jar" ] || broken "classpath names $jar, which is not a file"
  printf '%s  %s\n' "$(sha_of "$jar")" "${jar##*/}" >> "$actual"
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
#
# classes/ is first on the classpath, so whatever sits in it runs ahead of the
# pinned jars. It is therefore trusted only while classes.stamp, written next to
# it, still describes it exactly: the hash of the driver source, the hash of
# jars.sha256 (the driver is compiled against those jars), and the hash of every
# file under classes/. Anything else (an edited source, a bumped pin, a planted or
# altered .class, an added file, a symlink) wipes classes/ and compiles afresh.
src="$here/src/main/java/DmnCheckRun.java"
classes="$out/classes"
stamp="$out/classes.stamp"
srcsha="$(sha_of "$src" 2>/dev/null || true)"
[ -n "$srcsha" ] || broken "cannot read $src"
pinsha="$(sha_of "$here/jars.sha256")"
snapshot() {
  echo "source $srcsha"
  echo "pin $pinsha"
  [ -d "$classes" ] || return 0
  ( cd "$classes"
    if [ -n "$(find . ! -type d ! -type f -print)" ]; then echo "NOT-A-REGULAR-FILE"; fi
    find . -type f | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s  %s\n' "$(sha_of "$f")" "$f"
    done )
}
if [ ! -f "$stamp" ] || [ "$(snapshot)" != "$(cat "$stamp")" ]; then
  rm -rf "$classes" "$stamp"
  mkdir -p "$classes"
  "$JAVA_HOME/bin/javac" --release 21 -nowarn -cp "$classpath" -d "$classes" "$src" \
    || broken "javac failed on $src (see above)"
  snapshot > "$stamp"
fi

# The pin, read out of the pom rather than duplicated here, and handed to the
# driver ONLY so it can compare it with the version it observed off the classpath.
pinned="$(sed -n 's/.*<dmncheck\.version>\(.*\)<\/dmncheck\.version>.*/\1/p' "$here/pom.xml" | head -1)"
[ -n "$pinned" ] || broken "no <dmncheck.version> in $here/pom.xml"

jcmd=("$JAVA_HOME/bin/java" -Dorg.slf4j.simpleLogger.defaultLogLevel=off
  -Dl4.dmncheck.version.expected="$pinned" -cp "$classes:$classpath" DmnCheckRun)
run_driver() { "${jcmd[@]}" "$@"; }

if [ "$corpus" = 0 ]; then
  exec "${jcmd[@]}" ${passthru[@]+"${passthru[@]}"} "${roots[@]}"
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
echo
"$here/summarise.sh" "$work" || true
echo "# full report: $work/report.txt   findings: $work/findings.tsv   exports: $work/export-status.tsv"
exit "$rc"
