# --- jl4.legalese.com → play.legalese.com ---
#
# Off until the box is retired. Turn on with enable_jl4_redirect = true, apply,
# then point the jl4 CNAME in DNSimple at jl4_redirect_domain_name. A separate
# distribution, so play's own requests run no function.

resource "aws_cloudfront_function" "jl4_redirect" {
  count = var.enable_jl4_redirect ? 1 : 0

  name    = "${local.name_prefix}-jl4-redirect"
  comment = "301 ${var.legacy_domain} to ${var.domain}, keeping the path and query"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = templatefile("${path.module}/jl4-redirect.js", { domain = var.domain })
}

resource "aws_cloudfront_distribution" "jl4_redirect" {
  count = var.enable_jl4_redirect ? 1 : 0

  enabled         = true
  comment         = "Redirects ${var.legacy_domain} to ${var.domain}"
  aliases         = [var.legacy_domain]
  http_version    = "http2and3"
  is_ipv6_enabled = true
  price_class     = "PriceClass_All"

  # Never contacted: the viewer-request function answers every request.
  origin {
    origin_id                = local.site_origin_id
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id       = local.site_origin_id
    viewer_protocol_policy = "allow-all"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.jl4_redirect[0].arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.editor.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
