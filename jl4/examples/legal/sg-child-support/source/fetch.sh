#!/usr/bin/env bash
# Re-runs the P1 fetch for the sg-child-support subject, reproducibly.
# Every sha256 in registers/source-bundle.json is over the bytes this writes.
set -uo pipefail
cd "$(dirname "$0")"
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36'
get () { # get <slug> <url>
  printf '%-28s %s\n' "$1" "$2"
  curl -sSL --max-time 60 -A "$UA" -o "raw/$1" -w '  http=%{http_code} bytes=%{size_download}\n' "$2" \
    || echo "  FETCH FAILED"
}
get ndr2026-speech.html        'https://www.pmo.gov.sg/newsroom/ndr2026/'
get lifesg-csp.html            'https://www.life.gov.sg/family-parenting/benefits-support/sg-child-support-package'
get mff-baby-bonus.html        'https://www.madeforfamilies.gov.sg/support-measures/child-raising/financial-support/baby-bonus-scheme'
get mff-large-families.html    'https://www.madeforfamilies.gov.sg/support-measures/child-raising/financial-support/large-families-scheme'
get population-ndr2026.html    'https://www.population.gov.sg/marriage-parenthood-measures-at-national-day-rally-2026/'
echo
echo "sha256:"
shasum -a 256 raw/* 2>/dev/null
