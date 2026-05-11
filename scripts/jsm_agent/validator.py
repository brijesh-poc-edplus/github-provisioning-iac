import re
from dataclasses import dataclass, field
from typing import Any


VALID_VISIBILITIES = {"private", "internal", "public"}
VALID_REPO_TYPES = {"New", "Existing"}
VALID_ACCESS_LEVELS = {"Read", "Triage", "Write", "Maintain", "Admin"}


@dataclass
class ValidationResult:
    is_valid: bool
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def validate_request(request: dict[str, Any]) -> ValidationResult:
    errors: list[str] = []
    warnings: list[str] = []

    repo_name = request.get("repo_name", "")
    if not repo_name:
        errors.append("Repository name is required.")
    elif not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,98}[a-z0-9])?", repo_name):
        errors.append("Repository name must use lowercase letters, numbers, and hyphens only.")

    repo_type = request.get("repo_type", "New")
    if repo_type not in VALID_REPO_TYPES:
        errors.append("Request type must be New or Existing.")

    visibility = request.get("visibility", "private")
    if visibility not in VALID_VISIBILITIES:
        errors.append("Repository visibility must be private, internal, or public.")

    if not request.get("description"):
        errors.append("Repository description is required.")

    if not request.get("budget_info"):
        errors.append("Budget information is required.")

    jira_board = request.get("jira_board", "")
    if not jira_board:
        errors.append("Jira board URL is required.")
    elif not jira_board.startswith(("http://", "https://")):
        errors.append("Jira board must be a full URL starting with http:// or https://.")

    _validate_usernames("GitHub username", request.get("github_users", []), errors)
    _validate_usernames("Code owner username", request.get("code_owners", []), errors)

    github_team = request.get("github_team", "")
    if github_team and not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,98}[a-z0-9])?", github_team):
        errors.append("GitHub team name must use lowercase letters, numbers, and hyphens only.")

    if request.get("user_access", "Write") not in VALID_ACCESS_LEVELS:
        errors.append("Direct user access level is invalid.")

    if request.get("team_access", "Write") not in VALID_ACCESS_LEVELS:
        errors.append("Team access level is invalid.")

    if request.get("iac_setup"):
        _validate_account("AWS NonProd Account", request.get("aws_nonprod"), errors)
        _validate_account("AWS Prod Account", request.get("aws_prod"), errors)
    else:
        if request.get("aws_nonprod") and request["aws_nonprod"].account_id:
            warnings.append("AWS NonProd account was provided even though IaC setup is not required.")
        if request.get("aws_prod") and request["aws_prod"].account_id:
            warnings.append("AWS Prod account was provided even though IaC setup is not required.")

    if not request.get("github_users") and not github_team:
        warnings.append("No direct users or team were provided; repo will be created with org/admin access only.")

    return ValidationResult(is_valid=not errors, errors=errors, warnings=warnings)


def _validate_usernames(label: str, usernames: list[str], errors: list[str]) -> None:
    for username in usernames:
        if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,37}[a-z0-9])?", username):
            errors.append(f"{label} `{username}` is not a valid GitHub username.")


def _validate_account(label: str, account: Any, errors: list[str]) -> None:
    if not account or not account.name or not account.account_id:
        errors.append(f"{label} must use the format `account-name (123456789012)` when IaC setup is Yes.")
        return

    if not re.fullmatch(r"\d{12}", account.account_id):
        errors.append(f"{label} account id must be exactly 12 digits.")
