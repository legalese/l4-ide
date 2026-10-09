#!/bin/bash
# Smoke test for a built legalese-cloud-agent image (spec §14 step 5).
#
#   docker/smoke.sh <image>
#
# No AWS, no network: it checks the image's contents, that the entry point
# rejects a bad environment, and that a start with the task's runtime
# settings (read-only root, tmpfs, all capabilities dropped, user 1000)
# takes the lease, starts jl4-lsp, fails to renew the agent key (no
# network) and parks cleanly.
set -euo pipefail
IMAGE="$1"
SID=01J9Z3K4M5N6P7Q8R9S0T1V2W3

echo "── image contents"
docker run --rm --entrypoint /bin/bash "$IMAGE" -c '
  set -e
  node --version
  git --version
  /usr/bin/tini --version
  if ldd /app/bin/jl4-lsp | grep "not found"; then exit 1; fi
  test -x /app/entrypoint
  test -f /app/cloud-agent.cjs
  test "$(id -u):$(id -g)" = "1000:1000"
'

echo "── entry point rejects a bad environment"
set +e
docker run --rm -e SESSION_ID=not-a-ulid -e AGENT_KEY=sk_smoke_0000000000 "$IMAGE" >/dev/null 2>&1
code=$?
set -e
if [[ $code -ne 64 ]]; then
  echo "expected exit 64, got $code" >&2
  exit 1
fi

echo "── a session start without network parks"
WS=$(mktemp -d)
trap 'rm -rf "$WS"' EXIT
S="$WS/sessions/$SID"
mkdir -p "$S/repo/data" "$S/repo/tmp" "$S/attachments" "$S/state/events" "$S/state/commands" "$S/state/git/incoming"
now=$(($(date +%s) * 1000))
cat > "$S/session.json" <<JSON
{"sessionId":"$SID","ownerUserId":"smoke","title":"","created":$now,"lastActivity":$now,"status":"new","mcpServers":[]}
JSON
printf 'DECIDE x IS 1\n' > "$S/repo/data/rules.l4"
git -C "$S/repo" init -q -b main
chmod -R a+rwX "$WS"

set +e
timeout 240 docker run --rm \
  --network none --read-only --cap-drop ALL --user 1000:1000 \
  --tmpfs /tmp:size=512m --tmpfs /home/agent:size=256m --tmpfs /run:size=64m \
  -v "$WS:/workspace" \
  -e SESSION_ID="$SID" -e AGENT_KEY=sk_smoke_0000000000 \
  -e AI_PROXY_URL=https://ai.invalid -e MCP_URL=https://mcp.invalid \
  -e AUTH_URL=https://auth.invalid -e LOG_LEVEL=info \
  -e SOMETHING_ELSE=dropped \
  "$IMAGE" > "$WS/harness.log" 2>&1
code=$?
set -e
cat "$WS/harness.log"
if [[ $code -ne 0 ]]; then
  echo "harness exited $code" >&2
  exit 1
fi
grep -q '"status": "parked"' "$S/session.json" || { echo "session not parked" >&2; exit 1; }
grep -q '"type":"auth-required"' "$S/state/events/1.jsonl" || { echo "no auth-required event" >&2; exit 1; }
grep -q '"type":"session-state","state":"parked"' "$S/state/events/1.jsonl" || { echo "no parked state" >&2; exit 1; }
if grep -q 'sk_smoke' "$WS/harness.log"; then
  echo "the agent key reached the log" >&2
  exit 1
fi
echo "smoke test passed"
