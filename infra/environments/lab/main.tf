locals {
  name_prefix               = "devops-g9-iac"
  azs                       = ["eu-north-1a", "eu-north-1b"]
  vpc_cidr                  = "10.9.0.0/16"
  public_subnet_cidrs       = ["10.9.0.0/24", "10.9.1.0/24"]
  private_subnet_cidrs      = ["10.9.10.0/24", "10.9.11.0/24"]
  service_connect_namespace = "group9.internal"

  common_tags = {
    project     = "service-environment"
    group       = "g9"
    environment = "lab"
    build       = "iac"
  }
}

module "network" {
  source = "../../modules/network"

  name_prefix          = local.name_prefix
  aws_region           = var.aws_region
  vpc_cidr             = local.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = local.public_subnet_cidrs
  private_subnet_cidrs = local.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  tags                 = merge(local.common_tags, { owner = var.owner_tags["platform"] })
}

module "alb" {
  source = "../../modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  target_port       = 3001
  health_check_path = "/health"
  tags              = merge(local.common_tags, { owner = var.owner_tags["platform"] })
}

module "ecs_platform" {
  source = "../../modules/ecs-platform"

  name_prefix               = local.name_prefix
  service_connect_namespace = local.service_connect_namespace
  tags                      = merge(local.common_tags, { owner = var.owner_tags["platform"] })
}

module "service_a" {
  source = "../../modules/ecs-service"

  name_prefix                   = local.name_prefix
  service_name                  = "service-a"
  short_name                    = "a"
  aws_region                    = var.aws_region
  vpc_id                        = module.network.vpc_id
  cluster_id                    = module.ecs_platform.cluster_id
  private_subnet_ids            = module.network.private_subnet_ids
  vpce_security_group_id        = module.network.vpce_security_group_id
  task_execution_role_arn       = module.ecs_platform.task_execution_role_arn
  service_connect_namespace_arn = module.ecs_platform.service_connect_namespace_arn
  container_port                = 3001
  image_tag                     = var.service_a_image_tag
  desired_count                 = 2
  alb_target_group_arn          = module.alb.target_group_arn
  allow_public_egress           = var.enable_nat_gateway

  environment = {
    PYTHONUNBUFFERED = "1"
    SERVICE_B_URL    = "http://service-b:3002/process"
  }

  tags = merge(local.common_tags, { owner = var.owner_tags["service_a"] })
}

module "service_b" {
  source = "../../modules/ecs-service"

  name_prefix                   = local.name_prefix
  service_name                  = "service-b"
  short_name                    = "b"
  aws_region                    = var.aws_region
  vpc_id                        = module.network.vpc_id
  cluster_id                    = module.ecs_platform.cluster_id
  private_subnet_ids            = module.network.private_subnet_ids
  vpce_security_group_id        = module.network.vpce_security_group_id
  task_execution_role_arn       = module.ecs_platform.task_execution_role_arn
  service_connect_namespace_arn = module.ecs_platform.service_connect_namespace_arn
  container_port                = 3002
  image_tag                     = var.service_b_image_tag
  desired_count                 = 1
  allow_public_egress           = var.enable_nat_gateway

  environment = {
    PYTHONUNBUFFERED = "1"
    SERVICE_C_URL    = "http://service-c:3003/execute"
  }

  tags = merge(local.common_tags, { owner = var.owner_tags["service_b"] })
}

module "service_c" {
  source = "../../modules/ecs-service"

  name_prefix                   = local.name_prefix
  service_name                  = "service-c"
  short_name                    = "c"
  aws_region                    = var.aws_region
  vpc_id                        = module.network.vpc_id
  cluster_id                    = module.ecs_platform.cluster_id
  private_subnet_ids            = module.network.private_subnet_ids
  vpce_security_group_id        = module.network.vpce_security_group_id
  task_execution_role_arn       = module.ecs_platform.task_execution_role_arn
  service_connect_namespace_arn = module.ecs_platform.service_connect_namespace_arn
  container_port                = 3003
  image_tag                     = var.service_c_image_tag
  desired_count                 = 1
  allow_public_egress           = var.enable_nat_gateway

  environment = {
    PYTHONUNBUFFERED = "1"
    # SERVICE_A_URL is still set, matching the existing app code — but no
    # SG rule permits it (see sg-traffic-contract.tf). The callback will
    # fail closed exactly like Scar 1 in the manual build, until Robert
    # approves SG-7 or the app drops the synchronous callback.
    SERVICE_A_URL = "http://service-a:3001/callback"
  }

  tags = merge(local.common_tags, { owner = var.owner_tags["service_c"] })
}
