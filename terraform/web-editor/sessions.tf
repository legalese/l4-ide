# --- Share links (play.legalese.com/session) ---
#
# The Lambda in session-lambda/ stores each shared program as
# sessions/<uuid>.json. Only CloudFront can call it: the distribution sends
# random_password.origin_secret as a header, and the Lambda rejects requests
# without it. Shares also need a Cloudflare Turnstile token (secret in SSM).

resource "aws_s3_bucket" "sessions" {
  bucket = "${local.name_prefix}-sessions-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "sessions" {
  bucket = aws_s3_bucket.sessions.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "sessions" {
  bucket = aws_s3_bucket.sessions.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sessions" {
  bucket = aws_s3_bucket.sessions.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Every link someone shared lives here, so keep deleted versions.
resource "aws_s3_bucket_versioning" "sessions" {
  bucket = aws_s3_bucket.sessions.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Value set out-of-band:
#   aws ssm put-parameter --name /web-editor/turnstile-secret-key \
#     --type SecureString --overwrite --value <secret>
resource "aws_ssm_parameter" "turnstile_secret_key" {
  name  = "/${local.name_prefix}/turnstile-secret-key"
  type  = "SecureString"
  value = "REPLACE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "random_password" "origin_secret" {
  length  = 48
  special = false
}

data "archive_file" "session_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/session-lambda"
  output_path = "${path.module}/build/session-lambda.zip"
}

resource "aws_cloudwatch_log_group" "session_lambda" {
  name              = "/aws/lambda/${local.name_prefix}-session"
  retention_in_days = 30
}

data "aws_iam_policy_document" "session_lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "session_lambda" {
  name               = "${local.name_prefix}-session-lambda"
  assume_role_policy = data.aws_iam_policy_document.session_lambda_assume.json
}

data "aws_iam_policy_document" "session_lambda" {
  statement {
    sid       = "ReadAndWriteSessions"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.sessions.arn}/sessions/*"]
  }

  # Without ListBucket, S3 answers a missing key with AccessDenied instead of
  # NoSuchKey, and an unknown link would be a 500 instead of a 404.
  statement {
    sid       = "UnknownSessionsAre404"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.sessions.arn]
  }

  statement {
    sid       = "ReadTurnstileSecret"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.turnstile_secret_key.arn]
  }

  statement {
    sid       = "DecryptTurnstileSecret"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.session_lambda.arn}:*"]
  }
}

resource "aws_iam_role_policy" "session_lambda" {
  name   = "${local.name_prefix}-session-lambda"
  role   = aws_iam_role.session_lambda.id
  policy = data.aws_iam_policy_document.session_lambda.json
}

resource "aws_lambda_function" "session" {
  function_name    = "${local.name_prefix}-session"
  role             = aws_iam_role.session_lambda.arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  architectures    = ["arm64"]
  filename         = data.archive_file.session_lambda.output_path
  source_code_hash = data.archive_file.session_lambda.output_base64sha256
  memory_size      = 128
  timeout          = 10

  # Caps how fast anyone can write, whatever gets past Turnstile.
  reserved_concurrent_executions = 5

  environment {
    variables = {
      SESSIONS_BUCKET        = aws_s3_bucket.sessions.id
      ORIGIN_SECRET          = random_password.origin_secret.result
      ALLOWED_ORIGIN         = "https://${var.domain}"
      TURNSTILE_HOSTNAME     = var.domain
      TURNSTILE_SECRET_PARAM = aws_ssm_parameter.turnstile_secret_key.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.session_lambda]
}

# Public at the Lambda level; the origin secret is what limits it to CloudFront.
# With NONE, the provider adds the lambda:InvokeFunctionUrl and (URL-only)
# lambda:InvokeFunction permissions on creation, which function URLs need
# since October 2025. Declaring them as aws_lambda_permission too races with
# that and fails with a 409.
resource "aws_lambda_function_url" "session" {
  function_name      = aws_lambda_function.session.function_name
  authorization_type = "NONE"
}
