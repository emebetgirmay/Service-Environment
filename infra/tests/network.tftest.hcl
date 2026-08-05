mock_provider "aws" {}

variables {
  name_prefix          = "devops-g9-iac"
  aws_region           = "eu-north-1"
  vpc_cidr             = "10.9.0.0/16"
  azs                  = ["eu-north-1a", "eu-north-1b"]
  public_subnet_cidrs  = ["10.9.0.0/24", "10.9.1.0/24"]
  private_subnet_cidrs = ["10.9.10.0/24", "10.9.11.0/24"]
}

run "two_azs_is_accepted" {
  command = plan
  module {
    source = "../modules/network"
  }
}

run "single_az_is_rejected" {
  command = plan
  module {
    source = "../modules/network"
  }
  variables {
    azs                  = ["eu-north-1a"]
    public_subnet_cidrs  = ["10.9.0.0/24"]
    private_subnet_cidrs = ["10.9.10.0/24"]
  }
  expect_failures = [var.azs]
}

run "private_route_table_has_no_nat_route" {
  command = apply
  module {
    source = "../modules/network"
  }
  assert {
    condition     = length(aws_route_table.private.route) == 0
    error_message = "Private route table must have no 0.0.0.0/0 route — no NAT Gateway, per Gate 1 design"
  }
}

run "public_route_table_uses_igw" {
  command = apply
  module {
    source = "../modules/network"
  }
  assert {
    condition     = anytrue([for r in aws_route_table.public.route : r.cidr_block == "0.0.0.0/0"])
    error_message = "Public route table must have a default route to the Internet Gateway"
  }
}
