#!/bin/bash
# Entry point of the legalese-cloud-agent image (cloud-sessions spec §5.1,
# §5.4 step 1). ECS runs it as `/usr/bin/tini -- /app/entrypoint`.
#
# RunTask can override a container's command and environment, but not its
# entry point. So this script:
#   - ignores its arguments;
#   - accepts only the static task-definition variables (AI_PROXY_URL,
#     MCP_URL, AUTH_URL, LOG_LEVEL), SESSION_ID (a ULID) and AGENT_KEY
#     (sk_…), each validated by pattern, plus the Fargate task-metadata
#     URI; every other variable is dropped;
#   - sets HOME, writes the git identity and S3 Files settings;
#   - execs the harness with a fixed interpreter and bundle path.
# Paths are fixed here on purpose: nothing in the environment can change
# what runs.
set -euo pipefail

fail() {
  # Never echo values: AGENT_KEY must not reach the logs.
  echo "entrypoint: invalid or missing $1" >&2
  exit 64
}

readonly ULID_RE='^[0-7][0-9A-HJKMNP-TV-Z]{25}$'
# `sk_` + 8..512 of [A-Za-z0-9_-]; the length is checked separately because
# some regex engines cap bounds at 255.
readonly KEY_RE='^sk_[A-Za-z0-9_-]+$'
readonly URL_RE='^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$'
readonly META_RE='^http://169\.254\.170\.2/v4/[A-Za-z0-9-]+$'

[[ "${SESSION_ID:-}" =~ $ULID_RE ]] || fail SESSION_ID
[[ "${AGENT_KEY:-}" =~ $KEY_RE ]] || fail AGENT_KEY
((${#AGENT_KEY} >= 11 && ${#AGENT_KEY} <= 515)) || fail AGENT_KEY
[[ "${AI_PROXY_URL:-}" =~ $URL_RE ]] || fail AI_PROXY_URL
[[ "${MCP_URL:-}" =~ $URL_RE ]] || fail MCP_URL
[[ "${AUTH_URL:-}" =~ $URL_RE ]] || fail AUTH_URL
LOG_LEVEL="${LOG_LEVEL:-info}"
case "$LOG_LEVEL" in
  error | warn | info | debug) ;;
  *) fail LOG_LEVEL ;;
esac
META=""
if [[ "${ECS_CONTAINER_METADATA_URI_V4:-}" =~ $META_RE ]]; then
  META="$ECS_CONTAINER_METADATA_URI_V4"
fi

# Drop every variable that isn't on the list, then set the fixed ones.
readonly KEEP=" SESSION_ID AGENT_KEY AI_PROXY_URL MCP_URL AUTH_URL LOG_LEVEL "
while IFS= read -r name; do
  case "$KEEP" in
    *" $name "*) ;;
    *) unset "$name" 2>/dev/null || true ;;
  esac
done < <(compgen -e)

export HOME=/home/agent
export PATH=/usr/local/bin:/usr/bin:/bin
export LANG=C.UTF-8
export NODE_ENV=production
export SESSION_ID AGENT_KEY AI_PROXY_URL MCP_URL AUTH_URL LOG_LEVEL
if [[ -n "$META" ]]; then
  export ECS_CONTAINER_METADATA_URI_V4="$META"
fi

# HOME is a tmpfs; the root filesystem is read-only. The harness passes
# the same settings with `git -c` on every call, so a HOME that can't be
# written only costs this belt-and-braces copy.
if mkdir -p "$HOME" 2>/dev/null && [[ -w "$HOME" ]]; then
  git config --global user.name "Legalese AI"
  git config --global user.email "agent@legalese.cloud"
  git config --global core.createObject rename
  git config --global gc.auto 0
  git config --global core.hooksPath /dev/null
  git config --global safe.directory "/workspace/sessions/$SESSION_ID/repo"
else
  echo "entrypoint: HOME is not writable; skipping the global git config" >&2
fi

exec /usr/local/bin/node /app/cloud-agent.cjs
