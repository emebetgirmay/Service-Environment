# Remote, versioned, locked state — see docs/iac/gate1-design.md section 7.
# Bucket must already exist (infra/bootstrap, applied separately). If the
# bootstrap output ever changes the bucket name, update it here too — this
# value is intentionally not variable-interpolated (Terraform backend
# blocks don't allow it).
terraform {
  backend "s3" {
    bucket       = "devops-g9-iac-tfstate-827478161993"
    key          = "lab/workload.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
  }
}
