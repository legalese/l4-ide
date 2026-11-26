#!/usr/bin/env bash
#
# Selftest for etc/mvn-retry.sh and for what the three harnesses that source it
# do when Maven cannot resolve. OFFLINE and fast (about 25 s): it puts a stub
# `mvn` first on PATH and fake JDKs in front of the harnesses, so it needs no
# network, no real JDK and no Maven.
#
#   etc/mvn-retry.selftest.sh
#
# It asserts the two properties the retry exists to keep, and which no real
# Maven run can show you on demand:
#   * a transient failure (fails once, or hangs once) is retried and PASSES;
#   * a failure that persists is NEVER turned into a pass: the helper returns
#     non-zero, the DMN harnesses SKIP (exit 1 when *_CHECK_REQUIRED=1, which is
#     how CI runs them) and the BPMN harness exits 4.
#
# Exit 0 if every case held, 1 otherwise.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/l4-mvn-retry-selftest.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
fails=0

check() { # NAME EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then
    echo "ok    $1"
  else
    echo "FAIL  $1 (expected '$2', got '$3')"
    fails=$((fails + 1))
  fi
}
contains() { # NAME TEXT NEEDLE
  case "$2" in
    *"$3"*) echo "ok    $1" ;;
    *) echo "FAIL  $1 (no '$3' in: $2)"; fails=$((fails + 1)) ;;
  esac
}

# The stub. STUB_MODE picks its behaviour; STUB_COUNT counts its calls; the hang
# modes append the pids they started to STUB_PIDS, so the helper can be checked
# for leaving none behind. On success it writes the classpath file the caller
# asked for, as the real dependency:build-classpath does.
#   hang           the stub IS the sleeping process (exec), the easy case.
#   hang-child     the stub runs `sleep` as a CHILD, as the mvn wrapper script
#                  does with java. Killing the stub's pid orphans the sleep, so
#                  only the helper's `pkill -P` reaches it.
#   hang-stubborn  as hang-child, but TERM is ignored (and inherited by the
#                  child), so only the KILL escalation ends it.
#   hang-exit0     as hang-child, but it exits 0 when it is TERMed. A wrapper
#                  script does this when the sleeping child it waits for is
#                  killed first. The attempt was killed, so it must NOT count as
#                  a success: only the timeout flag says so.
cat >"$work/bin/mvn" <<'EOF'
#!/usr/bin/env bash
n=$(cat "$STUB_COUNT" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$STUB_COUNT"
fail() { echo "[ERROR] stub: central unreachable" >&2; exit 1; }
case "$STUB_MODE" in
  fail) fail ;;
  fail-once) [ "$n" -eq 1 ] && fail ;;
  hang) echo "$$" >>"$STUB_PIDS"; exec sleep 600 ;;
  hang-once) [ "$n" -eq 1 ] && { echo "$$" >>"$STUB_PIDS"; exec sleep 600; } ;;
  hang-child) sleep 600 & echo "$$ $!" >>"$STUB_PIDS"; wait ;;
  hang-stubborn) trap '' TERM; sleep 600 & echo "$$ $!" >>"$STUB_PIDS"; wait ;;
  hang-exit0) trap 'exit 0' TERM; sleep 600 & echo "$$ $!" >>"$STUB_PIDS"; wait ;;
esac
for a in "$@"; do
  case "$a" in -Dmdep.outputFile=*) echo "/stub.jar" >"${a#-Dmdep.outputFile=}" ;; esac
done
exit 0
EOF
chmod +x "$work/bin/mvn"

# A fake JDK: only what the harnesses probe before they reach Maven.
mkjdk() { # DIR MAJOR
  mkdir -p "$1/bin"
  printf '#!/bin/sh\necho "    java.specification.version = %s" >&2\n' "$2" >"$1/bin/java"
  printf '#!/bin/sh\necho "javac %s.0.1"\n' "$2" >"$1/bin/javac"
  chmod +x "$1/bin/java" "$1/bin/javac"
}
mkjdk "$work/jdk17" 17
mkjdk "$work/jdk21" 21

