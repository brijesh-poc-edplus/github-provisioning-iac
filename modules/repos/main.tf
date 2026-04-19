############################################################
# main.tf
############################################################

locals {
  default_branches = ["nonprod", "nonprod-qa", "main"]

  default_repo_branches = {
    for rb in flatten([
      for repo in var.repos : [
        for b in local.default_branches : {
          repo      = repo.name
          branch    = b
          frontend  = repo.frontend
          iac_setup = repo.iac_setup
        }
      ]
    ]) : "${rb.repo}:${rb.branch}" => rb
  }

  # Only the "main" branch entries (used to create canonical initial files)
  main_repo_branches = {
    for k, v in local.default_repo_branches : k => v
    if v.branch == "main"
  }

  default_branch_rules = {
    for b in local.default_repo_branches :
    "${b.repo}:${b.branch}:rules" => {
      repo                    = b.repo
      branch                  = b.branch
      minPRCount              = 1
      users                   = ""
      teams                   = ""
      codeOwnerReviewRequired = false
    }
  }

  custom_branches_filtered = {
    for b in var.branches :
    "${b.repo}:${b.branch}" => b
    if !contains(keys(local.default_repo_branches), "${b.repo}:${b.branch}")
  }

  custom_property_keys = [
    "aws-nonprod",
    "aws-nonprod-name",
    "aws-prod",
    "aws-prod-name",
    "budget-info",
    "jira-board",
    "portfolio-detail",
  ]

  pairs = flatten([
    for r in var.repos : [
      for k in local.custom_property_keys : {
        key = "${r.name}:${k}"
        obj = {
          repo     = r.name
          name     = k
          property = lookup(merge({}, r), k, "")
        }
      }
    ]
  ])

  custom_properties_map = { for p in local.pairs : p.key => p.obj if length(trimspace(p.obj.property)) > 0 }

  # helper: concatenated content checksum so null_resource triggers on content change
  _main_files_concat = join("", [
    file("${path.module}/files/README.md"),
    file("${path.module}/files/prettier.config.js"),
    file("${path.module}/files/.lintstagedrc"),
    file("${path.module}/files/pre-commit"),
    file("${path.module}/files/prepare-commit-msg"),
    file("${path.module}/files/package.json"),
    file("${path.module}/files/.gitconfig"),
    file("${path.module}/files/.gitignore"),
  ])

  secrets = [
    "MAROON_OIDC_ROLE",
    "MAROON_STATE_BUCKET",
    "OIDC_ROLE_COMMON_NAME"
  ]

  tf_files = {
    for pair in flatten([
      for rb in local.main_repo_branches : [
        for f in fileset("${path.module}/infra-setup", "**/*") : {
          key       = "${rb.repo}:${rb.branch}:${f}"
          repo      = rb.repo
          frontend  = rb.frontend
          iac_setup = rb.iac_setup
          file      = "infra-setup/${f}"
          content   = file("${path.module}/infra-setup/${f}")
        }
      ]
    ]) : pair.key => pair
  }

}

# ---------------------------
# Repositories
# ---------------------------
resource "github_repository" "repos" {
  for_each           = { for r in var.repos : r.name => r }
  name               = each.value.name
  visibility         = each.value.visibility
  description        = each.value.description
  allow_rebase_merge = false
  auto_init          = true
  lifecycle {
    ignore_changes  = all
    prevent_destroy = true
  }
}

# ---------------------------
# Custom properties (depends on repo)
# NOTE: Requires custom property definitions to exist at org level first.
# Disabled for PoC — re-enable after creating org-level property definitions.
# ---------------------------
# resource "github_repository_custom_property" "accounts-details" {
#   for_each       = local.custom_properties_map
#   repository     = each.value.repo
#   property_name  = each.value.name
#   property_value = [each.value.property]
#   property_type  = "string"
#   depends_on     = [github_repository.repos]
#   lifecycle {
#     ignore_changes = [property_value]
#   }
# }

# ---------------------------
# Create canonical files on MAIN only (single commit per repo)
# ---------------------------

