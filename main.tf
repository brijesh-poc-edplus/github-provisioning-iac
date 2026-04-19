provider "github" {
  owner = var.github_organization
  app_auth {
    id              = var.app_id
    installation_id = var.app_installation_id
    pem_file        = var.app_pem_file
  }
}

locals {
  branches          = csvdecode(file("data/branches.csv"))
  codeowners_rules  = csvdecode(file("data/codeowner_rules.csv"))
  members           = csvdecode(file("data/members.csv"))
  repos             = csvdecode(file("data/repos.csv"))
  team_members      = csvdecode(file("data/team_members.csv"))
  team_permissions  = csvdecode(file("data/team_repo_permissions.csv"))
  teams             = csvdecode(file("data/teams.csv"))
  user_permissions  = csvdecode(file("data/user_repo_permissions.csv"))
}

module "members" {
  source  = "./modules/org"
  members = local.members
}

module "teams" {
  source       = "./modules/teams"
  teams        = local.teams
  team_members = local.team_members
  depends_on   = [module.members]
}

module "repos" {
  source                = "./modules/repos"
  repos                 = local.repos
  branches              = local.branches
  user_permissions      = local.user_permissions
  team_permissions      = local.team_permissions
  codeowners_rules      = local.codeowners_rules
  infra_oidc_role       = var.infra_oidc_role
  infra_state_bucket    = var.infra_state_bucket
  oidc_role_common_name = var.oidc_role_common_name
  github_app_slug       = var.github_app_slug
  depends_on            = [module.members, module.teams]
}


