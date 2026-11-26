# shellcheck shell=bash
#
# mvn_retry: run a Maven classpath resolution with retries and a hard
# per-attempt timeout. SOURCE this file; it defines one function and runs nothing.
#
#   . "$here/../mvn-retry.sh"
#   mvn_retry "KIE 8.44.0.Final" "$out/mvn.log" \
#     mvn -q -B -f "$here/pom.xml" -Dmdep.outputFile="$cp" dependency:build-classpath \
#     || skip "could not resolve KIE 8.44.0.Final from Maven (offline?)"
#
# Used by etc/kie-dmn-check/run.sh, etc/camunda-dmn-check/run.sh and
# etc/check-bpmn-kie.sh, the three scripts that resolve an engine from Maven
# Central.
#
# WHY IT EXISTS. A merge_group run never finds the Maven cache (the entry lives
# on refs/heads/unstable; see the comment at the "Restore the Maven repository"
# step in .github/workflows/pr-checks.yml), so every merge group resolves its
# engines from Central. On 2026-11-26 one such resolve failed after 6.5 minutes
# with "No plugin found for prefix 'dependency' ... central", the harness
# SKIPped, KIE_CHECK_REQUIRED=1 turned the skip into exit 1, and a PR that
# changed nothing in the engines was ejected from the merge queue.
#
# WHAT IT DOES. Up to L4_MVN_ATTEMPTS attempts (default 3). Each attempt has a
# hard timeout, L4_MVN_ATTEMPT_TIMEOUT seconds (default 180; a normal cold
# resolve takes about 18 s, so a hung Central costs one timeout and not the
# job). Between attempts it sleeps for the next number in L4_MVN_BACKOFFS
# (default "10 30"; the last number is reused if there are more retries than
# numbers). Every failed attempt prints one line on stderr naming the attempt
# and why, then the last lines of Maven's output.
#
# HOW IT FAILS, sorted by whether it announces itself.
#   LOUD:   every attempt failing. The function returns non-zero (124 if the
#           last attempt timed out, else Maven's own exit code), and the CALLER
#           decides what that means. For the three harnesses that is exactly
#           what it meant before this file existed: the DMN harnesses SKIP (an
#           exit 1 under KIE_CHECK_REQUIRED=1 / CAMUNDA_CHECK_REQUIRED=1, which
#           CI sets) and check-bpmn-kie.sh exits 4. A retry never turns a
#           failure into a pass.
#   LOUD:   a bad pom or a mistyped coordinate. It fails the same way on every
#           attempt, so it costs the backoff time (about 40 s) before failing.
#           Telling a permanent error from a transient one by reading Maven's
#           text would be a guess, so nothing tries.
#   SILENT: none of its own. A run that needed a retry is a pass, and the only
#           trace is the "attempt 1/3 failed" lines above a normal result, so a
#           flaky Central shows up in the log and never in the verdict.
#
# Portable on purpose: bash 3.2 (the stock macOS /bin/bash) and no GNU
# `timeout`, which macOS does not ship. The timeout is a watchdog subshell that
# polls once a second and is woken as soon as Maven finishes, so it never leaves
# a `sleep` behind.

# _l4_mvn_run_timed SECS FLAGFILE CMD...: run CMD, and TERM it (then KILL it up
# to 5 s later) if it is still running after SECS seconds. Creates FLAGFILE if it
# had to. Returns CMD's exit status.
_l4_mvn_run_timed() {
  local secs="$1" flag="$2"
  shift 2
  "$@" &
  local pid=$!
  (
    local i=0
    while [ "$i" -lt "$secs" ]; do
      sleep 1
      kill -0 "$pid" 2>/dev/null || exit 0
      i=$((i + 1))
    done
    : >"$flag"
    pkill -TERM -P "$pid" 2>/dev/null || true
    kill -TERM "$pid" 2>/dev/null || true
    i=0
    while [ "$i" -lt 5 ]; do
      sleep 1
      kill -0 "$pid" 2>/dev/null || exit 0
      i=$((i + 1))
    done
    pkill -KILL -P "$pid" 2>/dev/null || true
    kill -KILL "$pid" 2>/dev/null || true
  ) >/dev/null 2>&1 &
  local wd=$!
  local rc=0
  wait "$pid" || rc=$?
  # Wake the watchdog out of its `sleep 1`: it then finds CMD gone and exits.
  pkill -TERM -P "$wd" 2>/dev/null || true
  wait "$wd" 2>/dev/null || true
  return "$rc"
}

# _l4_mvn_nth_word N WORD...: the Nth word, or the last one if there are fewer.
_l4_mvn_nth_word() {
  local n="$1" w="" i=0
  shift
  for w in "$@"; do
    i=$((i + 1))
    [ "$i" -ge "$n" ] && break
  done
  echo "$w"
}

# mvn_retry LABEL LOGFILE CMD...
#   LABEL    what is being resolved, for the messages ("KIE 8.44.0.Final")
#   LOGFILE  where Maven's output goes; the last attempt's output is left there
#   CMD...   the whole command, starting with `mvn`
mvn_retry() {
  local label="$1" log="$2"
  shift 2
  local attempts="${L4_MVN_ATTEMPTS:-3}"
  local tmo="${L4_MVN_ATTEMPT_TIMEOUT:-180}"
  local backoffs="${L4_MVN_BACKOFFS:-10 30}"
  case "$attempts" in '' | *[!0-9]* | 0) attempts=3 ;; esac
  case "$tmo" in '' | *[!0-9]* | 0) tmo=180 ;; esac

  local n=1 rc flag why delay
  while :; do
    rc=0
    flag="$log.timedout"
    rm -f "$flag"
    : >"$log"
    _l4_mvn_run_timed "$tmo" "$flag" "$@" >"$log" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ] && [ ! -e "$flag" ]; then
      # Maven's own output, as before: -q keeps it to warnings and errors.
      [ -s "$log" ] && cat "$log" >&2
      rm -f "$flag"
      return 0
    fi
    if [ -e "$flag" ]; then
      rc=124
      why="timed out after ${tmo}s"
    else
      why="exit $rc"
    fi
    rm -f "$flag"
    echo "# $label: Maven resolution attempt $n/$attempts failed ($why). Last lines of its output:" >&2
    tail -n 15 "$log" | sed 's/^/#   /' >&2
    if [ "$n" -ge "$attempts" ]; then
      echo "# $label: giving up after $attempts attempts." >&2
      return "$rc"
    fi
    # `$backoffs` is deliberately unquoted: it is a list of words.
    # shellcheck disable=SC2086
    delay="$(_l4_mvn_nth_word "$n" $backoffs)"
    case "$delay" in '' | *[!0-9]*) delay=0 ;; esac
    echo "# $label: retrying in ${delay}s." >&2
    sleep "$delay"
    n=$((n + 1))
  done
}
