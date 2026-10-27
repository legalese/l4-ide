# Web editor hosting (play.legalese.com)

Terraform stack for the static web editor (`ts-apps/jl4-web`) and its share links. `main-tag.yml` deploys the editor after each release (job `deploy-web-editor`); this stack only creates what it deploys into. It runs manually, like the jl4-auth-proxy and ai-proxy stacks in the same AWS account.

```
play.legalese.com ── CloudFront ── default    → S3 site bucket (OAC)
                                └─ /session   → Lambda function URL → S3 sessions bucket
```

| File                       | Purpose                                                                                          |
| -------------------------- | ------------------------------------------------------------------------------------------------ |
| `main.tf`                  | Providers (us-west-2, plus us-east-1 for the certificate), S3 backend, tags                      |
| `site.tf`                  | Private bucket for the build, readable only by the distribution                                  |
| `sessions.tf`              | Sessions bucket, the share-link Lambda, its function URL and the Turnstile secret parameter      |
| `session-lambda/index.mjs` | The Lambda: same API as jl4-websessions, POSTs need the editor's origin and a Turnstile token    |
| `cloudfront.tf`            | Certificate, security headers, the `/session` cache policy and the distribution                  |
| `redirect.tf`              | The later jl4.legalese.com → play.legalese.com redirect (off until `enable_jl4_redirect = true`) |
| `github-actions.tf`        | The OIDC role `deploy-web-editor` assumes; it trusts only the `web-editor` environment           |

## Caching

The deploy script (`ts-apps/jl4-web/scripts/deploy-static.sh`) sets the headers:

- `_app/immutable/**` (content-hashed) and `wasm/<release>/**` are cached for a year and never deleted, so a release never changes a URL's content and open tabs keep working.
- Everything else (`index.html`, `_app/version.json`, …) is revalidated on every load and invalidated on every deploy.
- Files over 10 MB, which CloudFront won't compress, are uploaded brotli-encoded.

Shared programs are immutable, so `GET /session?id=` is cached at the edge by its id.

## First-time setup

1. **Cloudflare Turnstile.** Create a widget for hostname `play.legalese.com` (mode: invisible). Put its site key in the repository variable `TURNSTILE_SITE_KEY`; the secret goes into SSM in step 4.
2. **Credentials.** `aws login`, then bridge them for the S3 backend, which doesn't read the CLI's stored login:
   ```bash
   eval "$(aws configure export-credentials --profile legalese --format env)"
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
7. Run `main-tag.yml` on `main`. Until `WEB_EDITOR_BUCKET` is set, `deploy-web-editor` is skipped.

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
aws s3 sync sessions/ "s3://$(terraform output -raw sessions_bucket)/sessions/" --content-type application/json
```

- `sessionid` is the UUID's 16 bytes in network order, so its hex with dashes is the id in the share link.
- `json_quote` produces the JSON string `GET /session` returns, with newlines escaped, so each row is one line.
- Spot-check a few ids: `curl -s 'https://jl4.legalese.com/session?id=<id>'` and `curl -s 'https://play.legalese.com/session?id=<id>'` should print the same.

## Redirecting jl4.legalese.com

1. Re-run the import above.
2. Set `enable_jl4_redirect = true` and `terraform apply`.
3. Before switching DNS, check a redirect keeps an encoded `?program=` intact. CloudFront Functions pass query values through as received; test that here:
   ```bash
   curl -sI "https://$(terraform output -raw jl4_redirect_domain_name)/?program=DECIDE%20x%20IS%201%26" | grep -i location
   # location: https://play.legalese.com/?program=DECIDE%20x%20IS%201%26
   ```
4. Point the `jl4` CNAME in DNSimple at `terraform output jl4_redirect_domain_name`.
