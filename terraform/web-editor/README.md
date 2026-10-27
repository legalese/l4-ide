# Web editor hosting (play.legalese.com)

Terraform stack for the static web editor (`ts-apps/jl4-web`) and its share links. `main-tag.yml` deploys the editor after each release (job `deploy-web-editor`); this stack only creates what it deploys into. It runs manually, like the jl4-auth-proxy and ai-proxy stacks in the same AWS account.

```
play.legalese.com ── CloudFront ── default    → S3 site bucket (OAC)
                                └─ /session   → Lambda function URL → S3 sessions bucket
```

| File                       | Purpose                                                                                               |
| -------------------------- | ----------------------------------------------------------------------------------------------------- |
| `main.tf`                  | Providers (us-west-2, plus us-east-1 for the certificate), S3 backend, tags                           |
| `site.tf`                  | Private bucket for the build, readable only by the distribution                                       |
| `sessions.tf`              | Sessions bucket, the share-link Lambda, its function URL and the Turnstile secret parameter           |
| `session-lambda/index.mjs` | The Lambda: same API as the old jl4-websessions, POSTs need the editor's origin and a Turnstile token |
| `cloudfront.tf`            | Certificate, security headers, the `/session` cache policy and the distribution                       |
| `redirect.tf`              | The later jl4.legalese.com → play.legalese.com redirect (off until `enable_jl4_redirect = true`)      |
| `github-actions.tf`        | The OIDC role `deploy-web-editor` assumes; it trusts only the `web-editor` environment                |

## Caching

The deploy script (`ts-apps/jl4-web/scripts/deploy-static.sh`) sets the headers:

- `_app/immutable/**` (content-hashed) and `wasm/<release>/**` are cached for a year and never deleted, so a release never changes a URL's content and open tabs keep working.
- Everything else (`index.html`, `_app/version.json`, …) is revalidated on every load and invalidated on every deploy. Only those files are invalidated, so a deploy leaves the edge copies of the WASM and of share links alone.
- Files over 10 MB, which CloudFront won't compress, are uploaded brotli-encoded.

Shared programs never change, so CloudFront caches `GET /session?id=` by its id for a year. Browsers keep it for an hour, so a program can still be taken down (below).

## First-time setup

1. **Cloudflare Turnstile.** Create a widget for hostname `play.legalese.com` (mode: invisible). Put its site key in the repository variable `TURNSTILE_SITE_KEY`; the secret goes into SSM in step 4.
2. **Credentials.** `aws login`. The S3 backend doesn't read the CLI's stored login, and credentials exported with `aws configure export-credentials` expire after about 10 minutes, before an apply that waits for ACM is done. Instead, use a profile that fetches fresh ones whenever they run out. Put it in a config file of its own, outside the repository:
   ```ini
   [profile tf]
   region = us-west-2
   # AWS_CONFIG_FILE must be an absolute path: the CLI doesn't expand $HOME here.
   credential_process = env AWS_CONFIG_FILE=/Users/<you>/.aws/config AWS_REGION=us-west-2 aws configure export-credentials --profile legalese --format process
   ```
   ```bash
   export AWS_CONFIG_FILE=<that file> AWS_PROFILE=tf AWS_SDK_LOAD_CONFIG=1
   ```
3. **Certificate first.**
   ```bash
   terraform init
   terraform apply -target=aws_acm_certificate.editor
   terraform output certificate_validation_records
   ```
   Add both CNAMEs in DNSimple (legalese.com).
4. **Everything else.** `terraform apply` waits until ACM has issued the certificate. Then:
   ```bash
   aws ssm put-parameter --name /web-editor/turnstile-secret-key \
     --type SecureString --overwrite --value '<turnstile secret>'
   ```
5. **DNS.** In DNSimple, add `play` CNAME → `terraform output distribution_domain_name`. It must be an explicit record: `*.legalese.com` points at KeyCDN.
6. **GitHub.**
   - Environment `web-editor`, deployment branches limited to `main`, with secret `AWS_ROLE_ARN` = `terraform output github_deploy_role_arn`.
   - Repository variables `WEB_EDITOR_BUCKET` = `terraform output site_bucket` and `WEB_EDITOR_DISTRIBUTION_ID` = `terraform output distribution_id`.
