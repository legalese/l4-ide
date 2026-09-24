#!/usr/bin/env bash
# Run the jBPM/KIE second opinion over emitted BPMN.
#
# This is the third and least portable of three BPMN checks, and it is the one
# that is NOT a gate. The other two come first:
#
#   etc/validate-bpmn.mjs          will Camunda Modeler open this?   (K4)
#   etc/check-bpmn-soundness.mjs   can the token game get stuck?     (the gate)
#   etc/check-bpmn-kie.sh          does an INDEPENDENT ENGINE agree? (this)
#
# The first two are ours. This one runs somebody else's implementation, so when
# it agrees that a diagram deadlocks, that agreement is evidence our own token
# semantics are right — the two share no code. Its measured value, and its
# measured limits, are recorded in jl4/examples/bpmn/unsound/README.md. Read
# etc/kie/KieBpmnCheck.java's header for what it does and does not check; the
# short version is that it explores ONE execution path, so it can prove a
# deadlock exists but never prove one absent.
#
# ZERO INSTALL, but not zero cost: it needs `mvn` and a JDK 11+, and on a cold
# cache it downloads ~44 MB of pinned jars into a cache OUTSIDE the repository.
# Nothing is added to package.json or the lockfile; nothing lands in the tree.
#
#   etc/check-bpmn-kie.sh jl4/examples/bpmn/expected/*.bpmn
#
# Exit codes:
#   0  no findings
#   1  a finding (jBPM rejected a file, or found a deadlock or a duplication)
#   2  usage error
#   3  SKIPPED — the toolchain is absent and NOTHING WAS CHECKED
#   4  BROKEN — the toolchain is present but THIS HARNESS failed to run
#              (including: the JVM ran but printed no verdict)
#
# 3 is deliberately NON-ZERO. A caller that cannot tell "skipped" from "passed"
# is the exact failure this whole exercise exists to avoid, so a fresh CI
# machine without a JDK gets a loud, visible, non-zero skip rather than a green
# tick. A caller that genuinely wants to tolerate an absent toolchain must say
# so with --allow-skip, which still prints the banner but exits 0.
#
# 4 is separate from 3, and --allow-skip does NOT suppress it. "There is no JDK
# on this machine" and "our own checker no longer compiles" are different facts
# with different owners, and an adversarial review found them sharing exit 3 —
# so a typo in the pinned pom returned green under the exact flag CI would use.
# A broken harness is never tolerable; an absent one sometimes is.
#
# 4 is also NOT folded into 1. Exit 1 means "a BPMN file has a defect"; routing
# infrastructure failure there would report a JVM crash as a diagram bug.

set -u

ALLOW_SKIP=0
CENSUS=""
# bash 3.2 (the stock /bin/bash on macOS) treats "${arr[@]}" on an EMPTY array as
# an unbound variable under `set -u`, which would turn the documented "exit 2 =
# usage" into exit 1 = "a finding". Track the count separately rather than
# relying on ${#FILES[@]}.
FILES=()
NFILES=0
for a in "$@"; do
  case "$a" in
    --allow-skip) ALLOW_SKIP=1 ;;
    --census) CENSUS="--census" ;;
    -*) ;;
    *) FILES+=("$a"); NFILES=$((NFILES + 1)) ;;
  esac
done

banner() {
  echo ""
  echo "=================================================================="
  echo " $1"
  echo "=================================================================="
  echo " reason: $2"
  echo ""
}

hint() {
  echo " To run it:"
  echo "   brew install maven openjdk@17"
  echo "   JAVA_HOME=\$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home \\"
  echo "     etc/check-bpmn-kie.sh jl4/examples/bpmn/expected/*.bpmn"
  echo ""
  echo " The two checks that do NOT need a JVM, and should be run instead:"
  echo "   node etc/check-bpmn-soundness.mjs jl4/examples/bpmn/expected/*.bpmn"
  echo "   npx --yes --package=bpmn-moddle@10 node etc/validate-bpmn.mjs jl4/examples/bpmn/expected/*.bpmn"
  echo ""
}

# The toolchain is ABSENT. Tolerable with --allow-skip.
skip() {
  banner "SKIPPED — jBPM/KIE check DID NOT RUN. Nothing above was verified." "$1"
  hint
  if [ "$ALLOW_SKIP" -eq 1 ]; then
    echo " (--allow-skip was given, so exiting 0 — but NOTHING WAS CHECKED.)"
    exit 0
  fi
  exit 3
}

