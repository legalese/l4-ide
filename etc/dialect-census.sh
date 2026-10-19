#!/bin/bash
#
# dialect-census.sh — list the .l4 files that one l4 binary rejects, with the first error each fails with.
#
# WHY THIS EXISTS
#   `main` and `unstable` are two compilers. A file written for one can fail to parse or type-check on the other,
#   and the failure reads as a broken example rather than as the wrong compiler.
#   This script runs ONE binary over a tree and reports what it rejects, so the same tree can be run through two binaries
#   and the two reports compared. skills/writing-l4-rules/references/dialects.md is built from that comparison.
#
# USAGE
#   etc/dialect-census.sh <l4 binary> [dir]
#
#     <l4 binary>   the compiler to test, by path or by name on PATH. Run `<l4 binary> --version` first and keep the line.
#     [dir]         the tree to scan for *.l4 files. Default: doc/ in the repository this script lives in.
#
# WHAT IT DOES
#   For every *.l4 under dir it runs `<l4 binary> check <file>` with the file's own directory as the working directory
#   and JL4_LIBRARY_PATH unset, so the binary resolves the prelude it carries itself and the prelude cannot be newer than the binary.
#   For each file that fails it prints one tab-separated line:
#
#       <path relative to dir>  <kind>  <line:col>  <first error, on one line>
#
#   kind is `parse` (the parser rejected the text), `type` (the type checker did), or `crash` (non-zero exit, no error block).
#   The last line is a summary: `census: <n> files, <m> fail (<binary version line>)`.
#   It exits 0 whatever it finds; it reports, it does not gate.
#
# READING THE RESULT
#   A binary OLDER than what it parses fails on newer syntax, and the failure looks like a broken example.
#   Run an unstable binary over the repository's own doc/ and it should fail nothing; if it does fail some pages,
#   the binary is older than the tree and those pages say nothing about main.
#   The first error is often a symptom: a parse error at a later token can be caused by an earlier unsupported construct.
#   Attribute a cause by a minimal probe, not by reading the message.
#
# `l4 check` output contains NUL bytes, so the output is cleaned with tr before any text tool sees it.

set -u

BIN_ARG="${1:-}"
if [ -z "$BIN_ARG" ] || [ "$BIN_ARG" = "-h" ] || [ "$BIN_ARG" = "--help" ]; then
  echo "usage: $0 <l4 binary> [dir]" >&2
  exit 2
fi
if [ -x "$BIN_ARG" ] && [ -f "$BIN_ARG" ]; then
  BIN="$(cd "$(dirname "$BIN_ARG")" && pwd)/$(basename "$BIN_ARG")"
elif command -v "$BIN_ARG" >/dev/null 2>&1; then
  BIN="$(command -v "$BIN_ARG")"
else
  echo "dialect-census: no executable l4 at $BIN_ARG" >&2
  exit 2
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="${2:-$HERE/../doc}"
[ -d "$DIR" ] || { echo "dialect-census: no such directory $DIR" >&2; exit 2; }
DIR="$(cd "$DIR" && pwd)"

TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD="timeout 120"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD="gtimeout 120"
fi

VERSION="$("$BIN" --version 2>&1 | tr -d '\000' | head -n 1)"

total=0
failing=0

while IFS= read -r -d '' f; do
  total=$((total + 1))
  rel="${f#"$DIR"/}"
  out="$(cd "$(dirname "$f")" && unset JL4_LIBRARY_PATH && $TIMEOUT_CMD "$BIN" check "$(basename "$f")" 2>&1; echo "census-rc=$?")"
  out="$(printf '%s\n' "$out" | tr -d '\000')"
  rc="$(printf '%s\n' "$out" | sed -n 's/^census-rc=//p' | tail -n 1)"
  out="$(printf '%s\n' "$out" | grep -a -v '^census-rc=')"
  # The first error block: its `Source:` and `Range:` lines, and the message that follows `Message:`.
  block="$(printf '%s\n' "$out" | awk '
    /^File:/ { if (found) exit; file = $2; src = ""; rng = "" }
    /^  Range:/ { rng = $2 }
    /^  Source:/ { src = $2 }
    /^  Severity: DiagnosticSeverity_Error/ { found = 1; print "FILE\t" file; print "SRC\t" src; print "RANGE\t" rng; next }
    found && /^  Message:/ { inmsg = 1; next }
    found && inmsg { if (++n > 40) exit; print "MSG\t" $0 }
  ')"
  if [ -z "$block" ]; then
    # No error diagnostic. A non-zero exit with nothing to show is still a failure worth naming.
    if [ "$rc" -ne 0 ]; then
      failing=$((failing + 1))
      printf '%s\t%s\t%s\t%s\n' "$rel" "crash" "-" "exit $rc, no error diagnostic"
    fi
    continue
  fi
  failing=$((failing + 1))
  src="$(printf '%s\n' "$block" | awk -F'\t' '$1=="SRC" {print $2; exit}')"
  rng="$(printf '%s\n' "$block" | awk -F'\t' '$1=="RANGE" {print $2; exit}')"
  efile="$(printf '%s\n' "$block" | awk -F'\t' '$1=="FILE" {print $2; exit}')"
  case "$src" in
    parser|lexer) kind=parse ;;
    check) kind=type ;;
    *) kind="${src:-other}" ;;
  esac
  # The message text on one line. A parse error: the line under the caret row ("unexpected X"; the "expecting ..." list is dropped).
  # A type error: the first three non-blank lines, which usually carry the quoted name, cut to 150 characters.
  limit=3; [ "$kind" = parse ] && limit=1
  msg="$(printf '%s\n' "$block" | awk -F'\t' -v limit="$limit" '
    $1 == "MSG" {
      line = substr($0, 5)
      if (line ~ /^ *[0-9]* *\|/) next
      if (line ~ /^ *$/) next
      if (taken < limit) { sub(/^ +/, "", line); sub(/ +$/, "", line); text = text (taken ? " " : "") line; taken++ }
    }
    END { print substr(text, 1, 150) }
  ')"
  [ -n "$msg" ] || msg="(no message text)"
  note=""
  [ -n "$efile" ] && [ "$efile" != "$(basename "$f")" ] && note=" [in $efile]"
  printf '%s\t%s\t%s\t%s%s\n' "$rel" "$kind" "${rng:--}" "$msg" "$note"
done < <(find "$DIR" -name '*.l4' -print0 | sort -z)

echo "census: $total files, $failing fail ($VERSION)"
exit 0