resource "github_repository_file" "readme" {
  for_each            = { for rb_key, rb in local.main_repo_branches : "${rb.repo}:main:README.md" => rb }
  repository          = each.value.repo
  branch              = "main"
  file                = "README.md"
  content             = file("${path.module}/files/README.md")
  overwrite_on_create = true
  depends_on          = [github_repository.repos]
  lifecycle {
    ignore_changes = [content]
  }
}

resource "github_repository_file" "prettier_config" {
  for_each            = { for rb_key, rb in local.main_repo_branches : "${rb.repo}:main:prettier.config.js" => rb }
  repository          = each.value.repo
  branch              = "main"
  file                = "prettier.config.js"
  content             = file("${path.module}/files/prettier.config.js")
  overwrite_on_create = true
  depends_on          = [github_repository.repos]
  lifecycle {
    ignore_changes  = [content]
    prevent_destroy = true
  }
}

resource "github_repository_file" "lintstagedrc" {
  for_each            = { for rb_key, rb in local.main_repo_branches : "${rb.repo}:main:.lintstagedrc" => rb }
  repository          = each.value.repo
  branch              = "main"
  file                = ".lintstagedrc"
  content             = file("${path.module}/files/.lintstagedrc")
  overwrite_on_create = true
  depends_on          = [github_repository.repos]
  lifecycle {
    ignore_changes  = [content]
    prevent_destroy = true
  }
}

resource "github_repository_file" "pre_commit" {
  for_each            = { for rb_key, rb in local.main_repo_branches : "${rb.repo}:main:.husky/pre-commit" => rb }
  repository          = each.value.repo
  branch              = "main"
  file                = ".husky/pre-commit"
  content             = file("${path.module}/files/pre-commit")
  overwrite_on_create = true
  depends_on          = [github_repository.repos]
  lifecycle {
    ignore_changes  = [content]
    prevent_destroy = true
  }
}

resource "github_repository_file" "prepare_commit_msg" {
  for_each            = { for rb_key, rb in local.main_repo_branches : "${rb.repo}:main:.husky/prepare-commit-msg" => rb }
  repository          = each.value.repo
  branch              = "main"
  file                = ".husky/prepare-commit-msg"
  content             = file("${path.module}/files/prepare-commit-msg")
  overwrite_on_create = true
  depends_on          = [github_repository.repos]
  lifecycle {
    ignore_changes  = [content]
    prevent_destroy = true
  }
}

resource "github_repository_file" "package_json" {
  for_each            = { for rb_key, rb in local.main_repo_branches : "${rb.repo}:main:package.json" => rb }
  repository          = each.value.repo
  branch              = "main"
  file                = "package.json"
  content             = file("${path.module}/files/package.json")
  overwrite_on_create = true
  depends_on          = [github_repository.repos]
  lifecycle {
    ignore_changes  = [content]
    prevent_destroy = true
  }
}

resource "github_repository_file" "gitignore" {
  for_each            = { for rb_key, rb in local.main_repo_branches : "${rb.repo}:main:.gitignore" => rb }
  repository          = each.value.repo
  branch              = "main"
  file                = ".gitignore"
  content             = file("${path.module}/files/.gitignore")
  overwrite_on_create = true
  depends_on          = [github_repository.repos]
  lifecycle {
    ignore_changes  = [content]
    prevent_destroy = true
  }
}

resource "github_repository_file" "gitconfig" {
  for_each            = { for rb_key, rb in local.main_repo_branches : "${rb.repo}:main:.gitconfig" => rb }
  repository          = each.value.repo
  branch              = "main"
  file                = ".gitconfig"
  content             = file("${path.module}/files/.gitconfig")
  overwrite_on_create = true
  depends_on          = [github_repository.repos]
  lifecycle {
    ignore_changes  = [content]
    prevent_destroy = true
  }
}

