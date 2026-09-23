#!/usr/bin/env bash
#
# Drive an emitted DMN 1.3 file through Camunda 8 (io.camunda:zeebe-dmn 8.7.6,
# i.e. dmn-scala + org.camunda.feel:feel-engine): parse + isValid, then evaluate
# every decision. See src/main/java/CamundaDmnCheck.java.
#
#   etc/camunda-dmn-check/run.sh jl4/examples/dmn/expected/reg-cf.dmn \
#     --cases jl4/examples/dmn/reg-cf.cases.json
#
# NOT CAMUNDA 7 (see pom.xml), and deliberately NOT sharing a classpath with
# etc/kie-dmn-check: the two feel-engine builds collide.
#
# WHAT THIS DOES NOT COVER, so that nobody reads a green run as more than it is:
#   * deployment-time validation. zeebe-dmn is the code Camunda 8 uses to
#     EVALUATE; a real deployment additionally runs DmnResourceTransformer's
#     id/DRG constraints, which would need a broker.
#   * Camunda Modeler desktop import, which is K4's human check and is
#     deliberately not scriptable.
#
# ZERO-INSTALL, like etc/validate-dmn.mjs: Maven resolves the classpath into
# $TMPDIR, nothing is written into the repo, and package.json and the lockfile
# are untouched.
#
# SKIPS LOUDLY, and prints no VERDICT banner when it does; jl4/tests-cli asserts
# on the banner, so a skip can never be mistaken for a pass. Set
# CAMUNDA_CHECK_REQUIRED=1 (as CI does) to turn every skip path into exit 1.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ZEEBE_VERSION=8.7.6

skip() {
  echo "SKIP  Camunda DMN check: $1" >&2
  if [ "${CAMUNDA_CHECK_REQUIRED:-0}" = "1" ]; then
    echo "      CAMUNDA_CHECK_REQUIRED=1 is set, so an unavailable checker is a failure." >&2
    exit 1
  fi
  exit 0
}

# NOT a skip: see the identical note in etc/kie-dmn-check/run.sh. A harness that
# does not compile is a repo defect and fails on every machine.
broken() {
  echo "BROKEN  Camunda DMN check: $1" >&2
  echo "        This is a defect in the repo, not a missing toolchain; it fails everywhere." >&2
  exit 1
}

command -v mvn >/dev/null 2>&1 || skip "mvn not on PATH (brew install maven)"

# zeebe-dmn 8.7.x is compiled to class file 65, i.e. Java 21. Anything older
# dies with UnsupportedClassVersionError, so take the newest JDK we can find and
# insist it is at least 21.
if [ -z "${CAMUNDA_CHECK_JAVA_HOME:-}" ]; then
  for candidate in \
      /opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home \
      /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
      /usr/lib/jvm/java-21-openjdk-amd64 \
      /usr/lib/jvm/java-21-openjdk \
      "$(/usr/libexec/java_home -v 21+ 2>/dev/null || true)"; do
    [ -n "$candidate" ] && [ -x "$candidate/bin/java" ] && { CAMUNDA_CHECK_JAVA_HOME="$candidate"; break; }
  done
fi
[ -n "${CAMUNDA_CHECK_JAVA_HOME:-}" ] && [ -x "$CAMUNDA_CHECK_JAVA_HOME/bin/java" ] \
  || skip "no JDK 21+ found (set CAMUNDA_CHECK_JAVA_HOME); zeebe-dmn needs class file 65"
export JAVA_HOME="$CAMUNDA_CHECK_JAVA_HOME"

major="$("$JAVA_HOME/bin/java" -XshowSettings:properties -version 2>&1 \
  | sed -n 's/.*java\.specification\.version = \([0-9][0-9]*\).*/\1/p' | head -1)"
[ -n "$major" ] && [ "$major" -ge 21 ] \
  || skip "JAVA_HOME is Java ${major:-?}; zeebe-dmn $ZEEBE_VERSION needs 21+"

out="${CAMUNDA_CHECK_WORKDIR:-${TMPDIR:-/tmp}/l4-camunda-dmn-check}"
mkdir -p "$out"
cp="$out/cp.txt"
if [ ! -s "$cp" ]; then
  echo "# resolving io.camunda:zeebe-dmn $ZEEBE_VERSION into $out (first run only)" >&2
  mvn -q -B -f "$here/pom.xml" -Dmdep.outputFile="$cp" dependency:build-classpath >&2 \
    || skip "could not resolve zeebe-dmn $ZEEBE_VERSION from Maven (offline?)"
fi
[ -s "$cp" ] || skip "empty classpath after dependency:build-classpath"

src="$here/src/main/java/CamundaDmnCheck.java"
if [ ! -s "$out/classes/CamundaDmnCheck.class" ] || [ "$src" -nt "$out/classes/CamundaDmnCheck.class" ]; then
  mkdir -p "$out/classes"
  "$JAVA_HOME/bin/javac" -nowarn -cp "$(cat "$cp")" -d "$out/classes" "$src" \
    || broken "javac failed on $src (see above)"
fi

# The pin, read out of the pom rather than duplicated in this script, and handed
# to the checker ONLY so it can compare it against the version it observed off
# the classpath. The banner prints the observed one. Review caught the earlier
# arrangement, in which the banner printed this constant and no engine ever
# produced the number in it.
pinned="$(sed -n 's/.*<zeebe\.version>\(.*\)<\/zeebe\.version>.*/\1/p' "$here/pom.xml" | head -1)"
[ "$pinned" = "$ZEEBE_VERSION" ] \
  || broken "pom.xml pins $pinned but run.sh says $ZEEBE_VERSION; reconcile them"

exec "$JAVA_HOME/bin/java" -Dorg.slf4j.simpleLogger.defaultLogLevel=off \
  -Dl4.camunda.version.expected="$pinned" \
  -cp "$out/classes:$(cat "$cp")" CamundaDmnCheck "$@"
