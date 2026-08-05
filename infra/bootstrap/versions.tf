terraform {
  required_version = "= 1.15.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.58.0"
    }
  }

  # Intentionally no backend block: bootstrap state stays local. This stack
  # creates the S3 bucket the workload backend depends on, so it can't
  # depend on that same bucket without a chicken-and-egg problem. It's a
  # rarely-run, single-operator stack — see README.md.
}
