#!/usr/bin/env bash
# lint-tics.sh — grep a blog post for the verbal tics banned in blog/STYLE.md §2.3.
# Usage: blog/lint-tics.sh blog/posts/*.md        exit 1 on any HARD hit; soft hits only warn.
# Quoted spans and *italic* / _italic_ titles are exempt (2026-09-14: a reviser omitted a paper's
# title to dodge the lint — never do that; the lint now skips quotations and titles).
# Calibrated 2026-09-13 against Gibson / Asimov / Somers (x2): zero hard hits on all four after
# 'genuinely' (Gibson x2) and 'leverage' (Somers) were demoted to soft. The epigram-closer warning
# The epigram check is a ratio (warn above 25% of paragraphs); the exemplars run 6-19%.
set -u
[ $# -gt 0 ] || { echo "usage: $0 <file.md>..." >&2; exit 2; }
HARD='\b(honest(ly)?|load-bearing|crucially|delve[sd]?|delving|tapestry|testament to|underscor(e|es|ed|ing)|robust(ly)?|nuanced|at its core|in a world where|let that sink in|here.s the thing|but that.s not (the|even)|keep reading|the twist|the kicker|it.s worth noting|the real [a-z]+ is)\b|\bit.s not [^.]{1,40} ?[—-]+ ?it.s\b|\bthis isn.t about\b|\belegant(ly)? (explanation|answer|result|solution)|\bis elegant\b'
SOFT='\b(quietly|remarkabl[ey]|of course|in other words|genuinely|leverag(e|es|ed|ing))\b'
rc=0
for f in "$@"; do
  # strip fenced code and the YAML front matter so quoted L4 and metadata are not linted
  body=$(awk 'BEGIN{fm=0;code=0} NR==1&&/^---$/{fm=1;next} fm&&/^---$/{fm=0;next} fm{next} /^```/{code=!code;next} !code' "$f")
  # quotations and cited titles keep their source's words: blank out "…", “…”, *…* and _…_ spans before linting
  body=$(printf '%s\n' "$body" | perl -pe 's/"[^"\n]{1,300}"/"…"/g; s/\x{201C}[^\x{201D}\n]{1,300}\x{201D}/“…”/g; s/(?<![*\w])\*[^*\n]{1,200}\*(?![*\w])/*…*/g; s/(?<![_\w])_[^_\n]{1,200}_(?![_\w])/_…_/g')
  hard=$(printf '%s\n' "$body" | grep -n -i -E "$HARD")
  soft=$(printf '%s\n' "$body" | grep -n -i -E "$SOFT")
  title=$(sed -n 's/^title: *//p' "$f" | head -1); tw=$(printf '%s' "$title" | wc -w | tr -d ' ')
  if [ -n "$hard" ]; then echo "FAIL $f"; printf '%s\n' "$hard" | sed 's/^/   /'; rc=1; fi
  if [ -n "$soft" ]; then echo "warn $f (soft)"; printf '%s\n' "$soft" | sed 's/^/   /'; fi
  if [ "${tw:-0}" -gt 12 ]; then echo "warn $f: title is $tw words (>12)"; fi
  # epigram ratio: share of paragraphs whose final sentence is <=6 words with no digit/quote/proper noun.
  # Exemplars measured 2026-09-13 run 6-19%; warn above 25%. Individual epigrams are allowed (Meng's ruling).
  printf '%s\n' "$body" | awk -v f="$f" 'BEGIN{RS="";FS="\n"} { if ($0 ~ /^[[:space:]]*[-|#>]/) next; np++;
     n=split($0,s,/[.!?]["”]? +/); last=s[n]; sub(/[.!?"”]+$/,"",last); w=split(last,ww," ");
     if (w>0 && w<=6 && last !~ /[0-9"“”]/) { caps=0; for(i=2;i<=w;i++) if (ww[i] ~ /^[A-Z]/) caps++; if (caps==0) ne++ } }
     END { if (np>0 && ne/np>0.25) printf "warn %s: epigram ratio %d/%d paragraphs (>25%%) — the figure is carrying the piece\n", f, ne, np }'
  [ -z "$hard" ] && echo "ok   $f (hard list clean)"
done
exit $rc
