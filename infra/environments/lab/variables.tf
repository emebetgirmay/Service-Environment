# --- Architecture rule: reject an unapproved Region -----------------------
variable "aws_region" {
  type    = string
  default = "eu-north-1"

  validation {
    condition     = var.aws_region == "eu-north-1"
    error_message = "Group 9 is assigned eu-north-1 only."
  }
}

# --- Architecture rule: required ownership tags must be present ----------
variable "owner_tags" {
  description = "Owner per Gate 1 ownership map — see docs/iac/gate1-design.md section 1."
  type        = map(string)

  validation {
    condition = alltrue([
      for k in ["platform", "service_a", "service_b", "service_c", "release"] :
      contains(keys(var.owner_tags), k) && length(trimspace(var.owner_tags[k])) > 0
    ])
    error_message = "owner_tags must have a non-empty value for platform, service_a, service_b, service_c, and release."
  }
}

# --- Architecture rule: image tag must be an immutable SHA (enforced again
# at the ecs-service module level too — the module doesn't trust its caller).
# Each service's ECR repo is created BY that service's module instance
# (main.tf) — these are just the tag of an image already pushed there.
# See docs/iac/deployment-sequence.md for the first-time bootstrap order.
variable "service_a_image_tag" {
  description = "Git SHA tag already pushed to devops-g9-iac-service-a."
  type        = string
}

variable "service_b_image_tag" {
  type = string
}

variable "service_c_image_tag" {
  type = string
}

# --- Escape hatch: NAT Gateway instead of endpoint-only egress ----------
# Default false = the Gate 1 NAT-free posture. Set true only where
# interface-endpoint private DNS for ECR isn't honoured by the VPC (the
# shared DevOpsCohort account) and image pulls therefore resolve to public
# ECR IPs with no route. See modules/network/variables.tf for the detail.
variable "enable_nat_gateway" {
  type    = bool
  default = false
}
