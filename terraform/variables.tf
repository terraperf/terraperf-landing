variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "terraperf-workloads-prod"
}

variable "bucket_name" {
  description = "S3 bucket name for landing page"
  type        = string
  default     = "terraperf-landing-prod"
}

variable "domain_name" {
  description = "Domain name for the landing page"
  type        = string
  default     = "terraperf.com"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "terraperf-landing"
}

variable "environment" {
  description = "Environment (prod, staging, dev)"
  type        = string
  default     = "prod"
}

variable "basic_auth_enabled" {
  description = "Enable Basic HTTP Authentication on CloudFront"
  type        = bool
  default     = true
}

variable "basic_auth_username" {
  description = "Username for Basic HTTP Authentication"
  type        = string
  default     = "terraperf"
  sensitive   = true
}

variable "basic_auth_password" {
  description = "Password for Basic HTTP Authentication"
  type        = string
  default     = "preview2025"
  sensitive   = true
}
