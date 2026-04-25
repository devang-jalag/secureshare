variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project identifier used for resource naming"
  type        = string
  default     = "secureshare"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}
