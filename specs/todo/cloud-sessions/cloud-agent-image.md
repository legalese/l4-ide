# cloud-agent-image — post-mortem

l4-ide · branch `thomasgorissen/cloud-agent-image` · base `cloud-agent-mcp` · [PR #516](https://github.com/legalese/l4-ide/pull/516) · 2026-09-28

## What was built

- `ts-apps/cloud-agent/docker/Dockerfile`: `node:24-trixie-slim` + git,
  tini, ca-certificates, libgmp10, libffi8, zlib1g; `/app/bin/jl4-lsp`,
  `/app/cloud-agent.cjs`, `USER 1000:1000`, entry point
  `/usr/bin/tini -- /app/entrypoint`; `.dockerignore` admits only those inputs.
- `docker/entrypoint.sh`: ignores arguments; validates `SESSION_ID`,
  `AGENT_KEY`, the three https URLs and `LOG_LEVEL`; keeps
  `ECS_CONTAINER_METADATA_URI_V4` only for `http://169.254.170.2/v4/…`;
  unsets everything else; `HOME=/home/agent`, fixed `PATH`; global git
  config; `exec /usr/local/bin/node /app/cloud-agent.cjs`. Exit 64, values
  never echoed.
- `docker/smoke.sh`: offline image checks (contents, `ldd`, bad env → 64, a
  start with the task's runtime flags and no network parks cleanly).
- `.github/workflows/cloud-agent-image.yml`: arm64 `jl4-lsp` (main-tag steps
  and cache key) → bundle + tests → `buildx` arm64 on `ubuntu-24.04-arm` →
  smoke → OIDC (`secrets.CLOUD_SESSIONS_AGENT_IMAGE_ROLE_ARN`) → push
  `legalese-cloud-agent:<sha>` (skip if the immutable tag exists) → digest
  `sha256:<hex>` → SSM `/cloud-sessions/<env>/image-digest`, previous value
  and rollback command in the summary.
- `test/entrypoint.test.ts`: 11 tests on a path-rewritten copy of the script.

## Spec sections covered, and deviations (with reasons)

§5.1 (entry point, env allow-list), §5.3, §5.4 step 1, §14. Deviations:

- Smoke test is offline (a start that parks), not a live session: no AWS
  resources exist and the CI role can't start tasks.
- `jl4-lsp` is built in this workflow (`main-tag.yml` is manual-only, so its
  artifacts aren't reliably there); same cache key.
- Pushes to `main` publish and roll out at once; `publish: false` for a dry run.
- zstd vs SOCI (§5.3) left open; buildx defaults.
- Also allowed through: the Fargate task-metadata URI (for the lease's task
  id), pattern-checked.

## Checks run

`npm ci`, `build`, `lint`, `format:check`, `check`, `test` — pass locally (91
tests). `actionlint` 1.7.7 (+ shellcheck on `run:` blocks), `shellcheck`
0.10.0 on both scripts, `hadolint` 2.15.1 — clean (DL3008 ignored with a
reason). **No Docker here:** the image was never built or smoke-tested; the
workflow wasn't run (per the task). No PR CI for stacked PRs.

## Problems and how they were solved

- macOS bash 3.2 regex rejected `{8,512}` (bound > 255, `RE_DUP_MAX`); the
  key is now `^sk_[A-Za-z0-9_-]+$` plus a length check.
- A read-only root and a possibly root-owned tmpfs `HOME` would make
  `git config --global` fatal; it's best effort now (the harness passes the
  same settings with `git -c`).

## Open questions and follow-ups for later items

- Deploy step: create the repository secret
  `CLOUD_SESSIONS_AGENT_IMAGE_ROLE_ARN` (not done; no repo-settings changes).
- First real build may surface missing shared libraries for `jl4-lsp`; the
  smoke test's `ldd` check fails the job before anything is pushed.
- Sessions API: the task definition's tmpfs entries set no mode. User 1000
  needs to write `/home/agent`; tmpfs normally mounts 1777 (P0 ran user 1000
  with tmpfs), but if not, add `mountOptions: ["mode=1777"]`. The harness
  still works without it (git config is best effort).

## Where a reviewer should start

`docker/entrypoint.sh`, then the workflow's `image` job, then `docker/smoke.sh`.