# THIS HARNESS is broken. Never tolerable, --allow-skip or not.
broken() {
  banner "BROKEN — the toolchain is present but this harness FAILED TO RUN." "$1"
  echo " This is not an absent toolchain and --allow-skip will not silence it:"
  echo " something in etc/kie/ needs fixing before the check means anything."
  echo ""
  exit 4
}

if [ "$NFILES" -eq 0 ]; then
  echo "usage: etc/check-bpmn-kie.sh FILE.bpmn [FILE.bpmn ...] [--allow-skip] [--census]" >&2
  exit 2
fi
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "no such file: $f" >&2; exit 2; }
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- locate a JDK (needs javac, not just java) ------------------------------
#
# There is a CEILING as well as a floor. jBPM 7.74.1 is a 2022 stack and does
# not run on an arbitrarily new JVM; Homebrew's default JAVA_HOME here is JDK 26,
# which the toolchain notes for this work call out as too new. So prefer a JDK in
# [11, MAX_JDK] and only fall back to something newer with a warning — rather
# than taking $JAVA_HOME on faith the way the first version did.
MIN_JDK=11
MAX_JDK=21

jdk_major() {
  [ -x "$1/bin/javac" ] || return 1
  "$1/bin/javac" -version 2>&1 | sed -E 's/javac ([0-9]+).*/\1/'
}

find_jdk() {
  # `local arr=()` + "${arr[@]}" is also unbound-variable-under-set-u on bash
  # 3.2, so accumulate newline-separated instead of using an array.
  cands=""
  [ -n "${JAVA_HOME:-}" ] && cands="$cands$JAVA_HOME
"
  # Deliberately BEFORE /usr/libexec/java_home. On a Mac with an old JDK still
  # installed, java_home -v 11+ happily returns something like 14.0.1, which is
  # in range and yet is nobody's intended toolchain; the explicitly versioned
  # brew casks are.
  if command -v brew >/dev/null 2>&1; then
    p="$(brew --prefix 2>/dev/null || true)"
    if [ -n "$p" ]; then
      cands="$cands$p/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
$p/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
$p/opt/openjdk/libexec/openjdk.jdk/Contents/Home
"
    fi
  fi
  if command -v /usr/libexec/java_home >/dev/null 2>&1; then
    h="$(/usr/libexec/java_home -v "$MIN_JDK+" 2>/dev/null || true)"
    [ -n "$h" ] && cands="$cands$h
"
  fi
  if command -v javac >/dev/null 2>&1; then
    cands="$cands$(dirname "$(dirname "$(command -v javac)")")
"
  fi

  # Pass 1: something in range. Pass 2: anything at or above the floor.
  fallback=""
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    v="$(jdk_major "$c" 2>/dev/null || true)"
    case "${v:-x}" in ''|*[!0-9]*) continue ;; esac
    [ "$v" -lt "$MIN_JDK" ] && continue
    if [ "$v" -le "$MAX_JDK" ]; then echo "$c"; return 0; fi
    [ -z "$fallback" ] && fallback="$c"
  done <<EOF
$cands
EOF
  if [ -n "$fallback" ]; then
    echo "warning: no JDK in [$MIN_JDK,$MAX_JDK]; using $fallback, which is newer than" >&2
    echo "         jBPM 7.74.1 was built for. A crash here is the toolchain, not the BPMN." >&2
    echo "$fallback"
    return 0
  fi
  return 1
}

command -v mvn >/dev/null 2>&1 || skip "\`mvn\` is not on PATH (needed to resolve the pinned jBPM jars)"
JDK="$(find_jdk)" || skip "no JDK $MIN_JDK or newer found (needs javac, not just a java runtime)"

CACHE="${L4_KIE_CACHE:-${TMPDIR:-/tmp}/l4-kie-bpmn-check}"
mkdir -p "$CACHE" || broken "cannot create the cache directory $CACHE"

