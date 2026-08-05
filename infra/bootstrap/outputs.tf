output "state_bucket_name" {
  description = "S3 bucket name to use as `bucket` in infra/environments/lab's backend config."
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  value = aws_s3_bucket.tfstate.arn
}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}
