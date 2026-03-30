variable "bucket_name" {
  description = "Name of the S3 bucket to create"
  type        = string
}

variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "enable_spa_redirect" {
  type    = bool
  default = false
}

variable "role_arn" {
  description = "The ARN of the role to assume"
  type        = string
}

variable "custom_domain_name" {
  description = "Custom domain name for the CloudFront distribution"
  type        = string
  default     = ""
}

variable "issue_custom_domain_cert" {
  description = "Whether to issue a custom domain certificate"
  type        = bool
  default     = false
}