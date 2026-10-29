variable "aws_region" {
  description = "Region for the buckets and the session Lambda"
  type        = string
  default     = "us-west-2"
}

variable "domain" {
  description = "Hostname the editor is served on"
  type        = string
  default     = "play.legalese.com"
}

variable "legacy_domain" {
  description = "The old editor hostname, which becomes a redirect to var.domain"
  type        = string
  default     = "jl4.legalese.com"
}

variable "enable_jl4_redirect" {
  description = "Create the distribution that redirects var.legacy_domain to var.domain. Switch the DNS record over only after this applies."
  type        = bool
  default     = false
}

variable "github_repository" {
  description = "Repository whose main-tag.yml deploys the editor"
  type        = string
  default     = "legalese/l4-ide"
}

variable "github_environment" {
  description = "GitHub environment the deploy job runs in; the deploy role trusts only this environment"
  type        = string
  default     = "web-editor"
}
