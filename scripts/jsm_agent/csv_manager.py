import csv
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


DATA_DIR = Path("data")

CSV_SCHEMAS = {
    "repos.csv": [
        "name",
        "visibility",
        "description",
        "frontend",
        "iac_setup",
        "aws-nonprod",
        "aws-nonprod-name",
        "aws-prod",
        "aws-prod-name",
        "budget-info",
        "jira-board",
        "portfolio-detail",
    ],
    "user_repo_permissions.csv": ["repo", "user", "permission"],
    "teams.csv": ["name", "description"],
    "team_repo_permissions.csv": ["repo", "team", "permission"],
    "codeowner_rules.csv": ["repo", "branch", "path", "users", "teams"],
}

ACCESS_TO_TERRAFORM = {
    "Read": "pull",
    "Triage": "triage",
    "Write": "push",
    "Maintain": "maintain",
    "Admin": "admin",
}


@dataclass
class CsvChange:
    file: str
    action: str
    key: str
    details: str


@dataclass
class CsvUpdateResult:
    changes: list[CsvChange] = field(default_factory=list)
    touched_files: set[Path] = field(default_factory=set)

    @property
    def changed(self) -> bool:
        return any(change.action in {"created", "updated"} for change in self.changes)


class CsvManager:
    def __init__(self, repo_root: Path) -> None:
        self.repo_root = repo_root
        self.data_dir = repo_root / DATA_DIR

    def apply_request(self, request: dict[str, Any], issue_number: int) -> CsvUpdateResult:
        result = CsvUpdateResult()
        repo_name = request["repo_name"]

        result.changes.append(
            self._upsert(
                "repos.csv",
                key_fields=["name"],
                new_row=self._repo_row(request),
                result=result,
            )
        )

        for username in request.get("github_users", []):
            result.changes.append(
                self._upsert(
                    "user_repo_permissions.csv",
                    key_fields=["repo", "user"],
                    new_row={
                        "repo": repo_name,
                        "user": username,
                        "permission": ACCESS_TO_TERRAFORM[request.get("user_access", "Write")],
                    },
                    result=result,
                )
            )

        github_team = request.get("github_team", "")
        if github_team:
            result.changes.append(
                self._upsert(
                    "teams.csv",
                    key_fields=["name"],
                    new_row={
                        "name": github_team,
                        "description": f"Team for {repo_name} from repo request #{issue_number}",
                    },
                    result=result,
                )
            )
            result.changes.append(
                self._upsert(
                    "team_repo_permissions.csv",
                    key_fields=["repo", "team"],
                    new_row={
                        "repo": repo_name,
                        "team": github_team,
                        "permission": ACCESS_TO_TERRAFORM[request.get("team_access", "Write")],
                    },
                    result=result,
                )
            )

        if request.get("code_owners") or github_team:
            result.changes.append(
                self._upsert(
                    "codeowner_rules.csv",
                    key_fields=["repo", "branch", "path"],
                    new_row={
                        "repo": repo_name,
                        "branch": "main",
                        "path": "*",
                        "users": ",".join(request.get("code_owners", [])),
                        "teams": github_team,
                    },
                    result=result,
                )
            )

        return result

    def _repo_row(self, request: dict[str, Any]) -> dict[str, str]:
        nonprod = request["aws_nonprod"]
        prod = request["aws_prod"]
        return {
            "name": request["repo_name"],
            "visibility": request.get("visibility", "private"),
            "description": request.get("description", ""),
            "frontend": _bool_to_csv(request.get("frontend", False)),
            "iac_setup": _bool_to_csv(request.get("iac_setup", False)),
            "aws-nonprod": nonprod.name,
            "aws-nonprod-name": nonprod.account_id,
            "aws-prod": prod.name,
            "aws-prod-name": prod.account_id,
            "budget-info": request.get("budget_info", ""),
            "jira-board": request.get("jira_board", ""),
            "portfolio-detail": request.get("portfolio_detail", ""),
        }

    def _upsert(
        self,
        filename: str,
        key_fields: list[str],
        new_row: dict[str, str],
        result: CsvUpdateResult,
    ) -> CsvChange:
        path = self.data_dir / filename
        rows, fieldnames = self._read_csv(path, filename)
        new_row = {field: str(new_row.get(field, "")) for field in fieldnames}
        key = _key(new_row, key_fields)

        for index, existing in enumerate(rows):
            if _key(existing, key_fields) != key:
                continue

            if _row_equal(existing, new_row, fieldnames):
                return CsvChange(filename, "skipped", key, "Already matches desired state.")

            before_after = _diff_summary(existing, new_row, fieldnames)
            rows[index] = new_row
            self._write_csv(path, fieldnames, rows)
            result.touched_files.add(path)
            return CsvChange(filename, "updated", key, before_after)

        rows.append(new_row)
        self._write_csv(path, fieldnames, rows)
        result.touched_files.add(path)
        return CsvChange(filename, "created", key, "Added new row.")

    def _read_csv(self, path: Path, filename: str) -> tuple[list[dict[str, str]], list[str]]:
        fieldnames = CSV_SCHEMAS[filename]
        if not path.exists():
            return [], fieldnames

        with path.open(newline="", encoding="utf-8") as csv_file:
            reader = csv.DictReader(csv_file)
            actual_fieldnames = reader.fieldnames or fieldnames
            rows = [
                {field: (row.get(field) or "").strip() for field in actual_fieldnames}
                for row in reader
                if any((value or "").strip() for value in row.values())
            ]

        return rows, actual_fieldnames

    def _write_csv(self, path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
        with path.open("w", newline="", encoding="utf-8") as csv_file:
            writer = csv.DictWriter(csv_file, fieldnames=fieldnames, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)


def _key(row: dict[str, str], key_fields: list[str]) -> str:
    return ":".join(row[field] for field in key_fields)


def _row_equal(left: dict[str, str], right: dict[str, str], fieldnames: list[str]) -> bool:
    return all((left.get(field) or "") == (right.get(field) or "") for field in fieldnames)


def _diff_summary(left: dict[str, str], right: dict[str, str], fieldnames: list[str]) -> str:
    diffs = [
        f"{field}: `{left.get(field, '')}` -> `{right.get(field, '')}`"
        for field in fieldnames
        if (left.get(field) or "") != (right.get(field) or "")
    ]
    return "; ".join(diffs)


def _bool_to_csv(value: bool) -> str:
    return "true" if value else "false"