resource "github_repository_file" "html_file" {
  for_each            = { for k, rb in local.main_repo_branches : k => rb if rb.frontend == true }
  repository          = each.value.repo
  branch              = "main"
  file                = "index.html"
  content             = <<-EOF
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <title>${each.value.repo}</title>
      </head>
      <body>
        <h1>${each.value.repo}</h1>
      </body>
    </html>
  EOF
  overwrite_on_create = true
  depends_on          = [github_repository.repos]
  lifecycle {
    ignore_changes  = [content]
    prevent_destroy = true
  }
}

resource "github_repository_file" "infra_setup" {
  for_each            = { for k, v in local.tf_files : k => v if v.iac_setup == true }
  repository          = each.value.repo
  branch              = "main"
  file                = each.value.file
  content             = each.value.content
  overwrite_on_create = true
  depends_on          = [github_repository.repos]
  lifecycle {
    ignore_changes = [content]
  }
}

# ---------------------------
# Null resource join: ensure main files exist before creating branches
# ---------------------------
resource "null_resource" "main_files_ready" {
  triggers = {
    repos      = join(",", sort(keys(local.main_repo_branches)))
    files_hash = md5(local._main_files_concat)
  }

  depends_on = [
    github_repository_file.readme,
    github_repository_file.prettier_config,
    github_repository_file.lintstagedrc,
    github_repository_file.pre_commit,
    github_repository_file.prepare_commit_msg,
    github_repository_file.package_json,
    github_repository_file.html_file,
  ]
}

# ---------------------------
# Create non-main branches FROM main (so branches share main commit)
# ---------------------------
resource "github_branch" "default" {
  for_each      = { for k, v in local.default_repo_branches : k => v if v.branch != "main" }
  repository    = each.value.repo
  branch        = each.value.branch
  source_branch = "main"
  depends_on    = [github_repository.repos, null_resource.main_files_ready]
  lifecycle {
    ignore_changes  = all
    prevent_destroy = true
  }
}

resource "github_branch" "custom" {
  for_each   = local.custom_branches_filtered
  repository = each.value.repo
  branch     = each.value.branch

  lifecycle {
    precondition {
      condition     = contains(keys(github_repository.repos), each.value.repo)
      error_message = "branches.csv references repo '${each.value.repo}' which is not managed by Terraform."
    }
  }

  depends_on = [github_repository.repos, null_resource.main_files_ready]
}

# ---------------------------
# Collaborators / Teams (repo must exist)
# ---------------------------
resource "github_repository_collaborator" "users" {
  for_each   = { for p in var.user_permissions : "${p.repo}:${p.user}" => p }
  repository = each.value.repo
  username   = each.value.user
  permission = each.value.permission
  depends_on = [github_repository.repos]
}

resource "github_team_repository" "teams" {
  for_each   = { for p in var.team_permissions : "${p.repo}:${p.team}" => p }
  repository = each.value.repo
  team_id    = each.value.team
  permission = each.value.permission
  depends_on = [github_repository.repos]
}

# ---------------------------
# CODEOWNERS (attach after branches exist)
# ---------------------------
locals {
  codeowners_content = {
    for r in var.codeowners_rules :
    "${r.repo}:${r.branch}:${r.path}" => join("\n", concat(
      [
        "# ----------------------------------------------------------------------",
        "# DO NOT MODIFY THIS FILE DIRECTLY",
        "# This CODEOWNERS file is managed by Terraform",
        "# ----------------------------------------------------------------------"
      ],
      [
        for x in var.codeowners_rules :
        "${x.path} ${join(" ", concat(
          [for u in split(",", x.users) : "@${trimspace(u)}" if trimspace(u) != ""],
          [for t in split(",", x.teams) : "@terragit-edplus/${trimspace(t)}" if trimspace(t) != ""]
        ))}"
        if x.repo == r.repo && x.branch == r.branch
      ]
    ))
  }
}

resource "github_repository_file" "codeowners" {
  for_each            = local.codeowners_content
  repository          = split(":", each.key)[0]
  branch              = split(":", each.key)[1]
  file                = ".github/CODEOWNERS"
  content             = each.value
  overwrite_on_create = true
  depends_on          = [github_branch.default, github_branch.custom]
}