# ---- the helper -------------------------------------------------------------
# The per-attempt timeout is long where nothing is meant to hang, so that a loaded
# CI runner starting a bash stub slowly cannot fail a case; it is short only
# where the case IS the timeout.
helper() { # MODE [TIMEOUT-SECONDS, default 30] [ATTEMPTS, default 3] -> RC, CALLS, ERR
  rm -f "$work/count" "$work/pids"
  ERR="$(STUB_MODE="$1" STUB_COUNT="$work/count" STUB_PIDS="$work/pids" \
    L4_MVN_ATTEMPT_TIMEOUT="${2:-30}" L4_MVN_ATTEMPTS="${3:-3}" L4_MVN_BACKOFFS="0 0" \
    bash -c '. "$1"; mvn_retry stub "$2" "$3" -q' _ "$here/mvn-retry.sh" "$work/log" "$work/bin/mvn" 2>&1 >/dev/null)"
  RC=$?
  CALLS="$(cat "$work/count" 2>/dev/null || echo 0)"
}

# How many of the processes the hang stubs started are still alive, after giving
# the kernel up to 2 s to reap them. Any that survive are killed, so a failing
# run leaves nothing behind.
leaked() {
  local n=0 p i
  for p in $(cat "$work/pids" 2>/dev/null); do
    i=0
    while kill -0 "$p" 2>/dev/null && [ "$i" -lt 20 ]; do
      sleep 0.1
      i=$((i + 1))
    done
    if kill -0 "$p" 2>/dev/null; then
      n=$((n + 1))
      kill -KILL "$p" 2>/dev/null
    fi
  done
  echo "$n"
}

helper ok
check "helper, resolves first time: exit 0" 0 "$RC"
check "helper, resolves first time: one call" 1 "$CALLS"

helper fail-once
check "helper, fails once: retried and passes" 0 "$RC"
check "helper, fails once: two calls" 2 "$CALLS"
contains "helper, fails once: says which attempt failed" "$ERR" "attempt 1/3 failed (exit 1)"
contains "helper, fails once: shows Maven's output" "$ERR" "stub: central unreachable"

helper hang-once 3
check "helper, hangs once: killed, retried and passes" 0 "$RC"
check "helper, hangs once: two calls" 2 "$CALLS"
contains "helper, hangs once: says it timed out" "$ERR" "attempt 1/3 failed (timed out after 3s)"

helper fail
check "helper, always fails: NOT a pass" 1 "$RC"
check "helper, always fails: three calls, no more" 3 "$CALLS"
contains "helper, always fails: gives up loudly" "$ERR" "giving up after 3 attempts"

helper hang 3
check "helper, always hangs: NOT a pass (124)" 124 "$RC"
check "helper, always hangs: three calls" 3 "$CALLS"
check "helper, always hangs: no stub process left running" 0 "$(leaked)"

helper hang-child 2 1
check "helper, hung child process: NOT a pass (124)" 124 "$RC"
check "helper, hung child process: one call" 1 "$CALLS"
check "helper, hung child process: the orphaned sleep is killed too" 0 "$(leaked)"

helper hang-stubborn 1 1
check "helper, process that ignores TERM: NOT a pass (124)" 124 "$RC"
contains "helper, process that ignores TERM: says it timed out" "$ERR" "attempt 1/1 failed (timed out after 1s)"
check "helper, process that ignores TERM: KILLed, nothing left running" 0 "$(leaked)"

helper hang-exit0 2 1
check "helper, process that exits 0 once TERMed: NOT a pass (124)" 124 "$RC"
contains "helper, process that exits 0 once TERMed: says it timed out" "$ERR" "attempt 1/1 failed (timed out after 2s)"
check "helper, process that exits 0 once TERMed: nothing left running" 0 "$(leaked)"

