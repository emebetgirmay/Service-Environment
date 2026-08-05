resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  # Container Insights left off deliberately — not required by the
  # assignment (only CloudWatch Logs is), and it adds ongoing CloudWatch
  # cost for a lab environment that gets destroyed/rebuilt three times.
  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-cluster" })
}

# Fargate only — no EC2 capacity provider, matching the assignment's
# "launch type FARGATE / awsvpc" requirement.
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# HTTP namespace (not private-DNS) — matches ECS Service Connect's
# recommended namespace type and the manual build's prior setup.
resource "aws_service_discovery_http_namespace" "this" {
  name = var.service_connect_namespace

  tags = merge(var.tags, { Name = var.service_connect_namespace })
}

# Shared across all three services — pulls images from ECR and ships
# container logs to CloudWatch. Per-service task roles (ecs-service
# module) are separate and only grant what each service's own task needs
# (currently: the ECS Exec SSM channel).
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.name_prefix}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-ecs-task-execution-role" })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
