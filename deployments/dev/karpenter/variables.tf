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
  description = "CIDR block for the VPC"
}

variable "az_count" {
  type        = number
  description = "Number of availability zones to use"
}

variable "aws_region" {
  type        = string
  description = "AWS Region to deploy to"
}