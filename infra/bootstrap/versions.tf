terraform {
  # Allow 1.15.x patch drift (CI runners and local installs won't all pin
  # the exact same patch) but hold the minor line — S3-native locking needs
  # >= 1.10 and nothing here is validated against 1.16+ yet.
  required_version = ">= 1.15.8, < 1.16.0"

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
