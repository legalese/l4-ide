# Cloud Sessions — headless Legalese AI on per-session cloud compute

Run the Legalese AI harness headless in the cloud: one short-lived Fargate task
per running session, working directly on the user's files in S3 through Amazon
S3 Files. The VS Code extension starts, watches and drives cloud sessions next
to its local session, and syncs a session's files with git.

**Status:** draft, 2026-09-28. Nothing is built beyond the prototypes in §2.
Start with the proof-of-concept gates in §16.
**Scope:** `l4-ide` (agent core, cloud runner, extension, webview, image
build), `jl4-auth-proxy` (access-token route, agent key chains), `ai-proxy`
(user-scoped agent keys), and new infrastructure `cloud-sessions` (Terraform
plus one Lambda) as a second Terraform root in `jl4-auth-proxy/cloud-sessions/`,
following the `ai-proxy` Terraform pattern. It can move to its own repo later.
**Client requirements:** VS Code 1.106 or newer (raised from 1.95; §9.3) and
`git` installed.
**Audience:** implementers familiar with the Legalese Cloud request path
(WorkOS → `jl4-auth-proxy` / `ai-proxy`) and with the Legalese AI harness in
`ts-apps/vscode/src/ai/`.
**Background reading:** `jl4-auth-proxy/ARCHITECTURE.md` (auth model; agent
keys around lines 195–244), `ai-proxy/ARCHITECTURE.md` (server-held
conversations, client-declared tools), [AI_CHAT_PLAN.md](../done/AI_CHAT_PLAN.md).

---

## 1. Goals and non-goals

**Goals**

- **G1** The harness that runs in the extension also runs headless in the
  cloud, and talks to `ai-proxy` and MCP the same way.
- **G2** Cloud sessions appear in the Legalese AI conversation history next to
  local chats, marked with a cloud icon. From the sidebar the user can start
  one, watch it, send messages, answer questions and approvals, and stop it.
- **G3** Starting a cloud session uploads the referenced artifacts: the active
  L4 file with its transitive imports, @-mentioned files, and prompt
  attachments. The user's HTTP MCP servers are passed in too (§6.4).
- **G4** The agent works directly on the user's files on the mount (there is
  no working copy) and commits after every **turn** — one user prompt and all
  the work the agent does for it. Any turn can be rolled back from the chat
  (§9.4).
- **G5** After 10 minutes without activity the compute stops. The next user
  action starts new compute on the same files.
- **G6** An active agent keeps working without the user for up to a day.
- **G7** A session's files can be cloned and synced (pull and push) with git,
  from a button in the prompt field. The extension uses VS Code's built-in Git
  support rather than a git implementation of its own.
- **G8** No session can reach another user's files. Compute is never reused and
  keeps no residual data.
- **G9** Costs accrue only while sessions run. Nothing per user runs while idle.
- **G10** New harness images roll out without downtime and roll back by
  changing one parameter.
- **G11** User data is reachable only by the user (git and the Sessions API)
  and by that user's session compute. Operational logs are readable by a
  superuser.

**Non-goals for v1**

- stdio MCP servers in cloud sessions. They are programs on the user's machine
  (§6.4).
- Sharing a session with other users or organisations.
- A web client (chat.legalese.cloud) for cloud sessions.
- Protection against AWS account administrators (customer-managed KMS keys,
  SCP fences) — see §18, deferred hardening.
- Git LFS. Files over the limits are declined when the session starts (§10);
  LFS is a later addition (§18).
- Rolling back turns in local chats. The extension doesn't commit to the
  user's own repositories.

## 2. Existing work to build on

| What                                                                                                                             | Where                                                                                                        | State                                                          | Use                                                                  |
| -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------- | -------------------------------------------------------------------- |
| Agent loop: `ChatService`, `AiProxyClient`, `ToolDispatcher`, tools                                                              | `ts-apps/vscode/src/ai/`                                                                                     | Production, local only. About a dozen modules import `vscode`. | Extract into a VS Code-free core (§11).                              |
| Cloud-turn prototype: second Send button, L4 import-tree bundle, SSE-to-`ChatServiceEvent` mapping, per-turn key mint and revoke | l4-ide branch `thomasgorissen/ai-cloud-agent` (`cloud-agent-client.ts`, `l4-bundle.ts`, `chat-input.svelte`) | Unmerged. Its server (`agent.legalese.cloud`) was never built. | Reuse bundle gathering (fix path flattening, §10) and the UI pieces. |
| Agent keys: `POST /auth/agent-token` (WorkOS user-scoped keys, 60–600 s) and `/auth/agent-token/revoke`                          | `jl4-auth-proxy/src/auth/routes.ts:775-889`, `src/auth/agent-keys.ts`                                        | Deployed, no callers. `revoke` doesn't check key ownership.    | Extend into key chains (§6).                                         |
| ai-proxy accepting user-scoped keys                                                                                              | ai-proxy branch `thomasgorissen/ai-cloud-agent` (`src/api-key-owner.ts`)                                     | Unmerged. `main` rejects these keys (`src/auth.ts:214`).       | Merge, and file conversations under the key's owner (§15).           |
| Server-held conversations, `GET /v1/conversations/{id}`                                                                          | ai-proxy                                                                                                     | Deployed                                                       | Conversation continuity across compute restarts.                     |
| Fargate service, ECR, EFS access point, GitHub OIDC deploy role                                                                  | `ai-proxy/terraform/{ecs,ecr,github-actions}.tf`                                                             | Deployed                                                       | Template for the cluster, image repository and CI role.              |
| Linux `jl4-lsp` binaries (x64, arm64)                                                                                            | `.github/workflows/main-tag.yml:159-346` (VSIX `bin/linux-*`)                                                | Built per release. Dynamically linked; need glibc ≥ 2.39.      | Image input (§14).                                                   |

## 3. Architecture

```
 VS Code (local)                                    AWS us-west-2
 Legalese AI sidebar
   local ChatService (unchanged)
   Cloud sessions: list · start · watch · send       Sessions API  (one Lambda, function URL, in the VPC)
     └─ HTTPS + 5-min WorkOS JWT ───────────────────►  • sessions, commands, events (files on the mount)
   Clone/Sync via VS Code Git ───── same endpoint ──►  • git smart-HTTP from scratch repos (§9)
   mints agent key chains ──► jl4-auth-proxy           • seed upload (pre-signed S3 → mount)
                                                       • RunTask / StopTask, per-user provisioning
                                                           │ mounts users/ (root access point)
 Fargate task — one per running session                   ▼
   headless harness + jl4-lsp ── /workspace = AP(user) ── S3 Files ⇄ s3://…/users/<folder>/
   └─ agent key (15 min, self-renewing while active) ──► ai.legalese.cloud, mcp.legalese.cloud
```

**Components**

- **Session task (§5).** One Fargate task per running session, running the
  harness and `jl4-lsp`. It mounts only its owner's folder, through a per-user
  access point.
- **Storage (§4).** One S3 bucket, one S3 Files file system over its `users/`
  prefix, one folder per user.
- **Sessions API (§7).** One Lambda. It is the only component that can reach
  every user's folder and start tasks. It runs no AI-driven or user-supplied
  code, and treats folder contents as hostile.
- **jl4-auth-proxy (§6).** Issues the extension's short-lived JWT and the agent
  key chains.
- **ai-proxy.** Same request path as today; additionally accepts agent keys.

**Deliberately absent**

- **No database.** Running sessions come from the ECS API and a lease file.
  Session metadata lives in `session.json` inside the user's folder. Key chains
  are stateless (§6.2).
- **No pub/sub service.** Events and commands are files on the mount, served
  by the Sessions API (§8).
- **No per-user IAM roles, no per-user Lambdas, no API Gateway, no separate
  orchestrator service.**

## 4. Storage and isolation

### 4.1 Bucket and file system

- Bucket `legalese-cloud-sessions-<env>` in us-west-2. Versioning on (S3 Files
  requires it), SSE-S3, Block Public Access, TLS-only bucket policy.
- Lifecycle rules:
  - noncurrent versions expire after 7 days — git rewrites `.git/index` on most
    commands, and each rewrite is a new object version;
  - expired delete markers are removed, incomplete multipart uploads aborted
    after 1 day;
  - `inbox/` objects expire after 1 day;
  - never transition `users/` to archive tiers: archived objects give I/O
    errors through the file system.