# --- resolve the classpath (cached) -----------------------------------------
# The PLUGIN is pinned too, not just the dependencies. Invoking it by prefix
# (`dependency:build-classpath`) makes Maven resolve maven-dependency-plugin from
# maven-metadata.xml — whatever is newest the day you run — which is the same
# unpinned-runtime-download failure mode as a bare `npx`.
DEP_PLUGIN=org.apache.maven.plugins:maven-dependency-plugin:3.6.1
CP_FILE="$CACHE/cp.txt"
if [ ! -s "$CP_FILE" ] || [ "$HERE/kie/pom.xml" -nt "$CP_FILE" ]; then
  echo "resolving pinned jBPM dependencies into $CACHE (first run downloads ~44 MB)..."
  if ! mvn -q -B -f "$HERE/kie/pom.xml" \
        -Dmaven.repo.local="$CACHE/repo" \
        -Dmdep.outputFile="$CP_FILE" -DincludeScope=runtime \
        "$DEP_PLUGIN:build-classpath" >"$CACHE/mvn.log" 2>&1; then
    echo "--- last 25 lines of $CACHE/mvn.log ---" >&2
    tail -25 "$CACHE/mvn.log" >&2
    # Maven is installed but could not resolve: that is a broken harness or a
    # broken network, NOT an absent toolchain, so it must not exit 0 under
    # --allow-skip.
    broken "maven is installed but failed to resolve the pinned dependencies (see the log above: commonly offline, a proxy blocking Maven Central, or an unreadable pom)"
  fi
fi
[ -s "$CP_FILE" ] || broken "the resolved classpath came back empty"

# --- compile the checker (cached) -------------------------------------------
# Invalidated by the classpath as well as the source. Bumping the pinned jBPM
# version regenerates cp.txt but would otherwise leave stale .class files, and
# the resulting NoSuchMethodError surfaces as a per-file "finding" — a toolchain
# problem misreported as a defect in the BPMN.
#
# Keyed on the JDK MAJOR VERSION too. Classes compiled by JDK 17 and then run by
# an older JVM that happened to win JDK selection on the next invocation die with
# UnsupportedClassVersionError — which exits 1, the code that means "a BPMN file
# has a defect". Measured, not hypothetical: on this machine `java_home -v 11+`
# returns a stale 14.0.1.
JDK_MAJOR="$(jdk_major "$JDK" 2>/dev/null || echo unknown)"
CLASSES="$CACHE/classes-jdk$JDK_MAJOR"
STAMP="$CLASSES/KieBpmnCheck.class"
NEEDS_BUILD=0
[ -f "$STAMP" ] || NEEDS_BUILD=1
[ "$HERE/kie/KieBpmnCheck.java" -nt "$STAMP" ] && NEEDS_BUILD=1
[ "$CP_FILE" -nt "$STAMP" ] && NEEDS_BUILD=1
if [ "$NEEDS_BUILD" -eq 1 ]; then
  rm -rf "$CLASSES"
  mkdir -p "$CLASSES"
  if ! "$JDK/bin/javac" -nowarn -cp "$(cat "$CP_FILE")" -d "$CLASSES" \
        "$HERE/kie/KieBpmnCheck.java" 2>"$CACHE/javac.log"; then
    cat "$CACHE/javac.log" >&2
    broken "etc/kie/KieBpmnCheck.java did not compile (see $CACHE/javac.log)"
  fi
fi

# --- run --------------------------------------------------------------------
# Drools logs XSD chatter to stderr that is noise here; findings all go to
# stdout. It is CAPTURED rather than discarded: a JVM that OOMs or dies before
# main() would otherwise exit non-zero with no diagnostic at all, and exit 1
# means "a BPMN file has a defect".
#
# THE VERDICT IS THE SENTINEL, NOT THE EXIT CODE. KieBpmnCheck always prints a
# "RESULT:" line before exiting 0 or 1, so its absence means the JVM never got
# far enough to judge anything. Sniffing the exit code alone is not enough: an
# UnsupportedClassVersionError, an OOM and a missing main class all exit 1, which
# is the code that means "a BPMN file has a defect". Requiring the sentence to
# have been printed is what makes exit 1 trustworthy.
JAVA_ERR="$CACHE/java.err"
JAVA_OUT="$CACHE/java.out"
"$JDK/bin/java" -Dorg.slf4j.simpleLogger.defaultLogLevel=off \
  -cp "$CLASSES:$(cat "$CP_FILE")" KieBpmnCheck ${CENSUS:+$CENSUS} "${FILES[@]}" \
  >"$JAVA_OUT" 2>"$JAVA_ERR"
RC=$?
cat "$JAVA_OUT"
if [ "$RC" -eq 2 ]; then
  cat "$JAVA_ERR" >&2
  exit 2
fi
if ! grep -q '^RESULT:' "$JAVA_OUT"; then
  echo "--- last 25 lines of $JAVA_ERR ---" >&2
  tail -25 "$JAVA_ERR" >&2
  broken "the JVM exited $RC without printing a verdict (no RESULT: line). Whatever went wrong is in this harness or its toolchain — it is NOT a finding about a BPMN file."
fi
case "$RC" in
  0 | 1) exit "$RC" ;;
  *) broken "the checker printed a verdict but the JVM then exited $RC" ;;
esac
