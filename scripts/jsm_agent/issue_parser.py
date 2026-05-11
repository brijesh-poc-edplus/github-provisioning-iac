import re
from dataclasses import dataclass
from typing import Any


FIELD_ALIASES = {
    "is this a new or existing repo?": "repo_type",
    "repository name": "repo_name",
    "repository visibility": "visibility",
    "repository description": "description",
    "is this a frontend/static site repo?": "frontend",
    "do you require an s3 and cloudfront setup for your project?": "iac_setup",
    "aws nonprod account": "aws_nonprod",
    "aws prod account": "aws_prod",
    "budget information": "budget_info",
    "jira board url": "jira_board",
    "portfolio detail": "portfolio_detail",
    "github username(s) for direct repo access": "github_users",
    "direct user access level": "user_access",
    "github team name": "github_team",
    "team access level": "team_access",
    "code owner username(s)": "code_owners",
}


@dataclass(frozen=True)
class AwsAccount:
    name: str = ""
    account_id: str = ""


def parse_issue_body(body: str) -> dict[str, Any]:
    """Parse GitHub Issue Form markdown into a normalized request dictionary."""
    raw_fields = _extract_markdown_fields(body or "")
    normalized: dict[str, Any] = {}

    for label, value in raw_fields.items():
        key = FIELD_ALIASES.get(_normalize_label(label))
        if key:
            normalized[key] = _empty_to_default(value)

    normalized["repo_name"] = _slug(normalized.get("repo_name", ""))
    normalized["repo_type"] = _title(normalized.get("repo_type", "New"))
    normalized["visibility"] = (normalized.get("visibility") or "private").lower()
    normalized["description"] = normalized.get("description", "")
    normalized["frontend"] = _yes_no_to_bool(normalized.get("frontend", "No"))
    normalized["iac_setup"] = _iac_to_bool(normalized.get("iac_setup", "No"))
    normalized["aws_nonprod"] = parse_aws_account(normalized.get("aws_nonprod", ""))
    normalized["aws_prod"] = parse_aws_account(normalized.get("aws_prod", ""))
    normalized["github_users"] = _split_csv(normalized.get("github_users", ""))
    normalized["code_owners"] = _split_csv(normalized.get("code_owners", ""))
    normalized["github_team"] = _slug(normalized.get("github_team", ""))
    normalized["user_access"] = _title(normalized.get("user_access", "Write"))
    normalized["team_access"] = _title(normalized.get("team_access", "Write"))
    normalized["portfolio_detail"] = normalized.get("portfolio_detail", "")
    normalized["budget_info"] = normalized.get("budget_info", "")
    normalized["jira_board"] = normalized.get("jira_board", "")

    return normalized


def parse_aws_account(value: str) -> AwsAccount:
    """Parse `account-name (123456789012)` into name and account id."""
    value = _empty_to_default(value)
    if not value:
        return AwsAccount()

    match = re.match(r"^(?P<name>.+?)\s*\((?P<id>\d{12})\)\s*$", value)
    if match:
        return AwsAccount(
            name=match.group("name").strip(),
            account_id=match.group("id").strip(),
        )

    if re.fullmatch(r"\d{12}", value):
        return AwsAccount(account_id=value)

    return AwsAccount(name=value)


def _extract_markdown_fields(body: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    current_label: str | None = None
    current_lines: list[str] = []

    for line in body.splitlines():
        heading = re.match(r"^###\s+(?P<label>.+?)\s*$", line)
        if heading:
            if current_label:
                fields[current_label] = _clean_value("\n".join(current_lines))
            current_label = heading.group("label")
            current_lines = []
            continue

        if current_label:
            current_lines.append(line)

    if current_label:
        fields[current_label] = _clean_value("\n".join(current_lines))

    return fields


def _clean_value(value: str) -> str:
    cleaned_lines = []
    for line in value.splitlines():
        if line.strip().startswith("_No response_"):
            continue
        if line.strip().startswith("<!--"):
            continue
        cleaned_lines.append(line.rstrip())
    return "\n".join(cleaned_lines).strip()


def _normalize_label(label: str) -> str:
    return re.sub(r"\s+", " ", label.strip().lower())


def _empty_to_default(value: Any) -> str:
    if value is None:
        return ""
    text = str(value).strip()
    return "" if text == "_No response_" else text


def _split_csv(value: str) -> list[str]:
    return [_slug(item) for item in value.split(",") if _slug(item)]


def _yes_no_to_bool(value: str) -> bool:
    return _normalize_label(value) in {"yes", "true", "y"}


def _iac_to_bool(value: str) -> bool:
    return _normalize_label(value) in {"yes", "true", "required"}


def _title(value: str) -> str:
    value = _empty_to_default(value)
    return value[:1].upper() + value[1:].lower() if value else ""


def _slug(value: str) -> str:
    return _empty_to_default(value).strip().lower()