- One S3 Files file system linked to the prefix `users/`, with mount targets
  in the two private subnets of the existing VPC. The mount-target security
  group allows TCP 2049 from the task and Lambda security groups.
- S3 Files service role: trusted by `elasticfilesystem.amazonaws.com`, scoped
  by `aws:SourceAccount` and `aws:SourceArn`, with the bucket permissions from
  the S3 Files prerequisites.
- One-time setup: the file-system root is owned by `1000:1000`, mode `0700`, so
  the Sessions API (POSIX user 1000) can create user folders. Do it once
  through a temporary root-access mount (break-glass role).
- Access points are capped at 25,000 per file system (hard limit). v1 uses one
  file system; shard users across file systems before about 20,000 users.

### 4.2 Folder layout

```
s3://legalese-cloud-sessions-<env>/
  users/<folder>/                     access-point root for one user (uid/gid 1000, mode 0700)
    sessions/<sid>/
      session.json                    ownerUserId, title, created, lastActivity, conversationId,
                                      status, MCP servers (names and URLs only, no secrets)
      repo/                           git working tree + .git — only the harness runs git here
      attachments/                    files attached to prompts (not in git)
      state/
        lease.json                    liveness lease written by the running harness
        head.json                     current event segment and length (written by the harness)
        events/<n>.jsonl              append-only event log segments
        commands.seq                  highest command number issued (written by the Sessions API)
        commands/<n>.json             commands, one file each, numbered
        git/main.bundle               git bundle of main, rewritten after each commit
        git/incoming/<ulid>.bundle    commits pushed by clients, waiting to be merged
  inbox/<sid>/…                       pre-signed uploads, outside the file system, 1-day expiry
```

`<sid>` is a ULID generated by the Sessions API.

### 4.3 Folder names

`folder = hex(HMAC-SHA256(FOLDER_KEY, workosUserId))[0:32]` (128 bits).

- `FOLDER_KEY` is an SSM SecureString readable only by the Sessions API role.
- There is no mapping table. The Sessions API derives the folder from the
  verified user id on every request.
- Nobody browsing the bucket, S3 logs or the S3 Files lost+found directory can
  tell whose folder is whose without the key, and folder names can't be
  guessed.
- `session.json` records `ownerUserId`, so a folder can still be attributed
  during break-glass recovery.
- Rotating `FOLDER_KEY` means renaming every folder. Treat it as permanent.

### 4.4 Per-user access point and task definition

A session task can only mount the folder baked into its task definition. The
Sessions API provisions both on demand, and repeating it is harmless:

1. `family = "ls-" + folder`.
2. `DescribeTaskDefinition(family)`. If it exists and references the current
   image digest (§14), use it.
3. If the family doesn't exist:
   - create `/<folder>` through the root mount (owner `1000:1000`, mode
     `0700`);
   - create the access point: root directory `/<folder>`, creation permissions
     `1000:1000 0700`, enforced POSIX user `1000:1000`, idempotency token =
     folder. Access points are immutable.
4. `RegisterTaskDefinition(family, …)` with that access point and the current
   image digest (§5.1). If the family exists with an older image, reuse the
   access point ARN from it.

ECS is the registry: the access point ARN is read back from the task
definition. `RegisterTaskDefinition` is throttled at 1 per second sustained,
burst 20, so back off and retry. It runs on a user's first session and on
their first start after each image release.

### 4.5 Policies

**Task role `cloud-session-task`** (shared by all session tasks)

- `s3files:ClientMount` and `s3files:ClientWrite` on the file system, only when
  `s3files:AccessPointArn` is present.
- Nothing else: no S3, ECS, S3 Files describe/list, logs read or SSM.

**Task execution role `cloud-session-exec`**

- ECR pull, CloudWatch Logs write.

**File system policy** (limited to 20,000 characters, so keep it generic)

- Deny `s3files:ClientRootAccess` to everyone except the break-glass role.
- Deny mounts that don't go through an access point (`Null` condition on
  `s3files:AccessPointArn` — confirmed to work, §16).
- Deny the root access point to every principal except the Sessions API role
  and the break-glass role.

**Bucket policy**

- Deny object reads and writes under `users/` to every principal except the S3
  Files service role and the break-glass role.

**Sessions API role**

- Mount and write through the root access point.
- `s3files:CreateAccessPoint`, `s3files:TagResource`,
  `s3files:DescribeAccessPoints` on the file system.
- `ecs:RegisterTaskDefinition`, `DescribeTaskDefinition`, `RunTask`,
  `StopTask`, `ListTasks`, `DescribeTasks`, `TagResource`, limited to the
  cluster and `ls-*` families.
- `iam:PassRole` for the two shared task roles only, with
  `iam:PassedToService = ecs-tasks.amazonaws.com`.
- S3 read, write and delete on `inbox/*`.
- `ssm:GetParameter` for `FOLDER_KEY` and the image digest.

**ECS Exec**

- Never enabled. Deny `ecs:ExecuteCommand` on the cluster and require
  `ecs:enable-execute-command = false` on `RunTask`. It can't work with a
  read-only root filesystem anyway.

### 4.6 Isolation invariants

Each invariant gets a test in Phase 5.

- **I1** A session task can read and write only its owner's folder. Fargate
  mounts the access point from the task definition before the container starts.
