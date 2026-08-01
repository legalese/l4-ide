#!/usr/bin/env bash
# P7 — the MCP leg (the module served as tools via jl4-service).
#
# THE ONE PLACE THIS ORCHESTRATOR MAKES A NETWORK WRITE, AND THE FENCE ROUND IT.
#
# Everywhere else, "nothing outward-facing happens" is guaranteed by there being
# no code that could do it. This leg posts a deployment. So:
#
#   * the deployable zip is built LOCALLY and hashed unconditionally — that part
#     is a real artifact and needs no service;
#   * the POST target must be LOOPBACK. A non-loopback host is refused with exit
#     3 citing HG2, because publishing a deployment to a host other people can
#     reach is outward-facing and SPEC.md §7.3 puts that behind Meng's gate;
#   * with no JL4_GO_SERVICE_URL set, the leg is SKIPPED with a named reason and
#     the zip is still recorded.
#
# The deployment id carries the run id, so a re-entered or concurrent run never
# collides on the service side.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "$GO_CORPUS" "$GO_WIZARD" "${BASH_SOURCE[0]}" "$GO_ROOT/etc/go/known-defects.json"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

ZIP="$GO_OUT/regcf-deployable.zip"
LOG="$GO_OUT/p7-mcp.txt"
: >"$LOG"

# --- 1. the local half, which always runs ------------------------------------
command -v zip >/dev/null 2>&1 || go_skip "zip is not on PATH; the deployable surface is a zip of regcf.l4 + regcf-wizard.l4 (PROJECTIONS.md §0 row 5)"
rm -f "$ZIP"
(cd "$(dirname "$GO_CORPUS")" && zip -q -r "$ZIP" "$(basename "$GO_CORPUS")" "$(basename "$GO_WIZARD")") >>"$LOG" 2>&1
[[ -f "$ZIP" ]] || go_broken "zip reported success but produced no $ZIP"
echo "built deployable surface: $ZIP ($(wc -c <"$ZIP" | tr -d ' ') bytes)" | tee -a "$LOG"

# --- 2. the fence -------------------------------------------------------------
URL="${JL4_GO_SERVICE_URL:-}"
if [[ -z "$URL" ]]; then
  go_receipt --status SKIPPED \
    --reason "JL4_GO_SERVICE_URL is unset, so no jl4-service was contacted and no deployment was made. The deployable zip was still built and hashed. Set JL4_GO_SERVICE_URL to a LOOPBACK service (./dev-start.sh brings one up on 8080) to exercise the deployment half." \
    --artifact "$ZIP" --artifact "$LOG"
  if [[ "${L4_GO_REQUIRED:-0}" == "1" ]]; then
    echo "::error::p7-mcp SKIPPED while L4_GO_REQUIRED=1 — no JL4_GO_SERVICE_URL" >&2
    exit "$GO_EXIT_SKIPPED_REQUIRED"
  fi
  exit "$GO_EXIT_CLEAN"
fi

HOST="$(echo "$URL" | sed -E 's#^[a-zA-Z]+://##; s#[:/].*$##')"
case "$HOST" in
  localhost | 127.0.0.1 | ::1 | 0.0.0.0) ;;
  *)
    cat >&2 <<EOF
GATE HG2: REFUSED — JL4_GO_SERVICE_URL points at '$HOST', which is not loopback.

