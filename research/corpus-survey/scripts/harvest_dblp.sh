#!/bin/zsh
# Phase 0 DBLP harvester: paginate the per-stream search API (100 hits/page cap),
# save raw JSON pages to data/raw/. Robust against DBLP's intermittent 5xx: retry
# each page up to 6x with backoff, polite 2s sleep between pages.
set -u
cd /Users/mengwong/src/legalese/l4wt/corpus-survey
RAW=research/corpus-survey/data/raw
mkdir -p "$RAW"
UA="l4-corpus-survey/0.1 (mengwong@gmail.com; academic literature index)"

fetch_page() {  # venue offset outfile
  local venue="$1" f="$2" out="$3" attempt url total
  url="https://dblp.org/search/publ/api?q=stream%3Astreams%2Fconf%2F${venue}%3A&h=100&f=${f}&format=json"
  for attempt in 1 2 3 4 5 6; do
    curl -s --max-time 45 -A "$UA" "$url" > "$out"
    total=$(jq -r '.result.hits."@total" // empty' "$out" 2>/dev/null)
    if [[ -n "$total" ]]; then
      echo "$total"; return 0
    fi
    echo "  retry $venue f=$f (attempt $attempt) bytes=$(wc -c < "$out")" >&2
    sleep $(( attempt * 3 ))
  done
  return 1
}

for venue in icail jurix deon; do
  echo "=== $venue ==="
  # first page also yields @total
  total=$(fetch_page "$venue" 0 "$RAW/${venue}-f0000.json") || { echo "FAILED first page $venue"; continue; }
  echo "  total=$total"
  f=100
  while (( f < total )); do
    printf -v fp "%04d" "$f"
    fetch_page "$venue" "$f" "$RAW/${venue}-f${fp}.json" >/dev/null || echo "  FAILED page f=$f $venue"
    sleep 2
    (( f += 100 ))
  done
  # tally what we actually stored
  got=$(cat "$RAW/${venue}-f"*.json 2>/dev/null | jq -s '[.[].result.hits.hit[]?] | length')
  echo "  stored hits=$got (expected ~$total)"
  sleep 2
done
echo "DONE"