variable "aws_region" {
  description = "AWS Region assigned to group 9. Must not be changed."
  type        = string
  default     = "eu-north-1"

  validation {
    condition     = var.aws_region == "eu-north-1"
    error_message = "Group 9 is assigned eu-north-1 only. Deploying to any other Region violates the assignment's Region rule."
  }
}

variable "state_bucket_name" {
  description = "Override the computed state bucket name. Leave null to use devops-g9-iac-tfstate-<account-id>."
  type        = string
  default     = null
}

# --- GitHub Actions OIDC ------------------------------------------------
# The CI pipeline (.github/workflows/container-ci-cd.yml) authenticates to
# this account with short-lived credentials via GitHub's OIDC provider —
# no long-lived IAM access keys stored as GitHub secrets. This stack
# creates the OIDC provider + the role CI assumes. Its permissions are
# scoped to pushing images to the devops-g9-iac-* ECR repos only; it has
# no Terraform/state access (IaC keeps deploy authority — see
# docs/iac/gate1-design.md section 8).

variable "create_github_oidc" {
  description = "Create the GitHub OIDC provider + CI deploy role. Set false if the provider already exists in the account (only one per account is allowed)."
  type        = bool
  default     = true
}

variable "github_repo" {
  description = "owner/repo allowed to assume the CI deploy role via OIDC."
  type        = string
  default     = "emebetgirmay/Service-Environment"

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repo))
    error_message = "github_repo must be in 'owner/repo' form."
  }
}

variable "github_oidc_provider_arn" {
  description = "ARN of a pre-existing GitHub OIDC provider to reuse when create_github_oidc = false. Ignored when create_github_oidc = true."
  type        = string
  default     = null
}
