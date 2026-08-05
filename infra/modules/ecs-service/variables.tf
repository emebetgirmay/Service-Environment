variable "name_prefix" {
  type = string
}

variable "service_name" {
  description = "Long form used everywhere except the ECS service resource name, e.g. \"service-a\"."
  type        = string
}

variable "short_name" {
  description = "Short suffix for the ECS service resource name only, e.g. \"a\" -> devops-g9-iac-svc-a."
  type        = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "cluster_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "vpce_security_group_id" {
  description = "VPC-endpoint security group (network module). This service's SG gets egress to it on :443, and the endpoint SG gets ingress from this service on :443."
  type        = string
}

variable "task_execution_role_arn" {
  type = string
}

variable "service_connect_namespace_arn" {
  type = string
}

variable "container_port" {
  type = number
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "image_tag" {
  description = "Git SHA tag of an image already pushed to this service's ECR repo, e.g. \"7628b7a\". The repo itself is created by this module (see main.tf) — full image reference is built internally as <repo_url>:<image_tag>."
  type        = string

  validation {
    # Reject `latest` outright and require something that looks like a
    # short or full Git SHA (7-40 lowercase hex chars).
    condition     = var.image_tag != "latest" && can(regex("^[0-9a-f]{7,40}$", var.image_tag))
    error_message = "image_tag must be an immutable Git SHA (7-40 hex chars) — \"latest\" and non-SHA tags are rejected."
  }
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type = number
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "alb_target_group_arn" {
  description = "Set only for Service A. Leave null for every other service — only Service A is registered behind the ALB."
  type        = string
  default     = null
}

variable "environment" {
  description = "Container environment variables, e.g. { SERVICE_B_URL = \"http://service-b:3002/process\" }."
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
