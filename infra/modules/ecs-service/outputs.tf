output "security_group_id" {
  value = aws_security_group.this.id
}

output "service_name_arn" {
  value = aws_ecs_service.this.id
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.this.name
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "repository_url" {
  description = "Push images here (as <repository_url>:<git-sha>) before the first apply that references them."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_name" {
  value = aws_ecr_repository.this.name
}
