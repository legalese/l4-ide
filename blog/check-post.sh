#!/usr/bin/env bash
# check-post.sh — structural checks for a blog post, then the tic lint. Exit 1 on any failure.
# Usage: blog/check-post.sh blog/posts/01-foo.md [...]
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ $# -gt 0 ] || { echo "usage: $0 <post.md>..." >&2; exit 2; }
STANZA='This research is supported by the National Research Foundation (NRF), Singapore, under its Industry Alignment Fund – Pre-Positioning Programme, as the Research Programme in Computational Law. Any opinions, findings and conclusions or recommendations expressed in this material are those of the author(s) and do not reflect the views of National Research Foundation, Singapore.'
rc=0
for f in "$@"; do
  fail() { echo "FAIL $f: $*"; rc=1; }
  warn() { echo "warn $f: $*"; }
  head -1 "$f" | grep -q '^---$' || fail "no YAML front matter"
  for k in title status date facet words license sources_checked; do grep -qE "^$k:" "$f" || fail "front matter lacks '$k:'"; done
  grep -qE '^license: *CC-BY-NC-4.0' "$f" || fail "license must be CC-BY-NC-4.0"
  grep -qE '^status: *(draft|review|published)' "$f" || fail "status must be draft|review|published"
  body=$(awk 'BEGIN{fm=0} NR==1&&/^---$/{fm=1;next} fm&&/^---$/{fm=0;next} fm{next} {print}' "$f")
  printf '%s\n' "$body" | grep -m1 -E '\S' | grep -qE '^\*\*STATUS [0-9]{4}-[0-9]{2}-[0-9]{2}:' || fail "body must open with a **STATUS <date>: …** header"
  # stanza: normalise whitespace and compare
  norm() { tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'; }
  if ! printf '%s\n' "$body" | norm | grep -qF "$(printf '%s' "$STANZA" | norm)"; then fail "NRF funding stanza missing or altered (must be verbatim)"; fi
  # stanza must be last non-empty paragraph
  lastpara=$(printf '%s\n' "$body" | awk 'BEGIN{RS=""} {p=$0} END{print p}' | norm)
  case "$lastpara" in *"do not reflect the views of National Research Foundation, Singapore."*) ;; *) fail "NRF stanza must be the last paragraph";; esac
  grep -qE '^#+ *Sources' "$f" || fail "no '## Sources' section"
  grep -qE '^\*\*STATUS' "$f" && true
  grep -n '\[UNVERIFIED' "$f" | head -5 | sed "s|^|warn $f: unverified marker at line |"
  grep -n '\[NEEDS MENG' "$f" | head -8 | sed "s|^|warn $f: needs-Meng marker at line |"
  # word count of prose (front matter, Sources, stanza excluded)
  words=$(printf '%s\n' "$body" | awk '/^#+ *Sources/{exit} {print}' | wc -w | tr -d ' ')
  [ "$words" -ge 1500 ] && [ "$words" -le 3500 ] || warn "prose is $words words (target 2,000–2,500; ceiling 3,500)"
  decl=$(sed -n 's/^words: *//p' "$f" | head -1); [ -n "$decl" ] && [ "${decl:-0}" -ne 0 ] && { d=$(( decl>words ? decl-words : words-decl )); [ "$d" -gt 150 ] && warn "front matter says words: $decl, counted $words"; }
  # US spelling: a short list of British forms that are not inside quotation marks
  brit=$(printf '%s\n' "$body" | grep -nE '\b([Ff]ormalis(e|ed|es|ing|ation)|[Rr]ecognis(e|ed|es|ing)|[Oo]rganis(e|ed|es|ation)|[Bb]ehaviour|[Cc]olour|[Ff]avour|[Ll]icence|[Pp]ractising|[Jj]udgement|[Aa]nalys(e|ed)|[Cc]entre|[Pp]rogramme)\b' | grep -vE 'Pre-Positioning Programme|Research Programme|Organisation for Economic|organisation-automaton|^[0-9]+:>' | grep -vE '"[^"]*\b([Ff]ormalis|[Rr]ecognis|[Bb]ehaviour|[Ll]icence|[Pp]ractising|[Pp]rogramme)[^"]*"' | cut -c1-120 | head -5)
  [ -n "$brit" ] && { echo "$brit" | sed "s|^|warn $f: British spelling? line |"; }
  # acronym spelled out: any ALLCAPS token of 3-6 letters in the PROSE (not footnotes/Sources, not code spans,
  # not house markers, not citation identifiers) must appear as '… (ABC)' somewhere in the post, or be allowlisted
  prose=$(printf '%s\n' "$body" | awk '/^#+ *Sources/{exit} /^\[\^[0-9]+\]:/{next} {print}' | perl -pe 's/`[^`\n]*`//g; s/\[(?:NEEDS MENG|UNVERIFIED)[^\]]*\]//g; s/\*\*STATUS[^*]*\*\*//g')
  printf '%s\n' "$prose" | grep -oE '\b[A-Z]{3,6}\b' | sort -u | while read -r a; do case "$a" in NRF|SMU|USA|AWS|PDF|URL|API|SQL|HTML|CSS|JSON|YAML|DOI|MIT|IBM|GPT|LLM|LLMs|TLA|NZ|UK|US|EU|OECD|ICAIL|JURIX|DEON|CACM|SOSP|ACM|CC|BY|NC|MUST|MAY|SHANT|GIVEN|DECIDE|IF|AND|OR|SHOULD|NOT|IS|A|THE|OF|FOR|EVAL|UNDER|RULES|EFFECTIVE|AT|DECLARE|HAS|ONE|TRUE|FALSE|STATUS|DRAFT|SC|EC|NEEDS|MENG|README|STYLE|SPEC|NOTES|CODEX|PROLEG|PROLOG|SWI|SWISH|LNCS|SGCA|SGHC|CELEX|EUR|EEC|CJEU|UPPAAL|NUSMV|SPIN|ATVA|ICTAC|ICFP|OPA|HSPEC|ZFS|SMR|CPU|ISO|IEEE|CXO|CEO|CTO|FCA|ABC|LSJ|NZLII|VUB|QUB|OUP|ENS|ICT|NUS|LTS|IR|CTD|FCL|ATL|LTL|CTL|TCTL|SMT|BMC|IC|WASM|NLG|DMN|BPMN|TCK|DVA|DHS|RR|YC|SAFE|OSM|LII|FTC|UPL|WJP|LSC|NUPEDIA) continue;; esac; printf '%s\n' "$body" | grep -qE "\($a\)" || echo "warn $f: acronym $a never spelled out as '… ($a)'"; done
  "$HERE/lint-tics.sh" "$f" || rc=1
  [ $rc -eq 0 ] && echo "ok   $f (structure clean)"
done
exit $rc
