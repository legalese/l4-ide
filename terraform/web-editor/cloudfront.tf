# --- play.legalese.com ---
#
# DNS for legalese.com is on DNSimple, not Route 53, so the certificate's
# validation records and the `play` CNAME are added there by hand (README.md).

resource "aws_acm_certificate" "editor" {
  provider = aws.us_east_1

  domain_name = var.domain
  # The distribution answers for the old hostname too, as a redirect.
  subject_alternative_names = [var.legacy_domain]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Waits until the DNSimple validation records exist and ACM has issued.
resource "aws_acm_certificate_validation" "editor" {
  provider = aws.us_east_1

  certificate_arn = aws_acm_certificate.editor.arn
}

resource "aws_cloudfront_response_headers_policy" "editor" {
  name    = "${local.name_prefix}-security-headers"
  comment = "Security headers for ${var.domain}"

  # No X-Frame-Options: ?standalone is meant for embedding.
  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
    }

    content_type_options {
      override = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}

# Shared programs never change, so a GET is cached by its id for as long as
# the Lambda's Cache-Control allows; errors come back no-store.
resource "aws_cloudfront_cache_policy" "session" {
  name        = "${local.name_prefix}-session"
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "whitelist"

      query_strings {
        items = ["id"]
      }
    }
  }
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# Forwards Origin, Content-Type and X-Turnstile-Token; the Lambda URL needs
# its own Host.
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

locals {
  site_origin_id    = "site"
  session_origin_id = "session-lambda"
  # https://<id>.lambda-url.<region>.on.aws/ → <id>.lambda-url.<region>.on.aws
  session_origin_domain = trimsuffix(trimprefix(aws_lambda_function_url.session.function_url, "https://"), "/")
}

resource "aws_cloudfront_distribution" "editor" {
  enabled = true
  comment = "Web editor (${var.domain})"
  # Requests for var.legacy_domain only get a redirect (redirect.tf).
  aliases             = [var.domain, var.legacy_domain]
  default_root_object = "index.html"
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  # PriceClass_100 leaves out Asia; the always-free tier covers every class.
  price_class = "PriceClass_All"

  origin {
    origin_id                = local.site_origin_id
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  origin {
    origin_id   = local.session_origin_id
    domain_name = local.session_origin_domain

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # CloudFront overwrites a viewer-sent header of the same name.
    custom_header {
      name  = "X-Origin-Secret"
      value = random_password.origin_secret.result
    }
  }

  # Compresses up to 10 MB itself; deploy-static.sh uploads larger files
  # already brotli-encoded.
  default_cache_behavior {
    target_origin_id           = local.site_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.editor.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.jl4_redirect.arn
    }
  }

  ordered_cache_behavior {
    path_pattern               = "/session"
    target_origin_id           = local.session_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.session.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.editor.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.jl4_redirect.arn
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