# ---- the harnesses: a persistent failure keeps its old meaning --------------
# Both DMN harnesses SKIP on a resolution failure, and that SKIP is exit 1 under
# *_CHECK_REQUIRED=1. The BPMN harness exits 4.
harness() { # MODE REQUIRED(0|1) SCRIPT...: RC, OUT, ERR
  rm -rf "$work/w" "$work/count"
  mkdir -p "$work/w"
  OUT="$work/w.out"
  ERR="$(STUB_MODE="$1" STUB_COUNT="$work/count" L4_MVN_ATTEMPT_TIMEOUT=30 L4_MVN_BACKOFFS="0 0" \
    PATH="$work/bin:$PATH" KIE_CHECK_REQUIRED="$2" CAMUNDA_CHECK_REQUIRED="$2" \
    KIE_CHECK_JAVA_HOME="$work/jdk17" CAMUNDA_CHECK_JAVA_HOME="$work/jdk21" \
    KIE_CHECK_WORKDIR="$work/w" CAMUNDA_CHECK_WORKDIR="$work/w" \
    JAVA_HOME="$work/jdk17" L4_KIE_CACHE="$work/w" \
    "${@:3}" 2>&1 >"$OUT")"
  RC=$?
}
: >"$work/x.dmn"
: >"$work/x.bpmn"

harness fail 1 "$repo/etc/kie-dmn-check/run.sh" "$work/x.dmn"
check "KIE, Maven always fails, REQUIRED=1: exit 1" 1 "$RC"
contains "KIE, REQUIRED=1: still says SKIP, then why it fails" "$ERR" "KIE_CHECK_REQUIRED=1 is set"
check "KIE, REQUIRED=1: no VERDICT banner" 0 "$(grep -c VERDICT "$OUT")"
harness fail 0 "$repo/etc/kie-dmn-check/run.sh" "$work/x.dmn"
check "KIE, Maven always fails, REQUIRED unset: SKIP exit 0" 0 "$RC"
contains "KIE, REQUIRED unset: SKIP is on stderr" "$ERR" "SKIP  KIE DMN check: could not resolve KIE 8.44.0.Final"
harness fail-once 1 "$repo/etc/kie-dmn-check/run.sh" "$work/x.dmn"
check "KIE, Maven fails once, REQUIRED=1: proceeds past resolution" 0 "$RC"
check "KIE, fails once: the classpath was written by the second call" "/stub.jar" "$(cat "$work/w/cp.txt" 2>/dev/null)"

harness fail 1 "$repo/etc/camunda-dmn-check/run.sh" "$work/x.dmn"
check "Camunda, Maven always fails, REQUIRED=1: exit 1" 1 "$RC"
contains "Camunda, REQUIRED=1: names the cause" "$ERR" "CAMUNDA_CHECK_REQUIRED=1 is set"
harness fail 0 "$repo/etc/camunda-dmn-check/run.sh" "$work/x.dmn"
check "Camunda, Maven always fails, REQUIRED unset: SKIP exit 0" 0 "$RC"
harness fail-once 1 "$repo/etc/camunda-dmn-check/run.sh" "$work/x.dmn"
check "Camunda, Maven fails once, REQUIRED=1: proceeds past resolution" 0 "$RC"
check "Camunda, fails once: the classpath was written by the second call" "/stub.jar" "$(cat "$work/w/cp.txt" 2>/dev/null)"

harness fail 0 "$repo/etc/check-bpmn-kie.sh" "$work/x.bpmn"
check "BPMN, Maven always fails: exit 4 (BROKEN)" 4 "$RC"
contains "BPMN: gave up after the retries" "$ERR" "giving up after 3 attempts"

if [ "$fails" -eq 0 ]; then
  echo "mvn-retry selftest: all cases held."
  exit 0
fi
echo "mvn-retry selftest: $fails case(s) FAILED."
exit 1
