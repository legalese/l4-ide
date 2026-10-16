# cloud-sessions-spec — post-mortem

l4-ide · branch `thomasgorissen/cloud-sessions-spec` · base `main` ·
[PR #506](https://github.com/legalese/l4-ide/pull/506) · 2026-09-28

## What was built

The cloud-sessions spec, the implementation tracker (§15), the cross-repo
contracts (§15.5), and this post-mortem folder. The PR is re-synced with the
live tracker and all post-mortems once the implementation items are done.

## Spec sections covered, and deviations (with reasons)

All of it; docs only. The Sessions API and Terraform live in
`jl4-auth-proxy/cloud-sessions/` instead of a new repo, so no GitHub repo had
to be created without approval.

## Checks run

`npx prettier --check` on the spec and post-mortems. CI on #506.

## Problems and how they were solved

- Implementers built both sides of each interface in parallel, so routes,
  error codes, headers and file formats were fixed up front in §15.5.
- The Sessions API mirrored the protocol package before it existed. It was
  aligned afterwards (jl4-auth-proxy#8, commit `cf1ab7f`).

## Open questions and follow-ups for later items

Collected from the item post-mortems:

- Deploy-time: create `/efs/agent-activity` (owner `1000:992`, mode `2775`);
  Fargate vCPU quota; one-time file-system root ownership; `FOLDER_KEY`; repo
  secret `CLOUD_SESSIONS_AGENT_IMAGE_ROLE_ARN` for the image workflow.
- Gates P6 (WorkOS `last_used_at`, rate limits, JWT claims) and P7 (function
  URL body limits, chunked pushes) still need live runs.
- Nothing has run end to end on AWS or in a live VS Code yet; the harness ran
  locally against a real `jl4-lsp` and a scripted ai-proxy.
- Existing hole outside this project: ai-proxy `DELETE /v1/conversations/{id}`
  is org-wide rather than per creator.
- Optional context field on `message` (active file, mentions) needs a
  protocol and Sessions API change.
- Stacked PRs into non-main bases get no CI in l4-ide; CI runs as the stacks
  land on `main`.

## Where a reviewer should start

§3 (architecture), §4.6 (isolation invariants), §15 (tracker), then the
post-mortems in dependency order.
