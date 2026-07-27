#!/usr/bin/env bash
#
# Drive an emitted DMN 1.3 file through Drools/KIE 8.44.0.Final: XSD (Xerces) +
# the KIE validator + KieBuilder + runtime evaluation. See
# src/main/java/KieDmnCheck.java for why all four legs are needed.
#
#   etc/kie-dmn-check/run.sh jl4/examples/dmn/expected/reg-cf.dmn \
#     --ctx jl4/examples/dmn/reg-cf.ctx.json
#
# ZERO-INSTALL, like etc/validate-dmn.mjs. Nothing is written into the repo and
# nothing is added to package.json or the lockfile: Maven resolves the classpath
# into $TMPDIR on first use and caches it there.
#
# SKIPS LOUDLY. With no JDK or no Maven it prints "SKIP  KIE DMN check: <reason>"
# on stderr and exits 0, because a developer laptop without a Java toolchain
# should not be told its L4 changes are broken. It prints no VERDICT banner when
# it skips, and jl4/tests-cli asserts on the BANNER rather than on the exit code,
# so a skip can never be mistaken for a pass.
#
# IN CI IT MUST NOT SKIP. Set KIE_CHECK_REQUIRED=1 and every skip path above
# becomes exit 1. That is the whole answer to "what if the checker is
# unavailable in CI": in CI, unavailable is a failure.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

skip() {
  echo "SKIP  KIE DMN check: $1" >&2
  if [ "${KIE_CHECK_REQUIRED:-0}" = "1" ]; then
    echo "      KIE_CHECK_REQUIRED=1 is set, so an unavailable checker is a failure." >&2
    exit 1
  fi
  exit 0
}

command -v mvn >/dev/null 2>&1 || skip "mvn not on PATH (brew install maven)"

# KIE/Drools 8.x wants Java 11+ and is unhappy on the very newest JDKs; 17 is
# what the measurements in the DMN spec were taken on. Homebrew's bare `java` is
# 26 and the macOS system one can be ancient, so look for 17 explicitly.
if [ -z "${KIE_CHECK_JAVA_HOME:-}" ]; then
  for candidate in \
      /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
      /usr/lib/jvm/java-17-openjdk-amd64 \
      /usr/lib/jvm/java-17-openjdk \
      "$(/usr/libexec/java_home -v 17 2>/dev/null || true)"; do
    [ -n "$candidate" ] && [ -x "$candidate/bin/java" ] && { KIE_CHECK_JAVA_HOME="$candidate"; break; }
  done
fi
[ -n "${KIE_CHECK_JAVA_HOME:-}" ] && [ -x "$KIE_CHECK_JAVA_HOME/bin/java" ] \
  || skip "no JDK 17 found (set KIE_CHECK_JAVA_HOME)"
export JAVA_HOME="$KIE_CHECK_JAVA_HOME"

# Build products stay OUT of the repo.
out="${KIE_CHECK_WORKDIR:-${TMPDIR:-/tmp}/l4-kie-dmn-check}"
mkdir -p "$out"
cp="$out/cp.txt"
if [ ! -s "$cp" ]; then
  echo "# resolving KIE 8.44.0.Final into $out (first run only)" >&2
  mvn -q -B -f "$here/pom.xml" -Dmdep.outputFile="$cp" dependency:build-classpath >&2 \
    || skip "could not resolve KIE 8.44.0.Final from Maven (offline?)"
fi
[ -s "$cp" ] || skip "empty classpath after dependency:build-classpath"

src="$here/src/main/java/KieDmnCheck.java"
if [ ! -s "$out/classes/KieDmnCheck.class" ] || [ "$src" -nt "$out/classes/KieDmnCheck.class" ]; then
  mkdir -p "$out/classes"
  "$JAVA_HOME/bin/javac" -nowarn --release 11 -cp "$(cat "$cp")" -d "$out/classes" "$src" \
    || skip "javac failed (see above)"
fi

exec "$JAVA_HOME/bin/java" -Dorg.slf4j.simpleLogger.defaultLogLevel=off \
  -cp "$out/classes:$(cat "$cp")" KieDmnCheck "$@"
