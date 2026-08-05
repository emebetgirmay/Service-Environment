provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project     = "service-environment"
      group       = "g9"
      owner       = "platform"
      environment = "lab"
      build       = "iac"
      managed_by  = "terraform-bootstrap"
    }
  }
}
