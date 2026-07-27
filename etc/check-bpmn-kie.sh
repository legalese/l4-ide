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
#
# 3 is deliberately NON-ZERO. A caller that cannot tell "skipped" from "passed"
# is the exact failure this whole exercise exists to avoid, so a fresh CI
# machine without a JDK gets a loud, visible, non-zero skip rather than a green
# tick. A caller that genuinely wants to tolerate an absent toolchain must say
# so with --allow-skip, which still prints the banner but exits 0.

set -u

ALLOW_SKIP=0
FILES=()
for a in "$@"; do
  case "$a" in
    --allow-skip) ALLOW_SKIP=1 ;;
    -*) ;;
    *) FILES+=("$a") ;;
  esac
done

skip() {
  echo ""
  echo "=================================================================="
  echo " SKIPPED — jBPM/KIE check DID NOT RUN. Nothing above was verified."
  echo "=================================================================="
  echo " reason: $1"
  echo ""
  echo " To run it:"
  echo "   brew install maven openjdk@17"
  echo "   JAVA_HOME=\$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home \\"
  echo "     etc/check-bpmn-kie.sh jl4/examples/bpmn/expected/*.bpmn"
  echo ""
  echo " The two checks that do NOT need a JVM, and should be run instead:"
  echo "   node etc/check-bpmn-soundness.mjs jl4/examples/bpmn/expected/*.bpmn"
  echo "   npx --yes --package=bpmn-moddle@10 node etc/validate-bpmn.mjs jl4/examples/bpmn/expected/*.bpmn"
  echo ""
  if [ "$ALLOW_SKIP" -eq 1 ]; then
    echo " (--allow-skip was given, so exiting 0 — but NOTHING WAS CHECKED.)"
    exit 0
  fi
  exit 3
}

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "usage: etc/check-bpmn-kie.sh FILE.bpmn [FILE.bpmn ...] [--allow-skip]" >&2
  exit 2
fi
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "no such file: $f" >&2; exit 2; }
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- locate a JDK 11+ (needs javac, not just java) --------------------------
find_jdk() {
  local cands=()
  [ -n "${JAVA_HOME:-}" ] && cands+=("$JAVA_HOME")
  if command -v /usr/libexec/java_home >/dev/null 2>&1; then
    local h; h="$(/usr/libexec/java_home -v 11+ 2>/dev/null)" && [ -n "$h" ] && cands+=("$h")
  fi
  if command -v brew >/dev/null 2>&1; then
    local p; p="$(brew --prefix 2>/dev/null)"
    cands+=("$p/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" "$p/opt/openjdk/libexec/openjdk.jdk/Contents/Home")
  fi
  for c in "${cands[@]}"; do
    if [ -x "$c/bin/javac" ]; then
      local v; v="$("$c/bin/javac" -version 2>&1 | sed -E 's/javac ([0-9]+).*/\1/')"
      if [ "${v:-0}" -ge 11 ] 2>/dev/null; then echo "$c"; return 0; fi
    fi
  done
  # last resort: javac on PATH
  if command -v javac >/dev/null 2>&1; then
    local v; v="$(javac -version 2>&1 | sed -E 's/javac ([0-9]+).*/\1/')"
    if [ "${v:-0}" -ge 11 ] 2>/dev/null; then dirname "$(dirname "$(command -v javac)")"; return 0; fi
  fi
  return 1
}

command -v mvn >/dev/null 2>&1 || skip "\`mvn\` is not on PATH (needed to resolve the pinned jBPM jars)"
JDK="$(find_jdk)" || skip "no JDK 11 or newer found (needs javac, not just a java runtime)"

CACHE="${L4_KIE_CACHE:-${TMPDIR:-/tmp}/l4-kie-bpmn-check}"
mkdir -p "$CACHE" || skip "cannot create the cache directory $CACHE"

# --- resolve the classpath (cached) -----------------------------------------
CP_FILE="$CACHE/cp.txt"
if [ ! -s "$CP_FILE" ] || [ "$HERE/kie/pom.xml" -nt "$CP_FILE" ]; then
  echo "resolving pinned jBPM dependencies into $CACHE (first run downloads ~44 MB)..."
  if ! mvn -q -B -f "$HERE/kie/pom.xml" \
        -Dmaven.repo.local="$CACHE/repo" \
        -Dmdep.outputFile="$CP_FILE" -DincludeScope=runtime \
        dependency:build-classpath >"$CACHE/mvn.log" 2>&1; then
    echo "--- last 25 lines of $CACHE/mvn.log ---" >&2
    tail -25 "$CACHE/mvn.log" >&2
    skip "maven failed to resolve the pinned dependencies (see the log above: commonly offline, a proxy blocking Maven Central, or an unreadable pom)"
  fi
fi
[ -s "$CP_FILE" ] || skip "the resolved classpath came back empty"

# --- compile the checker (cached) -------------------------------------------
CLASSES="$CACHE/classes"
if [ ! -f "$CLASSES/KieBpmnCheck.class" ] || [ "$HERE/kie/KieBpmnCheck.java" -nt "$CLASSES/KieBpmnCheck.class" ]; then
  mkdir -p "$CLASSES"
  if ! "$JDK/bin/javac" -nowarn -cp "$(cat "$CP_FILE")" -d "$CLASSES" \
        "$HERE/kie/KieBpmnCheck.java" 2>"$CACHE/javac.log"; then
    cat "$CACHE/javac.log" >&2
    skip "the checker did not compile (see $CACHE/javac.log)"
  fi
fi

# --- run --------------------------------------------------------------------
# Drools logs XSD chatter to stderr that is noise here; findings all go to stdout.
"$JDK/bin/java" -Dorg.slf4j.simpleLogger.defaultLogLevel=off \
  -cp "$CLASSES:$(cat "$CP_FILE")" KieBpmnCheck "${FILES[@]}" 2>/dev/null
exit $?
