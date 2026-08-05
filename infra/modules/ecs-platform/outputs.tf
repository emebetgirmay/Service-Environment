output "cluster_id" {
  value = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_connect_namespace_arn" {
  value = aws_service_discovery_http_namespace.this.arn
}

output "service_connect_namespace_name" {
  value = aws_service_discovery_http_namespace.this.name
}

output "task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}