# ---------------------------
# Branch protection (attach after branch refs exist)
# ---------------------------
resource "github_branch_protection_v3" "branch_protection" {
  for_each       = { for b in var.branches : "${b.repo}:${b.branch}:rules" => b }
  repository     = each.value.repo
  branch         = each.value.branch
  enforce_admins = true
  required_pull_request_reviews {
    require_code_owner_reviews      = each.value.codeOwnerReviewRequired
    required_approving_review_count = each.value.minPRCount
    bypass_pull_request_allowances {
      apps = [var.github_app_slug]
    }
  }
  restrictions {
    users = length(trimspace(each.value.users)) > 0 ? split(",", each.value.users) : []
    teams = length(trimspace(each.value.teams)) > 0 ? split(",", each.value.teams) : []
    apps  = [var.github_app_slug]
  }
  depends_on = [github_branch.default, github_branch.custom]
}

resource "github_branch_protection_v3" "default_branch_protection" {
  for_each = { for b in local.default_branch_rules : "${b.repo}:${b.branch}:rules" => b
    if !contains(keys({ for br in var.branches : "${br.repo}:${br.branch}:rules" => br }), "${b.repo}:${b.branch}:rules")
  }
  repository     = each.value.repo
  branch         = each.value.branch
  enforce_admins = true
  required_pull_request_reviews {
    require_code_owner_reviews      = each.value.codeOwnerReviewRequired
    required_approving_review_count = each.value.minPRCount
    bypass_pull_request_allowances {
      apps = [var.github_app_slug]
    }
  }
  restrictions {
    users = length(trimspace(each.value.users)) > 0 ? split(",", each.value.users) : []
    teams = length(trimspace(each.value.teams)) > 0 ? split(",", each.value.teams) : []
    apps  = [var.github_app_slug]
  }
  depends_on = [github_branch.default, github_branch.custom]
}

resource "github_actions_secret" "infra_oidc_role" {
  for_each        = { for r in var.repos : r.name => r if r.iac_setup == true }
  secret_name     = "INFRA_OIDC_ROLE"
  repository      = each.value.name
  plaintext_value = var.infra_oidc_role
  lifecycle {
    ignore_changes = all
  }
  depends_on = [github_repository.repos, github_branch.default]
}

resource "github_actions_secret" "infra_state_bucket" {
  for_each        = { for r in var.repos : r.name => r if r.iac_setup == true }
  secret_name     = "INFRA_STATE_BUCKET"
  repository      = each.value.name
  plaintext_value = var.infra_state_bucket
  lifecycle {
    ignore_changes = all
  }
  depends_on = [github_repository.repos, github_branch.default]
}

resource "github_actions_secret" "oidc_role_common_name" {
  for_each        = { for r in var.repos : r.name => r if r.iac_setup == true }
  secret_name     = "OIDC_ROLE_COMMON_NAME"
  repository      = each.value.name
  plaintext_value = var.oidc_role_common_name
  lifecycle {
    ignore_changes = all
  }
  depends_on = [github_repository.repos, github_branch.default]
}

resource "github_repository_file" "infra_cicd" {
  for_each            = { for rb_key, rb in local.default_repo_branches : "${rb.repo}:${rb.branch}" => rb if rb.iac_setup == true }
  repository          = each.value.repo
  branch              = each.value.branch
  file                = ".github/workflows/deploy-infra.yml"
  content             = file("${path.module}/files/deploy-infra.yml")
  overwrite_on_create = true
  depends_on          = [github_repository.repos, github_branch.default]
  lifecycle {
    ignore_changes = [content]
  }
}

data "github_team" "edpl_admins" {
  slug = "edpl-admins"
}

resource "github_repository_environment" "edpl_admins" {
  for_each    = { for r in var.repos : r.name => r if r.iac_setup == true }
  repository  = each.value.name
  environment = "edpl-admins"
  reviewers {
    teams = [data.github_team.edpl_admins.id]
  }
}
