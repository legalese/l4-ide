# --- jl4.legalese.com → play.legalese.com ---
#
# The editor's distribution also answers for the old hostname (its aliases in
# cloudfront.tf). This function runs on each of its requests: those for
# var.legacy_domain go on to var.domain, the editor's own pass through.

resource "aws_cloudfront_function" "jl4_redirect" {
  name    = "${local.name_prefix}-jl4-redirect"
  comment = "301 ${var.legacy_domain} to ${var.domain}, keeping the path and query"
  runtime = "cloudfront-js-2.0"
  publish = true
  code = templatefile("${path.module}/jl4-redirect.js", {
    domain        = var.domain
    legacy_domain = var.legacy_domain
  })
}
