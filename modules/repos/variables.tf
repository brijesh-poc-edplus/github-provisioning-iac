variable "repos" {
  type = list(object({
    name        = string
    visibility  = string
    description = string
    frontend    = optional(bool, false)
    aws-nonprod      = optional(string, "")
    aws-nonprod-name = optional(string, "")
    aws-prod         = optional(string, "")
    aws-prod-name    = optional(string, "")
    budget-info      = optional(string, "")
    jira-board       = optional(string, "")
    portfolio-detail = optional(string, "")
  }))
}

variable "branches" {
  type = list(object({
    repo                    = string
    branch                  = string
    minPRCount              = optional(number, 1)
    users                   = optional(string, "")
    teams                   = optional(string, "")
    codeOwnerReviewRequired = optional(bool, false)
  }))
}

variable "team_permissions" {
  type = list(object({
    repo       = string
    team       = string
    permission = string
  }))
}

variable "user_permissions" {
  type = list(object({
    repo       = string
    user       = string
    permission = string
  }))
}

variable "codeowners_rules" {
  type = list(object({
    repo   = string
    branch = string
    path   = string
    users  = string
    teams  = string
  }))
}

variable "infra_state_bucket" {
  description = "S3 bucket name for IAC state management"
  type        = string
}

variable "infra_oidc_role" {
  description = "ARN of the OIDC role for IAC"
  type        = string
}

variable "oidc_role_common_name" {
  description = "Common name for OIDC roles"
  type        = string
}