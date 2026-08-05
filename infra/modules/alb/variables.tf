variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "Must span at least two AZs (assignment requirement)."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "The ALB must span at least two public subnets in two AZs."
  }
}

variable "target_port" {
  description = "Port Service A listens on."
  type        = number
  default     = 3001
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "tags" {
  type    = map(string)
  default = {}
}
