#!/usr/bin/env bash
#
# Tabulate a --corpus run: findings grouped by KIND, with counts and one example.
# Called by run.sh --corpus; usable on its own against an earlier run:
#
#   etc/dmn-check/summarise.sh <workdir>/corpus
#
# Reads findings.tsv (written by DmnCheckRun --tsv) and export-status.tsv.
#
# A KIND is validator + severity + element type + the message with the parts that
# vary flattened: quoted names to '..', bracketed lists to [..], numbers to N, the
# expression and expected-token list of a FEEL parse error cut off, and the list of
# subgraphs in "Found unconnected requirement graphs" collapsed. Two findings of one kind
# differ only in which file, decision or rule they sit on. The grouping is
# mechanical and does not judge: whether a kind is a defect in the L4 source, an
# artefact of how the exporter writes DMN, or a false positive in dmn-check is a
# reading of an example, and README.md records those readings.
#
# Columns: findings, files, validator, severity, element type, kind, example
# (file, then decision, then element id).
set -euo pipefail

dir="${1:?usage: summarise.sh <corpus workdir>}"
tsv="$dir/findings.tsv"
[ -s "$tsv" ] || { echo "summarise.sh: no $tsv" >&2; exit 2; }

echo "FINDING KINDS"
awk -F'\t' '
  NR == 1 { next }
  {
    m = $8
    # Order matters: the expression inside "Could not parse \047..\047" can itself hold
    # apostrophes and brackets, so it goes first, as one greedy match.
    sub(/^Could not parse \047.*\047: line [0-9]+, column [0-9]+:.*$/, "Could not parse \047..\047: line N, column N: ..", m)
    sub(/^Found unconnected requirement graphs: .*$/, "Found unconnected requirement graphs: [..]", m)
    gsub(/\047[^\047]*\047/, "\047..\047", m)
    gsub(/\[[^]]*\]/, "[..]", m)
    gsub(/[0-9]+/, "N", m)
    k = $2 "\t" $3 "\t" $4 "\t" m
    n[k]++
    if (!((k SUBSEP $1) in seen)) { seen[k, $1] = 1; f[k]++ }
    if (!(k in ex)) {
      p = $1; sub(/^.*\/dmn\//, "", p)
      ex[k] = p " | " $6 " | " $7
    }
  }
  END { for (k in n) printf "%d\t%d\t%s\t%s\n", n[k], f[k], k, ex[k] }
' "$tsv" | LC_ALL=C sort -t$'\t' -k1,1nr -k3,3 \
  | awk -F'\t' '{ printf "%6d %5d  %-38s %-7s %-14s %s\n         e.g. %s\n", $1, $2, $3, $4, $5, $6, $7 }'

echo
echo "FILES"
awk -F'\t' '
  NR == 1 { next }
  { n++; w[$1] = 1 }
  END { print "  files with at least one finding: " length(w) }
' "$tsv"
