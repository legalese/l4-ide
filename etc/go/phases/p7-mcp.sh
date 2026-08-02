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
#
# THREE THINGS HERE WERE WRONG UNTIL 2026-08-02, EACH MEASURED AGAINST A REAL
# LOOPBACK jl4-service, AND EACH IS NOW STATED AS AN INVARIANT:
#
#   1. The fence extracted the host with `sed 's#[:/].*$##'`, which truncates at
#      the first colon. `http://127.0.0.1:8080@REALHOST/` therefore read as host
#      `127.0.0.1` and passed the allow-list, while curl parsed `127.0.0.1:8080`
#      as USERINFO and connected to REALHOST. The same parser REFUSED the
#      genuine loopback spellings `[::1]` and `LOCALHOST`. The URL is now parsed
#      by node's WHATWG URL parser, and userinfo is refused outright.
#   2. The tool list was read with a GET. `jl4-service/src/Application.hs:82`
#      declares `.mcp` as `Post … :<|> Get …` and :376 wires the Get alternative
#      to `throwError err405` — GET /.mcp is 405 BY DESIGN (MCP Streamable HTTP
#      is POST-only). curl was called without `--fail`, so the 405 left exit 0
#      and the leg fell through to a zero-tool branch whose recorded reason
#      blamed the corpus. The documented `execution` PASS was unreachable.
#      tools/list is now a JSON-RPC POST and its HTTP code is checked.
#   3. The tool list was read immediately after the POST returned 202
#      (`status: compiling`). Compilation is async, and a tools/list issued in
#      that window returns HTTP 200 carrying only the service's OWN generic
#      tools — zero corpus exports — so a method-only fix would have printed an
#      `execution` PASS over a tool list containing none of the module. The leg
#      now polls GET /deployments/{id} to `ready`, and requires the corpus tool
#      count to equal the function count the deployment itself reports.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "$GO_S_CORPUS" ${GO_S_WIZARD:+"$GO_S_WIZARD"} "${BASH_SOURCE[0]}" "$GO_S_KNOWN_DEFECTS"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

ZIP="$GO_OUT/$GO_S_ID-deployable.zip"
LOG="$GO_OUT/p7-mcp.txt"
: >"$LOG"

# The subject's module set: the corpus proper, plus the wizard companion when
# the sidecar declares one. Both go into the deployable zip.
declare -a MODULES=("$GO_S_CORPUS")
[[ -n "${GO_S_WIZARD:-}" ]] && MODULES+=("$GO_S_WIZARD")

# Bounds on a LOOPBACK service: how long an accepted deployment may take to
# finish compiling, and how long any single HTTP call may take.
READY_TIMEOUT_S=120
HTTP_TIMEOUT_S=15

# The tools jl4-service serves from its own file-browsing surface for EVERY
# deployment, whatever the module exports (jl4-service/src/McpServer.hs:309-364,
# dispatched at :440-443). They are not evidence about the corpus, so they are
# subtracted before the floor below is applied. This list is a PIN, and it is
# self-policing: if the service grows another generic tool, the corpus count
# computed here exceeds the deployment's own function count and the leg reports
# DEGRADED naming both numbers rather than silently over-counting.
SERVICE_OWN_TOOLS="list_files read_file search_identifier search_text"

# --- 1. the local half, which always runs ------------------------------------
command -v zip >/dev/null 2>&1 || go_skip "zip is not on PATH; the deployable surface is a zip of the subject's module set (${MODULES[*]##*/})"
rm -f "$ZIP"
(cd "$(dirname "$GO_S_CORPUS")" && zip -q -r "$ZIP" "${MODULES[@]##*/}") >>"$LOG" 2>&1
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

# Parse with a real URL parser. An ad-hoc host extraction is wrong in BOTH
# directions: it let userinfo smuggle a non-loopback host past the allow-list,
# and it refused `[::1]` and `LOCALHOST`, which are loopback.
HOSTINFO="$(node -e '
  const raw = process.argv[1];
  let u;
  try { u = new URL(raw); } catch { process.stdout.write("MALFORMED\t" + raw); process.exit(0); }
  // Userinfo is the bypass: curl reads `http://127.0.0.1:8080@REALHOST/` as
  // credentials `127.0.0.1:8080` for host REALHOST. A fence that reads userinfo
  // as the host is not a fence, so the shape is refused outright.
  if (u.username || u.password) { process.stdout.write("USERINFO\t" + u.hostname.toLowerCase()); process.exit(0); }
  if (u.protocol !== "http:" && u.protocol !== "https:") { process.stdout.write("SCHEME\t" + u.protocol); process.exit(0); }
  process.stdout.write("OK\t" + u.hostname.toLowerCase());
' "$URL")"
HOST_KIND="${HOSTINFO%%$'\t'*}"
HOST="${HOSTINFO#*$'\t'}"

