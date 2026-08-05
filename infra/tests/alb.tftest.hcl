mock_provider "aws" {}

variables {
  name_prefix       = "devops-g9-iac"
  vpc_id            = "vpc-mock"
  public_subnet_ids = ["subnet-mock-a", "subnet-mock-b"]
}

run "two_subnets_is_accepted" {
  command = plan
  module {
    source = "../modules/alb"
  }
}

run "single_subnet_is_rejected" {
  command = plan
  module {
    source = "../modules/alb"
  }
  variables {
    public_subnet_ids = ["subnet-mock-a"]
  }
  expect_failures = [var.public_subnet_ids]
}

run "target_group_uses_ip_target_type" {
  command = plan
  module {
    source = "../modules/alb"
  }
  assert {
    condition     = aws_lb_target_group.service_a.target_type == "ip"
    error_message = "Target group must use target_type = ip for Fargate awsvpc tasks"
  }
}

run "alb_ingress_is_scoped_to_port_80_only" {
  command = plan
  module {
    source = "../modules/alb"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.alb_http_from_internet.from_port == 80 && aws_vpc_security_group_ingress_rule.alb_http_from_internet.to_port == 80
    error_message = "ALB security group must only open port 80 to the internet, not a wider range"
  }
}
