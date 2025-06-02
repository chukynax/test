
variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., dev, prod)"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "az_count" {
  type        = number
  default     = 2
  description = "Number of availability zones to use"
}