LOOPBACK=0
if [[ "$HOST_KIND" == "OK" ]]; then
  case "$HOST" in
    localhost | 127.0.0.1 | ::1 | "[::1]" | 0.0.0.0) LOOPBACK=1 ;;
  esac
fi

if [[ $LOOPBACK -ne 1 ]]; then
  case "$HOST_KIND" in
    USERINFO) WHY="carries userinfo (a user or password component). curl reads that as credentials and connects to '$HOST', so the host an ad-hoc parser sees is not the host the request reaches." ;;
    MALFORMED) WHY="is not a parseable URL." ;;
    SCHEME) WHY="uses scheme '$HOST', not http or https." ;;
    *) WHY="points at host '$HOST', which is not loopback. The spellings this leg accepts are localhost, 127.0.0.1, ::1, [::1] and 0.0.0.0." ;;
  esac
  cat >&2 <<EOF
GATE HG2: REFUSED — JL4_GO_SERVICE_URL $WHY

Deploying to a host other people can reach is outward-facing, and SPEC.md §7.3
puts ANYTHING outward-facing behind HG2 (Meng's go). This leg will post to a
loopback service and to nothing else.

If a non-loopback deployment is genuinely wanted, it is HG2's subject and needs
its own signature — not an environment variable.
EOF
  go_receipt --status SKIPPED \
    --reason "refused to deploy: JL4_GO_SERVICE_URL $WHY An outward-facing deployment is HG2's subject (SPEC.md §7.3), not an environment variable's." \
    --artifact "$ZIP" --artifact "$LOG"
  exit "$GO_EXIT_GATE"
fi

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

DEPLOY_ID="$GO_S_ID-$GO_RUNID"
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

# --- 4. readiness ------------------------------------------------------------
# POST /deployments answers 202 with status "compiling"; compilation is async.
# A tool list read before the deployment is `ready` comes back HTTP 200 carrying
# only the service's own generic tools — a green-looking answer that says
# nothing about the module. So: poll, and record what was polled.
STATUS="$GO_OUT/p7-mcp.status.json"
DEPLOY_STATE="unknown"
FUNCTIONS=0
WAITED=0
while [[ $WAITED -lt $READY_TIMEOUT_S ]]; do
  set +e
  curl -sS --max-time "$HTTP_TIMEOUT_S" -o "$STATUS" -w '%{http_code}' \
    "$URL/deployments/$DEPLOY_ID" >"$GO_OUT/p7-mcp.status.httpcode" 2>>"$LOG"
  ST_RC=$?
  set -e
  ST_CODE="$(cat "$GO_OUT/p7-mcp.status.httpcode" 2>/dev/null || echo 000)"
  if [[ $ST_RC -eq 0 && "$ST_CODE" =~ ^2 && -f "$STATUS" ]]; then
    read -r DEPLOY_STATE FUNCTIONS <<<"$(node -e '
      const fs = require("node:fs");
      let j;
      try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
      catch { process.stdout.write("unparseable 0"); process.exit(0); }
      const fns = j.metadata && Array.isArray(j.metadata.functions) ? j.metadata.functions.length : 0;
      process.stdout.write(String(j.status ?? "unknown") + " " + String(fns));
    ' "$STATUS")"
  else
    DEPLOY_STATE="unreachable"
  fi
  echo "GET $URL/deployments/$DEPLOY_ID → HTTP $ST_CODE state=$DEPLOY_STATE functions=$FUNCTIONS (waited ${WAITED}s)" >>"$LOG"
  [[ "$DEPLOY_STATE" == "ready" || "$DEPLOY_STATE" == "failed" ]] && break
  sleep 1
  WAITED=$((WAITED + 1))
done
echo "deployment $DEPLOY_ID state=$DEPLOY_STATE functions=$FUNCTIONS after ${WAITED}s" | tee -a "$LOG"

if [[ "$DEPLOY_STATE" != "ready" ]]; then
  go_receipt --status DEGRADED \
    --reason "the deployment was accepted (HTTP $CODE) but did not become ready: GET $URL/deployments/$DEPLOY_ID reported state '$DEPLOY_STATE' after ${WAITED}s (limit ${READY_TIMEOUT_S}s). No tool list was read, because a tool list read before the deployment is ready enumerates only the service's own generic tools and is not evidence about the module. See $LOG." \
    --artifact "$ZIP" --artifact "$LOG" $([[ -f "$STATUS" ]] && echo --artifact "$STATUS") \
    --metric "deployment_id=$DEPLOY_ID" --metric "deploy_state=$DEPLOY_STATE" --metric "waited_s=$WAITED"
  exit "$GO_EXIT_FINDING"
fi

# --- 5. the tool list ---------------------------------------------------------
# JSON-RPC over POST. GET /deployments/{id}/.mcp is 405 by design: Application.hs
# :82 declares `Post … :<|> Get …` and :376 wires the Get to `throwError err405`.
MCP="$GO_OUT/p7-mcp.tools.json"
set +e
curl -sS --max-time "$HTTP_TIMEOUT_S" -o "$MCP" -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
  "$URL/deployments/$DEPLOY_ID/.mcp" >"$GO_OUT/p7-mcp.mcp.httpcode" 2>>"$LOG"
MCP_RC=$?
set -e
MCP_CODE="$(cat "$GO_OUT/p7-mcp.mcp.httpcode" 2>/dev/null || echo 000)"
echo "POST $URL/deployments/$DEPLOY_ID/.mcp tools/list → HTTP $MCP_CODE (curl exit $MCP_RC)" | tee -a "$LOG"

if [[ $MCP_RC -ne 0 || ! "$MCP_CODE" =~ ^2 ]]; then
  go_receipt --status DEGRADED \
    --reason "the deployment is ready, but POST $URL/deployments/$DEPLOY_ID/.mcp (JSON-RPC tools/list) returned HTTP $MCP_CODE (curl exit $MCP_RC). That is a transport failure between this leg and the service, not a finding about the corpus. See $LOG." \
    --artifact "$ZIP" --artifact "$LOG" $([[ -f "$MCP" ]] && echo --artifact "$MCP") \
    --metric "deployment_id=$DEPLOY_ID" --metric "functions=$FUNCTIONS" --metric "mcp_http=$MCP_CODE"
  exit "$GO_EXIT_FINDING"
fi

TOOLS=0
CORPUS_TOOLS=0
TOOL_NAMES=""
if [[ -f "$MCP" ]]; then
  read -r TOOLS CORPUS_TOOLS TOOL_NAMES <<<"$(node -e '
    const fs = require("node:fs");
    let j;
    try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
    catch { process.stdout.write("0 0 (unparseable)"); process.exit(0); }
    const own = new Set(process.argv[2].split(/\s+/).filter(Boolean));
    const t = j.result?.tools ?? j.tools ?? [];
    const names = Array.isArray(t) ? t.map((x) => String(x?.name ?? "")) : [];
    const corpus = names.filter((n) => !own.has(n));
    process.stdout.write(`${names.length} ${corpus.length} ${corpus.join(",") || "(none)"}`);
  ' "$MCP" "$SERVICE_OWN_TOOLS")"
fi
echo "tools/list → $TOOLS tool(s), $CORPUS_TOOLS from the module: $TOOL_NAMES" | tee -a "$LOG"

# The non-vacuity floor. "$TOOLS -gt 0" is satisfied by the service's own four
# generic tools over an EMPTY deployment, so it licenses nothing. The claim this
# leg wants to make is that the MODULE is served, and the deployment itself says
# how many functions it compiled — so that is the number the tool list must meet.
if [[ "$FUNCTIONS" -lt 1 || "$CORPUS_TOOLS" -ne "$FUNCTIONS" ]]; then
  go_receipt --status DEGRADED \
    --reason "the deployment is ready and .mcp answered, but the module's tools are not all there: the deployment reports $FUNCTIONS compiled function(s) while tools/list enumerates $TOOLS tool(s), of which $CORPUS_TOOLS are not jl4-service's own generic file-browsing tools ($SERVICE_OWN_TOOLS). Corpus tools found: $TOOL_NAMES. Zero here usually means the module carrying the subject's @export surface did not deploy — see the subject's NOTES.md for which module that is. A non-zero mismatch means the service's generic tool set has moved and the pin in this script is stale." \
    --artifact "$ZIP" --artifact "$LOG" --artifact "$MCP" $([[ -f "$STATUS" ]] && echo --artifact "$STATUS") \
    --metric "deployment_id=$DEPLOY_ID" --metric "functions=$FUNCTIONS" \
    --metric "tools=$TOOLS" --metric "corpus_tools=$CORPUS_TOOLS"
  exit "$GO_EXIT_FINDING"
fi

go_receipt --status PASS \
  --oracle-cmd "POST $URL/deployments (loopback) → HTTP 2xx; poll GET /deployments/$DEPLOY_ID to state=ready; POST /deployments/$DEPLOY_ID/.mcp {\"method\":\"tools/list\"} → a tool list whose non-generic entries number exactly the deployment's own compiled-function count" \
  --oracle-exit 0 \
  --oracle-class execution \
  --oracle-because "the module was compiled by a running jl4-service (state=ready) and the service enumerated $CORPUS_TOOLS callable tools from it, matching the $FUNCTIONS function(s) the deployment reports; that is the module executing as an MCP surface, not merely parsing, and the count excludes the service's own generic file-browsing tools so it cannot be satisfied vacuously" \
  --artifact "$ZIP" --artifact "$MCP" --artifact "$STATUS" --artifact "$LOG" \
  --metric "deployment_id=$DEPLOY_ID" --metric "tools=$TOOLS" \
  --metric "corpus_tools=$CORPUS_TOOLS" --metric "functions=$FUNCTIONS" \
  --metric "http=$CODE" --metric "ready_after_s=$WAITED" \
  --note "loopback only; a non-loopback deployment is refused as HG2's subject"