- **I2** Nothing inside a task names another user's folder or access point.
  Tasks never receive folder names, access point IDs or `FOLDER_KEY`, and have
  no permission to discover them. (P1 verifies that the task metadata endpoint
  and `/proc/mounts` don't reveal the access point ID.)
- **I3** A task can't mount the file-system root, the root access point, or as
  root.
- **I4** A task has no S3 API access to user data.
- **I5** Compute is never reused. Each Fargate task runs on its own single-use
  microVM. `/tmp`, `/run` and `$HOME` are tmpfs and disappear with the task.
- **I6** Only the Sessions API reaches every folder, and only after verifying
  the caller's WorkOS JWT. It runs no AI-driven or user-supplied code, and
  treats everything in a user folder as hostile input (§7.2).
- **I7** Agent credentials are short-lived, have limited permissions, renew
  only while the agent is active, and stop after 24 hours (§6).
- **I8** There is no ECS Exec or SSH into tasks. Operators can read user data
  only through the audited break-glass role.

**Accepted risk:** the shared task role can mount any access point whose ID it
knows. I2 is the control; AWS doesn't document access point IDs as
unguessable. Per-user IAM roles would remove this risk, but were rejected
because of scale (10,000 roles per account).

### 4.7 Git on S3 Files

- S3 Files doesn't support hard links, so every repo sets
  `core.createObject=rename`.
- `gc.auto=0`; the harness runs `git gc` only when a session goes to sleep.
- Only the harness runs git on a session repo (§9). There is one writer.
- Never write under `users/` through the S3 API. On a conflict S3 wins, and
  the file-system version moves to a lost+found directory at the file-system
  root, where it is invisible through access points but kept and billed.
  Alarm on the `LostAndFoundFiles` metric.

## 5. Session task

### 5.1 Task definition (one family per user)

| Setting              | Value                                                                                                                                                                      |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Family               | `ls-<folder>`                                                                                                                                                              |
| Platform             | Fargate, Linux, ARM64, platform version LATEST (1.4.0)                                                                                                                     |
| Size                 | 1 vCPU / 3 GB. `jl4-lsp` reserves about 128 MB per runtime thread (`jl4-lsp/jl4-lsp.cabal:112-118`).                                                                       |
| Container `harness`  | image `…/legalese-cloud-agent@sha256:<digest>`; entry point `/usr/bin/tini -- /app/entrypoint`; user `1000:1000`; `readonlyRootFilesystem: true`; all capabilities dropped |
| tmpfs                | `/tmp` 512 MiB, `/home/agent` 256 MiB, `/run` 64 MiB                                                                                                                       |
| Volume `workspace`   | `s3filesVolumeConfiguration { fileSystemArn, accessPointArn }` mounted at `/workspace`                                                                                     |
| Environment (static) | `AI_PROXY_URL`, `MCP_URL`, `AUTH_URL`, `LOG_LEVEL`                                                                                                                         |
| Logs                 | `awslogs` → `/legalese/cloud-sessions/<env>`, stream prefix `ls`                                                                                                           |
| Roles                | task `cloud-session-task`, execution `cloud-session-exec`                                                                                                                  |
| Stop timeout         | 30 s                                                                                                                                                                       |

**`RunTask` parameters**

- Capacity provider `FARGATE` (Spot deferred).
- The existing public subnets with `assignPublicIp: ENABLED`, security group
  `cloud-session-task`.
- `startedBy = <sid>`, tag `session=<sid>`, `clientToken = <sid>-<wake>`.
- Container override environment: **only** `SESSION_ID` and `AGENT_KEY`
  (§6.2).

`RunTask` can override a container's `command` and environment, but not its
entry point. The entry point ignores arguments and drops every environment
variable except the static ones and `SESSION_ID` (a ULID) and `AGENT_KEY`
(`sk_…`), both validated by pattern. Neither the Sessions API nor anyone who
compromises it can change what runs or where it connects.

### 5.2 Network

- Tasks run in the existing public subnets with a public IPv4 address (about
  $0.005 per hour). They don't depend on the NAT instance.
- ECR layer pulls go through an S3 gateway endpoint (free; add it if missing).
- Task security group: no inbound rules. Outbound TCP 443 to anywhere, and TCP
  2049 to the mount-target security group.
- The Sessions API Lambda runs in the private subnets, because it must reach
  the mount targets. It uses the existing NAT instance for WorkOS JWKS, ECS and
  SSM calls. That NAT instance is a single t3.nano; add interface endpoints if
  it becomes a bottleneck.

### 5.3 Image

- Base `node:24-trixie-slim`. It has glibc 2.41; the `jl4-lsp` binaries are
  built on Ubuntu 24.04 and need at least 2.39, so Alpine doesn't work.
- Add `git`, `tini`, `ca-certificates`, `libgmp10`, `libffi8`, `zlib1g`, the
  linux-arm64 `jl4-lsp`, and the cloud-agent bundle.
- Leave out the `l4` CLI and Graphviz. The harness only uses the language
  server, and `jl4-lsp` embeds the core libraries.
- Target about 250–300 MB. Measure cold starts with zstd compression against
  SOCI lazy loading. They are mutually exclusive; AWS recommends SOCI above
  250 MB.

### 5.4 Harness lifecycle

1. **Entry point.**
   - Validate the environment.
   - Set `HOME=/home/agent`.
   - Write git config: `user.name "Legalese AI"`,
     `user.email agent@legalese.cloud`, `core.createObject rename`,
     `gc.auto 0`, `safe.directory`.
   - Exec the harness.
2. **Start.**
   - Open `/workspace/sessions/$SESSION_ID/`; exit if it doesn't exist.
   - Take the lease (§7.3).
   - Renew `AGENT_KEY` immediately. This deletes the key that came through the
     environment.
   - If `repo/` has no commits yet, commit the seed ("Seed").
   - Start `jl4-lsp` over stdio with `--cwd` set to the repo.
   - Load `session.json`, including the conversation id and MCP servers.
   - Generate an ephemeral key pair for sealed secrets (§6.4).
   - Write `state/git/main.bundle` and emit `session-state: running` with the
     public key.
3. **Main loop.**
   - Read new commands (§8) every second and run turns, appending events.
   - Connect each MCP server once its sealed credentials arrive (§6.4).
   - Rewrite the lease every 30 s.
   - Renew the agent key when 5 minutes remain.
4. **End of turn.** A turn is one user prompt and all the work the agent does
   for it: model calls, tool calls, and questions answered along the way.
   - If anything changed: `git add -A && git commit` with the turn summary as
     the message and a `Turn-Id: <turnId>` trailer; rewrite
     `state/git/main.bundle`; emit `git-committed { turnId, sha, parent }`.
   - When idle, apply incoming bundles (§9.1) and rollbacks (§9.4).
5. **Idle exit.** After 10 minutes with no running turn and no new command:
   - make a final commit and run `git gc`;
   - end the key chain;
   - set `session.json` status to `sleeping`;
   - release the lease and exit 0.
6. **Parking.** If the key chain can't be renewed (§6.2):

   - finish the current step and record the pending state;
   - set status `parked` and emit `auth-required`;
   - exit as in an idle exit.

   The next start resumes from the server-held conversation.

7. **SIGTERM** (from `StopTask` or a deploy). Same as an idle exit, within the
   30 s stop timeout.

## 6. Credentials

### 6.1 Extension to Sessions API

New jl4-auth-proxy route: `GET /auth/access-token`, authenticated with the
sealed session. It returns `{ accessToken, expiresAt }`: the WorkOS access
token (a JWT valid for about 5 minutes) from the user's session.

- The extension refreshes it as needed.
- The Sessions API verifies it against the AuthKit JWKS (issuer = the AuthKit
  domain). It takes `sub` as the user id and `org_id` as the organisation.
- It requires the `ai:chat` permission. Confirm which permission or role claims
  the WorkOS JWT template provides.
- The sealed session never leaves the extension and jl4-auth-proxy.

### 6.2 Agent key chains

The session task authenticates to ai-proxy and MCP with WorkOS user-scoped API
keys, as the prototype does. A key lasts 15 minutes. The task renews it
itself while the agent is active, for up to 24 hours.

**Mint** (by the extension, with the user present)

- `POST /auth/agent-token { purpose: "cloud-session", sessionId }`, with the
  sealed session as today.
- The key is named `cloud-session:<sid>:<chainStartEpoch>`, has permissions
  `{ai:chat, l4:rules, l4:evaluate, l4:read}` intersected with the user's, and
  expires in 15 minutes.
- The extension passes it to `POST /sessions/:sid/start`. The Sessions API
  hands it to `RunTask` as `AGENT_KEY`.

**Renew** (by the task): `POST /auth/agent-token/renew` with
`Authorization: Bearer <current key>`. jl4-auth-proxy:

1. validates the key with WorkOS: it must be valid, user-scoped, and named
   `cloud-session:…`;
2. refuses with `chain_expired` if the chain start in the name is more than 24
   hours ago (per-organisation setting);
3. refuses with `inactive` if the key had no real use in the last 10 minutes
   (§6.3);
4. **deletes the presented key first**. If WorkOS says it's already gone,
   another renewal won and it refuses with `chain_forked`;
5. mints the successor with the same name and permissions and returns
   `{ token, id, expiresAt }`.

**End** (by the task): `POST /auth/agent-token/end` with the current key
deletes it.

**Properties**

- A task receives a key from outside only once, at start, through
  `AGENT_KEY`. Its first renewal deletes that key within seconds. `RunTask`
  overrides are visible to operators (DescribeTasks, EventBridge task events)
  only for those seconds.
- At most one key per chain is valid. A stolen key either dies at the next
  renewal, or — if the thief renews first — breaks the real task's chain within
  minutes (`chain_forked` → parked + `auth-required`).
- Chains are stateless; there is no store. A user who creates an API key
  themselves could give it a chain name, but that only extends their own
  authority.
- If a task stops renewing (idle, crashed, hung), its key dies within 15
  minutes.
- The 24-hour cap and the permission set are enforced by jl4-auth-proxy, not
  by the task.

### 6.3 Activity signal

Real use means a model call through ai-proxy (including sending tool results
back) or an MCP call. Renewal calls don't count.

- **Preferred:** WorkOS `last_used_at` on the key, which WorkOS updates when
  ai-proxy or MCP validate it. P6 must confirm it is accurate to about a minute
  and isn't bumped by the renewal's own validation.
- **Fallback:** on each model call with a `cloud-session:` key, ai-proxy
  writes a timestamp to `/efs/agent-activity/<sid>` (at most once a minute).
  That is the EFS volume ai-proxy and jl4-auth-proxy already share; the renew
  route reads it.

### 6.4 MCP servers and sealed secrets

The user's MCP servers can be used in a cloud session, and are passed in when
the session starts.

- **Which servers.** HTTP and SSE servers only. stdio servers are programs on
  the user's machine and aren't transferred. A later option is to forward
  their tool calls to the extension while it's connected.
- **Configuration.** Names, URLs and enabled tools go into `session.json`
  through `POST /sessions`. They contain no secrets.
- **Secrets.** Bearer tokens and OAuth access tokens never go into a file or a
  `RunTask` override in the clear. Files persist in S3, with old versions, and
  overrides are visible to operators for the whole life of the task.
- **Sealing.** At start the harness generates an ephemeral key pair and
  publishes the public key in its `session-state: running` event. The
  extension encrypts the credentials to that key and sends them as an
  `mcp-credentials` command. Only ciphertext reaches the disk; the private key
  exists only in the task's memory and disappears with it.
- **Expiry.** Refresh tokens stay on the user's machine. When a token expires,
  the harness emits `auth-required { server }`, and the extension, if open,
  sends a fresh sealed token.
- **Permissions.** MCP tool calls follow the user's permission settings.
  Approvals go through events and commands.

## 7. Sessions API

One Lambda: a container image with `git`, Node 24, in the VPC. It mounts the
root access point at `/mnt/users` and is exposed through a Lambda function URL
with auth type NONE; every route verifies the WorkOS JWT itself. A
`sessions.legalese.cloud` domain can be added later with CloudFront.

### 7.1 Routes

| Route                                                                                                      | Does                                                                                                                                                                                                                                                                                               |
| ---------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `POST /sessions` `{ title?, mcpServers?, attachments: [{ name, size, contentType }] }`                     | Provisions if needed (§4.4). Creates `sessions/<sid>/` with `session.json`, `repo/` (`git init -b main` plus the config in §4.7), `attachments/` and `state/`. Returns `{ sessionId, gitUrl, uploads }` with pre-signed, size-bound PUT URLs into `inbox/<sid>/` for the seed and each attachment. |
| `POST /sessions/:sid/init`                                                                                 | Extracts the seed tarball into `repo/` and copies attachments, through the file system. Rejects absolute paths, `..`, `.git/`, links and device files. Deletes the inbox objects.                                                                                                                  |
| `GET /sessions`                                                                                            | Lists the caller's cloud conversations for the history view (§12.1): id, title, created, last activity and state (§7.3), read from `sessions/*/session.json`.                                                                                                                                      |
| `GET /sessions/:sid`                                                                                       | `session.json` plus state.                                                                                                                                                                                                                                                                         |
| `POST /sessions/:sid/start` `{ agentKey }`                                                                 | If the session is already `starting` or `running`, ends the unused key and returns the state. Otherwise provisions if needed and calls `RunTask` (§5.1). Returns `202 { state: "starting" }`.                                                                                                      |
| `POST /sessions/:sid/commands` `{ type, … }`                                                               | Queues a command (§8). Works while the session sleeps; the harness reads queued commands when it starts. Returns `{ commandId, state }`.                                                                                                                                                           |
| `GET /events?s=<sid>:<cursor>&s=…`                                                                         | New events for up to 10 sessions per call, with new cursors and states (§8).                                                                                                                                                                                                                       |
| `POST /sessions/:sid/stop`                                                                                 | Queues a `stop` command, then calls `StopTask` 60 s later if the task is still running.                                                                                                                                                                                                            |
| `DELETE /sessions/:sid`                                                                                    | Stops the session, then deletes `sessions/<sid>/`.                                                                                                                                                                                                                                                 |
| `GET /git/:sid.git/info/refs`, `POST /git/:sid.git/git-upload-pack`, `POST /git/:sid.git/git-receive-pack` | Smart-HTTP git (§9). Accepts the JWT as a Bearer token or as the password in HTTP Basic auth, which is how git sends credentials.                                                                                                                                                                  |
| Scheduled `sweep` (EventBridge Scheduler, every 5 min)                                                     | Stops tasks running longer than 25 hours, or with a lease stale for more than 5 minutes.                                                                                                                                                                                                           |

- Every route derives the folder from the JWT `sub` (§4.3). A `sid` that isn't
  in the caller's folder returns 404.
- `start` is safe even with someone else's `sid`: the task definition comes
  from the caller's own folder, so the task can only ever see the caller's
  data.
- Lambda caps request and buffered response bodies at 6 MB, which is about
  4.5 MB of raw upload after encoding. Response streaming inside a VPC is
  unverified (P7).

### 7.2 Handling hostile folder contents

The session task writes everything in a user folder, and the task runs
AI-driven code. The Sessions API can see every folder, so it must never let
folder contents steer it elsewhere:

- **Opening files.** Paths are built only from validated names: ULIDs, fixed
  file names, and numbered segments. Every open uses `O_NOFOLLOW` and requires
  a regular file under a size cap.
- **Directories.** It never lists a directory to discover files — it follows
  `head.json` and `commands.seq` (§8). It never returns directory listings,
  paths or filesystem errors to clients.
- **Git.** It never runs git inside a user folder. It serves git from scratch
  repositories in its own `/tmp`, built from bundle files (§9). This rules out
  repository-controlled hooks, filters, config, alternates and symlinks.
- **Deleting.** It deletes a session only after its task has stopped. Deletion
  doesn't follow symlinks.

### 7.3 Session states

States are derived; nothing extra is stored.

| State                          | Condition                                                                                |
| ------------------------------ | ---------------------------------------------------------------------------------------- |
| `sleeping`                     | No live lease and no pending task (`ListTasks(family, startedBy=sid)` is empty)          |
| `starting`                     | Task pending or running, no lease yet                                                    |
| `running` / `busy` / `waiting` | Live lease. `busy` while a turn runs, `waiting` while a question or approval is pending. |
| `parked`                       | `session.json` status `parked`: needs a new key chain                                    |

The lease is `state/lease.json { taskId, state, turnId?, expiresAt }`,
rewritten every 30 s (write to a temp file, then rename) with 90 s validity. A
harness that finds another task's live lease at start exits, which handles
duplicate starts.

## 8. Events and commands (file relay)

The event log and the command queue are files in the session folder. They
carry the conversation between the extension and the harness, and give replay
and history for free.

**Events**

- The harness appends JSON lines `{ seq, ts, type, … }` to
  `state/events/<n>.jsonl`, closing the file after each batch, and starts a new
  segment every 1 MB.
- It rewrites `state/head.json { segment, length }` (temp file, then rename)
  after each batch.
- The Sessions API reads `head.json` and then the named segments. The cursor is
  `<n>:<byteOffset>`.
- Types:
  - the existing `ChatServiceEvent` kinds: `started`, `text-delta` (coalesced
    to at least 250 ms), `thinking-delta`, `tool-call`, `tool-activity`,
    `turn-spawn`, `queue-consumed`, `done`, `error`, `ask-user`;
  - new: `user-message { turnId, text, attachments }`, `approval-request`,
    `session-state` (carries the public key for sealed secrets while
    running), `git-committed { turnId, sha, parent }`,
    `rolled-back { turnId, sha }`, `local-merged { sha }`,
    `local-merge-conflict { files }`, `auth-required { reason, server? }`.
- `user-message` lets observers render turns they didn't start. Today the
  webview drops deltas for turns it didn't create
  (`ts-apps/webview/src/lib/stores/ai-chat.svelte.ts:1182-1206`).
- A reconnecting or late client reads from its last cursor. A sleeping session
  shows the same history.

**Commands**

- The Sessions API creates `state/commands/<n>.json` with an exclusive create,
  taking the next number after `commands.seq` and moving on if that number is
  taken. It then rewrites `commands.seq`.
- Types: `message { turnId, text, attachments? }`, `inject`,
  `abort { turnId }`, `approve { callId, decision }`,
  `answer { callId, answer }`, `rollback { turnId }` (§9.4),
  `mcp-credentials { sealed }` (§6.4), `stop`, `apply-bundle { file }` (§9).
- The harness reads `commands.seq` each second and opens each unseen number by
  name, in order.

**Why known names, not directory listings.** Linux NFS clients cache directory
contents and "file not found" results for up to about a minute, and ECS
doesn't let us set mount options. Opening a known name that already exists
always goes to the server. So:

- files are discovered through `head.json` and `commands.seq`;
- readers never probe names that may not exist yet;
- writers close files, and readers open them fresh on each poll.

P4 measures the delay end to end.

**Polling**

- The extension host polls `GET /events` every second while any watched
  session is `busy`, and every 5 s while `running` or `waiting`.
- It stops polling `sleeping` and `parked` sessions until the user acts.
- The harness checks `commands.seq` every second.
- Cost: about 3,600 short Lambda calls per watched session-hour (about $0.001)
  plus S3 Files operations (about $0.004).

**Fallback.** If P4 misses its target (≤1.5 s p95), move delivery to AppSync
Events (managed WebSocket pub/sub with per-channel authorisation) and keep the
same event schema. The file log stays the record of the session.

## 9. Git sync

### 9.1 How it works

- The harness is the only process that runs git on a session repo. After every
  commit, and at start, it writes `state/git/main.bundle`: a full bundle of
  `main`, written to a temp file and renamed.
- The Sessions API builds a scratch repository in its own `/tmp` from
  `main.bundle` plus any pending incoming bundles. Clone, fetch and push are
  served from there with `git http-backend`.
  - The scratch repository's config and hooks belong to the Lambda.
  - A push may update only `refs/heads/local`; anything else is rejected.
- After an accepted push, the Sessions API writes the new commits as
  `state/git/incoming/<ulid>.bundle` (exclusive create) and queues an
  `apply-bundle` command.
- The harness applies incoming bundles when idle, and at start:

  1. fetch into `refs/incoming/<ulid>`;
  2. merge into `main` and commit;
  3. rewrite `main.bundle` and emit `local-merged`.

  On a conflict it aborts the merge and emits `local-merge-conflict`.

- While a session sleeps, pushes are accepted and wait. They are applied at the
  next start.

The Sessions API never runs git inside a user folder (§7.2). The agent's
working tree is never touched by anything but the harness.

### 9.2 Endpoint and auth

- URL: `https://<sessions-api>/git/<sid>.git`.
- Clients authenticate with the WorkOS JWT, either as
  `Authorization: Bearer <jwt>` or as HTTP Basic auth with any username and
  the JWT as the password. Basic auth is how git's own credential system sends
  it.
- Terminal git can use the same endpoint later through a credential helper
  (`legalese git-credential` in `legalese-cli`).

### 9.3 Clone and sync through VS Code's Git support

The extension has no git implementation of its own. It drives VS Code's
built-in Git extension, which runs the user's installed `git`.

- **Credentials.** `registerCredentialsProvider` (Git extension API) answers
  for the Sessions API host with a fresh WorkOS JWT on every git operation.
- **Clone.**
  - The button calls the Git API's
    `clone(url, { parentPath, postCloneAction: 'none' })`, which returns the
    cloned folder so the extension can configure it and offer to open it.
    This API first shipped in VS Code 1.106 (November 2025), so the extension's
    minimum rises from 1.95 to 1.106 (§15).
  - Cloud sessions also appear in VS Code's own "Git: Clone" picker through
    `registerRemoteSourceProvider`.
- **After cloning,** the extension sets three repository options through the
  Git API's `setConfig`:
  - `remote.origin.push = refs/heads/main:refs/heads/local`, so an ordinary
    push, or VS Code's own "Sync Changes", sends the user's commits to
    `local`;
  - `credential.<host>.helper` set to empty, so git asks VS Code every time
    instead of reusing an expired token saved in the system keychain;
  - `http.postBuffer = 5 MB`, so pushes go out as one request rather than a
    chunked upload (whether function URLs accept chunked uploads is checked in
    P7).
- **Sync.** The prompt-field button calls the repository's `pull()` and then
  `push()`. VS Code's Sync button does the same. Conflicts are resolved with
  VS Code's usual merge editor.
- **Button states.** "Clone" until a clone exists (`sid → folder` is kept in
  extension storage). Then "Sync" with ahead and behind counts from the
  repository state, plus "pending until the session runs" for pushes to a
  sleeping session.
- **Requirements.** VS Code 1.106 or newer, and `git` installed. If the Git
  extension is unavailable, the button says so.
- **Minimum VS Code version.**
  - Policy: support VS Code releases from the last 12 months. As of
    2026-09-28 that window starts at 1.105 (2025-10-09).
  - The minimum is 1.106 (2025-11-12), the first release with the Git API's
    `clone()`. 1.105 is inside the window but lacks it.
  - VS Code now ships weekly (1.139 on 2026-09-23), so the window moves
    quickly. Revisit the minimum when a newer API is needed, not on a
    schedule.
  - The extension is published only to the VS Code Marketplace (no Open VSX),
    so the change affects Marketplace users on older versions, plus anyone who
    installs the release VSIX into a fork (R13).
- **Limits.**
  - Pushes over about 4.5 MB are rejected with a clear message (Lambda body
    limit).
  - Bundles are capped at 100 MB.
  - Attachments live outside `repo/` and aren't synced.

### 9.4 Rolling back a turn

- **Where.** In a cloud conversation, each completed turn that changed files
  shows a rollback button until the user sends the next prompt. Earlier turns
  offer "Restore to before this turn".
- **How.** The extension sends `rollback { turnId }`. When the agent is idle,
  the harness:
  1. restores the working tree and index to the parent of that turn's commit
     (`git restore --source=<parent> --staged --worktree :/`);
  2. commits the result ("Roll back: <turn summary>") and rewrites
     `main.bundle`;
  3. emits `rolled-back { turnId, sha }`.
- **No history rewrite.** The rollback is a new commit, so existing clones
  just pull it.
- **Scope.** Restoring to before turn N undoes everything after it, including
  later turns and merged local syncs. The UI says so when synced local changes
  are among them.
- **Conversation.** The conversation is kept. Rolled-back turns are dimmed,
  and the next prompt tells the model which turns' changes were undone.
  Removing turns from the model's history would need a truncation endpoint in
  ai-proxy; add it later if needed.
- **Sleeping sessions.** A rollback on a sleeping session starts it, like any
  other command.

## 10. Seeding a session

1. **Gather.**

   - The active file, plus its transitive imports from the language server
     (`l4/getExportedFunctions` → `importedFiles`, as the prototype's
     `l4-bundle.ts` does).
   - @-mentioned files.
   - Attachments.

   Keep paths relative to the files' common ancestor. The prototype flattens
   them to file names, which breaks imports across directories.

2. **Check sizes.** Decline anything over the limits before uploading, with a
   message naming the files: attachments over 10 MB (today's harness limit),
   or a seed over 50 MB. Git LFS can lift this later (§18).
3. `POST /sessions` with the attachment list and the user's HTTP MCP servers
   (§6.4). It returns pre-signed URLs.
4. Upload `seed.tar.gz` and the attachments to `inbox/<sid>/`.
5. `POST /sessions/:sid/init`.
6. Queue the first `message` command.
7. Mint a key chain and `POST /sessions/:sid/start`.
8. Poll events. When `session-state: running` arrives, send the sealed MCP
   credentials (§6.4).

User content passes only through the user's own folder, the harness, and
ai-proxy with its model provider.

## 11. Harness extraction (l4-ide)

**New package `ts-shared/legalese-agent`.** It has no `vscode` import. It takes
`chat-service.ts`, `ai-proxy-client.ts`, `tool-dispatcher.ts`,
`tool-registry.ts`, the tool implementations and the permission logic. It
reaches the platform through ports:

| Port                | VS Code adapter                       | Cloud adapter                                                                                                                                         |
| ------------------- | ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AuthProvider`      | sealed session or API key (`auth.ts`) | agent key chain (§6.2)                                                                                                                                |
| `Workspace`         | `vscode.workspace` fs and edits       | Node fs confined to `repo/`                                                                                                                           |
| `L4Language`        | `VSCodeL4LanguageClient`              | `jl4-lsp` over stdio (`vscode-jsonrpc/node`): diagnostics cache, `l4/directiveResultsUpdated`, references, semantic tokens, `l4/getExportedFunctions` |
| `UserInteraction`   | webview messenger                     | events and commands (§8)                                                                                                                              |
| `PermissionPolicy`  | settings                              | fixed cloud policy (below)                                                                                                                            |
| `ConversationStore` | `globalStorageUri`                    | `session.json` + server-held conversation                                                                                                             |
| `Logger`            | OutputChannel                         | structured stdout, no content (§13)                                                                                                                   |
| `EditorContext`     | active editor                         | none                                                                                                                                                  |

**New app `ts-apps/cloud-agent`**

- Entry point, lease, idle timer, per-turn commits, bundles, incoming merges,
  event log and command loop.
- Bundled with esbuild.
- A `--dev` mode runs against a local folder and a local ai-proxy.

**Cloud tool policy**

- File and L4 tools run without prompts, confined to `repo/`.
- `ask_user` and approvals go through events and commands.
- The l4-rules MCP tools call `mcp.legalese.cloud` directly with the agent
  key.
- The user's HTTP MCP servers are available once their sealed credentials
  arrive (§6.4). stdio servers aren't.
- Editor side effects (opening documents, HTML preview) do nothing.

**Extension fixes needed along the way**

- Starting a turn denies pending approvals in every conversation
  (`ts-apps/vscode/src/ai/register.ts:385-402, 433-434`). Scope it to one
  conversation.
- Module-level singletons — the directive snapshot store in `tools/fs.ts`,
  `tools/l4-evaluate.ts` and `tools/directive-snapshot.ts` — become
  per-session instances.

## 12. VS Code UX

### 12.1 Conversation history and how cloud conversations are tracked

A cloud conversation is stored the way a local one is, but in the user's own
cloud folder instead of on their machine:

|                               | Local chat                                                | Cloud conversation                                 |
| ----------------------------- | --------------------------------------------------------- | -------------------------------------------------- |
| Record the history list reads | JSON file in VS Code global storage (`ConversationStore`) | `sessions/<sid>/session.json` in the user's folder |
| Transcript                    | Same JSON file                                            | The session's event log (§8)                       |
| Model context                 | ai-proxy's server-held conversation                       | The same, by `conversationId`                      |
| How the sidebar lists it      | Reads the local files                                     | `GET /sessions` (§7.1)                             |

- The history view merges both lists and sorts them by last activity. Cloud
  entries carry a cloud icon and a small state badge (`starting`, `busy`,
  `waiting`, `sleeping`, `parked`).
- The list is refetched when the sidebar opens and every 30 s while it is
  visible. The last result is cached in extension storage so the history
  shows immediately.
- Opening a cloud conversation reads its event log from the start
  (`GET /events?s=<sid>:0`) and renders it with the same components as a local
  chat. If the session is running, the sidebar keeps polling from the returned
  cursor.
- The server is the source of truth: a cloud conversation started on one
  machine appears on another.

### 12.2 Composer and cloud session view

- **Run in cloud.** Sits next to Send (from the prototype's
  `chat-input.svelte`), behind `legaleseAi.cloudSessions.enabled`. It shows
  progress: uploading, starting compute, ready. A cold start takes about
  25–45 s (P5).
- **Cloud session view.** The same components as local chats. Sending,
  injecting, aborting, approving and answering become commands.
- **Rollback.** Each completed turn that changed files shows a rollback button
  until the next prompt is sent; earlier turns offer "Restore to before this
  turn" (§9.4).
- **Sync button** in the prompt field (§9.3).
- **Notifications.** A background cloud session that asks a question or needs
  an approval raises a notification.
- **Resume.** For `parked` sessions and `auth-required` events, "Resume" mints
  a new chain and starts the session.
- **Where polling runs.** In the extension host: the webview's content
  security policy only allows `https://legalese.com`
  (`ts-apps/vscode/src/webview-panel.ts:177`).

## 13. Logs and superuser access

- The harness and the Sessions API log to CloudWatch
  `/legalese/cloud-sessions/<env>` with 30-day retention.
  - Logged: ids, tool names, durations and errors.
  - **Not logged:** prompt text, model output or file content. The logger
    drops content fields in production.
- `cloud-sessions-log-reader` role: reads logs only. Requires MFA, and use
  triggers an alarm.
- `cloud-sessions-breakglass` role: may mount the root access point and read
  the bucket. Requires two-person approval, and use triggers an alarm.
- Alarms:
  - task start failures, start latency p95, running tasks;
  - `LostAndFoundFiles > 0`, `PendingExports`, `ExportAge`;
  - Lambda errors and cost anomalies.
- **Outside this boundary today** (also true for local chats):
  - ai-proxy stores conversations on EFS;
  - ai-proxy logs tool activity, including rule inputs and outputs, to
    CloudWatch;
  - prompts go to the model provider through OpenRouter.

## 14. Image build and upgrades

- **Workflow.** A new l4-ide workflow, `cloud-agent-image.yml`. It runs on
  changes under `ts-shared/legalese-agent/`, `ts-apps/cloud-agent/`,
  `jl4-lsp/` or `jl4-core/`, and manually. It:
  1. builds `jl4-lsp` for linux-arm64, as `main-tag.yml:273-346` does;
  2. bundles the harness;
  3. builds the image for arm64 with `docker buildx`;
  4. pushes `legalese-cloud-agent:<git-sha>` to ECR through a GitHub OIDC role
     (pattern: `ai-proxy/terraform/github-actions.tf`);
  5. runs a smoke-test session;
  6. writes the digest to SSM `/cloud-sessions/<env>/image-digest`.
- **Rollout.** On `start`, the Sessions API compares the user's task
  definition with that digest and registers a new revision if they differ
  (§4.4). Running sessions keep their image until they sleep.
- **Rollback.** Set the parameter back to the previous digest.
- **ECR.** Immutable tags; a lifecycle rule keeps the last 30 images.

## 15. Implementation tracker

Each item is one pull request on branch `thomasgorissen/<item>`. It is based on
the branch named in brackets (a stacked pull request) or on `main`. Every pull
request is complete on its own: it builds, its tests pass, and anything a user
could see stays behind `legaleseAi.cloudSessions.enabled` until the last item.
Pull requests are not merged by the implementers.

Tracking rules:

- When the pull request is open, add its link after the item name.
- When the item is done — pull request open, CI green (or failures explained),
  post-mortem written — tick it and put the post-mortem link directly after
  the tick:
  `- [x] [post-mortem](cloud-sessions/<item>.md) · <item> ([PR #n](url)) — …`
- Post-mortems live in `specs/todo/cloud-sessions/`, one per item, using the
  template in §15.5.

### 15.1 l4-ide

- [ ] `cloud-sessions-spec` (base `main`) — this spec and the post-mortem
      folder, so the plan is reviewable. Updated as items complete.
- [ ] `vscode-min-1-106` (base `main`) — raise `engines.vscode` and
      `@types/vscode` in `ts-apps/vscode/package.json` from `^1.95.0` to
      `^1.106.0`. Run `npm install` to update the lockfile, then type-check and
      build the extension against the newer types. From then on the
      Marketplace stops offering updates to users on VS Code older than 1.106
      (§9.3, R13).
- [ ] `legalese-agent-core` (base `vscode-min-1-106`) — extract
      `ts-shared/legalese-agent` with the ports in §11 and VS Code adapters,
      with no change in behaviour. Includes the two extension fixes in §11:
      approvals scoped to one conversation, and per-session instances instead
      of module-level singletons.
- [ ] `cloud-session-protocol` (base `legalese-agent-core`) — shared types and
      validators for events, commands, `session.json` and the Sessions API
      requests and responses (§7, §8).
- [ ] `cloud-agent-runner` (base `cloud-session-protocol`) — `ts-apps/cloud-agent`:
      Node adapters, `jl4-lsp` over stdio, the file relay, lease, idle exit,
      the key-chain credential provider with parking, and a `--dev` mode
      (§5.4, §6.2, §8, §11).
- [ ] `cloud-agent-git` (base `cloud-agent-runner`) — per-turn commits with
      `Turn-Id` trailers, bundles, incoming bundles and local merges, and
      rollback (§9.1, §9.4).
- [ ] `cloud-agent-mcp` (base `cloud-agent-git`) — sealed secrets and the
      user's HTTP MCP servers (§6.4).
- [ ] `cloud-agent-image` (base `cloud-agent-mcp`) — Dockerfile, entry point
      with the environment allow-list, and the `cloud-agent-image.yml`
      workflow (§5.1, §5.3, §14).
- [ ] `cloud-sessions-client` (base `cloud-session-protocol`) — extension side:
      Sessions API client, access token, polling, commands, key-chain minting,
      seeding (path fix, size limits), MCP transfer and sealing. Takes over
      the useful parts of the `thomasgorissen/ai-cloud-agent` prototype
      (§6, §10, §12).
- [ ] `cloud-sessions-git-sync` (base `cloud-sessions-client`) — clone and sync
      through VS Code's Git extension (§9.3).
- [ ] `cloud-sessions-ui` (base `cloud-sessions-git-sync`) — webview: history
      with cloud entries, cloud session view, `user-message` handling, Run in
      cloud, Resume, rollback and Sync buttons (§12).

### 15.2 ai-proxy

- [ ] `ai-user-scoped-agent-keys` (base `main`) — accept WorkOS user-scoped
      keys (take over the `thomasgorissen/ai-cloud-agent` branch: organisation
      from `owner.organization_id`, no caching), and set `userId = owner.id` so
      conversations stay under the user across key rotations
      (`src/chat.ts:461-462`).
- [ ] `ai-turn-reattach-ownership` (base `main`) — turn reattach checks that
      the turn belongs to the caller (`src/index.ts:534`).
- [ ] `ai-cloud-session-activity` (base `ai-user-scoped-agent-keys`) — session
      id in billing records; the `/efs/agent-activity/<sid>` stamp for
      `cloud-session:` keys (§6.3 fallback); an optional validation cache of
      at most 60 s, off by default.

### 15.3 jl4-auth-proxy

- [ ] `auth-agent-token-revoke-ownership` (base `main`) — `revoke` checks that
      the key belongs to the caller (`src/auth/routes.ts:863-881`).
- [ ] `auth-access-token` (base `auth-agent-token-revoke-ownership`) —
      `GET /auth/access-token` (§6.1).
- [ ] `auth-agent-key-chains` (base `auth-access-token`) — `purpose:
"cloud-session"`, `renew` and `end`, with the activity check and its EFS
      fallback (§6.2, §6.3).

### 15.4 cloud-sessions (in jl4-auth-proxy, under `cloud-sessions/`)

A second Terraform root plus the Sessions API, following the ai-proxy pattern
of looking up shared resources by tag.

- [ ] `cloud-sessions-terraform` (base `main`) — §4, §5.1, §5.2 and §13 as
      Terraform: bucket and lifecycle rules, S3 Files file system, mount
      targets, service role, policies, ECS cluster, shared task and execution
      roles, log group, ECR repositories, SSM parameters, the Lambda with its
      function URL and scheduler, alarms, break-glass and log-reader roles,
      and an S3 gateway endpoint if missing. `terraform fmt` and `validate`
      only; nothing is applied.
- [ ] `cloud-sessions-api` (base `cloud-sessions-terraform`) — the Sessions API
      Lambda (§7–§10): routes, JWT verification, folder derivation,
      provisioning, file relay, seed init, git served from bundles, sweep, and
      its container image. Unit tests run against a temporary directory as the
      mount, with AWS mocked.

Deploy-time steps, not pull requests: Fargate vCPU quota increase; the
one-time file-system root ownership (§4.1); `FOLDER_KEY` value.

### 15.5 Post-mortem template

```markdown
# <item> — post-mortem

Repo · branch `thomasgorissen/<item>` · base `<base>` · [PR #n](url) · date

## What was built

## Spec sections covered, and deviations (with reasons)

## Checks run

Commands, results, and CI status.

## Problems and how they were solved

## Open questions and follow-ups for later items

## Where a reviewer should start
```

## 16. Phases and gates

**Phase 0 — proof of concept (about 1 week).** Each gate either passes or
changes the design.

| Gate               | Passes when                                                                                                                                                                                                                                                                   | If it fails                                                           |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| P1 Mount isolation | Mounts without an access point, and root mounts, are denied. The container can't find its access point ID (task metadata endpoint, `/proc/mounts`, environment). Mounting another user's access point by ID with the shared role succeeds — this documents the accepted risk. | Per-user IAM roles for the mount                                      |
| P2 S3 permissions  | The ECS S3 Files mount works with no S3 permissions on the task role                                                                                                                                                                                                          | Grant `s3:GetObject` on `users/*` only (folder names are unguessable) |
| P3 Git on S3 Files | Harness-side commit, gc and bundle times are acceptable on a 500-file repo                                                                                                                                                                                                    | EFS, with the same access-point model                                 |
| P4 File relay      | Commands and events cross between Lambda and task within 1.5 s p95; exclusive create works across clients                                                                                                                                                                     | AppSync Events for delivery (§8)                                      |
| P5 Cold start      | `RunTask` to harness `running` in ≤ 40 s p50                                                                                                                                                                                                                                  | zstd or SOCI, a smaller image, clearer progress UI                    |
| P6 WorkOS          | `last_used_at` is accurate to about a minute and not bumped by renewal; delete-then-mint renewal works; rate limits allow about 12 mints per active session-hour                                                                                                              | ai-proxy activity stamp (§6.3 fallback)                               |
| P7 Lambda          | Function URL, VPC and S3 Files mount work together; clone, pull and push of a 5 MB repo through VS Code's Git extension with Basic auth and `http.postBuffer` succeed; JWKS verification works through the NAT                                                                | Front the Lambda with CloudFront or API Gateway                       |

**Proof-of-concept results (2026-09-28).** Run in account 370008249754,
us-west-2, in an isolated VPC; all resources deleted afterwards.

| Gate | Result                   | Measured                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ---- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| P1   | Passed                   | No access point or file-system ID in the environment, the ECS task and container metadata, or `/proc/self/mountinfo`; the mount shows as `127.0.0.1:/` through a local proxy. Root access point with the shared task role: "access denied by server". Mount without an access point: worked before the file-system policy (the container could list the file-system root), denied after it — the `Null` condition works. Mounting another user's access point by ID wasn't run; AWS documents that it works. |
| P2   | Passed                   | The task role had no S3 permissions; mounting and all file operations worked.                                                                                                                                                                                                                                                                                                                                                                                                                                |
| P3   | Passed                   | Hard links unsupported; git works with `core.createObject=rename`. First `git add` of 500 files 9.5 s (about 19 ms per file), commit 0.9 s; commits of 5 changed files 327 ms on average; `git status` 57 ms; bundle 1.4 s (44 KB); `git gc` 5.7 s; `git fsck` clean. Bulk operations are slow; per-turn commits are fine.                                                                                                                                                                                   |
| P4   | Passed                   | Commands written by the Lambda were seen by the task after 177–1,079 ms, including the 1 s poll interval. The newest task event was 58–988 ms old when the Lambda read it (the task writes one per second). Exclusive create across clients returned `EEXIST`. A name probed before it existed took 6.1 s to become visible, which confirms the known-names rule in §8. The Lambda refused a symlink planted by the task (`ELOOP`) and read the task's bundle.                                               |
| P5   | Passed with a test image | 23–28 s from `RunTask` to running with a public test image: about 13 s before the pull starts, 5.6 s pull, 4–8.5 s to mount and start. The real ~300 MB image adds pull time.                                                                                                                                                                                                                                                                                                                                |
| P6   | Not run                  | Needs WorkOS credentials and a test user.                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| P7   | Partly                   | A Lambda in the VPC mounting the root access point works (all P4 checks). Function URL, git over HTTP and body limits not tested.                                                                                                                                                                                                                                                                                                                                                                            |

Also confirmed: Fargate ARM64 accepts a read-only root, tmpfs, all
capabilities dropped (`CapEff` 0), user 1000 and an S3 Files volume together.
The file-system root is `root:root 0755`, and the Sessions API (user 1000) got
`EACCES` creating a folder there, so the one-time ownership step in §4.1 is
required. The mount target took 1.5 minutes to create; access points were
available immediately.

Optional spike: Lambda MicroVMs (suspend and resume, a built-in endpoint per
VM). They cost about 3× Fargate while running, are capped at 8 hours, and S3
Files mounting in them is unverified.

**Phase 1 — harness extraction (about 2 weeks).** The extension behaves as
before (existing tests plus a manual pass). `cloud-agent --dev` completes a
scripted multi-turn session against a local folder.

**Phase 2 — platform (about 2 weeks).** Terraform, the Sessions API and the
image pipeline. It passes when this runs end to end through the API alone:
create → init → start → message → events → idle sleep → start again → git
clone and push.

**Phase 3 — auth (about 1 week, in parallel with Phase 2).** Chains renew while
active, are refused after 10 idle minutes, stop at 24 hours, and detect forks.
Conversations stay continuous across key rotations.

**Phase 4 — VS Code (about 2 weeks).** These journeys work:

- run in cloud from the composer;
- watch a cloud session while working locally;
- answer a question from a background session;
- sync both ways;
- resume after sleep and after parking;
- find cloud conversations in the history (cloud icon) on a second machine;
- roll back the last turn and an earlier one;
- use an HTTP MCP server from a cloud session.

**Phase 5 — hardening and beta (about 1 week).**

- Tests for I1–I8, including a cross-user mount attempt from inside a task and
  hostile folder contents (symlinks, forged bundles) against the Sessions API.
- 50 concurrent starts.
- Fargate quota increase, runbooks and alarms.
- Enable for staff.

## 17. Cost

| Item                                       | Cost                                                                                                                        |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| Active session-hour (1 vCPU / 3 GB, ARM64) | Fargate about $0.043 + public IPv4 $0.005 + polling about $0.001 + S3 Files operations about $0.004 ≈ **$0.05**             |
| Idle tail before each sleep (10 min)       | About $0.008                                                                                                                |
| Fixed monthly                              | About $0–2. No database, no new NAT or endpoints, no customer-managed keys.                                                 |
| Storage                                    | S3 Standard at $0.023/GB-month, plus 7 days of old versions. S3 Files cache at $0.30/GB-month, for recently used data only. |

Fargate ARM64 is billed per second (1-minute minimum) at $0.03238 per
vCPU-hour and $0.00356 per GB-hour.

## 18. Risks, decisions and deferred work

**Risks**

- **R1** Access point IDs act as bearer capabilities for the shared task role
  (§4.6).
  - Control: I2.
  - Detection: alarm on client connections through an unexpected access
    point, if S3 Files logs them to CloudTrail (verify).
- **R2** The Sessions API can reach every folder and start any user's task.
  - Keep it small, with pinned dependencies and alone in its role.
  - Run no AI-driven or user-supplied code in it.
  - Treat folder contents as hostile (§7.2).
- **R3** NFS behaviour across the Lambda and the task (P3, P4). Fallbacks: EFS
  for storage, AppSync Events for delivery.
- **R4** Lambda body limits (6 MB). Attachments stay out of git; large pushes
  are rejected.
- **R5** WorkOS behaviour:
  - how current `last_used_at` is;
  - undocumented rate limits;
  - chain names on user-created keys (affects only that user).
- **R6** Cold starts of 30–60 s on every wake.
- **R7** Conversation content outside the per-user boundary: the ai-proxy
  conversation store, CloudWatch tool logs, and the model provider.
- **R8** Object versions piling up from git. Watch storage and tune the
  lifecycle rule.
- **R9** Quotas: Fargate vCPU (6 on new accounts), `RunTask` at 20 per second,
  `RegisterTaskDefinition` at 1 per second.
- **R10** The single NAT instance carries the Sessions API's JWKS, ECS and SSM
  traffic.
- **R11** MCP credentials reach cloud compute. They are sealed to the task and
  never stored in the clear (§6.4), but a compromised task can use them while
  it runs.
- **R12** Git through VS Code needs `git` installed, and relies on the
  repository options the extension sets after cloning (§9.3).
- **R13** Raising the minimum to VS Code 1.106 drops users on older versions.
  The extension is published only to the VS Code Marketplace, but anyone who
  installs the release VSIX into a fork (Cursor, Windsurf, VSCodium) needs a
  fork based on VS Code 1.106 or newer.

**Open decisions**

- Live cloud sessions per user (proposed: 3), and the chain maximum age per
  organisation (proposed: 24 hours).
- Where conversation content should live: the ai-proxy store or the user's
  folder.
- Fargate Spot for background sessions. About 70% cheaper, with a 2-minute
  interruption notice.

**Deferred hardening**

- Customer-managed KMS keys for the bucket, file system, logs and temporary
  task storage. A dedicated AWS account with SCPs, so operators can't read
  user data without break-glass.
- A DNS Firewall egress allow-list for session tasks. Disable the L4
  FETCH/POST builtins in the cloud `jl4-lsp`.
- Pin agent-key chains to the task's public IP in ai-proxy.
- Image signing.

**Later features**

- Git LFS: the Sessions API answers the LFS batch API with pre-signed S3 URLs,
  so large files bypass the Lambda body limit.
- Forwarding stdio MCP tool calls to the extension while it's connected.
- Removing rolled-back turns from the model's history (ai-proxy truncation
  endpoint).

**Rejected alternatives**

- **Per-user IAM roles.** Capped at 10,000 per account and need per-user
  provisioning. Replaced by per-user access points whose IDs stay out of the
  compute.
- **Secret folder names as the only control.** The name ends up inside the
  compute and in prompts, and a leaked name works from any other user's task.
- **A DynamoDB session registry.** ECS, the lease file and `session.json` are
  enough.
- **A credentials orchestrator, or the extension pushing keys every 10
  minutes.** Replaced by self-renewing key chains.
- **Git served from the live repo by the Sessions API.** A hostile repo could
  steer it through hooks, filters, alternates or symlinks. Replaced by
  harness-written bundles.
- **Per-user git Lambdas.** Per-user provisioning and payload limits, for no
  gain once git is served from bundles.
- **AgentCore Runtime.** Its storage mounts are shared by every session of a
  runtime.

## Appendix: platform facts this design relies on

| Fact                                                                                                          | Source                                                                                                                                                                                                         |
| ------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Each Fargate task runs on single-use, single-tenant compute                                                   | [Fargate security considerations](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-security-considerations.html)                                                                            |
| S3 Files on ECS: task role and TLS are mandatory; the access point is set only in the task definition         | [ECS S3 Files volumes](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/s3files-volumes.html)                                                                                                       |
| Access points scope what a client can do, not which clients can use them                                      | [S3 Files access point policies](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-files-access-point-policy-examples.html)                                                                             |
| No per-task session tags for ECS task roles                                                                   | [containers-roadmap #2426](https://github.com/aws/containers-roadmap/issues/2426)                                                                                                                              |
| `RunTask` can't override volumes or entry points                                                              | [TaskOverride](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_TaskOverride.html), [ContainerOverride](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerOverride.html)     |
| 25,000 access points per file system; 20,000-character file system policy; no hard links; advisory locks only | [S3 Files quotas](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-files-quotas.html)                                                                                                                  |
| Export to S3 after about 60 s without writes; S3 wins conflicts; lost+found                                   | [Synchronization](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-files-synchronization.html), [Troubleshooting](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-files-troubleshooting.html) |
| Lambda can mount one S3 Files access point, under `/mnt/`                                                     | [Lambda S3 Files](https://docs.aws.amazon.com/lambda/latest/dg/configuration-filesystem-s3files.html)                                                                                                          |
| Lambda payloads: 6 MB request and buffered response                                                           | [Lambda limits](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html)                                                                                                                       |
| tmpfs mounts on Fargate (January 2026)                                                                        | [What's New](https://aws.amazon.com/about-aws/whats-new/2026/01/amazon-ecs-tmpfs-mounts-aws-fargate-managed-instances/)                                                                                        |
| ECS API throttling (`RegisterTaskDefinition` 1/s, Fargate `RunTask` 20/s)                                     | [ECS throttling](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/request-throttling.html), [Fargate throttling](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/throttling.html)         |
| ECS Exec requirements and incompatibility with read-only root                                                 | [ECS Exec](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html)                                                                                                                          |
| WorkOS API keys: `expires_at`, `last_used_at`, validate, expire                                               | [WorkOS API keys](https://workos.com/docs/reference/authkit/api-keys)                                                                                                                                          |
| `core.createObject=rename` for file systems without hard links                                                | [git-config](https://git-scm.com/docs/git-config)                                                                                                                                                              |
| Fargate pricing                                                                                               | [AWS Fargate pricing](https://aws.amazon.com/fargate/pricing/)                                                                                                                                                 |
