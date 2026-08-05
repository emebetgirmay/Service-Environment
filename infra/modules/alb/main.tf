# Bare security group — the only inline rule is public :80 ingress, which
# is self-contained (source is the internet, not another module's SG).
# Egress to Service A is added in the root module, once ecs-service's
# security group exists (avoids a circular module dependency).
resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-sg-alb-"
  description = "ALB — inbound 80 from the internet; egress to Service A added in root module"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-sg-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_from_internet" {
  security_group_id = aws_security_group.alb.id
  description       = "Internet -> ALB :80"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb" })
}

# Only Service A is registered behind the ALB (assignment requirement).
# Target type "ip" because Fargate awsvpc tasks are registered by ENI IP,
# not instance ID. No static attachments here — the ECS service manages
# registration/deregistration dynamically via its own `load_balancer` block.
resource "aws_lb_target_group" "service_a" {
  name        = "${var.name_prefix}-tg-service-a"
  port        = var.target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-tg-service-a" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_a.arn
  }
}
