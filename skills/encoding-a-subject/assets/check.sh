#!/usr/bin/env bash
# Run every .l4 module in an encoding and print, per module, the numbers that matter:
# error diagnostics, assertions satisfied, assertions failed, assertions refused.
#
# Why not trust the exit code: `l4 run` exits 0 when an #ASSERT refuses, an l4
# built before legalese/l4-ide#518 exits 0 when one fails too, and no exit code
# says which assertion failed or how many ran. An encoding that "ran green" by
# exit code can be carrying any of those.
#
# Why read the line AFTER "Message:": l4 prints some outcomes on the Message line
# itself ("Message:  assertion failed") and others on the next one:
#   * `#ASSERT REFUSED e` where e produces a value: "assertion failed: expected a
#     refusal, but the expression produced a value" (Error severity);
#   * `#ASSERT e` where e REFUSES: "assertion refused: ..." (Warning severity, so it
#     never shows up as an error at all).
# A script that greps the Message line alone undercounts the first and never sees the
# second; a refusing assertion then looks green.
#
# The target check. An encoding is written for a TARGET compiler, `main` or `unstable`, and the
# target comes from the brief, not from the binary you happen to run. `main` rejects, or reads
# differently, much of what `unstable` accepts (references/dialects.md in the writing-l4-rules
# skill), and the only mechanical way to know is to run a main build over the module too. With the
# target `main` (the default) this script runs every module with BOTH binaries and compares the four
# counts. A module whose counts differ, or that errors on main, is red, its line says "reads
# differently on main", and the next line shows the first error main gives.
#
# WHAT IT DOES NOT SEE. It counts error diagnostics and assertion lines, and nothing else. So it
# catches a module main rejects, and a difference that changes an #ASSERT's outcome. It does NOT
# see a different #TRACE outcome: a trace prints FULFILLED or BREACH or a residual obligation, never
# an assertion line, so no count moves. Several differences between main and unstable live there
# (dialects.md marks them "degrades": an input named in a MUST action matches any payload on main,
# a MAY with a LEST lapses to BREACH on unstable and to FULFILLED on main). A trace is compared by
# running it with both builds and reading the two outcomes; this script will not tell you.
#
# TWO RUNS, THE SAME ENVIRONMENT. With the target main every module is run twice with `l4 run`,
# once with your l4 and once with the main build (in the module's directory), and both get your
# environment except that the main run has JL4_LIBRARY_PATH unset. A module that FETCHes or POSTs
# over the network, or reads ENV, does that twice, once with main. For such a module use
# L4_TARGET=unstable and compare by hand, or keep it out of the directory you check against main.
# The comparison is of COUNTS: equal counts can hide a different assertion failing on each side.
#
# Usage:  check.sh [DIR]          (DIR defaults to the directory this script is in)
# Env:    L4         the l4 binary you write with        (default: `l4` on PATH)
#         L4_TARGET  main | unstable                    (default: main)
#                    `unstable` skips the main check and says so on stderr; stdout and the exit
#                    status are then what this script printed before the target check existed.
#         L4_MAIN    the path of a main-build l4         (default: whatever fetch-main-l4.sh,
#                    next to this script, prints: the newest main build, cached)
#         L4_FETCH   a fetch-main-l4.sh somewhere else   (default: next to this script)
#         L4_MAIN_BUILD  a main build number for fetch-main-l4.sh to fetch instead of the newest
#         L4_MAIN_TIMEOUT  seconds each module may take on the main build (default: 300; 0 = no limit).
#                    A module that main cannot finish in that time is red: main is the compiler
#                    that has to read it. Your own l4 is never timed.
#
# Exit status: 0 only when no module has an error other than its expected failed
# assertions, no assertion refused, each module fails exactly as often as
# expected_failed says, and (target main) every module reads the same on main.
# 2 when a step could not be run: no l4, a bad L4_TARGET, or target main and no main binary.
# A run with a step missing is not a full check, so it does not return 0 or 1.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="${1:-$HERE}"
L4="${L4:-l4}"
TARGET="${L4_TARGET:-main}"
MAIN_TIMEOUT="${L4_MAIN_TIMEOUT:-300}"

