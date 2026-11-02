#!/bin/bash
# Upload a jl4-web build for play.legalese.com and refresh the CDN.
# main-tag.yml runs this after each release.
#
# Usage: ./scripts/deploy-static.sh <build-dir> <bucket> <distribution-id> [--dryrun]
#
# - _app/immutable/ (content-hashed) and wasm/<release>/ never change once
#   uploaded, so they are cached for a year and never deleted: tabs still on
#   the previous release keep loading their files.
# - Everything else (index.html, _app/version.json, ...) is revalidated on each
#   load, replaced and invalidated, so the next load picks up the new release's
#   file names.
# - The CDN only compresses files up to 10 MB, so larger ones are uploaded
#   as the brotli copy SvelteKit's precompress already made.

set -euo pipefail

if [ $# -lt 3 ]; then
    echo "Usage: $0 <build-dir> <bucket> <distribution-id> [--dryrun]" >&2
    exit 1
fi

BUILD_DIR="${1%/}"
BUCKET="$2"
DISTRIBUTION_ID="$3"
DRYRUN=()
if [ "${4:-}" = "--dryrun" ]; then
    DRYRUN=(--dryrun)
fi
# Arrays are expanded as ${A[@]+"${A[@]}"}: bash 3.2 (macOS) treats an empty
# "${A[@]}" as unbound under set -u.

IMMUTABLE="public, max-age=31536000, immutable"
REVALIDATE="public, max-age=0, must-revalidate, s-maxage=31536000"
CDN_COMPRESS_LIMIT=10000000

content_type() {
    case "$1" in
        *.wasm) echo "application/wasm" ;;
        *.mjs | *.js) echo "text/javascript" ;;
        *.css) echo "text/css" ;;
        *.html) echo "text/html" ;;
        *.json) echo "application/json" ;;
        *) echo "application/octet-stream" ;;
    esac
}

is_versioned() {
    case "$1" in
        _app/immutable/* | wasm/*) return 0 ;;
        *) return 1 ;;
    esac
}

cd "$BUILD_DIR"

# 1. Files the CDN won't compress, uploaded already brotli-encoded (or as
# they are, if there is no brotli copy).
EXCLUDE_BIG=()
while IFS= read -r file; do
    key="${file#./}"
    if is_versioned "$key"; then cache="$IMMUTABLE"; else cache="$REVALIDATE"; fi
    if [ -f "$key.br" ]; then
        aws s3 cp ${DRYRUN[@]+"${DRYRUN[@]}"} "$key.br" "s3://$BUCKET/$key" \
            --content-encoding br --content-type "$(content_type "$key")" --cache-control "$cache"
    else
        aws s3 cp ${DRYRUN[@]+"${DRYRUN[@]}"} "$key" "s3://$BUCKET/$key" \
            --content-type "$(content_type "$key")" --cache-control "$cache"
    fi
    EXCLUDE_BIG+=(--exclude "$key")
done < <(find . -type f ! -name '*.br' ! -name '*.gz' -size +"$CDN_COMPRESS_LIMIT"c)

# 2. Versioned files: hashed names, so a matching size means the same file.
aws s3 sync ${DRYRUN[@]+"${DRYRUN[@]}"} . "s3://$BUCKET/" --size-only \
    --exclude '*' --include '_app/immutable/*' --include 'wasm/*' \
    --exclude '*.br' --exclude '*.gz' --exclude '*.mjs' --exclude '*.wasm' \
    ${EXCLUDE_BIG[@]+"${EXCLUDE_BIG[@]}"} \
    --cache-control "$IMMUTABLE"

# Module and WASM files need exact types: import() rejects a module that isn't
# served as JavaScript.
while IFS= read -r file; do
    key="${file#./}"
    aws s3 cp ${DRYRUN[@]+"${DRYRUN[@]}"} "$key" "s3://$BUCKET/$key" \
        --content-type "$(content_type "$key")" --cache-control "$IMMUTABLE"
done < <(find ./_app/immutable ./wasm -type f \( -name '*.mjs' -o -name '*.wasm' \) \
    -size -"$((CDN_COMPRESS_LIMIT + 1))"c 2>/dev/null)

# 3. Everything else, replaced on each deploy. wasm-test.html is a dev page that
# loads unversioned WASM paths, so it isn't published. index.html goes last, once
# everything it references is in place.
SYNC_LOG=$(mktemp)
trap 'rm -f "$SYNC_LOG"' EXIT
aws s3 sync ${DRYRUN[@]+"${DRYRUN[@]}"} . "s3://$BUCKET/" --delete --no-progress \
    --exclude '_app/immutable/*' --exclude 'wasm/*' \
    --exclude '*.br' --exclude '*.gz' --exclude 'wasm-test.html' --exclude 'index.html' \
    ${EXCLUDE_BIG[@]+"${EXCLUDE_BIG[@]}"} \
    --cache-control "$REVALIDATE" | tee "$SYNC_LOG"
aws s3 cp ${DRYRUN[@]+"${DRYRUN[@]}"} index.html "s3://$BUCKET/index.html" \
    --content-type "text/html" --cache-control "$REVALIDATE"

# 4. Drop the CDN's copies of what step 3 replaced or deleted. Only those: a
# blanket /* would also flush the edge copies of every share link and the WASM.
PATHS=(/)
while IFS= read -r file; do
    PATHS+=("/${file#./}")
done < <(find . -type f ! -name '*.br' ! -name '*.gz' ! -name 'wasm-test.html' \
    ! -path './_app/immutable/*' ! -path './wasm/*' | sort)
while IFS= read -r key; do
    PATHS+=("/$key")
done < <(sed -n "s|^.*delete: s3://$BUCKET/||p" "$SYNC_LOG")

if [ "${4:-}" != "--dryrun" ]; then
    aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths "${PATHS[@]}" \
        --query 'Invalidation.Id' --output text
else
    echo "(dryrun) aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths ${PATHS[*]}"
fi
