variable "name_prefix" {
  type = string
}

variable "service_connect_namespace" {
  description = "Literal Cloud Map HTTP namespace name mandated by the assignment (group<N>.internal) — deliberately NOT name_prefix-derived."
  type        = string

  validation {
    condition     = can(regex("^group[0-9]+\\.internal$", var.service_connect_namespace))
    error_message = "Must match the assignment's required format: group<N>.internal"
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
