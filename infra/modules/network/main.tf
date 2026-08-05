resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

# --- Subnets -----------------------------------------------------------

resource "aws_subnet" "public" {
  for_each = { for idx, az in var.azs : az => idx }

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = var.public_subnet_cidrs[each.value]
  map_public_ip_on_launch = false # ALB gets its own public IP; nothing else in this subnet needs one

  tags = merge(var.tags, { Name = "${var.name_prefix}-public-${substr(each.key, -1, 1)}" })
}

resource "aws_subnet" "private" {
  for_each = { for idx, az in var.azs : az => idx }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = var.private_subnet_cidrs[each.value]

  tags = merge(var.tags, { Name = "${var.name_prefix}-private-app-${substr(each.key, -1, 1)}" })
}

# --- Route tables --------------------------------------------------------
# Public: default route to the Internet Gateway.
# Private: no default route at all — no NAT Gateway. Egress to AWS
# services goes through VPC endpoints instead (see below). This is a
# deliberate Gate 1 decision (no service calls a non-AWS endpoint), not an
# oversight.

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-rt-public" })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-rt-private" })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# --- Egress: VPC endpoints instead of a NAT Gateway -----------------------

# Bare security group, no inline rules. Ingress rules are added in the root
# module (infra/environments/lab) once the service security groups exist,
# to avoid a circular dependency between this module and ecs-service.
resource "aws_security_group" "vpce" {
  name_prefix = "${var.name_prefix}-sg-vpce-"
  description = "Interface VPC endpoints — inbound 443 from the service SGs only (rules added in root module)"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-sg-vpce" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-s3" })
}

locals {
  # Interface endpoints needed with no NAT Gateway: ECR (image pull),
  # CloudWatch Logs (log shipping), and the three SSM endpoints ECS Exec
  # depends on.
  interface_endpoint_services = {
    ecr-api     = "ecr.api"
    ecr-dkr     = "ecr.dkr"
    logs        = "logs"
    ssmmessages = "ssmmessages"
    ec2messages = "ec2messages"
    ssm         = "ssm"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoint_services

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-${each.key}" })
}
