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
