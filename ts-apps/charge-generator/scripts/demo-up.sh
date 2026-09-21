#!/usr/bin/env bash
# Bring the charge-generator demo up on this machine and expose it through a
# Cloudflare quick tunnel. Idempotent: re-running restarts the pieces it owns.
#
#   scripts/demo-up.sh            # service + build + node server + tunnel
#   scripts/demo-up.sh --no-tunnel
#
# Prints the public URL at the end. The tunnel hostname changes on every start
# (quick tunnels are anonymous); a named tunnel needs a Cloudflare account.
set -euo pipefail
APP=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(cd "$APP/../.." && pwd)
PORT=${PORT:-5175}
SVC_PORT=${SVC_PORT:-18099}
STORE=${JL4_STORE:-/tmp/jl4-store-charge-generator}
KEYFILE=${ANTHROPIC_KEY_FILE:-$ROOT/anthropic-apikey-charge-generator.api}
LOG=${DEMO_LOG:-/tmp/charge-generator-demo}
mkdir -p "$LOG" "$STORE"

# 1. jl4-service, from this worktree's build, if not already listening.
if ! curl -s -m 3 "http://127.0.0.1:$SVC_PORT/health" >/dev/null; then
  BIN=$(cd "$ROOT" && cabal list-bin jl4-service)
  [ -x "$BIN" ] || { echo "jl4-service not built: cabal build jl4-service" >&2; exit 1; }
  nohup "$BIN" --port "$SVC_PORT" --store-path "$STORE" > "$LOG/jl4-service.log" 2>&1 &
  for _ in $(seq 1 30); do curl -s -m 2 "http://127.0.0.1:$SVC_PORT/health" >/dev/null && break; sleep 1; done
fi
echo "jl4-service: $(curl -s -m 3 "http://127.0.0.1:$SVC_PORT/health")"

# 2. the corpus, from the canon clone.
(cd "$APP" && JL4_BASE_URL="http://127.0.0.1:$SVC_PORT" node scripts/seed.mjs 2>/dev/null | head -2)

# 3. the app: production build, node server.
(cd "$ROOT" && npx turbo run build --filter=charge-generator >/dev/null)
pkill -f "node build" 2>/dev/null || true
pkill -f "vite dev --port $PORT" 2>/dev/null || true
sleep 1
KEY=""
[ -f "$KEYFILE" ] && KEY=$(tr -d '[:space:]' < "$KEYFILE")
[ -n "$KEY" ] || echo "note: no Anthropic key at $KEYFILE — samples work, the live interview will not" >&2
(cd "$APP" && ANTHROPIC_API_KEY="$KEY" JL4_UPSTREAM="http://127.0.0.1:$SVC_PORT" PORT="$PORT" HOST=0.0.0.0 \
  nohup node build > "$LOG/node-server.log" 2>&1 &)
sleep 3
echo "app: http://127.0.0.1:$PORT/  ($(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/"))"

# 4. the tunnel.
if [ "${1:-}" != "--no-tunnel" ]; then
  pkill -f "cloudflared tunnel --url http://localhost:$PORT" 2>/dev/null || true
  nohup cloudflared tunnel --url "http://localhost:$PORT" --no-autoupdate > "$LOG/cloudflared.log" 2>&1 &
  for _ in $(seq 1 30); do
    URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG/cloudflared.log" | head -1 || true)
    [ -n "$URL" ] && break; sleep 1
  done
  echo "public: ${URL:-tunnel did not report a URL; see $LOG/cloudflared.log}"
fi
