terraform {
  required_version = ">= 1.5"

  required_providers {
    # 6.x adds the two permissions a public function URL needs since
    # October 2025 (see sessions.tf).
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket  = "jl4-terraform-state"
    key     = "l4-ide/web-editor/terraform.tfstate"
    region  = "us-west-2"
    encrypt = true
  }
}

# `Project = "web-editor"` and `Repository = "legalese/l4-ide"` mark which repo
# owns each resource in the account it shares with jl4-auth-proxy and ai-proxy.
locals {
  name_prefix = "web-editor"

  common_tags = {
    Project    = "web-editor"
    Repository = "legalese/l4-ide"
    ManagedBy  = "terraform"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# CloudFront only accepts ACM certificates from us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}
