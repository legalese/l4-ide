#!/usr/bin/env bash
# One clock, sourced by the driver AND by every phase script.
#
# It is its own file rather than eight lines in each because the two callers
# MUST agree: `go.sh` starts the interval and the phase script ends it, and a
# driver reading milliseconds against a phase reading seconds would produce a
# difference that is not a duration at all. One definition, two `source` lines.

# go_now_ms -> milliseconds since the epoch.
#
# EPOCHREALTIME is a bash 5 builtin and costs no process; the pipeline's CI runs
# on ubuntu-latest, where it is always there. The fallback is for a bash 4 box
# (macOS with an old shell), and it degrades to WHOLE SECONDS rather than
# failing — a coarse duration is still a duration, and `ledger.verify`'s
# elapsed_ms check carries a 1000 ms tolerance for exactly this reason.
#
# The locale guard is not hypothetical: EPOCHREALTIME uses the decimal separator
# of LC_NUMERIC, so under a comma locale the arithmetic below would parse the
# whole string as one integer and report a timestamp a million times too large.
go_now_ms() {
  local e="${EPOCHREALTIME:-}"
  if [[ -n "$e" ]]; then
    e="${e/,/.}"
    printf '%s' "$(((${e%%.*} * 1000) + (10#${e#*.} / 1000)))"
  else
    printf '%s' "$(($(date +%s) * 1000))"
  fi
}

# go_since_ms T0 -> milliseconds elapsed since T0, or nothing if T0 is unset.
#
# Prints NOTHING rather than 0 for a missing start: zero is a measurement and
# "nobody started the clock" is not, and a receipt carrying a fabricated 0 would
# make a stage that was never timed look instantaneous in the report.
go_since_ms() {
  [[ -n "${1:-}" ]] || return 0
  local now
  now="$(go_now_ms)"
  local d=$((now - $1))
  ((d < 0)) && d=0 # a clock stepped backwards mid-stage; report no time, not negative time
  printf '%s' "$d"
}