7. Run `main-tag.yml` on `main`, or deploy the latest release without cutting a new one (below). Until both `WEB_EDITOR_BUCKET` and `WEB_EDITOR_DISTRIBUTION_ID` are set, `deploy-web-editor` is skipped.

## Deploying without a release

`deploy-web-editor` does this on every `main-tag.yml` run. To put an existing release online by hand instead, for example before the first run, build the editor at that release's commit with the release's WASM:

```bash
TAG=l4-ide-build-<n>
cd ts-apps/jl4-web
mkdir -p "static/wasm/$TAG"
for f in jl4-core.wasm jl4-core.mjs; do
  curl -fsSL -o "static/wasm/$TAG/$f" "https://github.com/legalese/l4-ide/releases/download/$TAG/$f"
done
cat > .env.production.local <<EOF
VITE_WASM_VERSION=$TAG
VITE_WASM_URL=/wasm/$TAG/jl4-core.wasm
VITE_WASM_JS_URL=/wasm/$TAG/jl4-core.mjs
VITE_SESSION_URL=/session
VITE_TURNSTILE_SITE_KEY=<the TURNSTILE_SITE_KEY repository variable>
EOF
npx turbo build --filter=jl4-web
./scripts/deploy-static.sh build <site_bucket> <distribution_id>
```

`static/wasm/` must hold only that release's directory: anything else in it is uploaded too.

## Importing jl4.legalese.com share links

Run this once the first deploy works, and again just before the redirect switch: programs never change, so `sync` only adds the ones shared since. It needs root SSH to jl4.legalese.com.

```bash
scp root@jl4.legalese.com:/var/lib/private/jl4-websessions/sessions.db .
mkdir -p sessions
sqlite3 sessions.db "SELECT lower(hex(sessionid)) || char(9) || json_quote(jl4program) FROM sessions" |
  while IFS=$'\t' read -r hex json; do
    uuid="${hex:0:8}-${hex:8:4}-${hex:12:4}-${hex:16:4}-${hex:20:12}"
    printf '%s' "$json" > "sessions/$uuid.json"
  done
aws s3 sync sessions/ "s3://$(terraform output -raw sessions_bucket)/sessions/" --size-only --content-type application/json
```

`--size-only` because the loop writes every file again: without it, `sync` would upload them all, and the versioned bucket would keep a copy of each.

- `sessionid` is the UUID's 16 bytes in network order, so its hex with dashes is the id in the share link.
- `json_quote` produces the JSON string `GET /session` returns, with newlines escaped, so each row is one line.
- Spot-check a few ids: `curl -s 'https://jl4.legalese.com/session?id=<id>'` and `curl -s 'https://play.legalese.com/session?id=<id>'` should print the same.

## Taking a shared program down

Delete every version of its object (the bucket keeps old versions), then drop the edge copies. Browsers that opened the link keep it for up to an hour.

```bash
BUCKET=$(terraform output -raw sessions_bucket) KEY=sessions/<id>.json
for v in $(aws s3api list-object-versions --bucket "$BUCKET" --prefix "$KEY" --query 'Versions[].VersionId' --output text); do
  aws s3api delete-object --bucket "$BUCKET" --key "$KEY" --version-id "$v"
done
aws cloudfront create-invalidation --distribution-id "$(terraform output -raw distribution_id)" --paths '/session*'
```

The wildcard covers the cached copy of every `?id=`.

## Redirecting jl4.legalese.com

1. Re-run the import above.
2. Set `enable_jl4_redirect = true` and `terraform apply`.
3. Before switching DNS, check a redirect keeps an encoded `?program=` intact. CloudFront Functions pass query values through as received; test that here:
   ```bash
   curl -sI "https://$(terraform output -raw jl4_redirect_domain_name)/?program=DECIDE%20x%20IS%201%26" | grep -i location
   # location: https://play.legalese.com/?program=DECIDE%20x%20IS%201%26
   ```
4. Point the `jl4` CNAME in DNSimple at `terraform output jl4_redirect_domain_name`.
