variable "github_organization" {
  description = "GitHub Organization Name"
  type        = string
}

variable "app_id" {
  description = "GitHub App ID"
  type        = string
}

variable "app_installation_id" {
  description = "GitHub Installation ID"
  type        = string
}

variable "app_pem_file" {
  description = "GitHub App Private Key PEM file content"
  type        = string
}

variable "infra_oidc_role" {
  description = "ARN of the OIDC role for IAC"
  type        = string
}

variable "infra_state_bucket" {
  description = "S3 bucket name for IAC state management"
  type        = string
}

variable "oidc_role_common_name" {
  description = "Common name for OIDC roles"
  type        = string
}

variable "github_app_slug" {
  description = "Slug (URL-friendly name) of the GitHub App used by Terraform"
  type        = string
}