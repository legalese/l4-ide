#!/usr/bin/env bash
# Build the standalone interactive ladder page into standalone/dist/ via esbuild.
# Then open standalone/dist/index.html (file://), or serve it:
#   (cd standalone/dist && python3 -m http.server 8731)  ->  http://localhost:8731/
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p standalone/dist
npx esbuild standalone/app.ts --bundle --format=iife --outfile=standalone/dist/app.js
cp standalone/index.html standalone/dist/index.html
echo "built standalone/dist/{app.js,index.html}"
