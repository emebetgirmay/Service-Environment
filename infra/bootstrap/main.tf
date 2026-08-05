data "aws_caller_identity" "current" {}

locals {
  state_bucket_name = coalesce(var.state_bucket_name, "devops-g9-iac-tfstate-${data.aws_caller_identity.current.account_id}")
}

# Terraform/OpenTofu state backend for the workload stack
# (infra/environments/lab). Kept in its own stack, own state, so a
# `terraform destroy` run against the workload can never reach it.
resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket_name

  tags = {
    Name = local.state_bucket_name
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Deny any non-TLS request outright, regardless of who's asking.
resource "aws_s3_bucket_policy" "tfstate_tls_only" {
  bucket = aws_s3_bucket.tfstate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# No aws_dynamodb_table resource here on purpose: Terraform 1.15.8 (pinned
# in versions.tf) supports S3-native state locking (`use_lockfile = true`
# in the workload backend config), so a separate lock table isn't needed.