# The first error in a run's output, on one line: its kind (parse or type), where, and what it says.
# The same extraction as etc/dialect-census.sh.
first_error() {
  awk '
    /^File:/ { if (found) exit; src = ""; rng = "" }
    /^  Range:/ { rng = $2 }
    /^  Source:/ { src = $2 }
    /^  Severity: DiagnosticSeverity_Error/ { found = 1; next }
    found && /^  Message:/ { inmsg = 1; next }
    found && inmsg {
      line = $0
      if (line ~ /^ *[0-9]* *\|/) next
      if (line ~ /^ *$/) next
      sub(/^ +/, "", line); sub(/ +$/, "", line)
      text = text (taken ? " " : "") line; taken++
      if (taken >= ((src == "parser" || src == "lexer" || src ~ /^file:/) ? 1 : 3)) exit
    }
    END { if (found) printf "%s %s: %s\n", (src == "parser" || src == "lexer") ? "parse" : ((src == "check") ? "type" : ((src ~ /^file:/) ? "import" : src)), rng, substr(text, 1, 150) }
  '
}

# The main run is a child (and, for a wrapper-style binary, a tree of them) plus a watchdog that
# sleeps for L4_MAIN_TIMEOUT. However this script ends, including by SIGINT, SIGTERM or SIGHUP,
# what it started is killed and its temporary file removed.
kill_tree() { # kill_tree PID: PID and everything it started, children first, quietly
  local c
  if command -v pgrep >/dev/null 2>&1; then
    for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done
  fi
  kill -9 "$1" 2>/dev/null
}
mpid="" wd="" mtmp=""
cleanup() {
  if [ -n "$wd" ]; then kill_tree "$wd"; wd=""; fi
  if [ -n "$mpid" ]; then kill_tree "$mpid"; mpid=""; fi
  if [ -n "$mtmp" ]; then rm -f -- "$mtmp" "$mtmp.timeout"; mtmp=""; fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

# A module that is MEANT to fail (a draft's test cases run against the text as made,
# say) is listed here with its exact count, and named in encoding.json `expected_red`.
# Every real `l4 run` prints "Checking succeeded." or, when it has anything to say, a block that
# starts with "File:" or "Evaluation[". Output with none of them did not come from an l4 that ran
# the module (a stub, `true`, a crash), and a count of zero from it is not a reading of the module.
produced_output() {
  printf '%s\n' "$1" | grep -a -q -E '^(Checking succeeded|File:|Evaluation\[)'
}

expected_failed() {
  case "$1" in
    # tests-red.l4) echo 3 ;;
    *) echo 0 ;;
  esac
}

if ! command -v "$L4" >/dev/null 2>&1; then
  echo "check.sh: no l4 binary at '$L4'. Set L4=/path/to/l4 or put l4 on PATH." >&2
  exit 2
fi

