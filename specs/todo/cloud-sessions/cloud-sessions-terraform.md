# cloud-sessions-terraform — post-mortem

jl4-auth-proxy · branch `thomasgorissen/cloud-sessions-terraform` · base `main` · [PR #6](https://github.com/legalese/jl4-auth-proxy/pull/6) · 2026-09-28

## What was built

- `cloud-sessions/terraform/`, a second root (state `jl4-terraform-state` /
  `cloud-sessions/terraform.tfstate`, us-west-2), hashicorp/aws `~> 6.66`.
  VPC, public/private subnets, route tables, Route53 zone and GitHub OIDC
  provider are looked up by tag/name as in `ai-proxy/terraform`.
- Storage (§4): bucket with versioning, SSE-S3, BPA, lifecycle rules,
  TLS-only bucket policy plus a deny on `users/*` for everyone but the S3
  Files service role and break-glass; S3 Files file system on `users/`,
  service role (PoC `sync_policy`), mount targets per private subnet,
  mount-target SG, root access point `/` (1000:1000), file-system policy
  (PoC `fs_policy` incl. the `Null` condition, plus the root-access-point
  deny).
- Compute (§5.1–5.2): cluster (FARGATE), task role (PoC identity policy),
  execution role (ECR pull on the harness repo + log writes), task SG, log
  group (30 d), ECR ×2 (immutable, last 30), SSM `folder-key` / `image-digest`
  (`ignore_changes`), optional S3 gateway endpoint.
- Sessions API (§7): Lambda (image, arm64, private subnets, root access point
  at `/mnt/users`, env vars), function URL (NONE), scheduler every 5 min with
  `{"action":"sweep"}`, IAM per §4.5.
- §13: log-reader and break-glass roles (MFA), AssumeRole alerts, SNS topic,
  alarms (LostAndFoundFiles, PendingExports, ExportAge, Lambda errors,
  TaskStartFailures, RunningTasks, TaskFailedToStart events).
- GitHub OIDC roles for the API image workflow and l4-ide's
  `cloud-agent-image.yml`; `cloud-sessions/README.md` with deploy steps;
  `cloud-sessions-ci.yml` (fmt + validate).

## Spec sections covered, and deviations (with reasons)

§4.1, §4.5, §5.1 (shared parts), §5.2, §7 (infra), §13, §14 (repos, OIDC).
Deviations:

- IAM role names carry `-<env>` (account-global names).
- S3 Files has no `DescribeAccessPoints`: `GetAccessPoint` + `ListAccessPoints`.
- ECS Exec: deny `RunTask` when `ecs:enable-execute-command = true` instead of
  requiring `false` (the key may be absent), plus deny `ecs:ExecuteCommand`.
- Break-glass is exempt from the "no mount without access point" deny: the
  one-time root chown needs a root, no-access-point mount. A variable lets an
  ECS task assume break-glass only for that step. Two-person approval is an
  operational rule (not expressible in IAM).
- Lambda created only when `api_image_uri` is set (ECR must hold an image
  first); `image_uri` ignored afterwards so the workflow owns deploys.
- Not built: start-latency p95 and cost-anomaly alarms.

## Checks run

`terraform fmt -check -recursive`, `terraform init -backend=false`,
`terraform validate` — pass locally (1.5.7, provider 6.66.0) and in CI
(1.9.8). No plan/apply.

## Problems and how they were solved

- Provider support: confirmed from the provider changelog/docs that
  `aws_s3files_*`, ECS `s3files_volume_configuration` and Lambda S3 Files
  mounts are native — no awscc or local-exec stopgap.
- Metric names confirmed from the S3 Files CloudWatch docs (`AWS/S3/Files`,
  dimension `FileSystemId`).
- Role ARNs referenced by the bucket and file-system policies are computed
  from names to avoid dependency cycles.

## Open questions and follow-ups for later items

- Verify S3 Files sync still works with the `users/*` bucket-policy deny
  (it relies on `aws:PrincipalArn` = the service role). Not covered by the PoC.
- A root access point at a sub-directory with creation permissions would
  remove the break-glass chown step, at the cost of an extra key segment.
- Role-use alerts need a CloudTrail trail; confirm one exists.
- l4-ide `cloud-agent-image` should assume
  `cloud-sessions-<env>-agent-image-github` and write `sha256:<hex>` to
  `/cloud-sessions/<env>/image-digest`.

## Where a reviewer should start

`storage.tf` (file-system and bucket policies), then the `aws_iam_role_policy`
blocks in `compute.tf` and `sessions-api.tf`.
