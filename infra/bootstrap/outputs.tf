output "state_bucket_name" {
  description = "S3 bucket name to use as `bucket` in infra/environments/lab's backend config (backend.hcl)."
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  value = aws_s3_bucket.tfstate.arn
}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "github_actions_role_arn" {
  description = "Set this as the GitHub Actions repo variable AWS_DEPLOY_ROLE_ARN (Settings → Secrets and variables → Actions → Variables)."
  value       = one(aws_iam_role.github_actions[*].arn)
}
