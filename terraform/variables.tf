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
