variable "name_prefix" {
  description = "Prefix for every resource name created by this module, e.g. devops-g9-iac."
  type        = string
}

variable "aws_region" {
  description = "Region the VPC endpoints' service names are built against."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "azs" {
  description = "Availability Zones to spread public/private subnets across. Must have at least 2 entries."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least two Availability Zones are required (assignment: ALB must span at least two AZs)."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per AZ, same order as var.azs."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private app subnet CIDRs, one per AZ, same order as var.azs."
  type        = list(string)
}

variable "tags" {
  description = "Tags merged onto every resource this module creates."
  type        = map(string)
  default     = {}
}
