output "certificate_validation_records" {
  description = "CNAMEs to add in DNSimple so ACM can issue the certificate"
  value = [
    for option in aws_acm_certificate.editor.domain_validation_options : {
      domain = option.domain_name
      name   = option.resource_record_name
      type   = option.resource_record_type
      value  = option.resource_record_value
    }
  ]
}

output "distribution_domain_name" {
  description = "Target of the play and jl4 CNAMEs in DNSimple"
  value       = aws_cloudfront_distribution.editor.domain_name
}

output "distribution_id" {
  description = "Set as the WEB_EDITOR_DISTRIBUTION_ID repository variable"
  value       = aws_cloudfront_distribution.editor.id
}

output "site_bucket" {
  description = "Set as the WEB_EDITOR_BUCKET repository variable"
  value       = aws_s3_bucket.site.id
}

output "sessions_bucket" {
  description = "Where the session import goes (README.md)"
  value       = aws_s3_bucket.sessions.id
}

output "github_deploy_role_arn" {
  description = "Set as the AWS_ROLE_ARN secret of the web-editor environment"
  value       = aws_iam_role.github_deploy.arn
}