Deploying to a host other people can reach is outward-facing, and SPEC.md §7.3
puts ANYTHING outward-facing behind HG2 (Meng's go). This leg will post to a
loopback service and to nothing else.

If a non-loopback deployment is genuinely wanted, it is HG2's subject and needs
its own signature — not an environment variable.
EOF
    go_receipt --status SKIPPED \
      --reason "refused to deploy to non-loopback host '$HOST'; an outward-facing deployment is HG2's subject (SPEC.md §7.3), not an environment variable's" \
      --artifact "$ZIP" --artifact "$LOG"
    exit "$GO_EXIT_GATE"
    ;;
esac

command -v curl >/dev/null 2>&1 || go_skip "curl is not on PATH; the deployment route is POST /deployments (jl4-service/src/Application.hs)"

# --- 3. health, then deploy ---------------------------------------------------
set +e
curl -sS --max-time 5 "$URL/health" >>"$LOG" 2>&1
HEALTH_RC=$?
set -e
if [[ $HEALTH_RC -ne 0 ]]; then
  go_receipt --status SKIPPED \
    --reason "no jl4-service answered at $URL (curl exit $HEALTH_RC). The deployable zip was built and hashed; nothing was deployed." \
    --artifact "$ZIP" --artifact "$LOG"
  if [[ "${L4_GO_REQUIRED:-0}" == "1" ]]; then exit "$GO_EXIT_SKIPPED_REQUIRED"; fi
  exit "$GO_EXIT_CLEAN"
fi

DEPLOY_ID="regcf-$GO_RUNID"
RESP="$GO_OUT/p7-mcp.deploy.json"
set +e
curl -sS --max-time 30 -o "$RESP" -w '%{http_code}' \
  -X POST "$URL/deployments" -F "id=$DEPLOY_ID" -F "sources=@$ZIP" >"$GO_OUT/p7-mcp.httpcode" 2>>"$LOG"
CURL_RC=$?
set -e
CODE="$(cat "$GO_OUT/p7-mcp.httpcode" 2>/dev/null || echo 000)"
echo "POST $URL/deployments id=$DEPLOY_ID → HTTP $CODE (curl exit $CURL_RC)" | tee -a "$LOG"

if [[ $CURL_RC -ne 0 || ! "$CODE" =~ ^2 ]]; then
  go_receipt --status DEGRADED \
    --reason "POST $URL/deployments returned HTTP $CODE (curl exit $CURL_RC); see $LOG" \
    --artifact "$ZIP" --artifact "$LOG" $([[ -f "$RESP" ]] && echo --artifact "$RESP")
  exit "$GO_EXIT_FINDING"
fi

MCP="$GO_OUT/p7-mcp.tools.json"
set +e
curl -sS --max-time 15 "$URL/deployments/$DEPLOY_ID/.mcp" -o "$MCP" >>"$LOG" 2>&1
MCP_RC=$?
set -e

TOOLS=0
if [[ -f "$MCP" ]]; then
  TOOLS=$(node -e '
    const fs = require("node:fs");
    let j; try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch { process.stdout.write("0"); process.exit(0); }
    const t = j.tools || j.result?.tools || [];
    process.stdout.write(String(Array.isArray(t) ? t.length : 0));
  ' "$MCP")
fi

if [[ $MCP_RC -ne 0 || "$TOOLS" -eq 0 ]]; then
  go_receipt --status DEGRADED \
    --reason "the deployment was accepted (HTTP $CODE) but the .mcp endpoint returned no tool list (curl exit $MCP_RC, $TOOLS tools). regcf.l4 carries ZERO @export annotations by design; the exports live in regcf-wizard.l4, so a zero-tool list may mean the wizard module did not deploy." \
    --artifact "$ZIP" --artifact "$LOG" $([[ -f "$MCP" ]] && echo --artifact "$MCP")
  exit "$GO_EXIT_FINDING"
fi

go_receipt --status PASS \
  --oracle-cmd "POST $URL/deployments (loopback) → HTTP 2xx, then GET /deployments/$DEPLOY_ID/.mcp → a non-empty tool list" \
  --oracle-exit 0 \
  --oracle-class execution \
  --oracle-because "the module was served by a running jl4-service and the service enumerated $TOOLS callable tools from it; that is the module executing as an MCP surface, not merely parsing" \
  --artifact "$ZIP" --artifact "$MCP" --artifact "$LOG" \
  --metric "deployment_id=$DEPLOY_ID" --metric "tools=$TOOLS" --metric "http=$CODE" \
  --note "loopback only; a non-loopback deployment is refused as HG2's subject"
