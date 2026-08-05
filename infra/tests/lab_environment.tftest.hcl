mock_provider "aws" {}

variables {
  aws_region = "eu-north-1"
  owner_tags = {
    platform  = "Mitingi Joy"
    release   = "Emebet Girmay"
    service_a = "unassigned"
    service_b = "unassigned"
    service_c = "unassigned"
  }
  service_a_image_tag = "7628b7a"
  service_b_image_tag = "7628b7a"
  service_c_image_tag = "7628b7a"
}

run "valid_config_is_accepted" {
  command = plan
  module {
    source = "../environments/lab"
  }
}

run "wrong_region_is_rejected" {
  command = plan
  module {
    source = "../environments/lab"
  }
  variables {
    aws_region = "us-east-1"
  }
  expect_failures = [var.aws_region]
}

run "missing_owner_tag_is_rejected" {
  command = plan
  module {
    source = "../environments/lab"
  }
  variables {
    owner_tags = {
      platform  = "Mitingi Joy"
      release   = "Emebet Girmay"
      service_a = "unassigned"
      service_b = "unassigned"
    }
  }
  expect_failures = [var.owner_tags]
}
