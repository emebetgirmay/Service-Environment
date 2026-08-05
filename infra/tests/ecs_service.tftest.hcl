mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::827478161993:role/mock-role"
    }
  }
}

variables {
  name_prefix                   = "devops-g9-iac"
  service_name                  = "service-a"
  short_name                    = "a"
  aws_region                    = "eu-north-1"
  vpc_id                        = "vpc-mock"
  cluster_id                    = "cluster-mock"
  private_subnet_ids            = ["subnet-mock-a", "subnet-mock-b"]
  vpce_security_group_id        = "sg-mock-vpce"
  task_execution_role_arn       = "arn:aws:iam::827478161993:role/mock-exec"
  service_connect_namespace_arn = "arn:aws:servicediscovery:eu-north-1:827478161993:namespace/mock"
  container_port                = 3001
  desired_count                 = 2
  image_tag                     = "7628b7a"
}

run "valid_sha_tag_is_accepted" {
  command = plan
  module {
    source = "../modules/ecs-service"
  }
}

run "latest_tag_is_rejected" {
  command = plan
  module {
    source = "../modules/ecs-service"
  }
  variables {
    image_tag = "latest"
  }
  expect_failures = [var.image_tag]
}

run "non_sha_tag_is_rejected" {
  command = plan
  module {
    source = "../modules/ecs-service"
  }
  variables {
    image_tag = "v1.0"
  }
  expect_failures = [var.image_tag]
}

run "task_never_gets_a_public_ip" {
  command = plan
  module {
    source = "../modules/ecs-service"
  }
  assert {
    condition     = aws_ecs_service.this.network_configuration[0].assign_public_ip == false
    error_message = "Fargate tasks must never receive a public IP"
  }
}

run "circuit_breaker_and_rollback_enabled" {
  command = plan
  module {
    source = "../modules/ecs-service"
  }
  assert {
    condition     = aws_ecs_service.this.deployment_circuit_breaker[0].enable == true && aws_ecs_service.this.deployment_circuit_breaker[0].rollback == true
    error_message = "Deployment circuit breaker and automatic rollback must be enabled"
  }
}

run "ecs_exec_enabled" {
  command = plan
  module {
    source = "../modules/ecs-service"
  }
  assert {
    condition     = aws_ecs_service.this.enable_execute_command == true
    error_message = "ECS Exec must be enabled"
  }
}

run "ecr_repository_rejects_tag_reuse" {
  command = plan
  module {
    source = "../modules/ecs-service"
  }
  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "ECR repo must use IMMUTABLE tag mutability — a second, registry-level enforcement of no-latest/no-retagging"
  }
}

run "container_image_references_this_repo" {
  command = apply
  module {
    source = "../modules/ecs-service"
  }
  assert {
    condition     = strcontains(jsonencode(jsondecode(aws_ecs_task_definition.this.container_definitions)), "${var.image_tag}")
    error_message = "Task definition's container image must reference the module-owned ECR repo with the given tag"
  }
}
