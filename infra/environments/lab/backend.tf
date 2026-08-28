# Remote, versioned, locked state — see docs/iac/gate1-design.md section 7.
#
# PARTIAL backend config: the state bucket name embeds the AWS account ID
# (devops-g9-iac-tfstate-<account-id>) and Terraform backend blocks can't
# interpolate variables, so the bucket is supplied at init time instead of
# being hard-coded here. This lets the exact same code target a different
# AWS account without a source edit — see docs/iac/new-account-runbook.md.
#
#   cd infra/environments/lab
#   cp backend.hcl.example backend.hcl      # then set the new account's bucket
#   terraform init -reconfigure -backend-config=backend.hcl
#
# The bucket must already exist (created by infra/bootstrap, applied
# separately). key/region/use_lockfile are stable across accounts and stay
# pinned here.
terraform {
  backend "s3" {
    key          = "lab/workload.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
  }
}
