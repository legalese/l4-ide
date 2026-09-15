#!/usr/bin/env bash
# check-fidelity.sh BEFORE AFTER — a voice/register pass may change wording but not facts.
# Extracts every number, quoted string, footnote reference and [NEEDS MENG]/[UNVERIFIED] marker
# from both versions of a post and diffs the multisets. Exit 1 on any difference.
set -u
[ $# -eq 2 ] || { echo "usage: $0 before.md after.md" >&2; exit 2; }
facts() {
  # digits, and spelled-out numbers (a voice pass could turn "nine trials" into "eight")
  perl -ne 'while (/(\[\^\d+\]|\[(?:NEEDS MENG|UNVERIFIED)[^\]]*\]|"[^"\n]{3,300}"|\x{201C}[^\x{201D}\n]{3,300}\x{201D}|(?<![\w.])\d[\d,]*(?:\.\d+)?%?|\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|half|third|thirds|quarter|quarters|dozen|first|second|fourth|fifth)\b)/gi) { print lc($1), "\n" }' "$1" | sort
}
d=$(diff <(facts "$1") <(facts "$2"))
if [ -n "$d" ]; then echo "FIDELITY FAIL: numbers/quotes/footnotes/markers differ between $1 and $2:"; printf '%s\n' "$d" | head -40; exit 1; fi
echo "ok   fidelity: numbers, quotations, footnote refs and markers unchanged"
