resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name_prefix}/${var.service_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Name = "/ecs/${var.name_prefix}/${var.service_name}" })
}

# --- IAM: per-service task role (ECS Exec only) --------------------------
# The shared execution role (ecs-platform module) handles ECR pull + log
# shipping for every service. This role is what the *application* runs
# as — right now that's just the ECS Exec SSM channel, kept separate per
# service so a future service-specific permission doesn't leak sideways.

resource "aws_iam_role" "task" {
  name = "${var.name_prefix}-ecs-task-role-${var.service_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-ecs-task-role-${var.service_name}" })
}

resource "aws_iam_role_policy" "ecs_exec" {
  name = "ecs-exec"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Resource = "*"
      }
    ]
  })
}

# --- Security group --------------------------------------------------------
# Bare — no inline rules. Ingress from this service's upstream caller
# (ALB for A, the prior service for B/C) is wired in the root module,
# where both SG IDs in each traffic-contract pair are in scope together.
# The one relationship every service shares — talking to the VPC
# endpoints — is uniform enough to keep here instead of repeating it
# three times in root.
resource "aws_security_group" "this" {
  name_prefix = "${var.name_prefix}-sg-svc-${var.short_name}-"
  description = "${var.service_name} — ingress wired in root module; egress limited to VPC endpoints + downstream service"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-sg-svc-${var.short_name}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "to_vpce" {
  security_group_id            = aws_security_group.this.id
  description                  = "${var.service_name} -> VPC endpoints (ECR/logs/SSM)"
  referenced_security_group_id = var.vpce_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_this" {
  security_group_id            = var.vpce_security_group_id
  description                  = "${var.service_name} -> VPC endpoints :443"
  referenced_security_group_id = aws_security_group.this.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

# --- ECR repository ---------------------------------------------------
# Owned by this service (matches the Gate 1 ownership map — each service
# owner owns their own ECR repo). IMMUTABLE tag mutability is a second,
# registry-level enforcement of "no latest, no retagging" on top of the
# image_tag variable validation below — AWS itself will reject an attempt
# to push a different image under a tag that already exists.
#
# force_delete = true: this is a lab environment torn down and rebuilt
# across three cycles. Losing image history on destroy is an acceptable
# trade — SHA-tagged images can always be rebuilt from the same commit —
# versus a destroy that fails because a repo still has images in it.
resource "aws_ecr_repository" "this" {
  name                 = "${var.name_prefix}-${var.service_name}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.service_name}" })
}

# --- Task definition ---------------------------------------------------

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-td-${var.service_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = var.service_name
      image     = "${aws_ecr_repository.this.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          name          = "${var.service_name}-http"
          containerPort = var.container_port
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      environment = [for k, v in var.environment : { name = k, value = v }]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = var.service_name
        }
      }
    }
  ])

  tags = merge(var.tags, { Name = "${var.name_prefix}-td-${var.service_name}" })
}

# --- Service -------------------------------------------------------------

resource "aws_ecs_service" "this" {
  name            = "${var.name_prefix}-svc-${var.short_name}"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  enable_execute_command = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.this.id]
    assign_public_ip = false # structural: this module never exposes a way to set this true
  }

  service_connect_configuration {
    enabled   = true
    namespace = var.service_connect_namespace_arn

    service {
      port_name = "${var.service_name}-http"

      client_alias {
        port     = var.container_port
        dns_name = var.service_name
      }
    }
  }

  dynamic "load_balancer" {
    for_each = var.alb_target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.alb_target_group_arn
      container_name   = var.service_name
      container_port   = var.container_port
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  tags = merge(var.tags, { Name = "${var.name_prefix}-svc-${var.short_name}" })
}