# --- the main binary, when the target is main --------------------------------------------------
MAIN="" MAIN_VERSION=""
case "$TARGET" in
  unstable) echo "check.sh: the target is unstable, so the main check was skipped." >&2 ;;
  main)
    case "$MAIN_TIMEOUT" in
      ""|*[!0-9]*) echo "check.sh: L4_MAIN_TIMEOUT must be a number of seconds, not '$MAIN_TIMEOUT'." >&2; exit 2 ;;
    esac
    MAIN="${L4_MAIN:-}"
    if [ -z "$MAIN" ]; then
      fetch="${L4_FETCH:-$HERE/fetch-main-l4.sh}"
      [ -x "$fetch" ] || fetch="$(command -v fetch-main-l4.sh 2>/dev/null || true)"
      if [ -z "$fetch" ] || [ ! -x "$fetch" ]; then
        echo "check.sh: the target is main, and there is no main-build l4 to compare with: L4_MAIN is not set and fetch-main-l4.sh was not found next to this script." >&2
        echo "          Copy fetch-main-l4.sh from the encoding-a-subject skill's assets/ beside check.sh, or set L4_MAIN=/path/to/a/main/l4." >&2
        echo "          A run with this step missing is not a full check; if the brief says the target is unstable, set L4_TARGET=unstable." >&2
        exit 2
      fi
      MAIN="$("$fetch" ${L4_MAIN_BUILD:+"$L4_MAIN_BUILD"})" || {
        echo "check.sh: the target is main, and fetch-main-l4.sh could not get a main-build l4 (its message is above)." >&2
        echo "          A run with this step missing is not a full check. Set L4_MAIN=/path/to/a/main/l4 to supply one;" >&2
        echo "          if the brief says the target is unstable, set L4_TARGET=unstable." >&2
        exit 2
      }
    fi
    resolved="$(command -v "$MAIN" 2>/dev/null)" || resolved=""
    if [ -z "$resolved" ] || [ ! -x "$resolved" ]; then
      echo "check.sh: the target is main, and '$MAIN' is not an executable l4. A run with this step missing is not a full check." >&2
      exit 2
    fi
    # The main run happens in the module's directory, so a relative path to the binary must be made absolute now.
    case "$resolved" in
      /*) MAIN="$resolved" ;;
      *) MAIN="$(cd "$(dirname "$resolved")" && pwd)/$(basename "$resolved")" ;;
    esac
    MAIN_VERSION="$(env -u JL4_LIBRARY_PATH "$MAIN" --version 2>/dev/null | tr -d '\000' | head -n 1)"
    case "$MAIN_VERSION" in
      unstable-*)
        echo "check.sh: L4_MAIN is an unstable build ($MAIN_VERSION), not a main build. The target is main, so there is nothing to compare." >&2
        exit 2 ;;
      [0-9]*"(main,"*) ;;
      *) echo "check.sh: warning: cannot confirm that $MAIN is a main build (its --version says '${MAIN_VERSION:-nothing}')." >&2 ;;
    esac
    ;;
  *)
    echo "check.sh: L4_TARGET must be main or unstable, not '$TARGET'." >&2
    exit 2 ;;
esac

status=0 total_err=0 total_ok=0 total_bad=0 total_ref=0 n=0
m_err=0 m_ok=0 m_bad=0 m_ref=0 differ=0
if [ "$TARGET" = main ]; then
  echo "target: main. Each module is run with your l4 and with the main build below; the main columns must match."
  echo "main build: ${MAIN_VERSION:-unversioned}"
  printf '%-40s %7s %9s %7s %8s %9s | %6s %9s %7s %8s  %s\n' module errors satisfied failed refused expected "errors" satisfied failed refused "main"
else
  printf '%-40s %7s %9s %7s %8s %9s\n' module errors satisfied failed refused expected
fi
for f in "$DIR"/*.l4; do
  [ -e "$f" ] || { echo "check.sh: no .l4 files in $DIR" >&2; exit 2; }
  m="$(basename "$f")"
  out="$("$L4" run "$f" 2>&1)"; rc=$?
  msgs="$(printf '%s\n' "$out" | grep -A1 -E '^[[:space:]]*Message:')"
  err=$(printf '%s\n' "$out" | grep -c 'DiagnosticSeverity_Error')
  ok=$(printf '%s\n' "$msgs" | grep -cE 'assertion satisfied')
  bad=$(printf '%s\n' "$msgs" | grep -cE 'assertion failed|assertion could not be evaluated')
  ref=$(printf '%s\n' "$msgs" | grep -cE 'assertion refused')
  exp=$(expected_failed "$m")
  if [ "$TARGET" = main ] && ! produced_output "$out"; then
    echo "check.sh: your l4 ('$L4') printed nothing it recognises for $m, so the target check cannot compare anything. A run with this step missing is not a full check." >&2
    exit 2
  fi
  [ $((err - bad)) -eq 0 ] && [ "$ref" -eq 0 ] && [ "$bad" -eq "$exp" ] || status=1
  total_err=$((total_err + err)) total_ok=$((total_ok + ok)) total_bad=$((total_bad + bad)) total_ref=$((total_ref + ref)) n=$((n + 1))
  if [ "$TARGET" = main ]; then
    # The same module, the same counting, with the main build. JL4_LIBRARY_PATH is unset for it: a
    # library path newer than the binary breaks it with errors that look like the module's.
    # It is bounded by L4_MAIN_TIMEOUT: a module main cannot finish is not readable by main.
    mtmp="$(mktemp "${TMPDIR:-/tmp}/check-main.XXXXXX")" || { echo "check.sh: cannot make a temporary file." >&2; exit 2; }
    ( cd "$DIR" && exec env -u JL4_LIBRARY_PATH "$MAIN" run "$m" >"$mtmp" 2>&1 ) &
    mpid=$!
    wd=""
    if [ "$MAIN_TIMEOUT" -gt 0 ]; then
      ( sleep "$MAIN_TIMEOUT"; kill_tree "$mpid" && touch "$mtmp.timeout" ) >/dev/null 2>&1 &
      wd=$!
    fi
    wait "$mpid" 2>/dev/null; mrc=$?
    mpid=""
    if [ -n "$wd" ]; then kill_tree "$wd"; wait "$wd" 2>/dev/null; wd=""; fi
    timedout=0; [ -e "$mtmp.timeout" ] && timedout=1
    mout="$(tr -d '\000' <"$mtmp")"
    rm -f -- "$mtmp" "$mtmp.timeout"; mtmp=""
    if [ "$timedout" = 0 ] && ! produced_output "$mout"; then
      echo "check.sh: the main build ('$MAIN') printed nothing it recognises for $m (it exited $mrc), so the main step could not run. A run with this step missing is not a full check." >&2
      exit 2
    fi
    mmsgs="$(printf '%s\n' "$mout" | grep -a -A1 -E '^[[:space:]]*Message:')"
    merr=$(printf '%s\n' "$mout" | grep -a -c 'DiagnosticSeverity_Error')
    mok=$(printf '%s\n' "$mmsgs" | grep -a -cE 'assertion satisfied')
    mbad=$(printf '%s\n' "$mmsgs" | grep -a -cE 'assertion failed|assertion could not be evaluated')
    mref=$(printf '%s\n' "$mmsgs" | grep -a -cE 'assertion refused')
    verdict="same"
    if [ "$timedout" = 1 ]; then
      verdict="reads differently on main (it did not finish in $MAIN_TIMEOUT s)"
    elif [ "$merr" -ne "$err" ] || [ "$mok" -ne "$ok" ] || [ "$mbad" -ne "$bad" ] || [ "$mref" -ne "$ref" ]; then
      verdict="reads differently on main"
    elif [ "$mrc" != 0 ] && [ "$merr" -eq 0 ] && [ "$rc" = 0 ]; then
      verdict="reads differently on main (it exited $mrc and printed no error)"
    fi
    [ "$verdict" = same ] || { status=1; differ=$((differ + 1)); }
    printf '%-40s %7d %9d %7d %8d %9d | %6d %9d %7d %8d  %s\n' "$m" "$err" "$ok" "$bad" "$ref" "$exp" "$merr" "$mok" "$mbad" "$mref" "$verdict"
    if [ "$verdict" != same ] && [ "$merr" -gt 0 ]; then
      printf '    main says: %s\n' "$(printf '%s\n' "$mout" | first_error)"
    fi
    m_err=$((m_err + merr)) m_ok=$((m_ok + mok)) m_bad=$((m_bad + mbad)) m_ref=$((m_ref + mref))
  else
    printf '%-40s %7d %9d %7d %8d %9d\n' "$m" "$err" "$ok" "$bad" "$ref" "$exp"
  fi
done
if [ "$TARGET" = main ]; then
  printf '%-40s %7d %9d %7d %8d %9s | %6d %9d %7d %8d\n' "TOTAL ($n modules)" "$total_err" "$total_ok" "$total_bad" "$total_ref" "" "$m_err" "$m_ok" "$m_bad" "$m_ref"
else
  printf '%-40s %7d %9d %7d %8d\n' "TOTAL ($n modules)" "$total_err" "$total_ok" "$total_bad" "$total_ref"
fi
echo "(a failed assertion is also an error; any other error, or any refused assertion, makes the run red)"
if [ "$TARGET" = main ]; then
  if [ "$differ" -eq 0 ]; then
    echo "(target main: every module has the same four counts on the main build. That rules out a module main rejects and a difference an assertion shows; it does not see a different TRACE outcome, or any difference no assertion exercises)"
  else
    echo "(target main: $differ module(s) read differently on main, so this encoding is not readable by main as it stands; see references/dialects.md in the writing-l4-rules skill, or set L4_TARGET=unstable if the brief says the target is unstable)"
  fi
fi
exit $status
